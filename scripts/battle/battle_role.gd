class_name BattleRole
extends RefCounted
## 角色基类（对照服务端 DiceGameServer/PlayerEntity 的 p_* / v_* 钩子 + role/*）
##
## 钩子约定：
## - 统一签名为 func p_xxx(ctx: Dictionary) -> int，返回 SUCCESS / WAIT / URGENT
## - 引擎在对应时机对「每个玩家」调用一次；若某角色返回 WAIT，则整个钩子轮次暂停，
##   收到该玩家的回复后从同一位玩家继续调用（因此角色内部用 step 记录进度）
## - step 现在按「当前钩子轮次的状态实例」隔离，随实例新建（新实例从 0 开始），不再每轮统一清零；
##   角色用 engine.ask_skill() 请求玩家输入
## - 若角色在钩子内压入了新的引擎状态（如 push_harm 造成伤害），应「先把 step 推进过该子技能」
##   再返回 URGENT，引擎会先执行新状态、之后再回到本钩子继续

const SUCCESS: int = 0
const EMPTY_HANDLE: int = 1
const WAIT: int = 2
const URGENT: int = 3
## 子步骤「已完成」标记。取值必须大于所有子步骤常量（各角色的子步骤用 5 位技能号变体，
## 如 32031 / 36063 / 3507），否则 `step >= STEP_DONE` 的守卫会把「刚压入的子步骤」误判为已完成，
## 导致等待玩家回复后不再回到该钩子继续结算。
const STEP_DONE: int = 1000000
## 牌类校验返回此值表示「角色不覆写」，引擎会退回通用实现
const V_NOT_OVERRIDE: int = -1

var _player_ref: WeakRef = null
var player: BattlePlayer:
	get: return _player_ref.get_ref() as BattlePlayer if _player_ref != null else null
	set(value): _player_ref = weakref(value) if value != null else null
var _engine_ref: WeakRef = null
var engine: BattleEngine:
	get: return _engine_ref.get_ref() as BattleEngine if _engine_ref != null else null
	set(value): _engine_ref = weakref(value) if value != null else null
## 钩子轮次之外的持久进度：主动技能（SkillRun）与不经钩子轮次的同步钩子用它记分步进度。
var _持久进度: int = 0
## 钩子流程的进度：钩子轮次内由引擎按「本轮钩子」代管（每轮从 0 开始、互不污染），
## 轮次之外落回本角色自身的持久进度。
## 归属变更说明：以前这是「角色唯一的进度字段」，引擎要在每轮钩子开始时把它强制清零、
## 在 URGENT 时快照 / 恢复、还要靠 _角色技能挂起 特判放过正在等回复的技能。
## 现在进度随「当前钩子轮次」走，那一整套补丁都不再需要。
var step: int:
	get:
		if engine != null and engine.在进度流程中():
			return engine.取当前进度(player.id)
		return _持久进度
	set(值):
		if engine != null and engine.在进度流程中():
			engine.设当前进度(player.id, 值)
		else:
			_持久进度 = 值


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	player = p
	engine = e
	_按表初始化标识物()


## 从「角色表」的「指示物」列（写法 `槽位:名称:上限`，多枚用 `;` 分隔）建好专属标识物：
## 槽 0 / 1 建到 player.tokens，槽 2 是盖牌、写进 player.cover_cards_max。
## 上限一律以设计表为准，角色脚本不再写死；要改数值改设计表后重新导表即可。
func _按表初始化标识物() -> void:
	for 槽: int in [0, 1]:
		var 定义: Dictionary = Data.role_token_def(player.role_id, 槽)
		if 定义.is_empty():
			continue
		player.tokens[槽] = {"name": str(定义["name"]), "max": int(定义["max"]), "num": 0}
	var 盖牌: Dictionary = Data.role_token_def(player.role_id, 2)
	if not 盖牌.is_empty():
		player.cover_cards_max = int(盖牌["max"])


# ============================================================
# 钩子（默认空实现）
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_begin(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_begin_shiren(_ctx: Dictionary) -> int: return SUCCESS
## 角色卡被替换前（F7 / 10803）：旧角色在这里清理自己的形态 / 标记 / 临时变量。
## 必须同步返回（不能等待玩家输入）；替换后旧角色对象会解绑 player / engine，不会再收到任何钩子。
func p_before_role_replace(_ctx: Dictionary) -> int: return SUCCESS
func p_between_weak_and_action(_ctx: Dictionary) -> int: return SUCCESS
func p_before_action(_ctx: Dictionary) -> int: return SUCCESS
func p_boot(_ctx: Dictionary) -> int: return SUCCESS
func p_before_attack(_ctx: Dictionary) -> int: return SUCCESS
func p_after_attack(_ctx: Dictionary) -> int: return SUCCESS
func p_before_magic(_ctx: Dictionary) -> int: return SUCCESS
func p_after_magic(_ctx: Dictionary) -> int: return SUCCESS
func p_before_special(_ctx: Dictionary) -> int: return SUCCESS
func p_after_special(_ctx: Dictionary) -> int: return SUCCESS
## 提炼前（F9）：某玩家宣告【提炼】且校验通过、真正移动战绩区星石之前，对全体角色同步调用一次。
## 必须同步返回（不能等待玩家输入）；把 ctx["forbidden"] 置 true 可取消本次提炼。
## ctx: {player 提炼者, args 原始参数, dst_ids, forbidden=false}
func p_before_extract(_ctx: Dictionary) -> int: return SUCCESS
## 提炼后（F9 / 10604）：提炼结算完成（星石已经移动）后对全体角色触发一次，可等待玩家输入。
## ctx: {player 提炼者, gem 本次提炼的宝石数, crystal 本次提炼的水晶数,
##       args 原始参数, dst_ids, is_heaven 是否【冒险者天堂】}
func p_after_extract(_ctx: Dictionary) -> int: return SUCCESS
func p_attacked(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_1(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_2_hit(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_2_miss(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_3(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_4(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_5(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_6(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_6_drawn(_ctx: Dictionary) -> int: return SUCCESS
func p_harm_end(_ctx: Dictionary) -> int: return SUCCESS
func p_before_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
## 手牌超限、准备弃牌前（ctx.before_discard=true）：月女【新月庇护】在这里问是否发动；
## 掉士气链里还会再调一次（没有这个标记），角色应直接跳过，避免重复询问。
## ctx: {dst 超限者, amount 超限张数, cards 已选好要弃的牌, harm_cause, type, before_discard}
func p_xin_yue(_ctx: Dictionary) -> int: return SUCCESS
func p_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
## 同步掉士气链（合成星杯 / 逆反居合斩 / 暗月诅咒）真正扣完士气后补压的一轮钩子。
## 同步链里不能等玩家输入，需要询问的「士气下降时」响应（结界师【琉璃境】）在这里问；
## 士气已经扣完，响应不会改变它。ctx 同 p_lose_morale（带 sync=true）。
func p_lose_morale_after(_ctx: Dictionary) -> int: return SUCCESS
func p_fix_morale(_ctx: Dictionary) -> int: return SUCCESS
func p_true_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
## 盖牌变动（对照服务端 PlayerEntity::p_cover_change）：任意盖牌的加入/移出都会对全体触发一次。
## ctx: {dst 变动归属者, direction 见 GConst.CHANGE_*, howMany, cards, doer 发起者, cause}
func p_cover_change(_ctx: Dictionary) -> int: return SUCCESS
func p_show_hand(_ctx: Dictionary) -> int: return SUCCESS
func p_tap(_ctx: Dictionary) -> int: return SUCCESS
## 手牌数量变化（对照服务端 PlayerEntity::p_hand_change）：任何来源的加/减手牌后对全体触发一次
## ctx: {player 手牌变化者}
func p_hand_change(_ctx: Dictionary) -> int: return SUCCESS
## 摸牌前（引擎把牌发到某玩家手里之前对全体角色调用一次）：角色可在此询问该玩家是否发动响应
## （如暗杀者【水影】：除【特殊行动】外，当你摸牌前发动）。ctx: {player 摸牌者, count 张数, cause 来源}
func p_before_draw(_ctx: Dictionary) -> int: return SUCCESS
## 治疗溢出（F3）：某玩家获得治疗、加到上限之后还有剩余时对全体角色各触发一次，可以等待玩家输入。
## ctx: {player 溢出者, overflow 溢出点数, before 加之前, amount 本次加的量, src 来源}
## （圣庭检察士【裁决论定】= 我方目标角色溢出时给【异端裁决所】+1 治疗；圣殿骑士【神选者】= 自己溢出时 +1【圣印】）
func p_heal_overflow(_ctx: Dictionary) -> int: return SUCCESS
## 某玩家的【治疗】数**真正增加**后对全体角色各触发一次（可以等待玩家输入）。
## ctx: {player 获得治疗者, before 加之前, after 加之后, amount 本次加的量, src 来源}
## 只在确实加进上限里时触发：加满再加、被禁疗而作废的都不算。
## 例：铸律者【神律封锁】「每次你的治疗数增加时，我方士气 -1」。
func p_heal_gained(_ctx: Dictionary) -> int: return SUCCESS
## 某名玩家身上的基础效果能不能触发（结界师【绝界】：「你拥有的基础效果无法触发」）。
## 引擎在基础效果即将自身触发时问所有角色，任一返回 true 就当作「不触发」。
func 基础效果被禁止(_pid: int) -> bool: return false
## 士气下限（F5）：返回 >0 时，本队士气不会被扣到它以下（圣殿骑士【圣炎形态】：我方士气最少为 1）
func morale_floor() -> int: return 0
## 这名角色是否**始终**无法获得【治疗】（染污者【神弃之裔】：治疗上限为 0【恒定】）。
## 引擎在 add_cross / add_cross_pierce 里除了看 BattlePlayer.no_heal_round（本回合禁疗）之外也问这里，
## 返回 true 时整笔治疗作废 —— 「突破上限」类技能（神圣契约 / 圣光祈愈）也拿不到治疗。
func 禁止获得治疗() -> bool: return false
## 因承受伤害摸牌时「本次摸牌的第 1 张改从别处拿」（F8）：返回牌号（实现里要自己从来源取出），
## -1＝不替换。**同步钩子**，不能等待玩家输入。（异教徒【末日预言】：从【预言】堆顶拿）
func 伤害摸牌替换(_pid: int) -> int: return -1
## 弃牌前拦截（F6 / 4704）：某玩家手牌 / 盖牌里的牌即将进入弃牌堆前，对全体角色各触发一次。
## 角色可在此询问自己的玩家是否响应（可 WAIT），并「认领」其中的牌：
##   在 ctx 里写 taker = 自己 player.id、taken = [要拿走的牌号]；
##   引擎结算时把这些牌从待弃牌里剔除、加进认领者手牌（原主手里若还留着也会兜底清掉）。
## 一次弃牌只支持一名认领者（先问到的座位先得）：后问到的角色看到 ctx.taker >= 0 必须放弃。
## ctx: {owner 牌主（-1＝未知）, cards 待弃牌, source "hand"/"cover"/"other"/"basic",
##       cause 来源, face_up 是否公开进入弃牌（默认 true）}
## 只有 wants_before_discard(ctx) 返回 true 时，引擎才会把这次弃牌推迟到本钩子之后；
## 默认 false 保持同步弃牌，既有角色行为不变。例：4704 在「牌里有【魔弹】且牌主是队友」时返回 true。
func p_before_discard(_ctx: Dictionary) -> int: return SUCCESS
## 是否要参与本次弃牌前的拦截（同步预判，F6）：只有任一角色返回 true，引擎才推迟这次弃牌。
## 不要在这里询问玩家 / 改状态，只按 ctx 里的牌与牌主判断「有没有可能响应」。
func wants_before_discard(_ctx: Dictionary) -> bool: return false
func p_basic_effect_change(_ctx: Dictionary) -> int: return SUCCESS
## 基础效果触发并结算完成（F4 / 4604）：某角色面前的一张基础效果因其自身效果被触发、且这次效果
## 已经结算完成时，对全体角色触发一次。
## ctx: {dst 基础效果拥有者（触发者）, card 触发的基础效果牌,
##       doer 放置者（-1 = 引擎内部结算，如【中毒】/【圣盾】被动结算）, cause 触发来源}
## 只在「触发」时来：中毒结算、圣盾 / 天使之墙抵挡、封印 / 赐福被消耗……
## 被拿走 / 被【风之洁净】移除这类不算触发（对应 p_basic_effect_change 的 remove）。
## 例：4604「目标角色触发基础效果并结算完成后 → 你 +1【灵涌】」。
func p_basic_effect_triggered(_ctx: Dictionary) -> int: return SUCCESS
func p_additional_action(_ctx: Dictionary) -> int: return SUCCESS
## 行动结束（通用钩子，F2）：本回合任何一次「行动阶段」的行动结束时触发一次，
## 在具体的 p_after_attack / p_after_magic / p_after_special 之后（同一轮里各角色按座位序调用）。
## 同一次行动的两个钩子收到同一份上下文：
## {player, kind（"attack" / "magic" / "special"，技能行动归入它对应的基础种类）,
##  is_skill 是否技能行动, action_id 技能号（非技能为 0）, card_id, dst, special_action,
##  is_extra 是不是额外行动, extra_cause 这份额外行动的来源（非额外为 0）,
##  action_count 本回合第几次行动（含本次）, attack_action_count / magic_action_count /
##  special_action_count / extra_action_count 本回合各类次数}
## 「启动」技能不是一次行动，不触发本钩子（它照旧只触发 p_after_special）。
## 例：4103「本回合第三次行动结束时」看 action_count == 3；4104「每次额外行动结束时」看 is_extra。
func p_action_end(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_end(_ctx: Dictionary) -> int: return SUCCESS
func p_after_turn_end(_ctx: Dictionary) -> int: return SUCCESS
## 应战成立后（对照服务端 PlayerEntity::p_reattack）：可把应战打出的这张牌「视为」另一张。
## ctx: {card_id 打出的牌, doer 应战者, target 反击目标, 改用 视为哪张牌, real 是否实体牌}
## 角色也可设置 ctx["block"] = true，把这次应战当作「格挡」（本次攻击落空、不反击），如阴阳师光系应战
func p_reattack(_ctx: Dictionary) -> int: return SUCCESS
## 通用：此刻能不能用【圣光】（格挡攻击 / 抵挡魔弹都算）。
## 形态类被动用（如染污者【狂戾之心】：狂戾形态下无法使用【圣光】）；false 时引擎会在
## 攻击询问与魔弹询问里把 can_light 下发成 false（客户端把圣光置灰），并统一在 v_block 拒绝。
func 能否使用圣光() -> bool:
	return true


## 通用「卡牌系别属性」判定：这张牌在**我手里**时，有效系别是多少（0＝不改，按牌面算）。
## 引擎每拍按「持有者」现算，所以别人在别的回合把牌交给我、我自己摸牌 / 弃牌都不需要额外处理。
## 例：苍炎魔女【烈焰形态】—— 手里的攻击牌除水 / 暗外一律视为火。
func 牌系别覆盖(_card: GCard) -> int:
	return 0


## 上面那条覆盖对应的属性名（写进快照 hand_attrs，客户端据此把左上角系别标签画成覆盖后的系别）
func 牌系别属性名() -> String:
	return ""


## 主动攻击宣告时（对照应战那条的 p_reattack）：角色可把本次打出的攻击牌「视为」另一张结算
## （如噬神者在这里记录本次打出的【魔刃】/【异刃】）。
## ctx: {player 攻击者, card_id 打出的牌, 改用 视为哪张牌（默认＝card_id）}
## 真牌照常从手牌进弃牌堆并展示，本次攻击按「改用」的那张结算（系别就是那张牌的系别）
func p_attack_card(_ctx: Dictionary) -> int: return SUCCESS
## 攻击「预告加伤」：本次攻击在**命中时**还会追加多少伤害（对照各角色 p_timeline_2_hit 里对
## harm["point"] 的追加）。引擎发「应战询问」时把它加上去一起告诉被攻击者 —— **只用于显示，
## 不改变实际结算**，默认 0。用它补「客户端算不出的角色状态类」加伤（如魔剑士【暗影之力】+1、
## 魔枪【暗之解放】+1）；客户端能自己算的角色被动（狂战士【狂化】）走 GConst.攻击提示角色加成。
## ctx 与 p_timeline_1 同形（src / dst / is_active / harm / hit_rate…）。
func p_attack_preview(_ctx: Dictionary) -> int: return 0


# ============================================================
# 牌类校验覆写（返回 V_NOT_OVERRIDE 表示不覆写，退回通用实现）
# 想「通用校验 + 追加限制」时，先调 player.base_v_xxx(...) 再判断
# 注意：v_* 是纯校验，不得扣资源、不得置「本回合已用 / 形态」这类结算标记 ——
# 引擎除了在真正落子前问它，还会在「响应里点红色额外攻击按钮」时用它做预校验
# （BattleEngine._选择额外攻击响应），预校验里改状态会让那份额外行动当场变成不可发动。
# 扣费放 resolve_action_end_option / p_additional_action，标记放 p_* 钩子。
# ============================================================
func v_allow_action(_action_type: int, _args: Array, _allow: int, _can_give_up: bool) -> int: return V_NOT_OVERRIDE
func v_unactional() -> int: return V_NOT_OVERRIDE
func v_attack(_card_id: int, _dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_reattack(_card_id: int, _attack_card_id: int) -> int: return V_NOT_OVERRIDE
func v_block(_card_id: int) -> int: return V_NOT_OVERRIDE
func v_shield(_dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_weaken(_dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_missile(_card_id: int, _dst_id: int) -> int: return V_NOT_OVERRIDE
func v_remissile(_card_id: int) -> int: return V_NOT_OVERRIDE
## 多牌响应魔弹（10603「弃 2 张同系牌视为魔弹」这类）：默认不支持，返回 V_NOT_OVERRIDE。
## 引擎在 SMissileAsk 收到 2 张牌时先调它；返回 GE_SUCCESS 才按多牌响应结算。
func v_remissile_multi(_cards: Array) -> int: return V_NOT_OVERRIDE
## 魔弹传递询问允许选的最多牌数（默认 1；10603 在能凑出两张同系牌时为 2）。
## 客户端据此把「选牌上限」放宽到 2；服务端仍用 v_remissile_multi 逐张复核。
func missile_relay_card_max() -> int: return 1
## 多牌响应成功时补发的技能号（0 = 不播报；10603 为 10603），客户端据此飘技能名。
func remissile_multi_skill() -> int: return 0
func v_buy(_args: Array) -> int: return V_NOT_OVERRIDE
func v_extract(_args: Array, _team_gem: int, _team_crystal: int, _dst_ids: Array) -> int: return V_NOT_OVERRIDE
func v_attacked() -> int: return V_NOT_OVERRIDE
## 目标资格校验（F4 / 4601）：目标角色自己判断「能不能被放上这张基础效果」，默认成功。
## 引擎在【圣盾】/【虚弱】/【中毒】的出牌校验、技能行动的基础效果放置声明
## （basic_effect_placements）与 add_basic_effect 兜底里统一调用它；
## 客户端的目标过滤也应走同一口径（角色在 available_skills 的 targets 里用引擎方法筛）。
## 例：4601「你无法成为基础效果的目标」→ 返回 GConst.GE_INVALID_PLAYERID。
## 注意：这只挡「成为目标」，不阻止已经在自己面前的基础效果继续生效。
func v_basic_effect_target(_dst: BattlePlayer, _card_id: int) -> int: return GConst.GE_SUCCESS
## 行动结束时的最高优先级结算：在其它角色的普通 p_after_attack / p_after_magic
## 以及额外行动响应之前执行（如格斗家念弹必须先结算完）。
func has_priority_action_end() -> bool:
	return false


func p_priority_action_end(_ctx: Dictionary) -> int:
	return SUCCESS


## 行动聚合器的唯一来源入口：角色只需要实现/覆写 action_end_options()，
## 队列里的“行动结束响应”额外行动由基类统一补进来。
func 行动结束来源(ctx: Dictionary) -> Array:
	return action_end_options(ctx)


## 角色在「行动聚合器」里登记的可选行动；只给描述，不负责发询问。
## 默认把队列里「声明为行动结束响应」的额外行动也作为选项返回（in_end_response 由授予它的技能写进行动规格），
## 这样角色不必同时维护 action_end_options 和队列两套来源。
## 排序（_sort）：额外行动在最前（队列额外行动 0 → 基础效果 1），角色响应技能在后（2）。
func action_end_options(_ctx: Dictionary) -> Array:
	var out: Array = []
	if player == null:
		return out
	for a: Dictionary in player.additional_actions:
		if bool(a.get("direct", false)):
			continue
		var cause: int = int(a.get("cause", 0))
		if cause <= 0 or not bool(a.get("in_end_response", false)):
			continue
		out.append({
			"value": cause, "label": GConst.skill_name(cause), "skill_id": cause,
			"enabled": true, "_kind": "extra", "_sort": 0,
		})
	return out


## 行动聚合器选中一项后分派回角色；选中后怎样付费/入队/结算由角色自己处理。
func resolve_action_end_option(cause: int, _reply: Dictionary, _ctx: Dictionary) -> int:
	return resolve_queued_extra_action(cause)


## 队列里已获得、但还没确认的额外行动的默认处理：扣费后标 direct。
## 一定要找**队列里**那一份（额外行动队列数据），不能用 额外行动数据()：后者优先返回
## 引擎的「当前额外行动数据」—— 上一个同来源的行动用完后那份数据还留着，
## 会把新入队的这一份顶掉，结果新行动一直没标 direct、响应结束又把它当选项问一次
## （血色剑灵【赤色一闪】连续两次踩过：确认第二次时会再弹一次相同的询问）。
## 这次「行动结束」是不是攻击行动（攻击牌结束）。行动聚合器在**攻击牌结束时和法术牌结束时**
## 都会调 action_end_options()，技能原文写「攻击行动结束时」的选项必须先用它过滤，
## 否则法术结束也会把选项摆出来（风之剑圣【剑影】踩过）。
## 空 ctx / 没有 kind（旧测试直接调 action_end_options({})）按攻击结束处理，保持既有行为。
func 是攻击行动结束(ctx: Dictionary) -> bool:
	return str(ctx.get("kind", "attack")) != "magic"


func resolve_queued_extra_action(cause: int) -> int:
	var rc: int = 行动结束确认代价(cause)
	if rc == SUCCESS or rc == URGENT:
		# 只找「还没确认」的那一份：同一来源可能已经有一份确认过、还没用掉排在前头
		# （迅捷赐福的行动先确认、赤色一闪后确认；前一份没用掉时下一轮又入队一份新的）。
		var 数据: Dictionary = player.额外行动队列数据(cause, true)
		if not 数据.is_empty():
			数据["direct"] = true
			# 代价已在响应里付过：取消响应后进额外行动阶段使用这份行动时不能再扣一次
			数据["已付费"] = true
	else:
		# 付不起 / 条件不满足：这份行动不再保留，避免以后绕过 confirm 免费进入
		player.撤回额外行动(cause)
	return rc


## 在「行动结束响应」里确认使用某份额外行动时立即结算费用（方案 A：点选即付）。
## 返回 SUCCESS / URGENT；默认无费用。真正进入行动时仍走 p_additional_action 结算效果。
## 这是**技能自己的**费用逻辑（如剑帝【不屈意志】扣能量、兽灵【一击无念】扣残心），
## 引擎只提供确认时机，不认识具体技能号。
func 行动结束确认代价(_cause: int) -> int:
	return SUCCESS


## 额外行动的规格需要按「此刻」重算时覆写它：返回非空表＝引擎把这份行动的规格改写成它。
## 引擎在两处回调：进入这份额外行动时（p_additional_action 之前）与**本地切换到它**时
## （客户端点另一颗额外行动按钮，见 BattleEngine._切换额外行动）。
## 需要覆写的场景：规格里写了「按当前手牌 / 双方手牌数算」的白名单 ——
## 授予那一刻的快照会过期，切过来时若不重算，手里新拿到的牌会被白名单挡住（10702 踩过）。
## 默认不重算（返回空表＝保持授予时的规格）。
func 额外行动规格(_cause: int) -> Dictionary:
	return {}


## 手牌里指定系别的攻击牌（给「限定系别」的额外攻击行动算白名单用）。
## 一张都没有时返回「全禁」白名单：空表会被引擎当成「不限制」，界面会把手牌全点亮。
func 按系攻击牌(系: int) -> Array:
	if player == null or 系 <= 0:
		return []
	var out: Array = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_attack() and c.element_enum() == 系:
			out.append(cid)
	return out if not out.is_empty() else [GConst.手牌白名单_全禁]


## 梦想剑（4503）本回合当前档位：0=未启用 / 1=无视圣盾 / 2=对方无法应战 / 3=强制命中。
## 供客户端角色说明把梦想剑那一行标绿（45 / 108 覆写），默认 0。
func dream_tier() -> int: return 0


# ============================================================
# 校验与技能执行（默认无效）
# ============================================================
func v_attack_skill(_action: Dictionary) -> int: return GConst.GE_EMPTY_HANDLE
func v_magic_skill(_action: Dictionary) -> int: return GConst.GE_EMPTY_HANDLE
func v_special_skill(_action: Dictionary) -> int: return GConst.GE_EMPTY_HANDLE
func p_attack_skill(_action: Dictionary) -> int: return EMPTY_HANDLE
func p_magic_skill(_action: Dictionary) -> int: return EMPTY_HANDLE
func p_special_skill(_action: Dictionary) -> int: return EMPTY_HANDLE


## 行动阶段可选的技能列表；每项：
## { "type": ActionType.*_Skill, "id": CAUSE, "name": 按钮名, "need_card": 最少要选几张, "need_target": 0/1/2…,
##   "card_max": 最多能选几张（可省；省略＝必须恰好 need_card 张，给了就可以选到更多，如【欺诈】弃 2~3 张）、
##   "targets": [合法目标 id]（可省；给了就只让这几名玩家亮，如【魔弹融合】的固定落点）、
##   "cards": [合法手牌 id]（可省；给了就只让这几张牌可点，如只能弃法术牌的技能） }
func available_skills() -> Array:
	return []


## 本次技能行动会把哪些手牌作为「基础效果」放到谁面前（F4，供引擎统一做目标资格校验）。
## 返回 [{card: 牌号, dst: 目标玩家 id}, …]；默认空数组＝这次技能不放置基础效果。
## 封印 401~405 / 迅捷·威力赐福 1601~1602 / 天使之墙 701 这类「把牌放到角色面前」的技能应覆写它。
## 引擎在技能行动校验后、执行前逐条问目标角色 v_basic_effect_target：任一被拒就驳回整个技能行动
## （不扣牌、不挂效果）。客户端目标列表仍按 available_skills 的 targets 过滤，两边用同一口径。
func basic_effect_placements(_action: Dictionary) -> Array:
	return []


## 该主动技能是不是「启动」：引擎只在**特殊技能**这一类上问它（见 battle_engine），
## 认定后决定「结算完重新进入行动阶段」而不是回合结束，
## 同时受「每回合只能发动一个启动技能」限制（player.boot_skill_used，引擎统一下发/校验）。
## 发动成功的角色要在自己的结算里把 player.boot_skill_used 置 true
func is_free_skill(_skill_id: int) -> bool:
	return false


## 技能本体压入状态并返回 URGENT 之后，结算完还要不要重新进入技能本体接着做。
## 默认 false：引擎按「技能已经执行完」收尾（直接压 p_after_* / 行动结束）。
## 需要「中间插一段必须等状态结算的事、之后再继续」的多步技能按 action_id 返回 true ——
## 典型是「摸牌可能把手牌摸超限」：摸完要先压 SHandOverflow 让玩家弃牌 / 掉士气，
## 回来还得接着选目标 / 结算（如 7802 魔法入门、10601 别烦我……）。
## 返回 true 的场景：技能本体要把当前步骤推进到下一步再返回 URGENT，否则重入会重复执行刚做过的事。
## 只对声明过的技能号生效：同一个角色的其它技能返回 URGENT 仍按「执行完」处理。
func 技能URGENT后重入(_action: Dictionary = {}) -> bool:
	return false


## 额外行动的「出牌 / 目标限制」不再由角色按 cause 提供：授予行动时用 spec 写进那份行动
## （见 BattlePlayer.add_action 的 cards / targets / element），引擎照单执行。
## 技能自己算白名单可用下面的 helper（按系攻击牌），或直接遍历 player.hand_cards。


## 引擎按名字调用钩子
func call_hook(hook: String, ctx: Dictionary) -> int:
	if not has_method(hook):
		return SUCCESS
	return call(hook, ctx)


# ============================================================
# 常用工具
# ============================================================
## 取技能表「提示」列的第 序号 条并填好占位符：{src}=自己（发起者）、{n}=要交/弃的张数、
## {dst}=收牌人（「我交给别人」的场合才给）。同一个技能的多个询问各读哪一条，
## 由角色脚本自己按顺序定（如 #0 = 叫别人交牌、#1 = 自己交牌）。
## 表里没配就返回空串，客户端会退回默认文案（「是否发动【X】？」）。
## 【维护约定】技能专用提示写设计表「提示」列，通过转表生成，不在角色脚本里硬编码；
## 有额外询问（选目标 / 选牌 / 选效果 / 是否发动）的技能大概率需要专用提示，其余通常不需要。
func 提示(skill_id: int, 序号: int = 0, 张数: int = 0, 收牌人id: int = -1, 额外: Dictionary = {}) -> String:
	return GConst.提示文本(skill_id, 序号, engine._称号(player), 张数, _收牌人称号(收牌人id), 额外)


## 读技能表「提示」原文（不按数字规则加空格）：选项按钮文案要精确控制空格时用，
## 如「-2【水晶】-1【宝石】」「战绩区 -2【水晶】」。
func 提示原文(skill_id: int, 序号: int = 0, 额外: Dictionary = {}) -> String:
	return GConst.提示原文(skill_id, 序号, 额外)


## 读技能表「按钮」原文（选项按钮 / 二级技能栏按钮上的字），与 GConst.按钮原文 同口径。
## 选项字典一般两处都填：`"label": 按钮(S, n)`（ask_skill → 客户端 notes）
## 与 `"text": 按钮(S, n)`（available_skills 的 arg_choices）。
func 按钮(skill_id: int, 序号: int, 额外: Dictionary = {}) -> String:
	return GConst.按钮原文(skill_id, 序号, 额外)


## 收牌人称号（{dst} 用；没收牌人就返回空串）
func _收牌人称号(收牌人id: int) -> String:
	return engine._称号(engine.p(收牌人id)) if 收牌人id >= 0 else ""


## 询问某玩家（自己或别人）选牌 / 是否发动：参数与 engine.ask_skill 一致，只是「提示」文案
## 不用每个调用点手写 —— 自动取技能表「提示」列的第 序号 条，并把 {src}=本技能发起者（自己）、
## {n}=要交/弃的张数、{dst}=收牌人 填好（收牌人id 只在「我交给别人」的场合给）。
## pid 可以是当前行动者以外的玩家（F9 / 10601：由右手边队友指定目标对手）——
## 回复仍然回到发起本次询问的钩子 / 技能状态，用 take_skill_reply / take_skill_reply_full 读取。
## 同一个技能有多次询问且要不同文案时，靠 序号 区分；表里没配就退回默认文案（「是否发动【X】？」）
## 预览基准 / 预览类型 见 engine.ask_skill：客户端现算头像提示要用到的数值与它的伤害类型
## （如【战纹碎击】本次攻击原本的伤害、【朝圣】本次受到的伤害是法术还是攻击）。
## 保留倒计时 见 engine.wait_for：同一条询问链上的后续询问传 true，不重新计时
## 可圣光 见 engine.ask_skill：false＝这次攻击不能用【圣光】抵挡（如【阴阳转换】的询问）
## 高亮目标 见 engine.ask_skill：非空时随询问下发（highlight_ids），只把这几名角色点亮给人看，
## 不参与选择、不参与提交（如【别烦我……】目标弃牌那一步顺带点亮「不弃就 +1 治疗」的队友）
func 询问(pid: int, skill_id: int, need_card: int = 0, need_target: int = 0, card_source: int = GConst.CardSource.Hand, options: Array = [], card_max: int = 0, card_rule: String = "", cards: Array = [], can_cancel: bool = true, 序号: int = 0, 收牌人id: int = -1, targets: Array = [], 张数: int = -1, 额外: Dictionary = {}, 预览基准: int = 0, 预览类型: int = 0, 保留倒计时: bool = false, 预览目标: Array = [], 可圣光: bool = true, 预览伤害: int = -1, cover_need: int = 0, ask_prompt: String = "", 默认选项: int = -1, 询问文案: String = "", 高亮目标: Array = [], 超时目标: Array = [], 盖牌最多: int = 0, 手牌数: int = -1, 可返回: bool = false) -> void:
	# 提示里的 {n}：need_card 为 0 表示「可弃可不弃」，这时取上限（card_max）才说得通，
	# 否则文案会变成「弃 0 张」。需要「可弃可不弃、但文案要显式给出张数」时用 张数 覆盖。
	var n: int = 张数 if 张数 >= 0 else (need_card if need_card > 0 else card_max)
	# 询问文案：给了就直接用（如【别烦我……】让队友指定目标时，直接给整段技能说明）
	var 文案: String = 询问文案 if not 询问文案.is_empty() else 提示(skill_id, 序号, n, 收牌人id, 额外)
	engine.ask_skill(pid, skill_id, need_card, need_target, card_source, options, card_max, card_rule, cards, can_cancel,
		文案, targets, 预览基准, 预览类型, 保留倒计时, 预览目标, 可圣光, 预览伤害, cover_need,
		false, 默认选项, false, ask_prompt, 高亮目标, 超时目标, 盖牌最多, 手牌数, 可返回)


# ============================================================
# 多步询问（分段询问）框架
#   设计/需求/迁移进度：项目文档/多步询问统一框架-设计与迁移.md
#   一条链＝若干段，每段一次询问；段之间不落副作用，副作用统一放在结算回调里，
#   所以「返回上一段」不需要撤账。
# ============================================================
## 正在进行的链：{链号: {"段": int, "答案": Array}}
## 答案项：{"args": Array, "cards": Array, "dsts": Array}
var _多步链: Dictionary = {}


## 推进一条多步询问链（角色在自己的 p_* / p_*_skill 里调用）：
##   链号   技能号（也用作询问里的 skill_id，决定提示 / 指示器 / 飘字）
##   段表   每一项描述一段：
##     "选项"       Array   选项列表（空＝这一段只选牌 / 选目标 / 只是确认）
##     "需牌"       int     要选几张牌（0＝不选牌）
##     "需目标"     int     要点几名角色
##     "来源"       int     GConst.CardSource，默认手牌
##     "牌白"/"目标白" Array 白名单
##     "可返回"     bool    这一段空应答＝退回上一段重问（第一段无效）
##     "可取消"     bool    这一段空应答＝整条链不发动（默认 true）
##     "超时"       Callable 段号：超时（is_timeout）时直接调它收尾（优先于「超时默认」）
##     "超时默认"   Variant 没有「超时」回调时，超时把这一段当作这个答案；都没有就按「不发动」收尾
##     "问谁"       int / Callable(答案)  这一段问哪名玩家（默认自己；队友代答 / 问别人时用）
##     "技能号"     int / Callable(答案)  这一段用哪个技能号发询问（默认＝链号；一条链里两段是不同技能时用）
##     "取消"       Callable() -> int  玩家在这一段取消整条链时调用（清阶段标记 / 还原本地状态）；
##                  可以返回 URGENT/WAIT 表示「不这么做」本身要结算（框架原样返回）
##     "答完"       Callable(回, 答案) -> int  这一段答完立刻结算（可压状态并返回 URGENT/WAIT），
##                  返回值非 SUCCESS 时框架原样返回；段号已推进，重入时从下一段继续
##     "跳过"       Callable(答案) -> bool  条件段：返回 true 就跳过这一段不问
##     "校验"       Callable(答案项) -> bool 这一段提交的答案合法吗；不合法报错后重问本段
##     "校验失败回退" bool   校验不过时退回上一段（默认 false＝重问本段）
##     "提示序号"/"张数"/"收牌人"/"额外"/"预览基准"/"预览类型"/"预览目标"/"预览伤害"
##     "需盖牌"/"盖牌最多"/"手牌数"/"询问文案"/"默认选项"/"高亮"/"超时目标"/"可圣光"
##   结算   Callable(答案: Array) -> int：所有段都答完后调用；返回值原样传给引擎
## 返回：WAIT＝正在问；否则是结算回调的返回值（SUCCESS / URGENT）
func 多步询问(链号: int, 段表: Array, 结算: Callable) -> int:
	if not _多步链.has(链号):
		_多步链[链号] = {"段": 0, "答案": []}
	var 链: Dictionary = _多步链[链号]
	while true:
		var 段号: int = int(链.get("段", 0))
		var 答案: Array = 链.get("答案", [])
		if 段号 >= 段表.size():
			_多步链.erase(链号)
			return 结算.call(答案)
		var 段: Dictionary = 段表[段号]
		# 条件段：前面几段的答案决定这一段要不要问（如「怒火压制 / 魔纹融合」选了前者就不用问翻转档）
		var 跳过: Variant = 段.get("跳过", null)
		if 跳过 is Callable and bool((跳过 as Callable).call(答案)):
			链["段"] = 段号 + 1
			continue
		if not engine.has_reply():
			_多步问一段(链号, 段号, 段, 答案)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var 回: Dictionary = {
			"args": r.get("args", []), "cards": r.get("card_ids", []), "dsts": r.get("dst_ids", []),
		}
		var 空: bool = (回["args"] as Array).is_empty() and (回["cards"] as Array).is_empty() \
			and (回["dsts"] as Array).is_empty()
		if 空:
			# 超时：这一段给了默认答案就当作选中了它，否则整条链按「不发动」收尾
			# （不能让掉线 / 不操作的玩家把整局卡在一条强制询问上）
			if bool(r.get("is_timeout", false)):
				var 超时处理: Variant = 段.get("超时", null)
				if 超时处理 is Callable:
					_多步链.erase(链号)
					return (超时处理 as Callable).call()
				if 段.has("超时默认"):
					var 默认: Variant = 段["超时默认"]
					答案.append({"args": 默认 if 默认 is Array else [默认], "cards": [], "dsts": []})
					链["段"] = 段号 + 1
					continue
				_多步链.erase(链号)
				return SUCCESS
			# 返回上一段：这一段允许返回且不是第一段
			if bool(段.get("可返回", false)) and 段号 > 0:
				答案.resize(段号 - 1)
				链["段"] = 段号 - 1
				continue
			# 其余空应答＝整条链不发动（可取消时）；不能取消（异常空应答）就重问这一段
			if bool(段.get("可取消", true)):
				_多步链.erase(链号)
				# 「取消」回调可以返回 URGENT / WAIT：有的技能「不这么做」本身就是一次结算
				# （如忌妒少女【醋意休心】：目标不弃法术牌 → 直接 2 点法术伤害 + 水晶）
				var 取消回调: Variant = 段.get("取消", null)
				if 取消回调 is Callable:
					var 取消返回: int = int((取消回调 as Callable).call())
					if 取消返回 != SUCCESS:
						return 取消返回
				return SUCCESS
			_多步问一段(链号, 段号, 段, 答案)
			return WAIT
		# 段自带的合法性校验：不过关就报错并按「校验失败回退」决定重问本段还是退回上一段
		var 校验: Variant = 段.get("校验", null)
		if 校验 is Callable and not bool((校验 as Callable).call(回)):
			engine.报错(str(段.get("校验失败文案", "操作无效，请重新选择")), player.id)
			if bool(段.get("校验失败回退", false)) and 段号 > 0:
				答案.resize(段号 - 1)
				链["段"] = 段号 - 1
				continue
			_多步问一段(链号, 段号, 段, 答案)
			return WAIT
		答案.append(回)
		链["段"] = 段号 + 1
		# 「答完」：这一段答完立刻做的结算（可能压状态并返回 URGENT/WAIT）。
		# 段号已推进，引擎重入时会从下一段继续，不会把这一段重问一遍。
		var 答完: Variant = 段.get("答完", null)
		if 答完 is Callable:
			var 答完返回: int = int((答完 as Callable).call(回, 答案))
			if 答完返回 != SUCCESS:
				return 答完返回
	return SUCCESS


## 段字段可以是 Callable(答案) -> 值：按「已经答过的答案」现算（如第二步的白名单要看第一步丢了什么）
func _多步取值(值: Variant, 答案: Array) -> Variant:
	if 值 is Callable:
		return (值 as Callable).call(答案)
	return 值


## 问链里的某一段（内部用；询问参数照段规格逐项传，第二段起沿用同一次等待的倒计时）
func _多步问一段(链号: int, 段号: int, 段: Dictionary, 答案: Array = []) -> void:
	var 问谁: int = int(_多步取值(段.get("问谁", player.id), 答案))
	# 段可以自带技能号（默认＝链号）：同一条链里两段是不同技能时用（如圣炎收尾 → 圣炎祈愿）
	var 技能号: int = int(_多步取值(段.get("技能号", 链号), 答案))
	询问(问谁, 技能号,
		int(_多步取值(段.get("需牌", 0), 答案)), int(_多步取值(段.get("需目标", 0), 答案)),
		int(段.get("来源", GConst.CardSource.Hand)), _多步取值(段.get("选项", []), 答案),
		int(_多步取值(段.get("牌上限", 0), 答案)), str(段.get("牌规则", "")), _多步取值(段.get("牌白", []), 答案),
		bool(段.get("可取消", true)), int(段.get("提示序号", 0)), int(段.get("收牌人", -1)),
			_多步取值(段.get("目标白", []), 答案), int(段.get("张数", -1)), 段.get("额外", {}),
		int(_多步取值(段.get("预览基准", 0), 答案)), int(段.get("预览类型", 0)), 段号 > 0,
		_多步取值(段.get("预览目标", []), 答案), bool(段.get("可圣光", true)),
		int(段.get("预览伤害", -1)),
		int(段.get("需盖牌", 0)), str(_多步取值(段.get("询问文案", ""), 答案)),
		int(段.get("默认选项", -1)),
		"", 段.get("高亮", []), 段.get("超时目标", []),
		int(段.get("盖牌最多", 0)), int(段.get("手牌数", -1)), bool(段.get("可返回", false)))


## 放弃一条还没走完的链（技能被别的原因中断 / 新一轮发动前清干净）
func 多步询问重置(链号: int) -> void:
	_多步链.erase(链号)


## 这条链是不是正等着玩家回复（钩子类技能用它挡住「别的同类事件插进来」）
func 多步询问进行中(链号: int) -> bool:
	return _多步链.has(链号)


## 技能行动提交的牌本次「视为」哪个系别（如 3805 精灵的剑舞 = 风系）。
## 0＝按牌面本身（默认）。额外行动的「该系攻击牌」白名单校验据此放行：
## 视为系别的技能不再按真实牌的系别驳回（牌本身是否合法由技能自己的 v_* 校验）。
func 技能视为系别(_action: Dictionary) -> int:
	return 0


## 读取技能询问回复：返回 true=发动、false=放弃
func take_skill_reply() -> bool:
	var r: Dictionary = engine.take_reply()
	var args: Array = r.get("args", [])
	return args.size() > 0 and int(args[0]) == 1


## 读取技能询问的完整回复（需要卡牌/目标时用）
func take_skill_reply_full() -> Dictionary:
	return engine.take_reply()


## 广播技能发动
## 广播技能发动。名称（可选）覆盖本次播报 / 战斗日志里的技能名：
## 同一技能按选择分支显示不同名字时用（如 3802 元素射击按子弹系别显示「元素射击*SORA*风系」）。
func notice_skill(skill_id: int, dst_ids: Array = [], 名称: String = "") -> void:
	var 数据: Dictionary = {"skill_id": skill_id, "src_id": player.id, "dst_ids": dst_ids}
	if not 名称.is_empty():
		数据["name"] = 名称
	engine.broadcast(GConst.Msg.Skill, 数据)


## 施加治疗：一律经引擎入口（写日志，按输出量记、并带上施术者），不要直接调 add_cross_num
func 施加治疗(dst_id: int, amount: int) -> void:
	engine.add_cross(dst_id, amount, player.id)


## 施加治疗（无视目标治疗上限版）：【神圣契约】这类「突破上限」的技能用；
## 封顶 > 0 时治疗后不超过它（如最高到 4）。普通加治疗仍用 施加治疗()。
func 施加治疗_突破(dst_id: int, amount: int, 封顶: int) -> void:
	engine.add_cross_pierce(dst_id, amount, player.id, 封顶)


## ⑥ 伤害转移（F6 / 4702）：只能在 p_timeline_6 里调用。把这次伤害的承受者改成新目标，
## 并由引擎声明「这次伤害不因手牌超限掉士气」（超限牌照弃、士气不扣）；返回错误码。
## 必须在按点数摸牌之前调用 —— 新目标不会再有一次治疗回应（⑥ 在治疗之后）。
## 之后的摸牌 / 超限都按 harm["dst"] 走；p_timeline_6_drawn / p_harm_end 的 ctx 由引擎在钩子触发时
## 重建（ctx.dst = 转移后的新目标），所以按 ctx.dst 判断的角色（501 反噬、802 智慧法典等）会自动跟到新目标。
## 只有同一次 p_timeline_6 钩子轮次里的其它角色拿到的是轮次开始时的快照，那时要看最新目标请读 harm["dst"]；
## 发生转移时 harm["redirect_from"] 记录原目标。客户端头像提示 / 伤害对象由 CLIENT 任务接入。
func 转移伤害(harm: Dictionary, 新目标id: int, 免士气: bool = true) -> int:
	if engine == null:
		return GConst.GE_INVALID_PLAYERID
	return engine.转移伤害(harm, 新目标id, 免士气)


## 安排自己的额外回合（F7 / 10803）：当前回合结束后立即开始，不推进 current_id、不增加 round_id；
## 攻击加伤只作用于这个额外回合里自己的普通攻击 / 应战反击（角色自建 harm 的攻击技能需自行读取
## engine.攻击基础伤害 / engine.额外回合加伤）。
func 安排额外回合(攻击加伤: int = 0, 来源: int = 0) -> int:
	if engine == null or player == null:
		return GConst.GE_INVALID_PLAYERID
	return engine.安排额外回合(player.id, 攻击加伤, 来源)


## 永久替换自己的角色卡（F7 / 10803：剑之子 → 风之剑圣）。在技能结算末尾调用；
## 旧角色会先收到 p_before_role_replace 清理形态 / 标记，随后被解绑，之后只走新角色的钩子。
func 替换角色(新角色id: int, 重置上限: bool = true) -> int:
	if engine == null or player == null:
		return GConst.GE_INVALID_PLAYERID
	return engine.替换角色(player.id, 新角色id, 重置上限)


## 手牌里的法术牌牌号（不少技能要求「弃 N 张法术牌」，available_skills 的 "cards" 用它，
## 界面据此只让法术牌可点，避免玩家点到必被服务端拒的牌）
func magic_hand_ids() -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			out.append(cid)
	return out


## 手中满足条件的牌 id（available_skills 的 "cards" 用它；条件必须与 v_* 里的牌校验完全一致，
## 否则会出现「界面让点、服务端拒收」或「界面该亮的没亮」）
func hand_ids_where(条件: Callable) -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and bool(条件.call(cid, c)):
			out.append(cid)
	return out


## 手中带指定技能的牌 id（技能号见 技能表，如封印师的【地之封印】= 404）
func hand_ids_with_skill(技能号: int) -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.has_skill_id(技能号))


## 场上所有对手的 id（需要指定多名对手的技能，available_skills 的 "targets" 用它）
## 目标列表里有没有重复的人（说明写「N 名角色」的技能用它挡掉「同一人被点两次」）
func _has_duplicate(ids: Array) -> bool:
	var seen: Array = []
	for i: Variant in ids:
		if seen.has(int(i)):
			return true
		seen.append(int(i))
	return false


func enemy_ids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color:
			out.append(pid)
	return out


## 场上所有队友的 id（不含自己；需要指定队友的技能，available_skills 的 "targets" 用它）
func ally_ids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.id != player.id and p0.color == player.color:
			out.append(pid)
	return out


## 处于「盖牌可视为手牌使用或打出」的状态时返回 true（精灵射手【精灵祝福形态】下的【祝福】）。
## 出牌合法性、弃牌落位都问这里（BattlePlayer.has_hand_card / remove_hand_cards），
## 别把角色判断散在引擎或玩家对象里写死
func 盖牌可当手牌() -> bool:
	return false


## 场上满足条件的玩家 id（默认不含自己：只挑「别人」；确实允许指向自己的技能传 含自己 = true）。
## 需要按条件过滤目标的技能，available_skills 的 "targets" 用它
func player_ids_where(条件: Callable, 含自己: bool = false) -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and (含自己 or p0.id != player.id) and bool(条件.call(p0)):
			out.append(pid)
	return out


## 这名玩家能不能接收「这颗技能放置的基础效果」：问目标角色自己的 v_basic_effect_target
## （如 4601 灵枝旨意「你无法成为基础效果的目标」）；代表牌取手里带该技能的牌，没有就传 0。
## 放基础效果的技能（封印 401~405 / 赐福 1601~1602 / 天使之墙 701 等）：
## available_skills 的目标白名单和 v_magic_skill 校验都要用它，别只靠 add_basic_effect 兜底 ——
## 否则客户端会把「免疫基础效果」的角色点亮，玩家点了却被服务端拒，看着像客户端判断脱节。
func 目标可接收基础效果(dst_id: int, 技能号: int) -> bool:
	var 候选: Array[int] = hand_ids_with_skill(技能号)
	var 代表牌: int = 候选[0] if not 候选.is_empty() else 0
	return engine.v_basic_effect_target(dst_id, 代表牌) == GConst.GE_SUCCESS


## 从 from_id 出发、沿 post（或 pre）方向最近的一名对手；没有则 -1
func nearest_enemy_id(from_id: int, post_dir: bool) -> int:
	var cur: BattlePlayer = engine.p(from_id)
	if cur == null:
		return -1
	var nid: int = cur.post_id if post_dir else cur.pre_id
	for _i: int in range(engine.order.size()):
		var pp: BattlePlayer = engine.p(nid)
		if pp == null:
			return -1
		if pp.color != cur.color:
			return nid
		nid = pp.post_id if post_dir else pp.pre_id
	return -1


## 从 from_id 出发、沿 post（右手边）或 pre 方向最近的一名队友（不含自己）；没有则 -1。
## F9 / 10601「你右手边最近的队友」用 nearest_teammate_id(player.id, true)。
func nearest_teammate_id(from_id: int, post_dir: bool = true) -> int:
	if engine == null:
		return -1
	return engine.nearest_teammate_id(from_id, post_dir)


## 群伤结算顺序：服务端对多名目标一贯「从自己上家起、沿座位逆序」逐个压栈（状态是栈，LIFO →
## 从自己/下家起正序结算）。这里返回正序结算顺序 ＝ 从自己起沿行动顺序绕一圈、只保留「目标集合」里的人：
##   自己在集合里就排第一个，否则第一个就是下家（自己右手边第一个）。
## 因为伤害状态是栈（后压先算），调用方要**逆序**遍历本结果来压栈，自己/下家才会最先结算。
## 对照服务端：SiLing::WenYi、MoDao::HuiMieFengBao / MoBaoChongJi、LingFu::LeiMing_Effect 等
## 都是「从 getPre() 反向压栈」。
func 结算顺序(目标集合: Array) -> Array[int]:
	var 集合: Array = 目标集合.duplicate()
	var out: Array[int] = []
	var cur: int = player.id
	for _i: int in range(engine.order.size()):
		if 集合.has(cur):
			out.append(cur)
		cur = engine.next_id(cur)
	return out


# ============================================================
# 【魔弹掌控】（802）/【魔弹掌握】（7601）—— 主动打【魔弹】时的落点选择
# 技能原文：「你主动使用【魔弹】时可以选择逆向传递」。
# 只作用于「主动打出【魔弹】」这一步（见 missile_targets）；魔弹一旦打出，
# 后续的传递方向就由出弹时定下，任何角色在传递时都不能改向（见 BattleEngine.SMissileAsk）。
# ============================================================
## 本角色是否拥有【魔弹掌控】/【魔弹掌握】（默认为否，魔导 / 节日魔导覆写为 true）
func has_missile_mastery() -> bool:
	return false


## 本角色打出【魔弹】时的可选落点：默认只有右手边（post）最近的对手；
## 有【魔弹掌控】/【魔弹掌握】时左手边（pre）那个也能选（＝逆向传递）。剔除 -1 与重复
func missile_targets(from_id: int) -> Array[int]:
	var out: Array[int] = []
	var 顺: int = nearest_enemy_id(from_id, true)
	if 顺 >= 0:
		out.append(顺)
	if has_missile_mastery():
		var 逆: int = nearest_enemy_id(from_id, false)
		if 逆 >= 0 and not out.has(逆):
			out.append(逆)
	return out


# ============================================================
# 【魔弹融合】—— 魔导（803）/ 节日魔导（7602）共通
# 自己的地系 / 火系牌可以当【魔弹】打出去：落点与【魔弹】完全一致（默认右手边最近的对手，
# 不接受队友；有【魔弹掌控】/【魔弹掌握】的角色左右各一个候选，见 missile_targets）。
# 打出去之后的「继续传递 / 圣光抵挡 / 放弃承受」全部交给引擎统一的魔弹传递询问（SMissileAsk），
# 与主动打出【魔弹】走同一条链；能不能继续用牌传递由本角色的 v_remissile 覆写决定。
# 技能号各角色不同，只影响播报 / 日志，不影响牌与落点的校验。
#
# 系别可配：默认地 / 火（魔导师 8 / 节日魔导 76 的现状）。47 水/火、87 雷/火、107 地/风 等
# 角色在各自脚本里覆写 missile_fusion_elements() 即可，魔弹融合牌表、发动校验、响应传递
# 都走同一份配置，不要在下游再写死系别。106 的「弃 2 张同系牌」是独立入口，不经过这里。
# ============================================================
const MISSILE_FUSION_SKILL: int = 803


## 本角色【魔弹融合】可当【魔弹】的系别（默认地 / 火，与 8 / 76 现状一致）。
## 借用 / 变体角色覆写本方法即可（返回 GConst.CardElement.* 的数组）。
func missile_fusion_elements() -> Array[int]:
	return [GConst.CardElement.Fire, GConst.CardElement.Earth]


## 这张牌能否当【魔弹】使用 / 响应传递：【魔弹】本身恒可，其余走 missile_fusion_elements()。
## 拥有【魔弹融合】的角色在 v_missile / v_remissile 覆写里用它，保证「主动打出」与
## 「继续传递」是同一口径。
func can_use_as_missile(card: GCard) -> bool:
	if card == null:
		return false
	if card.card_name_enum() == GConst.CardName.Missile:
		return true
	return can_use_as_missile_fusion(card)


## 这张牌能否作为【魔弹融合】的发动牌：必须是配置系别之一。
## 【魔弹】本身不算融合材料（它走普通【魔弹】行动，不占【魔弹融合】这个技能按钮）。
func can_use_as_missile_fusion(card: GCard) -> bool:
	if card == null:
		return false
	return missile_fusion_elements().has(card.element_enum())


## 手牌里能作为【魔弹融合】发动牌的牌 id（available_skills 的 "cards" 用）。
## 与 can_use_as_missile_fusion / v_missile_fusion 同一口径，界面不会点到必被服务端拒的牌。
func missile_fusion_hand_ids() -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return can_use_as_missile_fusion(c))


## 本角色【魔弹融合】的技能号（默认魔导师的 803；节日魔导覆写为 7602）
func missile_fusion_skill() -> int:
	return MISSILE_FUSION_SKILL


## 魔弹融合的牌与落点校验（v_magic_skill 用）
func v_missile_fusion(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	if not player.has_hand_card(cid):
		return GConst.GE_INVALID_CARDID
	var card: GCard = Data.get_card(cid)
	if not can_use_as_missile_fusion(card):
		return GConst.GE_INVALID_CARDID
	if not missile_targets(player.id).has(int(dsts[0])):
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 把这张地系 / 火系牌当【魔弹】打出去（p_magic_skill 用）。
## 返回 URGENT：魔弹传递询问已经压在栈顶，本次技能行动要等它结算完再跑 p_after_magic。
## 若返回 SUCCESS，SkillRun 会把 p_after_magic 压到魔弹询问之上，行动结束钩子就会先于魔弹伤害触发，
## 与普通【魔弹】路径（先魔弹、再行动结束）不一致。
func cast_missile_fusion(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	notice_skill(missile_fusion_skill(), [dst_id])
	# 地/火牌这次是当【魔弹】打出去的：card_ids 仍放真正打出的牌（客户端要展示它），
	# 另用 as_card_id 说明这次出牌在系统里视为【魔弹】——音效/特效与后续魔弹相关逻辑都按它走
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true, "as_card_id": engine.missile_as_card(cid),
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	var used: Array[int] = [player.id, dst_id]
	# 落点选了逆向那个＝本次沿 pre 方向传递
	var 顺向: bool = dst_id == nearest_enemy_id(player.id, true)
	engine.push(BattleEngine.SMissileAsk.new(dst_id, player.id, BattleEngine.MISSILE_BASE_POINT, 顺向, used))
	return URGENT


# ============================================================
# 角色工厂
# ============================================================
static func create(role_id: int, p: BattlePlayer, e: BattleEngine) -> BattleRole:
	var script_path: String = _script_of(role_id)
	if script_path == "" or not ResourceLoader.exists(script_path):
		return null
	var scr: GDScript = load(script_path)
	var r: BattleRole = scr.new()
	r.setup(p, e)
	return r


static func _script_of(role_id: int) -> String:
	# 角色实现脚本写在「角色表」的「脚本」列；表里没有（未移植）时返回空，按通用规则结算
	return Data.role_script(role_id)

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
## 如 32031 / 36063 / 37052），否则 `step >= STEP_DONE` 的守卫会把「刚压入的子步骤」误判为已完成，
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
func p_between_weak_and_action(_ctx: Dictionary) -> int: return SUCCESS
func p_before_action(_ctx: Dictionary) -> int: return SUCCESS
func p_boot(_ctx: Dictionary) -> int: return SUCCESS
func p_before_attack(_ctx: Dictionary) -> int: return SUCCESS
func p_after_attack(_ctx: Dictionary) -> int: return SUCCESS
func p_before_magic(_ctx: Dictionary) -> int: return SUCCESS
func p_after_magic(_ctx: Dictionary) -> int: return SUCCESS
func p_before_special(_ctx: Dictionary) -> int: return SUCCESS
func p_after_special(_ctx: Dictionary) -> int: return SUCCESS
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
func p_xin_yue(_ctx: Dictionary) -> int: return SUCCESS
func p_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
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
func p_basic_effect_change(_ctx: Dictionary) -> int: return SUCCESS
func p_additional_action(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_end(_ctx: Dictionary) -> int: return SUCCESS
func p_after_turn_end(_ctx: Dictionary) -> int: return SUCCESS
## 应战成立后（对照服务端 PlayerEntity::p_reattack）：可把应战打出的这张牌「视为」另一张。
## ctx: {card_id 打出的牌, doer 应战者, target 反击目标, 改用 视为哪张牌, real 是否实体牌}
## 角色也可设置 ctx["block"] = true，把这次应战当作「格挡」（本次攻击落空、不反击），如阴阳师光系应战
func p_reattack(_ctx: Dictionary) -> int: return SUCCESS
## 主动攻击宣告时（对照应战那条的 p_reattack）：角色可把本次打出的攻击牌「视为」另一张，
## 如苍炎魔女【烈焰形态】下除水系 / 暗系外的攻击牌一律视为火系虚拟【火焰斩】。
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
func v_buy(_args: Array) -> int: return V_NOT_OVERRIDE
func v_extract(_args: Array, _team_gem: int, _team_crystal: int, _dst_ids: Array) -> int: return V_NOT_OVERRIDE
func v_attacked() -> int: return V_NOT_OVERRIDE
func v_additional_action(_cause: int) -> int: return V_NOT_OVERRIDE


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


## 该主动技能是不是「启动」：引擎只在**特殊技能**这一类上问它（见 battle_engine），
## 认定后决定「结算完重新进入行动阶段」而不是回合结束，
## 同时受「每回合只能发动一个启动技能」限制（player.boot_skill_used，引擎统一下发/校验）。
## 发动成功的角色要在自己的结算里把 player.boot_skill_used 置 true
func is_free_skill(_skill_id: int) -> bool:
	return false


## 本阶段「普通行动」（非技能，如直接打出手牌）能用的手牌白名单（空＝不限制）。
## 如【修罗连斩】的额外攻击行动期间只能出火系攻击牌，界面据此把其余牌置灰
func action_card_ids(_action_type: int) -> Array:
	return []


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
## 表里没配就返回空串，客户端会退回默认文案（「是否发动【X】？」）
func 提示(skill_id: int, 序号: int = 0, 张数: int = 0, 收牌人id: int = -1, 额外: Dictionary = {}) -> String:
	return GConst.提示文本(skill_id, 序号, engine._称号(player), 张数, _收牌人称号(收牌人id), 额外)


## 收牌人称号（{dst} 用；没收牌人就返回空串）
func _收牌人称号(收牌人id: int) -> String:
	return engine._称号(engine.p(收牌人id)) if 收牌人id >= 0 else ""


## 询问某玩家（自己或别人）选牌 / 是否发动：参数与 engine.ask_skill 一致，只是「提示」文案
## 不用每个调用点手写 —— 自动取技能表「提示」列的第 序号 条，并把 {src}=本技能发起者（自己）、
## {n}=要交/弃的张数、{dst}=收牌人 填好（收牌人id 只在「我交给别人」的场合给）。
## 同一个技能有多次询问且要不同文案时，靠 序号 区分；表里没配就退回默认文案（「是否发动【X】？」）
## 预览基准 / 预览类型 见 engine.ask_skill：客户端现算头像提示要用到的数值与它的伤害类型
## （如【战纹碎击】本次攻击原本的伤害、【朝圣】本次受到的伤害是法术还是攻击）。
## 保留倒计时 见 engine.wait_for：同一条询问链上的后续询问传 true，不重新计时
func 询问(pid: int, skill_id: int, need_card: int = 0, need_target: int = 0, card_source: int = GConst.CardSource.Hand, options: Array = [], card_max: int = 0, card_rule: String = "", cards: Array = [], can_cancel: bool = true, 序号: int = 0, 收牌人id: int = -1, targets: Array = [], 张数: int = -1, 额外: Dictionary = {}, 预览基准: int = 0, 预览类型: int = 0, 保留倒计时: bool = false, 预览目标: Array = []) -> void:
	# 提示里的 {n}：need_card 为 0 表示「可弃可不弃」，这时取上限（card_max）才说得通，
	# 否则文案会变成「弃 0 张」。需要「可弃可不弃、但文案要显式给出张数」时用 张数 覆盖。
	var n: int = 张数 if 张数 >= 0 else (need_card if need_card > 0 else card_max)
	engine.ask_skill(pid, skill_id, need_card, need_target, card_source, options, card_max, card_rule, cards, can_cancel,
		提示(skill_id, 序号, n, 收牌人id, 额外), targets, 预览基准, 预览类型, 保留倒计时, 预览目标)


## 读取技能询问回复：返回 true=发动、false=放弃
func take_skill_reply() -> bool:
	var r: Dictionary = engine.take_reply()
	var args: Array = r.get("args", [])
	return args.size() > 0 and int(args[0]) == 1


## 读取技能询问的完整回复（需要卡牌/目标时用）
func take_skill_reply_full() -> Dictionary:
	return engine.take_reply()


## 广播技能发动
func notice_skill(skill_id: int, dst_ids: Array = []) -> void:
	engine.broadcast(GConst.Msg.Skill, {"skill_id": skill_id, "src_id": player.id, "dst_ids": dst_ids})


## 施加治疗：一律经引擎入口（写日志，按输出量记、并带上施术者），不要直接调 add_cross_num
func 施加治疗(dst_id: int, amount: int) -> void:
	engine.add_cross(dst_id, amount, player.id)


## 施加治疗（无视目标治疗上限版）：【神圣契约】这类「突破上限」的技能用；
## 封顶 > 0 时治疗后不超过它（如最高到 4）。普通加治疗仍用 施加治疗()。
func 施加治疗_突破(dst_id: int, amount: int, 封顶: int) -> void:
	engine.add_cross_pierce(dst_id, amount, player.id, 封顶)


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


## 场上满足条件的玩家 id（默认不含自己：只挑「别人」；确实允许指向自己的技能传 含自己 = true）。
## 需要按条件过滤目标的技能，available_skills 的 "targets" 用它
func player_ids_where(条件: Callable, 含自己: bool = false) -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and (含自己 or p0.id != player.id) and bool(条件.call(p0)):
			out.append(pid)
	return out


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
# 【魔弹掌控】（802）—— 魔导的落点选择
# 技能原文：「你主动使用【魔弹】时可以选择逆向传递」。
# 只作用于「主动打出【魔弹】」这一步（见 missile_targets）；魔弹一旦打出，
# 后续的传递方向就由出弹时定下，任何角色在传递时都不能改向（见 BattleEngine.SMissileAsk）。
# ============================================================
## 本角色是否拥有【魔弹掌控】（默认为否，魔导覆写为 true）
func has_missile_mastery() -> bool:
	return false


## 本角色打出【魔弹】时的可选落点：默认只有右手边（post）最近的对手；
## 有【魔弹掌控】时左手边（pre）那个也能选（＝逆向传递）。剔除 -1 与重复
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
# 【魔弹融合】（803）—— 魔导 / 特殊魔导共通
# 自己的地系 / 火系牌可以当【魔弹】打出去：落点与【魔弹】完全一致（默认右手边最近的对手，
# 不接受队友；有【魔弹掌控】802 的角色左右各一个候选，见 missile_targets）。
# 打出去之后的「继续传递 / 圣光抵挡 / 放弃承受」全部交给引擎统一的魔弹传递询问（SMissileAsk），
# 与主动打出【魔弹】走同一条链；能不能继续用牌传递由本角色的 v_remissile 覆写决定。
# ============================================================
const MISSILE_FUSION_SKILL: int = 803


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
	if card == null:
		return GConst.GE_INVALID_CARDID
	if card.element_enum() != GConst.CardElement.Fire and card.element_enum() != GConst.CardElement.Earth:
		return GConst.GE_INVALID_CARDID
	if not missile_targets(player.id).has(int(dsts[0])):
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 把这张地系 / 火系牌当【魔弹】打出去（p_magic_skill 用）
func cast_missile_fusion(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	notice_skill(MISSILE_FUSION_SKILL, [dst_id])
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
	return SUCCESS


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

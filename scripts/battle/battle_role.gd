class_name BattleRole
extends RefCounted
## 角色基类（对照服务端 DiceGameServer/PlayerEntity 的 p_* / v_* 钩子 + role/*）
##
## 钩子约定：
## - 统一签名为 func p_xxx(ctx: Dictionary) -> int，返回 SUCCESS / WAIT / URGENT
## - 引擎在对应时机对「每个玩家」调用一次；若某角色返回 WAIT，则整个钩子轮次暂停，
##   收到该玩家的回复后从同一位玩家继续调用（因此角色内部用 step 记录进度）
## - step 由引擎在每次钩子轮次开始时统一重置为 0；角色用 engine.ask_skill() 请求玩家输入
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

var player: BattlePlayer = null
var engine: BattleEngine = null
var step: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	player = p
	engine = e


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
## 回合开始的基础效果检查（对照服务端 FengYin::WuXiShuFu_Effect）：引擎在虚弱询问前对全体角色调用，
## 角色若判定当前回合玩家身上有自己的效果（如【五系束缚】），把它消耗掉并把应摸牌数加进 ctx["how_many"]
## ctx: {player 当前回合玩家, how_many 累加值}
func p_check_basic_effect(_ctx: Dictionary) -> int: return SUCCESS
func p_basic_effect_change(_ctx: Dictionary) -> int: return SUCCESS
func p_additional_action(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_end(_ctx: Dictionary) -> int: return SUCCESS
func p_after_turn_end(_ctx: Dictionary) -> int: return SUCCESS
## 应战成立后（对照服务端 PlayerEntity::p_reattack）：可把应战打出的这张牌「视为」另一张。
## ctx: {card_id 打出的牌, doer 应战者, target 反击目标, 改用 视为哪张牌, real 是否实体牌}
## 角色也可设置 ctx["block"] = true，把这次应战当作「格挡」（本次攻击落空、不反击），如阴阳师光系应战
func p_reattack(_ctx: Dictionary) -> int: return SUCCESS


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
func v_extract(_args: Array, _team_gem: int, _team_crystal: int, _dst_id: int) -> int: return V_NOT_OVERRIDE
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


## 该主动技能是否属于「启动」：发动后不消耗本回合行动，行动阶段照旧继续
## （如格斗家【百式幻龙拳】【斗神天驱】：原版在回合开始的 p_boot 里询问，不占用行动）。
## 引擎在技能结算完后据此决定进入回合结束还是重新进入行动阶段
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
func 提示(skill_id: int, 序号: int = 0, 张数: int = 0, 收牌人id: int = -1) -> String:
	return GConst.提示文本(skill_id, 序号, engine._称号(player), 张数, _收牌人称号(收牌人id))


## 收牌人称号（{dst} 用；没收牌人就返回空串）
func _收牌人称号(收牌人id: int) -> String:
	return engine._称号(engine.p(收牌人id)) if 收牌人id >= 0 else ""


## 询问某玩家（自己或别人）选牌 / 是否发动：参数与 engine.ask_skill 一致，只是「提示」文案
## 不用每个调用点手写 —— 自动取技能表「提示」列的第 序号 条，并把 {src}=本技能发起者（自己）、
## {n}=要交/弃的张数、{dst}=收牌人 填好（收牌人id 只在「我交给别人」的场合给）。
## 同一个技能有多次询问且要不同文案时，靠 序号 区分；表里没配就退回默认文案（「是否发动【X】？」）
func 询问(pid: int, skill_id: int, need_card: int = 0, need_target: int = 0, card_source: int = GConst.CardSource.Hand, options: Array = [], card_max: int = 0, card_rule: String = "", cards: Array = [], can_cancel: bool = true, 序号: int = 0, 收牌人id: int = -1, targets: Array = []) -> void:
	# 提示里的 {n}：need_card 为 0 表示「可弃可不弃」，这时取上限（card_max）才说得通，
	# 否则文案会变成「弃 0 张」
	engine.ask_skill(pid, skill_id, need_card, need_target, card_source, options, card_max, card_rule, cards, can_cancel,
		提示(skill_id, 序号, need_card if need_card > 0 else card_max, 收牌人id), targets)


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
# 【魔弹掌握】（802）—— 魔导的落点选择
# 技能原文：「你主动使用【魔弹】时可以选择逆向传递」。
# 只作用于「主动打出【魔弹】」这一步（见 missile_targets）；魔弹一旦打出，
# 后续的传递方向就由出弹时定下，任何角色在传递时都不能改向（见 BattleEngine.SMissileAsk）。
# ============================================================
## 本角色是否拥有【魔弹掌握】（默认为否，魔导覆写为 true）
func has_missile_mastery() -> bool:
	return false


## 本角色打出【魔弹】时的可选落点：默认只有右手边（post）最近的对手；
## 有【魔弹掌握】时左手边（pre）那个也能选（＝逆向传递）。剔除 -1 与重复
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
# 不接受队友；有【魔弹掌握】802 的角色左右各一个候选，见 missile_targets）。
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

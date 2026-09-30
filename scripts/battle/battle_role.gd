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
func p_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
func p_true_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
# 说明：服务端的 p_cover_change / p_hand_change（盖牌/手牌变动时对全体触发）在本引擎没有通用触发点，
# 相关角色的效果改由各自的显式触发点处理（如蝶舞在移除【茧】处调用凋灵、巫女在多个结算点检查脱形态），
# 因此这里不再保留同名空钩子，避免被误当成「已接入」。
func p_show_hand(_ctx: Dictionary) -> int: return SUCCESS
func p_tap(_ctx: Dictionary) -> int: return SUCCESS
func p_basic_effect_change(_ctx: Dictionary) -> int: return SUCCESS
func p_additional_action(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_end(_ctx: Dictionary) -> int: return SUCCESS
func p_after_turn_end(_ctx: Dictionary) -> int: return SUCCESS


# ============================================================
# 牌类校验覆写（返回 V_NOT_OVERRIDE 表示不覆写，退回通用实现）
# 想「通用校验 + 追加限制」时，先调 player.base_v_xxx(...) 再判断
# ============================================================
func v_allow_action(_action_type: int, _args: Array) -> int: return V_NOT_OVERRIDE
func v_attack(_card_id: int, _dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_reattack(_card_id: int, _attack_card_id: int) -> int: return V_NOT_OVERRIDE
func v_block(_card_id: int) -> int: return V_NOT_OVERRIDE
func v_shield(_dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_weaken(_dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_missile(_card_id: int, _dst_id: int) -> int: return V_NOT_OVERRIDE
func v_remissile(_card_id: int) -> int: return V_NOT_OVERRIDE
func v_buy(_args: Array) -> int: return V_NOT_OVERRIDE
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


## 引擎按名字调用钩子
func call_hook(hook: String, ctx: Dictionary) -> int:
	if not has_method(hook):
		return SUCCESS
	return call(hook, ctx)


# ============================================================
# 常用工具
# ============================================================
## 询问本角色是否发动某技能（对应客户端「确定/取消」），返回 WAIT
func ask_self_skill(skill_id: int) -> int:
	engine.ask_skill(player.id, skill_id)
	return WAIT


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


## 场上满足条件的玩家 id（不含自己：默认只挑「别人」，确实允许指向自己的技能才把自己并进白名单；
## 需要按条件过滤目标的技能，available_skills 的 "targets" 用它）
func player_ids_where(条件: Callable) -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.id != player.id and bool(条件.call(p0)):
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


# ============================================================
# 【魔弹掌握】（802）—— 魔导的落点选择
# 技能原文：「你主动使用【魔弹】时可以选择逆向传递」。
# 这里按需求放宽到「响应【魔弹】继续传递时也能选方向」，其它角色不受影响。
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
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true,
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

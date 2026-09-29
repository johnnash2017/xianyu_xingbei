extends BattleRole
## 圣枪（roleID 10）—— 移植自服务端 role/ShengQiang.cpp
## 技能：
##   辉耀（1001，法术，弃 1 张水系牌，所有人各 +1 治疗，额外 +1 攻击行动）
##   惩戒（1002，法术，弃 1 张法术牌，将一名其他角色的 1 点治疗转移给你，额外 +1 攻击行动）
##   圣光祈愈（1003，法术，消耗 1 宝石，无视治疗上限 +2 治疗（最高 5），额外 +1 攻击行动；本回合不能发动天枪）
##   天枪（1004，主动攻击前，移除 2 点治疗，本次攻击对方无法应战；不能与圣击同时发动）
##   地枪（1005，主动攻击命中后，移除 X 点治疗（X<5），本次攻击伤害 +X；不能与圣击同时发动）
##   神圣信仰（1006，被动，[治疗] 上限 +1）
##   圣击（1007，被动，攻击命中后 +1 治疗）

const HUI_YAO: int = 1001
const CHENG_JIE: int = 1002
const SHENG_GUANG_QI_YU: int = 1003
const TIAN_QIANG: int = 1004
const DI_QIANG: int = 1005
const SHEN_SHENG_XIN_YANG: int = 1006
const SHENG_JI: int = 1007

var used_sheng_guang_qi_yu: bool = false
var used_tian_qiang: bool = false
var used_di_qiang: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 神圣信仰（1006）：[治疗] 上限 +1
	p.cross_max = GConst.CROSS_MAX + 1


## 每回合开始：重置三个回合限定标记
func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_sheng_guang_qi_yu = false
	used_tian_qiang = false
	used_di_qiang = false
	return SUCCESS


func available_skills() -> Array:
	var out: Array = []
	var 水系牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Water)
	if not 水系牌.is_empty():
		# 辉耀只能弃水系牌（v_magic_skill 校验同一条），下发 cards 让界面把其余手牌置灰
		out.append({"type": GConst.ActionType.MagicSkill, "id": HUI_YAO, "need_card": 1, "need_target": 0,
			"cards": 水系牌})
	if _hand_has_magic() and _has_other_with_cross():
		# 惩戒只能弃法术牌（v_magic_skill 校验同一条）
		# 目标须有治疗（v_magic_skill：dst.cross_num == 0 时返回 GE_INVALID_ACTION）
		out.append({"type": GConst.ActionType.MagicSkill, "id": CHENG_JIE, "need_card": 1, "need_target": 1,
			"cards": magic_hand_ids(),
			"targets": player_ids_where(func(p: BattlePlayer) -> bool: return p.cross_num > 0)})
	if player.gem >= 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_GUANG_QI_YU, "need_card": 0, "need_target": 0})
	return out


# ============================================================
# 主动攻击前（timeline_1）：天枪
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.cross_num < 2 or used_sheng_guang_qi_yu:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, TIAN_QIANG, 0, 0)
		return WAIT
	step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	notice_skill(TIAN_QIANG, [int(ctx.get("dst", -1))])
	player.sub_cross_num(2)
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	used_tian_qiang = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后（timeline_2_hit）：地枪 → 圣击
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = DI_QIANG
	if step == DI_QIANG:
		var r: int = _di_qiang(ctx)
		if r == WAIT:
			return WAIT
		step = SHENG_JI
	if step == SHENG_JI:
		_sheng_ji(ctx)
		step = STEP_DONE
	used_tian_qiang = false
	used_di_qiang = false
	return SUCCESS


## 地枪：主动攻击命中后，移除 X 点治疗（0<X<5），本次攻击伤害 +X
func _di_qiang(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.cross_num < 1:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, DI_QIANG, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var used: int = int(args[0]) if not args.is_empty() else 0
	if used <= 0 or used >= 5:
		return SUCCESS
	player.sub_cross_num(used)
	notice_skill(DI_QIANG, [int(ctx.get("dst", -1))])
	var harm: Dictionary = ctx["harm"]
	harm["point"] = int(harm["point"]) + used
	used_di_qiang = true
	engine._broadcast_game()
	return SUCCESS


## 圣击：被动，攻击命中后 +1 治疗（治疗已达上限 3、或本次已用地枪/天枪时不发动）
func _sheng_ji(ctx: Dictionary) -> void:
	if player.cross_num >= 3 or used_tian_qiang or used_di_qiang:
		return
	notice_skill(SHENG_JI, [int(ctx.get("dst", -1))])
	player.add_cross_num(1)
	engine._broadcast_game()


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	match aid:
		HUI_YAO:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or card.element_enum() != GConst.CardElement.Water:
				return GConst.GE_INVALID_ACTION
		CHENG_JIE:
			if cards.is_empty() or dsts.is_empty() or dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			var cid2: int = int(cards[0])
			var card2: GCard = Data.get_card(cid2)
			if not player.has_hand_card(cid2) or card2 == null or not card2.is_magic():
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			if dst == null or dst.cross_num == 0:
				return GConst.GE_INVALID_ACTION
		SHENG_GUANG_QI_YU:
			if player.gem < 1:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		HUI_YAO:
			return _hui_yao(action)
		CHENG_JIE:
			return _cheng_jie(action)
		SHENG_GUANG_QI_YU:
			return _sheng_guang_qi_yu()
	return GConst.GE_INVALID_ACTION


## 辉耀：弃 1 张水系牌，所有人各 +1 治疗，额外 +1 攻击行动
func _hui_yao(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var cid: int = int(cards[0])
	var dst_ids: Array = _all_player_ids_from_self()
	notice_skill(HUI_YAO, dst_ids)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	for d: Variant in dst_ids:
		var dp: BattlePlayer = engine.p(int(d))
		if dp != null:
			dp.add_cross_num(1)
	player.add_action(GConst.ActionType.Attack, HUI_YAO)
	engine._broadcast_game()
	return SUCCESS


## 惩戒：弃 1 张法术牌，将目标 1 点治疗转移给自己，额外 +1 攻击行动
func _cheng_jie(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	notice_skill(CHENG_JIE, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	dst.sub_cross_num(1)
	player.add_cross_num(1)
	player.add_action(GConst.ActionType.Attack, CHENG_JIE)
	engine._broadcast_game()
	return SUCCESS


## 圣光祈愈：消耗 1 宝石，无视治疗上限 +2 治疗（最高 5），额外 +1 攻击行动
func _sheng_guang_qi_yu() -> int:
	notice_skill(SHENG_GUANG_QI_YU, [player.id])
	player.set_gem(player.gem - 1)
	player.cross_num = mini(player.cross_num + 2, 5)
	player.add_action(GConst.ActionType.Attack, SHENG_GUANG_QI_YU)
	used_sheng_guang_qi_yu = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _hand_has_magic() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			return true
	return false


## 是否有其他角色拥有治疗（惩戒的目标条件）
func _has_other_with_cross() -> bool:
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.id != player.id and p0.cross_num > 0:
			return true
	return false


## 从自己下家开始、按座位序绕回自己，收集所有角色 id（辉耀的目标顺序）
func _all_player_ids_from_self() -> Array:
	var ids: Array = []
	var cur: int = player.post_id
	var guard: int = engine.order.size() + 1
	while cur != player.id and guard > 0:
		ids.append(cur)
		cur = engine.next_id(cur)
		guard -= 1
	ids.append(player.id)
	return ids

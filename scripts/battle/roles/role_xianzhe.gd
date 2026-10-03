extends BattleRole
## 贤者（roleID 17）—— 移植自服务端 role/XianZhe.cpp
## 被动：智慧法典（能量上限 +1；承受 >3 点法术伤害时 +2 宝石）
## 法术：魔道法典（弃 X 张异系牌，对目标与自己各造成 X-1 法术伤害）
##       圣洁法典（弃 X 张异系牌，最多 X-2 名角色各 +2 治疗，对自己造成 X-1 法术伤害）
## 响应：法术反弹（仅受 1 点法术伤害时，弃 X 张同系牌，对目标造成 X-1、对自己造成 X）

const ZHI_HUI_FA_DIAN: int = 1701
const MO_DAO_FA_DIAN: int = 1702
const SHENG_JIE_FA_DIAN: int = 1703
const FA_SHU_FAN_TAN: int = 1704

enum ElementKind { Invalid = 0, AllDifferent = 1, AllSame = 2 }


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.energy_max = p.energy_max + 1


func available_skills() -> Array:
	var out: Array = []
	if player.gem > 0:
		if _max_different_elements() >= 2:
			# 弃 X 张互异系牌（X≥2）：上限放到手牌数，并让客户端只让「与已选牌异系」的牌可点
			out.append({"type": GConst.ActionType.MagicSkill, "id": MO_DAO_FA_DIAN, "need_card": 2, "need_target": 1,
				"card_max": player.hand_count(), "card_rule": "diff"})
		if _max_different_elements() >= 3:
			# 圣洁法典要弃 X 张两两异系的牌（v_magic_skill：cards.size() >= 3 且全异系）：
			# 最少 3 张，最多只能选到手牌里不同元素的种数；目标数上限 = 弃牌数 - 2（服务端 cards.size()-2）。
			# 上限随弃牌数变化，故用 target_max_from_cards 告诉客户端（取消一张牌后上限要跟着降），
			# target_max 仍给「按当前手牌算出来的」最大值，仅供界面显示用
			out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_JIE_FA_DIAN, "need_card": 3, "need_target": 1,
				"target_max": maxi(1, _max_different_elements() - 2),
				"target_max_from_cards": 2,
				"card_max": _max_different_elements(), "card_rule": "diff"})
	return out


## 手牌中最多能凑出几种不同元素
func _max_different_elements() -> int:
	var elems: Array[int] = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null:
			var e: int = c.element_enum()
			if not elems.has(e):
				elems.append(e)
	return elems.size()


# ============================================================
# 承受法术伤害后：智慧法典 / 法术反弹
# ============================================================
func p_timeline_6_drawn(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	var point: int = int(harm.get("point", 0))
	if point > 3:
		_zhi_hui_fa_dian()
		return SUCCESS
	if point == 1:
		return _fa_shu_fan_tan()
	return SUCCESS


## 伤害 >3：+2 宝石
func _zhi_hui_fa_dian() -> void:
	notice_skill(ZHI_HUI_FA_DIAN, [player.id])
	player.set_gem(player.gem + 2)
	engine._broadcast_game()


## 伤害为 1：询问是否法术反弹
func _fa_shu_fan_tan() -> int:
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 弃 X 张同系牌（技能原文 X > 1，故最少 2 张）：上限放到手牌数，并让客户端只让同系牌可点
		询问(player.id, FA_SHU_FAN_TAN, 2, 1, GConst.CardSource.Hand, [], player.hand_count(), "same")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	var dsts: Array = r.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return SUCCESS
	# 技能原文要求弃牌数 X > 1（只弃 1 张不算发动）
	var 合法: bool = cards.size() > 1 and _has_cards(cards) and _element_kind(cards) == ElementKind.AllSame
	if not 合法:
		return SUCCESS
	var dst_id: int = int(dsts[0])
	notice_skill(FA_SHU_FAN_TAN, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	# 对自己造成 X 点法术伤害
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": cards.size(),
		"cause": FA_SHU_FAN_TAN, "type": GConst.HarmType.Magic,
	})
	# 对目标造成 X-1 点法术伤害
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": cards.size() - 1,
		"cause": FA_SHU_FAN_TAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	if aid == MO_DAO_FA_DIAN:
		if not _has_cards(cards):
			return GConst.GE_INVALID_CARDID
		if cards.size() < 2 or _element_kind(cards) != ElementKind.AllDifferent or player.gem == 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == SHENG_JIE_FA_DIAN:
		if not _has_cards(cards):
			return GConst.GE_INVALID_CARDID
		var dsts: Array = action.get("dst_ids", [])
		if _element_kind(cards) != ElementKind.AllDifferent or player.gem == 0:
			return GConst.GE_INVALID_ACTION
		if cards.size() < 3 or cards.size() - 2 < dsts.size():
			return GConst.GE_INVALID_ACTION
		if _has_duplicate(dsts):
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		MO_DAO_FA_DIAN:
			return _mo_dao_fa_dian(action)
		SHENG_JIE_FA_DIAN:
			return _sheng_jie_fa_dian(action)
	return GConst.GE_INVALID_ACTION


## 魔道法典：弃 X 张异系牌，对目标与自己各造成 X-1 法术伤害
func _mo_dao_fa_dian(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(MO_DAO_FA_DIAN, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	player.set_gem(player.gem - 1)
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	var point: int = cards.size() - 1
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": point,
		"cause": MO_DAO_FA_DIAN, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": point,
		"cause": MO_DAO_FA_DIAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 圣洁法典：弃 X 张异系牌，最多 X-2 名角色各 +2 治疗，对自己造成 X-1 法术伤害
func _sheng_jie_fa_dian(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	notice_skill(SHENG_JIE_FA_DIAN, dsts)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	player.set_gem(player.gem - 1)
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": cards.size() - 1,
		"cause": SHENG_JIE_FA_DIAN, "type": GConst.HarmType.Magic,
	})
	for d: Variant in dsts:
		var dp: BattlePlayer = engine.p(int(d))
		if dp != null:
			施加治疗(dp.id, 2)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 工具
# ============================================================
func _has_cards(cards: Array) -> bool:
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return false
	return not cards.is_empty()


## 判元素：全同 / 全异 / 其它
func _element_kind(cards: Array) -> int:
	var elements: Array[int] = []
	for c: Variant in cards:
		var card: GCard = Data.get_card(int(c))
		if card == null:
			return ElementKind.Invalid
		var e: int = card.element_enum()
		if not elements.has(e):
			elements.append(e)
	if elements.size() == 1:
		return ElementKind.AllSame
	if elements.size() == cards.size():
		return ElementKind.AllDifferent
	return ElementKind.Invalid


func _has_duplicate(ids: Array) -> bool:
	var seen: Array = []
	for i: Variant in ids:
		if seen.has(int(i)):
			return true
		seen.append(int(i))
	return false

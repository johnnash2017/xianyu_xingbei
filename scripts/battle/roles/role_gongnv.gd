extends BattleRole
## 弓之女神（roleID 3）—— 移植自服务端 role/GongNv.cpp
## 技能：闪电箭（被动，雷系攻击无法应战）、精准射击（攻击牌可选，强制命中但伤害-1）、
##       贯穿射击（主动攻击未命中后可选，弃 1 张法术牌造成 2 点法术伤害）、
##       闪光陷阱（法术技能，弃牌造成 2 点法术伤害）、狙击（法术技能，1 水晶把目标手牌补到 5 并额外攻击行动）

const JING_ZHUN_SHE_JI: int = 301
const SHAN_GUANG_XIAN_JING: int = 302
const JU_JI: int = 303
const SHAN_DIAN_JIAN: int = 304
const GUAN_CHUAN_SHE_JI: int = 305


func available_skills() -> Array:
	var out: Array = []
	# 闪光陷阱：只有手中带【闪光陷阱】的牌可作发动牌，下发给界面把其余手牌置灰
	# （v_magic_skill 校验同一张牌：须在手且带此特技）
	var 闪光牌: Array[int] = hand_ids_with_skill(SHAN_GUANG_XIAN_JING)
	if not 闪光牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHAN_GUANG_XIAN_JING, "need_card": 1, "need_target": 1,
			"cards": 闪光牌})
	if player.crystal > 0 or player.gem > 0:
		out.append({"type": GConst.ActionType.MagicSkill, "id": JU_JI, "need_card": 0, "need_target": 1})
	return out


# ============================================================
# 攻击宣告后：闪电箭（被动）→ 精准射击（可选）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SHAN_DIAN_JIAN
	if step == SHAN_DIAN_JIAN:
		_shan_dian_jian(ctx)
		step = JING_ZHUN_SHE_JI
	if step == JING_ZHUN_SHE_JI:
		var r: int = _jing_zhun_she_ji(ctx)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 闪电箭：雷系攻击无法被应战（被动，无需询问）
func _shan_dian_jian(ctx: Dictionary) -> void:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or card.element_enum() != GConst.CardElement.Thunder:
		return
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	notice_skill(SHAN_DIAN_JIAN, [int(ctx.get("dst", -1))])


## 精准射击：攻击牌带此特技时可选，强制命中但伤害 -1
func _jing_zhun_she_ji(ctx: Dictionary) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(JING_ZHUN_SHE_JI):
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, JING_ZHUN_SHE_JI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(JING_ZHUN_SHE_JI, [int(ctx.get("dst", -1))])
	ctx["hit_rate"] = GConst.HitRate.NoMiss
	var harm: Dictionary = ctx["harm"]
	harm["point"] = int(harm["point"]) - 1
	return SUCCESS


# ============================================================
# 主动攻击未命中后：贯穿射击（可选）
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, GUAN_CHUAN_SHE_JI, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	if cards.is_empty():
		return SUCCESS
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_magic() or not player.has_hand_card(cid):
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	notice_skill(GUAN_CHUAN_SHE_JI, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": GUAN_CHUAN_SHE_JI, "type": GConst.HarmType.Magic,
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
	if aid == SHAN_GUANG_XIAN_JING:
		if cards.is_empty():
			return GConst.GE_INVALID_CARDID
		var cid: int = int(cards[0])
		var card: GCard = Data.get_card(cid)
		if not player.has_hand_card(cid) or card == null or not card.has_skill_id(SHAN_GUANG_XIAN_JING):
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == JU_JI:
		if player.crystal == 0 and player.gem == 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHAN_GUANG_XIAN_JING:
			return _shan_guang_xian_jing(action)
		JU_JI:
			return _ju_ji(action)
	return GConst.GE_INVALID_ACTION


func _shan_guang_xian_jing(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else int(action.get("src_id", player.id))
	notice_skill(SHAN_GUANG_XIAN_JING, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": SHAN_GUANG_XIAN_JING, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


func _ju_ji(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(JU_JI, [dst_id])
	# 扣除能量：优先扣水晶
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	# 额外一次攻击行动
	player.add_action(GConst.ActionType.Attack, JU_JI)
	# 目标手牌补到 5 张
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null:
		var need: int = 5 - dst.hand_cards.size()
		if need > 0:
			engine.draw(dst_id, need)
	engine._broadcast_game()
	return SUCCESS

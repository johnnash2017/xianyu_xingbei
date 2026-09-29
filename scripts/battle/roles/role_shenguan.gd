extends BattleRole
## 神官（roleID 15）—— 移植自服务端 role/ShenGuan.cpp
## 被动：圣使守护（治疗上限 +4；每次用治疗抵御伤害最多只能用 1 点，见 p_timeline_4）
## 启动：神圣契约（回合开始，1 能量 + 转移 X 治疗给队友，无视其治疗上限但最高为 4）
## 法术：神圣祈福（弃 2 张法术牌，自己 +2 治疗）、
##       水之神力（弃 1 张水系牌，给目标队友 1 张手牌，双方各 +1 治疗）、
##       神圣领域（1 能量，弃 min(2, 手牌) 张牌：移除 1 治疗对目标造成 2 点法术伤害，或自己 +2 / 队友 +1 治疗）
## 响应：神圣启示（特殊行动结束时，自己 +1 治疗）

const SHEN_SHENG_QI_SHI: int = 1501   # 神圣启示（被动响应）
const SHEN_SHENG_QI_FU: int = 1502    # 神圣祈福
const SHUI_ZHI_SHEN_LI: int = 1503    # 水之神力
const SHENG_SHI_SHOU_HU: int = 1504   # 圣使守护（被动）
const SHEN_SHENG_QI_YUE: int = 1505   # 神圣契约
const SHEN_SHENG_LING_YU: int = 1506  # 神圣领域

const CROSS_MAX_BONUS: int = 4
const LING_YU_DISCARD: int = 2        # 神圣领域最多弃 2 张牌

## 水之神力的交牌子步骤（0 = 尚未弃牌 / 1 = 等待交出 1 张手牌）
var _shui_shen_phase: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 圣使守护：治疗上限 +4
	p.cross_max = p.cross_max + CROSS_MAX_BONUS


func available_skills() -> Array:
	var out: Array = []
	if _count_magic_cards() >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHEN_SHENG_QI_FU, "need_card": 2, "need_target": 0,
			"cards": magic_hand_ids()})
	if _has_water_card():
		# 水之神力要弃 1 张水系牌：只让手牌里的水系牌可点（v_magic_skill 校验 card2.element_enum() == Water）
		# 目标须为同色队友（v_magic_skill：dst1.color != player.color 时返回 GE_INVALID_ACTION）
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHUI_ZHI_SHEN_LI, "need_card": 1, "need_target": 1,
			"cards": hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Water),
			"targets": ally_ids()})
	if player.get_energy() >= 1:
		# 神圣领域要弃牌：手牌多于 2 张时恰好弃 2 张，否则把手牌弃光（v_magic_skill 同一条）
		# 两种用法的合法目标不同，所以目标白名单挂在各自选项上：
		#   mode=0（args[0]==0）目标须同色队友；mode=1（args[0]==1）不限颜色，且自身治疗须 ≥ 1
		var 领域选项: Array = [{"text": "自己 +2 治疗，目标队友 +1 治疗", "args": [0], "need_target": 1,
			"targets": ally_ids()}]
		if player.cross_num >= 1:
			领域选项.append({"text": "移除自己 1 治疗，对目标造成 2 点法术伤害", "args": [1], "need_target": 1,
				"targets": player_ids_where(func(_p: BattlePlayer) -> bool: return true)})
		out.append({
			"type": GConst.ActionType.MagicSkill, "id": SHEN_SHENG_LING_YU,
			"need_card": mini(LING_YU_DISCARD, player.hand_cards.size()), "need_target": 1,
			"arg_choices": 领域选项,
		})
	return out


## 手牌中法术牌数量
func _count_magic_cards() -> int:
	var n: int = 0
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			n += 1
	return n


## 手牌中是否有水系牌
func _has_water_card() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == GConst.CardElement.Water:
			return true
	return false


func _has_cards(cards: Array) -> bool:
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return false
	return not cards.is_empty()


# ============================================================
# 圣使守护（被动）：用治疗抵御伤害时最多只能用 1 点治疗
# 服务端 ShenGuan::ShengShiShouHu 于 p_timeline_4 把 crossAvailable 压到 1（仅当原本可抵御）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if int(harm.get("cross_available", 1)) <= 0 or player.cross_num <= 0:
		return SUCCESS
	harm["cross_max_point"] = 1
	notice_skill(SHENG_SHI_SHOU_HU, [player.id])
	return SUCCESS


# ============================================================
# 启动：神圣契约（自己回合开始、有能量且有治疗时询问）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if player.get_energy() == 0 or player.cross_num == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SHEN_SHENG_QI_YUE
	if step == SHEN_SHENG_QI_YUE:
		var r: int = _shen_sheng_qi_yue()
		if r == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


func _shen_sheng_qi_yue() -> int:
	# 1 能量且空手牌 / 唯一手牌为光系：无需发动
	if player.hand_cards.size() == 0 and player.get_energy() == 1:
		return SUCCESS
	if player.get_energy() == 1 and player.hand_cards.size() == 1:
		var only: GCard = Data.get_card(player.hand_cards[0])
		if only != null and only.element_enum() == GConst.CardElement.Light:
			return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, SHEN_SHENG_QI_YUE, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	var amount: int = int(args[0]) if not args.is_empty() else 0
	if amount <= 0 or dsts.is_empty():
		return SUCCESS
	amount = mini(amount, player.cross_num)
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	notice_skill(SHEN_SHENG_QI_YUE, [dst_id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	player.sub_cross_num(amount)
	# 以此法转移的治疗无视目标治疗上限，但其治疗最高为 4
	dst.cross_num = mini(dst.cross_num + amount, 4)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 响应：神圣启示（特殊行动结束时 +1 治疗）
# ============================================================
func p_after_special(ctx: Dictionary) -> int:
	var src_id: int = int(ctx.get("player", ctx.get("src", -1)))
	if src_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, SHEN_SHENG_QI_SHI, 0, 0)
		return WAIT
	step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	notice_skill(SHEN_SHENG_QI_SHI, [player.id])
	player.add_cross_num(1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能校验
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	match aid:
		SHEN_SHENG_QI_FU:
			if cards.size() != 2:
				return GConst.GE_INVALID_ACTION
			for c: Variant in cards:
				var card: GCard = Data.get_card(int(c))
				if card == null or not card.is_magic() or not player.has_hand_card(int(c)):
					return GConst.GE_INVALID_ACTION
		SHUI_ZHI_SHEN_LI:
			if cards.is_empty() or dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			var cid: int = int(cards[0])
			var card2: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card2 == null or card2.element_enum() != GConst.CardElement.Water:
				return GConst.GE_INVALID_ACTION
			var dst1: BattlePlayer = engine.p(int(dsts[0]))
			if dst1 == null or dst1.color != player.color:
				return GConst.GE_INVALID_ACTION
		SHEN_SHENG_LING_YU:
			if dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			if player.hand_cards.size() > LING_YU_DISCARD:
				if cards.size() != LING_YU_DISCARD:
					return GConst.GE_INVALID_ACTION
			elif cards.size() != player.hand_cards.size():
				return GConst.GE_INVALID_ACTION
			if not _has_cards(cards) and not cards.is_empty():
				return GConst.GE_INVALID_ACTION
			var args: Array = action.get("args", [])
			var mode: int = int(args[0]) if not args.is_empty() else 0
			if player.get_energy() < 1:
				return GConst.GE_INVALID_ACTION
			if mode == 1:
				if player.cross_num < 1:
					return GConst.GE_INVALID_ACTION
			else:
				var dst2: BattlePlayer = engine.p(int(dsts[0]))
				if dst2 == null or dst2.color != player.color:
					return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHEN_SHENG_QI_FU:
			return _shen_sheng_qi_fu(action)
		SHUI_ZHI_SHEN_LI:
			return _shui_zhi_shen_li(action)
		SHEN_SHENG_LING_YU:
			return _shen_sheng_ling_yu(action)
	return GConst.GE_INVALID_ACTION


## 神圣祈福：弃 2 张法术牌，自己 +2 治疗
func _shen_sheng_qi_fu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	notice_skill(SHEN_SHENG_QI_FU, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	player.add_cross_num(2)
	engine._broadcast_game()
	return SUCCESS


## 水之神力：弃 1 张水系牌；若仍有手牌则交给目标队友 1 张，之后双方各 +1 治疗
func _shui_zhi_shen_li(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var dst: BattlePlayer = engine.p(dst_id)
	if _shui_shen_phase == 0:
		var cid: int = int(cards[0])
		notice_skill(SHUI_ZHI_SHEN_LI, [dst_id])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [cid])
		engine.to_discard([cid])
		if player.hand_cards.is_empty():
			player.add_cross_num(1)
			dst.add_cross_num(1)
			engine._broadcast_game()
			return SUCCESS
		# 仍有手牌：请玩家选择交给队友的牌
		_shui_shen_phase = 1
		engine.ask_skill(player.id, SHUI_ZHI_SHEN_LI, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_shui_shen_phase = 0
	var picked: Array = r.get("card_ids", [])
	var give: int = -1
	if not picked.is_empty() and player.has_hand_card(int(picked[0])):
		give = int(picked[0])
	else:
		give = player.hand_cards[0]
	player.remove_hand_cards([give])
	dst.add_hand_cards([give])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [give], "is_real": true,
	})
	player.add_cross_num(1)
	dst.add_cross_num(1)
	engine._broadcast_game()
	return SUCCESS


## 神圣领域：1 能量 + 弃 min(2, 手牌) 张牌；移除 1 治疗造成 2 点法术伤害，或自己 +2 / 队友 +1 治疗
func _shen_sheng_ling_yu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var dst: BattlePlayer = engine.p(dst_id)
	var args: Array = action.get("args", [])
	var mode: int = int(args[0]) if not args.is_empty() else 0
	notice_skill(SHEN_SHENG_LING_YU, [dst_id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	var limit: int = mini(LING_YU_DISCARD, player.hand_cards.size())
	var use_cards: Array = []
	for i: int in range(mini(limit, cards.size())):
		use_cards.append(int(cards[i]))
	if not use_cards.is_empty():
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": use_cards, "is_real": true,
		})
		engine.take_from_hand(player.id, use_cards)
		engine.to_discard(use_cards)
	if mode == 1:
		player.sub_cross_num(1)
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": 2,
			"cause": SHEN_SHENG_LING_YU, "type": GConst.HarmType.Magic,
		})
		engine._broadcast_game()
		return URGENT
	player.add_cross_num(2)
	dst.add_cross_num(1)
	engine._broadcast_game()
	return SUCCESS

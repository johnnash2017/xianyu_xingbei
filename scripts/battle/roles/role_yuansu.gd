extends BattleRole
## 元素师（roleID 11）—— 移植自服务端 role/YuanSu.cpp
## 技能：元素吸收（被动，自己造成法术伤害时 +1 元素）、
## 陨石/风刃/火球/雷击/冰冻（独有法术，发动牌须是对应系的牌：地/风/火/雷/水；额外弃 1 张同系牌可加伤）、
##       元素点燃（法术，移除 3 点【元素】造成 2 点法术伤害并额外 +1 法术行动）、
##       月光（法术，1 宝石对目标造成 能量+1 点法术伤害）
## 【元素】为元素师专属指示物，放置于 tokens[0]，上限见角色表。

const FENG_REN: int = 1101          # 风刃
const BING_DONG: int = 1102         # 冰冻
const HUO_QIU: int = 1103           # 火球
const YUN_SHI: int = 1104           # 陨石
const LEI_JI: int = 1105            # 雷击
const YUAN_SU_DIAN_RAN: int = 1106  # 元素点燃
const YUE_GUANG: int = 1107         # 月光
const YUAN_SU_XI_SHOU: int = 1108   # 元素吸收（被动）

const TOKEN_ELEMENT: int = 0        # 「元素」指示物下标

## 各独有法术的发动牌系别（技能原文「若你额外弃 1 张 X 系牌」——第一张也必须是这个系的牌）
const 法术系别: Dictionary = {
	FENG_REN: GConst.CardElement.Wind,
	BING_DONG: GConst.CardElement.Water,
	HUO_QIU: GConst.CardElement.Fire,
	YUN_SHI: GConst.CardElement.Earth,
	LEI_JI: GConst.CardElement.Thunder,
}

## 冰冻/雷击的后续结算目标（服务端在 p_magic_skill 二次进入时处理）
var _bing_dong_heal_dst: int = -1
var _lei_ji_pending: bool = false


func available_skills() -> Array:
	var out: Array = []
	# 陨石/风刃/火球/雷击/冰冻：第 1 张必须是带该技能的牌（发动牌），
	# 第 2 张可再弃 1 张对应系的牌加伤 —— 两段条件分别用 card_slot_skill / card_slot_element 下发，
	# cards 白名单是两者并集（界面只亮这些牌，逐张顺序再由槽位条件卡）。
	# 手里没有对应的发动牌时照样摆出按钮，只把 enabled 置 false（界面半透明、点不动）
	for sid: int in [YUN_SHI, FENG_REN, HUO_QIU, LEI_JI, BING_DONG]:
		var 技能牌: Array[int] = hand_ids_with_skill(sid)
		var 元素: int = int(法术系别[sid])
		var 合法牌: Array[int] = 技能牌.duplicate()
		for cid: int in hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == 元素):
			if not 合法牌.has(cid):
				合法牌.append(cid)
		# 冰冻必须指定 2 名角色（v_magic_skill：dsts.size() < 2 拒绝），其余法术只需 1 名
		var 目标下限: int = 2 if sid == BING_DONG else 1
		out.append({"type": GConst.ActionType.MagicSkill, "id": sid, "need_card": 1, "need_target": 目标下限,
			"card_max": 2, "cards": 合法牌, "card_slot_skill": sid, "card_slot_element": 元素,
			"enabled": not 技能牌.is_empty()})
	out.append({"type": GConst.ActionType.MagicSkill, "id": YUAN_SU_DIAN_RAN, "need_card": 0, "need_target": 1,
		"enabled": _element_token() >= _element_max()})
	out.append({"type": GConst.ActionType.MagicSkill, "id": YUE_GUANG, "need_card": 0, "need_target": 1,
		"enabled": player.gem > 0})
	return out


# ============================================================
# 指示物
# ============================================================
func _element_token() -> int:
	var t: Dictionary = player.tokens[TOKEN_ELEMENT]
	return int(t["num"])


func _element_max() -> int:
	return int(player.tokens[TOKEN_ELEMENT]["max"])


func _add_element_token(n: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_ELEMENT]
	t["num"] = mini(int(t["num"]) + n, int(t["max"]))


func _clear_element_token() -> void:
	var t: Dictionary = player.tokens[TOKEN_ELEMENT]
	t["num"] = 0


# ============================================================
# 元素吸收（被动）：自己造成法术伤害时 +1【元素】（元素点燃除外）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if int(harm.get("cause", -1)) == YUAN_SU_DIAN_RAN:
		return SUCCESS
	notice_skill(YUAN_SU_XI_SHOU, [player.id])
	_add_element_token(1)
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
		FENG_REN, BING_DONG, HUO_QIU, YUN_SHI, LEI_JI:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			# 第 1 张（发动牌）必须是带该技能的牌
			if not player.has_hand_card(cid) or card == null or not card.has_skill_id(aid):
				return GConst.GE_INVALID_ACTION
			if cards.size() > 1:
				var cid2: int = int(cards[1])
				var card2: GCard = Data.get_card(cid2)
				# 第 2 张必须是该法术对应系的牌（技能原文「额外弃 1 张 X 系牌【展示】」）
				if not player.has_hand_card(cid2) or card2 == null or card2.element_enum() != int(法术系别[aid]):
					return GConst.GE_INVALID_ACTION
			if aid == BING_DONG and dsts.size() < 2:
				return GConst.GE_INVALID_ACTION
		YUAN_SU_DIAN_RAN:
			if dsts.is_empty():
				return GConst.GE_INVALID_ACTION
			if _element_token() < _element_max():
				return GConst.GE_INVALID_ACTION
		YUE_GUANG:
			if dsts.is_empty() or player.gem == 0:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		FENG_REN:
			# 风刃：额外 +1 攻击行动
			player.add_action(GConst.ActionType.Attack, FENG_REN, true)
			return _yuan_su_damage(action)
		YUN_SHI:
			# 陨石：额外 +1 法术行动
			player.add_action(GConst.ActionType.Magic, YUN_SHI, true)
			return _yuan_su_damage(action)
		HUO_QIU:
			return _yuan_su_damage(action)
		BING_DONG:
			var dsts: Array = action.get("dst_ids", [])
			_bing_dong_heal_dst = int(dsts[1]) if dsts.size() > 1 else player.id
			return _yuan_su_damage(action)
		LEI_JI:
			_lei_ji_pending = true
			return _yuan_su_damage(action)
		YUAN_SU_DIAN_RAN:
			return _yuan_su_dian_ran(action)
		YUE_GUANG:
			return _yue_guang(action)
	return GConst.GE_INVALID_ACTION


## 陨石/风刃/火球/雷击/冰冻 通用：展示并弃牌，按牌数（火球 +1）造成法术伤害
func _yuan_su_damage(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var use_cards: Array = [int(cards[0])]
	if cards.size() > 1:
		use_cards.append(int(cards[1]))
	var point: int = use_cards.size()
	if aid == HUO_QIU:
		point += 1
	notice_skill(aid, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": use_cards, "is_real": true,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": point,
		"cause": aid, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, use_cards, true)
	engine.to_discard(use_cards)
	engine._broadcast_game()
	return URGENT


## 冰冻的后续：指定角色 +1 治疗（服务端在第二次进入 p_magic_skill 时结算）
func _bing_dong_cross() -> void:
	var dst: BattlePlayer = engine.p(_bing_dong_heal_dst)
	_bing_dong_heal_dst = -1
	施加治疗(dst.id, 1)
	engine._broadcast_game()


## 雷击的后续：我方战绩区 +1 宝石（服务端在第二次进入 p_magic_skill 时结算）
func _lei_ji_gem() -> void:
	_lei_ji_pending = false
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	engine._broadcast_game()


## 元素点燃：移除 3 点元素，对目标造成 2 点法术伤害，额外 +1 法术行动
func _yuan_su_dian_ran(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	player.add_action(GConst.ActionType.Magic, YUAN_SU_DIAN_RAN, true)
	notice_skill(YUAN_SU_DIAN_RAN, [dst_id])
	_clear_element_token()
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": YUAN_SU_DIAN_RAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 月光：1 宝石，对目标造成（剩余能量+1）点法术伤害
func _yue_guang(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(YUE_GUANG, [dst_id])
	player.set_gem(player.gem - 1)
	var point: int = player.gem + player.crystal + 1
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": point,
		"cause": YUE_GUANG, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 法术行动结束后：结算冰冻 / 雷击 的追加效果
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var aid: int = int(ctx.get("action_id", 0))
	if aid == BING_DONG and _bing_dong_heal_dst >= 0:
		_bing_dong_cross()
	elif aid == LEI_JI and _lei_ji_pending:
		_lei_ji_gem()
	return SUCCESS

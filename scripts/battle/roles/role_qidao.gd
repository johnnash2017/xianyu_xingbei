extends BattleRole
## 祈祷师（roleID 16）—— 移植自服务端 role/QiDao.cpp
## 技能：祈祷（启动 1603：横置并消耗 1 宝石进入祈祷形态）、
##       光辉信仰（法术 1604：祈祷形态下移除 1 符文，弃 min(2, 手牌) 张牌，我方 +1 宝石，目标队友 +1 治疗）、
##       漆黑信仰（法术 1605：祈祷形态下移除 1 符文，对目标与自己各造成 2 点法术伤害）、
##       威力赐福（法术 1601：放置于队友面前，其攻击命中时可移除此牌使本次伤害 +2）、
##       迅捷赐福（法术 1602：放置于队友面前，其行动结束时可移除此牌获得 +1 攻击行动）、
##       法力潮汐（法术行动结束后 1606：消耗 1 能量获得 +1 法术行动，回合限定）
## 【符文】放置于 tokens[0]，上限 3；【祈祷形态】用 tap 表示。

const XUN_JIE_CI_FU: int = 1601      # 迅捷赐福（法术技能）
const WEI_LI_CI_FU: int = 1602       # 威力赐福（法术技能）
const QI_DAO: int = 1603             # 祈祷（启动）
const GUANG_HUI_XIN_YANG: int = 1604 # 光辉信仰（法术技能）
const QI_HEI_XIN_YANG: int = 1605    # 漆黑信仰（法术技能）
const FA_LI_CHAO_XI: int = 1606      # 法力潮汐（额外行动）

const TOKEN_QI_DAO_FU_WEN: int = 0   # 「符文」指示物下标
const TOKEN_QI_DAO_FU_WEN_MAX: int = 3

## 法力潮汐的回合限定标记
var used_FaLiChaoXi: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_QI_DAO_FU_WEN] = {"name": "符文", "max": TOKEN_QI_DAO_FU_WEN_MAX, "num": 0}


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_FaLiChaoXi = false
	return SUCCESS


func available_skills() -> Array:
	var out: Array = []
	# 祈祷（启动）：手牌非空、有宝石且未处于祈祷形态时可发动（耗 1 宝石横置进入祈祷形态）
	if not player.hand_cards.is_empty() and player.gem > 0 and not player.tap:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": QI_DAO, "need_card": 0, "need_target": 0})
	# 光辉信仰 / 黑暗诅咒：仅祈祷形态（横置）且符文 > 0
	if player.tap and _fu_wen() > 0:
		# 光辉信仰：发动时须弃 min(2, 手牌) 张牌（手牌不足 2 张就按实际张数弃，0 张也能发动）；
		# 目标限同色队友（原客户端 enableMate，不含自己）
		out.append({"type": GConst.ActionType.MagicSkill, "id": GUANG_HUI_XIN_YANG,
			"need_card": mini(2, player.hand_cards.size()), "need_target": 1, "targets": ally_ids()})
		# 黑暗诅咒：对目标角色与自己各造成 2 点法术伤害（目标任意）
		out.append({"type": GConst.ActionType.MagicSkill, "id": QI_HEI_XIN_YANG, "need_card": 0, "need_target": 1})
	# 迅捷赐福/威力赐福：只有手中带对应技能的牌可作发动牌，下发给界面把其余手牌置灰
	# （v_magic_skill 校验同一张牌：须在手、带该技能；目标限同色队友且面前无同类赐福，见 _check_ci_fu_target）
	var 迅捷牌: Array[int] = hand_ids_with_skill(XUN_JIE_CI_FU)
	if not 迅捷牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": XUN_JIE_CI_FU, "need_card": 1, "need_target": 1,
			"cards": 迅捷牌,
			"targets": player_ids_where(func(p: BattlePlayer) -> bool:
				return p.color == player.color and _find_effect_card(p, XUN_JIE_CI_FU) < 0)})
	var 威力牌: Array[int] = hand_ids_with_skill(WEI_LI_CI_FU)
	if not 威力牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": WEI_LI_CI_FU, "need_card": 1, "need_target": 1,
			"cards": 威力牌,
			"targets": player_ids_where(func(p: BattlePlayer) -> bool:
				return p.color == player.color and _find_effect_card(p, WEI_LI_CI_FU) < 0)})
	return out


# ============================================================
# 指示物：符文
# ============================================================
func _fu_wen() -> int:
	var t: Dictionary = player.tokens[TOKEN_QI_DAO_FU_WEN]
	return int(t["num"])


func _set_fu_wen(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_QI_DAO_FU_WEN]
	t["num"] = clampi(v, 0, int(t["max"]))


# ============================================================
# 启动技能（行动阶段按钮）：祈祷（1603）
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验技能自身条件）
# ============================================================
## 祈祷为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == QI_DAO


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QI_DAO:
		return GConst.GE_INVALID_ACTION
	# 手牌为空 / 无宝石 / 已处于祈祷形态：不能发动
	if player.hand_cards.is_empty() or player.gem <= 0 or player.tap:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 祈祷：耗 1 宝石并横置进入祈祷形态
func p_special_skill(_action: Dictionary) -> int:
	notice_skill(QI_DAO, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	# 转为祈祷形态（横置）
	engine.set_tap(player.id, true)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击宣告后：祈祷形态下 +2 符文
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if not player.tap:
		return SUCCESS
	_set_fu_wen(_fu_wen() + 2)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击命中后：威力赐福（放在攻击者面前的基础效果）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	var attacker_id: int = int(harm.get("src", ctx.get("src", -1)))
	var attacker: BattlePlayer = engine.p(attacker_id)
	if attacker == null:
		return SUCCESS
	var effect_card: int = _find_effect_card(attacker, WEI_LI_CI_FU)
	if effect_card < 0:
		return SUCCESS
	if not engine.has_reply():
		询问(attacker_id, WEI_LI_CI_FU, 0, 0)
		return WAIT
	if not take_skill_reply():
		step = STEP_DONE
		return SUCCESS
	step = STEP_DONE
	engine.broadcast(GConst.Msg.Skill, {"skill_id": WEI_LI_CI_FU, "src_id": attacker_id, "dst_ids": [attacker_id]})
	harm["point"] = int(harm.get("point", 0)) + 2
	# 移除该赐福牌并弃置
	engine.remove_basic_effect(attacker_id, effect_card, WEI_LI_CI_FU, player.id)
	engine.to_discard([effect_card])
	engine._broadcast_game()
	return URGENT


# ============================================================
# 攻击行动结束后：迅捷赐福
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	_xun_jie_effect(int(ctx.get("player", -1)))
	return SUCCESS


# ============================================================
# 法术行动结束后：迅捷赐福 → 法力潮汐
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	# 法术牌行动传 src，法术技能传 player
	var actor_id: int = int(ctx.get("player", ctx.get("src", -1)))
	if step == 0:
		step = XUN_JIE_CI_FU
	if step == XUN_JIE_CI_FU:
		_xun_jie_effect(actor_id)
		step = FA_LI_CHAO_XI
	if step == FA_LI_CHAO_XI:
		if actor_id != player.id:
			step = STEP_DONE
			return SUCCESS
		_fa_li_chao_xi()
		step = STEP_DONE
	return SUCCESS


## 迅捷赐福：队友行动结束时授予 +1 攻击行动（服务端 XunJieCiFuEffect 仅 addAction，
## 移除该赐福牌改在玩家选择该额外行动时结算）
func _xun_jie_effect(pid: int) -> void:
	var target: BattlePlayer = engine.p(pid)
	if target == null or target.hand_cards.is_empty():
		return
	for a: Dictionary in target.additional_actions:
		if int(a.get("cause", 0)) == XUN_JIE_CI_FU:
			return
	if _find_effect_card(target, XUN_JIE_CI_FU) < 0:
		return
	target.add_action(GConst.ActionType.Attack, XUN_JIE_CI_FU)


## 法力潮汐：法术行动结束后授予 +1 法术行动（回合限定；能量消耗改在玩家选择时结算）
func _fa_li_chao_xi() -> void:
	if _fu_wen() == 0 and player.hand_cards.is_empty():
		return
	if used_FaLiChaoXi or player.get_energy() <= 0:
		return
	player.add_action(GConst.ActionType.Magic, FA_LI_CHAO_XI)


# ============================================================
# 玩家选择额外行动时的二次校验（服务端 QiDao::v_additional_action）：
# 迅捷赐福需该玩家面前仍有【迅捷赐福】；法力潮汐需非本回合已用且仍有能量
# ============================================================
func v_additional_action(cause: int) -> int:
	if cause == XUN_JIE_CI_FU:
		if _find_effect_card(player, XUN_JIE_CI_FU) < 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if cause == FA_LI_CHAO_XI:
		if used_FaLiChaoXi or player.get_energy() <= 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return V_NOT_OVERRIDE


# ============================================================
# 玩家选择额外行动时：迅捷赐福移除赐福牌 → 法力潮汐消耗 1 能量
# （引擎已在选中时广播该额外行动的技能宣告，此处不再重复）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	var cause: int = int(ctx.get("cause", 0))
	var pid: int = int(ctx.get("player", -1))
	if cause == XUN_JIE_CI_FU:
		# 迅捷赐福：由持有该赐福牌的玩家选择该额外行动时移除并弃置
		var target: BattlePlayer = engine.p(pid)
		if target != null:
			var effect_card: int = _find_effect_card(target, XUN_JIE_CI_FU)
			if effect_card >= 0:
				engine.remove_basic_effect(pid, effect_card, XUN_JIE_CI_FU, player.id)
				engine.to_discard([effect_card])
				engine._broadcast_game()
		return SUCCESS
	if pid != player.id or cause != FA_LI_CHAO_XI:
		return SUCCESS
	used_FaLiChaoXi = true
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	if aid == GUANG_HUI_XIN_YANG:
		if not (player.tap and _fu_wen() > 0):
			return GConst.GE_INVALID_ACTION
		return _check_guang_hui_xin_yang(action)
	if aid == QI_HEI_XIN_YANG:
		if player.tap and _fu_wen() > 0:
			return GConst.GE_SUCCESS
		return GConst.GE_INVALID_ACTION
	if aid == XUN_JIE_CI_FU or aid == WEI_LI_CI_FU:
		if not _check_ci_fu_target(action, aid):
			return GConst.GE_INVALID_ACTION
		if cards.is_empty():
			return GConst.GE_INVALID_CARDID
		var cid: int = int(cards[0])
		var card: GCard = Data.get_card(cid)
		if not player.has_hand_card(cid) or card == null or not card.has_skill_id(aid):
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		GUANG_HUI_XIN_YANG:
			return _guang_hui_xin_yang(action)
		QI_HEI_XIN_YANG:
			return _qi_hei_xin_yang(action)
		XUN_JIE_CI_FU:
			return _place_ci_fu(action, XUN_JIE_CI_FU)
		WEI_LI_CI_FU:
			return _place_ci_fu(action, WEI_LI_CI_FU)
	return GConst.GE_INVALID_ACTION


## 光辉信仰：移除 1 符文，弃 min(2, 手牌) 张牌（不展示），我方 +1 宝石，目标队友 +1 治疗
func _guang_hui_xin_yang(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var cards: Array = action.get("card_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(GUANG_HUI_XIN_YANG, [dst_id])
	_set_fu_wen(_fu_wen() - 1)
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null:
		施加治疗(dst.id, 1)
	if not cards.is_empty():
		engine.take_from_hand(player.id, cards)
		engine.to_discard(cards)
		engine._log_discard(player.id, cards)
		engine._broadcast_game()
		return URGENT
	engine._broadcast_game()
	return SUCCESS


## 漆黑信仰：移除 1 符文，对目标与自己各造成 2 点法术伤害
func _qi_hei_xin_yang(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(QI_HEI_XIN_YANG, [dst_id])
	_set_fu_wen(_fu_wen() - 1)
	# 先结算目标、再结算自己，故自己先入栈
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": QI_HEI_XIN_YANG, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": QI_HEI_XIN_YANG, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 威力赐福 / 迅捷赐福：将牌放置于目标队友面前作为基础效果（cause 即该技能的技能号）
func _place_ci_fu(action: Dictionary, cause: int) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not card.has_skill_id(cause) or not player.has_hand_card(cid):
		return GConst.GE_INVALID_ACTION
	notice_skill(cause, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.add_basic_effect(dst_id, cid, player.id, cause)
	engine.take_from_hand(player.id, [cid], true)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 工具
# ============================================================
## 光辉信仰的发动校验：目标须为同色队友（不含自己），并须弃 min(2, 手牌) 张牌且都在手里
func _check_guang_hui_xin_yang(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null or dst.color != player.color or dst.id == player.id:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	# 原客户端 quota = min(2, 手牌)：手牌不足 2 张时按实际张数弃，0 张也合法
	if cards.size() != mini(2, player.hand_cards.size()):
		return GConst.GE_INVALID_CARDID
	for cid: Variant in cards:
		if not player.has_hand_card(int(cid)):
			return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


## 判断赐福目标是否合法（返回 true 表示可放置）：须为同色队友（不含自己）且面前无同类赐福
func _check_ci_fu_target(action: Dictionary, 技能号: int) -> bool:
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return false
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null:
		return false
	# 原客户端 enableMate()（不含自己）只放同色队友，服务端 v_MAGIC_SKILL 亦拒异色目标
	if dst.color != player.color or dst.id == player.id:
		return false
	for be: Dictionary in dst.basic_effects:
		var c: GCard = Data.get_card(int(be["card"]))
		if c != null and c.has_skill_id(技能号):
			return false
	return true


func _find_effect_card(target: BattlePlayer, 技能号: int) -> int:
	for be: Dictionary in target.basic_effects:
		var c: GCard = Data.get_card(int(be["card"]))
		if c != null and c.has_skill_id(技能号):
			return int(be["card"])
	return -1

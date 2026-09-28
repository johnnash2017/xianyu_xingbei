extends BattleRole
## 天使（roleID 7）—— 移植自服务端 role/TianShi.cpp
## 技能：
##   天使之墙（701，法术，将带此特技的牌作为基础效果放置于目标面前，视作圣盾）
##   天使祝福（702，法术，弃 1 张水系牌：指定 1 名角色→该角色交给你 2 张手牌；
##                 指定 2 名→各交 1 张。本引擎客户端仅支持单目标 2 张的形态）
##   风之洁净（703，法术，弃 1 张风系牌，移除场上任意一个基础效果）
##   天使羁绊（704，自身移除基础效果（703/705）或以【圣盾】/【天使之墙】放置基础效果时，
##                 为指定角色 +1 治疗；由 p_basic_effect_change 实现）
##   天使之歌（705，你的回合开始前，消耗 1 能量移除场上任意一个基础效果）
##   神之庇护（706，由 p_lose_morale 实现：我方角色因法术伤害将掉士气时，可消耗能量抵消等量损失。
##                 简化：客户端只支持「抵消几点」的选择，支付优先水晶再宝石）
##
## 覆写校验：v_shield——【天使之墙】视作圣盾（服务端 PlayerEntity::v_shield）

const TIAN_SHI_ZHI_QIANG: int = 701
const TIAN_SHI_ZHU_FU: int = 702
const FENG_ZHI_JIE_JING: int = 703
const TIAN_SHI_JI_BAN: int = 704
const TIAN_SHI_ZHI_GE: int = 705
const SHEN_ZHI_BI_HU: int = 706

const TAG_TIAN_SHI_ZHI_QIANG: String = "天使之墙"


func available_skills() -> Array:
	var out: Array = []
	if _hand_has_element(GConst.CardElement.Wind):
		out.append({"type": GConst.ActionType.MagicSkill, "id": FENG_ZHI_JIE_JING, "need_card": 1, "need_target": 1})
	if _hand_has_tag(TAG_TIAN_SHI_ZHI_QIANG):
		out.append({"type": GConst.ActionType.MagicSkill, "id": TIAN_SHI_ZHI_QIANG, "need_card": 1, "need_target": 1})
	if _hand_has_element(GConst.CardElement.Water):
		out.append({"type": GConst.ActionType.MagicSkill, "id": TIAN_SHI_ZHU_FU, "need_card": 1, "need_target": 1})
	return out


# ============================================================
# 圣盾校验覆写：【天使之墙】视作圣盾
# 对应服务端 PlayerEntity::v_shield：
#   目标已有【圣盾】或【天使之墙】基础效果时，不可再放置【圣盾】
# 说明：本钩子由「施放圣盾者的角色」实现，故仅在天师本人施放【圣盾】时追加该判定；
#   引擎的自动格挡（放弃应战时消耗圣盾）亦识别【天使之墙】特技，视作【圣盾】挡下
# ============================================================
func v_shield(dst_id: int, players: Dictionary) -> int:
	var base: int = player.base_v_shield(dst_id, players)
	if base != GConst.GE_SUCCESS:
		return base
	var dst: BattlePlayer = players.get(dst_id)
	if _has_basic_tag(dst, TAG_TIAN_SHI_ZHI_QIANG):
		return GConst.GE_BASIC_EFFECT_ALREADY_EXISTS
	return GConst.GE_SUCCESS


# ============================================================
# 回合开始前：天使之歌（移除场上任意一个基础效果）
# ============================================================
## 询问回复约定：args[0] = 使用的能量（1=宝石 0=水晶）、args[1] = 要移除的基础效果牌，
## dst_ids[0] = 该基础效果的拥有者；args 少于 2 项视为放弃（与服务端一致）。
func p_before_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if player.get_energy() <= 0:
		return SUCCESS
	if not _any_player_has_basic_effect():
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, TIAN_SHI_ZHI_GE, 1, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.size() < 2 or dsts.is_empty():
		return SUCCESS
	var use_gem: int = int(args[0])
	var effect_cid: int = int(args[1])
	var dst_id: int = int(dsts[0])
	if use_gem > 0 and player.gem == 0:
		return SUCCESS
	if use_gem == 0 and player.crystal == 0:
		return SUCCESS
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or not _has_basic_card(dst, effect_cid):
		return SUCCESS
	notice_skill(TIAN_SHI_ZHI_GE, [dst_id])
	if use_gem > 0:
		player.set_gem(player.gem - 1)
	else:
		player.set_crystal(player.crystal - 1)
	engine.remove_basic_effect(dst_id, effect_cid, TIAN_SHI_ZHI_GE)
	engine.to_discard([effect_cid])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 天使羁绊（704）：基础效果发生增/删时，由 天使 指定一名角色 +1 治疗
# 对应服务端 TianShi::p_basic_effect_change——仅当发动者为 天使 本人，且为
#   风之洁净（703）/ 天使之歌（705）移除，或以【圣盾】/【天使之墙】放置基础效果（CAUSE_USE）时触发。
# 说明：引擎 remove_basic_effect 的 ctx 不含发动者（doer 恒为 -1），但 cause 703/705 为 天使 专属，
#   故这两支改按 cause 判定；【圣盾】的通用放置路径未走 engine.add_basic_effect，暂不会触发本钩子。
# ============================================================
func p_basic_effect_change(ctx: Dictionary) -> int:
	var cause: int = int(ctx.get("cause", -1))
	if cause == FENG_ZHI_JIE_JING or cause == TIAN_SHI_ZHI_GE:
		return _tian_shi_ji_ban()
	if cause != GConst.CAUSE_USE or not bool(ctx.get("add", false)):
		return SUCCESS
	if int(ctx.get("doer", -1)) != player.id:
		return SUCCESS
	var card: GCard = Data.get_card(int(ctx.get("card", -1)))
	if card == null:
		return SUCCESS
	if not card.has_speciality_name(TAG_TIAN_SHI_ZHI_QIANG) and card.card_name_enum() != GConst.CardName.Shield:
		return SUCCESS
	return _tian_shi_ji_ban()


## 天使羁绊结算：询问 天使 指定的一名角色，使其 +1 治疗（未选择目标时默认自己）
func _tian_shi_ji_ban() -> int:
	if not engine.has_reply():
		engine.ask_skill(player.id, TIAN_SHI_JI_BAN, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(TIAN_SHI_JI_BAN, [dst_id])
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null:
		dst.add_cross_num(1)
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
	var dsts: Array = action.get("dst_ids", [])
	match aid:
		TIAN_SHI_ZHI_QIANG:
			if cards.is_empty() or dsts.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or not card.has_speciality_name(TAG_TIAN_SHI_ZHI_QIANG):
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			if dst == null:
				return GConst.GE_INVALID_PLAYERID
			if dst.check_basic_effect_name(GConst.CardName.Shield) or _has_basic_tag(dst, TAG_TIAN_SHI_ZHI_QIANG):
				return GConst.GE_INVALID_ACTION
		FENG_ZHI_JIE_JING:
			if cards.is_empty() or dsts.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid2: int = int(cards[0])
			var card2: GCard = Data.get_card(cid2)
			if not player.has_hand_card(cid2) or card2 == null or card2.element_enum() != GConst.CardElement.Wind:
				return GConst.GE_INVALID_ACTION
			var args: Array = action.get("args", [])
			if args.is_empty():
				return GConst.GE_INVALID_ARGUMENT
			var dst2: BattlePlayer = engine.p(int(dsts[0]))
			if dst2 == null or not _has_basic_card(dst2, int(args[0])):
				return GConst.GE_INVALID_ACTION
		TIAN_SHI_ZHU_FU:
			if cards.is_empty() or dsts.is_empty() or dsts.size() > 2:
				return GConst.GE_INVALID_ACTION
			var cid3: int = int(cards[0])
			var card3: GCard = Data.get_card(cid3)
			if not player.has_hand_card(cid3) or card3 == null or card3.element_enum() != GConst.CardElement.Water:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		TIAN_SHI_ZHI_QIANG:
			return _tian_shi_zhi_qiang(action)
		FENG_ZHI_JIE_JING:
			return _feng_zhi_jie_jing(action)
		TIAN_SHI_ZHU_FU:
			return _tian_shi_zhu_fu(action)
	return GConst.GE_INVALID_ACTION


## 天使之墙：将手牌移到目标的基础效果区（v_shield 已按【天使之墙】判定重复；
## 引擎的自动格挡路径也把【天使之墙】视作【圣盾】挡下，见文件头说明）
func _tian_shi_zhi_qiang(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	notice_skill(TIAN_SHI_ZHI_QIANG, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	# 走引擎方法以触发 p_basic_effect_change（天使羁绊 704）；cause 与服务端一致为 CAUSE_USE
	engine.add_basic_effect(dst_id, cid, player.id, GConst.CAUSE_USE)
	engine._broadcast_game()
	return SUCCESS


## 风之洁净：弃 1 张风系牌，移除场上任意一个基础效果
func _feng_zhi_jie_jing(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	var cid: int = int(cards[0])
	var effect_cid: int = int(args[0])
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	notice_skill(FENG_ZHI_JIE_JING, [dst.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.remove_basic_effect(dst.id, effect_cid, FENG_ZHI_JIE_JING)
	engine.to_discard([effect_cid])
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	engine._broadcast_game()
	return SUCCESS


## 天使祝福：弃 1 张水系牌后，向 1~2 名指定角色各索取手牌（单目标 2 张 / 双目标各 1 张），
## 索得的牌进入天使手中。对应服务端 TianShi::TianShiZhuFu + StateRequestHand（去向 DECK_HAND）
## 说明：客户端「发动技能」只支持单选目标，故实践中走单目标 2 张形态；
##   向目标索取手牌复用「需选牌」的技能询问（与兽灵武士等角色的请求手牌约定一致）。
func _tian_shi_zhu_fu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var 每人张数: int = 1 if dsts.size() > 1 else 2
	# 第一阶段：公告并弃掉发动用的水系牌
	if step == 0:
		step = TIAN_SHI_ZHU_FU
		notice_skill(TIAN_SHI_ZHU_FU, dsts)
		var use_cid: int = int(cards[0])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [use_cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [use_cid])
		engine.to_discard([use_cid])
		engine._broadcast_game()
	var idx: int = step - TIAN_SHI_ZHU_FU
	if idx >= dsts.size():
		step = STEP_DONE
		return SUCCESS
	var t: BattlePlayer = engine.p(int(dsts[idx]))
	# 目标无手牌：跳过
	if t == null or t.hand_cards.is_empty():
		step += 1
		return _tian_shi_zhu_fu(action)
	if not engine.has_reply():
		engine.ask_skill(t.id, TIAN_SHI_ZHU_FU, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var want: int = mini(每人张数, t.hand_cards.size())
	var chosen: Array = _pick_cards(t, r.get("card_ids", []), want)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": t.id, "dst_id": player.id,
		"card_ids": chosen, "is_real": true,
	})
	engine.take_from_hand(t.id, chosen)
	player.add_hand_cards(chosen)
	engine._broadcast_game()
	step += 1
	return _tian_shi_zhu_fu(action)


# ============================================================
# 神之庇护（706，服务端 TianShi::p_lose_morale）
# 我方角色因法术伤害将掉士气时（在超限掉士气的可等待钩子轮次里），
# 可消耗能量抵消等量士气损失；服务端由客户端分别指定宝石/水晶数量，
# 本引擎客户端只支持「抵消几点」，故支付顺序固定为「先水晶后宝石」。
# ============================================================
func p_lose_morale(ctx: Dictionary) -> int:
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	# 仅「因法术伤害」掉士气时可发动（con->harm.type == HARM_MAGIC）
	if int(ctx.get("type", 0)) != GConst.HarmType.Magic:
		return SUCCESS
	var amount: int = int(ctx.get("amount", 0))
	if amount <= 0 or player.get_energy() <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		var 上限: int = mini(amount, player.get_energy())
		var options: Array = []
		for n: int in range(1, 上限 + 1):
			options.append({"value": n, "label": "抵消 %d 点（耗 %d 能量）" % [n, n]})
		engine.ask_skill(player.id, SHEN_ZHI_BI_HU, 0, 0, GConst.CardSource.Hand, options)
		return WAIT
	step = STEP_DONE
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 支付: int = int(args[0]) if not args.is_empty() else 0
	支付 = clampi(支付, 0, mini(amount, player.get_energy()))
	if 支付 <= 0:
		return SUCCESS
	notice_skill(SHEN_ZHI_BI_HU, [dst.id])
	_consume_energy(支付)
	ctx["amount"] = amount - 支付
	engine._broadcast_game()
	return SUCCESS


## 消耗能量：先水晶后宝石
func _consume_energy(n: int) -> void:
	var 用水晶: int = mini(player.crystal, n)
	if 用水晶 > 0:
		player.set_crystal(player.crystal - 用水晶)
	var 剩: int = n - 用水晶
	if 剩 > 0:
		player.set_gem(player.gem - 剩)


# ============================================================
# 工具
# ============================================================
## 从回复的卡牌中挑出最多 n 张目标手牌里真实存在的牌；不足时用手牌补齐
## （目标取消/超时/掉线时不空转，与服务端 canGiveUp=false 的「必须交出」语义一致）
func _pick_cards(target: BattlePlayer, ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if target.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in target.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


func _hand_has_element(elem: int) -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == elem:
			return true
	return false


func _hand_has_tag(tag: String) -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.has_speciality_name(tag):
			return true
	return false


## 目标是否拥有带某特技的基础效果（天使之墙）
func _has_basic_tag(target: BattlePlayer, tag: String) -> bool:
	for e: Dictionary in target.basic_effects:
		var c: GCard = Data.get_card(int(e["card"]))
		if c != null and c.has_speciality_name(tag):
			return true
	return false


## 目标是否拥有指定的基础效果牌
func _has_basic_card(target: BattlePlayer, cid: int) -> bool:
	for e: Dictionary in target.basic_effects:
		if int(e["card"]) == cid:
			return true
	return false


## 场上是否有任意基础效果
func _any_player_has_basic_effect() -> bool:
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and not p0.basic_effects.is_empty():
			return true
	return false

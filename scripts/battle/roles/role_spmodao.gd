extends BattleRole
## sp魔导师（roleID 108）—— 移植自服务端 role/spMoDao.cpp
## 技能：
##   sp魔爆冲击（805）——【法术】弃 1 张法术牌【展示】；我方【战绩区】+1【宝石】；指定 1 名目标对手
##        弃 1 张法术牌【展示】，若他不如此做，则对其造成 2 点法术伤害③
##   魔弹融合（803）——【响应】你的地系或火系牌可以当【魔弹】使用（打出后成为魔弹，
##        落点＝右手边最近的对手；之后由引擎统一的「魔弹传递」询问接手：
##        被指向者可打出【魔弹】/地系/火系牌继续传递（每传递一次伤害 +1）、用【圣光】抵挡（效果终止），
##        或不如此做而承受伤害（其拥有【圣盾】/【天使之墙】时改为移除之并视作未命中））
##   毁灭风暴（804）——【法术·宝石】对 2 名对手各造成 2 点法术伤害③
##   法力护盾（806）——【响应】任何人对你造成伤害时（③），弃 X 张法术牌【展示】以抵御 X 点该次伤害（p_timeline_3）
##
## 牌类校验覆写：服务端 spMoDao.cpp 覆写 v_missile / v_remissile（手中【魔弹】或地系/火系牌
## 可当【魔弹】使用与响应），已按服务端移植于本文件。
## 引擎限制说明：服务端 spMoDao.cpp 并未实现【魔弹掌握】(802)，故本文件不实现该技能（不凭空编造）。
## 变通说明：服务端用 StateRequestHand 处理「请求手牌」，本引擎改用 ask_skill 逐一询问相关玩家
## （回复 args[0]==1 表示照做，card_ids 给出所弃的牌）；「魔弹传递」则复用引擎的 SMissileAsk。

const SP_MO_BAO_CHONG_JI: int = 805
const FA_LI_HU_DUN: int = 806
const MO_DAN_RONG_HE: int = 803
const HUI_MIE_FENG_BAO: int = 804

const SP_MO_BAO_HARM_POINT: int = 2     # sp魔爆冲击：不弃法术牌的目标受到的法术伤害
const HUI_MIE_HARM_POINT: int = 2       # 毁灭风暴：每名对手受到的法术伤害


# ============================================================
# 行动阶段可选技能
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	var enemies: int = _enemy_count()
	if _hand_has_magic() and enemies >= 1:
		# 弃 1 张法术牌 + 指定 1 名对手弃牌
		out.append({"type": GConst.ActionType.MagicSkill, "id": SP_MO_BAO_CHONG_JI, "need_card": 1, "need_target": 1,
			"targets": enemy_ids(), "cards": magic_hand_ids()})
	if _hand_has_fire_or_earth() and enemies >= 1:
		# 落点候选（本角色没有【魔弹掌握】，只有右手边那个）一并发给客户端，界面只亮这些
		# 可用牌＝手中的地系/火系牌（与 v_missile_fusion 的牌校验同一条），界面据此把其余手牌置灰
		var 魔弹牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Fire or c.element_enum() == GConst.CardElement.Earth)
		out.append({"type": GConst.ActionType.MagicSkill, "id": MO_DAN_RONG_HE, "need_card": 1, "need_target": 1,
			"targets": missile_targets(player.id), "cards": 魔弹牌})
	if player.gem > 0 and enemies >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": HUI_MIE_FENG_BAO, "need_card": 0, "need_target": 2,
			"targets": enemy_ids()})
	return out


# ============================================================
# 承受伤害（p_timeline_3）：法力护盾（弃 X 张法术牌抵御 X 点伤害）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if not _hand_has_magic():
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 只能弃法术牌（技能原文）：下发 magic 规则，界面把攻击牌等置灰
		询问(player.id, FA_LI_HU_DUN, 1, 0, GConst.CardSource.Hand, [], 0, "magic")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = _valid_magic_cards(r.get("card_ids", []))
	if cards.is_empty():
		return SUCCESS
	notice_skill(FA_LI_HU_DUN, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards)
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = maxi(int(harm.get("point", 0)) - cards.size(), 0)
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
		SP_MO_BAO_CHONG_JI:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or not card.is_magic():
				return GConst.GE_INVALID_CARDID
			if dsts.is_empty():
				return GConst.GE_INVALID_PLAYERID
		MO_DAN_RONG_HE:
			return v_missile_fusion(action)
		HUI_MIE_FENG_BAO:
			if player.gem <= 0:
				return GConst.GE_INVALID_ACTION
			return _check_two_target(action)
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SP_MO_BAO_CHONG_JI:
			return _sp_mo_bao_chong_ji(action)
		MO_DAN_RONG_HE:
			return cast_missile_fusion(action)
		HUI_MIE_FENG_BAO:
			return _hui_mie_feng_bao(action)
	return GConst.GE_INVALID_ACTION


## sp魔爆冲击：弃 1 张法术牌，我方 +1 宝石，目标对手弃 1 张法术牌，未弃则受 2 点法术伤害
func _sp_mo_bao_chong_ji(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var tid: int = int(dsts[0])
	var cid: int = int(cards[0])
	if step == 0:
		notice_skill(SP_MO_BAO_CHONG_JI, [tid])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		# 不论目标是否弃牌，我方战绩区都 +1 宝石
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
		# 代价牌当场弃掉，别拖到目标应答之后（否则这段询问期间它还在手上）
		engine.take_from_hand(player.id, [cid], true)
		engine.to_discard([cid])
		engine._broadcast_game()
		step = 1
	if step != 1:
		return SUCCESS
	if not engine.has_reply():
		# 目标只能弃法术牌（技能原文）：下发 magic 规则，界面把攻击牌等置灰
		询问(tid, SP_MO_BAO_CHONG_JI, 1, 0, GConst.CardSource.Hand, [], 0, "magic")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	if _target_discard_magic(tid, r):
		return SUCCESS
	engine.push_harm({
		"src": player.id, "dst": tid, "point": SP_MO_BAO_HARM_POINT,
		"cause": SP_MO_BAO_CHONG_JI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 毁灭风暴：消耗 1 宝石，对 2 名对手各造成 2 点法术伤害
func _hui_mie_feng_bao(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	notice_skill(HUI_MIE_FENG_BAO, dsts)
	player.set_gem(player.gem - 1)
	# 2 名目标按玩家点选顺序结算；伤害状态是栈（后压先算）→ 逆序压栈
	for i: int in range(dsts.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": int(dsts[i]), "point": HUI_MIE_HARM_POINT,
			"cause": HUI_MIE_FENG_BAO, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 牌类校验覆写：魔弹融合（803）——你的地系或火系牌可以当【魔弹】使用
# 对照服务端 spMoDao::v_missile / v_remissile：手中牌为【魔弹】或地系/火系则通过，
# 否则恒返回 GE_INVALID_CARDID（服务端把「不在手牌」与「牌型不符」合并为同一错误码）。
# ============================================================
func v_missile(card_id: int, _dst_id: int) -> int:
	if not _can_use_missile(card_id):
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


func v_remissile(card_id: int) -> int:
	if not _can_use_missile(card_id):
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


# ============================================================
# 工具
# ============================================================
## 校验「恰好 2 名互不相同的对手」（服务端 checkTwoTarget）
func _check_two_target(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != 2:
		return GConst.GE_INVALID_PLAYERID
	var d1: int = int(dsts[0])
	var d2: int = int(dsts[1])
	var p1: BattlePlayer = engine.p(d1)
	var p2: BattlePlayer = engine.p(d2)
	if p1 == null or p2 == null or d1 == d2:
		return GConst.GE_INVALID_PLAYERID
	if p1.color == player.color or p2.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 让目标弃 1 张法术牌【展示】；成功返回 true
func _target_discard_magic(tid: int, r: Dictionary) -> bool:
	var args: Array = r.get("args", [])
	var given: Array = r.get("card_ids", [])
	if args.is_empty() or int(args[0]) != 1 or given.is_empty():
		return false
	var gid: int = int(given[0])
	var target: BattlePlayer = engine.p(tid)
	var card: GCard = Data.get_card(gid)
	if target == null or card == null or not card.is_magic() or not target.has_hand_card(gid):
		return false
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": tid, "dst_id": tid,
		"card_ids": [gid], "is_real": true,
	})
	engine.take_from_hand(tid, [gid], true)
	engine.to_discard([gid])
	engine._broadcast_game()
	return true


## 手中牌能否当作【魔弹】使用／响应（服务端 v_missile / v_remissile 的判定）
func _can_use_missile(card_id: int) -> bool:
	if not player.has_hand_card(card_id):
		return false
	var card: GCard = Data.get_card(card_id)
	if card == null:
		return false
	return _can_remissile(card)


## 该牌能否继续传递魔弹（【魔弹】或地系/火系牌，对照 v_remissile）
func _can_remissile(card: GCard) -> bool:
	if card.card_name_enum() == GConst.CardName.Missile:
		return true
	var e: int = card.element_enum()
	return e == GConst.CardElement.Fire or e == GConst.CardElement.Earth


func _enemy_count() -> int:
	var n: int = 0
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color:
			n += 1
	return n


func _hand_has_magic() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			return true
	return false


func _hand_has_fire_or_earth() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		var e: int = c.element_enum()
		if e == GConst.CardElement.Fire or e == GConst.CardElement.Earth:
			return true
	return false


## 从回复的卡牌中筛出确实持有的法术牌
func _valid_magic_cards(ids: Array) -> Array:
	var out: Array = []
	for c: Variant in ids:
		var cid: int = int(c)
		if out.has(cid) or not player.has_hand_card(cid):
			continue
		var card: GCard = Data.get_card(cid)
		if card != null and card.is_magic():
			out.append(cid)
	return out

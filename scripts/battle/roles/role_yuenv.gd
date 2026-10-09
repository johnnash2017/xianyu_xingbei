extends BattleRole
## 月之女神（roleID 35）—— 移植自服务端 role/YueNv.cpp
## 【响应】新月庇护（3501）：我方角色因伤害导致手牌超限而将要掉士气时，横置转为【新月形态】，
##                  把因此弃掉的牌作为【暗月】，本次士气不下降
## 【被动】暗月诅咒（3502）：每次移除【暗月】，我方士气 -1；【暗月】为 0 时重置脱离新月形态
## 【响应】美杜莎之眼（3503）：目标对手攻击时移除 1 个【暗月】，+1 治疗、+1【石化】；
##                  若该【暗月】为法术牌则自己弃 1 张牌并额外对攻击者造成 1 点法术伤害
## 【响应】月之轮回（3504）：回合结束时，移除 1 个【暗月】令目标角色 +1 治疗；
##                  或移除自己 1 治疗换取 +1【新月】
## 【响应】月渎（3505）【回合限定】：对自己造成法术伤害时，移除 1 治疗并对目标对手造成 1 点法术伤害
## 【响应】暗月斩（3506）：耗 1 能量并一次性移除 X 个【暗月】，本次主动攻击伤害 +X
## 【法术】苍白之月（3507）：耗 1 宝石；移除 3【石化】获得额外攻击行动且本次攻击无法应战并获得额外回合；
##                  或移除 X【新月】、+1【石化】、弃 1 张牌并对目标对手造成（X+1）点法术伤害
## 【暗月】为专属盖牌、【新月】/【石化】为专属指示物，上限见角色表

const XIN_YUE_BI_HU: int = 3501
const AN_YUE_ZU_ZHOU: int = 3502
const MEI_DU_SHA: int = 3503
const YUE_ZHI_LUN_HUI: int = 3504
const YUE_DU: int = 3505
const AN_YUE_ZHAN: int = 3506
const CANG_BAI_ZHI_YUE: int = 3507

## 步骤标记（非技能号）：美杜莎之眼第二段（自己弃 1 张牌）
const STEP_MEI_DU_DISCARD: int = 35031
## 步骤标记（非技能号）：美杜莎之眼收尾（移除【暗月】）
const STEP_MEI_DU_END: int = 35032

## 【月渎】为回合限定
var _used_yue_du: bool = false
## 【苍白之月】授予的额外攻击：玩家选中该额外行动时置位，本次攻击无法应战
var _cang_bai_attack: bool = false
## 【苍白之月】第一分支：回合结束后额外获得一个回合
var _cang_bai_add_turn: bool = false
## 美杜莎之眼的中间状态
var _md_card: int = -1
var _md_dst: int = -1


func available_skills() -> Array:
	var out: Array = []
	# 苍白之月：耗 1 宝石，可选「移除 3【石化】」或「移除 x【新月】并造成伤害」；两者都不满足时不显示
	var 选项: Array = _cang_bai_choices()
	if player.gem > 0 and not 选项.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": CANG_BAI_ZHI_YUE, "need_card": 0, "need_target": 0,
			"target_max": 1, "arg_choices": 选项})
	return out


## 苍白之月的参数选项：choice=1 移除 3 点【石化】（无需目标）；
## choice=2 移除 x 点【新月】，弃 1 张牌并对目标造成 x+1 点法术伤害（需 1 名目标）
func _cang_bai_choices() -> Array:
	var out: Array = []
	if int(player.tokens[1]["num"]) >= 3:
		out.append({"text": "移除 3 点【石化】", "args": [1]})
	var 新月数: int = int(player.tokens[0]["num"])
	for x: int in range(1, 新月数 + 1):
		out.append({"text": "移除 %d 点【新月】，弃 1 张牌并对目标造成 %d 点法术伤害" % [x, x + 1],
			"args": [2, x], "need_target": 1})
	return out


# ============================================================
# 新月庇护：因伤害导致手牌超限而掉士气时，把弃牌作为【暗月】免掉本次士气下降
# 对应服务端 StateXinYue 阶段（掉士气链中的 p_xin_yue）
# ============================================================
func p_xin_yue(ctx: Dictionary) -> int:
	if player.tap:
		return SUCCESS
	# 服务端要求本次掉士气由伤害造成（con->harm.type != HARM_NONE）
	if int(ctx.get("type", 0)) == GConst.HarmType.None:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	var amount: int = int(ctx.get("amount", 0))
	if amount <= 0:
		return SUCCESS
	notice_skill(XIN_YUE_BI_HU, [dst.id])
	# 本次因超限而弃置的牌（弃牌堆尾部）作为【暗月】盖在自己面前
	var pulled: Array = []
	for _i: int in range(amount):
		if engine.deck.discard.is_empty():
			break
		pulled.append(engine.deck.discard.pop_back())
	engine.add_cover(player.id, pulled, player.id, XIN_YUE_BI_HU)
	player.tap = true
	ctx["amount"] = 0
	engine._broadcast_game()
	return SUCCESS


## 【美杜莎之眼】的推进阶段（0＝还没开始 / STEP_MEI_DU_DISCARD＝在等自己弃 1 张牌 / STEP_MEI_DU_END＝收尾移除【暗月】）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次敌方角色的攻击宣告后（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _mei_du_sha_step: int = 0


# ============================================================
# 美杜莎之眼：目标对手攻击时移除 1 个【暗月】
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	var src: int = int(ctx.get("src", -1))
	if src != player.id:
		return SUCCESS
	if _cang_bai_attack:
		# 【苍白之月】授予的额外攻击无法应战
		ctx["hit_rate"] = GConst.HitRate.NoReattack
		_cang_bai_attack = false
		return SUCCESS
	if _mei_du_sha_step >= STEP_DONE:
		return SUCCESS
	var attacker: BattlePlayer = engine.p(src)
	# 只对敌方角色的攻击响应
	if attacker == null or attacker.color == player.color:
		return SUCCESS
	if _mei_du_sha_step == 0:
		if player.cover_cards.is_empty():
			return SUCCESS
		if not engine.has_reply():
			询问(player.id, MEI_DU_SHA, 1, 1, GConst.CardSource.Cover, [
				{"value": 1, "label": "普通（+1 治疗、+1 暗月）"},
				{"value": 2, "label": "当作法术牌（弃 1 张牌，追加 1 点法术伤害）"},
			])
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var cids: Array = r.get("card_ids", [])
		if args.is_empty() or int(args[0]) <= 0 or cids.is_empty() or not player.cover_cards.has(int(cids[0])):
			_mei_du_sha_step = 0
			return SUCCESS
		_md_card = int(cids[0])
		_md_dst = -1
		notice_skill(MEI_DU_SHA, [src])
		施加治疗(player.id, 1)
		_add_token(1, 1)
		# args[0] == 2 表示移除的【暗月】为法术牌：自己弃 1 张牌并额外造成 1 点法术伤害
		if int(args[0]) == 2:
			var dsts: Array = r.get("dst_ids", [])
			if not dsts.is_empty():
				_md_dst = int(dsts[0])
			_mei_du_sha_step = STEP_MEI_DU_DISCARD
		else:
			_mei_du_sha_step = STEP_MEI_DU_END
	if _mei_du_sha_step == STEP_MEI_DU_DISCARD:
		var r2: int = _force_discard_one(player.id)
		if r2 == WAIT:
			return WAIT
		_mei_du_sha_step = STEP_MEI_DU_END
	if _mei_du_sha_step == STEP_MEI_DU_END:
		_mei_du_sha_step = 0
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [_md_card], "is_real": true,
		})
		# 服务端后进先出：先移除【暗月】，最后结算额外伤害
		_remove_anyue([_md_card])
		if _md_dst >= 0:
			engine.push_harm({
				"src": player.id, "dst": _md_dst, "point": 1,
				"cause": MEI_DU_SHA, "type": GConst.HarmType.Magic,
			})
		# 引擎在钩子返回 URGENT 后会重入同一钩子（step 归零），为避免【美杜莎之眼】重复触发，
		# 这里返回 SUCCESS；已压入的额外伤害随后仍会执行
		engine._broadcast_game()
		return SUCCESS
	return SUCCESS


# ============================================================
# 月之轮回：回合结束时选择「移除 1 个【暗月】令目标 +1 治疗」或「移除 1 治疗换 1【新月】」
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if player.cross_num < 1 and player.cover_cards.is_empty():
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, YUE_ZHI_LUN_HUI, 1, 1, GConst.CardSource.Cover, [
			{"value": 1, "label": "移除 1 张【暗月】：指定角色 +1 治疗"},
			{"value": 2, "label": "耗 1 点治疗：+1【新月】指示物"},
		])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty():
		return SUCCESS
	var choice: int = int(args[0])
	if choice == 1:
		var dsts: Array = r.get("dst_ids", [])
		var cids: Array = r.get("card_ids", [])
		if dsts.is_empty() or cids.is_empty() or not player.cover_cards.has(int(cids[0])):
			return SUCCESS
		var dst: BattlePlayer = engine.p(int(dsts[0]))
		notice_skill(YUE_ZHI_LUN_HUI, [int(dsts[0])])
		if dst != null:
			施加治疗(dst.id, 1)
		_remove_anyue([int(cids[0])])
		engine._broadcast_game()
		return SUCCESS
	if choice == 2 and player.cross_num >= 1:
		notice_skill(YUE_ZHI_LUN_HUI, [player.id])
		player.sub_cross_num(1)
		_add_token(0, 1)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 月渎【回合限定】：对自己造成法术伤害时，移除 1 治疗并对目标对手造成 1 点法术伤害
# ============================================================
func p_timeline_6_drawn(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if player.cross_num < 1 or _used_yue_du:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, YUE_DU, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
		return SUCCESS
	notice_skill(YUE_DU, [int(dsts[0])])
	_used_yue_du = true
	player.sub_cross_num(1)
	engine.push_harm({
		"src": player.id, "dst": int(dsts[0]), "point": 1,
		"cause": YUE_DU, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 暗月斩：主动攻击命中后移除 X 个【暗月】，本次伤害 +X
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.get_energy() < 1 or player.cover_cards.is_empty():
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 暗月斩移除的是【暗月】（专属盖牌）：选牌来源必须是盖牌区，否则界面会亮手牌却选不出合法的牌
		询问(player.id, AN_YUE_ZHAN, 1, 0, GConst.CardSource.Cover)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = []
	for c: Variant in r.get("card_ids", []):
		if player.cover_cards.has(int(c)) and not cards.has(int(c)):
			cards.append(int(c))
	if cards.is_empty():
		return SUCCESS
	notice_skill(AN_YUE_ZHAN, [int(harm.get("dst", -1))])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	harm["point"] = int(harm.get("point", 0)) + cards.size()
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	_remove_anyue(cards)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能：苍白之月
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != CANG_BAI_ZHI_YUE:
		return GConst.GE_INVALID_ACTION
	if player.gem < 1:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice == 1:
		# 移除 3 点【石化】
		if int(player.tokens[1]["num"]) < 3:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if choice == 2:
		var x: int = int(args[1]) if args.size() > 1 else 0
		if x < 1 or x > int(player.tokens[0]["num"]):
			return GConst.GE_INVALID_ACTION
		if action.get("dst_ids", []).is_empty():
			return GConst.GE_INVALID_PLAYERID
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != CANG_BAI_ZHI_YUE:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	player.set_gem(player.gem - 1)
	notice_skill(CANG_BAI_ZHI_YUE, action.get("dst_ids", []))
	if choice == 1:
		# 移除 3【石化】：额外 1 次攻击行动（选中该额外行动时置「无法应战」，见 p_additional_action）、
		# 并获得一个额外回合
		_add_token(1, -3)
		player.add_action(GConst.ActionType.Attack, CANG_BAI_ZHI_YUE, true)
		_cang_bai_add_turn = true
		engine._broadcast_game()
		return SUCCESS
	if choice == 2:
		var x: int = int(args[1]) if args.size() > 1 else 0
		x = clampi(x, 1, int(player.tokens[0]["num"]))
		_add_token(0, -x)
		_add_token(1, 1)
		# 弃 1 张牌（由技能动作携带的手牌）
		_discard_hand_cards(action.get("card_ids", []), 1)
		var dsts: Array = action.get("dst_ids", [])
		if not dsts.is_empty():
			engine.push_harm({
				"src": player.id, "dst": int(dsts[0]), "point": 1 + x,
				"cause": CANG_BAI_ZHI_YUE, "type": GConst.HarmType.Magic,
			})
		engine._broadcast_game()
		return URGENT
	return SUCCESS


# ============================================================
# 玩家选择额外行动时（服务端 YueNv::p_additional_action）：
# 选中【苍白之月】授予的攻击行动则记为不可应战，其他选择一律清除
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_cang_bai_attack = int(ctx.get("cause", 0)) == CANG_BAI_ZHI_YUE
	return SUCCESS


# ============================================================
# 额外回合（苍白之月第一分支）与回合限定的重置
# ============================================================
func p_after_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not _cang_bai_add_turn:
		return SUCCESS
	_cang_bai_add_turn = false
	# 服务端在这一步弹出「回合结束」状态（于是紧接着的「轮到下家」不再执行）、清掉额外行动，
	# 广播自己的 TurnBegin 并重开自己的回合开始。本引擎等价做法：告诉 SNextPlayer「下个回合还是我」
	player.clear_additional_action()
	engine.额外回合玩家 = player.id
	engine.broadcast(GConst.Msg.TurnBegin, {"id": player.id, "round": engine.round_id})
	engine._broadcast_game()
	return SUCCESS


func p_before_turn_begin(_ctx: Dictionary) -> int:
	_used_yue_du = false
	_cang_bai_attack = false
	_cang_bai_add_turn = false
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 移除【暗月】并结算「暗月诅咒」：我方士气 -1；【暗月】为 0 时脱离新月形态
func _remove_anyue(cards: Array) -> void:
	if cards.is_empty():
		return
	engine.to_discard(cards)
	engine.remove_cover(player.id, cards, player.id, AN_YUE_ZU_ZHOU)
	engine.lose_morale(player, 1, AN_YUE_ZU_ZHOU)
	if player.cover_cards.is_empty() and player.tap:
		player.tap = false


## 变更指示物数量（受上限约束）
func _add_token(idx: int, delta: int) -> void:
	var t: Dictionary = player.tokens[idx]
	t["num"] = clampi(int(t["num"]) + delta, 0, int(t["max"]))


## 弃掉至多 n 张手牌（客户端未给出合法牌时从手牌补齐）
func _discard_hand_cards(cards: Array, n: int) -> void:
	if n <= 0:
		return
	var chosen: Array = []
	for c: Variant in cards:
		if chosen.size() >= n:
			break
		if player.has_hand_card(int(c)) and not chosen.has(int(c)):
			chosen.append(int(c))
	while chosen.size() < n and chosen.size() < player.hand_cards.size():
		for cid: int in player.hand_cards:
			if chosen.size() >= n:
				break
			if not chosen.has(cid):
				chosen.append(cid)
	if chosen.is_empty():
		return
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen)
	engine._log_discard(player.id, chosen)


## 强制某玩家弃 1 张手牌（对应服务端 StateRequestHand → DECK_DISCARD）
func _force_discard_one(pid: int) -> int:
	var tp: BattlePlayer = engine.p(pid)
	if tp == null or tp.hand_cards.is_empty():
		return SUCCESS
	if not engine.has_reply():
		# cause 写技能号（不是 CAUSE_USE）：客户端据此把提示写成「【美杜莎之眼】：请选择 1 张牌弃掉」
		engine.ask_respond(pid, GConst.RespondType.Discard, [pid, MEI_DU_SHA, 1], [pid])
		engine.wait_for(pid, GConst.Msg.Respond)
		return WAIT
	var r: Dictionary = engine.take_reply()
	var chosen: Array = []
	for c: Variant in r.get("card_ids", []):
		if chosen.size() < 1 and tp.has_hand_card(int(c)):
			chosen.append(int(c))
	if chosen.is_empty():
		chosen.append(tp.hand_cards[0])
	engine.take_from_hand(pid, chosen)
	engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS

extends BattleRole
## 月之女神（roleID 35）—— 移植自服务端 role/YueNv.cpp
## 【响应】新月庇护（3501）：我方角色因伤害导致手牌超限而将要掉士气时，横置转为【暗月形态】，
##                  把因此弃掉的牌作为【暗月】，本次士气不下降
## 【被动】暗月诅咒（3502）：每次移除【暗月】，我方士气 -1；【暗月】为 0 时重置脱离【暗月形态】
## 【响应】美杜莎之眼（3503）：目标对手攻击时移除 1 个与攻击牌同系的【暗月】，+1 治疗、+1【石化】；
##                  若该【暗月】为法术牌则自己弃 1 张牌并额外对攻击者造成 1 点法术伤害
## 【响应】月之轮回（3504）：回合结束时，移除 1 个【暗月】令目标角色 +1 治疗；
##                  或移除自己 1 治疗换取 +1【新月】
## 【响应】月渎（3505）【回合限定】：你造成的法术伤害结算后，移除 1 治疗并对目标对手造成 1 点法术伤害
## 【响应】暗月斩（3506）：耗 1 能量并一次性移除 X 个【暗月】，本次主动攻击伤害 +X
## 【法术】苍白之月（3507）：耗 1 宝石；移除 3【石化】获得额外攻击行动（该次攻击无法应战）、
##                  额外获得一个回合；或移除 X【新月】、+1【石化】、弃 1 张牌并对目标对手造成（X+1）点法术伤害
## 【暗月】为专属盖牌、【新月】/【石化】为专属指示物，上限见角色表

const XIN_YUE_BI_HU: int = 3501
const AN_YUE_ZU_ZHOU: int = 3502
const MEI_DU_SHA: int = 3503
const YUE_ZHI_LUN_HUI: int = 3504
const YUE_DU: int = 3505
const AN_YUE_ZHAN: int = 3506
const CANG_BAI_ZHI_YUE: int = 3507

## 步骤标记（非技能号）：美杜莎之眼收尾（移除【暗月】）
const STEP_MEI_DU_END: int = 35032

## 【月渎】为回合限定
var _used_yue_du: bool = false
## 【苍白之月】第一项授予的那次额外攻击：玩家点中「额外攻击行动」时置位，该次攻击无法应战
var _cang_bai_attack: bool = false
## 【苍白之月】第一分支：回合结束后额外获得一个回合
var _cang_bai_add_turn: bool = false
## 美杜莎之眼的中间状态（暗月盖牌 / 法术伤害目标 / 同一步一起选的弃牌）
var _md_card: int = -1
var _md_dst: int = -1
var _md_hand: int = -1


func available_skills() -> Array:
	var out: Array = []
	# 苍白之月：耗 1 宝石，可选「移除 3【石化】」或「移除 x【新月】并造成伤害」；
	# 两项都做不了（没石化 / 没新月 / 没手牌可弃）时整条技能置灰
	var 选项: Array = _cang_bai_choices()
	var 有可用项: bool = false
	for 项: Dictionary in 选项:
		if bool(项.get("enabled", true)):
			有可用项 = true
			break
	out.append({"type": GConst.ActionType.MagicSkill, "id": CANG_BAI_ZHI_YUE, "need_card": 0, "need_target": 0,
		"target_max": 1, "arg_choices": 选项,
		"enabled": player.gem > 0 and 有可用项})
	return out


## 苍白之月的参数选项：choice=1 移除 3 点【石化】（无需目标 / 弃牌）；
## choice=2 移除 x 点【新月】，自己选 1 张手牌弃掉，并对目标对手造成 x+1 点法术伤害（需 1 名目标）
func _cang_bai_choices() -> Array:
	var 敌人: Array = enemy_ids()
	var 石化数: int = int(player.tokens[1]["num"])
	var 新月数: int = int(player.tokens[0]["num"])
	# 两项始终摆出来：条件不满足的置灰（半透明、点不动），不要整项消失
	return [
		{"text": "移除3点【石化】+1无法应战【攻击行动】。+1回合。",
			"args": [1], "enabled": 石化数 >= 3},
		{"text": "移除X点【新月】+1【石化】，弃 1 张牌。对目标对手造成 X+1点法术伤害。",
			"args": [2], "need_card": 1, "need_target": 1, "targets": 敌人,
			"enabled": 新月数 >= 1 and not player.hand_cards.is_empty() and not 敌人.is_empty()},
	]


# ============================================================
# 新月庇护：队友因伤害手牌超限、准备弃牌前，询问是否横置发动；
# 发动后由引擎把“本次本来要弃的那几张牌”直接移成【暗月】，本次士气不下降。
# ctx["before_discard"]=true 时才是超限弃牌前那次询问；掉士气链里的 p_xin_yue 已不再重复问。
# ============================================================
func p_xin_yue(ctx: Dictionary) -> int:
	if not bool(ctx.get("before_discard", false)):
		return SUCCESS
	if not bool(ctx.get("from_damage", false)):
		return SUCCESS
	if player.tap:
		return SUCCESS
	# 只响应“因伤害”造成的超限（非伤害掉士气 / 未知类型不触发）
	var 伤害类型: int = int(ctx.get("type", GConst.HarmType.None))
	if 伤害类型 != GConst.HarmType.Attack and 伤害类型 != GConst.HarmType.Magic:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	var cards: Array = ctx.get("cards", [])
	if cards.is_empty():
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, XIN_YUE_BI_HU, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(XIN_YUE_BI_HU, [dst.id])
	ctx["active"] = true
	ctx["moon_id"] = player.id
	return SUCCESS


## 【美杜莎之眼】的推进阶段（0＝还没开始 / STEP_MEI_DU_END＝收尾移除【暗月】）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨几次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次敌方角色的攻击宣告后（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _mei_du_sha_step: int = 0


# ============================================================
# 美杜莎之眼：目标对手攻击时移除 1 个【暗月】
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	var src: int = int(ctx.get("src", -1))
	if src == player.id:
		# 自己的攻击只处理【苍白之月】授予的那次额外攻击：本次无法应战
		if _cang_bai_attack and engine.行动额外 \
				and int(engine.行动额外来源) == CANG_BAI_ZHI_YUE:
			ctx["hit_rate"] = GConst.HitRate.NoReattack
			_cang_bai_attack = false
		return SUCCESS
	if _mei_du_sha_step >= STEP_DONE:
		return SUCCESS
	var attacker: BattlePlayer = engine.p(src)
	# 美杜莎之眼：任意敌方角色攻击时都可响应，不要求被攻击的是谁
	if attacker == null or attacker.color == player.color:
		return SUCCESS
	# 只能选与本次攻击牌同系的【暗月】
	var 合法暗月: Array = _mei_du_legal_covers(int(ctx.get("card_id", -1)))
	if 合法暗月.is_empty():
		return SUCCESS
	var 合法法术暗月: Array = []
	for cid: Variant in 合法暗月:
		var c: GCard = Data.get_card(int(cid))
		if c != null and c.is_magic():
			合法法术暗月.append(int(cid))
	var 敌人: Array = enemy_ids()
	if _mei_du_sha_step == 0:
		var 可选牌: Array = 合法暗月.duplicate()
		for cid: int in player.hand_cards:
			if not 可选牌.has(cid):
				可选牌.append(cid)
		if not engine.has_reply():
			# 手牌+盖牌同一步选：普通分支只要 1 张同系【暗月】；法术牌分支要
			# 1 张同系法术【暗月】+ 1 张手牌一起交上来，不再另开一次弃牌询问。
			询问(player.id, MEI_DU_SHA, 1, 0, GConst.CardSource.HandOrCover, [
				{"value": 1, "label": "移除 1 个【暗月】，+1【治疗】、+1【石化】",
					"enabled": true, "need_card": 1},
				{"value": 2, "label": "移除 1 个法术牌【暗月】并弃 1 张手牌，+1【治疗】、+1【石化】，对目标对手造成 1 点法术伤害",
					"enabled": not 合法法术暗月.is_empty() and not 敌人.is_empty() and not player.hand_cards.is_empty(),
					"need_card": 2, "need_target": 1, "targets": 敌人},
			], 1, "", 可选牌, true, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var cids: Array = r.get("card_ids", [])
		var 选择: int = int(args[0]) if not args.is_empty() else 0
		_md_hand = -1
		if 选择 == 1:
			if cids.size() != 1 or not 合法暗月.has(int(cids[0])):
				_mei_du_sha_step = 0
				return SUCCESS
			_md_card = int(cids[0])
			_md_dst = -1
		elif 选择 == 2:
			if cids.size() != 2:
				_mei_du_sha_step = 0
				return SUCCESS
			var 法术暗月: int = -1
			var 弃牌: int = -1
			for c: Variant in cids:
				var cid: int = int(c)
				if 法术暗月 < 0 and 合法法术暗月.has(cid):
					法术暗月 = cid
				elif 弃牌 < 0 and player.has_discard_card(cid):
					弃牌 = cid
			if 法术暗月 < 0 or 弃牌 < 0:
				_mei_du_sha_step = 0
				return SUCCESS
			var dsts: Array = r.get("dst_ids", [])
			if dsts.is_empty():
				_mei_du_sha_step = 0
				return SUCCESS
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			if dst == null or dst.color == player.color:
				_mei_du_sha_step = 0
				return SUCCESS
			_md_card = 法术暗月
			_md_hand = 弃牌
			_md_dst = dst.id
		else:
			_mei_du_sha_step = 0
			return SUCCESS
		notice_skill(MEI_DU_SHA, [src])
		施加治疗(player.id, 1)
		_add_token(1, 1)
		if _md_hand >= 0:
			# 和选目标同一步交上来的那张手牌，现在直接弃掉
			engine.take_from_hand(player.id, [_md_hand])
			engine.to_discard([_md_hand], {"owner": player.id, "source": "hand"})
			engine._log_discard(player.id, [_md_hand])
			_md_hand = -1
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


## 与攻击牌同系的【暗月】牌号（美杜莎之眼的可选范围）
func _mei_du_legal_covers(attack_card: int) -> Array:
	var atk: GCard = Data.get_card(attack_card)
	if atk == null:
		return []
	var 系: int = atk.element_enum()
	var out: Array = []
	for cid: Variant in player.cover_cards:
		var c: GCard = Data.get_card(int(cid))
		if c != null and c.element_enum() == 系:
			out.append(int(cid))
	return out


# ============================================================
# 月之轮回：回合结束时选择「移除 1 个【暗月】令目标 +1 治疗」或「移除 1 治疗换 1【新月】」
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	var 有暗月: bool = not player.cover_cards.is_empty()
	var 有治疗: bool = player.cross_num >= 1
	if not 有暗月 and not 有治疗:
		return SUCCESS
	if not engine.has_reply():
		# 两个选项永远都摆出来：没有对应资源的置灰；两个都点不动时上面已经提前返回
		询问(player.id, YUE_ZHI_LUN_HUI, 0, 0, GConst.CardSource.Cover, [
			{"value": 1, "label": "移除 1 张【暗月】：指定角色 +1【治疗】",
				"need_card": 1, "need_target": 1, "enabled": 有暗月},
			{"value": 2, "label": "耗 1 点【治疗】：+1【新月】指示物",
				"enabled": 有治疗},
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
		if cids.size() != 1 or dsts.size() != 1 or not player.有盖牌(int(cids[0])):
			return SUCCESS
		var dst: BattlePlayer = engine.p(int(dsts[0]))
		if dst == null:
			return SUCCESS
		notice_skill(YUE_ZHI_LUN_HUI, [dst.id])
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
# 月渎【回合限定】：你造成的法术伤害结算后，移除 1 治疗并对目标对手造成 1 点法术伤害
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
		询问(player.id, YUE_DU, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true, 0, -1, enemy_ids())
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null or dst.color == player.color:
		return SUCCESS
	notice_skill(YUE_DU, [dst.id])
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
	# 仅【暗月形态】（tap）下可发动；费用先扣水晶，没有水晶时用宝石替代（与其他必杀技一致）
	if not player.tap or player.get_energy() < 1 or player.cover_cards.is_empty():
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 暗月斩移除的是【暗月】（专属盖牌）：选牌来源必须是盖牌区，否则界面会亮手牌却选不出合法的牌。
		# card_max=2：X<3，只能移除 1~2 张。目标固定为本次攻击目标，随询问下发让头像自动选中；
		# preview_base＝加伤前的本次攻击伤害，客户端据此画「原伤害划掉 → +X 后伤害」。
		var 攻击目标: int = int(harm.get("dst", -1))
		询问(player.id, AN_YUE_ZHAN, 1, 0, GConst.CardSource.Cover, [], 2, "", [], true,
			0, -1, [攻击目标], -1, {}, int(harm.get("point", 0)), GConst.HarmType.Attack)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = []
	for c: Variant in r.get("card_ids", []):
		if player.有盖牌(int(c)) and not cards.has(int(c)):
			cards.append(int(c))
	if cards.is_empty() or cards.size() > 2:
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
		var dsts: Array = action.get("dst_ids", [])
		if dsts.is_empty():
			return GConst.GE_INVALID_PLAYERID
		var dst: BattlePlayer = engine.p(int(dsts[0]))
		if dst == null or dst.color == player.color:
			return GConst.GE_INVALID_PLAYERID
		# 弃 1 张牌必须由玩家自己选，且必须是真实手牌
		var cs: Array = action.get("card_ids", [])
		if cs.size() != 1 or not player.has_discard_card(int(cs[0])):
			return GConst.GE_INVALID_ACTION
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
		# 移除 3【石化】：额外 1 次攻击行动 + 额外回合；该次额外攻击无法应战
		# 标记属于技能释放，不放在额外行动进入时处理
		_add_token(1, -3)
		_cang_bai_attack = true
		player.add_action(GConst.ActionType.Attack, CANG_BAI_ZHI_YUE, true, true)
		_cang_bai_add_turn = true
		engine._broadcast_game()
		return SUCCESS
	if choice == 2:
		var x: int = int(args[1]) if args.size() > 1 else 0
		x = clampi(x, 1, int(player.tokens[0]["num"]))
		_add_token(0, -x)
		_add_token(1, 1)
		# 弃 1 张牌（玩家在发动时自己选的那张手牌）
		_discard_hand_cards(action.get("card_ids", []), 1)
		var dsts: Array = action.get("dst_ids", [])
		var dst: BattlePlayer = engine.p(int(dsts[0])) if not dsts.is_empty() else null
		if dst != null and dst.color != player.color:
			engine.push_harm({
				"src": player.id, "dst": dst.id, "point": 1 + x,
				"cause": CANG_BAI_ZHI_YUE, "type": GConst.HarmType.Magic,
			})
		engine._broadcast_game()
		return URGENT
	return SUCCESS


# ============================================================
# 玩家选择额外行动时（服务端 YueNv::p_additional_action）：
# 选中【苍白之月】授予的攻击行动则记为不可应战，其他选择一律清除
# ============================================================



func p_additional_action(_ctx: Dictionary) -> int:
	return SUCCESS


# ============================================================
# 额外回合（苍白之月第一分支）与回合限定的重置
# ============================================================
func p_after_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not _cang_bai_add_turn:
		return SUCCESS
	_cang_bai_add_turn = false
	# 对应原版：角色在这一步把 StateAfterTurnEnd 弹掉，让后面的 setStateCurrentPlayer(下家) 不再执行。
	# 本引擎等价做法：走引擎统一的「安排额外回合」；TurnBegin 由 SNextPlayer 统一广播一次，
	# 这里不能再发，否则同一次额外回合会下发两条「轮到你了」。
	player.clear_additional_action()
	engine.安排额外回合(player.id, 0, CANG_BAI_ZHI_YUE)
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
## 移除【暗月】并结算「暗月诅咒」：我方士气 -1；【暗月】为 0 时脱离【暗月形态】
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


## 弃掉玩家自己选中的 n 张手牌；不替玩家补牌（没选够时由 v_magic_skill 直接判无效）
func _discard_hand_cards(cards: Array, n: int) -> void:
	if n <= 0:
		return
	var chosen: Array = []
	for c: Variant in cards:
		if chosen.size() >= n:
			break
		if player.has_discard_card(int(c)) and not chosen.has(int(c)):
			chosen.append(int(c))
	if chosen.size() < n:
		return
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen, {"owner": player.id, "source": "hand"})
	engine._log_discard(player.id, chosen)

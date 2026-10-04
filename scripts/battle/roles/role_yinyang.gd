extends BattleRole
## 阴阳师（roleID 33）—— 移植自服务端 role/YinYang.cpp
## 指示物：tokens[0] = 鬼火（上限 3）
## 技能：式神咒束（3301，响应：队友被主动攻击时由自己代替其应战）※ 受限，见文末、
##       黑暗祭礼（3302，回合结束：鬼火达到上限时清空所有鬼火，对目标造成 2 点法术伤害）、
##       式神降临（3303，法术：弃 2 张同命格手牌 → +1 鬼火、横置进入式神形态、额外 +1 攻击行动）、
##       生命结界（3304，法术：耗 1 能量 → +1 鬼火，目标队友 +1 宝石 +1 治疗，
##                 然后对自己造成 X 点法术伤害（X 为鬼火数；X 为上限时该伤害不造成我方士气下降））、
##       式神转换（3305，与阴阳转换同时发动：+1 鬼火）、
##       阴阳转换（3306，响应：应战并把本次应战伤害改为自己的鬼火数）
##
## 受限说明：
## - 式神咒束（3301）的「代替队友应战」改由引擎 BattlePlayer.reattacker 实现：把自己的 id
##   写入队友的 reattacker，引擎在该队友被攻击时改问自己是否应战；应战成功后原攻击对队友
##   判定为未命中，并由自己向攻击者发起反击（服务端 popGameState + setStateReattack 的
##   应战状态重排由本引擎自动完成）。
## - 阴阳转换（3306）的「同命格应战」已由 v_reattack 覆写实现；
##   但服务端按弃牌系别判定「光系则视作【圣光】格挡」，本引擎格挡走 v_block（需【圣光】牌名），
##   角色无法改判，故该分支未实现。

const SHI_SHEN_ZHOU_SHU: int = 3301
const HEI_AN_JI_LI: int = 3302
const SHI_SHEN_JIANG_LIN: int = 3303
const SHENG_MING_JIE_JIE: int = 3304
const SHI_SHEN_ZHUAN_HUAN: int = 3305
const YIN_YANG_ZHUAN_HUAN: int = 3306

const TOKEN_GUI_HUO: int = 0
const TOKEN_GUI_HUO_MAX: int = 3

var gui_huo_atk: bool = false          # 本次应战伤害改为鬼火数


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_GUI_HUO] = {"name": "鬼火", "max": TOKEN_GUI_HUO_MAX, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if _has_same_property_pair():
		# 式神降临要弃 2 张同命格牌：card_rule="sameprop" 让界面选第 1 张后只亮同命格的牌
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHI_SHEN_JIANG_LIN, "need_card": 2, "need_target": 0,
			"card_rule": "sameprop"})
	if player.get_energy() >= 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_MING_JIE_JIE, "need_card": 0, "need_target": 1})
	return out


# ============================================================
# 指示物与工具
# ============================================================
func _gui_huo() -> int:
	var t: Dictionary = player.tokens[TOKEN_GUI_HUO]
	return int(t["num"])


func _set_gui_huo(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_GUI_HUO]
	t["num"] = clampi(v, 0, int(t["max"]))


## 手牌中是否存在 2 张同命格的牌（式神降临的条件）
func _has_same_property_pair() -> bool:
	for i: int in range(player.hand_cards.size()):
		var ci: GCard = Data.get_card(player.hand_cards[i])
		if ci == null:
			continue
		for j: int in range(i + 1, player.hand_cards.size()):
			var cj: GCard = Data.get_card(player.hand_cards[j])
			if cj != null and cj.property_enum() == ci.property_enum():
				return true
	return false


# ============================================================
# 攻击宣告（timeline_1 之前）：阴阳转换（3306）与应战伤害变化
# ============================================================
func p_attacked(ctx: Dictionary) -> int:
	var src_id: int = int(ctx.get("src", -1))
	if int(ctx.get("dst", -1)) == player.id:
		return _yin_yang_zhuan_huan(ctx)
	# 应战（阴阳转换）造成的伤害为鬼火数
	if src_id == player.id and gui_huo_atk:
		var harm: Dictionary = ctx.get("harm", {})
		harm["point"] = _gui_huo()
		gui_huo_atk = false
	return SUCCESS


## 阴阳转换：应战并把应战伤害改为鬼火数（若处于式神形态则脱离式神形态）
func _yin_yang_zhuan_huan(ctx: Dictionary) -> int:
	if int(ctx.get("hit_rate", GConst.HitRate.Normal)) != GConst.HitRate.Normal:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 选项值＝服务端的 args(0)：1=仅应战 / 2=应战+阴阳转换 / 3=应战+阴阳转换+式神转换
		询问(player.id, YIN_YANG_ZHUAN_HUAN, 1, 0, GConst.CardSource.Hand, [
			{"value": 1, "label": "仅应战"},
			{"value": 2, "label": "应战并发动阴阳转换（脱离式神形态，伤害改为鬼火数）"},
			{"value": 3, "label": "应战并发动阴阳转换，再发动式神转换（+1 鬼火）"},
		])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice <= 1:
		# 仅「应战」或放弃：实际应战由引擎常规应战询问处理（v_reattack 已放开同命格应战）
		return SUCCESS
	notice_skill(YIN_YANG_ZHUAN_HUAN, [player.id])
	if player.tap:
		player.tap = false
		gui_huo_atk = true
	if choice > 2:
		# 式神转换
		notice_skill(SHI_SHEN_ZHUAN_HUAN, [player.id])
		_set_gui_huo(_gui_huo() + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 应战校验覆写：阴阳转换（3306）放宽应战牌要求
# 对应服务端 YinYang::v_reattack：式神形态（player.tap）下，
# 弃 1 张与本次攻击牌同命格的攻击牌即可应战；
# 应战后新的攻击伤害由引擎 SAttackedAsk 用应战牌（即弃牌）重建，系别随之变为该牌的系别
# ============================================================
func v_reattack(card_id: int, attack_card_id: int) -> int:
	var base: int = player.base_v_reattack(card_id, attack_card_id)
	if base == GConst.GE_SUCCESS:
		return base
	# 仅式神形态可用（服务端的 tap 条件）
	if not player.tap:
		return base
	if not player.has_hand_card(card_id):
		return base
	var card: GCard = Data.get_card(card_id)
	var atk: GCard = Data.get_card(attack_card_id)
	if card == null or atk == null:
		return base
	# 暗系攻击不可应战（与服务端一致）
	if atk.element_enum() == GConst.CardElement.Darkness:
		return base
	if not card.is_attack() or card.property_enum() != atk.property_enum():
		return base
	return GConst.GE_SUCCESS


# ============================================================
# 应战成立后：用光系牌应战 → 视作格挡（本次攻击落空、不反击）
# 对应服务端 YinYangZhuanHuan：应战牌为光系时 setStateTimeline2Miss + setStateUseCard
# ============================================================
func p_reattack(ctx: Dictionary) -> int:
	if int(ctx.get("doer", -1)) != player.id:
		return SUCCESS
	var c: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if c == null or c.element_enum() != GConst.CardElement.Light:
		return SUCCESS
	ctx["block"] = true
	ctx["real"] = true
	return SUCCESS


# ============================================================
# 攻击应战阶段：式神咒束（3301）
# 对应服务端 YinYang::p_attacked 的式神咒束分支 + ShiShenZhouShu：
# 队友被主动攻击时，支付代价由自己代替其应战；可选同时发动阴阳转换
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	# 仅「队友被主动攻击」时发动（不含自己、不含由应战发起的反击）
	var dst_id: int = int(ctx.get("dst", -1))
	if dst_id == player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.color != player.color:
		return SUCCESS
	# 须处于式神形态，且命中率为普通；自身须有手牌可供应战
	if not player.tap:
		return SUCCESS
	if int(ctx.get("hit_rate", GConst.HitRate.Normal)) != GConst.HitRate.Normal:
		return SUCCESS
	if player.hand_cards.is_empty():
		return SUCCESS
	if not _can_pay_shi_shen_cost():
		return SUCCESS
	if not engine.has_reply():
		# 选项值＝服务端的 args(0)：1=仅式神咒束 / 2=+阴阳转换 / 3=+阴阳转换+1 鬼火
		询问(player.id, SHI_SHEN_ZHOU_SHU, 0, 0, GConst.CardSource.Hand, [
			{"value": 1, "label": "式神咒束：代替队友应战"},
			{"value": 2, "label": "式神咒束 + 阴阳转换（脱离式神形态，伤害改为鬼火数）"},
			{"value": 3, "label": "式神咒束 + 阴阳转换 + 式神转换（+1 鬼火）"},
		])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice <= 0:
		return SUCCESS
	return _shi_shen_zhou_shu(dst, choice)


## 式神咒束分支结算：1=正常应战 / 2=+阴阳转换 / 3=+阴阳转换+1 鬼火
## （服务端 case 1/2/3：仅 2/3 分支脱离式神形态并置「应战伤害改为鬼火数」）
func _shi_shen_zhou_shu(dst: BattlePlayer, choice: int) -> int:
	notice_skill(SHI_SHEN_ZHOU_SHU, [dst.id])
	if choice >= 2:
		notice_skill(YIN_YANG_ZHUAN_HUAN, [dst.id])
	_pay_shi_shen_cost()
	if choice >= 3:
		_set_gui_huo(_gui_huo() + 1)
	# 由自己代替队友应战：引擎在该队友被攻击时改问自己（伤害归属仍是队友）
	dst.reattacker = player.id
	if choice >= 2:
		# 复用阴阳转换标记：本次应战伤害改为自己的鬼火数，并脱离式神形态
		gui_huo_atk = true
		player.tap = false
	engine._broadcast_game()
	return SUCCESS


## 式神咒束的代价可否支付（战绩区）：1 水晶 + 1 宝石，或 2 宝石
## 对应服务端 team->getEnergy(color) > 1 && team->getGem(color) > 0
func _can_pay_shi_shen_cost() -> bool:
	var c: int = player.color
	return engine.team_gem[c] > 0 and engine.team_energy(c) > 1


func _pay_shi_shen_cost() -> void:
	var c: int = player.color
	if engine.team_crystal[c] > 0:
		engine.set_team_crystal(c, engine.team_crystal[c] - 1)
		engine.set_team_gem(c, engine.team_gem[c] - 1)
	else:
		engine.set_team_gem(c, engine.team_gem[c] - 2)


# ============================================================
# 回合结束：黑暗祭礼（3302）
# ============================================================
## 【黑暗祭礼】的推进阶段（0＝还没开始 / HEI_AN_JI_LI＝已清零鬼火、等回复）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问；
## 本流程在询问前就把鬼火清零（与服务端一致），若 step 被抹掉会退回第 0 步、被入口条件挡下，
## 2 点法术伤害与「脱离式神形态」整条不生效。每回合结束都可能触发，收尾清回 0
var _ji_li_step: int = 0


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 本次黑暗祭礼已结算：URGENT 回来后引擎会用同一 ctx 再进本钩子，直接挡掉，别重复询问/重复伤害
	if bool(ctx.get("ji_li_settled", false)):
		return SUCCESS
	if _ji_li_step >= STEP_DONE:
		return SUCCESS
	# 入口条件（鬼火满）只在第 0 步判：本条流程在询问前就把鬼火清零（与服务端一致），
	# 之后重入（等回复回来时会再进一次本钩子）不能再用它当门槛，
	# 否则 2 点法术伤害与「脱离式神形态」整条不生效，回复还会残留
	if _ji_li_step == 0:
		if _gui_huo() < TOKEN_GUI_HUO_MAX:
			return SUCCESS
		# 服务端在询问前先把鬼火清零
		_set_gui_huo(0)
		notice_skill(HEI_AN_JI_LI, [player.id])
		engine._broadcast_game()
		_ji_li_step = HEI_AN_JI_LI
	if _ji_li_step == HEI_AN_JI_LI:
		if not engine.has_reply():
			# 式神形态下可以选「重置」脱离形态（服务端 respond->args(0) == 2）
			var 选项: Array = []
			if player.tap:
				选项 = [
					{"value": 1, "label": "对目标造成 2 点法术伤害"},
					{"value": 2, "label": "造成伤害并脱离式神形态"},
				]
			询问(player.id, HEI_AN_JI_LI, 0, 1, GConst.CardSource.Hand, 选项)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_ji_li_step = 0
		# 标记本次已结算，挡住 URGENT 回来时的重入（同一 ctx）
		ctx["ji_li_settled"] = true
		var dsts: Array = r.get("dst_ids", [])
		var args: Array = r.get("args", [])
		var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
		# 式神形态下选择「重置」则脱离式神形态
		var reset: bool = player.tap and (not args.is_empty()) and int(args[0]) == 2
		notice_skill(HEI_AN_JI_LI, [dst_id])
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": 2,
			"cause": HEI_AN_JI_LI, "type": GConst.HarmType.Magic,
		})
		if reset:
			player.tap = false
		engine._broadcast_game()
		return URGENT
	return SUCCESS


# ============================================================
# 生命结界（3304）：满鬼火时该次自伤不造成我方士气下降
# 服务端据 con->harm.cause == 3304 && 鬼火 == 3 判定（YinYang::p_before_lose_morale）；
# 引擎 lose_morale 的 ctx 提供「harm_cause」（最近一次伤害的 cause），故据此判定
# ============================================================
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("harm_cause", 0)) != SHENG_MING_JIE_JIE:
		return SUCCESS
	if _gui_huo() != TOKEN_GUI_HUO_MAX:
		return SUCCESS
	ctx["amount"] = 0
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
		SHI_SHEN_JIANG_LIN:
			if cards.size() != 2:
				return GConst.GE_INVALID_CARDID
			var c0: GCard = Data.get_card(int(cards[0]))
			var c1: GCard = Data.get_card(int(cards[1]))
			if c0 == null or c1 == null:
				return GConst.GE_INVALID_CARDID
			if c0.property_enum() != c1.property_enum():
				return GConst.GE_INVALID_CARDID
			if not player.has_hand_card(int(cards[0])) or not player.has_hand_card(int(cards[1])):
				return GConst.GE_INVALID_ACTION
		SHENG_MING_JIE_JIE:
			if player.get_energy() < 1:
				return GConst.GE_INVALID_ACTION
			if dsts.is_empty():
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHI_SHEN_JIANG_LIN:
			return _shi_shen_jiang_lin(action)
		SHENG_MING_JIE_JIE:
			return _sheng_ming_jie_jie(action)
	return GConst.GE_INVALID_ACTION


## 式神降临：弃 2 张同命格手牌 → +1 鬼火、横置、额外 +1 攻击行动
func _shi_shen_jiang_lin(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var use_cards: Array = [int(cards[0]), int(cards[1])]
	notice_skill(SHI_SHEN_JIANG_LIN, [player.id])
	_set_gui_huo(_gui_huo() + 1)
	player.add_action(GConst.ActionType.Attack, SHI_SHEN_JIANG_LIN, true)
	engine.set_tap(player.id, true)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": use_cards, "is_real": true,
	})
	engine.take_from_hand(player.id, use_cards, true)
	engine.to_discard(use_cards)
	engine._broadcast_game()
	return URGENT


## 生命结界：耗 1 能量 → +1 鬼火，目标队友 +1 宝石 +1 治疗，自身受 X 点法术伤害
func _sheng_ming_jie_jie(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	notice_skill(SHENG_MING_JIE_JIE, [dst_id])
	_set_gui_huo(_gui_huo() + 1)
	if dst != null:
		dst.set_gem(dst.gem + 1)
		施加治疗(dst.id, 1)
	var point: int = _gui_huo()
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": point,
		"cause": SHENG_MING_JIE_JIE, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT

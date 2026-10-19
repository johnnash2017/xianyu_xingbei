extends BattleRole
## 阴阳师（roleID 33）—— 移植自服务端 role/YinYang.cpp
## 指示物：tokens[0] = 鬼火，上限见角色表
## 技能：式神咒束（3301，响应：队友被主动攻击时由自己代替其应战）※ 受限，见文末、
##       黑暗祭礼（3302，回合结束：鬼火达到上限时清空所有鬼火，对目标造成 2 点法术伤害）、
##       式神降临（3303，法术：弃 2 张同命格手牌 → +1 鬼火、横置进入式神形态、额外 +1 攻击行动）、
##       生命结界（3304，法术：耗 1 能量 → +1 鬼火，二选一：
##                 ① 目标队友 +1 宝石 +1 治疗，自己受 X 点法术伤害；
##                 ② 仅式神形态：弃 2 张同命格牌退出形态，目标队友弃 1 张牌）、
##       式神转换（3305，与阴阳转换同时发动：+1 鬼火）、
##       阴阳转换（3306，响应：应战并把本次应战伤害改为自己的鬼火数）
##
## 受限说明：
## - 式神咒束（3301）的「代替队友应战」改由引擎 BattlePlayer.reattacker 实现：把自己的 id
##   写入队友的 reattacker，引擎在该队友被攻击时改问自己是否应战；应战成功后原攻击对队友
##   判定为未命中，并由自己向攻击者发起反击（服务端 popGameState + setStateReattack 的
##   应战状态重排由本引擎自动完成）。
## - 阴阳转换（3306）的「同命格应战」由 v_reattack 实现：发动阴阳转换时不能用光系牌，
##   光系是格挡；不发动阴阳转换时，光系牌照常按普通格挡处理。

const SHI_SHEN_ZHOU_SHU: int = 3301
const HEI_AN_JI_LI: int = 3302
const SHI_SHEN_JIANG_LIN: int = 3303
const SHENG_MING_JIE_JIE: int = 3304
const SHI_SHEN_ZHUAN_HUAN: int = 3305
const YIN_YANG_ZHUAN_HUAN: int = 3306

const TOKEN_GUI_HUO: int = 0

## 阴阳转换已经选好、但还没选应战牌：选牌时放开同命格限制
var _yin_yang_pending: bool = false
## 本次阴阳转换同时发动了式神转换（摸 1 张 + 再 +1 鬼火）
var _shi_shen_pending: bool = false
## 应战牌选好后，在真正打出这次应战时结算 +鬼火 / 摸牌 / 退出形态
var _apply_yin_yang_after_use: bool = false
## 式神咒束已经宣告、还没选应战牌：选牌成功后才扣战绩区能量
var _shi_shen_zhou_shu_pending: bool = false


func available_skills() -> Array:
	var out: Array = []
	# 式神降临要弃 2 张同命格牌：card_rule="sameprop" 让界面选第 1 张后只亮同命格的牌。
	# 已经是式神形态（横置）时不能再开，必须等重置回普通形态。
	out.append({"type": GConst.ActionType.MagicSkill, "id": SHI_SHEN_JIANG_LIN, "need_card": 2, "need_target": 0,
		"card_rule": "sameprop", "enabled": not player.tap and _has_same_property_pair()})
	# 生命结界：两档效果；目标只能是队友。费用什么能量都行（水晶优先扣）。
	var 队友: Array[int] = ally_ids()
	out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_MING_JIE_JIE, "need_card": 0, "need_target": 1,
		"targets": 队友, "card_rule": "sameprop",
		"arg_choices": [
			{"text": 提示原文(SHENG_MING_JIE_JIE, 0), "args": [1],
				"enabled": player.get_energy() >= 1 and not 队友.is_empty()},
			{"text": 提示原文(SHENG_MING_JIE_JIE, 1), "args": [2], "need_card": 2,
				"enabled": player.tap and player.get_energy() >= 1 and _has_same_property_pair()},
		],
		"enabled": player.get_energy() >= 1 and not 队友.is_empty()})
	return out


# ============================================================
# 指示物与工具
# ============================================================
func _gui_huo() -> int:
	var t: Dictionary = player.tokens[TOKEN_GUI_HUO]
	return int(t["num"])


func _gui_huo_max() -> int:
	return int(player.tokens[TOKEN_GUI_HUO]["max"])


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
	var dst_id: int = int(ctx.get("dst", -1))
	# 自己被攻击：先问阴阳转换
	if dst_id == player.id:
		return _yin_yang_zhuan_huan(ctx)
	# 队友被攻击、自己已经用式神咒束代替他应战：接着问阴阳转换
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null and dst.reattacker == player.id:
		return _yin_yang_zhuan_huan(ctx)
	# 自己应战打出的这次反击：此时应战牌已经打出，结算 +鬼火 / 摸牌 / 退出形态
	var harm: Dictionary = ctx.get("harm", {})
	if src_id == player.id and _apply_yin_yang_after_use and bool(harm.get("reattack", false)):
		_结算阴阳转换后效(harm)
	return SUCCESS


## 阴阳转换：只选要不要发动；应战牌由引擎紧接着的应战询问选，只选一次
func _yin_yang_zhuan_huan(ctx: Dictionary) -> int:
	if int(ctx.get("hit_rate", GConst.HitRate.Normal)) != GConst.HitRate.Normal:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 选项值：1=仅应战 / 2=阴阳转换 / 3=阴阳转换+式神转换。
		# need_card=0：这里不选牌，避免和引擎随后的应战选牌重复
		询问(player.id, YIN_YANG_ZHUAN_HUAN, 0, 0, GConst.CardSource.Hand, [
			{"value": 1, "label": "仅应战"},
			{"value": 2, "label": "应战并发动阴阳转换（伤害改为鬼火数）"},
			{"value": 3, "label": "应战并发动阴阳转换，再发动式神转换（摸 1 张，+2 鬼火）"},
		])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice <= 1:
		return SUCCESS
	# 先记下选择；应战牌选好、真正打出后再加鬼火 / 摸牌 / 退出形态
	_yin_yang_pending = true
	_shi_shen_pending = choice > 2
	engine._broadcast_game()
	return SUCCESS


## 应战牌已经打出：按“先应战，再加鬼火，再退出形态”的顺序结算
func _结算阴阳转换后效(harm: Dictionary) -> void:
	notice_skill(YIN_YANG_ZHUAN_HUAN, [player.id])
	_set_gui_huo(_gui_huo() + 1)
	if _shi_shen_pending:
		notice_skill(SHI_SHEN_ZHUAN_HUAN, [player.id])
		# 【强制】摸 1 张：直接进手牌，保证这次应战结算完立刻能看到牌；
		# 不走 push_draw 的排队，避免被后面的应战 / 伤害流程压住
		engine.draw(player.id, 1)
		_set_gui_huo(_gui_huo() + 1)
	harm["point"] = _gui_huo()
	if player.tap:
		player.tap = false
	_apply_yin_yang_after_use = false
	_yin_yang_pending = false
	_shi_shen_pending = false
	_shi_shen_zhou_shu_pending = false
	engine._broadcast_game()


# ============================================================
# 应战校验覆写：阴阳转换（3306）放宽应战牌要求
# ============================================================
func v_reattack(card_id: int, attack_card_id: int) -> int:
	if _yin_yang_pending:
		if not player.has_hand_card(card_id):
			return GConst.GE_INVALID_CARDID
		var card: GCard = Data.get_card(card_id)
		var atk: GCard = Data.get_card(attack_card_id)
		if card == null or atk == null:
			return GConst.GE_INVALID_CARDID
		# 阴阳转换不能用光系牌：光系是格挡，不是应战
		if card.element_enum() == GConst.CardElement.Light:
			return GConst.GE_INVALID_CARDID
		if atk.element_enum() == GConst.CardElement.Darkness:
			return GConst.GE_INVALID_CARDID
		if not card.is_attack() or card.property_enum() != atk.property_enum():
			return GConst.GE_INVALID_CARDID
		return GConst.GE_SUCCESS
	return player.base_v_reattack(card_id, attack_card_id)


# ============================================================
# 应战牌选好后
# - 式神咒束：到这一步才扣战绩区能量
# - 阴阳转换：记下“打出后结算”，不在这里提前退出形态
# - 普通光系牌：视作格挡（不进行阴阳转换时的正常用法）
# ============================================================
func p_reattack(ctx: Dictionary) -> int:
	if int(ctx.get("doer", -1)) != player.id:
		return SUCCESS
	# 式神咒束的代价：选好合法应战牌后才扣，取消选牌不会白付
	if _shi_shen_zhou_shu_pending:
		if _can_pay_shi_shen_cost():
			_pay_shi_shen_cost()
		_shi_shen_zhou_shu_pending = false
	var c: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if _yin_yang_pending:
		# 光系牌在 v_reattack 已被挡掉；真走到这里就按普通格挡处理，不发动阴阳转换
		if c != null and c.element_enum() != GConst.CardElement.Light:
			_apply_yin_yang_after_use = true
			return SUCCESS
		_yin_yang_pending = false
		_shi_shen_pending = false
	if c != null and c.element_enum() == GConst.CardElement.Light:
		ctx["block"] = true
		ctx["real"] = true
	return SUCCESS


## 原攻击命中＝应战没成立（取消选牌 / 放弃）：清掉还没结算的待办，别留到下一次攻击
func p_timeline_2_hit(_ctx: Dictionary) -> int:
	_清空应战待办()
	return SUCCESS


func p_timeline_2_miss(_ctx: Dictionary) -> int:
	# 应战成功时原攻击会走 miss，此时 _apply_yin_yang_after_use 已置位，不能清
	if not _apply_yin_yang_after_use:
		_清空应战待办()
	return SUCCESS


func p_before_turn_begin(_ctx: Dictionary) -> int:
	_清空应战待办()
	return SUCCESS


func _清空应战待办() -> void:
	_yin_yang_pending = false
	_shi_shen_pending = false
	_apply_yin_yang_after_use = false
	_shi_shen_zhou_shu_pending = false


# ============================================================
# 攻击应战阶段：式神咒束（3301）
# 对应服务端 YinYang::p_attacked 的式神咒束分支 + ShiShenZhouShu：
# 队友被主动攻击时，由自己代替其应战；随后再问阴阳转换
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
	# 须处于式神形态，且命中率为普通；自身要有能打出的应战牌
	if not player.tap:
		return SUCCESS
	if int(ctx.get("hit_rate", GConst.HitRate.Normal)) != GConst.HitRate.Normal:
		return SUCCESS
	if not _has_legal_reattack_card(int(ctx.get("card_id", -1))):
		return SUCCESS
	if not _can_pay_shi_shen_cost():
		return SUCCESS
	if not engine.has_reply():
		# 只问「要不要用式神咒束」：没有选项，确定＝发动、取消＝不发动；
		# 阴阳转换 / 式神转换由紧接着的 p_attacked 再问
		询问(player.id, SHI_SHEN_ZHOU_SHU, 0, 0, GConst.CardSource.Hand, [])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice <= 0:
		step = STEP_DONE
		return SUCCESS
	notice_skill(SHI_SHEN_ZHOU_SHU, [dst.id])
	# 由自己代替队友应战；代价等应战牌选好后再扣（见 p_reattack）
	dst.reattacker = player.id
	_shi_shen_zhou_shu_pending = true
	# 让同一回合的 p_attacked 还能接着问阴阳转换
	step = 0
	engine._broadcast_game()
	return SUCCESS


## 手牌里有没有能应付这次攻击的牌：普通同系应战，或式神形态下同命格应战
func _has_legal_reattack_card(attack_card_id: int) -> bool:
	var atk: GCard = Data.get_card(attack_card_id)
	if atk == null:
		return false
	for cid: int in player.hand_cards:
		if player.base_v_reattack(cid, attack_card_id) == GConst.GE_SUCCESS:
			return true
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_attack():
			continue
		if atk.element_enum() == GConst.CardElement.Darkness:
			continue
		if card.element_enum() != GConst.CardElement.Light and card.property_enum() == atk.property_enum():
			return true
	return false


## 式神咒束的代价可否支付（战绩区）：1 水晶 + 1 宝石，或 2 宝石
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
## 【黑暗祭礼】的推进阶段（0＝还没开始 / HEI_AN_JI_LI＝等选目标）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问。
## 鬼火等选完目标后才清空；询问不能取消，超时由引擎自动选一名敌人。
var _ji_li_step: int = 0


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 本次黑暗祭礼已结算：URGENT 回来后引擎会用同一 ctx 再进本钩子，直接挡掉，别重复询问/重复伤害
	if bool(ctx.get("ji_li_settled", false)):
		return SUCCESS
	if _ji_li_step >= STEP_DONE:
		return SUCCESS
	if _ji_li_step == 0:
		if _gui_huo() < _gui_huo_max():
			return SUCCESS
		_ji_li_step = HEI_AN_JI_LI
	if _ji_li_step == HEI_AN_JI_LI:
		if not engine.has_reply():
			# 只选目标，没有别的选项；不能取消，超时由引擎从敌方里自动选一个目标
			询问(player.id, HEI_AN_JI_LI, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_ji_li_step = 0
		# 标记本次已结算，挡住 URGENT 回来时的重入（同一 ctx）
		ctx["ji_li_settled"] = true
		var dsts: Array = r.get("dst_ids", [])
		var dst_id: int = int(dsts[0]) if not dsts.is_empty() else -1
		if engine.p(dst_id) == null:
			dst_id = _随机敌人()
		if dst_id < 0:
			dst_id = player.id
		# 选完目标后才清空鬼火，再打目标 2 点法术伤害
		_set_gui_huo(0)
		notice_skill(HEI_AN_JI_LI, [dst_id])
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": 2,
			"cause": HEI_AN_JI_LI, "type": GConst.HarmType.Magic,
		})
		engine._broadcast_game()
		return URGENT
	return SUCCESS


## 黑暗祭礼超时兜底：随机一名敌人；没有敌人返回 -1
func _随机敌人() -> int:
	var ids: Array[int] = enemy_ids()
	return int(ids.pick_random()) if not ids.is_empty() else -1


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
	if _gui_huo() != _gui_huo_max():
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
			# 已经是式神形态时不能再开
			if player.tap:
				return GConst.GE_INVALID_ACTION
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
			if dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			# 目标只能是队友（不含自己）
			if dst == null or dst.id == player.id or dst.color != player.color:
				return GConst.GE_INVALID_PLAYERID
			var args: Array = action.get("args", [])
			var opt: int = int(args[0]) if not args.is_empty() else 1
			if opt == 2:
				if not player.tap or cards.size() != 2:
					return GConst.GE_INVALID_CARDID
				var a0: GCard = Data.get_card(int(cards[0]))
				var a1: GCard = Data.get_card(int(cards[1]))
				if a0 == null or a1 == null or a0.property_enum() != a1.property_enum():
					return GConst.GE_INVALID_CARDID
				if not player.has_hand_card(int(cards[0])) or not player.has_hand_card(int(cards[1])):
					return GConst.GE_INVALID_ACTION
			elif opt != 1:
				return GConst.GE_INVALID_ARGUMENT
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


## 生命结界第二档：目标队友弃 1 张牌（等这一步跨一次询问）
var _sheng_ming_step: int = 0
var _sheng_ming_dst: int = -1


## 生命结界：耗 1 能量 → +1 鬼火，然后二选一：
##   1. 目标队友 +1 宝石 +1 治疗；自己受 X 点法术伤害
##   2. 仅式神形态：弃 2 张同命格牌【展示】，重置脱离形态；目标队友弃 1 张牌
func _sheng_ming_jie_jie(action: Dictionary) -> int:
	if _sheng_ming_step != 0:
		# 第二档：等目标队友弃牌
		var back: Dictionary = take_skill_reply_full()
		var want_ids: Array = back.get("card_ids", [])
		var victim: BattlePlayer = engine.p(_sheng_ming_dst)
		var chosen: Array = []
		if victim != null:
			for cid: Variant in want_ids:
				var id: int = int(cid)
				if victim.has_hand_card(id) and not chosen.has(id):
					chosen.append(id)
					if chosen.size() >= 1:
						break
			if chosen.is_empty() and not victim.hand_cards.is_empty():
				chosen.append(int(victim.hand_cards[0]))
			if not chosen.is_empty():
				engine.take_from_hand(victim.id, chosen)
				engine.to_discard(chosen)
				engine._log_discard(victim.id, chosen)
		_sheng_ming_step = 0
		_sheng_ming_dst = -1
		engine._broadcast_game()
		return URGENT

	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	var args: Array = action.get("args", [])
	var opt: int = int(args[0]) if not args.is_empty() else 1
	# 费用：什么能量都行，水晶优先
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	notice_skill(SHENG_MING_JIE_JIE, [dst_id])
	_set_gui_huo(_gui_huo() + 1)

	if opt == 2:
		# 方案二：弃 2 张同命格牌，退出式神形态，再让目标队友弃 1 张
		var cards: Array = action.get("card_ids", [])
		var use_cards: Array = [int(cards[0]), int(cards[1])]
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": use_cards, "is_real": true,
		})
		engine.take_from_hand(player.id, use_cards, true)
		engine.to_discard(use_cards)
		engine._log_discard(player.id, use_cards)
		if player.tap:
			player.tap = false
		if dst != null and not dst.hand_cards.is_empty():
			_sheng_ming_step = 1
			_sheng_ming_dst = dst.id
			engine.ask_skill(dst.id, SHENG_MING_JIE_JIE, 1, 0, GConst.CardSource.Hand,
				[], 0, "", [], false, 提示原文(SHENG_MING_JIE_JIE, 2, {"n": 1}))
			engine._broadcast_game()
			return WAIT
		engine._broadcast_game()
		return URGENT

	# 方案一：目标队友 +1 宝石 +1 治疗；自己受 X 点法术伤害
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

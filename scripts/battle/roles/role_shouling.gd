extends BattleRole
## 兽灵武士（roleID 36）—— 移植自服务端 role/ShouLing.cpp
## 指示物：tokens[0] = 残心（上限 4）、tokens[1] = 兽魂（上限 2）
## 形态：tap（御魂流居合形态）
## 技能：武者残心（3601，响应：自己的攻击行动结束后 +1 残心（每回合一次））、
##       一击无念（3602，额外攻击行动：残心＞3 时移除 4 点残心，本次攻击无视圣盾与圣光，
##                 御魂流形态下再 +1 兽魂且技类攻击牌强制命中）、
##       兽魂意念（3603，被动：普通形态下主动攻击命中 +1 兽魂；每移除 1 点兽魂 +1 残心）、
##       兽魂警戒（3604，响应：其他角色横置时移除 1 点兽魂 → 横置并 +1 残心，目标弃 1 张牌）、
##       兽返（3605，响应：受到法术伤害时移除 X 点兽魂 → 自身弃 X 张牌，施害者弃 1 张牌）、
##       逆返居合斩（3606，响应：御魂流形态下对攻击前手牌＜4 的对手，命中后移除 X 点兽魂，
##                   抵御本次伤害并改为目标弃 X＋2 张手牌，不足则对方士气 -1）、
##       御魂流居合式（3607，启动：耗 1 宝石 → 横置进入御魂流居合形态并 +1 兽魂、摸或弃 1 张牌）、
##       形态附加：御魂流形态下攻击横置目标伤害 +1；造成伤害使其摸牌时脱离形态；回合结束移除 1 点兽魂

const WU_ZHE_CAN_XIN: int = 3601
const YI_JI_WU_NIAN: int = 3602
const SHOU_HUN_YI_NIAN: int = 3603
const SHOU_HUN_JING_JIE: int = 3604
const SHOU_FAN: int = 3605
const NI_FAN_ZHAN: int = 3606
const NI_FAN_HIT: int = 36062
const YU_HUN_BOOT: int = 3607

## 服务端的子状态编号（一击无念 / 御魂流居合形态的 step 标记）
const YI_JI_ATK: int = 36021
const YU_HUN_ATK: int = 36071

## 本引擎自有的分步标记（服务端把子步骤实现为压栈状态，此处只用 step 记录进度）
const SHOU_HUN_JING_JIE_DISCARD: int = 36041   # 兽魂警戒：请目标弃牌
const SHOU_FAN_TARGET_DISCARD: int = 36051     # 兽返：请施害者弃牌
const SHOU_FAN_SELF_DISCARD: int = 36052       # 兽返：自身弃牌
const NI_FAN_DISCARD: int = 36063              # 逆返居合斩：目标弃牌

const TOKEN_CAN_XIN: int = 0     # 残心（tokens[0]）
const TOKEN_SHOU_HUN: int = 1    # 兽魂（tokens[1]）
const CAN_XIN_MAX: int = 4
const SHOU_HUN_MAX: int = 2

const NI_FAN_TARGET_HAND: int = 4    # 逆返居合斩：对手手牌数须小于 4

var used_wu_zhe: bool = false        # 本回合是否已用【武者残心】
var yi_ji_atk: bool = false          # 本次攻击来自【一击无念】
var ni_fan_atk: bool = false         # 本次攻击已宣告【逆返居合斩】
var ni_fan_add_harm: int = 0         # 逆返居合斩额外移除的兽魂数 X

## 兽返的中间状态
var shou_fan_num: int = 0
var shou_fan_cards: Array = []


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_CAN_XIN] = {"name": "残心", "max": CAN_XIN_MAX, "num": 0}
	p.tokens[TOKEN_SHOU_HUN] = {"name": "兽魂", "max": SHOU_HUN_MAX, "num": 0}


## 兽灵武士的技能全部由钩子与启动流程触发
func available_skills() -> Array:
	return []


# ============================================================
# 指示物工具
# ============================================================
func _can_xin() -> int:
	var t: Dictionary = player.tokens[TOKEN_CAN_XIN]
	return int(t["num"])


func _shou_hun() -> int:
	var t: Dictionary = player.tokens[TOKEN_SHOU_HUN]
	return int(t["num"])


func _set_token(idx: int, v: int) -> void:
	var t: Dictionary = player.tokens[idx]
	t["num"] = clampi(v, 0, int(t["max"]))


## 移除 n 点兽魂并等量 +n 残心（兽魂意念：每移除 1 点兽魂 +1 残心）
func _remove_shou_hun(n: int) -> int:
	var real: int = mini(n, _shou_hun())
	_set_token(TOKEN_SHOU_HUN, _shou_hun() - real)
	_set_token(TOKEN_CAN_XIN, _can_xin() + real)
	return real


func _hand_card_count(pid: int) -> int:
	var p0: BattlePlayer = engine.p(pid)
	if p0 == null:
		return 0
	return p0.hand_cards.size()


# ============================================================
# 请某名角色弃 n 张牌（服务端 StateRequestHand；本引擎直接向其发起询问）
# 兽魂警戒 / 兽返下，若其弃掉的是法术牌则 +1 兽魂（服务端 p_show_hand）
# ============================================================
func _request_discard(pid: int, n: int, cause: int) -> int:
	var target: BattlePlayer = engine.p(pid)
	if target == null or n <= 0 or target.hand_cards.is_empty():
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(pid, cause, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var want: int = mini(n, target.hand_cards.size())
	var chosen: Array = _pick_cards(target, r.get("card_ids", []), want)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
		"card_ids": chosen, "is_real": true,
	})
	engine.take_from_hand(pid, chosen)
	engine.to_discard(chosen)
	if (cause == SHOU_HUN_JING_JIE or cause == SHOU_FAN) and not chosen.is_empty():
		var c: GCard = Data.get_card(int(chosen[0]))
		if c != null and c.is_magic():
			_set_token(TOKEN_SHOU_HUN, _shou_hun() + 1)
	engine._broadcast_game()
	return SUCCESS


## 从 ids 中挑出 n 张目标手牌（不足时按其手牌顺序补齐）
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


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_wu_zhe = false
	# 额外行动在回合开始时被清空，故一并清掉「一击无念」标记
	yi_ji_atk = false
	return SUCCESS


# ============================================================
# 攻击宣告后（timeline_1）：一击无念（3602）→ 御魂流形态伤害 +1 → 逆返居合斩（3606）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = YI_JI_WU_NIAN
	if step == YI_JI_WU_NIAN:
		_yi_ji_wu_nian(ctx)
		step = YI_JI_ATK
	if step == YI_JI_ATK:
		# 御魂流居合形态：攻击横置目标伤害 +1
		if player.tap:
			var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
			if dst != null and dst.tap:
				var harm: Dictionary = ctx.get("harm", {})
				harm["point"] = int(harm.get("point", 0)) + 1
		step = YU_HUN_ATK
	if step == YU_HUN_ATK:
		var r: int = _ni_fan_zhan(ctx)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 一击无念：本次攻击无视圣盾与圣光；御魂流形态下技类命格攻击牌强制命中
func _yi_ji_wu_nian(ctx: Dictionary) -> void:
	if not yi_ji_atk:
		return
	yi_ji_atk = false
	ctx["check_shield"] = false
	ctx["can_light"] = false
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card != null and card.property_enum() == GConst.CardProperty.Martial:
		ctx["hit_rate"] = GConst.HitRate.NoMiss


## 逆返居合斩：御魂流形态下对武前手牌＜4 的对手宣告，命中后改为弃牌
func _ni_fan_zhan(ctx: Dictionary) -> int:
	if not player.tap:
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	if _hand_card_count(dst_id) >= NI_FAN_TARGET_HAND:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, NI_FAN_ZHAN, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	ni_fan_atk = true
	notice_skill(NI_FAN_ZHAN, [dst_id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击命中后（timeline_2_hit）：兽魂意念（3603）→ 逆返居合斩·命中（36062）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SHOU_HUN_YI_NIAN
	if step == SHOU_HUN_YI_NIAN:
		# 普通形态下主动攻击命中：+1 兽魂
		if bool(ctx.get("is_active", false)) and not player.tap:
			_set_token(TOKEN_SHOU_HUN, _shou_hun() + 1)
			notice_skill(SHOU_HUN_YI_NIAN, [player.id])
			engine._broadcast_game()
		step = NI_FAN_HIT
	if step == NI_FAN_HIT:
		var r: int = _ni_fan_hit(ctx)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 逆返居合斩·命中：移除 X 点兽魂，本次攻击改为目标弃 X＋2 张手牌
func _ni_fan_hit(ctx: Dictionary) -> int:
	if not ni_fan_atk or _shou_hun() < 1:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, NI_FAN_HIT, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var howmany: int = int(args[1]) if args.size() > 1 else 0
	if howmany <= 0:
		return SUCCESS
	ni_fan_add_harm = _remove_shou_hun(howmany)
	notice_skill(NI_FAN_ZHAN, [int(ctx.get("dst", -1))])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 伤害结算前（timeline_4）：逆返居合斩改为「目标弃 X＋2 张牌」
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or not ni_fan_atk:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Attack:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	if step == 0:
		ni_fan_atk = false
		# 目标手牌不足以弃满时，对方士气 -1（服务端在弃牌状态前压入掉士气状态）
		if _hand_card_count(dst_id) < 2 + ni_fan_add_harm:
			var dst: BattlePlayer = engine.p(dst_id)
			if dst != null:
				engine.lose_morale(dst, 1, NI_FAN_ZHAN)
		step = NI_FAN_DISCARD
	if step == NI_FAN_DISCARD:
		var r: int = _request_discard(dst_id, 2 + ni_fan_add_harm, NI_FAN_ZHAN)
		if r == WAIT:
			return WAIT
		# 抵御本次攻击伤害（服务端 popGameState 取消后续结算）
		harm["point"] = 0
		ni_fan_add_harm = 0
		step = STEP_DONE
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 受到法术伤害时（timeline_3）：兽返（3605）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if _shou_hun() < 1:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SHOU_FAN
	if step == SHOU_FAN:
		if not engine.has_reply():
			engine.ask_skill(player.id, SHOU_FAN, 0, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty() or int(args[0]) != 1:
			step = STEP_DONE
			return SUCCESS
		var howmany: int = int(args[1]) if args.size() > 1 else 0
		shou_fan_num = _remove_shou_hun(howmany)
		shou_fan_cards = r.get("card_ids", [])
		if shou_fan_num <= 0:
			step = STEP_DONE
			return SUCCESS
		step = SHOU_FAN_TARGET_DISCARD
	if step == SHOU_FAN_TARGET_DISCARD:
		# 施害者弃 1 张牌
		var r2: int = _request_discard(int(harm.get("src", -1)), 1, SHOU_FAN)
		if r2 == WAIT:
			return WAIT
		step = SHOU_FAN_SELF_DISCARD
	if step == SHOU_FAN_SELF_DISCARD:
		var want: int = mini(shou_fan_num, player.hand_cards.size())
		if want > 0:
			var chosen: Array = _pick_cards(player, shou_fan_cards, want)
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": chosen, "is_real": true,
			})
			engine.take_from_hand(player.id, chosen)
			engine.to_discard(chosen)
		notice_skill(SHOU_FAN, [int(harm.get("src", -1))])
		step = STEP_DONE
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 其他角色横置（p_tap）：兽魂警戒（3604）
# ============================================================
func p_tap(ctx: Dictionary) -> int:
	if int(ctx.get("id", -1)) == player.id:
		return SUCCESS
	if not bool(ctx.get("tap", false)):
		return SUCCESS
	if _shou_hun() < 1 or player.tap:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SHOU_HUN_JING_JIE
	if step == SHOU_HUN_JING_JIE:
		if not engine.has_reply():
			engine.ask_skill(player.id, SHOU_HUN_JING_JIE, 0, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
			step = STEP_DONE
			return SUCCESS
		notice_skill(SHOU_HUN_JING_JIE, dsts)
		player.tap = true
		_remove_shou_hun(1)
		engine._broadcast_game()
		step = SHOU_HUN_JING_JIE_DISCARD
	if step == SHOU_HUN_JING_JIE_DISCARD:
		var r2: int = _request_discard(int(ctx.get("id", -1)), 1, SHOU_HUN_JING_JIE)
		if r2 == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


# ============================================================
# 攻击行动结束后（p_after_attack）：武者残心（3601）→ 残心＞3 时授予一击无念（3602）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = WU_ZHE_CAN_XIN
	if step == WU_ZHE_CAN_XIN:
		if not used_wu_zhe:
			if not engine.has_reply():
				engine.ask_skill(player.id, WU_ZHE_CAN_XIN, 0, 0)
				return WAIT
			if take_skill_reply():
				used_wu_zhe = true
				notice_skill(WU_ZHE_CAN_XIN, [player.id])
				_set_token(TOKEN_CAN_XIN, _can_xin() + 1)
				engine._broadcast_game()
		step = YI_JI_WU_NIAN
	if step == YI_JI_WU_NIAN:
		# 授予额外攻击行动；移除 4 点残心并开启一击无念改在玩家选择时结算
		if _can_xin() > CAN_XIN_MAX - 1:
			player.add_action(GConst.ActionType.Attack, YI_JI_WU_NIAN)
		step = STEP_DONE
	return SUCCESS


# ============================================================
# 玩家选择额外行动时：一击无念（移除 4 点残心并让本次攻击无视圣盾与圣光）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("cause", 0)) == YI_JI_WU_NIAN:
		_set_token(TOKEN_CAN_XIN, _can_xin() - 4)
		yi_ji_atk = true
		engine._broadcast_game()
	else:
		yi_ji_atk = false
	return SUCCESS


# ============================================================
# 造成伤害使其摸牌（p_timeline_6_drawn）：脱离御魂流居合形态
# ============================================================
func p_timeline_6_drawn(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or int(harm.get("point", 0)) <= 0:
		return SUCCESS
	if player.tap:
		player.tap = false
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 回合结束（p_turn_end）：御魂流居合形态移除 1 点兽魂并 +1 残心，兽魂归零则脱离形态
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not player.tap:
		return SUCCESS
	if _shou_hun() > 0:
		_set_token(TOKEN_SHOU_HUN, _shou_hun() - 1)
		_set_token(TOKEN_CAN_XIN, _can_xin() + 1)
	if _shou_hun() < 1:
		player.tap = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 启动（自己回合）：御魂流居合式（3607）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or player.tap or player.gem <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = YU_HUN_BOOT
	if not engine.has_reply():
		engine.ask_skill(player.id, YU_HUN_BOOT, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty():
		return SUCCESS
	var choose: int = int(args[0])
	if choose <= 0:
		return SUCCESS
	var howmany: int = int(args[1]) if args.size() > 1 else 0
	notice_skill(YU_HUN_BOOT, [player.id])
	player.tap = true
	player.set_gem(player.gem - 1)
	_set_token(TOKEN_SHOU_HUN, _shou_hun() + 1)
	if howmany > 0:
		if choose == 2:
			# 摸牌
			engine.draw(player.id, howmany)
		else:
			# 弃牌
			var want: int = mini(howmany, player.hand_cards.size())
			var chosen: Array = _pick_cards(player, r.get("card_ids", []), want)
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": chosen, "is_real": true,
			})
			engine.take_from_hand(player.id, chosen)
			engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS

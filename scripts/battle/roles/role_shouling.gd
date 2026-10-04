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
## 兽魂警戒选定的弃牌目标（跨 step 保留）
var jing_jie_dst: int = -1


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
	var want: int = mini(n, target.hand_cards.size())
	if not engine.has_reply():
		# 由玩家自己挑选要弃的牌（对照服务端 StateRequestHand 让玩家选满）；提示告诉他弃几张
		询问(pid, cause, want)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var chosen: Array = _pick_cards(target, r.get("card_ids", []), want)
	# 服务端这几处的 isShown：兽返 / 兽魂警戒 公开（顺带触发展示手牌钩子），
	# 逆返居合斩的目标弃牌是面朝下的（false），不能一起公开
	var 公开: bool = cause == SHOU_FAN or cause == SHOU_HUN_JING_JIE
	if 公开:
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
			"card_ids": chosen, "is_real": true,
		})
	engine.take_from_hand(pid, chosen, 公开)
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
		# 序号 1：这个技能号第 0 条提示是「叫别人弃牌」用的，自己发动这步留空走默认文案
		询问(player.id, NI_FAN_ZHAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true, 1)
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
		# 原版让玩家在提示区选「移除几点兽魂」，回 args=[1, 兽魂数]；通用客户端只回一维 args，
		# 不带 options 时读不到 args[1]。这里把「移除几点兽魂」做成 options（value=兽魂数，1..当前兽魂数）：
		# 本次询问不选牌不选目标 → 客户端弹居中选项窗，点某项回 args[0]=该值；取消/超时回 args[0]=0（不发动）
		var options: Array = []
		for n: int in range(1, _shou_hun() + 1):
			options.append({"value": n, "label": "移除 %d 点兽魂" % n})
		询问(player.id, NI_FAN_HIT, 0, 0, GConst.CardSource.Hand, options)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	# 选项 value 即要移除的兽魂数；0（取消/超时）视为不发动
	var howmany: int = int(args[0]) if not args.is_empty() else 0
	if howmany <= 0:
		return SUCCESS
	ni_fan_add_harm = _remove_shou_hun(howmany)
	notice_skill(NI_FAN_ZHAN, [int(ctx.get("dst", -1))])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 伤害结算前（timeline_4）：逆返居合斩改为「目标弃 X＋2 张牌」
# ============================================================
## 【逆返居合斩】的推进阶段（0＝还没开始 / NI_FAN_DISCARD＝等目标弃牌）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问；
## 本流程一开场就把 ni_fan_atk 清掉，若 step 被抹掉会退回第 0 步、被入口条件挡下，
## 「弃不满掉士气 + 抵御本次伤害」整段不生效。每次攻击都可能触发，收尾清回 0
var _ni_fan_step: int = 0


func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Attack:
		return SUCCESS
	if _ni_fan_step >= STEP_DONE:
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	# 入口条件（本次是逆返居合斩）只在第 0 步判：本条流程一开场就把 ni_fan_atk 清掉，
	# 之后重入（等回复回来时会再进一次本钩子）不能再用它当门槛，
	# 否则「弃不满掉士气 + 抵御本次伤害」整段不生效，回复还会残留
	if _ni_fan_step == 0:
		if not ni_fan_atk:
			return SUCCESS
		ni_fan_atk = false
		_ni_fan_step = NI_FAN_DISCARD
	if _ni_fan_step == NI_FAN_DISCARD:
		# 服务端先压掉士气、后压弃牌（LIFO）→ 先弃牌再掉士气；「弃不满」按弃牌前的手牌数判定
		var 弃不满: bool = _hand_card_count(dst_id) < 2 + ni_fan_add_harm
		var r: int = _request_discard(dst_id, 2 + ni_fan_add_harm, NI_FAN_ZHAN)
		if r == WAIT:
			return WAIT
		if 弃不满:
			var dst: BattlePlayer = engine.p(dst_id)
			if dst != null:
				engine.lose_morale(dst, 1, NI_FAN_ZHAN)
		# 抵御本次攻击伤害（服务端 popGameState 取消后续结算）
		harm["point"] = 0
		ni_fan_add_harm = 0
		_ni_fan_step = 0
		engine._broadcast_game()
	return SUCCESS


## 攻击未命中（timeline_2_miss）：清掉【逆返居合斩】宣告标记（服务端 ShouLing::p_timeline_2_miss）
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		ni_fan_atk = false
	return SUCCESS


# ============================================================
# 受到法术伤害时（timeline_3）：兽返（3605）
# ============================================================
## 【兽返】的推进阶段（0＝还没开始 / SHOU_FAN＝等选兽魂数 / SHOU_FAN_SELF_DISCARD＝自己弃牌 / SHOU_FAN_TARGET_DISCARD＝等施害者弃牌）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨两次询问，
## 中间自己弃牌会压入一轮手牌钩子 —— 那一轮开始时 step 被抹掉、流程退回第 0 步，
## 而兽魂此刻已经用掉，入口条件不成立 → 后半段整条不生效。每次受法术伤害都可能触发，收尾清回 0
var _shou_fan_step: int = 0


func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if _shou_fan_step >= STEP_DONE:
		return SUCCESS
	# 入口条件（身上还有兽魂）只在第 0 步判：本条流程中途会把兽魂用掉，
	# 之后重入（等回复回来时会再进一次本钩子）不能再用它当门槛，否则后半段整条不生效
	if _shou_fan_step == 0:
		if _shou_hun() < 1:
			return SUCCESS
		_shou_fan_step = SHOU_FAN
	if _shou_fan_step == SHOU_FAN:
		if not engine.has_reply():
			# 原版先选兽魂数、再弃等量手牌，回 args=[1, 兽魂数]。通用客户端只回一维 args，
			# 不带 options 时读不到 args[1]：把「兽魂数」做成 options（value=兽魂数，1..当前兽魂数）。
			# need_card=1 让客户端走「技能区选项按钮」而非居中弹窗（玩家要先选好手牌），
			# 选中的手牌仍由 card_ids 回传；点选项回 args[0]=兽魂数，取消/超时回 args[0]=0（不发动）。
			# 序号 1：第 0 条提示是「叫别人弃牌」用的，自己发动这步留空走默认文案
			var options: Array = []
			for n: int in range(1, _shou_hun() + 1):
				options.append({"value": n, "label": "移除 %d 点兽魂（弃 %d 张手牌）" % [n, n]})
			询问(player.id, SHOU_FAN, 1, 0, GConst.CardSource.Hand, options, player.hand_cards.size(), "", [], true, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		# 选项 value 即要移除的兽魂数（必 ≤ 当前兽魂数）；0（取消/超时）视为不发动
		var howmany: int = int(args[0]) if not args.is_empty() else 0
		if howmany <= 0:
			_shou_fan_step = 0
			return SUCCESS
		shou_fan_num = _remove_shou_hun(howmany)
		shou_fan_cards = r.get("card_ids", [])
		if shou_fan_num <= 0:
			_shou_fan_step = 0
			return SUCCESS
		# 服务端先压施害者弃牌、后压自己弃牌（LIFO）→ 自己先弃，再让施害者弃
		_shou_fan_step = SHOU_FAN_SELF_DISCARD
	if _shou_fan_step == SHOU_FAN_SELF_DISCARD:
		var want: int = mini(shou_fan_num, player.hand_cards.size())
		if want > 0:
			var chosen: Array = _pick_cards(player, shou_fan_cards, want)
			engine.take_from_hand(player.id, chosen)
			engine.to_discard(chosen)
		_shou_fan_step = SHOU_FAN_TARGET_DISCARD
	if _shou_fan_step == SHOU_FAN_TARGET_DISCARD:
		# 施害者弃 1 张牌
		var r2: int = _request_discard(int(harm.get("src", -1)), 1, SHOU_FAN)
		if r2 == WAIT:
			return WAIT
		notice_skill(SHOU_FAN, [int(harm.get("src", -1))])
		_shou_fan_step = 0
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 其他角色横置（p_tap）：兽魂警戒（3604）
# ============================================================
## 【兽魂警戒】的推进阶段（0＝还没开始 / SHOU_HUN_JING_JIE＝等指定谁弃牌 / SHOU_HUN_JING_JIE_DISCARD＝等目标弃牌）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨两次询问，
## 中间会把自己横置（压入一轮 p_tap 钩子）—— 那一轮开始时 step 被抹掉、流程退回第 0 步，
## 入口条件（自己没横置）此刻已不成立 → 「指定目标弃牌」那步整条不生效。每次他人横置都可能触发，收尾清回 0
var _jing_jie_step: int = 0


func p_tap(ctx: Dictionary) -> int:
	if int(ctx.get("id", -1)) == player.id:
		return SUCCESS
	if not bool(ctx.get("tap", false)):
		return SUCCESS
	if _jing_jie_step >= STEP_DONE:
		return SUCCESS
	# 入口条件（还有兽魂、自己没横置）只在第 0 步判：本条流程中途会把自己横置，
	# 之后重入（等回复回来时会再进一次本钩子）不能再用它当门槛，否则「指定目标弃牌」那步整条不生效
	if _jing_jie_step == 0:
		if _shou_hun() < 1 or player.tap:
			return SUCCESS
		_jing_jie_step = SHOU_HUN_JING_JIE
	if _jing_jie_step == SHOU_HUN_JING_JIE:
		if not engine.has_reply():
			# 序号 1：第 0 条提示是「叫别人弃牌」用的，这步「指定谁弃牌」读第 1 条
			询问(player.id, SHOU_HUN_JING_JIE, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
			_jing_jie_step = 0
			return SUCCESS
		notice_skill(SHOU_HUN_JING_JIE, dsts)
		jing_jie_dst = int(dsts[0])
		player.tap = true
		_remove_shou_hun(1)
		engine._broadcast_game()
		_jing_jie_step = SHOU_HUN_JING_JIE_DISCARD
	if _jing_jie_step == SHOU_HUN_JING_JIE_DISCARD:
		# 服务端由玩家指定的目标弃 1 张（不是被横置的那个角色）
		var 弃牌目标: int = jing_jie_dst if jing_jie_dst >= 0 else int(ctx.get("id", -1))
		var r2: int = _request_discard(弃牌目标, 1, SHOU_HUN_JING_JIE)
		if r2 == WAIT:
			return WAIT
		jing_jie_dst = -1
		_jing_jie_step = 0
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
				询问(player.id, WU_ZHE_CAN_XIN, 0, 0)
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
		# 原版 box 三项（1 弃 1 张牌、2 摸 1 张牌、3 启动但不调整），回 args=[选择, 数量]。
		# 通用客户端只回一维 args，不带 options 时读不到 args[1]：把三个分支做成 options（value=分支号），
		# 点选项回 args[0]=分支号，取消回 args[0]=0（不发动，不扣宝石、不横置）。
		# need_card=1 让客户端走「技能区选项按钮」（弃牌分支要选 1 张手牌，由 card_ids 回传），
		# 序号 1（该技能提示列为空）避免 ask_text 抢占提示条、挡掉选项按钮的构建；
		# 手牌为空时不列「弃牌 / 不调整」两项，避免出现必被服务端补牌的空弃分支
		var options: Array = []
		if not player.hand_cards.is_empty():
			options.append({"value": 1, "label": "弃 1 张手牌"})
		options.append({"value": 2, "label": "摸 1 张牌"})
		if not player.hand_cards.is_empty():
			options.append({"value": 3, "label": "不调整"})
		询问(player.id, YU_HUN_BOOT, 1, 0, GConst.CardSource.Hand, options, 1, "", [], true, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	# args[0] 即选项 value（分支号）；0（取消/超时）视为不发动
	var choose: int = int(args[0]) if not args.is_empty() else 0
	if choose <= 0:
		return SUCCESS
	notice_skill(YU_HUN_BOOT, [player.id])
	player.tap = true
	player.set_gem(player.gem - 1)
	_set_token(TOKEN_SHOU_HUN, _shou_hun() + 1)
	# 分支 1＝弃 1 张手牌；2＝摸 1 张牌；3＝不调整（数量固定为 1，故不再从 args[1] 取）
	if choose == 1:
		var chosen: Array = _pick_cards(player, r.get("card_ids", []), 1)
		engine.take_from_hand(player.id, chosen)
		engine.to_discard(chosen)
	elif choose == 2:
		engine.draw(player.id, 1)
	engine._broadcast_game()
	return SUCCESS

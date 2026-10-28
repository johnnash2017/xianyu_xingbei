extends BattleRole
## 兽灵武士（roleID 36）—— 移植自服务端 role/ShouLing.cpp
## 指示物：tokens[0] = 残心（上限 4）、tokens[1] = 兽魂（上限 2）
## 形态：tap（横置）=【御魂流居合形态】
## 技能：
##   武者残心（3601）：自己的攻击行动结束时 +1 残心（当前实现：可选发动、每回合一次）
##   一击无念（3602）：攻击行动结束且残心 ≥4 时授予额外攻击行动；选它即移除 4 点残心，
##                    该次攻击无视【圣盾】、不能用【圣光】抵挡；攻击牌为技类命格时强制命中
##   兽魂意念（3603）：每移除 1 点兽魂 +1 残心；普通形态下主动攻击命中 +1 兽魂
##   兽魂警戒（3604）：其他角色横置结算完后，移除 1 点兽魂并横置（转御魂流居合形态），
##                    指定 1 名角色弃 1 张牌【展示】；弃的是法术牌则 +1 兽魂
##   兽返（3605）：受法术伤害时移除 X 点兽魂，自己弃 X 张牌，施害者弃 1 张牌【展示】；
##                施害者弃的是法术牌则 +1 兽魂
##   御魂流居合形态（3608，被动形态）：对横置目标攻击伤害 +1；回合结束移除 1 点兽魂
##                （等量 +1 残心），兽魂为 0 时脱离；造成伤害（Timeline6）时脱离
##   逆反居合斩（3606）：仅御魂流居合形态下、对手手牌 <4 时宣告；发动时移除 X 点兽魂（X 可为 0），
##                    命中后取消伤害、改为目标弃 X+2 张手牌（不可取消；超时自动按手牌顺序补弃；弃不满则对方士气 -1）
##   御魂流居合式（3607）：启动（技能栏按钮），耗 1 宝石；无视上限 +1【兽魂】，
##                    点了在二级栏里选摸或弃 1 张牌（也可不调整）；并横置转【御魂流居合形态】

const WU_ZHE_CAN_XIN: int = 3601
const YI_JI_WU_NIAN: int = 3602
const SHOU_HUN_YI_NIAN: int = 3603
const SHOU_HUN_JING_JIE: int = 3604
const SHOU_FAN: int = 3605
const NI_FAN_ZHAN: int = 3606
const YU_HUN_BOOT: int = 3607

## 服务端的子状态编号（一击无念 / 御魂流居合形态的 step 标记）
const YI_JI_ATK: int = 36021
const YU_HUN_ATK: int = 36071

## 本引擎自有的分步标记（服务端把子步骤实现为压栈状态，此处只用 step 记录进度）
const SHOU_HUN_JING_JIE_DISCARD: int = 36041   # 兽魂警戒：请目标弃牌
const SHOU_FAN_TARGET_DISCARD: int = 36051     # 兽返：请施害者弃牌
const SHOU_FAN_SELF_DISCARD: int = 36052       # 兽返：自身弃牌
const NI_FAN_DISCARD: int = 36063              # 逆反居合斩：等目标弃牌（步骤标记，无技能表行）

const TOKEN_CAN_XIN: int = 0     # 残心（tokens[0]）
const TOKEN_SHOU_HUN: int = 1    # 兽魂（tokens[1]）

## 一击无念的残心门槛与消耗（说明：移除 4 点【残心】）
const YI_JI_COST: int = 4
const NI_FAN_TARGET_HAND: int = 4    # 逆反居合斩：对手手牌数须小于 4

var used_wu_zhe: bool = false        # 本回合是否已用【武者残心】
var yi_ji_atk: bool = false          # 本次攻击来自【一击无念】
var ni_fan_atk: bool = false         # 本次攻击已宣告【逆反居合斩】
var ni_fan_add_harm: int = 0         # 逆反居合斩额外移除的兽魂数 X

## 兽返的中间状态
var shou_fan_num: int = 0
var shou_fan_cards: Array = []
## 兽魂警戒选定的弃牌目标（跨 step 保留）
var jing_jie_dst: int = -1


## 行动阶段可发动的技能：御魂流居合式（3607）为「启动」，不消耗本回合行动，
## 发动后引擎重新进入行动阶段让玩家继续本回合行动。
## 其余技能（武者残心 / 兽魂警戒 / 兽返 / 逆反居合斩…）都只能在对应时机由钩子询问，不上技能栏。
func available_skills() -> Array:
	var out: Array = []
	# 御魂流居合式：技能栏里安安静静摆一颗按钮，点了才在二级栏里选效果
	# （弃 1 张手牌 / 摸 1 张牌 / 不调整），不再在回合开始时自动弹询问。
	# need_card 给 0：弃不弃牌由选中那一项自带的 need_card 决定（只有弃牌项要 1 张）；
	# card_max 给 1：选中弃牌项后才放出手牌可选，且最多 1 张。
	# 已是【御魂流居合形态】（横置）或没有宝石时按钮照摆、置灰。
	out.append({"type": GConst.ActionType.SpecialSkill, "id": YU_HUN_BOOT,
		"need_card": 0, "card_max": 1, "need_target": 0,
		"arg_choices": _yu_hun_boot_choices(),
		"enabled": player.gem > 0 and not player.tap})
	return out


# ============================================================
# 指示物工具
# ============================================================
func _can_xin() -> int:
	var t: Dictionary = player.tokens[TOKEN_CAN_XIN]
	return int(t["num"])


func _can_xin_max() -> int:
	return int(player.tokens[TOKEN_CAN_XIN]["max"])


func _shou_hun() -> int:
	var t: Dictionary = player.tokens[TOKEN_SHOU_HUN]
	return int(t["num"])


func _set_token(idx: int, v: int) -> void:
	var t: Dictionary = player.tokens[idx]
	t["num"] = clampi(v, 0, int(t["max"]))


## 加 n 点兽魂：默认按上限封顶，但已经超过上限时（御魂流居合式无视上限加出来的）不往下压；
## 无视上限 时不封顶
func _gain_shou_hun(n: int, 无视上限: bool = false) -> void:
	var t: Dictionary = player.tokens[TOKEN_SHOU_HUN]
	var 新值: int = int(t["num"]) + n
	if not 无视上限:
		新值 = mini(新值, maxi(int(t["max"]), int(t["num"])))
	t["num"] = 新值


## 移除 n 点兽魂并等量 +n 残心（兽魂意念：每移除 1 点兽魂 +1 残心）。
## 兽魂可能高于上限，这里不走 _set_token，免得减完又被上限压回去
func _remove_shou_hun(n: int) -> int:
	var real: int = mini(n, _shou_hun())
	player.tokens[TOKEN_SHOU_HUN]["num"] = _shou_hun() - real
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
func _request_discard(pid: int, n: int, cause: int, 必须弃: bool = false) -> int:
	var target: BattlePlayer = engine.p(pid)
	if target == null or n <= 0 or target.hand_cards.is_empty():
		return SUCCESS
	var want: int = mini(n, target.hand_cards.size())
	if not engine.has_reply():
		# 由玩家自己挑选要弃的牌（对照服务端 StateRequestHand 让玩家选满）；提示告诉他弃几张。
		# 必须弃的（逆反居合斩）：不给取消，超时由下面的「补齐」兜底；提示条写的是「需要弃的总数」n，
		# 不是手里实际能弃的张数（want）—— 手牌不够时照样要让他看到差多少会掉士气
		if 必须弃:
			engine.ask_skill(pid, cause, want, 0, GConst.CardSource.Hand, [], 0, "", [], false,
				提示原文(NI_FAN_ZHAN, 0, {"n": n}))
		else:
			询问(pid, cause, want)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	# 「必须选满才能点确定」由客户端按 option_need_cards / need_card 挡住；这里只取真正选中的牌，不替他补
	var chosen: Array = _pick_cards(target, r.get("card_ids", []), want)
	if 必须弃 and chosen.size() < want:
		# 强制弃牌没有「少弃」的选项：超时 / 空回复时按手牌顺序补满
		for cid: int in target.hand_cards:
			if chosen.size() >= want:
				break
			if not chosen.has(cid):
				chosen.append(cid)
	# 服务端这几处的 isShown：兽返 / 兽魂警戒 公开（顺带触发展示手牌钩子），
	# 逆反居合斩的目标弃牌是面朝下的（false），不能一起公开
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
			_gain_shou_hun(1)
	engine._broadcast_game()
	return SUCCESS


## 只保留玩家真正选中的手牌；数量不足时不补牌（选不满本来就点不了「确定」，
## 见询问里各选项的 need_card / need_card 参数）。
## 这里不能按手牌顺序补齐 —— 那会把玩家没选的牌也一起弃掉
func _pick_cards(target: BattlePlayer, ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if target.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	return out


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_wu_zhe = false
	# 额外行动在回合开始时被清空，故一并清掉「一击无念」标记
	yi_ji_atk = false
	return SUCCESS


# ============================================================
# 攻击宣告后（timeline_1）：一击无念（3602）→ 御魂流居合形态伤害 +1 → 逆反居合斩（3606）
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


## 一击无念：本次攻击无视圣盾与圣光；御魂流居合形态下技类命格攻击牌强制命中
func _yi_ji_wu_nian(ctx: Dictionary) -> void:
	if not yi_ji_atk:
		return
	# 只认自己主动打出的那一次攻击：应战反击（is_active=false）不能吃这个加成，
	# 也不消耗标记（标记留到回合结束由 p_turn_end 清掉）
	if not bool(ctx.get("is_active", false)):
		return
	yi_ji_atk = false
	ctx["check_shield"] = false
	ctx["can_light"] = false
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card != null and card.fate_pattern_enum() == GConst.FatePattern.Martial:
		ctx["hit_rate"] = GConst.HitRate.NoMiss


## 逆反居合斩：御魂流居合形态下、对手手牌 <4 时宣告。
## 说明：发动①时就选好移除几点兽魂（X 可以为 0），命中②时才按 X+2 结算弃牌 —— 所以 X 在这里扣
func _ni_fan_zhan(ctx: Dictionary) -> int:
	if not player.tap:
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	if _hand_card_count(dst_id) >= NI_FAN_TARGET_HAND:
		return SUCCESS
	if not engine.has_reply():
		# 选项 value = X + 1：X 允许是 0，不能拿 0 当「不移除」用；取消/超时回 0＝不发动。
		# 序号 1：这个技能号第 0 条提示是「叫别人弃牌」用的
		var options: Array = []
		for x: int in range(0, _shou_hun() + 1):
			options.append({
				"value": x + 1,
				"label": "不移除兽魂，目标弃 2 张" if x == 0 else "移除 %d 点兽魂，目标弃 %d 张" % [x, x + 2],
			})
		# 本次攻击目标不是这边点头像选出来的，但指示器要把它自动选中并点亮（头像亮起），
		# 再在它头像上写「弃 X+2 张牌」—— 故把目标随询问下发
		# （need_target=0：客户端只当提示 / 点亮落点用，不让玩家改选）
		var 提示目标: Array = [dst_id] if dst_id >= 0 else []
		询问(player.id, NI_FAN_ZHAN, 0, 0, GConst.CardSource.Hand, options, 0, "", [], true, 1, -1, 提示目标)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var choose: int = int(args[0]) if not args.is_empty() else 0
	if choose <= 0:
		return SUCCESS
	ni_fan_add_harm = _remove_shou_hun(choose - 1)
	ni_fan_atk = true
	notice_skill(NI_FAN_ZHAN, [dst_id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击命中后（timeline_2_hit）：兽魂意念（3603）→ 逆反居合斩·命中（36062）
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
			_gain_shou_hun(1)
			notice_skill(SHOU_HUN_YI_NIAN, [player.id])
			engine._broadcast_game()
		step = STEP_DONE
	return SUCCESS


# ============================================================
# 伤害结算前（timeline_4）：逆反居合斩改为「目标弃 X＋2 张牌」
# ============================================================
## 【逆反居合斩】的推进阶段（0＝还没开始 / NI_FAN_DISCARD＝等目标弃牌）。
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
	# 入口条件（本次是逆反居合斩）只在第 0 步判：本条流程一开场就把 ni_fan_atk 清掉，
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
		var r: int = _request_discard(dst_id, 2 + ni_fan_add_harm, NI_FAN_ZHAN, true)
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


## 攻击未命中（timeline_2_miss）：清掉【逆反居合斩】宣告标记（服务端 ShouLing::p_timeline_2_miss）
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
			# 只列真弃得出来的档：手里的牌不够 X 张时，选了也是白选（「确定」永远点不亮）
			var 最多: int = mini(_shou_hun(), player.hand_cards.size())
			if 最多 <= 0:
				_shou_fan_step = 0
				return SUCCESS
			var options: Array = []
			for n: int in range(1, 最多 + 1):
				# need_card=n：选了这一项就要弃满 n 张才让点「确定」（服务端不再替他补牌）
				options.append({"value": n, "label": "移除 %d 点兽魂，弃 %d 张手牌" % [n, n], "need_card": n})
			# 伤害来源不是这边点头像选出来的，但指示器要在它头像上写「弃 1 张牌」；
			# need_target=0 时 targets 只当提示落点，头像点不动
			var 来源: int = int(harm.get("src", -1))
			var 提示目标: Array = [来源] if 来源 >= 0 else []
			询问(player.id, SHOU_FAN, 1, 0, GConst.CardSource.Hand, options, player.hand_cards.size(), "", [], true, 1, -1, 提示目标)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		# 选项 value 即要移除的兽魂数（必 ≤ 当前兽魂数）；0（取消/超时）视为不发动
		var howmany: int = int(args[0]) if not args.is_empty() else 0
		if howmany <= 0:
			_shou_fan_step = 0
			return SUCCESS
		# 「先弹选项」的询问在选好一项后会先发一条 partial：若玩家还没选满手牌就超时，
		# 超时兜底只带回选项值、不带牌。此时不能先把兽魂扣掉（会白扣 X 点却没有弃牌），
		# 先按要弃的张数校验选中的牌，不够就当作没发动
		shou_fan_cards = _pick_cards(player, r.get("card_ids", []), howmany)
		if shou_fan_cards.size() < howmany:
			_shou_fan_step = 0
			return SUCCESS
		shou_fan_num = _remove_shou_hun(howmany)
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
		# 残心已经到上限：+1 会被封顶吃掉，不再弹「加不加」的询问。
		# 但仍要继续走一击无念的授予判定（满残心本来就够 4 点）。
		if not used_wu_zhe and _can_xin() < _can_xin_max():
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
		if _can_xin() >= YI_JI_COST:
			player.add_action(GConst.ActionType.Attack, YI_JI_WU_NIAN)
		step = STEP_DONE
	return SUCCESS


# ============================================================
# 玩家选择额外行动时：一击无念（移除 4 点残心并让本次攻击无视圣盾与圣光）
# ============================================================
func extra_action_switchable(_cause: int) -> bool: return false


## 一击无念属于行动结束响应，和迅捷赐福合并成一次询问
func extra_action_is_response(cause: int) -> bool:
	return cause == YI_JI_WU_NIAN


func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("cause", 0)) == YI_JI_WU_NIAN:
		_set_token(TOKEN_CAN_XIN, _can_xin() - YI_JI_COST)
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
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 一击无念只对「选它换来的那次主动攻击」有效：额外行动被放弃 / 没用掉时，
	# 标记在回合结束一并作废，不能留到后面（更不能喂给应战反击）
	yi_ji_atk = false
	if not player.tap:
		return SUCCESS
	if _shou_hun() > 0:
		_remove_shou_hun(1)
	if _shou_hun() < 1:
		player.tap = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 启动：御魂流居合式（3607）—— 技能栏按钮，点了才在二级栏里选效果
# ============================================================
## 三个分支（二级技能栏）：1＝弃 1 张手牌、2＝摸 1 张牌、3＝不调整。
## 三项始终摆出来；手牌为空时只有「弃 1 张手牌」置灰，另外两项仍然可点。
func _yu_hun_boot_choices() -> Array:
	return [
		{"text": "弃 1 张手牌", "args": [1], "need_card": 1,
			"enabled": not player.hand_cards.is_empty()},
		{"text": "摸 1 张牌", "args": [2]},
		{"text": "不调整", "args": [3]},
	]


## 【御魂流居合式】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == YU_HUN_BOOT


## 校验：有宝石、未横置（不在【御魂流居合形态】）时才能发动；
## args[0] 是选项值（1 弃牌 / 2 摸牌 / 3 不调整）；选 1 时必须正好带 1 张自己的手牌
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != YU_HUN_BOOT:
		return GConst.GE_INVALID_ACTION
	if player.gem <= 0 or player.tap:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var choose: int = int(args[0]) if not args.is_empty() else 0
	if choose < 1 or choose > 3:
		return GConst.GE_INVALID_ARGUMENT
	if choose == 1:
		var cards: Array = action.get("card_ids", [])
		if cards.size() != 1 or not player.has_hand_card(int(cards[0])):
			return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


## 御魂流居合式结算：耗 1 宝石、无视上限 +1【兽魂】、横置转入【御魂流居合形态】；
## 分支 1 弃 1 张手牌、2 摸 1 张牌、3 不调整。
## 「启动」每回合只能发动一个：成功发动后置 boot_skill_used（引擎靠它置灰其余启动技能）
func p_special_skill(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var choose: int = int(args[0]) if not args.is_empty() else 0
	if choose < 1 or choose > 3:
		return SUCCESS
	# 选「弃 1 张」但没带牌（正常会被 v_special_skill 挡下）：当作不发动，不扣宝石 / 不横置
	var 弃牌: Array = []
	if choose == 1:
		弃牌 = _pick_cards(player, action.get("card_ids", []), 1)
		if 弃牌.is_empty():
			return SUCCESS
	notice_skill(YU_HUN_BOOT, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	# 说明：无视【兽魂】上限 +1
	_gain_shou_hun(1, true)
	player.tap = true
	# 分支 1＝弃 1 张手牌；2＝摸 1 张牌；3＝不调整
	if choose == 1:
		engine.take_from_hand(player.id, 弃牌)
		engine.to_discard(弃牌)
		engine._log_discard(player.id, 弃牌)
	elif choose == 2:
		engine.push_draw(player.id, 1)
	engine._broadcast_game()
	return SUCCESS

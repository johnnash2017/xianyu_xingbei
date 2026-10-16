extends BattleRole
## 暗杀者（roleID 5）—— 移植自服务端 role/AnSha.cpp
## 技能：
##   反噬（501）——【被动】你承受攻击伤害时，攻击你的对手摸 1 张牌【强制】（p_timeline_6_drawn）
##   水影（502）——【响应】除【特殊行动】外，当你摸牌前发动：弃 X 张水系牌【展示】；
##        若你处于【潜行】效果下，可额外弃 1 张法术牌【展示】（纯可选；不弃也照常发动）（p_before_draw）
##   潜行（503）——【启动·宝石】发动时在二级技能栏选「摸 1 张牌 / 不摸牌」，随后【横置】持续到你的下个行动阶段开始：
##        手牌上限 -1；你的主动攻击对方无法应战且伤害额外 +X（X 为你剩余的能量数）
##        （行动阶段点技能栏【潜行】启动、p_timeline_1 无法应战、p_timeline_2_hit 加伤、【潜行】结束时【重置】）
##
## 引擎限制说明：服务端潜行的「你不能成为主动攻击的目标」由 PlayerEntity.v_attack 调用 dst->v_attacked()
## 实现；本引擎已提供 v_attacked() 钩子，故该条已实现（见文件末尾）。
##
## 变通说明：服务端 ShuiYing() 只展示并弃掉所选水系牌、不改动其它结算（con 参数未使用），本实现与之一致。

const FAN_SHI: int = 501
const SHUI_YING: int = 502
const QIAN_XING: int = 503

const QIAN_XING_HAND_MINUS: int = 1

## 【潜行】二级技能栏「摸 1 张牌 / 不摸牌」两项的选项值（随「确定」上交的 args[0]）
const QIAN_XING_DRAW: int = 1
const QIAN_XING_NO_DRAW: int = 0

# ============================================================
# 行动阶段可发动的技能：潜行（503）为「启动」，不消耗行动
# （is_free_skill 认可，发动后引擎重新进入行动阶段让玩家继续本回合行动）
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	# 潜行：有宝石且未横置（未处于潜行）时才能发动（耗 1 宝石并横置）。
	# 「要不要先摸 1 张牌」在二级技能栏里随「确定」一起选（arg_choices）——
	# 点技能时就问，不再发动完再由服务端补问一次
	out.append({"type": GConst.ActionType.SpecialSkill, "id": QIAN_XING, "need_card": 0, "need_target": 0,
		"enabled": player.gem > 0 and not player.tap,
		"arg_choices": [
			{"text": "不摸牌", "args": [QIAN_XING_NO_DRAW]},
			{"text": "摸 1 张牌", "args": [QIAN_XING_DRAW]},
		]})
	return out


## 【潜行】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == QIAN_XING


# ============================================================
# 行动阶段入口（p_before_action）：结束上一次潜行（对照服务端 AnSha::p_before_action）
# ============================================================
func p_before_action(_ctx: Dictionary) -> int:
	# 本回合「拒绝虚弱」等已跳过行动阶段：服务端此时不跑 p_before_action，这里同样不结算
	# （潜行持续到「下个行动阶段开始」，被跳过的回合不算）
	if engine.skip_action_phase:
		return SUCCESS
	if engine.current_id != player.id:
		return SUCCESS
	# 潜行持续到「你的下个行动阶段开始」，即此刻先结束
	if player.tap:
		_qian_xing_end()
	return SUCCESS


# ============================================================
# 启动技能（行动阶段按钮）：潜行（503）
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验技能自身条件）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QIAN_XING:
		return GConst.GE_INVALID_ACTION
	# 无宝石或已处于潜行：不能发动
	if player.gem <= 0 or player.tap:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 潜行（启动）：要不要先摸 1 张牌由二级技能栏「摸 1 张牌 / 不摸牌」两项决定，
## 随「确定」一起上交（args[0]），服务端不再补问。
## 进入潜行必须排在摸牌之后 —— 否则摸牌前的【水影】响应会看到已横置的自己，
## 连带触发「额外弃 1 张法术牌」那半段（正常时机下水影只能走「弃 X 张水系牌」）。
func p_special_skill(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var 要摸牌: bool = not args.is_empty() and int(args[0]) == QIAN_XING_DRAW
	if 要摸牌:
		# 先压「进入潜行」、后压摸牌（状态栈后进先出）→ 摸牌先跑：其摸牌前的【水影】响应里
		# 自己尚未横置，只会走「弃 X 张水系牌」那半段，不会连带触发「额外弃 1 张法术牌」
		engine.push(BattleEngine.SHook.new("p_qian_xing_enter", {"player": player.id}, []))
		engine.push_draw(player.id, 1)
		return SUCCESS
	# 没选摸牌：直接进入潜行
	_qian_xing_enter()
	return SUCCESS


## 【潜行】的实际进入：耗 1 宝石并横置、手牌上限 -1（不消耗本回合行动）。
## 由 p_special_skill 直接调用，或经 p_qian_xing_enter 钩子在「先摸的那 1 张牌」结算完之后调用。
func _qian_xing_enter() -> void:
	notice_skill(QIAN_XING, [player.id])
	player.boot_skill_used = true
	player.tap = true
	player.set_gem(player.gem - 1)
	player.hand_cards_max = maxi(player.hand_cards_max - QIAN_XING_HAND_MINUS, 0)
	engine._broadcast_game()


## 摸完牌后进入潜行的钩子（仅本角色实现；由 p_special_skill 压栈，保证「摸牌 → 进入潜行」的时序）。
## 钩子轮次会对每个玩家的角色各调一次，故必须按 ctx 点名的那名玩家过滤 ——
## 否则同桌的另一个暗杀者也会被带着耗宝石、横置、手牌上限 -1（并因此被误判超限而要求弃牌）
func p_qian_xing_enter(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_qian_xing_enter()
	return SUCCESS


## 潜行结束：重置横置并还原手牌上限
func _qian_xing_end() -> void:
	player.tap = false
	player.hand_cards_max = player.hand_cards_max + QIAN_XING_HAND_MINUS
	engine._broadcast_game()


# ============================================================
# 攻击宣告后（p_timeline_1）：潜行中你的主动攻击对方无法应战
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if not player.tap:
		return SUCCESS
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	return SUCCESS


# ============================================================
# 命中后（p_timeline_2_hit）：潜行中你的主动攻击伤害额外 +X（X = 剩余能量）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or not player.tap:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Attack:
		return SUCCESS
	if engine.current_id != player.id:
		return SUCCESS
	harm["point"] = int(harm.get("point", 0)) + player.get_energy()
	return SUCCESS


# ============================================================
# 被攻击校验：潜行（横置）期间不能成为主动攻击的目标
# ============================================================
func v_attacked() -> int:
	if player.tap:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 【水影】的推进阶段（0＝还没开始 / 1＝已问「弃 X 张水系牌」基础 / 2＝已问「额外弃 1 张法术牌」）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己摸牌前（p_before_draw）触发一次，收尾清回 0，好让下一次摸牌前再次响应。
var _shui_ying_step: int = 0


# ============================================================
# 摸牌前（p_before_draw）：水影（除【特殊行动】外，当你摸牌前发动）
#   先弃 X 张水系牌【展示】（这一步取消 / 超时＝水影不发动）；
#   基础成立后，若你处于【潜行】效果下再问「是否额外弃 1 张法术牌」——额外弃纯可选：不弃 / 取消照常发动
# ============================================================
func p_before_draw(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 同一枚摸牌事件只接管一次；若另一次摸牌的响应还没收尾，本次直接跳过（避免嵌套）
	var 已接管: bool = bool(ctx.get("shui_ying_taken", false))
	if not 已接管 and _shui_ying_step != 0:
		return SUCCESS
	ctx["shui_ying_taken"] = true

	# 基础：弃 X 张水系牌【展示】（X＝1~手里的水系牌数）。
	# 手里一张水系牌都没有也照样问（对照原客户端 AnSha::ShuiYing：永远弹「是否发动水影？」，
	# 那时没有可点的牌，只能取消）；这种情况下白名单发「全禁」而不是空表 ——
	# 空表在协议里表示「不限制」，别的系手牌反而会亮起来
	if _shui_ying_step == 0:
		var 水牌: Array[int] = _水系手牌()
		var 白名单: Array = 水牌 if not 水牌.is_empty() else [GConst.手牌白名单_全禁]
		# need_card=1 保证至少弃 1 张；card_max=水系牌数 放宽点选上限
		询问(player.id, SHUI_YING, 1, 0, GConst.CardSource.Hand, [], 水牌.size(), "", 白名单, true, 0)
		_shui_ying_step = 1
		return WAIT
	# 基础回复：没弃水系牌＝取消 / 超时，水影不发动（额外的法术牌那步也就不问）
	if _shui_ying_step == 1:
		var r: Dictionary = take_skill_reply_full()
		var 弃水: Array = _有效水系牌(r.get("card_ids", []))
		if 弃水.is_empty():
			_shui_ying_step = 0
			return SUCCESS
		notice_skill(SHUI_YING, [player.id])
		_展示并弃(player.id, 弃水)
		# 基础成立后，若处于【潜行】效果下，再二次询问「是否额外弃 1 张法术牌」（纯可选）
		if player.tap:
			var 法术牌: Array[int] = magic_hand_ids()
			# 手里没有法术牌就跳过这一步，直接收尾
			if not 法术牌.is_empty():
				询问(player.id, SHUI_YING, 1, 0, GConst.CardSource.Hand, [], 1, "magic", 法术牌, true, 1)
				_shui_ying_step = 2
				return WAIT
		_shui_ying_step = 0
		return SUCCESS
	# 额外回复：选「是」＝选中 1 张法术牌；选「否 / 取消」＝未选，两者水影均已发动
	var r2: Dictionary = take_skill_reply_full()
	_shui_ying_step = 0
	var 弃法术: Array = _有效法术牌(r2.get("card_ids", []))
	if not 弃法术.is_empty():
		notice_skill(SHUI_YING, [player.id])
		_展示并弃(player.id, 弃法术)
	return SUCCESS


# ============================================================
# 承受伤害结算后（p_timeline_6_drawn）：反噬（攻击者摸 1 张牌）
# ============================================================
func p_timeline_6_drawn(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("type", -1)) != GConst.HarmType.Attack:
		return SUCCESS
	var src_id: int = int(harm.get("src", -1))
	if src_id < 0 or engine.p(src_id) == null:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	notice_skill(FAN_SHI, [src_id])
	engine.push_draw(src_id, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 手里能弃的水系牌（水影主效果的合法牌）
func _水系手牌() -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Water)


## 从回复的卡牌中筛出确实持有的水系牌
func _有效水系牌(ids: Array) -> Array:
	var out: Array = []
	for c: Variant in ids:
		var cid: int = int(c)
		if out.has(cid) or not player.has_hand_card(cid):
			continue
		var card: GCard = Data.get_card(cid)
		if card != null and card.element_enum() == GConst.CardElement.Water:
			out.append(cid)
	return out


## 从回复的卡牌中筛出确实持有的法术牌（潜行下水影的额外弃牌）
func _有效法术牌(ids: Array) -> Array:
	var out: Array = []
	for c: Variant in ids:
		var cid: int = int(c)
		if out.has(cid) or not player.has_hand_card(cid):
			continue
		var card: GCard = Data.get_card(cid)
		if card != null and card.is_magic():
			out.append(cid)
	return out


## 展示并弃掉若干张手牌（带【展示】）：take_from_hand 会顺带压「展示手牌」钩子（封印师的水/火封印等）
func _展示并弃(pid: int, cards: Array) -> void:
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(pid, cards, true)
	engine.to_discard(cards)
	engine._broadcast_game()

extends BattleRole
## 暗杀者（roleID 5）—— 移植自服务端 role/AnSha.cpp
## 技能：
##   反噬（501）——【被动】你承受攻击伤害时，攻击你的对手摸 1 张牌【强制】（p_timeline_6_drawn）
##   水影（502）——【响应】任何人对你造成伤害时（③），弃 X 张水系牌【展示】以抵御 X 点该次伤害（p_timeline_3）
##   潜行（503）——【启动·宝石】持续到你的下个行动阶段开始：手牌上限 -1；你的主动攻击对方无法应战
##        且伤害额外 +X（X 为你剩余的能量数）（p_boot 启动、p_timeline_1 无法应战、p_timeline_2_hit 加伤）
##
## 引擎限制说明：服务端潜行的「你不能成为主动攻击的目标」由 PlayerEntity.v_attack 调用 dst->v_attacked()
## 实现；本引擎已提供 v_attacked() 钩子，故该条已实现（见文件末尾）。
##
## 变通说明：服务端 ShuiYing() 只做了「弃水系牌」而漏了扣减伤害（con 参数未使用），本实现按技能描述
## 补上「抵御 X 点伤害」，与服务端同类技能（如血色剑灵的血气屏障）一致。

const FAN_SHI: int = 501
const SHUI_YING: int = 502
const QIAN_XING: int = 503

const QIAN_XING_HAND_MINUS: int = 1

## 【潜行】的推进阶段（0＝还没开始 / QIAN_XING＝正在询问是否启动潜行）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合开始（p_boot）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _qian_xing_step: int = 0


# ============================================================
# 回合开始（p_boot）：结束上一次潜行，再决定是否重新潜行
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if _qian_xing_step >= STEP_DONE:
		return SUCCESS
	if _qian_xing_step == 0:
		# 潜行持续到「你的下个行动阶段开始」，即此刻先结束
		if player.tap:
			_qian_xing_end()
		_qian_xing_step = QIAN_XING
	if _qian_xing_step == QIAN_XING:
		var r: int = _qian_xing()
		if r == WAIT:
			return WAIT
		_qian_xing_step = 0
	return SUCCESS


## 潜行启动（消耗 1 宝石）
func _qian_xing() -> int:
	if player.gem <= 0:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, QIAN_XING, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(QIAN_XING, [player.id])
	player.tap = true
	player.set_gem(player.gem - 1)
	player.hand_cards_max = maxi(player.hand_cards_max - QIAN_XING_HAND_MINUS, 0)
	engine._broadcast_game()
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


## 【水影】的推进阶段（0＝还没开始 / 处理完本次水影后清回 0）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己承受伤害（p_timeline_3）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _shui_ying_step: int = 0


# ============================================================
# 承受伤害（p_timeline_3）：水影（弃 X 张水系牌抵御 X 点伤害）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if not _has_water_card():
		return SUCCESS
	if _shui_ying_step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 可以弃任意张水系手牌（X＝1~手里的水系牌数）：need_card=1 保证至少弃 1 张，
		# card_max=水系牌数 放宽点选上限（不给就默认「恰好 1 张」，只能弃 1 张）；
		# 下发白名单把其余手牌置灰，免得点了别的系提交后落空
		var 水牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Water)
		询问(player.id, SHUI_YING, 1, 0, GConst.CardSource.Hand, [], 水牌.size(), "", 水牌)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_shui_ying_step = 0
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = _valid_water_cards(r.get("card_ids", []))
	if cards.is_empty():
		return SUCCESS
	notice_skill(SHUI_YING, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards)
	# 服务端 ShuiYing 只展示并弃掉水系手牌，不抵消本次伤害
	engine._broadcast_game()
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
	engine.draw(src_id, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _has_water_card() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == GConst.CardElement.Water:
			return true
	return false


## 从回复的卡牌中筛出确实持有的水系牌
func _valid_water_cards(ids: Array) -> Array:
	var out: Array = []
	for c: Variant in ids:
		var cid: int = int(c)
		if out.has(cid) or not player.has_hand_card(cid):
			continue
		var card: GCard = Data.get_card(cid)
		if card != null and card.element_enum() == GConst.CardElement.Water:
			out.append(cid)
	return out

extends BattleRole
## 剑圣（roleID 1）—— 移植自服务端 role/JianSheng.cpp
## 技能：
##   疾风技（101，主动攻击牌带此特技时，额外 +1 攻击行动）
##   烈风技（102，攻击目标拥有圣盾或天使之墙时，无视其圣盾效果且对方无法应战）
##   连续技（103，回合限定，攻击行动结束时额外 +1 攻击行动）
##   圣剑（104，本回合第 3 次主动攻击强制命中）
##   剑影（105，回合限定，消耗 1 能量，攻击行动结束时额外 +1 攻击行动）
##
## v_attack 覆写：服务端 JianSheng::v_attack 限制「连续技」额外攻击只能用风系攻击牌
## （服务端在 p_additional_action 里置 using_LianXuJi，其余额外行动清除），此处对应为 using_lian_xu_ji。

const JI_FENG_JI: int = 101
const LIE_FENG_JI: int = 102
const LIAN_XU_JI: int = 103
const SHENG_JIAN: int = 104
const JIAN_YING: int = 105

var used_lian_xu_ji: bool = false
var used_jian_ying: bool = false
var using_lian_xu_ji: bool = false
var attack_count: int = 0


## 每回合开始：重置回合限定标记与圣剑计数
func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_lian_xu_ji = false
	used_jian_ying = false
	using_lian_xu_ji = false
	attack_count = 0
	return SUCCESS


## 【烈风技 / 疾风技 / 圣剑】的推进阶段（0＝还没开始 / LIE_FENG_JI＝在问烈风技 / JI_FENG_JI＝结算疾风技 / SHENG_JIAN＝结算圣剑）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0


# ============================================================
# 攻击宣告后（timeline_1）：烈风技 → 疾风技 → 圣剑
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	if _timeline_1_step == 0:
		_timeline_1_step = LIE_FENG_JI
	if _timeline_1_step == LIE_FENG_JI:
		var r: int = _lie_feng_ji(ctx)
		if r == WAIT:
			return WAIT
		_timeline_1_step = JI_FENG_JI
	if _timeline_1_step == JI_FENG_JI:
		_ji_feng_ji(ctx)
		_timeline_1_step = SHENG_JIAN
	if _timeline_1_step == SHENG_JIAN:
		_sheng_jian(ctx)
		_timeline_1_step = 0
	return SUCCESS


## 烈风技：目标拥有圣盾或天使之墙时，无视其圣盾效果且此攻击对方无法应战
func _lie_feng_ji(ctx: Dictionary) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(LIE_FENG_JI):
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		return SUCCESS
	if not dst.check_basic_effect_name(GConst.CardName.Shield) and not dst.check_basic_effect_skill(GConst.技能_天使之墙):
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, LIE_FENG_JI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(LIE_FENG_JI, [dst.id])
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	ctx["check_shield"] = false
	return SUCCESS


## 疾风技：作为主动攻击打出时，额外 +1 攻击行动
func _ji_feng_ji(ctx: Dictionary) -> void:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(JI_FENG_JI):
		return
	if not bool(ctx.get("is_active", false)):
		return
	notice_skill(JI_FENG_JI, [int(ctx.get("dst", -1))])
	player.add_action(GConst.ActionType.Attack, JI_FENG_JI, true)


## 圣剑：若本次行动阶段的第 3 次主动攻击，则此攻击强制命中
func _sheng_jian(ctx: Dictionary) -> void:
	if not bool(ctx.get("is_active", false)):
		return
	attack_count += 1
	if attack_count == 3:
		notice_skill(SHENG_JIAN, [int(ctx.get("dst", -1))])
		ctx["hit_rate"] = GConst.HitRate.NoMiss


# ============================================================
# 攻击行动结束时（after_attack）：连续技 → 剑影
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		_lian_xu_ji()
		step = JIAN_YING
	if step == JIAN_YING:
		_jian_ying()
		step = STEP_DONE
	return SUCCESS


## 连续技：回合限定，额外 +1 攻击行动（授予只挂行动，代价在玩家选中时结算）
func _lian_xu_ji() -> void:
	if player.hand_cards.is_empty() or used_lian_xu_ji or _contains_action(LIAN_XU_JI):
		return
	player.add_action(GConst.ActionType.Attack, LIAN_XU_JI, true)


## 剑影：回合限定，额外 +1 攻击行动（授予只挂行动，代价在玩家选中时结算）
func _jian_ying() -> void:
	if player.hand_cards.is_empty() or player.get_energy() <= 0:
		return
	if used_jian_ying or _contains_action(JIAN_YING):
		return
	player.add_action(GConst.ActionType.Attack, JIAN_YING)


# ============================================================
# 玩家选中额外行动时的二次校验（服务端 JianSheng::v_additional_action）：
# 连续技本回合限一次；剑影本回合限一次且需仍有能量
# ============================================================
func v_additional_action(cause: int) -> int:
	if cause == LIAN_XU_JI:
		if used_lian_xu_ji:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if cause == JIAN_YING:
		if used_jian_ying or player.get_energy() <= 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return V_NOT_OVERRIDE


# ============================================================
# 玩家选中额外行动时：结算连续技/剑影的代价
# 引擎在选中时会统一广播技能通知，故此处只处理回合限定标记与能量扣除
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var cause: int = int(ctx.get("cause", 0))
	# 对照服务端 p_additional_action：仅选中「连续技」时置位，其余额外行动一律清除
	using_lian_xu_ji = cause == LIAN_XU_JI
	if cause == LIAN_XU_JI:
		used_lian_xu_ji = true
	elif cause == JIAN_YING:
		used_jian_ying = true
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 牌类校验覆写：连续技（103）额外攻击行动期间只能用风系攻击牌
# （对照服务端 JianSheng::v_attack；using_lian_xu_ji 由 p_additional_action 置位/清除）
# ============================================================
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	var rc: int = player.base_v_attack(card_id, dst_id, players)
	if rc != GConst.GE_SUCCESS:
		return rc
	if using_lian_xu_ji:
		var card: GCard = Data.get_card(card_id)
		if card.element_enum() != GConst.CardElement.Wind:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


# ============================================================
# 工具
# ============================================================
## 是否已挂有某来源的额外行动
func _contains_action(cause: int) -> bool:
	for a: Dictionary in player.additional_actions:
		if int(a.get("cause", -1)) == cause:
			return true
	return false

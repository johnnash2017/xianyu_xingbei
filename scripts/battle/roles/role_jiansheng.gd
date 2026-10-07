extends BattleRole
## 剑圣（roleID 1）—— 移植自服务端 role/JianSheng.cpp
## 技能：
##   疾风技（101，攻击技能：选一张带此特技的攻击牌发起主动攻击，发动后额外 +1 攻击行动）
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


## 行动阶段可发动的技能：【疾风技】【烈风技】为「攻击技能」——选一张带对应特技的攻击牌 + 一名对手，
## 直接发起这次主动攻击（攻击宣告后 p_timeline_1 依据预选直接结算，不再弹窗询问）
## 【疾风技 / 烈风技】不再提供技能栏按钮：只能在主动攻击时响应发动（原版如此），
## 故这里不再覆写 available_skills（基类默认返回空）


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

## 本次主动攻击预选的「攻击技能」号（0＝普通攻击）：由 p_attack_skill 在发起攻击前写入，
## p_timeline_1 的【疾风技】一段据此判断是否发动（101），用完即清。
## 与 _timeline_1_step 相互独立：后者推进 102→101→104 的链，前者只标记本次攻击是否由技能栏发起。
var _预选攻击技能: int = 0


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
		var r: int = _ji_feng_ji(ctx)
		if r == WAIT:
			return WAIT
		_timeline_1_step = SHENG_JIAN
	if _timeline_1_step == SHENG_JIAN:
		_sheng_jian(ctx)
		_timeline_1_step = 0
	return SUCCESS


## 烈风技：目标拥有圣盾或天使之墙时，无视其圣盾效果且此攻击对方无法应战。
## 技能栏按钮发起（预选命中）→ 直接结算；普通出牌攻击 → 原版弹窗询问
func _lie_feng_ji(ctx: Dictionary) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(LIE_FENG_JI):
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		return SUCCESS
	if not dst.check_basic_effect_name(GConst.CardName.Shield) and not dst.check_basic_effect_skill(GConst.技能_天使之墙):
		return SUCCESS
	if _预选攻击技能 == LIE_FENG_JI:
		_应用烈风技(ctx, dst)
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, LIE_FENG_JI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	_应用烈风技(ctx, dst)
	return SUCCESS


## 烈风技的结算：本次攻击无视目标圣盾，且对方无法应战
func _应用烈风技(ctx: Dictionary, dst: BattlePlayer) -> void:
	notice_skill(LIE_FENG_JI, [dst.id])
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	ctx["check_shield"] = false


## 疾风技：本次主动攻击由技能栏的【疾风技】按钮发起（预选 == 101）时直接结算，额外 +1 攻击行动；
## 普通出牌攻击（预选为 0）则按原版流程弹窗询问是否发动，同意才加额外攻击行动。
## （额外行动本身设 direct：直接进入额外攻击阶段，不再二次追问，想跳过在那里「放弃行动」）
func _ji_feng_ji(ctx: Dictionary) -> int:
	var 预选: int = _预选攻击技能
	_预选攻击技能 = 0
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(JI_FENG_JI):
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if 预选 == JI_FENG_JI:
		notice_skill(JI_FENG_JI, [int(ctx.get("dst", -1))])
		player.add_action(GConst.ActionType.Attack, JI_FENG_JI, true)
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, JI_FENG_JI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(JI_FENG_JI, [int(ctx.get("dst", -1))])
	player.add_action(GConst.ActionType.Attack, JI_FENG_JI, true)
	return SUCCESS


## 圣剑：若本次行动阶段的第 3 次主动攻击，则此攻击强制命中
func _sheng_jian(ctx: Dictionary) -> void:
	if not bool(ctx.get("is_active", false)):
		return
	attack_count += 1
	if attack_count == 3:
		notice_skill(SHENG_JIAN, [int(ctx.get("dst", -1))])
		ctx["hit_rate"] = GConst.HitRate.NoMiss


# ============================================================
# 疾风技（101，攻击技能）：选一张带 101 特技的攻击牌 + 一名对手，直接发起一次主动攻击
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	if aid != JI_FENG_JI and aid != LIE_FENG_JI:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	# 所选牌必须是手里的攻击牌且带对应特技（101 疾风技 / 102 烈风技）
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_attack() or not card.has_skill_id(aid):
		return GConst.GE_INVALID_ACTION
	# 复用通用主动攻击校验（持有该攻击牌、目标不同队、面前【挑衅】限制等）
	if player.v_attack(cid, dst_id, engine.players) != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	# 烈风技：目标身上必须有【圣盾】或视作圣盾的【天使之墙】
	if aid == LIE_FENG_JI and not dst.check_basic_effect_name(GConst.CardName.Shield) \
			and not dst.check_basic_effect_skill(GConst.技能_天使之墙):
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 疾风技 / 烈风技：打出所选攻击牌发起一次主动攻击。
## 回合结束由引擎的技能行动入栈（与普通技能一致），这里只补这次攻击本身；
## 攻击宣告后 p_timeline_1 的对应一段会依据 _预选攻击技能 直接结算（不再弹窗询问）
func p_attack_skill(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	_预选攻击技能 = int(action.get("action_id", 0))
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": BattleEngine.ATTACK_BASE_POINT, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": cid, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, cid, harm))
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true,
	})
	return URGENT


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


## 风怒追击（103）：回合限定，额外 +1 攻击行动。
## 只挂行动、不置 direct —— 好让引擎在攻击行动结束后统一问「是否发动」；
## 能不能发动（手里有没有风系攻击牌）由 v_additional_action 判定，客户端据此把「确定」置灰
func _lian_xu_ji() -> void:
	if used_lian_xu_ji or _contains_action(LIAN_XU_JI):
		return
	player.add_action(GConst.ActionType.Attack, LIAN_XU_JI)


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
		# 回合限定一次；且手里要有风系攻击牌才可发动（客户端据此把「确定」置灰）
		if used_lian_xu_ji or not _has_wind_attack_card():
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


## 手上是否有风系攻击牌（风怒追击的额外攻击只能用风系攻击牌，见 v_attack）
func _has_wind_attack_card() -> bool:
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card != null and card.is_attack() and card.element_enum() == GConst.CardElement.Wind:
			return true
	return false

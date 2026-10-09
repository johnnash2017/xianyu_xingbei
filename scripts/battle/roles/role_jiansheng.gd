extends BattleRole
## 剑圣（roleID 1）—— 移植自服务端 role/JianSheng.cpp
## 技能：
##   疾风技（101，响应：带此特技的攻击牌作为主动攻击打出时发动，额外 +1 攻击行动）
##   烈风技（102，响应：带此特技的主动攻击，目标拥有圣盾或天使之墙时无视其圣盾、且对方无法应战）
##   风怒追击（103，回合限定，攻击行动结束时额外 +1 攻击行动）
##   圣剑（104，本回合第 3 次主动攻击强制命中，该次【攻击行动】结束后摸 X 张、弃 X 张，X＝1~3）
##   剑影（105，回合限定，消耗 1 能量，攻击行动结束时额外 +1 攻击行动）
##
## v_attack 覆写：服务端 JianSheng::v_attack 限制「风怒追击」额外攻击只能用风系攻击牌
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

## 【圣剑】追踪：
## _sheng_jian_active 记「本次【攻击行动】是否触发了圣剑强制命中」，供 p_after_attack 收尾时先摸 X 张、再弃 X 张；
## _sheng_jian_step 是该收尾流程的推进阶段（0＝在问要摸几张（据此摸牌）/ 1＝已摸牌、待问第二次弃牌 /
## 2＝在等第二次弃牌 / STEP_DONE＝已完成）；_sheng_jian_弃张数 记第一步选中的摸牌张数 X。
## 用自有变量而不是引擎的 step：这条收尾要跨两次询问，中途一旦被别的钩子轮次插进来，step 会被清零。
var _sheng_jian_active: bool = false
var _sheng_jian_step: int = 0
var _sheng_jian_弃张数: int = 0


## 【疾风技 / 烈风技】不提供技能栏按钮：带对应特技的攻击牌作为主动攻击打出时，由 p_timeline_1 弹窗询问是否发动
## （原版如此），故这里不覆写 available_skills（基类默认返回空）


## 每回合开始：重置回合限定标记与圣剑计数
func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_lian_xu_ji = false
	used_jian_ying = false
	using_lian_xu_ji = false
	attack_count = 0
	_sheng_jian_active = false
	_sheng_jian_step = 0
	_sheng_jian_弃张数 = 0
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
		var r: int = _ji_feng_ji(ctx)
		if r == WAIT:
			return WAIT
		_timeline_1_step = SHENG_JIAN
	if _timeline_1_step == SHENG_JIAN:
		_sheng_jian(ctx)
		_timeline_1_step = 0
	return SUCCESS


## 烈风技：目标拥有圣盾或天使之墙时，无视其圣盾效果且此攻击对方无法应战。
## 带此特技的攻击牌作为主动攻击打出时弹窗询问是否发动
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
	_应用烈风技(ctx, dst)
	return SUCCESS


## 烈风技的结算：本次攻击无视目标圣盾，且对方无法应战
func _应用烈风技(ctx: Dictionary, dst: BattlePlayer) -> void:
	notice_skill(LIE_FENG_JI, [dst.id])
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	ctx["check_shield"] = false


## 疾风技：带此特技的攻击牌作为主动攻击打出时弹窗询问是否发动，同意则额外 +1 攻击行动。
## （额外行动本身设 direct：直接进入额外攻击阶段，不再二次追问，想跳过在那里「放弃行动」）
func _ji_feng_ji(ctx: Dictionary) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(JI_FENG_JI):
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, JI_FENG_JI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(JI_FENG_JI, [int(ctx.get("dst", -1))])
	player.add_action(GConst.ActionType.Attack, JI_FENG_JI, true)
	return SUCCESS


## 圣剑：若本次行动阶段的第 3 次主动攻击，则此攻击强制命中；
## 并置标记 —— 该次【攻击行动】结束后还要摸 X 张、弃 X 张（见 p_after_attack / _sheng_jian_cycle）
func _sheng_jian(ctx: Dictionary) -> void:
	if not bool(ctx.get("is_active", false)):
		return
	attack_count += 1
	if attack_count == 3:
		notice_skill(SHENG_JIAN, [int(ctx.get("dst", -1))])
		ctx["hit_rate"] = GConst.HitRate.NoMiss
		_sheng_jian_active = true


# ============================================================
# 攻击行动结束时（after_attack）：风怒追击 → 剑影 → 圣剑收尾
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 【风怒追击】→【剑影】：不跨询问，一轮走完（同一 SHook 内 step 不会被重置）
	if step < STEP_DONE:
		if step == 0:
			_lian_xu_ji()
			step = JIAN_YING
		if step == JIAN_YING:
			_jian_ying()
			step = STEP_DONE
	# 【圣剑】：本次（第 3 次）【攻击行动】触发强制命中后，结束这次攻击时摸 X 张、弃 X 张（跨一次询问）
	if _sheng_jian_active:
		return _sheng_jian_cycle()
	return SUCCESS


## 【圣剑】收尾（先摸后弃）：第一步在二级技能栏里给「摸 1 / 2 / 3 张牌」三个选项（取消＝不摸牌，本次收尾结束），
## 取所选张数为 X → 摸 X 张；第二步再从手牌（此时含刚摸进来的牌）里弃 X 张。
## 两次询问文案分别取技能表「提示」列第 1、2 条（序号从 0 起），{n} 传入对应张数。
func _sheng_jian_cycle() -> int:
	if _sheng_jian_step >= STEP_DONE:
		return SUCCESS
	# 第一步：选摸牌张数 X（1~3）
	if _sheng_jian_step == 0:
		if not engine.has_reply():
			询问(player.id, SHENG_JIAN, 0, 0, GConst.CardSource.Hand, [
				{"value": 1, "label": "摸 1 张牌"},
				{"value": 2, "label": "摸 2 张牌"},
				{"value": 3, "label": "摸 3 张牌"},
			], 0, "", [], true, 0)
			return WAIT
		var r0: Dictionary = take_skill_reply_full()
		var args0: Array = r0.get("args", [])
		if args0.is_empty() or int(args0[0]) <= 0:
			_sheng_jian_active = false
			_sheng_jian_step = STEP_DONE
			return SUCCESS
		_sheng_jian_弃张数 = int(args0[0])
		engine.draw(player.id, _sheng_jian_弃张数)
		_sheng_jian_step = 1
		engine._broadcast_game()
	# 第二步：从手牌（含刚摸进来的）里弃 X 张
	if _sheng_jian_step == 1 and not engine.has_reply():
		询问(player.id, SHENG_JIAN, _sheng_jian_弃张数, 0, GConst.CardSource.Hand, [], _sheng_jian_弃张数, "",
				[], false, 1, -1, [], _sheng_jian_弃张数)
		_sheng_jian_step = 2
		return WAIT
	if _sheng_jian_step != 2:
		return SUCCESS
	var r1: Dictionary = take_skill_reply_full()
	_sheng_jian_active = false
	_sheng_jian_step = STEP_DONE
	_sheng_jian_弃张数 = 0
	var cards1: Array = r1.get("card_ids", [])
	# 收尾弃牌：只弃「确实还在手牌」的牌（客户端可能回带已离手的旧牌 id）。
	# take_from_hand 遇到任一张不在手牌就整体失败、一张不扣，若仍调 to_discard 会把牌塞进弃牌堆造成牌张重复。
	# 故先过滤成合法牌再弃，数量不足时宁少不多。
	var 弃牌: Array = []
	for c: Variant in cards1:
		var cid: int = int(c)
		if not 弃牌.has(cid) and player.has_hand_card(cid):
			弃牌.append(cid)
	if 弃牌.is_empty():
		return SUCCESS
	engine.take_from_hand(player.id, 弃牌)
	engine.to_discard(弃牌)
	engine._log_discard(player.id, 弃牌)
	engine._broadcast_game()
	return SUCCESS


## 风怒追击（103）：回合限定，额外 +1 攻击行动。
## 只挂行动、不置 direct —— 好让引擎在攻击行动结束后统一问「是否发动」；
## 能不能发动只看「本回合用过没有」（v_additional_action）：手里没有风系攻击牌也照样给这份行动，
## 出牌时才由 v_attack 要求风系（没牌就只能放弃行动）
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
# 风怒追击本回合限一次；剑影本回合限一次且需仍有能量
# ============================================================
func v_additional_action(cause: int) -> int:
	if cause == LIAN_XU_JI:
		# 只限「本回合一次」；手里有没有风系攻击牌不再拦「确定」——
		# 没有风系牌时也照样给这一份额外攻击行动（出牌时才由 v_attack 要求风系，没牌就只能放弃行动）
		if used_lian_xu_ji:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if cause == JIAN_YING:
		if used_jian_ying or player.get_energy() <= 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return V_NOT_OVERRIDE


# ============================================================
# 玩家选中额外行动时：结算风怒追击/剑影的代价
# 引擎在选中时会统一广播技能通知，故此处只处理回合限定标记与能量扣除
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var cause: int = int(ctx.get("cause", 0))
	# 对照服务端 p_additional_action：仅选中「风怒追击」时置位，其余额外行动一律清除
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
# 牌类校验覆写：风怒追击（103）额外攻击行动期间只能用风系攻击牌
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


## 风怒追击的额外攻击行动期间，本阶段「普通出牌」的手牌白名单只剩手里的风系攻击牌
## （对应上面 v_attack 的同一条限制：不收紧的话界面上别的系攻击牌也会亮，点了会被服务端判无效）。
## 一张风系攻击牌都没有时（没有风也允许确认的那条路）显式发「全禁」白名单，
## 免得空列表被当成「不限制」、手牌又全亮起来
func action_card_ids(action_type: int) -> Array:
	if not using_lian_xu_ji or action_type != GConst.ActionType.Attack:
		return []
	var out: Array = []
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card != null and card.is_attack() and card.element_enum() == GConst.CardElement.Wind:
			out.append(cid)
	return out if not out.is_empty() else [GConst.手牌白名单_全禁]


# ============================================================
# 工具
# ============================================================
## 是否已挂有某来源的额外行动
func _contains_action(cause: int) -> bool:
	for a: Dictionary in player.additional_actions:
		if int(a.get("cause", -1)) == cause:
			return true
	return false

extends BattleRole
## 剑圣（roleID 1）—— 移植自服务端 role/JianSheng.cpp
## 技能：
##   疾风技（101，响应：带此特技的攻击牌作为主动攻击打出时发动，额外 +1 攻击行动）
##   烈风技（102，响应：带此特技的主动攻击，目标拥有圣盾或天使之墙时无视其圣盾、且对方无法应战）
##   风怒追击（103，回合限定，攻击行动结束时额外 +1 攻击行动，只允许风系攻击牌）
##   圣剑（104，本回合第 3 次主动攻击强制命中，该次【攻击行动】结束后摸 X 张、弃 X 张，X＝1~3）
##   剑影（105，回合限定，消耗 1 能量，攻击行动结束时额外 +1 攻击行动）
##
## 103 / 105 照剑之子：攻击结束时一起摆出来问；确认后以 direct 额外行动入队，
## 不立刻进入，等攻击结束响应处理完、回合收尾时再依次进入。
## 剑影的 1 能量在确认发动时支付，之后切换行动不再重复扣。

const JI_FENG_JI: int = 101
const LIE_FENG_JI: int = 102
const LIAN_XU_JI: int = 103
const SHENG_JIAN: int = 104
const JIAN_YING: int = 105

var used_lian_xu_ji: bool = false
var used_jian_ying: bool = false
var using_lian_xu_ji: bool = false
var attack_count: int = 0
## 剑影的 1 能量是否已经在「攻击结束询问确认」时付过（之后切换行动不再重复付）
var _jian_ying_paid: bool = false

## p_after_attack 的推进阶段（0＝未开始 / 1＝正在问 103、105 / 2＝问完）
const KEY_AFTER_STEP: String = "_jiansheng_after_step"

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
	_jian_ying_paid = false
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
	player.add_action(GConst.ActionType.Attack, JI_FENG_JI, true, true)
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
# 攻击行动结束时（after_attack）：先问 103 / 105 是否发动，再做圣剑收尾
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 【风怒追击 / 剑影】像剑之子那样在攻击结束时一起摆出来问；
	# 选中后以 direct 额外行动入队，之后由引擎直接进入，不再在回合结束二次询问。
	var 阶段: int = int(ctx.get(KEY_AFTER_STEP, 0))
	if 阶段 == 0:
		阶段 = 1
		ctx[KEY_AFTER_STEP] = 阶段
	if 阶段 == 1:
		while true:
			var 选项: Array = _攻击结束额外选项()
			if 选项.is_empty():
				ctx[KEY_AFTER_STEP] = 2
				break
			if not engine.has_reply():
				engine.ask_skill(player.id, int(选项[0]["value"]), 0, 0, GConst.CardSource.Hand,
					选项, 0, "", [], true,
					"攻击结束时可以发动以下技能，选择一项（发动后还能发动另一项）", [],
					0, 0, false, [], true, -1, 0, true)
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			var args: Array = r.get("args", [])
			var 选中: int = int(args[0]) if not args.is_empty() else 0
			if not _选项里有(选项, 选中):
				ctx[KEY_AFTER_STEP] = 2
				break
			# 照剑之子：这里只确认「发动」并把额外行动以 direct 入队，
			# 不立刻进入。等攻击结束响应都处理完、回合收尾时再依次进入，
			# 这样还能继续发动另一项 / 处理其它响应。
			if 选中 == LIAN_XU_JI:
				notice_skill(LIAN_XU_JI, [])
				player.add_action(GConst.ActionType.Attack, LIAN_XU_JI, true, true)
			elif 选中 == JIAN_YING:
				# 剑影的 1 能量在确认发动时就付（询问释放即付），之后切换给的行动不再重复扣
				if not _jian_ying_paid:
					if player.get_energy() <= 0:
						continue
					if player.crystal > 0:
						player.set_crystal(player.crystal - 1)
					else:
						player.set_gem(player.gem - 1)
					_jian_ying_paid = true
					engine._broadcast_game()
				notice_skill(JIAN_YING, [])
				player.add_action(GConst.ActionType.Attack, JIAN_YING, true, true)
			elif 选中 == GConst.技能_迅捷赐福:
				# 正常由引擎在 on_message 里截获并走额外行动确认；这里兜底结束本轮询问
				ctx[KEY_AFTER_STEP] = 2
				break
	# 【圣剑】：本次（第 3 次）【攻击行动】触发强制命中后，结束这次攻击时摸 X 张、弃 X 张（跨一次询问）
	if _sheng_jian_active:
		return _sheng_jian_cycle()
	return SUCCESS


## 本次攻击结束还能发动的 103 / 105；用过、已在队列里、能量不够的不再出现。
func _攻击结束额外选项() -> Array:
	var out: Array = []
	if not used_lian_xu_ji and not _contains_action(LIAN_XU_JI):
		out.append({"value": LIAN_XU_JI, "label": "风怒追击", "skill_id": LIAN_XU_JI})
	if not used_jian_ying and not _contains_action(JIAN_YING) and player.get_energy() > 0:
		out.append({"value": JIAN_YING, "label": "剑影", "skill_id": JIAN_YING})
	# 迅捷赐福是独立挂在身上的额外行动：103/105 选了之后仍要留在同一轮询问里，
	# 不能等它们入队就提前结束、直接进入攻击阶段。
	if _contains_action(GConst.技能_迅捷赐福):
		out.append({"value": GConst.技能_迅捷赐福, "label": "迅捷赐福",
			"skill_id": GConst.技能_迅捷赐福})
	return out


func _选项里有(选项: Array, 技能号: int) -> bool:
	for o: Dictionary in 选项:
		if int(o.get("value", 0)) == 技能号:
			return true
	return false


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


# ============================================================
# 玩家选中额外行动时的二次校验（服务端 JianSheng::v_additional_action）：
# 风怒追击本回合限一次；剑影本回合限一次且需仍有能量（已付款的除外）
# ============================================================
func v_additional_action(cause: int) -> int:
	if cause == LIAN_XU_JI:
		# 只限「本回合一次」；手里有没有风系攻击牌不再拦「确定」——
		# 没有风系牌时也照样给这一份额外攻击行动（出牌时才由 v_attack 要求风系，没牌就只能放弃行动）
		if used_lian_xu_ji:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if cause == JIAN_YING:
		# 只限制本回合一次；费用在确认发动时已结算，不在进入/切换时再拦
		if used_jian_ying:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return V_NOT_OVERRIDE


# ============================================================
# 玩家选中额外行动时：标记回合限定 / 补付剑影能量（确认时已付过的不再扣）
# ============================================================
func extra_action_switchable(cause: int) -> bool:
	# 只看这份额外行动还在不在、本回合用没用过；费用在确认发动时已经结算，不再参与切换判断。
	if cause == JI_FENG_JI or cause == LIAN_XU_JI:
		return true
	if cause == JIAN_YING:
		return not used_jian_ying
	return false


## 风怒追击给的额外攻击行动只允许风系攻击牌
func extra_action_element(cause: int) -> int:
	return GConst.CardElement.Wind if cause == LIAN_XU_JI else 0


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
		if not _jian_ying_paid:
			if player.crystal > 0:
				player.set_crystal(player.crystal - 1)
			else:
				player.set_gem(player.gem - 1)
			_jian_ying_paid = true
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 牌类校验覆写：风怒追击（103）额外攻击行动期间只能用风系攻击牌
# 按「当前额外行动来源」判断，避免切到剑影后 still 带着 103 的旧 using 标记
# ============================================================
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	var rc: int = player.base_v_attack(card_id, dst_id, players)
	if rc != GConst.GE_SUCCESS:
		return rc
	var 额外来源: int = 0
	if engine != null and engine.行动额外:
		额外来源 = engine.行动额外来源
	match 额外来源:
		LIAN_XU_JI:
			using_lian_xu_ji = true
			used_lian_xu_ji = true
			var card: GCard = Data.get_card(card_id)
			if card.element_enum() != GConst.CardElement.Wind:
				return GConst.GE_INVALID_ACTION
		JIAN_YING:
			# 询问确认时已经付过能量；这里只补记已用/兼容未付过的旧路径
			using_lian_xu_ji = false
			if not used_jian_ying:
				if not _jian_ying_paid:
					if player.crystal > 0:
						player.set_crystal(player.crystal - 1)
					elif player.gem > 0:
						player.set_gem(player.gem - 1)
					_jian_ying_paid = true
				used_jian_ying = true
				engine._broadcast_game()
	return GConst.GE_SUCCESS


## 103 / 105 给的那份攻击行动：103 限风系攻击牌；105 不限制（返回全部手牌，避免回落到当前 103 的 using 状态）
func extra_action_card_ids(cause: int, action_type: int) -> Array:
	if action_type != GConst.ActionType.Attack:
		return []
	if cause == JIAN_YING:
		return player.hand_cards.duplicate()
	if cause != LIAN_XU_JI:
		return []
	var out: Array = []
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card != null and card.is_attack() and card.element_enum() == GConst.CardElement.Wind:
			out.append(cid)
	return out if not out.is_empty() else [GConst.手牌白名单_全禁]


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

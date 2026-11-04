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
## 当前这一刀 103 / 105 已经从技能响应进入行动队列（尚未结算完）
var active_lian_xu_ji: bool = false
var active_jian_ying: bool = false
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
	active_lian_xu_ji = false
	active_jian_ying = false
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
# 攻击行动结束时：风怒追击自动生效；圣剑先摸弃；其余（剑影）交给行动聚合器
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 【风怒追击】不再弹确认：攻击行动一结束就自动生效（与封印师【法术激荡】同一套体验）
	_自动风怒追击()
	# 【圣剑】第三刀：先结算摸 X / 弃 X，再进入剑影等响应。
	if _sheng_jian_active:
		return _sheng_jian_cycle()
	return SUCCESS


## 【风怒追击】自动生效：本次攻击行动结束 → 直接获得 1 份「只能用风系攻击牌」的额外攻击行动，
## 不再询问是否发动。这份行动带 direct，引擎会直接进入；不想打就在那个阶段点「放弃行动」。
## 【回合限定】：本回合已经用过 / 这份已经在队列里 / 本回合取消过额外攻击 → 不再给。
func _自动风怒追击() -> void:
	if used_lian_xu_ji or active_lian_xu_ji or _contains_action(LIAN_XU_JI):
		return
	if player.跳过额外攻击行动:
		return
	notice_skill(LIAN_XU_JI, [])
	player.add_action(GConst.ActionType.Attack, LIAN_XU_JI, true, true, {
		"element": GConst.CardElement.Wind,
	})
	active_lian_xu_ji = true


## 交给行动聚合器的技能选项：用过、已在队列里、能量不够的不出现。
## （风怒追击已改为结束后自动生效，不再出现在这里）
func action_end_options(ctx: Dictionary) -> Array:
	var out: Array = []
	# 剑影写的是「攻击行动结束时」：法术行动结束不能摆出来
	if not 是攻击行动结束(ctx):
		return out
	if not used_jian_ying and not active_jian_ying and not _contains_action(JIAN_YING):
		out.append({"value": JIAN_YING, "label": GConst.按钮原文(JIAN_YING, 0), "skill_id": JIAN_YING,
			"enabled": player.get_energy() > 0})
	return out


func resolve_action_end_option(cause: int, _reply: Dictionary, _ctx: Dictionary) -> int:
	if cause == JIAN_YING:
		if not _jian_ying_paid:
			if player.get_energy() <= 0:
				return GConst.GE_INVALID_ACTION
			if player.crystal > 0:
				player.set_crystal(player.crystal - 1)
			else:
				player.set_gem(player.gem - 1)
			_jian_ying_paid = true
			engine._broadcast_game()
		notice_skill(JIAN_YING, [])
		# 剑影不限制出牌，就是一份普通额外攻击行动
		player.add_action(GConst.ActionType.Attack, JIAN_YING, true, true)
		active_jian_ying = true
		return SUCCESS
	return resolve_queued_extra_action(cause)


func _选项里有(选项: Array, 技能号: int) -> bool:
	for o: Dictionary in 选项:
		if int(o.get("value", 0)) == 技能号:
			return true
	return false


## 【圣剑】收尾（先摸后弃）：第一步在二级技能栏里给「摸 1 / 2 / 3 张牌」三个选项（取消＝不摸牌，本次收尾结束），
## 取所选张数为 X → 摸 X 张；第二步再从手牌（此时含刚摸进来的牌）里弃 X 张。
## 两次询问文案分别取技能表「提示」列第 1、2 条（序号从 0 起），{n} 传入对应张数。
## 摸牌必须走 push_draw（压状态后返回 URGENT）：先让【水影】这类「摸牌前」响应结算，
## 再按状态边界统一判手牌超限 —— 摸完超上限就先弃到上限、按超限张数掉士气，然后才结算「弃 X 张」。
## 以前直接 engine.draw 把牌塞进手里，紧接着就在同一个钩子里问「弃 X 张」，
## 中间没有状态边界，超限从来没被判定过。
func _sheng_jian_cycle() -> int:
	if _sheng_jian_step >= STEP_DONE:
		return SUCCESS
	# 第一步：选摸牌张数 X（1~3）
	if _sheng_jian_step == 0:
		if not engine.has_reply():
			询问(player.id, SHENG_JIAN, 0, 0, GConst.CardSource.Hand, [
				{"value": 1, "label": GConst.按钮原文(SHENG_JIAN, 0)},
				{"value": 2, "label": GConst.按钮原文(SHENG_JIAN, 1)},
				{"value": 3, "label": GConst.按钮原文(SHENG_JIAN, 2)},
			], 0, "", [], true, 0)
			return WAIT
		var r0: Dictionary = take_skill_reply_full()
		var args0: Array = r0.get("args", [])
		if args0.is_empty() or int(args0[0]) <= 0:
			_sheng_jian_active = false
			_sheng_jian_step = STEP_DONE
			return SUCCESS
		_sheng_jian_弃张数 = int(args0[0])
		_sheng_jian_step = 1
		engine.push_draw(player.id, _sheng_jian_弃张数, SHENG_JIAN)
		return URGENT
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
	var 需要弃: int = _sheng_jian_弃张数
	_sheng_jian_弃张数 = 0
	var cards1: Array = r1.get("card_ids", [])
	# 收尾弃牌：只弃「确实还在手牌」的牌（客户端可能回带已离手的旧牌 id）。
	# take_from_hand 遇到任一张不在手牌就整体失败、一张不扣，若仍调 to_discard 会把牌塞进弃牌堆造成牌张重复。
	# 故先过滤成合法牌再弃。超时/跳过时回复为空：既然已经自动抽了 X 张，
	# 就必须自动从手牌补弃到 X 张，不能因为没选牌就整段跳过。
	var 弃牌: Array = []
	for c: Variant in cards1:
		var cid: int = int(c)
		if not 弃牌.has(cid) and player.has_hand_card(cid):
			弃牌.append(cid)
		if 弃牌.size() >= 需要弃:
			break
	if 弃牌.size() < 需要弃:
		for cid2: int in player.hand_cards:
			if not 弃牌.has(cid2):
				弃牌.append(cid2)
			if 弃牌.size() >= 需要弃:
				break
	if 弃牌.size() > 需要弃:
		弃牌.resize(需要弃)
	if 弃牌.is_empty():
		return SUCCESS
	engine.take_from_hand(player.id, 弃牌)
	engine.to_discard(弃牌, {"owner": player.id, "source": "hand", "cause": SHENG_JIAN})
	engine._log_discard(player.id, 弃牌)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 额外行动：行动本身是通用工具（只带规格），这里只负责「确认时付费 / 进入时结算 / 结束时记账」
# ============================================================
## 进入某份额外行动时：剑影若还没付过能量（旧路径 / 测试直接入队），在这里补付一次。
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("cause", 0)) != JIAN_YING:
		return SUCCESS
	if not _jian_ying_paid:
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
		_jian_ying_paid = true
		engine._broadcast_game()
	return SUCCESS


## 额外攻击行动真正结束时才记「本回合已用」。
## 进入行动阶段后还可以切走再切回来；若一进入就记已用，切回来时这份还没消耗的行动就没法再用了。
func p_action_end(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_extra", false)):
		return SUCCESS
	match int(ctx.get("extra_cause", 0)):
		LIAN_XU_JI:
			used_lian_xu_ji = true
			active_lian_xu_ji = false
		JIAN_YING:
			used_jian_ying = true
			active_jian_ying = false
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 是否已挂有某来源的额外行动
func _contains_action(cause: int) -> bool:
	for a: Dictionary in player.additional_actions:
		if int(a.get("cause", -1)) == cause:
			return true
	return false

extends BattleRole
## 狂战士（roleID 2）—— 移植自服务端 role/KuangZhan.cpp
## 技能：狂化（被动，攻击伤害+1，命中时手牌>3 再 +1）、血影狂刀（攻击时可选）、血腥咆哮（攻击时可选，强制命中）、撕裂（命中后消耗宝石+2 伤害）

const XUE_YING_KUANG_DAO: int = 201
const XUE_XING_PAO_XIAO: int = 202
const KUANG_HUA: int = 203
const SI_LIE: int = 205


## 【血影狂刀 / 血腥咆哮】不再提供技能栏按钮：只能作为主动攻击打出时响应发动（原版如此），
## 故这里不再覆写 available_skills（基类默认返回空）


## 【血影狂刀 / 血腥咆哮】的推进阶段（0＝还没开始 / XUE_YING_KUANG_DAO＝处理血影狂刀 / XUE_XING_PAO_XIAO＝处理血腥咆哮）。
## 带对应特技的攻击牌作为主动攻击打出时，按原版顺序弹窗询问是否发动。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0


func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	if _timeline_1_step == 0:
		_timeline_1_step = XUE_YING_KUANG_DAO
	if _timeline_1_step == XUE_YING_KUANG_DAO:
		var r: int = _xue_ying_kuang_dao(ctx)
		if r == WAIT:
			return WAIT
		_timeline_1_step = XUE_XING_PAO_XIAO
	if _timeline_1_step == XUE_XING_PAO_XIAO:
		var r2: int = _xue_xing_pao_xiao(ctx)
		if r2 == WAIT:
			return WAIT
		_timeline_1_step = 0
	return SUCCESS


## 【狂化 / 撕裂】的推进阶段（0＝还没开始 / KUANG_HUA＝结算狂化 / SI_LIE＝在问撕裂）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击命中（p_timeline_2_hit）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_2_hit_step: int = 0


func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if harm.get("type", GConst.HarmType.Attack) != GConst.HarmType.Attack:
		return SUCCESS
	if _timeline_2_hit_step >= STEP_DONE:
		return SUCCESS
	if _timeline_2_hit_step == 0:
		_timeline_2_hit_step = KUANG_HUA
	if _timeline_2_hit_step == KUANG_HUA:
		var r: int = _kuang_hua(harm)
		if r == WAIT:
			return WAIT
		_timeline_2_hit_step = SI_LIE
	if _timeline_2_hit_step == SI_LIE:
		var r2: int = _si_lie(harm)
		if r2 == WAIT:
			return WAIT
		_timeline_2_hit_step = 0
	return SUCCESS


# ============================================================
# 具体技能
# ============================================================
## 【血影狂刀】本次攻击伤害 +2（目标手牌 2 张）或 +1（目标手牌 3 张）。
## 普通出牌攻击按原版弹窗询问是否发动
func _xue_ying_kuang_dao(ctx: Dictionary) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(XUE_YING_KUANG_DAO) or not bool(ctx.get("is_active", false)):
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		return SUCCESS
	var n: int = dst.hand_cards.size()
	if n < 2 or n > 3:
		return SUCCESS
	if not engine.has_reply():
		# 目标与发动前的伤害一并下发：客户端据此在目标头像上现算「本次攻击伤害」。
		# 狂化「手牌 > 3 再 +1」只有服务端算得出来，随预览基准一起带上。
		var 预览基准: int = 攻击预览伤害(ctx)
		var 刀加伤: int = 2 if n == 2 else 1
		询问(player.id, XUE_YING_KUANG_DAO, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [dst.id], -1, {}, 预览基准, GConst.HarmType.Attack, false, [], true, 预览基准 + 刀加伤)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(XUE_YING_KUANG_DAO, [dst.id])
	var harm: Dictionary = ctx["harm"]
	加伤害(harm, (2 if n == 2 else 1))
	return SUCCESS


## 【血腥咆哮】本次攻击强制命中。
## 普通出牌攻击按原版弹窗询问是否发动
func _xue_xing_pao_xiao(ctx: Dictionary) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(XUE_XING_PAO_XIAO) or not bool(ctx.get("is_active", false)):
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.cross_num != 2:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, XUE_XING_PAO_XIAO)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(XUE_XING_PAO_XIAO, [dst.id])
	ctx["hit_rate"] = GConst.HitRate.NoMiss
	return SUCCESS


func _kuang_hua(harm: Dictionary) -> int:
	notice_skill(KUANG_HUA, [int(harm["dst"])])
	# 伤害由引擎在命中时按 p_attack_preview 统一加（这里只播报）：
	# 无条件 +1、手牌 > 3 再 +1，两边共用同一份声明
	return SUCCESS


## 【狂化】的条件加伤（手牌 > 3 时 +1）预告给被攻击者看：
## 这里返回**全部**「命中时才加、还没进 harm.point」的加伤（无条件 +1 ＋ 手牌 > 3 再 +1），
## 服务端统一用它算预览，客户端不再自己补这 1 点。只用于显示，不改变实际结算。
func p_attack_preview(_ctx: Dictionary) -> int:
	return 1 + (1 if player.hand_cards.size() > 3 else 0)


func _si_lie(harm: Dictionary) -> int:
	if player.gem <= 0:
		return SUCCESS
	var dst: int = int(harm.get("dst", -1))
	if dst < 0:
		return SUCCESS
	if not engine.has_reply():
		# 目标就是本次攻击目标：随询问下发 targets，客户端进场自动选中并锁死；
		# preview_base 是加伤前的原始攻击伤害，客户端据此在头像上画「原伤害划掉 → 新伤害」
		询问(player.id, SI_LIE, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [dst], -1, {}, int(harm.get("point", 0)), GConst.HarmType.Attack, false, [], true,
			int(harm.get("point", 0)) + 2)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(SI_LIE, [int(harm["dst"])])
	加伤害(harm, 2)
	player.set_gem(player.gem - 1)
	engine._broadcast_game()
	return SUCCESS

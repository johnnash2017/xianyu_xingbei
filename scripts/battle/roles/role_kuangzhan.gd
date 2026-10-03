extends BattleRole
## 狂战士（roleID 2）—— 移植自服务端 role/KuangZhan.cpp
## 技能：狂化（被动，攻击伤害+1）、血影狂刀（攻击时可选）、血腥咆哮（攻击时可选，强制命中）、撕裂（命中后消耗宝石+2 伤害）

const XUE_YING_KUANG_DAO: int = 201
const XUE_XING_PAO_XIAO: int = 202
const KUANG_HUA: int = 203
const SI_LIE: int = 205


## 【血影狂刀 / 血腥咆哮】的推进阶段（0＝还没开始 / XUE_YING_KUANG_DAO＝在问血影狂刀 / XUE_XING_PAO_XIAO＝在问血腥咆哮）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨两次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
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
		询问(player.id, XUE_YING_KUANG_DAO)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(XUE_YING_KUANG_DAO, [dst.id])
	var harm: Dictionary = ctx["harm"]
	harm["point"] = int(harm["point"]) + (2 if n == 2 else 1)
	return SUCCESS


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
	harm["point"] = int(harm["point"]) + 1
	return SUCCESS


func _si_lie(harm: Dictionary) -> int:
	if player.gem <= 0:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, SI_LIE)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(SI_LIE, [int(harm["dst"])])
	harm["point"] = int(harm["point"]) + 2
	player.set_gem(player.gem - 1)
	engine._broadcast_game()
	return SUCCESS

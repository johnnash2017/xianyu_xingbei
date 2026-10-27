extends RefCounted
## F5-F 剑圣（1）独有技 helper：101 疾风技 / 102 烈风技
##
## 供借用剑圣独有技的角色（如 108 剑之子【风之剑】10802）在 p_timeline_1 里路由；
## 只复用、不改动 role_jiansheng.gd，保证 1 号剑圣的行为不回归。
##
## 借用角色的接法：
##   const 剑圣独有技 = preload("res://scripts/battle/skills/skill_sword.gd")
##   var _剑圣: 剑圣独有技
##   func setup(p: BattlePlayer, e: BattleEngine) -> void:
##       super.setup(p, e)
##       _剑圣 = 剑圣独有技.new(self)          # 构造传借用角色本身
##   func p_timeline_1(ctx: Dictionary) -> int:
##       return _剑圣.p_timeline_1(ctx)        # 返回值原样返回；WAIT 时引擎会在回复后回到同一钩子
##
## 判定口径与 role_jiansheng.gd 一致：
## - 102 烈风技：带此技能的牌攻击的目标面前有【圣盾】/【天使之墙】时，先问攻击者是否发动；
##   发动后本次攻击对手无法应战（hit_rate = NoReattack）、且不查 / 不消耗目标的圣盾。
## - 101 疾风技：带此技能的牌作为**主动**攻击（is_active）打出时，先问攻击者是否发动；
##   发动后额外 +1【攻击行动】（direct + 不重复播报，与剑圣原实现相同）。
## 只处理「自己发起的攻击宣告」（ctx.src == 自己）；应战打出的攻击（is_active = false）只可能触发 102。
##
## 进度（先问 102、再问 101）放在 helper 实例变量里，不占角色的 step，也不动角色的持久进度。

## 剑圣独有技技能号（技能表：101 疾风技 / 102 烈风技）
const 疾风技: int = 101
const 烈风技: int = 102

## 本次攻击宣告的处理阶段：0＝未开始；1＝待问 102；2＝待问 101。
## 一轮处理完（或两个都不适用）回到 0，下一张攻击牌重新走一遍。
const 阶段_未开始: int = 0
const 阶段_待问烈风技: int = 1
const 阶段_待问疾风技: int = 2

## 借用它的角色（构造时传入；helper 不持有自己的 player / engine）
var 角色: BattleRole = null

var 引擎: BattleEngine:
	get:
		return 角色.engine if 角色 != null else null

var 玩家: BattlePlayer:
	get:
		return 角色.player if 角色 != null else null

var _阶段: int = 阶段_未开始


func _init(借用角色: BattleRole) -> void:
	角色 = 借用角色


## helper 是否已绑定到可用角色（角色、玩家、引擎都在）
func 可用() -> bool:
	return 角色 != null and 玩家 != null and 引擎 != null


## 清掉本次攻击宣告的进度（换攻击宣告、或角色想主动重来时用；正常一轮结束会自己清回未开始）
func 重置() -> void:
	_阶段 = 阶段_未开始


# ============================================================
# 攻击宣告（借用角色的 p_timeline_1 转发）
# ============================================================
## 攻击宣告的借用入口：先看 102 烈风技，再看 101 疾风技。
## 返回 SUCCESS（本次处理完）/ WAIT（已向攻击者问「是否发动」，等回复后引擎会再调本钩子）。
func p_timeline_1(ctx: Dictionary) -> int:
	if not 可用():
		return BattleRole.SUCCESS
	# 攻击宣告是全场广播：只有攻击者本人结算自己牌上的剑圣独有技
	if int(ctx.get("src", -1)) != 玩家.id:
		return BattleRole.SUCCESS
	if _阶段 == 阶段_未开始:
		_阶段 = 阶段_待问烈风技
	if _阶段 == 阶段_待问烈风技:
		var r1: int = _烈风技(ctx)
		if r1 == BattleRole.WAIT:
			return BattleRole.WAIT
		_阶段 = 阶段_待问疾风技
	if _阶段 == 阶段_待问疾风技:
		var r2: int = _疾风技(ctx)
		if r2 == BattleRole.WAIT:
			return BattleRole.WAIT
		_阶段 = 阶段_未开始
	return BattleRole.SUCCESS


# ============================================================
# 102 烈风技
# ============================================================
## 目标面前有【圣盾】或【天使之墙】时，问攻击者是否发动（先问「发不发动」，不替玩家做决定）
func _烈风技(ctx: Dictionary) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(烈风技):
		return BattleRole.SUCCESS
	var dst: BattlePlayer = 引擎.p(int(ctx.get("dst", -1)))
	if dst == null or not _目标有圣盾(dst):
		return BattleRole.SUCCESS
	if not 引擎.has_reply():
		角色.询问(玩家.id, 烈风技, 0, 0)
		return BattleRole.WAIT
	if not 角色.take_skill_reply():
		return BattleRole.SUCCESS
	_结算烈风技(ctx, dst)
	return BattleRole.SUCCESS


## 目标面前有【圣盾】或视作圣盾的【天使之墙】（判定口径同 role_jiansheng.gd）
func _目标有圣盾(dst: BattlePlayer) -> bool:
	return dst.check_basic_effect_name(GConst.CardName.Shield) \
			or dst.check_basic_effect_skill(GConst.技能_天使之墙)


## 烈风技的结算：本次攻击对手无法应战、且不查圣盾（圣盾保留，不触发 / 不消耗）
func _结算烈风技(ctx: Dictionary, dst: BattlePlayer) -> void:
	角色.notice_skill(烈风技, [dst.id])
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	ctx["check_shield"] = false


# ============================================================
# 101 疾风技
# ============================================================
## 带此技能的牌作为主动攻击打出时，问攻击者是否发动；发动则额外 +1【攻击行动】。
## 额外行动设 direct + skip_notice：直接进入额外攻击阶段（想跳过在那儿「放弃行动」），
## 且不再补发一次技能播报（本 helper 已经播报过），与 role_jiansheng.gd 一致。
func _疾风技(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_active", false)):
		return BattleRole.SUCCESS
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(疾风技):
		return BattleRole.SUCCESS
	if not 引擎.has_reply():
		角色.询问(玩家.id, 疾风技, 0, 0)
		return BattleRole.WAIT
	if not 角色.take_skill_reply():
		return BattleRole.SUCCESS
	角色.notice_skill(疾风技, [int(ctx.get("dst", -1))])
	玩家.add_action(GConst.ActionType.Attack, 疾风技, true, true)
	return BattleRole.SUCCESS

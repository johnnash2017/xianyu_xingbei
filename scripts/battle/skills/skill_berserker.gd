extends RefCounted
## 狂战士（2）独有技 helper：【血影狂刀】（201）/【血腥咆哮】（202）（F5-B）。
##
## 这两颗技能没有技能栏按钮，只能「作为主动攻击打出时」随攻击牌响应发动（原版如此）。
## 这里把 role_kuangzhan.gd 的这一段（牌 / 目标校验 + 询问 + 结算）抽成 helper，
## 供借用狂战士独有技的角色（97 萝莉番长【夜露死苦】9702、【爱死天流】9703）复用；
## **不改 role_kuangzhan.gd**：狂战士本人仍走自己的脚本，行为不回归。
##
## 借用方用法（构造传借用角色自己，setup 里创建）：
##   const 狂战士技能 = preload("res://scripts/battle/skills/skill_berserker.gd")
##   var _狂战士技能: Variant = null
##   func setup(p: BattlePlayer, e: BattleEngine) -> void:
##       super.setup(p, e)
##       _狂战士技能 = 狂战士技能.new(self)
##       _狂战士技能.技能号血影狂刀 = 9702   # 播报 / 询问都按本角色自己的技能行取
##       _狂战士技能.技能号血腥咆哮 = 9702
##   func p_timeline_1(ctx: Dictionary) -> int:
##       return int(_狂战士技能.call("响应攻击", ctx))
##
## 覆盖点（9702/9703 这类改写用；可不设，默认与 role_kuangzhan.gd 一致）：
## - 血影狂刀加伤: Callable(dst: BattlePlayer) -> int
##     替换默认加伤（狂战士原版：目标手牌 2 张 → +2、3 张 → +1）。
## - 血腥咆哮条件: Callable(dst: BattlePlayer) -> bool
##     替换默认的发动条件（狂战士原版：目标【治疗】为 2）。
##     例：9703【爱死天流】把条件改成「目标拥有【治疗】」→ 传 dst.cross_num > 0。
## - 血腥咆哮效果: Callable(ctx: Dictionary, dst: BattlePlayer) -> int
##     替换默认效果（狂战士原版：本次攻击强制命中）；返回 BattleRole.SUCCESS / WAIT。
##     例：9703 改成「本次攻击无法用【暗灭】应战 / 无法用【圣光】抵挡」时，
##     在这里改 ctx["hit_rate"] / ctx["can_light"]（仍由本 helper 负责牌校验、询问、播报）。
##
## 判定口径与 role_kuangzhan.gd 一致：只认主动攻击（is_active）、攻击牌上带 201/202；
## 【血影狂刀】在宣告阶段把加伤算进 harm（目标手牌 2~3 张），
## 【血腥咆哮】在宣告阶段改命中率（目标【治疗】为 2 时强制命中）。

## 牌上带的技能号（卡表里写死 201/202，借用方也用同一批牌，不能改）
const 牌上血影狂刀: int = 201
const 牌上血腥咆哮: int = 202

## 顺序进度：与 role_kuangzhan.gd 的 _timeline_1_step 同构（先 201、后 202）
const 进度_未开始: int = 0
const 进度_血影狂刀: int = 1
const 进度_血腥咆哮: int = 2

## 借用它的角色（构造时传入；helper 不持有自己的 player / engine）
var 角色: BattleRole = null

## 播报 / 询问用哪一行技能：狂战士 201 / 202；
## 借用角色（97 萝莉番长）两颗都填自己的技能号 9702，日志与提示才按本角色技能行取
var 技能号血影狂刀: int = 牌上血影狂刀
var 技能号血腥咆哮: int = 牌上血腥咆哮

## 覆盖点，见文件头；留空（Callable()）＝按狂战士原版
var 血影狂刀加伤: Callable = Callable()
var 血腥咆哮条件: Callable = Callable()
var 血腥咆哮效果: Callable = Callable()

## 本次主动攻击的推进进度（0 未开始 / 1 血影狂刀 / 2 血腥咆哮）
var _进度: int = 进度_未开始


var 引擎: BattleEngine:
	get:
		return 角色.engine if 角色 != null else null


var 玩家: BattlePlayer:
	get:
		return 角色.player if 角色 != null else null


func _init(借用角色: BattleRole) -> void:
	角色 = 借用角色


## helper 是否已绑定到可用角色（角色 / 玩家 / 引擎都在）
func 可用() -> bool:
	return 角色 != null and 角色.player != null and 角色.engine != null


## 当前进度（调试 / 测试用）
func 当前进度() -> int:
	return _进度


## 清掉进度：整段攻击流程被外部中断时由借用角色兜底调用，避免下一次攻击从中间开始
func 重置() -> void:
	_进度 = 进度_未开始


# ============================================================
# 静态判定
# ============================================================
## 【血影狂刀】是否可以发动：主动攻击、攻击牌带 201、目标手牌 2~3 张
## （与 role_kuangzhan.gd 的 _xue_ying_kuang_dao 同口径）
func 可发动血影狂刀(ctx: Dictionary) -> bool:
	if not bool(ctx.get("is_active", false)):
		return false
	var 目标: BattlePlayer = _取目标(ctx)
	if 目标 == null:
		return false
	if not _是带技能攻击牌(ctx, 牌上血影狂刀):
		return false
	var n: int = 目标.hand_cards.size()
	return n >= 2 and n <= 3


## 【血腥咆哮】是否可以发动：主动攻击、攻击牌带 202、目标满足【治疗】条件
## （条件默认按狂战士原版「治疗为 2」，借用方可用「血腥咆哮条件」覆盖）
func 可发动血腥咆哮(ctx: Dictionary) -> bool:
	if not bool(ctx.get("is_active", false)):
		return false
	var 目标: BattlePlayer = _取目标(ctx)
	if 目标 == null:
		return false
	if not _是带技能攻击牌(ctx, 牌上血腥咆哮):
		return false
	if 血腥咆哮条件.is_valid():
		return bool(血腥咆哮条件.call(目标))
	return 目标.cross_num == 2


# ============================================================
# p_timeline_1 转发入口
# ============================================================
## 借用角色在 p_timeline_1 里直接转给这里；返回 BattleRole.SUCCESS / WAIT。
## 按「血影狂刀 → 血腥咆哮」的顺序处理，每段等回复时停在同一段，收尾清回未开始。
func 响应攻击(ctx: Dictionary) -> int:
	if not 可用():
		return BattleRole.SUCCESS
	# 只处理自己发起的主动攻击（应战反击 is_active=false，不触发这两颗响应技）
	if int(ctx.get("src", -1)) != 角色.player.id:
		return BattleRole.SUCCESS
	if not bool(ctx.get("is_active", false)):
		return BattleRole.SUCCESS
	if _进度 == 进度_未开始:
		_进度 = 进度_血影狂刀
	if _进度 == 进度_血影狂刀:
		var r: int = _处理血影狂刀(ctx)
		if r == BattleRole.WAIT:
			return BattleRole.WAIT
		_进度 = 进度_血腥咆哮
	if _进度 == 进度_血腥咆哮:
		var r2: int = _处理血腥咆哮(ctx)
		if r2 == BattleRole.WAIT:
			return BattleRole.WAIT
		_进度 = 进度_未开始
	return BattleRole.SUCCESS


# ============================================================
# 具体技能
# ============================================================
## 【血影狂刀】这次攻击伤害 +2（目标手牌 2 张）或 +1（目标手牌 3 张）。
## 先问发动者（带本次攻击原伤害作为头像预览基准），确认后加到 harm 上。
func _处理血影狂刀(ctx: Dictionary) -> int:
	if not 可发动血影狂刀(ctx):
		return BattleRole.SUCCESS
	var 目标: BattlePlayer = _取目标(ctx)
	if not 角色.engine.has_reply():
		var harm: Dictionary = ctx.get("harm", {}) as Dictionary
		# 目标与发动前的伤害一并下发：客户端据此在目标头像上现算「本次攻击伤害」。
		# 狂化「手牌 > 3 再 +1」这类客户端算不出的加伤走 p_attack_preview 补进基准。
		var 预览基准: int = int(harm.get("point", 0)) + 角色.p_attack_preview(ctx)
		角色.询问(角色.player.id, 技能号血影狂刀, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [目标.id], -1, {}, 预览基准)
		return BattleRole.WAIT
	if not 角色.take_skill_reply():
		return BattleRole.SUCCESS
	角色.notice_skill(技能号血影狂刀, [目标.id])
	var 结算伤害: Dictionary = ctx.get("harm", {}) as Dictionary
	结算伤害["point"] = int(结算伤害.get("point", 0)) + _加伤值(目标)
	ctx["harm"] = 结算伤害
	return BattleRole.SUCCESS


## 【血腥咆哮】本次攻击强制命中。
## 默认按狂战士原版；借用角色可用「血腥咆哮条件 / 血腥咆哮效果」改条件与命中效果。
func _处理血腥咆哮(ctx: Dictionary) -> int:
	if not 可发动血腥咆哮(ctx):
		return BattleRole.SUCCESS
	var 目标: BattlePlayer = _取目标(ctx)
	if not 角色.engine.has_reply():
		角色.询问(角色.player.id, 技能号血腥咆哮)
		return BattleRole.WAIT
	if not 角色.take_skill_reply():
		return BattleRole.SUCCESS
	角色.notice_skill(技能号血腥咆哮, [目标.id])
	return _咆哮效果(ctx, 目标)


## 【血腥咆哮】的效果：设了覆盖就用覆盖，否则按狂战士原版改为强制命中
func _咆哮效果(ctx: Dictionary, 目标: BattlePlayer) -> int:
	if 血腥咆哮效果.is_valid():
		return int(血腥咆哮效果.call(ctx, 目标))
	ctx["hit_rate"] = GConst.HitRate.NoMiss
	return BattleRole.SUCCESS


# ============================================================
# 工具
# ============================================================
## 本次攻击的目标（取自 ctx.dst；不存在返回 null）
func _取目标(ctx: Dictionary) -> BattlePlayer:
	var e: BattleEngine = 引擎
	if e == null:
		return null
	return e.p(int(ctx.get("dst", -1)))


## 这次打出的攻击牌是否带指定技能号（与 role_kuangzhan.gd 一致，只按牌上技能判）
func _是带技能攻击牌(ctx: Dictionary, 技能号: int) -> bool:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	return card != null and card.has_skill_id(技能号)


## 【血影狂刀】的加伤值：设了覆盖就用覆盖，否则按狂战士原版
func _加伤值(目标: BattlePlayer) -> int:
	if 血影狂刀加伤.is_valid():
		return int(血影狂刀加伤.call(目标))
	return _默认血影狂刀加伤(目标)


func _默认血影狂刀加伤(目标: BattlePlayer) -> int:
	var n: int = 目标.hand_cards.size()
	if n == 2:
		return 2
	if n == 3:
		return 1
	return 0

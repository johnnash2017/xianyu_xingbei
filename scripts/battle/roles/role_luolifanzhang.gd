extends BattleRole
## 萝莉番长（roleID 97）—— 特典
## 技能：
##   喧哗上等（9701，被动）：攻击命中时②，持续移除牌库顶牌【展示】，直到移除的牌
##       非血类命格或非法术牌，或累计移除三张牌；本次攻击伤害额外 +X（X＝移除的牌数）
##   夜露死苦（9702，响应）：你可以使用狂战士的独有技（201 血影狂刀 / 202 血腥咆哮）
##   爱死天流（9703，被动）：你发动【血腥咆哮】时，把「目标【治疗】为 2 → 本次攻击强制命中」
##       改为「目标拥有【治疗】→ 本次攻击无法用【暗灭】应战或使用【圣光】抵挡」
##   灭茶苦茶（9704，响应）：攻击命中后②，选择以下一项：
##       【宝石】本次攻击伤害额外 +2；【水晶】本次攻击伤害额外 +1
##
## 借用狂战士独有技见 scripts/battle/skills/skill_berserker.gd：201 / 202 都按本角色自己的
## 技能行 9702 询问 / 播报；9703 通过 helper 的覆盖点改【血腥咆哮】的条件与效果，
## 不改 role_kuangzhan.gd（狂战士本人行为不回归）。
##
## 口径（见 data-audit §3.10 / A37~A40）：
##   - 9701 的「或」按字面口径：继续移除的条件是「血类命格 **且** 法术牌」，
##     否则停下；累计 3 张必停。移出的牌先【展示】，再进弃牌堆（走 to_discard，
##     保留 F6 的「进弃牌前拦截」入口）。只看牌库顶，牌库不足时不把弃牌堆洗回；
##   - 9702 借用 201 / 202 的原效果，不额外改写（9703 另行改写 202）；
##   - 9703「拥有【治疗】」按治疗 > 0；「无法用【暗灭】应战」需要引擎在应战询问里增加
##     「禁止指定牌应战」的标志（data-audit Q2），本任务范围改不到 battle_engine.gd，
##     当前只落实「无法使用【圣光】抵挡」（can_light=false）。
##     暗灭一条待引擎任务接入后在 _ai_si_tian_liu_效果 里补；
##   - 9704 的两个选项始终成对下发，做不了的置灰（enabled=false）；【宝石】费用必须是真宝石，
##     【水晶】费用按约定用 get_energy() 判断、remove_energy(1) 支付（宝石可顶水晶）。
##   - 9701 / 9704 的「攻击命中」不限主动攻击：应战反击打出并命中的攻击同样触发
##     （原文没有「主动攻击」的限定）。
##   - 同一份 harm 上 9701 先结算（自动），9704 后询问；9704 的头像预览基准是 9701 加伤后的伤害。

const 狂战士技能脚本: GDScript = preload("res://scripts/battle/skills/skill_berserker.gd")

const 喧哗上等: int = 9701
const 夜露死苦: int = 9702
const 爱死天流: int = 9703
const 灭茶苦茶: int = 9704

## 9701：累计移除三张牌必停
const 喧哗上等_最多移除: int = 3

## 9704 的固定选项值（顺序稳定，客户端按 notes 下标显示）
const 灭茶苦茶_选项宝石: int = 1
const 灭茶苦茶_选项水晶: int = 2
const 灭茶苦茶_宝石加伤: int = 2
const 灭茶苦茶_水晶加伤: int = 1

## 本次命中钩子的推进进度（存在 ctx：同一次命中的钩子重入拿的是同一份 ctx）
const KEY_HIT_STEP: String = "_luolifanzhang_hit_step"
const HIT_STEP_喧哗上等: int = 1

## 借用的狂战士独有技 helper（构造传自己；201/202 的分步状态存在 helper 实例里）
var _狂战士技能: Variant = null


func _init() -> void:
	_狂战士技能 = 狂战士技能脚本.new(self)
	# 9702：借用的两颗独有技都按本角色自己的 9702 询问 / 播报，不借用狂战士的 201 / 202
	_狂战士技能.技能号血影狂刀 = 夜露死苦
	_狂战士技能.技能号血腥咆哮 = 夜露死苦
	# 9703：条件改为「目标拥有【治疗】」（>0），效果替换掉默认的「强制命中」
	_狂战士技能.血腥咆哮条件 = Callable(self, "_ai_si_tian_liu_条件")
	_狂战士技能.血腥咆哮效果 = Callable(self, "_ai_si_tian_liu_效果")


# ============================================================
# 回合开始：清掉上一次攻击遗留的分步进度（攻击中途被外部中断时兜底）
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	if _狂战士技能 != null:
		_狂战士技能.重置()
	return SUCCESS


# ============================================================
# 攻击宣告：9702 借用的 201 血影狂刀 / 202 血腥咆哮（按 201 → 202 顺序）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if _狂战士技能 == null:
		return SUCCESS
	return int(_狂战士技能.响应攻击(ctx))


# ============================================================
# 攻击命中时（timeline_2_hit）：9701 喧哗上等 → 9704 灭茶苦茶
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", GConst.HarmType.None)) != GConst.HarmType.Attack:
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_HIT_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		_喧哗上等(harm)
		ctx[KEY_HIT_STEP] = HIT_STEP_喧哗上等
	if int(ctx.get(KEY_HIT_STEP, 0)) == HIT_STEP_喧哗上等:
		var r: int = _灭茶苦茶(harm)
		if r == WAIT:
			return WAIT
		ctx[KEY_HIT_STEP] = STEP_DONE
	return SUCCESS


## 9701 喧哗上等：从牌库顶逐张移除并【展示】，直到「非血类命格或非法术牌」或已移除 3 张。
## 本次攻击伤害额外 +移除张数；移出的牌进弃牌堆（to_discard 保留弃牌前拦截入口）。
func _喧哗上等(harm: Dictionary) -> void:
	if engine == null:
		return
	var 移除: Array[int] = []
	for _i: int in range(喧哗上等_最多移除):
		var 顶: Array[int] = engine.移除牌库顶(1)
		if 顶.is_empty():
			break
		var 牌号: int = int(顶[0])
		移除.append(牌号)
		engine.展示牌库顶(player.id, [牌号])
		var 牌: GCard = Data.get_card(牌号)
		if 牌 == null or 牌.fate_pattern_enum() != GConst.FatePattern.Blood or not 牌.is_magic():
			break
	if 移除.is_empty():
		return
	notice_skill(喧哗上等, [int(harm.get("dst", -1))])
	harm["point"] = int(harm.get("point", 0)) + 移除.size()
	engine.to_discard(移除, {"source": "deck", "cause": 喧哗上等, "face_up": true})
	engine._broadcast_game()


## 9704 灭茶苦茶：攻击命中后询问二选一；资源不足的选项照常下发、只置灰。
## 返回 WAIT＝正在等发动者回答；返回 SUCCESS＝不必再等（没资源 / 已结算 / 取消）。
func _灭茶苦茶(harm: Dictionary) -> int:
	var 可宝石: bool = player.gem > 0
	var 可水晶: bool = player.get_energy() > 0
	# 两项都付不起＝这个响应技能根本发动不了，不弹无用询问
	if not 可宝石 and not 可水晶:
		return SUCCESS
	if not engine.has_reply():
		# 目标就是本次攻击目标：随询问下发 targets，客户端进场自动选中并锁死；
		# 预览基准＝9701 加伤后的当前伤害，客户端据此画「原伤害划掉 → 新伤害」。
		询问(player.id, 灭茶苦茶, 0, 0, GConst.CardSource.Hand,
			_灭茶苦茶选项(可宝石, 可水晶), 0, "", [], true, 0, -1,
			[int(harm.get("dst", -1))], -1, {}, int(harm.get("point", 0)), GConst.HarmType.Attack)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty():
		return SUCCESS
	var 选项: int = int(args[0])
	# 回复期间资源可能已变化：支付前按当前资源再校验一次
	if 选项 == 灭茶苦茶_选项宝石:
		if player.gem <= 0:
			return SUCCESS
		player.set_gem(player.gem - 1)
		harm["point"] = int(harm.get("point", 0)) + 灭茶苦茶_宝石加伤
	elif 选项 == 灭茶苦茶_选项水晶:
		if player.get_energy() <= 0:
			return SUCCESS
		player.remove_energy(1)
		harm["point"] = int(harm.get("point", 0)) + 灭茶苦茶_水晶加伤
	else:
		return SUCCESS
	notice_skill(灭茶苦茶, [int(harm.get("dst", -1))])
	engine._broadcast_game()
	return SUCCESS


## 9704 的固定选项：两项顺序 / 文案稳定，做不了的那项 enabled=false（客户端置灰）。
func _灭茶苦茶选项(可宝石: bool, 可水晶: bool) -> Array:
	return [
		{"value": 灭茶苦茶_选项宝石, "label": "【宝石】本次攻击伤害 +%d" % 灭茶苦茶_宝石加伤, "enabled": 可宝石},
		{"value": 灭茶苦茶_选项水晶, "label": "【水晶】本次攻击伤害 +%d" % 灭茶苦茶_水晶加伤, "enabled": 可水晶},
	]


# ============================================================
# 9703 爱死天流：改写借用的【血腥咆哮】（helper 的覆盖点）
# ============================================================
## 条件：目标「拥有【治疗】」＝治疗 > 0（data-audit A39）。
func _ai_si_tian_liu_条件(目标: BattlePlayer) -> bool:
	return 目标 != null and 目标.cross_num > 0


## 效果：保留 9703 能落实的部分 —— 本次攻击无法使用【圣光】抵挡。
## 「无法用【暗灭】应战」需要 battle_engine.gd 的应战询问增加「禁止指定牌应战」标志
## （data-audit Q2）；本任务只改角色 / 用例，接入引擎任务后在这里补同一处判断。
func _ai_si_tian_liu_效果(ctx: Dictionary, _目标: BattlePlayer) -> int:
	ctx["can_light"] = false
	return SUCCESS

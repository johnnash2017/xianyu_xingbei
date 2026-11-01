extends BattleRole
## 见习制片（roleID 93）—— 特典版本
## 技能：
##   元子吸收（9301，响应）：你对目标角色造成法术伤害时③，你 +1【元子】。
##   元子重塑（9302，法术）：移除 2 点【元子】，弃 X 张牌、摸 X 张牌（X = 1~3），额外 +1【法术行动】。
##   元素学徒（9303，响应）：可以使用元素师的独有技（1101~1105），校验 / 结算转到 F5 的 helper。
##   雷击变异（9304，被动）：你发动【雷击】时，把「我方战绩区 +1 宝石」改为「你 +1 元子」。
##   月陨（9305，法术 / 必杀技）：支付 1【宝石】，对目标角色造成（剩余能量 + 1）点法术伤害③。
##
## 【元子】是角色表「指示物」槽 0 的计数指示物（上限 3），名称 / 上限从表里读，
## 计数一律走 player.add_token / remove_token，不在这里写死。
##
## 借用元素师独有技见 scripts/battle/skills/skill_elemental.gd：只给 helper 设「雷击后续」覆盖，
## 不改 role_yuansu.gd；元素师本人仍走自己的脚本，行为不回归。

const 元素师技能脚本: GDScript = preload("res://scripts/battle/skills/skill_elemental.gd")

const 元子吸收: int = 9301
const 元子重塑: int = 9302
const 元素学徒: int = 9303
const 雷击变异: int = 9304
const 月陨: int = 9305

## 元素师【雷击】的技能号（helper 的覆盖键，也是卡牌上带的技能号）
const 雷击: int = 1105

const 元素槽: int = 0
## 元子重塑的选牌上限：X<4 → X 取 1~3 张
const 重塑最多弃牌: int = 3
## 元子重塑的【元子】费用
const 重塑费用: int = 2

## 借用的元素师五颗独有法术（helper）；构造传自己，本角色只做路由
var _元素法术: Variant = null


func _init() -> void:
	_元素法术 = 元素师技能脚本.new(self)
	# 9304【雷击变异】：雷击的默认后续是「我方战绩区 +1 宝石」，
	# 这里替换成「你 +1 元子」；时点与元素师原版一致（雷击造成的伤害结算完、法术行动结束钩子）。
	_元素法术.设置覆盖(雷击, {"后续": Callable(self, "_雷击变异后续")})


# ============================================================
# 技能栏：自己的【元子重塑】+ 借用的元素师五颗独有法术
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	# 9302 元子重塑：X 由选了几张牌决定（1~3）；不够 2 元子或手里没牌时照常摆出、只置灰
	out.append({
		"type": GConst.ActionType.MagicSkill,
		"id": 元子重塑,
		"need_card": 1,
		"need_target": 0,
		"card_max": 重塑最多弃牌,
		"enabled": _可重塑(),
	})
	# 9305 月陨：费用写【宝石】，必须真有宝石；没有时照常摆出、只置灰
	out.append({
		"type": GConst.ActionType.MagicSkill,
		"id": 月陨,
		"need_card": 0,
		"need_target": 1,
		"enabled": player.gem > 0,
	})
	out.append_array(_元素法术.available_skills())
	return out


func _可重塑() -> bool:
	return player.token_num(元素槽) >= 重塑费用 and not player.hand_cards.is_empty()


# ============================================================
# 法术技能校验
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	# 1101~1105 是借用的元素师独有技，交给 helper 校验
	if bool(_元素法术.处理技能(技能号)):
		return int(_元素法术.v_magic_skill(action))
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match 技能号:
		元子重塑:
			return _校验元子重塑(action)
		月陨:
			return _校验月陨(action)
	return GConst.GE_INVALID_ACTION


func _校验元子重塑(action: Dictionary) -> int:
	if player.token_num(元素槽) < 重塑费用:
		return GConst.GE_INVALID_ACTION
	if not _合法重塑牌(action.get("card_ids", [])):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 元子重塑的弃牌是否合法：X<4 → 1~3 张、都在手里、不重复。
## 校验与结算共用同一份判断，避免「校验通过、结算时 take_from_hand 失败却仍把牌塞进弃牌堆」。
func _合法重塑牌(牌表: Array) -> bool:
	if 牌表.is_empty() or 牌表.size() > 重塑最多弃牌:
		return false
	var 已选: Array[int] = []
	for 值: Variant in 牌表:
		var 牌号: int = int(值)
		if 已选.has(牌号) or not player.has_hand_card(牌号):
			return false
		已选.append(牌号)
	return true


func _校验月陨(action: Dictionary) -> int:
	# 费用写【宝石】：必须真有宝石，不能用【水晶】顶（与【水晶】费用相反，见《技能维护约定》）
	if player.gem <= 0:
		return GConst.GE_INVALID_ACTION
	var 目标表: Array = action.get("dst_ids", [])
	# 技能原文是「对目标角色」：必须且只能指定 1 名（可选自己）
	if 目标表.is_empty() or 目标表.size() > 1:
		return GConst.GE_INVALID_ACTION
	if engine.p(int(目标表[0])) == null:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


# ============================================================
# 法术技能结算
# ============================================================
func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if bool(_元素法术.处理技能(技能号)):
		return int(_元素法术.p_magic_skill(action))
	match 技能号:
		元子重塑:
			return _元子重塑结算(action)
		月陨:
			return _月陨结算(action)
	return EMPTY_HANDLE


## 9302：移除 2【元子】→ 弃 X 张牌、摸 X 张牌 → 额外 +1【法术行动】。
## 摸牌走 push_draw（尊重【水影】这类「摸牌前」响应），故压入后返回 URGENT：
## 引擎先结算摸牌，再跑行动结束钩子，最后进入这份额外法术行动。
func _元子重塑结算(action: Dictionary) -> int:
	var 牌表: Array = action.get("card_ids", [])
	if not _合法重塑牌(牌表):
		return EMPTY_HANDLE
	if not player.remove_token(元素槽, 重塑费用):
		return EMPTY_HANDLE
	if not engine.take_from_hand(player.id, 牌表):
		return EMPTY_HANDLE
	notice_skill(元子重塑, [player.id])
	engine.to_discard(牌表, {"owner": player.id, "source": "hand"})
	engine._log_discard(player.id, 牌表)
	# direct=true：直接进入额外法术行动，不再二次询问；skip_notice=true：上面已播报过 9302
	player.add_action(GConst.ActionType.Magic, 元子重塑, true, true)
	engine._broadcast_game()
	engine.push_draw(player.id, 牌表.size(), 元子重塑)
	return URGENT


## 9305：支付 1【宝石】→ 对目标角色造成（支付后剩余能量 + 1）点法术伤害③。
## X 在扣费后计算（data-audit A36：先扣费再算当前能量）。
func _月陨结算(action: Dictionary) -> int:
	var 目标表: Array = action.get("dst_ids", [])
	var 目标号: int = int(目标表[0]) if not 目标表.is_empty() else player.id
	if engine.p(目标号) == null or player.gem <= 0:
		return EMPTY_HANDLE
	notice_skill(月陨, [目标号])
	player.set_gem(player.gem - 1)
	var 点数: int = player.get_energy() + 1
	engine.push_harm({
		"src": player.id, "dst": 目标号, "point": 点数,
		"cause": 月陨, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 9301 元子吸收：对目标角色造成法术伤害时③ → +1【元子】
# 与元素师【元素吸收】同型：每个受伤目标各触发一次，上限由角色表的指示物上限截断。
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	notice_skill(元子吸收, [int(harm.get("dst", -1))])
	player.add_token(元素槽, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 法术行动结束：结算借用的冰冻治疗 / 雷击后续（9304 已覆盖成 +1 元子）
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	return int(_元素法术.p_after_magic(ctx))


## 9304【雷击变异】的后续回调（由 helper 在雷击的法术行动结束钩子里调用）：
## 把「我方战绩区 +1 宝石」替换为「你 +1 元子」。
func _雷击变异后续(_helper: Variant) -> void:
	player.add_token(元素槽, 1)
	engine._broadcast_game()

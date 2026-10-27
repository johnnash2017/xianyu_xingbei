extends RefCounted
## F5-C 元素师（11）独有技 helper：1101 风刃 / 1102 冰冻 / 1103 火球 / 1104 陨石 / 1105 雷击
##
## 供「借用元素师独有技」的角色（如见习制片 93 的【元素学徒】9303）使用：只做发动牌校验 +
## 结算 + 后续效果，不绑定角色号，也不改 role_yuansu.gd（元素师本人仍走自己的脚本）。
##
## 借用方用法（构造传借用角色自己）：
##   const 元素法术 = preload("res://scripts/battle/skills/skill_elemental.gd")
##   var _元素法术: Variant = null
##   func setup(p: BattlePlayer, e: BattleEngine) -> void:
##       super.setup(p, e)
##       _元素法术 = 元素法术.new(self)
##   func available_skills() -> Array:
##       var out: Array = []
##       out.append_array(_元素法术.available_skills())
##       return out
##   func v_magic_skill(action: Dictionary) -> int:
##       if _元素法术.处理技能(int(action.get("action_id", 0))):
##           return _元素法术.v_magic_skill(action)
##       ...  # 其它技能
##   func p_magic_skill(action: Dictionary) -> int:
##       if _元素法术.处理技能(int(action.get("action_id", 0))):
##           return _元素法术.p_magic_skill(action)
##       ...
##   func p_after_magic(ctx: Dictionary) -> int:
##       return _元素法术.p_after_magic(ctx)  # 冰冻治疗 / 雷击宝石在行动结束钩子结算
##
## 覆盖（如 9304【雷击变异】把「我方战绩区 +1 宝石」改成「你 +1 元子」）：
##   _元素法术.设置覆盖(元素法术.雷击, {"后续": 回调})
##   回调签名 func(helper) -> void；传 Callable() 表示「本次不结算后续」。
##   其它配置项见 设置覆盖() 注释；不需要时保持默认，行为与 role_yuansu.gd 一致。

const 风刃: int = 1101
const 冰冻: int = 1102
const 火球: int = 1103
const 陨石: int = 1104
const 雷击: int = 1105

## 五颗独有法术（顺序与 role_yuansu.available_skills 的技能栏一致：
## 陨石 / 风刃 / 火球 / 雷击 / 冰冻）
const 元素法术: Array = [陨石, 风刃, 火球, 雷击, 冰冻]

## 各独有法术的发动牌系别：第 1 张（发动牌）必须带该技能，额外弃的第 2 张起必须是这个系
const 法术系别: Dictionary = {
	风刃: GConst.CardElement.Wind,
	冰冻: GConst.CardElement.Water,
	火球: GConst.CardElement.Fire,
	陨石: GConst.CardElement.Earth,
	雷击: GConst.CardElement.Thunder,
}

## 需要几名目标：冰冻 = 伤害目标 + 治疗目标，其余 = 1 名目标
const 目标数: Dictionary = {
	冰冻: 2,
}

## 借用它的角色（构造时传入；helper 不持有自己的 player / engine）。
## 用弱引用，避免「角色持有 helper、helper 又持有角色」的 RefCounted 循环泄漏。
var _角色引用: WeakRef = null
var _角色: BattleRole:
	get: return _角色引用.get_ref() as BattleRole if _角色引用 != null else null
	set(value): _角色引用 = weakref(value) if value != null else null

## 借用方允许用的法术子集（默认五颗全给；93 这类「只能用其中几张」的传自己的表）
var 技能列表: Array[int] = []

## 借用方对单个技能的覆盖，见 设置覆盖()
var _覆盖: Dictionary = {}

## 本次技能结算里等待「法术行动结束」补算的后续（冰冻 / 雷击）
var _待结算技能: int = 0
var _冰冻治疗目标: int = -1


func _init(角色: BattleRole, 子集: Array = []) -> void:
	_角色 = 角色
	for 技能号: Variant in (元素法术 if 子集.is_empty() else 子集):
		var sid: int = int(技能号)
		if 元素法术.has(sid) and not 技能列表.has(sid):
			技能列表.append(sid)


## helper 是否已绑定到可用角色（角色、玩家、引擎都在）
func 可用() -> bool:
	return _角色 != null and _角色.player != null and _角色.engine != null


## 本 helper 是否负责这个技能号（借用角色据此把请求转进来）
func 处理技能(技能号: int) -> bool:
	return 技能列表.has(技能号)


# ============================================================
# 借用方覆盖（9304 等）
# ============================================================
## 设置 / 增量合并某个技能的覆盖项：
##   "伤害加成": int 或 Callable(helper, 技能号, 基础点数, action) -> int
##   "后续": Callable(helper) -> void；替换默认后续（默认：冰冻 +1 治疗、雷击 +1 宝石）
##   "可用": Callable() -> bool；覆盖 available_skills 里的 enabled（其它条件不变）
##   "播报技能号": int；技能播报改用另一个技能号（默认仍是 1101~1105）
##   "额外加伤上限": int；额外弃同系牌最多几张，默认 1，设 0 表示不允许额外弃牌
func 设置覆盖(技能号: int, 配置: Dictionary) -> void:
	if not 元素法术.has(技能号):
		return
	var 当前: Dictionary = _覆盖.get(技能号, {})
	for 键: Variant in 配置:
		当前[键] = 配置[键]
	_覆盖[技能号] = 当前


## 清掉某个技能的覆盖，恢复元素师默认行为
func 清除覆盖(技能号: int) -> void:
	_覆盖.erase(技能号)


func _配置(技能号: int) -> Dictionary:
	return _覆盖.get(技能号, {})


func _额外加伤上限(技能号: int) -> int:
	return maxi(int(_配置(技能号).get("额外加伤上限", 1)), 0)


# ============================================================
# 技能栏：五颗独有法术作为主动法术技能下发（与 role_yuansu.available_skills 同口径）
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	if not 可用():
		return out
	for 技能号: int in 技能列表:
		var 发动牌: Array[int] = _角色.hand_ids_with_skill(技能号)
		var 元素: int = int(法术系别[技能号])
		var 额外上限: int = _额外加伤上限(技能号)
		# 第 1 张必须是带该技能的发动牌；第 2 张起可再弃同系牌加伤，
		# 所以白名单 = 发动牌 + 该系牌（没有额外加伤上限时只亮发动牌）
		var 合法牌: Array[int] = 发动牌.duplicate()
		if 额外上限 > 0:
			for cid: int in _角色.hand_ids_where(func(_cid: int, c: GCard) -> bool:
					return c.element_enum() == 元素):
				if not 合法牌.has(cid):
					合法牌.append(cid)
		# 条件不满足时也要下发（enabled=false 置灰），玩家得看得见技能存在
		var 可点: bool = not 发动牌.is_empty()
		var 配置: Dictionary = _配置(技能号)
		if 配置.has("可用") and 配置["可用"] is Callable:
			var 判定: Callable = 配置["可用"]
			if 判定.is_valid():
				可点 = bool(判定.call())
		out.append({
			"type": GConst.ActionType.MagicSkill,
			"id": 技能号,
			"need_card": 1,
			"need_target": int(目标数.get(技能号, 1)),
			"card_max": 1 + 额外上限,
			"cards": 合法牌,
			"card_slot_skill": 技能号,
			"card_slot_element": 元素,
			"enabled": 可点,
		})
	return out


# ============================================================
# 校验（对应 role_yuansu.v_magic_skill 的五颗独有法术部分）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if not 可用():
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("src_id", -1)) != _角色.player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if not 处理技能(技能号):
		return GConst.GE_EMPTY_HANDLE
	# 覆盖项「可用」不仅用于 available_skills 置灰，服务端校验也要兜底：
	# 客户端硬提交被置灰的技能时直接拒绝（技能维护约定：置灰项服务端仍要校验）。
	var 配置: Dictionary = _配置(技能号)
	if 配置.has("可用") and 配置["可用"] is Callable:
		var 判定: Callable = 配置["可用"]
		if 判定.is_valid() and not bool(判定.call()):
			return GConst.GE_INVALID_ACTION
	var 牌表: Array = action.get("card_ids", [])
	var 目标表: Array = action.get("dst_ids", [])
	if 牌表.is_empty():
		return GConst.GE_INVALID_CARDID
	var 首牌号: int = int(牌表[0])
	var 首牌: GCard = Data.get_card(首牌号)
	# 第 1 张（发动牌）必须是手里带该技能的牌
	if not _角色.player.has_hand_card(首牌号) or 首牌 == null or not 首牌.has_skill_id(技能号):
		return GConst.GE_INVALID_ACTION
	var 额外上限: int = _额外加伤上限(技能号)
	if 牌表.size() > 1 + 额外上限:
		return GConst.GE_INVALID_ACTION
	var 已选: Array[int] = [首牌号]
	for i: int in range(1, 牌表.size()):
		var 牌号: int = int(牌表[i])
		if 已选.has(牌号):
			return GConst.GE_INVALID_ACTION
		已选.append(牌号)
		var 牌: GCard = Data.get_card(牌号)
		# 额外弃的必须是该法术对应系的牌（技能原文「额外弃 1 张 X 系牌【展示】」）
		if not _角色.player.has_hand_card(牌号) or 牌 == null \
				or 牌.element_enum() != int(法术系别[技能号]):
			return GConst.GE_INVALID_ACTION
	# 每颗法术都要至少 1 名目标；冰冻另要 1 名治疗目标（可与伤害目标同一人）
	var 目标下限: int = int(目标数.get(技能号, 1))
	if 目标表.size() < 目标下限:
		return GConst.GE_INVALID_ACTION
	for dst: Variant in 目标表:
		if _角色.engine.p(int(dst)) == null:
			return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


# ============================================================
# 结算（对应 role_yuansu.p_magic_skill 的五颗独有法术部分）
# ============================================================
func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if not 处理技能(技能号):
		return BattleRole.EMPTY_HANDLE
	# 每次结算先清掉上一颗法术可能遗留的待结算后续，避免跨行动误结算
	_待结算技能 = 0
	_冰冻治疗目标 = -1
	if 技能号 == 风刃:
		# 风刃：额外 +1 攻击行动（技能通告由 _结算伤害 发）
		_角色.player.add_action(GConst.ActionType.Attack, 风刃, true, true)
	elif 技能号 == 陨石:
		# 陨石：额外 +1 法术行动
		_角色.player.add_action(GConst.ActionType.Magic, 陨石, true, true)
	elif 技能号 == 冰冻:
		# 冰冻的第 2 名目标是「+1 治疗」的目标，等行动结束钩子再补
		var dsts: Array = action.get("dst_ids", [])
		_冰冻治疗目标 = int(dsts[1]) if dsts.size() > 1 else _角色.player.id
		_待结算技能 = 冰冻
	elif 技能号 == 雷击:
		# 雷击的「战绩区 +1 宝石」等行动结束钩子再补（借用方可用「后续」覆盖）
		_待结算技能 = 雷击
	return _结算伤害(action)


## 展示并弃掉发动牌（+ 额外弃的同系牌），按张数造成法术伤害；火球基础 2 点。
## 返回 URGENT：伤害已压栈，技能行动要等它结算完再跑 p_after_magic。
func _结算伤害(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	var 目标表: Array = action.get("dst_ids", [])
	var 目标号: int = int(目标表[0]) if not 目标表.is_empty() else _角色.player.id
	var 牌表: Array = action.get("card_ids", [])
	var 用牌: Array[int] = []
	for i: int in range(mini(牌表.size(), 1 + _额外加伤上限(技能号))):
		用牌.append(int(牌表[i]))
	if 用牌.is_empty():
		return BattleRole.EMPTY_HANDLE
	var 点数: int = 伤害点数(技能号, 用牌)
	var 配置: Dictionary = _配置(技能号)
	if 配置.has("伤害加成"):
		var 加成: Variant = 配置["伤害加成"]
		if 加成 is Callable and (加成 as Callable).is_valid():
			点数 = int((加成 as Callable).call(self, 技能号, 点数, action))
		elif not (加成 is Callable):
			点数 += int(加成)
	_角色.notice_skill(_播报号(技能号), [目标号])
	_角色.engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": _角色.player.id, "dst_id": _角色.player.id,
		"card_ids": 用牌, "is_real": true,
	})
	_角色.engine.push_harm({
		"src": _角色.player.id, "dst": 目标号, "point": 点数,
		"cause": 技能号, "type": GConst.HarmType.Magic,
	})
	_角色.engine.take_from_hand(_角色.player.id, 用牌, true)
	_角色.engine.to_discard(用牌)
	_角色.engine._broadcast_game()
	return BattleRole.URGENT


## 本次伤害点数：每张牌 1 点（第 1 张发动牌也计 1 点），火球再 +1
func 伤害点数(技能号: int, 用牌: Array) -> int:
	var 点数: int = 用牌.size()
	if 技能号 == 火球:
		点数 += 1
	return 点数


## 打出的牌是不是这五颗法术之一（借用角色把「牌上技能」映射成 1101~1105 用）
func 牌上法术(牌号: int) -> int:
	var 牌: GCard = Data.get_card(牌号)
	if 牌 == null:
		return 0
	for 技能号: int in 元素法术:
		if 牌.has_skill_id(技能号):
			return 技能号
	return 0


func _播报号(技能号: int) -> int:
	var 配置: Dictionary = _配置(技能号)
	if 配置.has("播报技能号"):
		return int(配置["播报技能号"])
	return 技能号


# ============================================================
# 法术行动结束：结算冰冻 / 雷击的追加效果
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	if not 可用():
		return BattleRole.SUCCESS
	if int(ctx.get("player", -1)) != _角色.player.id:
		return BattleRole.SUCCESS
	var 技能号: int = int(ctx.get("action_id", 0))
	if 技能号 == 0:
		# 普通卡牌施法路径只带 card_id：按牌上的独有技还原
		技能号 = 牌上法术(int(ctx.get("card_id", 0)))
	if 技能号 == 0 or 技能号 != _待结算技能:
		return BattleRole.SUCCESS
	if 技能号 == 冰冻:
		_待结算技能 = 0
		var 目标号: int = _冰冻治疗目标
		_冰冻治疗目标 = -1
		var 目标: BattlePlayer = _角色.engine.p(目标号)
		if 目标 != null:
			_角色.施加治疗(目标.id, 1)
			_角色.engine._broadcast_game()
	elif 技能号 == 雷击:
		_待结算技能 = 0
		var 配置: Dictionary = _配置(雷击)
		if 配置.has("后续"):
			var 后续: Variant = 配置["后续"]
			if 后续 is Callable and (后续 as Callable).is_valid():
				(后续 as Callable).call(self)
			return BattleRole.SUCCESS
		_角色.engine.set_team_gem(_角色.player.color, _角色.engine.team_gem[_角色.player.color] + 1)
		_角色.engine._broadcast_game()
	return BattleRole.SUCCESS

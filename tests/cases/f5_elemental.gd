extends 自检用例
## F5-C 元素师（11）独有技 helper：1101 风刃 / 1102 冰冻 / 1103 火球 / 1104 陨石 / 1105 雷击。
##
## 验证点：
##   1. 五颗法术的发动牌校验：第 1 张必须带该技能，额外弃的牌必须同系，目标数（冰冻 2 名）；
##   2. 额外弃同系牌加伤（火球基础 2 点、其余 1 点）；
##   3. 各自后续：风刃 +1 攻击行动、陨石 +1 法术行动、冰冻 +1 治疗、雷击 +1 宝石（都在行动结束钩子补算）；
##   4. 9304【雷击变异】需要的覆盖扩展点（把雷击后续换成 +1 元子）和「伤害加成 / 可用」覆盖。
##
## 「dummy 借用角色」：先把 1 号玩家的角色换成只把四个入口转发给 helper 的假角色，
## 再让五颗法术各走一次完整结算；不改 role_yuansu.gd。

const 元素helper = preload("res://scripts/battle/skills/skill_elemental.gd")

const 风刃: int = 1101
const 冰冻: int = 1102
const 火球: int = 1103
const 陨石: int = 1104
const 雷击: int = 1105

var 引擎: BattleEngine
var 借用者: BattlePlayer
var 假角色: BattleRole
var 法术: Variant = null


## 只转发给 helper 的 dummy 借用角色（模拟 93 见习制片这类「借用元素师独有技」的角色）
class 借用角色:
	extends BattleRole

	const 元素helper脚本 = preload("res://scripts/battle/skills/skill_elemental.gd")

	var 法术: Variant = null


	func setup(p: BattlePlayer, e: BattleEngine) -> void:
		super.setup(p, e)
		法术 = 元素helper脚本.new(self)


	func available_skills() -> Array:
		return 法术.available_skills()


	func v_magic_skill(action: Dictionary) -> int:
		return 法术.v_magic_skill(action)


	func p_magic_skill(action: Dictionary) -> int:
		return 法术.p_magic_skill(action)


	func p_after_magic(ctx: Dictionary) -> int:
		return 法术.p_after_magic(ctx)


func _init() -> void:
	名称 = "元素独有技helper"


# ============================================================
# 工具
# ============================================================
func _取技能牌(技能号: int) -> GCard:
	for 牌: GCard in Data.card_db:
		if 牌 != null and not 牌.is_virtual and 牌.has_skill_id(技能号):
			return 牌
	return null


func _取同系牌(系: int, 排除: Array = []) -> GCard:
	for 牌: GCard in Data.card_db:
		if 牌 != null and not 牌.is_virtual and 牌.element_enum() == 系 \
				and not 排除.has(牌.id):
			return 牌
	return null


func _找技能(表: Array, 技能号: int) -> Dictionary:
	for 技能: Dictionary in 表:
		if int(技能.get("id", 0)) == 技能号:
			return 技能
	return {}


func _弃牌数(card_id: int) -> int:
	var n: int = 0
	for c: Variant in 引擎.deck.discard:
		if int(c) == card_id:
			n += 1
	return n


func _找伤害(cause: int, dst: int) -> Dictionary:
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var h: Variant = st.get("harm")
		if h is Dictionary and int((h as Dictionary).get("cause", 0)) == cause \
				and int((h as Dictionary).get("dst", -1)) == dst:
			return h as Dictionary
	return {}


func _有额外行动(行动类型: int, cause: int) -> bool:
	for a: Variant in 借用者.additional_actions:
		if a is Dictionary and int((a as Dictionary).get("allow_action", 0)) == 行动类型 \
				and int((a as Dictionary).get("cause", 0)) == cause:
			return true
	return false


## 每个结算用例前把双方场面清干净（伤害/宝石/治疗/额外行动/手牌/弃牌堆）
func _准备(牌号表: Array) -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎.last_harm_cause = 0
	引擎.last_harm_type = 0
	借用者.hand_cards.clear()
	借用者.cover_cards.clear()
	借用者.basic_effects.clear()
	借用者.additional_actions.clear()
	if 借用者.tokens.has(0):
		借用者.tokens[0]["num"] = 0
	for pid: int in 引擎.order:
		var pp: BattlePlayer = 引擎.p(pid)
		if pp != null:
			pp.cross_num = 0
	引擎.team_gem[GConst.BLUE] = 0
	引擎.team_gem[GConst.RED] = 0
	引擎.deck.discard.clear()
	for 牌号: Variant in 牌号表:
		借用者.hand_cards.append(int(牌号))


func _搭建() -> bool:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "借用者")
	引擎.add_player(2, GConst.RED, "红二")
	引擎.add_player(3, GConst.BLUE, "蓝三")
	引擎.add_player(4, GConst.RED, "红四")
	引擎.start_with_roles({1: 11, 2: 0, 3: 0, 4: 0})
	引擎._states.clear()
	引擎._清空等待()
	借用者 = 引擎.p(1)
	var 原角色: BattleRole = 借用者.role if 借用者 != null else null
	检(原角色 != null, "11 号元素师角色脚本应能加载")
	if 原角色 == null or 借用者 == null:
		return false
	var 假 = 借用角色.new()
	假.setup(借用者, 引擎)
	借用者.role = 假
	假角色 = 假
	法术 = 假.法术
	检(假角色 != null and 法术 != null, "dummy 借用角色 / helper 未创建")
	return 法术 != null


# ============================================================
# 用例
# ============================================================
func 跑() -> void:
	await 等帧(1)
	if not _搭建():
		return

	检(Data.role_script(11) == "res://scripts/battle/roles/role_yuansu.gd",
		"元素师脚本路径变了，本 helper 的参考实现需要重新对照")
	检(假角色.player == 借用者 and 假角色.engine == 引擎, "dummy 借用角色没接上玩家 / 引擎")
	检(法术.可用(), "helper 应在角色 / 玩家 / 引擎就绪后可用")

	# ---- 技能号 / 处理范围 ----
	for 技能号: int in [风刃, 冰冻, 火球, 陨石, 雷击]:
		检(法术.处理技能(技能号), "helper 应处理 %d" % 技能号)
	检(not 法术.处理技能(1106), "【元素点燃】不属于本 helper（原角色另有实现）")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 1106})) == GConst.GE_EMPTY_HANDLE,
		"非本 helper 的技能应返回 GE_EMPTY_HANDLE，便于借用方继续处理其它技能")

	var 风刃卡: GCard = _取技能牌(风刃)
	var 冰冻卡: GCard = _取技能牌(冰冻)
	var 火球卡: GCard = _取技能牌(火球)
	var 陨石卡: GCard = _取技能牌(陨石)
	var 雷击卡: GCard = _取技能牌(雷击)
	var 风系副: GCard = _取同系牌(GConst.CardElement.Wind, [风刃卡.id] if 风刃卡 != null else [])
	var 风系副二: GCard = _取同系牌(GConst.CardElement.Wind,
		[风刃卡.id, 风系副.id] if 风刃卡 != null and 风系副 != null else [])
	var 水系副: GCard = _取同系牌(GConst.CardElement.Water, [冰冻卡.id] if 冰冻卡 != null else [])
	var 火系副: GCard = _取同系牌(GConst.CardElement.Fire, [火球卡.id] if 火球卡 != null else [])
	var 地系副: GCard = _取同系牌(GConst.CardElement.Earth, [陨石卡.id] if 陨石卡 != null else [])
	检(风刃卡 != null and 冰冻卡 != null and 火球卡 != null and 陨石卡 != null and 雷击卡 != null,
		"卡表里找不到 1101~1105 的发动牌")
	检(风系副 != null and 风系副二 != null and 水系副 != null and 火系副 != null and 地系副 != null,
		"卡表里凑不齐四系的额外加伤牌")
	if 风刃卡 == null or 冰冻卡 == null or 火球卡 == null or 陨石卡 == null or 雷击卡 == null \
			or 风系副 == null or 风系副二 == null or 水系副 == null or 火系副 == null or 地系副 == null:
		return

	# ---- 技能栏：五颗都下发，没发动牌的置灰；白名单只亮发动牌 + 同系牌 ----
	_准备([风刃卡.id, 火球卡.id])
	var 技能表: Array = 法术.available_skills()
	检(技能表.size() == 5, "五颗独有法术都应下发，实际 %d 条" % 技能表.size())
	for 技能号: int in [风刃, 冰冻, 火球, 陨石, 雷击]:
		检(not _找技能(技能表, 技能号).is_empty(), "技能栏缺 %d" % 技能号)
	var 风刃条目: Dictionary = _找技能(技能表, 风刃)
	检(bool(风刃条目.get("enabled", false)), "手里有【风刃】发动牌时应可点")
	检(int(风刃条目.get("need_target", 0)) == 1, "【风刃】只需 1 名目标")
	检(int(风刃条目.get("card_max", 0)) == 2, "【风刃】应可额外弃 1 张同系牌（card_max=2）")
	检(int(风刃条目.get("card_slot_element", 0)) == GConst.CardElement.Wind,
		"【风刃】的额外弃牌系别应为风系")
	var 风刃白名单: Array = 风刃条目.get("cards", [])
	检(风刃白名单.has(风刃卡.id), "【风刃】白名单应包含发动牌")
	检(not 风刃白名单.has(火球卡.id), "【风刃】白名单不应包含火系牌")
	var 冰冻条目: Dictionary = _找技能(技能表, 冰冻)
	检(not 冰冻条目.is_empty(), "没有【冰冻】发动牌时按钮仍应下发（置灰）")
	检(not bool(冰冻条目.get("enabled", true)), "没有【冰冻】发动牌时应置灰")
	检(int(冰冻条目.get("need_target", 0)) == 2, "【冰冻】需要伤害目标 + 治疗目标共 2 名")
	检(bool(_找技能(技能表, 火球).get("enabled", false)), "手里有【火球】发动牌时应可点")
	检(int(_找技能(技能表, 火球).get("card_slot_element", 0)) == GConst.CardElement.Fire,
		"【火球】的额外弃牌系别应为火系")

	_准备([风刃卡.id, 风系副.id])
	风刃条目 = _找技能(法术.available_skills(), 风刃)
	风刃白名单 = 风刃条目.get("cards", [])
	检(风刃白名单.has(风刃卡.id) and 风刃白名单.has(风系副.id),
		"【风刃】白名单应同时亮发动牌和同系额外牌：%s" % str(风刃白名单))

	# ---- 校验：发动牌 / 额外同系 / 目标数 / 重复牌 / 超出额外数 ----
	_准备([风刃卡.id, 风系副.id, 水系副.id])
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃, "card_ids": [风刃卡.id], "dst_ids": [2]})) \
		== GConst.GE_SUCCESS, "【风刃】单发动牌应校验通过")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id], "dst_ids": [2]})) == GConst.GE_SUCCESS,
		"【风刃】额外弃 1 张风系牌应校验通过")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 水系副.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"【风刃】额外弃的牌不是风系应拒绝")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [水系副.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"第 1 张不是带【风刃】的牌应拒绝")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [], "dst_ids": [2]})) == GConst.GE_INVALID_CARDID,
		"没有牌应返回 GE_INVALID_CARDID")
	检(int(法术.v_magic_skill({"src_id": 2, "action_id": 风刃,
		"card_ids": [风刃卡.id], "dst_ids": [2]})) == GConst.GE_INVALID_PLAYERID,
		"不是自己发动的应拒绝")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id], "dst_ids": []})) == GConst.GE_INVALID_ACTION,
		"【风刃】没有目标应拒绝")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风刃卡.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"同一张牌不能既当发动牌又当额外牌")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id, 风系副.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"同一张额外牌不能重复提交两次")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id, 火系副.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"超出额外 1 张应拒绝")

	# 额外加伤上限=2：同一张额外牌重复提交必须被拒；两张不同额外牌应通过并按 3 张结算。
	# 这一段专门保证「已选」去重分支真的被执行（上限=1 时 3 张牌会先被张数上限挡掉）。
	法术.设置覆盖(风刃, {"额外加伤上限": 2})
	_准备([风刃卡.id, 风系副.id, 风系副二.id])
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id, 风系副.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"上限=2 时同一张额外牌也不能重复提交两次")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id, 风系副二.id], "dst_ids": [2]})) == GConst.GE_SUCCESS,
		"上限=2 时两张不同的同系额外牌应通过")
	var 前首: int = _弃牌数(风刃卡.id)
	var 前副: int = _弃牌数(风系副.id)
	var 前副二: int = _弃牌数(风系副二.id)
	var 双额外动作: Dictionary = {
		"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id, 风系副二.id], "dst_ids": [2],
	}
	检(int(法术.p_magic_skill(双额外动作)) == BattleRole.URGENT, "两张额外牌应结算")
	检(int(_找伤害(风刃, 2).get("point", 0)) == 3, "【风刃】1 张发动牌 + 2 张额外牌应打 3 点伤害")
	for c: GCard in [风刃卡, 风系副, 风系副二]:
		检(not 借用者.hand_cards.has(c.id), "额外牌结算后应离手：%d" % c.id)
	检(_弃牌数(风刃卡.id) == 前首 + 1 and _弃牌数(风系副.id) == 前副 + 1
		and _弃牌数(风系副二.id) == 前副二 + 1,
		"每张发动牌 / 额外牌都应各只进弃牌堆一次")
	法术.清除覆盖(风刃)

	_准备([冰冻卡.id, 水系副.id])
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 冰冻,
		"card_ids": [冰冻卡.id, 水系副.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"【冰冻】只给 1 名目标应拒绝")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 冰冻,
		"card_ids": [冰冻卡.id, 水系副.id], "dst_ids": [2, 3]})) == GConst.GE_SUCCESS,
		"【冰冻】给伤害 + 治疗 2 名目标应校验通过")

	# ---- 额外加伤上限覆盖（9303 这类「不许额外弃牌」可用） ----
	法术.设置覆盖(风刃, {"额外加伤上限": 0})
	_准备([风刃卡.id, 风系副.id])
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"额外加伤上限为 0 时不能再额外弃同系牌")
	检(int(_找技能(法术.available_skills(), 风刃).get("card_max", 0)) == 1,
		"额外加伤上限为 0 时 card_max 应回到 1")
	法术.清除覆盖(风刃)

	# ---- 可用覆盖：借用方可以把某颗法术整颗置灰 ----
	法术.设置覆盖(风刃, {"可用": func() -> bool: return false})
	_准备([风刃卡.id])
	检(not bool(_找技能(法术.available_skills(), 风刃).get("enabled", true)),
		"覆盖「可用」应能把按钮置灰")
	检(int(法术.v_magic_skill({"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id], "dst_ids": [2]})) == GConst.GE_INVALID_ACTION,
		"覆盖「可用」为 false 时，v_magic_skill 也要兜底拒绝硬提交")
	法术.清除覆盖(风刃)

	# ---- 风刃：额外弃风系牌 +1 伤害，并追加 1 次攻击行动 ----
	_准备([风刃卡.id, 风系副.id])
	var 风刃动作: Dictionary = {"src_id": 1, "action_id": 风刃,
		"card_ids": [风刃卡.id, 风系副.id], "dst_ids": [2]}
	检(int(法术.v_magic_skill(风刃动作)) == GConst.GE_SUCCESS, "【风刃】校验不通过")
	检(int(法术.p_magic_skill(风刃动作)) == BattleRole.URGENT, "【风刃】应压入法术伤害")
	检(int(_找伤害(风刃, 2).get("point", 0)) == 2, "【风刃】额外弃 1 张风系牌应打成 2 点伤害")
	检(not 借用者.hand_cards.has(风刃卡.id) and not 借用者.hand_cards.has(风系副.id),
		"【风刃】的发动牌和额外牌都应离手")
	检(引擎.deck.discard.has(风刃卡.id) and 引擎.deck.discard.has(风系副.id),
		"【风刃】用掉的牌应进弃牌堆")
	检(_有额外行动(GConst.ActionType.Attack, 风刃), "【风刃】应额外 +1 攻击行动")
	检(int(法术.p_after_magic({"player": 1, "action_id": 风刃})) == BattleRole.SUCCESS,
		"【风刃】的行动结束钩子不应再结算后续")

	# ---- 冰冻：1+1 伤害 + 治疗目标 +1 治疗 ----
	_准备([冰冻卡.id, 水系副.id])
	var 冰冻动作: Dictionary = {"src_id": 1, "action_id": 冰冻,
		"card_ids": [冰冻卡.id, 水系副.id], "dst_ids": [2, 3]}
	检(int(法术.p_magic_skill(冰冻动作)) == BattleRole.URGENT, "【冰冻】应压入法术伤害")
	检(int(_找伤害(冰冻, 2).get("point", 0)) == 2, "【冰冻】额外弃 1 张水系牌应打成 2 点伤害")
	检(引擎.p(3).cross_num == 0, "【冰冻】的治疗应在行动结束钩子才结算")
	检(int(法术.p_after_magic({"player": 1, "action_id": 冰冻})) == BattleRole.SUCCESS,
		"【冰冻】行动结束钩子应正常返回")
	检(引擎.p(3).cross_num == 1, "【冰冻】应给第 2 名目标 +1 治疗")
	检(int(法术.p_after_magic({"player": 1, "action_id": 冰冻})) == BattleRole.SUCCESS,
		"【冰冻】后续不应重复结算")
	检(引擎.p(3).cross_num == 1, "【冰冻】重复进入行动结束钩子不应再加治疗")

	# ---- 火球：基础 2 点；额外弃火系牌 +1 ----
	_准备([火球卡.id])
	var 火球动作: Dictionary = {"src_id": 1, "action_id": 火球,
		"card_ids": [火球卡.id], "dst_ids": [2]}
	检(int(法术.p_magic_skill(火球动作)) == BattleRole.URGENT, "【火球】应压入法术伤害")
	检(int(_找伤害(火球, 2).get("point", 0)) == 2, "【火球】基础伤害应为 2 点")
	_准备([火球卡.id, 火系副.id])
	火球动作 = {"src_id": 1, "action_id": 火球, "card_ids": [火球卡.id, 火系副.id], "dst_ids": [2]}
	检(int(法术.p_magic_skill(火球动作)) == BattleRole.URGENT, "【火球】额外弃牌后应结算")
	检(int(_找伤害(火球, 2).get("point", 0)) == 3, "【火球】额外弃 1 张火系牌应打成 3 点伤害")

	# ---- 陨石：1+1 伤害 + 1 次法术行动 ----
	_准备([陨石卡.id, 地系副.id])
	var 陨石动作: Dictionary = {"src_id": 1, "action_id": 陨石,
		"card_ids": [陨石卡.id, 地系副.id], "dst_ids": [2]}
	检(int(法术.p_magic_skill(陨石动作)) == BattleRole.URGENT, "【陨石】应压入法术伤害")
	检(int(_找伤害(陨石, 2).get("point", 0)) == 2, "【陨石】额外弃 1 张地系牌应打成 2 点伤害")
	检(_有额外行动(GConst.ActionType.Magic, 陨石), "【陨石】应额外 +1 法术行动")

	# ---- 雷击：伤害 1 点；行动结束我方战绩区 +1 宝石 ----
	_准备([雷击卡.id])
	var 雷击动作: Dictionary = {"src_id": 1, "action_id": 雷击,
		"card_ids": [雷击卡.id], "dst_ids": [2]}
	检(int(法术.p_magic_skill(雷击动作)) == BattleRole.URGENT, "【雷击】应压入法术伤害")
	检(int(_找伤害(雷击, 2).get("point", 0)) == 1, "【雷击】基础伤害应为 1 点")
	检(引擎.team_gem[GConst.BLUE] == 0, "【雷击】的宝石应在行动结束钩子才进战绩区")
	检(int(法术.p_after_magic({"player": 1, "action_id": 雷击})) == BattleRole.SUCCESS,
		"【雷击】行动结束钩子应正常返回")
	检(引擎.team_gem[GConst.BLUE] == 1, "【雷击】应让本队战绩区 +1 宝石")
	检(int(法术.p_after_magic({"player": 1, "action_id": 雷击})) == BattleRole.SUCCESS,
		"【雷击】后续不应重复结算")
	检(引擎.team_gem[GConst.BLUE] == 1, "【雷击】重复进入行动结束钩子不应再加宝石")

	# ---- 9304 雷击变异：用「后续」覆盖把 +1 宝石换成 +1 元子 ----
	法术.设置覆盖(雷击, {"后续": func(_h) -> void:
		借用者.tokens[0]["num"] = int(借用者.tokens[0]["num"]) + 1})
	_准备([雷击卡.id])
	检(int(法术.p_magic_skill(雷击动作)) == BattleRole.URGENT, "【雷击】覆盖后续后仍应结算伤害")
	检(int(法术.p_after_magic({"player": 1, "action_id": 雷击})) == BattleRole.SUCCESS,
		"【雷击】覆盖后续后行动结束钩子应正常返回")
	检(引擎.team_gem[GConst.BLUE] == 0, "【雷击变异】不应再给宝石")
	检(int(借用者.tokens[0]["num"]) == 1, "【雷击变异】应改为自己 +1 元子")
	法术.清除覆盖(雷击)

	# ---- 伤害加成覆盖：给雷击 +2 点（验证 Callable / 数值两种接口之一） ----
	法术.设置覆盖(雷击, {"伤害加成": 2})
	_准备([雷击卡.id])
	检(int(法术.p_magic_skill(雷击动作)) == BattleRole.URGENT, "【雷击】加伤覆盖后应结算")
	检(int(_找伤害(雷击, 2).get("point", 0)) == 3, "覆盖「伤害加成 2」后【雷击】应打成 3 点")
	法术.清除覆盖(雷击)

	# ---- 牌上法术：借用方把 9303 的牌映射成元素师技能号 ----
	检(int(法术.牌上法术(风刃卡.id)) == 风刃, "带【风刃】的牌应映射回 1101")
	检(int(法术.牌上法术(雷击卡.id)) == 雷击, "带【雷击】的牌应映射回 1105")
	var 无元素牌: GCard = null
	for 牌: GCard in Data.card_db:
		if 牌 != null and not 牌.is_virtual and int(法术.牌上法术(牌.id)) == 0:
			无元素牌 = 牌
			break
	检(无元素牌 != null, "卡表里找不到不带元素师独有技的牌")

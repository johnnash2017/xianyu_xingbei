extends 自检用例
## F5-D 封印师独有技 helper（401~405）自检。
##
## 只搭引擎、不跑全量对局：用一个 dummy「借用封印」角色把 available_skills / v_magic_skill /
## p_magic_skill / p_show_hand 全部路由到 scripts/battle/skills/skill_seal.gd，验证：
##   1. 五系封印的按钮、可点牌、合法目标（同色 / 已有同种封印要被挡）；
##   2. 放置结算：展示 → 挂到目标的基础效果区 → 离手；
##   3. 展示触发：同系牌触发 3 点法术伤害并移除封印；异系牌 / 非封印基础效果不触发；
##   4. 同一目标身上多枚封印依次触发，ctx["seals_triggered"] 防重复；
##   5. 借用入口：用借用角色自己的技能行（如 4606）转发，按牌上实际带的封印号校验与播报；
##   6. 原角色 4 封印师的脚本仍能加载、技能栏不变（helper 是新增文件，不改 role_fengyin.gd）。

const SkillSeal = preload("res://scripts/battle/skills/skill_seal.gd")
## 灵熙之潮【海神御巫】的技能号：本用例只用它验证「借用自己的技能行转发」，不加载 46 号角色
const 借用转发技能号: int = 4606


## dummy 借用角色：技能栏只多摆五系封印，三条入口原样转发给 helper
class 借用封印角色:
	extends BattleRole

	const 封印工具 = preload("res://scripts/battle/skills/skill_seal.gd")

	var 封印: 封印工具 = null
	## 0 = 直接用 action.action_id；借用自己的技能行（4606）时填牌上实际带的封印号
	var 借用技能号: int = 0

	func setup(p: BattlePlayer, e: BattleEngine) -> void:
		super.setup(p, e)
		封印 = 封印工具.new(self)

	func available_skills() -> Array:
		return 封印.available_skills()

	func v_magic_skill(action: Dictionary) -> int:
		return 封印.v_place(action, 借用技能号)

	func p_magic_skill(action: Dictionary) -> int:
		return 封印.p_place(action, 借用技能号)

	func p_show_hand(ctx: Dictionary) -> int:
		return 封印.p_show_hand(ctx)


var 引擎: BattleEngine
var 角色: 借用封印角色
var 借用者: BattlePlayer
var 靶: BattlePlayer
## 本次用例里引擎发出的广播（send_cb 收集），用来核对技能播报 / 展示牌
var 广播: Array = []


func _init() -> void:
	名称 = "F5-D 封印师独有技 helper"


# ============================================================
# 取样 / 断言工具
# ============================================================
func _取封印牌(技能号值: int, 排除: Array = []) -> GCard:
	for card: GCard in Data.card_db:
		if card == null or card.is_virtual or 排除.has(card.id):
			continue
		if card.has_skill_id(技能号值):
			return card
	return null


func _取同系牌(元素值: int, 排除: Array = []) -> GCard:
	for card: GCard in Data.card_db:
		if card == null or card.is_virtual or 排除.has(card.id):
			continue
		if card.element_enum() == 元素值:
			return card
	return null


func _找技能(表: Array, 技能号值: int) -> Dictionary:
	for 技能: Dictionary in 表:
		if int(技能.get("id", 0)) == 技能号值:
			return 技能
	return {}


## 在状态栈里找一条指定来源 / 目标的伤害，返回它的伤害字典；找不到返回空字典
func _找伤害(cause: int, dst: int) -> Dictionary:
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var harm: Variant = st.get("harm")
		if harm is Dictionary:
			var h: Dictionary = harm
			if int(h.get("cause", 0)) == cause and int(h.get("dst", -1)) == dst:
				return h
	return {}


## 指定来源 / 目标的伤害条数（验「同一张封印不会重复结算」用）
func _数伤害(cause: int, dst: int) -> int:
	var n: int = 0
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var harm: Variant = st.get("harm")
		if harm is Dictionary:
			var h: Dictionary = harm
			if int(h.get("cause", 0)) == cause and int(h.get("dst", -1)) == dst:
				n += 1
	return n


func _有技能播报(技能号值: int) -> bool:
	for 条: Dictionary in 广播:
		if int(条.get("msg", 0)) != GConst.Msg.Skill:
			continue
		if int((条.get("data", {}) as Dictionary).get("skill_id", 0)) == 技能号值:
			return true
	return false


func _有展示牌(卡号: int) -> bool:
	for 条: Dictionary in 广播:
		if int(条.get("msg", 0)) != GConst.Msg.Card:
			continue
		var data: Dictionary = 条.get("data", {})
		if int(data.get("type", 0)) == GConst.CardMsgType.Show and (data.get("card_ids", []) as Array).has(卡号):
			return true
	return false


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)
	var 地封印: GCard = _取封印牌(SkillSeal.地之封印)
	var 火封印: GCard = _取封印牌(SkillSeal.火之封印)
	检(地封印 != null and 火封印 != null, "卡库里找不到地之封印 / 火之封印的牌")
	if 地封印 == null or 火封印 == null:
		return
	var 地封印2: GCard = _取封印牌(SkillSeal.地之封印, [地封印.id])
	var 地系排除: Array = [地封印.id]
	if 地封印2 != null:
		地系排除.append(地封印2.id)
	var 地系牌: GCard = _取同系牌(GConst.CardElement.Earth, 地系排除)
	var 火系牌: GCard = _取同系牌(GConst.CardElement.Fire, [火封印.id])
	var 风系牌: GCard = _取同系牌(GConst.CardElement.Wind, [地封印.id, 火封印.id])
	var 法术牌: GCard = null
	for card: GCard in Data.card_db:
		if card != null and not card.is_virtual and card.is_magic():
			法术牌 = card
			break
	检(地系牌 != null and 火系牌 != null and 风系牌 != null,
		"卡库里找不到地 / 火 / 风系样本牌")
	检(法术牌 != null, "卡库里找不到法术牌样本")
	if 地系牌 == null or 火系牌 == null or 风系牌 == null or 法术牌 == null:
		return

	# ---- helper 的静态判定口径 ----
	检(SkillSeal.是封印牌(地封印), "地之封印牌（攻击 + 幻命格）应被识别为封印牌")
	检(not SkillSeal.是封印牌(法术牌), "法术牌不应被识别为封印牌")
	检(SkillSeal.封印技能号(GConst.CardElement.Earth) == SkillSeal.地之封印,
		"地系应映射到 404 地之封印")
	检(SkillSeal.封印元素(SkillSeal.雷之封印) == GConst.CardElement.Thunder,
		"405 雷之封印应映射到雷系")
	检(SkillSeal.封印技能号(GConst.CardElement.Light) == 0, "光系没有封印技能，应映射到 0")

	# ---- 搭引擎：1 号挂 dummy 借用角色，2/4 是对手 ----
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "借封")
	引擎.add_player(2, GConst.RED, "红二")
	引擎.add_player(3, GConst.BLUE, "蓝三")
	引擎.add_player(4, GConst.RED, "红四")
	引擎.start_with_roles({})
	引擎._states.clear()
	引擎._清空等待()
	借用者 = 引擎.p(1)
	靶 = 引擎.p(2)
	借用者.role_id = 4
	角色 = 借用封印角色.new()
	角色.setup(借用者, 引擎)
	借用者.role = 角色
	检(角色.封印 != null, "dummy 借用角色没有建出封印 helper")
	if 角色.封印 == null:
		return

	借用者.hand_cards.clear()
	借用者.hand_cards.append(地封印.id)
	靶.hand_cards.clear()
	靶.hand_cards.append(风系牌.id)

	# ---- 技能栏：五系封印照常下发，没有牌的置灰；目标只亮异色且没有同种封印的人 ----
	var 技能表: Array = 角色.available_skills()
	检(技能表.size() == 5, "五系封印应下发 5 个技能按钮，实际 %d 个" % 技能表.size())
	var 地项: Dictionary = _找技能(技能表, SkillSeal.地之封印)
	var 风项: Dictionary = _找技能(技能表, SkillSeal.风之封印)
	检(bool(地项.get("enabled", false)), "手里有地之封印时【地之封印】应可点")
	检((地项.get("cards", []) as Array) == [地封印.id],
		"【地之封印】的可点牌应只有手里那张：%s" % str(地项.get("cards", [])))
	检(not bool(风项.get("enabled", false)), "手里没有风之封印时【风之封印】应置灰（不是消失）")
	var 目标: Array = 地项.get("targets", [])
	检(目标.has(2) and 目标.has(4), "【地之封印】的合法目标应包含两名对手：%s" % str(目标))
	检(not 目标.has(3), "同色队友不能成为封印目标：%s" % str(目标))

	# ---- 放置校验 ----
	检(角色.v_magic_skill({"src_id": 1, "action_id": SkillSeal.地之封印,
		"card_ids": [地封印.id], "dst_ids": [2]}) == GConst.GE_SUCCESS, "合法放置应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": SkillSeal.地之封印,
		"card_ids": [地封印.id], "dst_ids": [3]}) == GConst.GE_INVALID_PLAYERID,
		"封印不能放到同色队友身上")
	检(角色.v_magic_skill({"src_id": 1, "action_id": SkillSeal.风之封印,
		"card_ids": [地封印.id], "dst_ids": [2]}) == GConst.GE_INVALID_ACTION,
		"地之封印牌不能当风之封印放")
	检(角色.v_magic_skill({"src_id": 1, "action_id": SkillSeal.地之封印,
		"card_ids": [], "dst_ids": [2]}) == GConst.GE_INVALID_CARDID, "没选封印牌应被拒")
	检(角色.v_magic_skill({"src_id": 1, "action_id": SkillSeal.地之封印,
		"card_ids": [地封印.id], "dst_ids": []}) == GConst.GE_INVALID_CARDID, "没选目标应被拒")
	检(角色.v_magic_skill({"src_id": 2, "action_id": SkillSeal.地之封印,
		"card_ids": [地封印.id], "dst_ids": [2]}) == GConst.GE_INVALID_PLAYERID,
		"不是自己发起的封印应被拒")
	# 借用入口：用借用角色自己的技能行（4606）转发，按牌上实际带的封印号校验
	角色.借用技能号 = SkillSeal.地之封印
	检(角色.v_magic_skill({"src_id": 1, "action_id": 借用转发技能号,
		"card_ids": [地封印.id], "dst_ids": [2]}) == GConst.GE_SUCCESS,
		"借用入口（4606 → 404）应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 借用转发技能号,
		"card_ids": [火封印.id], "dst_ids": [2]}) == GConst.GE_INVALID_ACTION,
		"借用入口按 404 校验时，火之封印牌应被拒")

	# ---- 放置结算：展示 → 挂基础效果 → 离手，并按牌上的封印号播报 ----
	引擎._states.clear()
	引擎._清空等待()
	广播.clear()
	引擎.send_cb = func(target: int, msg_type: int, data: Dictionary) -> void:
		广播.append({"target": target, "msg": msg_type, "data": data})
	var 借用放置: Dictionary = {"src_id": 1, "action_id": 借用转发技能号,
		"card_ids": [地封印.id], "dst_ids": [2]}
	检(角色.p_magic_skill(借用放置) == BattleRole.URGENT,
		"放置结算应返回 URGENT（要等展示 / 基础效果钩子结算）")
	检(not 借用者.hand_cards.has(地封印.id), "放置后封印牌应离手")
	var 挂上: bool = false
	for 效果: Dictionary in 靶.basic_effects:
		if int(效果["card"]) == 地封印.id and int(效果["src"]) == 1:
			挂上 = true
	检(挂上, "地之封印应挂到目标面前的基础效果区（来源＝借用者）")
	检(_有技能播报(SkillSeal.地之封印),
		"借用入口应按牌上的封印号（404）播报，而不是借用者的 4606")
	检(_有展示牌(地封印.id), "放置时要把封印牌公开展示")
	var 有展示钩子: bool = false
	for st: Variant in 引擎._states:
		if st is BattleEngine.SHook and str(st.get("hook")) == "p_show_hand":
			有展示钩子 = true
	检(有展示钩子, "放置后要触发展示钩子（封印牌离手并公开）")
	引擎.send_cb = Callable()

	# ---- 目标已有同种封印：不再合法、不能重复放置 ----
	检(not (角色.封印.合法目标(SkillSeal.地之封印) as Array).has(2),
		"目标身上已有地之封印时，不应再列为合法目标")
	检((角色.封印.合法目标(SkillSeal.火之封印) as Array).has(2),
		"别的系封印不受「已有地之封印」影响")
	if 地封印2 != null:
		借用者.hand_cards.append(地封印2.id)
		检(角色.v_magic_skill({"src_id": 1, "action_id": SkillSeal.地之封印,
			"card_ids": [地封印2.id], "dst_ids": [2]}) == GConst.GE_INVALID_PLAYERID,
			"目标已有同种封印时不能重复放置")

	# ---- 展示触发：异系不触发 ----
	引擎._states.clear()
	引擎._清空等待()
	检(角色.p_show_hand({"player": 2, "cards": [风系牌.id]}) == BattleRole.SUCCESS,
		"展示异系牌不应触发地之封印")
	检(引擎._states.is_empty(), "异系展示不应压入伤害")
	检(靶.basic_effects.size() == 1, "异系展示不应移除封印")

	# ---- 展示触发：同系牌 → 3 点法术伤害 + 移除封印 ----
	引擎._states.clear()
	引擎._清空等待()
	广播.clear()
	引擎.send_cb = func(target: int, msg_type: int, data: Dictionary) -> void:
		广播.append({"target": target, "msg": msg_type, "data": data})
	var 触发上下文: Dictionary = {"player": 2, "cards": [地系牌.id]}
	检(角色.p_show_hand(触发上下文) == BattleRole.URGENT,
		"展示同系牌应触发地之封印（返回 URGENT，先结算伤害）")
	检(靶.basic_effects.is_empty(), "触发后封印应移除")
	var 伤害: Dictionary = _找伤害(SkillSeal.地之封印, 2)
	检(not 伤害.is_empty(), "触发封印应对目标压入伤害")
	检(int(伤害.get("point", 0)) == SkillSeal.封印伤害, "封印触发伤害应为 3 点")
	检(int(伤害.get("type", 0)) == GConst.HarmType.Magic, "封印触发的是法术伤害")
	检(int(伤害.get("src", -1)) == 1, "封印伤害的来源应是借用者")
	检(引擎.deck.discard.has(地封印.id), "触发后的封印牌应进弃牌堆")
	检(_有技能播报(SkillSeal.地之封印), "触发时按封印技能号播报")
	var 伤害注数: int = _数伤害(SkillSeal.地之封印, 2)
	检(角色.p_show_hand(触发上下文) == BattleRole.SUCCESS,
		"同一批展示牌不应重复触发已结算的封印")
	检(_数伤害(SkillSeal.地之封印, 2) == 伤害注数, "重复调用不应再压第二次伤害")
	引擎.send_cb = Callable()

	# ---- 同一目标身上两枚封印：一次展示只结算一张，重入钩子后继续结算下一张 ----
	if 地封印2 == null:
		检(false, "卡库里找不到第二张地之封印，无法验证多封印依次触发")
		return
	引擎._states.clear()
	引擎._清空等待()
	靶.basic_effects.clear()
	靶.add_basic_effect(火封印.id, 1)
	靶.add_basic_effect(地封印2.id, 1)
	var 双封上下文: Dictionary = {"player": 2, "cards": [火系牌.id, 地系牌.id]}
	检(角色.p_show_hand(双封上下文) == BattleRole.URGENT,
		"两枚封印在场时，第一次展示应先结算一枚")
	检(靶.basic_effects.size() == 1, "第一次触发只移除一枚封印")
	检(not _找伤害(SkillSeal.火之封印, 2).is_empty(), "先结算与展示牌同系的火之封印")
	检(角色.p_show_hand(双封上下文) == BattleRole.URGENT,
		"重入钩子后应继续结算第二枚封印")
	检(靶.basic_effects.is_empty(), "第二枚封印也应被移除")
	检(not _找伤害(SkillSeal.地之封印, 2).is_empty(), "第二枚应是地之封印")
	检(角色.p_show_hand(双封上下文) == BattleRole.SUCCESS,
		"两枚都结算完后不应再触发")

	# ---- ctx["seals_triggered"]：多封印师同场时，别人已结算过的封印不再算一次 ----
	引擎._states.clear()
	引擎._清空等待()
	靶.basic_effects.clear()
	靶.add_basic_effect(地封印.id, 1)
	var 已记上下文: Dictionary = {"player": 2, "cards": [地系牌.id], "seals_triggered": [地封印.id]}
	检(角色.p_show_hand(已记上下文) == BattleRole.SUCCESS, "ctx 已记过的封印不应再结算")
	检(_数伤害(SkillSeal.地之封印, 2) == 0, "ctx 挡掉时不应压入伤害")
	检(靶.basic_effects.size() == 1, "ctx 挡掉时封印应留在目标面前")

	# ---- 非封印的基础效果不触发；非法玩家 id 安全返回 ----
	引擎._states.clear()
	引擎._清空等待()
	靶.basic_effects.clear()
	靶.add_basic_effect(法术牌.id, 1)
	检(角色.p_show_hand({"player": 2, "cards": [法术牌.id]}) == BattleRole.SUCCESS,
		"非封印的基础效果不应被展示触发")
	检(靶.basic_effects.size() == 1, "非封印的基础效果不应被移除")
	检(角色.p_show_hand({"player": -1, "cards": [地系牌.id]}) == BattleRole.SUCCESS,
		"非法玩家 id 应安全返回")
	检(角色.封印.p_place({"card_ids": [], "dst_ids": []}) == BattleRole.SUCCESS,
		"空参数放置应安全返回（不崩溃）")

	# ---- 原角色不受影响：4 号封印师脚本仍能加载、技能栏照旧 ----
	var 原引擎: BattleEngine = BattleEngine.new()
	原引擎.add_player(1, GConst.BLUE, "封印师")
	var 原玩家: BattlePlayer = 原引擎.p(1)
	原玩家.role_id = 4
	var 原角色: BattleRole = BattleRole.create(4, 原玩家, 原引擎)
	检(原角色 != null, "封印师 4 号脚本加载失败（helper 是新增文件，不应影响 role_fengyin.gd）")
	if 原角色 != null:
		原玩家.role = 原角色
		var 原技能表: Array = 原角色.available_skills()
		检(原技能表.size() >= 7,
			"封印师的技能栏应仍有 7 项（五系封印 + 五系束缚 + 封印破碎），实际 %d 项" % 原技能表.size())
		for 号: int in SkillSeal.封印技能号列表:
			检(not _找技能(原技能表, 号).is_empty(), "封印师的技能栏里缺 %d" % 号)

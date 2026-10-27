extends 自检用例
## F5-E 祈祷师独有技 helper（1601 迅捷赐福 / 1602 威力赐福）。
## 用一个 dummy「借用角色」把技能入口转给 skill_bless.gd，验证：
##   1. 两张赐福只放在同色队友面前，同类赐福不能叠加；
##   2. 迅捷赐福在队友行动结束时授予 +1 攻击行动，选择该额外行动时移除赐福牌；
##   3. 威力赐福在攻击命中时由牌的所有者决定是否 +2 伤害，发动后移除；取消则保留；
##   4. 威力赐福按 src 区分归属；迅捷赐福按持有者面前有没有 1601 校验/移除（别人放的也能正常用）；
##   5. 技能按钮即使不可用也照常下发（enabled=false），不会整条消失。

const 赐福脚本路径: String = "res://scripts/battle/skills/skill_bless.gd"
const 赐福脚本: GDScript = preload("res://scripts/battle/skills/skill_bless.gd")


## dummy 借用角色：只做转发，证明 helper 不依赖祈祷师角色号
class 借用角色 extends BattleRole:
	var 赐福: Variant = null

	func available_skills() -> Array:
		if 赐福 == null:
			return []
		return 赐福.available_skills()

	func v_magic_skill(action: Dictionary) -> int:
		if 赐福 == null:
			return GConst.GE_INVALID_ACTION
		return int(赐福.v_magic_skill(action))

	func p_magic_skill(action: Dictionary) -> int:
		if 赐福 == null:
			return EMPTY_HANDLE
		return int(赐福.p_magic_skill(action))

	func p_timeline_2_hit(ctx: Dictionary) -> int:
		if 赐福 == null:
			return SUCCESS
		return int(赐福.p_timeline_2_hit(ctx))

	func p_after_attack(ctx: Dictionary) -> int:
		if 赐福 == null:
			return SUCCESS
		return int(赐福.p_after_attack(ctx))

	func p_after_magic(ctx: Dictionary) -> int:
		if 赐福 == null:
			return SUCCESS
		return int(赐福.p_after_magic(ctx))

	func v_additional_action(cause: int) -> int:
		if 赐福 == null:
			return V_NOT_OVERRIDE
		return int(赐福.v_additional_action(cause))

	func 可选目标(技能号: int) -> Array:
		if 赐福 == null:
			return []
		return 赐福.可选目标(技能号)

	func p_additional_action(ctx: Dictionary) -> int:
		if 赐福 == null:
			return SUCCESS
		return int(赐福.p_additional_action(ctx))


var 引擎: BattleEngine
var 借用: 借用角色
var 赐福: RefCounted
var 祈: BattlePlayer
var 敌: BattlePlayer
var 友: BattlePlayer
var 友二: BattlePlayer


func _init() -> void:
	名称 = "F5-祈祷师赐福"


func _取技能牌(技能号: int, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		if c.has_skill_id(技能号):
			return c
	return null


func _取普通牌(排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		if not c.has_skill_id(1601) and not c.has_skill_id(1602):
			return c
	return null


func _找技能(表: Array, 技能号: int) -> Dictionary:
	for sk: Dictionary in 表:
		if int(sk.get("id", 0)) == 技能号:
			return sk
	return {}


func _取询问(pid: int, 技能号: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 技能号:
			return r
	return {}


func _清局() -> void:
	引擎._states.clear()
	引擎._清空等待()


func 跑() -> void:
	await 等帧(1)
	检(ResourceLoader.exists(赐福脚本路径), "缺少 helper：%s" % 赐福脚本路径)
	检(赐福脚本 != null and 赐福脚本.can_instantiate(), "helper 脚本无法实例化")

	var 迅捷: GCard = _取技能牌(1601)
	var 迅捷二: GCard = _取技能牌(1601, [迅捷.id] if 迅捷 != null else [])
	var 迅捷三: GCard = _取技能牌(1601, [迅捷.id, 迅捷二.id] if 迅捷 != null and 迅捷二 != null else [])
	var 威力: GCard = _取技能牌(1602)
	var 威力二: GCard = _取技能牌(1602, [威力.id] if 威力 != null else [])
	var 威力三: GCard = _取技能牌(1602, [威力.id, 威力二.id] if 威力 != null and 威力二 != null else [])
	var 普通: GCard = _取普通牌()
	检(迅捷 != null and 迅捷二 != null and 迅捷三 != null, "卡库找不到足够的【迅捷赐福】牌")
	检(威力 != null and 威力二 != null and 威力三 != null, "卡库找不到足够的【威力赐福】牌")
	检(普通 != null, "卡库找不到普通牌")
	if 迅捷 == null or 迅捷二 == null or 迅捷三 == null \
			or 威力 == null or 威力二 == null or 威力三 == null or 普通 == null:
		return

	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "借用者")
	引擎.add_player(2, GConst.RED, "对手")
	引擎.add_player(3, GConst.BLUE, "队友甲")
	引擎.add_player(4, GConst.BLUE, "队友乙")
	引擎.start_with_roles({1: 0, 2: 0, 3: 0, 4: 0})
	借用 = 借用角色.new()
	祈 = 引擎.p(1)
	敌 = 引擎.p(2)
	友 = 引擎.p(3)
	友二 = 引擎.p(4)
	for pl: BattlePlayer in [祈, 敌, 友, 友二]:
		pl.hand_cards.clear()
	祈.role = 借用
	借用.setup(祈, 引擎)
	赐福 = 赐福脚本.new(借用)
	借用.赐福 = 赐福
	检(祈.role == 借用 and 借用.赐福 != null, "dummy 借用角色没接上 helper")

	# ---- 技能栏：两张赐福始终下发，不可用时置灰而不是消失 ----
	var 技能表: Array = 借用.available_skills()
	var 迅捷技能: Dictionary = _找技能(技能表, 1601)
	var 威力技能: Dictionary = _找技能(技能表, 1602)
	检(not 迅捷技能.is_empty() and not 威力技能.is_empty(), "helper 应下发 1601 / 1602 两个技能按钮")
	检(bool(迅捷技能.get("enabled", true)) == false and bool(威力技能.get("enabled", true)) == false,
		"手里没有赐福牌时两张技能都应置灰（enabled=false）")
	检((迅捷技能.get("targets", []) as Array).has(3) and (迅捷技能.get("targets", []) as Array).has(4),
		"迅捷赐福的候选目标应包含两名同色队友：%s" % str(迅捷技能.get("targets", [])))
	检(not (迅捷技能.get("targets", []) as Array).has(1) and not (迅捷技能.get("targets", []) as Array).has(2),
		"迅捷赐福不能选自己或对手：%s" % str(迅捷技能.get("targets", [])))

	# ---- 投牌后：只让带对应技能的牌可点 ----
	祈.hand_cards.append(迅捷.id)
	祈.hand_cards.append(普通.id)
	技能表 = 借用.available_skills()
	迅捷技能 = _找技能(技能表, 1601)
	检(bool(迅捷技能.get("enabled", false)), "手里有【迅捷赐福】时应可点")
	检((迅捷技能.get("cards", []) as Array).has(迅捷.id), "【迅捷赐福】的可点牌应包含它自己")
	检(not (迅捷技能.get("cards", []) as Array).has(普通.id), "普通牌不能当赐福的发动牌")

	# ---- 放置校验：队友 / 自己 / 对手 / 空牌 / 错牌 / 越权 ----
	var 放置动作: Dictionary = {
		"src_id": 1, "action_id": 1601, "card_ids": [迅捷.id], "dst_ids": [3],
	}
	检(借用.v_magic_skill(放置动作) == GConst.GE_SUCCESS, "把迅捷赐福放在同色队友面前应通过校验")
	var 放对手: Dictionary = 放置动作.duplicate()
	放对手["dst_ids"] = [2]
	检(借用.v_magic_skill(放对手) == GConst.GE_INVALID_ACTION, "赐福不能放在对手面前")
	var 放自己: Dictionary = 放置动作.duplicate()
	放自己["dst_ids"] = [1]
	检(借用.v_magic_skill(放自己) == GConst.GE_INVALID_ACTION, "赐福不能放在自己面前")
	var 空牌: Dictionary = 放置动作.duplicate()
	空牌["card_ids"] = []
	检(借用.v_magic_skill(空牌) == GConst.GE_INVALID_CARDID, "没选发动牌应返回 GE_INVALID_CARDID")
	var 错牌: Dictionary = 放置动作.duplicate()
	错牌["card_ids"] = [普通.id]
	检(借用.v_magic_skill(错牌) == GConst.GE_INVALID_ACTION, "不带 1601 的牌不能发动迅捷赐福")
	var 越权: Dictionary = 放置动作.duplicate()
	越权["src_id"] = 2
	检(借用.v_magic_skill(越权) == GConst.GE_INVALID_PLAYERID, "别人的回合不能代放赐福")
	var 未知技能: Dictionary = 放置动作.duplicate()
	未知技能["action_id"] = 1603
	检(借用.v_magic_skill(未知技能) == GConst.GE_INVALID_ACTION, "helper 不应接受非赐福技能号")

	# ---- 放置结算：牌离手、成为队友面前的基础效果 ----
	_清局()
	var 放置结果: int = 借用.p_magic_skill(放置动作)
	检(放置结果 == BattleRole.URGENT, "放置赐福应返回 URGENT（基础效果变更钩子已压栈）")
	检(not 祈.hand_cards.has(迅捷.id), "放置后发动牌应离手")
	检(赐福.find_blessing(友, 1601, 1) == 迅捷.id, "迅捷赐福应成为队友甲面前的基础效果")
	检(友.basic_effects.size() == 1 and int(友.basic_effects[0].get("src", -1)) == 1,
		"基础效果应记录施术者（多祈祷师同桌时按 src 区分）")

	# ---- 同类赐福不能叠加；另一个队友仍可放 ----
	祈.hand_cards.append(迅捷二.id)
	var 重复动作: Dictionary = {
		"src_id": 1, "action_id": 1601, "card_ids": [迅捷二.id], "dst_ids": [3],
	}
	检(借用.v_magic_skill(重复动作) == GConst.GE_INVALID_ACTION, "同一名队友面前不能叠第二张同类赐福")
	检(not (借用.可选目标(1601) as Array).has(3), "已有迅捷赐福的队友不应再出现在候选目标里")
	检((借用.可选目标(1601) as Array).has(4), "另一名没有赐福的队友仍应是候选目标")
	var 放置二: Dictionary = {
		"src_id": 1, "action_id": 1601, "card_ids": [迅捷二.id], "dst_ids": [4],
	}
	_清局()
	检(借用.p_magic_skill(放置二) == BattleRole.URGENT, "迅捷赐福可以放到另一名队友面前")
	检(赐福.find_blessing(友二, 1601, 1) == 迅捷二.id, "第二张迅捷赐福应落在队友乙面前")

	# ---- 迅捷赐福：队友行动结束授予 +1 攻击行动 ----
	祈.hand_cards.erase(普通.id)
	友.hand_cards.clear()
	友.hand_cards.append(普通.id)
	友.additional_actions.clear()
	检(借用.p_after_attack({"player": 3}) == BattleRole.SUCCESS, "行动结束钩子本身应返回 SUCCESS")
	检(友.additional_actions.size() == 1, "拥有迅捷赐福的队友行动结束应获得 1 个额外行动")
	if 友.additional_actions.size() == 1:
		检(int(友.additional_actions[0].get("cause", 0)) == 1601
			and int(友.additional_actions[0].get("allow_action", 0)) == GConst.ActionType.Attack,
			"迅捷赐福应授予 +1 攻击行动：%s" % str(友.additional_actions[0]))
	借用.p_after_magic({"player": 3})
	检(友.additional_actions.size() == 1, "攻击 / 法术行动结束不应重复授予同一份额外行动")
	友二.additional_actions.clear()
	借用.p_after_attack({"player": 4})
	检(友二.additional_actions.is_empty(), "没有迅捷赐福的队友不应获得额外行动")
	借用.p_after_attack({"player": 2})
	检(敌.additional_actions.is_empty(), "对手不应获得迅捷赐福的额外行动")

	# 手里没牌不授予（与祈祷师原实现一致）
	友二.hand_cards.clear()
	友二.additional_actions.clear()
	借用.p_after_attack({"player": 4})
	检(友二.additional_actions.is_empty(), "队友手里没有牌时不应授予额外攻击行动")
	友二.hand_cards.append(普通.id)

	# ---- 额外行动被选中时移除并弃置赐福牌 ----
	友.additional_actions.clear()
	_清局()
	检(借用.p_additional_action({"player": 3, "cause": 1601}) == BattleRole.SUCCESS,
		"选择迅捷赐福给的额外行动时不应报错")
	检(赐福.find_blessing(友, 1601, 1) < 0, "选择额外行动后迅捷赐福应被移除")
	检(引擎.deck.discard.has(迅捷.id), "被移除的迅捷赐福应进入弃牌堆")
	检(借用.p_additional_action({"player": 3, "cause": 1601}) == BattleRole.SUCCESS,
		"赐福牌已移除后重复触发应安全返回")

	# v_additional_action 的自身分支：只有「本角色面前确实有自己放的迅捷赐福」才放行
	# （借用的常规流程里，额外行动由持有者自己的角色校验；这里单独验证 helper 的守卫）
	祈.basic_effects.clear()
	祈.add_basic_effect(迅捷三.id, 1)
	检(借用.v_additional_action(1601) == GConst.GE_SUCCESS, "自己面前有迅捷赐福时应认可该额外行动")
	祈.basic_effects.clear()
	检(借用.v_additional_action(1601) == GConst.GE_INVALID_ACTION, "没有迅捷赐福时该额外行动应被拒")
	检(借用.v_additional_action(9999) == BattleRole.V_NOT_OVERRIDE, "非赐福来源不应被 helper 覆写")

	# ---- 威力赐福：放置 ----
	祈.hand_cards.clear()
	祈.hand_cards.append(威力.id)
	var 威动作: Dictionary = {
		"src_id": 1, "action_id": 1602, "card_ids": [威力.id], "dst_ids": [3],
	}
	检(借用.v_magic_skill(威动作) == GConst.GE_SUCCESS, "威力赐福放在队友面前应通过校验")
	_清局()
	检(借用.p_magic_skill(威动作) == BattleRole.URGENT, "放置威力赐福应返回 URGENT")
	检(赐福.find_blessing(友, 1602, 1) == 威力.id, "威力赐福应成为队友甲面前的基础效果")

	# ---- 威力赐福：攻击命中时询问牌的所有者，发动则 +2 并移除 ----
	_清局()
	var 伤害: Dictionary = {
		"src": 3, "dst": 2, "point": 2,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
	}
	var 伤害上下文: Dictionary = {"harm": 伤害, "src": 3, "dst": 2, "is_active": true}
	检(借用.p_timeline_2_hit(伤害上下文) == BattleRole.WAIT, "威力赐福应先询问牌的所有者是否发动")
	var 威问: Dictionary = _取询问(3, 1602)
	检(not 威问.is_empty(), "没有向攻击者（牌的所有者）发出威力赐福询问")
	检(int(威问.get("preview_base", 0)) == 2
		and int(威问.get("preview_kind", 0)) == GConst.HarmType.Attack,
		"威力赐福的头像提示应下发原伤害 / 攻击类型：%s" % str(威问))
	检((威问.get("dst_ids", []) as Array).has(2), "受伤目标应作为固定目标随询问下发")
	检(str(威问.get("ask_text", "")).contains("+2"),
		"威力赐福的询问应带出「伤害 +2」提示：%s" % str(威问.get("ask_text", "")))
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	var 结算结果: int = 借用.p_timeline_2_hit(伤害上下文)
	检(结算结果 == BattleRole.URGENT, "发动威力赐福后应返回 URGENT（基础效果变更钩子已压栈）")
	检(int(伤害.get("point", 0)) == 4, "威力赐福应让本次攻击伤害 +2（2 → 4）")
	检(赐福.find_blessing(友, 1602, 1) < 0, "发动后威力赐福应被移除")
	检(引擎.deck.discard.has(威力.id), "被移除的威力赐福应进入弃牌堆")

	# ---- 威力赐福：取消发动则伤害不变、赐福保留 ----
	祈.hand_cards.clear()
	祈.hand_cards.append(威力二.id)
	var 威动作二: Dictionary = {
		"src_id": 1, "action_id": 1602, "card_ids": [威力二.id], "dst_ids": [3],
	}
	_清局()
	借用.p_magic_skill(威动作二)
	_清局()
	var 伤害二: Dictionary = {
		"src": 3, "dst": 2, "point": 1,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
	}
	var 伤害上下文二: Dictionary = {"harm": 伤害二, "src": 3, "dst": 2, "is_active": true}
	检(借用.p_timeline_2_hit(伤害上下文二) == BattleRole.WAIT, "威力赐福应再次先询问")
	引擎._reply = {"args": [0], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(借用.p_timeline_2_hit(伤害上下文二) == BattleRole.SUCCESS, "取消发动应直接结束本次钩子")
	检(int(伤害二.get("point", 0)) == 1, "取消发动不应改变伤害")
	检(赐福.find_blessing(友, 1602, 1) == 威力二.id, "取消发动不应移除威力赐福")

	# ---- 别人放的威力赐福不冒领（按 src 区分） ----
	_清局()
	敌.add_basic_effect(威力三.id, 4)
	var 伤害三: Dictionary = {
		"src": 2, "dst": 1, "point": 2,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
	}
	检(借用.p_timeline_2_hit({"harm": 伤害三, "src": 2, "dst": 1}) == BattleRole.SUCCESS,
		"别人放的威力赐福不应由本 helper 询问")
	检(引擎._await_id == -1, "不该冒领别人的赐福发询问")
	敌.basic_effects.clear()

	# ---- 边界：没有伤害上下文 / 没有目标时不异常 ----
	_清局()
	检(借用.p_timeline_2_hit({}) == BattleRole.SUCCESS, "没有伤害上下文时应安全返回")
	检(借用.p_after_attack({}) == BattleRole.SUCCESS, "没有行动者时应安全返回")

	# ---- 跨来源的迅捷赐福：别人放到「我」面前，也要能校验、触发、移除 ----
	# 场景：祈祷师把 1601 贴到 46 面前；46 的角色转发本 helper 时，
	# v_additional_action / p_additional_action / 触发都不能按「谁放的」过滤。
	_清局()
	友.basic_effects.clear()
	友.additional_actions.clear()
	友.hand_cards.clear()
	友.hand_cards.append(普通.id)
	友.add_basic_effect(迅捷三.id, 2)
	var 友角色: 借用角色 = 借用角色.new()
	友.role = 友角色
	友角色.setup(友, 引擎)
	友角色.赐福 = 赐福脚本.new(友角色)
	检(友角色.v_additional_action(1601) == GConst.GE_SUCCESS,
		"持有者面前有别人放的迅捷赐福时，v_additional_action 也应认可")
	检(not (借用.可选目标(1601) as Array).has(3),
		"别人放的同类迅捷赐福也要挡住重复放置（同类全局不叠加）")
	检(借用.p_after_attack({"player": 3}) == BattleRole.SUCCESS, "跨来源迅捷赐福的行动结束钩子应安全返回")
	var 跨来源额外: bool = false
	for a: Dictionary in 友.additional_actions:
		if int(a.get("cause", 0)) == 1601:
			跨来源额外 = true
	检(跨来源额外, "别人放的迅捷赐福也应在持有者行动结束时授予 +1 攻击行动")
	检(友角色.p_additional_action({"player": 3, "cause": 1601}) == BattleRole.SUCCESS,
		"持有者选择跨来源迅捷赐福的额外行动时应安全返回")
	检(赐福.find_blessing(友, 1601, -1) < 0, "跨来源迅捷赐福也应被移除")
	检(引擎.deck.discard.has(迅捷三.id), "跨来源迅捷赐福应进入弃牌堆")
	检(友角色.v_additional_action(1601) == GConst.GE_INVALID_ACTION,
		"跨来源迅捷赐福移除后，该额外行动应被拒")
	友.basic_effects.clear()
	友.additional_actions.clear()
	友.role = null

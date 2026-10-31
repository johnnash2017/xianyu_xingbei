extends 自检用例
## R75 EX魔弓（75）：7501 神风矢 / 7502 疾风追射 / 7503 弓神候补 / 7504 狙击。
##
## 任务范围只有 role + test，借用的 301 / 302 走 F5-archer 的 helper；
## 7504 与弓之女神的 303【狙击】**同名但独立技能行**，按 7504 校验 / 播报 / 结算。
## 覆盖：
##   - 数据：角色名 / 技能号 / 四颗技能行 / 技能说明 / 301·302 源技能行存在；
##   - 技能栏：借用来的 302、自己的 7504；缺牌 / 缺能量只置灰不消失；不借用 303；
##   - 7504：能量校验（水晶、宝石可顶）、目标校验、手牌补到 5 张【强制】、额外攻击行动、
##            目标已满 5 张不再摸、没给目标时按自己结算；
##   - 7501：风系攻击置「无法应战」，非风系 / 别人的攻击不动；跑完整攻击流水线确认目标被标 NoReattack；
##   - 7502：未命中时问是否弃 1 张法术牌；取消不生效、发动造成 2 点法术伤害并弃牌；
##            没有法术牌 / 非主动攻击 / 别人的未命中不询问；目标不存在时不弃牌不造伤；非法牌提交被忽略；
##   - 7503：302 完整结算、播报用源技能号 302（不是 7503）、301 在攻击宣告时询问并按源号播报。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_exmogong.gd")

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 靶: BattlePlayer = null
var 队友: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 风301牌: GCard = null
var 地301牌: GCard = null
var 火牌: GCard = null
var 法术牌: GCard = null
var 陷阱牌: GCard = null


func _init() -> void:
	名称 = "EX魔弓"


# ============================================================
# 找牌 / 查消息
# ============================================================
## 卡库里第一张「指定系别 + 是否带 301」的攻击牌
func _取攻击(元素: int, 需要301: bool) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() != 元素:
			continue
		if c.has_skill_id(301) == 需要301:
			return c
	return null


## 卡库里第一张法术牌（7502 的弃牌代价用）
func _取法术() -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic():
			return c
	return null


## 卡库里第一张带 302【闪光陷阱】的牌（7503 借用）
func _取302牌() -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(302):
			return c
	return null


func _找技能(表: Array, id: int) -> Dictionary:
	for sk: Dictionary in 表:
		if int(sk.get("id", 0)) == id:
			return sk
	return {}


## 最近一次下发给某玩家的询问里，是否有指定 respond_id 的那条
func _取询问(pid: int, respond_id: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == respond_id:
			return r
	return {}


## 在发送记录里找一条满足条件的广播消息
func _找消息(消息类型: int, 条件: Callable) -> Dictionary:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != 消息类型:
			continue
		var 数据: Dictionary = r.get("data", {})
		if bool(条件.call(数据)):
			return 数据
	return {}


## 某技能号播报过几次
func _播报次数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Skill:
			continue
		if int((r.get("data", {}) as Dictionary).get("skill_id", 0)) == 技能号:
			n += 1
	return n


## 状态栈里找一条指定来源 / 目标的伤害，返回它的伤害字典；找不到返回空字典
func _找伤害(cause: int, dst: int) -> Dictionary:
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var h: Variant = st.get("harm")
		if h is Dictionary and int((h as Dictionary).get("cause", 0)) == cause \
				and int((h as Dictionary).get("dst", -1)) == dst:
			return h as Dictionary
	return {}


## 当前状态栈顶若是额外行动阶段，返回它的关键字段（不是就返回空字典）
func _取额外阶段() -> Dictionary:
	var 顶: Variant = 引擎._states[-1] if not 引擎._states.is_empty() else null
	if not (顶 is BattleEngine.SActionPhase):
		return {}
	var 阶段: BattleEngine.SActionPhase = 顶
	return {
		"额外": bool(阶段.get("额外")),
		"允许": int(阶段.get("允许")),
		"来源": int(阶段.get("额外来源")),
		"可放弃": bool(阶段.get("可放弃")),
	}


## 清空战斗状态：只保留 EX魔弓 / 靶子 / 队友，清理手牌、能量、基础效果与发送记录
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	发送记录.clear()
	玩家.hand_cards.clear()
	玩家.additional_actions.clear()
	玩家.set_crystal(0)
	玩家.set_gem(0)
	靶.hand_cards.clear()
	靶.basic_effects.clear()
	靶.cross_num = 0
	队友.hand_cards.clear()


func _攻击上下文(牌: GCard, src: int, dst: int, 主动: bool, 伤害: int) -> Dictionary:
	var harm: Dictionary = {
		"src": src, "dst": dst, "point": 伤害, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 牌.id, "is_active": 主动,
	}
	return {
		"card_id": 牌.id, "dst": dst, "src": src, "is_active": 主动,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": harm,
	}


## 用一张不带 301 的火系攻击牌宣告一次新攻击：清掉角色身上上一击的分步标记
func _新一次攻击宣告() -> void:
	角色.p_timeline_1(_攻击上下文(火牌, 1, 2, true, BattleEngine.ATTACK_BASE_POINT))


## 没给回复时先把上次的回复清掉（防止上一条步骤的回复漏到这一条）
func _应答(args: Array, cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": []}
	引擎._has_reply = true


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 借用源 ----
	检(str(Data.role_list.get(75, "")) == "EX魔弓", "75 号角色名不是「EX魔弓」")
	检(Data.role_personal_name(75) == "泰罗莎", "75 号角色姓名不是「泰罗莎」")
	检(absf(Data.role_star(75) - 3.0) < 0.01, "EX魔弓应是 3.0 星，实际 %s" % str(Data.role_star(75)))
	检(Data.role_skills(75) == [7501, 7502, 7503, 7504],
		"EX魔弓技能号不对：%s" % str(Data.role_skills(75)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_exmogong.gd"), "EX魔弓的角色脚本文件不存在")
	for 技能号: int in [7501, 7502, 7503, 7504]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	# 7504 与 303 同名但独立技能行：播报 / 校验都不能借用 303
	检(GConst.技能号("技能#EX魔弓#狙击") == 7504 and GConst.技能号("技能#狙击") == 303,
		"7504【狙击】与 303【狙击】应是两条独立技能行")
	# 7503 借用的 301 / 302 技能行必须存在（播报、提示按源技能号取）
	for 源号: int in [301, 302]:
		检(not GConst.技能行(源号).is_empty(), "技能表里查不到借用的源技能 %d" % 源号)
	var 技能说明: String = Data.role_skill_info(75)
	for 技能名: String in ["神风矢", "疾风追射", "弓神候补", "狙击"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提 ----
	风301牌 = _取攻击(GConst.CardElement.Wind, true)
	地301牌 = _取攻击(GConst.CardElement.Earth, true)
	火牌 = _取攻击(GConst.CardElement.Fire, false)
	法术牌 = _取法术()
	陷阱牌 = _取302牌()
	检(风301牌 != null, "卡库找不到「风系 + 301」的攻击牌")
	检(地301牌 != null, "卡库找不到「非风系 + 301」的攻击牌")
	检(火牌 != null, "卡库找不到不带 301 的火系攻击牌")
	检(法术牌 != null, "卡库找不到法术牌")
	检(陷阱牌 != null, "卡库找不到带 302【闪光陷阱】的牌")
	if 风301牌 == null or 地301牌 == null or 火牌 == null or 法术牌 == null or 陷阱牌 == null:
		return

	# ---- 建引擎：1 / 3 同队，2 是对手；角色表脚本列留给 DATA，用例里手动挂上角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "魔弓")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.start_with_roles({1: 0, 2: 0, 3: 0})
	玩家 = 引擎.p(1)
	靶 = 引擎.p(2)
	队友 = 引擎.p(3)
	玩家.role_id = 75
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	_重置战斗()

	# ---- 技能栏：借用的 302 + 自己的 7504；缺牌 / 缺能量只置灰；不借用 303 ----
	发送记录.clear()
	var 栏: Array = 角色.available_skills()
	检(栏.size() == 2, "技能栏应有 302（借用）与 7504 两项，实际 %d 项：%s" % [栏.size(), str(栏)])
	var 陷阱项: Dictionary = _找技能(栏, 302)
	var 狙击项: Dictionary = _找技能(栏, 7504)
	检(not 陷阱项.is_empty(), "7503 借用来的【闪光陷阱】(302) 应下发到技能栏")
	检(int(陷阱项.get("type", 0)) == GConst.ActionType.MagicSkill, "302 应作为法术技能按钮下发")
	检(int(陷阱项.get("need_card", 0)) == 1 and int(陷阱项.get("need_target", 0)) == 1,
		"【闪光陷阱】应要求 1 张发动牌 + 1 名目标")
	检(not bool(陷阱项.get("enabled", true)), "手里没有 302 牌时【闪光陷阱】应置灰，不是消失")
	检((陷阱项.get("cards", []) as Array).is_empty(), "手里没有 302 牌时 cards 应为空")
	检(not 狙击项.is_empty(), "【狙击】(7504) 应下发到技能栏")
	检(int(狙击项.get("type", 0)) == GConst.ActionType.MagicSkill, "7504 应作为法术技能按钮下发")
	检(int(狙击项.get("need_card", 0)) == 0 and int(狙击项.get("need_target", 0)) == 1,
		"【狙击】应不耗手牌、要求 1 名目标角色")
	检(not bool(狙击项.get("enabled", true)), "没有能量时【狙击】应置灰，不是消失")
	玩家.set_crystal(1)
	检(bool(_找技能(角色.available_skills(), 7504).get("enabled", false)), "有 1 点水晶时【狙击】应可点")
	玩家.set_crystal(0)
	玩家.set_gem(1)
	检(bool(_找技能(角色.available_skills(), 7504).get("enabled", false)),
		"只有 1 点宝石时【狙击】也应可点（宝石可顶水晶）")
	玩家.hand_cards.append(陷阱牌.id)
	栏 = 角色.available_skills()
	陷阱项 = _找技能(栏, 302)
	检(bool(陷阱项.get("enabled", false)), "手里有 302 牌时【闪光陷阱】应可点")
	检((陷阱项.get("cards", []) as Array).has(陷阱牌.id), "302 的可点牌表应包含这张 302 牌")
	检(_找技能(栏, 303).is_empty(), "7503 只借用 301 / 302，不应下发 303")

	# ---- 7504 校验：来源 / 技能号 / 能量 / 目标 ----
	var 狙击动作: Dictionary = {"src_id": 1, "action_id": 7504, "card_ids": [], "dst_ids": [2]}
	检(角色.v_magic_skill(狙击动作) == GConst.GE_SUCCESS, "合法的【狙击】应通过校验")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 7504, "card_ids": [], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "别人的【狙击】行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 7501, "card_ids": [], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "不是 7504 / 302 的法术技能行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 303, "card_ids": [], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "7503 不借用 303，按 303 提交应被驳回")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 7504, "card_ids": [], "dst_ids": [99]})
		!= GConst.GE_SUCCESS, "目标不存在时不能发动【狙击】")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 7504, "card_ids": [], "dst_ids": []})
		== GConst.GE_SUCCESS, "没带目标时【狙击】按自己结算（与 303 一致）")
	玩家.set_crystal(0)
	玩家.set_gem(0)
	检(角色.v_magic_skill(狙击动作) != GConst.GE_SUCCESS, "没有能量时不能发动【狙击】")

	# ---- 7504 结算（水晶）：扣 1 能量、目标手牌补到 5、额外 +1 攻击行动 ----
	_重置战斗()
	玩家.set_crystal(1)
	靶.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 狙击动作)
	引擎.run()
	检(玩家.get_energy() == 0, "【狙击】应支付 1 点能量，实际还剩 %d" % 玩家.get_energy())
	检(玩家.crystal == 0 and 玩家.gem == 0, "【狙击】应扣掉 1 点水晶")
	检(靶.hand_cards.size() == 5, "【狙击】应把目标手牌补到 5 张，实际 %d 张" % 靶.hand_cards.size())
	# 额外行动被选中后会从 additional_actions 移出并进入行动阶段（SActionPhase），所以这里查栈顶
	var 阶段: Dictionary = _取额外阶段()
	检(not 阶段.is_empty(), "【狙击】结算完应直接进入额外攻击行动阶段（栈顶：%s）" % str(引擎._states[-1] if not 引擎._states.is_empty() else null))
	检(bool(阶段.get("额外", false)), "【狙击】进入的行动阶段应标记为额外行动")
	检(int(阶段.get("允许", 0)) == GConst.ActionType.Attack, "【狙击】的额外行动应只允许攻击")
	检(int(阶段.get("来源", 0)) == 7504, "【狙击】额外行动阶段的来源应为 7504")
	检(bool(阶段.get("可放弃", false)), "【狙击】的额外攻击阶段应允许放弃（direct 额外行动不再多问一次）")
	var 狙击播报: Dictionary = _找消息(GConst.Msg.Skill,
		func(数据: Dictionary) -> bool: return int(数据.get("skill_id", 0)) == 7504)
	检(not 狙击播报.is_empty(), "【狙击】结算应播报技能号 7504")
	检((狙击播报.get("dst_ids", []) as Array).has(2), "【狙击】的播报应点名目标 2")

	# ---- 7504 结算（宝石顶水晶）----
	_重置战斗()
	玩家.set_gem(1)
	靶.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 狙击动作)
	引擎.run()
	检(玩家.get_energy() == 0 and 玩家.gem == 0, "【水晶】费用应允许用宝石支付")
	检(靶.hand_cards.size() == 5, "用宝石支付时【狙击】也应把目标手牌补到 5 张")

	# ---- 7504 可以指定任意角色（技能写的是「目标角色」）----
	_重置战斗()
	玩家.set_crystal(1)
	队友.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill,
		{"src_id": 1, "action_id": 7504, "card_ids": [], "dst_ids": [3]})
	引擎.run()
	检(队友.hand_cards.size() == 5, "【狙击】可以指定队友，队友手牌应补到 5 张，实际 %d 张"
		% 队友.hand_cards.size())
	检(靶.hand_cards.is_empty(), "【狙击】只应补给指定目标，不应动其他角色的手牌")

	# ---- 7504：目标手牌已满 5 张时不再摸牌，但仍给额外攻击 ----
	_重置战斗()
	玩家.set_crystal(1)
	靶.hand_cards.clear()
	for _i: int in range(5):
		靶.hand_cards.append(法术牌.id)
	引擎.resolve_action(GConst.ActionType.MagicSkill, 狙击动作)
	引擎.run()
	检(靶.hand_cards.size() == 5, "目标手牌已是 5 张时不应再摸牌，实际 %d 张" % 靶.hand_cards.size())
	检(玩家.get_energy() == 0, "目标手牌已满时【狙击】仍应支付能量")
	检(int(_取额外阶段().get("来源", 0)) == 7504, "目标手牌已满时【狙击】仍应进入额外攻击行动阶段")

	# ---- 7504：没给目标时按自己结算 ----
	_重置战斗()
	玩家.set_crystal(1)
	引擎.resolve_action(GConst.ActionType.MagicSkill,
		{"src_id": 1, "action_id": 7504, "card_ids": [], "dst_ids": []})
	引擎.run()
	检(玩家.hand_cards.size() == 5, "没给目标时【狙击】应把发动者自己的手牌补到 5 张，实际 %d 张"
		% 玩家.hand_cards.size())

	# ============================================================
	# 7501 神风矢
	# ============================================================
	_重置战斗()
	发送记录.clear()
	var 火上下文: Dictionary = _攻击上下文(火牌, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_1(火上下文) == BattleRole.SUCCESS, "非风系攻击不应触发【神风矢】")
	检(int(火上下文.get("hit_rate", -1)) == GConst.HitRate.Normal, "非风系攻击的命中率不应被改")
	检(_播报次数(7501) == 0, "非风系攻击不应播报【神风矢】")

	# 风系 + 带 301：神风矢先生效，再问【精准射击】；重入时不重复播报神风矢
	发送记录.clear()
	var 风上下文: Dictionary = _攻击上下文(风301牌, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_1(风上下文) == BattleRole.WAIT, "带 301 的风系攻击应先问【精准射击】")
	检(int(风上下文.get("hit_rate", -1)) == GConst.HitRate.NoReattack,
		"【神风矢】应把风系攻击置为「无法应战」")
	检(_播报次数(7501) == 1, "【神风矢】应播报一次（含目标）")
	检(not _取询问(1, 301).is_empty(), "带 301 的风系攻击没有下发【精准射击】询问")
	_应答([0])
	检(角色.p_timeline_1(风上下文) == BattleRole.SUCCESS, "不发动【精准射击】时应正常收尾")
	检(int(风上下文.get("hit_rate", -1)) == GConst.HitRate.NoReattack, "不发动 301 不应改掉【神风矢】的效果")
	检(int((风上下文.get("harm", {}) as Dictionary).get("point", 0)) == BattleEngine.ATTACK_BASE_POINT,
		"不发动 301 不应改本次攻击伤害")
	检(_播报次数(7501) == 1, "等 301 回复的重入不应重复播报【神风矢】")

	# 非风系 + 带 301：301 借用照常询问、发动后强制命中且伤害 -1
	发送记录.clear()
	var 地上下文: Dictionary = _攻击上下文(地301牌, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_1(地上下文) == BattleRole.WAIT, "带 301 的非风系攻击也应问【精准射击】")
	检(int(地上下文.get("hit_rate", -1)) == GConst.HitRate.Normal, "非风系攻击不应被置「无法应战」")
	_应答([1])
	检(角色.p_timeline_1(地上下文) == BattleRole.SUCCESS, "发动【精准射击】后应正常收尾")
	检(int(地上下文.get("hit_rate", -1)) == GConst.HitRate.NoMiss, "【精准射击】应把本次攻击改成强制命中")
	检(int((地上下文.get("harm", {}) as Dictionary).get("point", 0)) == BattleEngine.ATTACK_BASE_POINT - 1,
		"【精准射击】应让本次攻击伤害 -1")
	检(_播报次数(301) == 1, "借用的【精准射击】应按源技能号 301 播报")
	检(_播报次数(7503) == 0, "借用技能不应播报 7503（播报按源技能号）")

	# 别人的风系攻击宣告：不管
	发送记录.clear()
	var 别家上下文: Dictionary = _攻击上下文(风301牌, 2, 1, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_1(别家上下文) == BattleRole.SUCCESS, "别人的攻击宣告不应触发【神风矢】")
	检(int(别家上下文.get("hit_rate", -1)) == GConst.HitRate.Normal, "别人的攻击命中率不应被改")
	检(_播报次数(7501) == 0, "别人的攻击不应播报【神风矢】")
	检(_取询问(2, 301).is_empty(), "别人的攻击牌不应由本角色询问 301")

	# 完整攻击流水线：风系 301 攻击牌 → 不发动 301 → 目标被标记「无法应战」→ 照常命中
	_重置战斗()
	玩家.hand_cards.append(风301牌.id)
	靶.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [风301牌.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(引擎._await_id == 1, "攻击宣告后应先问攻击者是否发动【精准射击】（等待 %s）" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond,
		{"respond_id": 301, "src_id": 1, "args": [0], "card_ids": [], "dst_ids": []})
	检(引擎._await_id == 2, "【神风矢】结算后应由目标应答（等待 %s）" % str(引擎._await_id))
	var 应战问: Dictionary = _取询问(2, GConst.RespondType.ReplyAttack)
	var 应战标记: int = -1
	if not 应战问.is_empty():
		var 应战参数: Array = 应战问.get("args", [])
		应战标记 = int(应战参数[0]) if not 应战参数.is_empty() else -1
	检(应战标记 == GConst.HitRate.NoReattack, "【神风矢】的应战询问应标记「无法应战」：%s" % str(应战问))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(靶.hand_cards.size() == BattleEngine.ATTACK_BASE_POINT,
		"【神风矢】只是无法应战，攻击应照常命中 %d 点（目标摸 %d 张），实际 %d 张"
		% [BattleEngine.ATTACK_BASE_POINT, BattleEngine.ATTACK_BASE_POINT, 靶.hand_cards.size()])
	检(_播报次数(7501) == 1, "完整攻击流水线里【神风矢】应只播报一次")

	# ============================================================
	# 7502 疾风追射
	# ============================================================
	# 取消：不弃牌、不造伤
	_重置战斗()
	_新一次攻击宣告()
	玩家.hand_cards.append(法术牌.id)
	发送记录.clear()
	var 未命中上下文: Dictionary = _攻击上下文(火牌, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "未命中且有法术牌时应先问是否发动【疾风追射】")
	var 追射问: Dictionary = _取询问(1, 7502)
	检(not 追射问.is_empty(), "没有下发【疾风追射】询问")
	检(str(追射问.get("card_rule", "")) == "magic", "【疾风追射】只能弃法术牌")
	检(int(追射问.get("card_max", 0)) == 1, "【疾风追射】应只能弃 1 张牌")
	检((追射问.get("card_ids", []) as Array).has(法术牌.id), "【疾风追射】的可点牌表应包含手里的法术牌")
	_应答([])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.SUCCESS, "取消【疾风追射】应正常收尾")
	检(玩家.hand_cards.has(法术牌.id), "取消【疾风追射】不应弃牌")
	检(_找伤害(7502, 2).is_empty(), "取消【疾风追射】不应压入伤害")

	# 发动：弃 1 张法术牌【展示】→ 对所攻击目标 2 点法术伤害
	_重置战斗()
	_新一次攻击宣告()
	玩家.hand_cards.append(法术牌.id)
	发送记录.clear()
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "未命中时应先问【疾风追射】")
	_应答([1], [法术牌.id])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.URGENT, "发动【疾风追射】应压入 2 点法术伤害")
	var 追射伤害: Dictionary = _找伤害(7502, 2)
	检(not 追射伤害.is_empty(), "【疾风追射】没有压入对所攻击目标的伤害")
	检(int(追射伤害.get("point", 0)) == 2, "【疾风追射】的伤害应为 2 点")
	检(int(追射伤害.get("type", -1)) == GConst.HarmType.Magic, "【疾风追射】的伤害应是法术伤害")
	检(int(追射伤害.get("src", -1)) == 1, "【疾风追射】的伤害来源应是发动者")
	检(not 玩家.hand_cards.has(法术牌.id), "【疾风追射】弃的法术牌应离手")
	检(引擎.deck.discard.has(法术牌.id), "【疾风追射】弃的法术牌应进弃牌堆")
	检(_播报次数(7502) == 1, "【疾风追射】发动后应播报一次")
	检(not _找消息(GConst.Msg.Card,
		func(数据: Dictionary) -> bool: return (数据.get("card_ids", []) as Array).has(法术牌.id)).is_empty(),
		"【疾风追射】应把弃掉的牌【展示】给所有人")

	# 手里没有法术牌：不询问
	_重置战斗()
	_新一次攻击宣告()
	玩家.hand_cards.append(火牌.id)
	发送记录.clear()
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.SUCCESS, "手里没有法术牌时不应询问【疾风追射】")
	检(_取询问(1, 7502).is_empty(), "手里没有法术牌时不应下发【疾风追射】询问")

	# 非主动攻击（应战反击）不触发
	_重置战斗()
	_新一次攻击宣告()
	玩家.hand_cards.append(法术牌.id)
	发送记录.clear()
	var 应战上下文: Dictionary = _攻击上下文(火牌, 1, 2, false, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_miss(应战上下文) == BattleRole.SUCCESS, "非主动攻击未命中不应触发【疾风追射】")
	检(_取询问(1, 7502).is_empty(), "非主动攻击未命中不应下发【疾风追射】询问")

	# 别人的未命中：不管
	_重置战斗()
	_新一次攻击宣告()
	玩家.hand_cards.append(法术牌.id)
	发送记录.clear()
	var 别家未命中: Dictionary = _攻击上下文(火牌, 2, 1, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_miss(别家未命中) == BattleRole.SUCCESS, "别人的未命中不应触发【疾风追射】")
	检(_取询问(1, 7502).is_empty(), "别人的未命中不应下发【疾风追射】询问")

	# 目标不存在：不弃牌、不造伤
	_重置战斗()
	_新一次攻击宣告()
	玩家.hand_cards.append(法术牌.id)
	发送记录.clear()
	var 空目标上下文: Dictionary = _攻击上下文(火牌, 1, 99, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_miss(空目标上下文) == BattleRole.WAIT, "未命中时应先问【疾风追射】")
	_应答([1], [法术牌.id])
	检(角色.p_timeline_2_miss(空目标上下文) == BattleRole.SUCCESS, "目标不存在时应安全收尾")
	检(玩家.hand_cards.has(法术牌.id), "目标不存在时不应弃牌")
	检(_找伤害(7502, 99).is_empty(), "目标不存在时不应压入伤害")

	# 硬提交非法牌（不是法术牌）：忽略、不弃牌、不造伤
	_重置战斗()
	_新一次攻击宣告()
	玩家.hand_cards.append(火牌.id)
	玩家.hand_cards.append(法术牌.id)
	发送记录.clear()
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "未命中时应先问【疾风追射】")
	_应答([1], [火牌.id])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.SUCCESS, "硬提交非法术牌时应忽略")
	检(玩家.hand_cards.has(火牌.id), "硬提交非法术牌时不应弃牌")
	检(_找伤害(7502, 2).is_empty(), "硬提交非法术牌时不应压入伤害")

	# ============================================================
	# 7503 弓神候补（借用 301 / 302）
	# ============================================================
	# 302 完整结算：亮牌 → 弃置 → 2 点法术伤害 → 目标摸 2 张；播报用源技能号
	_重置战斗()
	玩家.hand_cards.append(陷阱牌.id)
	靶.hand_cards.clear()
	靶.cross_num = 0
	var 陷阱动作: Dictionary = {"src_id": 1, "action_id": 302, "card_ids": [陷阱牌.id], "dst_ids": [2]}
	检(角色.v_magic_skill(陷阱动作) == GConst.GE_SUCCESS, "经 7503 借用的【闪光陷阱】应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 302, "card_ids": [火牌.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "不带【闪光陷阱】的牌不能发动 302")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 302, "card_ids": [陷阱牌.id], "dst_ids": [99]})
		!= GConst.GE_SUCCESS, "目标不存在时不能发动 302")
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 陷阱动作)
	引擎.run()
	检(not 玩家.hand_cards.has(陷阱牌.id), "302 的发动牌应离手")
	检(引擎.deck.discard.has(陷阱牌.id), "302 的发动牌应进弃牌堆")
	检(靶.hand_cards.size() == 2, "302 的 2 点法术伤害应让目标摸 2 张，实际 %d 张" % 靶.hand_cards.size())
	var 陷阱伤害: Dictionary = _找消息(GConst.Msg.Hurt,
		func(数据: Dictionary) -> bool: return int(数据.get("dst_id", -1)) == 2)
	检(not 陷阱伤害.is_empty(), "302 结算没有广播伤害")
	检(int(陷阱伤害.get("hurt", 0)) == 2, "302 的伤害应为 2 点，实际 %s" % str(陷阱伤害.get("hurt")))
	检(int(陷阱伤害.get("type", -1)) == GConst.HarmType.Magic, "302 的伤害应是法术伤害")
	检(int(陷阱伤害.get("cause", 0)) == 302, "302 的伤害来源应为技能号 302")
	检(_播报次数(302) == 1, "借用的【闪光陷阱】应按源技能号 302 播报")
	检(_播报次数(7503) == 0, "借用技能不应播报 7503")

	# 角色说明：7503 借用的神箭手独有技 301 / 302 显示在「独有技」分段，
	# 并且视作 EX魔弓自己的独有技正常显示（不能像剑之子那样置灰）
	var 说明文本: String = 角色技能提示.悬浮提示(75)
	检(说明文本.contains("独有技") and 说明文本.contains("精准射击") and 说明文本.contains("闪光陷阱"),
		"EX魔弓的角色说明应显示神箭手的独有技：%s" % 说明文本)
	检(not 说明文本.contains(角色技能提示.失效行标记 + "精准射击")
		and not 说明文本.contains(角色技能提示.失效行标记 + "闪光陷阱"),
		"EX魔弓借用的神箭手独有技应视作自己的独有技，不能置灰")

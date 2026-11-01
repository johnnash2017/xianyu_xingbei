extends 自检用例
## R93 见习制片（93）：9301 元子吸收 / 9302 元子重塑 / 9303 元素学徒 / 9304 雷击变异 / 9305 月陨。
##
## 任务范围只有 role + test：角色表「脚本」列、技能表「提示」列留给 DATA 任务，
## 所以这里手动把角色挂到玩家 1 身上；提示文案只验「技能栏 / 询问」有没有正确下发。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 技能号 / 技能行 / 技能说明 / 脚本文件 / 元子指示物；
##   - 9301：自己造成法术伤害时每目标 +1 元子、播报 9301；攻击伤害 / 别人造成 / 上限不误加；
##   - 9302：技能栏置灰条件、1~3 张牌校验（重复 / 不在手牌 / 超过 3 张 / 元子不足）、
##            结算（移除 2 元子、弃 X 摸 X、额外法术行动、播报）；
##   - 9303：借用元素师五系独有技（1101~1105）下发、校验，并完整结算一次 1101 风刃；
##   - 9304：雷击的「战绩区 +1 宝石」改为「+1 元子」，宝石不变、元子受上限 3 截断；
##   - 9305：宝石费用不能用晶体顶、目标 1 名、伤害 = 支付后剩余能量 +1、命中后 9301 也触发。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_jianxizhipian.gd")

const 元子槽: int = 0

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 队友: BattlePlayer = null
var 对手甲: BattlePlayer = null
var 对手乙: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []
## 源技能号 -> 卡库里带该技能的一张牌
var 源技能卡: Dictionary = {}


func _init() -> void:
	名称 = "见习制片"


# ============================================================
# 卡库 / 消息 / 询问工具
# ============================================================
func _取卡(技能号: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(技能号):
			return c
	return null


## 取若干张普通牌号作手牌（排除已用的牌；并同步从牌堆里拿掉，避免测试里牌重复）
func _取普通牌(数量: int, 排除: Array = []) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if out.size() >= 数量:
			break
		if c == null or c.is_virtual or 排除.has(c.id) or out.has(c.id):
			continue
		out.append(c.id)
	return out


## 技能表 / 技能栏里按 id 找一项
func _取技能(表: Array, id: int) -> Dictionary:
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


## 某技能号造成的伤害有几条
func _伤害条数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Hurt:
			continue
		if int((r.get("data", {}) as Dictionary).get("cause", 0)) == 技能号:
			n += 1
	return n


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


## 直接给引擎喂一条回复（不经过 run 循环）
func _应答(args: Array, cards: Array = [], dsts: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": dsts}
	引擎._has_reply = true


## 设手牌：先从牌堆 / 弃牌堆拿掉这些牌号，再放进手牌，保证测试的牌张一致
func _设手牌(牌号: Array) -> void:
	玩家.hand_cards.clear()
	for 值: Variant in 牌号:
		var cid: int = int(值)
		引擎.deck.remove_one(cid)
		玩家.hand_cards.append(cid)


## 清空战斗状态：回到「轮到玩家 1、行动阶段、无手牌、0 元子」的同一起点
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.测试跳过回合 = -1
	引擎.team_gem[0] = 0
	引擎.team_gem[1] = 0
	引擎.team_crystal[0] = 0
	引擎.team_crystal[1] = 0
	引擎.team_grail[0] = 0
	引擎.team_grail[1] = 0
	引擎.team_morale[0] = GConst.MORALE_DEFAULT
	引擎.team_morale[1] = GConst.MORALE_DEFAULT
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.cross_num = 0
		p0.set_crystal(0)
		p0.set_gem(0)
		p0.additional_actions.clear()
		p0.boot_skill_used = false
		p0.hand_cards_max = GConst.HAND_CARDS_MAX
		p0.reset_action_counts()
	玩家.set_token_num(元子槽, 0)
	角色.p_before_turn_begin({})


## 9302 的动作字典（默认合法）
func _重塑动作(cards: Array, src: int = 1) -> Dictionary:
	return {"src_id": src, "action_id": 9302, "card_ids": cards, "dst_ids": []}


## 9305 的动作字典（默认合法）
func _月陨动作(dsts: Array, src: int = 1) -> Dictionary:
	return {"src_id": src, "action_id": 9305, "card_ids": [], "dst_ids": dsts}


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 / 元子指示物 ----
	检(str(Data.role_list.get(93, "")) == "见习制片", "93 号角色名不是「见习制片」")
	检(Data.role_personal_name(93) == "惕惕子", "93 号角色姓名不是「惕惕子」")
	检(absf(Data.role_star(93) - 3.5) < 0.01, "见习制片应是 3.5 星，实际 %s" % str(Data.role_star(93)))
	检(Data.role_skills(93) == [9301, 9302, 9303, 9304, 9305],
		"见习制片技能号不对：%s" % str(Data.role_skills(93)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_jianxizhipian.gd"),
		"见习制片的角色脚本文件不存在")
	for 技能号: int in [9301, 9302, 9303, 9304, 9305]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	var 技能说明: String = Data.role_skill_info(93)
	for 技能名: String in ["元子吸收", "元子重塑", "元素学徒", "雷击变异", "月陨"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])
	var 元子定义: Dictionary = Data.role_token_def(93, 元子槽)
	检(str(元子定义.get("name", "")) == "元子", "93 的槽 0 指示物名不是「元子」：%s" % str(元子定义))
	检(int(元子定义.get("max", 0)) == 3, "元子上限应为 3，实际 %s" % str(元子定义))

	# ---- 卡库前提：元素师五系独有技的载体牌 ----
	for 技能号: int in [1101, 1102, 1103, 1104, 1105]:
		var 卡: GCard = _取卡(技能号)
		if 卡 != null:
			源技能卡[技能号] = 卡
	检(源技能卡.size() == 5, "卡库里找不到元素师 1101~1105 的载体牌：%s" % str(源技能卡.keys()))
	if 源技能卡.size() != 5:
		return

	# ---- 建引擎：1 / 2 蓝，3 / 4 红；角色表脚本列留给 DATA，用例里手动挂上角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "见习制片")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({1: 0, 2: 0, 3: 0, 4: 0})
	玩家 = 引擎.p(1)
	队友 = 引擎.p(2)
	对手甲 = 引擎.p(3)
	对手乙 = 引擎.p(4)
	玩家.role_id = 93
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	_重置战斗()
	检(玩家.token_name(元子槽) == "元子" and 玩家.token_max(元子槽) == 3,
		"角色 setup 后槽 0 应是「元子」上限 3：%s" % str(玩家.token_def(元子槽)))

	# ============================================================
	# 9301 元子吸收：自己造成法术伤害时③ +1 元子
	# ============================================================
	_重置战斗()
	角色.p_timeline_3({
		"harm": {"src": 1, "dst": 3, "point": 1, "cause": 9305, "type": GConst.HarmType.Magic},
	})
	检(玩家.token_num(元子槽) == 1, "自己造成法术伤害后应有 1 元子，实际 %d" % 玩家.token_num(元子槽))
	检(_播报次数(9301) == 1, "元子吸收应对目标播报 9301，实际 %d 次" % _播报次数(9301))

	# 别人的法术伤害：不触发
	_重置战斗()
	角色.p_timeline_3({
		"harm": {"src": 3, "dst": 1, "point": 1, "cause": 99, "type": GConst.HarmType.Magic},
	})
	检(玩家.token_num(元子槽) == 0, "别人造成的法术伤害不应触发元子吸收")
	检(_播报次数(9301) == 0, "别人造成的法术伤害不应播报 9301")

	# 攻击伤害：不触发
	_重置战斗()
	角色.p_timeline_3({
		"harm": {"src": 1, "dst": 3, "point": 1, "cause": 9305, "type": GConst.HarmType.Attack},
	})
	检(玩家.token_num(元子槽) == 0, "攻击伤害不应触发元子吸收")
	检(_播报次数(9301) == 0, "攻击伤害不应播报 9301")

	# 多目标各 +1，上限 3
	_重置战斗()
	for 目标: int in [3, 4, 3, 4]:
		角色.p_timeline_3({
			"harm": {"src": 1, "dst": 目标, "point": 1, "cause": 9305, "type": GConst.HarmType.Magic},
		})
	检(玩家.token_num(元子槽) == 3, "多目标触发应各 +1 且被上限 3 截断，实际 %d" % 玩家.token_num(元子槽))
	检(_播报次数(9301) == 4, "每个目标都应播报一次元子吸收，实际 %d 次" % _播报次数(9301))

	# ============================================================
	# 9302 元子重塑：技能栏 / 校验
	# ============================================================
	_重置战斗()
	var 栏: Array = 角色.available_skills()
	var 重塑项: Dictionary = _取技能(栏, 9302)
	检(not 重塑项.is_empty(), "【元子重塑】(9302) 应下发到技能栏")
	检(int(重塑项.get("type", 0)) == GConst.ActionType.MagicSkill, "9302 应作为法术技能按钮下发")
	检(int(重塑项.get("need_card", 0)) == 1 and int(重塑项.get("need_target", 0)) == 0,
		"【元子重塑】应要求至少 1 张牌、不要目标")
	检(int(重塑项.get("card_max", 0)) == 3, "【元子重塑】最多弃 3 张牌")
	检(not bool(重塑项.get("enabled", true)), "没有元子时【元子重塑】应置灰")
	玩家.set_token_num(元子槽, 2)
	检(not bool(_取技能(角色.available_skills(), 9302).get("enabled", true)),
		"手里没有牌时【元子重塑】应置灰")
	var 手牌: Array[int] = _取普通牌(5)
	检(手牌.size() == 5, "卡库里找不到 5 张普通牌")
	if 手牌.size() != 5:
		return
	_设手牌(手牌)
	检(bool(_取技能(角色.available_skills(), 9302).get("enabled", false)),
		"有 2 元子且有手牌时【元子重塑】应可点")

	检(角色.v_magic_skill(_重塑动作([手牌[0]])) == GConst.GE_SUCCESS,
		"弃 1 张牌（X=1）应通过【元子重塑】校验")
	检(角色.v_magic_skill(_重塑动作([手牌[0], 手牌[1], 手牌[2]])) == GConst.GE_SUCCESS,
		"弃 3 张牌（X=3）应通过【元子重塑】校验")
	检(角色.v_magic_skill(_重塑动作([手牌[0], 手牌[1], 手牌[2], 手牌[3]])) != GConst.GE_SUCCESS,
		"弃 4 张牌（X≥4）不应通过【元子重塑】校验")
	检(角色.v_magic_skill(_重塑动作([])) != GConst.GE_SUCCESS,
		"弃 0 张牌不应通过【元子重塑】校验")
	检(角色.v_magic_skill(_重塑动作([手牌[0], 手牌[0]])) != GConst.GE_SUCCESS,
		"同一张牌重复提交不应通过【元子重塑】校验")
	var 不在手牌: int = -1
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and not 玩家.hand_cards.has(c.id):
			不在手牌 = c.id
			break
	检(不在手牌 >= 0, "找不到一张不在手里的牌")
	if 不在手牌 >= 0:
		检(角色.v_magic_skill(_重塑动作([手牌[0], 不在手牌])) != GConst.GE_SUCCESS,
			"不在手里的牌不应通过【元子重塑】校验")
	检(角色.v_magic_skill(_重塑动作([手牌[0]], 2)) != GConst.GE_SUCCESS,
		"别人的【元子重塑】行动不应通过本角色校验")
	玩家.set_token_num(元子槽, 1)
	检(角色.v_magic_skill(_重塑动作([手牌[0]])) != GConst.GE_SUCCESS,
		"只有 1 元子时不应通过【元子重塑】校验")

	# ============================================================
	# 9302 元子重塑：完整结算
	# ============================================================
	_重置战斗()
	玩家.set_token_num(元子槽, 2)
	_设手牌(手牌)
	var 弃牌前: int = 引擎.deck.discard_size()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _重塑动作([手牌[0], 手牌[1]]))
	引擎.run()
	检(玩家.token_num(元子槽) == 0, "【元子重塑】应移除 2 元子，实际剩 %d" % 玩家.token_num(元子槽))
	检(玩家.hand_cards.size() == 5, "弃 2 摸 2 后手牌应仍为 5 张，实际 %d 张" % 玩家.hand_cards.size())
	检(引擎.deck.discard_size() == 弃牌前 + 2,
		"【元子重塑】弃掉的 2 张牌应进弃牌堆，弃牌堆 %d → %d" % [弃牌前, 引擎.deck.discard_size()])
	检(引擎.deck.discard.has(手牌[0]) and 引擎.deck.discard.has(手牌[1]),
		"【元子重塑】弃掉的 2 张牌应进弃牌堆")
	检(_播报次数(9302) == 1, "【元子重塑】结算应播报 9302，实际 %d 次" % _播报次数(9302))
	检(玩家.magic_action_count == 1 and 玩家.action_count() == 1,
		"【元子重塑】应记 1 次法术行动：%s" % str(引擎.行动计数(1)))
	var 重塑阶段: Dictionary = _取额外阶段()
	检(not 重塑阶段.is_empty(), "【元子重塑】结算完应进入额外法术行动阶段（栈顶：%s）"
		% str(引擎._states[-1] if not 引擎._states.is_empty() else null))
	检(bool(重塑阶段.get("额外", false)) and int(重塑阶段.get("允许", 0)) == GConst.ActionType.Magic,
		"【元子重塑】的额外行动应只允许法术：%s" % str(重塑阶段))
	检(int(重塑阶段.get("来源", 0)) == 9302, "【元子重塑】额外行动阶段的来源应为 9302：%s" % str(重塑阶段))
	var 弃牌展示: Dictionary = _找消息(GConst.Msg.Card,
		func(数据: Dictionary) -> bool:
			return int(数据.get("type", 0)) == GConst.CardMsgType.Show \
				and (数据.get("card_ids", []) as Array).has(手牌[0]))
	检(弃牌展示.is_empty(), "技能原文没写【展示】，【元子重塑】不应把弃牌展示给全场")

	# ============================================================
	# 9303 元素学徒：借用元素师五系独有技（1101~1105）
	# ============================================================
	_重置战斗()
	var 全源卡: Array[int] = []
	for 技能号: int in [1101, 1102, 1103, 1104, 1105]:
		全源卡.append(int(源技能卡[技能号].id))
	_设手牌(全源卡)
	栏 = 角色.available_skills()
	检(栏.size() == 7, "技能栏应是【元子重塑】+【月陨】+ 借用的五系法术共 7 项，实际 %d 项：%s"
		% [栏.size(), str(栏)])
	for 技能号: int in [1101, 1102, 1103, 1104, 1105]:
		var 借用项: Dictionary = _取技能(栏, 技能号)
		检(not 借用项.is_empty(), "元素学徒应下发借用的 %d" % 技能号)
		检(int(借用项.get("type", 0)) == GConst.ActionType.MagicSkill, "%d 应作为法术技能按钮下发" % 技能号)
		检(int(借用项.get("need_card", 0)) == 1, "借用的 %d 应要求 1 张发动牌" % 技能号)
		检(bool(借用项.get("enabled", false)), "手里有载体牌时借用的 %d 应可点" % 技能号)
		var 目标: Array = [3, 4] if 技能号 == 1102 else [3]
		检(角色.v_magic_skill({
			"src_id": 1, "action_id": 技能号,
			"card_ids": [int(源技能卡[技能号].id)], "dst_ids": 目标,
		}) == GConst.GE_SUCCESS, "借用的 %d 应通过校验" % 技能号)
	检(角色.v_magic_skill({
		"src_id": 2, "action_id": 1101,
		"card_ids": [int(源技能卡[1101].id)], "dst_ids": [1],
	}) != GConst.GE_SUCCESS, "别人的借用元素师技能不应通过本角色校验")

	# 完整结算一次 1101 风刃：弃发动牌 → 1 法术伤害 → 9301 +1 元子 → 额外 +1 攻击行动
	_重置战斗()
	_设手牌([int(源技能卡[1101].id)])
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 1101,
		"card_ids": [int(源技能卡[1101].id)], "dst_ids": [3],
	})
	引擎.run()
	检(not 玩家.hand_cards.has(int(源技能卡[1101].id)), "借用的【风刃】发动牌应离手")
	检(引擎.deck.discard.has(int(源技能卡[1101].id)), "借用的【风刃】发动牌应进弃牌堆")
	检(对手甲.hand_cards.size() == 1, "【风刃】应对目标造成 1 点法术伤害（摸 1 张），实际 %d 张"
		% 对手甲.hand_cards.size())
	检(_播报次数(1101) == 1, "借用的【风刃】应按源技能号 1101 播报，实际 %d 次" % _播报次数(1101))
	检(玩家.token_num(元子槽) == 1, "借用的【风刃】造成法术伤害也应触发元子吸收")
	var 风刃阶段: Dictionary = _取额外阶段()
	检(not 风刃阶段.is_empty() and int(风刃阶段.get("允许", 0)) == GConst.ActionType.Attack,
		"【风刃】结算完应进入额外攻击行动阶段：%s" % str(风刃阶段))
	检(int(风刃阶段.get("来源", 0)) == 1101, "【风刃】额外行动阶段的来源应为 1101：%s" % str(风刃阶段))

	# ============================================================
	# 9304 雷击变异：雷击的「战绩区 +1 宝石」改为「你 +1 元子」
	# ============================================================
	_重置战斗()
	_设手牌([int(源技能卡[1105].id)])
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 1105,
		"card_ids": [int(源技能卡[1105].id)], "dst_ids": [3],
	})
	引擎.run()
	检(int(引擎.team_gem[GConst.BLUE]) == 0,
		"【雷击变异】不应再给战绩区 +1 宝石，实际 %d" % int(引擎.team_gem[GConst.BLUE]))
	检(玩家.token_num(元子槽) == 2,
		"【雷击】的 9301 与【雷击变异】各 +1 元子，应为 2，实际 %d" % 玩家.token_num(元子槽))
	检(对手甲.hand_cards.size() == 1, "【雷击】应对目标造成 1 点法术伤害，实际 %d 张"
		% 对手甲.hand_cards.size())
	检(_播报次数(1105) == 1, "借用的【雷击】应按源技能号 1105 播报，实际 %d 次" % _播报次数(1105))

	# 元子已满：雷击变异不越过上限 3，也不改宝石
	_重置战斗()
	玩家.set_token_num(元子槽, 3)
	_设手牌([int(源技能卡[1105].id)])
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 1105,
		"card_ids": [int(源技能卡[1105].id)], "dst_ids": [3],
	})
	引擎.run()
	检(玩家.token_num(元子槽) == 3, "元子已满时【雷击变异】不应越过上限，实际 %d" % 玩家.token_num(元子槽))
	检(int(引擎.team_gem[GConst.BLUE]) == 0, "元子已满时【雷击变异】也不应改回 +1 宝石")

	# ============================================================
	# 9305 月陨：技能栏 / 校验
	# ============================================================
	_重置战斗()
	var 月陨项: Dictionary = _取技能(角色.available_skills(), 9305)
	检(not 月陨项.is_empty(), "【月陨】(9305) 应下发到技能栏")
	检(int(月陨项.get("type", 0)) == GConst.ActionType.MagicSkill, "9305 应作为法术技能按钮下发")
	检(int(月陨项.get("need_target", 0)) == 1, "【月陨】应要求 1 名目标")
	检(not bool(月陨项.get("enabled", true)), "没有宝石时【月陨】应置灰")
	玩家.set_crystal(1)
	检(not bool(_取技能(角色.available_skills(), 9305).get("enabled", true)),
		"只有水晶时【月陨】仍应置灰（费用写【宝石】，不能用晶体顶）")
	检(角色.v_magic_skill(_月陨动作([3])) != GConst.GE_SUCCESS,
		"只有水晶时【月陨】不应通过校验")
	玩家.set_gem(1)
	检(bool(_取技能(角色.available_skills(), 9305).get("enabled", false)),
		"有宝石时【月陨】应可点")
	检(角色.v_magic_skill(_月陨动作([3])) == GConst.GE_SUCCESS, "合法的【月陨】应通过校验")
	检(角色.v_magic_skill(_月陨动作([])) != GConst.GE_SUCCESS, "【月陨】必须指定 1 名目标")
	检(角色.v_magic_skill(_月陨动作([3, 4])) != GConst.GE_SUCCESS, "【月陨】不应接受 2 名目标")
	检(角色.v_magic_skill(_月陨动作([99])) != GConst.GE_SUCCESS, "【月陨】不应接受不存在的目标")
	检(角色.v_magic_skill(_月陨动作([3], 2)) != GConst.GE_SUCCESS,
		"别人的【月陨】行动不应通过本角色校验")

	# ============================================================
	# 9305 月陨：完整结算（X 在支付后计算）
	# ============================================================
	_重置战斗()
	玩家.set_gem(1)
	玩家.set_crystal(1)
	对手甲.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _月陨动作([3]))
	引擎.run()
	检(玩家.gem == 0 and 玩家.crystal == 1, "【月陨】应支付 1 宝石、保留 1 水晶：宝石 %d / 水晶 %d"
		% [玩家.gem, 玩家.crystal])
	检(对手甲.hand_cards.size() == 2,
		"支付后剩余能量 1，【月陨】应造成 2 点法术伤害（目标摸 2 张），实际 %d 张"
		% 对手甲.hand_cards.size())
	检(_伤害条数(9305) == 1, "【月陨】应广播 1 条法术伤害，实际 %d 条" % _伤害条数(9305))
	检(_播报次数(9305) == 1, "【月陨】应播报 9305，实际 %d 次" % _播报次数(9305))
	检(玩家.token_num(元子槽) == 1, "【月陨】造成法术伤害也应触发元子吸收")

	# 3 宝石：先扣 1 再算 X（2+1=3 点），不是扣费前的 4 点
	_重置战斗()
	玩家.set_gem(3)
	对手甲.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _月陨动作([3]))
	引擎.run()
	检(玩家.gem == 2, "【月陨】应支付 1 宝石，实际剩 %d" % 玩家.gem)
	检(对手甲.hand_cards.size() == 3,
		"3 宝石支付后剩 2 能量，【月陨】应造成 3 点法术伤害（目标摸 3 张），实际 %d 张"
		% 对手甲.hand_cards.size())

	# 目标可以选择自己
	_重置战斗()
	玩家.set_gem(1)
	玩家.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _月陨动作([1]))
	引擎.run()
	检(玩家.gem == 0, "以自己为目标的【月陨】也应支付 1 宝石")
	检(玩家.token_num(元子槽) == 1, "【月陨】打自己也是一次自己造成的法术伤害，应触发元子吸收")
	检(玩家.hand_cards.size() == 1, "以自己为目标的【月陨】造成 1 点伤害应摸 1 张，实际 %d 张"
		% 玩家.hand_cards.size())

	# ============================================================
	# 9303 借用的元素师五系独有法术：统一登记进「借用独有技」表
	# （卡面标绿 / 测试指令 2 / 角色说明；视作自己的独有技，不置灰）
	# ============================================================
	检(GConst.借用独有技(93) == [1101, 1102, 1103, 1104, 1105],
		"93 的借用独有技应为元素师 1101~1105：%s" % str(GConst.借用独有技(93)))
	var 卡面脚本: GDScript = load("res://scripts/CardUI.gd")
	var 卡面技能: Array = 卡面脚本.显示技能(93, Data.role_skills(93))
	检(卡面技能.has(1101) and 卡面技能.has(1105),
		"见习制片的卡面应把元素师独有法术 1101~1105 显示成自己会：%s" % str(卡面技能))
	检(not 卡面脚本.显示技能(38, Data.role_skills(38)).has(1101),
		"别的角色不应白拿 1101")
	_重置战斗()
	引擎.debug_key(1, GConst.DebugKey.SkillCards)
	var 有元素法术: bool = false
	for cid: int in 玩家.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		for 技能号: int in [1101, 1102, 1103, 1104, 1105]:
			if c.has_skill_id(技能号):
				有元素法术 = true
	检(有元素法术, "测试指令 2 应给见习制片发元素师独有法术的牌：%s" % str(玩家.hand_cards))
	var 说明文本: String = 角色技能提示.悬浮提示(93)
	检(说明文本.contains("独有技") and 说明文本.contains("风刃") and 说明文本.contains("雷击"),
		"见习制片的角色说明应显示元素师的独有法术：%s" % 说明文本)
	检(not 说明文本.contains(角色技能提示.失效行标记 + "风刃"),
		"见习制片借用的元素法术应视作自己的，不置灰")

	# ============================================================
	# 9304【雷击变异】改写借来的元素师【雷击】(1105)：
	# 技能名改成【雷击*见习制片】，说明用改写版；悬停提示也按「当前角色」取改写后的
	# ============================================================
	检(GConst.技能名覆盖(93, 1105) == "雷击*见习制片",
		"9304 应把雷击改名成【雷击*见习制片】：%s" % GConst.技能名覆盖(93, 1105))
	检(GConst.技能名覆盖(11, 1105) == "", "元素师自己不该被改名")
	var 雷击改写: String = GConst.技能说明覆盖(93, 1105)
	检(雷击改写.contains("元子") and not 雷击改写.contains("宝石"),
		"9304 应把雷击说明改写成「+1 元子」、不再写宝石：%s" % 雷击改写)
	var 雷击悬停: String = 角色技能提示.单个技能(1105, 0, 93)
	检(雷击悬停.contains("雷击*见习制片"),
		"见习制片悬停雷击应显示【雷击*见习制片】：%s" % 雷击悬停)
	检(雷击悬停.contains("元子"), "见习制片悬停雷击应显示改写后的说明：%s" % 雷击悬停)
	var 元素师悬停: String = 角色技能提示.单个技能(1105, 0, 11)
	检(元素师悬停.contains("战绩区") and not 元素师悬停.contains("元子") \
		and not 元素师悬停.contains("*见习制片"),
		"元素师自己悬停雷击仍是原名原说明：%s" % 元素师悬停)
	# 角色说明的「独有技」里也应是【雷击*见习制片】，不再单列原版划掉
	var 改名行: String = ""
	for 行: String in 说明文本.split("\n"):
		if 行.contains("雷击*见习制片"):
			改名行 = 行
			break
	检(改名行 != "" and 改名行.contains("元子"),
		"独有技里应显示【雷击*见习制片】+ 改写后的说明：%s" % 改名行)
	检(not 说明文本.contains("[s]"),
		"不再用「把原版列出来划掉」的做法：%s" % 说明文本)

extends 自检用例
## 异教徒（95）实际跑测：末日预言的【预言】堆、翻面、天雷劫火 / 地裂波涛的「展示时」、
## 【贪婪】两项都发动、【灾殃止息】移除、【献祭】、【放逐】（无视手牌上限）。
##
## 驱动方式与其它角色用例一致：直接调角色钩子 / 技能入口，把回复塞进引擎后 run()，
## 由状态栈自己推进（与线上同一条路径，不在用例里复制规则）。

const 角色路径: String = "res://scripts/battle/roles/role_yijiaotu.gd"

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "异教徒（95）：末日预言 / 天雷劫火 / 地裂波涛 / 贪婪 / 灾殃止息"


func 跑() -> void:
	_检开局与手牌上限()
	_检状态显示资料()
	_检献祭同系()
	_检献祭异系()
	_检翻面天雷()
	_检贪婪两项()
	_检灾殃止息()
	_检放逐()
	_检翻面用记下的正面()
	_检放逐超时()
	_检审判()
	_检审判超时()
	_检审判弃刃触发渗蚀()
	_检审判选项值对应()
	_检审判摸牌先结算超限()
	_检审判头像提示()
	_检审判残留状态()
	引擎 = null


# ============================================================
# 建局
# ============================================================
func _建引擎() -> void:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles({})
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.role = null
		p0.hand_cards.clear()
		p0.cross_num = 0
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	角色 = (load(角色路径) as GDScript).new()
	角色.setup(玩家1, 引擎)
	玩家1.role = 角色
	玩家1.role_id = 95
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.round_id = 1


## 把一条回复塞进引擎（随后 run() 由状态栈取走）
func _应答(args: Array = [], dsts: Array = [], cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": dsts, "respond_id": 0}
	引擎._has_reply = true


## 跑到「问目标对手」的询问为止：途中的「治疗抵挡」询问一律答不用治疗
func _等到目标询问() -> bool:
	for i: int in range(10):
		引擎.run()
		if 引擎._await_id < 0:
			return false
		if 引擎._pending_respond_id == GConst.RespondType.Heal:
			_应答([0])
			continue
		return 引擎._await_id == 1 and 引擎._pending_respond_id == 9507
	return false


## 最近一条指定技能号的技能询问文案（ask_text）
func _最近询问文案(技能号: int) -> String:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 技能号:
			return str(c.get("ask_prompt", c.get("ask_text", "")))
	return ""


## 模拟超时兜底：引擎超时下发的就是空 args / 空 card_ids + is_timeout
func _应答超时() -> void:
	引擎._reply = {"args": [], "card_ids": [], "dst_ids": [], "is_timeout": true, "respond_id": 0}
	引擎._has_reply = true


## 最近一条「放逐」技能询问里的 option_skill_ids（选项各自挂的技能号）
func _询问选项技能号() -> Array:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 9505:
			return (c.get("option_skill_ids", []) as Array).duplicate()
	return []


## 一项的收尾：目标对手「自选弃任意张该系牌」答不弃、治疗抵挡答不用；
## 直到出现下一项的目标询问（交给调用方）或整个展示流程结束
func _本项收尾() -> void:
	for i: int in range(8):
		引擎.run()
		if 引擎._await_id < 0:
			return
		if 引擎._pending_respond_id == GConst.RespondType.Heal:
			_应答([0])
			continue
		if 引擎._await_id == 玩家2.id and 引擎._pending_respond_id == 9507:
			_应答([], [], [])
			continue
		return


## 跑一段伤害结算：只在「治疗抵挡」询问时回答不用治疗，其它询问一律留着给用例自己答
func _收伤害() -> void:
	for i: int in range(8):
		引擎.run()
		if 引擎._await_id < 0 or 引擎._pending_respond_id != GConst.RespondType.Heal:
			return
		_应答([0])


## 给某玩家 n 张指定系别的牌（牌库牌的实例号 == 牌面），返回实例号
func _发牌(p: BattlePlayer, 元素: int, n: int) -> Array:
	var out: Array = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element_enum() != 元素:
			continue
		p.add_hand_cards([c.id])
		out.append(c.id)
		if out.size() >= n:
			break
	return out


func _放末日(预言: Array = []) -> void:
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 预言.size(), "counter_max": 6, "state": 0, "pile": 预言})


func _场卡(名: String) -> Dictionary:
	return 引擎.取场卡(名) if 引擎.有场卡(名) else {}


# ============================================================
# 1. 异端邪说：开局 +1 水晶；【末日预言】在场时手牌上限 -1
# ============================================================
func _检开局与手牌上限() -> void:
	_建引擎()
	检(玩家1.crystal == 1, "【异端邪说】开局应 +1 水晶：%d" % 玩家1.crystal)
	_放末日([101])
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == GConst.HAND_CARDS_MAX - 1,
		"【末日预言】在场时手牌上限应 -1：%d" % 玩家1.hand_cards_max)
	引擎.移除场卡("末日预言")
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == GConst.HAND_CARDS_MAX,
		"【末日预言】离场后手牌上限应恢复：%d" % 玩家1.hand_cards_max)


# ============================================================
# 2. 献祭：同系 → 移除该预言、+1 宝石
# ============================================================
func _检献祭同系() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	var 两张: Array = _发牌(玩家1, GConst.CardElement.Wind, 2)
	_放末日(两张)
	# 【献祭】是「启动」：技能类型必须是 SpecialSkill（不是法术技能），否则会去消耗放逐给的额外行动
	var 献祭项: Dictionary = {}
	for 项: Dictionary in 角色.available_skills():
		if int(项.get("id", 0)) == 9503:
			献祭项 = 项
	检(int(献祭项.get("type", 0)) == GConst.ActionType.SpecialSkill,
		"【献祭】应作为启动技（SpecialSkill）下发：%s" % str(献祭项.get("type", 0)))
	var rc: int = 角色.p_special_skill({"action_id": 9503, "src_id": 1})
	检(rc == BattleRole.URGENT, "【献祭】应压入展示流程并返回 URGENT")
	检(玩家1.boot_skill_used, "发动启动技后应记 boot_skill_used（每回合只能一个）")
	引擎.run()
	检(引擎._await_id == 1, "【献祭】应先问系别（等待 %s）" % str(引擎._await_id))
	_应答([GConst.CardElement.Wind])
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	检(int(表.get("pile", []).size()) == 1, "同系应移除 1 张【预言】：%d" % int(表.get("pile", []).size()))
	检(引擎.team_gem[GConst.BLUE] == 1, "同系应让战绩区 +1【宝石】")
	检(角色.v_magic_skill({"action_id": 9503, "src_id": 1}) == GConst.GE_INVALID_ACTION,
		"【献祭】不应再有法术技能入口（否则能被当成放逐给的额外法术行动用掉）")
	检(引擎.deck.discard.has(int(两张[1])), "被移除的【预言】应进弃牌堆")


# ============================================================
# 3. 献祭：异系 → 与牌库顶交换、该【预言】加入手牌
# ============================================================
func _检献祭异系() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	var 风: Array = _发牌(玩家1, GConst.CardElement.Wind, 1)
	var 牌库顶前: int = int(引擎.deck.pile.back())
	_放末日([int(风[0])])
	角色.p_special_skill({"action_id": 9503, "src_id": 1})
	引擎.run()
	_应答([GConst.CardElement.Fire])
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	var 堆: Array = 表.get("pile", [])
	检(堆.size() == 1, "异系交换后【预言】堆应仍是 1 张：%d" % 堆.size())
	检(int(堆.back()) == 牌库顶前, "交换后堆顶应是原牌库顶那张：%d / %d" % [int(堆.back()), 牌库顶前])
	检(玩家1.有手牌(int(风[0])), "异系的【预言】应加入你手牌")
	检(引擎.team_gem[GConst.BLUE] == 0, "异系不应 +宝石")


# ============================================================
# 4. 翻面 + 天雷劫火「展示时」（无贪婪）
# ============================================================
func _检翻面天雷() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	玩家1.set_gem(0)
	var 雷: Array = _发牌(玩家1, GConst.CardElement.Thunder, 2)
	var 敌雷: Array = _发牌(玩家2, GConst.CardElement.Thunder, 1)
	var 敌手牌前: int = 玩家2.hand_cards.size()
	_放末日([])
	角色._检查预言取空()
	引擎.run()
	检(引擎._await_id == 1, "【预言】取空后应问翻面（等待 %s）" % str(引擎._await_id))
	_应答([1])          # 1 = 天雷劫火
	引擎.run()
	检(引擎.有场卡("天雷劫火") and not 引擎.有场卡("末日预言"),
		"翻面后场卡应变成【天雷劫火】")
	检(引擎._await_id == 1, "能量为 0 时应跳过贪婪、直接问系别")
	_应答([GConst.CardElement.Thunder])
	引擎.run()
	检(引擎._await_id == 1, "选完系别应问弃几张该系牌（等待 %s）" % str(引擎._await_id))
	_应答([], [], 雷)
	引擎.run()
	检(引擎._await_id == 1, "弃牌后应问目标对手（等待 %s）" % str(引擎._await_id))
	_应答([], [2])
	引擎.run()
	检(引擎._await_id == 2, "应问目标对手弃任意张该系牌（等待 %s / %s）"
		% [str(引擎._await_id), str(引擎._await_kind)])
	_应答([], [], 敌雷)
	_收伤害()
	检(引擎.deck.discard.has(int(敌雷[0])), "目标对手弃掉的牌应进弃牌堆")
	检(玩家2.hand_cards.size() == 敌手牌前 - 1 + 3,
		"目标应弃 1 张、再因 3 点法术伤害摸 3 张：%d → %d"
		% [敌手牌前, 玩家2.hand_cards.size()])
	检(玩家1.hand_cards.size() == 雷.size() - 2 + 2, "你弃 2 张再摸 2 张")
	检(引擎.有场卡("天雷劫火"), "展示结算完后【天雷劫火】应留在场上（等灾殃止息移除）")


# ============================================================
# 5. 贪婪：两项都发动、顺序由玩家选
# ============================================================
func _检贪婪两项() -> void:
	_建引擎()
	检(玩家1.get_energy() >= 1, "开局应有 1 点能量可供【贪婪】")
	var 敌手牌前: int = 玩家2.hand_cards.size()
	_放末日([])
	角色._检查预言取空()
	引擎.run()
	_应答([1])          # 天雷劫火
	引擎.run()
	检(引擎._await_id == 1, "有能量时应先问是否发动【贪婪】（等待 %s）" % str(引擎._await_id))
	_应答([1])          # 发动贪婪
	引擎.run()
	检(玩家1.get_energy() == 0, "【贪婪】应消耗 1 点能量")
	检(引擎._await_id == 1, "贪婪应再问两项顺序（等待 %s）" % str(引擎._await_id))
	_应答([1])          # 先雷后火
	# 两项都不弃牌（手里没有该系牌）：各造成 X+1 = 1 点法术伤害。
	# 中间可能插入目标方的「治疗抵挡」询问，必须先答掉、等到真正问目标时才提交。
	for i: int in range(2):
		检(_等到目标询问(), "第 %d 项应问目标对手（等待 %s / 号 %s）"
			% [i + 1, str(引擎._await_id), str(引擎._pending_respond_id)])
		_应答([], [2])
		_本项收尾()
	检(玩家2.hand_cards.size() == 敌手牌前 + 2,
		"两项各 1 点伤害，目标应摸 2 张：%d → %d" % [敌手牌前, 玩家2.hand_cards.size()])
	检(引擎.有场卡("天雷劫火"), "两项结算完后场卡仍在")


# ============================================================
# 6. 灾殃止息：异教徒回合开始移除天雷 / 地裂
# ============================================================
func _检灾殃止息() -> void:
	_建引擎()
	引擎.加场卡({"id": "天雷劫火", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 0, "state": 1})
	引擎.加场卡({"id": "地裂波涛", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 0, "state": 2})
	角色.p_before_turn_begin({"player": 1})
	检(not 引擎.有场卡("天雷劫火") and not 引擎.有场卡("地裂波涛"),
		"【灾殃止息】应移除【天雷劫火】/【地裂波涛】")
	var 有通知: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Skill and int((r["data"] as Dictionary).get("skill_id", 0)) == 9509:
			有通知 = true
	检(有通知, "【灾殃止息】移除时应播技能通知")


# ============================================================
# 7. 放逐：无视手牌上限摸 6、6 张手牌作【预言】、额外行动
# ============================================================
func _检放逐() -> void:
	_建引擎()
	# 手里 5 张、场上已有【末日预言】（手牌上限 5）：摸 6 张会超过上限，
	# 但放逐期间是「不爆牌」状态，不该弹超限弃牌。
	_发牌(玩家1, GConst.CardElement.Wind, 5)
	_放末日([101, 102])
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == 5, "放逐前手牌上限应为 5：%d" % 玩家1.hand_cards_max)
	# 摸几张由二级技能栏选（同魔眼）：技能栏带三个 arg_choices，不选返回就不该通过校验
	var 放逐项: Dictionary = {}
	for 项: Dictionary in 角色.available_skills():
		if int(项.get("id", 0)) == 9505:
			放逐项 = 项
	检(not 放逐项.is_empty() and (放逐项.get("arg_choices", []) as Array).size() == 3,
		"【放逐】应给出摸 6/7/8 三个档（二级技能栏）")
	var 档: Array = 放逐项.get("arg_choices", [])
	检(int(档[0].get("args", [0])[0]) == 6 and int(档[2].get("args", [0])[0]) == 8,
		"三档应分别是 6 / 7 / 8 张")
	检(角色.v_magic_skill({"action_id": 9505, "src_id": 1, "args": []}) == GConst.GE_INVALID_ARGUMENT,
		"没选摸牌档（按「返回」）时不应通过校验")
	var rc: int = 角色.p_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]})
	检(rc == BattleRole.URGENT, "【放逐】应进入摸牌流程")
	引擎.run()
	检(玩家1.hand_cards.size() == 11, "摸 6 张后应 11 张手牌：%d" % 玩家1.hand_cards.size())
	检(引擎._pending_respond_id == 9505,
		"不爆牌状态下不应弹超限弃牌（当前询问号 %s）" % str(引擎._pending_respond_id))
	检(引擎._await_id == 1, "摸完牌应问放哪张【末日预言】（等待 %s）" % str(引擎._await_id))
	检(_询问选项技能号() == [9507, 9508],
		"正面二选一的选项应挂技能号（悬停看被动说明）：%s" % str(_询问选项技能号()))
	_应答([1])          # 天雷劫火
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9505,
		"选完正面后应问选 6 张手牌作为【预言】（等待 %s）" % str(引擎._await_id))
	var 手: Array = 玩家1.hand_cards.duplicate()
	var 选六: Array = []
	for i: int in range(6):
		选六.append(int(手[i]))
	_应答([], [], 选六)
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	检(int(表.get("counter", 0)) == 6 and int(表.get("pile", []).size()) == 6,
		"6 张手牌应成为【预言】：%d" % int(表.get("counter", 0)))
	检(str(表.get("front", "")) == "天雷劫火", "放置时应记下正面为【天雷劫火】：%s"
		% str(表.get("front", "")))
	# 正面是隐藏信息：只有拥有者自己的快照能拿到，别人拿不到
	var 自己正面: String = ""
	var 别人正面: String = ""
	for 项: Dictionary in 引擎.game_info(1).get("field_cards", []):
		if str(项.get("id", "")) == "末日预言":
			自己正面 = str(项.get("front", ""))
	for 项: Dictionary in 引擎.game_info(2).get("field_cards", []):
		if str(项.get("id", "")) == "末日预言":
			别人正面 = str(项.get("front", ""))
	检(自己正面 == "天雷劫火", "拥有者自己的快照里应带正面：%s" % 自己正面)
	检(别人正面.is_empty(), "别人的快照里不应带正面：%s" % 别人正面)
	检(玩家1.hand_cards.size() == 5, "选走 6 张后应剩 5 张：%d" % 玩家1.hand_cards.size())
	检(玩家1.get_energy() == 0, "【放逐】应消耗 1 点能量")
	# 回合限定：同一回合只能发动一次
	var 放逐项2: Dictionary = {}
	for 项2: Dictionary in 角色.available_skills():
		if int(项2.get("id", 0)) == 9505:
			放逐项2 = 项2
	检(not bool(放逐项2.get("enabled", true)), "同一回合内【放逐】应置灰")
	检(角色.v_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]}) == GConst.GE_INVALID_ACTION,
		"同一回合第二次【放逐】不应通过校验")
	检(角色.p_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]}) == GConst.GE_INVALID_ACTION,
		"直接调执行体也不能绕过回合限定")
	# 下回合开始重置
	玩家1.set_crystal(1)
	角色.p_before_turn_begin({"player": 1})
	var 放逐项3: Dictionary = {}
	for 项3: Dictionary in 角色.available_skills():
		if int(项3.get("id", 0)) == 9505:
			放逐项3 = 项3
	检(bool(放逐项3.get("enabled", false)), "新回合开始【放逐】应重新可发动")
	# 「额外 +1【攻击行动】或【法术行动】」= 一份攻击/法术都能用的额外行动
	var 额外: Dictionary = {}
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 9505:
			额外 = a
	检(not 额外.is_empty(), "【放逐】应给 1 份额外行动")
	检(int(额外.get("allow_action", 0)) == GConst.ActionType.AttackMagic,
		"这份额外行动应同时允许攻击与法术：%s" % str(额外.get("allow_action", 0)))
	检(引擎._不爆牌.is_empty(), "放逐结算完应解除不爆牌状态")


# ============================================================
# 8. 放逐放下的【末日预言】翻面时用记下的正面（不再问二选一）
# ============================================================
func _检翻面用记下的正面() -> void:
	_建引擎()
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 6, "state": 0, "pile": [], "front": "地裂波涛"})
	角色._检查预言取空()
	引擎.run()
	检(引擎.有场卡("地裂波涛") and not 引擎.有场卡("末日预言"),
		"应按记下的正面翻成【地裂波涛】")
	检(引擎._pending_respond_id != 9504 or 引擎._await_id < 0,
		"已记正面时不应再问翻面二选一（询问号 %s）" % str(引擎._pending_respond_id))


# ============================================================
# 9. 放逐超时兜底：正面随机、6 张手牌自动放
# ============================================================
func _检放逐超时() -> void:
	_建引擎()
	var rc: int = 角色.p_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]})
	检(rc == BattleRole.URGENT, "【放逐】应进入摸牌流程")
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9505,
		"摸完牌应问正面（等待 %s / 号 %s）" % [str(引擎._await_id), str(引擎._pending_respond_id)])
	# 正面超时 / 跳过：随机选一个，继续流程
	_应答超时()
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	var 正面: String = str(表.get("front", ""))
	检(正面 == "天雷劫火" or 正面 == "地裂波涛", "超时应随机选一个正面：%s" % 正面)
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9505,
		"超时选正面后应继续问 6 张手牌（等待 %s）" % str(引擎._await_id))
	# 6 张手牌超时：自动放 6 张
	_应答超时()
	引擎.run()
	表 = _场卡("末日预言")
	检(int(表.get("counter", 0)) == 6 and int(表.get("pile", []).size()) == 6,
		"超时应自动放 6 张作为【预言】：%d" % int(表.get("counter", 0)))
	检(玩家1.hand_cards.is_empty(), "6 张都被放成【预言】后手牌应为空：%d" % 玩家1.hand_cards.size())
	var 有额外: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 9505 and int(a.get("allow_action", 0)) == GConst.ActionType.AttackMagic:
			有额外 = true
	检(有额外, "超时结算完也应给那份攻击/法术合一的额外行动")
	检(引擎._不爆牌.is_empty(), "超时结算完应解除不爆牌状态")


# ============================================================
# 10. 审判：只发动一次、队友弃牌文案、超时自动弃一张
# ============================================================
func _检审判() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 1)
	_发牌(引擎.p(3), GConst.CardElement.Fire, 1)
	_放末日([101])
	角色._本回合造成伤害 = true
	检(角色.p_turn_end({"player": 1}) == BattleRole.WAIT, "【审判】应先问是否发动")
	# 发动询问不再自带「是否发动【审判】：…」：说明交给默认的技能说明（技能名已由询问标题显示）
	检(_最近询问文案(9502).is_empty(), "发动询问应留给默认技能说明：%s" % _最近询问文案(9502))
	_应答([1])
	角色.p_turn_end({"player": 1})
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502,
		"应先问 1 号队友弃牌（等待 %s / 号 %s）" % [str(引擎._await_id), str(引擎._pending_respond_id)])
	# 强制弃牌：询问不能带取消（can_cancel=false），客户端不该出现可点的取消按钮
	var 弃牌询问: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 9502 and int(c.get("card_max", 0)) == 1:
			弃牌询问 = c
	检(not 弃牌询问.is_empty() and not bool(弃牌询问.get("can_cancel", true)),
		"审判的队友弃牌是强制的，询问不应可取消：%s" % str(弃牌询问))
	检(_最近询问文案(9502).find("摸 1 张牌") >= 0,
		"队友弃牌询问应写「弃 1 张牌【展示】，摸 1 张牌」：%s" % _最近询问文案(9502))
	_应答([], [], [玩家1.hand_cards[0]])
	引擎.run()
	检(玩家1.hand_cards.size() == 1, "队友弃牌后应先摸 1 张，再问下一名：%d" % 玩家1.hand_cards.size())
	检(引擎._await_id == 3 and 引擎._pending_respond_id == 9502,
		"再问 3 号队友弃牌（等待 %s / 号 %s）" % [str(引擎._await_id), str(引擎._pending_respond_id)])
	_应答([], [], [引擎.p(3).hand_cards[0]])
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502,
		"两名队友弃完应问交给哪名对手（等待 %s）" % str(引擎._await_id))
	# 不合法的目标（自己/队友）应被服务端驳回并重新问，不能随机换目标或静默给牌
	var 驳回前: int = 发送记录.size()
	_应答([1], [1])
	引擎.run()
	var 有驳回: bool = false
	for i: int in range(驳回前, 发送记录.size()):
		var r: Dictionary = 发送记录[i]
		if int(r["msg"]) == GConst.Msg.ErrorInput:
			有驳回 = true
	检(有驳回, "目标选成自己应被驳回（ErrorInput）")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "驳回后应重新问这一步")
	_应答([1], [2])
	引擎.run()
	检(玩家2.hand_cards.size() == 1, "对手应收到 1 张弃牌：%d" % 玩家2.hand_cards.size())
	检(int(_场卡("末日预言").get("counter", 0)) == 2,
		"其余 1 张弃牌应进【预言】堆：%d" % int(_场卡("末日预言").get("counter", 0)))
	# 结算完再重入回合结束钩子：不应再问一遍（不能循环发动）
	检(角色.p_turn_end({"player": 1}) == BattleRole.SUCCESS, "本回合已发动过，不应再问")
	检(引擎._await_id < 0, "不应重新弹【审判】询问")


func _检审判超时() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 1)
	_发牌(引擎.p(3), GConst.CardElement.Fire, 1)
	_放末日([101])
	角色._本回合造成伤害 = true
	角色.p_turn_end({"player": 1})
	_应答([1])
	角色.p_turn_end({"player": 1})
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应先问 1 号队友弃牌")
	# 超时 / 跳过：自动弃掉一张
	_应答超时()
	引擎.run()
	检(玩家1.hand_cards.size() == 1, "超时自动弃 1 张后应立刻摸 1 张：%d" % 玩家1.hand_cards.size())
	检(引擎._await_id == 3 and 引擎._pending_respond_id == 9502, "应继续问 3 号队友")
	_应答([], [], [引擎.p(3).hand_cards[0]])
	引擎.run()
	_应答([1], [2])
	引擎.run()
	检(玩家2.hand_cards.size() == 1, "超时后流程应照常走完，对手收到 1 张弃牌")


# ============================================================
# 11. 状态区显示资料：图标名 / 悬停被动说明
# ============================================================
func _检状态显示资料() -> void:
	检(GConst.场卡显示.has("末日预言"), "状态区应有【末日预言】的图标配置")
	检(not GConst.skill_desc(9504).is_empty(), "悬停提示应能取到【末日预言】的被动说明")
	# 悬停像魔刃一样显示「【被动】技能名：说明」（限宽换行由客户端的提示内容负责）
	var 提示: String = 角色技能提示.单个技能(9504, 16, 95)
	检(提示.find("【被动】") >= 0, "悬停说明应带【被动】类型：%s" % 提示.substr(0, 20))
	检(提示.find("末日预言") >= 0, "悬停说明应写技能名：%s" % 提示.substr(0, 20))
	检(提示.find("[color=") >= 0, "带字号的说明也要有【被动】标色码：%s" % 提示.substr(0, 40))


# ============================================================
# 12. 审判弃掉【魔刃】要触发噬神者【渗蚀】
# ============================================================
func _检审判弃刃触发渗蚀() -> void:
	_建引擎()
	# 3 号座位挂噬神者，拿到他的【魔刃】唯一实例并塞给 1 号（任何持有者弃置都要触发渗蚀）
	var 噬: BattleRole = (load("res://scripts/battle/roles/role_shishenzhe.gd") as GDScript).new()
	噬.setup(引擎.p(3), 引擎)
	引擎.p(3).role = 噬
	引擎.p(3).role_id = 79
	引擎.确保噬神者刃(3)
	var 刃: int = 引擎.p(3).刃实例(GConst.噬神者_魔刃卡)
	检(刃 > 0, "噬神者应生成【魔刃】唯一实例")
	引擎.deck.discard.erase(刃)
	玩家1.add_hand_cards([刃])
	_发牌(引擎.p(3), GConst.CardElement.Wind, 1)
	角色._本回合造成伤害 = true
	检(角色.p_turn_end({"player": 1}) == BattleRole.WAIT, "【审判】应先问是否发动")
	_应答([1])
	角色.p_turn_end({"player": 1})
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应先问 1 号队友弃牌")
	_应答([], [], [刃])
	引擎.run()
	# 渗蚀：3 号噬神者应对弃牌者（1 号）造成法术伤害
	var 有渗蚀: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Skill:
			continue
		var 数据: Dictionary = r["data"]
		if int(数据.get("skill_id", 0)) == 7911 and (数据.get("dst_ids", []) as Array).has(1):
			有渗蚀 = true
	检(有渗蚀, "弃置【魔刃】应触发【渗蚀】并对弃牌者造成伤害")
	检(引擎._await_id == 3 and 引擎._pending_respond_id == 9502,
		"渗蚀结算完应继续问 3 号队友（等待 %s）" % str(引擎._await_id))
	var 三号弃牌: int = int(引擎.p(3).hand_cards[0])
	_应答([], [], [三号弃牌])
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应问选哪张弃牌交给对手")
	# 被移除的刃不应再作为「选 1 张弃牌交给对手」的选项：只剩 3 号队友那张
	var 选项数: int = 0
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 9502 and c.has("option_card_ids"):
			选项数 = (c.get("option_card_ids", []) as Array).size()
	检(选项数 == 1, "被移除的【魔刃】不应作为审判的弃牌选项，实际选项数 %d" % 选项数)
	_应答([1], [2])
	引擎.run()
	检(玩家2.有手牌(三号弃牌), "对手应收到玩家交出的那张弃牌")
	检(引擎.移除牌堆.has(刃), "渗蚀后的【魔刃】应收纳在移除牌堆里")
	检(not 引擎.deck.discard.has(刃) and not 玩家1.有手牌(刃),
		"被移除的【魔刃】不应进弃牌堆 / 手牌")
	检(引擎._await_id < 0, "审判结算完不应还停在等待")


# ============================================================
# 13. 审判残留状态：新回合清掉后必须还能正常发动（修「偶尔触发不了」）
# ============================================================
func _检审判残留状态() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 1)
	角色._审判步 = 3
	角色._审判弃牌 = [int(玩家1.hand_cards[0])]
	角色.p_before_turn_begin({"player": 1})
	检(int(角色.get("_审判步")) == 0 and (角色.get("_审判弃牌") as Array).is_empty(),
		"新回合开始应清掉残留的审判流程状态")
	角色._本回合造成伤害 = true
	检(角色.p_turn_end({"player": 1}) == BattleRole.WAIT, "清掉残留后【审判】应能正常发动")


# ============================================================
# 14. 选项目标：客户端显示的第 N 项必须对应服务器列表的第 N 项
# ============================================================
func _检审判选项值对应() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 2)
	var 甲: int = int(玩家1.hand_cards[0])
	var 乙: int = int(玩家1.hand_cards[1])
	玩家1.取出实例(玩家1.hand_cards, 甲)
	玩家1.取出实例(玩家1.hand_cards, 乙)
	引擎.deck.push_discard([甲, 乙])
	角色._审判步 = 3
	角色._审判弃牌 = [甲, 乙]
	引擎.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": 1}, []))
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应先问选 1 张弃牌交给对手")
	# 越界的选项值（客户端旧列表 / 乱传）：驳回重问，不能交牌
	_应答([3], [2])
	引擎.run()
	检(not 玩家2.有手牌(甲) and not 玩家2.有手牌(乙), "越界选项值不应交出任何牌")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "越界选项值应被驳回并重问")
	# 客户端显示的第 2 项 → args[0] = 服务器该项的 value(2) → 交给对手的应是列表第 2 张（乙）
	_应答([2], [2])
	引擎.run()
	检(玩家2.有手牌(乙) and not 玩家2.有手牌(甲),
		"选项值 2 应对应服务器选项列表的第 2 项，实际手牌=%s" % str(玩家2.hand_cards))


# ============================================================
# 15. 审判：队友摸 1 张后必须先结算手牌超限，再问下一名队友
# ============================================================
func _检审判摸牌先结算超限() -> void:
	_建引擎()
	for i: int in range(GConst.HAND_CARDS_MAX):
		_发牌(玩家1, GConst.CardElement.Wind, 1)
	角色._审判步 = 2
	角色._审判下标 = 1
	角色._审判待摸 = 1
	引擎.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": 1}, []))
	引擎.run()
	检(引擎._await_id == 1, "摸牌超过上限时应先问超出上限的人弃牌（等待 %s）" % str(引擎._await_id))
	检(引擎._pending_respond_id != 9502, "不应跳过超限结算、直接问下一名队友弃牌")


# ============================================================
# 16. 审判：选牌给对手时，选中敌方头像要写「给予【卡名】」
# ============================================================
func _检审判头像提示() -> void:
	var 甲: GCard = Data.get_card(3)
	var 乙: GCard = Data.get_card(4)
	检(甲 != null and 乙 != null, "测试用卡面 3 / 4 应存在")
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	窗._mode = 3
	窗._skill_ask_id = GConst.技能_审判
	窗._二级选项 = [{"参数": [1], "卡牌": 3}, {"参数": [2], "卡牌": 4}]
	窗._已选参数 = [2]
	窗._sel_players.append(2)
	var 提示: Dictionary = 窗.call("_审判头像提示")
	检(str(提示.get(2, "")) == "给予【%s】" % (乙.card_name if 乙 != null else "?"),
		"审判选中第 2 项时目标头像应写「给予【第 2 张牌名】」：%s" % str(提示))
	窗._已选参数 = [1]
	提示 = 窗.call("_审判头像提示")
	检(str(提示.get(2, "")) == "给予【%s】" % (甲.card_name if 甲 != null else "?"),
		"改选第 1 项后头像提示应跟着换成第 1 张牌名：%s" % str(提示))
	窗._已选参数 = []
	检(窗.call("_审判头像提示").is_empty(), "没选牌时不应写提示")
	窗._sel_players.clear()
	窗._已选参数 = [1]
	检(窗.call("_审判头像提示").is_empty(), "没选目标时不应写提示")
	窗.queue_free()

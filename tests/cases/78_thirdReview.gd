extends 自检用例
## 第三次审查（2026-11-11）修复项的交互回归。
##
## 这些技能以前「第一段答了不发动，后面几段照样执行」（框架的「答完」返回 SUCCESS 只表示继续
## 下一段，不能中止整条链），或者「一条链的截止时刻被下一个人继承」。这里用真实钩子 + 喂回复
## 走一遍，确认修复后的交互：不发动就真的停、换人问就重新计时。
##
## 覆盖：异象剑 4502 / 收魔术 4202 / 噬神者共振 7907（付完代价必须弹四选一）/ 框架换人计时。
## 其余受影响技能由既有用例覆盖：圣剑、水影（26 号）、英灵召唤（44 号）、
## 异象剑与展示（32 / 49 号）、魔法入门（矜贵之女用例）。

var 引擎: BattleEngine = null
var 发送记录: Array = []


func 跑() -> void:
	名称 = "第三次审查修复：不发动不再继续 / 换人问重新计时"
	_检异象剑不发动()
	_检收魔术不发动()
	_检英灵召唤不发动()
	_检圣剑不发动()
	_检共振付完代价要弹四选一()
	_检换人问重新计时()


## 角色号 → 角色脚本（按角色表「脚本」列反查，不写死号）
func _角色号(文件名: String) -> int:
	for r: int in range(1, 120):
		if str(Data.role_script(r)).ends_with(文件名):
			return r
	return -1


func _元素号(系: String) -> int:
	match 系:
		"火": return GConst.CardElement.Fire
		"水": return GConst.CardElement.Water
		"风": return GConst.CardElement.Wind
		"雷": return GConst.CardElement.Thunder
		"地": return GConst.CardElement.Earth
		"圣": return GConst.CardElement.Light
		"暗": return GConst.CardElement.Darkness
	return 0


func _找牌(系: String, 类型: String = "") -> int:
	var 元素: int = _元素号(系)
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element_enum() != 元素:
			continue
		if 类型 == "attack" and c.is_attack():
			return c.id
		if 类型 == "magic" and c.is_magic():
			return c.id
		if 类型 == "":
			return c.id
	return 0


## 同系的 N 张不同牌面
func _同系牌(系: String, 数量: int) -> Array:
	var out: Array = []
	var 元素: int = _元素号(系)
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element_enum() != 元素:
			continue
		if out.has(c.id):
			continue
		out.append(c.id)
		if out.size() >= 数量:
			break
	return out


## 重建一个 4 人引擎并给 1 号挂上指定角色
func _建引擎(角色号: int) -> BattleRole:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles({})
	var 玩家: BattlePlayer = 引擎.p(1)
	var 脚本: GDScript = load(str(Data.role_script(角色号))) as GDScript
	var 角色: BattleRole = 脚本.new()
	玩家.role_id = 角色号
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	if 角色号 == 79:
		引擎.确保噬神者刃(1)
	引擎.phase = BattleEngine.Phase.Playing
	引擎.round_id = 1
	return 角色


## 直接给角色钩子喂一条回复（不经过引擎的 run 循环）
func _应答(args: Array, cards: Array = [], dsts: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": dsts}
	引擎._has_reply = true
	引擎._await_state = 引擎._当前状态


## 最后一次下发给某人的询问命令
func _最后命令(pid: int) -> Dictionary:
	var 问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(pid, {})
	var 表: Array = 问.get("commands", [])
	if 表.is_empty():
		return {}
	return 表[0]


## 异象剑 4502：第一段答「不发动」后，不许再逼目标弃牌、不许加伤、不许送牌
func _检异象剑不发动() -> void:
	var 号: int = _角色号("role_jianzhimoni.gd")
	检(号 > 0, "找不到剑之魔女角色行")
	if 号 <= 0:
		return
	var 角色: BattleRole = _建引擎(号)
	var 目标: BattlePlayer = 引擎.p(2)
	目标.hand_cards.clear()
	目标.add_hand_cards([_找牌("火", "attack")])
	var 上下文: Dictionary = {"src": 1, "dst": 2, "is_active": true}
	检(int(角色.p_timeline_2_hit(上下文)) == BattleRole.WAIT, "【异象剑】应先问是否发动")
	_应答([0])
	var 结果: int = int(角色.p_timeline_2_hit(上下文))
	检(结果 != BattleRole.WAIT, "第一段答「不发动」后不应继续问目标弃牌，实际 %d" % 结果)
	检(int(引擎._await_id) == -1, "答「不发动」后不应再等目标回复")
	检(目标.hand_cards.size() == 1, "答「不发动」后目标不应被迫弃牌，实际手牌 %d 张" % 目标.hand_cards.size())
	检(not 角色.多步询问进行中(4502), "答「不发动」后链应收干净")


## 收魔术 4202：第一段答「不发动」后，不要再问目标弃牌
func _检收魔术不发动() -> void:
	var 号: int = _角色号("role_liewuren.gd")
	检(号 > 0, "找不到猎巫人角色行")
	if 号 <= 0:
		return
	var 角色: BattleRole = _建引擎(号)
	var 目标: BattlePlayer = 引擎.p(2)
	目标.hand_cards.clear()
	目标.add_hand_cards([_找牌("火", "attack"), _找牌("水", "attack")])
	# 入口要求：目标手牌 < 4 张、且瓶子还立着
	var 入口: int = int(角色.p_timeline_1({"src": 1, "dst": 2, "is_active": true}))
	检(入口 == BattleRole.WAIT, "【收魔术】应先问是否发动，实际 %d" % 入口)
	if 入口 != BattleRole.WAIT:
		return
	_应答([0])
	var 结果: int = int(角色.p_timeline_1({"src": 1, "dst": 2, "is_active": true}))
	检(结果 != BattleRole.WAIT, "第一段答「不发动」后不应再问目标弃牌，实际 %d" % 结果)
	检(目标.hand_cards.size() == 2, "答「不发动」后目标不应被点名弃牌，实际手牌 %d 张" % 目标.hand_cards.size())


## 英灵召唤 2505：第一段答「不发动」后，不许白弃法术牌 +1 治疗
func _检英灵召唤不发动() -> void:
	var 号: int = _角色号("role_nvwushen.gd")
	检(号 > 0, "找不到女武神角色行")
	if 号 <= 0:
		return
	var 角色: BattleRole = _建引擎(号)
	var 玩家: BattlePlayer = 引擎.p(1)
	var 法术: int = _找牌("火", "magic")
	检(法术 > 0, "找不到法术牌")
	玩家.hand_cards.clear()
	玩家.add_hand_cards([法术])
	玩家.set_crystal(1)
	var 能量前: int = 玩家.get_energy()
	var 上下文: Dictionary = {
		"harm": {"src": 1, "dst": 2, "point": 1, "type": GConst.HarmType.Attack},
		"is_active": true,
	}
	var 第一问: int = int(角色.p_timeline_2_hit(上下文))
	检(第一问 == BattleRole.WAIT, "【英灵召唤】应先问是否发动，实际 %d" % 第一问)
	if 第一问 != BattleRole.WAIT:
		return
	_应答([0])
	var 结果: int = int(角色.p_timeline_2_hit(上下文))
	检(结果 != BattleRole.WAIT, "答「不发动」后不应继续问第 2 段，实际 %d" % 结果)
	检(玩家.get_energy() == 能量前, "答「不发动」后不应扣能量：%d → %d" % [能量前, 玩家.get_energy()])
	检(玩家.hand_cards.size() == 1, "答「不发动」后不应弃掉法术牌，实际手牌 %d 张" % 玩家.hand_cards.size())


## 圣剑 104：第一段回的不是 1~3 时，不要带着「弃 0 张」继续问第二段
func _检圣剑不发动() -> void:
	var 号: int = _角色号("role_jiansheng.gd")
	检(号 > 0, "找不到记录者角色行")
	if 号 <= 0:
		return
	var 角色: BattleRole = _建引擎(号)
	var 第一问: int = int(角色.call("_sheng_jian_cycle"))
	检(第一问 == BattleRole.WAIT, "【圣剑】应先问摸几张，实际 %d" % 第一问)
	if 第一问 != BattleRole.WAIT:
		return
	_应答([0])
	var 结果: int = int(角色.call("_sheng_jian_cycle"))
	检(结果 != BattleRole.WAIT, "第一段回 [0] 后不应再问「弃 X 张」，实际 %d" % 结果)
	检(int(引擎._await_id) == -1, "第一段回 [0] 后不应还在等回复")
	检(not 角色.多步询问进行中(104), "第一段回 [0] 后链应收干净")


## 噬神者共振 7907：付完 1 能量 + 2 张同系牌后，必须弹出四选一
func _检共振付完代价要弹四选一() -> void:
	var 号: int = _角色号("role_shishenzhe.gd")
	检(号 > 0, "找不到噬神者角色行")
	if 号 <= 0:
		return
	var 角色: BattleRole = _建引擎(号)
	var 玩家: BattlePlayer = 引擎.p(1)
	玩家.hand_cards.clear()
	var 牌: Array = _同系牌("火", 2)
	检(牌.size() == 2, "找不到两张同系牌")
	if 牌.size() != 2:
		return
	玩家.add_hand_cards([int(牌[0]), int(牌[1])])
	玩家.set_crystal(2)
	var 能量前: int = 玩家.get_energy()
	角色.set("_共振待问", true)
	var 第一问: int = int(角色.call("p_shi_shen_ask", {"player": 1}))
	检(第一问 == BattleRole.WAIT, "【共振】应先问弃 2~3 张同系牌，实际 %d" % 第一问)
	if 第一问 != BattleRole.WAIT:
		return
	var 问: Dictionary = _最后命令(1)
	检(int(问.get("card_max", 0)) >= 2, "共振弃牌询问应允许最多 3 张（card_max），实际 %s" % str(问.get("card_max", 0)))
	_应答([], [int(牌[0]), int(牌[1])])
	var 付完: int = int(角色.call("p_shi_shen_ask", {"player": 1}))
	检(付完 == BattleRole.URGENT, "付完代价应挂起等刃的移除结算，实际 %d" % 付完)
	检(玩家.get_energy() == 能量前 - 1, "共振应付 1 能量：%d → %d" % [能量前, 玩家.get_energy()])
	var 四选一: int = int(角色.call("p_shi_shen_ask", {"player": 1}))
	检(四选一 == BattleRole.WAIT, "付完代价后必须弹出四选一，实际 %d（链被 _共振弃牌成立 被清掉时是 0）" % 四选一)
	if 四选一 == BattleRole.WAIT:
		var 选项问: Dictionary = _最后命令(1)
		检((选项问.get("notes", []) as Array).size() == 4,
			"四选一应下发 4 项，实际 %s" % str(选项问.get("notes", [])))


## 框架：换人问（循环段 / 问目标弃牌）要重新计时，不能继承前一个人的截止时刻
func _检换人问重新计时() -> void:
	var 号: int = _角色号("role_jianzhimoni.gd")
	if 号 <= 0:
		return
	var 角色: BattleRole = _建引擎(号)
	var 结算: Callable = func(_答案: Array) -> int: return BattleRole.SUCCESS
	# 第 1 段问自己、第 2 段问 2 号
	var 第一问: int = int(角色.多步询问(99001, [
		{"需目标": 1, "目标白": [1]},
		{"问谁": 2, "需目标": 1, "目标白": [2], "可取消": false},
	], 结算))
	检(第一问 == BattleRole.WAIT, "第 1 段应先问自己")
	if 第一问 != BattleRole.WAIT:
		return
	# 把「整链截止时刻」改到只剩 1 秒，模拟「第一个人在最后时刻才答」
	引擎.链截止_ms = Time.get_ticks_msec() + 1000
	_应答([], [], [1])
	var 第二问: int = int(角色.多步询问(99001, [
		{"需目标": 1, "目标白": [1]},
		{"问谁": 2, "需目标": 1, "目标白": [2], "可取消": false},
	], 结算))
	检(第二问 == BattleRole.WAIT, "第 2 段应改问 2 号")
	检(int(引擎._await_id) == 2, "第 2 段应等 2 号（实际等 %d）" % int(引擎._await_id))
	var 剩余: int = int(引擎.wait_deadline_ms) - Time.get_ticks_msec()
	检(剩余 > 30000,
		"换人问应重新计时（不能继承前一个人的截止时刻）：剩余只有 %d ms" % 剩余)

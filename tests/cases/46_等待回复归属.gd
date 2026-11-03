extends 自检用例
## 引擎「回复归属」收敛用例。
##
## 场景：某状态先问 1 号玩家，回复回来时，压在栈上的内层状态先问了 2 号玩家。
## 以前等待槽只有一个，内层一 wait_for 就把外层那份「已收到、还没取走」的回复冲掉
## （女武神【英灵召唤】被兽灵【兽魂警戒】插队、以及「付完能量后被入口守卫提前 return」
## 这两类静默失败都归这里）。现在按归属状态暂存、回到栈顶再恢复。


## 内层：在外层等回复期间先问 2 号
class S内层:
	extends RefCounted

	var 阶段: int = 0
	var 收到: Array = []

	func handle(e: BattleEngine) -> int:
		if 阶段 == 0:
			阶段 = 1
			e.ask_skill(2, 9002, 0, 0)
			e.wait_for(2, GConst.Msg.Respond)
			return BattleEngine.WAIT
		if not e.has_reply():
			return BattleEngine.WAIT
		收到.append(e.take_reply())
		return BattleEngine.CONTINUE


## 外层：先压一个会问别人的内层状态，再问 1 号；回复被插队也不能丢
class S外层:
	extends RefCounted

	var 阶段: int = 0
	var 收到: Array = []

	func handle(e: BattleEngine) -> int:
		if 阶段 == 0:
			阶段 = 1
			# 模拟「问玩家之前先压入一轮钩子」（如 player.tap 的 p_tap 轮次）
			e.push(S内层.new())
			e.ask_skill(1, 9001, 0, 0)
			e.wait_for(1, GConst.Msg.Respond)
			return BattleEngine.WAIT
		if not e.has_reply():
			return BattleEngine.WAIT
		收到.append(e.take_reply())
		return BattleEngine.CONTINUE


var 引擎: BattleEngine = null
var 外层: S外层 = null
var 内层: S内层 = null


func _init() -> void:
	名称 = "引擎回复归属：插队询问不能顶掉上一位的回复"


func 跑() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.start_with_roles({})
	for pid: int in 引擎.order:
		引擎.p(pid).role = null
	引擎.phase = BattleEngine.Phase.Playing
	外层 = S外层.new()
	内层 = null
	引擎.push(外层)
	引擎.run()
	检(引擎._await_id == 1, "外层应先问 1 号：%s" % str(引擎._await_id))
	内层 = _找内层()
	检(内层 != null, "外层没有先压入内层状态")
	if 内层 == null:
		return
	# 1 号答复外层 —— 此时栈顶是内层，它会先问 2 号
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": 9001, "args": [7],
		"card_ids": [], "dst_ids": []})
	检(引擎._await_id == 2, "内层应接着问 2 号：%s" % str(引擎._await_id))
	检(引擎._挂起回复.has(外层), "外层的回复没有被暂存（会被内层的等待冲掉）")
	# 2 号答复内层：内层结算完后，外层应能取回自己那份回复
	引擎.on_message(2, GConst.Msg.Respond, {"respond_id": 9002, "args": [8],
		"card_ids": [], "dst_ids": []})
	检(内层.收到.size() == 1 and int(内层.收到[0].get("args", [0])[0]) == 8,
		"内层没拿到自己的回复：%s" % str(内层.收到))
	检(外层.收到.size() == 1 and int(外层.收到[0].get("args", [0])[0]) == 7,
		"外层没取回被暂存的回复（拿到的是 %s）" % str(外层.收到))
	检(引擎._挂起回复.is_empty(), "暂存区应已清空：%s" % str(引擎._挂起回复))


func _找内层() -> S内层:
	for st: Variant in 引擎._states:
		if st is S内层:
			return st
	return null

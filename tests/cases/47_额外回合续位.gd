extends 自检用例
## 额外回合的「续位」：在别人的回合结束时安排 → 额外回合打完要回到那个人的下家，
## 而不是从额外回合主人的下家继续（10803 剑守誓言会在任意一方的回合结束时触发）。

var 引擎: BattleEngine = null


func _init() -> void:
	名称 = "额外回合续位"


func 跑() -> void:
	_建局()
	var 当前: int = 引擎.order[2]
	var 主人: int = 引擎.order[0]
	var 预期续位: int = 引擎.next_id(当前)
	引擎.current_id = 当前
	引擎.round_id = 1
	检(引擎.安排额外回合(主人, 1, 10803) == GConst.GE_SUCCESS, "安排额外回合应成功")
	检(引擎.额外回合续位 == 预期续位,
		"续位应是「刚结束回合的人的下家」：期望 %d，实际 %d" % [预期续位, 引擎.额外回合续位])
	# 第 3 号（order[2]）的回合结束 → 开始主人的额外回合
	引擎.push(BattleEngine.SNextPlayer.new())
	引擎.run()
	检(引擎.current_id == 主人, "应先进入额外回合主人的回合：%s" % str(引擎.current_id))
	检(引擎.是否额外回合(), "应处于额外回合中")
	检(引擎.额外回合加伤(主人) == 1, "额外回合里攻击加伤应为 1")
	# 快照里要带上「额外回合的加伤来源 / 数值」：客户端据此画「剑守誓言」状态图标
	var 快照: Dictionary = 引擎.p(主人).to_proto(1)
	检(int(快照.get("extra_turn_cause", 0)) == 10803,
		"快照应带额外回合来源 10803，实际 %s" % str(快照.get("extra_turn_cause", 0)))
	检(int(快照.get("extra_turn_bonus", 0)) == 1, "快照应带额外回合加伤 1")
	# 额外回合结束 → 应回到「原来该轮到的人」，而不是主人的下家
	引擎._states.clear()
	引擎.push(BattleEngine.SNextPlayer.new())
	引擎.run()
	检(引擎.current_id == 预期续位,
		"额外回合结束后应回到 %d（原顺序的下家），实际 %d" % [预期续位, 引擎.current_id])
	检(not 引擎.是否额外回合(), "额外回合结束后不应还挂着额外回合状态")
	var 快照2: Dictionary = 引擎.p(主人).to_proto(1)
	检(int(快照2.get("extra_turn_bonus", 0)) == 0, "额外回合结束后快照里的加伤应清零（状态图标随之移除）")


## 4 人局：清掉开局的回合流程，只留干净的状态栈
func _建局() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles({})
	for pid: int in 引擎.order:
		引擎.p(pid).role = null
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing

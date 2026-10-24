extends 自检用例
## 魔弹传递目标：每轮已经参与过的人不能再被传；一轮结束后开新一轮，
## 但新一轮第一个目标不能是刚把魔弹传给自己的人。

func _init() -> void:
	名称 = "魔弹传递分轮且不回头"


func 跑() -> void:
	await 等帧(1)

	# 4 人交替座次：1 蓝、2 红、3 蓝、4 红
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "蓝一")
	引擎.add_player(2, GConst.RED, "红二")
	引擎.add_player(3, GConst.BLUE, "蓝三")
	引擎.add_player(4, GConst.RED, "红四")

	# 红二把魔弹传给蓝三后，蓝三沿 post 找：红四还没参与 → 红四
	检(引擎._next_missile_target(3, true, [2, 3]) == 4,
		"蓝三接弹后，下一个未参与对手应是红四")
	# 红四传过之后，继续到蓝一 → 蓝一
	检(引擎._next_missile_target(4, true, [2, 3, 4]) == 1,
		"红四传过之后，下一个未参与对手应是蓝一")
	# 四个人都参与过：本轮目标选择返回 -1；但可以开新一轮，且不能立刻传回给刚传给我的人（红四）
	检(引擎._next_missile_target(1, true, [2, 3, 4, 1], 4) == -1,
		"本轮内所有玩家都参与过后，不应再回头选择已参与目标")
	检(引擎._missile_relay_targets(1, true, [2, 3, 4, 1], 4) == [2],
		"一轮结束后应开新一轮，沿方向传给红二，且不能传回刚传给我的红四")
	检(引擎._next_missile_target(1, true, [1], 4) == 2,
		"新一轮里刚传给我的人应当被跳过，下一位应轮到红二")

	# 3 人局：红二 → 蓝三后，蓝三只剩刚传给我的红二；新一轮也不能立刻传回去
	var 三人: BattleEngine = BattleEngine.new()
	三人.add_player(1, GConst.BLUE, "蓝一")
	三人.add_player(2, GConst.RED, "红二")
	三人.add_player(3, GConst.BLUE, "蓝三")
	检(三人._next_missile_target(3, true, [2, 3], 2) == -1,
		"只剩刚传给我的玩家时，不应把他作为新一轮目标")
	检(三人._missile_relay_targets(3, true, [2, 3], 2).is_empty(),
		"只剩刚传给我的玩家时，新一轮也不应给出传递候选")

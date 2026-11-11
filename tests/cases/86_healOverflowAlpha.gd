extends 自检用例
## 用例 86：超过治疗上限的【治疗】格要半透明（发虚）
##
## 用户口径：超出上限的那部分【治疗】在头像下方画成 50% 透明度，和正常治疗区分开。
## 覆盖：cross_max=3、当前 5 点时，前 3 格不透明、第 4/5 格 alpha=0.5；
## 没溢出时所有实心格都不透明。

const 面板场景: PackedScene = preload("res://scenes/prefabs/battlemobile/PlayerOtherPanel.tscn")

func _init() -> void:
	名称 = "溢出治疗半透明"


func 跑() -> void:
	await 等帧(1)
	var 旧列表: Array[GPlayer] = []
	旧列表.append_array(Data.player_list)
	Data.player_list.clear()
	var 玩家: GPlayer = GPlayer.new(7, GConst.BLUE, "溢血")
	玩家.cross_max = 3
	玩家.cross_num = 5
	Data.player_list.append(玩家)

	var 面板: Control = 面板场景.instantiate()
	get_tree().root.add_child(面板)
	await 等帧(1)
	面板.set("ID", 7)
	面板.call("set_HealCount", 5)
	await 等帧(1)
	var 格们: Array = (面板.get("healArea") as Node).get_children()
	检(格们.size() == 5, "5 点治疗应画 5 格（实际 %d）" % 格们.size())
	for i: int in range(格们.size()):
		var 色: Color = (格们[i] as CanvasItem).modulate
		if i < 3:
			检(色 == Color.WHITE, "第 %d 格在上限内，应正常颜色（实际 %s）" % [i + 1, str(色)])
		else:
			检(色 == GConst.置灰色, "第 %d 格超过上限，应置灰（实际 %s）" % [i + 1, str(色)])
			检(is_equal_approx(色.a, 1.0), "第 %d 格超过上限也不该半透明（实际 alpha=%s）" % [i + 1, str(色.a)])

	# 没溢出：全部不透明
	面板.call("set_HealCount", 2)
	await 等帧(1)
	var 格们2: Array = (面板.get("healArea") as Node).get_children()
	检(格们2.size() == 3, "2 点治疗 + 上限 3 应画 3 格（实心 2 + 空 1，实际 %d）" % 格们2.size())
	for i: int in range(mini(2, 格们2.size())):
		检((格们2[i] as CanvasItem).modulate == Color.WHITE,
			"没溢出时第 %d 格不该发灰" % [i + 1])

	面板.queue_free()
	await 等帧(1)
	Data.player_list.clear()
	Data.player_list.append_array(旧列表)

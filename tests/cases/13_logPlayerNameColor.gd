extends 自检用例
## 用例 13：日志玩家名里有技能名时（如「祈祷师」含技能「祈祷」）也要整段染成玩家色，
## 不能被 _专名着色 从中间再染成技能色。

func _init() -> void:
	名称 = "日志玩家名整体染色"


func 跑() -> void:
	await 等帧(2)
	var 原列表: Array[GPlayer] = []
	原列表.append_array(Data.player_list)
	Data.player_list.clear()
	var 假玩家: GPlayer = GPlayer.new(999, GConst.BLUE, "测试")
	假玩家.role_name = "祈祷师"
	Data.player_list.append(假玩家)

	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	var 简: String = 窗.call("_日志着色", "圣弓 对 测试[祈祷师] 打出：地裂斩·圣", true)
	var 详: String = 窗.call("_日志着色", "圣弓 对 测试[祈祷师] 打出：地裂斩·圣", false)
	检(简.contains("[color=#FFD98A]祈祷师[/color]"),
		"简洁模式应把「祈祷师」整段染成玩家色：%s" % 简)
	检(详.contains("[color=#FFD98A]测试[祈祷师][/color]"),
		"详情模式应把「测试[祈祷师]」整段染成玩家色：%s" % 详)

	窗.free()
	Data.player_list.clear()
	Data.player_list.append_array(原列表)

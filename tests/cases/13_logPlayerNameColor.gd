extends 自检用例
## 用例 13：日志里的职业名（[祈祷师]）里含着技能名（祈祷）时，也要整段染成玩家色，
## 不能被 _专名着色 从中间再染成技能色。日志已不再显示玩家昵称，只写 [职业名]。


func _init() -> void:
	名称 = "日志职业名整体染色"


func 跑() -> void:
	await 等帧(2)
	var 原列表: Array[GPlayer] = []
	原列表.append_array(Data.player_list)
	Data.player_list.clear()
	var 假玩家: GPlayer = GPlayer.new(999, GConst.BLUE, "测试")
	假玩家.role_name = "祈祷师"
	Data.player_list.append(假玩家)

	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	# 日志只写 [职业名]（不带玩家昵称），整段染成玩家色
	var 称号: String = str(窗.call("_称号", 999))
	检(称号 == "[祈祷师]", "日志里的称号应只有 [职业名]：%s" % 称号)
	var 文: String = str(窗.call("_日志着色", "圣弓 对 [祈祷师] 打出：地裂斩·圣"))
	检(文.contains("[color=#FFD98A][祈祷师][/color]"),
		"职业名应整段染成玩家色（不能被技能名「祈祷」从中间再染）：%s" % 文)

	窗.free()
	Data.player_list.clear()
	Data.player_list.append_array(原列表)

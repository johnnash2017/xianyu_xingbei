extends 自检用例
## 用例 89：【特殊行动】入口常驻技能栏，不能用时只置灰、不消失
##
## 用户口径：被【挑衅】、发动过「启动」技能后、以及额外行动阶段，特殊行动都不能做，
## 但技能栏里那颗「特殊行动」按钮要留在原位并置灰 —— 不能整颗消失。
##
## 覆盖三种状态：
##   1) 只放行攻击（被挑衅 / 额外攻击）→ 按钮在、置灰；
##   2) 正常行动阶段（放行 Any、有星石）→ 按钮在、可点；
##   3) 启动过技能（no_special）→ 按钮在、置灰。

func _init() -> void:
	名称 = "特殊行动常驻置灰"


func 跑() -> void:
	await 等帧(1)
	var 旧我: int = Logic.my_player_id
	var 旧列表: Array[GPlayer] = []
	旧列表.append_array(Data.player_list)
	Logic.my_player_id = 1
	Data.player_list.clear()
	var 我: GPlayer = GPlayer.new(1, GConst.BLUE, "冒险家")
	我.role_id = 12
	Data.player_list.append(我)
	Data.blue.set_gem(2)
	Data.blue.set_crystal(0)

	Logic.game_info_updated.emit({"is_started": true, "room_id": 89,
		"blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 0, "red_gem": 0, "red_crystal": 0})
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)

	# 1) 只放行攻击：按钮在、置灰
	_发行动(窗, GConst.ActionType.Attack, false)
	await 等帧(2)
	var 钮: 技能按钮 = _特殊行动按钮(窗)
	检(钮 != null, "只放行攻击时「特殊行动」按钮不该消失")
	if 钮 != null:
		检(钮.plateButton.disabled, "只放行攻击时「特殊行动」按钮应置灰")

	# 2) 正常行动阶段：按钮在、可点
	_发行动(窗, GConst.ActionType.Any, false)
	await 等帧(2)
	钮 = _特殊行动按钮(窗)
	检(钮 != null, "正常行动阶段应有「特殊行动」按钮")
	if 钮 != null:
		检(not 钮.plateButton.disabled, "有星石时「特殊行动」按钮应可点")

	# 3) 启动过技能（no_special）：按钮在、置灰
	_发行动(窗, GConst.ActionType.Any, true)
	await 等帧(2)
	钮 = _特殊行动按钮(窗)
	检(钮 != null, "启动过技能后「特殊行动」按钮不该消失")
	if 钮 != null:
		检(钮.plateButton.disabled, "启动过技能后「特殊行动」按钮应置灰")

	# 4) 额外行动阶段（is_extra 且只放行攻击）：按钮在、置灰
	_发行动(窗, GConst.ActionType.Attack, false, true)
	await 等帧(2)
	钮 = _特殊行动按钮(窗)
	检(钮 != null, "额外行动阶段「特殊行动」按钮不该消失")
	if 钮 != null:
		检(钮.plateButton.disabled, "额外行动阶段「特殊行动」按钮应置灰")

	窗.queue_free()
	await 等帧(1)
	Data.player_list.clear()
	Data.player_list.append_array(旧列表)
	Logic.my_player_id = 旧我


func _发行动(窗: Control, 允许: int, 禁特殊: bool, 额外: bool = false) -> void:
	var 命令: Dictionary = {"respond_id": 允许, "src_id": 1, "args": [], "card_ids": [], "dst_ids": []}
	if 禁特殊:
		命令["no_special"] = true
	if 额外:
		命令["is_extra"] = true
		命令["extra_cause"] = 0
	窗.call("_on_command", {"cmd_type": GConst.CmdType.Action, "commands": [命令]})


func _特殊行动按钮(窗: Control) -> 技能按钮:
	for 子: Node in (窗.get("_技能按钮") as Array):
		if 子 is 技能按钮:
			var 钮: 技能按钮 = 子
			if 钮.visible and 钮.skillName != null and str(钮.skillName.text) == "特殊行动":
				return 钮
	return null

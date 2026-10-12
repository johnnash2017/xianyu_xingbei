extends 自检用例
## 用例 6：治疗抵挡伤害（RespondType.Heal）的选项应**默认选中「挡最多」的那一项** ——
## 玩家直接用治疗抵挡时，不必先点一次「挡 N 点」，进来就是挡满（可抵的最大值），直接「确定」即可。

func _init() -> void:
	名称 = "治疗抵挡默认选项"

func 跑() -> void:
	await 等帧(2)
	UI.goto_lobby()
	await 等帧(2)
	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手A"),
	]
	Data.player_list = 玩家

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	Logic.game_info_updated.emit({"is_started": true, "room_id": 7, "blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 1, "red_gem": 1, "red_crystal": 2})
	await 等帧(2)

	# 治疗抵挡询问：args = [目标, 伤害点数=4, 伤害类型=攻击, 可抵御上限=3] → 本可抵 3 点
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{"respond_id": GConst.RespondType.Heal, "src_id": 1,
			"args": [1, 4, GConst.HarmType.Attack, 3], "dst_ids": [], "card_ids": []}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 2, "治疗抵挡没进应答流程：%d" % int(窗.get("_mode")))
	var 二级: Array = 窗.get("_二级选项")
	检(二级.size() == 4, "选项数量不对（应 4 个：不抵挡 + 挡 1~3）：%d" % 二级.size())
	检(int(窗.get("_二级选中")) == 3, "没默认选中「挡最多」那一项：_二级选中=%d" % int(窗.get("_二级选中")))
	检((窗.get("_已选参数") as Array) == [3], "默认选中项的提交值不对：%s" % str(窗.get("_已选参数")))
	检(not (窗.get("BtnOK") as Button).disabled, "默认选好后「确定」却是灰的")

	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	窗.queue_free()
	await 等帧(3)

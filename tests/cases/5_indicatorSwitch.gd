extends 自检用例
## 用例 5：技能指示器「切换用法」后对已选内容的重校验 ——
## 目标（普通选择 / 点头像分配）与手牌都要按新用法的白名单复检：合法的保留、不合法的清掉。
## 复现的缺陷：神官【神圣领域】先选「队友」用法并给队友分配 1 点治疗，再切到「敌人」用法时，
## 队友已不在新用法的目标白名单里，却仍留在分配记录里（头像指示器不消、且旧逻辑可被带去误伤队友）。

func _init() -> void:
	名称 = "指示器切用法复检"

func 跑() -> void:
	await 等帧(2)
	UI.goto_lobby()
	await 等帧(2)

	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	var 旧手牌: Array[GCard] = Data.hand_cards
	var 旧盖牌: Array[GCard] = Data.cover_cards
	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手A"),
		GPlayer.new(3, GConst.RED, "对手B"),
		GPlayer.new(4, GConst.BLUE, "队友"),
	]
	Data.player_list = 玩家
	玩家[0].role_id = 15
	var 牌: Array[GCard] = []
	for c: GCard in Data.card_db:
		牌.append(c)
		if 牌.size() >= 2:
			break
	Data.hand_cards = 牌
	Data.cover_cards = []

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	Logic.game_info_updated.emit({"is_started": true, "room_id": 7, "blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 1, "red_gem": 1, "red_crystal": 2})
	await 等帧(2)

	# 神圣领域（1506）：两种用法各带自己的目标白名单（0＝队友含自己；1＝敌人）
	var 选项: Array = [
		{"text": "队友用法", "args": [0], "need_target": 1, "targets": [1, 4]},
		{"text": "敌人用法", "args": [1], "need_target": 1, "targets": [2, 3]},
	]
	窗.call("_选择技能", 1506, GConst.ActionType.MagicSkill, 2, 1, [1, 4, 2, 3], [], 0, 0, 0,
		GConst.CardSource.Hand, "", 0, 0, 选项, null, 0)
	await 等帧(2)
	检(bool(窗.get("_先弹选项")), "神圣领域没进「先弹选项」流程")
	var 二级: Array = 窗.get("_二级选项")
	检(二级.size() == 2, "二级选项数量不对：%d" % 二级.size())
	if 二级.size() == 2:
		检((二级[0]["目标白名单"] as Array) == [1, 4], "用法0 的目标白名单丢了：%s" % str(二级[0]["目标白名单"]))
		检((二级[1]["目标白名单"] as Array) == [2, 3], "用法1 的目标白名单丢了：%s" % str(二级[1]["目标白名单"]))

	# 选「队友」用法 → 给队友（id 4）分配 1 点治疗
	窗.call("_选中二级选项", 1506, 0)
	await 等帧()
	检(bool(窗.call("_玩家可选", 4)), "选了队友用法后队友仍不可点")
	窗.call("_on_player_clicked", 4)
	await 等帧()
	检((窗.get("_治疗分配") as Array) == [4], "队友没被记进分配：%s" % str(窗.get("_治疗分配")))

	# 切到「敌人」用法：队友已不合法，分配记录与头像指示器都必须清掉
	窗.call("_选中二级选项", 1506, 1)
	await 等帧()
	检((窗.get("_治疗分配") as Array).is_empty(),
		"切换用法后不合法的队友仍留在分配里：%s" % str(窗.get("_治疗分配")))
	检(not (窗.get("_sel_players") as Array).has(4), "切换用法后队友头像仍被标为已选")
	检((窗.get("BtnOK") as Button).disabled, "目标不合法时「确定」却是可用的")

	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	窗.queue_free()
	await 等帧(3)

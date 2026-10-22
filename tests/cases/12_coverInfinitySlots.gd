extends 自检用例
## 用例 12f：盖牌上限是 99 时，点开「查看盖牌」只显示真实盖牌，不再补空槽；
## 普通上限仍按剩余位置补空槽。

func _init() -> void:
	名称 = "盖牌99不显示空槽"


func 跑() -> void:
	await 等帧(2)
	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	var 旧盖牌: Array[GCard] = Data.cover_cards
	var 牌: Array[GCard] = []
	for c: GCard in Data.card_db:
		if not c.is_virtual:
			牌.append(c)
		if 牌.size() >= 2:
			break
	检(牌.size() >= 2, "找不到两张实体牌做盖牌")
	if 牌.size() < 2:
		return

	Logic.my_player_id = 1
	var 我: GPlayer = GPlayer.new(1, GConst.BLUE, "我")
	我.cover_cards_max = 99
	Data.player_list = [我] as Array[GPlayer]
	Data.cover_cards = [牌[0], 牌[1]] as Array[GCard]
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	add_child(窗)
	await 等帧(2)
	窗.set("_查看盖牌", true)
	窗.call("刷新盖牌")
	检((窗.get("_盖牌空槽") as Array).is_empty(), "99 上限查看盖牌时不应创建空槽")

	我.cover_cards_max = 5
	窗.call("刷新盖牌")
	检((窗.get("_盖牌空槽") as Array).size() == 3, "普通上限应补 5-2=3 个空槽")

	# 盖牌被选中时整张牌染黄（学头像选中色），不只是边框
	var 选中牌: Array[int] = [牌[0].id]
	窗.set("_sel_cards", 选中牌)
	窗.call("刷新盖牌")
	var 卡节点: Control = null
	for c: Node in (窗.get("ChooseArea") as Control).get_children():
		if c.get("card") != null and int((c.get("card") as GCard).id) == 牌[0].id:
			卡节点 = c as Control
			break
	检(卡节点 != null, "找不到盖牌卡节点")
	if 卡节点 != null:
		检(卡节点.modulate == Color(1.0, 1.0, 0.55), "选中的盖牌应整张染黄：%s" % str(卡节点.modulate))

	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.cover_cards = 旧盖牌
	窗.queue_free()

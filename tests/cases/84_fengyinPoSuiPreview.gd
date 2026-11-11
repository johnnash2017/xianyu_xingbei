extends 自检用例
## 用例 84：封印师【封印破碎】选「拿走哪张基础效果」时，选项要能摊出对应卡面
##
## 这些选项是**客户端本地拼的**（_基础效果选项，把目标面前的基础效果列成选项），
## 以前只带「参数」，没带卡牌 id → 悬停时 _显示技能说明 找不到「卡牌」，
## 只能看到「拿走 XXX」这一行字，同名 / 同系的多张分不清。
##
## 覆盖：_基础效果选项 产出的每一项都带 card_id，且经 _选项项 归一化后「卡牌」仍是那张牌；
## 同一个机制服务的【风之洁净】/【天使之歌】也就一起有了悬停卡面。

func _init() -> void:
	名称 = "封印破碎选项卡面"


func 跑() -> void:
	await 等帧(1)
	var 旧我: int = Logic.my_player_id
	var 旧列表: Array[GPlayer] = []
	旧列表.append_array(Data.player_list)
	Logic.my_player_id = 1

	# 造一个：「敌方面前有一张基础效果牌」
	var 卡: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual:
			卡 = c
			break
	检(卡 != null, "卡库为空，前提不成立")
	if 卡 == null:
		return
	var 敌: GPlayer = GPlayer.new(3, GConst.RED, "敌")
	敌.basic_status_list.append(GPlayer.BasicStatus.new(0, 卡, 卡.id))
	Data.player_list.clear()
	Data.player_list.append(敌)

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(1)
	窗.set("_mode", 4)
	窗.set("_pending_skill_id", GConst.技能_封印破碎)
	窗.set("_sel_players", [3] as Array[int])

	var 选项: Array = 窗.call("_基础效果选项")
	检(选项.size() == 1, "封印破碎应列出 1 个基础效果选项（实际 %d）" % 选项.size())
	if not 选项.is_empty():
		检(int((选项[0] as Dictionary).get("card_id", -1)) == 卡.id,
			"基础效果选项没有带 card_id（悬停摊不出卡面）：%s" % str(选项[0]))
		var 项: Array = 窗.call("_选项项", 选项)
		检(not 项.is_empty() and int((项[0] as Dictionary).get("卡牌", -1)) == 卡.id,
			"归一化后「卡牌」丢了：%s" % str(项))

	窗.queue_free()
	await 等帧(1)
	Data.player_list.clear()
	Data.player_list.append_array(旧列表)
	Logic.my_player_id = 旧我

extends 自检用例
## 用例 53：独有效果（五系束缚 / 灵魂链接 / 同生共死 / 永恒乐章）的状态提示 ——
## 悬停要按「专属卡包含的技能」逐条列说明（同场卡的显示方式），
## 【五系束缚】还要把应摸张数（2+场上封印数，封顶 4）画在图标上并实时重算。

var 窗: Control = null
var 玩家: Array[GPlayer] = []


func _init() -> void:
	名称 = "独有效果状态提示"


func 等帧(_数: int = 2) -> void:
	var 截止: int = Time.get_ticks_msec() + 120
	while Time.get_ticks_msec() < 截止:
		await get_tree().process_frame


func 跑() -> void:
	await 等帧(2)
	UI.goto_lobby()
	await 等帧(2)
	# 配置齐全 + 技能说明都能取出来
	var 名字们: Array = ["五系束缚", "灵魂链接", "同生共死", "永恒乐章"]
	for 名: String in 名字们:
		var 配置: Dictionary = GConst.独有效果显示.get(名, {})
		检(not 配置.is_empty(), "GConst.独有效果显示 没配 %s" % 名)
		if 配置.is_empty():
			continue
		var 技能们: Array = []
		var 配: Variant = 配置.get("被动技能", null)
		if 配 is Array:
			技能们 = 配
		elif 配 != null:
			技能们 = [int(配)]
		检(not 技能们.is_empty(), "%s 没配被动技能" % 名)
		var 角色号: int = int(配置.get("被动技能角色", -1))
		检(角色号 > 0, "%s 没配被动技能角色" % 名)
		for 技能号: Variant in 技能们:
			var 说明: String = 角色技能提示.单个技能(int(技能号), 0, 角色号)
			检(说明 != "", "%s 的技能 %d 取不到说明" % [名, int(技能号)])

	# 造一份对局视图：玩家 2 身上挂 1 张封印（幻命格攻击牌）
	Logic.my_player_id = 1
	玩家 = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手A"),
		GPlayer.new(3, GConst.RED, "对手B"),
	]
	Data.player_list = 玩家
	Data.hand_cards = [] as Array[GCard]
	Data.cover_cards = [] as Array[GCard]
	var 封印: GCard = null
	for c: GCard in Data.card_db:
		if c != null and c.is_attack() and c.fate_pattern_enum() == GConst.FatePattern.Phantom:
			封印 = c
			break
	检(封印 != null, "卡库找不到「幻命格攻击牌」当封印，用例前提不成立")
	if 封印 == null:
		return
	玩家[1].basic_status_list.append(GPlayer.BasicStatus.new(0, 封印))
	玩家[0].specials[GConst.Exclusive.WuXiShuFu] = true

	窗 = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)

	# 应摸张数：基数 2 + 1 张封印 = 3
	var 面板: 战斗玩家面板 = 窗.get("MainPlayer") as 战斗玩家面板
	检(面板 != null, "找不到主玩家面板")
	if 面板 == null:
		return
	面板.set("BasicAndExCards", [])
	面板.set("ExclusiveCards", [GConst.Exclusive.WuXiShuFu])
	await 等帧(1)
	检(int(面板.call("五系束缚应摸张数")) == 3,
		"1 张封印时应摸 3 张（实际 %d）" % int(面板.call("五系束缚应摸张数")))
	var 图标: Control = _找独有效果图标(面板, "五系束缚")
	检(图标 != null, "面板上没画出【五系束缚】图标")
	if 图标 != null:
		var 数标签: Node = 图标.get_node_or_null("Text")
		检(数标签 is Label and (数标签 as Label).visible and (数标签 as Label).text == "3",
			"应摸张数应写在图标上（实际：%s）" % str((数标签 as Label).text if 数标签 is Label else "无"))
		# 悬停内容按技能说明排版（标题 + 技能行）
		var 内容: Control = 窗.call("_造被动状态内容", 图标, "五系束缚", [407], 4)
		检(内容 != null and 内容.get_child_count() >= 2,
			"【五系束缚】悬停应列出技能说明（实际子节点 %d）" %
			(内容.get_child_count() if 内容 != null else -1))

	# 再加 1 张封印 → 4；再加 1 张 → 仍封顶 4
	玩家[2].basic_status_list.append(GPlayer.BasicStatus.new(0, 封印))
	检(int(面板.call("五系束缚应摸张数")) == 4, "2 张封印时应摸 4 张")
	玩家[0].basic_status_list.append(GPlayer.BasicStatus.new(0, 封印))
	检(int(面板.call("五系束缚应摸张数")) == 4, "3 张封印时应封顶 4 张")
	# 重新渲染后图标上的数字跟着变
	面板.set("ExclusiveCards", [GConst.Exclusive.WuXiShuFu])
	await 等帧(1)
	var 图标2: Control = _找独有效果图标(面板, "五系束缚")
	if 图标2 != null:
		var 数2: Node = 图标2.get_node_or_null("Text")
		检(数2 is Label and (数2 as Label).text == "4",
			"封印增加后图标应重算成 4（实际：%s）" % str((数2 as Label).text if 数2 is Label else "无"))
	窗.free()


## 在面板的状态图标区里找 Name 标签为指定名字的那一枚
func _找独有效果图标(面板: 战斗玩家面板, 名: String) -> Control:
	var 区: Control = 面板.get("basicAndExCardArea") as Control
	if 区 == null:
		return null
	for 子: Node in 区.get_children():
		if not (子 is Control):
			continue
		var 名标签: Node = 子.get_node_or_null("Name")
		if 名标签 is Label and (名标签 as Label).text == 名:
			return 子 as Control
	return null

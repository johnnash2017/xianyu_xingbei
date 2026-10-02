extends 自检用例
## 用例 2：主场景 / 界面切换 / 版面（设计基准 1920×1080）


func _init() -> void:
	名称 = "界面与版面"


func 跑() -> void:
	await 等帧(2)
	var 视口: Vector2 = get_viewport().get_visible_rect().size

	# 主场景：登录界面自动出现；界面层里只有它一个；全局只有一张背景
	检(UI.界面层 != null, "主场景没有把界面层交给 UI")
	检(UI.current != null and UI.current.name == "Enter", "启动后当前界面不是登录界面")
	检(_界面层名单().size() == 1, "界面层下同时存在多个界面：%s" % str(_界面层名单()))
	var 背景数: int = _数背景(get_tree().root)
	检(背景数 == 1, "全局「背景」节点 %d 个（应为 1）" % 背景数)

	# 登录卡片居中
	var 卡: Control = UI.current.get_node("居中/登录卡片")
	var 中心: Vector2 = 卡.get_global_rect().get_center()
	检(absf(中心.x - 视口.x * 0.5) <= 2.0 and absf(中心.y - 视口.y * 0.5) <= 2.0,
		"登录卡片没居中：中心 %s，视口中心 %s" % [str(中心), str(视口 * 0.5)])

	# 切换界面：旧界面要被销毁，界面层里始终只剩当前界面
	UI.goto_lobby()
	await 等帧(2)
	检(UI.current.name == "Lobby", "切大厅后当前界面是 %s" % str(UI.current.name))
	检(_界面层名单().size() == 1, "进大厅后界面层：%s" % str(_界面层名单()))
	var 战: Node = UI.goto_battle_mobile()
	await 等帧(2)
	检(UI.current.name == "BattleUIMobile", "切战斗后当前界面是 %s" % str(UI.current.name))
	检(_界面层名单().size() == 1, "进战斗后界面层：%s" % str(_界面层名单()))

	# 战斗界面根节点必须是带实体尺寸的 Control（它是 1280×720 设计、整体缩放适配，不与视口等大）
	var 战根: Control = 战 as Control
	检(战根 != null and 战根.size.x > 0.0 and 战根.size.y > 0.0,
		"战斗界面根节点异常：%s" % str(战根))

	# 大厅建房弹层：人数沿用共享配置里上次开房记下的值（从没开过房时才是场景默认的 4 人）、房名光标在末尾
	var 厅: Node = UI.goto_lobby()
	await 等帧(2)
	检(not (厅.get("创建层") as Control).visible, "建房弹层默认不该显示")
	厅.call("_on_open_create_pressed")
	await 等帧(2)
	检((厅.get("创建层") as Control).visible, "点了「创建房间」弹层没显示")
	# 键名与 lobby.gd 的 共享键_人数 一致
	var 记下的人数: int = int(Cfg.shared_get("room_max_player", 4))
	检(int((厅.get("人数组") as ButtonGroup).get_pressed_button().get_meta("people")) == 记下的人数,
		"房间人数不是上次开房记下的 %d 人" % 记下的人数)
	var 房名框: LineEdit = 厅.get("房名输入")
	检(房名框.caret_column == 房名框.text.length(),
		"房名光标不在末尾（%d / %d）" % [房名框.caret_column, 房名框.text.length()])
	厅.call("_on_close_create_pressed")


func _界面层名单() -> Array[String]:
	var 名单: Array[String] = []
	for c: Node in UI.界面层.get_children():
		名单.append(str(c.name))
	return 名单


func _数背景(节点: Node) -> int:
	var n: int = 1 if 节点.name == "背景" else 0
	for c: Node in 节点.get_children():
		n += _数背景(c)
	return n

extends Control
## 主场景（project.godot 的 run/main_scene）
## 整个游戏只有这一处画背景；登录/大厅/战斗/选将这些界面都由 UI 管理器（autoload 名 UI）
## 挂到「界面层」上，一层层叠在这张背景之上。

@export var 界面层: Control
## 右上角「问题反馈」：一行文字，点一下用系统默认浏览器打开问卷（见 UI.打开反馈问卷）
@export var 问题反馈: Label
## 按住 TAB 显示的「玩家列表」浮层：玩家三列（名字 / 队伍 / 角色）+ 观战者名单
@export var 玩家列表层: Control
@export var 玩家标题: Label
@export var 玩家网格: GridContainer
@export var 观战标题: Label
@export var 观战网格: GridContainer


func _ready() -> void:
	UI.attach(界面层)
	问题反馈.gui_input.connect(_on_问题反馈_gui_input)
	玩家列表层.visible = false
	UI.goto_enter()
	if Cfg.自动开局:
		_自动开局()


## 点一下右上角的「问题反馈」：左键抬起时用系统默认浏览器打开问卷。
## 必须用「抬起」而不是「按下」：打开浏览器会让游戏窗口失焦，
## 若在按下时就打开，抬起事件会被浏览器收走，切回游戏后鼠标会一直停在长按状态。
func _on_问题反馈_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var 鼠标: InputEventMouseButton = event as InputEventMouseButton
	if 鼠标.button_index == MOUSE_BUTTON_LEFT and not 鼠标.pressed:
		UI.打开反馈问卷()


# ============================================================
# 玩家列表（按住 TAB 看：战斗中的玩家 + 观战者）
# ============================================================
## TAB 按住显示、松开隐藏。用 _input 而不是 _unhandled_key_input：
## TAB 默认会被 GUI 拿去做焦点切换，_unhandled_* 收不到；
## 真要用这一次输入时才 set_input_as_handled()，顺带吃掉 TAB 的焦点跳转。
## 只在房间里（准备室 / 战斗界面）弹，大厅和登录界面按 TAB 不拦也不显示。
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var 键: InputEventKey = event
	if 键.keycode != KEY_TAB or 键.echo:
		return
	if 键.pressed:
		if not _在房间里():
			return
		_刷新玩家名单()
		玩家列表层.visible = true
	else:
		if not 玩家列表层.visible:
			return
		玩家列表层.visible = false
	get_viewport().set_input_as_handled()


## 当前是不是在房间里（准备室 / 战斗界面 —— 观战者也停在这两个界面）
func _在房间里() -> bool:
	return UI.current != null and (UI.current.name == "ReadyRoom" or UI.current.name == "BattleUIMobile")


## 填「玩家列表」：战斗中的玩家（名字 / 队伍 / 角色，自己的名字标橙色）+ 观战者名单
func _刷新玩家名单() -> void:
	玩家标题.text = "【战斗】%d 人" % Data.player_list.size()
	# 常规字色取自段标题：改主题时这里跟着变，不用再抄一个颜色值
	var 常规色: Color = 玩家标题.get_theme_color("font_color")
	_清空网格(玩家网格)
	for p: GPlayer in _按座位排序(Data.player_list):
		_加一格(玩家网格, p.nickname, Color(1.0, 0.65, 0.25) if p.id == Data.id else 常规色)
		var 队伍: String = "红队" if p.color == GConst.RED else ("蓝队" if p.color == GConst.BLUE else "未分队")
		_加一格(玩家网格, 队伍, 常规色)
		_加一格(玩家网格, p.role_name, 常规色)
		var 质量: Array = _连接质量(p)
		_加一格(玩家网格, str(质量[0]), 质量[1] as Color)
	_清空网格(观战网格)
	var 观战者: Array = Data.game_info.get("watchers", [])
	观战标题.text = "【观战者】无" if 观战者.is_empty() else "【观战者】%d 人" % 观战者.size()
	for 名: Variant in 观战者:
		_加一格(观战网格, str(名), 常规色)


## 连接质量一列：掉线就写「掉线」，否则按到房主那一跳的往返延迟分档（0 = 还没测出来）
func _连接质量(p: GPlayer) -> Array:
	if not p.online:
		return ["掉线", Color(0.9, 0.4, 0.4)]
	if p.ping <= 0:
		return ["测量中", Color(0.7, 0.7, 0.7)]
	if p.ping < 80:
		return ["良好 %dms" % p.ping, Color(0.55, 0.9, 0.55)]
	if p.ping < 180:
		return ["一般 %dms" % p.ping, Color(0.95, 0.85, 0.45)]
	return ["较差 %dms" % p.ping, Color(0.95, 0.5, 0.4)]


## 清空一个网格（立刻从树上摘下来再 queue_free，免得和新填的内容并排显示一帧）
func _清空网格(网格: GridContainer) -> void:
	for 旧: Node in 网格.get_children():
		网格.remove_child(旧)
		旧.queue_free()


## 往网格里加一格文字；字号跟段标题取同一个值（省得两处各写一个数字）
func _加一格(网格: GridContainer, 文字: String, 颜色: Color) -> void:
	var 格: Label = Label.new()
	格.text = 文字
	格.add_theme_font_size_override("font_size", 玩家标题.get_theme_font_size("font_size"))
	格.add_theme_color_override("font_color", 颜色)
	网格.add_child(格)


## 玩家按座位号排序：Data.player_list 是「从我开始的顺时针」，直接列出来顺序看着是乱的
func _按座位排序(列表: Array[GPlayer]) -> Array[GPlayer]:
	var 副本: Array[GPlayer] = 列表.duplicate()
	副本.sort_custom(func(a: GPlayer, b: GPlayer) -> bool: return a.id < b.id)
	return 副本


# ============================================================
# 自动开局（多开脚本带 --auto，如按 F10 四开想直接开一盘）
# 走的就是玩家自己那套：进入游戏 → 房主建房 / 其余窗口进同一间房 → 全部准备
# ============================================================
func _自动开局() -> void:
	if not await _等到(func() -> bool: return _界面是("Enter"), 5.0):
		return
	# 昵称在登录界面 _ready 里已按槽位填好（玩家1 / 玩家2 …），直接点「进入游戏」
	UI.current.call("_on_enter_pressed")
	if not await _等到(func() -> bool: return _界面是("Lobby"), 20.0):
		return
	var 大厅: Node = UI.current
	if Net.hosting:
		大厅.call("_on_open_create_pressed")
		await get_tree().create_timer(0.3).timeout
		大厅.call("_on_create_pressed")
	else:
		# 等房主把房间建出来（房间列表非空）再进第 1 间
		if not await _等到(func() -> bool: return not (大厅.get("_room_ids") as Array).is_empty(), 25.0):
			return
		(大厅.get("房间列表") as ItemList).select(0)
		大厅.call("_on_join_pressed")
	if not await _等到(func() -> bool: return _界面是("ReadyRoom"), 25.0):
		return
	# 歇一下再点准备：界面是先出现、玩家数据随后才到的（与 tests/lanPlay.gd 的节奏一致）
	await get_tree().create_timer(0.8).timeout
	UI.current.call("_on_ready_pressed")


## 当前界面是不是指定的那个（界面由 UI 管理器挂，名字见各自 .tscn 的根节点）
func _界面是(名字: String) -> bool:
	return UI.current != null and UI.current.name == 名字


## 等条件成立（每 0.2 秒看一眼）；超时返回 false
func _等到(条件: Callable, 超时: float) -> bool:
	var 截止: int = Time.get_ticks_msec() + int(超时 * 1000.0)
	while Time.get_ticks_msec() < 截止:
		if 条件.call():
			return true
		await get_tree().create_timer(0.2).timeout
	return bool(条件.call())

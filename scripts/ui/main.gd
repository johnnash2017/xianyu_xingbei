extends Control
## 主场景（project.godot 的 run/main_scene）
## 整个游戏只有这一处画背景；登录/大厅/战斗/选将这些界面都由 UI 管理器（autoload 名 UI）
## 挂到「界面层」上，一层层叠在这张背景之上。

@export var 界面层: Control


func _ready() -> void:
	UI.attach(界面层)
	UI.goto_enter()
	if Cfg.自动开局:
		_自动开局()


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

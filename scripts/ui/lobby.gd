extends Control
## 大厅（局域网房间列表）
## 对照参考项目 LobbyUI 的局域网改造思路：
##   * 房间列表只负责「显示房间、点进去」；建房走独立的「创建房间」面板 —— 两者不再混在一个界面里；
##   * 列表每 2 秒自动刷新；满房/进行中照样可点，能不能进由服务端说了算，被拒时显示服务端给的原因；
##   * 跨机加入走「搜索局域网房主」（UDP 发现）或直接填 IP 连接。
## 界面结构全部在 lobby.tscn 里（可在编辑器里所见即所得地改），本脚本只绑节点 + 跑逻辑。

const 刷新间隔: float = 0.5

## 上次开房选的人数 / 选角，记在共享配置里（Cfg.shared_set / shared_get）：
## 多开的几个窗口共用同一份，重开也还在。键名与摆位参数（layout_*）同一段，都在 [shared]。
const 共享键_人数: String = "room_max_player"
const 共享键_选角: String = "room_role_strategy"
## 共享配置里没记录过时的取值：人数与选角的合法值都 ≥ 1，所以用 0 表示「没记过」
const 未记录: int = 0

# ---- 场景里的界面节点 ----
@export var 标题栏: Label
@export var 房间列表: ItemList
@export var 状态栏: Label
@export var 进入按钮: Button
@export var 刷新按钮: Button
@export var 创建房间按钮: Button
@export var 搜索按钮: Button
@export var 返回登录按钮: Button
@export var 设置按钮: Button
@export var 跨机IP输入: LineEdit
@export var 连接按钮: Button
@export var 房主列表: ItemList
## 创建房间弹层
@export var 创建层: Control
@export var 房名输入: LineEdit
## 创建房间的人数单选组（每个按钮的 metadata/people = 人数）
@export var 人数组: ButtonGroup
## 创建房间的选角单选组（每个按钮的 metadata/strategy = GConst.RoleStrategy 值）
@export var 选角组: ButtonGroup
@export var 创建按钮: Button
@export var 取消创建按钮: Button
## 创建房间「指令」行的勾选（界面上写的是「开启作弊」）：勾上后本房间内所有玩家都能用测试指令
@export var 调试模式: CheckBox

var _room_ids: Array[int] = []
var _刷新计时: float = 0.0
var _发现的房主: Array = []


func _ready() -> void:
	UI.register(self)
	Logic.lobby = self
	Logic.room_list_changed.connect(_fill)
	Logic.error_received.connect(_on_error)
	Logic.gossip_received.connect(_on_gossip)
	Logic.notice_received.connect(_on_gossip)
	Net.discovery.host_found.connect(_on_host_found)
	房间列表.item_activated.connect(_on_room_activated)
	房主列表.item_activated.connect(_on_host_activated)
	标题栏.text = "房间列表（局域网）　昵称：%s ｜ 窗口 %d ｜ %s" % [
		Cfg.nickname, Cfg.slot + 1, "房主" if Net.hosting else "加入方",
	]
	进入按钮.pressed.connect(func() -> void: _点了(_on_join_pressed))
	刷新按钮.pressed.connect(func() -> void: _点了(_on_refresh_pressed))
	创建房间按钮.pressed.connect(func() -> void: _点了(_on_open_create_pressed))
	搜索按钮.pressed.connect(func() -> void: _点了(_on_search_pressed))
	返回登录按钮.pressed.connect(func() -> void: _点了(_on_back_pressed))
	设置按钮.pressed.connect(func() -> void: _点了(UI.切换设置))
	连接按钮.pressed.connect(func() -> void: _点了(_on_connect_ip_pressed))
	创建按钮.pressed.connect(func() -> void: _点了(_on_create_pressed))
	取消创建按钮.pressed.connect(func() -> void: _点了(_on_close_create_pressed))
	_恢复建房选项()
	Logic.request_room_list()
	设状态("双击房间或点「进入选中房间」加入；没有房间就点「创建房间」")


func _exit_tree() -> void:
	if Logic.lobby == self:
		Logic.lobby = null


## 按钮统一：先出点击音，再跑各自的处理
func _点了(回调: Callable) -> void:
	Art.play_sfx("Equip")
	回调.call()


func 设状态(t: String) -> void:
	状态栏.text = t


# ============================================================
# 房间列表
# ============================================================
func _process(delta: float) -> void:
	_刷新计时 -= delta
	if _刷新计时 <= 0.0:
		_刷新计时 = 刷新间隔
		Logic.request_room_list()


func _fill(rooms: Array) -> void:
	var 上次选中: int = -1
	var 选中项: Array = 房间列表.get_selected_items()
	if not 选中项.is_empty():
		上次选中 = int(选中项[0])
	房间列表.clear()
	_room_ids.clear()
	for r: Dictionary in rooms:
		var rid: int = int(r.get("room_id", 0))
		_room_ids.append(rid)
		var 现在: int = int(r.get("now_player", 0))
		var 上限: int = int(r.get("max_player", 0))
		var 房间状态: String = "已满" if (上限 > 0 and 现在 >= 上限) else ("进行中" if bool(r.get("playing", false)) else "等待中")
		房间列表.add_item("%d号房　%s　　%d/%d　　%s" % [rid, str(r.get("room_name", "")), 现在, 上限, 房间状态])
		var idx: int = 房间列表.item_count - 1
		if 房间状态 == "已满":
			房间列表.set_item_custom_fg_color(idx, Color(0.85, 0.55, 0.55))
		elif 房间状态 == "进行中":
			房间列表.set_item_custom_fg_color(idx, Color(0.85, 0.8, 0.5))
	# 刷新后尽量保持原来的选中项（否则列表每 2 秒刷一次会把玩家的选择清掉）
	if 上次选中 >= 0 and 上次选中 < _room_ids.size():
		房间列表.select(上次选中)


func _on_room_activated(_index: int) -> void:
	_on_join_pressed()


func _on_join_pressed() -> void:
	var 选中项: Array = 房间列表.get_selected_items()
	if 选中项.is_empty():
		设状态("请先在列表里点一个房间，再点「进入选中房间」")
		return
	var idx: int = int(选中项[0])
	if idx < 0 or idx >= _room_ids.size():
		return
	if not Net.is_connected_to_host():
		设状态("已与房主断开连接，正在重连…")
		return
	设状态("正在进入 %d 号房…" % _room_ids[idx])
	Logic.enter_room(_room_ids[idx])


func _on_refresh_pressed() -> void:
	Logic.request_room_list()
	设状态("已请求刷新房间列表")


# ============================================================
# 创建房间（独立弹层）
# ============================================================
func _on_open_create_pressed() -> void:
	创建层.visible = true
	房名输入.text = "%s 的房间" % Cfg.nickname
	房名输入.grab_focus()
	# 光标放到文本末尾，打开就能直接接着改（不用先按 End）
	房名输入.caret_column = 房名输入.text.length()
	# 调试模式不记忆：每次打开建房面板都从「未勾选」开始（多开脚本 --auto 时已是打开的）
	调试模式.button_pressed = Cfg.调试模式


func _on_close_create_pressed() -> void:
	创建层.visible = false


func _on_create_pressed() -> void:
	if not Net.is_connected_to_host():
		设状态("已与房主断开连接，无法建房")
		return
	var 房名: String = 房名输入.text.strip_edges()
	if 房名 == "":
		房名 = "%s 的房间" % Cfg.nickname
	创建层.visible = false
	设状态("正在创建房间…")
	# 人数 / 选角都是单选组，直接读被按下那个按钮上标的数值（ButtonGroup 不允许全部松开，必定有一个）
	var 人数: int = int(人数组.get_pressed_button().get_meta("people"))
	var 选角: int = int(选角组.get_pressed_button().get_meta("strategy"))
	var 调试: bool = 调试模式.button_pressed
	# 记住这次选的：写共享配置，多开共用一份，下次启动直接沿用。
	# 调试模式刻意不记：每次建房都从「未勾选」开始，免得顺手把调试入口带进正常局
	Cfg.shared_set(共享键_人数, 人数)
	Cfg.shared_set(共享键_选角, 选角)
	Logic.create_room(房名, 人数, 选角, 调试)


# ============================================================
# 建房选项的记忆（人数 / 选角）
# ============================================================
## 按共享配置把人数 / 选角拨回上次选的项（没记过就保持场景里的默认）。
## 多开脚本带了 --count（本批窗口数）时人数以它为准：否则会沿用上次记下的 4 人，
## 六开被建成一间 2v2 房；没有对应按钮的数值（如 1）就保持原样。
## 调试模式刻意不记忆：每次建房都从「未勾选」开始，只有多开脚本带 --auto
## （按 F10 / F11 那种）才强制勾上，方便一拉起来就能用测试指令。
func _恢复建房选项() -> void:
	var 人数: int = int(Cfg.shared_get(共享键_人数, 未记录))
	if Cfg.多开人数 > 0:
		人数 = Cfg.多开人数
	_选中按元数据(人数组, "people", 人数)
	_选中按元数据(选角组, "strategy", int(Cfg.shared_get(共享键_选角, 未记录)))
	调试模式.button_pressed = Cfg.调试模式


## 在单选组里选中 metadata[键] == 值 的那个按钮；「未记录」或没有对应按钮时保持原样
func _选中按元数据(组: ButtonGroup, 键: String, 值: int) -> void:
	if 值 == 未记录:
		return
	for 钮: BaseButton in 组.get_buttons():
		if int(钮.get_meta(键, 未记录)) == 值:
			钮.button_pressed = true
			return


# ============================================================
# 跨机：搜索 / 填 IP
# ============================================================
func _on_search_pressed() -> void:
	_发现的房主.clear()
	房主列表.clear()
	房主列表.visible = true
	设状态("正在搜索局域网房主…")
	Net.search_lan()


func _on_host_found(address: String, port: int, _room_count: int, host_name: String) -> void:
	var 键: String = "%s:%d" % [address, port]
	for f: Dictionary in _发现的房主:
		if f["键"] == 键:
			return
	_发现的房主.append({"键": 键, "address": address, "port": port})
	房主列表.add_item("%s  (%s:%d)　双击连接" % [host_name, address, port])
	设状态("发现 %d 个房主，双击列表项连接" % _发现的房主.size())


func _on_host_activated(index: int) -> void:
	if index < 0 or index >= _发现的房主.size():
		return
	var f: Dictionary = _发现的房主[index]
	Net.stop_search()
	_连到房主(str(f["address"]), int(f["port"]))


func _on_connect_ip_pressed() -> void:
	var ip: String = 跨机IP输入.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	_连到房主(ip, Cfg.server_port)


func _连到房主(ip: String, port: int) -> void:
	设状态("正在连接 %s:%d…" % [ip, port])
	Net.stop_search()
	Net.join_game(ip, port)


# ============================================================
# 服务端回执
# ============================================================
func _on_error(err_id: int, msg: String) -> void:
	设状态("错误：%s" % msg)
	# 房间可能已经被房主解散（列表是 2 秒前的快照）→ 立刻刷新一次，别让玩家反复点空房间
	if err_id == GConst.GE_INVALID_TABLEID or err_id == GConst.GE_PLAYER_FULL:
		Logic.request_room_list()


func _on_gossip(txt: String, _kind: int = 0) -> void:
	设状态(txt)


func _on_back_pressed() -> void:
	Logic.leave_room()
	Net.idle()
	UI.goto_enter()

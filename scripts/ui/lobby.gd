extends Control
## 大厅（局域网房间列表）
## 对照参考项目 LobbyUI 的局域网改造思路：
##   * 房间列表只负责「显示房间、点进去」；建房走独立的「创建房间」面板 —— 两者不再混在一个界面里；
##   * 列表每 2 秒自动刷新；满房/进行中照样可点，能不能进由服务端说了算，被拒时显示服务端给的原因；
##   * 跨机加入走「搜索局域网房主」（UDP 发现）或直接填 IP 连接。
## 界面结构全部在 lobby.tscn 里（可在编辑器里所见即所得地改），本脚本只绑节点 + 跑逻辑。

const 刷新间隔: float = 0.5
## Steam 模式下的刷新间隔：Steam 对大厅查询有限流，别按局域网那个频率刷
const 刷新间隔_steam: float = 2.0
## 状态栏默认提示
const 通用提示: String = "双击房间或点「进入选中房间」加入；没有房间就点「创建房间」"

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
## 底部的 Steam 连接状态（一直显示、持续刷新）
@export var Steam状态: Label
@export var 进入按钮: Button
@export var 刷新按钮: Button
@export var 创建房间按钮: Button
@export var 返回登录按钮: Button
@export var 设置按钮: Button
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
## 满员房间的「是否观战」确认层与它的两个按钮（是 / 否）
@export var 观战确认层: Control
@export var 观战是按钮: Button
@export var 观战否按钮: Button

var _room_ids: Array[int] = []
## 与 _room_ids 一一对应：该房间是不是已满（已满的房间点进去要先问「是否观战」）
var _room_full: Array[bool] = []
## 与 _room_ids 一一对应：该房间还留着我的座位吗（对局中退出/掉线会留座，重进直接坐回去）
var _room_reenter: Array[bool] = []
## 正在问「是否观战」的房间号（-1 = 没在问）
var _待观战房间: int = -1
var _刷新计时: float = 0.0


func _ready() -> void:
	UI.register(self)
	Logic.lobby = self
	Logic.room_list_changed.connect(_fill)
	# Steam 模式：大厅列表整理好后同样走 _fill（形状与局域网那套一致），列表 UI 不用改
	SteamNet.大厅列表已就绪.connect(_fill)
	SteamNet.进房结果.connect(_on_steam_join)
	Logic.error_received.connect(_on_error)
	Logic.gossip_received.connect(_on_gossip)
	Logic.notice_received.connect(_on_gossip)
	房间列表.item_activated.connect(_on_room_activated)
	标题栏.text = "房间列表（%s）　昵称：%s" % [
		"局域网·本地调试" if Cfg.本地模式 else "Steam",
		Cfg.nickname,
	]
	进入按钮.pressed.connect(func() -> void: _点了(_on_join_pressed))
	刷新按钮.pressed.connect(func() -> void: _点了(_on_refresh_pressed))
	创建房间按钮.pressed.connect(func() -> void: _点了(_on_open_create_pressed))
	返回登录按钮.pressed.connect(func() -> void: _点了(_on_back_pressed))
	设置按钮.pressed.connect(func() -> void: _点了(UI.切换设置))
	创建按钮.pressed.connect(func() -> void: _点了(_on_create_pressed))
	取消创建按钮.pressed.connect(func() -> void: _点了(_on_close_create_pressed))
	观战是按钮.pressed.connect(func() -> void: _点了(_on_watch_yes_pressed))
	观战否按钮.pressed.connect(func() -> void: _点了(_on_watch_no_pressed))
	_恢复建房选项()
	Logic.request_room_list()
	设状态(通用提示)
	_刷新Steam状态()


## 底部 Steam 连接状态：一直摆着、每帧对一次（文本没变就不动标签）。
## 联机全靠它，所以不管连没连上都写清楚，别让玩家对着空列表猜。
func _刷新Steam状态() -> void:
	var 用Steam: bool = not Cfg.本地模式
	if Steam状态.visible != 用Steam:
		Steam状态.visible = 用Steam
	if not 用Steam:
		return
	var 文本: String
	var 颜色: Color
	if SteamNet.就绪:
		文本 = "Steam：已连接（%s）" % SteamNet.steam_id
		颜色 = Color(0.5, 0.9, 0.55, 1.0)
	else:
		文本 = "Steam：未登录 —— 请启动并登录 Steam 客户端（登录后会自动重连）"
		颜色 = Color(1.0, 0.45, 0.4, 1.0)
	if Steam状态.text == 文本:
		return
	Steam状态.text = 文本
	Steam状态.add_theme_color_override("font_color", 颜色)


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
	_刷新Steam状态()
	_刷新计时 -= delta
	if _刷新计时 <= 0.0:
		_刷新计时 = 刷新间隔_steam if not Cfg.本地模式 else 刷新间隔
		Logic.request_room_list()


func _fill(rooms: Array) -> void:
	var 上次选中: int = -1
	var 选中项: Array = 房间列表.get_selected_items()
	if not 选中项.is_empty():
		上次选中 = int(选中项[0])
	房间列表.clear()
	_room_ids.clear()
	_room_full.clear()
	_room_reenter.clear()
	for r: Dictionary in rooms:
		var rid: int = int(r.get("room_id", 0))
		_room_ids.append(rid)
		var 现在: int = int(r.get("now_player", 0))
		var 上限: int = int(r.get("max_player", 0))
		var 座位: int = int(r.get("seat_count", 现在))
		var 观战: int = int(r.get("watchers", 0))
		# 「满不满」看座位数（对局中退出/掉线的人座位还留着，服务端也按座位放人）；
		# 显示的人数用在线人数 —— 有人走了列表上立刻看得出来
		var 已满: bool = 上限 > 0 and 座位 >= 上限
		var 可重连: bool = bool(r.get("can_reenter", false))
		_room_full.append(已满)
		_room_reenter.append(可重连)
		var 房间状态: String = "可重连" if 可重连 else ("已满" if 已满 else ("进行中" if bool(r.get("playing", false)) else "等待中"))
		var 掉线: int = 座位 - 现在
		if 掉线 > 0:
			房间状态 += "（%d人掉线）" % 掉线
		房间列表.add_item("%d号房　%s　　%d/%d　观战%d　%s" % [rid, str(r.get("room_name", "")), 现在, 上限, 观战, 房间状态])
		var idx: int = 房间列表.item_count - 1
		if 可重连:
			房间列表.set_item_custom_fg_color(idx, Color(0.55, 0.85, 0.95))
		elif 已满:
			房间列表.set_item_custom_fg_color(idx, Color(0.85, 0.55, 0.55))
		elif bool(r.get("playing", false)):
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
	# 满员的房间：这间房还留着我的座位就直接坐回去（对局中退出/掉线会保留座位），
	# 没留我的座位才问要不要以观战身份进去
	if idx < _room_full.size() and _room_full[idx] and not _可重连(idx):
		_待观战房间 = _room_ids[idx]
		观战确认层.visible = true
		return
	_进入房间(_room_ids[idx])


## 该下标的房间是不是还留着我的座位（重进直接坐回去，不必问要不要观战）
func _可重连(idx: int) -> bool:
	return idx < _room_reenter.size() and _room_reenter[idx]


## Steam 模式下的进房结果：Logic 负责把 P2P 连接切到房主（见 Logic._on_steam_join），这里只显示进度
func _on_steam_join(_成功: bool, 说明: String) -> void:
	设状态(说明)


## 进房（点房间直接进、确认观战后进，都走这里，保证提示文案一致）
func _进入房间(房间号: int) -> void:
	设状态("正在进入 %d 号房…" % 房间号)
	Logic.enter_room(房间号)


# ============================================================
# 满员房间：是否观战
# ============================================================
func _on_watch_yes_pressed() -> void:
	观战确认层.visible = false
	var 房间号: int = _待观战房间
	_待观战房间 = -1
	if 房间号 >= 0:
		_进入房间(房间号)


func _on_watch_no_pressed() -> void:
	观战确认层.visible = false
	_待观战房间 = -1
	设状态("房间已满，已取消进入")


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

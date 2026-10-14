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
const 共享键_座位: String = "room_seat_mode"
## 共享配置里没记录过时的取值：人数与选角的合法值都 ≥ 1，所以用 0 表示「没记过」
const 未记录: int = 0

# ---- 场景里的界面节点 ----
@export var 标题栏: Label
@export var 房间列表: Tree
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
## 创建房间的座位单选组（每个按钮的 metadata/seat = GConst.SeatMode 值）
@export var 座位组: ButtonGroup
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
	SteamNet.建房结果.connect(_on_steam_host_result)
	Logic.error_received.connect(_on_error)
	Logic.gossip_received.connect(_on_gossip)
	Logic.notice_received.connect(_on_gossip)
	_初始化房间列表()
	房间列表.item_activated.connect(_on_room_activated)
	# 昵称只在「本地调试」下标出来（多开时靠它区分窗口）；Steam 模式是正式界面，不显示
	标题栏.text = ("房间列表（局域网·本地调试）　昵称：%s" % Cfg.nickname) if Cfg.本地模式 else "房间列表"
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
	UI.刷新Steam状态(Steam状态)


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
	UI.刷新Steam状态(Steam状态)
	_刷新计时 -= delta
	if _刷新计时 <= 0.0:
		_刷新计时 = 刷新间隔_steam if not Cfg.本地模式 else 刷新间隔
		Logic.request_room_list()


## 列表的列：表头文字（顺序即列序）。用 Tree 的列头显示
const 列表列名: PackedStringArray = ["状态", "人数", "房间名", "观战", "选项"]
## 「房间名」所在列（吃掉多余空间的就这一列；列头文字、悬停、列宽都按它定位）
const 列_房间名: int = 2


## 房间列表用 Tree：原生带列头、每列各占一块矩形，列宽交给控件算 —— 比手工补空格稳得多，
## 列头永远和下面的数据对齐。这里只做一次静态配置（列数 / 列头 / 列宽策略 / 配色）
func _初始化房间列表() -> void:
	房间列表.columns = 列表列名.size()
	房间列表.column_titles_visible = true
	房间列表.hide_root = true
	房间列表.select_mode = Tree.SELECT_ROW
	for i: int in range(列表列名.size()):
		房间列表.set_column_title(i, _列头文字(i))
		房间列表.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_CENTER)
	# 列宽完全跟着内容走：每列的最小宽度由 _调整列宽 按「列头 + 最宽的一格」算出来，
	# 只有「房间名」吃掉多余空间。列头与每一行都由 Tree 统一排，永远对齐、也不会被裁掉
	for i: int in range(列表列名.size()):
		房间列表.set_column_expand(i, i == 列_房间名)
	# 保住大厅的星空底：Tree 默认那块深色 panel 盖上去会和别处不一致
	var 空样式: StyleBoxEmpty = StyleBoxEmpty.new()
	房间列表.add_theme_stylebox_override("panel", 空样式)
	房间列表.add_theme_stylebox_override("focus", 空样式)
	var 选中: StyleBoxFlat = StyleBoxFlat.new()
	选中.bg_color = Color(1.0, 1.0, 1.0, 0.16)
	房间列表.add_theme_stylebox_override("selected", 选中)
	房间列表.add_theme_stylebox_override("selected_focus", 选中)


func _fill(rooms: Array) -> void:
	# 先记住原来选中的是哪间房（列表每 2 秒刷一次，刷完要还回去）
	var 上次选中号: int = _选中房号()
	房间列表.clear()
	_room_ids.clear()
	_room_full.clear()
	_room_reenter.clear()
	# 先把每间房那一行的数据算出来（建列宽要用到，得先有全部内容）
	var 各行: Array[Dictionary] = []
	for r: Dictionary in rooms:
		各行.append(_房间行(r))
	_调整列宽(各行)
	var 根: TreeItem = 房间列表.create_item()   # hide_root=true：根不显示，只当所有房间的父节点
	for 行: Dictionary in 各行:
		var 项: TreeItem = 房间列表.create_item(根)
		var 列: PackedStringArray = 行["列"]
		for i: int in range(列.size()):
			项.set_text(i, 列[i])
			项.set_text_alignment(i, HORIZONTAL_ALIGNMENT_CENTER)
		项.set_metadata(0, int(行["id"]))
		var 悬停: String = str(行["悬停"])
		if 悬停 != "":
			项.set_tooltip_text(列_房间名, 悬停)
		if bool(行["可重连"]):
			_整行着色(项, Color(0.55, 0.85, 0.95))
		elif bool(行["战斗中"]):
			_整行着色(项, Color(0.85, 0.8, 0.5))
		_room_ids.append(int(行["id"]))
		_room_full.append(bool(行["已满"]))
		_room_reenter.append(bool(行["可重连"]))
	if 上次选中号 >= 0:
		_选中房(上次选中号)


## 按内容给每列定最小宽度：取「列头文字」与「这一列所有单元格」里最宽的那个。
## 列头用 title_button_font(_size)，单元格用 font(_size)，两套字体分别量（字号不同）。
## 多留一点边距给 Tree 的单元格内边距，保证列头和内容都不被裁掉。
func _调整列宽(各行: Array[Dictionary]) -> void:
	const 边距: int = 28
	var 列头字体: Font = 房间列表.get_theme_font("title_button_font")
	var 列头字号: int = 房间列表.get_theme_font_size("title_button_font_size")
	var 单元字体: Font = 房间列表.get_theme_font("font")
	var 单元字号: int = 房间列表.get_theme_font_size("font_size")
	for i: int in range(列表列名.size()):
		var 头: String = _列头文字(i)
		var 最宽: float = 列头字体.get_string_size(头, HORIZONTAL_ALIGNMENT_LEFT, -1, 列头字号).x
		for 行: Dictionary in 各行:
			var 列: PackedStringArray = 行["列"]
			最宽 = maxf(最宽, 单元字体.get_string_size(列[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 单元字号).x)
		房间列表.set_column_custom_minimum_width(i, int(最宽) + 边距)


## 列头文字：与数据行一样每列前后各留一个空格（见 _房间行），保证列头和数据左端对齐
func _列头文字(列序: int) -> String:
	return " %s " % 列表列名[列序]


## 当前选中的是哪间房（没选中返回 -1）：房号存在首列的 metadata 里
func _选中房号() -> int:
	var 项: TreeItem = 房间列表.get_selected()
	if 项 == null:
		return -1
	return int(项.get_metadata(0))


## 按房号把对应的行重新选上（列表刷新后还原玩家原来的选择）
func _选中房(rid: int) -> void:
	var 项: TreeItem = 房间列表.get_root().get_first_child()
	while 项 != null:
		if int(项.get_metadata(0)) == rid:
			项.select(0)
			return
		项 = 项.get_next()


## 给整行（所有列）上色
func _整行着色(项: TreeItem, 色: Color) -> void:
	for i: int in range(列表列名.size()):
		项.set_custom_color(i, 色)


## 算出一间房在列表里的那一行：各列文字（顺序见 列表列名）、悬停说明、进房要用的状态标记。
## 状态列只有三种 —— 可重连 / 战斗中 / 等待中；「已满」不当状态显示（座位满含掉线留座，
## 只用来决定进房时要不要问「观战」，否则一局开打后有人掉线，座位仍占满，会显示成「已满」）
func _房间行(r: Dictionary) -> Dictionary:
	var 现在: int = int(r.get("now_player", 0))
	var 上限: int = int(r.get("max_player", 0))
	var 座位: int = int(r.get("seat_count", 现在))
	var 观战: int = int(r.get("watchers", 0))
	var 已满: bool = 上限 > 0 and 座位 >= 上限
	var 可重连: bool = bool(r.get("can_reenter", false))
	var 战斗中: bool = bool(r.get("playing", false))
	var 房间状态: String = "可重连" if 可重连 else ("战斗中" if 战斗中 else "等待中")
	# 建房设置：选角模式 / 座位规则 /（开了才有的）作弊。直接空开显示在行尾，
	# 悬停再给带标签的全称 —— 房间列表每行是单行文本、字号又大，摊开写会把房间名挤出去
	var 设置: PackedStringArray = PackedStringArray()
	var 悬停: PackedStringArray = PackedStringArray()
	var 选角名: String = str(GConst.ROLE_STRATEGY_NAMES.get(int(r.get("role_strategy", 0)), ""))
	if 选角名 != "":
		设置.append(选角名)
		悬停.append("选角：%s" % 选角名)
	var 座位名: String = str(GConst.SEAT_MODE_NAMES.get(int(r.get("seat_mode", 0)), ""))
	if 座位名 != "":
		设置.append(座位名)
		悬停.append("座位：%s" % 座位名)
	if bool(r.get("debug", false)):
		设置.append("作弊")
		悬停.append("作弊：开")
	return {
		"id": int(r.get("room_id", 0)),
		# 每列前后各留一个空格：列与列之间、以及最外侧与列边之间都有呼吸空间
		"列": PackedStringArray([
			" %s " % 房间状态, " %d/%d " % [现在, 上限], " %s " % str(r.get("room_name", "")),
			" 观战 %d " % 观战, " %s " % "　".join(设置)]),
		"悬停": "　".join(悬停),
		"已满": 已满,
		"可重连": 可重连,
		"战斗中": 战斗中,
	}


func _on_room_activated() -> void:
	_on_join_pressed()


func _on_join_pressed() -> void:
	var 项: TreeItem = 房间列表.get_selected()
	if 项 == null:
		设状态("请先在列表里点一个房间，再点「进入选中房间」")
		return
	# 行的下标就是房号（所有房行都挂在隐藏的根下，顺序与 _room_ids 一致）
	var idx: int = 项.get_index()
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


## 建房结果（只有 Steam 模式会发）：直接显示在状态栏，成功 / 失败都能看到
func _on_steam_host_result(_成功: bool, 说明: String) -> void:
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
	# 人数 / 选角 / 座位都是单选组，直接读被按下那个按钮上标的数值（ButtonGroup 不允许全部松开，必定有一个）
	var 人数: int = int(人数组.get_pressed_button().get_meta("people"))
	var 选角: int = int(选角组.get_pressed_button().get_meta("strategy"))
	var 座位: int = int(座位组.get_pressed_button().get_meta("seat"))
	var 调试: bool = 调试模式.button_pressed
	# 记住这次选的：写共享配置，多开共用一份，下次启动直接沿用。
	# 调试模式刻意不记：每次建房都从「未勾选」开始，免得顺手把调试入口带进正常局
	Cfg.shared_set(共享键_人数, 人数)
	Cfg.shared_set(共享键_选角, 选角)
	Cfg.shared_set(共享键_座位, 座位)
	Logic.create_room(房名, 人数, 选角, 座位, 调试)


# ============================================================
# 建房选项的记忆（人数 / 选角 / 座位）
# ============================================================
## 按共享配置把人数 / 选角 / 座位拨回上次选的项（没记过就保持场景里的默认）。
## 多开脚本带了 --count（本批窗口数）时人数以它为准：否则会沿用上次记下的 4 人，
## 六开被建成一间 2v2 房；没有对应按钮的数值（如已取消的 2 人）就保持原样。
## 调试模式刻意不记忆：每次建房都从「未勾选」开始，只有多开脚本带 --auto
## （按 F10 / F11 那种）才强制勾上，方便一拉起来就能用测试指令。
func _恢复建房选项() -> void:
	var 人数: int = int(Cfg.shared_get(共享键_人数, 未记录))
	if Cfg.多开人数 > 0:
		人数 = Cfg.多开人数
	_选中按元数据(人数组, "people", 人数)
	_选中按元数据(选角组, "strategy", int(Cfg.shared_get(共享键_选角, 未记录)))
	_选中按元数据(座位组, "seat", int(Cfg.shared_get(共享键_座位, 未记录)))
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

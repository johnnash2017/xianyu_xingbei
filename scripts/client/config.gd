extends Node
## 配置与多开（autoload 名：Cfg）
## 对照「多开与局域网实现说明.md」第二节：
##  - 每个窗口有独立「槽位」，决定：配置文件、昵称、窗口摆位
##  - 槽位来源：启动参数 --slot N（显式，最稳）；无参数时用回环端口独占性自动认领
##  - 存档按槽位分文件；第一槽位沿用单开存档
##  - 所有窗口共享的配置（如固定随机种子）单独一份文件

const CONFIG_DIR: String = "user://"
const SHARED_FILE: String = "user://shared.cfg"
## 窗口设计比例（与 project.godot 的 1920x1080 设计基准一致，多开摆位按此保持等比）
const 设计宽: float = 1920.0
const 设计高: float = 1080.0

var slot: int = 0
var slot_source: String = "默认"
var nickname: String = ""
var shared: ConfigFile = ConfigFile.new()
var local: ConfigFile = ConfigFile.new()
## 本进程占用的槽位回环端口（保持监听以独占）
var _slot_server: TCPServer = null
## 服务端口（房主监听端口，可被启动参数覆盖）
var server_port: int = GConst.DEFAULT_PORT
## 自动开局（启动参数 --auto）：启动后自动「进入游戏 → 房主建房 / 其余窗口进同一间房 → 准备」，
## 给多开脚本用（按 F10 那种）；不带这个参数时一切照旧，全是手动点。
var 自动开局: bool = false
## 调试模式（建房面板「调试模式」勾选项的默认值）：
## 多开脚本用 --auto 拉起来的那批（F10 / F11 快捷键）默认开着，方便直接测；
## 手动开游戏时为关，只有房主在「创建房间」里勾上才会开。
var 调试模式: bool = false
## 本批多开的窗口数（启动参数 --count=N；0＝没指定）：自动开局建房时按它挑房间人数。
## 不带这个参数就只能沿用上次记下的人数，六开会被建成上次那个 4 人局（2v2）
var 多开人数: int = 0
## 本进程启动时刻（秒）：用来认出「同一批」多开出来的窗口
var 启动时刻: float = 0.0


## 是否处于多开状态：只有多开才做同批联动（关窗一起关、最小化一起切），单开不去影响别的窗口
var 多开: bool = false
## 本地调试模式：只有多开脚本（--slot / --count / --auto，也就是 F9/F10/F11 那三个）拉起来时才为 true，
## 这种启动走现有的局域网 / 本机房间；**直接（裸）启动则为 false**，走 Steam（大厅 + P2P，见 SteamNet）
var 本地模式: bool = false


## 客户端身份标识：连上房主时随登录包发过去，服务端靠它认「还是同一个人」，
## 断线 / 退出后能认领回原座位（见 LocalServer._reclaim_seat）。
## - 本地调试（多开脚本）：用昵称，同机多开时 玩家1/玩家2… 天然区分，重启进程也认得出；
## - Steam 模式：用 SteamID（字符串，64 位过协议不丢精度）；Steam 没连上时退回昵称，
##   免得所有人共用一个空身份。
func 身份标识() -> String:
	if not 本地模式 and SteamNet.就绪:
		return SteamNet.steam_id
	return nickname


func _ready() -> void:
	启动时刻 = Time.get_unix_time_from_system()
	_清理关窗标记()
	_parse_cmdline()
	_claim_slot()
	_load_configs()
	_ensure_nickname()
	# 本地调试模式：多开脚本（--slot / --count / --auto，也就是 F9/F10/F11 那三个）拉起来的一律走本地房间，
	# 裸启动（一个参数都不带）走 Steam。
	# 注意别用「同批窗口数 ≥ 2」（多开）来判断：
	#   ① 多开 是在下面 _apply_layout 里才赋值的，放前面读到的永远是初始的 false；
	#   ② F9 那种只开一个窗口的本地调试，窗口数本来就不到 2，会被误判成裸启动。
	本地模式 = slot_source == "启动参数" or 自动开局 or 多开人数 > 0
	if slot_source == "启动参数":
		# 多开脚本显式指定了槽位与窗口数：立刻按宫格摆位
		_apply_layout(int(shared_get("layout_count", 默认摆位列数 * 默认摆位行数)))
	else:
		# 编辑器「运行多个实例」不带 --slot：先看看一共开了几个窗口，再决定要不要摆位。
		# 只认编辑器里跑起来的实例（F5/F9 那类）：导出的正式包不做这件事 ——
		# 否则玩家同时开两个客户端，窗口会被自动摆到屏幕格子（角落）里，还固定在那儿
		if OS.has_feature("editor"):
			_watch_instances()
	_watch_peers()
	print("[Cfg] 槽位=%d（%s）昵称=%s 服务端口=%d 本地模式=%s" % [
		slot, slot_source, nickname, server_port, str(本地模式)])


# ============================================================
# 启动参数
# ============================================================
func _parse_cmdline() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--slot="):
			slot = int(a.substr(7))
			slot_source = "启动参数"
		elif a == "--slot" and i + 1 < args.size():
			slot = int(args[i + 1])
			slot_source = "启动参数"
			i += 1
		elif a.begins_with("--port="):
			server_port = int(a.substr(7))
		elif a == "--port" and i + 1 < args.size():
			server_port = int(args[i + 1])
			i += 1
		elif a == "--auto":
			自动开局 = true
			调试模式 = true
		elif a.begins_with("--count="):
			多开人数 = int(a.substr(8))
		elif a == "--count" and i + 1 < args.size():
			多开人数 = int(args[i + 1])
			i += 1
		i += 1
	if slot < 0 or slot >= GConst.MAX_SLOT:
		slot = 0


# ============================================================
# 槽位认领：显式参数优先；否则靠回环端口独占性
# ============================================================
func _claim_slot() -> void:
	if slot_source == "启动参数":
		# 显式指定的槽位也占住端口：别的窗口数槽位端口时能数到它（多开脚本与编辑器实例混跑时更准），
		# 同时也避免这个槽位被自动认领的窗口抢走
		var srv: TCPServer = TCPServer.new()
		if srv.listen(GConst.SLOT_PORT_BASE + slot, "127.0.0.1") == OK:
			_slot_server = srv
		else:
			push_warning("[Cfg] 槽位 %d 的端口已被占用（可能有同名多开还在跑）" % slot)
		return
	for k: int in range(GConst.MAX_SLOT):
		var srv: TCPServer = TCPServer.new()
		var err: int = srv.listen(GConst.SLOT_PORT_BASE + k, "127.0.0.1")
		if err == OK:
			_slot_server = srv
			slot = k
			slot_source = "端口认领"
			return
	# 全部槽位被占满：退回第一个
	slot = 0
	slot_source = "回退"


# ============================================================
# 配置文件
# ============================================================
func local_path() -> String:
	# 第一个槽位沿用单开存档，保证单开行为不变
	if slot == 0:
		return CONFIG_DIR + "config.cfg"
	return CONFIG_DIR + "config_%d.cfg" % (slot + 1)


func _load_configs() -> void:
	shared.load(SHARED_FILE)
	local.load(local_path())
	nickname = str(local.get_value("user", "nickname", ""))


func _ensure_nickname() -> void:
	if nickname == "":
		nickname = "玩家%d" % (slot + 1)
		local.set_value("user", "nickname", nickname)
		local.save(local_path())


func set_nickname(n: String) -> void:
	nickname = n
	local.set_value("user", "nickname", n)
	local.save(local_path())


# ============================================================
# 本地设置（设置窗用：背景音乐 / 效果音 音量）
# 存在各自窗口那份 config[_N].cfg 的 [设置] 段，随窗口槽位走（多开互不影响）
# ============================================================
func get_setting(key: String, 默认: Variant) -> Variant:
	return local.get_value("设置", key, 默认)


func set_setting(key: String, value: Variant) -> void:
	local.set_value("设置", key, value)
	local.save(local_path())


## 共享配置：写前重新读盘再改，避免覆盖别的窗口刚写入的键
func shared_set(key: String, value: Variant) -> void:
	shared.load(SHARED_FILE)
	shared.set_value("shared", key, value)
	shared.save(SHARED_FILE)


func shared_get(key: String, default_value: Variant) -> Variant:
	shared.load(SHARED_FILE)
	return shared.get_value("shared", key, default_value)


# ============================================================
# 窗口摆位（每个窗口自己算，只需一份共享的宫格参数）
# ============================================================
## 多开摆位的宫格：按屏幕均分成 列数 × 行数。参数写在共享配置 shared.cfg 里
## （key: layout_cols / layout_rows），所有窗口读同一份 —— 早先这组参数是按槽位存在
## 各自的 config_N.cfg 里，一旦某个槽位的历史值不同（比如 2×2 与 3×2 混着），
## 同一批多开出来的窗口就会被摆成不同大小（表现为「偶尔有一个窗口特别小」）。
## 默认 2×2（4 格，对应 2v2 的 4 人局，正好铺满屏幕）；开超过 4 个时宫格不缩，
## 多出来的窗口绕回已有格子、按整格的 90% 缩小后错位叠上去。
const 默认摆位列数: int = 2
const 默认摆位行数: int = 2
## 同一格里叠多个窗口时，窗口按整格的这个比例缩一点（留出边距，便于看清叠放层次）
const 叠放缩放: float = 0.9
## 同一格里叠多个窗口时，每多一个往下错开这么多像素（要能露出上一个窗口的标题栏）
const 错位间距: int = 40
## 轮询窗口数的间隔；没带 --slot 时（编辑器多开）最多轮询这么多次，等几个窗口都抢完槽位
const 探测间隔: float = 0.3
const 探测次数: int = 20


## 数一数当前有几个窗口占着槽位端口（含本进程自己的）——不依赖 --slot，用来判断是不是多开
func _instance_count() -> int:
	var 数量: int = 0
	for k: int in range(GConst.MAX_SLOT):
		var srv: TCPServer = TCPServer.new()
		if srv.listen(GConst.SLOT_PORT_BASE + k, "127.0.0.1") == OK:
			srv.stop()
		else:
			数量 += 1
	return 数量


## 编辑器「运行多个实例」不带 --slot，只能靠端口认领槽位：启动时还不知道一共开了几个窗口，
## 于是轮询一小段时间，窗口数一变就按新的数量重新摆位。
## 全程只有自己一个（单开）就完全不动窗口。
func _watch_instances() -> void:
	var 上次数量: int = 0
	for i: int in range(探测次数):
		await get_tree().create_timer(探测间隔).timeout
		var 数量: int = _instance_count()
		if 数量 >= 2 and 数量 != 上次数量:
			_apply_layout(数量)
		上次数量 = 数量


# ============================================================
# 关窗联动：一个窗口被关掉，同一批的其它窗口一起关掉
# ============================================================
## 关窗标记：每个槽位一个文件，放在 user:// 下，退出时写下自己的启动时刻。
## 为什么用文件而不是「数槽位端口少没少」：端口占用会被无关进程、启动时序、
## listen 偶发抢占等干扰，数字偶然少一个就会把整批窗口莫名其妙一起关掉；
## 文件标记则只在窗口真的退出时才出现。
const 关窗标记前缀: String = "多开_关闭_"
## 认作「同一批」的启动时刻差（秒）：只和启动时刻相近的窗口联动，
## 避免误伤从编辑器单独跑的实例、或更早批次留下的标记
const 同批秒数: float = 10.0
## 检查关窗标记的间隔（秒）
const 联动间隔: float = 0.2
## 正在重启本窗口（本地调试按 ESC）：退出时**不写关窗标记**，否则同批其它窗口会跟着一起退
var _重启中: bool = false


func _关窗标记路径(槽位: int) -> String:
	return "%s%s%d.txt" % [CONFIG_DIR, 关窗标记前缀, 槽位]


## 启动时清掉上一次多开留下的关窗标记：否则新一批窗口一启动就会看到旧标记而一起退出
func _清理关窗标记() -> void:
	var 目录: DirAccess = DirAccess.open(CONFIG_DIR)
	for 名: String in 目录.get_files():
		if 名.begins_with(关窗标记前缀):
			目录.remove(名)


## 守着其它槽位（每 0.2 秒看一次）：
## 1) 同批的某个窗口关掉了 → 跟着退出；
## 2) 我的最小化被点了 → 喊同批窗口一起切；别人喊的时候我也跟着切。
func _watch_peers() -> void:
	while true:
		await get_tree().create_timer(联动间隔).timeout
		if not 多开:
			continue
		for k: int in range(GConst.MAX_SLOT):
			if k == slot:
				continue
			var 路径: String = _关窗标记路径(k)
			if not FileAccess.file_exists(路径):
				continue
			if absf(FileAccess.get_file_as_string(路径).to_float() - 启动时刻) > 同批秒数:
				continue
			get_tree().quit()
			return
		_同步最小化状态()


## 退出时留下关窗标记，让同批的其它窗口一起退出。
## 放在 _exit_tree 是为了不管走哪条退出路径（点关闭按钮、程序自己 quit）都能留下标记。
func _exit_tree() -> void:
	# 重启本窗口（ESC）时的退出：不写关窗标记，别把同批其它窗口一起带走
	if not 多开 or _重启中:
		return
	var 文件: FileAccess = FileAccess.open(_关窗标记路径(slot), FileAccess.WRITE)
	if 文件 != null:
		文件.store_string("%f" % 启动时刻)


# ============================================================
# 最小化联动：点最小化，同批窗口一起最小化；取消最小化，一起取消
# ============================================================
## 状态请求文件：内容「发起窗口的启动时刻 请求时刻 目标(1=最小化 / 0=取消最小化)」。
## 跨进程读不到别的窗口，就用这个文件喊话：谁的最小化状态被点了，写一份，同批的窗口看到就照做。
## 带启动时刻是为了认「同一批」：上一批留下的请求不会被当真。
const 状态请求文件: String = "多开_窗口状态.txt"
## 请求的有效期（秒）：过期没人理的请求不再响应
const 状态请求秒数: float = 5.0

## 上一次轮询到的自身最小化状态（也就是「我现在是不是最小化着」）
var _上次最小化: bool = false
## 已处理过的请求（请求时刻）：同一份请求只响应一次，
## 否则它还在有效期内时，我再被点一次最小化 / 恢复就会被它立刻弹回去
var _已处理状态请求: float = 0.0


## 每 0.2 秒看一眼自己的最小化状态：
## 自己这一下被点了最小化 / 取消最小化 → 喊同批窗口一起；顺便看看别人有没有在喊我
func _同步最小化状态() -> void:
	var 现在最小化: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	if 现在最小化 != _上次最小化:
		_上次最小化 = 现在最小化
		_请求集体切换(现在最小化)
	_响应状态请求()


## 喊同批窗口切换状态：写一份请求，目标是「我现在的状态」
func _请求集体切换(最小化: bool) -> void:
	var 文件: FileAccess = FileAccess.open(CONFIG_DIR + 状态请求文件, FileAccess.WRITE)
	if 文件 != null:
		文件.store_string("%f %f %d" % [启动时刻, Time.get_unix_time_from_system(), 1 if 最小化 else 0])


## 看有没有同批窗口在喊切换状态：有就跟着切成同样的状态（同一份请求只响应一次）
func _响应状态请求() -> void:
	var 路径: String = CONFIG_DIR + 状态请求文件
	if not FileAccess.file_exists(路径):
		return
	var 片: PackedStringArray = FileAccess.get_file_as_string(路径).strip_edges().split(" ")
	if 片.size() != 3:
		return
	var 发起启动时刻: float = 片[0].to_float()
	var 请求时刻: float = 片[1].to_float()
	var 目标最小化: bool = int(片[2]) == 1
	if absf(发起启动时刻 - 启动时刻) > 同批秒数:
		return
	if 请求时刻 <= _已处理状态请求 or Time.get_unix_time_from_system() - 请求时刻 > 状态请求秒数:
		return
	_已处理状态请求 = 请求时刻
	if 目标最小化 == _上次最小化:
		return   # 本来就是这个状态（多半是我自己喊的那份，或别人已经跟上了）
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_MINIMIZED if 目标最小化 else DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_layout(实例数: int) -> void:
	实例数 = maxi(实例数, slot + 1)
	多开 = 实例数 >= 2
	var cols: int = int(shared_get("layout_cols", 默认摆位列数))
	var rows: int = int(shared_get("layout_rows", 默认摆位行数))
	if cols <= 0 or rows <= 0:
		return
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var cell_w: float = float(usable.size.x) / float(cols)
	var cell_h: float = float(usable.size.y) / float(rows)
	var 格数: int = cols * rows
	var 格号: int = slot % 格数
	@warning_ignore("integer_division")
	var 组内序: int = slot / 格数
	# 一格要叠几个窗口（槽位最多 8 个 → 一格最多 2 个）
	var 组内人数: int = maxi(1, int(ceil(float(实例数) / float(格数))))
	var col: int = 格号 % cols
	@warning_ignore("integer_division")
	var row: int = 格号 / cols
	# 窗口装饰（标题栏 + 两侧边框）：设置/读取窗口自身尺寸用的是逻辑像素，屏幕信息是物理像素，
	# 要把装饰尺寸乘上屏幕缩放系数，才能从物理格子里正确扣除；否则标题栏会被顶出屏幕外。
	var 缩放: float = DisplayServer.screen_get_scale(screen)
	var 装饰: Vector2i = DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	var 边框: int = int(round(float(装饰.x) * 缩放 / 2.0))
	var 标题栏: int = int(round(float(装饰.y) * 缩放)) - 边框
	# 一格一人时窗口铺满整格（保持设计比例 16:9，宽或高总有一条顶满）；一格多人时缩到整格的 90%
	var 占格比: float = 叠放缩放 if 组内人数 > 1 else 1.0
	var 可用客户宽: float = (cell_w - float(边框 * 2)) * 占格比
	var 可用客户高: float = (cell_h - float(标题栏 + 边框)) * 占格比
	if 可用客户宽 <= 0.0 or 可用客户高 <= 0.0:
		return
	var design_ratio: float = 设计宽 / 设计高
	var w: int = 0
	var h: int = 0
	if 可用客户宽 / 可用客户高 > design_ratio:
		h = int(可用客户高)
		w = int(h * design_ratio)
	else:
		w = int(可用客户宽)
		h = int(w / design_ratio)
	if w <= 0 or h <= 0:
		return
	var 外框宽: int = w + 边框 * 2
	var 外框高: int = h + 标题栏 + 边框
	# 外框水平居中；一格一人时垂直居中，一格多人时从格顶起、每多一个往下错开「错位间距」，
	# 这样上面那个窗口的标题栏始终露在外面，点它能把它提到最前。
	var 外框x: int = usable.position.x + int(cell_w * col + (cell_w - 外框宽) / 2.0)
	var 外框y: int = usable.position.y + int(cell_h * row)
	if 组内人数 <= 1:
		外框y += int((cell_h - 外框高) / 2.0)
	else:
		外框y += 组内序 * 错位间距
	# 先摆位置、后改尺寸；window_set_position 摆的是客户区左上角，所以加上装饰偏移；
	# 坐标不能为负，给负数窗口会被系统甩到极远处。
	DisplayServer.window_set_position(Vector2i(maxi(外框x + 边框, 0), maxi(外框y + 标题栏, 0)))
	DisplayServer.window_set_size(Vector2i(w, h))


# ============================================================
# 本地调试：按 ESC 重启本窗口
# ============================================================
## 按 ESC 重启本窗口：先关掉自己，再拉起一个同参数的新窗口（槽位 / 端口 / 窗口数 / 摆位照旧），
## 但**不带 --auto** —— 新窗口停在登录界面、不连任何服务器，是「干净的一个窗口」。
## 两个前提：
##   1) 只在「编辑器里跑起来的本地测试」生效 —— 既要本地模式（F9/F10/F11 的多开脚本拉起来、
##      或带 --slot/--count/--auto 的启动），又要求是本进程由编辑器/工具版引擎拉起的
##      （OS.has_feature("editor")）。导出的正式包即使是本地模式也不给按 ESC 重启；
##   2) 退出时跳过关窗标记（见 _重启中），否则同批其它窗口会跟着一起退。
func _unhandled_key_input(event: InputEvent) -> void:
	if not 本地模式 or not OS.has_feature("editor"):
		return
	var 按键: InputEventKey = event as InputEventKey
	# 只认「按下且非长按重复」的 ESC：按住不放不会连着重启出一串窗口
	if 按键 == null or not 按键.pressed or 按键.echo or 按键.keycode != KEY_ESCAPE:
		return
	# 走到 _unhandled_ 说明没被界面吃掉（设置 / 选角弹层吃掉 ESC 时就该由它们处理）
	get_viewport().set_input_as_handled()
	重启窗口()


## 重启本窗口：参数取本进程的原始命令行，只去掉 --auto。
## 用 set_restart_on_exit 而不是自己 create_process：引擎是在退出收尾的最后才拉起新进程
## （见 main 结尾），也就是「旧窗口先彻底关掉、新窗口才开始」，不会和旧的抢端口 / 抢槽位。
func 重启窗口() -> void:
	var 参数: PackedStringArray = OS.get_cmdline_args()
	var 用户参数: PackedStringArray = PackedStringArray()
	for 项: String in OS.get_cmdline_user_args():
		# --auto 一启动就自动登录 → 建房 / 进房 → 准备，那正是「有连接」：
		# 按 ESC 要的是一个没连接的干净窗口，所以丢掉它（顺带也回到非调试模式）
		if 项 == "--auto":
			continue
		用户参数.append(项)
	if not 用户参数.is_empty():
		# 分隔符要补回来：用户参数（--slot / --port / --count…）不在 get_cmdline_args() 里，
		# 少了这个 --，重启回来的窗口会丢掉自己的槽位，变成另认一个端口
		参数.append("--")
		参数.append_array(用户参数)
	_重启中 = true
	OS.set_restart_on_exit(true, 参数)
	get_tree().quit()

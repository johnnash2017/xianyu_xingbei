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
## 本进程的稳定身份标识：断线重连时用它让服务端认出「还是同一个人」，从而回到原座位。
## 仅在本进程生命周期内稳定——重启客户端即视为新玩家，不会抢占旧座位。
var client_id: String = ""


func _ready() -> void:
	client_id = "%d_%d" % [OS.get_process_id(), randi()]
	_parse_cmdline()
	_claim_slot()
	_load_configs()
	_ensure_nickname()
	_apply_layout()
	print("[Cfg] 槽位=%d（%s）昵称=%s 服务端口=%d" % [slot, slot_source, nickname, server_port])


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
		i += 1
	if slot < 0 or slot >= GConst.MAX_SLOT:
		slot = 0


# ============================================================
# 槽位认领：显式参数优先；否则靠回环端口独占性
# ============================================================
func _claim_slot() -> void:
	if slot_source == "启动参数":
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


## 共享配置：写前重新读盘再改，避免覆盖别的窗口刚写入的键
func shared_set(key: String, value: Variant) -> void:
	shared.load(SHARED_FILE)
	shared.set_value("shared", key, value)
	shared.save(SHARED_FILE)


func shared_get(key: String, default_value: Variant) -> Variant:
	shared.load(SHARED_FILE)
	return shared.get_value("shared", key, default_value)


# ============================================================
# 窗口摆位（每个窗口自己算，不需协调）
# ============================================================
func _apply_layout() -> void:
	var cols: int = int(local.get_value("layout", "cols", 0))
	var rows: int = int(local.get_value("layout", "rows", 0))
	var fill: bool = bool(local.get_value("layout", "fill", true))
	var w_percent: float = float(local.get_value("layout", "width_percent", 0.0))
	var h_percent: float = float(local.get_value("layout", "height_percent", 0.0))
	var fixed_w: int = int(local.get_value("layout", "fixed_width", 0))
	if cols <= 0 or rows <= 0:
		return
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var cell_w: float = float(usable.size.x) / float(cols)
	var cell_h: float = float(usable.size.y) / float(rows)
	var col: int = slot % cols
	var row: int = slot / cols
	var w: int = 0
	var h: int = 0
	if fill:
		# 等比铺满格子：保持设计比例（16:9）
		var design_ratio: float = 设计宽 / 设计高
		var avail_w: float = cell_w - 8.0
		var avail_h: float = cell_h - 40.0
		if avail_w / avail_h > design_ratio:
			h = int(avail_h)
			w = int(h * design_ratio)
		else:
			w = int(avail_w)
			h = int(w / design_ratio)
	elif w_percent > 0.0:
		w = int(usable.size.x * w_percent)
		h = int(usable.size.y * h_percent)
	if fixed_w > 0:
		w = fixed_w
		h = int(fixed_w * 设计高 / 设计宽)
	if w <= 0 or h <= 0:
		return
	# 先摆位置、后改尺寸；坐标不能为负
	var px: int = int(usable.position.x + cell_w * col + (cell_w - w) / 2.0)
	var py: int = int(usable.position.y + cell_h * row + (cell_h - h) / 2.0)
	px = maxi(px, 0)
	py = maxi(py, 0)
	DisplayServer.window_set_position(Vector2i(px, py))
	DisplayServer.window_set_size(Vector2i(w, h))

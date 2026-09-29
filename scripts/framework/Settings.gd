## 本地存档 —— 对应 Unity 的 PlayerPrefs
## 用 ConfigFile 落盘，接口保持 HasKey/GetFloat/SetFloat 风格。
##
## 多开（同一台机器开好几个窗口联机）时，「按工程」的 user:// 就不够用了：
## 六个窗口共用同一个 settings.cfg，用户名、上次进的房间、头像编号互相覆盖，
## 于是每次启动六个窗口名字都一样，得手动改六遍。
##
## 这里给每个窗口一个**槽位（slot）**，各读各的配置：
##   * 槽位 1 继续用原来的 user://settings.cfg —— 单开时行为与以前完全一致；
##   * 槽位 2..N 用 user://settings_<slot>.cfg，第一次创建时把原存档整份复制过来，
##     并给用户名补上窗口号（"玩家" -> "玩家3"），一开就是六个不同的名字；
##   * 之后在登录界面改的名字只写进自己那份文件，重启窗口还是它。
##
## 槽位怎么定：
##   * 启动参数 `--slot=N` 显式指定，最稳（配合工程根目录的 启动多开.ps1）；
##   * 不给参数就自动认领一个空闲槽位 —— 每个槽位对应一个监听端口
##     （11500+N，只绑 127.0.0.1），谁先抢到谁占着：TCP 端口是独占的，
##     占用的进程一退出（哪怕是被强杀）系统立刻归还，所以「关掉窗口 3 再启动一个」
##     会拿回槽位 3 和它的名字。
##     这里刻意不用「记 pid + OS.is_process_running()」：实测在 Windows 上
##     它对别的 Godot 进程会返回 false（对自己才是 true），六个窗口会全挤到槽位 1。
extends Node

## 老路径：单开（槽位 1）仍然用它
const LEGACY_PATH := "user://settings.cfg"
const SLOT_PATH_FMT := "user://settings_%d.cfg"
## 所有窗口共用的那份配置：跟窗口槽位无关，六个窗口读的是同一个文件
const SHARED_PATH := "user://settings_shared.cfg"
## 槽位 N 占用 11500+N 端口（避开 11116 房主端口 / 11117 发现广播 / 11216 自测端口）
const SLOT_PORT_BASE := 11500
## 一台机器最多认到多少个窗口槽位
const MAX_SLOTS := 16

## 本窗口的槽位号（1 起）
var slot: int = 1
## 本窗口实际使用的配置文件路径
var path: String = LEGACY_PATH

var _cfg := ConfigFile.new()
var _loaded := false
## 占住本槽位端口的监听器（进程活着就一直握着，退出时系统自动释放）
var _slot_server: TCPServer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	slot = _resolve_slot()
	path = LEGACY_PATH if slot <= 1 else SLOT_PATH_FMT % slot
	_seed_slot_file()
	_cfg.load(path)
	_loaded = true
	print("Settings: 本窗口槽位 %d，配置 %s，用户名=%s" % [
		slot, path, get_string("username", "<空>")])


func _exit_tree() -> void:
	if _slot_server != null:
		_slot_server.stop()
		_slot_server = null


# ===========================================================================
# 槽位分配（靠端口的独占性，不依赖进程号）
# ===========================================================================
func _resolve_slot() -> int:
	var forced := _cmdline_slot()
	if forced > 0:
		if not _bind_slot(forced):
			push_warning("Settings: 槽位 %d 已被另一个窗口占用（端口 %d），两个窗口会共用同一份配置" % [
				forced, SLOT_PORT_BASE + forced])
		return forced
	for s in range(1, MAX_SLOTS + 1):
		if _bind_slot(s):
			return s
	push_warning("Settings: %d 个窗口槽位全被占用，退回槽位 1" % MAX_SLOTS)
	return 1


## 启动参数 --slot=N（N 非法就返回 0 走自动认领）
func _cmdline_slot() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--slot="):
			var n := a.split("=")[1]
			if n.is_valid_int() and int(n) >= 1 and int(n) <= MAX_SLOTS:
				return int(n)
			push_warning("Settings: --slot=%s 不是 1..%d 的数字，忽略" % [n, MAX_SLOTS])
	return 0


## 认领槽位 s：能独占它的端口就说明没人用。
## 只绑 127.0.0.1，免得 Windows 防火墙为六个窗口各弹一次授权框。
func _bind_slot(s: int) -> bool:
	var srv := TCPServer.new()
	if srv.listen(SLOT_PORT_BASE + s, "127.0.0.1") != OK:
		return false
	if _slot_server != null:
		_slot_server.stop()
	_slot_server = srv
	return true


# ===========================================================================
# 槽位 2..N 的配置文件首次创建：复制原存档 + 用户名带上窗口号
# ===========================================================================
func _seed_slot_file() -> void:
	if slot <= 1 or FileAccess.file_exists(path):
		return
	var legacy := ConfigFile.new()
	if legacy.load(LEGACY_PATH) == OK:
		for k in legacy.get_section_keys("main"):
			_cfg.set_value("main", k, legacy.get_value("main", k))
	var base := str(_cfg.get_value("main", "username", "")).strip_edges()
	if base == "":
		base = "玩家"
	_cfg.set_value("main", "username", "%s%d" % [base, slot])
	# 上次进的房间是「上一个窗口」的，新窗口别跟着自动重进
	# （ConfigFile.erase_section_key 对不存在的键会报错，先判存在）
	if _cfg.has_section_key("main", "lastGame"):
		_cfg.erase_section_key("main", "lastGame")
	_cfg.save(path)


# ===========================================================================
# 读写（对应 PlayerPrefs 的 HasKey/GetFloat/SetFloat 风格）
# ===========================================================================
func has(key: String) -> bool:
	return _cfg.has_section_key("main", key)

func get_value(key: String, def: Variant = null) -> Variant:
	return _cfg.get_value("main", key, def)

func set_value(key: String, value: Variant) -> void:
	_cfg.set_value("main", key, value)
	_cfg.save(path)

func erase(key: String) -> void:
	_cfg.erase_section_key("main", key)
	_cfg.save(path)

func get_int(key: String, def: int = 0) -> int:
	return int(get_value(key, def))

func get_float(key: String, def: float = 0.0) -> float:
	return float(get_value(key, def))

func get_bool(key: String, def: bool = false) -> bool:
	return bool(get_value(key, def))

func get_string(key: String, def: String = "") -> String:
	return str(get_value(key, def))


# ===========================================================================
# 共享配置（与窗口槽位无关，六个窗口共用一份）
# ===========================================================================
## 多开时有些设置本来就该所有窗口一致，比如建房用的「固定种子」——
## 你不可能每次都先找出「当初填种子的那个窗口」。这类键放到单独一份 SHARED_PATH 里：
## 既不会被各窗口自己的配置盖掉，也不跟 settings.cfg（槽位 1 的配置）混在一起。
var _shared := ConfigFile.new()
var _shared_ready := false


func _ensure_shared() -> void:
	if _shared_ready:
		return
	_shared.load(SHARED_PATH)      # 文件不存在就用默认值，set 时会建出来
	_shared_ready = true


func get_shared_int(key: String, def: int = 0) -> int:
	_ensure_shared()
	return int(_shared.get_value("main", key, def))


func get_shared_bool(key: String, def: bool = false) -> bool:
	_ensure_shared()
	return bool(_shared.get_value("main", key, def))


func set_shared_value(key: String, value: Variant) -> void:
	# 写之前重新读一次盘：这份配置是六个窗口共用的，别的窗口可能刚改过，
	# 拿自己进程里那份旧副本直接写会把它改的键盖回去。
	_shared.load(SHARED_PATH)
	_shared_ready = true
	_shared.set_value("main", key, value)
	_shared.save(SHARED_PATH)

@tool
extends EditorPlugin
## 多开测试入口（工程内）：「项目 → 工具 → 多开测试」，或在编辑器里直接按 F9 / F10 / F11。
## 点 / 按之后用 GDScript 拉起现有的 tests/启动多开.ps1 —— 窗口摆位 / 关掉上一批 / 批量昵称
## 仍由那个脚本负责（已跑通，不重写）。
##   F9  = 多开 4 窗口
##   F10 = 多开 4 窗口（自动开局）
##   F11 = 多开 6 窗口（自动开局）
##
## 注意：这三个键在编辑器里被本插件接管（F9 原本是脚本编辑器的加断点、F11 是全屏切换），
## 只在编辑器窗口获得焦点时生效。不想要就在 快捷键表 里删掉对应项。

const 菜单名: String = "多开测试"
const 脚本路径: String = "res://tests/启动多开.ps1"
## 快捷键：键码 → [窗口数, 是否自动开局]
const 快捷键表: Dictionary = {
	KEY_F9: [4, false],
	KEY_F10: [4, true],
	KEY_F11: [6, true],
}
## 菜单项：显示文字 → [窗口数, 是否自动开局]（标题里带上快捷键，好记）
const 菜单项: Dictionary = {
	"多开 4 窗口（F9）": [4, false],
	"多开 4 窗口（自动开局，F10）": [4, true],
	"多开 6 窗口（自动开局，F11）": [6, true],
}

var _子菜单: PopupMenu = null


func _enter_tree() -> void:
	_子菜单 = PopupMenu.new()
	var 序: int = 0
	for 名: String in 菜单项.keys():
		_子菜单.add_item(名, 序)
		序 += 1
	_子菜单.id_pressed.connect(_点了菜单)
	add_tool_submenu_item(菜单名, _子菜单)


func _exit_tree() -> void:
	remove_tool_menu_item(菜单名)
	if _子菜单 != null:
		_子菜单.queue_free()
		_子菜单 = null


## 编辑器里按 F9 / F10 / F11 直接多开。
## _input 比编辑器的快捷键处理更早拿到事件，所以命中后要显式标为已处理，
## 免得同一个 F9 又被脚本编辑器当成「加断点」等编辑器功能再吃一遍
func _input(event: InputEvent) -> void:
	var 键: InputEventKey = event as InputEventKey
	if 键 == null or not 键.pressed or 键.echo:
		return
	if not 快捷键表.has(键.keycode):
		return
	get_viewport().set_input_as_handled()
	var 配置: Array = 快捷键表[键.keycode]
	_拉起多开(int(配置[0]), bool(配置[1]))


func _点了菜单(id: int) -> void:
	var 配置: Array = 菜单项[str(菜单项.keys()[id])]
	_拉起多开(int(配置[0]), bool(配置[1]))


## 用 powershell 执行 tests/启动多开.ps1：不阻塞编辑器（create_process），
## 也不重写脚本里那套摆位 / 关上一批。
## open_console=false：**完全不弹出控制台窗口**（脚本里那句隐藏控制台也就成了空操作）；
## 脚本输出随之丢弃，排查时可改回 true 或直接用 .bat 加 -KeepConsole 跑
func _拉起多开(数量: int, 自动开局: bool) -> void:
	var 脚本: String = ProjectSettings.globalize_path(脚本路径)
	if not FileAccess.file_exists(脚本):
		push_error("[多开] 找不到脚本：%s" % 脚本)
		return
	var 参数: PackedStringArray = PackedStringArray([
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", 脚本,
		"-Count", str(数量),
	])
	if 自动开局:
		参数.append("-Auto")
	var pid: int = OS.create_process("powershell", 参数, false)
	if pid <= 0:
		push_error("[多开] 拉起失败：请确认系统 PATH 里有 powershell")
		return
	print("[多开] 已请求拉起 %d 个窗口（自动开局：%s）" % [数量, "是" if 自动开局 else "否"])

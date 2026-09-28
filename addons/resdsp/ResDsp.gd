@tool
extends EditorPlugin
## ResDsp 插件：让指定后缀的文件显示在文件系统面板中，
## 双击直接用系统默认程序打开，不触发 Godot 内部打开行为。
##
## 原理：
## 1. 将后缀加入编辑器设置 docks/filesystem/other_file_extensions，
##    使其作为普通文件显示，且不会被内部文本编辑器接管。
## 2. 在 _input 阶段拦截文件系统面板中的双击事件（早于 GUI 分发）：
##    - 鼠标位于文件系统 Tree 上、双击左键、且选中项命中配置后缀时，
##      消费该事件（set_input_as_handled），Tree 收不到双击，
##      从而避免 Godot 对 keep 导入文件（如 csv）弹「无法打开」警告；
##    - 随后调用 OS.shell_open 交给系统默认程序打开。
##
## 配置：修改 DISPLAY_EXTENSIONS 数组即可增删需要「显示 + 双击外部打开」的后缀。
## 说明：有内置导入器的后缀（如 csv 的 keep 导入）不受 other_file_extensions 影响，
## 但 keep 导入的文件本身无内部打开行为，双击由本插件交给外部程序。

const DISPLAY_EXTENSIONS: Array[String] = ["xlsx", "csv"]
const OTHER_FILE_EXTENSIONS_SETTING: String = "docks/filesystem/other_file_extensions"
const TEXTFILE_EXTENSIONS_SETTING: String = "docks/filesystem/textfile_extensions"

## 文件系统面板中的 Tree 控件列表，用于判断鼠标位置。
var _fs_trees: Array[Tree] = []

func _enter_tree() -> void:
	_register_extensions()
	call_deferred("_connect_file_system_trees")

func _exit_tree() -> void:
	_fs_trees.clear()

## 在 GUI 分发之前拦截文件系统面板中的双击：
## 命中配置后缀时外部打开并消费事件，避免 Godot 内部处理（警告弹窗等）。
func _input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null:
		return
	if not (mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	if not _is_mouse_on_fs_tree():
		return
	var paths: PackedStringArray = EditorInterface.get_selected_paths()
	var matched: bool = false
	for path: String in paths:
		if DISPLAY_EXTENSIONS.has(path.get_extension().to_lower()):
			OS.shell_open(ProjectSettings.globalize_path(path))
			matched = true
	if matched:
		get_viewport().set_input_as_handled()

## 判断鼠标当前是否位于文件系统面板的 Tree 上（含其子控件）。
func _is_mouse_on_fs_tree() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	for tree: Tree in _fs_trees:
		if is_instance_valid(tree) and (hovered == tree or tree.is_ancestor_of(hovered)):
			return true
	return false

## 将 DISPLAY_EXTENSIONS 中的后缀登记为「其他文件扩展名」，并清理历史误加项。
func _register_extensions() -> void:
	var settings: EditorSettings = EditorInterface.get_editor_settings()
	for extension: String in DISPLAY_EXTENSIONS:
		var ext: String = extension.to_lower()
		_add_extension(settings, OTHER_FILE_EXTENSIONS_SETTING, ext)
		_remove_extension(settings, TEXTFILE_EXTENSIONS_SETTING, ext)

## 向指定的逗号分隔扩展名设置中添加扩展名。
func _add_extension(settings: EditorSettings, setting_name: String, extension: String) -> void:
	var current: String = str(settings.get_setting(setting_name))
	var extensions: PackedStringArray = current.split(",")
	for i: int in extensions.size():
		extensions[i] = extensions[i].strip_edges()
	if extensions.has(extension):
		return
	extensions.append(extension)
	# set_setting 会自动持久化编辑器设置（4.7 中 EditorSettings 已无 save() 方法）
	settings.set_setting(setting_name, ",".join(extensions))

## 从指定的逗号分隔扩展名设置中移除扩展名。
func _remove_extension(settings: EditorSettings, setting_name: String, extension: String) -> void:
	var current: String = str(settings.get_setting(setting_name))
	var extensions: PackedStringArray = current.split(",")
	var new_extensions: PackedStringArray = []
	for ext: String in extensions:
		var trimmed: String = ext.strip_edges()
		if trimmed != extension:
			new_extensions.append(trimmed)
	if new_extensions.size() == extensions.size():
		return
	settings.set_setting(setting_name, ",".join(new_extensions))

## 延迟到下一帧收集文件系统面板中的 Tree（面板此时已构建完成）。
func _connect_file_system_trees() -> void:
	var dock: FileSystemDock = EditorInterface.get_file_system_dock()
	if dock == null:
		return
	_fs_trees.clear()
	_collect_trees(dock, _fs_trees)

## 递归收集 FileSystemDock 下所有 Tree 控件。
func _collect_trees(node: Node, result: Array[Tree]) -> void:
	if node is Tree:
		result.append(node)
	for child: Node in node.get_children():
		_collect_trees(child, result)

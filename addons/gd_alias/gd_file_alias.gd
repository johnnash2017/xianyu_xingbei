@tool
extends EditorPlugin
## GD 文件别名插件
##
## 功能：在编辑器文件系统面板中，为任意文件/文件夹显示自定义别名标签（[ 别名 ]），
## 并把原本文件名置灰；脚本编辑器左侧的脚本列表（"筛选脚本"面板）同样显示别名。
## 别名不再写在脚本头部，而是通过文件系统面板的
## 右键菜单"设置别名…"或 Ctrl+Alt+A 快捷键来添加、修改、删除，数据保存在
## 插件根目录下的 alias_data.json 中。
##
## 设计要点：
## - TreeItem 的文本始终保持真实文件名，F2 / 右键重命名完全不受影响；
## - 别名通过 SubViewport 渲染成小图片（加粗），与该文件的类型图标合并后
##   作为该文件的图标，显示在名字前面，结构上与文件名分离；
## - 原本文件名基于主题色置灰显示；
## - 没有别名的文件保持原样。
## - 脚本列表用同一套合并图标显示别名。该列表被编辑器高频整体重建
##   （节点变动、每秒自动保存、保存脚本等都会重建），事后补显示必然慢一拍、
##   表现为闪烁，因此改为"绘制前接管"：断开编辑器对 tree_changed 的响应，
##   并在每帧绘制前做一次幂等校正（见 _update_script_list_display）。
## - 首次使用时，会自动把旧版写在 .gd 头部的 `#别名` 标记迁移进数据文件，
##   并把这些标记行从脚本中移除。

# ========== 常量 ==========
## 旧版 .gd 头部别名标记（仅用于一次性迁移），例如 "#别名 玩家"
const 别名前缀: String = "#别名"
const MENU_REFRESH_ID: int = 0
## 右键菜单插件脚本（preload 避免 class_name 全局注册时序问题）
const 别名上下文菜单类 := preload("res://addons/gd_alias/alias_context_menu.gd")
## 别名文本图片的基准字号（会随编辑器缩放比例放大）
const 别名基准字号: int = 15
## 别名文本颜色（中性灰，深浅主题下均可读）
const 别名颜色: Color = Color(0.878, 0.878, 0.878, 1.0)
## 别名文本加粗程度（FontVariation 的 embolden，0 为不加粗）
const 别名加粗: float = 0.35
## 别名文本图片四周的留白倍数（随编辑器缩放放大；右侧会多留一份，避免加粗后 ] 贴边被裁剪）
const 别名留白: int = 3
## 别名标签显示时的前缀
const 显示前缀: String = ""
## 别名标签显示时的后缀
const 显示后缀: String = ""
## 别名文本图片的上下高度裁剪量（像素）：把 [ 别名 ] 文字图片上下各裁掉 N 像素，
## 图片变矮后 Tree 行高随之变矮（文字上下会被切掉一点），前面的类型图标不受影响。
## 0 表示不裁剪；配 1 就是上下各裁 1 像素。
const 行高裁剪: int = 10
## 原本名字的置灰程度（0~1：0 保持默认颜色，1 完全灰）
const 原名置灰程度: float = 1
## 别名纹理的磁盘缓存目录（user:// 下，不污染项目文件系统面板）。
## 脚本热重载或编辑器重启后直接从缓存加载，避免全部别名重新渲染闪烁。
const 缓存目录: String = "user://gd_alias_cache"
## 别名数据文件（存于插件根目录，路径 -> 别名）
const 数据文件: String = "res://addons/gd_alias/alias_data.json"
## 场景标签栏查找失败后的重试间隔（帧）：每帧硬找一次全树太费，改成约每秒一次
const 场景标签重试间隔帧: int = 60

# ========== 成员变量 ==========
## 路径 -> 别名 的映射表
var _alias_map: Dictionary[String, String] = {}
## 别名文本 -> 渲染好的纹理（避免重复渲染）
var _icon_cache: Dictionary[String, Texture2D] = {}
## "路径\n显示文本" -> 合并图标（类型图标 + 别名文本），重命名/别名变化后失效重建
var _combined_cache: Dictionary[String, Texture2D] = {}
var _file_system: EditorFileSystem
var _dock: FileSystemDock
var _tree: Tree
var _item_list: ItemList
## 编辑器顶部场景标签栏（TabBar）缓存，以及 场景路径 -> 编辑器原本标题 的备份
var _scene_tabs: TabBar = null
var _scene_tab_titles: Dictionary[String, String] = {}
## 上次尝试查找场景标签栏时的「打开场景」签名（见 _保证场景标签栏，用于限流）
var _场景标签查找签名: String = ""
## 下一次允许重试查找场景标签栏的帧号（限流用）
var _场景标签重试帧: int = 0
var _menu: PopupMenu
## 别名用字体（编辑器默认字体的加粗变体，支持中文），懒加载
var _alias_font: Font
## 设置别名的输入对话框
var _dialog: AcceptDialog
var _dialog_input: LineEdit
var _dialog_path: String
## 文件系统面板右键菜单插件（官方 EditorContextMenuPlugin API）
var _ctx_menu: 别名上下文菜单类
## 文件系统变化导致的刷新是否已排队（合并同一帧内的多次信号触发）
var _refresh_pending: bool = false
## 最后一次导入活动（resources_reimporting / resources_reimported）的时间戳（毫秒）。
## 导入期间 Godot 会为每个资源连续触发信号，用时间门控判断导入是否仍在进行：
## 距最后一次活动不足 3 秒时视为导入中，暂停一切刷新，结束后再统一刷一次。
var _last_import_activity_ms: int = 0
## 导入结束后的兜底刷新是否已排队（避免每个 reimported 都起一个 3 秒 timer 协程）
var _flush_scheduled: bool = false
## 别名数据文件的最后修改时间戳（秒）。未变化时跳过重读与缓存清理，避免高频刷新反复 IO。
var _alias_data_mtime: int = -1
## 当前（或曾经）被应用过别名显示的路径集合。恢复默认显示时只处理这些路径，
## 避免对从未设过别名的节点做无谓的类型图标查询；删除别名后不立即移除，
## 由 _refresh_display 末尾统一清理，保证树/列表两个视图都能各自执行一次幂等恢复。
var _applied_paths: Dictionary[String, bool] = {}
## 路径 -> 文件类型字符串缓存（get_file_type 结果，避免高频文件系统查询）
var _file_type_cache: Dictionary[String, String] = {}
## 脚本编辑器左侧的脚本列表（ItemList），首次识别后缓存
var _script_list: ItemList
## 编辑器自身连在 SceneTree.tree_changed 上的脚本列表重建回调，插件退出时恢复
var _editor_tree_changed_callback: Callable
## 路径 -> 别名显示前的条目原始图标（删除别名后用于恢复脚本列表条目）
var _script_icon_backup: Dictionary[String, Texture2D] = {}
## 路径 -> 别名显示前的条目图标着色（@tool 脚本为强调色），恢复时一并还原
var _script_tint_backup: Dictionary[String, Color] = {}
## 磁盘缓存里也没有的别名显示文本 -> true：排队等统一渲染，避免启动时一次性渲染全部
var _待渲染: Dictionary[String, bool] = {}
## 待渲染队列是否已排了延迟处理（同一批只排一次）
var _渲染排队中: bool = false

func _enter_tree() -> void:
	_file_system = EditorInterface.get_resource_filesystem()
	_dock = EditorInterface.get_file_system_dock()
	# 文件系统变化时（新增/删除/重命名/内容修改）重新加载数据并刷新显示
	_file_system.filesystem_changed.connect(_on_filesystem_changed)
	# 批量导入开始/结束：导入期间暂停刷新，全部导入完成后统一刷一次
	_file_system.resources_reimporting.connect(_on_resources_reimporting)
	_file_system.resources_reimported.connect(_on_resources_reimported)
	# 切换树/列表显示模式时刷新显示
	_dock.display_mode_changed.connect(_on_display_mode_changed)
	# 提供"项目"菜单中的手动刷新入口，覆盖编辑器内保存脚本等未触发文件系统信号的场景
	_menu = PopupMenu.new()
	_menu.add_item("刷新 GD 文件别名显示", MENU_REFRESH_ID)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_tool_submenu_item("GD 文件别名", _menu)
	# 设置别名的输入对话框（回车确认、Esc 关闭）
	_create_alias_dialog()
	# 注册文件系统面板右键菜单"设置别名…"（官方 API，带 Ctrl+Alt+A 快捷键提示）
	_ctx_menu = 别名上下文菜单类.new()
	_ctx_menu.设置别名请求.connect(_on_context_menu_alias_requested)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _ctx_menu)
	# 编辑器会把脚本列表整体重建成原样（节点变动、每秒自动保存等），在下一步之前
	# 事后补显示都慢一拍；这里改成"绘制前接管"：断开编辑器对节点变动的重建响应，
	# 并在每帧绘制前做一次幂等校正，保证画出来的始终是带别名的版本
	_disable_editor_script_list_rebuild()
	# 编辑器每次自动保存都会整表重建（save_all_scripts 末尾是无条件重建），
	# 在同一信号上再连一次：编辑器回调先执行，本插件紧随其后同步补回别名
	_connect_editor_autosave_repair()
	# 输入阶段触发的重建（敲"筛选脚本"、快捷键切脚本、菜单操作、保存、开关脚本页签、
	# 文件系统变动等）都在节点处理之前发生，而容器重排是延迟调用、绘制更在其后：
	# 在 process_frame（输入之后、延迟队列与绘制之前）补一次，这一帧的排布就是别名版
	get_tree().process_frame.connect(_update_script_list_display)
	RenderingServer.frame_pre_draw.connect(_update_script_list_display)
	# 文件系统面板同样会被编辑器整体重建（保存脚本、文件系统变动、切换显示模式、
	# 展开折叠等）且没有"重建完成"信号，同样在每帧绘制前兜底校正
	RenderingServer.frame_pre_draw.connect(_update_file_system_display)
	# 顶部场景标签栏（带 "+" 那条）的标题同样会被编辑器重设，纳入每帧校正
	get_tree().process_frame.connect(_update_scene_tabs_display)
	RenderingServer.frame_pre_draw.connect(_update_scene_tabs_display)
	# 启动只把别名数据读进来（几 KB 的 JSON），**不做全量刷新**：
	# 全量刷新会一次性把全部别名图片解码/渲染出来、再遍历整棵文件树，
	# 正是编辑器启动变慢的主因。显示交给每帧的幂等校正按需补齐
	# （别名图片改为懒加载，见 _取别名图片）；要彻底重来一次用
	# 「项目 → 工具 → 刷新 GD 文件别名显示」。
	_load_alias_data.call_deferred()

func _exit_tree() -> void:
	if _ctx_menu != null:
		remove_context_menu_plugin(_ctx_menu)
		_ctx_menu.设置别名请求.disconnect(_on_context_menu_alias_requested)
	# EditorContextMenuPlugin 是 RefCounted，不需要 queue_free，置空即可释放
	_ctx_menu = null
	remove_tool_menu_item("GD 文件别名")
	if _menu != null:
		_menu.queue_free()
	_menu = null
	if _dialog != null:
		_dialog.queue_free()
	_dialog = null
	_dialog_input = null
	if _file_system != null and _file_system.filesystem_changed.is_connected(_on_filesystem_changed):
		_file_system.filesystem_changed.disconnect(_on_filesystem_changed)
	if _file_system != null and _file_system.resources_reimporting.is_connected(_on_resources_reimporting):
		_file_system.resources_reimporting.disconnect(_on_resources_reimporting)
	if _file_system != null and _file_system.resources_reimported.is_connected(_on_resources_reimported):
		_file_system.resources_reimported.disconnect(_on_resources_reimported)
	if _dock != null and is_instance_valid(_dock) and _dock.display_mode_changed.is_connected(_on_display_mode_changed):
		_dock.display_mode_changed.disconnect(_on_display_mode_changed)
	if get_tree().process_frame.is_connected(_update_script_list_display):
		get_tree().process_frame.disconnect(_update_script_list_display)
	if RenderingServer.frame_pre_draw.is_connected(_update_script_list_display):
		RenderingServer.frame_pre_draw.disconnect(_update_script_list_display)
	if RenderingServer.frame_pre_draw.is_connected(_update_file_system_display):
		RenderingServer.frame_pre_draw.disconnect(_update_file_system_display)
	if get_tree().process_frame.is_connected(_update_scene_tabs_display):
		get_tree().process_frame.disconnect(_update_scene_tabs_display)
	if RenderingServer.frame_pre_draw.is_connected(_update_scene_tabs_display):
		RenderingServer.frame_pre_draw.disconnect(_update_scene_tabs_display)
	_restore_editor_script_list_rebuild()
	_disconnect_script_list()
	_script_icon_backup.clear()
	_script_tint_backup.clear()
	_disconnect_tree()
	_disconnect_item_list()

func _on_menu_id_pressed(id: int) -> void:
	if id == MENU_REFRESH_ID:
		_do_full_refresh()

## 一批资源开始导入：记录活动时间（导入期间暂停刷新）
func _on_resources_reimporting(_resources: PackedStringArray) -> void:
	_last_import_activity_ms = Time.get_ticks_msec()

## 单个资源导入完成：记录活动时间，并排一个延迟协程兜底刷新。
## 不立即刷新——多文件导入时 reimported 会连续触发，期间刷新只会拖慢主循环。
## 只保留一个兜底协程，避免每个 reimported 都起一个 3 秒 timer 堆积。
func _on_resources_reimported(_resources: PackedStringArray) -> void:
	_last_import_activity_ms = Time.get_ticks_msec()
	if _flush_scheduled:
		return
	_flush_scheduled = true
	_flush_after_import.call_deferred()

func _on_filesystem_changed() -> void:
	# 距最后一次导入活动不足 3 秒视为导入仍在进行：暂停刷新，
	# 避免导入进行中反复执行全量刷新拖慢主循环（表现为导入进度卡住）
	if Time.get_ticks_msec() - _last_import_activity_ms < 3000:
		return
	# 合并同一帧内的多次触发，一帧内最多只刷新一次
	if _refresh_pending:
		return
	_refresh_pending = true
	# 延迟到当前帧结束再刷新，确保文件系统面板自身已完成重建
	_do_full_refresh.call_deferred()

## 延迟协程兜底：导入结束后若迟迟没有 filesystem_changed（异常场景），
## 延迟 3 秒确认导入已停止后，刷新一次面板。
func _flush_after_import() -> void:
	await get_tree().create_timer(3.0).timeout
	_flush_scheduled = false
	if not is_inside_tree():
		return
	# 期间又发生了导入活动，说明导入仍在进行，交给下一次 reimported 重新排队
	if Time.get_ticks_msec() - _last_import_activity_ms < 3000:
		return
	if _refresh_pending:
		return
	_refresh_pending = true
	_do_full_refresh.call_deferred()

func _on_display_mode_changed() -> void:
	_refresh_display.call_deferred()

func _on_item_collapsed(_item: TreeItem) -> void:
	# 树节点展开时会懒加载子项，需要重新应用显示名
	_refresh_display.call_deferred()

## 重新加载别名数据并刷新面板显示
func _do_full_refresh() -> void:
	_refresh_pending = false
	# 数据文件未变化时跳过重读与缓存清理，只刷新显示（保存脚本等高频触发场景）
	if _load_alias_data():
		_cleanup_caches()
	# 别名图片一律懒加载（见 _取别名图片）：这里不再批量渲染补齐，
	# 交给每帧的显示校正按「实际显示到的」去补齐，避免一次性解码/渲染全部别名拖住主循环
	_refresh_display()


## 清理各缓存中已失效的项（仅当别名数据发生变化时调用）：
## - 合并图标缓存：路径已不在数据表，或显示文本已变化；
## - 别名文本纹理缓存：显示文本已不被任何别名使用；
## - 文件类型缓存：路径已不在数据表；
## - 磁盘纹理缓存：孤儿 png（不再对应任何有效别名）。
func _cleanup_caches() -> void:
	_cleanup_combined_cache()
	_cleanup_icon_cache()
	_cleanup_file_type_cache()
	_cleanup_disk_cache()

## 删除合并图标缓存中已失效的项：路径已不在数据表中（重命名/删除），
## 或路径仍在但显示文本已变化（修改别名后旧缓存会继续命中旧图标）。
## 缓存 key 为 "路径\n显示文本"，与别名强绑定。
func _cleanup_combined_cache() -> void:
	var 失效: Array[String] = []
	for key: String in _combined_cache:
		var path: String = key.get_slice("\n", 0)
		if not _alias_map.has(path):
			失效.append(key)
			continue
		var display: String = key.get_slice("\n", 1)
		if _get_display_text(_alias_map[path]) != display:
			失效.append(key)
	for key: String in 失效:
		_combined_cache.erase(key)

## 清理别名文本纹理缓存中已不被任何别名使用的显示文本
func _cleanup_icon_cache() -> void:
	var 有效: Dictionary[String, bool] = {}
	for path: String in _alias_map:
		有效[_get_display_text(_alias_map[path])] = true
	var 失效: Array[String] = []
	for display: String in _icon_cache:
		if not 有效.has(display):
			失效.append(display)
	for display: String in 失效:
		_icon_cache.erase(display)

## 清理文件类型缓存中已不在别名表的路径
func _cleanup_file_type_cache() -> void:
	var 失效: Array[String] = []
	for path: String in _file_type_cache:
		if not _alias_map.has(path):
			失效.append(path)
	for path: String in 失效:
		_file_type_cache.erase(path)

## 清理磁盘缓存中不再对应任何有效别名的孤儿 png
func _cleanup_disk_cache() -> void:
	var dir: DirAccess = DirAccess.open(缓存目录)
	if dir == null:
		return
	var 有效路径: Dictionary[String, bool] = {}
	for path: String in _alias_map:
		有效路径[_get_cache_path(_get_display_text(_alias_map[path]))] = true
	var 待删除: Array[String] = []
	dir.list_dir_begin()
	var 文件名: String = dir.get_next()
	while 文件名 != "":
		if 文件名.ends_with(".png"):
			var full: String = 缓存目录 + "/" + 文件名
			if not 有效路径.has(full):
				待删除.append(文件名)
		文件名 = dir.get_next()
	dir.list_dir_end()
	for 待删文件: String in 待删除:
		dir.remove(待删文件)

## 刷新文件系统面板的显示（树形视图与列表视图均处理）
func _refresh_display() -> void:
	if _dock == null or not is_instance_valid(_dock):
		return
	_update_tree_display()
	_update_item_list_display()
	_update_script_list_display()
	_update_scene_tabs_display()
	# 恢复完成后清理已不在别名表中的 applied 路径，避免集合无限增长
	_cleanup_applied_paths()

## 清理 _applied_paths 中已不在别名表中的路径（删除别名/重命名/删除文件后残留项）
func _cleanup_applied_paths() -> void:
	var 失效: Array[String] = []
	for path: String in _applied_paths:
		if not _alias_map.has(path):
			失效.append(path)
	for path: String in 失效:
		_applied_paths.erase(path)

# ========== 设置别名的入口（右键菜单 / Ctrl+Alt+A） ==========

## 右键菜单"设置别名…"被点击时回调：对选中的第一个路径弹出输入框
func _on_context_menu_alias_requested(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	_open_alias_dialog(paths[0])

## 在文件系统面板树视图中按 Ctrl+Alt+A 弹出设置别名
func _on_tree_gui_input(event: InputEvent) -> void:
	if not _is_alias_shortcut(event):
		return
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if meta == null:
		return
	_open_alias_dialog(str(meta))
	get_viewport().set_input_as_handled()

## 在文件系统面板列表视图中按 Ctrl+Alt+A 弹出设置别名
func _on_item_list_gui_input(event: InputEvent) -> void:
	if not _is_alias_shortcut(event):
		return
	var selected: PackedInt32Array = _item_list.get_selected_items()
	if selected.is_empty():
		return
	var meta: Variant = _item_list.get_item_metadata(selected[0])
	if meta == null:
		return
	_open_alias_dialog(str(meta))
	get_viewport().set_input_as_handled()

## 检测设置别名快捷键（Ctrl+Alt+A）。不用 F3——F3 是编辑器"查找下一个"的默认快捷键。
func _is_alias_shortcut(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		return key.pressed and not key.echo \
			and key.keycode == KEY_A and key.ctrl_pressed and key.alt_pressed
	return false

# ========== 设置别名对话框 ==========

func _create_alias_dialog() -> void:
	_dialog = AcceptDialog.new()
	_dialog.title = "设置别名"
	_dialog.ok_button_text = "确定"
	# 高度要足够容纳：说明文字 + 输入框 + 按钮，否则说明会被挤出窗口外
	_dialog.size = Vector2i(720, 150)
	_dialog.min_size = Vector2i(600, 130)
	# 用 VBoxContainer 让说明与输入框按顺序垂直排布（AcceptDialog 内部按容器布局，
	# 不能依赖 anchors/offsets 定位）
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	# 说明文字放在窗口内固定可见，不放输入框占位符里（占位符平时看不到）
	var hint: Label = Label.new()
	hint.name = "别名说明"
	hint.text = "输入别名 或 置空可删除别名"
	box.add_child(hint)
	_dialog_input = LineEdit.new()
	_dialog_input.placeholder_text = "输入别名"
	box.add_child(_dialog_input)
	_dialog.add_child(box)
	_dialog.confirmed.connect(_on_alias_dialog_confirmed)
	# 输入框内回车等同点击确定
	_dialog_input.text_submitted.connect(_on_alias_text_submitted)
	add_child(_dialog)

func _open_alias_dialog(path: String) -> void:
	if _dialog == null:
		return
	_dialog_path = path
	_dialog_input.text = _alias_map.get(path, "")
	_dialog_input.select_all()
	_dialog.popup_centered(Vector2i(720, 150))
	_dialog_input.grab_focus()

func _on_alias_text_submitted(_text: String) -> void:
	# 输入框内回车等同点击确定：直接提交并关闭窗口
	_on_alias_dialog_confirmed()
	_dialog.hide()

func _on_alias_dialog_confirmed() -> void:
	var alias: String = _dialog_input.text.strip_edges()
	if alias.is_empty():
		_alias_map.erase(_dialog_path)
	else:
		_alias_map[_dialog_path] = alias
	_save_alias_data()
	_do_full_refresh()

# ========== 数据读写 ==========

## 加载别名数据；返回 true 表示数据内容发生变化（含首次加载/迁移）。
## 数据文件 mtime 未变化时直接返回 false，避免反复 IO 与 JSON 解析。
## 数据文件不存在时（首次使用）把旧版 .gd 头部的 #别名 迁移进来。
func _load_alias_data() -> bool:
	var 存在: bool = FileAccess.file_exists(数据文件)
	var mtime: int = FileAccess.get_modified_time(数据文件) if 存在 else -1
	if 存在 and mtime == _alias_data_mtime:
		return false
	_alias_data_mtime = mtime
	_alias_map.clear()
	if not 存在:
		_migrate_legacy_aliases()
		_save_alias_data()
		return true
	var file: FileAccess = FileAccess.open(数据文件, FileAccess.READ)
	if file == null:
		return true
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		for key: Variant in parsed:
			_alias_map[str(key)] = str(parsed[key])
	return true

## 把别名数据保存到插件根目录的数据文件；写入失败时弹窗提示
func _save_alias_data() -> void:
	var file: FileAccess = FileAccess.open(数据文件, FileAccess.WRITE)
	if file == null:
		_show_save_error()
		return
	file.store_string(JSON.stringify(_alias_map, "\t"))
	file.close()

## 弹窗提示别名数据保存失败
func _show_save_error() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "保存失败"
	dialog.dialog_text = "无法写入别名数据文件，本次修改可能未保存：\n" + 数据文件
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

## 遍历项目里所有 .gd，把头部 #别名 标记读入数据表，并记录需要移除标记的文件
func _migrate_legacy_aliases() -> void:
	var fs_root: EditorFileSystemDirectory = _file_system.get_filesystem()
	if fs_root == null:
		return
	var 待移除: Array[String] = []
	_scan_directory_for_legacy(fs_root, 待移除)
	for path: String in 待移除:
		_remove_alias_header(path)

func _scan_directory_for_legacy(dir: EditorFileSystemDirectory, 待移除: Array[String]) -> void:
	for i in range(dir.get_file_count()):
		var path: String = dir.get_file_path(i)
		if path.ends_with(".gd"):
			var alias: String = _read_alias(path)
			if not alias.is_empty():
				_alias_map[path] = alias
				待移除.append(path)
	for j in range(dir.get_subdir_count()):
		_scan_directory_for_legacy(dir.get_subdir(j), 待移除)

## 读取 .gd 文件头部的 #别名 标记，未找到时返回空字符串
func _read_alias(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var result: String = ""
	# 只在文件头部前 50 行内查找，避免整文件读取的开销
	for i in range(50):
		if file.eof_reached():
			break
		var line: String = file.get_line().strip_edges()
		# 兼容带 UTF-8 BOM 的文件（BOM 会在第一行开头出现）
		if line.begins_with("\uFEFF"):
			line = line.substr(1)
		if line.begins_with(别名前缀):
			var value: String = line.substr(别名前缀.length()).strip_edges()
			# 排除 "#别名xxx" 之类的误匹配以及以 # 开头的其它指令
			if not value.is_empty() and not value.begins_with("#"):
				result = value
				break
	file.close()
	return result

## 移除 .gd 文件头部（任意位置）的 #别名 标记行，保留其它内容与换行风格
func _remove_alias_header(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var lines: PackedStringArray = text.split("\n")
	var filtered: PackedStringArray = []
	for line: String in lines:
		var stripped: String = line.strip_edges()
		if stripped.begins_with("\uFEFF"):
			stripped = stripped.substr(1).strip_edges()
		if stripped.begins_with(别名前缀):
			continue
		filtered.append(line)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(filtered))
	file.close()

# ========== 显示名应用 ==========

## 文件系统面板的别名校正（每帧绘制前调用）。面板的树/列表会被编辑器整体重建
## （保存脚本、文件系统变动、切换显示模式、展开折叠等），重建后若在绘制前没有
## 刷新事件补齐，就会露出编辑器原图标——表现为"闪一下"。这里做幂等校正兜底；
## 各项写入都先比较再写，避免每帧把控件标脏重绘。
func _update_file_system_display() -> void:
	if _alias_map.is_empty():
		return
	_update_tree_display()
	_update_item_list_display()

func _update_tree_display() -> void:
	var tree: Tree = _find_tree()
	if tree == null:
		return
	var root: TreeItem = tree.get_root()
	if root == null:
		return
	_apply_tree_item(root)

func _apply_tree_item(item: TreeItem) -> void:
	_try_apply_alias(item)
	var child: TreeItem = item.get_first_child()
	while child != null:
		_apply_tree_item(child)
		child = child.get_next()

## 该树节点有别名则应用别名图标并置灰原名；无别名则恢复默认显示。
## 仅对之前被应用过别名显示的路径做恢复（幂等），避免对从未设过别名的
## 大量节点做无谓的类型图标查询。
func _try_apply_alias(item: TreeItem) -> void:
	var meta: Variant = item.get_metadata(0)
	if meta == null:
		return
	var path: String = str(meta)
	var alias: String = _alias_map.get(path, "")
	if alias.is_empty():
		if not _applied_paths.has(path):
			return
		# 无别名：恢复默认文字颜色、对应类型图标与默认行高
		# 注意：不能用 Color() 清除，Godot 会把 Color()（透明黑）当作有效颜色应用
		item.set_custom_color(0, _get_default_name_color())
		var base_icon: Texture2D = _get_type_icon(path)
		if base_icon != null:
			item.set_icon(0, base_icon)
		item.set_custom_minimum_height(0)
		item.set_icon_max_width(0, 0)
		return
	var icon: Texture2D = _get_combined_icon(path, alias)
	if icon != null and item.get_icon(0) != icon:
		item.set_icon(0, icon)
		# 行高跟随裁剪后的图标高度（收紧行距请调大 行高裁剪 常量）
		item.set_custom_minimum_height(int(icon.get_height()) + int(4 * EditorInterface.get_editor_scale()))
		# 解除 Tree 对图标最大宽度的限制，否则整个合并图标会被按比例压缩变小
		item.set_icon_max_width(0, int(icon.get_width()))
	# 原本名字置灰，突出别名标签
	var 目标色: Color = _get_grayed_name_color()
	if item.get_custom_color(0) != 目标色:
		item.set_custom_color(0, 目标色)
	_applied_paths[path] = true

func _update_item_list_display() -> void:
	var list: ItemList = _find_item_list()
	if list == null:
		return
	for i in range(list.item_count):
		var meta: Variant = list.get_item_metadata(i)
		if meta == null:
			continue
		var path: String = str(meta)
		var alias: String = _alias_map.get(path, "")
		if alias.is_empty():
			if not _applied_paths.has(path):
				continue
			# 无别名：恢复默认文字颜色与对应类型图标（不能用 Color()，否则文字变透明黑）
			list.set_item_custom_fg_color(i, _get_default_list_name_color())
			var base_icon: Texture2D = _get_type_icon(path)
			if base_icon != null:
				list.set_item_icon(i, base_icon)
			continue
		var icon: Texture2D = _get_combined_icon(path, alias)
		if icon != null and list.get_item_icon(i) != icon:
			list.set_item_icon(i, icon)
		# 原本名字置灰
		var 目标色: Color = _get_grayed_name_color()
		if list.get_item_custom_fg_color(i) != 目标色:
			list.set_item_custom_fg_color(i, 目标色)
		_applied_paths[path] = true

## 生成并缓存 合并图标 = 该文件类型图标 + 别名文本图片。
## 注意：必须以纯净的类型图标为基础拼接，绝不能用 item 当前显示的图标，
## 否则热重载后当前图标已是上次的合并图，会导致别名反复叠加。
## 缓存 key 为 "路径\n显示文本\n条目着色"：路径不变但别名或着色变化时旧缓存自动失效，
## 保证修改别名后文件系统面板能立即显示新别名。
## tint 为该条目的图标着色（脚本列表里 @tool 脚本的强调色），先烘焙进类型图标再拼接，
## 使别名文字保持中性色——条目着色会作用于整张合并图标。
func _get_combined_icon(path: String, alias: String, tint: Color = Color.WHITE) -> Texture2D:
	var display: String = _get_display_text(alias)
	var key: String = path + "\n" + display + "\n" + tint.to_html(false)
	if _combined_cache.has(key):
		return _combined_cache[key]
	var alias_tex: Texture2D = _取别名图片(display)
	if alias_tex == null:
		# 图片还没有（磁盘缓存里没有）：排队渲染，本轮先保持类型图标，渲染完成后自动补刷新
		_排队渲染(display)
		return null
	var base_icon: Texture2D = _get_type_icon(path)
	if base_icon == null:
		return null
	var base_img: Image = base_icon.get_image()
	var alias_img: Image = alias_tex.get_image()
	if base_img == null or alias_img == null or base_img.is_empty() or alias_img.is_empty():
		return null
	# 只裁剪别名文本图片的上下（前面的类型图标保持完整），文字会上下被切掉一点
	if 行高裁剪 > 0:
		var 裁剪: int = min(行高裁剪, int(alias_img.get_height() / 2))
		alias_img = alias_img.get_region(Rect2i(0, 裁剪, alias_img.get_width(),
				maxi(1, alias_img.get_height() - 裁剪 * 2)))
	var 间隔: int = int(5 * EditorInterface.get_editor_scale())
	var width: int = base_img.get_width() + 间隔 + alias_img.get_width()
	var height: int = maxi(base_img.get_height(), alias_img.get_height())
	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.blit_rect(base_img, Rect2i(Vector2i.ZERO, base_img.get_size()), Vector2i.ZERO)
	if tint != Color.WHITE:
		# 条目着色只作用在类型图标上：直接给条目设置会连别名文字一起染色
		_tint_icon_region(img, Rect2i(Vector2i.ZERO, base_img.get_size()), tint)
	var alias_y: int = int((height - alias_img.get_height()) / 2)
	img.blit_rect(alias_img, Rect2i(Vector2i.ZERO, alias_img.get_size()),
			Vector2i(base_img.get_width() + 间隔, alias_y))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_combined_cache[key] = tex
	return tex

## 把着色乘到图片的指定区域上（等价于只对该区域应用 TextureRect 的 modulate）
func _tint_icon_region(img: Image, rect: Rect2i, tint: Color) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var color: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(color.r * tint.r, color.g * tint.g, color.b * tint.b, color.a))

# ========== 脚本编辑器脚本列表显示 ==========
#
# 脚本编辑器左侧的脚本列表（"筛选脚本"面板）里的条目提示文本即脚本的 res:// 路径，
# 据此取别名并按文件系统面板同样的规则显示（合并图标 + 原本名字置灰）。
# 该列表会被编辑器高频整体重建且没有"列表已更新"信号，重建会把条目换回编辑器
# 原图标，所以显示是"幂等校正"：每次校正时按条目当前状态决定应用还是恢复，
# 不依赖历史状态。重建的补位时机（按编辑器重建的触发来源分类，缺一个就会在那种
# 操作下闪一次）：
# - 节点增删（运行游戏、增删节点）：断开编辑器对 tree_changed 的响应（见
#   _disable_editor_script_list_rebuild），从源头消掉这类重建；
# - 自动保存定时器：编辑器 save_all_scripts() 结尾是无条件重建，在同一 timeout
#   上后连一次（见 _connect_editor_autosave_repair）；
# - 点击/选中脚本条目：在 item_selected / item_clicked 上后连一次，
#   同步 + 延迟各补一次（见 _repair_script_list_now）；
# - 其余输入阶段触发的重建（敲"筛选脚本"、快捷键切脚本、菜单操作、保存、开关页签、
#   文件系统变动等）：SceneTree.process_frame 补一次，位于输入之后、容器延迟重排
#   与绘制之前，保证这一帧的排布与内容都已是别名版；
# - 最后兜底：每帧绘制前（RenderingServer.frame_pre_draw）再校正一次，
#   任何漏网的重建都不会影响画出来的结果；
# - 别名数据变化 / 文件系统变化：由 _refresh_display 顺带校正。

## 断开编辑器对 SceneTree.tree_changed 的响应。编辑器在该信号里延迟重建整套脚本
## 列表，而节点增删极其频繁（运行游戏时逐帧触发），重建会不断把别名图标换回去。
## 断开后由本插件接管该列表的显示；插件退出时在 _restore_editor_script_list_rebuild 恢复。
func _disable_editor_script_list_rebuild() -> void:
	var editor: ScriptEditor = EditorInterface.get_script_editor()
	for connection: Dictionary in get_tree().tree_changed.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == editor:
			_editor_tree_changed_callback = callback
			get_tree().tree_changed.disconnect(callback)

## 恢复编辑器对 SceneTree.tree_changed 的响应（插件卸载/禁用时调用）
func _restore_editor_script_list_rebuild() -> void:
	if not _editor_tree_changed_callback.is_valid():
		return
	if not get_tree().tree_changed.is_connected(_editor_tree_changed_callback):
		get_tree().tree_changed.connect(_editor_tree_changed_callback)
	_editor_tree_changed_callback = Callable()

## 编辑器的内部自动保存定时器到点就执行 save_all_scripts()，而该函数结尾是**无条件**的
## 整表重建（与"脚本有没有改动"无关），所以只要开了自动保存，脚本列表每秒都会被重建。
## 这里在同一个 timeout 信号上再连一次：编辑器回调先执行（它先连接），本插件紧随其后
## 同步补回别名，同一帧内完成，不会有中间态。
func _connect_editor_autosave_repair() -> void:
	var editor: ScriptEditor = EditorInterface.get_script_editor()
	for node: Node in editor.find_children("*", "Timer", true, false):
		var timer: Timer = node as Timer
		if not timer.timeout.is_connected(_update_script_list_display):
			timer.timeout.connect(_update_script_list_display)

## 校正脚本列表的别名显示（每帧绘制前、条目被重建后、别名或文件系统变化时调用）
func _update_script_list_display() -> void:
	if _alias_map.is_empty():
		return
	var list: ItemList = _find_script_list()
	if list == null or not list.is_visible_in_tree():
		return
	var 有条目变化: bool = false
	for i: int in range(list.item_count):
		有条目变化 = _update_script_list_item(list, i) or 有条目变化
	if 有条目变化:
		# 条目矩形（以及滚动范围）只在 ItemList::force_update_list_size() 里重算：它在
		# NOTIFICATION_DRAW 里会被调用，也会被无障碍更新流程调用——后者会在编辑器重建
		# 之后抢先用"编辑器原图标"算一次，缓存的矩形就偏小。我们补回宽图标后必须立刻
		# 强制重算一次，否则那一帧列表会矮几像素（表现为闪一下），要等下一帧才恢复。
		list.force_update_list_size()

## 校正单个脚本列表条目；返回条目图标是否发生了变化
func _update_script_list_item(list: ItemList, index: int) -> bool:
	var path: String = list.get_item_tooltip(index)
	# 未保存的脚本、帮助页面的提示文本不是路径，直接跳过
	if not path.begins_with("res://"):
		return false
	var alias: String = _alias_map.get(path, "")
	if alias.is_empty():
		return _restore_script_list_item(list, index, path)
	# 条目原始着色（@tool 脚本为强调色）只在首次应用时备份：应用后条目着色被置白，
	# 之后只能以备份为准，否则重新校正时会丢失强调色
	if not _script_icon_backup.has(path):
		_script_icon_backup[path] = list.get_item_icon(index)
		_script_tint_backup[path] = list.get_item_icon_modulate(index)
	var icon: Texture2D = _get_combined_icon(path, alias, _script_tint_backup[path])
	if icon == null:
		return false
	# 合并图标（类型图标 + 别名文字）是宽图，脚本列表默认把图标限制成 class_icon_size
	# 的正方形并按比例缩小，别名文字会被压得看不清；清掉限制按原始尺寸绘制
	# （编辑器在主题变化时会重置该值，故每次校正都重新清）
	var 尺寸变化: bool = false
	if list.fixed_icon_size != Vector2i.ZERO:
		list.fixed_icon_size = Vector2i.ZERO
		尺寸变化 = true
	var 图标变化: bool = list.get_item_icon(index) != icon
	if 图标变化:
		list.set_item_icon(index, icon)
	# 着色已烘焙进合并图标里的类型图标部分，条目本身不再着色，避免别名文字被染色
	list.set_item_icon_modulate(index, Color.WHITE)
	# 原本名字置灰，突出别名标签
	list.set_item_custom_fg_color(index, _get_grayed_script_list_name_color(list))
	return 图标变化 or 尺寸变化

## 别名已删除时，把脚本列表条目恢复为编辑器原始的图标、着色与文字颜色；返回图标是否变化
func _restore_script_list_item(list: ItemList, index: int, path: String) -> bool:
	if not _script_icon_backup.has(path):
		return false
	var 图标变化: bool = list.get_item_icon(index) != _script_icon_backup[path]
	list.set_item_icon(index, _script_icon_backup[path])
	list.set_item_icon_modulate(index, _script_tint_backup[path])
	list.set_item_custom_fg_color(index, list.get_theme_color("font_color"))
	_script_icon_backup.erase(path)
	_script_tint_backup.erase(path)
	return 图标变化

## 脚本列表中原本名字的置灰色。取脚本列表自身的主题字体色，
## 兼容编辑器给它设置的主题变体（ItemListSecondary）
func _get_grayed_script_list_name_color(list: ItemList) -> Color:
	return list.get_theme_color("font_color").lerp(Color(0.5, 0.5, 0.5), 原名置灰程度)

## 查找脚本编辑器左侧的脚本列表（ItemList）并缓存。
## 脚本编辑器内部有三个 ItemList（脚本列表、成员概览、帮助概览），
## 只有脚本列表的条目提示文本是 res:// 路径，据此识别（列表为空时下次再找）
func _find_script_list() -> ItemList:
	if _script_list != null and is_instance_valid(_script_list):
		return _script_list
	var editor: ScriptEditor = EditorInterface.get_script_editor()
	if editor == null:
		return null
	var lists: Array[Node] = editor.find_children("*", "ItemList", true, false)
	for node: Node in lists:
		var list: ItemList = node as ItemList
		for i: int in range(list.item_count):
			if list.get_item_tooltip(i).begins_with("res://"):
				_script_list = list
				# 点击条目时编辑器会立刻重建列表，而容器的重排是延迟调用：补显示必须排进
				# 同一个延迟队列（编辑器先连、本插件后连），否则那一帧会拿重建后的旧尺寸/
				# 旧图标去排布与绘制，表现为"点一下闪一下"
				list.item_selected.connect(_on_script_list_item_selected)
				list.item_clicked.connect(_on_script_list_item_clicked)
				return list
	return null

## 脚本列表条目被选中：立刻补一次（覆盖编辑器同步重建）
func _on_script_list_item_selected(_index: int) -> void:
	_repair_script_list_now()

## 脚本列表条目被点击：同上（点击当前条目时不一定触发 item_selected）
func _on_script_list_item_clicked(_index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	_repair_script_list_now()

## 编辑器重建脚本列表后紧接着补回显示：先同步一次（编辑器若在这一步同步重建，
## 结果会赶在容器重排与绘制之前生效），再排一次延迟调用（编辑器若是延迟重建，
## 它会排在同一个延迟队列里、位于编辑器之后，同样赶在绘制之前）
func _repair_script_list_now() -> void:
	_update_script_list_display()
	_update_script_list_display.call_deferred()

# ========== 编辑器场景标签栏显示 ==========
#
# 编辑器顶部的场景标签栏（"游戏 → Game"那条，右侧带 "+"）标题就是场景名，编辑器在
# 打开/关闭/保存/切换/重命名场景时都会重设，所以同样是"每帧绘制前幂等校正"。
# 编辑器没有暴露场景标签栏的 API，只能按"页签与 get_open_scenes() 一一对应"识别；
# 原本标题不做推导（可能是根节点名），首次见到时记下来，编辑器重设时以编辑器为准。

## 校正场景标签栏的别名显示（每帧绘制前、别名变化时调用）
func _update_scene_tabs_display() -> void:
	if _alias_map.is_empty():
		return
	var 打开场景: PackedStringArray = EditorInterface.get_open_scenes()
	if 打开场景.is_empty():
		return
	if _scene_tabs == null or not is_instance_valid(_scene_tabs) or _scene_tabs.tab_count != 打开场景.size():
		if not _保证场景标签栏(打开场景):
			return
	for i: int in range(打开场景.size()):
		_update_scene_tab(i, 打开场景[i])

## 保证 _scene_tabs 可用；找到返回 true。
## 编辑器根控件树有几千个节点，find_children 全树查找一次不便宜，而本校正每帧要跑两遍
## （process_frame + frame_pre_draw），所以「同一批打开场景找不到」时不能每帧硬找：
## 限流到最多每秒重试一次。下面两种情况立刻重试、不受限流：
##   - 打开场景变了（签名不同）：标签栏可能才刚被建出来；
##   - 缓存的控件被编辑器重排销毁了（引用失效）：得马上重新认一个。
func _保证场景标签栏(打开场景: PackedStringArray) -> bool:
	var 控件被销毁: bool = _scene_tabs != null and not is_instance_valid(_scene_tabs)
	var 签名: String = ",".join(打开场景)
	if not 控件被销毁 and 签名 == _场景标签查找签名 \
			and Engine.get_process_frames() < _场景标签重试帧:
		return false
	_场景标签查找签名 = 签名
	_场景标签重试帧 = Engine.get_process_frames() + 场景标签重试间隔帧
	_scene_tabs = _find_scene_tabs(打开场景)
	return _scene_tabs != null

## 校正单个场景标签：有别名则显示"别名 原名"，无别名则还原原名
func _update_scene_tab(index: int, path: String) -> void:
	# 未保存的新场景路径为空，跳过
	if path.is_empty():
		return
	var 当前标题: String = _scene_tabs.get_tab_title(index)
	var alias: String = _alias_map.get(path, "")
	var 原本标题: String = _scene_tab_titles.get(path, "")
	if 原本标题.is_empty():
		原本标题 = 当前标题
		_scene_tab_titles[path] = 原本标题
	# 编辑器重设了标题（场景改名等）时以编辑器给的为准，避免一直按旧名显示
	elif 当前标题 != 期望标题(原本标题, alias) and not 当前标题.contains(原本标题):
		原本标题 = 当前标题
		_scene_tab_titles[path] = 原本标题
	var 期望: String = 期望标题(原本标题, alias)
	if 当前标题 != 期望:
		_scene_tabs.set_tab_title(index, 期望)

## 标签栏上要显示的标题（无别名时就是原名）
func 期望标题(原本标题: String, alias: String) -> String:
	if alias.is_empty():
		return 原本标题
	return "%s %s" % [alias, 原本标题]

## 查找场景标签栏：编辑器里 TabBar 很多（底部面板、各类停靠页签等），
## 只有场景标签栏的页签与 get_open_scenes() 一一对应（标题中含有场景文件名）
func _find_scene_tabs(打开场景: PackedStringArray) -> TabBar:
	var 基控件: Control = EditorInterface.get_base_control()
	if 基控件 == null:
		return null
	for node: Node in 基控件.find_children("*", "TabBar", true, false):
		var tabs: TabBar = node as TabBar
		if tabs.tab_count != 打开场景.size():
			continue
		var 匹配: bool = true
		for i: int in range(打开场景.size()):
			var 场景名: String = 打开场景[i].get_file().get_basename()
			if 场景名.is_empty() or not tabs.get_tab_title(i).contains(场景名):
				匹配 = false
				break
		if 匹配:
			return tabs
	return null

# ========== 别名文本渲染 ==========

## 别名在面板中显示的实际文本（前后缀可分别配置）
func _get_display_text(alias: String) -> String:
	return 显示前缀 + alias + 显示后缀

## 取别名的文字图片：内存缓存 → 磁盘缓存。磁盘缓存命中就直接用，一张都不渲染。
## 懒加载是「启动不卡」的关键：别名可能上百个，但只有真正显示到的才需要读进来。
func _取别名图片(display: String) -> Texture2D:
	if _icon_cache.has(display):
		return _icon_cache[display]
	var cached: Texture2D = _load_cached_texture(display)
	if cached != null:
		_icon_cache[display] = cached
	return cached

## 别名文字图片连磁盘缓存里都没有时排队等渲染。同一批只排一次延迟处理，
## 且延迟到本帧的显示校正跑完之后，避免边遍历边渲染。
func _排队渲染(display: String) -> void:
	_待渲染[display] = true
	if _渲染排队中:
		return
	_渲染排队中 = true
	_冲洗待渲染.call_deferred()

## 把排队等渲染的别名一次性渲染出来（渲染完成后自动补刷新显示）
func _冲洗待渲染() -> void:
	_渲染排队中 = false
	if _待渲染.is_empty():
		return
	var 名单: Array[String] = []
	名单.assign(_待渲染.keys())
	_待渲染.clear()
	_render_alias_textures(名单)

## 渲染一批别名文本图片：多个别名各建一个 SubViewport，统一等待两帧后一次性读取，
## 避免逐个串行等待。渲染结果写进内存缓存与磁盘缓存（脚本重载/编辑器重启后直接用缓存）。
func _render_alias_textures(名单: Array[String]) -> void:
	var viewports: Array[SubViewport] = []
	for display: String in 名单:
		viewports.append(_create_alias_viewport(display))
	# 等待至少两帧，确保所有 SubViewport 完成一次渲染
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for i: int in range(名单.size()):
		var display: String = 名单[i]
		var viewport: SubViewport = viewports[i]
		if viewport == null or not is_instance_valid(viewport):
			continue
		var img: Image = viewport.get_texture().get_image()
		var tex: ImageTexture = ImageTexture.create_from_image(img)
		viewport.queue_free()
		_icon_cache[display] = tex
		# 保存到磁盘缓存，脚本重载/编辑器重启后无需重新渲染
		DirAccess.make_dir_recursive_absolute(缓存目录)
		img.save_png(_get_cache_path(display))
	_refresh_display()

## 计算别名纹理的缓存文件路径（key 包含渲染参数，参数变化后自动失效重渲染）
func _get_cache_path(text: String) -> String:
	var key: String = "%s_%d_%d_%d_%s_%d" % [
			text,
			别名基准字号,
			int(EditorInterface.get_editor_scale() * 10),
			int(别名加粗 * 100),
			别名颜色.to_html(false),
			别名留白]
	return 缓存目录 + "/" + key.sha256_text().substr(0, 16) + ".png"

## 从磁盘缓存加载别名纹理，没有缓存时返回 null
func _load_cached_texture(text: String) -> Texture2D:
	var path: String = _get_cache_path(text)
	if not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

## 创建用于渲染别名文本的 SubViewport（透明背景，含加粗 Label）。
## 不等待渲染完成，由调用方统一等待两帧后读取纹理。
func _create_alias_viewport(display: String) -> SubViewport:
	if not is_inside_tree():
		return null
	var font: Font = _get_alias_font()
	# 字号与内边距都随编辑器缩放比例放大，保证在任意缩放下的可读性
	var 字号: int = int(别名基准字号 * EditorInterface.get_editor_scale())
	var pad: int = int(别名留白 * EditorInterface.get_editor_scale())
	var text_size: Vector2 = font.get_string_size(display, HORIZONTAL_ALIGNMENT_LEFT, -1, 字号)
	var viewport: SubViewport = SubViewport.new()
	viewport.transparent_bg = true
	# 加粗（embolden）会使字形向外扩展，右侧多留出空白，避免末尾的右括号 ] 贴边甚至被裁剪
	viewport.size = Vector2i(int(text_size.x) + pad * 3, int(text_size.y) + pad * 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var label: Label = Label.new()
	label.text = display
	label.add_theme_font_size_override("font_size", 字号)
	label.add_theme_color_override("font_color", 别名颜色)
	label.add_theme_font_override("font", font)
	# 垂直居中，避免文本在图片中偏上或偏下
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(label)
	add_child(viewport)
	return viewport

## 获取可渲染中文的字体（编辑器主题默认字体的加粗变体）
func _get_alias_font() -> Font:
	if _alias_font == null:
		var base: Font = EditorInterface.get_editor_theme().default_font
		if base == null:
			base = ThemeDB.fallback_font
		var variation: FontVariation = FontVariation.new()
		variation.base_font = base
		variation.variation_embolden = 别名加粗
		_alias_font = variation
	return _alias_font

# ========== 颜色与图标 ==========

## 原本名字的置灰色（基于主题默认文字色向灰色混合，深浅主题自适应）
func _get_grayed_name_color() -> Color:
	var theme: Theme = EditorInterface.get_editor_theme()
	var base: Color = theme.get_color("font_color", "Tree")
	return base.lerp(Color(0.5, 0.5, 0.5), 原名置灰程度)

## 树视图中原本名字的默认颜色（用于恢复无别名文件）
func _get_default_name_color() -> Color:
	return EditorInterface.get_editor_theme().get_color("font_color", "Tree")

## 列表视图中原本名字的默认颜色（用于恢复无别名文件）
func _get_default_list_name_color() -> Color:
	return EditorInterface.get_editor_theme().get_color("font_color", "ItemList")

## 获取文件/文件夹对应的编辑器默认图标（无别名时用于恢复显示）。
## 文件类型查询结果缓存到 _file_type_cache，避免高频刷新时反复查文件系统；
## 图标本身每次用当前主题实时获取，保证深浅主题切换后颜色正确。
func _get_type_icon(path: String) -> Texture2D:
	var theme: Theme = EditorInterface.get_editor_theme()
	if path.ends_with("/"):
		if theme.has_icon("Folder", "EditorIcons"):
			return theme.get_icon("Folder", "EditorIcons")
		return null
	var type: String = ""
	if _file_type_cache.has(path):
		type = _file_type_cache[path]
	else:
		type = _file_system.get_file_type(path)
		_file_type_cache[path] = type
	if not type.is_empty() and theme.has_icon(type, "EditorIcons"):
		return theme.get_icon(type, "EditorIcons")
	if theme.has_icon("File", "EditorIcons"):
		return theme.get_icon("File", "EditorIcons")
	return null

# ========== 内部控件查找 ==========

func _find_tree() -> Tree:
	if _tree != null and is_instance_valid(_tree):
		return _tree
	_tree = _find_control("Tree") as Tree
	if _tree != null:
		# 树节点懒加载，展开时重新应用显示名
		_tree.item_collapsed.connect(_on_item_collapsed)
		# 在面板内按 Ctrl+Alt+A 设置别名
		_tree.gui_input.connect(_on_tree_gui_input)
	return _tree

func _find_item_list() -> ItemList:
	if _item_list != null and is_instance_valid(_item_list):
		return _item_list
	_item_list = _find_control("ItemList") as ItemList
	if _item_list != null:
		_item_list.gui_input.connect(_on_item_list_gui_input)
	return _item_list

## 在文件系统面板中查找指定类型的控件（兼容不同 Godot 版本的内部结构）
func _find_control(control_type: String) -> Control:
	if _dock == null:
		return null
	var nodes: Array[Node] = _dock.find_children("*", control_type, true, false)
	for node: Node in nodes:
		if node is Control:
			return node as Control
	return null

func _disconnect_tree() -> void:
	if _tree != null and is_instance_valid(_tree):
		if _tree.item_collapsed.is_connected(_on_item_collapsed):
			_tree.item_collapsed.disconnect(_on_item_collapsed)
		if _tree.gui_input.is_connected(_on_tree_gui_input):
			_tree.gui_input.disconnect(_on_tree_gui_input)
	_tree = null

func _disconnect_item_list() -> void:
	if _item_list != null and is_instance_valid(_item_list):
		if _item_list.gui_input.is_connected(_on_item_list_gui_input):
			_item_list.gui_input.disconnect(_on_item_list_gui_input)
	_item_list = null

func _disconnect_script_list() -> void:
	if _script_list != null and is_instance_valid(_script_list):
		if _script_list.item_selected.is_connected(_on_script_list_item_selected):
			_script_list.item_selected.disconnect(_on_script_list_item_selected)
		if _script_list.item_clicked.is_connected(_on_script_list_item_clicked):
			_script_list.item_clicked.disconnect(_on_script_list_item_clicked)
	_script_list = null

## 转换修正层 —— 把「Unity 语义被错误映射成 Godot 语义」的地方改回来。
##
## 目前只处理一类高频问题：**Unity 的 `Image.color` 只影响自己那一个 Graphic，
## 而转换器把它写成了 Godot 的 `modulate` —— modulate 会乘到整棵子树**。
## 于是同一个节点下的子按钮/子文字全被一起染色，颜色偏黑时看起来就是「一坨黑」：
##   * ReadyRoom 的 ChooseTeamPanel（黑 0.916）→ 里面红/蓝/无队伍三个按钮变成黑块；
##   * BattleUIMobile / RoleChoose* 的 LogRoot / ChatRoot_（黑 0.784）→ 战斗日志、聊天底下的内容被压黑；
##   * Lobby 的 MainPanel / HandBook（黑 1.0）、ReadyRoom 的 LeaderField（黑 0.766）…
## 全工程共 30 多个这样的节点，逐个改场景不现实（场景是脚本生成的，重新生成就没了），
## 所以统一在窗口入栈时扫一遍修正。
##
## 修正两件事：
##   1. 颜色从 `modulate` 搬到 `self_modulate`（只染自己，语义与 Unity 的 Image.color 一致）；
##   2. 原来那层「纯色底」（Unity 的 Image 用内置白图 1x1 + color 铺一块色块）在转换时
##      丢了贴图 —— Godot 的 TextureRect 没贴图就什么都不画。对**深色且不透明**的
##      底色补一张 1x1 白图，颜色才显示得出来（模态遮罩、日志底、面板底都属于这类）。
class_name ConversionFix
extends RefCounted

## 一个共享的 1x1 白图，供「纯色底」节点使用
static var _white_tex: ImageTexture = null


## 窗口入栈时统一跑一遍的所有转换修正
static func apply(root: Node) -> void:
	fix_modulate(root)
	fix_button_children(root)
	fix_toggle_marks(root)


## 递归修正一棵界面树（窗口实例化后调用一次即可）
static func fix_modulate(root: Node) -> void:
	if root == null:
		return
	for c in root.get_children():
		if c is CanvasItem:
			_fix_one(c as CanvasItem)
		fix_modulate(c)


## Unity 的点击是「射线打到谁，就沿父链冒泡给第一个能处理的」——
## 所以 Button 的子图片（Background / Checkmark / Label…）不会挡住按钮本身。
## Godot 不一样：鼠标拾取从最上层开始，子 Control 只要是默认的 STOP 就把点击吃掉，
## 父按钮永远收不到。转换后的界面里到处都是「满尺寸子图 + mouse_filter=0」，
## 表现就是**一整排单选项点了没反应**（CreateRoomUI 的游戏模式/人数/座位/扩展四排、
## ReadyRoom 的人数三选一…）。这里统一处理：BaseButton 的后代一律改成 IGNORE，
## 它们只是装饰；真的可交互的子控件（嵌套按钮/输入框/滚动条）保持原样。
static func fix_button_children(root: Node) -> void:
	if root == null:
		return
	for c in root.get_children():
		if c is BaseButton:
			_ignore_descendants(c)
		fix_button_children(c)


## 把一棵子树里「纯装饰」的 Control 全部改成 MOUSE_FILTER_IGNORE，让点击落到底下的按钮上。
## 与 fix_button_children 的区别：那个只收拾「按钮的后代」，而这里连普通子图一起收拾 ——
## 战斗里的玩家面板（PlayerOtherPanel）**自己就是那个按钮**，队色底/头像/名牌这些装饰图
## 是它的子节点而不是「某个按钮的子节点」，光靠 fix_button_children 盖不住，
## 于是点在大头像中间时按钮收不到点击（只有点面板边缘才算点到），
## 长按看角色技能、点头像选目标都会时灵时不灵。
static func ignore_decorations(root: Node) -> void:
	if root == null:
		return
	for c in root.get_children():
		if c is Control and not _is_interactive(c):
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_decorations(c)


static func _ignore_descendants(n: Node) -> void:
	for c in n.get_children():
		# 注意必须是 Control：Node2D 也是 CanvasItem，但没有 mouse_filter
		# （给 Node2D 赋值会报 Invalid assignment of property 'mouse_filter'）。
		if c is Control and not _is_interactive(c):
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_descendants(c)


static func _is_interactive(n: Node) -> bool:
	return n is BaseButton or n is LineEdit or n is TextEdit or n is Range \
		or n is ScrollContainer or n is TabBar


## Unity 的 Toggle 会把「选中标记」那张图（Toggle.graphic，转换后就是子节点 Checkmark）
## 随 isOn 显隐；转换后这张图是**常显**的 —— 于是每个选项看起来都被选中了
## （CreateRoomUI 四排单选项全红就是这个原因：Checkmark 与 Background 用同一张贴图，
##  Checkmark 额外加了 modulate=(1,0,0)）。
## 这里把 Checkmark* 的可见性绑到 button_pressed 上，并跟随之后的 toggled 变化。
static func fix_toggle_marks(root: Node) -> void:
	if root == null:
		return
	for c in root.get_children():
		if c is BaseButton and (c as BaseButton).toggle_mode:
			_bind_marks(c as BaseButton)
		fix_toggle_marks(c)


static func _bind_marks(b: BaseButton) -> void:
	for m in b.find_children("Checkmark*", "", true, false):
		if not (m is CanvasItem):
			continue
		var mark := m as CanvasItem
		mark.visible = b.button_pressed
		# 用 lambda 捕获那张图（不捕获 self，避免 RefCounted 引用环）；
		# 连接挂在按钮自己身上，按钮释放时一起回收。
		b.toggled.connect(func(on: bool) -> void:
			if is_instance_valid(mark):
				mark.visible = on)


## 把某个开关的选中标记同步到它当前状态。
## 注意：用 `set_pressed_no_signal()` 静默改状态时不会发 toggled，
## 上面的绑定收不到通知 —— 互斥逻辑里取消其他选项后要显式调一次这个。
static func sync_marks(b: BaseButton) -> void:
	if b == null or not is_instance_valid(b):
		return
	for m in b.find_children("Checkmark*", "", true, false):
		if m is CanvasItem:
			(m as CanvasItem).visible = b.button_pressed


static func _fix_one(ci: CanvasItem) -> void:
	var m := ci.modulate
	if m.is_equal_approx(Color.WHITE):
		return
	# 「没贴图的 TextureRect」自己什么都画不出来，那个颜色只可能漏给子节点 ——
	# 所以无论当前有没有子节点，都该按 Unity 语义搬到 self_modulate。
	# （典型例子：RoleChoose31 的 Panel 是 a=0 的容器，英雄卡是运行时才 add_child 进去的，
	#  若只在「有子节点」时才处理，就会把三张卡一起染成全透明。）
	var no_tex := ci is TextureRect and (ci as TextureRect).texture == null
	# 有子节点的：modulate 会波及子节点，必须搬走
	if ci.get_child_count() == 0 and not no_tex:
		return
	ci.modulate = Color.WHITE
	ci.self_modulate = m
	# 深色不透明的「纯色底」：补 1x1 白图，否则这块底色根本画不出来
	if no_tex and m.a > 0.5 and m.v < 0.5:
		(ci as TextureRect).texture = white_texture()


static func white_texture() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

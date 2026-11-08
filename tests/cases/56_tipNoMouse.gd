extends 自检用例
## 用例 56：悬停说明框整块不吃鼠标。
##
## 说明框只负责「看」：根节点、底板、富文本、分块里的标题 / 技能、卡面预览……
## 整棵子树的 mouse_filter 必须全是 IGNORE、focus_mode 必须全是 NONE。否则提示框盖到
## 头像 / 技能按钮上时，它会把鼠标信号截走：下面的控件被判成「离开」、点击也点不到，
## 提示还可能一闪就没；里面的按钮还会被 Tab 聚焦 / 回车触发。
## 这里把整段 / 分块 / 短提示 / 自定义内容四条路都走一遍。

const 整段角色: int = 1      # 风之剑圣：没有专属卡牌，走整段富文本
const 分组角色: int = 4      # 封印师：走专属卡牌分块（SkillGroupBox 预制体）


func _init() -> void:
	名称 = "悬停说明不吃鼠标"


func 跑() -> void:
	await 等帧(1)
	var 宿主: Control = Control.new()
	宿主.size = Vector2(1280, 720)
	add_child(宿主)
	var 提示框: 说明提示框 = load("res://scenes/prefabs/ui/TipBox.tscn").instantiate() as 说明提示框
	检(提示框 != null, "TipBox.tscn 加载失败")
	if 提示框 == null:
		宿主.queue_free()
		return
	宿主.add_child(提示框)
	await 等帧(1)

	# ---- 整段角色说明 ----
	提示框.显示角色说明(整段角色, Rect2(100, 100, 64, 64))
	await 等帧(4)
	_检查(提示框, "整段角色说明")

	# ---- 分块角色说明（专属卡牌分组框） ----
	提示框.显示角色说明(分组角色, Rect2(100, 100, 64, 64))
	await 等帧(6)
	_检查(提示框, "分块角色说明")
	var 块: Node = 提示框.块容器
	检(块 != null, "分块角色说明没有建出块容器")
	if 块 != null:
		var 分组框: 专属卡牌分组框 = _找分组框(块)
		检(分组框 != null, "分块角色说明里没有分组框")
		if 分组框 != null and 分组框.标题 != null:
			检(分组框.标题.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"分组标题 Label 还在吃鼠标（mouse_filter=%d）" % 分组框.标题.mouse_filter)

	# ---- 短提示（技能按钮 / 状态图标那种一句话） ----
	提示框.显示("一句话短提示", Rect2(100, 100, 64, 64), 300.0, 16)
	await 等帧(2)
	_检查(提示框, "短提示")

	# ---- 自定义内容（卡面预览等）：内容节点自己可能带 Button，也得整棵忽略 ----
	var 按钮: Button = Button.new()
	按钮.text = "内容里的按钮"
	按钮.custom_minimum_size = Vector2(240, 90)
	提示框.显示内容(按钮, Rect2(100, 100, 240, 90))
	await 等帧(3)
	检(按钮.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"自定义内容根节点还在吃鼠标（mouse_filter=%d）" % 按钮.mouse_filter)
	_检查(提示框, "自定义内容")

	提示框.queue_free()
	宿主.queue_free()


## 扫整棵树：任何一个 Control 不是 IGNORE、或者还能被键盘聚焦，都记失败
func _检查(提示框: 说明提示框, 场景名: String) -> void:
	var 吃鼠标: Control = _找吃鼠标(提示框)
	检(吃鼠标 == null, "%s 里还有控件在吃鼠标：%s（mouse_filter=%d）" % [
		场景名, 吃鼠标.get_path() if 吃鼠标 != null else "", 吃鼠标.mouse_filter if 吃鼠标 != null else -1])
	var 可聚焦: Control = _找可聚焦(提示框)
	检(可聚焦 == null, "%s 里还有控件能被键盘聚焦 / 回车触发：%s（focus_mode=%d）" % [
		场景名, 可聚焦.get_path() if 可聚焦 != null else "", 可聚焦.focus_mode if 可聚焦 != null else -1])


## 返回第一个 mouse_filter 不是 IGNORE 的 Control；全都忽略返回 null
func _找吃鼠标(节点: Node) -> Control:
	if 节点 is Control and (节点 as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return 节点 as Control
	for 子: Node in 节点.get_children():
		var 结果: Control = _找吃鼠标(子)
		if 结果 != null:
			return 结果
	return null


## 返回第一个能被键盘聚焦的 Control；全都不可聚焦返回 null
func _找可聚焦(节点: Node) -> Control:
	if 节点 is Control and (节点 as Control).focus_mode != Control.FOCUS_NONE:
		return 节点 as Control
	for 子: Node in 节点.get_children():
		var 结果: Control = _找可聚焦(子)
		if 结果 != null:
			return 结果
	return null


## 在块容器里找专属卡牌分组框（找不到返回 null）
func _找分组框(块: Node) -> 专属卡牌分组框:
	for 子: Node in 块.get_children():
		var 框: 专属卡牌分组框 = 子 as 专属卡牌分组框
		if 框 != null:
			return 框
	return null

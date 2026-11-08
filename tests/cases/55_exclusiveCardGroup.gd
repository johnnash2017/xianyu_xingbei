extends 自检用例
## 用例 55：专属卡牌分组框（SkillGroupBox 预制体）的标题与技能必须紧贴。
##
## 分组框现在整块是工程里的预制体（scenes/prefabs/ui/SkillGroupBox.tscn）：
## 外缩进 / 圆角描边面板 / 标题 Label / 技能容器都在场景里，间距由「内容」VBox 的
## separation 一个数决定。这里把结构钉死：
##  - 标题是独立的 Label（文本、字号对得上），不是塞在第一条技能文本里；
##  - 组内技能节点数 = 技能数；
##  - 标题和技能之间只有预制体里配置的那一个 separation，没有多出来的空行 / 隐藏节点；
##  - 每条技能的富文本不能以 [indent] 开头：Godot 的 [indent] 出现在富文本最开头会先
##    另起一行（等于凭空一条空行，这正是标题下面那截空隙的真因）；缩进改由
##    SkillGroupItem 的 normal StyleBox content_margin_left 提供；
##  - 分组框高度 = 内容高度 + 面板内边距。
## 只要有人再往标题和技能之间插一个节点或空行，这个用例就会失败。

## 封印师（4）：专属技【五系束缚】配了专属卡牌，组里 1 条技能
const 封印师: int = 4
## 结界师（82）：一个「绝界」组里 3 条技能（验证多技能组仍是一条技能一个节点）
const 结界师: int = 82
## 风之剑圣（1）：没配专属卡牌，应继续走整段说明（不受分组逻辑影响）
const 无分组角色: int = 1


func _init() -> void:
	名称 = "专属卡牌分组框标题紧贴技能"


func 跑() -> void:
	await 等帧(1)

	# ---- 数据侧 ----
	var 封印块: Array = 角色技能提示.悬浮提示块(封印师)
	var 封印组: Dictionary = _找组(封印块, "五系束缚")
	检(not 封印组.is_empty(), "封印师应有一组「五系束缚」专属卡牌技能")
	检((封印组.get("技能", []) as Array).size() == 1, "「五系束缚」组里应只有 1 条技能")
	检(角色技能提示.悬浮提示块(无分组角色).is_empty(),
		"没配专属卡牌的角色不该走分块版（否则整段说明的行为会变）")

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

	# ---- 封印师：单技能组 ----
	提示框.显示角色说明(封印师, Rect2(100, 100, 64, 64))
	await 等帧(5)
	var 分组框: 专属卡牌分组框 = _找分组框(提示框, "五系束缚")
	检(分组框 != null, "封印师的角色说明里没有「五系束缚」分组框（SkillGroupBox 预制体没装上？）")
	if 分组框 != null:
		_检查分组框(分组框, "五系束缚", 1)

	# ---- 结界师：多技能组仍是一条技能一个节点 ----
	提示框.显示角色说明(结界师, Rect2(100, 100, 64, 64))
	await 等帧(5)
	var 多技能框: 专属卡牌分组框 = _找分组框(提示框, "绝界")
	检(多技能框 != null, "结界师的角色说明里没有「绝界」分组框")
	if 多技能框 != null:
		_检查分组框(多技能框, "绝界", 3)

	提示框.queue_free()
	宿主.queue_free()


## 检查一个分组框：标题文本、技能节点数、标题与技能之间没有多余空隙、框高与内容一致
func _检查分组框(分组框: 专属卡牌分组框, 组名: String, 技能数: int) -> void:
	检(分组框.标题 != null and 分组框.技能 != null, "SkillGroupBox 的标题 / 技能容器没有绑定")
	if 分组框.标题 == null or 分组框.技能 == null:
		return
	检(分组框.标题.text == 组名, "分组框标题不对：应为「%s」，实际「%s」" % [组名, 分组框.标题.text])
	检(分组框.标题.get_theme_font_size("font_size") >= 12,
		"分组标题字号太小：%d（字号在 SkillGroupBox.tscn 的标题 Label 上改）" % 分组框.标题.get_theme_font_size("font_size"))
	检(分组框.技能.get_child_count() == 技能数,
		"组内技能节点数不对：应为 %d，实际 %d" % [技能数, 分组框.技能.get_child_count()])

	# 标题是 Label：高度就是字体行高，不能是两行 / 多出来的空行
	检(分组框.标题 is Label, "分组标题应是一个 Label（不再是塞进技能文本的 BBCode 首行）")
	检(absf(分组框.标题.size.y - 分组框.标题.get_combined_minimum_size().y) <= 0.5,
		"标题 Label 高度应等于字体行高（多出来就是空行）：节点 %.1f / 最小 %.1f" % [
			分组框.标题.size.y, 分组框.标题.get_combined_minimum_size().y])

	# 标题和技能之间只允许有「内容」VBox 的 separation 这一个间距
	var 内容: VBoxContainer = 分组框.标题.get_parent() as VBoxContainer
	if 内容 != null:
		var 间距: float = float(内容.get_theme_constant("separation"))
		检(absf(分组框.技能.position.y - (分组框.标题.position.y + 分组框.标题.size.y + 间距)) <= 0.5,
			"标题和技能之间除了预制体的 separation（%.1f）还有别的空隙：标题底 %.1f，技能顶 %.1f" % [
				间距, 分组框.标题.position.y + 分组框.标题.size.y, 分组框.技能.position.y])
	else:
		检(false, "分组标题的父节点不是 VBoxContainer")

	# 面板高度 = 内容 + 面板内边距（不能多出标题那一行）
	var 边框: PanelContainer = 分组框.边框
	if 边框 != null and 内容 != null:
		var 样式: StyleBox = 边框.get_theme_stylebox("panel")
		检(absf(边框.size.y - (内容.size.y + 样式.get_minimum_size().y)) <= 1.0,
			"分组框高度应正好是内容 + 内边距：框 %.1f / 内容 %.1f + 边距 %.1f" % [
				边框.size.y, 内容.size.y, 样式.get_minimum_size().y])
	else:
		检(false, "分组框的边框 / 内容节点没有绑定")

	# 每条技能都是一个独立 RichTextLabel，且不带分组标题（标题是上面那个独立 Label）
	for i: int in range(分组框.技能.get_child_count()):
		var 条: RichTextLabel = 分组框.技能.get_child(i) as RichTextLabel
		检(条 != null, "第 %d 条技能不是 RichTextLabel" % (i + 1))
		if 条 != null:
			# 真凶：上色() 给正文套的 [indent] 出现在富文本最开头时会先另起一行（等于空一行）。
			# 分组里每条技能都是独立富文本，所以这里改用 StyleBox 的 content_margin_left 缩进。
			检(not 条.text.contains("[indent]"),
				"第 %d 条技能文本还带 [indent]：富文本开头会被它顶出一条空行（标题下面那截空隙的真因）" % (i + 1))
			var 样式: StyleBox = 条.get_theme_stylebox("normal")
			检(样式 != null and 样式.get_margin(SIDE_LEFT) >= 16.0,
				"第 %d 条技能的左缩进应由 normal StyleBox 的 content_margin_left 提供" % (i + 1))


## 从悬浮提示块里找某一组（找不到返回空字典）
func _找组(块: Array, 组名: String) -> Dictionary:
	for 项: Variant in 块:
		var d: Dictionary = 项
		if str(d.get("分组", "")) == 组名:
			return d
	return {}


## 从提示框的分块树里找标题＝组名的分组框（块容器 → 专属卡牌分组框）
func _找分组框(提示框: 说明提示框, 组名: String) -> 专属卡牌分组框:
	var 块容器: VBoxContainer = 提示框.块容器
	if 块容器 == null:
		return null
	for 子: Node in 块容器.get_children():
		var 框: 专属卡牌分组框 = 子 as 专属卡牌分组框
		if 框 != null and 框.标题 != null and 框.标题.text == 组名:
			return 框
	return null

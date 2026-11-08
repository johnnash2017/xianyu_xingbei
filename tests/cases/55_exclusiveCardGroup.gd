extends 自检用例
## 用例 55：专属卡牌分组框的「标题 → 第一条技能」必须是紧贴的。
##
## 这一格以前反复出问题：标题单独一个 RichTextLabel 时，标签按整行行高占位，
## 标题文字下面总会空出一大截（字体行高 > 字形高度那一截）。
## 现在标题直接写成第一条技能的首行（同一个富文本、只隔一个普通换行），
## 这里把结构钉死：组内节点数 = 技能数、标题在第一条技能文本开头、
## 技能节点高度 = 内容高度、分组框高度 = 内容 + 内边距。
## 只要有人再把标题拆回独立标签，这个用例就会失败。

## 封印师（4）：专属技【五系束缚】配了专属卡牌，组里 1 条技能
const 封印师: int = 4
## 结界师（82）：一个「绝界」组里 3 条技能（验证多技能组仍是一条技能一个节点）
const 结界师: int = 82
## 风之剑圣（1）：没配专属卡牌，应继续走整段说明（不受分组逻辑影响）
const 无分组角色: int = 1


func _init() -> void:
	名称 = "专属卡牌分组标题紧贴技能"


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
	var 标题号: int = maxi(1, int(round(
		float(角色技能提示.提示框标题字号) * 说明提示框.角色说明字号缩放 * 0.75)))

	# ---- 封印师：单技能组 ----
	提示框.显示角色说明(封印师, Rect2(100, 100, 64, 64))
	await 等帧(5)
	var 竖排: VBoxContainer = _找分组竖排(提示框, "五系束缚")
	检(竖排 != null, "封印师的角色说明里没有「五系束缚」分组面板")
	if 竖排 != null:
		检(竖排.get_child_count() == 1,
			"组内节点数应等于技能数（标题不许再单独占一个节点）：实际 %d 个" % 竖排.get_child_count())
		var 首条: RichTextLabel = 竖排.get_child(0) as RichTextLabel
		检(首条 != null, "分组里第一条技能不是 RichTextLabel")
		if 首条 != null:
			var 期望标题: String = "[font_size=%d]五系束缚[/font_size]\n" % 标题号
			检(首条.text.begins_with(期望标题),
				"分组标题应作为第一条技能的首行（只隔一个换行）：文本开头是 %s" % 首条.text.substr(0, 48))
			检(absf(首条.size.y - 首条.get_content_height()) <= 1.0,
				"技能节点高度应等于内容高度，多出来的就是标题下那截空隙：节点 %.1f / 内容 %.1f" % [
					首条.size.y, 首条.get_content_height()])
		var 面板: PanelContainer = 竖排.get_parent() as PanelContainer
		if 面板 != null:
			var 样式: StyleBox = 面板.get_theme_stylebox("panel")
			检(absf(面板.size.y - (竖排.size.y + 样式.get_minimum_size().y)) <= 1.0,
				"分组框高度应正好是内容 + 内边距，不能多出标题那一行：框 %.1f / 内容 %.1f + 边距 %.1f" % [
					面板.size.y, 竖排.size.y, 样式.get_minimum_size().y])
		else:
			检(false, "分组竖排的父节点不是 PanelContainer")

	# ---- 结界师：多技能组仍是一条技能一个节点 ----
	提示框.显示角色说明(结界师, Rect2(100, 100, 64, 64))
	await 等帧(5)
	var 多技能竖排: VBoxContainer = _找分组竖排(提示框, "绝界")
	检(多技能竖排 != null, "结界师的角色说明里没有「绝界」分组面板")
	if 多技能竖排 != null:
		检(多技能竖排.get_child_count() == 3,
			"「绝界」组里 3 条技能应各占一个节点：实际 %d 个" % 多技能竖排.get_child_count())
		var 首条: RichTextLabel = 多技能竖排.get_child(0) as RichTextLabel
		if 首条 != null:
			var 期望标题: String = "[font_size=%d]绝界[/font_size]\n" % 标题号
			检(首条.text.begins_with(期望标题),
				"多技能组的标题也应写在第一条技能的首行：文本开头是 %s" % 首条.text.substr(0, 48))
		for i: int in range(1, 多技能竖排.get_child_count()):
			var 其余: RichTextLabel = 多技能竖排.get_child(i) as RichTextLabel
			if 其余 != null:
				检(not 其余.text.begins_with("[font_size=%d]绝界" % 标题号),
					"第 %d 条技能不该再重复分组标题" % (i + 1))

	提示框.queue_free()
	宿主.queue_free()


## 从悬浮提示块里找某一组（找不到返回空字典）
func _找组(块: Array, 组名: String) -> Dictionary:
	for 项: Variant in 块:
		var d: Dictionary = 项
		if str(d.get("分组", "")) == 组名:
			return d
	return {}


## 在提示框的分块树里找「标题＝组名」的那个分组竖排（MarginContainer → PanelContainer → VBox）
func _找分组竖排(提示框: 说明提示框, 组名: String) -> VBoxContainer:
	var 块容器: VBoxContainer = 提示框.块容器
	if 块容器 == null:
		return null
	var 前缀: String = "[font_size="
	for 边距: Node in 块容器.get_children():
		if not (边距 is MarginContainer):
			continue
		for 面板: Node in 边距.get_children():
			if not (面板 is PanelContainer):
				continue
			for 竖排: Node in 面板.get_children():
				if not (竖排 is VBoxContainer):
					continue
				var 子们: Array = 竖排.get_children()
				if 子们.is_empty():
					continue
				var 首条: RichTextLabel = 子们[0] as RichTextLabel
				if 首条 != null and 首条.text.begins_with(前缀) and 首条.text.contains(组名 + "[/font_size]"):
					return 竖排
	return null

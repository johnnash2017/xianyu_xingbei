## 卡牌 UI（手牌 / 盖牌）—— 由参考工程的 AGrail.CardUI 解耦而来。
##
## 现在只做两件事：把一张 GCard 画到卡面上（含命格/元素小图标、发光可选框、选中框），
## 以及被左键点击时发 `点击` 信号。**数据与状态由容器塞进来**
## （scripts/ui/battle_mobile.gd），不再引用参考工程的 BattleData / MessageSystem。
##
## 节点引用一律 @export，在 res://scenes/prefabs/battlemobile/Card.tscn 里绑定。
extends Control

## 卡牌被点击（左键）—— 容器据此切换选中
signal 点击(卡牌号: int)

## 以下节点对应 Card.tscn 里的同名节点（card_face 画在 Root 这个 Button 的 icon 上）
@export var btn: Button
@export var txtSkill1: Label
@export var txtSkill2: Label
@export var propertyRoot: Control
@export var elementRoot: Control
@export var selectBorder: TextureRect
@export var canSelectBorder: TextureRect

## 这张卡（本工程的客户端卡牌视图）
var card: GCard = null
## 当前是否可用：可用的牌亮起并显示发光框，不可用的置灰且点不动
var isEnable: bool = false

## 卡图原始尺寸（assets/textures/card/*.png，267×400）
const CARD_ART_SIZE: Vector2 = Vector2(267.0, 400.0)
## 发光框贴图尺寸（b02_selected_card.png / b02_selected_card_y.png）
const GLOW_TEX_SIZE: Vector2 = Vector2(166.0, 230.0)
## 发光框贴图内侧那块透明窗口 —— 卡面该占的位置
const GLOW_WINDOW_SIZE: Vector2 = Vector2(126.0, 190.0)
## 不可用（置灰）时的整体压暗色
const DISABLED_TINT: Color = Color(0.5, 0.5, 0.5, 1.0)
## 「可选」发光框的换色着色器与默认色（与贴图同色：绿）。
## 贴图是纯绿，靠 modulate 变不出红色，弃牌时由容器调 设置发光色 换成红光。
const 发光框着色器: Shader = preload("res://scripts/effects/卡牌发光框.gdshader")
const 发光色_默认: Color = Color(0.0, 1.0, 0.024)
## 可选发光框的材质（每个卡牌自己一份，颜色互不影响）
var _发光材质: ShaderMaterial = null

## Card.tscn 里的装饰（命格图标 / 元素图标 / 技能名）都是**固定像素偏移**，
## 这套数值是按「设计卡面 126×190」（发光框贴图的透明窗口）标的。
## 卡面被放大或缩小（手牌 130×192、盖牌 100×150…）时这些装饰要同比例跟着走，
## 否则小卡上命格图标会跑到卡面外面去。
const DESIGN_FACE_SIZE: Vector2 = Vector2(126.0, 190.0)
## 设计尺寸下各装饰的数值（与 Card.tscn 的偏移、字号一一对应）
const DECOR_PROPERTY_HALF_W: float = 12.5
const DECOR_PROPERTY_TOP: float = 71.6
const DECOR_PROPERTY_BOTTOM: float = 96.6
const DECOR_ELEMENT_SIZE: float = 30.0
const DECOR_SKILL_W: float = 60.0
const DECOR_SKILL_H: float = 30.0
const DECOR_SKILL_FONT: int = 14


func _ready() -> void:
	# 卡面走 btn.icon：先清空各状态 stylebox（去掉默认主题的灰底/内容边距/焦点框），
	# 卡面才会铺满卡片矩形，也就正好落进发光框的窗口里（同参考脚本的做法）。
	if btn != null:
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 卡面/发光框这些装饰子图在转换时带着 mouse_filter=STOP，会把点击吃掉，统一放行
	ConversionFix.ignore_decorations(self)
	# 「可选」发光框挂换色材质（默认绿；弃牌时容器改成红）
	if canSelectBorder != null:
		_发光材质 = ShaderMaterial.new()
		_发光材质.shader = 发光框着色器
		_发光材质.set_shader_parameter("glow_color", 发光色_默认)
		canSelectBorder.material = _发光材质
	_fit_glow()
	_fit_decor()


func _notification(what: int) -> void:
	# 卡牌尺寸由手牌区/盖牌区决定，尺寸一变卡面就变，发光框与装饰都得跟着重算
	if what == NOTIFICATION_RESIZED:
		_fit_glow()
		_fit_decor()


# ============================================================
# 对外：塞数据 / 收点击
# ============================================================
## 设置这张卡显示什么，以及是否可用（可用=亮起并显示「可选中」发光框，不可用=整体压暗置灰）。
## 可置灰 = false 时即使不可用也保持原色（如只读查看自己的盖牌：不给点，但牌面要看得清）
func 设置卡牌(new_card: GCard, 可用: bool, 可置灰: bool = true) -> void:
	card = new_card
	isEnable = 可用
	# 置灰走 modulate：会一并压暗卡面、命格元素与发光框，整张牌看起来是一体的
	modulate = DISABLED_TINT if (可置灰 and not 可用) else Color.WHITE
	if selectBorder != null:
		selectBorder.visible = false
	if canSelectBorder != null:
		canSelectBorder.visible = 可用
	if new_card == null:
		return
	_画卡面(new_card)
	_画命格元素(new_card)
	_fit_decor()


## 设置「可选」发光框的颜色（默认绿；弃牌询问由容器改成红，和「打出」区分开）
func 设置发光色(色: Color) -> void:
	if _发光材质 != null:
		_发光材质.set_shader_parameter("glow_color", 色)


## 是否处于「已选中」（黄框）
func 设置选中(值: bool) -> void:
	if selectBorder != null:
		selectBorder.visible = 值


## 对应 C# public void OnCardClick()（由 Card.tscn 的 [connection] 调用，方法名逐字保留）
func OnCardClick() -> void:
	if card == null:
		return
	点击.emit(card.id)


# ============================================================
# 绘制
# ============================================================
func _画卡面(c: GCard) -> void:
	if btn != null:
		btn.icon = Art.card_face(c)
	# 卡面底部那两格：印这张牌带的技能名（照搬参照工程 CardUI 的 Skill1/Skill2）
	if txtSkill1 != null:
		txtSkill1.text = c.skill_names[0] if c.skill_names.size() >= 1 else ""
	if txtSkill2 != null:
		txtSkill2.text = c.skill_names[1] if c.skill_names.size() >= 2 else ""


## 命格（血/技/幻/咏/圣）与元素（earth/wind/water/fire/thunder）小图标：
## 预制体里各是一排同名子图，按卡牌数据把对应的那张显出来即可（光/暗没有图，都不显）
func _画命格元素(c: GCard) -> void:
	if propertyRoot != null:
		for n: Node in propertyRoot.get_children():
			if n is CanvasItem:
				(n as CanvasItem).visible = n.name == c.property
	if elementRoot != null:
		for n: Node in elementRoot.get_children():
			if n is CanvasItem:
				(n as CanvasItem).visible = n.name == c.element


## 让发光框贴合卡面。卡面尺寸 = 卡片矩形按卡图比例（267:400）等比缩放的结果
## （icon 是 expand_icon，只等比缩放），所以发光框按同一比例重算：窗口对准卡面，
## 外圈光晕按贴图里 20px 的边宽同步放大。
func _fit_glow() -> void:
	if btn == null:
		return
	if canSelectBorder == null and selectBorder == null:
		return
	# 用自身的尺寸算（Root 是满锚点、跟卡片同尺寸）：NOTIFICATION_RESIZED 是卡片自己
	# 改尺寸时发出的，此时子节点的矩形可能还没刷新，读 btn.size 会拿到旧值。
	var s: float = minf(size.x / CARD_ART_SIZE.x, size.y / CARD_ART_SIZE.y)
	var face: Vector2 = CARD_ART_SIZE * s
	var glow: Vector2 = Vector2(
		face.x * GLOW_TEX_SIZE.x / GLOW_WINDOW_SIZE.x,
		face.y * GLOW_TEX_SIZE.y / GLOW_WINDOW_SIZE.y)
	for c: Control in [canSelectBorder, selectBorder]:
		if c == null:
			continue
		# 两个边框都锚在 Root 正中的，对称给 offsets 就能保持居中
		c.offset_left = -glow.x * 0.5
		c.offset_top = -glow.y * 0.5
		c.offset_right = glow.x * 0.5
		c.offset_bottom = glow.y * 0.5


## 命格图标 / 元素图标 / 技能名跟着卡面尺寸等比缩放（卡面相对 DESIGN_FACE_SIZE 的比例）。
## 这三样在预制体里都是写死的像素偏移，卡一变尺寸就错位（盖牌区缩到 100×150 时命格图标会掉到卡外）。
func _fit_decor() -> void:
	var s: float = minf(size.x / DESIGN_FACE_SIZE.x, size.y / DESIGN_FACE_SIZE.y)
	if s <= 0.0:
		s = 1.0
	if propertyRoot != null:
		var 半宽: float = DECOR_PROPERTY_HALF_W * s
		propertyRoot.offset_left = -半宽
		propertyRoot.offset_right = 半宽
		propertyRoot.offset_top = DECOR_PROPERTY_TOP * s
		propertyRoot.offset_bottom = DECOR_PROPERTY_BOTTOM * s
	if elementRoot != null:
		for n: Node in elementRoot.get_children():
			if n is Control:
				(n as Control).offset_right = DECOR_ELEMENT_SIZE * s
				(n as Control).offset_bottom = DECOR_ELEMENT_SIZE * s
	var 字宽: float = DECOR_SKILL_W * s
	var 字高: float = DECOR_SKILL_H * s
	var 字号: int = maxi(1, int(round(float(DECOR_SKILL_FONT) * s)))
	if txtSkill1 != null:
		txtSkill1.offset_right = 字宽
		txtSkill1.offset_top = -字高
		txtSkill1.add_theme_font_size_override("font_size", 字号)
	if txtSkill2 != null:
		txtSkill2.offset_left = -字宽
		txtSkill2.offset_top = -字高
		txtSkill2.add_theme_font_size_override("font_size", 字号)

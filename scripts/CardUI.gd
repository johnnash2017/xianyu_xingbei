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
## 发光框相对卡面的缩小比例：贴图从窗口边缘往外是「由暗到亮」的，窗口边上那 1~2 像素几乎全暗。
## 发光框现在画在卡面之下（Card.tscn 里排在卡面按钮前面），缩一点点让卡面正好盖住这段暗边，
## 光晕就贴着卡牌外缘亮起来（1.0＝不缩，但会露出一圈暗边）
const GLOW_SHRINK: float = 0.96
## 不可用（置灰）时的整体压暗色
const DISABLED_TINT: Color = Color(0.5, 0.5, 0.5, 1.0)
## 卡面底部两格技能名的字色：我的角色有这门技能＝亮绿黄，没有＝灰
const 技能字色_有: Color = Color("a9ff00")
const 技能字色_无: Color = Color("b1b1b1")
## 「可选」发光框的换色着色器与默认色（与贴图同色：绿）。
## 贴图是纯绿，靠 modulate 变不出红色，弃牌时由容器调 设置发光色 换成红光。
const 发光框着色器: Shader = preload("res://scripts/effects/cardGlowFrame.gdshader")
const 发光色_默认: Color = Color(0.0, 1.0, 0.024)
## 可选发光框的材质（每个卡牌自己一份，颜色互不影响）
var _发光材质: ShaderMaterial = null

## Card.tscn 里的装饰（命格图标 / 元素图标 / 技能名）都是**固定像素偏移**，是按
## 「设计卡面 126×190」（发光框贴图的透明窗口）标的。卡面被放大或缩小
## （手牌 130×192、盖牌 100×150…）时这些装饰要同比例跟着走，否则小卡上命格图标会跑到卡面外面去。
## 缩放用的基准**从预制体上现抓**（第一次缩放前抓一次存住），脚本里不另抄一份数字 ——
## 抄一份的话，预制体里调好的位置会被脚本按常量盖回去，等于白调。
const DESIGN_FACE_SIZE: Vector2 = Vector2(126.0, 190.0)
## 预制体上的装饰基准 {Control: Vector4(offset_left, top, right, bottom)}；技能名另有字号与描边基准
var _装饰基准: Dictionary = {}
var _基准字号: int = 0
var _基准描边: int = 0
var _基准已抓: bool = false


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


## 是否处于「已选中」（黄框）：选中时把绿框收掉，免得黄、绿两圈叠在一起分不清
func 设置选中(值: bool) -> void:
	if selectBorder != null:
		selectBorder.visible = 值
	if canSelectBorder != null:
		canSelectBorder.visible = isEnable and not 值


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
	# 卡面底部那两格：印这张牌带的技能名（照搬参照工程 CardUI 的 Skill1/Skill2）。
	# 字色看「我的角色有没有这门技能」：有＝亮绿黄，没有＝灰
	var 我的技能: Array[int] = _我的角色技能()
	if txtSkill1 != null:
		txtSkill1.text = c.skill_names[0] if c.skill_names.size() >= 1 else ""
		txtSkill1.add_theme_color_override("font_color", _技能字色(c, 0, 我的技能))
	if txtSkill2 != null:
		txtSkill2.text = c.skill_names[1] if c.skill_names.size() >= 2 else ""
		txtSkill2.add_theme_color_override("font_color", _技能字色(c, 1, 我的技能))


## 卡面第 位（0 / 1）格技能名的字色：这张牌的这门技能属于我的角色＝亮绿黄，否则灰。
## 没印技能的那格（技能数只有 1）无所谓，给灰。
func _技能字色(c: GCard, 位: int, 我的技能: Array[int]) -> Color:
	if 位 >= c.skill_ids.size():
		return 技能字色_无
	return 技能字色_有 if 我的技能.has(c.skill_ids[位]) else 技能字色_无


## 我的角色引用的技能号。还没定角色（非对局界面）就拿不到，返回空数组：这时两格都按灰显示。
func _我的角色技能() -> Array[int]:
	var 空: Array[int] = []
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.role_id <= 0:
		return 空
	return Data.role_skills(我.role_id)


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
		face.y * GLOW_TEX_SIZE.y / GLOW_WINDOW_SIZE.y) * GLOW_SHRINK
	for c: Control in [canSelectBorder, selectBorder]:
		if c == null:
			continue
		# 两个边框都锚在 Root 正中的，对称给 offsets 就能保持居中
		c.offset_left = -glow.x * 0.5
		c.offset_top = -glow.y * 0.5
		c.offset_right = glow.x * 0.5
		c.offset_bottom = glow.y * 0.5


## 节点当前的 offset_left / top / right / bottom（就是预制体里写的那四个数）
func _原偏移(c: Control) -> Vector4:
	return Vector4(c.offset_left, c.offset_top, c.offset_right, c.offset_bottom)


## 把预制体上写死的装饰偏移抓一份下来当基准。只抓第一次 —— 卡面尺寸会反复变，
## 基准必须一直是预制体上的设计值，否则会越缩放越小。
func _抓装饰基准() -> void:
	if _基准已抓:
		return
	_基准已抓 = true
	if propertyRoot != null:
		_装饰基准[propertyRoot] = _原偏移(propertyRoot)
	if elementRoot != null:
		for n: Node in elementRoot.get_children():
			if n is Control:
				_装饰基准[n] = _原偏移(n)
	if txtSkill1 != null:
		_装饰基准[txtSkill1] = _原偏移(txtSkill1)
		_基准字号 = txtSkill1.get_theme_font_size("font_size")
		_基准描边 = txtSkill1.get_theme_constant("outline_size")
	if txtSkill2 != null:
		_装饰基准[txtSkill2] = _原偏移(txtSkill2)


## 命格图标 / 元素图标 / 技能名跟着卡面尺寸等比缩放（卡面相对 DESIGN_FACE_SIZE 的比例）。
## 位置与尺寸都按预制体抓下来的基准乘比例 —— 想调位置就在 Card.tscn 里调，改完立刻生效。
func _fit_decor() -> void:
	_抓装饰基准()
	var s: float = minf(size.x / DESIGN_FACE_SIZE.x, size.y / DESIGN_FACE_SIZE.y)
	if s <= 0.0:
		s = 1.0
	for 键: Variant in _装饰基准:
		var c: Control = 键 as Control
		if not is_instance_valid(c):
			continue
		var b: Vector4 = _装饰基准[键]
		c.offset_left = b.x * s
		c.offset_top = b.y * s
		c.offset_right = b.z * s
		c.offset_bottom = b.w * s
	if _基准字号 > 0:
		var 字号: int = maxi(1, int(round(float(_基准字号) * s)))
		if txtSkill1 != null:
			txtSkill1.add_theme_font_size_override("font_size", 字号)
		if txtSkill2 != null:
			txtSkill2.add_theme_font_size_override("font_size", 字号)
	# 描边粗细也得跟着缩：字号小了描边不缩，小卡上那圈白边会显得比字还粗
	if _基准描边 > 0:
		var 描边: int = maxi(1, int(round(float(_基准描边) * s)))
		if txtSkill1 != null:
			txtSkill1.add_theme_constant_override("outline_size", 描边)
		if txtSkill2 != null:
			txtSkill2.add_theme_constant_override("outline_size", 描边)

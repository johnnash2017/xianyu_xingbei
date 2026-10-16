## 卡牌 UI（手牌 / 盖牌）—— 由参考工程的 AGrail.CardUI 解耦而来。
##
## 现在只做两件事：把一张 GCard 画到卡面上（含命格/元素小图标、边框），
## 以及被左键点击时发 `点击` 信号。**数据与状态由容器塞进来**
## （scripts/ui/battle_mobile.gd），不再引用参考工程的 BattleData / MessageSystem。
##
## 边框只有一个节点（Border）：三种状态（可选 / 弃牌询问 / 选中）共用它，
## 形状参数完全一样，**只有颜色不同**（可选=绿、弃牌询问=红、选中=黄）。
## 颜色与形状都是下面这些 @export，在 Card.tscn 的检查器里调，见 cardGlowFrame.gdshader。
##
## 节点引用一律 @export，在 res://scenes/prefabs/battlemobile/Card.tscn 里绑定。
##
## 带 @tool：在编辑器里打开 Card.tscn，改下面这些 @export（三个框的颜色、框的宽度/浓淡、技能字色）
## 立刻能在 2D 视图里看到效果，不用启动游戏（编辑器里边框常显，看哪个框由「编辑器预览」挑）。
@tool
extends Control

## 卡牌被点击（左键）—— 容器据此切换选中
signal 点击(卡牌号: int)

## 以下节点对应 Card.tscn 里的同名节点（card_face 画在 Root 这个 Button 的 icon 上）
@export var btn: Button
@export var txtSkill1: Label
@export var txtSkill2: Label
@export var propertyRoot: Control
@export var elementRoot: Control
## 卡牌边框（一个节点就够）：可选=绿、弃牌询问=红、选中=黄，不可用时隐藏
@export var 边框: ColorRect
## 卡面顶部的卡名（对应 Card.tscn 的 Name 节点）
@export var txtName: Label

## 这张卡（本工程的客户端卡牌视图）
var card: GCard = null
## 当前是否可用：可用 = 亮起并显示边框；不可用 = 置灰、不显示边框
var _可用: bool = false
## 是否处于「已选中」：选中时边框换成选中框那个颜色（与「可选」互斥 —— 同一个节点，只换颜色）
var _选中: bool = false
## 当前这次选牌是不是「被迫弃牌」：是的话「可选」框换成弃牌框那个颜色（红）
var _弃牌询问: bool = false

## 卡图原始尺寸（assets/textures/card/*.png，267×400）
const CARD_ART_SIZE: Vector2 = Vector2(267.0, 400.0)
# ============================================================
# 边框：三种状态（可选 / 弃牌询问 / 选中）共用一套形状参数，只有颜色不同
# ============================================================
## 框带基准宽度：卡面短边 × 这个比例（外扩 = 1 时）。手牌（卡面短边 ≈113px）≈ 18px 一圈、
## 盖牌 ≈ 13px，随卡牌大小自动缩放。这个比例就是原贴图框的宽度（166 的图 / 126 的卡面 → 20/126）
const 框带比例: float = 0.16
## 宽度倍数：框带 = 基准宽度 × 这个值（手牌下 1.25 ≈ 22px 一圈）。
## 再往上加，相邻手牌的框会互相糊在一起，够用就收着点
@export var 框外扩: float = 1.25:
	set(值):
		框外扩 = 值
		_刷新边框()
## 整体不透明度：1 = 按曲线原样，< 1 更淡、> 1 更浓（封顶 1）
@export var 框强度: float = 1.0:
	set(值):
		框强度 = 值
		_刷新边框()
## 实心段占整条框带的比例：0 = 纯渐变（贴卡面处也是半透）；0.35 = 内侧 35% 实心、其余渐隐
@export var 框实心: float = 0.35:
	set(值):
		框实心 = 值
		_刷新边框()
## 框往外渐隐的曲线：横轴 0 = 实心段刚结束（紧贴「框实心」），1 = 框带最外缘；纵轴 = 不透明度。
## 默认是一段「慢—快—慢」的下降（两端的切线都是平的，和以前的样子一致）；
## 想让透明度涨得更快/更慢，就在检查器里拖曲线上的点（想从卡面边缘就开始渐隐，把「框实心」调成 0）
@export var 框渐隐曲线: Curve:
	set(值):
		框渐隐曲线 = 值
		_曲线变化()
## 框的拐角半径：占卡面短边的比例（0 = 与卡面一样直角；卡面素材本身是直角，一般不用改）
@export var 边框圆角: float = 0.0:
	set(值):
		边框圆角 = 值
		_刷新边框()
## 三个框的颜色（形状都一样，只有颜色不同）
@export var 可选框颜色: Color = Color(0.0, 1.0, 0.024):
	set(值):
		可选框颜色 = 值
		_刷新边框()
## 弃牌询问（手牌 / 盖牌溢出被迫弃牌）时的框色：红，和「打出」区分开
@export var 弃牌框颜色: Color = Color(1.0, 0.25, 0.25):
	set(值):
		弃牌框颜色 = 值
		_刷新边框()
## 已选中时的框色（取自原贴图 b02_selected_cardy.png 的 231,242,1）
@export var 选中框颜色: Color = Color(0.906, 0.949, 0.004):
	set(值):
		选中框颜色 = 值
		_刷新边框()
## 编辑器里预览哪一个框（运行时不生效，只为在编辑器里边调边看）
enum 预览框 { 可选框, 弃牌框, 选中框 }
@export var 编辑器预览: 预览框 = 预览框.可选框:
	set(值):
		编辑器预览 = 值
		_刷新边框()
## 不可用（置灰）时的整体压暗色（与玩家面板、掉线头像共用 GConst.置灰色）
const DISABLED_TINT: Color = GConst.置灰色
## 卡面底部两格技能名的字色（在 Card.tscn 的检查器里直接调，不用改代码）：
##   有 = 我的角色会这门技能；无 = 不会（两格各自独立判断，取的同一组色）
@export var 技能字色_有: Color = Color("a9ff00"):
	set(值):
		技能字色_有 = 值
		_刷新技能字色()
@export var 技能字色_无: Color = Color("b1b1b1"):
	set(值):
		技能字色_无 = 值
		_刷新技能字色()
## 边框（三种状态共用一个节点）用的外发光着色器；节点是 ColorRect（底色透明、不参与画面），
## 颜色与形状全部由着色器算，节点本身只负责占出这块矩形。
const 发光框着色器: Shader = preload("res://scripts/effects/cardGlowFrame.gdshader")
## 边框的材质（每张卡一份，颜色互不影响）
var _边框材质: ShaderMaterial = null
## 「框渐隐曲线」转成的贴图（着色器只能采样贴图）。曲线被拖动时 CurveTexture 自己会重新烘焙，
## 所以这个贴图建一次就够，不用每次刷新都重建
var _曲线贴图: CurveTexture = null

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
	# 卡面才会铺满卡片矩形（同参考脚本的做法）。
	if btn != null:
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 边框挂外发光材质（三种状态共用这一个节点，形状一样，只按状态换颜色）
	if 边框 != null:
		_边框材质 = ShaderMaterial.new()
		_边框材质.shader = 发光框着色器
		边框.material = _边框材质
		_曲线变化()
	# 编辑器里只做「预览」：把边框贴出来、给技能名上色，改参数就能立刻看到；
	# 不放行鼠标、不缩放装饰（那是运行时的活，在编辑器里会改坏预制体）
	if Engine.is_editor_hint():
		# 曲线上的点被拖动时（资源发出 changed）也重画一次，预览跟着变
		if 框渐隐曲线 != null:
			框渐隐曲线.changed.connect(_刷新边框)
		_刷新边框()
		_刷新技能字色()
		return
	# 卡面/边框这些装饰子图在转换时带着 mouse_filter=STOP，会把点击吃掉，统一放行
	ConversionFix.ignore_decorations(self)
	_刷新边框()
	_fit_decor()


func _notification(what: int) -> void:
	# 卡牌尺寸由手牌区/盖牌区决定，尺寸一变卡面就变，边框与装饰都得跟着重算
	if what == NOTIFICATION_RESIZED:
		_刷新边框()
		# 编辑器里不缩放装饰：装饰位置/字号是预制体上标好的设计值，跟着缩放会把预制体改掉
		if not Engine.is_editor_hint():
			_fit_decor()


# ============================================================
# 对外：塞数据 / 收点击
# ============================================================
## 设置这张卡显示什么，以及是否可用（可用=亮起并显示可选光晕，不可用=整体压暗置灰）。
## 可置灰 = false 时即使不可用也保持原色（如只读查看自己的盖牌：不给点，但牌面要看得清）
func 设置卡牌(new_card: GCard, 可用: bool, 可置灰: bool = true) -> void:
	card = new_card
	_可用 = 可用
	if not 可用:
		_选中 = false
	# 置灰走 modulate：会一并压暗卡面、命格元素与边框，整张牌看起来是一体的
	modulate = DISABLED_TINT if (可置灰 and not 可用) else Color.WHITE
	_刷新边框()
	if new_card == null:
		return
	_画卡面(new_card)
	_画命格元素(new_card)
	_fit_decor()


## 当前这次选牌是不是「被迫弃牌」：是的话「可选」框用「弃牌框」那个颜色（红），和「打出」区分开
func 设置弃牌询问(值: bool) -> void:
	_弃牌询问 = 值
	_刷新边框()


## 是否处于「已选中」：选中时边框换成「选中框」那个颜色（同一个节点，不叠两圈）
func 设置选中(值: bool) -> void:
	_选中 = 值
	_刷新边框()


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
	txtName.text = c.card_name
	_画技能名(c)


## 卡面底部那两格：印这张牌带的技能名（照搬参照工程 CardUI 的 Skill1/Skill2）。
## 字色看「我的角色有没有这门技能」：有＝亮绿黄，没有＝灰
func _画技能名(c: GCard) -> void:
	var 我的技能: Array[int] = _我的角色技能()
	if txtSkill1 != null:
		txtSkill1.text = c.skill_names[0] if c.skill_names.size() >= 1 else ""
		txtSkill1.add_theme_color_override("font_color", _技能字色(c, 0, 我的技能))
	if txtSkill2 != null:
		txtSkill2.text = c.skill_names[1] if c.skill_names.size() >= 2 else ""
		txtSkill2.add_theme_color_override("font_color", _技能字色(c, 1, 我的技能))


## 技能字色改动后立刻重画。编辑器里没塞卡牌数据（就是给调色看的），
## 两格都按「有」色显示，改一次就能看到一次
func _刷新技能字色() -> void:
	if card != null:
		_画技能名(card)
		return
	if not Engine.is_editor_hint():
		return
	if txtSkill1 != null:
		txtSkill1.add_theme_color_override("font_color", 技能字色_有)
	if txtSkill2 != null:
		txtSkill2.add_theme_color_override("font_color", 技能字色_有)


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


## 刷新边框：三种状态只差颜色，形状参数（宽度 / 实心 / 强度 / 圆角）都一样。
## 运行时：选中 → 选中框；可用 → 可选框（弃牌询问时是弃牌框的红）；都不是 → 隐藏。
## 编辑器：边框常显当预览，颜色按「编辑器预览」挑。
func _刷新边框() -> void:
	if 边框 == null or _边框材质 == null:
		return
	var 编辑器: bool = Engine.is_editor_hint()
	边框.visible = true if 编辑器 else (_选中 or _可用)
	if not 边框.visible:
		return
	_边框材质.set_shader_parameter("glow_color", _预览框色() if 编辑器 else _状态框色())
	# 卡面尺寸用自身尺寸算（Root 是满锚点、跟卡片同尺寸）：NOTIFICATION_RESIZED 是卡片自己
	# 改尺寸时发出的，此时子节点的矩形可能还没刷新，读 btn.size 会拿到旧值。
	var face: Vector2 = CARD_ART_SIZE * minf(size.x / CARD_ART_SIZE.x, size.y / CARD_ART_SIZE.y)
	# 卡片自身是 0 尺寸（编辑器里没被容器摆过）时按设计卡面尺寸算，不然什么都看不到
	if face.x <= 0.0 or face.y <= 0.0:
		face = DESIGN_FACE_SIZE
	_贴边框(face, 框带比例 * 框外扩, 框实心, 框强度)


## 「框渐隐曲线」变了（换了一条，或在检查器里拖了点）：
## 把曲线挂到贴图上再通知刷新 —— 编辑器里拖曲线就能立刻看到预览变化
func _曲线变化() -> void:
	if _边框材质 == null:
		return
	if _曲线贴图 == null:
		_曲线贴图 = CurveTexture.new()
	_曲线贴图.curve = 框渐隐曲线
	_边框材质.set_shader_parameter("fade_curve", _曲线贴图)
	_刷新边框()


## 运行时的框色：选中黄最优先，其次可选绿（被迫弃牌时是红）
func _状态框色() -> Color:
	if _选中:
		return 选中框颜色
	return 弃牌框颜色 if _弃牌询问 else 可选框颜色


## 编辑器预览挑中的那一个框的颜色
func _预览框色() -> Color:
	match 编辑器预览:
		预览框.弃牌框:
			return 弃牌框颜色
		预览框.选中框:
			return 选中框颜色
		_:
			return 可选框颜色


## 把边框贴到卡面外：节点 = 卡面 + 四周等宽的一圈（带宽 = 卡面短边 × 带宽比例），
## 同时把着色器参数下发下去（见 cardGlowFrame.gdshader）。
func _贴边框(face: Vector2, 带宽比例: float, 实心: float, 强度: float) -> void:
	var 带: float = minf(face.x, face.y) * 带宽比例
	var 尺寸: Vector2 = face + Vector2(带, 带) * 2.0
	if Engine.is_editor_hint() and size.x <= 0.0 and size.y <= 0.0:
		# 编辑器里卡片是 0 尺寸（尺寸由容器在运行时给）：边框贴节点原点往右下画，整圈才在视野里
		边框.offset_left = 0.0
		边框.offset_top = 0.0
		边框.offset_right = 尺寸.x
		边框.offset_bottom = 尺寸.y
	else:
		# 边框锚在卡片正中，对称给 offsets 就能保持居中
		边框.offset_left = -尺寸.x * 0.5
		边框.offset_top = -尺寸.y * 0.5
		边框.offset_right = 尺寸.x * 0.5
		边框.offset_bottom = 尺寸.y * 0.5
	_边框材质.set_shader_parameter("face_half_px", face * 0.5)
	_边框材质.set_shader_parameter("band_px", 带)
	_边框材质.set_shader_parameter("corner_px", minf(face.x, face.y) * 边框圆角)
	_边框材质.set_shader_parameter("glow_core", 实心)
	_边框材质.set_shader_parameter("glow_intensity", 强度)


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

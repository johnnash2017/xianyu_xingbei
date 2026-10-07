## 技能按钮 —— 由参考工程的 AGrail.SkillUI 解耦而来。
##
## 现在只做两件事：显示一个技能名、被点击时发 `点击(技能号)`。
## 数据由容器塞进来（scripts/ui/battle_mobile.gd），不再引用参考工程的
## BattleData / RoleFactory / MessageSystem。
##
## 根节点就是那个按钮（Skill.tscn 的根是 Button），故直接 extends Button；
## 其余节点引用 @export，在 res://scenes/prefabs/battlemobile/Skill.tscn 里绑定。
##
## 悬停不靠 Godot 自带的 tooltip：技能区贴着屏幕底，自带的提示框跟着光标走、会顶出可视区，
## 所以这里只把「指到了 / 离开了」报给容器，由容器把说明摆在按钮正上方（见 battle_mobile）。
class_name 技能按钮
extends Button

## 技能按钮被点击 —— 容器据此进入「发动技能」或提交技能询问
signal 点击(技能号: int)
## 鼠标指向 / 离开这个技能按钮（容器据此在按钮上方显示 / 收起技能说明）
signal 悬停(按钮: 技能按钮)
signal 离开悬停()

## 对应 Skill.tscn 里的 背景板（真正接收点击、带 hover / 按下反馈的按钮）
@export var plateButton: Button
## 对应 Skill.tscn 里的 背景板/选中发光（点中时亮起的黄色外发光）
@export var selectedGlow: ColorRect
## 对应 Skill.tscn 里的 SkillName（技能名文字）
@export var skillName: Label
## 对应 Skill.tscn 里的 SelectBorder（选中高亮框）
@export var selectBorder: TextureRect

## 名字左右各留一个字宽的空白（跟按钮字号走，字号改了自动跟着变）

## 这个按钮代表的技能号
var 技能号: int = 0


func _ready() -> void:
	# 点击由「背景板」按钮承受（它是场景里真正的按钮，带 hover / 按下反馈）；本节点只做容器
	plateButton.pressed.connect(_on_pressed)
	# 悬停同样听「背景板」的（它铺满整个按钮，鼠标不会落到根节点上）
	plateButton.mouse_entered.connect(func() -> void: 悬停.emit(self))
	plateButton.mouse_exited.connect(func() -> void: 离开悬停.emit())
	# 「凸起」「选中发光」两个材质都按按钮尺寸画，宽度随技能名变化，尺寸一变就刷新
	plateButton.resized.connect(_刷新材质尺寸)
	_刷新材质尺寸()
	if selectBorder != null:
		selectBorder.visible = false


## 把当前尺寸喂给两个材质（材质是每个实例的本地副本，见 Skill.tscn 的 resource_local_to_scene）
func _刷新材质尺寸() -> void:
	var 尺寸: Vector2 = plateButton.size
	(plateButton.material as ShaderMaterial).set_shader_parameter("rect_size", 尺寸)
	(selectedGlow.material as ShaderMaterial).set_shader_parameter("rect_size", 尺寸)


## 设置这个按钮显示哪个技能
func 设置技能(id: int) -> void:
	技能号 = id
	# 底色由「凸起」着色器上色：把技能类型色传给它（与技能说明里【类型】的标色一致），
	# 不再靠节点 modulate，免得把子节点「选中发光」也一起染色
	(plateButton.material as ShaderMaterial).set_shader_parameter("button_color", GConst.skill_type_color(id))
	var 文本: String = GConst.skill_name(id)
	if skillName != null:
		skillName.text = 文本
		# 名字不换行：按钮宽度按名字长度自适应撑开，左右各留一个字宽（否则【百式幻龙拳】这类长名会折行）
		custom_minimum_size.x = _名字宽度(文本) + _一字宽() * 2.0
	if selectBorder != null:
		selectBorder.visible = false


## 当成「二级技能栏」里的一个选项按钮：只显示一段文案，底色由调用方给。
## 选项本身就是个技能时（如【蓄力一击】/【风怒追击】）传 选项技能号 > 0：绑上技能号（容器悬停时
## 像普通技能按钮那样弹它的技能说明），底色也改用技能自己的类型色，和技能栏里那颗按钮一致；
## 纯参数选项传 0，用调用方给的统一底色（黑灰 / 治疗抵挡的蓝色），悬停不弹。
func 设置选项(文本: String, 底色: Color, 选项技能号: int = 0) -> void:
	技能号 = 选项技能号
	var 用色: Color = GConst.skill_type_color(选项技能号) if 选项技能号 > 0 else 底色
	(plateButton.material as ShaderMaterial).set_shader_parameter("button_color", 用色)
	if skillName != null:
		skillName.text = 文本
		custom_minimum_size.x = _名字宽度(文本) + _一字宽() * 2.0
	if selectBorder != null:
		selectBorder.visible = false


## 名字在按钮字体下的实际渲染宽度（含描边）
func _名字宽度(名: String) -> float:
	var 字体: Font = skillName.get_theme_font("font")
	var 字号: int = skillName.get_theme_font_size("font_size")
	var 描边: int = skillName.get_theme_constant("outline_size")
	return 字体.get_string_size(名, HORIZONTAL_ALIGNMENT_LEFT, -1, 字号).x + float(描边) * 2.0


## 一个字宽：用当前字体量一个「字」的宽度（留白按它算，字号改了自动跟着变）
func _一字宽() -> float:
	var 字体: Font = skillName.get_theme_font("font")
	var 字号: int = skillName.get_theme_font_size("font_size")
	return 字体.get_string_size("字", HORIZONTAL_ALIGNMENT_LEFT, -1, 字号).x


## 是否处于「已选中」：点亮 / 熄灭黄色外发光，表示这个技能被点中了
func 设置选中(值: bool) -> void:
	selectedGlow.visible = 值


func _on_pressed() -> void:
	点击.emit(技能号)

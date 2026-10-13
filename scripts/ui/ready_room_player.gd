class_name 准备座位
extends TextureRect
## 房间准备室里的一个座位格（对应参照工程 scripts/ReadyRoomPlayer.gd）
## 结构在 scenes/ReadyRoom.tscn 的 Player0..Player7 上，本脚本只把「队伍 / 昵称 / 已准备」画出来：
##   队伍 → 换座位底色贴图（TeamBlue / TeamRed / TeamOther）
##   昵称 → 写进座位上的名字标签
##   已准备 → 显示 READY 图标

## 队伍取值：与 assets/textures/lobby/TeamXxx.png 一一对应
enum 队伍 { 蓝队, 红队, 未分队 }

## 队伍底色贴图（按上面的 enum 顺序取值）
const 队伍贴图: Array[String] = ["TeamBlue", "TeamRed", "TeamOther"]

## 座位上的昵称
@export var NickName: Label
## 已准备时显示出来的 READY 图标
@export var ReadyIcon: TextureRect

## 「自己」的昵称标色（橙）：房间里用颜色区分自己，而不是往名字后面加「（你）」
const 自身名字色: Color = Color(1.0, 0.65, 0.25)
## 座位上的名字栏（六边形右边那条横条）在座位里的横向范围，按座位宽度取比例。
## 由 TeamOther / TeamRed / TeamBlue.png 量得：横条大致落在座位宽度的 0.27~0.77 之间。
## 名字必须落在栏内才谈得上「左右居中」——之前场景里的偏移把名字摆到了横条右端之外
const 名字栏左比例: float = 0.27
const 名字栏右比例: float = 0.77
## 名字栏内左右各留的余量（像素）：截断按「栏宽 - 这份余量」算，名字不会贴着栏边
const 名字栏内边距: float = 12.0

## 当前队伍（enum 队伍 的取值），只用于贴图切换
var 队伍值: int = 队伍.未分队


func _ready() -> void:
	# 名字只占一行、左右居中；clip_text 保证再怎么长也只在自己这一栏里，不会顶出座位框
	NickName.autowrap_mode = TextServer.AUTOWRAP_OFF
	NickName.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NickName.clip_text = true
	# 横向：把名字标签摆到座位右侧那条横条上（锚点都是 0.5，所以偏移以座位中心为基准）
	var 座宽: float = size.x
	NickName.offset_left = 座宽 * 名字栏左比例 - 座宽 * 0.5
	NickName.offset_right = 座宽 * 名字栏右比例 - 座宽 * 0.5
	# 纵向：场景里的 offset 把名字压在了下半格，这里按标签自身高度重新居中
	var 半高: float = (NickName.offset_bottom - NickName.offset_top) * 0.5
	NickName.offset_top = -半高
	NickName.offset_bottom = 半高
	# 改过偏移后必须把支点重新放回标签正中：右侧座位靠 scale=-1 做镜像，
	# 支点一旦不在正中，镜像就会把整段文字挪走（另一半的座位看着就「远离名字栏」）。
	# 支点用偏移直接算（锚点左右上下都是 0.5，块宽高就等于偏移之差），不依赖 size 是否已刷新
	NickName.pivot_offset = Vector2(
		(NickName.offset_right - NickName.offset_left) * 0.5,
		(NickName.offset_bottom - NickName.offset_top) * 0.5)
	清空()


## 昵称；是自己时把名字标成橙色（用来区分「我」）
func 设置昵称(昵称: String, 是自己: bool = false) -> void:
	NickName.text = _截短(昵称)
	if 是自己:
		NickName.add_theme_color_override("font_color", 自身名字色)
	else:
		NickName.remove_theme_color_override("font_color")


## 名字太长就截短（超出用「…」收尾）。宽度是「估」出来的：汉字 / 全角按一个字宽、ASCII 按 0.6 个，
## 不用字体量宽 —— 该字体对中文的测量偏小，量着截常常截不够而溢出。
## 标签另外开了 clip_text 兜底：万一估得不准，也只会被裁掉，不会顶出座位框。
func _截短(昵称: String) -> String:
	var 字号: int = NickName.get_theme_font_size("font_size")
	var 可用: float = NickName.offset_right - NickName.offset_left - 名字栏内边距
	if _估宽(昵称, 字号) <= 可用:
		return 昵称
	var 结果: String = ""
	var 宽: float = 0.0
	var 省略宽: float = _字宽("…", 字号)
	for 字: String in 昵称:
		var 字宽: float = _字宽(字, 字号)
		if 宽 + 字宽 + 省略宽 > 可用:
			break
		宽 += 字宽
		结果 += 字
	return 结果 + "…"


## 估一个字符的显示宽度：ASCII 约 0.6 个字宽，其余（汉字 / 全角）算 1 个字宽
func _字宽(字: String, 字号: int) -> float:
	return float(字号) * (0.6 if 字.unicode_at(0) < 128 else 1.0)


## 估一整串文字的显示宽度
func _估宽(文本: String, 字号: int) -> float:
	var 宽: float = 0.0
	for 字: String in 文本:
		宽 += _字宽(字, 字号)
	return 宽


## 已准备：只切 READY 图标的可见性
func 设置准备(已准备: bool) -> void:
	ReadyIcon.visible = 已准备


## 队伍：换座位底色的贴图
func 设置队伍(队: int) -> void:
	队伍值 = clampi(队, 0, 队伍贴图.size() - 1)
	var 贴图路径: String = AssetIndex.image(队伍贴图[队伍值])
	if 贴图路径 != "":
		texture = load(贴图路径)


## 清空：刷新座位前先把整桌清一遍，否则退房那位的名字与 READY 会留在座位上
func 清空() -> void:
	设置队伍(队伍.未分队)
	设置准备(false)
	设置昵称("")

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
## 左边 0.27 是贴着六边形的位置；右边界取到座位内端（1.0）—— 横条末端是渐隐的，
## 名字用满整段才放得下几个字，居中也自然离六边形远一些
const 名字栏左比例: float = 0.27
const 名字栏右比例: float = 1.0
## 名字栏内左右各留的余量（像素）：截断按「栏宽 - 这份余量」算，名字两端就不会贴到栏边
## （名字栏两端紧挨着六边形，留白不够就会显得名字贴着框）
const 名字栏内边距: float = 64.0

## 当前队伍（enum 队伍 的取值），只用于贴图切换
var 队伍值: int = 队伍.未分队


func _ready() -> void:
	# 名字只占一行、左右居中。不开 clip_text：它在居中排版下会把文字挤向一侧，
	# 越长的名字越明显（截断交给 设置昵称 预先做，长度按保守估宽控制）
	NickName.autowrap_mode = TextServer.AUTOWRAP_OFF
	NickName.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	# 名字栏可用宽 = 标签块宽 - 两端留白（标签锚点都是 0.5，块宽就是偏移之差）
	var 可用宽: float = NickName.offset_right - NickName.offset_left - 名字栏内边距
	NickName.text = GConst.截断文字(昵称, 可用宽, NickName.get_theme_font_size("font_size"))
	if 是自己:
		NickName.add_theme_color_override("font_color", 自身名字色)
	else:
		NickName.remove_theme_color_override("font_color")


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

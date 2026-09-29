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

## 当前队伍（enum 队伍 的取值），只用于贴图切换
var 队伍值: int = 队伍.未分队


func _ready() -> void:
	清空()


## 昵称
func 设置昵称(昵称: String) -> void:
	NickName.text = 昵称


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

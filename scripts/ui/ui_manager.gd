extends Node
## 界面管理（autoload 名：UI）
## 负责界面切换：进入 → 大厅 → 战斗（含房间等待阶段）
## 所有界面都挂在主场景（Main.tscn）的「界面层」下，背景由主场景统一画，界面本身不再各画一张背景。

const SCENE_ENTER: String = "res://scenes/enter.tscn"
const SCENE_LOBBY: String = "res://scenes/lobby.tscn"
## 房间准备室：进房后、开局前的界面（参照工程的 ReadyRoom 搬过来）
const SCENE_READY_ROOM: String = "res://scenes/ReadyRoom.tscn"
## 对局进行中用参考工程搬来的那套：res://scenes/BattleUIMobile.tscn
const SCENE_BATTLE_MOBILE: String = "res://scenes/BattleUIMobile.tscn"

var current: Node = null
## 界面容器：主场景 _ready 时通过 attach() 交过来
var 界面层: Control = null


func _ready() -> void:
	# 字体统一用引擎默认字体（缺的中文字形由系统的字体回退补上）
	# 设计基准 1920x1080：没单独指定字号的地方按 20 号（原 16 号是 1152x680 时的默认）
	ThemeDB.fallback_font_size = 20


## 主场景把界面容器交过来（此后所有界面都挂到它下面）
func attach(层: Control) -> void:
	界面层 = 层


## 启动场景自报家门
func register(n: Node) -> void:
	current = n


## 进入界面。播放主界面音乐默认打开：登录 / 大厅 / 房间准备室都用主界面曲子（进房间不换曲子）。
## 战斗界面要传 false —— 它自己按「对局是否开始 / 谁赢了」管音乐，
## 而 add_child 会先同步跑完新界面的 _ready（战斗曲就是在那里起播的），
## 这里再补一句主界面曲子会把刚起的战斗曲直接盖掉。
func goto(scene_path: String, 播放主界面音乐: bool = true) -> Node:
	var ps: PackedScene = load(scene_path)
	if ps == null:
		push_error("UI: 无法加载场景 %s" % scene_path)
		return null
	# 先记下旧界面再实例化：新场景 _ready 里会 register 把自己设成 current，
	# 晚一步取到的就是新界面本身，旧界面就永远留在后面（登录界面会一直挂在房间列表后头）
	var old: Node = current
	var inst: Node = ps.instantiate()
	界面层.add_child(inst)
	current = inst
	if old != null and old != inst and is_instance_valid(old):
		old.queue_free()
	# 界面层里除新界面外还可能留着弹层（如选将层）。切界面时一并清掉，
	# 否则把弹层留在已经换掉的界面上（比如选将中途退出房间，选将层会盖在大厅上）。
	for c: Node in 界面层.get_children():
		if c != inst and is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()
	if 播放主界面音乐:
		Audio.播放音乐(Audio.场景主界面)
	return inst


func goto_lobby() -> Node:
	return goto(SCENE_LOBBY)


## 房间准备室（进房后、开局前）
func goto_ready_room() -> Node:
	return goto(SCENE_READY_ROOM)


## 对局进行中的战斗界面（参考工程那套 BattleUIMobile）：音乐由它自己切，见 goto 的说明
func goto_battle_mobile() -> Node:
	return goto(SCENE_BATTLE_MOBILE, false)


func goto_enter() -> Node:
	return goto(SCENE_ENTER)

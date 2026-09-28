extends Node
## 界面管理（autoload 名：UI）
## 负责界面切换：进入 → 大厅 → 战斗（含房间等待阶段）
## 所有界面都挂在主场景（Main.tscn）的「界面层」下，背景由主场景统一画，界面本身不再各画一张背景。

const SCENE_ENTER: String = "res://scenes/enter.tscn"
const SCENE_LOBBY: String = "res://scenes/lobby.tscn"
const SCENE_BATTLE: String = "res://scenes/battle.tscn"

var current: Node = null
## 界面容器：主场景 _ready 时通过 attach() 交过来
var 界面层: Control = null


func _ready() -> void:
	# 默认字体不含中文字形，改用系统字体（宋体/Microsoft YaHei）
	var f: SystemFont = SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei", "SimSun", "SimHei", "sans-serif"])
	ThemeDB.fallback_font = f
	# 设计基准 1920x1080：没单独指定字号的地方按 20 号（原 16 号是 1152x680 时的默认）
	ThemeDB.fallback_font_size = 20


## 主场景把界面容器交过来（此后所有界面都挂到它下面）
func attach(层: Control) -> void:
	界面层 = 层


## 启动场景自报家门
func register(n: Node) -> void:
	current = n


func goto(scene_path: String) -> Node:
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
	# 切界面时同步音乐：登录 / 大厅 / 房间等待阶段都用主界面音乐（进房间不换曲子），
	# 战斗音乐与胜负音乐由 battle.gd 按对局是否真正开始来切
	Audio.播放音乐(Audio.场景主界面)
	return inst


func goto_lobby() -> Node:
	return goto(SCENE_LOBBY)


func goto_battle() -> Node:
	return goto(SCENE_BATTLE)


func goto_enter() -> Node:
	return goto(SCENE_ENTER)

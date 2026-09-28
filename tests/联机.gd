extends Node
## 三窗口端到端联机驱动（测试件，别删）
## 由 tests/跑联机.ps1 拉起：每个窗口走「登录 → 大厅 → 建房/进房 → 准备 → 开局 → 出牌 → 应战」，
## 结束时打印一行 [联机<槽位>] 结论=… ，脚本按这行汇总。
##
## 手动跑单个窗口也行：
##   godot --path <工程> res://tests/联机.tscn -- --slot=0 --port=12641

## 打多久（秒）
const 战斗时长: float = 12.0
## 等大厅 / 等开局的超时（秒）
const 等大厅超时: float = 12.0
const 等房间超时: float = 15.0
const 等开局超时: float = 20.0

var _出牌次数: int = 0
var _错误: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	Logic.error_received.connect(_on_error)
	Logic.command_received.connect(_on_command)
	# 主场景照真实启动走一遍（等价于 project.godot 的 run/main_scene）
	var 主: Control = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(主)
	await _等(0.5)
	var 登录: Node = UI.current
	if 登录 == null or 登录.name != "Enter":
		_结束("登录界面没出现")
		return
	(登录.get("昵称输入") as LineEdit).text = "玩家%d" % (Cfg.slot + 1)
	登录.call("_on_enter_pressed")
	if not await _等到(_是大厅, 等大厅超时):
		_结束("没进大厅（连接失败？）")
		return
	_记("已进大厅，房主=%s" % str(Net.hosting))
	var 大厅: Node = UI.current
	if Net.hosting:
		大厅.call("_on_open_create_pressed")
		await _等(0.4)
		大厅.call("_on_create_pressed")
		_记("已建房")
		await _等(1.5)
		Logic.set_ready(1)
	else:
		if not await _等到(_有房间, 等房间超时):
			_结束("房间列表一直是空的")
			return
		(大厅.get("房间列表") as ItemList).select(0)
		大厅.call("_on_join_pressed")
		_记("已进房")
		await _等(1.0)
		Logic.set_ready(1)
	if not await _等到(_已开局, 等开局超时):
		_结束("没等到开局")
		return
	_记("已开局")
	await _等(战斗时长)
	_结束("")


# ============================================================
# 机器人：替这个窗口应答服务端的询问
# ============================================================
func _on_command(data: Dictionary) -> void:
	var 命令表: Array = data.get("commands", [])
	if 命令表.is_empty():
		return
	var 类型: int = int(data.get("cmd_type", 0))
	var 询问号: int = int((命令表[0] as Dictionary).get("respond_id", 0))
	if 类型 == GConst.CmdType.Action:
		_尝试出牌()
		return
	if 询问号 == GConst.RespondType.ReplyAttack:
		Logic.send_respond(询问号, [], [], [GConst.Reattack.GiveUp])
		return
	if 询问号 >= 100:
		Logic.send_respond(询问号, [], [], [0])
	elif 询问号 == GConst.RespondType.Discard or 询问号 == GConst.RespondType.DiscardCover:
		var 弃: Array = []
		for 卡: GCard in Data.hand_cards:
			弃.append(卡.id)
			break
		Logic.send_respond(询问号, [], 弃, [])
	else:
		Logic.send_respond(询问号, [], [], [0])


func _尝试出牌() -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		Logic.send_action(GConst.ActionType.None, 0, [], [], [])
		return
	for 目标: GPlayer in Data.player_list:
		if 目标.id == Logic.my_player_id or 目标.id < 0 or 目标.color == 我.color or 目标.color == GConst.TEAM_NONE:
			continue
		for 卡: GCard in Data.hand_cards:
			if 卡.is_attack():
				_出牌次数 += 1
				Logic.send_action(GConst.ActionType.Attack, 0, [目标.id], [卡.id], [])
				return
		break
	Logic.send_action(GConst.ActionType.None, 0, [], [], [])


func _on_error(err_id: int, msg: String) -> void:
	_错误.append("%d:%s" % [err_id, msg])


# ============================================================
# 收尾
# ============================================================
func _结束(问题: String) -> void:
	var 界面: String = str(UI.current.name) if UI.current != null else "<无>"
	var 结论: String = "通过"
	if 问题 != "":
		结论 = "失败：" + 问题
	elif not _错误.is_empty():
		结论 = "失败：收到错误 %s" % str(_错误)
	elif _出牌次数 == 0:
		结论 = "失败：整局没出过牌"
	print("[联机%d] 结论=%s 房主=%s 座位=%d 界面=%s 出牌=%d 错误=%d 声音=%s" % [
		Cfg.slot, 结论, str(Net.hosting), Logic.my_player_id, 界面, _出牌次数, _错误.size(),
		"关" if Audio.是否静音() else "开"])
	get_tree().quit(0 if 结论 == "通过" else 1)


# ============================================================
# 小工具
# ============================================================
func _是大厅() -> bool:
	return UI.current != null and UI.current.name == "Lobby"


func _有房间() -> bool:
	if UI.current == null:
		return false
	return not (UI.current.get("_room_ids") as Array).is_empty()


func _已开局() -> bool:
	if UI.current == null or UI.current.name != "Battle":
		return false
	var 等待框: Control = UI.current.get("_waiting_box")
	return 等待框 != null and not 等待框.visible


func _等(秒: float) -> void:
	await get_tree().create_timer(秒).timeout


func _等到(条件: Callable, 超时: float) -> bool:
	var 截止: int = Time.get_ticks_msec() + int(超时 * 1000.0)
	while Time.get_ticks_msec() < 截止:
		if 条件.call():
			return true
		await _等(0.2)
	return bool(条件.call())


func _记(t: String) -> void:
	print("[联机%d] %s" % [Cfg.slot, t])

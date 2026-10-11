extends Node
## 三窗口端到端联机驱动（测试件，别删）
## 由 tests/runLanPlay.ps1 拉起：每个窗口走「登录 → 大厅 → 建房/进房 → 准备 → 开局 → 出牌 → 应战」，
## 结束时打印一行 [联机<槽位>] 结论=… ，脚本按这行汇总。
##
## 手动跑单个窗口也行：
##   godot --path <工程> res://tests/lanPlay.tscn -- --slot=0 --port=12641

## 打多久（秒）
const 战斗时长: float = 12.0
## 已知使用「引擎钩子进度 step」的角色实现脚本：联机时优先让各窗口选这些角色，
## 好让对局真正覆盖到 step 重构（否则整池模式下各窗口很可能选中同一个无关角色）。
const 用STEP的脚本: Array[String] = [
	"role_ansha", "role_fengyin", "role_gedou", "role_honglian", "role_jiandi", "role_jiansheng",
	"role_lingfu", "role_mogong", "role_mojian", "role_moqiang", "role_nvwushen", "role_qidao",
	"role_shenggong", "role_shengnv", "role_shenguan", "role_shiren", "role_shouling", "role_spmodao",
	"role_tianshi", "role_wunu", "role_xianzhe", "role_xuejian", "role_yinglingrenxing",
	"role_yinyang", "role_yongzhe", "role_yuenv", "role_jinglingsheshou",
]
## 机器人每次应答前的等待（秒）：放慢战斗节奏。战斗推进得越快，一秒下发的全量快照越多，
## 客户端每次都要整体重建界面。默认 0.3；可用启动参数 --op-delay=0.1 覆盖（调机器性能用）。
var 操作间隔: float = 0.3
## 选将洗牌种子：由 runLanPlay.ps1 每批生成一个，同一批窗口共用 → 各选不同角色；
## 0 表示没传（退回按时间取种子）。
var 洗牌种子: int = 0
## 等大厅 / 等开局的超时（秒）
const 等大厅超时: float = 12.0
const 等房间超时: float = 15.0
const 等开局超时: float = 20.0

var _出牌次数: int = 0
## 出牌广播 / 命中广播的计数：确认攻击真的「打出去了」，而不是只「发出去了」
var _亮牌次数: int = 0
var _命中次数: int = 0
var _错误: Array[String] = []
## 服务端驳回玩家操作（ErrorInput 走聊天提示，不计入 error_received）：出现即视为失败
var _操作无效次数: int = 0


var 抽样计时: float = 0.0
## 最近 1 秒内收到的快照 / 询问次数（判断主线程是不是被广播与界面重建压住）
var 每秒快照: int = 0
var 每秒询问: int = 0


## 每秒采一条性能样本，用于定位「战斗时到底什么最占资源」：
## 逻辑耗时（CPU 主线程）/ 绘制调用与渲染对象（GPU）/ 对象总数 / 内存
func _process(delta: float) -> void:
	抽样计时 += delta
	if 抽样计时 < 1.0:
		return
	抽样计时 = 0.0
	var 界面: String = str(UI.current.name) if UI.current != null else "<无>"
	_记("采样 fps=%d 逻辑=%.1fms 物理=%.1fms 绘制=%d 渲染对象=%d 对象数=%d 内存=%.0fMB 快照/秒=%d 询问/秒=%d 界面=%s" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		每秒快照, 每秒询问,
		界面,
	])
	每秒快照 = 0
	每秒询问 = 0


## 收到一帧对局快照（战斗界面据此整体重建玩家/手牌/头像）
func _on_snap(_info: Dictionary) -> void:
	每秒快照 += 1


func _ready() -> void:
	# headless 下 Godot 默认进「低处理器模式」，帧率被压得很低，按帧推进的流程会变慢；
	# 关掉它让测试跑满速（只影响本测试进程，不改被测逻辑）。
	OS.low_processor_usage_mode = false
	# 允许命令行覆盖机器人操作间隔（--op-delay=0.1）与选将洗牌种子（--seed=N，同一批共用）
	for 参: String in OS.get_cmdline_user_args():
		if 参.begins_with("--op-delay="):
			操作间隔 = float(参.substr(11))
		elif 参.begins_with("--seed="):
			洗牌种子 = int(参.substr(7))
	await get_tree().process_frame
	Logic.error_received.connect(_on_error)
	Logic.gossip_received.connect(_on_gossip)
	Logic.role_pick_required.connect(_on_role_pick)
	Logic.command_received.connect(_on_command)
	Logic.game_info_updated.connect(_on_snap)
	Logic.card_shown.connect(_on_card_shown)
	Logic.hit_received.connect(_on_hit)
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
## 选将：替本窗口挑一个候选角色提交，否则会卡在准备室、永远进不了战斗。
## 优先在候选里挑「使用 step 的角色」，并让各窗口取不同位置 —— 整池（任选）模式下服务端
## 给每个人发同一份候选，若都取第 0 个会全选同一个角色，联机验证面太窄。
func _on_role_pick(data: Dictionary) -> void:
	var 候选: Array = data.get("role_ids", [])
	if 候选.is_empty():
		return
	var 用step: Array[int] = []
	for rid: Variant in 候选:
		# 角色表「脚本」列存的是完整路径（res://scripts/battle/roles/xxx.gd），按片段匹配
		var 脚本: String = str(Data.role_script(int(rid)))
		for 名: String in 用STEP的脚本:
			if 脚本.find(名) >= 0:
				用step.append(int(rid))
				break
	# 洗牌用「分钟级种子」手动进行：同一批窗口拿到相同顺序，从而各槽位取到不同角色、
	# 同一局内不重复；不同批次又因时间不同而覆盖到不同角色。
	var 池: Array = (用step if not 用step.is_empty() else 候选).duplicate()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 洗牌种子 if 洗牌种子 != 0 else int(Time.get_unix_time_from_system())
	for i: int in range(池.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var 暂: Variant = 池[i]
		池[i] = 池[j]
		池[j] = 暂
	var 位: int = Cfg.slot % 池.size()
	var 选中: int = int(池[位])
	_记("选将：候选 %d 个（用 step 的 %d 个），本窗口取第 %d 个 → 角色 %d（%s）" % [
		候选.size(), 用step.size(), 位, 选中, Data.role_name(选中)])
	Logic.send_pick(int(data.get("strategy", 0)), [选中])


func _on_command(data: Dictionary) -> void:
	每秒询问 += 1
	# 放慢节奏：应答前先等一会儿，降低战斗推进速度 → 快照频率下降 → CPU 压力下降
	if 操作间隔 > 0.0:
		await get_tree().create_timer(操作间隔).timeout
	_应答(data)


func _应答(data: Dictionary) -> void:
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


## 【操作无效】提示（对应服务端 ErrorInput）：出牌链路回归时会被驳回，必须计入失败
func _on_gossip(txt: String) -> void:
	if txt.find("操作无效") >= 0:
		_操作无效次数 += 1


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
	elif _亮牌次数 == 0:
		结论 = "失败：出过牌但一次都没真正打出去（无亮牌广播）"
	elif _操作无效次数 > 0:
		结论 = "失败：有 %d 次操作被服务端驳回" % _操作无效次数
	var 行: String = "[联机%d] 结论=%s 房主=%s 座位=%d 界面=%s 出牌=%d 亮牌=%d 命中=%d 驳回=%d 错误=%d fps=%d 声音=%s" % [
		Cfg.slot, 结论, str(Net.hosting), Logic.my_player_id, 界面, _出牌次数, _亮牌次数, _命中次数,
		_操作无效次数, _错误.size(), Engine.get_frames_per_second(), "关" if Audio.是否静音() else "开"]
	print(行)
	# stdout 在 Windows 下重定向到文件时是块缓冲，窗口被脚本强杀会把结论一起丢掉：
	# 另写一份到工程外的 _联调日志，供 runLanPlay.ps1 汇总读取
	var 结论文件: String = ProjectSettings.globalize_path("res://") + "../_联调日志/结论_%d.txt" % Cfg.slot
	var f: FileAccess = FileAccess.open(结论文件, FileAccess.WRITE)
	if f != null:
		f.store_string(行)
		f.close()
	get_tree().quit(0 if 结论 == "通过" else 1)


## 出牌广播（引擎确实把这张牌打出去了才会广播）—— 用来确认「发出去了」不等于「真打出去了」
func _on_card_shown(_msg: Dictionary) -> void:
	_亮牌次数 += 1


## 命中判定广播
func _on_hit(_src: int, _dst: int, _hit: int) -> void:
	_命中次数 += 1


# ============================================================
# 小工具
# ============================================================
func _是大厅() -> bool:
	return UI.current != null and UI.current.name == "Lobby"


func _有房间() -> bool:
	if UI.current == null:
		return false
	return not (UI.current.get("_room_ids") as Array).is_empty()


## 已开局：开局后从「房间准备室」ReadyRoom 切到新版战斗界面 BattleUIMobile
func _已开局() -> bool:
	if UI.current == null:
		return false
	if UI.current.name == "BattleUIMobile":
		return true
	if UI.current.name != "Battle":
		return false
	var 等待框: Control = UI.current.get("_waiting_box")
	return 等待框 != null and not 等待框.visible


func _等(秒: float) -> void:
	# 不用 SceneTreeTimer：多窗口时实测后台窗口的定时器不推进，
	# 改成按真实时间轮询帧，保证每个窗口都能走完计时
	var 截止: int = Time.get_ticks_msec() + int(秒 * 1000.0)
	while Time.get_ticks_msec() < 截止:
		await get_tree().process_frame


func _等到(条件: Callable, 超时: float) -> bool:
	var 截止: int = Time.get_ticks_msec() + int(超时 * 1000.0)
	while Time.get_ticks_msec() < 截止:
		if 条件.call():
			return true
		await _等(0.2)
	return bool(条件.call())


func _记(t: String) -> void:
	var 行: String = "[联机%d] %s" % [Cfg.slot, t]
	print(行)
	_追加进度(行)


## 进度另落盘一份：stdout 在重定向时可能被强杀丢掉，落盘文件不受影响（便于定位卡点）
func _追加进度(行: String) -> void:
	var 路径: String = ProjectSettings.globalize_path("res://") + "../_联调日志/进度_%d.txt" % Cfg.slot
	var f: FileAccess = FileAccess.open(路径, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(路径, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(行)
		f.close()

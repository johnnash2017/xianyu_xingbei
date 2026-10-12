extends Node
## 三窗口端到端联机驱动（测试件，别删）
## 由 tests/runLanPlay.ps1 拉起：每个窗口走「登录 → 大厅 → 建房/进房 → 准备 → 开局 → 出牌 → 应战」，
## 结束时打印一行 [联机<槽位>] 结论=… ，脚本按这行汇总。
##
## 手动跑单个窗口也行：
##   godot --path <工程> res://tests/lanPlay.tscn -- --slot=0 --port=12641

## 打多久（秒）
const 战斗时长: float = 20.0
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
## 命令行 --roles=12,22 指定本批要选的角色（定向补覆盖用）；空 = 自动从「用 step 的角色」里随机挑
var 指定角色: Array[int] = []
## 等大厅 / 等开局的超时（秒）
const 等大厅超时: float = 12.0
const 等房间超时: float = 15.0
const 等开局超时: float = 20.0

var _出牌次数: int = 0
## 发动技能的次数：机器人优先用技能，用不了才出手牌，两者都用来衡量「这局真打过东西」
var _技能次数: int = 0
## 宣告「无法行动」换一手牌的次数（手里没有能打的攻击牌、也没有可用技能时的兜底）
var _换牌次数: int = 0
## 出牌广播 / 命中广播的计数：确认攻击真的「打出去了」，而不是只「发出去了」
var _亮牌次数: int = 0
var _命中次数: int = 0
var _错误: Array[String] = []
## 服务端驳回玩家操作（ErrorInput 走聊天提示，不计入 error_received）：出现即视为失败
var _操作无效次数: int = 0
## 被服务端驳回过一次的技能号：记下来，下次行动直接跳过，避免反复被拒、也避免卡死
var _禁用技能: Dictionary = {}
## 上一次尝试发动、还没等到结果的技能号（收到错误就把它列入 _禁用技能）
var _上次尝试技能: int = -1
## 被服务端驳回过一次的牌 id：同理，出了会被拒的牌就换一张
var _禁用牌: Dictionary = {}
## 上一次尝试打出、还没等到结果的牌 id（收到错误就把它列入 _禁用牌）
var _上次尝试牌: int = -1
## 本窗口收到过几次行动询问（判断「整局没行动」时排除「压根没轮到出手」的窗口）
var _收到行动询问: int = 0
## 被服务端驳回过一次的特殊行动（购买/合成/提炼）：同理拉黑
var _禁用特殊: Dictionary = {}
## 上一次尝试的特殊行动（收到错误就把它列入 _禁用特殊）
var _上次尝试特殊: int = -1
## 发动特殊行动的次数（购买 / 合成 / 提炼）
var _特殊次数: int = 0
## 被服务端驳回过一次的目标玩家 id：拉黑，改打别的（如「潜行中的暗杀者不能成为主动攻击目标」）
var _禁用目标: Dictionary = {}
## 上一次尝试指向、还没等到结果的目标 id
var _上次尝试目标: int = -1


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
		elif 参.begins_with("--roles="):
			for s: String in 参.substr(8).split(","):
				指定角色.append(int(s))
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
	_记("用 step 的角色 id：%s" % str(用step))
	# 洗牌用「分钟级种子」手动进行：同一批窗口拿到相同顺序，从而各槽位取到不同角色、
	# 同一局内不重复；不同批次又因时间不同而覆盖到不同角色。
	var 池: Array = (用step if not 用step.is_empty() else 候选).duplicate()
	if not 指定角色.is_empty():
		var 指定池: Array = []
		for rid2: Variant in 候选:
			if 指定角色.has(int(rid2)):
				指定池.append(int(rid2))
		if not 指定池.is_empty():
			池 = 指定池
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
	var 首: Dictionary = 命令表[0]
	var 询问号: int = int(首.get("respond_id", 0))
	if 类型 == GConst.CmdType.Action:
		_收到行动询问 += 1
		_尝试出牌(命令表)
		return
	if 询问号 == GConst.RespondType.ReplyAttack:
		Logic.send_respond(询问号, [], [], [GConst.Reattack.GiveUp])
		return
	# 角色技能询问（被动技能）：一半概率发动、一半放弃，发动时按询问参数帮它选好牌 / 目标
	if bool(首.get("is_skill", false)):
		_应答技能询问(首)
		return
	if 询问号 == GConst.RespondType.Discard or 询问号 == GConst.RespondType.DiscardCover:
		# 弃手牌 / 弃盖牌，张数取询问参数（Discard 的 args[2] 是要弃的张数）
		var 池: Array = Data.cover_cards if 询问号 == GConst.RespondType.DiscardCover else Data.hand_cards
		var 参数: Array = 首.get("args", [])
		var 张: int = int(参数[2]) if 参数.size() >= 3 else 1
		var 弃: Array = []
		for 卡: GCard in 池:
			弃.append(卡.id)
			if 弃.size() >= 张:
				break
		Logic.send_respond(询问号, [], 弃, [])
		return
	# 额外行动：一半概率挑一项去做（dst_ids 是当前能发动的 cause），一半放弃
	if 询问号 == GConst.RespondType.AdditionalAction:
		var 可发动: Array = 首.get("dst_ids", [])
		if not 可发动.is_empty() and randi() % 2 == 0:
			Logic.send_respond(询问号, [], [], [int(可发动[0])])
		else:
			Logic.send_respond(询问号, [], [], [0])
		return
	Logic.send_respond(询问号, [], [], [0])


## 被动技能询问：cmd.args = [需牌数, 需目标数, 选牌来源, 选项数, 选项值…]。
## 有选项的（二级选项 / 治疗分配等）机器人不构造，能取消就取消；无选项的一半概率发动并选好牌 / 目标。
func _应答技能询问(cmd: Dictionary) -> void:
	var 技能号: int = int(cmd.get("respond_id", 0))
	var 参数: Array = cmd.get("args", [])
	var 可取消: bool = bool(cmd.get("can_cancel", true))
	if 参数.size() < 4:
		Logic.send_respond(技能号, [], [], [0])
		return
	var 需牌: int = int(参数[0])
	var 需目标: int = int(参数[1])
	var 牌来源: int = int(参数[2])
	var 选项数: int = int(参数[3])
	if 选项数 > 0:
		Logic.send_respond(技能号, [], [], [int(参数[4]) if (not 可取消 and 参数.size() > 4) else 0])
		return
	# 牌 / 目标没给白名单的询问（角色自己另作校验，机器人无从构造）一律不发动，避免被驳回
	if 需牌 > 0 and (cmd.get("card_ids", []) as Array).is_empty():
		Logic.send_respond(技能号, [], [], [0])
		return
	if 需目标 > 0 and (cmd.get("dst_ids", []) as Array).is_empty():
		Logic.send_respond(技能号, [], [], [0])
		return
	if 可取消 and randi() % 2 != 0:
		Logic.send_respond(技能号, [], [], [0])
		return
	var 选牌结果: Dictionary = _按规则选牌(需牌, cmd.get("card_ids", []), str(cmd.get("card_rule", "")), 0, 0, 0, 牌来源)
	if not bool(选牌结果.get("ok", false)):
		Logic.send_respond(技能号, [], [], [0])
		return
	var 选目标: Array = []
	if 需目标 > 0:
		var 目标表: Array = (cmd.get("dst_ids", []) as Array).duplicate()
		if 目标表.size() < 需目标:
			Logic.send_respond(技能号, [], [], [0])
			return
		选目标 = 目标表.slice(0, 需目标)
	_上次尝试技能 = 技能号
	Logic.send_respond(技能号, 选目标, 选牌结果.get("cards", []), [1])


## 行动阶段决策：命令表里下发的技能能发动就发动（用技能），发动不了再出手牌，最后才放弃。
## 命令表第 0 项是通用行动（respond_id = 本阶段允许的行动种类），其后是当前能点的技能。
func _尝试出牌(命令表: Array) -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		Logic.send_action(GConst.ActionType.None, 0, [], [], [])
		return
	var 首项: Dictionary = 命令表[0]
	var 允许: int = int(首项.get("respond_id", GConst.ActionType.Any))
	var 禁特殊: bool = bool(首项.get("no_special", false))
	var 可放弃: bool = false
	for 项: Variant in 命令表:
		if int((项 as Dictionary).get("respond_id", 0)) == GConst.ActionType.None:
			可放弃 = true
			break
	# 有条件也用技能时先掷硬币（一半一半）：避免整局只放技能，覆盖不到「出牌」这条路
	if randi() % 2 == 0:
		for 项: Variant in 命令表:
			if _试着用技能(项 as Dictionary, 允许, 禁特殊):
				return
	# 一半概率走特殊行动（提炼 / 购买 / 合成）：这类「行动」也得让机器人会走
	if randi() % 2 == 0 and _尝试特殊行动(我, 允许, 禁特殊):
		return
	# 这一手不掷中技能 / 技能条件都不满足 → 出手牌：挑一张本阶段允许的攻击牌打最近的对手。
	# 白名单来自通用行动项（如【修罗连斩】额外攻击行动只许出火系攻击牌），不在白名单里的牌会被服务端拒
	var 白名单: Array = 首项.get("card_ids", [])
	for 目标: GPlayer in Data.player_list:
		if 目标.id == Logic.my_player_id or 目标.id < 0 or 目标.color == 我.color or 目标.color == GConst.TEAM_NONE:
			continue
		if _禁用目标.has(目标.id) or not _能主动攻击(目标):
			continue
		for 卡: GCard in Data.hand_cards:
			if not 卡.is_attack() or _禁用牌.has(卡.id):
				continue
			if not 白名单.is_empty() and not 白名单.has(卡.id):
				continue
			_出牌次数 += 1
			_上次尝试技能 = -1
			_上次尝试牌 = 卡.id
			_上次尝试目标 = 目标.id
			Logic.send_action(GConst.ActionType.Attack, 0, [目标.id], [卡.id], [])
			return
		break
	# 没有可用技能、也没有能打的攻击牌：
	#   允许放弃（额外行动 / 被挑衅）→ 放弃；普通行动阶段 → 宣告「无法行动」换一手牌（不能直接放弃，
	#   直接回 None 会被服务端判非法、反复驳回）
	if 可放弃:
		Logic.send_action(GConst.ActionType.None, 0, [], [], [])
	elif 允许 == GConst.ActionType.Any:
		_换牌次数 += 1
		Logic.send_action(GConst.ActionType.Unactional, 0, [], [], [])
	else:
		Logic.send_action(GConst.ActionType.None, 0, [], [], [])


## 按命令表下发的一项技能发起行动：行动种类 / 目标 / 选牌 / 选项等条件都满足才提交，返回 true。
## 任一条满足不了就返回 false，交给调用方换下一项技能、或退回出手牌。
func _试着用技能(cmd: Dictionary, 允许: int, 禁特殊: bool) -> bool:
	var 类型: int = int(cmd.get("respond_id", 0))
	if 类型 != GConst.ActionType.AttackSkill and 类型 != GConst.ActionType.MagicSkill and 类型 != GConst.ActionType.SpecialSkill:
		return false
	if not GConst.放行动作(类型, 允许):
		return false
	if 禁特殊 and 类型 == GConst.ActionType.SpecialSkill:
		return false
	var 参数: Array = cmd.get("args", [])
	if 参数.size() < 5:
		return false
	var 技能号: int = int(参数[0])
	if _禁用技能.has(技能号):
		return false
	# 一级参数：需牌数 / 需目标数 / 选牌来源；二级技能栏的选项（arg_choices）取第一项，并认它自带的
	# 「需目标 / 目标表」（如圣枪两种用法各自限定队友或对手）
	var 需牌: int = int(参数[1])
	var 需目标: int = int(参数[2])
	var 牌来源: int = int(参数[4])
	var 目标表: Array = (cmd.get("dst_ids", []) as Array).duplicate()
	var 追加参数: Array = []
	var 选项: Array = cmd.get("arg_choices", [])
	if not 选项.is_empty():
		var 首选: Dictionary = 选项[0]
		追加参数 = (首选.get("args", []) as Array).duplicate()
		if 首选.has("need_target"):
			需目标 = int(首选.get("need_target", 需目标))
		if 首选.has("targets"):
			目标表 = (首选.get("targets", []) as Array).duplicate()
	# 选牌：按白名单 / card_rule（同系、互异系、同命格、法术）/ 逐张条件 / 需盖牌数挑
	var 选牌结果: Dictionary = _按规则选牌(需牌, cmd.get("card_ids", []), str(cmd.get("card_rule", "")),
		int(cmd.get("card_slot_skill", 0)), int(cmd.get("card_slot_element", 0)),
		int(cmd.get("cover_need", 0)), 牌来源)
	if not bool(选牌结果.get("ok", false)):
		return false
	var 选牌: Array = 选牌结果.get("cards", [])
	# 目标数上限随已选牌数变化：上限 = 已选牌数 - 该值（至少 1 张）；连最低要求都装不下就跳过
	var 随牌: int = int(cmd.get("target_max_from_cards", 0))
	if 随牌 > 0 and 需目标 > maxi(选牌.size() - 随牌, 1):
		return false
	var 选目标: Array = []
	if 需目标 > 0:
		if 目标表.is_empty():
			# 命令表没限定目标 ＝ 界面把所有玩家都放开；挑对手（需要指队友的技能在表里都会带 targets）
			var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
			for 目标: GPlayer in Data.player_list:
				if 我 != null and (目标.id == 我.id or 目标.id < 0 or 目标.color == 我.color or 目标.color == GConst.TEAM_NONE):
					continue
				if _禁用目标.has(目标.id) or not _能主动攻击(目标):
					continue
				目标表.append(目标.id)
		if 目标表.size() < 需目标:
			return false
		选目标 = 目标表.slice(0, 需目标)
	# 有些技能还要「每个目标分几点」这类与目标平行的 args（如红莲骑士【血腥祷言】），命令表不给提示：
	# 没给 arg_choices 时按「每名目标 1 点」兜底，正好是最小合法分配
	if 追加参数.is_empty() and 需目标 > 0:
		for _i: int in range(需目标):
			追加参数.append(1)
	_上次尝试技能 = 技能号
	_上次尝试牌 = -1
	_上次尝试目标 = int(选目标[0]) if not 选目标.is_empty() else -1
	_技能次数 += 1
	Logic.send_action(类型, 技能号, 选目标, 选牌, 追加参数)
	return true


## 特殊行动（提炼 / 购买 / 合成）：按客户端同一套组合规则挑一个必定合法的提交，避免被服务端驳回。
## 冒险家（12）的购买与提炼有独有流程（地下法则 / 冒险者天堂），机器人不构造。
func _尝试特殊行动(我: GPlayer, 允许: int, 禁特殊: bool) -> bool:
	if 禁特殊 or not GConst.放行动作(GConst.ActionType.Special, 允许):
		return false
	if 我.role_id == 12:
		return false
	var 战绩: GTeam = Data.team_of(我.color)
	var 总: int = 战绩.gem + 战绩.crystal
	var 余量: int = 我.energy_max - 我.get_energy()
	# 提炼：把战绩区星石取给自己，取得进（余量够）才提
	var 提宝: int = 0
	var 提水: int = 0
	if 余量 >= 1 and 战绩.gem >= 1:
		提宝 = 1
	if 余量 - 提宝 >= 1 and 战绩.crystal >= 1:
		提水 = 1
	if not _禁用特殊.has(GConst.SpecialAction.Extract) and 提宝 + 提水 > 0:
		return _发特殊(GConst.SpecialAction.Extract, [提宝, 提水])
	# 购买：手牌留得下 3 张；战绩区总量 < 5（满 4 时只买 1 颗）
	if not _禁用特殊.has(GConst.SpecialAction.Buy) and Data.hand_cards.size() + 3 <= 我.hand_cards_max and 总 < 5:
		return _发特殊(GConst.SpecialAction.Buy, [1, 1] if 总 < 4 else [1, 0])
	# 合成圣杯：手牌留得下 3 张、战绩区够 3 颗
	if not _禁用特殊.has(GConst.SpecialAction.Synthesize) and Data.hand_cards.size() + 3 <= 我.hand_cards_max and 总 >= 3:
		for 项: Variant in [[0, 3], [1, 2], [2, 1], [3, 0]]:
			var 花: Array = 项
			if int(花[0]) <= 战绩.gem and int(花[1]) <= 战绩.crystal:
				return _发特殊(GConst.SpecialAction.Synthesize, 花)
	return false


## 提交一次特殊行动并登记（供驳回时拉黑）
func _发特殊(aid: int, args: Array) -> bool:
	_上次尝试技能 = -1
	_上次尝试牌 = -1
	_上次尝试目标 = -1
	_上次尝试特殊 = aid
	_特殊次数 += 1
	Logic.send_action(GConst.ActionType.Special, aid, [], [], args)
	return true


## 按技能对选牌的要求挑牌，返回 {"ok": 是否挑得出来, "cards": id 数组}。
## 规则（card_rule）：""＝不限 / magic＝只能法术牌 / same＝必须同系 / diff＝必须互异系 / sameprop＝同命格；
## 另认「逐张条件」（第 1 张须带某技能 card_slot_skill、第 2 张须为某系 card_slot_element）与「需盖牌数」cover_need。
func _按规则选牌(需牌: int, 白名单: Array, 规则: String, slot_skill: int, slot_element: int, cover_need: int, 来源: int) -> Dictionary:
	# 只能从「场上基础效果」选牌的技能，机器人不会构造，跳过
	if 来源 == GConst.CardSource.BasicEffect or 来源 == GConst.CardSource.HandAndBasicEffect:
		return {"ok": false, "cards": []}
	var 池: Array = []
	if 来源 == GConst.CardSource.Hand or 来源 == GConst.CardSource.HandOrCover:
		for 卡: GCard in Data.hand_cards:
			池.append({"id": 卡.id, "card": 卡, "cover": false})
	if 来源 == GConst.CardSource.Cover or 来源 == GConst.CardSource.HandOrCover:
		for 卡: GCard in Data.cover_cards:
			池.append({"id": 卡.id, "card": 卡, "cover": true})
	var 候选: Array = []
	for 项: Variant in 池:
		var c: GCard = 项["card"]
		if not 白名单.is_empty() and not 白名单.has(int(项["id"])):
			continue
		if 规则 == "magic" and not c.is_magic():
			continue
		候选.append(项)
	if 需牌 <= 0:
		return {"ok": cover_need <= 0, "cards": []}
	if 规则 == "same" or 规则 == "sameprop":
		# 同系 / 同命格：按元素或命格分组，某一组里挑得够就行
		var 分组: Dictionary = {}
		for 项: Variant in 候选:
			var c2: GCard = 项["card"]
			var 键: int = c2.property_enum() if 规则 == "sameprop" else c2.element_enum()
			if not 分组.has(键):
				分组[键] = []
			(分组[键] as Array).append(项)
		for 键2: Variant in 分组.keys():
			var 选: Array = _在池中选(分组[键2] as Array, 需牌, slot_skill, slot_element, cover_need)
			if not 选.is_empty():
				return {"ok": true, "cards": 选}
		return {"ok": false, "cards": []}
	if 规则 == "diff":
		return _选互异系(候选, 需牌, slot_skill, slot_element, cover_need)
	var 选2: Array = _在池中选(候选, 需牌, slot_skill, slot_element, cover_need)
	return {"ok": not 选2.is_empty(), "cards": 选2}


## 在给定池里挑 需牌 张：先满足逐张条件（第 1/2 张），再优先盖牌凑够 cover_need，最后手牌补齐。
## 挑不出来返回空数组。
func _在池中选(池: Array, 需牌: int, slot_skill: int, slot_element: int, cover_need: int) -> Array:
	var 选: Array = []
	var 用: Dictionary = {}
	# 第 1 张：可能要带指定技能
	var 得0: bool = false
	for 项: Variant in 池:
		var c: GCard = 项["card"]
		if slot_skill > 0 and not c.has_skill_id(slot_skill):
			continue
		选.append(int(项["id"]))
		用[int(项["id"])] = true
		得0 = true
		break
	if not 得0:
		return []
	# 第 2 张：可能要求指定系别
	if 需牌 >= 2:
		var 得1: bool = false
		for 项: Variant in 池:
			if 用.has(int(项["id"])):
				continue
			if slot_element > 0 and int((项["card"] as GCard).element_enum()) != slot_element:
				continue
			选.append(int(项["id"]))
			用[int(项["id"])] = true
			得1 = true
			break
		if not 得1:
			return []
	# 先盖牌后手牌补齐
	for 项: Variant in 池:
		if 选.size() >= 需牌:
			break
		if 用.has(int(项["id"])) or not bool(项["cover"]):
			continue
		选.append(int(项["id"]))
		用[int(项["id"])] = true
	for 项: Variant in 池:
		if 选.size() >= 需牌:
			break
		if 用.has(int(项["id"])):
			continue
		选.append(int(项["id"]))
		用[int(项["id"])] = true
	if 选.size() < 需牌:
		return []
	var 盖数: int = 0
	for 项: Variant in 池:
		if 用.has(int(项["id"])) and bool(项["cover"]):
			盖数 += 1
	if 盖数 < cover_need:
		return []
	return 选


## 互异系规则：逐张挑不同元素的牌，同时认逐张条件与需盖牌数。挑不出来返回 {"ok": false, "cards": []}
func _选互异系(池: Array, 需牌: int, slot_skill: int, slot_element: int, cover_need: int) -> Dictionary:
	var 选: Array = []
	var 用: Dictionary = {}
	var 已用系: Array[int] = []
	var 盖数: int = 0
	for 项: Variant in 池:
		if 选.size() >= 需牌:
			break
		var c: GCard = 项["card"]
		if 用.has(int(项["id"])):
			continue
		var 系: int = c.element_enum()
		if 已用系.has(系):
			continue
		if 选.size() == 0 and slot_skill > 0 and not c.has_skill_id(slot_skill):
			continue
		if 选.size() == 1 and slot_element > 0 and 系 != slot_element:
			continue
		选.append(int(项["id"]))
		用[int(项["id"])] = true
		已用系.append(系)
		if bool(项["cover"]):
			盖数 += 1
	if 选.size() < 需牌 or 盖数 < cover_need:
		return {"ok": false, "cards": []}
	return {"ok": true, "cards": 选}


func _on_error(err_id: int, msg: String) -> void:
	_错误.append("%d:%s" % [err_id, msg])


## 【操作无效】提示（对应服务端 ErrorInput）：出牌链路回归时会被驳回，必须计入失败。
## 驳回只走这里（不是 error_received），把刚发的那一条拉黑，换别的继续，避免原地死循环。
func _on_gossip(txt: String) -> void:
	if txt.find("操作无效") >= 0:
		_操作无效次数 += 1
		_拉黑上次尝试()


## 能不能把某人当「主动攻击」的目标：暗杀者（5）【潜行】（横置）期间不能成为主动攻击目标
## （对照服务端 AnSha::v_attacked）。别的角色没有这条限制
func _能主动攻击(玩家: GPlayer) -> bool:
	if 玩家.role_id == 5 and 玩家.tap:
		return false
	return true


## 把「上一次尝试、刚被驳回」的技能 / 牌 / 特殊行动 / 目标记下来，下次别再原样重发
func _拉黑上次尝试() -> void:
	if _上次尝试技能 > 0:
		_禁用技能[_上次尝试技能] = true
		_上次尝试技能 = -1
	if _上次尝试牌 > 0:
		_禁用牌[_上次尝试牌] = true
		_上次尝试牌 = -1
	if _上次尝试特殊 >= 0:
		_禁用特殊[_上次尝试特殊] = true
		_上次尝试特殊 = -1
	if _上次尝试目标 > 0:
		_禁用目标[_上次尝试目标] = true
		_上次尝试目标 = -1


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
	elif _出牌次数 + _技能次数 + _换牌次数 + _特殊次数 == 0 and _收到行动询问 > 0:
		结论 = "失败：轮到过出手却整局没产生任何行动"
	elif _出牌次数 > 0 and _亮牌次数 == 0:
		结论 = "失败：出过牌但一次都没真正打出去（无亮牌广播）"
	elif _操作无效次数 > 0:
		结论 = "失败：有 %d 次操作被服务端驳回" % _操作无效次数
	var 行: String = "[联机%d] 结论=%s 房主=%s 座位=%d 界面=%s 出牌=%d 技能=%d 特殊=%d 换牌=%d 亮牌=%d 命中=%d 驳回=%d 错误=%d fps=%d 声音=%s" % [
		Cfg.slot, 结论, str(Net.hosting), Logic.my_player_id, 界面, _出牌次数, _技能次数, _特殊次数, _换牌次数, _亮牌次数, _命中次数,
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

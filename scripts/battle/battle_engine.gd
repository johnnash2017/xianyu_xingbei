class_name BattleEngine
extends RefCounted
## 权威战斗引擎（移植自服务端 DiceGameServer/GameGrail.cpp + GrailState.cpp）
##
## 设计：状态栈 + 等待回复。单线程下不能阻塞，所以每个状态 handle() 返回：
##   CONTINUE(0) —— 本状态已完成，从栈中移除
##   WAIT(1)     —— 正在等某玩家回复，停在这里；收到回复后再次 handle()
## 压栈约定：后压入的先执行（LIFO）。「先执行」的步骤要后 push。
##
## 角色钩子：SHook 状态对「每个玩家」按座位序调用同名钩子；角色返回 WAIT 则整个钩子轮次暂停。

const CONTINUE: int = 0
const WAIT: int = 1
const SUSPEND: int = 2

## 引擎里要单独处理的技能号见 GConst.技能_天使之墙

enum Phase { Idle, Playing, Over }

## 回复超时（毫秒）：普通玩家 60s；已掉线玩家 5s（避免队友长时间干等）
## 这个值就是「行动等待时间」—— 对局里所有要玩家回话的询问（行动/应战/技能/弃牌/魔弹传递…）都用它
const RESPONSE_TIMEOUT_MS: int = 60000
const OFFLINE_TIMEOUT_MS: int = 5000

## 【魔弹】的初始伤害（每被传递一次 +1）——值集中在 GConst.魔弹基础伤害，客户端头像提示读同一处
const MISSILE_BASE_POINT: int = GConst.魔弹基础伤害
## 主动攻击的基础伤害（攻击牌固定 2 点）。主动攻击的加成（如格斗【蓄力一击】+1、百式幻龙拳 +2）
## 只写进本次伤害，不应被「应战反击」继承——反击按基础值重建（见 SReattackGo）
const ATTACK_BASE_POINT: int = 2

var room_id: int = 0
## 房间名与房间设定人数：由服务端建房时写入，随 Game 快照下发，
## 房间准备界面据此显示房名与「已到 / 应到」人数
var room_name: String = ""
var room_max_player: int = 0
## 房间的「调试模式」：由房主建房时勾选，随 Game 快照下发。
## 只有开着时，房内玩家才能用测试指令（服务端 DebugReq 也会按它拦一道）
var room_debug: bool = false
## 房间里的观战者昵称：房间级状态，由 LocalServer 维护，随 Game 快照下发给房内所有人
var room_watchers: Array[String] = []
## 房间是不是正处于选角（选将）阶段：房间级状态，由 LocalServer 维护，随 Game 快照下发。
## 准备室的观战提示靠它区分「正在等待选角」和「正在等待开始」
var room_picking: bool = false
## 开局倒计时剩余毫秒（0 = 没在倒计时）：房间级状态，由 LocalServer 维护、随 Game 快照下发，
## 准备室据此显示「N 秒后开始」
var start_countdown_ms: int = 0
## 房间的「座位模式」（GConst.SeatMode）：由服务端建房时写入，开局时按它重排座位顺序。
## 乱序 = 谁坐哪个座位随机；间隔 = 两队沿座位交替（红蓝红蓝…），相邻座位永远是对手
var seat_mode: int = GConst.SeatMode.Random
var players: Dictionary = {}      # id -> BattlePlayer
var order: Array[int] = []        # 座位顺序（顺时针）
var deck: BattleDeck = BattleDeck.new()
var current_id: int = -1
var first_id: int = -1
var round_id: int = 1
var phase: int = Phase.Idle
var winner: int = -1

## 队伍数值，下标为颜色（0 蓝 / 1 红）
var team_morale: Array[int] = [0, 0]
var team_gem: Array[int] = [0, 0]
var team_crystal: Array[int] = [0, 0]
var team_grail: Array[int] = [0, 0]

## 发送回调：(目标id:int, 协议号:int, 字段:Dictionary) -> void
var send_cb: Callable = Callable()

## 状态机
var _states: Array = []
## 本回合要不要跳过行动阶段（虚弱拒绝 / 五系束缚拒绝）：轮到 SActionPhase 时它自己直接收尾进回合结束。
## 用标记而不是「把 SActionPhase 从栈里抠掉再压回合结束」，是为了不打断它上面还有的 p_boot / p_before_action 钩子
var skip_action_phase: bool = false
## 本次行动阶段放行的行动种类与是否允许「放弃行动」：对照原版 StateActionPhase(allowAction, canGiveUp)。
## 普通行动阶段 = Any + 不允许放弃；额外行动阶段 = 该额外行动声明的 allowAction + 允许放弃；
## 被【挑衅】时 = 只能攻击 + 允许放弃
var 行动允许: int = GConst.ActionType.Any
var 行动可放弃: bool = false
## 本次行动阶段是不是「额外行动」（额外行动阶段允许放弃，与「被挑衅」那种可放弃的普通阶段区分开）
var 行动额外: bool = false
## 本次行动阶段是否禁止「特殊行动」（购买/合成/提炼）。发动过「启动」技能后，行动阶段照旧继续，
## 但只能再攻击 / 法术，不能再走特殊行动（启动技与特殊行动互斥）
var 行动禁特殊: bool = false
## 测试指令「跳过自己回合」（战斗界面按 8）：记下是谁按的，行动阶段轮到他直接收尾（-1 = 无）
var 测试跳过回合: int = -1
## 角色的 p_after_turn_end 要求「接下来的回合还是他」时写这里（月女【苍白之月】），
## 轮到 SNextPlayer 时据此不轮转、直接重开他的回合（对照原版：角色把 StateAfterTurnEnd 弹掉，跳过轮转）
var 额外回合玩家: int = -1
## 各玩家上次记录的手牌数量（player_id -> 张数），用于在「手牌变化」时触发 p_hand_change
var _hand_counts: Dictionary = {}
## 各玩家上次记录的手牌上限（player_id -> 张数），用于在「手牌上限变化」时写日志
var _hand_maxes: Dictionary = {}
## 各玩家上次记录的指示物数量（player_id -> Array[int]），用于在「指示物变化」时写日志
var _token_counts: Dictionary = {}
## 各玩家上次记录的星石（player_id -> [宝石, 水晶]），只在「获得」时写日志
var _gems: Dictionary = {}
## 各阵营战绩区上次记录的星石（color -> [宝石, 水晶]），只在「获得」时写日志
var _team_energies: Dictionary = {}
## 各玩家最后一次下发的行动命令表（player_id -> Array）：快照刷新后重算，只有变了才重发询问
var _最后行动命令: Dictionary = {}
## 各玩家最近一次收到的询问（player_id -> {cmd_type, commands}）：重连回来时原样补发一次 ——
## 客户端手里没有询问就画不出行动 / 应战界面，只能干等超时被自动代打
var _最后询问: Dictionary = {}
var _await_id: int = -1
var _await_kind: int = -1
## 本次等待「归属」的状态实例（RefCounted）：只有它自己被 handle 时才认这份回复。
## 防止等待期间被补压在栈顶的新状态（边界检查补压的超限结算等）错取 / 覆盖玩家回复。
var _await_state: Variant = null
## 当前正在 handle 的状态实例（run 内逐状态设置）：wait_for 据此登记等待归属，
## has_reply / take_reply 据此判断「这份回复是不是发给我的」
var _当前状态: Variant = null
## 当前行动询问允许的行动种类（ask_action 写入）：快照里据此给客户端下发
## 「等待行动 / 等待攻击行动 / 等待法术行动」这类头像文案
var _pending_action_type: int = 0
var _reply: Dictionary = {}
var _has_reply: bool = false
## 当前等待的截止时刻（Time.get_ticks_msec() 口径，0 表示当前没有在等）
var wait_deadline_ms: int = 0
## 本次等待的总时长（毫秒）：客户端按「剩余/总时长」画进度条
var wait_total_ms: int = 0
## 「查询链」共用的截止时刻与总时长：同一条链（如女武神【军神威光】：二选一 → 选星石+目标）
## 逐段问时沿用第一次那份，不重算。中途收到回复会把 wait_deadline_ms / wait_total_ms 清零，
## 所以另存一份；每次重新计时的等待都会覆盖它们（见 wait_for）
var 链截止_ms: int = 0
var 链总时长_ms: int = 0
## 掉线玩家标记：player_id -> true
var offline_players: Dictionary = {}
## 最近一次询问（ask_respond / ask_skill）的询问号与参数（超时时据此构造默认回复）
var _pending_respond_id: int = 0
var _pending_args: Array = []
## 本次询问是不是「是否发动某技能」的技能询问（ask_skill=true / ask_respond=false）：
## 超时兜底要按它区分「技能询问」与应战、弃牌之类的通用应答，而不是靠询问号的大小去猜
var _pending_is_skill: bool = false
## 本次询问已收到的「分步应答」（客户端带 partial 标记的消息，如【剑气斩】在弹窗里选好「移除几点剑气」）：
## 只记下这一步的选择、不算最终回复；超时时若已收到它就据此继续（选好数量后超时＝自动释放），
## 没收到就按空回复处理（弹窗还没选就超时＝取消）
var _pending_partial: Dictionary = {}
var _running: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# ============================================================
# 房间内玩家登记（开局前）
# ============================================================
func add_player(pid: int, color: int, pname: String) -> void:
	if players.has(pid):
		return
	var bp: BattlePlayer = BattlePlayer.new(pid, color, pname)
	# 绑定引擎：BattlePlayer.tap 的 setter 靠它通知形态变化
	bp.engine = self
	players[pid] = bp
	if not order.has(pid):
		order.append(pid)
		order.sort()
	_rebuild_links()


func remove_player(pid: int) -> void:
	var 玩家: BattlePlayer = players.get(pid)
	if 玩家 == null:
		return
	玩家.解绑()
	players.erase(pid)
	_hand_counts.erase(pid)
	_hand_maxes.erase(pid)
	_token_counts.erase(pid)
	_gems.erase(pid)
	_最后行动命令.erase(pid)
	offline_players.erase(pid)
	order.erase(pid)
	_rebuild_links()


func set_color(pid: int, color: int) -> void:
	var p0: BattlePlayer = players.get(pid)
	if p0 != null:
		p0.color = color


func set_name(pid: int, pname: String) -> void:
	var p0: BattlePlayer = players.get(pid)
	if p0 != null:
		p0.player_name = pname


func set_ready(pid: int, v: bool) -> void:
	var p0: BattlePlayer = players.get(pid)
	if p0 != null:
		p0.ready = v


func all_ready() -> bool:
	if order.size() < 2:
		return false
	for pid: int in order:
		if not players[pid].ready:
			return false
	return true


## 红蓝两队当前的在座人数，下标与 team_morale / team_gem 等一致（0 蓝 / 1 红）
func team_counts() -> Array[int]:
	var 人数: Array[int] = [0, 0]
	for pid: int in order:
		match players[pid].color:
			GConst.RED: 人数[GConst.RED] += 1
			GConst.BLUE: 人数[GConst.BLUE] += 1
	return 人数


## 两队人数是否对等。不对等就不该开局：手动选边不受人数约束，而补位只能往人少的一边
## 加人、补不平，会开出 3 打 1、4 打 0 这种局
func is_team_balanced() -> bool:
	var 人数: Array[int] = team_counts()
	return 人数[GConst.RED] == 人数[GConst.BLUE]


## 未选边的玩家自动补到人数少的一边。
## 补位次序是打散的：谁被补进红队、谁进蓝队不带偏向
## （若按座位顺序依次补，排在第一位的房主就永远吃红）
func balance_colors() -> void:
	var 待补: Array[int] = []
	for pid: int in order:
		if players[pid].color == GConst.TEAM_NONE:
			待补.append(pid)
	if 待补.is_empty():
		# 没人没选边：直接返回（开局倒计时期间本函数每帧都会被调到，别白造随机数发生器）
		return
	var 人数: Array[int] = team_counts()
	var 随机: RandomNumberGenerator = RandomNumberGenerator.new()
	随机.randomize()
	_shuffle_arr(待补, 随机)
	for pid: int in 待补:
		if 人数[GConst.RED] <= 人数[GConst.BLUE]:
			players[pid].color = GConst.RED
			人数[GConst.RED] += 1
		else:
			players[pid].color = GConst.BLUE
			人数[GConst.BLUE] += 1


## 按房间的座位模式重排座位顺序（order）。
## 间隔 = 两队沿座位交替，相邻座位永远是对手；其余（乱序）= 谁坐哪个座位随机。
## 必须在 balance_colors() 之后调用（间隔模式要靠最终确定的队伍色来排），
## 且一局只调一次：排座会消耗随机数，连调两次会排出两个不同的座位顺序。
## 调用点在 LocalServer：定完队、进选角之前排一次，这样选角界面顶部的座位条
## 与实际座位是一致的。
func arrange_seats() -> void:
	var 随机: RandomNumberGenerator = RandomNumberGenerator.new()
	随机.randomize()
	if seat_mode == GConst.SeatMode.Interlace:
		_arrange_seats_interlace(随机)
	else:
		_shuffle_arr(order, 随机)


## 间隔：两队各自随机打散后一红一蓝交替落座（红蓝红蓝…）。
## 谁坐 0 号座位（先手）随机决定，所以「先手是红还是蓝」两种排法都会出现。
## 两队人数不等时（玩家自己挑了边、没走 balance_colors 配平）交替维持不住，
## 多出来的一队接着往后排，不越界。
func _arrange_seats_interlace(随机: RandomNumberGenerator) -> void:
	var 红队: Array[int] = []
	var 蓝队: Array[int] = []
	for pid: int in order:
		if players[pid].color == GConst.RED:
			红队.append(pid)
		else:
			蓝队.append(pid)
	_shuffle_arr(红队, 随机)
	_shuffle_arr(蓝队, 随机)
	var 先红: bool = 随机.randi_range(0, 1) == 0
	var 座位: Array[int] = []
	for i: int in maxi(红队.size(), 蓝队.size()):
		if 先红:
			if i < 红队.size():
				座位.append(红队[i])
			if i < 蓝队.size():
				座位.append(蓝队[i])
		else:
			if i < 蓝队.size():
				座位.append(蓝队[i])
			if i < 红队.size():
				座位.append(红队[i])
	order = 座位


func _rebuild_links() -> void:
	for i: int in range(order.size()):
		var 玩家: BattlePlayer = players[order[i]]
		玩家.pre_id = order[(i - 1 + order.size()) % order.size()]
		玩家.post_id = order[(i + 1) % order.size()]
	if not order.is_empty():
		first_id = order[0]


# ============================================================
# 开局
# ============================================================
func start(role_pool: Array) -> void:
	start_with_roles({}, role_pool)


## 用「选将阶段选定的角色」开局；role_map: player_id -> role_id
## 保留 start(pool) 的随机分配入口，二者共用同一套开局初始化
## 座位顺序不在这里排：调用方（LocalServer）定完队后先调 arrange_seats()，
## 这里只按已排好的 order 建座位邻接（先手 = order[0]）
func start_with_roles(role_map: Dictionary, role_pool: Array = []) -> void:
	_rng.randomize()
	deck = BattleDeck.new()
	deck.init_full()
	balance_colors()
	_rebuild_links()
	current_id = first_id
	round_id = 1
	phase = Phase.Playing
	winner = -1
	var base_morale: int = GConst.MORALE_8P if order.size() == 8 else GConst.MORALE_DEFAULT
	team_morale = [base_morale, base_morale]
	team_gem = [0, 0]
	team_crystal = [0, 0]
	team_grail = [0, 0]
	for pid: int in order:
		var 玩家: BattlePlayer = players[pid]
		玩家.hand_cards.clear()
		玩家.cover_cards.clear()
		玩家.basic_effects.clear()
		玩家.ready = true
	if role_map.is_empty():
		_assign_roles(role_pool)
	else:
		_assign_roles_by_map(role_map)
	# 角色构造：让角色做开局初始化（指示物等）
	for pid: int in order:
		var p2: BattlePlayer = players[pid]
		if p2.role != null:
			p2.role.call_hook("p_before_turn_begin", {"init": true})
	for pid: int in order:
		players[pid].add_hand_cards(deck.draw(GConst.START_HAND))
	_states.clear()
	_进度表.clear()
	_清空等待()
	_broadcast_game()
	broadcast(GConst.Msg.TurnBegin, {"id": current_id, "round": round_id})
	push(SCheckTurnStart.new())
	run()


func _assign_roles(role_pool: Array) -> void:
	var pool: Array = role_pool.duplicate()
	_shuffle_arr(pool, _rng)
	if pool.is_empty():
		return
	for i: int in range(order.size()):
		var pid: int = order[i]
		var rid: int = int(pool[i % pool.size()])
		var 玩家: BattlePlayer = players[pid]
		玩家.role_id = rid
		玩家.role = BattleRole.create(rid, 玩家, self)


## 按选将结果分配角色（role_map: player_id -> role_id）
func _assign_roles_by_map(role_map: Dictionary) -> void:
	for pid: int in order:
		var rid: int = int(role_map.get(pid, 0))
		if rid <= 0:
			continue
		var 玩家: BattlePlayer = players[pid]
		玩家.role_id = rid
		玩家.role = BattleRole.create(rid, 玩家, self)


func _shuffle_arr(a: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# ============================================================
# 状态机驱动
# ============================================================
## 分步流程的进度：每个「状态实例」（钩子轮次 SHook、主动技能 SkillRun、以及其它状态）
## 各持一份自己的进度表（键 = player_id），状态新建即从 0 开始。
## 取代了旧实现里「每轮清零所有角色 step + URGENT 快照 / 恢复 + _角色技能挂起 特判」那套补丁：
## 轮次之间、轮次与技能之间不再争用同一个 step；等待 / 挂起后回来继续同一实例，进度自然保留；
## 状态跑完即销毁对应进度。角色自身的持久进度（BattleRole._持久进度）只兜底「不在任何状态里」的调用。
var _进度表: Dictionary = {}
var _当前进度槽: Dictionary = {}
var _在进度流程: bool = false

func 在进度流程中() -> bool:
	return _在进度流程

func 取当前进度(pid: int) -> int:
	return int(_当前进度槽.get(pid, 0))

func 设当前进度(pid: int, 值: int) -> void:
	_当前进度槽[pid] = 值


## 取某状态实例的进度表（没有就新建）
func _进度槽(st: Variant) -> Dictionary:
	if not _进度表.has(st):
		_进度表[st] = {}
	return _进度表[st]


func run() -> void:
	if _running:
		return
	_running = true
	# 安全阀：单次驱动的状态处理上限，避免异常状态链把主线程卡死
	var budget: int = 20000
	while not _states.is_empty():
		# 终局（_game_over 已清空状态栈）后不再推进，也不做边界检查补压新状态
		if phase == Phase.Over:
			break
		budget -= 1
		if budget <= 0:
			break
		var idx: int = _states.size() - 1
		var st: Variant = _states[idx]
		# 分步流程：本次 handle 期间角色的 step 读写落到「本状态实例」的进度上；
		# 同时登记当前状态，供 wait_for 记录等待归属、供回复归属判定
		_当前状态 = st
		_当前进度槽 = _进度槽(st)
		_在进度流程 = true
		var r: int = st.handle(self)
		_在进度流程 = false
		_当前状态 = null
		# 本状态 handle 期间可能已分出胜负，立即停下，不再补压 / 结算
		if phase == Phase.Over:
			break
		if r == WAIT:
			# 等回复期间不做边界检查：那会在等待者之上补压新状态，
			# 玩家回复回来时被新状态错取（回复归属见 _await_state）
			break
		if r == SUSPEND:
			# 本状态请求「先执行我压入的新状态，之后再回来继续我」
			continue
		_check_hand_overflow()
		_check_cover_overflow()
		_check_hand_change()
		_check_token_change()
		_check_energy_change()
		if idx >= _states.size():
			break
		if _states[idx] == st:
			_states.remove_at(idx)
		else:
			break
	_running = false
	# 本轮推进期间攒下的快照在这里补发一次（见 _broadcast_game）
	if _快照待发:
		_快照待发 = false
		_发送对局快照()
	# 清掉已不在状态栈里的进度：handle 内部可能直接改动过状态栈，
	# 统一在这里回收，避免进度表随旧实例累积（规模 = 当前活跃状态数，开销可忽略）
	for k: Variant in _进度表.keys():
		if not _states.has(k):
			_进度表.erase(k)


func push(st: Variant) -> void:
	# 终局后不再受理任何新状态（避免残留流程在清栈后又被压回来）
	if phase == Phase.Over:
		return
	_states.append(st)


## 每个状态跑完后重新结算一次手牌超限。
## 对照原版：任何「加牌 / 改手牌上限」都会立刻触发超限结算（StateHandChange / setStateChangeMaxHand
## → setStateHandOverLoad）；这里放在状态边界上兜住角色脚本直接改上限、直接加牌的情况
## （引擎自己 push 的那几处照旧，重复的会因「栈里已排着一次结算」而跳过）
func _check_hand_overflow() -> void:
	for st: Variant in _states:
		if st is SHandOverflow:
			return
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp != null and pp.hand_cards.size() > pp.hand_cards_max:
			push(SHandOverflow.new())
			return


## 摸牌把手牌顶过上限时，带着「本次伤害」的上下文入队结算超限掉士气。
## 对照服务端 StateTimeline6 → setStateHandOverLoad(con->harm)：这一步不能交给通用的
## _check_hand_overflow 去补 —— 它创建的超限结算没有伤害上下文，而「最近一次伤害」是全局字段，
## 连续两人受法术伤害时前一个人的掉士气已经把它清零，后一个人就判不出「因法术伤害掉士气」
## （表现为【神之庇护】只结算一次）
func push_overload_with_harm(harm: Dictionary) -> void:
	var dst: BattlePlayer = players.get(int(harm.get("dst", -1)))
	if dst == null or dst.hand_cards.size() <= dst.hand_cards_max:
		return
	for st: Variant in _states:
		if st is SHandOverflow:
			return
	push(SHandOverflow.new(int(harm.get("cause", 0)), int(harm.get("type", GConst.HarmType.None))))


## 每个状态跑完后重新结算一次盖牌超限（对照服务端 StateCoverChange → setStateCoverOverLoad）。
## 盖牌超限只把超出上限的盖牌弃掉，不掉士气；由盖牌所有者自己选择弃哪几张（SCoverOverflow）。
func _check_cover_overflow() -> void:
	for st: Variant in _states:
		if st is SCoverOverflow:
			return
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp != null and pp.cover_cards_max > 0 and pp.cover_cards.size() > pp.cover_cards_max:
			push(SCoverOverflow.new())
			return


## 每个状态跑完后对比各玩家手牌数量：有变化就触发一次 p_hand_change
## （对照服务端 StateHandChange → PlayerEntity::p_hand_change；巫女【流血形态】靠它判断脱形态）
func _check_hand_change() -> void:
	_check_hand_max_change()
	for st: Variant in _states:
		if st is SRunHandChange:
			return
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null:
			continue
		var now: int = pp.hand_cards.size()
		if not _hand_counts.has(pid):
			_hand_counts[pid] = now
			continue
		if int(_hand_counts[pid]) != now:
			push(SRunHandChange.new(pid))
			return


## 每个状态跑完后对比各玩家手牌上限：有变化就往战斗日志写一条（与手牌数量同一类日志）
func _check_hand_max_change() -> void:
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null:
			continue
		var 现在: int = pp.hand_cards_max
		if not _hand_maxes.has(pid):
			_hand_maxes[pid] = 现在
			continue
		if int(_hand_maxes[pid]) == 现在:
			continue
		_播手牌日志(pp, "%s 的手牌上限 %d→%d" % [_称号(pp), int(_hand_maxes[pid]), 现在])
		_hand_maxes[pid] = 现在


## 手牌数量 / 上限变化日志（沿用【弃牌】那一类：GossipType.Discard → 日志里的 [卡牌]）
func _播手牌日志(pp: BattlePlayer, 文案: String) -> void:
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Discard,
		"txt": 文案,
		"id": pp.id,
	})


## 每个状态跑完后对比各玩家指示物数量：有变化就往战斗日志写一条（只记录，不改变流程）
## 注意：tokens 是未类型化的 Array，槽位可能是 null（角色未用到），要按 Variant 取
func _check_token_change() -> void:
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null:
			continue
		var 现在: Array[int] = []
		for t: Variant in pp.tokens:
			现在.append(int((t as Dictionary).get("num", 0)) if t is Dictionary else 0)
		if not _token_counts.has(pid):
			_token_counts[pid] = 现在
			continue
		var 上次: Array = _token_counts[pid]
		if 上次 == 现在:
			continue
		var 片段: Array[String] = []
		for i: int in range(mini(上次.size(), 现在.size())):
			if int(上次[i]) == 现在[i]:
				continue
			var 槽: Variant = pp.tokens[i]
			var 名: String = str((槽 as Dictionary).get("name", "指示物")) if 槽 is Dictionary else "指示物"
			片段.append("【%s】%d→%d" % [名, int(上次[i]), 现在[i]])
		if not 片段.is_empty():
			broadcast(GConst.Msg.Gossip, {
				"type": GConst.GossipType.Token,
				"txt": "%s 的%s" % [_称号(pp), "、".join(片段)],
				"id": pp.id,
			})
		_token_counts[pid] = 现在


## 每个状态跑完后对比各玩家与各阵营战绩区的星石：只在「获得」时写一条（消耗不必刷屏）。
## 个人写「谁获得 x 宝石 x 水晶」；战绩区写「哪一队战绩区 获得 x 宝石 x 水晶」。
## 只获得其中一类时就只写那一类（由 _星石片段 拼）
func _check_energy_change() -> void:
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null:
			continue
		var 个人现在: Array[int] = [pp.gem, pp.crystal]
		if not _gems.has(pid):
			_gems[pid] = 个人现在
			continue
		var 个人上次: Array = _gems[pid]
		if 个人上次 == 个人现在:
			continue
		var 个人片段: String = _星石片段(个人现在[0] - int(个人上次[0]), 个人现在[1] - int(个人上次[1]))
		if not 个人片段.is_empty():
			_播星石日志("%s 获得 %s" % [_称号(pp), 个人片段], pp.id)
		_gems[pid] = 个人现在
	for color: int in [GConst.RED, GConst.BLUE]:
		var 队伍现在: Array[int] = [team_gem[color], team_crystal[color]]
		if not _team_energies.has(color):
			_team_energies[color] = 队伍现在
			continue
		var 队伍上次: Array = _team_energies[color]
		if 队伍上次 == 队伍现在:
			continue
		var 队伍片段: String = _星石片段(队伍现在[0] - int(队伍上次[0]), 队伍现在[1] - int(队伍上次[1]))
		if not 队伍片段.is_empty():
			_播星石日志("%s 战绩区获得 %s" % [_阵营名(color), 队伍片段], -1)
		_team_energies[color] = 队伍现在


## 星石增减的文案片段：只写「获得了」的那一类（个人与战绩区共用）。
## 两类都没增加（含纯消耗）就返回空串，调用方据此不写日志
func _星石片段(宝石增量: int, 水晶增量: int) -> String:
	var 段: Array[String] = []
	if 宝石增量 > 0:
		段.append("%d 宝石" % 宝石增量)
	if 水晶增量 > 0:
		段.append("%d 水晶" % 水晶增量)
	return "、".join(段)


## 阵营名（战绩区日志用）
func _阵营名(color: int) -> String:
	return "红队" if color == GConst.RED else "蓝队"


## 星石获得日志：个人与战绩区共用，类别沿用「指示物」
func _播星石日志(文案: String, 相关玩家: int) -> void:
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Token,
		"txt": 文案,
		"id": 相关玩家,
	})


## 施加治疗（角色主动加治疗一律走这里，见 BattleRole.施加治疗）：写日志并按「输出量」记录 ——
## 即本次打算加多少点就写多少点，括号里给出治疗值的实际变化（目标接近上限时会只加进去一部分，
## 如上限 2、当前 1、加 2 点 → 日志写「加 2 点（治疗 1→2）」）。
func add_cross(pid: int, amount: int, src_id: int) -> void:
	if amount <= 0:
		return
	var pp: BattlePlayer = players.get(pid)
	if pp == null:
		return
	var 前: int = pp.cross_num
	pp.add_cross_num(amount)
	_播治疗日志(pp, amount, src_id, 前)


## 施加治疗（无视目标治疗上限）：封顶 > 0 时治疗后不超过它（<= 0 表示不额外封顶），
## 目标本来更高时保持不动（只加不减）。用于【神圣契约】这类「突破上限」的转移。
func add_cross_pierce(pid: int, amount: int, src_id: int, 封顶: int) -> void:
	if amount <= 0:
		return
	var pp: BattlePlayer = players.get(pid)
	if pp == null:
		return
	var 前: int = pp.cross_num
	var 新: int = 前 + amount
	if 封顶 > 0:
		新 = mini(新, 封顶)
	pp.cross_num = maxi(新, 前)
	_播治疗日志(pp, amount, src_id, 前)


## 治疗日志（按「输出量」记，与是否被上限截断无关）
func _播治疗日志(pp: BattlePlayer, amount: int, src_id: int, 前: int) -> void:
	var 来源: String = "自身" if src_id == pp.id else _称号(players.get(src_id))
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Heal,
		"txt": "%s 获得来自 %s 的 %d 点治疗（治疗 %d→%d）" % [_称号(pp), 来源, amount, 前, pp.cross_num],
		"id": pp.id,
		# 点数单独给一份：客户端据此决定头像上冒几个「+」，不必去解析日志文案
		"num": amount,
	})


## 交牌日志（不公开亮牌的「把牌交给别人」用）：交牌双方在日志里看到具体牌名，
## 其他人只看到张数 —— 所以按人分别下发，而不是一条广播。
func _log_give_cards(src_id: int, dst_id: int, cards: Array) -> void:
	if cards.is_empty():
		return
	var 名表: Array[String] = []
	for c: Variant in cards:
		var 牌: GCard = Data.get_card(int(c))
		名表.append("【%s】" % (牌.card_name if 牌 != null else str(int(c))))
	var 来源: String = _称号(players.get(src_id))
	var 去处: String = _称号(players.get(dst_id))
	var 详版: String = "%s 交给 %s %s" % [来源, 去处, "、".join(名表)]
	var 略版: String = "%s 交给 %s %d 张牌" % [来源, 去处, cards.size()]
	var 略条: Dictionary = {"type": GConst.GossipType.Discard, "txt": 略版, "id": src_id}
	for pid: int in order:
		var 条: Dictionary = 略条.duplicate()
		if pid == src_id or pid == dst_id:
			条["txt"] = 详版
		send(pid, GConst.Msg.Gossip, 条)
	# 观战者不在 order 里，收不到上面那份：单独补一条「略版」（牌面只有交牌双方看得到）
	send(GConst.GUEST, GConst.Msg.Gossip, 略条)
	# 顺带广播一个给牌动效：牌从交牌人飘到收牌人。
	# 不带 card_ids —— 这条是发给所有人的，带上就等于把牌面公开了（牌面只有交牌双方在日志里看得到）；
	# 只给张数，客户端据此「交几张就飞几张」
	broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Give,
		"src_id": src_id,
		"dst_id": dst_id,
		"card_ids": [],
		"count": cards.size(),
	})


## 开始等某玩家的回复。保留倒计时=true 时沿用「这条链」最早的截止时刻、不重新计时 ——
## 同一条询问链上的后续询问用它（如女武神【军神威光】：二选一 → 选星石+目标，
## 中途「点进去 / 退回来」都不该把倒计时刷新一遍）。截止时刻另存在 链截止_ms：
## 中途收到回复会把 wait_deadline_ms 清零，只认它才能跨过那一步
func wait_for(pid: int, kind: int, 保留倒计时: bool = false) -> void:
	_await_id = pid
	_await_kind = kind
	# 登记等待归属：这次回复只认「当前正在 handle 的这个状态实例」
	_await_state = _当前状态
	_has_reply = false
	if 保留倒计时 and 链截止_ms > 0:
		wait_deadline_ms = 链截止_ms
		wait_total_ms = 链总时长_ms
		# 广播一次对局信息，让所有客户端知道「现在在等谁、还剩多久」（界面据此画等待进度条）
		_broadcast_game()
		return
	# 登记截止时刻：掉线玩家用更短的超时，避免队友长时间干等
	var timeout: int = OFFLINE_TIMEOUT_MS if offline_players.has(pid) else RESPONSE_TIMEOUT_MS
	wait_deadline_ms = Time.get_ticks_msec() + timeout
	wait_total_ms = timeout
	链截止_ms = wait_deadline_ms
	链总时长_ms = wait_total_ms
	# 广播一次对局信息，让所有客户端知道「现在在等谁、还剩多久」（界面据此画等待进度条）
	_broadcast_game()


func has_reply() -> bool:
	# 只认「等待归属的那个状态」：别的状态（等待期间被补压到栈上的）取不到这份回复
	return _has_reply and _当前状态 == _await_state


func take_reply() -> Dictionary:
	# 非等待归属者不得读取，更不能顺带清掉这份回复
	if _当前状态 != _await_state:
		return {}
	# 注意：必须先取出引用再清空，否则返回的是空字典
	var r: Dictionary = _reply
	_has_reply = false
	_await_id = -1
	_await_state = null
	wait_deadline_ms = 0
	wait_total_ms = 0
	_reply = {}
	_pending_partial = {}
	return r


## 清掉等待 / 回复 / 分步应答 / 查询链倒计时等交互态：终局与新对局开始时统一收尾，
## 避免残留在这些字段里的回复被后续流程（或下一局复用同一引擎时）误用
func _清空等待() -> void:
	_await_id = -1
	_await_kind = -1
	_await_state = null
	_当前状态 = null
	_has_reply = false
	_reply = {}
	_pending_partial = {}
	wait_deadline_ms = 0
	wait_total_ms = 0
	链截止_ms = 0
	链总时长_ms = 0


func on_message(pid: int, kind: int, data: Dictionary) -> void:
	if _await_id != pid or kind != _await_kind:
		return
	# 分步应答（如【剑气斩】先在弹窗选好「移除几点剑气」）：只记下这一步，不算本次询问的最终回复，
	# 继续等玩家选目标 / 目标超时兜底时再拿它用
	if bool(data.get("partial", false)):
		_pending_partial = data
		return
	_reply = data
	_has_reply = true
	_await_id = -1
	wait_deadline_ms = 0
	wait_total_ms = 0
	# 等待已结束：先广播一次，客户端会收起等待进度条；随后 run() 若又进入等待会再广播
	_broadcast_game()
	run()


# ============================================================
# 回复超时（挂机/掉线的兜底：避免单个玩家不回消息把整局卡死）
# ============================================================
## 超时驱动：由服务端 poll 周期调用；单次 tick 只处理一次超时，不递归
func tick() -> void:
	if _await_id < 0 or _has_reply or wait_deadline_ms <= 0:
		return
	if Time.get_ticks_msec() < wait_deadline_ms:
		return
	var pid: int = _await_id
	var kind: int = _await_kind
	var 默认回复: Dictionary = _build_timeout_reply(pid, kind)
	if 默认回复.is_empty():
		# 普通行动阶段（canGiveUp=false）没有「放弃」兜底：原版 StateActionPhase 超时只返回 GE_TIMEOUT、
		# 不推进，但本地对局没有踢人/托管，干等会把整局卡死 —— 直接把这名玩家的行动阶段跳过。
		if kind == GConst.Msg.Action and not _states.is_empty() and _states[-1] is SActionPhase:
			(_states[-1] as SActionPhase).跳过 = true
			_has_reply = false
			_await_id = -1
			wait_deadline_ms = 0
			wait_total_ms = 0
			_notice_timeout(pid, kind, true)
			_broadcast_game()
			run()
			return
		# 其余没有超时兜底的询问：不发回复，公告一次后继续等玩家自己操作
		wait_deadline_ms = 0
		wait_total_ms = 0
		_broadcast_game()
		_notice_timeout(pid, kind, false)
		return
	# 构造默认回复（等价客户端点「放弃 / 不发动」）写入，交给状态机继续推进
	_提交默认回复(pid, kind, 默认回复)


## 把「默认回复」当成玩家答完了写进去、继续推进（超时兜底与测试键 0 共用）。
## 公告 = false 时不写「超时」日志（测试键不是超时）
func _提交默认回复(pid: int, kind: int, 默认回复: Dictionary, 公告: bool = true) -> void:
	_reply = 默认回复
	_has_reply = true
	_await_id = -1
	wait_deadline_ms = 0
	wait_total_ms = 0
	_broadcast_game()
	if 公告:
		_notice_timeout(pid, kind, true)
	run()


## 构造超时默认回复：与客户端「放弃 / 不发动」等价；返回空字典 = 这个询问不允许超时兜底
func _build_timeout_reply(pid: int, kind: int) -> Dictionary:
	if kind == GConst.Msg.Action:
		# 行动询问（ask_action 下发 CmdReq/Action）：对照原版 StateActionPhase 的超时分支——
		# 该阶段允许放弃（被挑衅 / 额外行动阶段）才按「放弃行动」收尾，否则不推进
		if not 行动可放弃:
			return {}
		return {
			"action_type": GConst.ActionType.None, "action_id": 0,
			"src_id": pid, "dst_ids": [], "card_ids": [], "args": [],
		}
	# 应答询问：按询问号选择默认项
	var rid: int = _pending_respond_id
	var args: Array = []
	if _pending_is_skill:
		# 技能询问（ask_skill）→ 不发动：回空 args，
		# 与客户端「取消」一致（0 留给正常的选项值，如【魔女之怒】的「摸 0 张牌」）
		# 「先弹选项」型若已收到分步应答（选好了选项值，如【剑气斩】选好剑气数），超时时带上它继续
		# （选好数量后超时＝自动释放；弹窗还没选就超时 → 仍回空 args＝取消）
		if not _pending_partial.is_empty():
			args = _pending_partial.get("args", [])
	elif rid == GConst.RespondType.ReplyAttack or rid == GConst.RespondType.Bullet:
		# 应战 / 魔弹传递 → 放弃（魔弹放弃＝承受伤害，面前有【圣盾】则自动挡下）
		args = [GConst.Reattack.GiveUp]
	elif rid == GConst.RespondType.Heal:
		# 治疗抵御 → 不使用（0 点）
		args = [0]
	elif rid == GConst.RespondType.AdditionalAction:
		# 额外行动 → 放弃
		args = []
	# Discard / DiscardCover / Weaken 等：card_ids 留空，引擎或角色会按「放弃 / 自动补齐」处理
	return {
		"respond_id": rid, "src_id": pid, "dst_ids": [],
		"card_ids": [], "args": args,
		# 标记「这是超时兜底」而非玩家主动取消：需要区分挂机与主动不发的角色脚本读它
		"is_timeout": true,
	}


## 超时公告
func _notice_timeout(pid: int, kind: int, 已处理: bool) -> void:
	var p0: BattlePlayer = players.get(pid)
	var pname: String = _称号(p0) if p0 != null else str(pid)
	var kind_name: String = "行动" if kind == GConst.Msg.Action else "应答"
	var txt: String = "%s %s超时，已自动处理" % [pname, kind_name] if 已处理 else "%s %s超时，仍在等其操作" % [pname, kind_name]
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Warn,
		"txt": txt,
		"id": 0,
	})


## 标记玩家掉线/上线；掉线时立刻把当前等待的截止时刻收紧到掉线超时
func set_offline(pid: int, v: bool) -> void:
	if offline_players.has(pid) == v:
		return
	if v:
		offline_players[pid] = true
	else:
		offline_players.erase(pid)
	var p0: BattlePlayer = players.get(pid)
	var pname: String = _称号(p0) if p0 != null else str(pid)
	# 同步到玩家身上：快照里的 online 就是它（客户端据此把「玩家列表」那一列显示成「掉线」）
	if p0 != null:
		p0.online = not v
	if v:
		if _await_id == pid and not _has_reply:
			wait_deadline_ms = Time.get_ticks_msec() + OFFLINE_TIMEOUT_MS
			wait_total_ms = OFFLINE_TIMEOUT_MS
			_broadcast_game()
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Warn,
			"txt": "%s 已掉线，超时将由系统自动代打" % pname,
			"id": 0,
		})
	else:
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Warn,
			"txt": "%s 已重新上线" % pname,
			"id": 0,
		})


# ============================================================
# 基础查询
# ============================================================
func p(pid: int) -> BattlePlayer:
	return players.get(pid)


func next_id(pid: int) -> int:
	var p0: BattlePlayer = players.get(pid)
	return p0.post_id if p0 != null else pid


func team_energy(c: int) -> int:
	return team_gem[c] + team_crystal[c]


func set_morale(c: int, v: int) -> void:
	team_morale[c] = maxi(v, 0)


func set_team_gem(c: int, v: int) -> void:
	team_gem[c] = clampi(v, 0, GConst.TEAM_ENERGY_MAX)
	_clamp_team_energy(c)


func set_team_crystal(c: int, v: int) -> void:
	team_crystal[c] = clampi(v, 0, GConst.TEAM_ENERGY_MAX)
	_clamp_team_energy(c)


func _clamp_team_energy(c: int) -> void:
	while team_gem[c] + team_crystal[c] > GConst.TEAM_ENERGY_MAX:
		if team_gem[c] > team_crystal[c]:
			team_gem[c] -= 1
		else:
			team_crystal[c] -= 1


# ============================================================
# 消息发送
# ============================================================
func send(target: int, msg_type: int, data: Dictionary) -> void:
	if send_cb.is_valid():
		send_cb.call(target, msg_type, data)


func broadcast(msg_type: int, data: Dictionary) -> void:
	send(-1, msg_type, data)


## 行动阶段询问（附带角色可选技能）
## can_give_up：本阶段是否允许「放弃行动」（对照原版 Coder::askForAction 的 canGiveUp 分支，
## 允许时额外下发一条 ACTION_NONE 命令，客户端据此显示「放弃行动」）
func ask_action(pid: int, action_type: int, can_give_up: bool = false, extra: bool = false, no_special: bool = false) -> void:
	_pending_action_type = action_type
	var cmds: Array = action_commands(pid, action_type, can_give_up, extra, no_special)
	_最后行动命令[pid] = cmds
	_询问(pid, GConst.CmdType.Action, cmds)


## 下发一条询问给某玩家，并把它记下来：玩家重连回来时照原样补发（见 重发当前询问）
func _询问(pid: int, cmd_type: int, commands: Array) -> void:
	_最后询问[pid] = {"cmd_type": cmd_type, "commands": commands}
	send(pid, GConst.Msg.CmdReq, {"cmd_type": cmd_type, "commands": commands})


## 玩家重新进房：把「正等他的那份询问」补发一次。
## 不补发的话客户端手里没有询问、画不出操作界面，只能干等到超时被自动代打 —— 等于白掉一次线
func 重发当前询问(pid: int) -> void:
	if _await_id != pid or not _最后询问.has(pid):
		return
	var 询问: Dictionary = _最后询问[pid]
	_询问(pid, int(询问["cmd_type"]), 询问["commands"])


## 重算「这名玩家此刻能放的技能」，有变化才重发一次行动询问。
## 手牌、能量、治疗、阵营这些都会影响能放的技能，所以不盯某一个字段，而是跟着对局快照（_broadcast_game）走：
## 每发一次快照就重算一遍 —— 快照本身很密，算完跟上次一样就不发，界面不会被打断。
## 只在「正等这名玩家做行动」时生效：别人的回合、或正在结算的时候不动他的界面
func _刷新技能可用(pid: int) -> void:
	if _await_id != pid or _await_kind != GConst.Msg.Action:
		return
	var cmds: Array = action_commands(pid, 行动允许, 行动可放弃, 行动额外, 行动禁特殊)
	if str(cmds) == str(_最后行动命令.get(pid, [])):
		return
	_最后行动命令[pid] = cmds
	_询问(pid, GConst.CmdType.Action, cmds)


## 行动询问的命令表：第 0 项是通用行动（允许放弃时再补一项「放弃」），其余是当前手牌下该角色能放的技能
func action_commands(pid: int, action_type: int, can_give_up: bool, extra: bool = false, no_special: bool = false) -> Array:
	var cmds: Array = [{
		"respond_id": action_type, "src_id": pid,
		"dst_ids": [], "card_ids": [], "args": [],
		# 额外行动阶段：客户端据此把提示写成「获得额外攻击行动 / 额外法术行动 / 额外行动」
		"is_extra": extra,
		# 禁止特殊行动（发动过「启动」技能后）：客户端据此把「特殊行动」按钮收掉
		"no_special": no_special,
	}]
	if can_give_up:
		cmds.append({
			"respond_id": GConst.ActionType.None, "src_id": pid,
			"dst_ids": [], "card_ids": [], "args": [],
		})
	var pl: BattlePlayer = players.get(pid)
	if pl != null and pl.role != null:
		# 本阶段「普通行动」能用的手牌白名单（如【修罗连斩】额外攻击期间只能出火系攻击牌）：
		# 非空时下发给界面，客户端据此把其余手牌置灰
		var 行动牌: Array = pl.role.action_card_ids(action_type)
		if not 行动牌.is_empty():
			cmds[0]["card_ids"] = 行动牌
		for sk: Dictionary in pl.role.available_skills():
			# 「启动」技能每回合只能发动一个：本回合已发动过就整条不再下发
			# （「启动」都是特殊技能；同一个技能号另有攻击 / 法术入口时不受这条限制）
			if pl.boot_skill_used and int(sk.get("type", 0)) == GConst.ActionType.SpecialSkill \
					and pl.role.is_free_skill(int(sk.get("id", 0))):
				continue
			# 声明了 targets 就等于「本次目标受限」：一个合法目标都没有时这条技能整条不发。
			# 空列表在协议/客户端那里等于「不限制」（_玩家可选），会让本该被挡住的人
			# （如已有【圣盾】/【天使之墙】的目标）反而变成能点，点了又被服务端拒。
			if sk.has("targets") and (sk.get("targets", []) as Array).is_empty():
				continue
			cmds.append({
				"respond_id": int(sk.get("type", 0)), "src_id": pid,
				# targets 非空时，客户端只把这几名玩家点亮（如【魔弹融合】的落点固定是右手边最近的对手）
				"dst_ids": sk.get("targets", []),
				# cards 非空时，客户端只让这几张牌可点（如【暗影流星】只能弃法术牌）
				"card_ids": sk.get("cards", []),
				# card_max 非空时，客户端点选上限放宽到它（如【欺诈】弃 2~3 张）
				"card_max": int(sk.get("card_max", 0)),
				# arg_choices 非空时，客户端把每项渲染成一个按钮，点哪个就用当前已选的牌/目标提交该项 args
				# （如【冒险者天堂】选要用哪些星石）
				"arg_choices": sk.get("arg_choices", []),
				# card_rule 非空时客户端限制可点牌（same＝必须同系 / diff＝必须互异系 /
				# magic＝只能法术牌 / sameprop＝必须与已选牌同命格）
				"card_rule": str(sk.get("card_rule", "")),
				# card_prompt 非空时客户端用它替代默认的「从手牌中选 N 张」发动提示
				# （如【充能】的发动代价是「弃到 4 张牌」，说「选 4 张」不准确）
				"card_prompt": str(sk.get("card_prompt", "")),
				# 目标数上限随已选牌数变化的减数（0＝不适用）：上限 = 已选牌数 - 该值，至少 1 名
				# （如【圣洁法典】＝弃牌数 - 2；玩家取消一张牌后上限随之变小）
				"target_max_from_cards": int(sk.get("target_max_from_cards", 0)),
				# 逐张选牌的条件（0＝不要求）：第 1 张须带某技能 / 第 2 张须为某系
				# （如元素师独有法术：第 1 张是带该技能的发动牌，第 2 张是加伤的该系牌）
				"card_slot_skill": int(sk.get("card_slot_skill", 0)),
				"card_slot_element": int(sk.get("card_slot_element", 0)),
				# 手牌 + 盖牌混选时，要求其中几张必须是盖牌（如【魔贯冲击】：1 张攻击牌 + 1 张火系【充能】）
				"cover_need": int(sk.get("cover_need", 0)),
				# args = [技能号, 最少选牌, 最少选目标, 最多选目标, 选牌来源]
				"args": [int(sk.get("id", 0)), int(sk.get("need_card", 0)), int(sk.get("need_target", 0)),
					int(sk.get("target_max", 0)), int(sk.get("card_source", GConst.CardSource.Hand))],
			})
	return cmds


func ask_respond(pid: int, respond_id: int, args: Array, dst_ids: Array = [], src_id: int = -1) -> void:
	# 记录本次询问，供超时构造默认回复
	_pending_respond_id = respond_id
	_pending_args = args.duplicate()
	_pending_is_skill = false
	_pending_partial = {}
	_询问(pid, GConst.CmdType.Respond, [{
		"respond_id": respond_id,
		"src_id": src_id if src_id >= 0 else pid,
		"dst_ids": dst_ids,
		"card_ids": [],
		"args": args,
	}])


## 询问某玩家是否发动某技能（客户端表现为「确定/取消」）
## need_card/need_target 告诉客户端本技能需要选出几张牌 / 几个目标
## card_source 为 GConst.CardSource：选牌来源（手牌 / 盖牌 / 两者皆可），如蝶舞的毒粉需指定一张【茧】
## options 非空时客户端改为渲染「选项按钮」，点击即以该项的 value 作为回复的 args[0]。
## 选项项还可带 "skill_id"（>0 表示这一项本身就是个技能，如【蓄力一击】/【风怒追击】）：
## 客户端鼠标指向该选项按钮时按它弹技能说明（同普通技能按钮）
## 编码约定（客户端解析）：args = [need_card, need_target, card_source, 选项数, 选项值…]，
## 选项文案放在同一条命令的 notes 里，与选项值一一对应；选项技能号放在 option_skill_ids 里（同序）
## card_max 给点选上限（省略或 0＝刚好 need_card 张，如【法术反弹】可弃 1~N 张同系牌）
## card_rule 给选牌规则（""＝不限 / "same"＝必须同系 / "diff"＝必须互异系 /
## "magic"＝只能选法术牌 / "sameprop"＝必须与已选牌同命格）
## cards 给合法牌白名单（非空时客户端只让这几张牌可点，如【魔能反转】只能弃法术牌）
## can_cancel 为 false 时客户端把「取消」置灰（强制询问，如【水之神力】的交牌）
## ask_text 非空时客户端改用它当指令条文案：内容取自技能表「提示」列里对应的那一条
## （问谁、读第几条由角色脚本自己定，如【天使祝福】的「请选择 1 张手牌交给 天使[x]」）
## targets 非空时客户端只让这几名玩家可点（need_target 为 0 时头像本来就点不动，
## 这时它只当「这次伤害落在谁身上」用，如【魔纹融合】/【战纹碎击】把伤害数写在目标头像上）
## 预览基准 非 0 时随询问下发（preview_base）：客户端现算头像提示要用到的数值
## （如【战纹碎击】里本次攻击原本的伤害、【双重回响】要复制的那份伤害）
## 预览类型 非 0 时随询问下发（preview_kind）：上面那个数值的类型（GConst.HarmType），
## 供客户端按伤害类型措辞 / 上色（如【朝圣】写「法术伤害」还是「攻击伤害」）
## 预览目标 非空时随询问下发（preview_ids）：现算头像提示要画在哪几名角色身上，
## 当它与「可点目标（targets）」不是同一批时用（如【英灵召唤】伤害 +1 要写在本次攻击目标头像上）
## 保留倒计时=true 时沿用这条链当前那次等待的截止时刻（见 wait_for），用于同一条链上的后续询问
func ask_skill(pid: int, skill_id: int, need_card: int = 0, need_target: int = 0, card_source: int = GConst.CardSource.Hand, options: Array = [], card_max: int = 0, card_rule: String = "", cards: Array = [], can_cancel: bool = true, ask_text: String = "", targets: Array = [], 预览基准: int = 0, 预览类型: int = 0, 保留倒计时: bool = false, 预览目标: Array = []) -> void:
	var args: Array = [need_card, need_target, card_source, options.size()]
	var notes: Array = []
	var 选项技能号: Array = []
	var 选项需牌: Array = []
	var 选项目标: Array = []
	var 有选项目标: bool = false
	for o: Dictionary in options:
		args.append(int(o.get("value", 0)))
		notes.append(str(o.get("label", "")))
		选项技能号.append(int(o.get("skill_id", 0)))
		选项需牌.append(int(o.get("need_card", 0)))
		var 目标: Array = o.get("targets", [])
		选项目标.append({"ids": 目标})
		if not 目标.is_empty():
			有选项目标 = true
	var cmd: Dictionary = {
		"respond_id": skill_id,
		"src_id": pid,
		# 显式标记这是技能询问（客户端据此进入技能询问界面，不用拿询问号大小去猜）
		"is_skill": true,
		# targets 非空时客户端只让这几名玩家可点（如【天使之歌】只能选面前有基础效果的人）
		"dst_ids": targets,
		"card_ids": cards,
		"args": args,
		"card_max": maxi(need_card, card_max),
		"card_rule": card_rule,
		# 只有「不能取消」才下发这个字段（客户端拿不到就按可以取消处理）
		"can_cancel": can_cancel,
	}
	if not notes.is_empty():
		cmd["notes"] = notes
	# 有「本身就是技能」的选项时才下发（如【蓄力一击】/【气绝崩击】），客户端据此让这些选项悬停弹技能说明
	if not 选项技能号.is_empty() and 选项技能号.max() > 0:
		cmd["option_skill_ids"] = 选项技能号
	# 有「选中后要弃牌」的选项时才下发（如【魔纹融合】）：客户端选到该项才放出手牌可选
	if not 选项需牌.is_empty() and 选项需牌.max() > 0:
		cmd["option_need_cards"] = 选项需牌
	# 有「各自目标白名单」的选项时才下发（如吟游诗人【希望赋格曲】的「放置」不含自己、
	# 「转移」含自己）：客户端选中某项后按它收紧可点头像（未选＝按并集）
	if 有选项目标:
		cmd["option_targets"] = 选项目标
	# 客户端现算头像提示要用的基准数值（如【战纹碎击】要显示「原伤害 + 弃牌加伤」、
	# 【双重回响】要显示它复制出来的那份伤害）
	if 预览基准 > 0:
		cmd["preview_base"] = 预览基准
	if 预览类型 > 0:
		cmd["preview_kind"] = 预览类型
	# 头像提示画在这些角色身上（非空时用它，否则沿用 dst_ids）：见 ask_skill 顶部「预览目标」
	if not 预览目标.is_empty():
		cmd["preview_ids"] = 预览目标
	# 询问别人的场合（如请人交牌）：下发目标侧文案，客户端优先显示它
	if not ask_text.is_empty():
		cmd["ask_text"] = ask_text
	_pending_respond_id = skill_id
	_pending_args = args.duplicate()
	_pending_is_skill = true
	_pending_partial = {}
	_询问(pid, GConst.CmdType.Respond, [cmd])
	wait_for(pid, GConst.Msg.Respond, 保留倒计时)


## 当前等待的说明文案：给「被等的那名玩家」写在头像上，说明大家正在等他做什么
## （对照参考工程 PlayerActionChange 的文案；没有在等任何人时返回空串）
func _等待文案() -> String:
	if _await_id < 0:
		return ""
	# 行动询问：按允许的行动种类区分「等待行动 / 等待攻击行动 / 等待法术行动」
	if _await_kind == GConst.Msg.Action:
		match _pending_action_type:
			GConst.ActionType.Attack: return "等待攻击行动"
			GConst.ActionType.Magic: return "等待法术行动"
			GConst.ActionType.None: return "等待响应无法行动"
			_: return "等待行动"
	# 技能询问：写「等待响应 + 技能名」
	if _pending_is_skill:
		return "等待响应" + GConst.skill_name(_pending_respond_id)
	# 应答询问：按询问号区分应战 / 弃牌 / 弃盖牌 / 治疗 / 虚弱 / 魔弹 / 额外行动
	match _pending_respond_id:
		GConst.RespondType.ReplyAttack: return "等待应战响应"
		GConst.RespondType.Bullet: return "等待魔弹响应"
		GConst.RespondType.Heal: return "等待治疗响应"
		GConst.RespondType.Discard: return "等待弃牌响应"
		GConst.RespondType.Weaken: return "等待虚弱响应"
		GConst.RespondType.AdditionalAction: return "等待响应额外行动"
		GConst.RespondType.DiscardCover: return "等待弃盖牌响应"
		GConst.RespondType.Role: return "等待选择角色"
		GConst.RespondType.InsertBan: return "等待禁选"
	return "等待响应"


func game_info(viewer_id: int) -> Dictionary:
	var infos: Array = []
	for pid: int in order:
		infos.append(players[pid].to_proto(viewer_id))
	# 当前在等谁回复、还剩多久（客户端据 wait_pid 在对应玩家面板底部画进度条）
	var 剩余: int = 0
	if _await_id >= 0 and wait_deadline_ms > 0:
		剩余 = maxi(wait_deadline_ms - Time.get_ticks_msec(), 0)
	return {
		"room_id": room_id,
		"room_name": room_name,
		"max_player": room_max_player,
		"debug": room_debug,
		"watchers": room_watchers,
		"picking": room_picking,
		"player_id": viewer_id,
		"red_morale": team_morale[GConst.RED],
		"blue_morale": team_morale[GConst.BLUE],
		"red_gem": team_gem[GConst.RED],
		"blue_gem": team_gem[GConst.BLUE],
		"red_crystal": team_crystal[GConst.RED],
		"blue_crystal": team_crystal[GConst.BLUE],
		"red_grail": team_grail[GConst.RED],
		"blue_grail": team_grail[GConst.BLUE],
		"pile": deck.pile_size(),
		"discard": deck.discard_size(),
		"is_started": phase != Phase.Idle,
		"player_infos": infos,
		"wait_pid": _await_id,
		"wait_ms": 剩余,
		"wait_total_ms": wait_total_ms,
		"wait_text": _等待文案(),
		"start_countdown_ms": start_countdown_ms,
	}


## 对局快照广播：一次状态推进里它会被连着调很多次（每改一点数据就调一次）。原地直发的话
## 一帧能发几十份全量快照，客户端每收到一份就整体重建战斗界面（实测逻辑耗时飙到 300ms+、帧率掉到个位数）。
## 所以状态机推进期间（_running）只做「待发」标记，等本轮 run 收尾统一发一次；
## run 之外的调用（tick / 收尾等）仍立即发，行为不变。
var _快照待发: bool = false


func _broadcast_game() -> void:
	if _running:
		_快照待发 = true
		return
	_发送对局快照()


func _发送对局快照() -> void:
	for pid: int in order:
		send(pid, GConst.Msg.Game, game_info(pid))
		# 快照一刷新就顺带重算「他能放哪些技能」（没变不会重发，见 _刷新技能可用）
		_刷新技能可用(pid)


## 应战的反击目标是否合法（对照服务端 PlayerEntity::v_reattack）：
## 必须是存在的其它玩家，不能是自己、不能是原攻击者、不能是同队
func _reattack_target_ok(defender: BattlePlayer, dst_id: int, origin_src: int) -> bool:
	if defender == null or dst_id < 0 or dst_id == defender.id or dst_id == origin_src:
		return false
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return false
	return dst.color != GConst.TEAM_NONE and dst.color != defender.color


## 本次攻击「命中时才会结算」的加伤合计（只用于给被攻击者看提示，不改变实际结算）。
## 问一遍攻击者的角色（p_attack_preview）：如魔剑士【暗影之力】+1、魔枪【暗之解放】+1。
func _预告加伤(src: int, ctx: Dictionary) -> int:
	var 攻击者: BattlePlayer = players.get(src)
	if 攻击者 == null or 攻击者.role == null:
		return 0
	return 攻击者.role.p_attack_preview(ctx)


# ============================================================
# 牌操作辅助
# ============================================================
func draw(pid: int, n: int) -> Array:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return []
	var cards: Array[int] = deck.draw(n)
	p0.add_hand_cards(cards)
	return cards


## 发牌（可被角色响应）：先跑 p_before_draw 钩子（角色可询问该玩家是否发动响应，如暗杀者【水影】），
## 再真正摸牌。钩子与摸牌都排进状态栈，故钩子里可以等待玩家输入。
## 【特殊行动】（购买 / 合成）的摸牌不走这里 —— 技能表里「水影」等响应写明「除【特殊行动】外」。
func push_draw(pid: int, n: int, cause: int = 0) -> void:
	if n <= 0:
		return
	push(SDraw.new(pid, n))
	push(SHook.new("p_before_draw", {"player": pid, "count": n, "cause": cause}, []))


func to_discard(cards: Array) -> void:
	deck.push_discard(cards)


## 战斗日志里称呼玩家的统一写法：角色名[玩家名]
func _称号(pp: BattlePlayer) -> String:
	if pp == null:
		return "?"
	return "%s[%s]" % [pp.player_name, Data.role_name(pp.role_id)]


## 广播「弃牌」日志：某玩家把手牌 / 盖牌里的若干张送进弃牌堆时，写一条日志（只报张数）。
## 供玩家主动选牌的弃牌点调用（手牌超限 / 盖牌超限 / 技能要求弃牌）。
## 播特效=false：这次弃牌已经把牌亮给所有人看过（Show 广播），只写日志、不再播弃牌特效
func _log_discard(pid: int, cards: Array, 播特效: bool = true) -> void:
	if cards.is_empty():
		return
	var pp: BattlePlayer = players.get(pid)
	if pp == null:
		return
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Discard,
		"txt": "%s 弃掉 %d 张牌" % [_称号(pp), cards.size()],
		"id": pp.id,
		# 张数单独给一份：客户端据此播弃牌特效（其余 Discard 类日志不带 num，按 0 处理）
		"num": cards.size() if 播特效 else 0,
	})


## 广播「基础效果被移除」日志，说清「谁移除了谁面前的什么状态」。
## doer_id 是发动者（-1 表示引擎内部结算，如【圣盾】挡下攻击、【中毒】结算：没有发动者，只写被移除方）
func _log_basic_effect_remove(doer_id: int, dst_id: int, card_id: int) -> void:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return
	var 牌: GCard = Data.get_card(card_id)
	var 牌名: String = 牌.card_name if 牌 != null else str(card_id)
	var 谁: BattlePlayer = players.get(doer_id)
	var 文案: String = "%s 面前的【%s】被移除" % [_称号(dst), 牌名]
	if 谁 != null:
		文案 = "%s 移除了 %s 面前的【%s】" % [_称号(谁), _称号(dst), 牌名]
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Discard,
		"txt": 文案,
		"id": dst_id,
	})


## 盖牌变动入口（对照服务端 StateCoverChange）：立刻加/减盖牌并广播，随后对全体跑
## p_cover_change（doer 为本次变动发起者，direction 见 GConst.CHANGE_*）。
## 盖牌超限由状态边界的 _check_cover_overflow 结算。
func add_cover(dst_id: int, cards: Array, src_id: int, cause: int) -> void:
	_apply_cover_change(dst_id, GConst.CHANGE_ADD, cards, src_id, cause)


func remove_cover(dst_id: int, cards: Array, src_id: int, cause: int) -> void:
	_apply_cover_change(dst_id, GConst.CHANGE_REMOVE, cards, src_id, cause)


func _apply_cover_change(dst_id: int, direction: int, cards: Array, src_id: int, cause: int) -> void:
	if cards.is_empty():
		return
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return
	if direction == GConst.CHANGE_ADD:
		dst.add_cover_cards(cards)
	else:
		dst.remove_cover_cards(cards)
	_broadcast_game()
	push(SHook.new("p_cover_change", {
		"dst": dst_id, "direction": direction,
		"howMany": cards.size(), "cards": cards.duplicate(),
		"doer": src_id, "cause": cause,
	}, []))


## 已展示 = true 时顺手触发「展示手牌」钩子（封印师的水/火/地/风/雷之封印靠它结算）——
## 对应服务端 GameGrail::setStateMoveCards 的 isShown：只要这张牌是公开打出/展示给全场看的，
## 就必须带这个标记（藏在调用点里声明，别再各写一遍 push_show_hand）。
## 时机：要在本函数所有 push 之后再调用，「展示手牌」钩子才会压在这些效果之上先结算（同服务端 LIFO）。
func take_from_hand(pid: int, card_ids: Array, 已展示: bool = false) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return false
	for c: Variant in card_ids:
		if not p0.has_hand_card(int(c)):
			return false
	p0.remove_hand_cards(card_ids)
	if 已展示:
		push_show_hand(pid, card_ids)
	return true


## 测试用（战斗界面里的数字键，见 GConst.DebugKey）：给自己发圣光 / 测试牌、按技能发技能牌、双方士气 99、
## 自己的标识物 / 治疗 / 宝石开关式拉满、跳过当前行动玩家的回合等。
## 技能牌 = 卡表里技能属于该角色的牌：角色技能号取自 角色表（Data.role_skills），
## 卡牌自带技能号（技能1 / 技能2 列）；每个技能随机抽一张，手里已有的不算候选。
func debug_key(pid: int, kind: int) -> void:
	if phase != Phase.Playing:
		return
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return
	if kind == GConst.DebugKey.GiveHolyLight:
		# 测试用（战斗界面按 1）：给自己发 4 张【圣光】（挑 4 张不同牌号的，免得手里出现重复牌号）
		var 圣光候选: Array[int] = []
		for cid: int in range(GConst.CARDSUM):
			if p0.has_hand_card(cid):
				continue
			var c: GCard = Data.get_card(cid)
			if c != null and c.card_name_enum() == GConst.CardName.HolyLight:
				圣光候选.append(cid)
		圣光候选.shuffle()
		for i: int in range(mini(4, 圣光候选.size())):
			_发一张到手里(p0, 圣光候选[i])
	elif kind == GConst.DebugKey.SkillCards:
		for 技能号: int in Data.role_skills(p0.role_id):
			var 候选: Array[int] = []
			for cid: int in range(GConst.CARDSUM):
				if p0.has_hand_card(cid):
					continue
				var c: GCard = Data.get_card(cid)
				if c != null and c.has_skill_id(技能号):
					候选.append(cid)
			if 候选.is_empty():
				continue
			var 抽: int = 候选[_rng.randi_range(0, 候选.size() - 1)]
			_发一张到手里(p0, 抽)
	elif kind == GConst.DebugKey.ToggleCards:
		# 测试用（战斗界面按 3）：手里有牌就先清空（全部进弃牌堆），空手就发测试牌 ——
		# 3 张随机同系攻击牌（斩）+ 3 张随机不同系别的法术牌
		if p0.hand_cards.is_empty():
			_发测试牌(p0, 3, true, true)
			_发测试牌(p0, 3, false, false)
		else:
			to_discard(p0.hand_cards.duplicate())
			p0.hand_cards.clear()
	elif kind == GConst.DebugKey.ShortenWait:
		# 测试用（战斗界面按 4）：把当前正在进行的询问倒计时压到 1 秒（到点走超时兜底）
		if _await_id >= 0 and wait_deadline_ms > 0:
			wait_total_ms = 1000
			wait_deadline_ms = Time.get_ticks_msec() + 1000
	elif kind == GConst.DebugKey.MoraleFull:
		# 测试用（战斗界面按 5）：双方士气拉到 99（怎么挨打都还有剩）
		for c: int in [GConst.RED, GConst.BLUE]:
			set_morale(c, 99)
	elif kind == GConst.DebugKey.SkipTurn:
		# 测试用（战斗界面按 0）：
		# 1) 正等某人应答（弃牌 / 应战 / 是否发动…）→ 替他把这次询问取消掉
		#    （与超时兜底同一条路：能安全放弃或自动补齐的才处理，其余照旧等他自己操作）；
		# 2) 否则跳过「当前正在行动」的那名玩家这一回合（不限于按键盘的人），只在「正等某人做行动」时有效，
		#    交给行动阶段自己收尾（不在引擎外直接推动状态栈，免得留下没跑完的旧状态）
		if _await_id >= 0 and _await_kind == GConst.Msg.Respond:
			var 被等的人: int = _await_id
			var 默认回复: Dictionary = _build_timeout_reply(被等的人, _await_kind)
			if not 默认回复.is_empty():
				_提交默认回复(被等的人, _await_kind, 默认回复, false)
				return
		if _await_id >= 0 and _await_kind == GConst.Msg.Action:
			测试跳过回合 = _await_id
			run()
	elif kind == GConst.DebugKey.ToggleTokens:
		# 测试用（战斗界面按 6）：自己的标识物（指示物）拉满 ↔ 再按清空
		var 已有值: bool = false
		for t: Variant in p0.tokens:
			if t != null and int((t as Dictionary).get("num", 0)) > 0:
				已有值 = true
				break
		for t2: Variant in p0.tokens:
			if t2 == null:
				continue
			var 槽2: Dictionary = t2
			槽2["num"] = 0 if 已有值 else int(槽2.get("max", 0))
	elif kind == GConst.DebugKey.RandomEnergy:
		# 测试用（战斗界面按 7）：战绩区已经有星石 → 再按清空；是空的 → 按战绩区上限逐颗随机填成宝石 / 水晶
		# （总数恰好等于上限，故直接累加，不走 set_team_gem/set_team_crystal 的夹取）
		var 已有星石: bool = (
			team_gem[GConst.RED] > 0
			or team_crystal[GConst.RED] > 0
			or team_gem[GConst.BLUE] > 0
			or team_crystal[GConst.BLUE] > 0
		)
		for c: int in [GConst.RED, GConst.BLUE]:
			team_gem[c] = 0
			team_crystal[c] = 0
			if 已有星石:
				continue
			for _i: int in range(GConst.TEAM_ENERGY_MAX):
				if _rng.randi_range(0, 1) == 0:
					team_gem[c] += 1
				else:
					team_crystal[c] += 1
	elif kind == GConst.DebugKey.ToggleHeal:
		# 测试用（战斗界面按 8）：自己的治疗拉满 ↔ 再按清零
		if p0.cross_num > 0:
			p0.cross_num = 0
		else:
			p0.add_cross_num(p0.cross_max)
	elif kind == GConst.DebugKey.ToggleGem:
		# 测试用（战斗界面按 9）：自己的宝石补满 ↔ 再按清空
		if p0.gem > 0:
			p0.set_gem(0)
		else:
			p0.set_gem(p0.energy_max)
	# 手牌 / 能量 / 治疗一变，这一回合能放的技能也可能跟着变（如【神圣祈福】要 2 张法术牌）：
	# 快照里会顺带重算一次技能可用性，变了才重发询问
	_broadcast_game()


## 测试发牌：把这张牌从牌堆 / 弃牌堆拿走再加进手里（避免同一张牌凭空多出来）
func _发一张到手里(p0: BattlePlayer, cid: int) -> void:
	deck.remove_one(cid)
	p0.add_hand_cards([cid])


## 测试发牌：给某玩家发 count 张牌。
## 要攻击 = true 发攻击牌（斩）、false 发法术牌；同系 = true 这 count 张要同一种系别，
## false 则要互不相同的系别。候选只从「手里还没有的牌」里挑。
func _发测试牌(p0: BattlePlayer, count: int, 要攻击: bool, 同系: bool) -> void:
	var 分组: Dictionary = {}
	for cid: int in range(GConst.CARDSUM):
		if p0.has_hand_card(cid):
			continue
		var c: GCard = Data.get_card(cid)
		if c == null or c.is_attack() != 要攻击:
			continue
		var e: int = c.element_enum()
		if not 分组.has(e):
			分组[e] = []
		(分组[e] as Array).append(cid)
	var 系别表: Array = 分组.keys()
	系别表.shuffle()
	var 已发: int = 0
	for e2: Variant in 系别表:
		if 已发 >= count:
			break
		var 候选: Array = 分组[e2]
		候选.shuffle()
		if 同系:
			if 候选.size() < count:
				continue
			for k: int in range(count):
				_发一张到手里(p0, int(候选[k]))
			已发 = count
		else:
			_发一张到手里(p0, int(候选[0]))
			已发 += 1


func _find_basic_card(p0: BattlePlayer, name_enum: int) -> int:
	for be: Dictionary in p0.basic_effects:
		var c: GCard = Data.get_card(int(be["card"]))
		if c != null and c.card_name_enum() == name_enum:
			return int(be["card"])
	return -1


## 按技能号查找基础效果牌（如【天使之墙】= 701）
func _find_basic_card_by_skill(p0: BattlePlayer, 技能号: int) -> int:
	for be: Dictionary in p0.basic_effects:
		var c: GCard = Data.get_card(int(be["card"]))
		if c != null and c.has_skill_id(技能号):
			return int(be["card"])
	return -1


## 构造伤害相关的钩子上下文（供角色读取 src/dst/card/is_active）
func harm_ctx(harm: Dictionary) -> Dictionary:
	return {
		"harm": harm,
		"src": int(harm.get("src", -1)),
		"dst": int(harm.get("dst", -1)),
		"card_id": int(harm.get("card_id", -1)),
		"is_active": bool(harm.get("is_active", true)),
	}


## 最近一次伤害的来源/类型（供「因伤害掉士气」类技能判定）
var last_harm_cause: int = 0
var last_harm_type: int = 0


## 伤害流水线入口：执行顺序（pop 顺序）3 → 钩子3 → 钩子4 → 治疗询问 → 钩子5 → 钩子6 → 摸牌 → 钩子6drawn → 伤害结束 → 手牌超限
func push_harm(harm: Dictionary) -> void:
	last_harm_cause = int(harm.get("cause", 0))
	last_harm_type = int(harm.get("type", GConst.HarmType.None))
	var hc: Dictionary = harm_ctx(harm)
	# 手牌超限不在这里压：原版是在「摸牌」那一拍结算（StateTimeline6 → 移动牌 → setStateHandOverLoad），
	# 引擎每跑完一个状态都会调 _check_hand_overflow()，摸完牌就会补上
	push(SHook.new("p_harm_end", hc, []))
	# 对照原版：Timeline5 跑完才决定要不要进 Timeline6（伤害被治疗抵成 0 点时整串不跑）
	push(SGateTimeline6.new(harm))
	push(SHook.new("p_timeline_5", hc, []))
	push(SAskCross.new(harm))
	push(SHook.new("p_timeline_4", hc, []))
	push(SHook.new("p_timeline_3", hc, []))
	push(SHarmTimeline3.new(harm))


## 攻击/法术/特殊行动收尾：先跑「行动结束」钩子，再进入回合结束
func push_after_action(hook: String, ctx: Dictionary) -> void:
	push(STurnEnd.new())
	push(SHook.new(hook, ctx, []))


## 出牌/展示牌后触发 p_show_hand 钩子（封印类技能依赖）。
## 格挡攻击=true：本次展示是「用牌格挡攻击」（应战抵挡，见 SAttackedAsk 的 Block 分支），
## 供需要区分「抵挡攻击」与其它公开打牌（如抵挡魔弹 / 弃牌展示）的角色判定（如圣女冰霜祷言）
func push_show_hand(pid: int, cards: Array, show_only: bool = false, 格挡攻击: bool = false) -> void:
	push(SHook.new("p_show_hand", {"player": pid, "cards": cards, "show_only": show_only, "格挡攻击": 格挡攻击}, []))


## 增删基础效果（会触发 p_basic_effect_change 钩子）；角色应优先用这两个方法
func add_basic_effect(dst_id: int, card_id: int, src_id: int, cause: int = 0) -> void:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return
	dst.add_basic_effect(card_id, src_id)
	push(SHook.new("p_basic_effect_change", {
		"dst": dst_id, "card": card_id, "doer": src_id, "cause": cause, "add": true,
	}, []))


## 移除基础效果；src_id 记发动者（对照服务端 doerID，无人负责的引擎内部移除传 -1）。
## 天使羁绊要靠它区分「哪个天使移除的」，不能让场上所有天使都触发
func remove_basic_effect(dst_id: int, card_id: int, cause: int = 0, src_id: int = -1) -> void:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return
	dst.remove_basic_effect(card_id)
	_log_basic_effect_remove(src_id, dst_id, card_id)
	push(SHook.new("p_basic_effect_change", {
		"dst": dst_id, "card": card_id, "doer": src_id, "cause": cause, "add": false,
	}, []))


## 横置/重置（形态进入/退出）。实际通知（写日志 + p_tap 钩子）由 BattlePlayer.tap 的 setter 统一完成，
## 所以直接写 player.tap = X 与本方法等价
func set_tap(pid: int, v: bool) -> void:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return
	p0.tap = v


## 形态进入/退出（由 BattlePlayer.tap 的 setter 调用）：真的变化才记日志，并触发 p_tap 钩子
func 形态变更(p0: BattlePlayer, v: bool, 记日志: bool) -> void:
	if 记日志:
		_播形态日志(p0, v)
	push(SHook.new("p_tap", {"id": p0.id, "tap": v}, []))


## 形态日志：形态名取自角色表「横置形态」列，写「X 进入/退出【形态名】」；
## 表里没配形态名的角色退回「X 横置/重置」
func _播形态日志(p0: BattlePlayer, 进入: bool) -> void:
	var 形态列表: Array[String] = Data.role_forms(p0.role_id)
	var 形态: String = 形态列表[0] if not 形态列表.is_empty() else ""
	var 文案: String
	if 形态.is_empty():
		文案 = "%s %s" % [_称号(p0), "横置" if 进入 else "重置"]
	else:
		文案 = "%s %s【%s】" % [_称号(p0), "进入" if 进入 else "退出", 形态]
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Token,
		"txt": 文案,
		"id": p0.id,
	})


# ============================================================
# 内部状态类
# ============================================================

## 通用钩子轮次：对每个玩家按座位序调用同名钩子；全部完成后依次压入 after。
## 进度（轮到第几个座位）与「各角色的 step」都存放在**本实例**里：
## 角色在钩子里压入新状态后会返回 URGENT 挂起本轮次，先跑那些新状态；
## 那些新状态里往往又含别的钩子轮次（p_timeline_* 等），它们会把所有角色的 step 归零——
## 回到本轮次时必须把 step 还原，否则角色会从 step 0 重跑（表现为同一回合反复询问同一技能）。
class SHook:
	var hook: String
	var ctx: Dictionary
	var after: Array
	## 本轮次处理到第几个座位
	var _iter: int = 0
	var _started: bool = false

	func _init(h: String, c: Dictionary = {}, a: Array = []) -> void:
		hook = h
		ctx = c
		after = a

	func handle(e: BattleEngine) -> int:
		if not _started:
			_started = true
			_iter = 0
		while _iter < e.order.size():
			var pid2: int = e.order[_iter]
			var r: BattleRole = e.p(pid2).role
			if r != null:
				var res: int = r.call_hook(hook, ctx)
				if res == BattleRole.WAIT:
					return BattleEngine.WAIT
				if res == BattleRole.URGENT:
					return BattleEngine.SUSPEND
			_iter += 1
		# after[0] 应先执行，故逆序压栈
		for i: int in range(after.size() - 1, -1, -1):
			e.push(after[i])
		return BattleEngine.CONTINUE


## 回合开始：清额外行动、处理中毒、处理虚弱，最后进入行动阶段
class SCheckTurnStart:
	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		cur.clear_additional_action()
		# 「启动」技能每回合只能发动一个：新回合开始清零
		cur.boot_skill_used = false
		e.skip_action_phase = false
		var poison_cards: Array[int] = []
		for be: Dictionary in cur.basic_effects:
			var c: GCard = Data.get_card(int(be["card"]))
			if c != null and c.card_name_enum() == GConst.CardName.Poison:
				poison_cards.append(int(be["card"]))
		e.push(SActionPhase.new())
		# 行动阶段之前的钩子顺序对照服务端 setStateCheckBasicEffect：
		#   中毒 → （虚弱询问）→ p_between_weak_and_action → p_before_action → p_boot → 行动阶段
		# 后压先执行，故这里按「行动阶段 → boot → before_action → between」的顺序压
		e.push(SHook.new("p_boot", {}, []))
		e.push(SHook.new("p_before_action", {}, []))
		e.push(SHook.new("p_between_weak_and_action", {}, []))
		e.push(SWeaken.new())
		if not poison_cards.is_empty():
			e.push(SPoison.new(poison_cards))
		# 回合开始钩子（先执行，后压入）
		e.push(SHook.new("p_turn_begin", {}, []))
		e.push(SHook.new("p_before_turn_begin", {}, []))
		return BattleEngine.CONTINUE


## 中毒结算
class SPoison:
	var cards: Array[int]
	func _init(cs: Array[int]) -> void:
		cards = cs
	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		for cid: int in cards:
			# 伤害来源取「施加【中毒】的那名玩家」（对照原版 GameGrail.cpp 的 poisonHarm.srcID = it->srcUser）
			var 来源: int = 0
			for be: Dictionary in cur.basic_effects:
				if int(be["card"]) == cid:
					来源 = int(be["src"])
					break
			cur.remove_basic_effect(cid)
			e._log_basic_effect_remove(-1, cur.id, cid)
			e.to_discard([cid])
			e.push_harm({"src": 来源, "dst": cur.id, "point": 1, "cause": GConst.CAUSE_POISON, "type": GConst.HarmType.Magic})
		e._broadcast_game()
		return BattleEngine.CONTINUE


## 虚弱询问（对照服务端 GameGrail::setStateCheckBasicEffect → StateWeaken）：
## 摸牌总数 = 3 × 虚弱牌数；玩家「确定」＝一次摸走全部，「取消」＝直接结束回合并跳过整个行动阶段。
## 【五系束缚】不再并入这里，改在行动阶段入口由角色的 p_before_action 单独询问。
class SWeaken:
	## 应摸数只在第一次进入时算一次，之后沿用（见 handle 的注释）
	var 已计算: bool = false
	var 虚弱牌: Array[int] = []
	var 应摸: int = 0

	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		# 数值必须只算一次：玩家回复后引擎会再跑一次本状态，重算会得到空数组、
		# 于是在下面直接 CONTINUE，玩家的「确定 / 取消」被丢掉，摸牌与跳过回合双双失效。
		if not 已计算:
			已计算 = true
			for be: Dictionary in cur.basic_effects:
				var c: GCard = Data.get_card(int(be["card"]))
				if c != null and c.card_name_enum() == GConst.CardName.Weaken:
					虚弱牌.append(int(be["card"]))
			应摸 = 3 * 虚弱牌.size()
			if 应摸 <= 0:
				return BattleEngine.CONTINUE
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var args: Array = r.get("args", [])
			var accept: int = int(args[0]) if args.size() > 0 else 0
			for cid: int in 虚弱牌:
				cur.remove_basic_effect(cid)
				e._log_basic_effect_remove(-1, cur.id, cid)
				e.to_discard([cid])
			if accept == 1:
				# 强摸走 push_draw：先让角色响应（如暗杀者【水影】），再摸牌；
				# 摸牌可能把手牌顶过上限 → 走和购买/特殊行动同一条「强制弃牌 + 掉士气」的路径
				e.push(SHandOverflow.new())
				e.push_draw(cur.id, 应摸)
				return BattleEngine.CONTINUE
			e.skip_action_phase = true
			e._broadcast_game()
			return BattleEngine.CONTINUE
		# args 末两项是「束缚摸牌数 / 虚弱牌数」，界面据此把文案写成「虚弱」（束缚恒为 0，已不在此询问）
		e.ask_respond(cur.id, GConst.RespondType.Weaken, [cur.id, 应摸, 0, 虚弱牌.size()])
		e.wait_for(cur.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 行动阶段
## 行动阶段（对照原版 StateActionPhase(allowAction, canGiveUp)）：
## 允许的行动种类与「能否放弃」由本状态的字段决定；被【挑衅】时强制改成「只能攻击 + 可放弃」
class SActionPhase:
	var 允许: int = GConst.ActionType.Any
	var 可放弃: bool = false
	## 本阶段是不是「额外行动」（额外行动声明的 allowAction + 允许放弃）
	var 额外: bool = false
	## 本阶段是否禁止特殊行动（发动过「启动」技能后：只能再攻击 / 法术）
	var 禁特殊: bool = false
	## 玩家挂机超时：本阶段已作废，直接收尾（tick 里置位，不替他出牌，也不宣告「无法行动」换手牌）
	var 跳过: bool = false

	func _init(allow: int = GConst.ActionType.Any, can_give_up: bool = false, extra: bool = false, no_special: bool = false) -> void:
		允许 = allow
		可放弃 = can_give_up
		额外 = extra
		禁特殊 = no_special

	func handle(e: BattleEngine) -> int:
		# 挂机超时：把这名玩家的行动阶段直接跳过，轮到下家
		if 跳过:
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		# 虚弱拒绝 / 五系束缚拒绝：本回合没有行动阶段，直接收尾（额外行动由 STurnEnd 照常处理）
		if e.skip_action_phase:
			e.skip_action_phase = false
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		# 测试指令「跳过当前行动玩家的回合」（按 0）：当前行动的人直接收尾，不进标准规则
		if e.测试跳过回合 == e.current_id:
			e.测试跳过回合 = -1
			e.take_reply()
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		var cur: BattlePlayer = e.p(e.current_id)
		# 被【挑衅】：本回合只能攻击、但允许放弃（对照原版 StateActionPhase::handle 开头）
		if cur != null and cur.check_exclusive_effect(GConst.Exclusive.TiaoXin):
			允许 = GConst.ActionType.Attack
			可放弃 = true
		e.行动允许 = 允许
		e.行动可放弃 = 可放弃
		e.行动额外 = 额外
		e.行动禁特殊 = 禁特殊
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var at: int = int(r.get("action_type", GConst.ActionType.None))
			return e.resolve_action(at, r)
		e.ask_action(e.current_id, 允许, 可放弃, 额外, 禁特殊)
		e.wait_for(e.current_id, GConst.Msg.Action)
		return BattleEngine.WAIT


## 回合结束：先处理额外行动，否则轮转到下家
class STurnEnd:
	## 技能行动被取消（见 BattleEngine.取消技能行动）：本回合不结束，改为重新进入行动阶段
	var 回行动阶段: bool = false

	func handle(e: BattleEngine) -> int:
		if e.phase == BattleEngine.Phase.Over:
			return BattleEngine.CONTINUE
		if 回行动阶段:
			回行动阶段 = false
			e.push(SActionPhase.new(e.行动允许, e.行动可放弃, e.行动额外, e.行动禁特殊))
			return BattleEngine.CONTINUE
		var cur: BattlePlayer = e.p(e.current_id)
		if cur != null and cur.contains_action():
			e.push(SAdditionalAction.new())
			return BattleEngine.CONTINUE
		# 对照原版：StateTurnEnd（p_turn_end）→ StateAfterTurnEnd（p_after_turn_end）→ 才 setStateCurrentPlayer(下家)。
		# 顺序不能反：月女【苍白之月】要在 p_after_turn_end 里把「下一个回合还是我」定下来
		e.push(SHook.new("p_after_turn_end", {"player": e.current_id}, [SNextPlayer.new()]))
		e.push(SHook.new("p_turn_end", {"player": e.current_id}, []))
		return BattleEngine.CONTINUE


## 轮转到下家
class SNextPlayer:
	func handle(e: BattleEngine) -> int:
		if e.额外回合玩家 >= 0:
			# 角色在 p_after_turn_end 里要求「下一个回合还是他」（月女【苍白之月】）：
			# 对照原版 —— 角色把 StateAfterTurnEnd 弹掉，于是后面的 setStateCurrentPlayer(下家) 不再执行
			var 自己: int = e.额外回合玩家
			e.额外回合玩家 = -1
			e.current_id = 自己
			e.broadcast(GConst.Msg.TurnBegin, {"id": e.current_id, "round": e.round_id})
			e.push(SCheckTurnStart.new())
			return BattleEngine.CONTINUE
		var nid: int = e.next_id(e.current_id)
		if nid == e.first_id:
			e.round_id += 1
		e.current_id = nid
		e.broadcast(GConst.Msg.TurnBegin, {"id": e.current_id, "round": e.round_id})
		e.push(SCheckTurnStart.new())
		return BattleEngine.CONTINUE


## 额外行动询问
class SAdditionalAction:
	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		if cur == null or not cur.contains_action():
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		# 声明了 direct 的额外行动（如圣女【圣疗】）不用先问：直接进入它的额外行动阶段。
		# 该阶段允许「放弃行动」，想跳过在那里放弃即可，省掉「再点一次技能按钮」这一步。
		if not e.has_reply():
			for i: int in range(cur.additional_actions.size()):
				if not bool(cur.additional_actions[i].get("direct", false)):
					continue
				var 直接: int = int(cur.additional_actions[i]["cause"])
				if cur.v_additional_action(直接) == GConst.GE_SUCCESS:
					return _进入(e, cur, i, 直接)
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var args: Array = r.get("args", [])
			var chosen: int = int(args[0]) if args.size() > 0 else -1
			var idx: int = -1
			if chosen >= 0:
				for i: int in range(cur.additional_actions.size()):
					if int(cur.additional_actions[i]["cause"]) == chosen:
						idx = i
						break
			if idx >= 0 and cur.v_additional_action(chosen) != GConst.GE_SUCCESS:
				# 角色二次校验未通过（服务端 v_additional_action）：提示并重新询问
				e.send(cur.id, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
				var 参数2: Array = _询问参数(cur)
				e.ask_respond(cur.id, GConst.RespondType.AdditionalAction, 参数2[0], 参数2[1])
				e.wait_for(cur.id, GConst.Msg.Respond)
				return BattleEngine.WAIT
			if idx >= 0:
				return _进入(e, cur, idx, chosen)
			# 放弃/无匹配：清空待办并继续结束回合
			cur.clear_additional_action()
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		var 参数: Array = _询问参数(cur)
		e.ask_respond(cur.id, GConst.RespondType.AdditionalAction, 参数[0], 参数[1])
		e.wait_for(cur.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


	## 额外行动询问参数：causes = 全部可选；可发动 = 当前 v_additional_action 认可的。
	## 后者作为询问的 dst_ids 下发，客户端据此把「确定」/选项按钮置灰（不能发动也能点「取消」跳过）
	func _询问参数(cur: BattlePlayer) -> Array:
		var causes: Array = []
		var 可发动: Array = []
		for a: Dictionary in cur.additional_actions:
			var c: int = int(a["cause"])
			causes.append(c)
			if cur.v_additional_action(c) == GConst.GE_SUCCESS:
				可发动.append(c)
		return [causes, 可发动]

	## 进入某份额外行动：移除它、广播技能通知，再压入额外行动阶段（允许放弃）与其「被选中」代价钩子
	func _进入(e: BattleEngine, cur: BattlePlayer, idx: int, cause: int) -> int:
		var 允许: int = int(cur.additional_actions[idx]["allow_action"])
		cur.additional_actions.remove_at(idx)
		e.broadcast(GConst.Msg.Skill, {"skill_id": cause, "src_id": cur.id, "dst_ids": []})
		# 先让角色结算「被选中」的代价（p_additional_action），再进入额外行动阶段。
		# 额外行动阶段只放行这份额外行动声明的种类、且允许放弃（对照原版
		# PlayerEntity::p_additional_action → StateActionPhase(it->allowAction, true)）
		e.push(SActionPhase.new(允许, true, true))
		e.push(SHook.new("p_additional_action", {"player": cur.id, "cause": cause}, []))
		return BattleEngine.CONTINUE


## 一次攻击的入口：先跑 timeline_1 钩子（可改命中率/是否查圣盾），再压入应战询问
class SAttackCard:
	var src: int
	var dst: int
	var card: int
	var harm: Dictionary
	var ctx_built: bool = false
	var ctx: Dictionary = {}

	func _init(s: int, d: int, c: int, h: Dictionary) -> void:
		src = s
		dst = d
		card = c
		harm = h

	func handle(e: BattleEngine) -> int:
		if not ctx_built:
			var c: GCard = Data.get_card(card)
			var hit_rate: int = GConst.HitRate.Normal
			if c != null and c.element_enum() == GConst.CardElement.Darkness:
				hit_rate = GConst.HitRate.NoReattack
			ctx = {
				"card_id": card, "dst": dst, "src": src,
				"is_active": not harm.get("reattack", false),
				"hit_rate": hit_rate, "check_shield": true, "can_light": true,
				"harm": harm,
			}
			ctx_built = true
			e.push(SHook.new("p_before_attack", ctx, [
				SHook.new("p_timeline_1", ctx, [SAttacked.new(self)]),
			]))
			return BattleEngine.CONTINUE
		# 钩子完成后继续（由 SHook 压入 SAttacked）
		return BattleEngine.CONTINUE


## 应战前的全员钩子（跑完后进入实际询问）
class SAttacked:
	var owner: SAttackCard

	func _init(o: SAttackCard) -> void:
		owner = o

	func handle(e: BattleEngine) -> int:
		e.push(SHook.new("p_attacked", owner.ctx, [SAttackedAsk.new(owner)]))
		return BattleEngine.CONTINUE


## 实际发出应战询问并解析
class SAttackedAsk:
	var owner: SAttackCard

	func _init(o: SAttackCard) -> void:
		owner = o

	func handle(e: BattleEngine) -> int:
		var harm: Dictionary = owner.harm
		var dst: BattlePlayer = e.p(owner.dst)
		# 代替应战者：由其代替目标应战（伤害仍落在目标身上），用于【式神咒束】等
		var defender: BattlePlayer = dst
		if dst.reattacker >= 0:
			var helper: BattlePlayer = e.players.get(dst.reattacker)
			if helper != null:
				defender = helper
			else:
				# 指向不存在的玩家：清掉脏标记，按常规应战
				dst.reattacker = -1
		var hit_rate: int = int(owner.ctx.get("hit_rate", GConst.HitRate.Normal))
		# 应战询问的参数；末位＝本次攻击伤害：harm["point"]（怒吼 / 精准射击 / 蓄力一击等「宣告阶段」
		# 已加进去的）＋ 攻击者预告的「命中才结算」加伤（暗影之力 / 暗之解放…，见 p_attack_preview）。
		# 客户端把它写进提示（「受到 N 伤害攻击：…」），让被攻击者一眼看到这一下要挨多少
		var 应战询问: Array = [hit_rate, owner.card, defender.id, owner.src,
			owner.ctx.get("can_light", 1), int(harm.get("point", 0)) + e._预告加伤(owner.src, owner.ctx)]
		if hit_rate == GConst.HitRate.NoMiss:
			e.push(STimeline2Hit.new(harm))
			return BattleEngine.CONTINUE
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var args: Array = r.get("args", [])
			var choice: int = int(args[0]) if args.size() > 0 else GConst.Reattack.GiveUp
			var cards: Array = r.get("card_ids", [])
			if choice == GConst.Reattack.Attack and not cards.is_empty():
				var cid: int = int(cards[0])
				# 应战的反击目标由应战者指定（对照服务端 reply_attack->dst_ids(0)）：只能是敌方、且不是原攻击者
				var 选定: Array = r.get("dst_ids", [])
				var 反击目标: int = int(选定[0]) if not 选定.is_empty() else -1
				if hit_rate != GConst.HitRate.Normal or not e._reattack_target_ok(defender, 反击目标, owner.src) \
						or defender.v_reattack(cid, owner.card) != GConst.GE_SUCCESS:
					# args[2] 必须是「应该由谁来应战」（defender），客户端据此判断这条询问是不是给我的：
					# 代应战（式神咒束）时 defender 是代替者，不等于被攻击的目标 dst，写成 dst.id 会让代替者的客户端把询问丢掉
					e.ask_respond(defender.id, GConst.RespondType.ReplyAttack, 应战询问)
					e.wait_for(defender.id, GConst.Msg.Respond)
					return BattleEngine.WAIT
				# 应战成立：原攻击落空，应战者以自己的攻击牌对所选目标发起一次新攻击。
				# 对照原版：先跑一轮 p_reattack（角色可把这张牌「视为」另一张，如魔女烈焰形态下的
				# 虚拟【火焰斩】），再按结果结算（真牌照样进弃牌堆并展示，反击用「视为」的那张）
				var 应战: Dictionary = {"card_id": cid, "doer": defender.id, "target": 反击目标, "改用": cid, "real": true}
				e.push(SReattackGo.new(defender, harm, 应战, cid, 反击目标))
				e.push(SHook.new("p_reattack", 应战, []))
				# 应战打出的真牌同样要跑「展示手牌」钩子（封印师的水/火/地/风/雷之封印靠它触发）。
				# 但这一压必须由 SReattackGo 在自己那步的末尾做（见该类 handle）：状态栈后进先出，
				# 在这里提前压会让展示钩子排在「出牌广播」之前先跑，客户端表现成「先弹技能询问
				# （圣女冰霜祷言）加治疗、后摊牌 + 出手特效」。
				# 对照服务端 setStateReattack → setStateUseCard(realCard=true) → StateShowHand
				return BattleEngine.CONTINUE
			if choice == GConst.Reattack.Block and not cards.is_empty():
				var cid2: int = int(cards[0])
				if defender.v_block(cid2) == GConst.GE_SUCCESS:
					e.take_from_hand(defender.id, [cid2])
					e.to_discard([cid2])
					dst.reattacker = -1
					e.broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": defender.id, "dst_id": dst.id, "card_ids": [cid2], "is_real": true})
					e.push(STimeline2Miss.new(harm))
					# 格挡打出的真牌同样要走「展示手牌」钩子（对照服务端 RA_BLOCK → setStateUseCard，
					# realCard 默认 true → StateShowHand）。带「格挡攻击」标记：本条才是「用牌抵挡攻击」，
					# 供圣女冰霜祷言等区分它与抵挡魔弹 / 弃牌展示等其它公开打牌场合
					e.push_show_hand(defender.id, [cid2], false, true)
					return BattleEngine.CONTINUE
			# 放弃应战：【圣盾】或视作【圣盾】的【天使之墙】自动挡下
			dst.reattacker = -1
			if bool(owner.ctx.get("check_shield", true)):
				var shield_card: int = -1
				if dst.check_basic_effect_name(GConst.CardName.Shield):
					shield_card = e._find_basic_card(dst, GConst.CardName.Shield)
				elif dst.check_basic_effect_skill(GConst.技能_天使之墙):
					shield_card = e._find_basic_card_by_skill(dst, GConst.技能_天使之墙)
				if shield_card >= 0:
					dst.remove_basic_effect(shield_card)
					e._log_basic_effect_remove(-1, dst.id, shield_card)
					e.to_discard([shield_card])
					e._broadcast_game()
					e.push(STimeline2Miss.new(harm))
					return BattleEngine.CONTINUE
			e.push(STimeline2Hit.new(harm))
			return BattleEngine.CONTINUE
		e.ask_respond(defender.id, GConst.RespondType.ReplyAttack, 应战询问)
		e.wait_for(defender.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 应战成立后的结算（对照原版 setStateReattack）：
## 反击用的是 p_reattack 给出的「视为」牌（可能是虚拟牌，如魔女的虚拟【火焰斩】87）；
## 真牌一律从手牌进弃牌堆，并广播给所有人看（card_ids 是真牌，「视为」哪张放在 as_card_id）
class SReattackGo:
	var defender: BattlePlayer
	var harm: Dictionary
	var 应战: Dictionary
	var 原牌: int
	var 目标: int

	func _init(d: BattlePlayer, h: Dictionary, s: Dictionary, yuan: int, t: int) -> void:
		defender = d
		harm = h
		应战 = s
		原牌 = yuan
		目标 = t

	func handle(e: BattleEngine) -> int:
		var 用牌: int = int(应战.get("改用", 原牌))
		var 被攻击者: BattlePlayer = e.p(int(harm["dst"]))
		if 被攻击者 != null:
			被攻击者.reattacker = -1
		e.take_from_hand(defender.id, [原牌])
		e.to_discard([原牌])
		e.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Use, "src_id": defender.id, "dst_id": 目标,
			"card_ids": [原牌], "is_real": true,
			"as_card_id": 用牌 if 用牌 != 原牌 else 0,
		})
		# 角色可把这次应战「视为格挡」（如阴阳师式神形态下用光系牌应战）：本次攻击落空、不反击
		if bool(应战.get("block", false)):
			e.push(STimeline2Miss.new(harm))
			e.push_show_hand(defender.id, [原牌])
			return BattleEngine.CONTINUE
		# 反击是应战者自己的攻击：伤害按「攻击牌基础值」重建，不继承原攻击者本次的加成
		# （如格斗【蓄力一击】的 +1 只属于他这次主动攻击；应战者的加伤由他自己的角色钩子按 is_active=false 施加）
		var new_harm: Dictionary = {
			"src": defender.id, "dst": 目标, "point": ATTACK_BASE_POINT,
			"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
			"reattack": true, "card_id": 用牌, "is_active": false,
		}
		e.push(SAttackCard.new(defender.id, 目标, 用牌, new_harm))
		e.push(STimeline2Miss.new(harm))
		# 「展示手牌」钩子最后压（＝最先跑）：上面那条出牌广播已经先发出去（客户端摊牌 + 出手特效），
		# 之后才轮到技能询问（如圣女冰霜祷言）—— 与非应战场合（主动打出）的次序一致
		e.push_show_hand(defender.id, [原牌])
		return BattleEngine.CONTINUE


## 魔弹传递询问：持有者可以打出【魔弹】继续传递、出【圣光】抵挡，或放弃并承受伤害。
## 对照服务端 StateMissiled：传递方向沿用出弹时定下的方向（【魔弹】默认右手边 post；
## 魔导用【魔弹掌控】逆向打出则是 pre），后续传递者只是「传给下一个」、不改方向，
## 只有【魔弹掌控】的持有者才能在传递时改方向。同一轮传递里每人只能参与一次。
## 即使持有者手里既没有【魔弹】也没有【圣光】，也照样要问、要等应答。
class SMissileAsk:
	## 当前持有者 / 上一个打出魔弹的人（伤害来源）/ 当前伤害
	var holder: int
	var src: int
	var point: int
	## 当前传递方向：true = 沿 post（角色顺序的下一个座位），false = 逆向（pre）
	var post_dir: bool
	## 本轮已参与过的玩家（含最初打出魔弹的人与第一个目标）
	var used: Array[int]

	func _init(h: int, s: int, p: int, dir: bool, u: Array[int]) -> void:
		holder = h
		src = s
		point = p
		post_dir = dir
		used = u

	func handle(e: BattleEngine) -> int:
		if not e.has_reply():
			# dst_ids = 本次可以把魔弹传给谁（候选，有【魔弹掌控】时左右各一个）
			# args[0] 放持有者 id：客户端据此判断这条询问是不是发给自己的
			e.ask_respond(holder, GConst.RespondType.Bullet, [holder, point, src],
				e._missile_relay_targets(holder, post_dir, used))
			e.wait_for(holder, GConst.Msg.Respond)
			return BattleEngine.WAIT
		var r: Dictionary = e.take_reply()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if args.size() > 0 else GConst.Reattack.GiveUp
		var cards: Array = r.get("card_ids", [])
		var me: BattlePlayer = e.p(holder)
		if me != null and not cards.is_empty():
			var cid: int = int(cards[0])
			if choice == GConst.Reattack.Block and me.v_block(cid) == GConst.GE_SUCCESS:
				# 【圣光】抵挡：魔弹效果终止，不造成伤害（牌是公开打出的，带 已展示 触发展示手牌钩子）
				e.take_from_hand(holder, [cid], true)
				e.to_discard([cid])
				e.broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": holder, "dst_id": holder, "card_ids": [cid], "is_real": true})
				e._broadcast_game()
				return BattleEngine.CONTINUE
			if choice == GConst.Reattack.Attack and me.v_remissile(cid) == GConst.GE_SUCCESS:
				# 继续传递：伤害 +1，沿**当前方向**转给下一个还没参与过的对手。
				# 方向由出弹时定下（顺时针打出＝顺向，魔导用【魔弹掌控】逆向打出＝逆向）；
				# 【魔弹掌控】只作用于「主动打出」那一步，传递者一律不能改向
				var nxt: int = e._next_missile_target(holder, post_dir, used)
				# 打出的是【魔弹】继续传递：dst_id 必须给下一个落点，客户端才知道魔弹要从自己飞向谁；
				# 没人能再接（nxt < 0）就仍写自己，动画落在自己身上。
				# 魔导/特殊魔导也可以拿地系、火系牌传递：这次出牌同样视为【魔弹】
				e.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Use, "src_id": holder,
					"dst_id": nxt if nxt >= 0 else holder,
					"card_ids": [cid], "is_real": true, "as_card_id": e.missile_as_card(cid),
				})
				if nxt >= 0:
					used.append(nxt)
					e.push(SMissileAsk.new(nxt, holder, point + 1, post_dir, used))
				else:
					# 没人能再接：由当前持有者承受
					e.push_harm({"src": src, "dst": holder, "point": point, "cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic})
				# 传递打出的牌是公开的：带 已展示；放在这些 push 之后，展示手牌钩子才压在栈顶先结算
				e.take_from_hand(holder, [cid], true)
				e.to_discard([cid])
				e._broadcast_game()
				return BattleEngine.CONTINUE
		# 放弃（或打出的牌既不是【圣光】也不能继续传递）：面前有【圣盾】/【天使之墙】则视作未命中
		if e._missile_block_by_basic(holder):
			e._broadcast_game()
			return BattleEngine.CONTINUE
		e.push_harm({"src": src, "dst": holder, "point": point, "cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic})
		e._broadcast_game()
		return BattleEngine.CONTINUE


## 命中
class STimeline2Hit:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		var src_p: BattlePlayer = e.p(harm["src"])
		e.broadcast(GConst.Msg.Hit, {"cmd_id": 0, "hit": 1, "src_id": harm["src"], "dst_id": harm["dst"]})
		if src_p != null:
			if harm.get("reattack", false):
				e.set_team_crystal(src_p.color, e.team_crystal[src_p.color] + 1)
			else:
				e.set_team_gem(src_p.color, e.team_gem[src_p.color] + 1)
		e._broadcast_game()
		# 先让钩子跑（可能改伤害值），再进入伤害流水线
		e.push_harm(harm)
		e.push(SHook.new("p_timeline_2_hit", e.harm_ctx(harm), []))
		return BattleEngine.CONTINUE


## 未命中
class STimeline2Miss:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		e.broadcast(GConst.Msg.Hit, {"cmd_id": 0, "hit": 0, "src_id": harm["src"], "dst_id": harm["dst"]})
		e.push(SHook.new("p_timeline_2_miss", e.harm_ctx(harm), []))
		return BattleEngine.CONTINUE


## Timeline3：先广播受伤飘字（界面要在战斗日志那一行之前把数字飘出来），
## 再广播伤害事件（音效 / 受击动画 / 日志那行）。点数为 0 时不飘
class SHarmTimeline3:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		var 点数: int = int(harm["point"])
		if 点数 > 0:
			e.broadcast(GConst.Msg.HurtFloat, {
				"dst_id": harm["dst"], "point": 点数, "type": harm["type"],
			})
		e.broadcast(GConst.Msg.Hurt, {
			"src_id": harm["src"], "dst_id": harm["dst"], "hurt": harm["point"],
			"cause": harm["cause"], "type": harm["type"],
		})
		return BattleEngine.CONTINUE


## Timeline4：治疗回应询问
class SAskCross:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		var dst: BattlePlayer = e.p(harm["dst"])
		# 任何伤害都能用治疗抵御（对照服务端 GrailState.cpp 的 StateTimeline4：crossAvailable 直接取
		# 玩家治疗数，不看伤害类型；类型只用于给客户端的文案）。
		# 角色可在 p_timeline_4 用 harm["cross_available"]=0 关闭治疗结算，
		# 或用 harm["cross_max_point"]=N 把本次可抵御点数限制为 N
		var cross_ok: bool = int(harm.get("cross_available", 1)) != 0
		var cap: int = int(harm.get("cross_max_point", 0))
		var avail: int = dst.cross_num if cross_ok else 0
		if cap > 0:
			avail = mini(avail, cap)
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var args: Array = r.get("args", [])
			var used: int = int(args[0]) if args.size() > 0 else 0
			used = clampi(used, 0, avail)
			var 治疗前: int = dst.cross_num
			var 伤害前: int = int(harm["point"])
			dst.sub_cross_num(used)
			harm["point"] = maxi(伤害前 - used, 0)
			# 日志写清楚这次治疗抵挡各自的变化（只通知、不进聊天区）
			if used > 0:
				var 类型名: String = "攻击" if int(harm.get("type", -1)) == GConst.HarmType.Attack else "法术"
				e.broadcast(GConst.Msg.Gossip, {
					"type": GConst.GossipType.Combat,
					"txt": "%s 用 %d 点治疗抵挡 %d 点%s伤害，治疗 %d→%d，伤害 %d→%d" % [
						e._称号(dst), used, 伤害前, 类型名,
						治疗前, dst.cross_num, 伤害前, int(harm["point"])],
					"id": dst.id,
				})
			e._broadcast_game()
			return BattleEngine.CONTINUE
		if int(harm["point"]) > 0 and avail > 0:
			e.ask_respond(dst.id, GConst.RespondType.Heal, [dst.id, harm["point"], harm["type"], avail])
			e.wait_for(dst.id, GConst.Msg.Respond)
			return BattleEngine.WAIT
		return BattleEngine.CONTINUE


## Timeline6 的入口（对照原版 StateTimeline5 的收尾）：
## 只有伤害点数 > 0 才进 Timeline6 —— 跑 p_timeline_6、按点数摸牌、再跑 p_timeline_6_drawn；
## 被治疗抵成 0 点时这一串都不跑（原版是 pop 掉 Timeline5 直接接 harm_end）
class SGateTimeline6:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		if int(harm["point"]) <= 0:
			return BattleEngine.CONTINUE
		var hc: Dictionary = e.harm_ctx(harm)
		e.push(SHook.new("p_timeline_6_drawn", hc, []))
		e.push(SHarmTimeline6.new(harm))
		e.push(SHook.new("p_timeline_6", hc, []))
		return BattleEngine.CONTINUE


## Timeline6：目标按伤害点数摸牌（进入这里时点数必然 > 0）
class SHarmTimeline6:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		# 摸牌前先让角色响应（如暗杀者【水影】：除特殊行动外，当你摸牌前发动）；
		# 钩子先跑（LIFO），随后 SHarmDrawOverload 才真正摸牌
		e.push(SHarmDrawOverload.new(harm))
		e.push(SHook.new("p_before_draw", {
			"player": harm["dst"], "count": int(harm["point"]), "cause": int(harm.get("cause", 0)),
		}, []))
		return BattleEngine.CONTINUE


## 摸牌：把 n 张牌从牌堆发到某玩家手里（对照服务端发牌状态）
class SDraw:
	var pid: int
	var count: int
	func _init(p_id: int, c: int) -> void:
		pid = p_id
		count = c
	func handle(e: BattleEngine) -> int:
		e.draw(pid, count)
		e._broadcast_game()
		return BattleEngine.CONTINUE


## 伤害摸牌（摸完立刻结算超限）：从 SHarmTimeline6 拆出来，好让 p_before_draw 钩子排在摸牌之前
class SHarmDrawOverload:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		e.draw(harm["dst"], int(harm["point"]))
		e._broadcast_game()
		# 摸牌顶过手牌上限：立刻带着本次伤害的上下文结算超限掉士气（对照服务端 StateTimeline6 →
		# setStateHandOverLoad(con->harm)）；等通用的 _check_hand_overflow 补就会丢掉这份上下文
		e.push_overload_with_harm(harm)
		return BattleEngine.CONTINUE


## 盖牌超限：超出上限的盖牌由所有者自己选择弃哪几张（每次处理一名玩家）
## 对照服务端 StateRequestCover：不涉及掉士气，只把选中的盖牌移入弃牌堆
class SCoverOverflow:
	func handle(e: BattleEngine) -> int:
		var target: BattlePlayer = null
		for pid: int in e.order:
			var pp: BattlePlayer = e.p(pid)
			if pp.cover_cards_max > 0 and pp.cover_cards.size() > pp.cover_cards_max:
				target = pp
				break
		if target == null:
			return BattleEngine.CONTINUE
		var over: int = target.cover_cards.size() - target.cover_cards_max
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var cards: Array = r.get("card_ids", [])
			var chosen: Array = []
			for c: Variant in cards:
				if chosen.size() < over and target.cover_cards.has(int(c)) and not chosen.has(int(c)):
					chosen.append(int(c))
			if chosen.size() < over:
				for cid: int in target.cover_cards:
					if chosen.size() >= over:
						break
					if not chosen.has(cid):
						chosen.append(cid)
			target.remove_cover_cards(chosen)
			e.to_discard(chosen)
			e._log_discard(target.id, chosen)
			e.push(SCoverOverflow.new())
			e._broadcast_game()
			return BattleEngine.CONTINUE
		e.ask_respond(target.id, GConst.RespondType.DiscardCover, [target.id, GConst.CAUSE_OVERLOAD, over], [target.id])
		e.wait_for(target.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 通用「由玩家选牌弃掉」（对照服务端 StateRequestHand 的简单用法）。
## 用于把「弃牌」排在其它结算之后执行（如魔女痛苦链接、巫女血之诅咒：先伤害后弃牌）。
## count >= 0 时弃 count 张；否则按 keep 弃到只剩 keep 张。
class SRequestDiscard:
	var pid: int
	var count: int
	var keep: int
	var cause: int
	func _init(p_id: int, n: int, k: int, c: int) -> void:
		pid = p_id
		count = n
		keep = k
		cause = c
	func handle(e: BattleEngine) -> int:
		var p0: BattlePlayer = e.p(pid)
		if p0 == null:
			return BattleEngine.CONTINUE
		var want: int = mini(count, p0.hand_cards.size()) if count >= 0 else maxi(p0.hand_cards.size() - keep, 0)
		if want <= 0:
			return BattleEngine.CONTINUE
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var chosen: Array = []
			for c: Variant in r.get("card_ids", []):
				if chosen.size() < want and p0.has_hand_card(int(c)) and not chosen.has(int(c)):
					chosen.append(int(c))
			if chosen.size() < want:
				for cid: int in p0.hand_cards:
					if chosen.size() >= want:
						break
					if not chosen.has(cid):
						chosen.append(cid)
			e.take_from_hand(pid, chosen)
			e.to_discard(chosen)
			e._log_discard(pid, chosen)
			e._broadcast_game()
			return BattleEngine.CONTINUE
		e.ask_respond(pid, GConst.RespondType.Discard, [pid, cause, want], [pid])
		e.wait_for(pid, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 直接弃掉「玩家已经选好」的几张牌（不再另发一次弃牌询问）：
## 给「选目标时同时选弃牌」的技能用（如血之巫女【血之诅咒】：弃牌与目标一起提交，
## 结算时先造成伤害、再弃这几张）。伤害结算期间手牌可能变过，只弃还在手里的
class SDiscardChosen:
	var pid: int
	var cards: Array
	func _init(p_id: int, c: Array) -> void:
		pid = p_id
		cards = c
	func handle(e: BattleEngine) -> int:
		var p0: BattlePlayer = e.p(pid)
		if p0 == null:
			return BattleEngine.CONTINUE
		var chosen: Array = []
		for c: Variant in cards:
			var cid: int = int(c)
			if p0.has_hand_card(cid) and not chosen.has(cid):
				chosen.append(cid)
		if chosen.is_empty():
			return BattleEngine.CONTINUE
		e.take_from_hand(pid, chosen)
		e.to_discard(chosen)
		e._log_discard(pid, chosen)
		e._broadcast_game()
		return BattleEngine.CONTINUE


## 记录某玩家手牌数量的变化，并触发一次 p_hand_change（对照服务端 StateHandChange）
class SRunHandChange:
	var pid: int
	func _init(p_id: int) -> void:
		pid = p_id
	func handle(e: BattleEngine) -> int:
		var p0: BattlePlayer = e.p(pid)
		if p0 == null:
			return BattleEngine.CONTINUE
		var 新: int = p0.hand_cards.size()
		var 旧: int = int(e._hand_counts.get(pid, 新))
		if 旧 != 新:
			# 手牌数量变化日志：谁的手牌从多少变成了多少（与手牌上限同一类：[卡牌]）
			e._播手牌日志(p0, "%s 的手牌 %d→%d" % [e._称号(p0), 旧, 新])
		e._hand_counts[pid] = 新
		e.push(SHook.new("p_hand_change", {"player": pid}, []))
		return BattleEngine.CONTINUE


## 手牌超限：强制弃牌并掉士气（每次处理一名玩家）
class SHandOverflow:
	## 本次超限结算归属的伤害上下文（cause / type），沿链传给下一个人。
	## 必须由「摸牌那一拍」带着伤害上下文创建（见 push_overload_with_harm）；
	## 引擎通用的 _check_hand_overflow 建出来的实例没带（-1），只能在 handle 里按最近一次伤害兜底
	var harm_cause: int = -1
	var harm_type: int = -1

	func _init(cause: int = -1, htype: int = -1) -> void:
		harm_cause = cause
		harm_type = htype

	func handle(e: BattleEngine) -> int:
		if harm_cause < 0:
			harm_cause = e.last_harm_cause
			harm_type = e.last_harm_type
		var target: BattlePlayer = null
		for pid: int in e.order:
			var pp: BattlePlayer = e.p(pid)
			if pp.hand_cards.size() > pp.hand_cards_max:
				target = pp
				break
		if target == null:
			return BattleEngine.CONTINUE
		var over: int = target.hand_cards.size() - target.hand_cards_max
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var cards: Array = r.get("card_ids", [])
			var chosen: Array = []
			for c: Variant in cards:
				if chosen.size() < over and target.has_hand_card(int(c)):
					chosen.append(int(c))
			if chosen.size() < over:
				for cid: int in target.hand_cards:
					if chosen.size() >= over:
						break
					if not chosen.has(cid):
						chosen.append(cid)
			e.take_from_hand(target.id, chosen)
			e.to_discard(chosen)
			e._log_discard(target.id, chosen)
			# 先压「继续处理下一个超限玩家」，再压掉士气（后压先执行 → 士气先结算，与服务器一致）；
			# 下一个玩家共用同一份伤害上下文
			e.push(SHandOverflow.new(harm_cause, harm_type))
			e.push(SOverloadMorale.new(target.id, over, GConst.CAUSE_OVERLOAD, harm_cause, harm_type))
			e._broadcast_game()
			return BattleEngine.CONTINUE
		e.ask_respond(target.id, GConst.RespondType.Discard, [target.id, GConst.CAUSE_OVERLOAD, over], [target.id])
		e.wait_for(target.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 超限掉士气（可等待玩家输入）：依次跑完整掉士气链 ——
## p_before_lose_morale → p_xin_yue → p_lose_morale → p_fix_morale → p_true_lose_morale → 扣士气
## 对应服务端 StateBeforeLoseMorale → StateXinYue → StateLoseMorale → StateFixMorale → StateTrueLoseMorale；
## 服务端 StateTrueLoseMorale 是「先把 p_true 钩子对全体跑完，最后才真正扣士气并判结束」。
## 仅在「干净栈位」（SHandOverflow 内）压入，故允许钩子等待玩家输入（如天使的神之庇护 706）；
## 由角色在自身钩子中途触发的掉士气仍走同步 lose_morale()（其栈位不能安全等待）。
class SOverloadMorale:
	var target_id: int
	var ctx: Dictionary
	var started: bool = false
	func _init(t: int, amount: int, cause: int, harm_cause: int, harm_type: int) -> void:
		target_id = t
		ctx = {"dst": t, "amount": amount, "cause": cause, "harm_cause": harm_cause, "type": harm_type}
	func handle(e: BattleEngine) -> int:
		if started:
			return BattleEngine.CONTINUE
		started = true
		# 逆序压栈（后压先执行）：p_before → p_xin_yue → p_lose_morale → p_fix_morale → p_true → 扣士气
		e.push(SApplyOverloadMorale.new(target_id, ctx))
		e.push(SHook.new("p_true_lose_morale", ctx, []))
		e.push(SHook.new("p_fix_morale", ctx, []))
		e.push(SHook.new("p_lose_morale", ctx, []))
		e.push(SHook.new("p_xin_yue", ctx, []))
		e.push(SHook.new("p_before_lose_morale", ctx, []))
		return BattleEngine.SUSPEND


## 扣除超限掉士气并判定结束（在钩子轮次之后执行）
class SApplyOverloadMorale:
	var target_id: int
	var ctx: Dictionary
	func _init(t: int, c: Dictionary) -> void:
		target_id = t
		ctx = c
	func handle(e: BattleEngine) -> int:
		var target: BattlePlayer = e.p(target_id)
		if target != null:
			var amount: int = maxi(int(ctx.get("amount", 0)), 0)
			e.set_morale(target.color, e.team_morale[target.color] - amount)
		e.last_harm_cause = 0
		e.last_harm_type = 0
		e._broadcast_game()
		e._check_game_over()
		return BattleEngine.CONTINUE


## 技能执行（主动技能）：先校验，再交给角色；结束后补跑对应的「行动结束」钩子
class SkillRun:
	var kind: String
	var action: Dictionary
	var checked: bool = false
	var invoked: bool = false
	var after_pushed: bool = false
	func _init(k: String, a: Dictionary) -> void:
		kind = k
		action = a
	func _push_after(e: BattleEngine, src: int) -> void:
		if after_pushed:
			return
		after_pushed = true
		e.push(SHook.new("p_after_" + kind, {"player": src, "action_id": int(action.get("action_id", 0))}, []))
	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		if cur.role == null:
			e.push(SActionPhase.new())
			return BattleEngine.CONTINUE
		if not checked:
			# 「启动」技能每回合只能发动一个：本回合已发动过就直接驳回（客户端漏网点了也会被挡）
			# （「启动」都是特殊技能；同一个技能号另有攻击 / 法术入口时不受这条限制）
			if cur.boot_skill_used and kind == "special" \
					and cur.role.is_free_skill(int(action.get("action_id", 0))):
				e.send(cur.id, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Action, "commands": []})
				e.push(SActionPhase.new())
				return BattleEngine.CONTINUE
			var rc: int = cur.role.call("v_" + kind + "_skill", action)
			if rc != GConst.GE_SUCCESS:
				e.send(cur.id, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Action, "commands": []})
				e.push(SActionPhase.new())
				return BattleEngine.CONTINUE
			checked = true
		# 已经执行过一次且角色压入了状态（URGENT）→ 不再重复执行技能本体
		if invoked:
			_push_after(e, cur.id)
			return BattleEngine.CONTINUE
		var res: int = cur.role.call("p_" + kind + "_skill", action)
		if res == BattleRole.WAIT:
			return BattleEngine.WAIT
		invoked = true
		if res == BattleRole.URGENT:
			return BattleEngine.SUSPEND
		_push_after(e, cur.id)
		return BattleEngine.CONTINUE


# ============================================================
# 玩家动作结算
# ============================================================
## 驳回当前行动：告知客户端「操作无效」并重新进入行动阶段
## （服务端返回 GE_INVALID_ACTION 后同样会回一条错误；不提示会变成「点了没反应」，还会让客户端反复重试）
func _reject_action(cur: BattlePlayer) -> int:
	send(cur.id, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Action, "commands": []})
	push(SActionPhase.new())
	return CONTINUE


func resolve_action(action_type: int, data: Dictionary) -> int:
	var cur: BattlePlayer = players.get(current_id)
	# 行动合法性总闸：对照原版 StateActionPhase → PlayerEntity::v_allow_action(action, allowAction, canGiveUp)。
	# 角色可覆写 v_allow_action 追加限制（如「审判满 4 时该阶段只能发动末日审判」「暗影抗拒禁用法术牌」）
	var 总闸: int = cur.v_allow_action(action_type, data.get("args", []), 行动允许, 行动可放弃) if cur != null else GConst.GE_SUCCESS
	if 总闸 != GConst.GE_SUCCESS:
		return _reject_action(cur)
	# 发动过「启动」技能后本阶段禁止特殊行动（购买/合成/提炼）：客户端已把按钮收掉，这里兜底驳回
	if 行动禁特殊 and (action_type == GConst.ActionType.Special or action_type == GConst.ActionType.SpecialSkill):
		return _reject_action(cur)
	match action_type:
		GConst.ActionType.None:
			push(STurnEnd.new())
			return CONTINUE
		GConst.ActionType.Unactional:
			return _do_unactional(cur)
		GConst.ActionType.Attack:
			return _do_attack(cur, data)
		GConst.ActionType.Magic:
			return _do_magic(cur, data)
		GConst.ActionType.Special:
			return _do_special(cur, data)
		GConst.ActionType.AttackSkill:
			_进入技能行动(cur, "attack", data)
			return CONTINUE
		GConst.ActionType.MagicSkill:
			_进入技能行动(cur, "magic", data)
			return CONTINUE
		GConst.ActionType.SpecialSkill:
			_进入技能行动(cur, "special", data)
			return CONTINUE
		_:
			push(STurnEnd.new())
			return CONTINUE


## 技能行动入栈：普通技能用完即结束行动阶段；「启动」技能（角色 is_free_skill 认可，如格斗家
## 【百式幻龙拳】【斗神天驱】）不消耗行动，结算完重新进入行动阶段让玩家继续本回合行动
func _进入技能行动(cur: BattlePlayer, kind: String, data: Dictionary) -> void:
	var 技能号: int = int(data.get("action_id", 0))
	# 「启动」都是特殊技能；同一个技能号另有攻击 / 法术入口时不算启动（如苍炎魔女【魔女之怒】的启动与攻击入口同号）
	var 启动: bool = kind == "special" and 技能号 > 0 and cur != null and cur.role != null \
			and cur.role.is_free_skill(技能号)
	if 启动:
		# 「启动」技能不消耗本回合行动，发动后行动阶段照旧继续；但只能再攻击 / 法术，
		# 不能再走特殊行动（启动技与特殊行动互斥）
		push(SActionPhase.new(行动允许, 行动可放弃, 行动额外, true))
	else:
		push(STurnEnd.new())
	push(SkillRun.new(kind, data))


## 技能行动取消（角色在技能询问里点了「取消」，如【灵魂转换】的方向询问）：
## 让「技能用完即结束行动」的那个收尾改成重新进入行动阶段，玩家改做别的。
## 不这么做的话，取消＝本回合的行动白白用掉，回合直接结束。
## 只能在栈里就地设标记：run() 拿「状态下标还是不是自己」判断该状态是否自移除，
## 若在这里增删栈里非栈顶的状态（比如直接把 STurnEnd 抽掉），下标就错位、状态机当轮直接停摆
func 取消技能行动() -> void:
	for i: int in range(_states.size() - 1, -1, -1):
		if _states[i] is STurnEnd:
			(_states[i] as STurnEnd).回行动阶段 = true
			return


## 无法行动：把手里的牌全部弃掉（亮出牌面 + 弃牌动画）再摸 4 张。不消耗本回合行动，
## 换完手牌重新进入行动阶段让玩家拿新牌继续行动。
## 客户端在「技能栏没可用技能、手牌全打不出去、特殊行动也做不了」时提示玩家点「确定」触发
func _do_unactional(cur: BattlePlayer) -> int:
	# 不结束回合：换完手牌重新进入行动阶段
	push(SActionPhase.new())
	var old: Array = cur.hand_cards.duplicate()
	if not old.is_empty():
		take_from_hand(cur.id, old)
		to_discard(old)
		_log_discard(cur.id, old)
		# 把弃掉的牌亮出来给所有人看
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Show, "src_id": cur.id, "dst_id": cur.id, "card_ids": old, "is_real": true})
	# 摸 4 张走直连 draw：【无法行动】换手牌不算「技能让你摸牌」，不触发【水影】等「摸牌前发动」的响应；
	# 摸 4 张一般不会超上限，但手牌上限小于 4 的角色仍要照常结算爆牌
	push(SHandOverflow.new())
	draw(cur.id, 4)
	return CONTINUE


func _do_attack(cur: BattlePlayer, data: Dictionary) -> int:
	var cards: Array = data.get("card_ids", [])
	var dsts: Array = data.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		print("[战斗诊断] 攻击被丢弃：牌或目标为空 → 直接结束回合")
		push(STurnEnd.new())
		return CONTINUE
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	var 校验: int = cur.v_attack(cid, dst_id, players)
	if 校验 != GConst.GE_SUCCESS:
		print("[战斗诊断] 攻击被拒：v_attack 返回 %d（牌 %d，目标 %d，我方队色 %d，目标队色 %s）" % [
			校验, cid, dst_id, cur.color,
			str(players.get(dst_id).color if players.get(dst_id) != null else -9)])
		# 临时诊断
		return _reject_action(cur)
	# 防守方角色可拒绝被选为目标（如暗杀者潜行中「不能成为主动攻击的目标」）
	var dst_p: BattlePlayer = players.get(dst_id)
	if dst_p != null and dst_p.v_attacked() != GConst.GE_SUCCESS:
		return _reject_action(cur)
	push_after_action("p_after_attack", {"player": cur.id, "card_id": cid, "dst": dst_id})
	# 攻击方向也跑一次「视为」判定（与应战的 p_reattack 同一套）：角色可把这张攻击牌换成另一张，
	# 如苍炎魔女【烈焰形态】下除水系 / 暗系外的攻击牌一律视为火系虚拟【火焰斩】。
	# 真牌照样展示 + 进弃牌堆，本次攻击按「视为」的那张结算（系别就是那张牌的系别）
	var 出牌: Dictionary = {"player": cur.id, "card_id": cid, "改用": cid}
	if cur.role != null:
		cur.role.call_hook("p_attack_card", 出牌)
	var 用牌: int = int(出牌.get("改用", cid))
	var harm: Dictionary = {
		"src": cur.id, "dst": dst_id, "point": ATTACK_BASE_POINT, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 用牌, "is_active": true,
	}
	push(SAttackCard.new(cur.id, dst_id, 用牌, harm))
	# 攻击牌是公开打出的：带 已展示，take_from_hand 会顺手压「展示手牌」钩子。
	# 放在 push(SAttackCard) 之后，钩子才压在这次攻击之上、先结算（封印伤害先于本次攻击，同服务端 LIFO）
	take_from_hand(cur.id, [cid], true)
	to_discard([cid])
	# 广播里面把「视为」的那张放 as_card_id（同应战那条）：客户端按它出声、出特效
	# （如苍炎魔女【烈焰形态】下普通攻击视为火系【火焰斩】→ 播火斩特效与火系攻击音）；
	# 摊牌与日志仍用真正打出的牌
	broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true, "as_card_id": 用牌 if 用牌 != cid else 0})
	return CONTINUE


func _do_magic(cur: BattlePlayer, data: Dictionary) -> int:
	var cards: Array = data.get("card_ids", [])
	var dsts: Array = data.get("dst_ids", [])
	if cards.is_empty():
		push(STurnEnd.new())
		return CONTINUE
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not cur.has_hand_card(cid):
		return _reject_action(cur)
	# 角色可用 p_before_magic 禁止本次法术（如「暗影形态不能使用法术牌」；该钩子不得等待玩家输入）
	var gate: Dictionary = {"player": cur.id, "card_id": cid, "forbidden": false}
	if cur.role != null:
		cur.role.call_hook("p_before_magic", gate)
	if bool(gate.get("forbidden", false)):
		return _reject_action(cur)
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else cur.id
	var name_enum: int = card.card_name_enum()
	if name_enum == GConst.CardName.Shield:
		if cur.v_shield(dst_id, players) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [cid])
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		# 先压「行动结束」再压基础效果变更钩子：LIFO 下钩子先跑（对照服务端 basicMagic：
		# StateAfterMagic 先入栈、随后 setStateUseCard 把 StateBasicEffectChange 压在其上）。
		# 顺序颠倒会把钩子压在回合结束乃至下家整回合之下，天使羁绊这类钩子实际不会触发
		push_after_action("p_after_magic", {"player": cur.id, "card_id": cid})
		add_basic_effect(dst_id, cid, cur.id, GConst.CAUSE_USE)
		# 「展示手牌」钩子必须最后压（同 _do_attack 与应战抵挡那条）：压在动作状态之上才先执行。
		# 跟着 take_from_hand(已展示=true) 在开头就压的话，它会被埋在「回合结束」之下，而栈上又不断
		# 压入下一回合的状态 —— 这个钩子永远轮不到执行，冰霜祷言这种「公开打出水系牌时发动」的响应
		# 就从不触发（水系法术牌不触发的根因）
		push_show_hand(cur.id, [cid])
		_broadcast_game()
		return CONTINUE
	if name_enum == GConst.CardName.Weaken:
		if cur.v_weaken(dst_id, players) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [cid])
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		# 同上：行动结束先入栈，基础效果变更钩子后压（LIFO 下钩子先跑）
		push_after_action("p_after_magic", {"player": cur.id, "card_id": cid})
		add_basic_effect(dst_id, cid, cur.id, GConst.CAUSE_USE)
		push_show_hand(cur.id, [cid])
		_broadcast_game()
		return CONTINUE
	if name_enum == GConst.CardName.Poison:
		take_from_hand(cur.id, [cid])
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		# 同上：行动结束先入栈，基础效果变更钩子后压（LIFO 下钩子先跑）
		push_after_action("p_after_magic", {"player": cur.id, "card_id": cid})
		add_basic_effect(dst_id, cid, cur.id, GConst.CAUSE_USE)
		push_show_hand(cur.id, [cid])
		_broadcast_game()
		return CONTINUE
	if name_enum == GConst.CardName.Missile:
		# 落点默认是右手边最近的对手；有【魔弹掌控】802 的角色可以把落点选成左手边那个
		# （客户端点哪个就把哪个放在 dst_ids[0]，落点决定传递方向）
		var 候选: Array[int] = []
		if cur.role != null:
			候选 = cur.role.missile_targets(cur.id)
		else:
			var 顺: int = _nearest_enemy(cur)
			if 顺 >= 0:
				候选.append(顺)
		var target: int = 候选[0] if not 候选.is_empty() else -1
		var 顺向: bool = true
		if not dsts.is_empty() and 候选.has(int(dsts[0])):
			target = int(dsts[0])
			顺向 = target == _nearest_enemy(cur)
		# 角色可用 v_missile 禁止使用魔弹（如魔剑/魔枪的牌类禁止）
		if target >= 0 and cur.v_missile(cid, target) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [cid])
		to_discard([cid])
		push_after_action("p_after_magic", {"player": cur.id, "card_id": cid})
		if target >= 0:
			broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": target, "card_ids": [cid], "is_real": true})
			# 交给目标自己决定：打出【魔弹】继续传递 / 出【圣光】抵挡 / 放弃并承受伤害。
			# 即使他手里既没有【魔弹】也没有【圣光】，也要问一次并等他应答（对照服务端 StateMissiled）
			var used: Array[int] = [cur.id, target]
			push(SMissileAsk.new(target, cur.id, MISSILE_BASE_POINT, 顺向, used))
		# 展示手牌钩子最后压：压在动作状态与应战询问之上，先于它们执行（对照服务端 basicMagic 的
		# StateBeforeMagic → setStateUseCard(展示手牌) → StateMissiled 顺序）；压在开头则永远轮不到
		push_show_hand(cur.id, [cid])
		return CONTINUE
	# 其余法术牌（如【圣光】只作响应）不能主动施放
	return _reject_action(cur)


func _nearest_enemy(cur: BattlePlayer) -> int:
	var nid: int = cur.post_id
	for _i: int in range(order.size()):
		var pp: BattlePlayer = players.get(nid)
		if pp != null and pp.color != cur.color:
			return nid
		nid = next_id(nid)
	return -1


## 本次可以把魔弹传给谁（候选）：只有「当前传递方向上最近、本轮还没接过的对手」。
## 传递时一律不能改方向（【魔弹掌控】802 只作用于「主动打出」那一步，见 BattleRole.missile_targets）
func _missile_relay_targets(holder: int, post_dir: bool, used: Array[int]) -> Array[int]:
	var out: Array[int] = []
	var 顺: int = _next_missile_target(holder, post_dir, used)
	if 顺 >= 0:
		out.append(顺)
	return out


## 该方向上最近的一名「本轮还没参与过魔弹传递」的对手（对照服务端 StateMissiled）。
## 该方向上的人全都参与过之后从头再来：允许把魔弹递给已经接过的人（否则传完一圈就没人可接、链条卡死）。
func _next_missile_target(from_id: int, post_dir: bool, used: Array[int]) -> int:
	var cur: BattlePlayer = players.get(from_id)
	if cur == null:
		return -1
	var nid: int = cur.post_id if post_dir else cur.pre_id
	var 已传过的人: int = -1
	for _i: int in range(order.size()):
		var pp: BattlePlayer = players.get(nid)
		if pp == null:
			return -1
		if pp.color != cur.color:
			if not used.has(nid):
				return nid
			if 已传过的人 < 0:
				已传过的人 = nid
		nid = pp.post_id if post_dir else pp.pre_id
	return 已传过的人


## 目标若拥有【圣盾】或视作【圣盾】的【天使之墙】，移除之并返回 true（魔弹视作未命中）
func _missile_block_by_basic(target_id: int) -> bool:
	var dst: BattlePlayer = players.get(target_id)
	if dst == null:
		return false
	var cid: int = -1
	if dst.check_basic_effect_name(GConst.CardName.Shield):
		cid = _find_basic_card(dst, GConst.CardName.Shield)
	elif dst.check_basic_effect_skill(GConst.技能_天使之墙):
		cid = _find_basic_card_by_skill(dst, GConst.技能_天使之墙)
	if cid < 0:
		return false
	remove_basic_effect(target_id, cid, GConst.CAUSE_MISSILE)
	to_discard([cid])
	return true


## 这次打出的牌在系统里该「视为」哪张牌用，返回视为的牌号；牌本身就是它时返回 0。
## 目前只有【魔弹】有这种用法：地/火牌当【魔弹】打出去（【魔弹融合】发起、响应魔弹时拿地/火牌
## 继续传递）→ 返回【魔弹】牌号。出牌音效/特效、以及后续任何「这次是不是魔弹」的判断都按它走；
## 真正打出的那张地/火牌仍写在 card_ids 里（要展示、也确实进了弃牌堆）。
func missile_as_card(card_id: int) -> int:
	var 牌: GCard = Data.get_card(card_id)
	if 牌 != null and 牌.card_name_enum() == GConst.CardName.Missile:
		return 0
	return Data.card_id_by_name_enum(GConst.CardName.Missile)


func _do_special(cur: BattlePlayer, data: Dictionary) -> int:
	var aid: int = int(data.get("action_id", -1))
	var args: Array = data.get("args", [])
	# 角色可用 p_before_special 禁止本次特殊行动（该钩子不得等待玩家输入）
	var gate: Dictionary = {"player": cur.id, "action_id": aid, "forbidden": false}
	if cur.role != null:
		cur.role.call_hook("p_before_special", gate)
	if bool(gate.get("forbidden", false)):
		return _reject_action(cur)
	if aid == GConst.SpecialAction.Buy:
		if cur.v_buy(args) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		_log_special(cur, aid)
		set_team_gem(cur.color, team_gem[cur.color] + (int(args[0]) if args.size() > 0 else 0))
		set_team_crystal(cur.color, team_crystal[cur.color] + (int(args[1]) if args.size() > 1 else 0))
		# 【特殊行动】的摸牌不走 push_draw（技能表：水影等响应写明「除【特殊行动】外」）
		draw(cur.id, 3)
		_broadcast_game()
		push_after_action("p_after_special", {"player": cur.id, "card_id": -1, "special_action": true})
		push(SHandOverflow.new())
		return CONTINUE
	if aid == GConst.SpecialAction.Synthesize:
		if cur.v_synthesize(args, team_energy(cur.color), team_gem[cur.color], team_crystal[cur.color]) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		_log_special(cur, aid)
		_spend_team_energy(cur.color, int(args[0]) if args.size() > 0 else 0, int(args[1]) if args.size() > 1 else 0)
		team_grail[cur.color] += 1
		# 【特殊行动】的摸牌不走 push_draw（技能表：水影等响应写明「除【特殊行动】外」）
		draw(cur.id, 3)
		_broadcast_game()
		if team_grail[cur.color] >= GConst.GRAIL_WIN:
			_game_over(cur.color)
			return CONTINUE
		push_after_action("p_after_special", {"player": cur.id, "card_id": -1, "special_action": true})
		push(SHandOverflow.new())
		return CONTINUE
	if aid == GConst.SpecialAction.Extract:
		var dsts: Array = data.get("dst_ids", [])
		# 提炼校验：常规提炼按自身空位；【冒险者天堂】自己的那份按自身空位、队友那份按队友空位
		# （由角色覆写 v_extract）
		if cur.v_extract(args, team_gem[cur.color], team_crystal[cur.color], dsts) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		_log_special(cur, aid)
		# 常规提炼 args = [宝石, 水晶]；【冒险者天堂】的头位是 GConst.提炼天堂标记
		var 是天堂: bool = not args.is_empty() and int(args[0]) == GConst.提炼天堂标记
		if not 是天堂:
			# 常规提炼：从战绩区取出、归自己
			var g3: int = int(args[0]) if args.size() > 0 else 0
			var c3: int = int(args[1]) if args.size() > 1 else 0
			set_team_gem(cur.color, team_gem[cur.color] - g3)
			set_team_crystal(cur.color, team_crystal[cur.color] - c3)
			cur.set_gem(cur.gem + g3)
			cur.set_crystal(cur.crystal + c3)
		else:
			# 【冒险者天堂】：args = [标记, 自己的宝石, 自己的水晶, 队友的宝石, 队友的水晶, 移除的自身能量 X,
			# 各目标颗数…]。星石只能分给队友（自己那两位恒为 0），战绩区按「队友那份」扣；
			# 再移除自身 X 点能量（额外提炼的 X 颗每颗代价 1 点能量），
			# 队友按客户端提交的颗数领（宝石 / 水晶的构成不影响能量总量，按宝石优先发放）
			var 自己宝石: int = int(args[1]) if args.size() > 1 else 0
			var 自己水晶: int = int(args[2]) if args.size() > 2 else 0
			var 队友宝石: int = int(args[3]) if args.size() > 3 else 0
			var 队友水晶: int = int(args[4]) if args.size() > 4 else 0
			var x3: int = int(args[5]) if args.size() > 5 else 0
			set_team_gem(cur.color, team_gem[cur.color] - 自己宝石 - 队友宝石)
			set_team_crystal(cur.color, team_crystal[cur.color] - 自己水晶 - 队友水晶)
			cur.set_gem(cur.gem + 自己宝石)
			cur.set_crystal(cur.crystal + 自己水晶)
			cur.remove_energy(x3)
			var 宝石池: int = 队友宝石
			for i: int in range(dsts.size()):
				var 枚: int = int(args[6 + i])
				var 目标: BattlePlayer = players.get(int(dsts[i]))
				var 给宝石: int = mini(枚, 宝石池)
				宝石池 -= 给宝石
				目标.set_gem(目标.gem + 给宝石)
				目标.set_crystal(目标.crystal + (枚 - 给宝石))
		_broadcast_game()
		push_after_action("p_after_special", {"player": cur.id, "card_id": -1, "special_action": true})
		if 是天堂:
			# 发动了【冒险者天堂】：给角色一次广播技能通知的机会
			push(SHook.new("p_extract_to", {"player": cur.id, "dst_ids": dsts}, []))
		return CONTINUE
	# 未知特殊行动
	return _reject_action(cur)


func _spend_team_energy(color: int, gem: int, crystal: int) -> void:
	var need: int = 3
	var use_gem: int = mini(gem, team_gem[color])
	var use_crystal: int = mini(crystal, team_crystal[color])
	need -= use_gem + use_crystal
	while need > 0:
		if team_gem[color] - use_gem > 0:
			use_gem += 1
		elif team_crystal[color] - use_crystal > 0:
			use_crystal += 1
		else:
			break
		need -= 1
	set_team_gem(color, team_gem[color] - use_gem)
	set_team_crystal(color, team_crystal[color] - use_crystal)


## 特殊行动日志：谁执行了购买 / 合成 / 提炼（写进战斗日志）
func _log_special(cur: BattlePlayer, aid: int) -> void:
	var 名: String = ""
	match aid:
		GConst.SpecialAction.Buy:
			名 = "购买"
		GConst.SpecialAction.Synthesize:
			名 = "合成"
		GConst.SpecialAction.Extract:
			名 = "提炼"
	if 名.is_empty():
		return
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Skill, "id": cur.id,
		"txt": "%s 执行【%s】" % [_称号(cur), 名],
	})


# ============================================================
# 士气与结束
# ============================================================
## 掉士气（带角色钩子；ctx 的 cause/harm_cause = 本次掉士气来源，type = 伤害类型）
## 与服务器一致：before / true 钩子对「所有玩家」按座位序调用（如蝶舞的凋零形态要限制
## 对手的士气下降、月女的新月庇护要响应队友的士气下降），钩子内部按 ctx["dst"] 自行判断是否相关。
## 限制：本实现为同步调用，钩子内不能等待玩家输入。超限掉士气走 SOverloadMorale（可等待，见下），
## 需要等待支付的技能（如天使的神之庇护 706）在那边实现。
## 本入口只用于「非伤害」来源（逆反居合斩 / 暗月诅咒）：对照服务端，这类惩罚的 harm.type = HARM_NONE、
## harm.cause = 技能 cause，不能沿用 last_harm_*（最近一次伤害的上下文）——否则依 type 判定的钩子
## （新月庇护 / 神之庇护 / 舞女同生 / 蝶舞凋灵…）会把非伤害惩罚误判成「因伤害掉士气」。
## 因伤害掉士气（手牌超限）走 SOverloadMorale，其 harm 上下文由伤害那一拍显式带入。
func lose_morale(target: BattlePlayer, amount: int, cause: int) -> void:
	var ctx: Dictionary = {
		"dst": target.id, "amount": amount, "cause": cause,
		"harm_cause": cause, "type": GConst.HarmType.None,
	}
	# 对照原版掉士气链：StateBeforeLoseMorale → StateXinYue → StateLoseMorale → StateFixMorale
	# → StateTrueLoseMorale，全部跑完才真正扣士气（角色在钩子里可以改 ctx["amount"]，
	# 如天使【神之庇护】抵消、蝶舞【凋灵】把对方士气兜到最少 1）
	for 钩子: String in ["p_before_lose_morale", "p_xin_yue", "p_lose_morale", "p_fix_morale", "p_true_lose_morale"]:
		for pid: int in order:
			var p0: BattlePlayer = players.get(pid)
			if p0 != null and p0.role != null:
				p0.role.call_hook(钩子, ctx)
	amount = int(ctx.get("amount", amount))
	set_morale(target.color, team_morale[target.color] - amount)
	_check_game_over()


func _check_game_over() -> void:
	if phase == Phase.Over:
		return
	if team_morale[GConst.RED] <= 0:
		_game_over(GConst.BLUE)
	elif team_morale[GConst.BLUE] <= 0:
		_game_over(GConst.RED)


func _game_over(win_color: int) -> void:
	phase = Phase.Over
	winner = win_color
	_states.clear()
	# 终局后不再受理任何玩家回复：清掉等待 / 回复 / 分步应答 / 查询链倒计时，
	# 否则残留在这些字段里的回复会被后续流程（或下一次对局复用引擎时）误用
	_清空等待()
	_broadcast_game()
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Notice,
		"txt": "游戏结束，%s方获胜！" % ("红" if win_color == GConst.RED else "蓝"),
		"id": 0,
	})

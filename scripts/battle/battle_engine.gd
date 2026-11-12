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

const 行动来源_角色: String = "role"
const 行动来源_额外: String = "extra"
const 行动来源_基础: String = "basic"
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
## 选角阶段「已准备」的座位号（本地扩展，随 Game 快照下发）：选角界面底部的「立即开始（x/X）」据此显示。
## 由 LocalServer 在选角期间维护（见 _on_pick_ban_candidates）
var pick_ready: Array[int] = []
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
## 房主坐在哪个座位上（-1 = 没记录）：客户端据此在「玩家列表」里给房主标个星号。
## 房主是房间层面的概念，引擎自己不知道，由 LocalServer 每次广播前塞进来（见 LocalServer._房主座位）
var host_seat: int = -1

## 队伍数值，下标为颜色（0 蓝 / 1 红）
var team_morale: Array[int] = [0, 0]
var team_gem: Array[int] = [0, 0]
var team_crystal: Array[int] = [0, 0]
var team_grail: Array[int] = [0, 0]
## 场卡（F1）：摆在场上或某人面前的公共卡，不属于任何人的手牌 / 盖牌。
## 每项 shape 见 加场卡() 的注释；按 id 唯一（重复放置前先 移除场卡）。
## 目前用在：【异端裁决所】39 /【末日预言】95 /【绝界】82。
var field_cards: Array[Dictionary] = []

## 发送回调：(目标id:int, 协议号:int, 字段:Dictionary) -> void
var send_cb: Callable = Callable()

# ---------- 对局埋点（battle_start / round_end / battle_end，只由房主进程上报） ----------
## 上报回调：(事件名:String, 属性:Dictionary) -> void。LocalServer 建房间时注入；
## 引擎只负责按当前对局状态组快照，组包 / 重试 / 网络在 scripts/net/telemetry.gd
var telemetry_cb: Callable = Callable()
## 座位 → 登录时的身份标识（Steam = SteamID，本地 = 昵称）。开局前由 LocalServer 写入。
## 座位号只是本局内部编号，埋点里的 steam_id 要用这个
var 玩家标识: Dictionary = {}
## 本次战斗的唯一标识：开局时生成，三个事件共用，靠它把同一场战斗串起来
var battle_id: String = ""
## 本回合每个座位的统计（键就是埋点属性名：heal_amount / heal_enemy / 6 项伤害），每回合结束时清零
var _回合统计: Dictionary = {}
## 最近一次伤害的发起者：超限掉士气时按它归属到「谁的伤害把人打崩了」
var _最后伤害来源: int = -1
## 埋点取号专用的随机源：和战斗判定用的 _rng、牌库洗牌用的全局 randi() 都分开，
## 免得为了取个号把对局随机结果改掉（tests/diffProbe 固定 _rng 种子做对比）
var _埋点rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 状态机
var _states: Array = []
## 本回合要不要跳过行动阶段（虚弱拒绝 / 五系束缚拒绝）：轮到 SActionPhase 时它自己直接收尾进回合结束。
## 用标记而不是「把 SActionPhase 从栈里抠掉再压回合结束」，是为了不打断它上面还有的 p_boot / p_before_action 钩子
var skip_action_phase: bool = false
## 待消费的「跳过行动阶段」来源（F9 / 10602：请求跳过时写，SActionPhase 消费时搬到本回合记录）
var 跳过行动阶段来源: int = 0
## 本回合的 SActionPhase 是否真的被跳过行动阶段效果跳过（F9 / 10605「你跳过行动阶段后」用它判断）。
## SCheckTurnStart 清零；SActionPhase 消费 skip_action_phase 时置位。
var 本回合跳过行动阶段: bool = false
## 本回合跳过行动阶段的来源技能号（0＝不是技能跳过，如虚弱拒绝 / 五系束缚）
var 本回合跳过行动阶段来源: int = 0
## 本次行动阶段放行的行动种类与是否允许「放弃行动」：对照原版 StateActionPhase(allowAction, canGiveUp)。
## 普通行动阶段 = Any + 不允许放弃；额外行动阶段 = 该额外行动声明的 allowAction + 允许放弃；
## 被【挑衅】时 = 只能攻击 + 允许放弃
var 行动允许: int = GConst.ActionType.Any
var 行动可放弃: bool = false
## 本次行动阶段是不是「额外行动」（额外行动阶段允许放弃，与「被挑衅」那种可放弃的普通阶段区分开）
var 行动额外: bool = false
## 本次额外行动的触发来源（cause）：苍白之月要据此把提示写成「获得额外【无法应战】攻击行动」
var 行动额外来源: int = 0
## 正处在「技能出牌」里（见 技能出牌）：那次出牌是技能效果的一部分，不压回合结束
var _技能出牌中: bool = false
## 这次技能出牌要不要顺带开「行动结束响应」：默认要（真言术本体）；
## 但由响应技能（真言压制）白送的那次真言术不要 —— 它本身还在外层响应的「待决」里，
## 再开一轮响应就会套娃，玩家得一层层取消。角色在调 技能出牌 之前把它置 true。
var 技能出牌不开响应: bool = false
## 本次行动阶段是否禁止「特殊行动」（购买/合成/提炼）。发动过「启动」技能后，行动阶段照旧继续，
## 但只能再攻击 / 法术，不能再走特殊行动（启动技与特殊行动互斥）
var 行动禁特殊: bool = false
## 攻击结束响应里玩家点了「额外攻击行动」快捷按钮：下一次 SAdditionalAction 直接进入它。
## 数据存在当前玩家身上，不再用引擎全局字段跨状态携带。
var 首选额外行动: int:
	get:
		var cur: BattlePlayer = p(current_id)
		return cur.快捷额外行动 if cur != null else -1
	set(value):
		var cur: BattlePlayer = p(current_id)
		if cur != null:
			cur.快捷额外行动 = value
## 响应里点额外攻击时已经选好的攻击牌 / 目标：进入该额外行动后直接用它们发起攻击
var 首选额外行动卡: int:
	get:
		var cur: BattlePlayer = p(current_id)
		return cur.快捷额外行动卡 if cur != null else -1
	set(value):
		var cur: BattlePlayer = p(current_id)
		if cur != null:
			cur.快捷额外行动卡 = value
var 首选额外行动目标: int:
	get:
		var cur: BattlePlayer = p(current_id)
		return cur.快捷额外行动目标 if cur != null else -1
	set(value):
		var cur: BattlePlayer = p(current_id)
		if cur != null:
			cur.快捷额外行动目标 = value
## 当前额外行动阶段的原始数据（同一份引用：技能在 p_additional_action 里改写规格也改它）
var 当前额外行动数据: Dictionary = {}
## 按「系别 / 命格」规则算出的可用攻击牌 id 表缓存（"系别_命格" → 卡库 id 表），
## 见 额外行动出牌白名单
var _规则攻击牌缓存: Dictionary = {}
## 测试指令「跳过自己回合」（战斗界面按 8）：记下是谁按的，行动阶段轮到他直接收尾（-1 = 无）
var 测试跳过回合: int = -1
## 角色的 p_after_turn_end 要求「接下来的回合还是他」时写这里（月女【苍白之月】），
## 轮到 SNextPlayer 时据此不轮转、直接重开他的回合（对照原版：角色把 StateAfterTurnEnd 弹掉，跳过轮转）。
## F7 的「额外回合」（10803）也走这条：接口见 安排额外回合()。额外回合本身不推进 current_id / round_id。
var 额外回合玩家: int = -1
## 待执行的额外回合的攻击加伤（F7 / 10803：该额外回合你的攻击伤害 +1）。
## 在 SNextPlayer 真正开始额外回合时搬到 当前额外回合攻击加伤，回合结束后清零。
var 额外回合攻击加伤: int = 0
## 安排这份额外回合的来源技能号（F7 / 10803）；只用于快照 / 日志，不参与结算
var 额外回合来源: int = 0
## 当前正在执行的是谁的额外回合（-1＝普通回合）。STurnEnd 收尾时由 SNextPlayer 清掉。
var 当前额外回合玩家: int = -1
## 当前这个额外回合里「该玩家攻击伤害 +1」的数值（只作用于额外回合的主人）
var 当前额外回合攻击加伤: int = 0
## 当前额外回合的来源技能（如剑守誓言 10803）：快照里下发给客户端画状态图标
var 当前额外回合来源: int = 0
## 额外回合结束后的「续位」：安排那一刻本该轮到的人（当作没有这次额外回合）。
## 10803 会在**别人**的回合结束时触发，结束后必须回到那个人之后继续，
## 不能从额外回合主人的下家继续（否则整轮顺序被改写）。只在一条链的第一次安排时取号。
var 额外回合续位: int = -1
## 各玩家上次记录的手牌数量（player_id -> 张数），用于在「手牌变化」时触发 p_hand_change
var _hand_counts: Dictionary = {}
## 刚写过「获得【具体牌名】」或摸牌「获得 N 张牌」的玩家：SRunHandChange 不再补一条
## 泛化的「获得 N 张牌」，避免同一次获得出现三行（具体牌 / 获得 N 张 / 手牌变化）。
var _获得牌已播: Dictionary = {}
## 各玩家上次记录的手牌上限（player_id -> 张数），用于在「手牌上限变化」时写日志
var _hand_maxes: Dictionary = {}
## 各玩家上次记录的指示物数量（player_id -> Array[int]），用于在「指示物变化」时写日志
var _token_counts: Dictionary = {}
## 各玩家上次记录的盖牌张数（player_id -> int），用于在「盖牌变化」时写一条和指示物同类的日志
var _cover_counts: Dictionary = {}
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
## 盖牌变动序号：每次 add / remove 唯一。钩子返回 URGENT 时引擎会回栈重跑同一个钩子，
## 角色据此判断「这次 add 已经处理过」，避免盖牌渗蚀这类一次性效果被反复触发。
var _cover_change_seq: int = 0
## 尚未执行的盖牌变动钩子数：add/remove 时 +1，p_cover_change 跑完一个 -1。
## SHook 里某个角色中途放了盖牌并返回 SUCCESS 时，SHook 主动让出一次执行权，
## 让 p_cover_change 立刻结算，而不是等当前 SHook 把所有角色跑完。
var _盖牌变动待处理: int = 0
## 噬神者专属刃的唯一实例归属：实例号 -> 初始拥有者 pid（之后不变）
var 刃归属: Dictionary = {}
var _刃序号: int = 0
## 当前正在 handle 的状态实例（run 内逐状态设置）：wait_for 据此登记等待归属，
## has_reply / take_reply 据此判断「这份回复是不是发给我的」
var _当前状态: Variant = null
## 当前行动询问允许的行动种类（ask_action 写入）：快照里据此给客户端下发
## 「等待行动 / 等待攻击行动 / 等待法术行动」这类头像文案
var _pending_action_type: int = 0
var _reply: Dictionary = {}
## 「已经收到、但还没被取走」的回复暂存：等待归属的状态实例 -> {reply, kind}。
## 等待期间被压到栈上的状态会先问别人（如 p_tap 钩子里兽灵【兽魂警戒】的询问），
## 它的 wait_for 会顶掉等待槽；覆盖前先把上一位等待者的回复按它的归属状态存到这里，
## 等那个状态重新回到栈顶时再恢复 —— 否则「回复已经回来了、却被别人的询问冲掉」，
## 表现为玩家选了牌 / 点了目标却什么都没发生（女武神【英灵召唤】踩过）。
var _挂起回复: Dictionary = {}
## 客户端攒操作时预置的应答：由角色在询问别人之前写入，轮到该询问时直接取用、不再等客户端
var _prepared_replies: Dictionary = {}
var _has_reply: bool = false
## 当前等待的截止时刻（Time.get_ticks_msec() 口径，0 表示当前没有在等）
var wait_deadline_ms: int = 0
## 等待序号：每开始一次新的等待 +1。客户端据此只在「确实换了一次等待」时才弹
## 「正在等待 X 操作…」提示 —— 中途有人进房等触发的快照重发不会让全场重复弹
var wait_seq: int = 0
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
## 快捷额外攻击已经转成普通回复，聚合器分派成功后立即收尾
var _快捷提前收尾: bool = false
## 已下发过的询问次数（测试用：确认取消后没有再次询问）
var _询问计数: int = 0
## 本次攻击结束响应里已经确认过的基础效果额外行动（技能号 -> true）
var _基础效果额外行动已确认: Dictionary = {}


## 某份基础效果额外行动是否已经确认过
func 基础效果额外行动已确认(cause: int) -> bool:
	return bool(_基础效果额外行动已确认.get(cause, false))


## 目标身上还有哪些未确认的基础效果额外行动（供角色询问循环继续问）
func 基础效果额外行动选项(pid: int) -> Array:
	var cur: BattlePlayer = players.get(pid)
	var out: Array = []
	if cur == null or cur.基础效果禁用:
		return out
	for cause: int in GConst.基础效果额外行动:
		if 基础效果额外行动已确认(cause):
			continue
		if not cur.check_basic_effect_skill(cause):
			continue
		if cur.hand_cards.is_empty():
			continue
		var 配置: Dictionary = GConst.基础效果额外行动[cause]
		out.append({
			"value": cause,
			"label": str(配置.get("label", GConst.skill_name(cause))),
			"skill_id": cause,
		})
	return out


## 收集本次行动结束响应的所有选项。聚合器不关心来源类型，只消费这里合并后的描述。
## kind：role＝角色技能；extra＝队列里的额外行动；basic＝基础效果额外行动。
## 排序：行动在前、响应在后 —— 队列额外行动（_sort 0）→ 基础效果（1）→ 角色响应技能（2）；
## 同一组内按收集顺序（_seq）排。
## 只基础＝玩家已经取消过本回合的行动结束响应：不再提供角色 / 队列的额外攻击行动，
## 但基础效果（迅捷赐福）是「每次攻击 / 法术行动结束都可以发动」的独立响应，仍要提供。
func _收集行动结束选项(pid: int, ctx: Dictionary, 只基础: bool = false) -> Array:
	var out: Array = []
	var cur: BattlePlayer = players.get(pid)
	if cur == null:
		return out
	var 序号: int = 0
	if not 只基础 and cur.role != null:
		for o: Dictionary in cur.role.行动结束来源(ctx):
			var 项: Dictionary = o.duplicate()
			项["_kind"] = str(项.get("_kind", 行动来源_角色))
			项["_sort"] = int(项.get("_sort", 2))
			项["_seq"] = 序号
			序号 += 1
			out.append(项)
	for o: Dictionary in 基础效果额外行动选项(pid):
		var 已有: bool = false
		for old: Dictionary in out:
			if int(old.get("value", 0)) == int(o.get("value", 0)):
				已有 = true
				break
		if 已有:
			continue
		var 项: Dictionary = o.duplicate()
		项["_kind"] = 行动来源_基础
		项["_sort"] = 1
		项["_seq"] = 序号
		序号 += 1
		out.append(项)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = int(a.get("_sort", 0))
		var sb: int = int(b.get("_sort", 0))
		if sa == sb:
			return int(a.get("_seq", 0)) < int(b.get("_seq", 0))
		return sa < sb)
	return out


## 把选中的行动结束选项分派回来源。返回 result（SUCCESS/WAIT/URGENT）+ terminal。
## terminal=true：该来源的 URGENT 已经结算完，不需要回来继续；false：多步角色技能还要回来。
func _分派行动结束选项(pid: int, cause: int, reply: Dictionary, kind: String,
		ctx: Dictionary) -> Dictionary:
	if kind == 行动来源_基础:
		var 基础cur: BattlePlayer = players.get(pid)
		if 基础cur == null or 基础cur.基础效果禁用 or not 基础cur.check_basic_effect_skill(cause) \
				or 基础效果额外行动已确认(cause):
			return {"result": GConst.GE_INVALID_ACTION, "terminal": true}
		_确认基础效果额外行动(pid, cause)
		_基础效果额外行动已确认[cause] = true
		return {"result": BattleRole.SUCCESS, "terminal": true}
	var cur: BattlePlayer = players.get(pid)
	if cur == null or cur.role == null:
		return {"result": GConst.GE_INVALID_ACTION, "terminal": true}
	if kind == 行动来源_额外:
		var 结果: int = cur.role.resolve_queued_extra_action(cause)
		# 基础效果额外行动（迅捷赐福）从队列路径点选时，代价（移除赐福牌）也要在响应点选时结算，
		# 不能等进入额外行动阶段 —— 与「响应里点选就扣代价」保持一致。
		if (结果 == BattleRole.SUCCESS or 结果 == BattleRole.URGENT) \
				and GConst.基础效果额外行动.has(cause):
			_支付基础效果额外行动(pid, cause)
		return {"result": 结果, "terminal": true}
	return {"result": cur.role.resolve_action_end_option(cause, reply, ctx), "terminal": false}
## 本次技能询问「能不能取消」「要选几名目标」「合法目标白名单」：超时兜底要据此判断
## 「不许回取消」以及「从谁里面随机挑目标」（如【念弹】：问之前就已记上 +1【斗气】，不能白拿）
var _pending_skill_can_cancel: bool = true
var _pending_skill_need_target: int = 0
var _pending_skill_targets: Array = []
## 不可取消的技能询问超时时优先从这里挑目标（如冰冻 +1 治疗只能自动选友方）
var _pending_skill_timeout_targets: Array = []
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
	_转动座位到先手()


## 把座位环的起点转到先手（红队第一个行动的人）上：选角界面顶部的座位条按 order 的顺序摆，
## 于是它就从先手开始排。转的只是「从谁开始数」，环内的相邻关系（pre/post）不受影响。
func _转动座位到先手() -> void:
	var 起点: int = order.find(_先手座位())
	if 起点 <= 0:
		return
	var 新序: Array[int] = []
	for i: int in order.size():
		新序.append(order[(起点 + i) % order.size()])
	order = 新序


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
		first_id = _先手座位()


## 先手座位：从 0 号座位沿座位顺序往前走，第一个红队玩家 —— 每轮行动固定由红队开始。
## 分队之前（准备室 / 选角中）谁都还不是红队，此时退回 order[0]（那个阶段用不到先手）
func _先手座位() -> int:
	for pid: int in order:
		# 变量名别用 p：类里有个取玩家的方法也叫 p()（见文件后部），p 作局部名会被判定为遮蔽
		var p0: BattlePlayer = players.get(pid)
		if p0 != null and p0.color == GConst.RED:
			return pid
	return order[0]


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
	Data.清空实例卡()
	_属性归属.clear()
	刃归属.clear()
	_刃序号 = 0
	deck = BattleDeck.new()
	deck.init_full()
	balance_colors()
	_rebuild_links()
	current_id = first_id
	round_id = 1
	phase = Phase.Playing
	winner = -1
	_不爆牌.clear()
	额外回合玩家 = -1
	额外回合攻击加伤 = 0
	额外回合来源 = 0
	当前额外回合玩家 = -1
	当前额外回合攻击加伤 = 0
	当前额外回合来源 = 0
	额外回合续位 = -1
	var base_morale: int = 士气上限()
	team_morale = [base_morale, base_morale]
	team_gem = [0, 0]
	team_crystal = [0, 0]
	team_grail = [0, 0]
	for pid: int in order:
		var 玩家: BattlePlayer = players[pid]
		玩家.hand_cards.clear()
		玩家.cover_cards.clear()
		玩家.basic_effects.clear()
		玩家.魔刃实例 = -1
		玩家.异刃实例 = -1
		玩家.ready = true
	if role_map.is_empty():
		_assign_roles(role_pool)
	else:
		_assign_roles_by_map(role_map)
	_初始化噬神者刃()
	# 没有角色脚本的「白板角色」也按角色表初始化指示物 / 盖牌上限（F3）：
	# 有脚本的角色在 BattleRole.setup() 里做同一件事；这里只兜底 role 为 null 的玩家，
	# 不覆盖脚本自己设置的开局指示物数量（如灵魂术士 setup 里 +3 战纹）。
	for pid: int in order:
		var p3: BattlePlayer = players[pid]
		if p3.role == null:
			p3.按表初始化指示物()
	# 角色构造：让角色做开局初始化（指示物等）
	for pid: int in order:
		var p2: BattlePlayer = players[pid]
		if p2.role != null:
			p2.role.call_hook("p_before_turn_begin", {"init": true})
	for pid: int in order:
		players[pid].add_hand_cards(deck.draw(GConst.START_HAND))
	# 埋点：这一局的标识 / 统计从零开始（battle_start / round_end / battle_end 共用 battle_id）。
	# 随机段用埋点专用随机源：_rng 是战斗判定用的、全局 randi() 被牌库洗牌用，动哪个都会改对局结果。
	# 三段各 6 位（1e18 种组合）：同一秒、同一微秒创建两间房也撞不上
	_埋点rng.randomize()
	battle_id = "R%d-%d-%d-%06d-%06d-%06d" % [
		room_id, int(Time.get_unix_time_from_system()), Time.get_ticks_usec() % 1000000,
		_埋点rng.randi_range(0, 999999), _埋点rng.randi_range(0, 999999), _埋点rng.randi_range(0, 999999)]
	_回合统计.clear()
	_最后伤害来源 = -1
	_states.clear()
	_进度表.clear()
	_清空等待()
	_broadcast_game()
	_上报事件("battle_start", 0)
	broadcast(GConst.Msg.TurnBegin, {"id": current_id, "round": round_id, "extra_turn": false})
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


# ============================================================
# 噬神者专属刃 / 移除牌堆
# ============================================================
## 移除牌堆：被「移除」的牌实体收在这里（当前只有噬神者【渗蚀】会移除刃）。
## **不在移除牌堆里＝在场**：技能要用一张牌的实例之前，先过 牌在场() 这一关，
## 不在场的牌不能进入后续选项 / 结算。刃在移除牌堆里时才算「不在场」，御刃/共振/侵刻
## 必须先用 刃从移除牌堆取出() 把它取出来，才能加回手牌 / 交给别人。
var 移除牌堆: Array[int] = []


## 这张牌的实例是否还在场（只要不在移除牌堆就算在场）。
## 注意：0 是合法实例号（牌库卡的实例号==牌号，卡表#0 就是【圣盾】），不能拿 >0 当「有效实例」；
## 只有负数（-1 等）才代表「没有这张牌」。
func 牌在场(inst: int) -> bool:
	return inst >= 0 and not 移除牌堆.has(inst)


## 过滤出一组仍在场的牌实例（保持原顺序）。技能把收集来的牌列成选项 / 继续结算之前
## 统一用它，避免把已被移除的牌当成还能用的牌。
func 在场牌(ids: Array) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in ids:
		if 牌在场(int(c)):
			out.append(int(c))
	return out


## 把一张牌的实体移入移除牌堆（幂等）
func 放入移除牌堆(inst: int) -> void:
	# 0 是合法实例号（卡表#0 圣盾），只有负数才代表「没有这张牌」
	if inst >= 0 and not 移除牌堆.has(inst):
		移除牌堆.append(inst)


## 从移除牌堆取出这张牌（不在这里返回 -1）；取出来的牌可以重新加回手牌 / 盖牌等
func 从移除牌堆取出(inst: int) -> int:
	var idx: int = 移除牌堆.find(inst)
	if idx < 0:
		return -1
	移除牌堆.remove_at(idx)
	return inst


## 刃专用别名：取出一张刃的唯一实例（不在移除牌堆返回 -1）
func 刃从移除牌堆取出(inst: int) -> int:
	return 从移除牌堆取出(inst)


func _初始化噬神者刃() -> void:
	for pid: int in order:
		确保噬神者刃(pid)


## 给一名已经确定为噬神者的玩家创建两张唯一刃实例（幂等）。
## 正常开局由 _初始化噬神者刃 统一调；测试/中途设角色也能显式调。
## 两张刃初始就「不在场」：实体收在 移除牌堆（不在牌库 / 弃牌堆 / 手牌 / 盖牌），
## 由【御刃】【共振】先用 刃从移除牌堆取出() 取出，再加回手牌（被【渗蚀】移除后也是同一条路）。
func 确保噬神者刃(pid: int) -> void:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null or p0.role_id != GConst.角色_噬神者 or p0.魔刃实例 >= 0:
		return
	_刃序号 += 1
	var seq: int = 100 + _刃序号
	for 面: int in [GConst.噬神者_魔刃卡, GConst.噬神者_异刃卡]:
		var inst: int = GConst.实例号(面, seq)
		var 牌面: GCard = Data.get_card(面)
		var 元素: int = 牌面.可选元素[0] if 牌面 != null and not 牌面.可选元素.is_empty() else 0
		Data.取实例卡(inst, 元素, pid)
		刃归属[inst] = pid
		放入移除牌堆(inst)
		if 面 == GConst.噬神者_魔刃卡:
			p0.魔刃实例 = inst
		else:
			p0.异刃实例 = inst


func 刃归属者(inst: int) -> int:
	return int(刃归属.get(inst, -1))


## 当前持有者（手牌/盖牌）；不在这些区域返回 -1
func 刃持有者(inst: int) -> int:
	for pid: int in order:
		var p0: BattlePlayer = players.get(pid)
		if p0 == null:
			continue
		if p0.hand_cards.has(inst) or p0.cover_cards.has(inst):
			return pid
	return -1


## 按「归属者的唯一实例」判断是否在场：只要不在移除牌堆里就算在场。
## （刃被【渗蚀】移除后收进移除牌堆 → 不在场，御刃/共振可以把它取出来用）
func 刃在场(pid: int, 面: int) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return false
	var inst: int = p0.刃实例(面)
	if inst < 0:
		return false
	return 牌在场(inst)


## 把某张刃按记录的唯一实例加回某人的手牌（刃被移除后实体不在任何区域，也走这条）。
## 只负责加牌与清攻击牌缓存；广播 / 播报由调用方按技能需要决定。
func 刃加入手牌(pid: int, inst: int) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null or inst < 0:
		return false
	_规则攻击牌缓存.clear()
	p0.add_hand_cards([inst])
	return true


## 角色卡替换（F7 / 10803：剑之子 → 风之剑圣）。
## 顺序：旧角色 p_before_role_replace 清理自己的形态/标记 → 解绑旧角色（之后不会再收到任何钩子）
## → 清通用状态（横置、额外行动、行动计数、启动标记）→ 按需把上限恢复到基础上限
## → 清空指示物槽 / 盖牌上限 → 写新角色号并按角色表重新 setup（技能、指示物、上限加成都会重算）。
## 手牌 / 盖牌 / 基础效果 / 能量 / 治疗 / 战绩区等「玩家身上的资源」保留，不做回收。
## 同步调用：在角色技能结算末尾调用（p_before_role_replace 不得等待玩家输入）。
func 替换角色(pid: int, 新角色id: int, 重置上限: bool = true) -> int:
	if 新角色id <= 0:
		return GConst.GE_INVALID_TABLEID
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return GConst.GE_INVALID_PLAYERID
	var 旧角色名: String = Data.role_name(p0.role_id)
	# 指示物：两张角色卡共用同一个计数板时（红衣主教 / 铸律者的【银制子弹】【圣遗物】），
	# 数值要跟着换过去的角色卡走 —— 否则「+2 银制子弹 / +2 圣遗物」在替换这一步凭空消失
	var 旧指示物: Array = []
	for 槽: int in [0, 1]:
		var 旧定义: Dictionary = p0.token_def(槽)
		if not 旧定义.is_empty():
			旧指示物.append({"name": str(旧定义.get("name", "")), "num": int(旧定义.get("num", 0))})
	if p0.role != null:
		p0.role.call_hook("p_before_role_replace", {"player": pid, "new_role_id": 新角色id})
	# 解绑旧角色：setter 会把它自己的 player / engine 置空，之后引擎的钩子轮次不会再调用它
	p0.role = null
	if p0.tap:
		p0.tap = false
	p0.xue_qiang_wei = false
	p0.sheng_huang_side = 0
	p0.reattacker = -1
	p0.clear_additional_action()
	p0.reset_action_counts()
	p0.boot_skill_used = false
	if 重置上限:
		p0.重置手牌上限状态()
		p0.energy_max = GConst.ENERGY_MAX
		p0.cross_max = GConst.CROSS_MAX
	p0.cover_cards_max = 0
	p0.tokens[0] = null
	p0.tokens[1] = null
	p0.tokens[2] = null
	p0.role_id = 新角色id
	var 新角色: BattleRole = BattleRole.create(新角色id, p0, self)
	p0.role = 新角色
	if 新角色 == null:
		# 没有脚本的角色（白板）也按角色表初始化指示物 / 盖牌上限（与开局同口径）
		p0.按表初始化指示物()
	# 同名指示物把数值带过去（新角色表里没有这个名字的槽位就保持 0）
	for 槽: int in [0, 1]:
		var 新定义: Dictionary = p0.token_def(槽)
		if 新定义.is_empty():
			continue
		for 旧: Dictionary in 旧指示物:
			if str(旧["name"]) == str(新定义.get("name", "")):
				新定义["num"] = clampi(int(旧["num"]), 0, int(新定义.get("max", 0)))
				break
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Notice,
		"txt": "[%s] 的角色卡替换为【%s】" % [旧角色名, Data.role_name(新角色id)],
		"id": pid,
	})
	_broadcast_game()
	return GConst.GE_SUCCESS


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
		_check_cover_change()
		_check_卡牌属性()
		_check_energy_change()
		if idx >= _states.size():
			break
		if _states[idx] == st:
			# 结束的状态不该还挂着没取走的回复：这几乎都是「钩子顶部的入口守卫在重入时
			# 提前 return」造成的静默失败（付完代价后资源刚好用光之类）。清掉并告警，
			# 让它在调试期就暴露，而不是变成「界面收了这一问、服务端什么都没做」。
			_清理状态遗留回复(st)
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
## 「本次结算结束前不会爆牌」的玩家（异教徒【放逐】9505「无视你的手牌上限摸 6-8 张」）。
## 不是临时改手牌上限，而是一个状态：处于其中时超限检查一律跳过；
## 由技能在结算完成时显式解除（见 解除不爆牌）。
var _不爆牌: Dictionary = {}


## 让 pid 进入「不爆牌」状态（手牌可以超过上限，不结算超限）
func 进入不爆牌(pid: int) -> void:
	_不爆牌[pid] = true


## 解除「不爆牌」状态（之后超过上限会照常结算超限）
func 解除不爆牌(pid: int) -> void:
	_不爆牌.erase(pid)


func _check_hand_overflow() -> void:
	for st: Variant in _states:
		if st is SHandOverflow:
			return
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null or pp.hand_cards.size() <= pp.hand_cards_max:
			continue
		if bool(_不爆牌.get(pid, false)):
			continue
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
			(st as SHandOverflow).补充伤害上下文(
				int(harm.get("cause", 0)), int(harm.get("type", GConst.HarmType.None)),
				bool(harm.get("no_morale", false)))
			return
	push(SHandOverflow.new(int(harm.get("cause", 0)), int(harm.get("type", GConst.HarmType.None)),
		bool(harm.get("no_morale", false))))


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


## 每个状态跑完后对比各玩家**盖牌张数**：有变化就往战斗日志写一条（和指示物同一类、同一格式）。
## 盖牌不计在 tokens 里（槽 2 只存上限），所以 _check_token_change 抓不到它，这里单独比。
func _check_cover_change() -> void:
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null:
			continue
		var 现在: int = pp.cover_cards.size()
		if not _cover_counts.has(pid):
			_cover_counts[pid] = 现在
			continue
		var 上次: int = int(_cover_counts[pid])
		if 上次 == 现在:
			continue
		_cover_counts[pid] = 现在
		var 名: String = str(Data.role_token_def(pp.role_id, 2).get("name", "盖牌"))
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Token,
			"txt": "%s 的【%s】%d→%d" % [_称号(pp), 名, 上次, 现在],
			"id": pp.id,
		})


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


## 手牌数量 / 上限变化日志（GossipType.Hand，客户端把这一类也归到 [卡牌] 标签下）
func _播手牌日志(pp: BattlePlayer, 文案: String) -> void:
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Hand,
		"txt": 文案,
		"id": pp.id,
	})


## 清除一名玩家身上的【神威】禁疗标记；写日志由调用方决定。
## 圣殿骑士自己的回合结束时由角色清除双方；round 过期只是兜底。
func 清除神威禁疗(pid: int, 写日志: bool = true) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null or p0.no_heal_round < 0:
		return false
	p0.no_heal_round = -1
	if 写日志:
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Heal,
			"txt": "%s 可以正常获得治疗" % _称号(p0),
			"id": pid,
			"num": 0,
		})
	return true


## 【神威】的「本回合无法获得治疗」按 round_id 自动过期（兜底）：
## 正常路径由圣殿骑士 p_turn_end 在圣殿骑士回合结束时清除双方。
func _检查神威过期(旧回合: int) -> void:
	var 有过期: bool = false
	for pid: int in order:
		var p0: BattlePlayer = players.get(pid)
		if p0 == null or p0.no_heal_round != 旧回合:
			continue
		if 清除神威禁疗(pid):
			有过期 = true
	if 有过期:
		_broadcast_game()


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
		var 增益: Array[Dictionary] = []
		for i: int in range(mini(上次.size(), 现在.size())):
			if int(上次[i]) == 现在[i]:
				continue
			var 槽: Variant = pp.tokens[i]
			var 名: String = str((槽 as Dictionary).get("name", "指示物")) if 槽 is Dictionary else "指示物"
			片段.append("【%s】%d→%d" % [名, int(上次[i]), 现在[i]])
			var 差: int = 现在[i] - int(上次[i])
			if 差 > 0:
				增益.append({"num": 差, "name": 名, "slot": i})
		if not 片段.is_empty():
			broadcast(GConst.Msg.Gossip, {
				"type": GConst.GossipType.Token,
				"txt": "%s 的%s" % [_称号(pp), "、".join(片段)],
				"id": pp.id,
			})
		# 指示物增加：给客户端一条不带日志的资源获得事件（治疗走 Heal 类）
		for 项: Dictionary in 增益:
			broadcast(GConst.Msg.Gossip, {
				"type": GConst.GossipType.Token,
				"txt": "",
				"id": pp.id,
				"res_num": int(项["num"]),
				"res_name": str(项["name"]),
				"res_slot": int(项["slot"]),
			})
		_token_counts[pid] = 现在


## 每个状态跑完后对比各玩家与各阵营战绩区的星石：获得和移除都写一条。
## 个人写「谁获得/移除 x 宝石 x 水晶」；战绩区写「哪一队战绩区获得/移除 x 宝石 x 水晶」。
## 同一次增减里两类都有时由 _星石片段 分开拼「获得 …、移除 …」
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
			_播星石日志("%s %s" % [_称号(pp), 个人片段], pp.id)
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
			_播星石日志("%s 战绩区%s" % [_阵营名(color), 队伍片段], -1)
		_team_energies[color] = 队伍现在


## 星石增减的文案片段（个人与战绩区共用）：
## 正数写「获得 …」，负数写「移除 …」；两类都有就拼成「获得 …、移除 …」。
## 没有变化返回空串，调用方据此不写日志。
func _星石片段(宝石增量: int, 水晶增量: int) -> String:
	var 获得: Array[String] = []
	var 移除: Array[String] = []
	if 宝石增量 > 0:
		获得.append("%d 宝石" % 宝石增量)
	elif 宝石增量 < 0:
		移除.append("%d 宝石" % -宝石增量)
	if 水晶增量 > 0:
		获得.append("%d 水晶" % 水晶增量)
	elif 水晶增量 < 0:
		移除.append("%d 水晶" % -水晶增量)
	var 段: Array[String] = []
	if not 获得.is_empty():
		段.append("获得 " + "、".join(获得))
	if not 移除.is_empty():
		段.append("移除 " + "、".join(移除))
	return "、".join(段)


## 阵营名（战绩区日志用）
func _阵营名(color: int) -> String:
	return "红队" if color == GConst.RED else "蓝队"


## 星石增减日志：个人与战绩区共用，类别 [星石]（提炼、购买、合成等增减都走这里）
func _播星石日志(文案: String, 相关玩家: int) -> void:
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Gem,
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
	# 「本回合无法获得治疗」（圣殿骑士【神威】）：整笔作废。
	# 状态获得 / 结束时已经在【神威】那里逐人播报过，这里不再重复写同一句。
	if pp.无法获得治疗():
		return
	# 角色自身「始终无法获得治疗」（染污者【神弃之裔】）：同样整笔作废
	if pp.role != null and pp.role.禁止获得治疗():
		return
	var 前: int = pp.cross_num
	pp.add_cross_num(amount)
	_统计治疗(src_id, pid, amount)
	_播治疗日志(pp, amount, src_id, 前)
	_治疗溢出后(pp, 前, amount, src_id)
	_治疗增加后(pp, 前, amount, src_id)


## 治疗数**真正增加**后压一轮 p_heal_gained 钩子（铸律者【神律封锁】「每次你的治疗数增加时」）。
## 只在加进上限里、确实变多时才触发；加满再加、被禁疗而作废的都不算。
func _治疗增加后(pp: BattlePlayer, 前: int, amount: int, src_id: int) -> void:
	if pp == null or pp.cross_num <= 前:
		return
	if not _running or phase != Phase.Playing:
		return
	push(SHook.new("p_heal_gained", {
		"player": pp.id, "before": 前, "after": pp.cross_num, "amount": amount, "src": src_id,
	}, []))


## 治疗溢出（F3）：本次加到上限之后仍有剩余 → 压一次 p_heal_overflow 钩子，让角色自己响应
## （圣庭检察士【裁决论定】/ 圣殿骑士【神选者】）。钩子可以等待玩家输入，所以走状态栈，
## 只在真正对局推进中压（setup / 终局收尾时不压，避免非对局态多出一段流程）。
func _治疗溢出后(pp: BattlePlayer, 前: int, amount: int, src_id: int) -> void:
	if pp == null:
		return
	var 溢出: int = 前 + amount - pp.cross_max
	if 溢出 <= 0:
		return
	if not _running or phase != Phase.Playing:
		return
	push(SHook.new("p_heal_overflow", {
		"player": pp.id, "overflow": 溢出, "before": 前, "amount": amount, "src": src_id,
	}, []))


## 施加治疗（无视目标治疗上限）：封顶 > 0 时治疗后不超过它（<= 0 表示不额外封顶），
## 目标本来更高时保持不动（只加不减）。用于【神圣契约】这类「突破上限」的转移。
func add_cross_pierce(pid: int, amount: int, src_id: int, 封顶: int) -> void:
	if amount <= 0:
		return
	var pp: BattlePlayer = players.get(pid)
	if pp == null:
		return
	if pp.无法获得治疗():
		# 获得【神威】时已按双方各播报一条，这里不重复
		return
	# 「始终无法获得治疗」（染污者【神弃之裔】）：突破上限也拿不到
	if pp.role != null and pp.role.禁止获得治疗():
		return
	var 前: int = pp.cross_num
	var 新: int = 前 + amount
	if 封顶 > 0:
		新 = mini(新, 封顶)
	pp.cross_num = maxi(新, 前)
	_统计治疗(src_id, pid, amount)
	_播治疗日志(pp, amount, src_id, 前)
	_治疗增加后(pp, 前, amount, src_id)


## 治疗日志（按「输出量」记，与是否被上限截断无关）。
## 拆成两行：谁给了谁几点；以及这名角色自己的治疗变化。
func _播治疗日志(pp: BattlePlayer, amount: int, src_id: int, 前: int) -> void:
	var 来源: String = "自身" if src_id == pp.id else _称号(players.get(src_id))
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Heal,
		"txt": "%s 获得 %s 的 %d 点治疗" % [_称号(pp), 来源, amount],
		"id": pp.id,
		# 点数单独给一份：客户端据此决定头像上冒几个「+」，不必去解析日志文案。
		# 只挂在第一行，第二行不带 num，避免同一个「+」播两遍。
		"num": amount,
	})
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Heal,
		"txt": "%s 的治疗 %d→%d" % [_称号(pp), 前, pp.cross_num],
		"id": pp.id,
	})


## 战斗日志里的卡名：名字·系别·命格（如「虚弱·暗·血」），与客户端 _牌日志名 同口径。
## 系别写在中间：法术牌光看名字分不出地 / 水 / 风 / 火 / 雷 / 暗
func _牌日志名(牌: GCard) -> String:
	if 牌 == null:
		return "?"
	var 部件: Array[String] = [牌.card_name]
	var 系别: String = GConst.element_to_chinese(牌.element_enum())
	if not 系别.is_empty() and 系别 != "?":
		部件.append(系别)
	if not 牌.fate_pattern.is_empty():
		部件.append(牌.fate_pattern)
	return "·".join(部件)


## 获得牌日志：某张已公开的牌加入某人手牌时写一条「谁 获得【什么】」。
## 只用于牌面已经公开的场合（如【剑守誓言】从牌库顶展示后选牌），不要拿它公开暗牌。
func 播获得牌日志(pid: int, cards: Array) -> void:
	var pp: BattlePlayer = players.get(pid)
	if pp == null or cards.is_empty():
		return
	var 名表: Array[String] = []
	for c: Variant in cards:
		var 牌: GCard = Data.get_card(int(c))
		名表.append("【%s】" % (_牌日志名(牌) if 牌 != null else str(int(c))))
	_播手牌日志(pp, "%s 获得 %s" % [_称号(pp), "、".join(名表)])
	_获得牌已播[pid] = true


## 交牌日志（不公开亮牌的「把牌交给别人」用）：交牌双方在日志里看到具体牌名，
## 其他人只看到张数 —— 所以按人分别下发，而不是一条广播。
func _log_give_cards(src_id: int, dst_id: int, cards: Array) -> void:
	if cards.is_empty():
		return
	var 名表: Array[String] = []
	for c: Variant in cards:
		var 牌: GCard = Data.get_card(int(c))
		名表.append("【%s】" % (_牌日志名(牌) if 牌 != null else str(int(c))))
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
	# 这次等待会顶掉等待槽。如果槽里躺着一份「已经收到、还没被取走」的回复
	# （等待期间被压到栈上的状态要先问别人），先按它的归属状态暂存起来，
	# 等那个状态回到栈顶时由 has_reply / take_reply 恢复 —— 否则这份回复就被冲掉了。
	# 同一个状态自己重问（_await_state == _当前状态）时是作废重问，不暂存。
	if _has_reply and _await_state != null and _await_state != _当前状态:
		_挂起回复[_await_state] = {"reply": _reply, "kind": _await_kind}
	_await_id = pid
	_await_kind = kind
	# 新的一次等待：序号 +1（客户端据此只在真的换等待时弹提示）
	wait_seq += 1
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


## 当前状态回到栈顶时，把它那份被暂存的回复放回等待槽（只放一次）。
## 只认「等待归属的那个状态」：别的状态（等待期间被补压到栈上的）取不到这份回复。
func _恢复挂起回复() -> void:
	if _当前状态 == null or not _挂起回复.has(_当前状态):
		return
	if _await_state != _当前状态 and (_await_id >= 0 or _has_reply):
		# 等待槽被别的状态占着（还没答复 / 已答复但还没取走）：不能顶掉，等它自己取走之后再来
		return
	var 箱: Dictionary = _挂起回复[_当前状态]
	_挂起回复.erase(_当前状态)
	_reply = 箱.get("reply", {})
	_has_reply = true
	_await_id = -1
	_await_kind = int(箱.get("kind", -1))
	_await_state = _当前状态
	wait_deadline_ms = 0
	wait_total_ms = 0


## 当前状态是否已经收到回复。会先把它「插队期间按归属暂存」的那份恢复回等待槽再判断，
## 所以等待期间被压到栈上的状态先问了别人，也不会把这一份冲掉。
func has_reply() -> bool:
	_恢复挂起回复()
	return _has_reply and _当前状态 == _await_state


## 取走当前状态的回复（同样会先恢复插队期间暂存的回复）。不是等待归属者取不到。
func take_reply() -> Dictionary:
	_恢复挂起回复()
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
	# 同一状态若还挂着更早的一份（作废的回复），一并清掉
	_挂起回复.erase(_当前状态)
	return r


## 客户端攒操作：角色把「下一次应战询问」的答复先放这里，轮到该询问时直接取用
func prepare_reply(pid: int, r: Dictionary) -> void:
	_prepared_replies[pid] = r


func take_prepared_reply(pid: int) -> Dictionary:
	var r: Dictionary = _prepared_replies.get(pid, {})
	_prepared_replies.erase(pid)
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
	_挂起回复.clear()
	_prepared_replies.clear()
	_pending_partial = {}
	wait_deadline_ms = 0
	wait_total_ms = 0
	链截止_ms = 0
	链总时长_ms = 0
	# 中止流程时一并清掉「弃牌前拦截」标记，免得残留成 true 让之后的弃牌永远走同步分支
	_弃牌拦截中 = false
	# 中止时也不要残留行动聚合器的流程标记，否则角色自己的 p_after_attack 会被跳过


## 一个状态结束（出栈）时，把它还没被取走的回复清掉并告警。
## 正常流程里状态要么 WAIT 等下一次，要么先 take_reply 再结束；带着回复结束说明
## 角色在重入时被入口守卫挡住了（如「发动后能量为 0」这种付款后状态），回复就没人要了。
func _清理状态遗留回复(st: Variant) -> void:
	if st == null:
		return
	var 有挂起: bool = _挂起回复.has(st)
	if 有挂起:
		_挂起回复.erase(st)
	var 有活回复: bool = _has_reply and _await_state == st
	if 有活回复:
		_has_reply = false
		_reply = {}
		_await_id = -1
		_await_state = null
		wait_deadline_ms = 0
		wait_total_ms = 0
	if (有挂起 or 有活回复) and OS.is_debug_build():
		var 名: String = str(st)
		if st.get("hook") != null:
			名 = "SHook(%s)" % str(st.get("hook"))
		print("[引擎] %s 结束时还挂着一份没取走的回复：入口守卫多半在重入时提前 return 了" % 名)


func on_message(pid: int, kind: int, data: Dictionary) -> void:
	if _await_id != pid or kind != _await_kind:
		return
	# 处理这次行动 / 应答之前，先按「持有者」同步一次卡牌系别属性：
	# 调试发牌、刚交给她的牌可能还没等到状态边界，规则这边要立刻读到正确系别
	_check_卡牌属性()
	# 攻击结束响应里的「额外攻击行动」快捷按钮：放弃剩余响应，下一次直接进入所选额外攻击
	if kind == GConst.Msg.Respond \
			and int(data.get("respond_id", 0)) == GConst.RespondType.ChooseExtraAction:
		if _当前状态 is S行动聚合器:
			var 快参: Array = data.get("args", [])
			var 快ID: int = int(快参[0]) if not 快参.is_empty() else 0
			var 快牌表: Array = data.get("card_ids", [])
			var 快目标表: Array = data.get("dst_ids", [])
			var 快牌: int = int(快牌表[0]) if not 快牌表.is_empty() \
				else (int(快参[1]) if 快参.size() > 1 else 0)
			var 快目标: int = int(快目标表[0]) if not 快目标表.is_empty() \
				else (int(快参[2]) if 快参.size() > 2 else 0)
			var 快者: BattlePlayer = players.get(pid)
			# 按唯一 ID 认人（同一技能可以同时挂两份攻击行动）；拿到 cause 时退回按 cause 找
			var 快行动: Dictionary = {}
			if 快者 != null:
				快行动 = 快者.额外行动按ID(快ID)
				if 快行动.is_empty():
					快行动 = 快者.额外行动数据(快ID)
			var 快uid: int = int(快行动.get("uid", 0))
			var 快因: int = int(快行动.get("cause", 0))
			var 快卡: GCard = Data.get_card(快牌)
			var 原额外2: bool = 行动额外
			var 原来源2: int = 行动额外来源
			行动额外 = true
			行动额外来源 = 快因
			var 快通过: bool = 快者 != null and not 快行动.is_empty() and 快卡 != null \
				and 快卡.is_attack() and 快者.has_hand_card(快牌) \
				and 快者.v_attack(快牌, 快目标, players) == GConst.GE_SUCCESS \
				and 校验额外行动限制(快者, 快行动, GConst.ActionType.Attack,
					[快牌], [快目标]) == GConst.GE_SUCCESS
			行动额外 = 原额外2
			行动额外来源 = 原来源2
			if not 快通过:
				if OS.is_debug_build():
					print("[额外行动排查] 快捷攻击被拒(聚合器)：id=%d cause=%d 牌=%d 目标=%d 卡=%s 攻击=%s 在手=%s v_attack=%d 限制=%d 在队列=%s 规格=%s" % [
						快ID, 快因, 快牌, 快目标, str(快卡 != null),
						str(快卡 != null and 快卡.is_attack()),
						str(快者 != null and 快者.has_hand_card(快牌)),
						快者.v_attack(快牌, 快目标, players) if 快者 != null else -1,
						校验额外行动限制(快者, 快行动, GConst.ActionType.Attack,
							[快牌], [快目标]) if 快者 != null else -1,
						str(额外行动在队列ID(快者, 快uid)), str(快行动)])
				send(pid, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
				return
			首选额外行动 = 快uid
			首选额外行动卡 = 快牌
			首选额外行动目标 = 快目标
			_快捷提前收尾 = true
			_reply = {"args": [快uid], "card_ids": [快牌], "dst_ids": [快目标]}
			_has_reply = true
			_await_id = -1
			_await_state = null
			run()
			return
		_选择额外攻击响应(pid, data)
		return
	# 行动结束响应里点了「取消」：响应界面已经替玩家做过选择，后面不再问额外攻击行动
	var 取消应答: bool = (data.get("args", []) as Array).is_empty() \
		and (data.get("card_ids", []) as Array).is_empty() \
		and (data.get("dst_ids", []) as Array).is_empty()
	var 可取消额外: bool = _当前状态 is S行动聚合器
	if not 可取消额外 and _最后询问.has(pid):
		var 当前命令: Array = _最后询问[pid].get("commands", [])
		if not 当前命令.is_empty():
			可取消额外 = bool((当前命令[0] as Dictionary).get("has_extra_options", false))
	if 取消应答 and 可取消额外:
		_处理行动结束取消(pid)
	# 分步应答（如【剑气斩】先在弹窗选好「移除几点剑气」）：只记下这一步，不算本次询问的最终回复，
	# 继续等玩家选目标 / 目标超时兜底时再拿它用
	if bool(data.get("partial", false)):
		_pending_partial = data
		return
	_reply = data
	_has_reply = true
	_await_id = -1
	# 这次询问已经答复完：取消标记不能遗留到后面的应战 / 其它 Respond 询问上

	wait_deadline_ms = 0
	wait_total_ms = 0
	# 等待已结束：先广播一次，客户端会收起等待进度条；随后 run() 若又进入等待会再广播
	_broadcast_game()
	run()


## 一份额外行动现在还在不在队列里（授予它的技能若不再可用，会自己撤回它，见 BattlePlayer.撤回额外行动）。
## 行动本身是通用工具：能不能出牌 / 打谁只看它自带的规格，不再回头问来源技能。
func 额外行动在队列(cur: BattlePlayer, cause: int) -> bool:
	if cur == null:
		return false
	for a: Dictionary in cur.additional_actions:
		if int(a.get("cause", 0)) == cause:
			return true
	return false


## 按唯一 ID 判断这份行动还在不在队列里：同一技能挂了两份时只能靠 ID 认人。
func 额外行动在队列ID(cur: BattlePlayer, uid: int) -> bool:
	if cur == null or uid <= 0:
		return false
	return cur.额外行动下标按ID(uid) >= 0


## 取某份额外行动的数据：正在行动的这份或队列里的那份（同一份数据，含技能写好的规格）。
func _额外行动数据(cur: BattlePlayer, cause: int) -> Dictionary:
	if cur != null:
		return cur.额外行动数据(cause)
	if not 当前额外行动数据.is_empty() and int(当前额外行动数据.get("cause", 0)) == cause:
		return 当前额外行动数据
	return {}


## 一份额外行动能不能被切换：看行动自带规格（默认可以），与来源技能无关。
func 额外行动可切换(_cur: BattlePlayer, 行动: Dictionary) -> bool:
	return bool(行动.get("switchable", true))


## 行动结束响应点取消＝本回合不再使用任何额外攻击行动：
## 清掉队列里所有能执行攻击的额外行动，并阻止之后再由角色补进队列。
## 例外：已经由基础效果（迅捷赐福）确认、标了 direct 的那一份要保留 ——
## 它是玩家取消之后又主动选的，必须能真正进入（见 方案A / _处理行动结束取消）。
func _清除额外攻击行动(pid: int) -> void:
	var cur: BattlePlayer = players.get(pid)
	if cur == null:
		return
	var 保留: Array = []
	for a: Dictionary in cur.additional_actions:
		var cause: int = int(a.get("cause", 0))
		if GConst.基础效果额外行动.has(cause) and bool(a.get("direct", false)):
			保留.append(a)
			continue
		if GConst.放行动作(GConst.ActionType.Attack, int(a.get("allow_action", 0))):
			continue
		保留.append(a)
	cur.additional_actions.assign(保留)


## 行动结束响应被取消：只结束这一次响应，不再清空 / 跳过任何额外行动。
## 已获得的额外行动全部保留，响应结束后由额外行动阶段（SAdditionalAction）逐个选择使用 / 放弃。
## 保留这个入口是为了让上层（on_message 的取消识别）有一个统一落点，并记录语义。
## 注意：还没确认的「响应选项」由 S行动聚合器 在出栈时撤回（见 _撤回未确认额外行动）。
func _处理行动结束取消(_pid: int) -> void:
	# 新规则下取消响应与额外行动无关：这里刻意什么都不做。
	pass


## 撤回「本次行动结束响应里摆出来、但玩家没确认」的额外行动选项。
## 这类行动是技能在 p_after_* 里以 in_end_response＝true、direct＝false 预先入队的，
## 只作为响应询问里的选项存在（如女武神【神圣追击】、剑帝【不屈意志】）；
## 玩家确认时 resolve_queued_extra_action 才会把它标成 direct 并结算代价。
## 基础效果授予的行动（祈祷师【迅捷赐福】等）同理：它是被提前垫进队列的「占位」，
## 玩家在响应里确认时 _确认基础效果额外行动 才把它换成 direct 的真行动；没确认就结束响应，
## 占位也要一并撤回，否则额外行动阶段会冒出一颗玩家从没确认过的红色「迅捷赐福」按钮。
## 响应结束时仍没确认的（取消 / 超时 / 点了红色额外攻击提前收尾）都必须撤回。
func _撤回未确认额外行动(pid: int) -> void:
	var cur: BattlePlayer = players.get(pid)
	if cur == null or cur.additional_actions.is_empty():
		return
	var 保留: Array = []
	for a: Dictionary in cur.additional_actions:
		if not bool(a.get("direct", false)):
			var cause: int = int(a.get("cause", 0))
			# ① 响应选项占位（in_end_response）；② 基础效果授予的行动占位（迅捷赐福 1601 等）。
			# 确认过的基础效果行动会被换成 direct 的真行动，不会走到这里。
			if bool(a.get("in_end_response", false)) or GConst.基础效果额外行动.has(cause):
				continue
		保留.append(a)
	if 保留.size() == cur.additional_actions.size():
		return
	cur.additional_actions.assign(保留)
	_broadcast_game()


## 确认基础效果授予的额外行动（迅捷赐福等）：
## 按配置表取出 allow_action，把行动加进队列并标 direct，同时移除对应的赐福牌。
## 「获取序号」＝这份额外行动真正进入队列的时刻，而不是赐福牌贴在身上的时刻：
## 赐福可能在前几个回合就贴上了，若沿用贴牌时的序号，它授予的行动会被排到之后获得的行动前面
## （行动结束响应的快捷按钮、额外行动阶段的技能栏都按这个序号排列）。
func _确认基础效果额外行动(pid: int, cause: int) -> void:
	var cur: BattlePlayer = players.get(pid)
	var 配置: Dictionary = GConst.基础效果额外行动.get(cause, {})
	if cur == null or 配置.is_empty():
		return
	var 允许: int = int(配置.get("allow_action", GConst.ActionType.Attack))
	var 数据: Dictionary = {}
	for i: int in range(cur.additional_actions.size()):
		if int(cur.additional_actions[i].get("cause", 0)) == cause:
			数据 = cur.additional_actions[i].duplicate()
			cur.additional_actions.remove_at(i)
			break
	if 数据.is_empty():
		# 这份行动此刻才获得：add_action 取一个新序号，队列顺序＝获取顺序。
		cur.add_action(允许, cause, true, true, {"in_end_response": true})
		for a: Dictionary in cur.additional_actions:
			if int(a.get("cause", 0)) == cause:
				数据 = a
				break
	else:
		# 攻击结束钩子前半段已经由赐福转发补进队列（如祈祷师）：确认那一刻**重新取号** ——
		# 「获取时刻」是玩家确认使用的时刻，不是转发提前入队的时刻。提前入队发生在演员顺序里，
		# 可能比同一回合自动获得的额外行动（如魔剑士【修罗连斩】）还早，沿用旧序号就会让
		# 「我确认的迅捷赐福」排在「自动获得的修罗连斩」前面，看着像没按顺序排。
		数据["direct"] = true
		数据["skip_notice"] = true
		数据["in_end_response"] = true
		数据["order"] = cur.额外行动新序号()
		if not 数据.has("uid"):
			数据["uid"] = cur.额外行动新ID()
		cur.additional_actions.append(数据)
		# 重新入队后按获取序号排回去（数组顺序必须始终等于获取顺序）
		cur.额外行动排序()
	# 移除对应的基础效果牌并弃置
	for be: Dictionary in cur.basic_effects:
		var 牌id: int = int(be.get("card", -1))
		var 牌: GCard = Data.get_card(牌id)
		if 牌 != null and 牌.has_skill_id(cause):
			remove_basic_effect(pid, 牌id, cause, int(be.get("src", pid)))
			to_discard([牌id])
			_broadcast_game()
			break


## 进入基础效果授予的额外行动时补齐一次性代价：移除并弃置对应的赐福牌。
## 响应里点选确认（_确认基础效果额外行动）时已经移除过的，这里看到牌不在了就只补确认标记；
## 响应里没点、取消后直接进额外行动阶段使用的那份，由这里统一移除，避免借用赐福的角色漏掉。
func _支付基础效果额外行动(pid: int, cause: int) -> void:
	var cur: BattlePlayer = players.get(pid)
	if cur == null or 基础效果额外行动已确认(cause):
		return
	for be: Dictionary in cur.basic_effects:
		var 牌id: int = int(be.get("card", -1))
		var 牌: GCard = Data.get_card(牌id)
		if 牌 != null and 牌.has_skill_id(cause):
			remove_basic_effect(pid, 牌id, cause, int(be.get("src", pid)))
			to_discard([牌id])
			break
	_基础效果额外行动已确认[cause] = true
	_broadcast_game()


## 额外行动的**唯一排序入口**：队列（按获取序号）＋可选的「当前正在行动的那份」。
## 数组顺序就是任何界面看到的顺序——行动结束响应里的快捷按钮、额外行动阶段的技能栏、
## 额外行动选择框都按它渲染，客户端不排序、不重排。要改排列方式只改这里。
func 额外行动序列(pid: int, 含当前: bool = false) -> Array:
	var cur: BattlePlayer = players.get(pid)
	var 原表: Array = []
	if cur != null:
		原表 = cur.additional_actions.duplicate()
	if 含当前 and not 当前额外行动数据.is_empty() \
			and int(当前额外行动数据.get("cause", 0)) > 0:
		原表.append(当前额外行动数据)
	原表.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 0)) < int(b.get("order", 0)))
	var 序列: Array = []
	for a: Dictionary in 原表:
		# 兜底：手工塞进队列、没走过 add_action 的行动也补一个唯一 ID（老数据 / 脚本自测）
		if int(a.get("uid", 0)) <= 0 and cur != null and not bool(a.get("current", false)):
			a["uid"] = cur.额外行动新ID()
		序列.append({
			"uid": int(a.get("uid", 0)),
			"cause": int(a.get("cause", 0)),
			"allow_action": int(a.get("allow_action", 0)),
			"cards": a.get("cards", []),
			"targets": a.get("targets", []),
			"element": int(a.get("element", 0)),
			# 命格限制也要带给客户端：只按命格限制的行动不下发牌号名单，客户端靠它比对牌面
			"card_fate": int(a.get("card_fate", 0)),
			"direct": bool(a.get("direct", false)),
			"switchable": bool(a.get("switchable", true)),
			"in_end_response": bool(a.get("in_end_response", false)),
			"current": 含当前 and a == 当前额外行动数据,
		})
	return 序列


## 攻击结束响应里的快速攻击按钮只认「已确认、可直接出手的攻击额外行动」：
## 排除未确认的基础效果、非 direct 的响应型行动。
func _可快捷攻击(项: Dictionary) -> bool:
	if not GConst.放行动作(GConst.ActionType.Attack, int(项.get("allow_action", 0))):
		return false
	var c: int = int(项.get("cause", 0))
	if GConst.基础效果额外行动.has(c) and not 基础效果额外行动已确认(c):
		return false
	if not bool(项.get("direct", false)) and bool(项.get("in_end_response", false)):
		return false
	return true


## 攻击结束响应里点了「额外攻击行动」快捷按钮：记录首选，跳过当前响应钩子剩余角色，
## 让本轮行动收尾后由 SAdditionalAction 直接进入该额外攻击。
func _选择额外攻击响应(pid: int, data: Dictionary) -> void:
	if _await_id != pid or _await_kind != GConst.Msg.Respond:
		return
	var 钩: SHook = null
	for i: int in range(_states.size() - 1, -1, -1):
		if _states[i] is SHook:
			var 候选: SHook = _states[i] as SHook
			if 候选.hook == "p_after_attack" or 候选.hook == "p_after_magic":
				钩 = 候选
				break
	# 聚合器发问时，p_after_magic / p_after_attack 那个 SHook 可能已经执行完出栈了；
	# 这时不能因为找不到钩子就判无效，仍要记录首选额外行动，让聚合器跳过剩余选项。
	var args: Array = data.get("args", [])
	var 选中ID: int = int(args[0]) if not args.is_empty() else 0
	var cur: BattlePlayer = players.get(pid)
	if cur == null or 选中ID <= 0:
		send(pid, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
		return
	# 按唯一 ID 认人（同一技能挂了两份行动时必须能分开）；万一拿到的是 cause 就退回按 cause 找
	var 选中行动: Dictionary = cur.额外行动按ID(选中ID)
	if 选中行动.is_empty():
		选中行动 = cur.额外行动数据(选中ID)
	if 选中行动.is_empty() \
			or not GConst.放行动作(GConst.ActionType.Attack, int(选中行动.get("allow_action", 0))):
		send(pid, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
		return
	var uid: int = int(选中行动.get("uid", 0))
	var cause: int = int(选中行动.get("cause", 0))
	var 牌表: Array = data.get("card_ids", [])
	var 目标表: Array = data.get("dst_ids", [])
	var 攻击牌: int = int(牌表[0]) if not 牌表.is_empty() \
		else (int(args[1]) if args.size() > 1 else -1)
	var 攻击目标: int = int(目标表[0]) if not 目标表.is_empty() \
		else (int(args[2]) if args.size() > 2 else -1)
	# 校验不过时不要先清等待退出响应；保留当前响应让客户端恢复选项，玩家可以重选牌/目标。
	# 0 号牌 / 0 号座位都是合法值（卡表有 #0、座位从 0 开始），缺失用 -1。
	if 攻击牌 < 0 or 攻击目标 < 0:
		send(pid, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
		return
	var 卡: GCard = Data.get_card(攻击牌)
	var 原额外: bool = 行动额外
	var 原来源: int = 行动额外来源
	# 校验必须按「选中的这份额外行动」算，不能按当前正在行动的那份算。
	行动额外 = true
	行动额外来源 = cause
	var 校验通过: bool = 卡 != null and 卡.is_attack() and cur.has_hand_card(攻击牌) \
		and cur.v_attack(攻击牌, 攻击目标, players) == GConst.GE_SUCCESS \
		and 校验额外行动限制(cur, 选中行动, GConst.ActionType.Attack,
			[攻击牌], [攻击目标]) == GConst.GE_SUCCESS
	行动额外 = 原额外
	行动额外来源 = 原来源
	# v_* 只做校验：校验完这份行动必须仍然在队列里。
	# 角色若在校验里撤了自己的单（撤回额外行动），这里就会对不上——
	# 那种情况下直接驳回并保留响应界面（客户端 on_invalid_input 会恢复），
	# 不能悄悄改成进入队列里的另一份额外行动（玩家点的是这一份）。
	if not 校验通过 or not 额外行动在队列ID(cur, uid):
		send(pid, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
		return
	首选额外行动 = uid
	首选额外行动卡 = 攻击牌
	首选额外行动目标 = 攻击目标
	_await_id = -1
	_has_reply = false
	wait_deadline_ms = 0
	wait_total_ms = 0
	if 钩 != null:
		钩._iter = order.size()
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


## 本次对局的士气上限：当前只支持 4 / 6 人局，固定 15。开局定下来后就照它算，
## 角色脚本（如剑帝【天使之魂】）也读这里，别在别处再写死一个数字
func 士气上限() -> int:
	return GConst.MORALE_DEFAULT


# ============================================================
# 额外回合（F7 / 10803）
# ============================================================
## 安排一个额外回合：当前回合照常结束后，由 pid 立即开始一个完整的「额外回合」——
## 不推进 current_id 到下家、不增加 round_id，回合开始钩子 / 中毒虚弱 / 行动计数重置等
## 全部照常走（见 SNextPlayer → SCheckTurnStart）。
## 攻击加伤：该额外回合里 pid 的普通攻击 / 应战反击伤害 +N（见 攻击基础伤害）；
## 由引擎统一加，不依赖角色对象，所以「先安排额外回合、再替换角色」也不会丢。
## 来源：只用于快照 / 日志（如 10803），不参与结算。重复调用时以最后一次为准。
## 只能在引擎推进中调用；当前回合的额外行动会先结算完，再进额外回合。
func 安排额外回合(pid: int, 攻击加伤: int = 0, 来源: int = 0) -> int:
	if players.get(pid) == null:
		return GConst.GE_INVALID_PLAYERID
	# 续位＝「当作没有这次额外回合时本来会轮到的人」：安排时 current_id 还是刚结束 / 正在行动的人。
	# 一条链只取第一次，判断依据是「现在有没有正在执行的额外回合、有没有已排好还没执行的」——
	# 不用「续位 < 0」判断：状态被外部重置（调试指令 / 测试用例）时续位可能残留，会续到上一次的位置。
	if 当前额外回合玩家 < 0 and 额外回合玩家 < 0:
		额外回合续位 = next_id(current_id)
	额外回合玩家 = pid
	额外回合攻击加伤 = maxi(攻击加伤, 0)
	额外回合来源 = 来源
	return GConst.GE_SUCCESS


## 当前正在执行的是不是额外回合
func 是否额外回合() -> bool:
	return 当前额外回合玩家 >= 0


## 本次额外回合里 pid 的攻击加伤（不是该玩家的额外回合时为 0）
func 额外回合加伤(pid: int) -> int:
	if 当前额外回合玩家 < 0 or 当前额外回合玩家 != pid:
		return 0
	return 当前额外回合攻击加伤


## 某玩家现在一次普通攻击的基础伤害（含额外回合的攻击加伤，F7 / 10803）。
## 引擎自己的主动攻击 / 应战反击都走这里；角色自行构造 harm 的攻击技能若也要吃额外回合加伤，
## 应把这里返回的值当作基础伤害。
func 攻击基础伤害(pid: int) -> int:
	return ATTACK_BASE_POINT + 额外回合加伤(pid)


## 构造超时默认回复：与客户端「放弃 / 不发动」等价；返回空字典 = 这个询问不允许超时兜底
func _build_timeout_reply(pid: int, kind: int) -> Dictionary:
	# 询问超时兜底：按「这次问的是什么」构一条合理的最小回复
	# 行动询问：允许放弃才按「放弃行动」收尾，否则不推进（见下）
	# 应答询问：按询问号选默认项；技能询问：默认不发动，但**不可取消**的技能询问例外（见下）
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
	var dst_ids: Array = []
	if _pending_is_skill:
		# 技能询问（ask_skill）→ 不发动：回空 args，
		# 与客户端「取消」一致（0 留给正常的选项值，如【魔女之怒】的「摸 0 张牌」）
		# 「先弹选项」型若已收到分步应答（选好了选项值，如【剑气斩】选好剑气数），超时时带上它继续
		# （选好数量后超时＝自动释放；弹窗还没选就超时 → 仍回空 args＝取消）
		if not _pending_partial.is_empty():
			args = _pending_partial.get("args", [])
		elif not _pending_skill_can_cancel and _pending_skill_need_target > 0:
			# 不可取消的技能询问（如【念弹】：一定要打出一发）：超时不能按「取消」收尾 ——
			# 那会让这条技能白拿代价（【念弹】在问之前就已经 +1【斗气】了）。
			# 自动发动：目标优先从这次下发的合法目标里随机取一名，没给白名单就随机取一名对手；
			# 一个目标都找不到（如只剩自己）才退回「取消」
			var 候选: Array = _pending_skill_timeout_targets.duplicate()
			if 候选.is_empty():
				候选 = _pending_skill_targets.duplicate()
			var 问者: BattlePlayer = players.get(pid)
			if 候选.is_empty() and 问者 != null:
				for p1: BattlePlayer in players.values():
					if p1 != null and p1.id != pid and p1.color != 问者.color:
						候选.append(p1.id)
			if not 候选.is_empty():
				args = [1]
				dst_ids = [int(候选[_rng.randi_range(0, 候选.size() - 1)])]
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
		"respond_id": rid, "src_id": pid, "dst_ids": dst_ids,
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


## 标记玩家掉线/上线。
## 刻意不动「当前正在等的这一次」的截止时刻：他掉线前那一次询问本来就该等满正常时长，
## 一掉线就把倒计时砍到几秒太粗暴（玩家只是网络抖一下就被当成挂机处理）。
## 之后的等待由 wait_for 按掉线时长收紧 —— 所以是「第一次等满，后续按短时长快速处理」。
func set_offline(pid: int, v: bool) -> void:
	if offline_players.has(pid) == v:
		return
	if v:
		offline_players[pid] = true
	else:
		offline_players.erase(pid)
	var p0: BattlePlayer = players.get(pid)
	var pname: String = str(pid)
	if p0 != null:
		# 还没开局（选角阶段）不带角色名：那会儿对局还没开打，写角色反而让人看不懂
		pname = _称号(p0) if phase != Phase.Idle else p0.player_name
	# 同步到玩家身上：快照里的 online 就是它（客户端据此把「玩家列表」那一列显示成「掉线」）
	if p0 != null:
		p0.online = not v
	if v:
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
	# 士气下限（F5）：圣殿骑士【圣炎形态】期间「我方士气最少为 1」
	team_morale[c] = maxi(maxi(v, 0), 士气下限(c))


## 某队当前的士气下限：取该队所有角色 morale_floor() 的最大值（默认 0＝没有下限）
func 士气下限(c: int) -> int:
	var 下限: int = 0
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null or pp.color != c or pp.role == null:
			continue
		下限 = maxi(下限, pp.role.morale_floor())
	return 下限


# ============================================================
# 场卡（F1）：摆在场上 / 某人面前的公共卡
# ============================================================
## 增加（或覆盖）一张场卡。数据形状：
##   id          唯一键（"异端裁决所" / "末日预言" / "绝界"）
##   owner       拥有者玩家号（-1＝无主）
##   attached    挂在谁面前（-1＝不挂人；【绝界】用它）
##   counter     主计数（裁决所=治疗点；末日预言=预言张数）
##   counter_max 计数上限（0＝不限制）
##   state       0/1/2…，语义由角色定义（末日预言：0=正面 / 1=天雷劫火 / 2=地裂波涛）
##   pile        隐藏牌堆（实例号；只把张数下发）
func 加场卡(数据: Dictionary) -> Dictionary:
	var id: String = str(数据.get("id", ""))
	if id.is_empty():
		return {}
	var 表: Dictionary = {
		"id": id,
		"owner": int(数据.get("owner", -1)),
		"attached": int(数据.get("attached", -1)),
		"counter": int(数据.get("counter", 0)),
		"counter_max": int(数据.get("counter_max", 0)),
		"state": int(数据.get("state", 0)),
		"pile": (数据.get("pile", []) as Array).duplicate(),
	}
	# 角色自定义的附加字段原样保留（如异教徒【末日预言】记下翻面后的正面 "front"）
	for k: Variant in 数据.keys():
		if not 表.has(k):
			表[k] = 数据[k]
	移除场卡(id)
	field_cards.append(表)
	_broadcast_game()
	return 表


## 按 id 找场卡（找不到返回空字典）
func 取场卡(id: String) -> Dictionary:
	for 表: Dictionary in field_cards:
		if str(表.get("id", "")) == id:
			return 表
	return {}


## 场上有没有这张场卡
func 有场卡(id: String) -> bool:
	return not 取场卡(id).is_empty()


## 移除场卡（不存在时什么都不做）
func 移除场卡(id: String) -> void:
	for i: int in range(field_cards.size() - 1, -1, -1):
		if str(field_cards[i].get("id", "")) == id:
			field_cards.remove_at(i)
			_broadcast_game()
			return


## 场卡计数增减（返回新值；counter_max > 0 时夹在 [0, counter_max] 内）
func 场卡加计数(id: String, n: int) -> int:
	var 表: Dictionary = 取场卡(id)
	if 表.is_empty():
		return 0
	var 值: int = int(表.get("counter", 0)) + n
	if int(表.get("counter_max", 0)) > 0:
		值 = mini(值, int(表.get("counter_max", 0)))
	表["counter"] = maxi(值, 0)
	_broadcast_game()
	return int(表["counter"])


## 场卡快照（给 game_info）：隐藏牌堆只给张数
func 场卡快照(viewer_id: int) -> Array:
	var out: Array = []
	for 表: Dictionary in field_cards:
		var 项: Dictionary = {
			"id": str(表.get("id", "")),
			"owner": int(表.get("owner", -1)),
			"attached": int(表.get("attached", -1)),
			"counter": int(表.get("counter", 0)),
			"counter_max": int(表.get("counter_max", 0)),
			"state": int(表.get("state", 0)),
			"pile_count": (表.get("pile", []) as Array).size(),
			# 场卡上叠着的明牌（【王权宝珠】）：牌面，-1＝没有牌
			"card": int(表.get("card", -1)),
		}
		# 隐藏信息（【末日预言】的正面）：只给拥有者自己看，别人拿不到
		if int(表.get("owner", -1)) == viewer_id and 表.has("front"):
			项["front"] = str(表.get("front", ""))
		# 明牌堆（仲裁者·圣的【天平·左】/【天平·右】）：牌面朝上摆在卡上，所有人看得到是哪几张
		if bool(表.get("公开牌堆", false)):
			var 明牌: Array = []
			for c: Variant in 表.get("pile", []):
				明牌.append(GConst.牌号(int(c)))
			项["pile"] = 明牌
		out.append(项)
	return out


## 某名玩家面前的场卡（attached == pid）：【绝界】这类“挂在角色面前”的卡用它
func 玩家面前的场卡(pid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for 表: Dictionary in field_cards:
		if int(表.get("attached", -1)) == pid:
			out.append(表)
	return out


## 某名玩家面前有没有这张场卡
func 玩家有场卡(pid: int, id: String) -> bool:
	for 表: Dictionary in field_cards:
		if int(表.get("attached", -1)) == pid and str(表.get("id", "")) == id:
			return true
	return false


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
# 星杯 / 战绩区 / 士气（F8 / 9701 · 8704 · 10803）
# ============================================================
## 某队星杯区的星杯数（10803 的 X / 胜负条件都读它；越界颜色返回 0）
func 星杯数(color: int) -> int:
	if color < 0 or color >= team_grail.size():
		return 0
	return team_grail[color]


## 双方星杯区星杯数之和（10803「X 为双方星杯区星杯数之和」）
func 星杯总数() -> int:
	var 总: int = 0
	for n: int in team_grail:
		总 += n
	return 总


## 某队战绩区当前的星石构成 {gem, crystal, total}（8704「移除战绩区所有星石」前先读）
func 战绩区构成(color: int) -> Dictionary:
	if color < 0 or color >= team_gem.size():
		return {"gem": 0, "crystal": 0, "total": 0}
	return {
		"gem": team_gem[color],
		"crystal": team_crystal[color],
		"total": team_gem[color] + team_crystal[color],
	}


## 移除某队战绩区全部星石，返回移除前的构成 {gem, crystal, total}（8704）。
## 只清该队，另一队不受影响；返回的 gem 用于「本次移除中【宝石】>1」这类后续判定。
func 清空战绩区(color: int) -> Dictionary:
	var 构成: Dictionary = 战绩区构成(color)
	if int(构成.get("total", 0)) <= 0:
		return 构成
	set_team_gem(color, 0)
	set_team_crystal(color, 0)
	_broadcast_game()
	return 构成


## 士气转移（F8 / 8704）：从「从颜色」队扣 n 点士气加到「到颜色」队，返回实际转出点数。
## 【转移】是先扣来源、再加目标：来源队照常扣（有多少扣多少，最多扣到 0）；
## 目标队已经满了时**只是不加**，来源队那一点照样扣掉（不是「加不进去就整笔不转」）。
## 两队相同 / 来源为空一律返回 0。转移后若来源队士气归零，按正常败北判定结束。
func 转移士气(从颜色: int, 到颜色: int, 点: int = 1) -> int:
	if 点 <= 0 or 从颜色 == 到颜色:
		return 0
	if 从颜色 < 0 or 从颜色 >= team_morale.size() or 到颜色 < 0 or 到颜色 >= team_morale.size():
		return 0
	var 扣: int = mini(点, team_morale[从颜色])
	if 扣 <= 0:
		return 0
	var 空间: int = maxi(士气上限() - team_morale[到颜色], 0)
	var 加: int = mini(扣, 空间)
	set_morale(从颜色, team_morale[从颜色] - 扣)
	if 加 > 0:
		set_morale(到颜色, team_morale[到颜色] + 加)
	var 从名: String = _阵营名(从颜色)
	var 到名: String = _阵营名(到颜色)
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Morale,
		"txt": "%s 将 %d 点士气转移给 %s" % [从名, 扣, 到名],
		"id": -1,
	})
	_broadcast_game()
	if team_morale[从颜色] <= 0:
		_check_game_over()
	# 被转走的那一队也是「士气下降」：补压事后钩子，让【琉璃境】这类响应能问
	if 扣 > 0 and phase != Phase.Over:
		var 代表: int = -1
		for pid: int in order:
			var p0: BattlePlayer = players.get(pid)
			if p0 != null and p0.color == 从颜色:
				代表 = p0.id
				break
		if 代表 >= 0:
			push(SHook.new("p_lose_morale_after", {
				"dst": 代表, "amount": 扣, "cause": 0,
				"harm_cause": 0, "type": GConst.HarmType.None, "sync": true,
			}, []))
	return 扣


# ============================================================
# 消息发送
# ============================================================
func send(target: int, msg_type: int, data: Dictionary) -> void:
	if not send_cb.is_valid():
		return
	# 卡牌消息只用于展示 / 音效 / 动画：一律按牌面下发。
	# 服务端内部（手牌 / 盖牌 / 牌堆 / 弃牌堆）按实例号走，两者不能混，否则客户端按牌面找节点会找错。
	if msg_type == GConst.Msg.Card:
		data = _卡牌消息折面(data)
	send_cb.call(target, msg_type, data)


## 把一组牌 id 折成牌面（规则比较 / 下发给客户端用）。
## 实例号在正常牌上就等于牌号，只有调试克隆出来的副本不同（见 GConst.实例号）。
func _牌面表(ids: Array) -> Array:
	var 出: Array = []
	for v: Variant in ids:
		出.append(GConst.牌号(int(v)))
	return 出


## Card 消息折成牌面：card_ids 与 as_card_id 都是给客户端找卡面 / 展示位用的
func _卡牌消息折面(data: Dictionary) -> Dictionary:
	var 出: Dictionary = data.duplicate()
	var ids: Array = 出.get("card_ids", [])
	if not ids.is_empty():
		出["card_ids"] = _牌面表(ids)
	if 出.has("as_card_id"):
		出["as_card_id"] = GConst.牌号(int(出.get("as_card_id", -1)))
	return 出


func broadcast(msg_type: int, data: Dictionary) -> void:
	send(-1, msg_type, data)


## 战斗日志输出一条 [报错]（GossipType.Error）。
## 只用在「正常流程有前置保证、但数据和状态确实可能异常」的地方：
## 报错后按「什么都不做 / 结束当前步骤」处理，不要静默改选目标、随机选择、自动补牌。
func 报错(文本: String, pid: int = -1) -> void:
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Error,
		"txt": 文本,
		"id": pid,
	})


## 行动阶段询问（附带角色可选技能）
## can_give_up：本阶段是否允许「放弃行动」（对照原版 Coder::askForAction 的 canGiveUp 分支，
## 允许时额外下发一条 ACTION_NONE 命令，客户端据此显示「放弃行动」）
func ask_action(pid: int, action_type: int, can_give_up: bool = false, extra: bool = false, no_special: bool = false, extra_cause: int = 0) -> void:
	_pending_action_type = action_type
	var cmds: Array = action_commands(pid, action_type, can_give_up, extra, no_special, extra_cause)
	_最后行动命令[pid] = cmds
	_询问(pid, GConst.CmdType.Action, cmds)


## 下发一条询问给某玩家，并把它记下来：玩家重连回来时照原样补发（见 重发当前询问）
func _询问(pid: int, cmd_type: int, commands: Array) -> void:
	_询问计数 += 1
	_最后询问[pid] = {"cmd_type": cmd_type, "commands": commands}
	send(pid, GConst.Msg.CmdReq, {"cmd_type": cmd_type, "commands": commands})


## 玩家重新进房：把「正等他的那份询问」补发一次。
## 不补发的话客户端手里没有询问、画不出操作界面，只能干等到超时被自动代打 —— 等于白掉一次线
func 重发当前询问(pid: int) -> void:
	if _await_id != pid or not _最后询问.has(pid):
		return
	var 询问: Dictionary = _最后询问[pid]
	_询问(pid, int(询问["cmd_type"]), 询问["commands"])


## 切换手牌里一张多系别牌（魔刃/异刃）的当前系别。
## 只改卡牌当前系别、重算这名玩家能放的技能，**不消耗行动、不重发正式询问**：
## 回一条 CardElement 带上刷新后的行动命令，客户端原地更新技能栏（避免 ErrorInput 回滚闪一下）。
## 卡牌的当前系别在服务端保存在 GCard 上，之后所有通用系别逻辑（同系/异系、攻击牌白名单、
## 弃牌费用等）都按它判断。
func 设置卡牌元素(pid: int, card_id: int, element: int) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null or not p0.has_hand_card(card_id):
		return false
	var 牌: GCard = Data.get_card(card_id)
	if 牌 == null or not 牌.设置当前元素(element):
		return false
	# 「按系别规则算可用攻击牌」的缓存里可能还留着切换前的那几项
	_规则攻击牌缓存.clear()
	var cmds: Array = []
	if _await_id == pid and _await_kind == GConst.Msg.Action:
		cmds = action_commands(pid, 行动允许, 行动可放弃, 行动额外, 行动禁特殊, 行动额外来源)
		_最后行动命令[pid] = cmds
		_最后询问[pid] = {"cmd_type": GConst.CmdType.Action, "commands": cmds}
	send(pid, GConst.Msg.CardElement, {
		"card_id": card_id, "element": element, "commands": cmds,
	})
	# 再补一次快照：卡牌的「有效系别」可能被卡牌系别属性改写过（如苍炎魔女【烈焰形态】视为火），
	# 客户端要按快照里的 hand_elements / hand_attrs 重新算显示，只发 CardElement 会停在旧系别上
	_broadcast_game()
	return true


# ============================================================
# 通用「卡牌系别属性」（按持有者现算，不需要给牌挂东西）
# ============================================================
## 属性不是「挂上去」的，而是每拍按**持有者**现算：
## 卡牌持有人若处于某个改变系别的形态（如苍炎魔女【烈焰形态】：除水 / 暗外的攻击牌视为火），
## 这张牌的有效系别就按形态算 —— 别人隔着他的回合塞牌给她、她自己摸牌 / 弃牌 / 交牌，都不需要额外处理。
## 计算结果写进 GCard.系别覆盖（element_enum() 优先返回它），所以同系 / 异系、应战要求、弃牌费用、
## 攻击表现牌、卡面左上角标签……所有读 element_enum() 的地方自动跟着走，不含任何角色特判。
var _属性归属: Dictionary = {}   # 卡牌实例号 -> 属性持有者 player_id（只用于「牌离手后清掉」）


## 这名玩家此刻手里（含「盖牌当手牌」形态下的盖牌）的牌
func _持有牌列表(pp: BattlePlayer) -> Array:
	var out: Array = pp.hand_cards.duplicate()
	if pp.role != null and pp.role.盖牌可当手牌():
		out.append_array(pp.cover_cards)
	return out


## 每拍同步「卡牌系别属性」：① 手里每张牌按持有者现算；② 已经离手的清掉（正在攻击结算里的先留着）
func _check_卡牌属性() -> void:
	var 改了: bool = false
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null:
			continue
		var 属性名: String = pp.role.牌系别属性名() if pp.role != null else ""
		for iid: int in _持有牌列表(pp):
			var 牌: GCard = Data.get_card(iid)
			if 牌 == null:
				continue
			var 想要: int = pp.role.牌系别覆盖(牌) if pp.role != null else 0
			if 想要 == 0:
				if 牌.系别覆盖 != 0:
					_清一条卡牌属性(iid)
					改了 = true
				continue
			if 牌.系别覆盖 == 想要 and 牌.系别覆盖名 == 属性名:
				continue
			# 必须写到**运行时实例副本**上：牌库里序号为 0 的牌实例号 == 牌号，
			# 直接改 get_card(iid) 拿到的那张牌面对象，会连其它同牌面的副本一起改掉。
			var 实例牌: GCard = Data.取实例卡(iid)
			if 实例牌 == null:
				continue
			实例牌.系别覆盖 = 想要
			实例牌.系别覆盖名 = 属性名
			_属性归属[iid] = pid
			_规则攻击牌缓存.clear()
			改了 = true
	for iid: int in _属性归属.keys().duplicate():
		var pid2: int = int(_属性归属[iid])
		var pp2: BattlePlayer = players.get(pid2)
		if pp2 != null and _持有牌列表(pp2).has(iid):
			continue
		if _牌在结算中(iid):
			continue
		_清一条卡牌属性(iid)
		改了 = true
	if 改了:
		_broadcast_game()


func _清一条卡牌属性(iid: int) -> void:
	_属性归属.erase(iid)
	# 只清实例副本：属性当初就是写在它上面的，牌面对象从来不动
	if not Data.实例卡.has(iid):
		return
	var 牌: GCard = Data.实例卡[iid]
	if 牌 == null or 牌.系别覆盖 == 0:
		return
	牌.系别覆盖 = 0
	牌.系别覆盖名 = ""
	_规则攻击牌缓存.clear()


## 这张牌是不是正在某次攻击 / 应战的结算里（此时不能清属性：
## 应战要求、伤害结算、表现牌动画都还要读它的有效系别）
func _牌在结算中(iid: int) -> bool:
	for st: Variant in _states:
		if st is SAttackCard:
			var a: SAttackCard = st
			if int(a.card) == iid:
				return true
			if int((a.harm as Dictionary).get("card_id_instance", -1)) == iid:
				return true
		elif st is SReattackGo:
			var r: SReattackGo = st
			if int(r.原牌) == iid:
				return true
	return false


## 重算「这名玩家此刻能放的技能」，有变化才重发一次行动询问。
## 手牌、能量、治疗、阵营这些都会影响能放的技能，所以不盯某一个字段，而是跟着对局快照（_broadcast_game）走：
## 每发一次快照就重算一遍 —— 快照本身很密，算完跟上次一样就不发，界面不会被打断。
## 只在「正等这名玩家做行动」时生效：别人的回合、或正在结算的时候不动他的界面
func _刷新技能可用(pid: int) -> void:
	if _await_id != pid or _await_kind != GConst.Msg.Action:
		return
	var cmds: Array = action_commands(pid, 行动允许, 行动可放弃, 行动额外, 行动禁特殊, 行动额外来源)
	if str(cmds) == str(_最后行动命令.get(pid, [])):
		return
	_最后行动命令[pid] = cmds
	_询问(pid, GConst.CmdType.Action, cmds)


## 行动询问的命令表：第 0 项是通用行动（允许放弃时再补一项「放弃」），其余是当前手牌下该角色能放的技能
func action_commands(pid: int, action_type: int, can_give_up: bool, extra: bool = false, no_special: bool = false, extra_cause: int = 0) -> Array:
	var cmds: Array = [{
		"respond_id": action_type, "src_id": pid,
		"dst_ids": [], "card_ids": [], "args": [],
		# 额外行动阶段：客户端据此把提示写成「获得额外攻击行动 / 额外法术行动 / 额外行动」
		"is_extra": extra,
		# 这份额外行动的来源（如苍白之月 3507）；普通行动不带
		"extra_cause": extra_cause,
		# 这份额外行动的唯一 ID：客户端提交切换 / 出手时回这个 ID（同一技能挂两份也分得清）
		"extra_uid": int(当前额外行动数据.get("uid", 0)) if extra else 0,
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
		# 额外行动阶段：出牌白名单 / 目标白名单 / 系别全部读这份行动自己的规格
		# （授予时由技能算好，见 BattlePlayer.add_action 的 spec）。引擎不按 cause 回问角色。
		if extra and extra_cause > 0:
			var 额外数据: Dictionary = _额外行动数据(pl, extra_cause)
			var 命格: int = int(额外数据.get("card_fate", 0))
			# 只按命格限制（如技之剑意＝技类攻击牌）：下发规则本身，客户端直接比对牌面的「命格」字段，
			# 不再塞一张「全部技类攻击牌」的牌号名单（牌号表会随卡表变化，也没必要占带宽）
			var 只按命格: bool = 命格 > 0 and int(额外数据.get("element", 0)) <= 0 \
					and (额外数据.get("cards", []) as Array).is_empty()
			if 只按命格:
				cmds[0]["extra_fate"] = 命格
			else:
				var 行动牌: Array = 额外行动出牌白名单(额外数据, pl.id)
				if not 行动牌.is_empty():
					cmds[0]["card_ids"] = _牌面表(行动牌)
			var 目标限制: Array = 额外数据.get("targets", [])
			if not 目标限制.is_empty():
				cmds[0]["dst_ids"] = 目标限制
			var 系别: int = int(额外数据.get("element", 0))
			if 系别 > 0:
				cmds[0]["extra_element"] = 系别
		# 额外行动的系别限制交给客户端判：会改系别的技能（3805 视为风系）在额外行动阶段
		# 可能被本地切换行动，服务端这里只把「这条技能固定视为哪个系别」带下去。
		for sk: Dictionary in pl.role.available_skills():
			cmds.append(_技能按钮命令(pl, sk, action_type))
	# 额外行动阶段：这次询问里可用的额外行动整份下发，**顺序由 额外行动序列 定死**，
	# 客户端照着摆（不排序、不重排）；当前正在行动的那份也在这份列表里（is_extra 那条）。
	# 这里**不按动作种类过滤**：额外行动可能是攻击、法术或两类都行（如元素师【元素点燃】+1 法术行动
	# 与迅捷赐福 +1 攻击行动同时挂着），玩家要能看到全部并自由切换；
	# 切换后能做什么由那份行动自己的 allow_action 决定（客户端按照它点亮手牌 / 技能，服务端按它校验）。
	if extra and extra_cause > 0 and pl != null and pl.role != null:
		var 序列原因: Array = []
		var 序列ID: Array = []
		var 序列允许: Array = []
		var 序列牌: Array = []
		var 序列目标: Array = []
		var 序列系别: Array = []
		var 序列命格: Array = []
		for 项: Dictionary in 额外行动序列(pid, true):
			var c: int = int(项.get("cause", 0))
			var uid: int = int(项.get("uid", 0))
			var 允许: int = int(项.get("allow_action", 0))
			if c <= 0 or uid <= 0 or 允许 <= 0:
				continue
			var 是当前: bool = bool(项.get("current", false))
			# 队列里的其它额外行动：只有 direct 且允许切换的才摆出来（点一个就切过去）
			if not 是当前 and (not bool(项.get("direct", false)) or not bool(项.get("switchable", true))):
				continue
			# 只按命格限制的那一份（技之剑意等）不下发牌号名单，只给命格，客户端比对牌面字段
			var 项命格: int = int(项.get("card_fate", 0))
			var 只按命格: bool = 项命格 > 0 and int(项.get("element", 0)) <= 0 \
					and (项.get("cards", []) as Array).is_empty()
			序列原因.append(c)
			序列ID.append(uid)
			序列允许.append(允许)
			序列牌.append({"ids": [] if 只按命格 else _牌面表(额外行动出牌白名单(项, pid))})
			序列目标.append({"ids": 项.get("targets", [])})
			序列系别.append(int(项.get("element", 0)))
			序列命格.append(项命格 if 只按命格 else 0)
			if not 是当前:
				cmds.append({
					"respond_id": GConst.ActionType.ChooseExtraAction, "src_id": pid,
					"dst_ids": 项.get("targets", []),
					"card_ids": _牌面表(项.get("cards", [])),
					"args": [uid], "extra_cause": c, "extra_uid": uid,
					"extra_element": int(项.get("element", 0)),
				})
		if not 序列原因.is_empty():
			cmds[0]["extra_attack_causes"] = 序列原因
			cmds[0]["extra_attack_uids"] = 序列ID
			# 与 extra_attack_causes 一一对应的动作种类：客户端据此把「攻击/法术/两类都行」
			# 写成对应文案（AttackMagic 要写成「额外【攻击行动】或【法术行动】」）
			cmds[0]["allow_actions"] = 序列允许
			cmds[0]["extra_attack_cards"] = 序列牌
			cmds[0]["extra_attack_targets"] = 序列目标
			cmds[0]["extra_attack_elements"] = 序列系别
			# 与 extra_attack_causes 一一对应的命格限制（0＝那一份不限）：客户端切换后按它比对牌面
			cmds[0]["extra_attack_fates"] = 序列命格
	return cmds


## 把角色 available_skills() 的一项翻成「技能栏上的那颗按钮」命令（行动询问用）。
## 字段名与 ask_skill（技能询问）保持同一批：enabled / card_ids / card_max / card_rule /
## card_slot_* / target_max_from_cards / cover_need / dst_ids / highlight_ids。
## 区别只有 respond_id：这里是「技能类型」（决定按钮颜色与点击后走哪条行动通道），
## 而 ask_skill 里是「技能号」（这次在问哪个技能）。
func _技能按钮命令(pl: BattlePlayer, sk: Dictionary, action_type: int) -> Dictionary:
	# 技能一律下发（界面默认全摆出来），当前不可用的只把 enabled 置 false —— 客户端据此置灰、
	# 点不动，玩家能看见「这个技能存在、但现在用不了」，而不是整条消失
	var 技能可用: bool = bool(sk.get("enabled", true))
	# 会改系别的技能（3805 视为风系）：把系别带给客户端，由客户端按「当前/切换后的行动」
	# 的系别要求置灰 —— 不能在这里写死 enabled：额外行动可以在本地切换，
	# 服务端算的这次 enabled 只对应「下发那一刻」的那份行动（切换后就会过时）。
	var 技能视为: int = int(pl.role.call("技能视为系别",
		{"action_id": int(sk.get("id", 0)), "src_id": pl.id}))
	# 「启动」技能每回合只能发动一个：本回合已发动过就置灰
	if pl.boot_skill_used and int(sk.get("type", 0)) == GConst.ActionType.ActivateSkill:
		技能可用 = false
	# 启动技能是独立类型（ActivateSkill）：不看本阶段放行哪种行动（被【挑衅】只放行攻击时也能用），
	# 只看「本回合第一个行动之前 + 非额外行动阶段」这一条（见 可发动启动）。
	var 技能类型: int = int(sk.get("type", 0))
	if 技能类型 == GConst.ActionType.ActivateSkill:
		if not 可发动启动(pl.id) or 行动禁特殊:
			技能可用 = false
	elif not GConst.放行动作(技能类型, action_type):
		技能可用 = false
	# 声明了 targets 就等于「本次目标受限」：一个合法目标都没有时置灰。
	# 空列表在协议/客户端那里等于「不限制」（_玩家可选），会让本该被挡住的人
	# （如已有【圣盾】/【天使之墙】的目标）反而变成能点 —— 所以只能靠置灰挡住点击
	if sk.has("targets") and (sk.get("targets", []) as Array).is_empty():
		技能可用 = false
	return {
		"respond_id": int(sk.get("type", 0)), "src_id": pl.id,
		# 技能栏按钮的规格：命名字段（阶段 5.5）。老客户端读下面的 args，新客户端读这几个。
		"skill_id": int(sk.get("id", 0)),
		"need_card": int(sk.get("need_card", 0)),
		"need_target": int(sk.get("need_target", 0)),
		"target_max": int(sk.get("target_max", 0)),
		"card_source": int(sk.get("card_source", GConst.CardSource.Hand)),
		# false＝这条技能本次不可用：界面照样摆出来，但半透明、点不动
		"enabled": 技能可用,
		# 这条技能把本次出牌固定视为哪个系别（0＝不固定）：额外行动阶段客户端本地切换
		# 行动时据此重算置灰（服务端的 enabled 只按「当前那份行动」算过一次）
		"skill_element": 技能视为,
		# targets 非空时，客户端只把这几名玩家点亮（如【魔弹融合】的落点固定是右手边最近的对手）
		"dst_ids": sk.get("targets", []),
		# 这一手顺带点亮给人看的角色（纯展示，不参与选择、不提交）：
		# 如怠惰少女【别烦我……】10601 —— 目标由右手边队友代选，本人这一手没有目标，
		# 只把那名队友高亮出来（服务端结算时本来就不看这个 dst）
		"highlight_ids": sk.get("highlight", []),
		# cards 非空时，客户端只让这几张牌可点（如【暗影流星】只能弃法术牌）。
		# 角色给出的白名单可能取自手牌（带实例号），下发前统一折成牌面
		"card_ids": _牌面表(sk.get("cards", [])),
		# card_max 非空时，客户端点选上限放宽到它（如【欺诈】弃 2~3 张）
		"card_max": int(sk.get("card_max", 0)),
		# arg_choices 非空时，客户端把每项渲染成一个按钮，点哪个就用当前已选的牌/目标提交该项 args
		# （如【冒险者天堂】选要用哪些星石）
		"arg_choices": sk.get("arg_choices", []),
		# card_rule 非空时客户端限制可点牌（same＝必须同系 / diff＝必须互异系 /
		# magic＝只能法术牌 / same_fate_pattern＝必须与已选牌同命格）
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
	}


func ask_respond(pid: int, respond_id: int, args: Array, dst_ids: Array = [], src_id: int = -1,
		card_max: int = 0, card_rule: String = "", ask_text: String = "", allow_actions: Array = [],
		option_uids: Array = [], ban_reattack_card_names: Array = [], can_light: bool = true) -> void:
	# 记录本次询问，供超时构造默认回复
	_pending_respond_id = respond_id
	_pending_args = args.duplicate()
	_pending_is_skill = false
	_pending_partial = {}
	var cmd: Dictionary = {
		"respond_id": respond_id,
		"src_id": src_id if src_id >= 0 else pid,
		"dst_ids": dst_ids,
		"card_ids": [],
		"args": args,
	}
	if not allow_actions.is_empty():
		cmd["allow_actions"] = allow_actions
	# 与 args 里每个选项一一对应的「额外行动唯一 ID」：客户端提交时回这个 ID（同一技能挂两份也分得清）
	if not option_uids.is_empty():
		cmd["option_uids"] = option_uids
	# 魔弹传递等少数应答需要放宽选牌上限 / 给提示（10603 弃 2 张同系牌视为魔弹）
	if card_max > 0:
		cmd["card_max"] = card_max
	if not card_rule.is_empty():
		cmd["card_rule"] = card_rule
	if not ask_text.is_empty():
		cmd["ask_text"] = ask_text
	# 本次攻击禁用来应战的卡名（如 9703 禁【暗灭】）：客户端据此置灰，服务端仍复核
	if not ban_reattack_card_names.is_empty():
		cmd["ban_reattack_card_names"] = ban_reattack_card_names
	# 这次应答不能用【圣光】（如染污者狂戾形态）：魔弹传递询问也走这条，客户端据此把圣光置灰
	if not can_light:
		cmd["can_light"] = false
	_询问(pid, GConst.CmdType.Respond, [cmd])


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
## "magic"＝只能选法术牌 / "same_fate_pattern"＝必须与已选牌同命格）
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
## can_light=false 时随询问下发 can_light=false（如【阴阳转换】：这次攻击不能用【圣光】抵挡，
## 客户端据此把【圣光】置灰；默认 true 时不下发，客户端按可用处理）
## 高亮目标 非空时随询问下发（highlight_ids）：只把这几名角色点亮给人看，**不参与选择、不参与提交**。
## 用于「效果落在不受玩家选择的角色身上」的技能 —— 如【别烦我……】让目标弃牌那一步，
## 同时点亮「不弃就 +1 治疗」的那名队友（目标自己由客户端点亮）
func ask_skill(pid: int, skill_id: int, need_card: int = 0, need_target: int = 0, card_source: int = GConst.CardSource.Hand, options: Array = [], card_max: int = 0, card_rule: String = "", cards: Array = [], can_cancel: bool = true, ask_text: String = "", targets: Array = [], 预览基准: int = 0, 预览类型: int = 0, 保留倒计时: bool = false, 预览目标: Array = [], can_light: bool = true, 预览伤害: int = -1, cover_need: int = 0, 允许额外攻击快捷: bool = false, default_option: int = -1, no_parent: bool = false, ask_prompt: String = "", 高亮目标: Array = [], timeout_targets: Array = [], cover_max: int = 0, hand_need: int = -1,
		allow_back: bool = false, 预览规则: String = "") -> void:
	# 基础效果授予的额外行动（迅捷赐福等）：未确认时作为普通响应选项摆出来；
	# 确认后不再出现选项，改由额外的行动快捷按钮显示。
	var 用选项: Array = options.duplicate(true)
	# 公用规则：「要用一张牌的实例，先确认它还在场」——
	# 选项指向的具体牌实例（card_id）若已被移除，就不再作为选项下发；
	# 只丢这一项、其余 value 原样保留，调用方按 args[0] 仍能对上自己的列表。
	var 在场选项: Array = []
	for o0: Dictionary in 用选项:
		# -1＝这一项不对应牌；0 是合法牌号（卡表#0 圣盾），只有负数才代表「没有牌」
		var 选项牌: int = int(o0.get("card_id", -1))
		if 选项牌 >= 0 and not 牌在场(选项牌):
			continue
		在场选项.append(o0)
	用选项 = 在场选项
	# 牌白名单同理：被移除的实例不能留在可点列表里（牌面值不受影响）
	var 在场牌表: Array = []
	for c0: Variant in cards:
		if int(c0) >= 0 and not 牌在场(int(c0)):
			continue
		在场牌表.append(c0)
	cards = 在场牌表

	if not _基础效果额外行动已确认.is_empty():
		var 过滤后: Array = []
		for o: Dictionary in 用选项:
			if not _基础效果额外行动已确认.has(int(o.get("value", 0))):
				过滤后.append(o)
		用选项 = 过滤后
	if 允许额外攻击快捷:
		for o: Dictionary in 基础效果额外行动选项(pid):
			var 选项号: int = int(o.get("value", 0))
			var 已有: bool = false
			for old: Dictionary in 用选项:
				if int(old.get("value", 0)) == 选项号:
					已有 = true
					break
			if not 已有:
				用选项.append(o)
	options = 用选项
	var args: Array = [need_card, need_target, card_source, options.size()]
	var notes: Array = []
	var 选项技能号: Array = []
	var 选项可用: Array = []
	var 选项需牌: Array = []
	var 选项目标: Array = []
	var 选项牌号: Array = []
	var 选项不改提示: Array = []
	var 选项提示: Array = []
	var 选项独立技能: Array = []
	var 选项需目标: Array = []
	var 选项预览牌: Array = []
	var 选项元素: Array = []
	var 选项技能组: Array = []
	var 选项牌白: Array = []
	var 选项来源: Array = []
	# 每个选项「选了它之后本次攻击会打多少」（只用于画头像提示；0＝这一项不改伤害）
	var 选项伤害: Array = []
	var 有选项目标: bool = false
	# 阶段 5.2：同一份选项再按「一个选项一条 Option 消息」攒一份（旧端会跳过这个字段号）
	var 嵌套选项: Array = []
	for o: Dictionary in options:
		args.append(int(o.get("value", 0)))
		notes.append(str(o.get("label", "")))
		选项技能号.append(int(o.get("skill_id", 0)))
		选项可用.append(bool(o.get("enabled", true)))
		选项需牌.append(int(o.get("need_card", 0)))
		# -1＝这一项不对应牌；0 是合法牌号（卡表#0 圣盾），不能拿 0 当「没有」
		选项牌号.append(int(o.get("card_id", -1)))
		选项不改提示.append(bool(o.get("no_prompt_change", false)))
		选项提示.append(str(o.get("提示", "")))
		选项独立技能.append(bool(o.get("独立技能", false)))
		选项需目标.append(int(o.get("need_target", 0)))
		选项预览牌.append({"ids": _牌面表(o.get("preview_cards", []))})
		选项元素.append({"ids": o.get("elements", [])})
		选项技能组.append({"ids": o.get("技能组", [])})
		选项牌白.append({"ids": _牌面表(o.get("cards", []))})
		选项来源.append(int(o.get("card_source", -1)))
		选项伤害.append(int(o.get("damage", 0)))
		var 目标: Array = o.get("targets", [])
		选项目标.append({"ids": 目标})
		if not 目标.is_empty():
			有选项目标 = true
		# 与上面那些平行数组取自同一份 `o`，保证两边永远同值（阶段 5.3 客户端会改读这一份）
		嵌套选项.append({
			"value": int(o.get("value", 0)),
			"label": str(o.get("label", "")),
			"enabled": bool(o.get("enabled", true)),
			"skill_id": int(o.get("skill_id", 0)),
			"need_card": int(o.get("need_card", 0)),
			"need_target": int(o.get("need_target", 0)),
			"target_max": int(o.get("target_max", 0)),
			# -1＝这一项不对应牌（0 是合法牌号：卡表#0 圣盾）
			"card_id": int(o.get("card_id", -1)),
			# -1＝沿用技能本体的选牌来源
			"card_source": int(o.get("card_source", -1)),
			"cover_need": int(o.get("cover_need", 0)),
			"hand_need": int(o.get("hand_need", -1)),
			"targets": {"ids": 目标},
			"cards": {"ids": _牌面表(o.get("cards", []))},
			"elements": {"ids": o.get("elements", [])},
			"preview_cards": {"ids": _牌面表(o.get("preview_cards", []))},
			"skill_group": {"ids": o.get("技能组", [])},
			"prompt": str(o.get("提示", "")),
			"no_prompt_change": bool(o.get("no_prompt_change", false)),
			"damage": int(o.get("damage", 0)),
		})
	var cmd: Dictionary = {
		"respond_id": skill_id,
		"src_id": pid,
		# 显式标记这是技能询问（客户端据此进入技能询问界面，不用拿询问号大小去猜）
		"is_skill": true,
		# targets 非空时客户端只让这几名玩家可点（如【天使之歌】只能选面前有基础效果的人）
		"dst_ids": targets,
		# 角色给出的白名单可能取自手牌（带实例号），下发前统一折成牌面：
		# 客户端按牌面比较可点性，服务端自己的校验也按牌面
		"card_ids": _牌面表(cards),
		"args": args,
		"card_max": maxi(need_card, card_max),
		"card_rule": card_rule,
		# 只有「不能取消」才下发这个字段（客户端拿不到就按可以取消处理）
		"can_cancel": can_cancel,
	}
	# 手牌+盖牌混选时，要求其中几张必须是盖牌（如美杜莎之眼：1 张暗月盖牌 + 1 张手牌）
	if cover_need > 0:
		cmd["cover_need"] = cover_need
	# 混选时盖牌最多几张（如黄金律：1 张手牌 + 1 个【卢恩】，盖牌不能选第 2 张）
	if cover_max > 0:
		cmd["cover_max"] = cover_max
	# 混选时**直接**给手牌张数：客户端按「手牌 hand_need 张 + 盖牌 cover_need 张」卡，
	# 不用再拿「总张数 - 至少盖牌数」倒算。不传（-1）＝沿用旧口径。
	if hand_need >= 0:
		cmd["hand_need"] = hand_need
	if not notes.is_empty():
		cmd["notes"] = notes
	# 有「本身就是技能」的选项时才下发（如【蓄力一击】/【气绝崩击】），客户端据此让这些选项悬停弹技能说明
	if not 选项技能号.is_empty() and 选项技能号.max() > 0:
		cmd["option_skill_ids"] = 选项技能号
	# 选项对应一张牌时（如剑之子【剑守誓言】的「选 1 张加入手牌」）：客户端悬停选项按钮时直接摊卡面
	if not 选项牌号.is_empty() and 选项牌号.max() >= 0:
		cmd["option_card_ids"] = _牌面表(选项牌号)
	# 选项声明「选中不改提示条」时才下发（如放逐的正面二选一）
	if not 选项不改提示.is_empty() and 选项不改提示.has(true):
		cmd["option_no_prompt_change"] = 选项不改提示
	# 选项自带「选中后本步文案」/「独立技能」时才下发（统一 4 规则后由客户端读取）
	if not 选项提示.is_empty() and not str(选项提示).is_empty():
		var 提示有内容: bool = false
		for _t: Variant in 选项提示:
			if not str(_t).is_empty():
				提示有内容 = true
				break
		if 提示有内容:
			cmd["option_prompts"] = 选项提示
	if not 选项独立技能.is_empty() and 选项独立技能.has(true):
		cmd["option_switch_desc"] = 选项独立技能
	# 有不可用选项时才下发（如魔纹不够时的额外翻转档）：客户端据此置灰、点不动
	if not 选项可用.is_empty() and 选项可用.has(false):
		cmd["option_enabled"] = 选项可用
	# 有「选中后要弃牌」的选项时才下发（如【魔纹融合】）：客户端选到该项才放出手牌可选
	if not 选项需牌.is_empty() and 选项需牌.max() > 0:
		cmd["option_need_cards"] = 选项需牌
	# 每个选项各自要求选几名目标（攻击结束二选一：剑残影 1 名、剑影*断念 0 名）
	if not 选项需目标.is_empty() and 选项需目标.max() > 0:
		cmd["option_need_targets"] = 选项需目标
	# 有「各自目标白名单」的选项时才下发（如吟游诗人【希望赋格曲】的「放置」不含自己、
	# 「转移」含自己）：客户端选中某项后按它收紧可点头像（未选＝按并集）
	if 有选项目标:
		cmd["option_targets"] = 选项目标
	# 选项涉及的系别 / 悬停技能组（与 args 一一对应；共振的四项、御刃同款）
	if not options.is_empty():
		cmd["option_elements"] = 选项元素
		cmd["option_skill_groups"] = 选项技能组
		# 选项自带牌白名单（空数组＝不限；有 -1 表示一张都不给点）
		if 选项牌白.any(func(项: Dictionary) -> bool: return not (项.get("ids", []) as Array).is_empty()):
			cmd["option_cards"] = 选项牌白
	# 选项自带的选牌来源（-1＝沿用技能本体）：如行动结束响应里魔弓【多重射击】
	# 选中后要把盖牌区亮出来（服务端自己挑充能）
	if 选项来源.any(func(v: Variant) -> bool: return int(v) >= 0):
		cmd["option_card_sources"] = 选项来源
	# 有「选中后本次伤害变成多少」的选项时才下发（与 args 一一对应；0＝这一项不改伤害）：
	# 客户端据此画「原值划掉 → 新值」，不再按技能名自己现算加成
	if 选项伤害.any(func(v: Variant) -> bool: return int(v) > 0):
		cmd["option_damages"] = 选项伤害
	# 选项带「悬停预览牌」时（如【三秒原则】的「获得 2 张【魔弹】」）：
	# 客户端悬停那个选项按钮时把这几张牌的卡面并排摊出来
	if not 选项预览牌.is_empty():
		var 有预览: bool = false
		for 项预览: Dictionary in 选项预览牌:
			if not (项预览.get("ids", []) as Array).is_empty():
				有预览 = true
		if 有预览:
			cmd["option_preview_cards"] = 选项预览牌
	# 阶段 5.2：整份选项再按「一个选项一条 Option 消息」发一遍（见 proto_schema 的 Option）。
	# 客户端目前不读它、旧端也会按不认识的字段号跳过，所以发它不改变任何现有行为；
	# 5.3 让客户端改读这份之后，上面那些平行数组才会退役。
	if not 嵌套选项.is_empty():
		cmd["options"] = 嵌套选项
	# 默认替玩家选中哪一项（0 基下标；行动结束响应用）：不传＝不预选。
	# 客户端据此在选项摆出来的同时先点亮第一项，玩家不用先点一次选项才能按「确定」。
	if default_option >= 0:
		cmd["default_option"] = default_option
	# 不摆「被问的技能」本体（行动结束响应用）：选项本身就是全部可选项，没有父技能。
	# 否则 respond_id（只是列表第一项）会多摆一颗与选项同名的按钮。
	if no_parent:
		cmd["no_parent"] = true
	# 客户端现算头像提示要用的基准数值（如【战纹碎击】要显示「原伤害 + 弃牌加伤」、
	# 【双重回响】要显示它复制出来的那份伤害）
	if 预览基准 > 0:
		cmd["preview_base"] = 预览基准
	if 预览类型 > 0:
		cmd["preview_kind"] = 预览类型
	# 头像提示画在这些角色身上（非空时用它，否则沿用 dst_ids）：见 ask_skill 顶部「预览目标」
	if not 预览目标.is_empty():
		cmd["preview_ids"] = 预览目标
	# 顺带点亮给人看的角色（纯展示，不参与选择 / 提交）：见 ask_skill 顶部「高亮目标」
	if not 高亮目标.is_empty():
		cmd["highlight_ids"] = 高亮目标
	# 本次攻击不能用【圣光】抵挡时才下发（客户端据此把【圣光】置灰）
	if not can_light:
		cmd["can_light"] = false
	# 多步询问：这一段是「后面几步中的一步」，客户端在选项左侧摆「返回」，
	# 玩家点了就回一条空应答，服务端把它当「退回上一段重问」（见角色里的分段函数）
	if allow_back:
		cmd["allow_back"] = true
	# 同一次攻击的伤害预览（客户端「受到 N 伤害攻击」用）：普通应战里由 SAttackedAsk 下发，
	# 3306 这种在同一步里先问效果的技能询问也要带上，提示才对得上。
	if 预览伤害 >= 0:
		cmd["preview_damage"] = 预览伤害
	# 按「玩家当前选择」现算的预览加伤规则（如「每张所选火系牌 +1」）：客户端只按它加，不判规则
	if not 预览规则.is_empty():
		cmd["preview_rule"] = 预览规则
	# 询问别人的场合（如请人交牌）：下发目标侧文案，客户端优先显示它
	if not ask_text.is_empty():
		cmd["ask_text"] = ask_text
	# 整段专属提示（如 9703 改写后的【血腥咆哮】）：客户端提示条直接用它，不再套技能说明
	if not ask_prompt.is_empty():
		cmd["ask_prompt"] = ask_prompt
	_pending_respond_id = skill_id
	_pending_args = args.duplicate()
	_pending_is_skill = true
	# 攻击结束响应期间，把「已获得但还没用的攻击行动」一并下发给客户端做红色快捷按钮。
	# 顺序来自 额外行动序列（唯一排序入口），和额外行动阶段的技能栏完全一致。
	if 允许额外攻击快捷:
		var 额外攻击: Array = []
		var 额外攻击ID: Array = []
		var 额外允许: Array = []
		var 额外牌表: Array = []
		var 额外目标表: Array = []
		var 额外系别表: Array = []
		for 项: Dictionary in 额外行动序列(pid, false):
			if not _可快捷攻击(项):
				continue
			额外攻击.append(int(项.get("cause", 0)))
			额外攻击ID.append(int(项.get("uid", 0)))
			额外允许.append(int(项.get("allow_action", 0)))
			额外牌表.append({"ids": _牌面表(额外行动出牌白名单(项, pid))})
			额外目标表.append({"ids": 项.get("targets", [])})
			额外系别表.append(int(项.get("element", 0)))
		if not 额外攻击.is_empty():
			cmd["extra_attack_causes"] = 额外攻击
			cmd["extra_attack_uids"] = 额外攻击ID
			# 与 extra_attack_causes 一一对应的动作种类：客户端据此写对按钮文案
			cmd["allow_actions"] = 额外允许
			cmd["extra_attack_cards"] = 额外牌表
			cmd["extra_attack_targets"] = 额外目标表
			cmd["extra_attack_elements"] = 额外系别表
		cmd["has_extra_options"] = not 用选项.is_empty() or not 额外攻击.is_empty()
	# 超时兜底要用的三项（见 _build_timeout_reply）：不可取消的技能询问不许按「取消」收尾
	# 超时兜底要用的三项（见 _build_timeout_reply）：不可取消的技能询问不许按「取消」收尾
	_pending_skill_can_cancel = can_cancel
	_pending_skill_need_target = need_target
	_pending_skill_targets = targets.duplicate()
	_pending_skill_timeout_targets = timeout_targets.duplicate()
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
	# 技能询问：通用写法「响应【技能名】」；技能名末尾的【回合限定】这类标签不带进等待栏
	if _pending_is_skill:
		var 技能名: String = GConst.skill_name(_pending_respond_id).replace("【回合限定】", "")
		return "响应【%s】" % 技能名
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
		"pick_ready": pick_ready,
		"player_id": viewer_id,
		# 士气上限（固定 15）：随快照下发，客户端直接用，不必自己再算
		"morale_max": 士气上限(),
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
		# 等待序号：客户端据此判断「是不是开始了新的一次等待」，避免重发快照重复弹提示
		"wait_seq": wait_seq,
		"start_countdown_ms": start_countdown_ms,
		# 本局是否已经打完：房主随即解散房间，客户端据此留在结算界面看结果（见 client_logic）
		"over": phase == Phase.Over,
		# 房主座位号（-1 = 没记录）：客户端「玩家列表」据此给房主标星号
		"host_seat": host_seat,
		# 场卡（F1）：【异端裁决所】/【末日预言】/【绝界】这类摆在场上或某人面前的卡
		"field_cards": 场卡快照(viewer_id),
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
	if defender == null:
		return false
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return false
	return GConst.可作反击目标(defender.id, defender.color, dst.id, dst.color, origin_src)


## 这张应战牌是否被本次攻击禁用（攻击 ctx 的「禁应战牌名」＝卡名枚举数组；如 9703 禁【暗灭】）。
## 客户端按同一份名单置灰，这里再复核一次 —— 客户端过滤不能当合法性判据。
func _禁应战(攻击ctx: Dictionary, 应战牌: int) -> bool:
	var 禁: Variant = 攻击ctx.get("禁应战牌名", [])
	if not (禁 is Array):
		return false
	var 名单: Array = 禁 as Array
	if 名单.is_empty():
		return false
	var card: GCard = Data.get_card(应战牌)
	if card == null:
		return false
	return 名单.has(card.card_name_enum())


## 本次攻击「现在」的伤害（含命中时才会生效的自动加伤）：`攻击伤害 = harm.point + 攻击者角色的 p_attack_preview`。
## 所有要显示"这一击会打多少"的地方（应战提示、改伤技能的询问）都从这里取，客户端不再自己叠加角色被动 / 荒神 / 百式。
## 注意：p_attack_preview 只该返回「尚未加进 harm.point 的、必将在命中时加上」的那部分；
## 已经在 harm.point 里的（如荒神之力在 p_before_attack 就加了）不要再返回，否则这里会重复算。
func 攻击预览伤害(ctx: Dictionary) -> int:
	return int(ctx.get("harm", {}).get("point", 0)) + _预告加伤(int(ctx.get("src", -1)), ctx)


## 某个系别的攻击会被「按系别加伤」的被动加多少（如结界师【荒神之力】）。
## 只用于预览还没建立 harm 的虚拟攻击（如魔弓【多重射击】）：
## 正常攻击在 p_before_attack 已经把这份加伤并进 harm.point，不要再调它重复加。
func 攻击元素加伤(元素: int) -> int:
	var 合计: int = 0
	for p: BattlePlayer in players.values():
		if p != null and p.role != null:
			合计 += p.role.p_attack_element_bonus(元素)
	return 合计


## 本次攻击「命中时才会结算」的加伤合计（只用于给被攻击者看提示，不改变实际结算）。
## 问一遍攻击者的角色（p_attack_preview）：如魔剑士【暗影之力】+1、魔枪【暗之解放】+1。
func _预告加伤(src: int, ctx: Dictionary) -> int:
	var 攻击者: BattlePlayer = players.get(src)
	if 攻击者 == null or 攻击者.role == null:
		return 0
	return 攻击者.role.p_attack_preview(ctx)


## 应战提示里的「受到 N 伤害」：本次伤害 + 攻击者预告加伤。
## 加伤全部由服务端算（含狂化这类角色被动），客户端不再自己补，直接显示这个数。
func _应战提示伤害(src: int, ctx: Dictionary, harm: Dictionary) -> int:
	var 预览上下文: Dictionary = ctx.duplicate()
	预览上下文["harm"] = harm
	预览上下文["src"] = src
	return 攻击预览伤害(预览上下文)


# ============================================================
# 牌操作辅助
# ============================================================
func draw(pid: int, n: int) -> Array:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return []
	var cards: Array[int] = deck.draw(n)
	p0.add_hand_cards(cards)
	if not cards.is_empty():
		# 摸牌当场写「获得 N 张牌」：不能等手牌变化边界 —— 技能先把手牌放进盖牌区再摸、
		# 或摸完马上 WAIT 时，手牌数可能净减少 / 边界被跳过，泛化日志就漏了。
		_播手牌日志(p0, "%s 获得 %d 张牌" % [_称号(p0), cards.size()])
		_获得牌已播[pid] = true
	return cards


## 基础效果能不能触发：先看这名角色自己的「禁止基础效果生效」属性（【虚空境】），
## 再依次问所有角色（历史上【绝界】走角色钩子，现在改由属性驱动）。
func 基础效果被禁止(pid: int) -> bool:
	var 本人: BattlePlayer = players.get(pid)
	if 本人 != null and 本人.基础效果禁用:
		return true
	for 座位: int in order:
		var pp: BattlePlayer = players.get(座位)
		if pp == null or pp.role == null:
			continue
		if pp.role.基础效果被禁止(pid):
			return true
	return false


## 因承受伤害摸牌时的「第 1 张改从别处拿」（F8）：依次问所有角色，第一个返回 >= 0 的生效。
## 返回的牌由角色自己从它的来源（如异教徒【末日预言】的【预言】堆）取出，引擎只负责
## 加进摸牌者手里、并且这次少摸 1 张。**同步钩子**：角色实现里不能等待玩家输入。
func 伤害摸牌替换(pid: int) -> int:
	for 座位: int in order:
		var pp: BattlePlayer = players.get(座位)
		if pp == null or pp.role == null:
			continue
		var 牌: int = pp.role.伤害摸牌替换(pid)
		if 牌 >= 0:
			return 牌
	return -1


## 发牌（可被角色响应）：先跑 p_before_draw 钩子（角色可询问该玩家是否发动响应，如暗杀者【水影】），
## 再真正摸牌。钩子与摸牌都排进状态栈，故钩子里可以等待玩家输入。
## 【特殊行动】（购买 / 合成）的摸牌不走这里 —— 技能表里「水影」等响应写明「除【特殊行动】外」。
func push_draw(pid: int, n: int, cause: int = 0) -> void:
	if n <= 0:
		return
	push(SDraw.new(pid, n))
	push(SHook.new("p_before_draw", {"player": pid, "count": n, "cause": cause}, []))


## 强制摸牌的状态版：压一个「摸牌状态」再摸，摸完回到状态边界统一结算手牌 / 盖牌超限。
## 角色在钩子里摸完**还要继续问人**时必须用这条 —— 直接调 强制摸牌() 后 return WAIT 会跳过
## 边界检查（run() 遇到 WAIT 不做 _check_hand_overflow），超限会拖到后面甚至永远不结算。
## after_hook 非空时：摸完（含边界超限结算）再压一个同名钩子，ctx 里带 cards＝本次摸到的牌，
## 供「摸到的牌要参与后续结算」的技能使用（如 7802【魔法入门】亮出摸到的那 1 张）。
func push_强制摸牌(pid: int, n: int, _cause: int = 0, after_hook: String = "", after_ctx: Dictionary = {}) -> void:
	if n <= 0:
		return
	push(S强制摸牌.new(pid, n, after_hook, after_ctx))


## 强制摸牌（F9 / 10601「指定目标对手摸 1 张牌【强制】」、7804 补到手牌 N 张）：
## 直接发牌，不走 p_before_draw（与【特殊行动】的摸牌同口径：不能被「摸牌前发动」的响应改写）。
## 手牌超限由状态边界统一结算。返回实际摸到的牌。
func 强制摸牌(pid: int, n: int, _cause: int = 0) -> Array[int]:
	if n <= 0:
		return []
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return []
	var cards: Array[int] = deck.draw(n)
	p0.add_hand_cards(cards)
	if not cards.is_empty():
		_播手牌日志(p0, "%s 获得 %d 张牌" % [_称号(p0), cards.size()])
		_获得牌已播[pid] = true
		_broadcast_game()
	return cards


## 随机弃掉某玩家手牌 n 张（F9 / 10601「队友随机丢弃你 1 张手牌」）：不经过玩家选牌，
## 从真实手牌里随机抽，离手后进弃牌堆并写弃牌日志。展示=true 时额外走 p_show_hand（公开亮牌）。
## 返回实际弃掉的牌（手牌不足时只弃现有的；n<=0 / 玩家不存在返回空）。
func 随机弃手牌(pid: int, n: int = 1, cause: int = 0, 展示: bool = false) -> Array[int]:
	if n <= 0:
		return []
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return []
	var 候选: Array = p0.hand_cards.duplicate()
	var 选: Array[int] = []
	for _i: int in range(mini(n, 候选.size())):
		var idx: int = _rng.randi_range(0, 候选.size() - 1)
		选.append(int(候选[idx]))
		候选.remove_at(idx)
	if 选.is_empty():
		return 选
	if not take_from_hand(pid, 选, 展示):
		return []
	to_discard(选, {"owner": pid, "source": "hand", "cause": cause, "face_up": 展示})
	_log_discard(pid, 选)
	_broadcast_game()
	return 选


## 把某玩家手牌补 / 弃到「目标张数」（F9 / 7804「将手牌调整为 4 张【强制】」）。
## 不足：压标准摸牌状态（push_draw）补齐 —— 摸完由状态边界统一结算超限；
## 超出且 随机弃牌=true：随机弃；
## 超出且 随机弃牌=false：压入等待状态让牌主自己选弃。
## 返回 true＝压了需要挂起的流程（补牌 / 等牌主选弃，调用方必须返回 URGENT）；false＝当场完成 / 无需调整。
func 调整手牌到(pid: int, 目标张数: int, cause: int = 0, 随机弃牌: bool = false) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null or 目标张数 < 0:
		return false
	var 差: int = p0.hand_cards.size() - 目标张数
	if 差 < 0:
		push_draw(pid, -差, cause)
		return true
	if 差 == 0:
		return false
	if 随机弃牌:
		随机弃手牌(pid, 差, cause)
		return false
	push(SHandAdjust.new(pid, 目标张数, cause))
	return true


## 正在跑「弃牌前拦截」钩子（F6）：钩子内部产生的弃牌（如拦截者支付的代价）不再二次拦截，
## 避免「拦截一张牌又触发一次拦截」的递归与重复询问。
var _弃牌拦截中: bool = false


## 牌进弃牌堆的统一入口（F6 起支持「弃牌前拦截」）。
## ctx 可选：{owner 牌主, source "hand"/"cover"/"other"/"basic", cause 来源, face_up 是否公开}。
## 只有同时满足「引擎正在推进」「有角色 wants_before_discard(ctx) 返回 true」「当前不在拦截钩子里」时，
## 才把这次弃牌推迟成状态：先跑 p_before_discard（可等待玩家），再按 ctx.taker / ctx.taken
## 剔除被认领的牌，其余照常进弃牌堆。否则与原来的同步 push_discard 完全一致。
## 注意：调用方仍应先 take_from_hand / remove_cover_cards（既有路径本来就是这样）；
## 被认领的牌由引擎从原主手里兜底清掉，再加进认领者手牌。
func to_discard(cards: Array, ctx: Dictionary = {}, 允许嵌套: bool = false) -> void:
	if cards.is_empty():
		return
	# 正常路径在拦截钩子执行期间不再二次拦截，避免递归；
	# 但技能在拦截过程中产生的「真实弃牌代价」（如噬神者【共振】弃刃）必须照常拦截，
	# 否则渗蚀不触发、刃会直接进弃牌堆而无法从移除堆取回 —— 这类调用传 允许嵌套=true。
	if phase != Phase.Playing or not _running or (_弃牌拦截中 and not 允许嵌套):
		deck.push_discard(cards)
		return
	var 上下文: Dictionary = {
		"owner": int(ctx.get("owner", -1)),
		"cards": cards.duplicate(),
		"source": str(ctx.get("source", "other")),
		"cause": int(ctx.get("cause", 0)),
		"face_up": bool(ctx.get("face_up", true)),
		"taker": -1,
		"taken": [],
	}
	if not _有弃牌拦截者(上下文):
		deck.push_discard(cards)
		return
	push(SDiscardBeforeHook.new(上下文))


## 某次弃牌有没有角色可能响应（F6）：同步预判，任一角色覆写 wants_before_discard 返回 true 即可。
func _有弃牌拦截者(ctx: Dictionary) -> bool:
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp != null and pp.role != null and pp.role.wants_before_discard(ctx):
			return true
	return false


## 弃牌前拦截钩子跑完之后真正结算（F6）：未被认领的牌进弃牌堆；被认领的牌交给认领者。
func _结算待弃牌(ctx: Dictionary) -> void:
	var 被认领: Array = ctx.get("taken", [])
	# 角色可以把某些牌从这次弃牌里直接移出游戏（如噬神者【渗蚀】把魔刃/异刃移除）
	var 已移除: Array = ctx.get("removed", [])
	var 待弃: Array = []
	for c0: Variant in ctx.get("cards", []):
		var cid0: int = int(c0)
		if 被认领.has(cid0):
			continue
		if 已移除.has(cid0):
			# 「移除」的牌收进移除牌堆（那里才算不在场），不进弃牌堆
			放入移除牌堆(cid0)
			continue
		待弃.append(cid0)
	deck.push_discard(待弃)
	var taker: int = int(ctx.get("taker", -1))
	if taker >= 0 and not 被认领.is_empty():
		var 认领者: BattlePlayer = players.get(taker)
		if 认领者 != null:
			# 正常路径调用 to_discard 前牌已离手；这里兜底清掉原主手里 / 盖牌区里还留着的同名牌
			var 原主: BattlePlayer = players.get(int(ctx.get("owner", -1)))
			if 原主 != null:
				for c1: Variant in 被认领:
					var cid: int = int(c1)
					if 原主.取出实例(原主.hand_cards, cid) < 0:
						原主.取出实例(原主.cover_cards, cid)
			认领者.add_hand_cards(被认领)
			broadcast(GConst.Msg.Gossip, {
				"type": GConst.GossipType.Discard,
				"txt": "%s 在牌进入弃牌堆前获得了 %d 张牌" % [_称号(认领者), 被认领.size()],
				"id": taker,
			})
	_broadcast_game()


## 在某一列牌里认一张「还没被选过」的牌：实例号优先、牌面兜底，返回实际实例号或 -1。
## 弃牌 / 弃盖牌的回复只带牌号（玩家点的是牌面），同一牌面有多份副本时要按份数逐个认；
## 按牌号去重的话，两张同牌面永远只能选出 1 张，另一张会被当成「已经选过」。
func _认一张(列: Array, id: int, 已选: Array) -> int:
	for 实例: Variant in 列:
		if int(实例) == id and not 已选.has(int(实例)):
			return int(实例)
	var 面: int = GConst.牌号(id)
	for 实例2: Variant in 列:
		if GConst.牌号(int(实例2)) == 面 and not 已选.has(int(实例2)):
			return int(实例2)
	return -1


# ============================================================
# 牌库顶（F8 / 9701 · 10803）
# ============================================================
## 从牌库顶移除 n 张（不洗回弃牌堆；牌库不足只返回实际张数）。
## 只改牌库，不展示、不入弃牌堆 —— 调用方按技能需要再调 展示牌库顶 / to_discard。
func 移除牌库顶(张数: int = 1) -> Array[int]:
	if 张数 <= 0:
		return []
	var cards: Array[int] = deck.remove_top(张数)
	if not cards.is_empty():
		_broadcast_game()
	return cards


## 把牌库顶的牌【展示】给全场看（展示牌库顶 / 弃置牌库顶牌类技能用）。
## 只是广播展示，不会移动牌；真正的移除/入弃牌由调用方做。
## 持久=true：客户端一直摆在展示区，直到下一条 Pick / Show（10803 选牌期间不自动收起）。
## 牌库牌不属于手牌 → 走「展示牌」（不触发 p_show_hand 的封印判定）。
func 展示牌库顶(展示者id: int, cards: Array, 持久: bool = false) -> void:
	展示牌(展示者id, cards, 持久)


## 从展示区选走一张牌（10803 剑守誓言）：给全场播一条 Pick，客户端把这张牌从展示位
## 飞向选牌者头像，并收起其余仍摊着的展示牌。牌面已经在展示区公开过，is_real 固定为 true。
## 实例号 0 是合法牌（卡表#0 圣盾），只有负数才代表「没有这张牌」。
func 选走展示牌(玩家id: int, 实例号: int) -> void:
	if 玩家id < 0 or 实例号 < 0:
		return
	broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Pick, "src_id": 玩家id, "dst_id": 玩家id,
		"card_ids": [实例号], "is_real": true,
	})


## 逐张移除牌库顶并逐张展示（9701「持续移除牌库顶牌【展示】」这类用法）。
## 返回实际移除的牌（顺序＝从牌库顶往下）；牌库不足时自然停止，不会把弃牌堆洗回。
func 逐张移除牌库顶(张数: int, 展示者id: int = -1) -> Array[int]:
	var out: Array[int] = []
	if 张数 <= 0:
		return out
	for _i: int in range(张数):
		var cards: Array[int] = 移除牌库顶(1)
		if cards.is_empty():
			break
		if 展示者id >= 0:
			展示牌库顶(展示者id, cards)
		out.append_array(cards)
	return out


## 弃置牌库顶 n 张（不洗回）：逐张移除、可选展示，然后全部进弃牌堆。
## 9701 / 10803 需要「先看牌再决定其中一张的去留」时不要用这个，改用 逐张移除牌库顶 + to_discard。
func 弃置牌库顶(张数: int, 展示者id: int = -1, 展示: bool = true) -> Array[int]:
	var cards: Array[int] = 移除牌库顶(张数)
	if cards.is_empty():
		return cards
	if 展示 and 展示者id >= 0:
		展示牌库顶(展示者id, cards)
	to_discard(cards, {"source": "deck"})
	return cards


## 战斗日志里称呼玩家的统一写法：[职业名]（不带玩家名，和客户端 _称号 一个口径）
func _称号(pp: BattlePlayer) -> String:
	if pp == null:
		return "?"
	return "[%s]" % Data.role_name(pp.role_id)


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
func _log_basic_effect_remove(doer_id: int, dst_id: int, card_id: int, triggered: bool = false) -> void:
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
		# 被移除的牌面 + 是不是「被自身效果触发」：客户端在【圣盾】/【天使之墙】抵挡攻击、魔弹时
		# 补一声圣盾音效（被动抵挡没有出牌消息，只能靠这条日志）。
		"card": GConst.牌号(card_id),
		"triggered": triggered,
	})


## 盖牌变动入口（对照服务端 StateCoverChange）：立刻加/减盖牌并广播，随后对全体跑
## p_cover_change（doer 为本次变动发起者，direction 见 GConst.CHANGE_*）。
## 盖牌超限由状态边界的 _check_cover_overflow 结算。
## 放进盖牌区。open 见 BattlePlayer.记盖牌标记：
## open=true 是「面朝上、牌面公开」的旁置牌（结界师【结界】）。
func add_cover(dst_id: int, cards: Array, src_id: int, cause: int, open: bool = false) -> void:
	var dst: BattlePlayer = players.get(dst_id)
	if dst != null and open:
		for c: Variant in cards:
			dst.记盖牌标记(int(c), open)
	_apply_cover_change(dst_id, GConst.CHANGE_ADD, cards, src_id, cause)
	if dst != null and not cards.is_empty():
		var 盖牌名: String = str(Data.role_token_def(dst.role_id, 2).get("name", "盖牌"))
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Token,
			"txt": "",
			"id": dst_id,
			"res_num": cards.size(),
			"res_name": 盖牌名,
			"res_slot": 2,
		})


func remove_cover(dst_id: int, cards: Array, src_id: int, cause: int) -> void:
	_apply_cover_change(dst_id, GConst.CHANGE_REMOVE, cards, src_id, cause)


## 从牌库顶取 count 张、面朝下放进盖牌区（F3 通用能力：38【精灵赠礼】开局 6 颗【子弹】这类）。
## 与 add_cover 的区别：牌不是从手牌出，而是直接从牌库顶取（走 BattleDeck.draw 的洗回语义）；
## 只放到盖牌槽上限为止（角色没配槽 2 / 已满时返回 0），放不下的牌留在牌库；
## 成功后按普通盖牌变动广播快照并触发 p_cover_change（doer = src_id，cause 由调用方给）。
## 返回实际放进盖牌区的张数。
func draw_cover(pid: int, count: int, src_id: int = -1, cause: int = 0) -> int:
	if count <= 0:
		return 0
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return 0
	var 张数: int = mini(count, p0.cover_space())
	if 张数 <= 0:
		return 0
	var cards: Array[int] = deck.draw(张数)
	if cards.is_empty():
		return 0
	add_cover(pid, cards, src_id, cause)
	return cards.size()


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
	_cover_change_seq += 1
	_盖牌变动待处理 += 1
	push(SHook.new("p_cover_change", {
		"dst": dst_id, "direction": direction,
		"howMany": cards.size(), "cards": cards.duplicate(),
		"doer": src_id, "cause": cause,
		# 本次变动的唯一序号：URGENT 回栈重跑同一钩子时，角色据此只处理一次
		"seq": _cover_change_seq,
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
		# 测试用（战斗界面按 1）：给自己发 4 张【圣光】。
		# 牌库里还有就发牌库里那张，已经全在场就克隆（见 _发一张到手里），所以按几次都不会撞号
		var 圣光候选: Array[int] = []
		for cid: int in range(GConst.CARDSUM):
			var c: GCard = Data.get_card(cid)
			if c != null and c.card_name_enum() == GConst.CardName.HolyLight:
				圣光候选.append(cid)
		圣光候选.shuffle()
		for i: int in range(mini(4, 圣光候选.size())):
			_发一张到手里(p0, 圣光候选[i])
	elif kind == GConst.DebugKey.SkillCards:
		# 角色自己的技能 + 借用 / 视为自己拥有的独有技（统一读 GConst.角色借用独有技）：
		# 测试 EX魔弓 / 剑之子 时按 2，也能拿到神箭手 301/302、剑圣 101/102 的发动牌。
		var 技能表: Array[int] = []
		for 技能号: Variant in Data.role_skills(p0.role_id):
			技能表.append(int(技能号))
		for 技能号: int in GConst.借用独有技(p0.role_id):
			if not 技能表.has(技能号):
				技能表.append(技能号)
		for 技能号: int in 技能表:
			var 候选: Array[int] = []
			for cid: int in range(GConst.CARDSUM):
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
			to_discard(p0.hand_cards.duplicate(), {"owner": p0.id, "source": "hand"})
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
		# 测试用（战斗界面按 6）：自己的标识物（指示物）拉满 + 盖牌填满 ↔ 再按清空
		var 已有值: bool = not p0.cover_cards.is_empty()
		for t: Variant in p0.tokens:
			if t != null and int((t as Dictionary).get("num", 0)) > 0:
				已有值 = true
				break
		for t2: Variant in p0.tokens:
			if t2 == null:
				continue
			var 槽2: Dictionary = t2
			槽2["num"] = 0 if 已有值 else int(槽2.get("max", 0))
		if 已有值:
			var 盖们: Array = p0.cover_cards.duplicate()
			if not 盖们.is_empty():
				remove_cover(p0.id, 盖们, p0.id, 0)
		else:
			var 张数: int = p0.cover_space()
			if 张数 > 0:
				var 牌们: Array[int] = deck.draw(张数)
				if not 牌们.is_empty():
					add_cover(p0.id, 牌们, p0.id, 0)
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


## 测试发牌：把一张【cid 这个牌面】的牌加进手里。
## 牌库 / 弃牌堆里还有这张实体，就直接拿那一份（实例号就是牌号）；
## 已经全部在场时克隆一份新的实例号（序号*实例步长 + 牌号，见 GConst.实例号）——
## 克隆牌的身份唯一，客户端按实例号选中/渲染，不会再出现「点一张、好几张一起亮」。
func _发一张到手里(p0: BattlePlayer, cid: int) -> void:
	var 面: int = GConst.牌号(cid)
	var 实例: int = deck.取出实例(面)
	if 实例 < 0:
		实例 = _新克隆实例(面)
	p0.add_hand_cards([实例])


## 给调试克隆牌找一个还没被占用的实例号（序号从 1 起）
func _新克隆实例(面: int) -> int:
	var 序号: int = 1
	while _实例在场(GConst.实例号(面, 序号)):
		序号 += 1
	return GConst.实例号(面, 序号)


## 这个实例号现在是不是已经在某个区域里（手牌 / 盖牌 / 牌堆 / 弃牌堆）
func _实例在场(实例: int) -> bool:
	for 玩家: BattlePlayer in players.values():
		if 玩家.hand_cards.has(实例) or 玩家.cover_cards.has(实例):
			return true
	return deck.pile.has(实例) or deck.discard.has(实例)


## 测试发牌：给某玩家发 count 张牌。
## 要攻击 = true 发攻击牌（斩）、false 发法术牌；同系 = true 这 count 张要同一种系别，
## false 则要互不相同的系别。候选不再排除手里的牌 —— 同牌面可以克隆（见 _发一张到手里）。
func _发测试牌(p0: BattlePlayer, count: int, 要攻击: bool, 同系: bool) -> void:
	# 测试指令 3 不把牌发到手牌上限以上：按当前空位截断
	count = mini(count, maxi(p0.hand_cards_max - p0.hand_cards.size(), 0))
	if count <= 0:
		return
	var 分组: Dictionary = {}
	for cid: int in range(GConst.CARDSUM):
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
		# 命格来源：攻击牌被「视为」换掉牌面时，命格仍按真正打出的那张牌算（没设就是 card_id 本身）
		"fate_card_id": int(harm.get("fate_card_id", -1)),
		"is_active": bool(harm.get("is_active", true)),
	}


## 最近一次伤害的来源/类型（供「因伤害掉士气」类技能判定）
var last_harm_cause: int = 0
var last_harm_type: int = 0


## 伤害流水线入口：执行顺序（pop 顺序）3 → 钩子3 → 钩子4 → 治疗询问 → 钩子5 → 钩子6 → 摸牌 → 钩子6drawn → 伤害结束 → 手牌超限
func push_harm(harm: Dictionary) -> void:
	# 通用口径：**攻击**类伤害如果没有「真正打出去的那张实体牌」（harm 里没有 card_id_instance），
	# 它就是用虚拟牌打出的攻击（欺诈 / 多重射击 / 圣屑飓暴这类手拼 harm 的），一律标成无命格，
	# 不参与「同命格」判定（阴阳师【阴阳转换】/【式神咒束】等）；真实牌的攻击由引擎或角色填了
	# card_id_instance，不受这条影响（要「无命格」仍可自己显式标 virtual_no_fate）。
	if int(harm.get("type", GConst.HarmType.None)) == GConst.HarmType.Attack \
			and not harm.has("card_id_instance"):
		harm["virtual_no_fate"] = true
	last_harm_cause = int(harm.get("cause", 0))
	last_harm_type = int(harm.get("type", GConst.HarmType.None))
	var hc: Dictionary = harm_ctx(harm)
	# 手牌超限不在这里压：原版是在「摸牌」那一拍结算（StateTimeline6 → 移动牌 → setStateHandOverLoad），
	# 引擎每跑完一个状态都会调 _check_hand_overflow()，摸完牌就会补上。
	# p_harm_end 的 ctx 不在这里构造：⑥ 伤害转移可能在 p_timeline_6 里改掉 harm["dst"]，
	# 交给 SHookHarmEnd 在钩子真正触发时按 harm 现算，伤害结束钩子才看得到最终目标。
	push(SHookHarmEnd.new(harm))
	# 对照原版：Timeline5 跑完才决定要不要进 Timeline6（伤害被治疗抵成 0 点时整串不跑）
	push(SGateTimeline6.new(harm))
	push(SHook.new("p_timeline_5", hc, []))
	push(SAskCross.new(harm))
	push(SHook.new("p_timeline_4", hc, []))
	# 先跑③的改伤钩子，再广播受伤飘字 / 伤害事件：③（神弃之裔、狂戾形态、念气力场、圣炎抵御…）
	# 会改 harm 的点数，飘字若抢先发出去，界面就会「飘 2 实际打 3」。
	# 顺序仍是「飘字 → 伤害事件 → 治疗抵御」，只是把③挪到飘字之前。
	push(SHarmTimeline3.new(harm))
	push(SHook.new("p_timeline_3", hc, []))


## ⑥ 伤害转移（F6 / 4702）：把 harm 的承受者改成新目标，并声明这次伤害不因手牌超限掉士气。
## 只能在 p_timeline_6 内调用：此时治疗回应已结算完（新目标不再有治疗回应），按点数摸牌还没开始，
## 之后的摸牌 / 手牌超限都直接读 harm["dst"]；p_timeline_6_drawn 与 p_harm_end 的 ctx 由
## SHookTimeline6Drawn / SHookHarmEnd 在钩子触发时按 harm 现算，ctx.dst 同样是转移后的新目标
## （所以 501 反噬 / 802 智慧法典 / 幻影形态收尾 / 沉沦协奏曲这类按 ctx.dst 判断的角色会自动跟到新目标）。
## 注意：只有同一次 p_timeline_6 钩子轮次里，后问到的角色拿到的 ctx.dst 还是本轮开始时的快照；
## 那一轮里要看最新目标请读 ctx.harm["dst"]（与 47 / 月女这类改 harm 的既有写法一致）。
## 「免士气」只作用于这次伤害带来的手牌超限（超限牌照弃、不扣士气），之后别的伤害 / 普通超限照旧；
## 标志随这次伤害的超限结算一起消费，不做全局开关。返回 GConst.GE_*（新目标不存在时为 GE_INVALID_PLAYERID）。
func 转移伤害(harm: Dictionary, 新目标id: int, 免士气: bool = true) -> int:
	var 新目标: BattlePlayer = players.get(新目标id)
	if 新目标 == null:
		return GConst.GE_INVALID_PLAYERID
	var 原目标id: int = int(harm.get("dst", -1))
	if 原目标id != 新目标id:
		harm["dst"] = 新目标id
		harm["redirect_from"] = 原目标id
		var 原目标: BattlePlayer = players.get(原目标id)
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Combat,
			"txt": "%s 将本次伤害转移给 %s" % [_称号(原目标), _称号(新目标)],
			"id": 新目标id,
		})
	if 免士气:
		harm["no_morale"] = true
	else:
		harm.erase("no_morale")
	_broadcast_game()
	return GConst.GE_SUCCESS


## 攻击/法术/特殊行动收尾：先跑具体的「行动结束」钩子与通用 p_action_end，再进入回合结束。
## 「是不是额外行动 / 来源」取当前行动阶段的状态（见 action_commands 的 is_extra / extra_cause）
## 技能出牌（技能出牌()）时**不压回合结束**：那次出牌是技能效果的一部分，回合还没结束；
## 同时把行动结束响应整组延后到 p_action_end 之后 —— 真言术这种「行动结束后还有第二段」的技能，
## 必须先结算完第二段，再问妖精秘术 / 真言压制这些响应。
func push_after_action(hook: String, ctx: Dictionary) -> void:
	if _技能出牌中:
		if 技能出牌不开响应:
			# 只压 p_action_end（技能自己的收尾 / 第二段），不开行动结束响应：
			# 外层那次响应的「待决」会在本段结算完后继续收集剩余选项，不再套一层
			var 上下文: Dictionary = ctx.duplicate()
			var cur2: BattlePlayer = players.get(int(上下文.get("player", current_id)))
			if cur2 != null:
				上下文["is_extra"] = 行动额外
				上下文["extra_cause"] = 行动额外来源 if 行动额外 else 0
				上下文["action_count"] = cur2.action_count()
				上下文["attack_action_count"] = cur2.attack_action_count
				上下文["magic_action_count"] = cur2.magic_action_count
				上下文["special_action_count"] = cur2.special_action_count
				上下文["extra_action_count"] = cur2.extra_action_count
			push(SHook.new("p_action_end", 上下文, []))
			return
		_push_action_end_hooks(hook, ctx, 行动额外, 行动额外来源 if 行动额外 else 0, true)
		return
	push(STurnEnd.new())
	_push_action_end_hooks(hook, ctx, 行动额外, 行动额外来源 if 行动额外 else 0)


## 记一次行动并压「行动结束」钩子（F2）：直接行动（攻击 / 法术 / 特殊）在确认会结算时调用，
## 计数按当前行动阶段是否额外行动来记。角色自己的技能行动由 SkillRun 记（它要等校验通过）。
func _记录行动并收尾(cur: BattlePlayer, kind: String, hook: String, ctx: Dictionary) -> void:
	var 上下文: Dictionary = ctx.duplicate()
	上下文["kind"] = kind
	cur.record_action(kind, 行动额外)
	push_after_action(hook, 上下文)


## 技能出牌（真言术：把 1 个【言灵】当手牌用掉）：在技能本体里直接把一张牌当行动打出去。
## 和普通行动的区别：
##   · 不进行动阶段（玩家不会再被问一次「要出哪张牌」）；
##   · 记成**额外行动**，不消耗本次攻击 / 法术行动计数（技能本身已经消耗了行动）；
##   · 不压回合结束（STurnEnd），由外层技能收尾。
## 走的是引擎原生的 _do_attack / _do_magic，所以「视为 / 应战 / 命中 / 伤害 / 行动结束响应」全部照常。
## 返回引擎的 CONTINUE / WAIT（调用方拿到后应返回 URGENT 等它跑完）；
## 牌 / 目标不合法时返回 GConst.GE_*（这时什么都没压栈，调用方自己报错 / 重问）。
func 技能出牌(pid: int, action_type: int, card_ids: Array, dst_ids: Array, cause: int) -> int:
	var cur: BattlePlayer = players.get(pid)
	if cur == null or card_ids.is_empty():
		return GConst.GE_INVALID_ACTION
	# 先按原生校验过一遍：不合法就原样退回，让角色自己报错重问（不能走 _do_attack 的驳回路径，
	# 那会把玩家退回普通行动阶段）
	if action_type == GConst.ActionType.Attack:
		var 目标: BattlePlayer = players.get(int(dst_ids[0]) if not dst_ids.is_empty() else -1)
		if 目标 == null or cur.v_attack(int(card_ids[0]), 目标.id, players) != GConst.GE_SUCCESS \
				or 目标.v_attacked() != GConst.GE_SUCCESS:
			return GConst.GE_INVALID_ACTION
	var 原额外: bool = 行动额外
	var 原来源: int = 行动额外来源
	var 原数据: Dictionary = 当前额外行动数据
	行动额外 = true
	行动额外来源 = cause
	当前额外行动数据 = {}
	_技能出牌中 = true
	var 数据: Dictionary = {"action_type": action_type, "card_ids": card_ids, "dst_ids": dst_ids}
	var 结果: int = _do_attack(cur, 数据) if action_type == GConst.ActionType.Attack else _do_magic(cur, 数据)
	_技能出牌中 = false
	技能出牌不开响应 = false
	行动额外 = 原额外
	行动额外来源 = 原来源
	当前额外行动数据 = 原数据
	return 结果


## 一次行动结束的两个钩子（F2）：先跑具体的 p_after_attack / p_after_magic / p_after_special，
## 再跑通用的 p_action_end；两者收到同一份带本回合行动计数的上下文。
## STurnEnd 由调用方压（普通行动见 push_after_action；技能行动在 _进入技能行动 里提前压）。
## 行动结束钩子组。延后响应=true（技能出牌＝技能效果里打出的一张牌，见 技能出牌）：
## 把「行动结束响应」整组压到 p_action_end 之下 —— LIFO 下 p_action_end 先跑，
## 等技能把「行动结束之后还有第二段」的结算（真言术的 1 点法术伤害）做完，才问聚合器里的响应。
func _push_action_end_hooks(hook: String, ctx: Dictionary, is_extra: bool,
		extra_cause: int, 延后响应: bool = false) -> void:
	var 上下文: Dictionary = ctx.duplicate()
	var cur: BattlePlayer = players.get(int(上下文.get("player", current_id)))
	if cur != null:
		上下文["is_extra"] = is_extra
		上下文["extra_cause"] = extra_cause if is_extra else 0
		上下文["action_count"] = cur.action_count()
		上下文["attack_action_count"] = cur.attack_action_count
		上下文["magic_action_count"] = cur.magic_action_count
		上下文["special_action_count"] = cur.special_action_count
		上下文["extra_action_count"] = cur.extra_action_count
	# 响应组（先压 → 后跑）
	var 响应组: Array = []
	if hook == "p_after_attack" or hook == "p_after_magic":
		# 行动聚合器：只聚合当前时点可执行的行动选项
		响应组.append(S行动聚合器.new(上下文))
	响应组.append(SHook.new(hook, 上下文, []))
	# 最高优先级行动结束结算（如格斗家念弹）：必须排在普通行动结束响应之前
	if hook == "p_after_magic" and cur != null and cur.role != null and cur.role.has_priority_action_end():
		响应组.append(SHook.new("p_priority_action_end", 上下文, []))
	if 延后响应:
		for 状态: Variant in 响应组:
			push(状态)
		push(SHook.new("p_action_end", 上下文, []))
		return
	push(SHook.new("p_action_end", 上下文, []))
	for 状态2: Variant in 响应组:
		push(状态2)


## 额外行动的单份行动"可用牌"白名单：技能直接给的 id 表优先；没给 id 表但给了
## 系别 / 命格规则时，按规则现算（对照卡库，不看当前手牌快照）。
## 为什么不能拿手牌快照：手牌会变。技能授予时算一次 id 表，等玩家再摸到同类牌就出不了了
## （修罗连斩 / 风怒追击 / 二重剑影 的「该系攻击牌」、技之剑意的「技类攻击牌」都踩过）。
func 额外行动出牌白名单(行动: Dictionary, pid: int = -1) -> Array:
	if 行动.is_empty():
		return []
	var 表: Array = 行动.get("cards", [])
	if not 表.is_empty():
		return 表
	var 系: int = int(行动.get("element", 0))
	var 命格: int = int(行动.get("card_fate", 0))
	if 系 <= 0 and 命格 <= 0:
		return []
	return _规则攻击牌(系, 命格, pid)


## 卡库里符合「该系 / 该命格」的全部攻击牌 id（按规则缓存一次）：
## 界面据此点亮可出的牌，服务端据此校验。一张都没有时给「全禁」哨兵，
## 避免空表被当成「不限制」。系别与命格都为 0 时按「不限」处理（调用方已挡掉）。
func _规则攻击牌(系: int, 命格: int, pid: int = -1) -> Array:
	# 普通牌按牌面缓存；魔刃/异刃要按「该玩家手里的实例当前系别」临时补进来，
	# 不能把 1005/1006 写进全局缓存（多个噬神者各切各的系）。
	var 键: String = "%d_%d" % [系, 命格]
	var 基础: Array
	if _规则攻击牌缓存.has(键):
		基础 = _规则攻击牌缓存[键]
	else:
		基础 = []
		for c: GCard in Data.card_db:
			if c == null or not c.is_attack():
				continue
			if c.id == GConst.噬神者_魔刃卡 or c.id == GConst.噬神者_异刃卡:
				continue
			# 没有系别的虚拟牌（借用/欺诈临时牌）不进「该系攻击牌」白名单
			if c.is_virtual and c.element_enum() <= 0:
				continue
			if 系 > 0 and c.element_enum() != 系:
				continue
			if 命格 > 0 and c.fate_pattern_enum() != 命格:
				continue
			基础.append(c.id)
		_规则攻击牌缓存[键] = 基础
	var 表: Array = 基础.duplicate()
	# 玩家号 0 是合法座位（不是「没有玩家」），默认值用 -1
	if pid >= 0:
		var p0: BattlePlayer = players.get(pid)
		if p0 != null:
			# 手里「有效系别 / 命格」符合的牌面也要放行：
			#   · 魔刃 / 异刃按**实例**当前系别（同一张牌面在不同人手里系别不同）；
			#   · 被卡牌系别属性改过系别的普通牌（如苍炎魔女【烈焰形态】把攻击牌视为火）也按改后的系别算 ——
			#     否则「只能用火系攻击牌」这种额外行动会把她手里被视作火的斩驳回。
			for cid: int in p0.hand_cards:
				var 面: int = GConst.牌号(cid)
				if 表.has(面):
					continue
				var 实例卡: GCard = Data.get_card(cid)
				if 实例卡 == null or not 实例卡.is_attack():
					continue
				if 系 > 0 and 实例卡.element_enum() != 系:
					continue
				if 命格 > 0 and 实例卡.fate_pattern_enum() != 命格:
					continue
				表.append(面)
	else:
		# 旧调用（无玩家上下文，测试/兜底）：按共用牌面当前系别补
		for 面2: int in [GConst.噬神者_魔刃卡, GConst.噬神者_异刃卡]:
			if 表.has(面2):
				continue
			var 面卡2: GCard = Data.get_card(面2)
			if 面卡2 != null and (系 <= 0 or 面卡2.element_enum() == 系) \
					and (命格 <= 0 or 面卡2.fate_pattern_enum() == 命格):
				表.append(面2)
	if 表.is_empty():
		表 = [GConst.手牌白名单_全禁]
	return 表


## 攻击牌的「表现牌」：魔刃/异刃是真实攻击牌，但没有自己的斩击特效预制体，
## 按当前系别借一张普通斩击牌作为 Card.as_card_id，客户端据此播对应系别的音效/特效；
## 规则结算、摊牌、日志仍用原牌。
func 攻击表现牌(card_id: int) -> int:
	var 卡: GCard = Data.get_card(card_id)
	if 卡 == null or not 卡.is_attack():
		return card_id
	var 是刃: bool = 卡.id == GConst.噬神者_魔刃卡 or 卡.id == GConst.噬神者_异刃卡
	# 普通攻击牌的「有效系别」被卡牌系别属性改过（如苍炎魔女【烈焰形态】视为火）时，
	# 表现也要按改后的系别走：否则客户端会按牌面自己的系别播斩击特效 / 音效。
	if not 是刃 and 卡.element_enum() == 卡.基础元素():
		return card_id
	var 表现: int = int(GConst.元素斩击表现牌.get(卡.element_enum(), 0))
	return 表现 if 表现 > 0 else card_id


## 「启动」能不能发动：它是一次免费动作，但只能在本回合**第一个行动之前**执行。
## 已经做过攻击 / 法术 / 特殊行动（含额外行动）之后就不能再启动；
## 额外行动阶段同样不行（那一阶段是消耗已获得的行动，不是本回合的第一个行动）。
func 可发动启动(pid: int) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return false
	if 行动额外:
		return false
	return p0.action_count() == 0


## 本回合的行动计数（只读查询，F2）：供角色 / 头像提示 / 测试读取
func 行动计数(pid: int) -> Dictionary:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return {}
	return {
		"action_count": p0.action_count(),
		"attack_action_count": p0.attack_action_count,
		"magic_action_count": p0.magic_action_count,
		"special_action_count": p0.special_action_count,
		"extra_action_count": p0.extra_action_count,
	}


## 额外行动的出牌 / 目标限制校验（F2）：本次若是某份额外行动，牌与目标必须落在**这份行动自己的规格**里
## （BattlePlayer.add_action 的 spec.cards / spec.targets；空表＝不限制，[-1] 哨兵＝全禁）。
## 只给了系别、没给 id 白名单的行动（如「只能用火系攻击牌」）按系别规则算，见 额外行动出牌白名单。
## 技能行动（技能栏里的招式，如 10703 魔弹融合）读 spec.skill_cards，缺省沿用 cards：
## 同一份额外行动里，普通出牌与技能招式可用的牌不一定是同一批。
func 校验额外行动限制(cur: BattlePlayer, 行动: Dictionary, action_type: int,
		card_ids: Array, dst_ids: Array, is_skill: bool = false, 视为系别: int = 0) -> int:
	if cur == null or 行动.is_empty():
		return GConst.GE_SUCCESS
	if not GConst.放行动作(action_type, int(行动.get("allow_action", action_type))):
		return GConst.GE_INVALID_ACTION
	var 白名单: Array
	var 显式牌表: Array = 行动.get("cards", [])
	var 行动系: int = int(行动.get("element", 0))
	var 行动命格: int = int(行动.get("card_fate", 0))
	# 技能把这次出牌视为某系（如 3805 精灵的剑舞 = 风）：按「视为后的系别」过规则，
	# 不能整段跳过 —— 额外行动要求暗系时，把牌变成风系打出去仍然违规（3803 踩过）。
	# 只有规则型白名单（系别 / 命格）才按视为算；显式 cards 名单 / skill_cards 仍按真实牌面。
	var 按视为: bool = is_skill and 视为系别 > 0 and not 行动.has("skill_cards") and 显式牌表.is_empty()
	if is_skill and 行动.has("skill_cards"):
		白名单 = 行动.get("skill_cards", [])
	else:
		白名单 = 额外行动出牌白名单(行动, cur.id)
	for c: Variant in card_ids:
		# 提交上来的是实例号，规格里的白名单是牌面：比较前先折回牌面（克隆牌也按同一张牌面算）
		var 面: int = GConst.牌号(int(c))
		if 按视为:
			var 卡: GCard = Data.get_card(面)
			if 卡 == null or not 卡.is_attack():
				return GConst.GE_INVALID_CARDID
			if 行动系 > 0 and 视为系别 != 行动系:
				return GConst.GE_INVALID_CARDID
			if 行动命格 > 0 and 卡.fate_pattern_enum() != 行动命格:
				return GConst.GE_INVALID_CARDID
			continue
		if not 按视为 and 行动系 > 0 \
				and (面 == GConst.噬神者_魔刃卡 or 面 == GConst.噬神者_异刃卡):
			var 实例卡: GCard = Data.get_card(int(c))
			if 实例卡 == null or 实例卡.element_enum() != 行动系:
				return GConst.GE_INVALID_CARDID
		if not 白名单.is_empty() and not 白名单.has(面):
			return GConst.GE_INVALID_CARDID
	var 目标表: Array = 行动.get("targets", [])
	if not 目标表.is_empty():
		for d: Variant in dst_ids:
			if not 目标表.has(int(d)):
				return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 技能行动的「基础效果目标资格」校验（F4 / 4601）：角色用 BattleRole.basic_effect_placements
## 声明这次会把哪张牌放到谁面前，这里逐条问目标角色 v_basic_effect_target；任一被拒即驳回技能行动。
## 角色没声明（默认空）＝这次技能不放置基础效果，不校验。
## 引擎内部（圣盾 / 虚弱 / 中毒）在 _do_magic 里另有一道同口径校验；add_basic_effect 是最后兜底。
func 校验基础效果放置目标(action: Dictionary) -> bool:
	var cur: BattlePlayer = players.get(current_id)
	if cur == null or cur.role == null:
		return true
	for 项: Variant in cur.role.basic_effect_placements(action):
		if not (项 is Dictionary):
			continue
		var 表: Dictionary = 项
		var dst_id: int = int(表.get("dst", -1))
		var card_id: int = int(表.get("card", -1))
		if dst_id < 0 or card_id < 0:
			continue
		if v_basic_effect_target(dst_id, card_id) != GConst.GE_SUCCESS:
			return false
	return true


## 出牌/展示牌后触发 p_show_hand 钩子（封印类技能依赖）。
## 格挡攻击=true：本次展示是「用牌格挡攻击」（应战抵挡，见 SAttackedAsk 的 Block 分支），
## 供需要区分「抵挡攻击」与其它公开打牌（如抵挡魔弹 / 弃牌展示）的角色判定（如圣女冰霜祷言）
func push_show_hand(pid: int, cards: Array, show_only: bool = false, 格挡攻击: bool = false) -> void:
	push(SHook.new("p_show_hand", {"player": pid, "cards": cards, "show_only": show_only, "格挡攻击": 格挡攻击}, []))


# ============================================================
# 公开亮牌：全工程唯一入口
# ------------------------------------------------------------
# 「牌面被别人看到」只有这三种情况，角色脚本不要再手写 broadcast(Card.Show)：
#   展示牌    —— 牌不是从这个人的手里拿出来的（牌库顶 / 盖牌区 / 弃牌堆 / 场上）
#   展示手牌  —— 牌是从他手里公开亮出来的（打出 / 展示 / 公开弃牌）
#                → 客户端摊牌 + p_show_hand 钩子（封印师的五系封印靠它结算）
#   私下看牌  —— 只发给本人看（查看类技能），不广播、也不触发钩子
# 需要「亮完顺手把牌移走」时用下面两个封装（顺序固定：亮 → 离手 → 进区域）：
#   展示手牌并弃     —— 手牌 → 弃牌堆（已亮过，不再播弃牌特效，只写文字日志）
#   展示手牌进盖牌   —— 手牌 → 面朝上盖牌区（【言灵】/【遗迹】这类）
# 时机：钩子是「压栈」，谁先压谁后跑由调用顺序决定。想让展示响应排在后面的结算之前，
# 就把 展示手牌 放在那几处 push 之后再调（如「先 push_强制摸牌，再展示手牌」＝先结算封印再摸牌）。
# ============================================================
## 亮出牌面（只广播给全场，不触发 p_show_hand）：牌源不是手牌时用
func 展示牌(pid: int, cards: Array, 持久: bool = false) -> void:
	if cards.is_empty():
		return
	var 数据: Dictionary = {
		"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
		"card_ids": _牌面表(cards), "is_real": true,
	}
	if 持久:
		数据["persist"] = true
	broadcast(GConst.Msg.Card, 数据)
	_broadcast_game()


## 公开亮出手牌：客户端摊牌 + 触发 p_show_hand（封印类技能的触发点）
func 展示手牌(pid: int, cards: Array) -> void:
	if cards.is_empty():
		return
	展示牌(pid, cards)
	push_show_hand(pid, cards)


## 只给本人看（查看类技能）：不广播、不触发 p_show_hand
func 私下看牌(pid: int, cards: Array) -> void:
	if cards.is_empty():
		return
	send(pid, GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
		"card_ids": _牌面表(cards), "is_real": true,
	})


## 亮出手牌并弃掉（返回实际离手的实例号）。ctx 与 to_discard 同形，owner/source 由这里补。
func 展示手牌并弃(pid: int, cards: Array, ctx: Dictionary = {}) -> Array:
	var 实际: Array = []
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return 实际
	for c: Variant in cards:
		var 实例: int = p0.手牌实例(int(c))
		if 实例 >= 0 and not 实际.has(实例):
			实际.append(实例)
	if 实际.is_empty():
		return 实际
	展示手牌(pid, 实际)
	take_from_hand(pid, 实际)
	var 上下文: Dictionary = ctx.duplicate()
	上下文["owner"] = pid
	上下文["source"] = "hand"
	to_discard(实际, 上下文)
	_log_discard(pid, 实际, false)
	return 实际


## 亮出手牌并面朝上放进盖牌区（【言灵】/【遗迹】这类；返回实际离手的实例号）
func 展示手牌进盖牌(pid: int, cards: Array, cause: int) -> Array:
	var 实际: Array = []
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return 实际
	for c: Variant in cards:
		var 实例: int = p0.手牌实例(int(c))
		if 实例 >= 0 and not 实际.has(实例):
			实际.append(实例)
	if 实际.is_empty():
		return 实际
	展示手牌(pid, 实际)
	take_from_hand(pid, 实际)
	add_cover(pid, 实际, pid, cause, true)
	return 实际


## 目标资格校验（F4 / 4601）：dst 能不能被放上这张基础效果（由目标角色判定，默认成功）。
## 角色 / 技能在「将要放基础效果」前先调它，客户端的目标列表也按同一口径过滤；
## add_basic_effect 里还有一道兜底：目标拒绝时不挂效果。
func v_basic_effect_target(dst_id: int, card_id: int) -> int:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	return dst.v_basic_effect_target(card_id)


## 增删基础效果（会触发 p_basic_effect_change 钩子）；角色应优先用这两个方法。
## 放置前统一问目标角色 v_basic_effect_target（F4 / 4601）：被拒时不挂效果并返回该错误码，
## 调用方应把它当「非法目标」处理（各条正常施放路径已在上游先校验，这里是最后一道兜底）。
func add_basic_effect(dst_id: int, card_id: int, src_id: int, cause: int = 0) -> int:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	var 资格: int = dst.v_basic_effect_target(card_id)
	if 资格 != GConst.GE_SUCCESS:
		return 资格
	dst.add_basic_effect(card_id, src_id)
	push(SHook.new("p_basic_effect_change", {
		"dst": dst_id, "card": card_id, "doer": src_id, "cause": cause, "add": true,
		"triggered": false,
	}, []))
	return GConst.GE_SUCCESS


## 移除基础效果；src_id 记发动者（对照服务端 doerID，无人负责的引擎内部移除传 -1）。
## 天使羁绊要靠它区分「哪个天使移除的」，不能让场上所有天使都触发。
## triggered = true：这次移除是「基础效果被自身效果触发」（圣盾抵挡、中毒结算、封印 / 赐福被消耗…）。
## 除了 p_basic_effect_change（ctx 里带 triggered=true），还会压 p_basic_effect_triggered（F4 / 4604），
## 后者压得更低：调用方接着压入的伤害 / 结算状态先跑完，钩子才执行 —— 满足「触发并结算完成后」。
## 不显式传时也认「触发」的常见写法：cause 就是这张牌自己带的技能号（封印 401~405、赐福 1601~1602
## 的现有触发点就是这么移除的），免得每个调用点都改一遍。
func remove_basic_effect(dst_id: int, card_id: int, cause: int = 0, src_id: int = -1, triggered: bool = false) -> void:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return
	var 在场上: bool = false
	for be: Dictionary in dst.basic_effects:
		if int(be["card"]) == card_id:
			在场上 = true
			break
	dst.remove_basic_effect(card_id)
	var 触发: bool = 在场上 and (triggered or _是基础效果自身触发(card_id, cause)) 			and not 基础效果被禁止(dst_id)
	_log_basic_effect_remove(src_id, dst_id, card_id, 触发)
	if 触发:
		# 先压 triggered、再压 change：LIFO 下 change 先跑、triggered 后跑，
		# 让「变动」先通知完，再由 triggered 表示「这次触发已经结算完成」
		push(SHook.new("p_basic_effect_triggered", {
			"dst": dst_id, "card": card_id, "doer": src_id, "cause": cause,
		}, []))
	push(SHook.new("p_basic_effect_change", {
		"dst": dst_id, "card": card_id, "doer": src_id, "cause": cause, "add": false,
		"triggered": 触发,
	}, []))


## 这次移除算不算「基础效果被自身效果触发」：cause 就是这张牌自己带的技能号
## （封印 401~405 / 迅捷·威力赐福 1601~1602 的触发点都这么调 remove_basic_effect）。
## 圣盾 / 虚弱 / 中毒这类牌上没有技能号，由引擎的结算点显式传 triggered=true。
func _是基础效果自身触发(card_id: int, cause: int) -> bool:
	if cause <= 0:
		return false
	var 牌: GCard = Data.get_card(card_id)
	return 牌 != null and 牌.has_skill_id(cause)


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
				# 角色在钩子里放了/移了盖牌：立即让出执行权，先跑 p_cover_change，
				# 回来再从下一个角色继续；否则要等整轮 SHook 跑完才结算
				if e._盖牌变动待处理 > 0 and hook != "p_cover_change":
					_iter += 1
					return BattleEngine.SUSPEND
			_iter += 1
		if hook == "p_cover_change" and e._盖牌变动待处理 > 0:
			e._盖牌变动待处理 -= 1
		# after[0] 应先执行，故逆序压栈
		for i: int in range(after.size() - 1, -1, -1):
			e.push(after[i])
		return BattleEngine.CONTINUE


## 回合开始：清额外行动、处理中毒、处理虚弱，最后进入行动阶段
class SCheckTurnStart:
	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		cur.clear_additional_action()
		cur.跳过额外攻击行动 = false
		e._基础效果额外行动已确认.clear()
		# F2 行动计数：新回合从零开始记（攻击 / 法术 / 特殊 / 额外）
		cur.reset_action_counts()
		# 「启动」技能每回合只能发动一个：新回合开始清零
		cur.boot_skill_used = false
		# 回合级标记「本回合下次主动攻击只能打谁」：新回合重来（正常在攻击打出时就消费掉了，
		# 没打出去（放弃行动 / 回合被跳过）也不带到下一回合）
		cur.set_attack_lock(-1)
		e.skip_action_phase = false
		e.跳过行动阶段来源 = 0
		e.本回合跳过行动阶段 = false
		e.本回合跳过行动阶段来源 = 0
		var poison_cards: Array[int] = []
		if not cur.基础效果禁用:
			for be: Dictionary in cur.basic_effects:
				var c: GCard = Data.get_card(int(be["card"]))
				if c != null and c.card_name_enum() == GConst.CardName.Poison:
					poison_cards.append(int(be["card"]))
		e.push(SActionPhase.new())
		# F7：额外回合与普通回合走同一套开始流程，只是上下文里带 extra_turn 标记（角色可区分）
		var 回合上下文: Dictionary = {
			"player": e.current_id,
			"extra_turn": e.当前额外回合玩家 == e.current_id,
			"attack_bonus": e.当前额外回合攻击加伤,
		}
		# 行动阶段之前的钩子顺序对照服务端 setStateCheckBasicEffect：
		#   中毒 → （虚弱询问）→ p_between_weak_and_action → p_before_action → p_boot → 行动阶段
		# 后压先执行，故这里按「行动阶段 → boot → before_action → between」的顺序压
		e.push(SHook.new("p_boot", 回合上下文, []))
		e.push(SHook.new("p_before_action", 回合上下文, []))
		e.push(SHook.new("p_between_weak_and_action", 回合上下文, []))
		e.push(SWeaken.new())
		if not poison_cards.is_empty():
			e.push(SPoison.new(poison_cards))
		# 回合开始钩子（先执行，后压入）
		e.push(SHook.new("p_turn_begin", 回合上下文, []))
		e.push(SHook.new("p_before_turn_begin", 回合上下文, []))
		return BattleEngine.CONTINUE


## 中毒结算
class SPoison:
	var cards: Array[int]
	func _init(cs: Array[int]) -> void:
		cards = cs
	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		# 禁止基础效果生效（【虚空境】）：中毒不结算、牌留在原处
		if cur.基础效果禁用:
			return BattleEngine.CONTINUE
		for cid: int in cards:
			# 伤害来源取「施加【中毒】的那名玩家」（对照原版 GameGrail.cpp 的 poisonHarm.srcID = it->srcUser）
			var 来源: int = 0
			for be: Dictionary in cur.basic_effects:
				if int(be["card"]) == cid:
					来源 = int(be["src"])
					break
			# F4：中毒结算是一次「基础效果触发」，钩子压在伤害之下 —— 先跑完伤害结算，再通知触发完成
			e.remove_basic_effect(cur.id, cid, GConst.CAUSE_POISON, -1, true)
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
		# 禁止基础效果生效（【虚空境】）：虚弱不询问、牌留在原处
		if cur.基础效果禁用:
			return BattleEngine.CONTINUE
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
				# F4：虚弱结算也是一次「基础效果触发」；triggered 钩子压在摸牌 / 跳过行动之下，
				# 等它的效果结算完才通知「触发完成」
				e.remove_basic_effect(cur.id, cid, 0, -1, true)
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


## 行动阶段（对照原版 StateActionPhase(allowAction, canGiveUp)）：
## 允许的行动种类与「能否放弃」由本状态的字段决定；被【挑衅】时强制改成「只能攻击 + 可放弃」
class SActionPhase:
	var 允许: int = GConst.ActionType.Any
	var 可放弃: bool = false
	## 本阶段是不是「额外行动」（额外行动声明的 allowAction + 允许放弃）
	var 额外: bool = false
	## 本阶段是否禁止特殊行动（发动过「启动」技能后：只能再攻击 / 法术）
	var 禁特殊: bool = false
	## 额外行动的来源（cause；普通行动为 0）
	var 额外来源: int = 0
	## 当前这份额外行动的原始数据（切换额外攻击时退回队列用）
	var 额外数据: Dictionary = {}
	## 玩家挂机超时：本阶段已作废，直接收尾（tick 里置位，不替他出牌，也不宣告「无法行动」换手牌）
	var 跳过: bool = false

	func _init(allow: int = GConst.ActionType.Any, can_give_up: bool = false, extra: bool = false, no_special: bool = false, cause: int = 0) -> void:
		允许 = allow
		可放弃 = can_give_up
		额外 = extra
		禁特殊 = no_special
		额外来源 = cause

	func handle(e: BattleEngine) -> int:
		# 挂机超时：把这名玩家的行动阶段直接跳过，轮到下家
		if 跳过:
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		# 虚弱拒绝 / 五系束缚拒绝 / 10602 跳过行动阶段：本回合没有行动阶段，直接收尾
		# （额外行动由 STurnEnd 照常处理）。在这里记下「本回合被跳过」供 10605 等后续钩子读取。
		if e.skip_action_phase:
			e.skip_action_phase = false
			e.本回合跳过行动阶段 = true
			e.本回合跳过行动阶段来源 = e.跳过行动阶段来源
			e.跳过行动阶段来源 = 0
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
		e.行动额外来源 = 额外来源
		e.当前额外行动数据 = 额外数据
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var at: int = int(r.get("action_type", GConst.ActionType.None))
			if at == GConst.ActionType.ChooseExtraAction:
				var 参数: Array = r.get("args", [])
				e.切换额外攻击(self, cur, int(参数[0]) if not 参数.is_empty() else 0)
				# 无论切换成功与否都回到本状态重新发行动询问（失败时保留原行动）
				return BattleEngine.SUSPEND
			return e.resolve_action(at, r)
		e.ask_action(e.current_id, 允许, 可放弃, 额外, 禁特殊, 额外来源)
		e.wait_for(e.current_id, GConst.Msg.Action)
		return BattleEngine.WAIT


## 切换当前额外攻击行动：把当前这份退回队列、取出一份新的直接额外攻击，重新发行动询问。
## 只允许 direct（选中无额外代价）且角色认可可切换的额外行动，避免退款 / 重复扣代价。
func 切换额外攻击(状态: SActionPhase, cur: BattlePlayer, cause: int) -> bool:
	if cur == null or cur.role == null or not 状态.额外 or 状态.额外数据.is_empty():
		return false
	if not bool(状态.额外数据.get("direct", false)):
		return false
	if not 额外行动可切换(cur, 状态.额外数据):
		return false
	var idx: int = -1
	for i: int in range(cur.additional_actions.size()):
		var a: Dictionary = cur.additional_actions[i]
		if int(a.get("cause", 0)) == cause and bool(a.get("direct", false)) \
				and GConst.放行动作(GConst.ActionType.Attack, int(a.get("allow_action", 0))) \
				and 额外行动可切换(cur, a):
			idx = i
			break
	if idx < 0:
		return false
	var 新: Dictionary = cur.additional_actions[idx].duplicate()
	cur.additional_actions.remove_at(idx)
	cur.additional_actions.append(状态.额外数据)
	cur.额外行动排序()
	状态.额外数据 = 新
	状态.允许 = int(新.get("allow_action", GConst.ActionType.Attack))
	状态.额外来源 = cause
	状态.禁特殊 = false
	return true


## 换到队列里指定的那一份额外行动，作为「马上要做的动作种类」（攻击 / 法术 / 特殊按各自放行判断）。
## 按唯一 ID 认人（拿到 cause 时退回按 cause 找）。打牌、技能行动都走这里：
## 换成功后原当前那份退回队列、新的成为当前，行动允许 / 来源一起更新。
func _切换额外行动(cur: BattlePlayer, 选中: int, 作为: int) -> bool:
	if cur == null or not 行动额外 or 当前额外行动数据.is_empty():
		return false
	if not bool(当前额外行动数据.get("direct", false)):
		return false
	if not 额外行动可切换(cur, 当前额外行动数据):
		return false
	var idx: int = cur.额外行动下标按ID(选中)
	if idx < 0:
		for i: int in range(cur.additional_actions.size()):
			if int(cur.additional_actions[i].get("cause", 0)) == 选中:
				idx = i
				break
	if idx < 0:
		return false
	var 候选: Dictionary = cur.additional_actions[idx]
	# 「放弃行动」不真正执行某类动作：不需要过 放行动作 这一关（否则切到只放行攻击的行动再放弃
	# 会被判非法，服务端把放弃驳回，玩家看到的是「放弃后另一份额外行动不见了」）。
	if not bool(候选.get("direct", false)) \
			or (作为 != GConst.ActionType.None \
				and not GConst.放行动作(作为, int(候选.get("allow_action", 0)))) \
			or not 额外行动可切换(cur, 候选):
		return false
	var 新: Dictionary = 候选.duplicate()
	cur.additional_actions.remove_at(idx)
	cur.additional_actions.append(当前额外行动数据)
	cur.额外行动排序()
	当前额外行动数据 = 新
	行动额外来源 = int(新.get("cause", 0))
	行动允许 = int(新.get("allow_action", GConst.ActionType.Attack))
	# 切过来的这份行动按「此刻」重算规格：手牌 / 双方手牌数可能在授予之后变过，
	# 授予时的快照会过期（如 10702「只能使用【魔弹】」的白名单、10704「只能打手牌更多的对手」）。
	# 不重算的话：切过来就能打的一定是授予那一刻手里的牌，新拿到的牌会被白名单挡住。
	var 重算: Dictionary = {}
	if cur.role != null:
		重算 = cur.role.额外行动规格(行动额外来源)
	if not 重算.is_empty():
		cur.改写额外行动(行动额外来源, 重算)
	return true


## 出攻击牌时的换队（历史入口，等同「作为＝攻击」的通用换队）
func _直接切换额外攻击(cur: BattlePlayer, 选中: int) -> bool:
	return _切换额外行动(cur, 选中, GConst.ActionType.Attack)


## 响应里选额外攻击时已经点好手牌 + 敌方：进入额外行动（含选中代价钩子）后直接发起攻击
class S自动攻击:
	var cause: int
	var card: int
	var target: int
	var data: Dictionary
	func _init(c: int, cd: int, t: int, d: Dictionary) -> void:
		cause = c
		card = cd
		target = t
		data = d
	func handle(e: BattleEngine) -> int:
		e.行动允许 = GConst.ActionType.Attack
		e.行动可放弃 = false
		e.行动额外 = true
		e.行动禁特殊 = false
		e.行动额外来源 = cause
		e.当前额外行动数据 = data
		return e.resolve_action(GConst.ActionType.Attack, {
			"card_ids": [card], "dst_ids": [target], "args": [cause],
		})


## 回合结束：先处理额外行动，否则轮转到下家
class STurnEnd:
	## 技能行动被取消（见 BattleEngine.取消技能行动）：本回合不结束，改为重新进入行动阶段
	var 回行动阶段: bool = false

	func handle(e: BattleEngine) -> int:
		if e.phase == BattleEngine.Phase.Over:
			return BattleEngine.CONTINUE
		if 回行动阶段:
			回行动阶段 = false
			e.push(SActionPhase.new(e.行动允许, e.行动可放弃, e.行动额外, e.行动禁特殊, e.行动额外来源))
			return BattleEngine.CONTINUE
		var cur: BattlePlayer = e.p(e.current_id)
		if cur != null and cur.contains_action():
			e.push(SAdditionalAction.new())
			return BattleEngine.CONTINUE
		# 对照原版：StateTurnEnd（p_turn_end）→ StateAfterTurnEnd（p_after_turn_end）→ 才 setStateCurrentPlayer(下家)。
		# 顺序不能反：月女【苍白之月】/ 10803 要在 p_after_turn_end 里把额外回合定下来
		var 回合上下文: Dictionary = {
			"player": e.current_id,
			"extra_turn": e.当前额外回合玩家 == e.current_id,
			"attack_bonus": e.当前额外回合攻击加伤,
		}
		e.push(SHook.new("p_after_turn_end", 回合上下文, [SNextPlayer.new()]))
		e.push(SHook.new("p_turn_end", 回合上下文, []))
		return BattleEngine.CONTINUE


## 轮转到下家 / 开始额外回合
class SNextPlayer:
	func handle(e: BattleEngine) -> int:
		# 上一回合如果是额外回合，到这里已经彻底结束：清掉「当前额外回合」状态，取出这条链的续位。
		# （p_after_turn_end 可能又安排了下一份额外回合，所以先清活动状态、再消费待执行队列。）
		var 续位: int = -1
		if e.当前额外回合玩家 >= 0:
			e.当前额外回合玩家 = -1
			e.当前额外回合攻击加伤 = 0
			e.当前额外回合来源 = 0
			# 状态图标（剑守誓言等）跟着消失：立刻补一份快照
			e._broadcast_game()
			续位 = e.额外回合续位
			e.额外回合续位 = -1
		if e.额外回合玩家 >= 0:
			# 额外回合（F7 / 10803；也兼容月女【苍白之月】）：
			# 不推进 current_id 到下家、不增加 round_id，只把行动者切到「额外回合玩家」，
			# 走完整的回合开始流程（p_before_turn_begin / p_turn_begin / 中毒虚弱 / 行动阶段）。
			var 自己: int = e.额外回合玩家
			e.额外回合玩家 = -1
			e.current_id = 自己
			e.当前额外回合玩家 = 自己
			e.当前额外回合攻击加伤 = e.额外回合攻击加伤
			e.额外回合攻击加伤 = 0
			var 来源: int = e.额外回合来源
			e.额外回合来源 = 0
			e.当前额外回合来源 = 来源
			# 状态图标（剑守誓言等）从回合开始就显示：立刻补一份快照
			e._broadcast_game()
			# 战斗日志：真的开始执行这个额外回合时才记（同一次回合结束里安排了两次时，
			# 只有最后真正执行的那一次会记，不会出现「两个人各获得一个额外回合」的假日志）。
			# 用 Turn 类（日志标签 [回合]）：Combat 在客户端会被标成 [伤害]。
			e.broadcast(GConst.Msg.Gossip, {
				"type": GConst.GossipType.Turn,
				"txt": "%s 获得一个额外回合" % e._称号(e.players[自己]),
				"id": 自己,
			})
			# 链式额外回合（额外回合结束时又安排了一份）：续位沿用外层这条链的
			if 续位 >= 0:
				e.额外回合续位 = 续位
			e.broadcast(GConst.Msg.TurnBegin, {
				"id": e.current_id, "round": e.round_id,
				"extra_turn": true, "extra_cause": 来源,
				"attack_bonus": e.当前额外回合攻击加伤,
			})
			e.push(SCheckTurnStart.new())
			return BattleEngine.CONTINUE
		# 额外回合结束后从「续位」继续（＝当作没有这次额外回合时本该轮到的人）；
		# 普通回合没有续位，照常从 current_id 推到下家。
		var nid: int = 续位 if 续位 >= 0 else e.next_id(e.current_id)
		if nid == e.first_id:
			var 旧回合: int = e.round_id
			# 一轮（所有人各行动一次）到此结束：先把这一回合的统计报上去，再清零进下一回合
			e._回合结束埋点()
			e.round_id += 1
			e.current_id = nid
			e._检查神威过期(旧回合)
		else:
			e.current_id = nid
		e.broadcast(GConst.Msg.TurnBegin, {"id": e.current_id, "round": e.round_id, "extra_turn": false})
		e.push(SCheckTurnStart.new())
		return BattleEngine.CONTINUE


## 行动聚合器：专门用于聚合「行动」选项。
## 只负责收集、合并、发询问、把选中的 cause 分派回来源；
## 扣费、direct 标记、入队等行动本身由角色 / 基础效果自己处理。
## 1) 目标身上未确认的基础效果额外行动（迅捷赐福等）；
## 2) 队列里已获得、但还没确认的额外行动（行动规格里 in_end_response＝true，由授予它的技能写）。
class S行动聚合器:
	var 上下文: Dictionary = {}
	var 待决: int = 0
	var 待决类型: String = ""

	func _init(ctx: Dictionary = {}) -> void:
		上下文 = ctx

	func _取回复(e: BattleEngine) -> Dictionary:
		# 与 take_reply 同一套归属判定：插队时被暂存的回复要先恢复出来（见 BattleEngine._挂起回复）
		e._恢复挂起回复()
		var r: Dictionary = e._reply
		e._has_reply = false
		e._await_id = -1
		e._await_state = null
		e._reply = {}
		e._挂起回复.erase(e._当前状态)
		e._pending_partial = {}
		return r

	## 把选中项交回引擎的来源分派器；返回 -1 表示成功可继续，其他为引擎状态。
	func _分派(e: BattleEngine, cur: BattlePlayer, cause: int, reply: Dictionary,
			kind: String) -> int:
		var 分派: Dictionary = e._分派行动结束选项(cur.id, cause, reply, kind, 上下文)
		var 结果: int = int(分派.get("result", GConst.GE_INVALID_ACTION))
		var 终结: bool = bool(分派.get("terminal", true))
		if 结果 == BattleRole.WAIT:
			待决 = cause
			待决类型 = kind
			return BattleEngine.WAIT
		if 结果 == BattleRole.URGENT:
			if 终结:
				待决 = 0
			else:
				待决 = cause
				待决类型 = kind
			return BattleEngine.SUSPEND
		待决 = 0
		if 结果 != BattleRole.SUCCESS:
			return BattleEngine.CONTINUE
		待决 = 0
		return -1

	func handle(e: BattleEngine) -> int:
		var 结果: int = _跑(e)
		# 响应结束（CONTINUE＝本状态出栈）：把本次响应里**还没确认**的额外行动选项撤回。
		# 它们只是「摆出来给玩家选」的选项（in_end_response＝true、direct＝false），不是已获得的行动；
		# 不撤回的话，取消 / 超时 / 点了红色额外攻击提前收尾之后，它们会以「额外行动」身份冒到
		# 额外行动阶段（女武神【神圣追击】、剑帝【不屈意志】踩过：取消响应后弹出红色行动按钮）。
		# WAIT / SUSPEND 说明还在响应里，不动。
		if 结果 == BattleEngine.CONTINUE:
			e._撤回未确认额外行动(e.current_id)
		return 结果

	func _跑(e: BattleEngine) -> int:
		var pid: int = e.current_id
		var cur: BattlePlayer = e.p(pid)
		if cur == null:
			return BattleEngine.CONTINUE
		# 响应里已经点红色额外攻击按钮：放弃剩余响应选项，直接进入所选额外攻击
		if e.首选额外行动 >= 0:
			return BattleEngine.CONTINUE
		# 取消过本回合的行动结束响应：不再提供角色 / 队列的额外攻击行动；
		# 但基础效果（迅捷赐福）是「每次攻击 / 法术行动结束都可以发动」的独立响应，
		# 取消只结束当时那一次，后续行动结束仍要再问（见 _处理行动结束取消）。
		var 只基础效果: bool = cur.跳过额外攻击行动
		if 只基础效果 and e.基础效果额外行动选项(pid).is_empty():
			return BattleEngine.CONTINUE
		# 角色技能的多步结算：上次已经分派，等待本状态再次被唤醒
		if 待决 > 0:
			var 续回复: Dictionary = _取回复(e) if e.has_reply() else {}
			var 续结果: int = _分派(e, cur, 待决, 续回复, 待决类型)
			if 续结果 >= 0:
				return 续结果
		while true:
			# 来源收集全部交给引擎；聚合器不认识角色技能 / 队列额外行动 / 基础效果
			var 待问: Array = e._收集行动结束选项(pid, 上下文, 只基础效果)
			if 待问.is_empty():
				return BattleEngine.CONTINUE
			# 全部不可发动时不要弹一张全是灰按钮的询问；只要有一项可发动，
			# 其余不可发动的技能也照样列出来（客户端置灰）。
			var 有可用: bool = false
			for o: Dictionary in 待问:
				if bool(o.get("enabled", true)):
					有可用 = true
					break
			if not 有可用:
				return BattleEngine.CONTINUE
			if not e.has_reply():
				var 首: int = int(待问[0].get("value", 0))
				var 选牌来源: int = GConst.CardSource.Hand
				for o: Dictionary in 待问:
					if int(o.get("need_card", 0)) > 0 and o.has("card_source"):
						选牌来源 = int(o.get("card_source", 选牌来源))
						break
				# 选项自带「本次攻击的基准伤害」时（如多重射击的虚拟暗系攻击），随询问下发，
				# 客户端就能按 preview_base / option_damage 画「原值划掉 → 新值」，不用自己算荒神
				var 预览基: int = 0
				for o: Dictionary in 待问:
					if o.has("preview_base"):
						预览基 = int(o.get("preview_base", 0))
						break
				e.ask_skill(pid, 首, 0, 0, 选牌来源,
					待问, 0, "", [], true,
					"行动结束时可以发动以下行动，选择一项（发动后还能发动另一项）",
					[], 预览基, 0, false, [], true, -1, 0, true, 0, true)
				return BattleEngine.WAIT
			var r: Dictionary = _取回复(e)
			var args: Array = r.get("args", [])
			# 取消 / 超时（空应答）：只结束本次响应，不清空任何已获得的额外行动；
			# 它们会在响应结束后的「额外行动阶段」（SAdditionalAction）里由玩家选择使用 / 放弃。
			if args.is_empty() and (r.get("dst_ids", []) as Array).is_empty():
				return BattleEngine.CONTINUE
			var 选中: int = int(args[0]) if not args.is_empty() else 0
			var 选中可用: bool = true
			var 选中类型: String = 行动来源_角色
			var 找到选中: bool = false
			for o: Dictionary in 待问:
				if int(o.get("value", 0)) == 选中:
					选中可用 = bool(o.get("enabled", true))
					选中类型 = str(o.get("_kind", 行动来源_角色))
					找到选中 = true
					break
			# 客户端提交了不在本次选项表里的 cause（旧界面/改包）：不能直接分派给角色
			if not 找到选中:
				e.send(pid, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
				continue
			if not 选中可用:
				e.send(pid, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Respond, "commands": []})
				continue
			var 结果: int = _分派(e, cur, 选中, r, 选中类型)
			if 结果 >= 0:
				return 结果
			if e._快捷提前收尾:
				e._快捷提前收尾 = false
				return BattleEngine.CONTINUE
		return BattleEngine.CONTINUE


## 额外行动询问
class SAdditionalAction:
	## 响应里没点选、取消后直接进额外行动阶段使用的那份行动：代价钩子返回 URGENT 时，
	## 等它压入的结算（如血剑【赤色一闪】的伤害）跑完再回来进入
	var 待进入: int = -1

	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		if 待进入 >= 0:
			var 下标: int = 待进入
			待进入 = -1
			if cur != null and 下标 >= 0 and 下标 < cur.additional_actions.size():
				return _进入(e, cur, 下标, int(cur.additional_actions[下标]["cause"]))
		# 行动结束响应点了取消：本回合不再处理额外攻击行动；
		# 若队列里还有法术/特殊类额外行动，仍按原逻辑处理。
		if cur.跳过额外攻击行动:
			e._清除额外攻击行动(e.current_id)
			if cur == null or not cur.contains_action():
				e.push(STurnEnd.new())
				return BattleEngine.CONTINUE
		if cur == null or not cur.contains_action():
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		# 攻击结束响应里玩家点了某份额外攻击行动：直接进入它（不再弹额外行动选择）。
		# 首选记的是唯一 ID（同一技能挂两份时只能靠它区分）；拿到 cause 的旧格式按要求退回按 cause 找。
		if e.首选额外行动 >= 0:
			var 期望: int = e.首选额外行动
			e.首选额外行动 = -1
			var 期望下标: int = cur.额外行动下标按ID(期望)
			if 期望下标 < 0:
				for i: int in range(cur.additional_actions.size()):
					if int(cur.additional_actions[i].get("cause", 0)) == 期望:
						期望下标 = i
						break
			if 期望下标 >= 0:
				return _进入(e, cur, 期望下标, int(cur.additional_actions[期望下标]["cause"]))
			# 选中的额外行动已经不在队列：清掉预选牌和目标，避免错误地打第一份 direct 行动
			e.首选额外行动卡 = -1
			e.首选额外行动目标 = -1
		# 声明了 direct 的额外行动（如圣女【圣疗】）不用先问：直接进入它的额外行动阶段。
		# 该阶段允许「放弃行动」，想跳过在那里放弃即可，省掉「再点一次技能按钮」这一步。
		if not e.has_reply():
			for i: int in range(cur.additional_actions.size()):
				if not bool(cur.additional_actions[i].get("direct", false)):
					continue
				return _进入(e, cur, i, int(cur.additional_actions[i]["cause"]))
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var args: Array = r.get("args", [])
			var chosen: int = int(args[0]) if args.size() > 0 else -1
			# 玩家选的是唯一 ID；万一拿到的是 cause（旧格式 / 脚本自测）就退回按 cause 找
			var idx: int = cur.额外行动下标按ID(chosen) if chosen > 0 else -1
			if idx < 0 and chosen > 0:
				for i: int in range(cur.additional_actions.size()):
					if int(cur.additional_actions[i]["cause"]) == chosen:
						idx = i
						break
			if idx >= 0:
				return _进入(e, cur, idx, int(cur.additional_actions[idx]["cause"]))
			# 放弃/无匹配：清空待办并继续结束回合
			cur.clear_additional_action()
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		var 参数: Array = _询问参数(e, cur)
		e.ask_respond(cur.id, GConst.RespondType.AdditionalAction, 参数[0], 参数[1],
			-1, 0, "", "", 参数[2], 参数[3])
		e.wait_for(cur.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


	## 额外行动询问参数：causes = 队列里的全部（顺序来自 额外行动序列，先获得的在前）；
	## 允许 = 每份额外行动各自允许的行动种类（客户端据此写「额外【攻击行动】」）；
	## uids = 与 causes 一一对应的唯一 ID（客户端提交时用它认人，不按 cause 认）。
	## 能不能用只看行动自带规格、由技能在授予时保证；不再做「按来源的二次校验」。
	func _询问参数(e: BattleEngine, cur: BattlePlayer) -> Array:
		var causes: Array = []
		var 可发动: Array = []
		var 允许: Array = []
		var uids: Array = []
		for 项: Dictionary in e.额外行动序列(cur.id, false):
			var c: int = int(项.get("cause", 0))
			var uid: int = int(项.get("uid", 0))
			if c <= 0 or uid <= 0:
				continue
			causes.append(c)
			uids.append(uid)
			允许.append(int(项.get("allow_action", 0)))
			可发动.append(uid)
		return [causes, 可发动, 允许, uids]

	## 进入某份额外行动：移除它、广播技能通知（授予者已宣告过时不重复），
	## 再压入额外行动阶段（允许放弃）与其「被选中」代价钩子。
	## 数据保持同一份引用（不复制）：技能在 p_additional_action 里改写规格（如按当前手牌重算白名单）
	## 时，改的就是这份正在行动的行动。
	func _进入(e: BattleEngine, cur: BattlePlayer, idx: int, cause: int) -> int:
		var 允许: int = int(cur.additional_actions[idx]["allow_action"])
		var 跳过宣告: bool = bool(cur.additional_actions[idx].get("skip_notice", false))
		var 数据: Dictionary = cur.additional_actions[idx]
		# 响应里点选过的额外行动已在当时付过代价（已付费）；取消响应后直接进额外行动阶段
		# 使用的那份，在这里补付一次，避免「取消一下就能免费使用」。
		if not bool(数据.get("已付费", false)):
			var 代价: int = BattleRole.SUCCESS
			if cur.role != null:
				代价 = cur.role.行动结束确认代价(cause)
			if 代价 == BattleRole.URGENT:
				数据["已付费"] = true
				待进入 = idx
				return BattleEngine.SUSPEND
			if 代价 != BattleRole.SUCCESS:
				# 付不起 / 条件已失效：这份行动不再保留，继续问剩下的
				cur.additional_actions.remove_at(idx)
				if cur.contains_action():
					e.push(SAdditionalAction.new())
				else:
					e.push(STurnEnd.new())
				return BattleEngine.CONTINUE
			数据["已付费"] = true
		if GConst.基础效果额外行动.has(cause) and not e.基础效果额外行动已确认(cause):
			e._支付基础效果额外行动(cur.id, cause)
		cur.additional_actions.remove_at(idx)
		if not 跳过宣告:
			e.broadcast(GConst.Msg.Skill, {"skill_id": cause, "src_id": cur.id, "dst_ids": []})
		# 先让角色结算「被选中」的代价（p_additional_action），再进入额外行动阶段。
		# 额外行动阶段只放行这份额外行动声明的种类、且允许放弃（对照原版
		# PlayerEntity::p_additional_action → StateActionPhase(it->allowAction, true)）
		var 阶段: SActionPhase = SActionPhase.new(允许, true, true, false, cause)
		阶段.额外数据 = 数据
		e.当前额外行动数据 = 数据
		# 响应里已经点好手牌 + 敌方：进入该额外行动后不再问，直接发起这次攻击
		# 响应里点好手牌 + 敌方：进入该额外行动后不再问，直接发起这次攻击。
		# 牌 / 目标都可能就是 0（卡表#0 圣盾、0 号座位），只有负数才代表「没选」
		if e.首选额外行动卡 >= 0 and e.首选额外行动目标 >= 0:
			var 卡: int = e.首选额外行动卡
			var 目标: int = e.首选额外行动目标
			e.首选额外行动卡 = -1
			e.首选额外行动目标 = -1
			e.push(S自动攻击.new(cause, 卡, 目标, 数据))
			e.push(SHook.new("p_additional_action", {"player": cur.id, "cause": cause}, []))
			return BattleEngine.CONTINUE
		e.push(阶段)
		e.push(SHook.new("p_additional_action", {"player": cur.id, "cause": cause}, []))
		return BattleEngine.CONTINUE


## 一次攻击的入口：先跑 timeline_1 钩子（可改命中率/是否查圣盾），再压入应战询问
class SAttackCard:
	var src: int
	var dst: int
	var card: int
	var instance: int = -1
	var harm: Dictionary
	var ctx_built: bool = false
	var ctx: Dictionary = {}

	func _init(s: int, d: int, c: int, h: Dictionary, inst: int = -1) -> void:
		src = s
		dst = d
		card = c
		instance = inst
		harm = h
		# 通用口径：攻击状态创建时就判定「有没有真实打出的实体牌」（harm.card_id_instance），
		# 没有就是虚拟攻击 → 标成无命格。必须在这里做：应战询问（阴阳师 3306 / 3301 读这个标记）
		# 发生在 push_harm 之前，晚标就来不及了。
		if int(harm.get("type", GConst.HarmType.None)) == GConst.HarmType.Attack \
				and not harm.has("card_id_instance"):
			harm["virtual_no_fate"] = true

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
				SHook.new("p_timeline_1", ctx, [SAttackDiscard.new(self)]),
			]))
			return BattleEngine.CONTINUE
		# 钩子完成后继续（由 SHook 压入 SAttacked）
		return BattleEngine.CONTINUE


## 攻击时间线 1 跑完、进入应战/命中之前：把攻击牌正式送进弃牌堆。
## 这样噬灭/殇灭（timeline 1）先结算，之后才触发攻击牌的【渗蚀】；侵刻（timeline 2 命中）再往后。
## to_discard 可能压入「弃牌前拦截」状态，先把 SAttacked 压在它下面，保证弃牌/渗蚀跑完再进入应战。
class SAttackDiscard:
	var owner: SAttackCard

	func _init(o: SAttackCard) -> void:
		owner = o

	func handle(e: BattleEngine) -> int:
		e.push(SAttacked.new(owner))
		if owner.instance >= 0:
			e.to_discard([owner.instance], {
				"owner": owner.src, "source": "hand", "cause": GConst.CAUSE_ATTACK,
			})
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
		# 通用：应战者此刻不能用【圣光】（如染污者狂戾形态）→ 随询问下发 can_light=false，
		# 客户端把圣光置灰；格挡校验也读同一个字段（见下面 owner.ctx.get("can_light")）
		if defender.role != null and not defender.role.能否使用圣光():
			owner.ctx["can_light"] = false
		# 应战询问的参数；末位＝本次攻击伤害：harm["point"]（怒吼 / 精准射击 / 蓄力一击等「宣告阶段」
		# 已加进去的）＋ 攻击者预告的「命中才结算」加伤（暗影之力 / 暗之解放…，见 p_attack_preview）。
		# 客户端把它写进提示（「受到 N 伤害攻击，…」），让被攻击者一眼看到这一下要挨多少
		# 应战比对用「攻击牌实例」的当前系别，不用共用牌面：
		# 多个噬神者各有一张魔刃/异刃时，牌面的 element 会被另一边切换改写。
		# 普通牌/虚拟「视为」牌按牌面；只有魔刃/异刃这种多系别实例才按实例当前系别
		var 攻击牌判定: int = owner.card
		if (owner.card == GConst.噬神者_魔刃卡 or owner.card == GConst.噬神者_异刃卡) \
				and owner.instance >= 0:
			攻击牌判定 = owner.instance
		var 攻击牌卡: GCard = Data.get_card(攻击牌判定)
		var 应战询问: Array = [hit_rate, 攻击牌判定, defender.id, owner.src,
			owner.ctx.get("can_light", 1), e._应战提示伤害(owner.src, owner.ctx, harm),
			攻击牌卡.element_enum() if 攻击牌卡 != null else 0]
		if hit_rate == GConst.HitRate.NoMiss:
			e.push(STimeline2Hit.new(harm))
			return BattleEngine.CONTINUE
		# 客户端攒操作的预置应战答复优先；没有预置才等正常回复
		var r: Dictionary = e.take_prepared_reply(defender.id)
		if r.is_empty() and e.has_reply():
			r = e.take_reply()
		if not r.is_empty():
			var args: Array = r.get("args", [])
			var choice: int = int(args[0]) if args.size() > 0 else GConst.Reattack.GiveUp
			var cards: Array = r.get("card_ids", [])
			if choice == GConst.Reattack.Attack and not cards.is_empty():
				var cid: int = int(cards[0])
				# 应战的反击目标由应战者指定（对照服务端 reply_attack->dst_ids(0)）：只能是敌方、且不是原攻击者
				var 选定: Array = r.get("dst_ids", [])
				var 反击目标: int = int(选定[0]) if not 选定.is_empty() else -1
				if hit_rate != GConst.HitRate.Normal or not e._reattack_target_ok(defender, 反击目标, owner.src) \
						or defender.v_reattack(cid, 攻击牌判定) != GConst.GE_SUCCESS \
						or e._禁应战(owner.ctx, cid):
					# args[2] 必须是「应该由谁来应战」（defender），客户端据此判断这条询问是不是给我的：
					# 代应战（式神咒束）时 defender 是代替者，不等于被攻击的目标 dst，写成 dst.id 会让代替者的客户端把询问丢掉
					e.ask_respond(defender.id, GConst.RespondType.ReplyAttack, 应战询问, [], -1, 0, "", "", [], [],
						owner.ctx.get("禁应战牌名", []))
					e.wait_for(defender.id, GConst.Msg.Respond)
					return BattleEngine.WAIT
				# 应战成立：原攻击落空，应战者以自己的攻击牌对所选目标发起一次新攻击。
				# 对照原版：先跑一轮 p_reattack（角色可把这张牌「视为」另一张，如魔女烈焰形态下的
				# 另一张牌），再按结果结算（真牌照样进弃牌堆并展示，反击用「视为」的那张）
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
				# 与询问里下发的 can_light 对齐：本次攻击不能用【圣光】时，格挡不成立。
				# 解析失败按常规「放弃应战」收尾（不扣牌、不改形态）。
				if bool(owner.ctx.get("can_light", true)) and defender.v_block(cid2) == GConst.GE_SUCCESS:
					e.take_from_hand(defender.id, [cid2])
					e.to_discard([cid2], {"owner": defender.id, "source": "hand", "cause": GConst.CAUSE_ATTACK})
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
			if bool(owner.ctx.get("check_shield", true)) and not dst.基础效果禁用:
				var shield_card: int = -1
				if dst.check_basic_effect_name(GConst.CardName.Shield):
					shield_card = e._find_basic_card(dst, GConst.CardName.Shield)
				elif dst.check_basic_effect_skill(GConst.技能_天使之墙):
					shield_card = e._find_basic_card_by_skill(dst, GConst.技能_天使之墙)
				if shield_card >= 0:
					# F4：圣盾 / 天使之墙挡下攻击＝一次「基础效果触发」；
					# triggered 钩子压在本次落空结算之下，先跑完落空再通知触发完成
					e.remove_basic_effect(dst.id, shield_card, GConst.CAUSE_ATTACK, -1, true)
					e.to_discard([shield_card])
					e._broadcast_game()
					e.push(STimeline2Miss.new(harm))
					return BattleEngine.CONTINUE
			e.push(STimeline2Hit.new(harm))
			return BattleEngine.CONTINUE
		e.ask_respond(defender.id, GConst.RespondType.ReplyAttack, 应战询问, [], -1, 0, "", "", [], [],
			owner.ctx.get("禁应战牌名", []))
		e.wait_for(defender.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 应战成立后的结算（对照原版 setStateReattack）：
## 反击用的是 p_reattack 给出的「视为」牌（可能是虚拟牌）；
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
		# 应战打出的魔刃/异刃也记「本次刃」，供侵刻在命中时判断。
		# 必须在 take_from_hand 之前记：p_attack_card 要从手牌找实例。
		var 出牌: Dictionary = {
			"player": defender.id, "card_id": GConst.牌号(原牌),
			"card_id_instance": 原牌, "改用": 用牌, "reattack": true,
		}
		if defender.role != null:
			defender.role.call_hook("p_attack_card", 出牌)
		var 归属者: int = e.刃归属者(原牌)
		if 归属者 >= 0 and 归属者 != defender.id:
			var 归属玩家: BattlePlayer = e.p(归属者)
			if 归属玩家 != null and 归属玩家.role != null:
				归属玩家.role.call_hook("p_attack_card", 出牌)
		e.take_from_hand(defender.id, [原牌])
		# 应战打出的魔刃/异刃同样按当前系别借普通斩击牌出特效/音效
		var 表现用牌: int = e.攻击表现牌(用牌)
		var 应战卡数据: GCard = Data.get_card(原牌)
		e.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Use, "src_id": defender.id, "dst_id": 目标,
			"card_ids": [原牌], "is_real": true,
			"as_card_id": 表现用牌 if 表现用牌 != 原牌 else -1,
			"card_elements": [应战卡数据.element_enum() if 应战卡数据 != null else 0],
		})
		# 角色可把这次应战「视为格挡」（如阴阳师式神形态下用光系牌应战）：本次攻击落空、不反击
		if bool(应战.get("block", false)):
			e.push(STimeline2Miss.new(harm))
			e.push_show_hand(defender.id, [原牌])
			return BattleEngine.CONTINUE
		# 反击是应战者自己的攻击：伤害按「攻击牌基础值」重建，不继承原攻击者本次的加成
		# （如格斗【蓄力一击】的 +1 只属于他这次主动攻击；应战者的加伤由他自己的角色钩子按 is_active=false 施加）
		var new_harm: Dictionary = {
			"src": defender.id, "dst": 目标, "point": e.攻击基础伤害(defender.id),
			"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
			"reattack": true, "card_id": 用牌, "is_active": false,
			# 反击用的是应战者真实打出的那张牌（「视为」只换牌面，牌本身是他的）
			"card_id_instance": 原牌,
			# 命格同理：按他真实打出的那张牌算
			"fate_card_id": 原牌,
		}
		var 是噬神刃: bool = GConst.牌号(原牌) == GConst.噬神者_魔刃卡 \
			or GConst.牌号(原牌) == GConst.噬神者_异刃卡
		if 是噬神刃:
			e.push(SAttackCard.new(defender.id, 目标, 用牌, new_harm, 原牌))
		else:
			e.to_discard([原牌], {"owner": defender.id, "source": "hand", "cause": GConst.CAUSE_ATTACK})
			e.push(SAttackCard.new(defender.id, 目标, 用牌, new_harm, -1))
		e.push(STimeline2Miss.new(harm))
		# 「展示手牌」钩子最后压（＝最先跑）：上面那条出牌广播已经先发出去（客户端摊牌 + 出手特效），
		# 之后才轮到技能询问（如圣女冰霜祷言）—— 与非应战场合（主动打出）的次序一致
		e.push_show_hand(defender.id, [原牌])
		return BattleEngine.CONTINUE


## 魔弹传递询问：持有者可以打出【魔弹】继续传递、出【圣光】抵挡，或放弃并承受伤害。
## 对照服务端 StateMissiled：传递方向沿用出弹时定下的方向（【魔弹】默认右手边 post；
## 魔导用【魔弹掌控】/ 节日魔导用【魔弹掌握】逆向打出则是 pre），后续传递者只是「传给下一个」、
## 不能改方向 —— 落点方向只在「主动打出」那一步决定（见 BattleRole.missile_targets）。
## 同一轮传递里每人只能参与一次；
## 一轮结束后重置参与记录开新一轮，但新一轮的第一个目标不能是刚把魔弹传给自己的人。
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
		var me: BattlePlayer = e.p(holder)
		# 10603：持有者能凑出两张同系牌时，选牌上限放宽到 2；其余角色保持 1
		var 选牌上限: int = 1
		if me != null:
			选牌上限 = me.missile_relay_card_max()
		var 提示: String = ""
		if 选牌上限 > 1:
			提示 = "受到 %d 伤害魔弹攻击，出【魔弹】继续传递，或弃 2 张同系牌视为【魔弹】，或出【圣光】抵挡，或点「取消」承受伤害" % point
		if not e.has_reply():
			# dst_ids = 本次可以把魔弹传给谁（候选，有【魔弹掌控】时左右各一个）
			# args[0] 放持有者 id：客户端据此判断这条询问是不是发给自己的
			var 持者: BattlePlayer = e.players.get(holder)
			var 可圣光: bool = 持者 == null or 持者.role == null or 持者.role.能否使用圣光()
			e.ask_respond(holder, GConst.RespondType.Bullet, [holder, point, src],
				e._missile_relay_targets(holder, post_dir, used, src), src,
				选牌上限, "", 提示, [], [], [], 可圣光)
			e.wait_for(holder, GConst.Msg.Respond)
			return BattleEngine.WAIT
		var r: Dictionary = e.take_reply()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if args.size() > 0 else GConst.Reattack.GiveUp
		var cards: Array = r.get("card_ids", [])
		if me != null and cards.size() > 1 and choice == GConst.Reattack.Attack:
			# 多牌响应：10603「弃 2 张同系牌，视为使用【魔弹】」。
			# 两张牌作为多牌响应结算；不合法则重新询问（不能静默只取第一张）。
			if me.v_remissile_multi(cards) != GConst.GE_SUCCESS:
				e.ask_respond(holder, GConst.RespondType.Bullet, [holder, point, src],
					e._missile_relay_targets(holder, post_dir, used, src), src,
					选牌上限, "", 提示, [], [], [],
					me == null or me.role == null or me.role.能否使用圣光())
				e.wait_for(holder, GConst.Msg.Respond)
				return BattleEngine.WAIT
			var 多牌下轮: Array[int] = []
			多牌下轮.append_array(used)
			var 多牌落点: int = e._next_missile_target(holder, post_dir, 多牌下轮, src)
			if 多牌落点 < 0:
				多牌下轮.clear()
				多牌下轮.append(holder)
				多牌落点 = e._next_missile_target(holder, post_dir, 多牌下轮, src)
			var 多牌技能: int = me.remissile_multi_skill()
			if 多牌技能 > 0:
				e.broadcast(GConst.Msg.Skill, {
					"skill_id": 多牌技能, "src_id": holder,
					"dst_ids": [多牌落点 if 多牌落点 >= 0 else holder],
				})
			var 视为魔弹: int = Data.card_id_by_name_enum(GConst.CardName.Missile)
			e.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Use, "src_id": holder,
				"dst_id": 多牌落点 if 多牌落点 >= 0 else holder,
				"card_ids": cards.duplicate(), "is_real": true, "as_card_id": 视为魔弹,
			})
			if 多牌落点 >= 0:
				多牌下轮.append(多牌落点)
				e.push(SMissileAsk.new(多牌落点, holder, point + 1, post_dir, 多牌下轮))
			else:
				e.push_harm({"src": src, "dst": holder, "point": point, "cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic})
			e.take_from_hand(holder, cards, true)
			e.to_discard(cards, {"owner": holder, "source": "hand", "cause": GConst.CAUSE_MISSILE})
			e._broadcast_game()
			return BattleEngine.CONTINUE
		if me != null and not cards.is_empty():
			var cid: int = int(cards[0])
			if choice == GConst.Reattack.Block and me.v_block(cid) == GConst.GE_SUCCESS:
				# 【圣光】抵挡：魔弹效果终止，不造成伤害（牌是公开打出的，带 已展示 触发展示手牌钩子）
				e.take_from_hand(holder, [cid], true)
				e.to_discard([cid], {"owner": holder, "source": "hand", "cause": GConst.CAUSE_MISSILE})
				e.broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": holder, "dst_id": holder, "card_ids": [cid], "is_real": true})
				e._broadcast_game()
				return BattleEngine.CONTINUE
			if choice == GConst.Reattack.Attack and me.v_remissile(cid) == GConst.GE_SUCCESS:
				# 继续传递：伤害 +1，沿**当前方向**转给下一个还没参与过的对手。
				# 方向由出弹时定下（顺时针打出＝顺向，魔导用【魔弹掌控】逆向打出＝逆向）；
				# 【魔弹掌控】只作用于「主动打出」那一步，传递者一律不能改向。
				# 本轮没人可接时开新一轮；新一轮的第一个目标不能是刚把魔弹传给自己的人。
				var 下轮记录: Array[int] = []
				下轮记录.append_array(used)
				var nxt: int = e._next_missile_target(holder, post_dir, 下轮记录, src)
				if nxt < 0:
					下轮记录.clear()
					下轮记录.append(holder)
					nxt = e._next_missile_target(holder, post_dir, 下轮记录, src)
				# 打出的是【魔弹】继续传递：dst_id 必须给下一个落点，客户端才知道魔弹要从自己飞向谁；
				# 没人能再接（nxt < 0）就仍写自己，动画落在自己身上。
				# 魔导/特殊魔导也可以拿地系、火系牌传递：这次出牌同样视为【魔弹】
				var 视为魔弹号: int = e.missile_as_card(cid)
				# 地/火牌继续传递也是发动【魔弹融合】：补发技能通知，客户端才知道该飘技能名
				# （真正的【魔弹】牌视为魔弹号 = -1，不补；它本来就不靠魔弹融合）
				# 技能号按传递者自己的角色取：魔导师 803、节日魔导 7602
				if 视为魔弹号 >= 0:
					var 融合技能号: int = GConst.技能_魔弹融合
					if me != null and me.role != null:
						融合技能号 = me.role.missile_fusion_skill()
					e.broadcast(GConst.Msg.Skill, {
						"skill_id": 融合技能号, "src_id": holder,
						"dst_ids": [nxt if nxt >= 0 else holder],
					})
				e.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Use, "src_id": holder,
					"dst_id": nxt if nxt >= 0 else holder,
					"card_ids": [cid], "is_real": true, "as_card_id": 视为魔弹号,
				})
				if nxt >= 0:
					下轮记录.append(nxt)
					e.push(SMissileAsk.new(nxt, holder, point + 1, post_dir, 下轮记录))
				else:
					# 没人能再接：由当前持有者承受
					e.push_harm({"src": src, "dst": holder, "point": point, "cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic})
				# 传递打出的牌是公开的：带 已展示；放在这些 push 之后，展示手牌钩子才压在栈顶先结算
				e.take_from_hand(holder, [cid], true)
				e.to_discard([cid], {"owner": holder, "source": "hand", "cause": GConst.CAUSE_MISSILE})
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
		# p_timeline_6_drawn 的 ctx 在摸牌 / 超限之后再构造（见 SHookTimeline6Drawn）：
		# ⑥ 伤害转移可能在 p_timeline_6 里改掉 harm["dst"]，这里先构造会拿到转移前的旧目标
		e.push(SHookTimeline6Drawn.new(harm))
		e.push(SHarmTimeline6.new(harm))
		e.push(SHook.new("p_timeline_6", hc, []))
		return BattleEngine.CONTINUE


## p_timeline_6_drawn 的延迟构造：钩子真正轮到（按点数摸牌、超限结算都做完）时，按 harm 现算 ctx，
## ctx.dst 才是 ⑥ 伤害转移之后的新目标（原目标不触发、新目标触发，见 battle_role.gd 的转移伤害说明）
class SHookTimeline6Drawn:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		e.push(SHook.new("p_timeline_6_drawn", e.harm_ctx(harm), []))
		return BattleEngine.CONTINUE


## p_harm_end 的延迟构造：伤害流水线最末尾才按 harm 现算 ctx（ctx.dst / ctx.harm.dst 都是最终目标；
## 发生转移时 harm["redirect_from"] 记录原目标），避免整条流水线开头构造的快照与转移结果不一致
class SHookHarmEnd:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		e.push(SHook.new("p_harm_end", e.harm_ctx(harm), []))
		return BattleEngine.CONTINUE


## Timeline6：目标按伤害点数摸牌（进入这里时点数必然 > 0）
class SHarmTimeline6:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		# 走到这里伤害点数必然 > 0，且治疗已抵完、⑥ 伤害转移已改好最终目标 —— 埋点的伤害记笔就在这里
		e._统计伤害(harm)
		# 摸牌前先让角色响应（如暗杀者【水影】：除特殊行动外，当你摸牌前发动）；
		# 钩子先跑（LIFO），随后 SHarmDrawOverload 才真正摸牌
		e.push(SHarmDrawOverload.new(harm))
		e.push(SHook.new("p_before_draw", {
			"player": harm["dst"], "count": int(harm["point"]), "cause": int(harm.get("cause", 0)),
		}, []))
		return BattleEngine.CONTINUE


## 摸牌：把 n 张牌从牌堆发到某玩家手里（对照服务端发牌状态）
## 强制摸牌（不走 p_before_draw）：摸完照常回到状态边界，结算超限等。
## 与 强制摸牌() 同步版区别：这条会先让引擎跑完边界检查再回到调用方的流程。
class S强制摸牌:
	var pid: int
	var n: int
	var after_hook: String
	var after_ctx: Dictionary
	func _init(_pid: int, _n: int, hook: String = "", ctx: Dictionary = {}) -> void:
		pid = _pid
		n = _n
		after_hook = hook
		after_ctx = ctx
	func handle(e: BattleEngine) -> int:
		var cards: Array = e.强制摸牌(pid, n)
		if not after_hook.is_empty():
			var ctx: Dictionary = after_ctx.duplicate()
			ctx["cards"] = cards
			e.push(SHook.new(after_hook, ctx, []))
		return BattleEngine.CONTINUE


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
		# 因承受伤害摸牌（F8）：先问角色有没有「第 1 张改从别处拿」的效果
		# （异教徒【末日预言】：本次摸牌的第 1 张改为自【预言】处获得），剩下的照常摸
		var 需要: int = int(harm["point"])
		var 替换: int = e.伤害摸牌替换(int(harm["dst"]))
		if 替换 >= 0:
			var 主人: BattlePlayer = e.p(int(harm["dst"]))
			if 主人 != null:
				主人.add_hand_cards([替换])
			需要 -= 1
		if 需要 > 0:
			e.draw(harm["dst"], 需要)
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
				if chosen.size() >= over:
					break
				# 同牌面的副本按份数逐个认（不能按牌号去重，否则两张同牌面只能选出一张）
				var 实例: int = e._认一张(target.cover_cards, int(c), chosen)
				if 实例 >= 0:
					chosen.append(实例)
			if chosen.size() < over:
				for cid: int in target.cover_cards:
					if chosen.size() >= over:
						break
					if not chosen.has(cid):
						chosen.append(cid)
			target.remove_cover_cards(chosen)
			e.to_discard(chosen, {"owner": target.id, "source": "cover", "cause": GConst.CAUSE_OVERLOAD, "face_up": false})
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
				if chosen.size() >= want:
					break
				# 只认真实手牌（弃牌不能弃盖牌），同牌面的副本按份数逐个认
				var 实例: int = e._认一张(p0.hand_cards, int(c), chosen)
				if 实例 >= 0:
					chosen.append(实例)
			if chosen.size() < want:
				for cid: int in p0.hand_cards:
					if chosen.size() >= want:
						break
					if not chosen.has(cid):
						chosen.append(cid)
			e.take_from_hand(pid, chosen)
			e.to_discard(chosen, {"owner": pid, "source": "hand", "cause": cause, "face_up": false})
			e._log_discard(pid, chosen)
			e._broadcast_game()
			return BattleEngine.CONTINUE
		e.ask_respond(pid, GConst.RespondType.Discard, [pid, cause, want], [pid])
		e.wait_for(pid, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 手牌调整到 N 张（F9 / 7804）：超出目标时压一次「由牌主自己选弃」的询问；
## 询问跑完再回来检查一次。补牌走 push_draw、随机弃牌当场处理，都不进这里。
class SHandAdjust:
	var pid: int
	var 目标: int
	var cause: int
	var _已推: bool = false

	func _init(p_id: int, target: int, c: int) -> void:
		pid = p_id
		目标 = target
		cause = c

	func handle(e: BattleEngine) -> int:
		var p0: BattlePlayer = e.p(pid)
		if p0 == null:
			return BattleEngine.CONTINUE
		if p0.hand_cards.size() <= 目标:
			# 正常流程只会在「超限」时压入 SRequestDiscard；这里只做收尾检查，不再补牌
			return BattleEngine.CONTINUE
		if _已推:
			# 弃牌询问回来仍超限（异常 / 询问被提前结束）：不再重复询问，避免死循环
			return BattleEngine.CONTINUE
		_已推 = true
		e.push(SRequestDiscard.new(pid, -1, 目标, cause))
		return BattleEngine.SUSPEND


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
			# 只认真实手牌；同牌面的副本各认一份，不能按牌号去重
			var 实例: int = e._认一张(p0.hand_cards, int(c), chosen)
			if 实例 >= 0:
				chosen.append(实例)
		if chosen.is_empty():
			return BattleEngine.CONTINUE
		e.take_from_hand(pid, chosen)
		e.to_discard(chosen, {"owner": pid, "source": "hand"})
		e._log_discard(pid, chosen)
		e._broadcast_game()
		return BattleEngine.CONTINUE


## 弃牌前拦截（F6 / 4704）：把一次弃牌推迟到 p_before_discard 钩子之后。
## 第一次 handle 压入钩子轮次并挂起自己（钩子里可以等待玩家输入）；钩子跑完后再回到这里，
## 按 ctx.taker / ctx.taken 结算：被认领的牌交给认领者，其余照常进弃牌堆。
class SDiscardBeforeHook:
	var ctx: Dictionary
	var _已问过: bool = false

	func _init(c: Dictionary) -> void:
		ctx = c

	func handle(e: BattleEngine) -> int:
		if not _已问过:
			_已问过 = true
			# 钩子期间产生的弃牌（拦截代价等）不再二次拦截，避免递归
			e._弃牌拦截中 = true
			e.push(SHook.new("p_before_discard", ctx, []))
			return BattleEngine.SUSPEND
		e._弃牌拦截中 = false
		e._结算待弃牌(ctx)
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
			# 手牌数量变化日志：先写「获得 N 张牌」（只写涨、不写跌），再写「手牌 X→Y」。
			# 走「获得【具体牌名】」的场合（播获得牌日志）已经写过一次获得，不再补泛化那条。
			if 新 > 旧 and not bool(e._获得牌已播.get(pid, false)):
				e._播手牌日志(p0, "%s 获得 %d 张牌" % [e._称号(p0), 新 - 旧])
			e._获得牌已播.erase(pid)
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
	## 目标已选好超限牌、但还没真正弃掉：先给月女【新月庇护】一次发动机会
	var _pending_target: int = -1
	var _pending_over: int = 0
	var _pending_cards: Array = []
	var _xinyue_checked: bool = false
	var _xinyue_ctx: Dictionary = {}
	## 本次超限是否真的带着伤害上下文（push_overload_with_harm 建出来的）。
	## 通用 _check_hand_overflow 建出来的实例没有，不能拿最近一次伤害去硬凑，
	## 否则普通的摸牌超限会误触发月女【新月庇护】。
	var _from_damage: bool = false
	## 这次伤害是否声明「不因这次伤害掉士气」（F6 / 4702）：超限牌照弃，只免掉士气这一步。
	var _no_morale: bool = false

	func _init(cause: int = -1, htype: int = -1, no_morale: bool = false) -> void:
		harm_cause = cause
		harm_type = htype
		_no_morale = no_morale
		_from_damage = htype == GConst.HarmType.Attack or htype == GConst.HarmType.Magic

	## 已有一次排队中的超限结算时，把这次伤害的上下文补给它（原先 push_overload_with_harm 直接 return，
	## 若排着的是 _check_hand_overflow 建的通用结算，就会丢掉「因伤害」标记）。
	## 已有真实伤害上下文 / 已经开始问弃牌 的不覆盖。
	func 补充伤害上下文(cause: int, htype: int, no_morale: bool = false) -> void:
		if _from_damage or _pending_target >= 0:
			return
		if htype != GConst.HarmType.Attack and htype != GConst.HarmType.Magic:
			return
		harm_cause = cause
		harm_type = htype
		_from_damage = true
		if no_morale:
			_no_morale = true

	func handle(e: BattleEngine) -> int:
		if harm_cause < 0:
			harm_cause = e.last_harm_cause
			harm_type = e.last_harm_type
		# 超限牌已经选好：先问完月女，再决定「变暗月」还是「正常弃掉」
		if _pending_target >= 0:
			return _finish(e)
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
				if chosen.size() >= over:
					break
				# 同牌面的副本按份数逐个认（不能按牌号去重，否则两张同牌面只能选出一张）
				var 实例: int = e._认一张(target.hand_cards, int(c), chosen)
				if 实例 >= 0:
					chosen.append(实例)
			if chosen.size() < over:
				for cid: int in target.hand_cards:
					if chosen.size() >= over:
						break
					if not chosen.has(cid):
						chosen.append(cid)
			_pending_target = target.id
			_pending_over = over
			_pending_cards = chosen
			if not _xinyue_checked:
				_xinyue_checked = true
				# 目标已经选好要弃的牌，但还没真正弃；此时让【新月庇护】决定是否把它们变成【暗月】
				_xinyue_ctx = {
					"dst": target.id, "amount": over, "cards": chosen.duplicate(),
					"cause": GConst.CAUSE_OVERLOAD, "harm_cause": harm_cause,
					"type": harm_type, "before_discard": true,
					"from_damage": _from_damage,
				}
				e.push(SHook.new("p_xin_yue", _xinyue_ctx, []))
				return BattleEngine.SUSPEND
			return _finish(e)
		e.ask_respond(target.id, GConst.RespondType.Discard, [target.id, GConst.CAUSE_OVERLOAD, over], [target.id])
		e.wait_for(target.id, GConst.Msg.Respond)
		return BattleEngine.WAIT

	## 月女已决定：active＝把这几张牌变成【暗月】且本次不掉士气；否则按原流程弃牌 + 掉士气
	func _finish(e: BattleEngine) -> int:
		var target: BattlePlayer = e.p(_pending_target)
		if target == null:
			return BattleEngine.CONTINUE
		if bool(_xinyue_ctx.get("active", false)):
			var moon: BattlePlayer = e.p(int(_xinyue_ctx.get("moon_id", -1)))
			if moon != null and not _pending_cards.is_empty() \
					and e.take_from_hand(target.id, _pending_cards):
				# 先排下一个超限玩家，再 add_cover（它会把 p_cover_change 压到上面），
				# 保证盖牌变动钩子仍在下一名玩家之前结算
				e.push(SHandOverflow.new(harm_cause, harm_type, _no_morale))
				e.add_cover(moon.id, _pending_cards, moon.id, GConst.技能_新月庇护)
				moon.tap = true
				e.last_harm_cause = 0
				e.last_harm_type = 0
				e._broadcast_game()
				return BattleEngine.CONTINUE
		e.take_from_hand(target.id, _pending_cards)
		# 先排「继续处理下一个超限玩家 / 掉士气」，最后再调 to_discard：
		# 若这次弃牌被拦截（F6），拦截询问与结算会压在这两步之上先跑，符合「弃牌前」语义。
		# 先压「继续处理下一个超限玩家」，再压掉士气（后压先执行 → 士气先结算，与服务器一致）；
		# 下一个玩家共用同一份伤害上下文
		e.push(SHandOverflow.new(harm_cause, harm_type, _no_morale))
		if _no_morale:
			# 本次伤害声明不掉士气（F6 / 4702）：超限牌照弃，不压 SOverloadMorale；
			# 同时清掉「最近一次伤害」，避免后面的普通超限误挂这份伤害上下文
			e.last_harm_cause = 0
			e.last_harm_type = 0
		else:
			e.push(SOverloadMorale.new(target.id, _pending_over, GConst.CAUSE_OVERLOAD, harm_cause, harm_type))
		e.to_discard(_pending_cards, {"owner": target.id, "source": "hand", "cause": GConst.CAUSE_OVERLOAD, "face_up": false})
		e._log_discard(target.id, _pending_cards)
		e._broadcast_game()
		return BattleEngine.CONTINUE


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
			e._统计士气(target, amount, int(ctx.get("type", GConst.HarmType.None)))
		e.last_harm_cause = 0
		e.last_harm_type = 0
		e._broadcast_game()
		e._check_game_over()
		return BattleEngine.CONTINUE


## 技能执行（主动技能）：先校验，再交给角色；结束后补跑对应的「行动结束」钩子
class SkillRun:
	var kind: String
	var action: Dictionary
	## 是不是「启动」技能（不消耗行动：不记 F2 行动计数、不触发通用 p_action_end）
	var 启动: bool = false
	## 本技能行动所处阶段是不是额外行动、来源是什么（由 _进入技能行动 快照：
	## 等玩家回复期间可能又跑过别的状态，回来时不能再读引擎的当前阶段字段）
	var 额外: bool = false
	var 额外来源: int = 0
	## F2 行动计数是否已记（校验通过、行动成立时记一次）
	var 计数已记: bool = false
	## 本次技能行动是否被取消（engine.取消技能行动）：取消掉的行动要撤销计数、不触发 p_action_end
	var 已取消: bool = false
	var checked: bool = false
	var invoked: bool = false
	var after_pushed: bool = false
	func _init(k: String, a: Dictionary, free_skill: bool = false, extra: bool = false, cause: int = 0) -> void:
		kind = k
		action = a
		启动 = free_skill
		额外 = extra
		额外来源 = cause
	## 本次技能行动的基础行动种类（技能入口归入攻击 / 法术 / 特殊）
	func _基本种类() -> int:
		match kind:
			"attack": return GConst.ActionType.Attack
			"magic": return GConst.ActionType.Magic
		return GConst.ActionType.Special
	func _push_after(e: BattleEngine, src: int) -> void:
		if after_pushed:
			return
		after_pushed = true
		var ctx: Dictionary = {
			"player": src, "kind": kind, "is_skill": true,
			"action_id": int(action.get("action_id", 0)),
		}
		# 「启动」技能不是一次行动：照旧只触发 p_after_special（现有角色靠它收尾），不计入 F2
		if 启动:
			e.push(SHook.new("p_after_" + kind, ctx, []))
			return
		# 被取消的技能行动没真正发生：撤销计数，也不触发通用的「行动结束」
		if 已取消:
			if 计数已记:
				计数已记 = false
				var cur: BattlePlayer = e.p(src)
				if cur != null:
					cur.undo_action(kind, 额外)
			e.push(SHook.new("p_after_" + kind, ctx, []))
			return
		e._push_action_end_hooks("p_after_" + kind, ctx, 额外, 额外来源)
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
				e._回当前行动阶段()
				return BattleEngine.CONTINUE
			# 额外行动的出牌 / 目标限制（F2）：这份行动自带的规格同样约束技能行动里的牌与目标。
			# 技能把这次出牌视为某系时（如 3805 精灵的剑舞＝风系），系别白名单按视为系别放行。
			var 视为系别2: int = 0
			if 额外 and cur.role != null:
				视为系别2 = int(cur.role.call("技能视为系别", action))
			if e.校验额外行动限制(cur, e._额外行动数据(cur, 额外来源) if 额外 else {},
					_基本种类(), action.get("card_ids", []),
					action.get("dst_ids", []), true, 视为系别2) != GConst.GE_SUCCESS:
				e.send(cur.id, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Action, "commands": []})
				e._回当前行动阶段()
				return BattleEngine.CONTINUE
			# 基础效果的目标资格（F4 / 4601）：角色声明这次会把牌放到谁面前，就逐条问目标角色；
			# 被拒就驳回整个技能行动（不扣牌、不挂效果），与普攻 / 法术的校验同一口径
			if not e.校验基础效果放置目标(action):
				e.send(cur.id, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Action, "commands": []})
				e._回当前行动阶段()
				return BattleEngine.CONTINUE
			var rc: int = cur.role.call("v_" + kind + "_skill", action)
			if rc != GConst.GE_SUCCESS:
				e.send(cur.id, GConst.Msg.ErrorInput, {"error_type": GConst.CmdType.Action, "commands": []})
				e._回当前行动阶段()
				return BattleEngine.CONTINUE
			checked = true
			# F2：校验通过、行动成立时记一次（「启动」技能不算行动）
			if not 启动 and not 计数已记:
				计数已记 = true
				cur.record_action(kind, 额外)
		# 已经执行过一次且角色压入了状态（URGENT）→ 不再重复执行技能本体。
		# 例外：角色声明「URGENT 结算完还要接着做」（技能URGENT后重入，如摸牌要先走超限结算的
		# 7802 / 10601）—— 这时把 invoked 复位、再进一次本体，由角色自己按分步继续。
		if invoked:
			if cur.role == null or not cur.role.技能URGENT后重入(action):
				_push_after(e, cur.id)
				return BattleEngine.CONTINUE
			invoked = false
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
	_回当前行动阶段()
	return CONTINUE


## 驳回后回到「当前这个阶段」，而不是无条件退回普通行动阶段：
## 额外行动阶段被驳回时还要保持 额外 / 来源 / 当前那份行动的规格，
## 否则客户端会整排额外行动按钮消失（玩家表现就是「点确定后闪一下，选项全没了」）。
func _回当前行动阶段() -> void:
	if 行动额外 and not 当前额外行动数据.is_empty():
		var 允许: int = int(当前额外行动数据.get("allow_action", 行动允许))
		if 允许 <= 0:
			允许 = 行动允许
		var 阶段: SActionPhase = SActionPhase.new(允许, true, true, false,
			int(当前额外行动数据.get("cause", 0)))
		阶段.额外数据 = 当前额外行动数据
		push(阶段)
	else:
		push(SActionPhase.new())


func resolve_action(action_type: int, data: Dictionary) -> int:
	var cur: BattlePlayer = players.get(current_id)
	# 额外行动阶段：客户端选了「这一手要消耗哪份额外行动」（Action.extra_uid）→ 先换队，
	# 再按换后的放行种类过总闸。打牌、技能行动都走这里 ——
	# 以前只有出攻击牌会换队，所以「先点行动、再点技能」永远消耗服务端当前那一份。
	if cur != null and 行动额外:
		var 选中ID: int = int(data.get("extra_uid", 0))
		if 选中ID > 0 and 选中ID != int(当前额外行动数据.get("uid", 0)):
			if not _切换额外行动(cur, 选中ID, action_type):
				return _reject_action(cur)
	# 行动合法性总闸：对照原版 StateActionPhase → PlayerEntity::v_allow_action(action, allowAction, canGiveUp)。
	# 角色可覆写 v_allow_action 追加限制（如「审判满 4 时该阶段只能发动末日审判」「暗影抗拒禁用法术牌」）。
	# 启动技能（ActivateSkill）是独立类型：不看放行种类，只按「本回合第一个行动之前」判；
	# 角色自己的覆写仍要问一次（如仲裁满审判时专门放行），没覆写就跳过 base 的种类判定。
	if action_type == GConst.ActionType.ActivateSkill:
		if cur == null or not 可发动启动(cur.id):
			return _reject_action(cur)
		var 角色判定: int = BattleRole.V_NOT_OVERRIDE
		if cur.role != null:
			角色判定 = cur.role.v_allow_action(action_type, data.get("args", []), 行动允许, 行动可放弃)
		if 角色判定 != BattleRole.V_NOT_OVERRIDE and 角色判定 != GConst.GE_SUCCESS:
			return _reject_action(cur)
	else:
		var 总闸: int = cur.v_allow_action(action_type, data.get("args", []), 行动允许, 行动可放弃) if cur != null else GConst.GE_SUCCESS
		if 总闸 != GConst.GE_SUCCESS:
			return _reject_action(cur)
	# 发动过「启动」技能后本阶段禁止特殊行动（购买/合成/提炼）：客户端已把按钮收掉，这里兜底驳回
	if 行动禁特殊 and (action_type == GConst.ActionType.Special or action_type == GConst.ActionType.ActivateSkill):
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
		GConst.ActionType.ActivateSkill:
			_进入技能行动(cur, "special", data, true)
			return CONTINUE
		_:
			push(STurnEnd.new())
			return CONTINUE


## 技能行动入栈：普通技能用完即结束行动阶段；启动技能（ActivateSkill，如格斗家
## 【百式幻龙拳】【斗神天驱】）是免费动作，不消耗行动，结算完重新进入行动阶段让玩家继续本回合行动
func _进入技能行动(cur: BattlePlayer, kind: String, data: Dictionary, 是启动: bool = false) -> void:
	var 技能号: int = int(data.get("action_id", 0))
	# 「启动」现在是独立动作类型（ActivateSkill，由调用方传 是启动）；
	# 老口径（kind="special" + is_free_skill）保留兜底，兼容同号另有攻击 / 法术入口的技能。
	var 启动: bool = 是启动 or (kind == "special" and 技能号 > 0 and cur != null and cur.role != null \
			and cur.role.is_free_skill(技能号))
	if 启动:
		# 「启动」技能不消耗本回合行动，发动后行动阶段照旧继续；但只能再攻击 / 法术，
		# 不能再走特殊行动（启动技与特殊行动互斥）
		push(SActionPhase.new(行动允许, 行动可放弃, 行动额外, true))
	else:
		push(STurnEnd.new())
	# F2：把「是不是额外行动 / 来源」随技能行动快照下来（结算回来时引擎字段可能已被后续阶段覆盖）
	push(SkillRun.new(kind, data, 启动, 行动额外, 行动额外来源 if 行动额外 else 0))


## 请求跳过当前回合的行动阶段（F9 / 10602）：轮到 SActionPhase 时直接进入回合结束，
## 并把「本回合跳过行动阶段 / 来源」记下来供 10605 这类「跳过之后」的技能读取。
## 在回合开始钩子（p_before_turn_begin / p_turn_begin）或更早调用都有效；来源只用于判定/提示。
func 请求跳过行动阶段(来源: int = 0) -> void:
	skip_action_phase = true
	跳过行动阶段来源 = 来源


## 技能行动取消（角色在技能询问里点了「取消」，如【灵魂转换】的方向询问）：
## 让「技能用完即结束行动」的那个收尾改成重新进入行动阶段，玩家改做别的。
## 不这么做的话，取消＝本回合的行动白白用掉，回合直接结束。
## 只能在栈里就地设标记：run() 拿「状态下标还是不是自己」判断该状态是否自移除，
## 若在这里增删栈里非栈顶的状态（比如直接把 STurnEnd 抽掉），下标就错位、状态机当轮直接停摆
func 取消技能行动() -> void:
	for i: int in range(_states.size() - 1, -1, -1):
		if _states[i] is STurnEnd:
			(_states[i] as STurnEnd).回行动阶段 = true
			break
	# F2：被取消的技能行动其实没发生 —— 标记给 SkillRun，让它撤销行动计数、不触发 p_action_end
	for i: int in range(_states.size() - 1, -1, -1):
		if _states[i] is SkillRun:
			(_states[i] as SkillRun).已取消 = true
			break


## 无法行动：把手里的牌全部弃掉（亮出牌面 + 弃牌动画）再摸 4 张。不消耗本回合行动，
## 换完手牌重新进入行动阶段让玩家拿新牌继续行动。
## 客户端在「技能栏没可用技能、手牌全打不出去、特殊行动也做不了」时提示玩家点「确定」触发
func _do_unactional(cur: BattlePlayer) -> int:
	# 战斗日志：宣布不可行动本身也是一次行动声明
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Skill,
		"txt": "%s宣称不可行动" % _称号(cur),
		"id": cur.id,
	})
	# 不结束回合：换完手牌重新进入行动阶段
	push(SActionPhase.new())
	var old: Array = cur.hand_cards.duplicate()
	if not old.is_empty():
		take_from_hand(cur.id, old)
		to_discard(old, {"owner": cur.id, "source": "hand", "face_up": true})
		_log_discard(cur.id, old)
		# 把弃掉的牌亮出来给所有人看
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Show, "src_id": cur.id, "dst_id": cur.id, "card_ids": old, "is_real": true})
	# 摸 4 张走直连 draw：【无法行动】换手牌不算「技能让你摸牌」，不触发【水影】等「摸牌前发动」的响应；
	# 摸 4 张一般不会超上限，但手牌上限小于 4 的角色仍要照常结算爆牌
	push(SHandOverflow.new())
	draw(cur.id, 4)
	# 关键：摸完立刻发一次完整快照。否则客户端手里还是「弃牌后的空/旧手牌」，
	# 下一条行动询问会按旧数据重新判成「不可行动」，让玩家第二次把刚摸到的牌全弃掉。
	_broadcast_game()
	return CONTINUE


func _do_attack(cur: BattlePlayer, data: Dictionary) -> int:
	var cards: Array = data.get("card_ids", [])
	var dsts: Array = data.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		# 客户端没给出牌或目标（改包 / 界面状态错乱）：当作放弃这次行动
		push(STurnEnd.new())
		return CONTINUE
	# 额外攻击阶段里客户端本地切到了另一份额外行动：提交攻击时再换队（不重发行动询问，避免界面闪烁）。
	# 客户端回的是那一份行动的唯一 ID（同一技能挂两份时也能分开）；与当前这份不同才换。
	if 行动额外:
		var 参数: Array = data.get("args", [])
		var 选中ID: int = int(参数[0]) if not 参数.is_empty() else 0
		if 选中ID > 0 and 选中ID != int(当前额外行动数据.get("uid", 0)):
			_直接切换额外攻击(cur, 选中ID)
	# 提交上来的是实例号：删手牌 / 进弃牌堆按它走，牌的实例身份才不会被折成牌面；
	# 规则判定、钩子上下文、广播一律按牌面（同牌面的副本对规则完全等价）
	var 提交号: int = int(cards[0])
	var cid: int = GConst.牌号(提交号)
	var 提交实例卡: GCard = Data.get_card(提交号)
	var dst_id: int = int(dsts[0])
	if cur.v_attack(提交号, dst_id, players) != GConst.GE_SUCCESS:
		if OS.is_debug_build() and 行动额外:
			print("[额外行动排查] 攻击被拒(v_attack)：来源=%d 牌=%d 目标=%d 结果=%d 在手=%s" % [
				行动额外来源, 提交号, dst_id, cur.v_attack(提交号, dst_id, players),
				str(cur.has_hand_card(提交号))])
		return _reject_action(cur)
	# 防守方角色可拒绝被选为目标（如暗杀者潜行中「不能成为主动攻击的目标」）
	var dst_p: BattlePlayer = players.get(dst_id)
	if dst_p != null and dst_p.v_attacked() != GConst.GE_SUCCESS:
		if OS.is_debug_build() and 行动额外:
			print("[额外行动排查] 攻击被拒(v_attacked)：来源=%d 目标=%d 结果=%d" % [
				行动额外来源, dst_id, dst_p.v_attacked()])
		return _reject_action(cur)
	# 额外行动的目标 / 出牌限制（F2，如 10704 只能打手牌更多的对手、4501 只能用技类攻击牌）
	if 校验额外行动限制(cur, 当前额外行动数据 if 行动额外 else {},
			GConst.ActionType.Attack, [提交号], [dst_id]) != GConst.GE_SUCCESS:
		if OS.is_debug_build() and 行动额外:
			print("[额外行动排查] 攻击被拒(额外行动限制)：来源=%d 牌=%d 目标=%d 规格=%s" % [
				行动额外来源, cid, dst_id, str(当前额外行动数据)])
		return _reject_action(cur)
	# 这次主动攻击已经成立：「本回合的下次主动攻击只能打谁」的回合级标记到此消费
	# （剑之子【剑残影】10804；它是玩家身上的标记，与这份行动 / 这张牌的规格无关）
	cur.set_attack_lock(-1)
	_记录行动并收尾(cur, "attack", "p_after_attack", {"player": cur.id, "card_id": 提交号, "dst": dst_id})
	# 攻击方向也跑一次「视为」判定（与应战的 p_reattack 同一套）：角色可把这张攻击牌换成另一张结算
	# （如噬神者在这里记录本次打出的【魔刃】/【异刃】）。
	# 真牌照样展示 + 进弃牌堆，本次攻击按「视为」的那张结算（系别就是那张牌的系别）
	var 出牌: Dictionary = {"player": cur.id, "card_id": 提交号, "card_id_instance": 提交号, "改用": cid}
	if cur.role != null:
		cur.role.call_hook("p_attack_card", 出牌)
	# 刃的归属者可能不是当前攻击者（侵刻给出去的牌）；归属者仍要记本次刃，
	# 这样渗蚀/侵刻/噬灭/殇灭按「你的刃」判断，而不是按谁在用
	var 归属者: int = 刃归属者(提交号)
	if 归属者 >= 0 and 归属者 != cur.id:
		var 归属玩家: BattlePlayer = players.get(归属者)
		if 归属玩家 != null and 归属玩家.role != null:
			归属玩家.role.call_hook("p_attack_card", 出牌)
	var 用牌: int = int(出牌.get("改用", cid))
	# 没有「视为」时，规则/伤害直接用提交的实例；有「视为」时保留虚拟牌面
	if 用牌 == cid:
		用牌 = 提交号
	# 规则 / 伤害仍用「用牌」；虚拟攻击牌另给客户端一张同系普通斩击牌做音效/特效表现
	var 表现用牌: int = 攻击表现牌(用牌)
	var 表现面: int = GConst.牌号(表现用牌)
	var harm: Dictionary = {
		"src": cur.id, "dst": dst_id, "point": 攻击基础伤害(cur.id), "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 用牌, "is_active": true,
		# 真正打出去的那张实体牌（实例号）：card_id 被「视为」换成虚拟牌面时靠它找回原件。
		# 角色据此区分「真实牌」与「被视为的虚拟牌」（如女仆长【影之风】只认真实牌）
		"card_id_instance": 提交号,
		# 命格按真正打出的那张牌算（「视为」只换系别/牌面）：阴阳师【阴阳转换】等按它匹配
		"fate_card_id": 提交号,
	}
	# 先压攻击状态，再离手：take_from_hand 的「展示手牌」钩子会压在这次攻击之上，
	# 保持封印等钩子先于本次攻击结算（与旧顺序一致）。
	# 魔刃/异刃把进弃牌堆/渗蚀推迟到 timeline1 之后；普通牌保持原来的「攻击前弃置」。
	var 是噬神刃: bool = cid == GConst.噬神者_魔刃卡 or cid == GConst.噬神者_异刃卡
	if 是噬神刃:
		push(SAttackCard.new(cur.id, dst_id, 用牌, harm, 提交号))
		take_from_hand(cur.id, [提交号], true)
	else:
		push(SAttackCard.new(cur.id, dst_id, 用牌, harm, -1))
		take_from_hand(cur.id, [提交号], true)
		to_discard([提交号], {"owner": cur.id, "source": "hand", "cause": GConst.CAUSE_ATTACK})
	# 广播里面把「视为」的那张放 as_card_id（同应战那条）：客户端按它出声、出特效
	# （「视为」换掉系别时，客户端按它播对应系的斩击特效 / 攻击音）；
	# 摊牌与日志仍用真正打出的牌
	broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true, "as_card_id": 表现面 if 表现面 != cid else -1,
		"card_elements": [提交实例卡.element_enum() if 提交实例卡 != null else 0]})
	return CONTINUE


func _do_magic(cur: BattlePlayer, data: Dictionary) -> int:
	var cards: Array = data.get("card_ids", [])
	var dsts: Array = data.get("dst_ids", [])
	if cards.is_empty():
		push(STurnEnd.new())
		return CONTINUE
	var 提交号: int = int(cards[0])
	var cid: int = GConst.牌号(提交号)
	var card: GCard = Data.get_card(提交号)
	if card == null or not cur.has_hand_card(提交号):
		return _reject_action(cur)
	# 角色可用 p_before_magic 禁止本次法术（如「暗影形态不能使用法术牌」；该钩子不得等待玩家输入）
	var gate: Dictionary = {"player": cur.id, "card_id": 提交号, "forbidden": false}
	if cur.role != null:
		cur.role.call_hook("p_before_magic", gate)
	if bool(gate.get("forbidden", false)):
		return _reject_action(cur)
	# 额外行动的出牌 / 目标限制（F2，如 10702 的额外法术行动只能用【魔弹】）
	if 校验额外行动限制(cur, 当前额外行动数据 if 行动额外 else {},
			GConst.ActionType.Magic, [提交号], dsts) != GConst.GE_SUCCESS:
		return _reject_action(cur)
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else cur.id
	var name_enum: int = card.card_name_enum()
	# 目标资格（F4 / 4601）：圣盾 / 虚弱 / 中毒都是「放到目标面前的基础效果」，能不能放统一问目标角色。
	# 必须在扣牌 / 挂效果之前拦下，否则被拒的目标会白吃一张牌
	if name_enum == GConst.CardName.Shield or name_enum == GConst.CardName.Weaken \
			or name_enum == GConst.CardName.Poison:
		if v_basic_effect_target(dst_id, 提交号) != GConst.GE_SUCCESS:
			return _reject_action(cur)
	if name_enum == GConst.CardName.Shield:
		if cur.v_shield(dst_id, players) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [提交号])
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		# 先压「行动结束」再压基础效果变更钩子：LIFO 下钩子先跑（对照服务端 basicMagic：
		# StateAfterMagic 先入栈、随后 setStateUseCard 把 StateBasicEffectChange 压在其上）。
		# 顺序颠倒会把钩子压在回合结束乃至下家整回合之下，天使羁绊这类钩子实际不会触发
		_记录行动并收尾(cur, "magic", "p_after_magic", {"player": cur.id, "card_id": 提交号})
		add_basic_effect(dst_id, 提交号, cur.id, GConst.CAUSE_USE)
		# 「展示手牌」钩子必须最后压（同 _do_attack 与应战抵挡那条）：压在动作状态之上才先执行。
		# 跟着 take_from_hand(已展示=true) 在开头就压的话，它会被埋在「回合结束」之下，而栈上又不断
		# 压入下一回合的状态 —— 这个钩子永远轮不到执行，冰霜祷言这种「公开打出水系牌时发动」的响应
		# 就从不触发（水系法术牌不触发的根因）
		push_show_hand(cur.id, [提交号])
		_broadcast_game()
		return CONTINUE
	if name_enum == GConst.CardName.Weaken:
		if cur.v_weaken(dst_id, players) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [提交号])
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		# 同上：行动结束先入栈，基础效果变更钩子后压（LIFO 下钩子先跑）
		_记录行动并收尾(cur, "magic", "p_after_magic", {"player": cur.id, "card_id": 提交号})
		add_basic_effect(dst_id, 提交号, cur.id, GConst.CAUSE_USE)
		push_show_hand(cur.id, [提交号])
		_broadcast_game()
		return CONTINUE
	if name_enum == GConst.CardName.Poison:
		take_from_hand(cur.id, [提交号])
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		# 同上：行动结束先入栈，基础效果变更钩子后压（LIFO 下钩子先跑）
		_记录行动并收尾(cur, "magic", "p_after_magic", {"player": cur.id, "card_id": 提交号})
		add_basic_effect(dst_id, 提交号, cur.id, GConst.CAUSE_USE)
		push_show_hand(cur.id, [提交号])
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
		if target >= 0 and cur.v_missile(提交号, target) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [提交号])
		_记录行动并收尾(cur, "magic", "p_after_magic", {"player": cur.id, "card_id": 提交号})
		if target >= 0:
			broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": target, "card_ids": [cid], "is_real": true})
			# 交给目标自己决定：打出【魔弹】继续传递 / 出【圣光】抵挡 / 放弃并承受伤害。
			# 即使他手里既没有【魔弹】也没有【圣光】，也要问一次并等他应答（对照服务端 StateMissiled）
			var used: Array[int] = [cur.id, target]
			push(SMissileAsk.new(target, cur.id, MISSILE_BASE_POINT, 顺向, used))
		# 打出的【魔弹】进弃牌堆要压在「行动结束」之后调（to_discard 在有角色能响应时只压一个
		# 弃牌前拦截状态，如 4704【三秒原则】）。压在 take_from_hand 后面直接调的话，这个拦截状态
		# 会被随后压入的传递询问 / 展示手牌 / 行动结束钩子 / STurnEnd 埋在最底下，那一轮询问
		# 永远轮不到 —— 表现就是「队友直接使用【魔弹】，暴食少女的三秒原则不响应」。
		# 压在传递询问之后 = 它先于传递结算被问（「使用完」＝这张牌打出、要进弃牌堆的那一刻，
		# 不是整条魔弹传递结算完），顺序：展示手牌 → 弃牌前拦截（要不要收走）→ 魔弹传递 → 行动结束。
		to_discard([提交号], {"owner": cur.id, "source": "hand", "cause": GConst.CAUSE_MISSILE})
		# 展示手牌钩子最后压：压在动作状态与应战询问之上，先于它们执行（对照服务端 basicMagic 的
		# StateBeforeMagic → setStateUseCard(展示手牌) → StateMissiled 顺序）；压在开头则永远轮不到
		push_show_hand(cur.id, [提交号])
		return CONTINUE
	# 其余法术牌（如【圣光】只作响应）不能主动施放
	return _reject_action(cur)


## 从 from_id 出发沿 post（右手边）/ pre 方向最近的一名队友（不含自己）；没有则 -1。
## F9 / 10601「你右手边最近的队友」用它（角色侧另有 BattleRole.nearest_teammate_id 包装）。
func nearest_teammate_id(from_id: int, post_dir: bool = true) -> int:
	var cur: BattlePlayer = players.get(from_id)
	if cur == null:
		return -1
	var nid: int = cur.post_id if post_dir else cur.pre_id
	for _i: int in range(order.size()):
		var pp: BattlePlayer = players.get(nid)
		if pp == null:
			return -1
		if pp.color == cur.color and pp.id != cur.id:
			return nid
		nid = pp.post_id if post_dir else pp.pre_id
	return -1


func _nearest_enemy(cur: BattlePlayer) -> int:
	var nid: int = cur.post_id
	for _i: int in range(order.size()):
		var pp: BattlePlayer = players.get(nid)
		if pp != null and pp.color != cur.color:
			return nid
		nid = next_id(nid)
	return -1


## 本次可以把魔弹传给谁（候选）：当前方向上最近、本轮还没接过的对手。
## 本轮所有人都接过之后开新一轮；新一轮的第一个目标不能是刚把魔弹传给自己的人（禁选）。
func _missile_relay_targets(holder: int, post_dir: bool, used: Array[int], 禁选: int = -1) -> Array[int]:
	var out: Array[int] = []
	var 顺: int = _next_missile_target(holder, post_dir, used, 禁选)
	if 顺 < 0:
		# 本轮没有可接的人：重置本轮参与记录，开始新一轮，但仍跳过刚传给自己的人
		var 新一轮: Array[int] = [holder]
		顺 = _next_missile_target(holder, post_dir, 新一轮, 禁选)
	if 顺 >= 0:
		out.append(顺)
	return out


## 该方向上最近的一名「本轮还没参与过魔弹传递」的对手；禁选 = 刚把魔弹传给自己的人。
## 本轮所有对手都参与过就返回 -1，由调用方决定是否开始新一轮。
func _next_missile_target(from_id: int, post_dir: bool, used: Array[int], 禁选: int = -1) -> int:
	var cur: BattlePlayer = players.get(from_id)
	if cur == null:
		return -1
	var nid: int = cur.post_id if post_dir else cur.pre_id
	for _i: int in range(order.size()):
		var pp: BattlePlayer = players.get(nid)
		if pp == null:
			return -1
		if pp.color != cur.color and not used.has(nid) and nid != 禁选:
			return nid
		nid = pp.post_id if post_dir else pp.pre_id
	return -1


## 目标若拥有【圣盾】或视作【圣盾】的【天使之墙】，移除之并返回 true（魔弹视作未命中）
func _missile_block_by_basic(target_id: int) -> bool:
	var dst: BattlePlayer = players.get(target_id)
	if dst == null or dst.基础效果禁用:
		return false
	var cid: int = -1
	if dst.check_basic_effect_name(GConst.CardName.Shield):
		cid = _find_basic_card(dst, GConst.CardName.Shield)
	elif dst.check_basic_effect_skill(GConst.技能_天使之墙):
		cid = _find_basic_card_by_skill(dst, GConst.技能_天使之墙)
	if cid < 0:
		return false
	# F4：圣盾 / 天使之墙挡下魔弹＝一次「基础效果触发」
	remove_basic_effect(target_id, cid, GConst.CAUSE_MISSILE, -1, true)
	to_discard([cid])
	return true


## 这次打出的牌在系统里该「视为」哪张牌用，返回视为的牌号；-1＝它本身就是那张牌（不视为别的）。
## 目前只有【魔弹】有这种用法：地/火牌当【魔弹】打出去（【魔弹融合】发起、响应魔弹时拿地/火牌
## 继续传递）→ 返回【魔弹】牌号。出牌音效/特效、以及后续任何「这次是不是魔弹」的判断都按它走；
## 真正打出的那张地/火牌仍写在 card_ids 里（要展示、也确实进了弃牌堆）。
## 注意：0 是合法牌号（卡表#0 圣盾），「不视为别的牌」只能返回 -1。
func missile_as_card(card_id: int) -> int:
	var 牌: GCard = Data.get_card(card_id)
	if 牌 != null and 牌.card_name_enum() == GConst.CardName.Missile:
		return -1
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
		_记录行动并收尾(cur, "special", "p_after_special", {"player": cur.id, "card_id": -1, "special_action": true, "action_id": aid})
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
		# 合成星杯的附带：对方阵容 −1 士气（对照原版：星杯 +1、摸 3 张、敌方士气 −1 属同一次合成）。
		# 非伤害来源（type = NONE），与逆反居合斩 / 暗月诅咒同一入口走同步掉士气链；
		# 同步入口不广播，故扣完自己补一次，客户端才能看到士气数字变化。
		var 敌方id: int = _nearest_enemy(cur)
		if 敌方id >= 0:
			lose_morale(p(敌方id), 1, GConst.CAUSE_SYNTHESIZE)
			_broadcast_game()
			if phase == Phase.Over:
				return CONTINUE
		_记录行动并收尾(cur, "special", "p_after_special", {"player": cur.id, "card_id": -1, "special_action": true, "action_id": aid})
		push(SHandOverflow.new())
		return CONTINUE
	if aid == GConst.SpecialAction.Extract:
		var dsts: Array = data.get("dst_ids", [])
		# 提炼校验：常规提炼按自身空位；【冒险者天堂】自己的那份按自身空位、队友那份按队友空位
		# （由角色覆写 v_extract）
		if cur.v_extract(args, team_gem[cur.color], team_crystal[cur.color], dsts) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		# F9 提炼前钩子：全体角色同步调用（不得等待玩家输入），可把 forbidden 置 true 取消本次提炼
		var 提炼前: Dictionary = {
			"player": cur.id, "args": args.duplicate(), "dst_ids": dsts.duplicate(),
			"forbidden": false,
		}
		for pid: int in order:
			var 看提炼: BattlePlayer = players.get(pid)
			if 看提炼 != null and 看提炼.role != null:
				看提炼.role.call_hook("p_before_extract", 提炼前)
		if bool(提炼前.get("forbidden", false)):
			return _reject_action(cur)
		_log_special(cur, aid)
		# 常规提炼 args = [宝石, 水晶]；「星石直接交给队友」的提炼（【冒险者天堂】1202 /
		# 【恩典神授】3903）头位是 GConst.提炼转交标记 里的值，之后才是自己那份 / 队友那份
		var 是天堂: bool = not args.is_empty() and GConst.是提炼转交标记(int(args[0]))
		# 本次提炼的星石总数（供 p_after_extract / 10604 读取；天堂按自己+队友两份合计）
		var 提炼宝石: int = 0
		var 提炼水晶: int = 0
		if not 是天堂:
			# 常规提炼：从战绩区取出、归自己
			var g3: int = int(args[0]) if args.size() > 0 else 0
			var c3: int = int(args[1]) if args.size() > 1 else 0
			提炼宝石 = g3
			提炼水晶 = c3
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
			提炼宝石 = 自己宝石 + 队友宝石
			提炼水晶 = 自己水晶 + 队友水晶
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
		_记录行动并收尾(cur, "special", "p_after_special", {"player": cur.id, "card_id": -1, "special_action": true, "action_id": aid})
		if 是天堂:
			# 发动了【冒险者天堂】：给角色一次广播技能通知的机会
			push(SHook.new("p_extract_to", {"player": cur.id, "dst_ids": dsts}, []))
		# F9 提炼后钩子：星石已经移动；可等待（10604 这类「队友提炼后」的响应在这里结算）
		push(SHook.new("p_after_extract", {
			"player": cur.id, "gem": 提炼宝石, "crystal": 提炼水晶,
			"args": args.duplicate(), "dst_ids": dsts.duplicate(), "is_heaven": 是天堂,
		}, []))
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
		"special_action": aid,
	})


# ============================================================
# 士气与结束
# ============================================================
## 掉士气（带角色钩子；ctx 的 cause/harm_cause = 本次掉士气来源，type = 伤害类型）
## 与服务器一致：before / true 钩子对「所有玩家」按座位序调用（如蝶舞的凋零形态要限制
## 对手的士气下降、月女的新月庇护要响应队友的士气下降），钩子内部按 ctx["dst"] 自行判断是否相关。
## 限制：本实现为同步调用，钩子内不能等待玩家输入。超限掉士气走 SOverloadMorale（可等待，见下），
## 需要等待支付的技能（如天使的神之庇护 706）在那边实现。
## 本入口只用于「非伤害」来源（合成星杯扣对方士气 / 逆反居合斩 / 暗月诅咒）：对照服务端，这类惩罚的 harm.type = HARM_NONE、
## harm.cause = 技能 cause，不能沿用 last_harm_*（最近一次伤害的上下文）——否则依 type 判定的钩子
## （新月庇护 / 神之庇护 / 舞女同生 / 蝶舞凋灵…）会把非伤害惩罚误判成「因伤害掉士气」。
## 因伤害掉士气（手牌超限）走 SOverloadMorale，其 harm 上下文由伤害那一拍显式带入。
func lose_morale(target: BattlePlayer, amount: int, cause: int) -> void:
	var ctx: Dictionary = {
		"dst": target.id, "amount": amount, "cause": cause,
		"harm_cause": cause, "type": GConst.HarmType.None,
		# 同步链：钩子内部不能等玩家输入。需要询问的掉士气响应（琉璃境 8205 等）
		# 据此跳过这条路，只在 SOverloadMorale（可等待）里响应。
		"sync": true,
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
	var 前士气: int = team_morale[target.color]
	set_morale(target.color, team_morale[target.color] - amount)
	_check_game_over()
	# 同步链里不能等玩家输入：士气**真的降了**再补压一条可等待的「事后」钩子，
	# 让【琉璃境】这类「我方士气下降时」的响应仍能问（士气已扣，响应不改变它）。
	if team_morale[target.color] < 前士气 and phase != Phase.Over:
		push(SHook.new("p_lose_morale_after", ctx, []))


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
	_上报事件("battle_end", round_id)
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Notice,
		"txt": "游戏结束，%s方获胜！" % ("红" if win_color == GConst.RED else "蓝"),
		"id": 0,
	})


# ============================================================
# 对局埋点（battle_start / round_end / battle_end）
# 属性名、字段名、阵营口径都必须与埋点方案一致，改之前先对一遍方案。
# ============================================================
## 上报一次对局事件：属性按当前状态现算。
## current_round：battle_start = 0（还没进入回合），round_end = 刚结束的那一回合，
## battle_end = 结束时的回合
func _上报事件(事件名: String, 回合数: int) -> void:
	if not telemetry_cb.is_valid():
		return
	telemetry_cb.call(事件名, _埋点属性(回合数))


## 回合结束：先按「刚打完的这一回合」上报，再清统计（下一回合从 0 记）
func _回合结束埋点() -> void:
	_上报事件("round_end", round_id)
	_回合统计.clear()


## 三个事件共用的 15 个属性里属于对局状态的这 12 个；
## 另外 3 个（report_time / game_version / is_test_data）由 telemetry.gd 在上报时补。
## team 0 = 红，team 1 = 蓝（引擎颜色是 1 红 / 0 蓝，转换见 _埋点阵营）。
func _埋点属性(回合数: int) -> Dictionary:
	var 明细: Array = []
	for pid: int in order:
		var pp: BattlePlayer = players.get(pid)
		if pp == null:
			continue
		var 统计: Dictionary = _回合统计.get(pid, {})
		明细.append({
			"character_id": str(pp.role_id),
			"player_name": pp.player_name,
			"steam_id": str(玩家标识.get(pid, pp.player_name)),
			"team": _埋点阵营(pp.color),
			# 能量拆红蓝：红 = 宝石（gem），蓝 = 水晶（crystal）
			"red_energy": pp.gem,
			"blue_energy": pp.crystal,
			"hand_card": pp.hand_cards.size(),
			"heal_current": pp.cross_num,
			# 本回合施加出去的治疗（按输出量记，含溢出；给队友/自己算友方，给敌方算敌方）
			"heal_amount": int(统计.get("heal_amount", 0)),
			"heal_enemy": int(统计.get("heal_enemy", 0)),
			"attack_damage": int(统计.get("attack_damage", 0)),
			"attack_self_damage": int(统计.get("attack_self_damage", 0)),
			"spell_damage": int(统计.get("spell_damage", 0)),
			"spell_self_damage": int(统计.get("spell_self_damage", 0)),
			"morale_damage": int(统计.get("morale_damage", 0)),
			"morale_self_damage": int(统计.get("morale_self_damage", 0)),
		})
	return {
		"battle_id": battle_id,
		"player_count": 明细.size(),
		"character_details": 明细,
		"team_0_morale": team_morale[GConst.RED],
		"team_1_morale": team_morale[GConst.BLUE],
		"current_round": 回合数,
		"team_0_star_cup_count": team_grail[GConst.RED],
		"team_1_star_cup_count": team_grail[GConst.BLUE],
		# 星石拆红蓝：红 = 宝石（gem），蓝 = 水晶（crystal）
		"team_0_red_star_stone": team_gem[GConst.RED],
		"team_0_blue_star_stone": team_crystal[GConst.RED],
		"team_1_red_star_stone": team_gem[GConst.BLUE],
		"team_1_blue_star_stone": team_crystal[GConst.BLUE],
	}


## 埋点里的阵营编号：team_0 = 红，team_1 = 蓝。
## 引擎自己那套是「1 红 / 0 蓝」（GConst.RED / BLUE），正好相反，别混。
func _埋点阵营(color: int) -> int:
	return 0 if color == GConst.RED else 1


## 本回合施加出去的治疗：记在「施加者」头上，按输出量算（含溢出）。
## 受益者与施加者同阵营算友方（含自己给自己加），否则算敌方。整笔被禁疗作废的不计。
func _统计治疗(来源id: int, 受益id: int, 点: int) -> void:
	var 来源: BattlePlayer = players.get(来源id)
	var 受益: BattlePlayer = players.get(受益id)
	if 来源 == null or 受益 == null or 点 <= 0:
		return
	_加统计(来源id, "heal_amount" if 来源.color == 受益.color else "heal_enemy", 点)


## 伤害真正落地时记一笔（SGateTimeline6 之后进 SHarmTimeline6：治疗已抵完、伤害转移已改好目标）。
## attack_* = 攻击伤害，spell_* = 法术伤害；承受者与发起者同阵营算「自残」，否则算「对敌方」。
func _统计伤害(harm: Dictionary) -> void:
	var 点: int = int(harm.get("point", 0))
	var 类型: int = int(harm.get("type", GConst.HarmType.None))
	var 我: BattlePlayer = players.get(int(harm.get("src", -1)))
	var 他: BattlePlayer = players.get(int(harm.get("dst", -1)))
	if 点 <= 0 or 我 == null or 他 == null or not _是伤害类型(类型):
		return
	var 前缀: String = "attack" if 类型 == GConst.HarmType.Attack else "spell"
	_加统计(我.id, 前缀 + ("_self_damage" if 我.color == 他.color else "_damage"), 点)
	_最后伤害来源 = 我.id


## 超限掉士气：归属到「造成这次伤害的那个角色」。
## 非伤害来源的掉士气（合成星杯扣士气、技能惩罚等，type = None）记不到具体角色头上，这里不计。
func _统计士气(target: BattlePlayer, 点: int, 伤害类型: int) -> void:
	if 点 <= 0 or target == null or not _是伤害类型(伤害类型):
		return
	var 来源: BattlePlayer = players.get(_最后伤害来源)
	if 来源 == null:
		return
	_加统计(来源.id, "morale_self_damage" if 来源.color == target.color else "morale_damage", 点)


func _加统计(pid: int, 键: String, 点: int) -> void:
	var 统计: Dictionary = _回合统计.get(pid, {})
	统计[键] = int(统计.get(键, 0)) + 点
	_回合统计[pid] = 统计


func _是伤害类型(t: int) -> bool:
	return t == GConst.HarmType.Attack or t == GConst.HarmType.Magic

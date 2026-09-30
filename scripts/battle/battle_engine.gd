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

## 引擎里要单独处理的技能号（就是「技能表#N」的 N）
const 技能_天使之墙: int = 701

enum Phase { Idle, Playing, Over }

## 回复超时（毫秒）：普通玩家 60s；已掉线玩家 5s（避免队友长时间干等）
## 这个值就是「行动等待时间」—— 对局里所有要玩家回话的询问（行动/应战/技能/弃牌/魔弹传递…）都用它
const RESPONSE_TIMEOUT_MS: int = 60000
const OFFLINE_TIMEOUT_MS: int = 5000

## 【魔弹】的初始伤害（每被传递一次 +1）
const MISSILE_BASE_POINT: int = 2

var room_id: int = 0
## 房间名与房间设定人数：由服务端建房时写入，随 Game 快照下发，
## 房间准备界面据此显示房名与「已到 / 应到」人数
var room_name: String = ""
var room_max_player: int = 0
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
var _await_id: int = -1
var _await_kind: int = -1
var _reply: Dictionary = {}
var _has_reply: bool = false
## 当前等待的截止时刻（Time.get_ticks_msec() 口径，0 表示当前没有在等）
var wait_deadline_ms: int = 0
## 本次等待的总时长（毫秒）：客户端按「剩余/总时长」画进度条
var wait_total_ms: int = 0
## 掉线玩家标记：player_id -> true
var offline_players: Dictionary = {}
## 最近一次 ask_respond 的询问号与参数（超时时据此构造默认回复）
var _pending_respond_id: int = 0
var _pending_args: Array = []
var _running: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# ============================================================
# 房间内玩家登记（开局前）
# ============================================================
func add_player(pid: int, color: int, pname: String) -> void:
	if players.has(pid):
		return
	var bp: BattlePlayer = BattlePlayer.new(pid, color, pname)
	players[pid] = bp
	if not order.has(pid):
		order.append(pid)
		order.sort()
	_rebuild_links()


func remove_player(pid: int) -> void:
	players.erase(pid)
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


## 未选边的玩家自动补到人数少的一边
func balance_colors() -> void:
	var red_n: int = 0
	var blue_n: int = 0
	for pid: int in order:
		match players[pid].color:
			GConst.RED: red_n += 1
			GConst.BLUE: blue_n += 1
	for pid: int in order:
		if players[pid].color == GConst.TEAM_NONE:
			if red_n <= blue_n:
				players[pid].color = GConst.RED
				red_n += 1
			else:
				players[pid].color = GConst.BLUE
				blue_n += 1


func _rebuild_links() -> void:
	for i: int in range(order.size()):
		var p: BattlePlayer = players[order[i]]
		p.pre_id = order[(i - 1 + order.size()) % order.size()]
		p.post_id = order[(i + 1) % order.size()]
	if not order.is_empty():
		first_id = order[0]


# ============================================================
# 开局
# ============================================================
func start(role_pool: Array) -> void:
	start_with_roles({}, role_pool)


## 用「选将阶段选定的角色」开局；role_map: player_id -> role_id
## 保留 start(pool) 的随机分配入口，二者共用同一套开局初始化
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
		var p: BattlePlayer = players[pid]
		p.hand_cards.clear()
		p.cover_cards.clear()
		p.basic_effects.clear()
		p.ready = true
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
	_broadcast_game()
	broadcast(GConst.Msg.TurnBegin, {"id": current_id, "round": round_id})
	push(SCheckTurnStart.new())
	run()


func _assign_roles(role_pool: Array) -> void:
	var pool: Array = role_pool.duplicate()
	_shuffle_arr(pool)
	if pool.is_empty():
		return
	for i: int in range(order.size()):
		var pid: int = order[i]
		var rid: int = int(pool[i % pool.size()])
		players[pid].role_id = rid
		players[pid].role = BattleRole.create(rid, players[pid], self)


## 按选将结果分配角色（role_map: player_id -> role_id）
func _assign_roles_by_map(role_map: Dictionary) -> void:
	for pid: int in order:
		var rid: int = int(role_map.get(pid, 0))
		if rid <= 0:
			continue
		players[pid].role_id = rid
		players[pid].role = BattleRole.create(rid, players[pid], self)


func _shuffle_arr(a: Array) -> void:
	for i: int in range(a.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# ============================================================
# 状态机驱动
# ============================================================
func run() -> void:
	if _running:
		return
	_running = true
	# 安全阀：单次驱动的状态处理上限，避免异常状态链把主线程卡死
	var budget: int = 20000
	while not _states.is_empty():
		budget -= 1
		if budget <= 0:
			break
		var idx: int = _states.size() - 1
		var st: Variant = _states[idx]
		var r: int = st.handle(self)
		if r == WAIT:
			break
		if r == SUSPEND:
			# 本状态请求「先执行我压入的新状态，之后再回来继续我」
			continue
		if idx >= _states.size():
			break
		if _states[idx] == st:
			_states.remove_at(idx)
		else:
			break
	_running = false


func push(st: Variant) -> void:
	_states.append(st)


func wait_for(pid: int, kind: int) -> void:
	_await_id = pid
	_await_kind = kind
	_has_reply = false
	# 登记截止时刻：掉线玩家用更短的超时，避免队友长时间干等
	var timeout: int = OFFLINE_TIMEOUT_MS if offline_players.has(pid) else RESPONSE_TIMEOUT_MS
	wait_deadline_ms = Time.get_ticks_msec() + timeout
	wait_total_ms = timeout
	# 广播一次对局信息，让所有客户端知道「现在在等谁、还剩多久」（界面据此画等待进度条）
	_broadcast_game()


func has_reply() -> bool:
	return _has_reply


func take_reply() -> Dictionary:
	# 注意：必须先取出引用再清空，否则返回的是空字典
	var r: Dictionary = _reply
	_has_reply = false
	_await_id = -1
	wait_deadline_ms = 0
	wait_total_ms = 0
	_reply = {}
	return r


func on_message(pid: int, kind: int, data: Dictionary) -> void:
	if _await_id != pid or kind != _await_kind:
		# 临时诊断：客户端发来的行动/应答被丢掉时打出来（正常收工前删掉这行）
		print("[战斗诊断] 丢弃消息：来自 %d 类型 %d，当前在等 %d 的类型 %d；内容=%s" % [
			pid, kind, _await_id, _await_kind, str(data)])
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
	# 构造默认回复（等价客户端点「放弃 / 不发动」）写入，交给状态机继续推进
	_reply = _build_timeout_reply(pid, kind)
	_has_reply = true
	_await_id = -1
	wait_deadline_ms = 0
	wait_total_ms = 0
	_broadcast_game()
	_notice_timeout(pid, kind)
	run()


## 构造超时默认回复：与客户端「放弃 / 不发动」等价
func _build_timeout_reply(pid: int, kind: int) -> Dictionary:
	if kind == GConst.Msg.Action:
		# 行动询问（ask_action 下发 CmdReq/Action）
		var cur: BattlePlayer = players.get(pid)
		# 规则可能禁止「放弃」（如仲裁者审判满 4 时必须发动末日审判）：
		# 此时从角色可用技能里挑一个能立即执行的默认动作，避免超时后反复重问造成死循环
		if cur != null and cur.role != null and cur.v_allow_action(GConst.ActionType.None, []) != GConst.GE_SUCCESS:
			var 自动动作: Dictionary = _auto_legal_action(cur)
			if not 自动动作.is_empty():
				return 自动动作
		# 默认放弃行动
		return {
			"action_type": GConst.ActionType.None, "action_id": 0,
			"src_id": pid, "dst_ids": [], "card_ids": [], "args": [],
		}
	# 应答询问：按询问号选择默认项
	var rid: int = _pending_respond_id
	var args: Array = []
	if rid >= 100:
		# 技能询问（ask_skill 以技能号作为询问号）→ 不发动
		args = [0]
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
	}


## 超时代打：从玩家当前可用技能中挑一个「能立即执行」的默认动作（无可选时返回空字典）
## 用于规则禁止「放弃」时（如仲裁者审判满 4），避免超时默认回复被驳回后无限重问
func _auto_legal_action(cur: BattlePlayer) -> Dictionary:
	if cur.role == null:
		return {}
	for 技能: Dictionary in cur.role.available_skills():
		var 类型: int = int(技能.get("type", 0))
		var 技能号: int = int(技能.get("id", 0))
		# 需要选牌的技能无法自动代打（缺牌信息）
		if int(技能.get("need_card", 0)) > 0:
			continue
		var 目标列表: Array = []
		if int(技能.get("need_target", 0)) > 0:
			var 目标: int = _nearest_enemy(cur)
			if 目标 < 0:
				continue
			目标列表 = [目标]
		var 候选: Dictionary = {
			"action_type": 类型, "action_id": 技能号, "src_id": cur.id,
			"dst_ids": 目标列表, "card_ids": [], "args": [],
		}
		if cur.v_allow_action(类型, []) != GConst.GE_SUCCESS:
			continue
		var 类别: String = ""
		match 类型:
			GConst.ActionType.AttackSkill: 类别 = "attack"
			GConst.ActionType.MagicSkill: 类别 = "magic"
			GConst.ActionType.SpecialSkill: 类别 = "special"
		if 类别 == "" or cur.role.call("v_" + 类别 + "_skill", 候选) != GConst.GE_SUCCESS:
			continue
		return 候选
	return {}


## 超时公告
func _notice_timeout(pid: int, kind: int) -> void:
	var p0: BattlePlayer = players.get(pid)
	var pname: String = p0.player_name if p0 != null else str(pid)
	var kind_name: String = "行动" if kind == GConst.Msg.Action else "应答"
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Notice,
		"txt": "%s %s超时，已自动处理" % [pname, kind_name],
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
	var pname: String = p0.player_name if p0 != null else str(pid)
	if v:
		if _await_id == pid and not _has_reply:
			wait_deadline_ms = Time.get_ticks_msec() + OFFLINE_TIMEOUT_MS
			wait_total_ms = OFFLINE_TIMEOUT_MS
			_broadcast_game()
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Notice,
			"txt": "%s 已掉线，超时将由系统自动代打" % pname,
			"id": 0,
		})
	else:
		broadcast(GConst.Msg.Gossip, {
			"type": GConst.GossipType.Notice,
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
func ask_action(pid: int, action_type: int) -> void:
	var cmds: Array = [{
		"respond_id": action_type, "src_id": pid,
		"dst_ids": [], "card_ids": [], "args": [],
	}]
	var pl: BattlePlayer = players.get(pid)
	if pl != null and pl.role != null:
		for sk: Dictionary in pl.role.available_skills():
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
				# args = [技能号, 最少选牌, 最少选目标, 最多选目标, 选牌来源]
				"args": [int(sk.get("id", 0)), int(sk.get("need_card", 0)), int(sk.get("need_target", 0)),
					int(sk.get("target_max", 0)), int(sk.get("card_source", GConst.CardSource.Hand))],
			})
	send(pid, GConst.Msg.CmdReq, {"cmd_type": GConst.CmdType.Action, "commands": cmds})


func ask_respond(pid: int, respond_id: int, args: Array, dst_ids: Array = [], src_id: int = -1) -> void:
	# 记录本次询问，供超时构造默认回复
	_pending_respond_id = respond_id
	_pending_args = args.duplicate()
	send(pid, GConst.Msg.CmdReq, {
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": respond_id,
			"src_id": src_id if src_id >= 0 else pid,
			"dst_ids": dst_ids,
			"card_ids": [],
			"args": args,
		}],
	})


## 询问某玩家是否发动某技能（客户端表现为「确定/取消」）
## need_card/need_target 告诉客户端本技能需要选出几张牌 / 几个目标
## card_source 为 GConst.CardSource：选牌来源（手牌 / 盖牌 / 两者皆可），如蝶舞的毒粉需指定一张【茧】
## options 非空时客户端改为渲染「选项按钮」，点击即以该项的 value 作为回复的 args[0]
## 编码约定（客户端解析）：args = [need_card, need_target, card_source, 选项数, 选项值…]，
## 选项文案放在同一条命令的 notes 里，与选项值一一对应
func ask_skill(pid: int, skill_id: int, need_card: int = 0, need_target: int = 0, card_source: int = GConst.CardSource.Hand, options: Array = []) -> void:
	var args: Array = [need_card, need_target, card_source, options.size()]
	var notes: Array = []
	for o: Dictionary in options:
		args.append(int(o.get("value", 0)))
		notes.append(str(o.get("label", "")))
	var cmd: Dictionary = {
		"respond_id": skill_id,
		"src_id": pid,
		"dst_ids": [],
		"card_ids": [],
		"args": args,
	}
	if not notes.is_empty():
		cmd["notes"] = notes
	_pending_respond_id = skill_id
	_pending_args = args.duplicate()
	send(pid, GConst.Msg.CmdReq, {"cmd_type": GConst.CmdType.Respond, "commands": [cmd]})
	wait_for(pid, GConst.Msg.Respond)


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
	}


func _broadcast_game() -> void:
	for pid: int in order:
		send(pid, GConst.Msg.Game, game_info(pid))


## 应战的反击目标是否合法（对照服务端 PlayerEntity::v_reattack）：
## 必须是存在的其它玩家，不能是自己、不能是原攻击者、不能是同队
func _reattack_target_ok(defender: BattlePlayer, dst_id: int, origin_src: int) -> bool:
	if defender == null or dst_id < 0 or dst_id == defender.id or dst_id == origin_src:
		return false
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return false
	return dst.color != GConst.TEAM_NONE and dst.color != defender.color


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


func to_discard(cards: Array) -> void:
	deck.push_discard(cards)


func take_from_hand(pid: int, card_ids: Array) -> bool:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return false
	for c: Variant in card_ids:
		if not p0.has_hand_card(int(c)):
			return false
	p0.remove_hand_cards(card_ids)
	return true


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
	push(SHandOverflow.new())
	push(SHook.new("p_harm_end", hc, []))
	push(SHook.new("p_timeline_6_drawn", hc, []))
	push(SHarmTimeline6.new(harm))
	push(SHook.new("p_timeline_6", hc, []))
	push(SHook.new("p_timeline_5", hc, []))
	push(SAskCross.new(harm))
	push(SHook.new("p_timeline_4", hc, []))
	push(SHook.new("p_timeline_3", hc, []))
	push(SHarmTimeline3.new(harm))


## 攻击/法术/特殊行动收尾：先跑「行动结束」钩子，再进入回合结束
func push_after_action(hook: String, ctx: Dictionary) -> void:
	push(STurnEnd.new())
	push(SHook.new(hook, ctx, []))


## 出牌/展示牌后触发 p_show_hand 钩子（封印类技能依赖）
func push_show_hand(pid: int, cards: Array, show_only: bool = false) -> void:
	push(SHook.new("p_show_hand", {"player": pid, "cards": cards, "show_only": show_only}, []))


## 增删基础效果（会触发 p_basic_effect_change 钩子）；角色应优先用这两个方法
func add_basic_effect(dst_id: int, card_id: int, src_id: int, cause: int = 0) -> void:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return
	dst.add_basic_effect(card_id, src_id)
	push(SHook.new("p_basic_effect_change", {
		"dst": dst_id, "card": card_id, "doer": src_id, "cause": cause, "add": true,
	}, []))


func remove_basic_effect(dst_id: int, card_id: int, cause: int = 0) -> void:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return
	dst.remove_basic_effect(card_id)
	push(SHook.new("p_basic_effect_change", {
		"dst": dst_id, "card": card_id, "doer": -1, "cause": cause, "add": false,
	}, []))


## 横置/重置变更（会触发 p_tap 钩子）
func set_tap(pid: int, v: bool) -> void:
	var p0: BattlePlayer = players.get(pid)
	if p0 == null:
		return
	p0.tap = v
	push(SHook.new("p_tap", {"id": pid, "tap": v}, []))


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
	## 挂起前各角色的 step 快照（键 = player_id）
	var _steps: Dictionary = {}

	func _init(h: String, c: Dictionary = {}, a: Array = []) -> void:
		hook = h
		ctx = c
		after = a

	func handle(e: BattleEngine) -> int:
		if not _started:
			_started = true
			_iter = 0
			# 每次钩子轮次开始统一重置所有角色的 step
			for pid: int in e.order:
				var r0: BattleRole = e.p(pid).role
				if r0 != null:
					r0.step = 0
		elif not _steps.is_empty():
			# 从挂起中回来：把 step 还原成本轮次挂起前的值
			for pid: int in _steps:
				var r1: BattleRole = e.p(pid).role
				if r1 != null:
					r1.step = int(_steps[pid])
			_steps.clear()
		while _iter < e.order.size():
			var pid2: int = e.order[_iter]
			var r: BattleRole = e.p(pid2).role
			if r != null:
				var res: int = r.call_hook(hook, ctx)
				if res == BattleRole.WAIT:
					return BattleEngine.WAIT
				if res == BattleRole.URGENT:
					# 角色已压入新状态：先存档 step，让新状态执行，之后再从同一位玩家继续
					_steps.clear()
					for pid3: int in e.order:
						var r2: BattleRole = e.p(pid3).role
						if r2 != null:
							_steps[pid3] = r2.step
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
		e.skip_action_phase = false
		var poison_cards: Array[int] = []
		for be: Dictionary in cur.basic_effects:
			var c: GCard = Data.get_card(int(be["card"]))
			if c != null and c.card_name_enum() == GConst.CardName.Poison:
				poison_cards.append(int(be["card"]))
		e.push(SActionPhase.new())
		e.push(SHook.new("p_before_action", {}, []))
		e.push(SHook.new("p_boot", {}, []))
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
			cur.remove_basic_effect(cid)
			e.to_discard([cid])
			e.push_harm({"src": 0, "dst": cur.id, "point": 1, "cause": GConst.CAUSE_POISON, "type": GConst.HarmType.Magic})
		e._broadcast_game()
		return BattleEngine.CONTINUE


## 虚弱询问
class SWeaken:
	func handle(e: BattleEngine) -> int:
		var cur: BattlePlayer = e.p(e.current_id)
		var weaken_cards: Array[int] = []
		for be: Dictionary in cur.basic_effects:
			var c: GCard = Data.get_card(int(be["card"]))
			if c != null and c.card_name_enum() == GConst.CardName.Weaken:
				weaken_cards.append(int(be["card"]))
		if weaken_cards.is_empty():
			return BattleEngine.CONTINUE
		var draw_n: int = 3 * weaken_cards.size()
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var args: Array = r.get("args", [])
			var accept: int = int(args[0]) if args.size() > 0 else 0
			for cid: int in weaken_cards:
				cur.remove_basic_effect(cid)
				e.to_discard([cid])
			if accept == 1:
				e.draw(cur.id, draw_n)
				e._broadcast_game()
				# 强摸可能把手牌顶过上限：走和购买/特殊行动同一条「强制弃牌 + 掉士气」的路径
				e.push(SHandOverflow.new())
				return BattleEngine.CONTINUE
			e.skip_action_phase = true
			e._broadcast_game()
			return BattleEngine.CONTINUE
		e.ask_respond(cur.id, GConst.RespondType.Weaken, [cur.id, draw_n])
		e.wait_for(cur.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 行动阶段
class SActionPhase:
	func handle(e: BattleEngine) -> int:
		# 虚弱拒绝 / 五系束缚拒绝：本回合没有行动阶段，直接收尾（额外行动由 STurnEnd 照常处理）
		if e.skip_action_phase:
			e.skip_action_phase = false
			e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var at: int = int(r.get("action_type", GConst.ActionType.None))
			return e.resolve_action(at, r)
		e.ask_action(e.current_id, GConst.ActionType.Any)
		e.wait_for(e.current_id, GConst.Msg.Action)
		return BattleEngine.WAIT


## 回合结束：先处理额外行动，否则轮转到下家
class STurnEnd:
	func handle(e: BattleEngine) -> int:
		if e.phase == BattleEngine.Phase.Over:
			return BattleEngine.CONTINUE
		var cur: BattlePlayer = e.p(e.current_id)
		if cur != null and cur.contains_action():
			e.push(SAdditionalAction.new())
			return BattleEngine.CONTINUE
		e.push(SHook.new("p_after_turn_end", {"player": e.current_id}, []))
		e.push(SHook.new("p_turn_end", {"player": e.current_id}, [SNextPlayer.new()]))
		return BattleEngine.CONTINUE


## 轮转到下家
class SNextPlayer:
	func handle(e: BattleEngine) -> int:
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
				var causes2: Array = []
				for a2: Dictionary in cur.additional_actions:
					causes2.append(int(a2["cause"]))
				e.ask_respond(cur.id, GConst.RespondType.AdditionalAction, causes2)
				e.wait_for(cur.id, GConst.Msg.Respond)
				return BattleEngine.WAIT
			var found: bool = idx >= 0
			if found:
				cur.additional_actions.remove_at(idx)
			if found:
				e.broadcast(GConst.Msg.Skill, {"skill_id": chosen, "src_id": cur.id, "dst_ids": []})
				# 先让角色结算「被选中」的代价（p_additional_action），再进入额外行动阶段
				e.push(SActionPhase.new())
				e.push(SHook.new("p_additional_action", {"player": cur.id, "cause": chosen}, []))
			else:
				# 放弃/无匹配：清空待办并继续结束回合
				cur.clear_additional_action()
				e.push(STurnEnd.new())
			return BattleEngine.CONTINUE
		var causes: Array = []
		for a: Dictionary in cur.additional_actions:
			causes.append(int(a["cause"]))
		e.ask_respond(cur.id, GConst.RespondType.AdditionalAction, causes)
		e.wait_for(cur.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


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
					e.ask_respond(defender.id, GConst.RespondType.ReplyAttack, [hit_rate, owner.card, defender.id, owner.src, owner.ctx.get("can_light", 1)])
					e.wait_for(defender.id, GConst.Msg.Respond)
					return BattleEngine.WAIT
				# 应战成立：原攻击落空，应战者以自己的攻击牌对所选目标发起一次新攻击
				e.take_from_hand(defender.id, [cid])
				e.to_discard([cid])
				dst.reattacker = -1
				e.broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": defender.id, "dst_id": 反击目标, "card_ids": [cid], "is_real": true})
				var new_harm: Dictionary = {
					"src": defender.id, "dst": 反击目标, "point": harm["point"],
					"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
					"reattack": true, "card_id": cid, "is_active": false,
				}
				e.push(SAttackCard.new(defender.id, 反击目标, cid, new_harm))
				e.push(STimeline2Miss.new(harm))
				return BattleEngine.CONTINUE
			if choice == GConst.Reattack.Block and not cards.is_empty():
				var cid2: int = int(cards[0])
				if defender.v_block(cid2) == GConst.GE_SUCCESS:
					e.take_from_hand(defender.id, [cid2])
					e.to_discard([cid2])
					dst.reattacker = -1
					e.broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": defender.id, "dst_id": dst.id, "card_ids": [cid2], "is_real": true})
					e.push(STimeline2Miss.new(harm))
					return BattleEngine.CONTINUE
			# 放弃应战：【圣盾】或视作【圣盾】的【天使之墙】自动挡下
			dst.reattacker = -1
			if bool(owner.ctx.get("check_shield", true)):
				var shield_card: int = -1
				if dst.check_basic_effect_name(GConst.CardName.Shield):
					shield_card = e._find_basic_card(dst, GConst.CardName.Shield)
				elif dst.check_basic_effect_skill(技能_天使之墙):
					shield_card = e._find_basic_card_by_skill(dst, 技能_天使之墙)
				if shield_card >= 0:
					dst.remove_basic_effect(shield_card)
					e.to_discard([shield_card])
					e._broadcast_game()
					e.push(STimeline2Miss.new(harm))
					return BattleEngine.CONTINUE
			e.push(STimeline2Hit.new(harm))
			return BattleEngine.CONTINUE
		e.ask_respond(defender.id, GConst.RespondType.ReplyAttack, [hit_rate, owner.card, defender.id, owner.src, owner.ctx.get("can_light", 1)])
		e.wait_for(defender.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 魔弹传递询问：持有者可以打出【魔弹】继续传递、出【圣光】抵挡，或放弃并承受伤害。
## 对照服务端 StateMissiled：传递方向沿用出弹时定下的方向（【魔弹】默认右手边 post；
## 魔导用【魔弹掌握】逆向打出则是 pre），后续传递者只是「传给下一个」、不改方向，
## 只有【魔弹掌握】的持有者才能在传递时改方向。同一轮传递里每人只能参与一次。
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
			# dst_ids = 本次可以把魔弹传给谁（候选，有【魔弹掌握】时左右各一个）
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
				# 【圣光】抵挡：魔弹效果终止，不造成伤害
				e.take_from_hand(holder, [cid])
				e.to_discard([cid])
				e.broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": holder, "dst_id": holder, "card_ids": [cid], "is_real": true})
				e._broadcast_game()
				return BattleEngine.CONTINUE
			if choice == GConst.Reattack.Attack and me.v_remissile(cid) == GConst.GE_SUCCESS:
				# 继续传递：伤害 +1，沿**当前方向**转给下一个还没参与过的对手
				# （方向是出弹时定下的：顺时针打出＝顺向，被魔导用【魔弹掌握】逆向打出＝逆向，传递者不改方向）
				e.take_from_hand(holder, [cid])
				e.to_discard([cid])
				e.broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": holder, "dst_id": holder, "card_ids": [cid], "is_real": true})
				var 顺: int = e._next_missile_target(holder, post_dir, used)
				var nxt: int = 顺
				var nxt_dir: bool = post_dir
				# 只有【魔弹掌握】802 能在传递时改方向（＝选另一个方向上那个人）
				if me.role != null and me.role.has_missile_mastery():
					var 回复选: Array = r.get("dst_ids", [])
					if not 回复选.is_empty() and int(回复选[0]) != 顺:
						var 逆: int = e._next_missile_target(holder, not post_dir, used)
						if 逆 >= 0 and int(回复选[0]) == 逆:
							nxt = 逆
							nxt_dir = not post_dir
				if nxt >= 0:
					used.append(nxt)
					e.push(SMissileAsk.new(nxt, holder, point + 1, nxt_dir, used))
				else:
					# 没人能再接：由当前持有者承受
					e.push_harm({"src": src, "dst": holder, "point": point, "cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic})
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


## Timeline3：广播伤害
class SHarmTimeline3:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
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
		# 治疗只能抵御法术伤害；角色可在 p_timeline_4 用 harm["cross_available"]=0 关闭治疗结算，
		# 或用 harm["cross_max_point"]=N 把本次可抵御点数限制为 N
		var cross_ok: bool = int(harm.get("cross_available", 1)) != 0
		var cap: int = int(harm.get("cross_max_point", 0))
		var avail: int = dst.cross_num if (harm["type"] == GConst.HarmType.Magic and cross_ok) else 0
		if cap > 0:
			avail = mini(avail, cap)
		if e.has_reply():
			var r: Dictionary = e.take_reply()
			var args: Array = r.get("args", [])
			var used: int = int(args[0]) if args.size() > 0 else 0
			used = clampi(used, 0, avail)
			dst.sub_cross_num(used)
			harm["point"] = maxi(int(harm["point"]) - used, 0)
			e._broadcast_game()
			return BattleEngine.CONTINUE
		if avail > 0:
			e.ask_respond(dst.id, GConst.RespondType.Heal, [dst.id, harm["point"], harm["cause"], avail])
			e.wait_for(dst.id, GConst.Msg.Respond)
			return BattleEngine.WAIT
		return BattleEngine.CONTINUE


## Timeline6：目标按伤害点数摸牌
class SHarmTimeline6:
	var harm: Dictionary
	func _init(h: Dictionary) -> void:
		harm = h
	func handle(e: BattleEngine) -> int:
		var point: int = int(harm["point"])
		if point > 0:
			e.draw(harm["dst"], point)
			e._broadcast_game()
		return BattleEngine.CONTINUE


## 手牌超限：强制弃牌并掉士气（每次处理一名玩家）
class SHandOverflow:
	func handle(e: BattleEngine) -> int:
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
			# 先压「继续处理下一个超限玩家」，再压掉士气（后压先执行 → 士气先结算，与服务器一致）
			e.push(SHandOverflow.new())
			e.push(SOverloadMorale.new(target.id, over, GConst.CAUSE_OVERLOAD, e.last_harm_cause, e.last_harm_type))
			e._broadcast_game()
			return BattleEngine.CONTINUE
		e.ask_respond(target.id, GConst.RespondType.Discard, [target.id, GConst.CAUSE_OVERLOAD, over], [target.id])
		e.wait_for(target.id, GConst.Msg.Respond)
		return BattleEngine.WAIT


## 超限掉士气（可等待玩家输入）：依次跑 p_before_lose_morale → p_lose_morale → 扣士气 → p_true_lose_morale
## 对应服务端 StateBeforeLoseMorale → StateLoseMorale → StateTrueLoseMorale。
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
		# 逆序压栈：p_before_lose_morale → p_lose_morale → 扣士气 → p_true_lose_morale
		e.push(SHook.new("p_true_lose_morale", ctx, []))
		e.push(SApplyOverloadMorale.new(target_id, ctx))
		e.push(SHook.new("p_lose_morale", ctx, []))
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
	# 动作合法性总闸：角色可用 v_allow_action 覆写（如「审判满 4 时该阶段只能发动末日审判」）
	var 总闸: int = cur.v_allow_action(action_type, data.get("args", [])) if cur != null else GConst.GE_SUCCESS
	if 总闸 != GConst.GE_SUCCESS:
		# 临时诊断（收工前删）
		print("[战斗诊断] 行动被拒：v_allow_action(action_type=%d) 返回 %d" % [action_type, 总闸])
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
			push(STurnEnd.new())
			push(SkillRun.new("attack", data))
			return CONTINUE
		GConst.ActionType.MagicSkill:
			push(STurnEnd.new())
			push(SkillRun.new("magic", data))
			return CONTINUE
		GConst.ActionType.SpecialSkill:
			push(STurnEnd.new())
			push(SkillRun.new("special", data))
			return CONTINUE
		_:
			push(STurnEnd.new())
			return CONTINUE


func _do_unactional(cur: BattlePlayer) -> int:
	push(STurnEnd.new())
	if cur.hand_cards.is_empty():
		set_morale(cur.color, 0)
		_broadcast_game()
		_check_game_over()
		return CONTINUE
	var old: Array = cur.hand_cards.duplicate()
	var new_cards: Array[int] = deck.draw(old.size())
	cur.hand_cards.clear()
	cur.add_hand_cards(new_cards)
	to_discard(old)
	broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Show, "src_id": cur.id, "dst_id": cur.id, "card_ids": old, "is_real": true})
	_broadcast_game()
	push_show_hand(cur.id, old, true)
	push(SHandOverflow.new())
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
		print("[战斗诊断] 攻击被拒：目标角色 v_attacked 返回 %d" % dst_p.v_attacked())
		# 临时诊断
		return _reject_action(cur)
	push_after_action("p_after_attack", {"player": cur.id, "card_id": cid, "dst": dst_id})
	take_from_hand(cur.id, [cid])
	to_discard([cid])
	broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
	var harm: Dictionary = {
		"src": cur.id, "dst": dst_id, "point": 2, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": cid, "is_active": true,
	}
	push(SAttackCard.new(cur.id, dst_id, cid, harm))
	push_show_hand(cur.id, [cid])
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
	push_show_hand(cur.id, [cid])
	if name_enum == GConst.CardName.Shield:
		if cur.v_shield(dst_id, players) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [cid])
		add_basic_effect(dst_id, cid, cur.id, GConst.CAUSE_USE)
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		_broadcast_game()
		push_after_action("p_after_magic", {"src": cur.id, "card_id": cid})
		return CONTINUE
	if name_enum == GConst.CardName.Weaken:
		if cur.v_weaken(dst_id, players) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		take_from_hand(cur.id, [cid])
		add_basic_effect(dst_id, cid, cur.id, GConst.CAUSE_USE)
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		_broadcast_game()
		push_after_action("p_after_magic", {"src": cur.id, "card_id": cid})
		return CONTINUE
	if name_enum == GConst.CardName.Poison:
		take_from_hand(cur.id, [cid])
		add_basic_effect(dst_id, cid, cur.id, GConst.CAUSE_USE)
		broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true})
		_broadcast_game()
		push_after_action("p_after_magic", {"src": cur.id, "card_id": cid})
		return CONTINUE
	if name_enum == GConst.CardName.Missile:
		# 落点默认是右手边最近的对手；有【魔弹掌握】802 的角色可以把落点选成左手边那个
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
		push_after_action("p_after_magic", {"src": cur.id, "card_id": cid})
		if target >= 0:
			broadcast(GConst.Msg.Card, {"type": GConst.CardMsgType.Use, "src_id": cur.id, "dst_id": target, "card_ids": [cid], "is_real": true})
			# 交给目标自己决定：打出【魔弹】继续传递 / 出【圣光】抵挡 / 放弃并承受伤害。
			# 即使他手里既没有【魔弹】也没有【圣光】，也要问一次并等他应答（对照服务端 StateMissiled）
			var used: Array[int] = [cur.id, target]
			push(SMissileAsk.new(target, cur.id, MISSILE_BASE_POINT, 顺向, used))
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


## 本次可以把魔弹传给谁（候选）：默认只有「当前传递方向上最近、本轮还没接过的对手」；
## 有【魔弹掌握】802 的角色另一个方向上那个人也能选（方向随之改写）。
func _missile_relay_targets(holder: int, post_dir: bool, used: Array[int]) -> Array[int]:
	var out: Array[int] = []
	var 顺: int = _next_missile_target(holder, post_dir, used)
	if 顺 >= 0:
		out.append(顺)
	var h: BattlePlayer = players.get(holder)
	if h != null and h.role != null and h.role.has_missile_mastery():
		var 逆: int = _next_missile_target(holder, not post_dir, used)
		if 逆 >= 0 and not out.has(逆):
			out.append(逆)
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
	elif dst.check_basic_effect_skill(技能_天使之墙):
		cid = _find_basic_card_by_skill(dst, 技能_天使之墙)
	if cid < 0:
		return false
	remove_basic_effect(target_id, cid, GConst.CAUSE_MISSILE)
	to_discard([cid])
	return true


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
		set_team_gem(cur.color, team_gem[cur.color] + (int(args[0]) if args.size() > 0 else 0))
		set_team_crystal(cur.color, team_crystal[cur.color] + (int(args[1]) if args.size() > 1 else 0))
		draw(cur.id, 3)
		_broadcast_game()
		push_after_action("p_after_special", {"src": cur.id, "card_id": -1})
		push(SHandOverflow.new())
		return CONTINUE
	if aid == GConst.SpecialAction.Synthesize:
		if cur.v_synthesize(args, team_energy(cur.color)) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		_spend_team_energy(cur.color, int(args[0]) if args.size() > 0 else 0, int(args[1]) if args.size() > 1 else 0)
		team_grail[cur.color] += 1
		draw(cur.id, 3)
		_broadcast_game()
		if team_grail[cur.color] >= GConst.GRAIL_WIN:
			_game_over(cur.color)
			return CONTINUE
		push_after_action("p_after_special", {"src": cur.id, "card_id": -1})
		push(SHandOverflow.new())
		return CONTINUE
	if aid == GConst.SpecialAction.Extract:
		if cur.v_extract(args, team_gem[cur.color], team_crystal[cur.color]) != GConst.GE_SUCCESS:
			return _reject_action(cur)
		var g3: int = int(args[0]) if args.size() > 0 else 0
		var c3: int = int(args[1]) if args.size() > 1 else 0
		set_team_gem(cur.color, team_gem[cur.color] - g3)
		set_team_crystal(cur.color, team_crystal[cur.color] - c3)
		cur.set_gem(cur.gem + g3)
		cur.set_crystal(cur.crystal + c3)
		_broadcast_game()
		push_after_action("p_after_special", {"src": cur.id, "card_id": -1})
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


# ============================================================
# 士气与结束
# ============================================================
## 掉士气（带角色钩子；ctx 含最近一次伤害的 cause/type，供「因伤害掉士气」类技能判定）
## 与服务器一致：before / true 钩子对「所有玩家」按座位序调用（如蝶舞的凋零形态要限制
## 对手的士气下降、月女的新月庇护要响应队友的士气下降），钩子内部按 ctx["dst"] 自行判断是否相关。
## 限制：本实现为同步调用，钩子内不能等待玩家输入。超限掉士气走 SOverloadMorale（可等待，见下），
## 需要等待支付的技能（如天使的神之庇护 706）在那边实现。
func lose_morale(target: BattlePlayer, amount: int, cause: int) -> void:
	var ctx: Dictionary = {
		"dst": target.id, "amount": amount, "cause": cause,
		"harm_cause": last_harm_cause, "type": last_harm_type,
	}
	for pid: int in order:
		var p0: BattlePlayer = players.get(pid)
		if p0 != null and p0.role != null:
			p0.role.call_hook("p_before_lose_morale", ctx)
	amount = int(ctx.get("amount", amount))
	set_morale(target.color, team_morale[target.color] - amount)
	for pid2: int in order:
		var p1: BattlePlayer = players.get(pid2)
		if p1 != null and p1.role != null:
			p1.role.call_hook("p_true_lose_morale", ctx)
	last_harm_cause = 0
	last_harm_type = 0
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
	_broadcast_game()
	broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Notice,
		"txt": "游戏结束，%s方获胜！" % ("红" if win_color == GConst.RED else "蓝"),
		"id": 0,
	})
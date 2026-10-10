class_name LocalServer
extends RefCounted
## 权威服务端（对照服务端 DiceGameServer/UserTask.cpp + GameManager.cpp + GameSessionManager）
## 房主进程内运行；承载房间列表、建房/进房/退房、选边、准备，以及权威战斗引擎。
## 去登录：客户端连上后由服务端自动登记身份，客户端只用登录消息上报昵称。

## 选角 / 随机分配的角色池 = 角色表「启用」列打开的那些（Data.role_pool）。
## 启用或停用一个角色：改角色表那一行的「启用」（1 开 / 0 关），再导出一次 TableScripts/DataTables.gd。

## 候选制选将每人发几个候选：三选一发 3 个、六选一发 6 个，都只从中选 1 个
const 三选一候选数: int = 3
const 六选一候选数: int = 6

## 选将超时（毫秒），超时按服务端 GE_TIMEOUT 的语义收尾
const PICK_TIMEOUT_MS: int = 30000

signal rooms_changed

var server: NetServer = NetServer.new()
var _sessions: Dictionary = {}     # conn_id -> {nickname, room_id, player_id}
var _rooms: Dictionary = {}        # room_id -> 房间字典
var _next_room_id: int = 1


# ============================================================
# 启动 / 轮询
# ============================================================
func start(port: int) -> int:
	randomize()
	var err: int = server.listen(port)
	if err != OK:
		return err
	server.client_connected.connect(_on_client_connected)
	server.client_disconnected.connect(_on_client_disconnected)
	server.client_message.connect(_on_client_message)
	return OK


func poll() -> void:
	server.poll()
	for rid: int in _rooms.keys():
		var room: Dictionary = _rooms[rid]
		# 推进选将阶段的超时（到点还没提交的按候选第 1 个收尾）
		if room.has("pick"):
			_check_pick_timeout(room)
		# 推进对局回复超时：挂机/掉线玩家到点自动代打，避免整局被一个人卡死
		if _is_battle_playing(room):
			var battle: BattleEngine = room["battle"]
			battle.tick()
		# 观战流是降频推的：欠着的快照到点补发，保证最后一次状态变化不会被吃掉
		if bool(room["watch_dirty"]):
			_请求观战快照(room)
		# 连接质量：定期给房内每条连接打一次心跳（玩家的延迟只有服务端测得到）
		_推房间心跳(room)


## 心跳 / 延迟测量：每 心跳间隔_ms 给房内每条连接发一次 HeartBeat，客户端回声后即可算出往返延迟。
## 观战者也发（他们的连接质量同样只有服务端看得到），房主自己那条约为 0ms
func _推房间心跳(room: Dictionary) -> void:
	var 现在: int = Time.get_ticks_msec()
	for cid: int in _房间接收者(room):
		var s: Dictionary = _sessions.get(cid, {})
		if s.is_empty():
			continue
		var 在等回声: int = int(s.get("ping_sent_ms", 0))
		if 在等回声 > 0:
			if 现在 - 在等回声 > 心跳超时_ms:
				# 这一轮没回声：按最差一档处理（多半是卡住或刚掉线）
				s["ping_sent_ms"] = 0
				s["ping_ms"] = 心跳超时_ms
		elif 现在 - int(s.get("ping_last_ms", 0)) >= 心跳间隔_ms:
			s["ping_sent_ms"] = 现在
			s["ping_last_ms"] = 现在
			server.send(cid, GConst.Msg.HeartBeat, {})


## 收到心跳回声：算出往返延迟并平滑（旧值权重 2/3），抖动时数字不会乱跳
func _记心跳回声(conn_id: int) -> void:
	var s: Dictionary = _sessions.get(conn_id, {})
	if s.is_empty():
		return
	var 发出: int = int(s.get("ping_sent_ms", 0))
	if 发出 <= 0:
		return
	s["ping_sent_ms"] = 0
	var 新值: int = Time.get_ticks_msec() - 发出
	# 加权平滑：旧值占 2/3、新值占 1/3。毫秒取整就够了（显式忽略「整数除法丢小数」警告）
	@warning_ignore("integer_division")
	s["ping_ms"] = (int(s.get("ping_ms", 新值)) * 2 + 新值) / 3


## 把各连接测出的延迟写进玩家：快照会带着它一起下发（「玩家列表」右侧那一列）
func _同步连接质量(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	var conn_of: Dictionary = room["conn_of"]
	for pid: int in conn_of.keys():
		if not battle.players.has(pid):
			continue
		var s: Dictionary = _sessions.get(int(conn_of[pid]), {})
		(battle.players[pid] as BattlePlayer).ping_ms = int(s.get("ping_ms", 0))


## 在线玩家数：对局中掉线/退出的人座位会保留（状态机还指着他），不能再算进「人数」里，
## 否则房间列表会一直显示 4/4，看不出人已经走了
func _统计在线人数(battle: BattleEngine) -> int:
	var n: int = 0
	for pid: int in battle.order:
		var p: BattlePlayer = battle.players.get(pid)
		if p != null and p.online:
			n += 1
	return n


## 该房间是否正处于「进行中的对局」（已开局且未结束）
func _is_battle_playing(room: Dictionary) -> bool:
	if room.is_empty():
		return false
	var battle: BattleEngine = room["battle"]
	return bool(room["started"]) and battle.phase == BattleEngine.Phase.Playing


# ============================================================
# 连接生命周期
# ============================================================
func _on_client_connected(conn_id: int) -> void:
	_sessions[conn_id] = {
		"nickname": "玩家%d" % conn_id,
		"room_id": -1,
		"player_id": -1,
		"client_id": "",
		"ping_ms": 0,        # 这一路测出的往返延迟（心跳测量，见 _推房间心跳）
		"ping_sent_ms": 0,   # 本轮心跳发出时刻；0 = 没有在等回声
		"ping_last_ms": 0,   # 上一轮心跳发出时刻（控制发送间隔）
	}


func _on_client_disconnected(conn_id: int) -> void:
	var room: Dictionary = _room_of(conn_id)
	if _is_battle_playing(room):
		var pid: int = int(_sessions.get(conn_id, {}).get("player_id", -1))
		if pid >= 0 and pid != GConst.GUEST:
			# 对局中掉线：标记掉线，引擎把等待时限收紧到掉线超时并自动代打
			var battle: BattleEngine = room["battle"]
			battle.set_offline(pid, true)
	leave_room(conn_id)
	_sessions.erase(conn_id)


func _on_client_message(conn_id: int, msg_type: int, data: Dictionary) -> void:
	var s: Dictionary = _sessions.get(conn_id, {})
	if s.is_empty():
		return
	match msg_type:
		GConst.Msg.LoginReq:
			# 去登录：仅用登录消息上报昵称与进程身份
			var nick: String = str(data.get("user_id", ""))
			if nick != "":
				s["nickname"] = nick
			var cid: String = str(data.get("client_id", ""))
			if cid != "":
				s["client_id"] = cid
			server.send(conn_id, GConst.Msg.LoginRep, {"state": 6, "nickname": s["nickname"]})
		GConst.Msg.RoomListReq:
			server.send(conn_id, GConst.Msg.RoomListRep, {"rooms": _room_infos(conn_id)})
		GConst.Msg.CreateRoomReq:
			create_room(conn_id, data)
		GConst.Msg.EnterRoomReq:
			enter_room(conn_id, int(data.get("room_id", -1)))
		GConst.Msg.LeaveRoomReq:
			leave_room(conn_id)
		GConst.Msg.JoinTeamReq:
			join_team(conn_id, int(data.get("team", 2)))
		GConst.Msg.ReadyForGameReq:
			ready_for_game(conn_id, int(data.get("type", 1)))
		GConst.Msg.Talk:
			_talk(conn_id, str(data.get("txt", "")))
		GConst.Msg.HeartBeat:
			# 客户端回的心跳：据此算这一路的往返延迟。
			# 这里不能再回一声，否则两边会互相回成死循环
			_记心跳回声(conn_id)
		GConst.Msg.PickBan:
			var pick_room: Dictionary = _room_of(conn_id)
			if not pick_room.is_empty():
				_on_pick_ban(pick_room, int(s["player_id"]), data)
		GConst.Msg.Action, GConst.Msg.Respond:
			var room: Dictionary = _room_of(conn_id)
			if not room.is_empty():
				var battle: BattleEngine = room["battle"]
				battle.on_message(int(s["player_id"]), msg_type, data)
		GConst.Msg.DebugReq:
			# 测试用：按连接认人，谁按的键就以谁的名义做。
			# 只在房主开了「调试模式」的房间里生效（客户端会隐藏入口，这里再拦一道防改包）
			var 测试房: Dictionary = _room_of(conn_id)
			if not 测试房.is_empty() and (测试房["battle"] as BattleEngine).room_debug:
				(测试房["battle"] as BattleEngine).debug_key(int(s["player_id"]), int(data.get("kind", 1)))


# ============================================================
# 房间
# ============================================================
## 房间列表。带 conn_id 时额外告诉这个连接「哪几间房还留着你的座位」——
## 对局中退出/掉线时座位不会被移除，这些人重进应该直接坐回去，而不是被当成观战
func _room_infos(conn_id: int = -1) -> Array:
	var 我的身份: String = str(_sessions.get(conn_id, {}).get("client_id", ""))
	var out: Array = []
	for rid: int in _rooms.keys():
		var r: Dictionary = _rooms[rid]
		var battle: BattleEngine = r["battle"]
		out.append({
			"room_id": rid,
			"room_name": r["name"],
			"max_player": r["max_player"],
			"now_player": _统计在线人数(battle),
			"seat_count": battle.order.size(),
			"watchers": (r["watchers"] as Array).size(),
			"role_strategy": r["role_strategy"],
			"seat_mode": r["seat_mode"],
			"role_range": 31,
			"allow_guest": r["allow_guest"],
			"has_password": false,
			"first_extension": false,
			"second_extension": false,
			"sp_mo_dao": false,
			"playing": r["started"],
			"silence": false,
			"can_reenter": _reclaim_seat(r, 我的身份) >= 0,
		})
	return out


func create_room(conn_id: int, data: Dictionary) -> void:
	if int(_sessions[conn_id]["room_id"]) >= 0:
		leave_room(conn_id)
	var rid: int = _next_room_id
	_next_room_id += 1
	var battle: BattleEngine = BattleEngine.new()
	battle.room_id = rid
	var room: Dictionary = {
		"id": rid,
		"name": str(data.get("room_name", "房间%d" % rid)),
		"max_player": clampi(int(data.get("max_player", 6)), 2, GConst.MAX_PLAYER),
		"role_strategy": int(data.get("role_strategy", GConst.RoleStrategy.Random)),
		"seat_mode": int(data.get("seat_mode", GConst.SeatMode.Random)),
		"allow_guest": bool(data.get("allow_guest", true)),
		"started": false,
		"host_conn": conn_id,
		"conn_of": {},          # player_id -> conn_id
		"client_of": {},        # player_id -> 客户端身份标识（认领座位用；局域网 = 昵称，Steam = SteamID）
		"watchers": [],         # 观战者 conn_id 列表（满员时进来的人，不占座位，可同时有多个）
		"watch_next_ms": 0,     # 观战流下次可发送的时刻（降频用）
		"watch_dirty": false,   # 有没有欠着还没发出去的观战快照
		"battle": battle,
	}
	battle.room_name = str(room["name"])
	battle.room_max_player = int(room["max_player"])
	battle.room_debug = bool(data.get("debug", false))
	battle.send_cb = func(target: int, msg_type: int, fields: Dictionary) -> void:
		_engine_send(rid, target, msg_type, fields)
	_rooms[rid] = room
	enter_room(conn_id, rid)
	rooms_changed.emit()


func enter_room(conn_id: int, room_id: int) -> void:
	if not _rooms.has(room_id):
		server.send(conn_id, GConst.Msg.Error, {"id": GConst.GE_INVALID_TABLEID, "dst_id": conn_id, "args": []})
		return
	var room: Dictionary = _rooms[room_id]
	var battle: BattleEngine = room["battle"]
	var s: Dictionary = _sessions[conn_id]
	if int(s["room_id"]) >= 0:
		leave_room(conn_id)
	# 有座位就落座；满员则作为观战者进来（不占座位，能同时有多个）
	var pid: int = GConst.GUEST
	var 认领: int = _reclaim_seat(room, str(s.get("client_id", "")))
	if 认领 >= 0:
		# 断线重连：认领回本进程此前在本房间的座位（对局中座位不会被移除）
		pid = 认领
		(room["conn_of"] as Dictionary)[pid] = conn_id
	elif battle.order.size() < int(room["max_player"]):
		# 座位号取「当前空闲的最小号」：有人退房再进人时新玩家补进空出来的座位，
		# 房间界面的座位图才不会因为号一直自增而串位
		var 空位: int = 0
		while battle.players.has(空位):
			空位 += 1
		pid = 空位
		battle.add_player(pid, GConst.TEAM_NONE, str(s["nickname"]))
		(room["conn_of"] as Dictionary)[pid] = conn_id
		var cid: String = str(s.get("client_id", ""))
		if cid != "":
			(room["client_of"] as Dictionary)[pid] = cid
	else:
		(room["watchers"] as Array).append(conn_id)
	s["room_id"] = room_id
	s["player_id"] = pid
	if pid == GConst.GUEST:
		# 观战者：名单跟着广播，房内所有人都能看到谁在观战；
		# 新来的观战者立刻给一份快照（不等降频的下一拍）
		_同步观战者名单(room)
		_推送观战快照(room, Time.get_ticks_msec())
	else:
		# 进入房间（含掉线后重新进入）：清除掉线标记，恢复常规回复超时
		battle.set_offline(pid, false)
	_broadcast_game(room)


func leave_room(conn_id: int) -> void:
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty():
		return
	var s: Dictionary = _sessions.get(conn_id, {})
	var pid: int = int(s.get("player_id", -1))
	var battle: BattleEngine = room["battle"]
	if pid == GConst.GUEST:
		# 观战者离席：从观战名单里去掉，不涉及座位
		(room["watchers"] as Array).erase(conn_id)
	elif pid >= 0:
		(room["conn_of"] as Dictionary).erase(pid)
		if _is_battle_playing(room):
			# 对局进行中：座位不可移除（引擎状态机与等待对象都指向该玩家），
			# 保留座位并标记掉线，由引擎按掉线超时自动代打
			battle.set_offline(pid, true)
		else:
			battle.remove_player(pid)
			# 未开局时座位被移除，身份绑定一并清除（此前未开局离席即不再保留认领资格）
			(room["client_of"] as Dictionary).erase(pid)
			# 选将期间掉线：立刻按超时处理该玩家，避免房间卡死
			_on_pick_player_left(room, pid)
	s["room_id"] = -1
	s["player_id"] = -1
	_同步观战者名单(room)
	# 房间内已无在线玩家、也没有观战者：对局无从继续也无人在看，直接销毁房间
	if (room["conn_of"] as Dictionary).is_empty() and (room["watchers"] as Array).is_empty():
		_rooms.erase(int(room["id"]))
		rooms_changed.emit()
	else:
		_broadcast_game(room)
		rooms_changed.emit()


## 断线重连认领座位：找出本房间内属于该身份标识、且当前无连接占用的座位（无则 -1）
func _reclaim_seat(room: Dictionary, client_id: String) -> int:
	if client_id == "":
		return -1
	var client_of: Dictionary = room["client_of"]
	var conn_of: Dictionary = room["conn_of"]
	for pid: int in client_of.keys():
		if str(client_of[pid]) != client_id:
			continue
		if conn_of.has(pid):
			continue
		return int(pid)
	return -1


func join_team(conn_id: int, team: int) -> void:
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty():
		return
	var s: Dictionary = _sessions[conn_id]
	var pid: int = int(s["player_id"])
	var battle: BattleEngine = room["battle"]
	match team:
		1:
			battle.set_color(pid, GConst.BLUE)
		2:
			battle.set_color(pid, GConst.RED)
		_:
			battle.set_color(pid, GConst.TEAM_NONE)
	_broadcast_game(room)


func ready_for_game(conn_id: int, type: int) -> void:
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty() or bool(room["started"]):
		return
	var s: Dictionary = _sessions[conn_id]
	var pid: int = int(s["player_id"])
	if pid == GConst.GUEST:
		return
	var battle: BattleEngine = room["battle"]
	var 新值: bool = type == 1
	var p0: BattlePlayer = battle.players.get(pid)
	if p0 != null and p0.ready == 新值:
		# 准备状态未变化：直接返回、不再广播
		# （否则「准备 → 广播 Game → 客户端收到 Game 又准备」会形成无限回环，把服务端读循环钉死）
		return
	battle.set_ready(pid, 新值)
	_broadcast_game(room)
	if not battle.all_ready():
		return
	if battle.order.size() != int(room["max_player"]):
		# 人数没坐满不开局：房间设定几人就得几人（2V2 必须凑齐 4 人），
		# 否则 2V2 的房间里两个人都准备了也会直接开成 1v1
		return
	if room.has("pick"):
		# 选将进行中，等待各玩家提交
		return
	if int(room["role_strategy"]) == GConst.RoleStrategy.Random:
		# Random 策略保持原样：不发询问、直接随机分配（自动测试依赖这条零交互路径）
		room["started"] = true
		battle.start(Data.role_pool.duplicate())
		rooms_changed.emit()
		return
	# 选将前先把队伍配平：没提前选边的人在这里定下蓝/红（对照参照工程开局前先 balance_colors），
	# 否则选角界面顶部的「座位顺序」全是未分队，看不出谁跟谁一队
	battle.balance_colors()
	_broadcast_game(room)
	_begin_role_pick(room)


func _talk(conn_id: int, txt: String) -> void:
	if txt.strip_edges() == "":
		return
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty():
		return
	_broadcast_raw(room, GConst.Msg.Gossip, {"type": GConst.GossipType.Talk, "txt": txt, "id": int(_sessions[conn_id]["player_id"])})


# ============================================================
# 选将阶段（对照服务端 DiceGameServer/GrailState.cpp）
# ============================================================
## 开局前入口：按房间策略进入选将流程。选将状态保存在 room["pick"]，由 poll() 推进超时。
## 候选池统一是角色表「启用」列打开的角色（Data.role_pool）；Random 不走这里，它在 ready_for_game 直接随机分配。
## 三选一抽 3 个候选、六选一抽 6 个（服务端 StateRoleStrategy31）；任选（Any/All）候选数 0 = 整池下发。
func _begin_role_pick(room: Dictionary) -> void:
	var 候选数: int = 三选一候选数
	if int(room["role_strategy"]) == GConst.RoleStrategy.Strategy61:
		候选数 = 六选一候选数
	elif _任选模式(room):
		候选数 = 0
	_begin_pick_candidates(room, Data.role_pool, 候选数)


## 收客户端的 PickBan（选角结果）
func _on_pick_ban(room: Dictionary, pid: int, data: Dictionary) -> void:
	if not room.has("pick") or pid == GConst.GUEST:
		return
	_on_pick_ban_candidates(room, pid, data)


## 31 / 61 / Any：服务端 StateRoleStrategy31(331-372) 与 StateRoleStrategyAny(374-407)
## 候选数 > 0：每人抽这么多个互不重复的候选（三选一发 3 个、六选一发 6 个），最后只取其一；
## 候选数 = 0：整池下发（Any）
## 下发用 strategy=2：服务端 Coder::askForRole(GameGrailCommon.h:759) 固定填 ROLE_STRATEGY_31，Any/61 只差候选池
func _begin_pick_candidates(room: Dictionary, pool: Array, 候选数: int) -> void:
	var battle: BattleEngine = room["battle"]
	var 池: Array = pool.duplicate()
	池.shuffle()
	var 候选表: Dictionary = {}
	for pid: int in battle.order:
		var 候选: Array = []
		if 候选数 > 0:
			for _k: int in range(候选数):
				if 池.is_empty():
					池 = pool.duplicate()
					池.shuffle()
				候选.append(int(池.pop_back()))
		else:
			候选 = pool.duplicate()
		候选表[pid] = 候选
	room["pick"] = {
		"candidates": 候选表,
		"pool": pool.duplicate(),
		"picked": {},
		"deadline": Time.get_ticks_msec() + PICK_TIMEOUT_MS,
	}
	# 选角开始：标记进快照，准备室的观战提示据此显示「正在等待选角」（观战者收不到 RoleReq）
	battle.room_picking = true
	for pid: int in battle.order:
		_engine_send(int(room["id"]), pid, GConst.Msg.RoleReq, {
			"id": pid,
			"strategy": int(room["role_strategy"]),
			"role_ids": 候选表[pid],
			# 选角倒计时：客户端据此画进度条（本地扩展字段，见 proto_schema 的 RoleReq）
			"wait_ms": PICK_TIMEOUT_MS,
			"wait_total_ms": PICK_TIMEOUT_MS,
			"args": [],
			"opration": 0,
		})
	_broadcast_game(room)


func _on_pick_ban_candidates(room: Dictionary, pid: int, data: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var 候选表: Dictionary = pick["candidates"]
	if not 候选表.has(pid):
		return
	var 已选: Dictionary = pick["picked"]
	if 已选.has(pid):
		return
	var 候选: Array = 候选表[pid]
	var 提交: Array = data.get("role_ids", [])
	var 选定: int = 0
	if not 提交.is_empty() and 候选.has(int(提交[0])):
		选定 = int(提交[0])
	elif not 候选.is_empty():
		选定 = int(候选[0])
	if 选定 <= 0:
		return
	已选[pid] = 选定
	if _pick_candidates_done(room):
		_finish_pick_candidates(room)


## 31/Any 是否所有在房玩家都已提交（掉线者已从 order 移除，不再计入）
func _pick_candidates_done(room: Dictionary) -> bool:
	var battle: BattleEngine = room["battle"]
	var 已选: Dictionary = room["pick"]["picked"]
	for pid: int in battle.order:
		if not 已选.has(pid):
			return false
	return true


## 收尾 31/Any：超时或掉线者在自己候选里**随机**取一个（原版服务端取候选第 1 个（messages[i]->role_ids(0)，
## GrailState.cpp:362），这里改成随机，免得每次超时都是同一个角色）；
## 若该角色已被先提交者占用（Any 可能出现），改为该玩家候选里随机一个未被占用的角色，保证全局不重复。
## 例外：任选（Any/All）允许全场重复选同一个角色 —— 它的候选本来就是全部启用角色，
## 再强行去重会把「大家都想玩同一个角色」改成随机补位，反而不符合任选的本意。
func _finish_pick_candidates(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var battle: BattleEngine = room["battle"]
	if battle.order.size() < 2:
		room.erase("pick")
		return
	var 角色表: Dictionary = _分配角色(
		battle.order, pick["candidates"], pick["picked"], pick["pool"], _任选模式(room))
	room.erase("pick")
	_start_battle(room, 角色表)


## 把各玩家的提交落成最终角色分配（顺序: 座位序；已选: pid -> 提交的角色号）。
## 候选制（31/61）保证全局不重复：没提交（超时 / 掉线）或提交的角色被占了的人，
## 在自己候选里**随机**挑一个没被占的，候选全被占就从整池里随机补一个。
## 任选（Any/All）允许重复，提交什么就是什么。
func _分配角色(顺序: Array, 候选表: Dictionary, 已选: Dictionary, 全池: Array, 允许重复: bool) -> Dictionary:
	var 已用: Array = []
	var 角色表: Dictionary = {}
	for pid: int in 顺序:
		var 选定: int = int(已选.get(pid, 0))
		if 选定 <= 0 or (not 允许重复 and 已用.has(选定)):
			选定 = _随机取未占用(候选表.get(pid, []), 已用, 允许重复)
		if 选定 <= 0:
			# 候选全被占用：从整池里随机补一个未用角色
			选定 = _随机取未占用(全池, 已用, 允许重复)
		if 选定 <= 0:
			continue
		已用.append(选定)
		角色表[pid] = 选定
	return 角色表


## 在候选里随机挑一个还没被占用的角色号；允许重复时随便挑一个。挑不到（空表 / 全被占）返回 0
func _随机取未占用(候选: Array, 已用: Array, 允许重复: bool) -> int:
	var 可选: Array = []
	for c: Variant in 候选:
		if 允许重复 or not 已用.has(int(c)):
			可选.append(int(c))
	if 可选.is_empty():
		return 0
	return int(可选.pick_random())


## 是否「任选」策略：候选是整张角色表，允许多人选同一个角色
func _任选模式(room: Dictionary) -> bool:
	var 策略: int = int(room.get("role_strategy", 0))
	return 策略 == GConst.RoleStrategy.Any or 策略 == GConst.RoleStrategy.All


## 选将超时（poll 中调用）：到点全体收尾（没提交的取候选第 1 个）
func _check_pick_timeout(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var 截止: int = int(pick.get("deadline", 0))
	if 截止 <= 0 or Time.get_ticks_msec() < 截止:
		return
	_finish_pick_candidates(room)


## 选将期间玩家掉线：未提交的人由收尾兜底；都提交完就直接收尾
func _on_pick_player_left(room: Dictionary, pid: int) -> void:
	if not room.has("pick"):
		return
	var pick: Dictionary = room["pick"]
	if (pick["candidates"] as Dictionary).has(pid) and _pick_candidates_done(room):
		_finish_pick_candidates(room)


## 选将完成：按结果开局并广播（与原来 start() 之后的行为一致）
func _start_battle(room: Dictionary, 角色表: Dictionary) -> void:
	room["started"] = true
	var battle: BattleEngine = room["battle"]
	# 选角结束（Random 策略直接开局，压根没进过选角阶段，这里一并归零）
	battle.room_picking = false
	battle.start_with_roles(角色表)
	rooms_changed.emit()


# ============================================================
# 发送
# ============================================================
func _engine_send(room_id: int, target: int, msg_type: int, fields: Dictionary) -> void:
	var room: Dictionary = _rooms.get(room_id, {})
	if room.is_empty():
		return
	if target < 0:
		_broadcast_raw(room, msg_type, fields)
		return
	# 约定：引擎把 target 填 GUEST = 「只发给观战者」（观战视角那一份，座位表里没有他们）
	if target == GConst.GUEST:
		for cid2: Variant in (room["watchers"] as Array):
			server.send(int(cid2), msg_type, fields)
		return
	var cid: int = int((room["conn_of"] as Dictionary).get(target, -1))
	if cid >= 0:
		server.send(cid, msg_type, fields)
	# 引擎发给玩家的对局快照，观战者也得跟着收（按降频推）：
	# 只走「发给座位玩家」这条路的话，观战画面就一直不动 —— 测试指令、等待倒计时都看不到
	if msg_type == GConst.Msg.Game:
		_请求观战快照(room)


func _broadcast_raw(room: Dictionary, msg_type: int, fields: Dictionary) -> void:
	for cid: int in _房间接收者(room):
		server.send(cid, msg_type, fields)


## 房间广播的收件人：座位上的玩家 + 观战者
func _房间接收者(room: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for pid: int in (room["conn_of"] as Dictionary).keys():
		out.append(int((room["conn_of"] as Dictionary)[pid]))
	for cid: Variant in (room["watchers"] as Array):
		out.append(int(cid))
	return out


## 把观战者名单（昵称）同步给引擎，跟着 Game 快照下发给房内所有人
func _同步观战者名单(room: Dictionary) -> void:
	var 名单: Array[String] = []
	for cid: Variant in (room["watchers"] as Array):
		var s: Dictionary = _sessions.get(int(cid), {})
		名单.append(str(s.get("nickname", "观战者")))
	(room["battle"] as BattleEngine).room_watchers = 名单


## 观战流的降频间隔（毫秒）：观战只要能看清场面，4Hz 就够，省主机出口带宽
const 观战推送间隔_ms: int = 250
## 心跳间隔 / 等回声的超时（毫秒）：间隔越小连接质量越灵敏，超时到点按最差一档显示
const 心跳间隔_ms: int = 2000
const 心跳超时_ms: int = 5000


## 请求推一次观战快照（降频：没到点就先记一笔欠着，由 poll() 到点补发，
## 这样最后一次状态变化一定送得出去，不会停在旧画面）
func _请求观战快照(room: Dictionary) -> void:
	if (room["watchers"] as Array).is_empty():
		room["watch_dirty"] = false
		return
	var 现在: int = Time.get_ticks_msec()
	if 现在 >= int(room["watch_next_ms"]):
		_推送观战快照(room, 现在)
	else:
		room["watch_dirty"] = true


## 把观战快照发给所有观战者（共用同一份，观战人数再多也只算一次）
func _推送观战快照(room: Dictionary, 现在: int) -> void:
	var 观战者们: Array = room["watchers"]
	if 观战者们.is_empty():
		return
	room["watch_next_ms"] = 现在 + 观战推送间隔_ms
	room["watch_dirty"] = false
	_同步连接质量(room)
	var 快照: Dictionary = (room["battle"] as BattleEngine).game_info(GConst.GUEST)
	for cid: Variant in 观战者们:
		server.send(int(cid), GConst.Msg.Game, 快照)


## 广播「按人个性化」的对局信息（只有本人能看到自己的手牌）
func _broadcast_game(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	_同步连接质量(room)
	for pid: int in (room["conn_of"] as Dictionary).keys():
		var cid: int = int((room["conn_of"] as Dictionary)[pid])
		server.send(cid, GConst.Msg.Game, battle.game_info(pid))
	# 观战者看的是观战视角（player_id = GUEST），所有人共用同一份快照
	_请求观战快照(room)


func _room_of(conn_id: int) -> Dictionary:
	var s: Dictionary = _sessions.get(conn_id, {})
	if s.is_empty():
		return {}
	var rid: int = int(s.get("room_id", -1))
	if rid < 0 or not _rooms.has(rid):
		return {}
	return _rooms[rid]

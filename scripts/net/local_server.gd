class_name LocalServer
extends RefCounted
## 权威服务端（对照服务端 DiceGameServer/UserTask.cpp + GameManager.cpp + GameSessionManager）
## 房主进程内运行；承载房间列表、建房/进房/退房、选边、准备，以及权威战斗引擎。
## 去登录：客户端连上后由服务端自动登记身份，客户端只用登录消息上报昵称。

const ROLE_POOL_BASE: Array = [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
	18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
]

## 全部已实现角色（Any 策略用，对照服务端 GameGrailCommon.h 的 SUMMON）
const ROLE_POOL_ANY: Array = [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
	20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 108,
]

## 31/CM 策略每人候选角色数（服务端 StateRoleStrategy31：roles->pop(5, options)）
const ROLE_PICK_COUNT: int = 5

## BP 候选角色数（服务端 GameGrailCommon.h：BP_ALTERNATIVE_NUM[] = {12,16,20}）
const BP_ALTERNATIVE_NUM: Array = [12, 16, 20]

## BP 操作类型（服务端 protocal/action_respond.proto：BP_OPRATION）
const BP_NULL: int = 1
const BP_BAN: int = 2
const BP_PICK: int = 3

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
		# 推进选将阶段的超时（31/Any 到点收尾、BP 到点跳过当前步）
		if room.has("pick"):
			_check_pick_timeout(room)
		# 推进对局回复超时：挂机/掉线玩家到点自动代打，避免整局被一个人卡死
		if _is_battle_playing(room):
			var battle: BattleEngine = room["battle"]
			battle.tick()


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
			server.send(conn_id, GConst.Msg.RoomListRep, {"rooms": _room_infos()})
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
			server.send(conn_id, GConst.Msg.HeartBeat, {})
		GConst.Msg.PickBan:
			var pick_room: Dictionary = _room_of(conn_id)
			if not pick_room.is_empty():
				_on_pick_ban(pick_room, int(s["player_id"]), data)
		GConst.Msg.Action, GConst.Msg.Respond:
			var room: Dictionary = _room_of(conn_id)
			if not room.is_empty():
				var battle: BattleEngine = room["battle"]
				battle.on_message(int(s["player_id"]), msg_type, data)


# ============================================================
# 房间
# ============================================================
func _room_infos() -> Array:
	var out: Array = []
	for rid: int in _rooms.keys():
		var r: Dictionary = _rooms[rid]
		var battle: BattleEngine = r["battle"]
		out.append({
			"room_id": rid,
			"room_name": r["name"],
			"max_player": r["max_player"],
			"now_player": battle.order.size(),
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
		"client_of": {},        # player_id -> client_id（进程身份，断线重连认领座位用）
		"battle": battle,
		"next_player_id": 0,
	}
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
	# 满员则以 GUEST 身份观战
	var pid: int = GConst.GUEST
	var 认领: int = _reclaim_seat(room, str(s.get("client_id", "")))
	if 认领 >= 0:
		# 断线重连：认领回本进程此前在本房间的座位（对局中座位不会被移除）
		pid = 认领
		(room["conn_of"] as Dictionary)[pid] = conn_id
	elif battle.order.size() < int(room["max_player"]):
		pid = int(room["next_player_id"])
		room["next_player_id"] = pid + 1
		battle.add_player(pid, GConst.TEAM_NONE, str(s["nickname"]))
		(room["conn_of"] as Dictionary)[pid] = conn_id
		var cid: String = str(s.get("client_id", ""))
		if cid != "":
			(room["client_of"] as Dictionary)[pid] = cid
	s["room_id"] = room_id
	s["player_id"] = pid
	# 进入房间（含掉线后重新进入）：清除掉线标记，恢复常规回复超时
	if pid != GConst.GUEST:
		battle.set_offline(pid, false)
	_broadcast_game(room)


func leave_room(conn_id: int) -> void:
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty():
		return
	var s: Dictionary = _sessions.get(conn_id, {})
	var pid: int = int(s.get("player_id", -1))
	var battle: BattleEngine = room["battle"]
	if pid >= 0 and pid != GConst.GUEST:
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
	# 房间内已无在线玩家：对局无从继续也无人在看，直接销毁房间
	if (room["conn_of"] as Dictionary).is_empty():
		_rooms.erase(int(room["id"]))
		rooms_changed.emit()
	else:
		_broadcast_game(room)
		rooms_changed.emit()


## 断线重连认领座位：找出本房间内属于该 client_id、且当前无连接占用的座位（无则 -1）
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
	if room.has("pick"):
		# 选将进行中，等待各玩家提交
		return
	if int(room["role_strategy"]) == GConst.RoleStrategy.Random:
		# Random 策略保持原样：不发询问、直接随机分配（自动测试依赖这条零交互路径）
		room["started"] = true
		battle.start(ROLE_POOL_BASE.duplicate())
		rooms_changed.emit()
		return
	_begin_role_pick(room)


func _talk(conn_id: int, txt: String) -> void:
	if txt.strip_edges() == "":
		return
	var room: Dictionary = _room_of(conn_id)
	var nick: String = str(_sessions.get(conn_id, {}).get("nickname", ""))
	if room.is_empty():
		return
	_broadcast_raw(room, GConst.Msg.Gossip, {"type": GConst.GossipType.Talk, "txt": txt, "id": int(_sessions[conn_id]["player_id"])})


# ============================================================
# 选将阶段（对照服务端 DiceGameServer/GrailState.cpp）
# ============================================================
## 开局前入口：按房间策略进入选将流程。选将状态保存在 room["pick"]，由 poll() 推进超时。
func _begin_role_pick(room: Dictionary) -> void:
	match int(room["role_strategy"]):
		GConst.RoleStrategy.BP:
			_begin_pick_bp(room)
		GConst.RoleStrategy.CM:
			_begin_pick_cm(room)
		GConst.RoleStrategy.Any, GConst.RoleStrategy.All:
			# Any 与大厅用的 All：候选人 = 全部已实现角色（服务端 StateRoleStrategyAny 直接下发 SUMMON 全表）
			_begin_pick_candidates(room, ROLE_POOL_ANY, false)
		_:
			# 31（Random 与未指定策略同样走 31）
			_begin_pick_candidates(room, ROLE_POOL_BASE, true)


## 收客户端的 PickBan（选角结果），路由到当前房间的选将状态
func _on_pick_ban(room: Dictionary, pid: int, data: Dictionary) -> void:
	if not room.has("pick") or pid == GConst.GUEST:
		return
	var 模式: String = str((room["pick"] as Dictionary).get("mode", ""))
	if 模式 == "bp":
		_on_pick_ban_bp(room, pid, data)
	elif 模式 == "cm":
		_on_pick_ban_cm(room, pid, data)
	else:
		_on_pick_ban_candidates(room, pid, data)


## 31 / Any：服务端 StateRoleStrategy31(331-372) 与 StateRoleStrategyAny(374-407)
## 抽候选=true 时每人抽 ROLE_PICK_COUNT 个不重复候选（31）；false 时下发整池（Any）
## 下发用 strategy=2：服务端 Coder::askForRole(GameGrailCommon.h:759) 固定填 ROLE_STRATEGY_31，Any 只差候选池
func _begin_pick_candidates(room: Dictionary, pool: Array, 抽候选: bool) -> void:
	var battle: BattleEngine = room["battle"]
	var 池: Array = pool.duplicate()
	池.shuffle()
	var 候选表: Dictionary = {}
	for pid: int in battle.order:
		var 候选: Array = []
		if 抽候选:
			for _k: int in range(ROLE_PICK_COUNT):
				if 池.is_empty():
					池 = pool.duplicate()
					池.shuffle()
				候选.append(int(池.pop_back()))
		else:
			候选 = pool.duplicate()
		候选表[pid] = 候选
	room["pick"] = {
		"mode": "candidate",
		"candidates": 候选表,
		"pool": pool.duplicate(),
		"picked": {},
		"deadline": Time.get_ticks_msec() + PICK_TIMEOUT_MS,
	}
	for pid: int in battle.order:
		_engine_send(int(room["id"]), pid, GConst.Msg.RoleReq, {
			"id": pid,
			"strategy": GConst.RoleStrategy.Strategy31,
			"role_ids": 候选表[pid],
			"args": [],
			"opration": 0,
		})


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


## 收尾 31/Any：超时或掉线者取候选第 1 个（服务端 messages[i]->role_ids(0)，GrailState.cpp:362）；
## 若该角色已被先提交者占用（Any 可能出现），改为该玩家候选里第一个未被占用的角色，保证全局不重复。
func _finish_pick_candidates(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var battle: BattleEngine = room["battle"]
	if battle.order.size() < 2:
		room.erase("pick")
		return
	var 候选表: Dictionary = pick["candidates"]
	var 已选: Dictionary = pick["picked"]
	var 全池: Array = pick["pool"]
	var 已用: Array = []
	var 角色表: Dictionary = {}
	for pid: int in battle.order:
		var 选定: int = int(已选.get(pid, 0))
		if 选定 <= 0 or 已用.has(选定):
			var 该候选: Array = 候选表.get(pid, [])
			选定 = 0
			for c: Variant in 该候选:
				if not 已用.has(int(c)):
					选定 = int(c)
					break
		if 选定 <= 0:
			# 候选全被占用：从整池补一个未用角色
			for c2: Variant in 全池:
				if not 已用.has(int(c2)):
					选定 = int(c2)
					break
		if 选定 <= 0:
			continue
		已用.append(选定)
		角色表[pid] = 选定
	room.erase("pick")
	_start_battle(room, 角色表)


## CM（颜色对抗）：服务端 StateRoleStrategyCM(GrailState.cpp:520-749)
## 步骤：1 = 红队队长禁 1 个；2、3 = 蓝队队长各禁 1 个；4..9 = 红蓝交替选
##   （每个选择步先由对方队长决定是否「额外禁用」一次，再由本方队长为序位队友指定角色）。
## 候选与「每张候选对应的操作」用 args 同步给全员（服务端 727-735 的全量快照）。
## 简化说明：服务端队长由 StateLeaderElection（BECOME_LEADER_REQ 竞选）产生，
##   本引擎取每队座位序最前者为队长；时长上限 9 步，双方各 3 次额外禁用各仅可用一次。
func _begin_pick_cm(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	battle.balance_colors()
	var 人数: int = battle.order.size()
	if 人数 < 4 or 人数 > 8 or 人数 % 2 != 0:
		# 人数无法套用 BP_ALTERNATIVE_NUM：退回 31，避免卡死
		_begin_pick_candidates(room, ROLE_POOL_BASE, true)
		return
	var 候选数: int = int(BP_ALTERNATIVE_NUM[人数 / 2 - 2])
	var 池: Array = ROLE_POOL_BASE.duplicate()
	池.shuffle()
	var 候选: Array = []
	for _i: int in range(候选数):
		if 池.is_empty():
			池 = ROLE_POOL_BASE.duplicate()
			池.shuffle()
		候选.append(int(池.pop_back()))
	var 选项: Array = []
	选项.resize(候选数)
	选项.fill(0)
	var 红方: Array = []
	var 蓝方: Array = []
	for pid: int in battle.order:
		if battle.players[pid].color == GConst.RED:
			红方.append(pid)
		else:
			蓝方.append(pid)
	while 红方.size() > 人数 / 2:
		var 转蓝: int = int(红方.pop_back())
		battle.players[转蓝].color = GConst.BLUE
		蓝方.append(转蓝)
	while 蓝方.size() > 人数 / 2:
		var 转红: int = int(蓝方.pop_back())
		battle.players[转红].color = GConst.RED
		红方.append(转红)
	room["pick"] = {
		"mode": "cm",
		"alternative": 候选,
		"options": 选项,
		"red": 红方,
		"blue": 蓝方,
		"idr": int(红方[0]) if not 红方.is_empty() else -1,
		"idb": int(蓝方[0]) if not 蓝方.is_empty() else -1,
		"ibb": 1,          # 蓝方额外禁用是否仍可用
		"ibr": 1,          # 红方额外禁用是否仍可用
		"decided": false,  # 当前步是否已由对方用过额外禁用（本步不再选人）
		"step": 1,
		"phase": "ask",
		"step_picker": -1, # 本步的选人者（服务端 id1）
		"step_other": -1,  # 本步的额外禁用者（服务端 id2）
		"await_pid": -1,
		"role_map": {},
		"deadline": 0,
	}
	# 开局先广播一次全量候选（服务端 step 0：setCMRoles(-1, ...) + CM_NULL）
	_cm_broadcast(room, -1)
	_cm_prompt_step(room)


## CM 全量快照：idn 为「刚行动者」，供客户端显示高亮
func _cm_broadcast(room: Dictionary, idn: int) -> void:
	var pick: Dictionary = room["pick"]
	_engine_send(int(room["id"]), -1, GConst.Msg.RoleReq, {
		"id": idn,
		"strategy": GConst.RoleStrategy.CM,
		"role_ids": (pick["alternative"] as Array).duplicate(),
		"args": (pick["options"] as Array).duplicate(),
		"opration": GConst.CmOperation.Null,
	})


## 推进当前 CM 步：决定本步询问谁、问哪种操作
func _cm_prompt_step(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var battle: BattleEngine = room["battle"]
	var 步: int = int(pick["step"])
	if 步 > 9:
		_finish_pick_cm(room)
		return
	var 操作: int = GConst.CmOperation.Null
	var 行动者: int = -1
	if 步 == 1:
		操作 = GConst.CmOperation.RedBan
		行动者 = int(pick["idr"])
		pick["step_picker"] = 行动者
		pick["step_other"] = int(pick["idb"])
	elif 步 == 2 or 步 == 3:
		操作 = GConst.CmOperation.BlueBan
		行动者 = int(pick["idb"])
		pick["step_picker"] = 行动者
		pick["step_other"] = int(pick["idr"])
	else:
		var 颜色: int = 步 % 2
		var 序号: int = (步 - 4) / 2
		var 本方: Array = pick["red"] if 颜色 == 0 else pick["blue"]
		var 队长: int = int(pick["idr"]) if 颜色 == 0 else int(pick["idb"])
		var 对方队长: int = int(pick["idb"]) if 颜色 == 0 else int(pick["idr"])
		var 对方可禁: int = int(pick["ibb"]) if 颜色 == 0 else int(pick["ibr"])
		pick["step_picker"] = 队长
		pick["step_other"] = 对方队长
		if 序号 >= 本方.size():
			行动者 = -1
		elif 对方可禁 == 1 and not bool(pick["decided"]):
			# 先问对方队长是否额外禁用（服务端 631-697）
			操作 = GConst.CmOperation.BlueInsertBan if 颜色 == 0 else GConst.CmOperation.RedInsertBan
			行动者 = 对方队长
		else:
			操作 = GConst.CmOperation.RedPick if 颜色 == 0 else GConst.CmOperation.BluePick
			行动者 = 队长
	pick["phase"] = "ask"
	pick["await_pid"] = 行动者
	if 行动者 < 0 or not battle.players.has(行动者):
		# 无人可行动（人数变化/掉线）：按跳过处理，避免卡死
		_cm_resolve(room, 行动者, 0)
		return
	pick["deadline"] = Time.get_ticks_msec() + PICK_TIMEOUT_MS
	_engine_send(int(room["id"]), 行动者, GConst.Msg.RoleReq, {
		"id": 行动者,
		"strategy": GConst.RoleStrategy.CM,
		"role_ids": (pick["alternative"] as Array).duplicate(),
		"args": (pick["options"] as Array).duplicate(),
		"opration": 操作,
	})


func _on_pick_ban_cm(room: Dictionary, pid: int, data: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	if int(pick.get("await_pid", -1)) != pid:
		return
	var 提交: Array = data.get("role_ids", [])
	_cm_resolve(room, pid, int(提交[0]) if not 提交.is_empty() else 0)


## 结算一次 CM 询问，并推进（服务端 574-741）
## 超时/无人应答按「跳过该次操作」处理（服务端会直接 GE_TIMEOUT 卡住整局）
func _cm_resolve(room: Dictionary, pid: int, 选中角色: int) -> void:
	var pick: Dictionary = room["pick"]
	var 步: int = int(pick["step"])
	var 候选: Array = pick["alternative"]
	var 选项: Array = pick["options"]
	var 索引: int = -1
	for i: int in range(候选.size()):
		if int(候选[i]) == 选中角色 and int(选项[i]) == 0:
			索引 = i
			break
	pick["await_pid"] = -1
	pick["deadline"] = 0
	var 额外禁: bool = 步 > 3 and int(pick["step_other"]) == pid
	if 步 == 1:
		if 索引 >= 0:
			选项[索引] = GConst.CmOperation.RedBan
	elif 步 == 2 or 步 == 3:
		if 索引 >= 0:
			选项[索引] = GConst.CmOperation.BlueBan
	elif 额外禁:
		# 额外禁用：不论是否真的禁用，本步都转入「选人」（服务端 640/672：decided = true）
		pick["decided"] = true
		if 选中角色 != GConst.CM_CANCEL_ROLE_ID and 索引 >= 0:
			if 步 % 2 == 0:
				选项[索引] = GConst.CmOperation.BlueInsertBan
				pick["ibb"] = 0
			else:
				选项[索引] = GConst.CmOperation.RedInsertBan
				pick["ibr"] = 0
	else:
		# 选人：由本方队长为序位队友指定角色
		pick["decided"] = false
		var 颜色: int = 步 % 2
		var 序号: int = (步 - 4) / 2
		var 本方: Array = pick["red"] if 颜色 == 0 else pick["blue"]
		if 序号 < 本方.size():
			var 对象: int = int(本方[序号])
			var 记录: int = GConst.CmOperation.RedPick if 颜色 == 0 else GConst.CmOperation.BluePick
			if 索引 >= 0:
				选项[索引] = 记录
				(pick["role_map"] as Dictionary)[对象] = 选中角色
			else:
				# 超时/掉线/非法提交：自动取第一个未被占用的候选（服务端会卡死，这里保证推进）
				for i2: int in range(候选.size()):
					if int(选项[i2]) == 0:
						选项[i2] = 记录
						(pick["role_map"] as Dictionary)[对象] = int(候选[i2])
						break
	var idn: int = int(pick["step_picker"])
	if 步 <= 3:
		idn = int(pick["idr"]) if 步 == 1 else int(pick["idb"])
	elif bool(pick["decided"]):
		idn = int(pick["step_other"])
	_cm_broadcast(room, idn)
	if not bool(pick["decided"]):
		pick["step"] = 步 + 1
	_cm_prompt_step(room)


func _finish_pick_cm(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var battle: BattleEngine = room["battle"]
	if battle.order.size() < 2:
		room.erase("pick")
		return
	var 角色表: Dictionary = (pick["role_map"] as Dictionary).duplicate()
	var 候选: Array = pick["alternative"]
	var 选项: Array = pick["options"]
	# 人数中途变化可能让个别玩家没被指定：用未占用的候选补齐
	for pid: int in battle.order:
		if 角色表.has(pid):
			continue
		for i: int in range(候选.size()):
			if int(选项[i]) == 0:
				选项[i] = GConst.CmOperation.RedPick
				角色表[pid] = int(候选[i])
				break
	room.erase("pick")
	_start_battle(room, 角色表)


## BP：服务端 StateRoleStrategyBP(409-518)
## 步进完全按服务端 446-454 行：color = step % 2（1=红 0=蓝）、index = (step-1)/4、
## isPick = ((step-1)/2) % 2（0=BAN 1=PICK）；每步只向行动者发 BP_BAN / BP_PICK，
## 该步结束后再用 BP_NULL 给全员发「候选 + 每张候选对应步号」的全量快照（服务端 507-510）。
func _begin_pick_bp(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	# BP 按红蓝各半推导行动者，服务端由布座阶段保证人数均衡，这里先配平
	battle.balance_colors()
	var 人数: int = battle.order.size()
	if 人数 < 4 or 人数 > 8 or 人数 % 2 != 0:
		# 人数无法套用 BP_ALTERNATIVE_NUM（服务端会 GE_FATAL_ERROR）：退回 31，避免卡死
		_begin_pick_candidates(room, ROLE_POOL_BASE, true)
		return
	var 候选数: int = int(BP_ALTERNATIVE_NUM[人数 / 2 - 2])
	var 池: Array = ROLE_POOL_BASE.duplicate()
	池.shuffle()
	var 候选: Array = []
	for _i: int in range(候选数):
		if 池.is_empty():
			池 = ROLE_POOL_BASE.duplicate()
			池.shuffle()
		候选.append(int(池.pop_back()))
	var 选项: Array = []
	选项.resize(候选数)
	选项.fill(0)
	var 红方: Array = []
	var 蓝方: Array = []
	for pid: int in battle.order:
		if battle.players[pid].color == GConst.RED:
			红方.append(pid)
		else:
			蓝方.append(pid)
	while 红方.size() > 人数 / 2:
		var 转蓝: int = int(红方.pop_back())
		battle.players[转蓝].color = GConst.BLUE
		蓝方.append(转蓝)
	while 蓝方.size() > 人数 / 2:
		var 转红: int = int(蓝方.pop_back())
		battle.players[转红].color = GConst.RED
		红方.append(转红)
	room["pick"] = {
		"mode": "bp",
		"candidates": {},
		"pool": [],
		"picked": {},
		"alternative": 候选,
		"options": 选项,
		"red": 红方,
		"blue": 蓝方,
		"step": 1,
		"await_pid": -1,
		"await_is_pick": false,
		"role_map": {},
		"deadline": 0,
	}
	# 开局先广播一次全量候选（服务端 435-443：setAlternativeRoles(-1, ...) + BP_NULL）
	_engine_send(int(room["id"]), -1, GConst.Msg.RoleReq, {
		"id": -1,
		"strategy": GConst.RoleStrategy.BP,
		"role_ids": 候选.duplicate(),
		"args": 选项.duplicate(),
		"opration": BP_NULL,
	})
	_bp_prompt_step(room)


## 推进当前 BP 步：给行动者发询问（服务端 while 循环内的 waitForOne）
func _bp_prompt_step(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var battle: BattleEngine = room["battle"]
	var 步: int = int(pick["step"])
	if 步 > battle.order.size() * 2:
		_finish_pick_bp(room)
		return
	var 颜色: int = 步 % 2
	var 序号: int = (步 - 1) / 4
	var 是选: bool = ((步 - 1) / 2) % 2 == 1
	var 方: Array = pick["red"] if 颜色 == 1 else pick["blue"]
	var 行动者: int = int(方[序号]) if 序号 < 方.size() else -1
	pick["await_pid"] = 行动者
	pick["await_is_pick"] = 是选
	if 行动者 < 0 or not battle.players.has(行动者):
		# 该步无人可行动（人数变化/掉线）：按超时跳过，避免卡死
		_bp_resolve_step(room, 行动者, 0)
		return
	pick["deadline"] = Time.get_ticks_msec() + PICK_TIMEOUT_MS
	_engine_send(int(room["id"]), 行动者, GConst.Msg.RoleReq, {
		"id": 行动者,
		"strategy": GConst.RoleStrategy.BP,
		"role_ids": (pick["alternative"] as Array).duplicate(),
		"args": (pick["options"] as Array).duplicate(),
		"opration": BP_PICK if 是选 else BP_BAN,
	})


func _on_pick_ban_bp(room: Dictionary, pid: int, data: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	if int(pick.get("await_pid", -1)) != pid:
		return
	var 提交: Array = data.get("role_ids", [])
	if 提交.is_empty():
		return
	_bp_resolve_step(room, pid, int(提交[0]))


## 结算一步：把该角色记到第 步（options[i] = step），PICK 步记归行动者；随后广播全量快照并推进。
## 服务端在 BP 超时时直接 return GE_TIMEOUT（整个状态不再推进、房间会卡住）；
## 这里按「不要让房间卡死」的要求改为跳过该步：BAN 步不记录，PICK 步自动取第一个未被占用的候选。
func _bp_resolve_step(room: Dictionary, pid: int, 选中角色: int) -> void:
	var pick: Dictionary = room["pick"]
	var 步: int = int(pick["step"])
	var 是选: bool = bool(pick["await_is_pick"])
	var 候选: Array = pick["alternative"]
	var 选项: Array = pick["options"]
	var 实际角色: int = 0
	if 选中角色 > 0:
		for i: int in range(候选.size()):
			if int(候选[i]) == 选中角色:
				if int(选项[i]) == 0:
					选项[i] = 步
					实际角色 = 选中角色
				break
	if 实际角色 <= 0 and 是选:
		for i2: int in range(候选.size()):
			if int(选项[i2]) == 0:
				选项[i2] = 步
				实际角色 = int(候选[i2])
				break
	if 是选 and 实际角色 > 0:
		(pick["role_map"] as Dictionary)[pid] = 实际角色
	if 实际角色 > 0:
		_engine_send(int(room["id"]), -1, GConst.Msg.RoleReq, {
			"id": pid,
			"strategy": GConst.RoleStrategy.BP,
			"role_ids": 候选.duplicate(),
			"args": 选项.duplicate(),
			"opration": BP_NULL,
		})
	pick["step"] = 步 + 1
	pick["await_pid"] = -1
	pick["deadline"] = 0
	_bp_prompt_step(room)


func _finish_pick_bp(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var battle: BattleEngine = room["battle"]
	if battle.order.size() < 2:
		room.erase("pick")
		return
	var 角色表: Dictionary = (pick["role_map"] as Dictionary).duplicate()
	# 人数中途变化可能让个别玩家没轮到 PICK：用未占用的候选补齐，避免开局缺角色
	var 候选: Array = pick["alternative"]
	var 选项: Array = pick["options"]
	for pid: int in battle.order:
		if 角色表.has(pid):
			continue
		for i: int in range(候选.size()):
			if int(选项[i]) == 0:
				选项[i] = int(pick["step"])
				角色表[pid] = int(候选[i])
				break
	room.erase("pick")
	_start_battle(room, 角色表)


## 选将超时（poll 中调用）：31/Any 到点全体收尾；BP / CM 当前步跳过
func _check_pick_timeout(room: Dictionary) -> void:
	var pick: Dictionary = room["pick"]
	var 截止: int = int(pick.get("deadline", 0))
	if 截止 <= 0 or Time.get_ticks_msec() < 截止:
		return
	var 模式: String = str(pick.get("mode", ""))
	if 模式 == "bp":
		_bp_resolve_step(room, int(pick.get("await_pid", -1)), 0)
	elif 模式 == "cm":
		_cm_resolve(room, int(pick.get("await_pid", -1)), 0)
	else:
		_finish_pick_candidates(room)


## 选将期间玩家掉线：按超时处理（31/Any 由收尾兜底；BP 若正轮到他就跳过该步）
func _on_pick_player_left(room: Dictionary, pid: int) -> void:
	if not room.has("pick"):
		return
	var pick: Dictionary = room["pick"]
	var 模式: String = str(pick.get("mode", ""))
	if 模式 == "bp":
		if int(pick.get("await_pid", -1)) == pid:
			_bp_resolve_step(room, pid, 0)
		return
	if 模式 == "cm":
		if int(pick.get("await_pid", -1)) == pid:
			_cm_resolve(room, pid, 0)
		return
	if (pick["candidates"] as Dictionary).has(pid) and _pick_candidates_done(room):
		_finish_pick_candidates(room)


## 选将完成：按结果开局并广播（与原来 start() 之后的行为一致）
func _start_battle(room: Dictionary, 角色表: Dictionary) -> void:
	room["started"] = true
	var battle: BattleEngine = room["battle"]
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
	else:
		var cid: int = int((room["conn_of"] as Dictionary).get(target, -1))
		if cid >= 0:
			server.send(cid, msg_type, fields)


func _broadcast_raw(room: Dictionary, msg_type: int, fields: Dictionary) -> void:
	for pid: int in (room["conn_of"] as Dictionary).keys():
		var cid: int = int((room["conn_of"] as Dictionary)[pid])
		server.send(cid, msg_type, fields)


## 广播「按人个性化」的对局信息（只有本人能看到自己的手牌）
func _broadcast_game(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	for pid: int in (room["conn_of"] as Dictionary).keys():
		var cid: int = int((room["conn_of"] as Dictionary)[pid])
		server.send(cid, GConst.Msg.Game, battle.game_info(pid))


func _room_of(conn_id: int) -> Dictionary:
	var s: Dictionary = _sessions.get(conn_id, {})
	if s.is_empty():
		return {}
	var rid: int = int(s.get("room_id", -1))
	if rid < 0 or not _rooms.has(rid):
		return {}
	return _rooms[rid]

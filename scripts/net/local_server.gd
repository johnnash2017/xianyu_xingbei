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

## 观战席上限（与 Steam 大厅的观战席数一致）：观战者不占战斗座位，但也不能无限进
const 观战者上限: int = 16
## 入站字符串的服务端长度上限（字符）。必须由服务端自己截断 —— 客户端的输入框限制挡不住改包，
## 而这些字（昵称 / 房名 / 聊天）会随对局快照广播给全房，太长会让整帧超过 Framing.MAX_FRAME 被静默丢弃
const 昵称最大字符数: int = 24
const 房名最大字符数: int = 24
const 聊天最大字符数: int = 128
## 身份标识（client_id）的最大长度：它会被写进 Steam 大厅数据，也不该放任超长
const 身份标识最大字符数: int = 64

signal rooms_changed

var server: NetworkServer = null
var _sessions: Dictionary = {}     # conn_id -> {nickname, room_id, player_id}
var _rooms: Dictionary = {}        # room_id -> 房间字典
var _next_room_id: int = 1
## 上一次写给 Steam 大厅的数据（拼成一个字符串比对，见 _同步大厅数据）：内容没变就不重复写
var _大厅已写数据: String = ""
## 上面那份数据是写进哪个 Steam 大厅的：Steam 掉线重连后会新建大厅（旧数据全没了），
## 大厅号一变就必须重写一遍，否则「内容没变就不写」会让新大厅一直空着（见 _同步大厅数据）
var _大厅已写大厅id: int = 0
## 变化太密、还没到写入间隔的那一份大厅数据（由 poll 到点补写，保证最后一次变化送得出去）
var _大厅待写: Dictionary = {}
## 上一次真正写 Steam 大厅的时刻（毫秒）
var _大厅写入时刻_ms: int = 0
## Steam 大厅数据的最小写入间隔（毫秒）：对局快照每帧都可能刷新，而 Steam 侧对大厅数据更新有限流，
## 变化太密时先攒着、由 poll 到点补写（见 _推大厅数据）
const 大厅写入间隔_ms: int = 1500


# ============================================================
# 启动 / 轮询
# ============================================================
func start(port: int) -> int:
	randomize()
	# 传输底座按启动模式选（写成 if/else 而不是三元表达式：两个实现类型不同，三元会被判「分支类型不兼容」）：
	#   本地调试 / 局域网模式 —— 只监听 TCP 端口；
	#   Steam 模式 —— Steam P2P + 局域网 TCP 双路复用，房间同时向「Steam 大厅」和
	#   「同一局域网的机器」开放（后者不需要 Steam 账号，见 MultiServer）
	if Cfg.无Steam():
		server = NetServer.new()
	else:
		server = MultiServer.new()
	var err: int = server.listen(port)
	if err != OK:
		return err
	server.client_connected.connect(_on_client_connected)
	server.client_disconnected.connect(_on_client_disconnected)
	server.client_message.connect(_on_client_message)
	return OK


func stop() -> void:
	server.stop()
	for room: Dictionary in _rooms.values():
		_解绑房间(room)
	_rooms.clear()
	_sessions.clear()
	server = null


## 让房主自己那一路客户端接上本机服务端（只有 Steam 模式用）。
## Steam NetworkingMessages 的「发给自己」会被对端当成关闭连接（实测发送返回 35 + 抛会话失败），
## 房主自己收不到任何下行包、还会被上层当成掉线踢回大厅，所以房主自己一律走进程内直连。
## 连接号用本机 SteamID（与对端的 SteamID 同一套编号，不会撞）。
## Steam 模式下的底座是多路复用的（MultiServer），由它转交给内部的 Steam 底座。
func 接入本地客户端(c: SteamClient, 连接号: int) -> void:
	server.接入本地客户端(c, 连接号)
	c.本机投递 = func(协议号: int, 字段: Dictionary) -> void: _on_client_message(连接号, 协议号, 字段)


func poll() -> void:
	server.poll()
	for rid: int in _rooms.keys():
		var room: Dictionary = _rooms[rid]
		# 一局打完：这间房不再复用（准备 / 开局都被 started 封死），立刻解散。
		# 不散的话它会永远挂在列表上显示「战斗中」，里面的人按准备 / 选边 / 再开局全没反应。
		# 玩家那边不会被踢走：终局快照带着 over，客户端据此留在结算界面看结果（见 client_logic）
		if _本局已结束(room):
			_解散房间(room)
			continue    # 已打完：选角 / 开局 / 心跳都不必再推进（房间已在这轮里销毁）
		# 推进选将阶段的超时（到点还没提交的按候选第 1 个收尾）
		if room.has("pick"):
			_check_pick_timeout(room)
		# 推进开局倒计时：条件被打断就撤销，到点真正开局
		_check_start_countdown(room)
		# 推进对局回复超时：挂机/掉线玩家到点自动代打，避免整局被一个人卡死
		if _is_battle_playing(room):
			var battle: BattleEngine = room["battle"]
			battle.tick()
		# 观战流是降频推的：欠着的快照到点补发，保证最后一次状态变化不会被吃掉
		if bool(room["watch_dirty"]):
			_请求观战快照(room)
	# 连接质量 / 幽灵连接：定期给「每一条还连着的连接」打一次心跳（不只是房间里的人，见 _推心跳）
	_推心跳()
	# 房间列表数据变了但还没写给 Steam 大厅的，到点补写（见 _同步大厅数据）
	_推大厅数据()


## 心跳 / 延迟测量：每 心跳间隔_ms 给「每一条还连着的连接」发一次 HeartBeat，客户端回声后即可算出往返延迟。
## 必须覆盖房间外的人：Steam P2P 没有底层断连事件，只能靠回声超时判定掉线；
## 只给房里的人发的话，在大厅里就消失的玩家会永远挂在会话表里（幽灵连接，见 _sessions）。
func _推心跳() -> void:
	var 现在: int = Time.get_ticks_msec()
	var 掉线: Array[int] = []
	for cid: int in _sessions.keys():
		var s: Dictionary = _sessions[cid]
		# 这一轮心跳还在等回声（ping_sent_ms > 0）；回音到了由 _记心跳回声 清零
		var 等回声起_ms: int = int(s.get("ping_sent_ms", 0))
		if 等回声起_ms > 0:
			# 「连续多久没有回音」的起点（ping_since_ms）：本轮心跳超时后会重发一次，
			# 重发只更新 ping_sent_ms、不动它 —— 否则掉线判定永远攒不够时间（见下）
			var 无回声起_ms: int = int(s.get("ping_since_ms", 等回声起_ms))
			var 等了: int = 现在 - 等回声起_ms
			# Steam P2P 没有「底层断连」事件，只能靠回声超时判定掉线。
			# 判据必须挂在「这一次心跳有没有回音」上，绝不能看「多久没收到它的任何消息」：
			# 「最近收到消息的时刻」对不回心跳的人永远是陈旧值，会把好好的人误判成掉线。
			# 局域网 TCP 由底座自己发现断连，这里不重复判定（底座不同，按连接分别判断）
			if server.靠回声判掉线(cid) and 现在 - 无回声起_ms > 掉线超时_ms:
				掉线.append(cid)
				continue
			if 等了 > 心跳超时_ms:
				# 回声迟迟不来：先按最差一档显示延迟；清掉「本轮等回声」标记让下一轮重新发一次
				# （留在「等回声」上就再也不发心跳了，回音真到了也无法恢复）。
				# 只清 ping_sent_ms、不动 ping_since_ms：连着几轮都没回音才算掉线
				s["ping_ms"] = 心跳超时_ms
				s["ping_sent_ms"] = 0
			continue
		if 现在 - int(s.get("ping_last_ms", 0)) >= 心跳间隔_ms:
			s["ping_sent_ms"] = 现在
			s["ping_last_ms"] = 现在
			# 还没有「连续无回音」起点时记一个，直到收到回音才清（见 _记心跳回声）
			if int(s.get("ping_since_ms", 0)) <= 0:
				s["ping_since_ms"] = 现在
			server.send(cid, GConst.Msg.HeartBeat, {})
	# 掉线的统一在遍历外断开：close_conn 会连锁触发退房，不能在遍历中改房间结构
	for cid: int in 掉线:
		server.close_conn(cid)


## 收到心跳回声：这一轮心跳有了回音（清掉「等回声」标记），顺便算出往返延迟并平滑（旧值权重 2/3）
func _记心跳回声(conn_id: int) -> void:
	var s: Dictionary = _sessions.get(conn_id, {})
	if s.is_empty():
		return
	var 发出: int = int(s.get("ping_sent_ms", 0))
	if 发出 <= 0:
		# 没欠着回声：只说明「这一轮已经回来了」，连续无回音的起点照旧清零
		s["ping_since_ms"] = 0
		return
	s["ping_sent_ms"] = 0
	# 回音到了：清掉「连续无回音」起点（掉线判定按它累计，见 _推心跳）
	s["ping_since_ms"] = 0
	var 新值: int = Time.get_ticks_msec() - 发出
	# 第一次测到（旧值还是未测哨兵）：直接用新值，别拿哨兵去平滑，否则要把均值一路带偏
	var 旧值: int = int(s.get("ping_ms", GConst.PING_未测))
	@warning_ignore("integer_division")
	s["ping_ms"] = 新值 if 旧值 >= GConst.PING_未测 else (旧值 * 2 + 新值) / 3


## 房主坐在哪个座位上（没有 = -1）：用 conn_of 反查「房主那条连接占着哪个座位」。
## 快照里的 host_seat 就是它，客户端「玩家列表」据此给房主标星号
func _房主座位(room: Dictionary) -> int:
	var 房主连接: int = int(room.get("host_conn", -1))
	if 房主连接 < 0:
		return -1
	for pid: Variant in (room["conn_of"] as Dictionary).keys():
		if int(room["conn_of"][pid]) == 房主连接:
			return int(pid)
	return -1


## 把各连接测出的延迟写进玩家：快照会带着它一起下发（「玩家列表」右侧那一列）
func _同步连接质量(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	var conn_of: Dictionary = room["conn_of"]
	for pid: int in conn_of.keys():
		if not battle.players.has(pid):
			continue
		var s: Dictionary = _sessions.get(int(conn_of[pid]), {})
		(battle.players[pid] as BattlePlayer).ping_ms = int(s.get("ping_ms", GConst.PING_未测))


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


## 本房间是否已经进入「留座」阶段：选角开始之后（选角中 / 对局中都要留座）。
## 准备室阶段不留座 —— 退出就是退出：离席即释放座位与身份绑定，回来按新玩家重新落座，
## 房间列表也不显示「可重连」（见 leave_room / enter_room / _room_infos 的 can_reenter）
func _留座阶段(room: Dictionary) -> bool:
	return bool(room["started"]) or room.has("pick")


## 把座位连同身份绑定一起释放（准备室离席、房主退房都走这一份）：座位从座位表里摘掉，
## 身份绑定清掉（回来就是个新玩家）。选角开始之后的离席不释放座位，见 leave_room。
func _释放座位(room: Dictionary, pid: int) -> void:
	(room["conn_of"] as Dictionary).erase(pid)
	(room["battle"] as BattleEngine).remove_player(pid)
	(room["client_of"] as Dictionary).erase(pid)


## 本局是否已经打完（有结果、不再推进）：打完的房间不再复用，见 poll 里的解散处理
func _本局已结束(room: Dictionary) -> bool:
	if not bool(room.get("started", false)):
		return false
	return (room["battle"] as BattleEngine).phase == BattleEngine.Phase.Over


# ============================================================
# 连接生命周期
# ============================================================
func _on_client_connected(conn_id: int) -> void:
	_sessions[conn_id] = {
		"nickname": "玩家%d" % conn_id,
		"room_id": -1,
		"player_id": -1,
		"client_id": "",
		"ping_ms": GConst.PING_未测,   # 这一路测出的往返延迟；未测出来时是哨兵值（0ms 是合法值，房主自己就是 0）
		"ping_sent_ms": 0,   # 本轮心跳发出时刻；0 = 没欠着回声（没发过 / 已经回来了）
		"ping_last_ms": 0,   # 上一轮心跳发出时刻（控制发送间隔）
		"ping_since_ms": 0,  # 「连续没有回音」的起点（0 = 最近一轮心跳有回音）：掉线判定按它累计
	}


func _on_client_disconnected(conn_id: int) -> void:
	var room: Dictionary = _room_of(conn_id)
	if _is_battle_playing(room):
		var pid: int = int(_sessions.get(conn_id, {}).get("player_id", -1))
		if pid >= 0 and pid != GConst.GUEST:
			# 对局中掉线：标记掉线，引擎把等待时限收紧到掉线超时并自动代打
			var battle: BattleEngine = room["battle"]
			battle.set_offline(pid, true)
	leave_room(conn_id, true)
	_sessions.erase(conn_id)


func _on_client_message(conn_id: int, msg_type: int, data: Dictionary) -> void:
	var s: Dictionary = _sessions.get(conn_id, {})
	if s.is_empty():
		# 会话不在了（这条连接被判掉线断开过）却又来消息：只有「登录」能把它重新登记回来。
		# 少了这一步，房主自己那一路断一次就永远失聪 —— 他照旧发消息，服务端一句不理，
		# 界面上建房 / 准备 / 退出全都没反应、也不会报错（见 SteamServer._断开 与 SteamClient.收到断开）
		if msg_type != GConst.Msg.LoginReq:
			return
		_on_client_connected(conn_id)
		s = _sessions[conn_id]
	# 版本不合格的连接：只放行「登录」消息 —— 对方更新完再连时要在那里重新判一次
	# （早先这里是「一律不理」，结果 Steam 下连接号就是同一个 SteamID，被拒一次之后就永远不合格了：
	#   第二次进来连错误都不回，客户端一直卡在「正在进入房间…」）。其余消息照旧不理会
	if msg_type != GConst.Msg.LoginReq and bool(s.get("版本不合格", false)):
		return
	match msg_type:
		GConst.Msg.LoginReq:
			# 版本不一致：直接拒绝（新旧版本的房间在列表里互相看得见，但进不去房间）。
			# 大厅隔离标记 / 局域网发现只负责「显示对方版本」，这里挡的是真进房 ——
			# 不同版本的房间数据与协议细节都可能对不上
			var 对端版本: String = str(data.get("game_version", ""))
			var 本机版本: String = Cfg.游戏版本()
			if 对端版本 != 本机版本:
				# 谁低谁去更新：本机更低 → 告诉对端「对方版本过低」；
				# 否则（对端更低，或只是写法不同但数值相等）让对端去更新
				var 码: int = GConst.GE_VERSION_PEER_HIGH if GConst.版本比较(对端版本, 本机版本) > 0 else GConst.GE_VERSION_PEER_LOW
				server.send(conn_id, GConst.Msg.Error, {"id": 码, "dst_id": conn_id, "args": []})
				# 不在这里主动断开：先保证这条错误消息发得出去（立刻断可能把它一起丢掉），
				# 客户端收到后会自己断开；服务端这侧标记后不再理会它的非登录消息
				s["版本不合格"] = true
				return
			# 之前不合格过、现在版本对上了（对方更新完重连）：放行
			s.erase("版本不合格")
			# 去登录：仅用登录消息上报昵称与进程身份。
			# 长度一律按服务端自己的上限截断：这些字会随快照广播给全房，不能采信客户端的限制
			var nick: String = str(data.get("user_id", "")).left(昵称最大字符数)
			if nick != "":
				s["nickname"] = nick
			var cid: String = str(data.get("client_id", "")).left(身份标识最大字符数)
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
			# 房主勾了「作弊」（调试模式）：房间列表据此显示一段提示（没勾就不显示）
			"debug": battle.room_debug,
			"role_range": 31,
			"allow_guest": r["allow_guest"],
			"has_password": false,
			"first_extension": false,
			"second_extension": false,
			"sp_mo_dao": false,
			"playing": r["started"],
			"silence": false,
			# 房主版本号：房间列表要显示（进不进得去由登录时的版本校验决定，见 LoginReq）
			"version": Cfg.游戏版本(),
			# 只有「留座阶段」（选角开始之后）才有可重连这一说：准备室离席即放弃座位（见 _留座阶段）
			"can_reenter": _留座阶段(r) and _reclaim_seat(r, conn_id) >= 0,
		})
	return out


func create_room(conn_id: int, data: Dictionary) -> void:
	if int(_sessions[conn_id]["room_id"]) >= 0:
		leave_room(conn_id)
	var room: Dictionary = _建房间(data, conn_id)
	_rooms[int(room["id"])] = room
	enter_room(conn_id, int(room["id"]))
	rooms_changed.emit()


## 按建房参数造一个房间对象（不登记到 _rooms）
func _建房间(数据: Dictionary, 房主连接: int) -> Dictionary:
	var rid: int = _next_room_id
	_next_room_id += 1
	var battle: BattleEngine = BattleEngine.new()
	battle.room_id = rid
	var room: Dictionary = {
		"id": rid,
		"name": str(数据.get("room_name", "房间%d" % rid)).left(房名最大字符数),
		"max_player": clampi(int(数据.get("max_player", 6)), 2, GConst.MAX_PLAYER),
		"role_strategy": int(数据.get("role_strategy", GConst.RoleStrategy.Random)),
		"seat_mode": int(数据.get("seat_mode", GConst.SeatMode.Random)),
		"allow_guest": bool(数据.get("allow_guest", true)),
		"started": false,
		# 房主的身份标识：断线重连后靠它把「房主」重新绑回房主的新连接（见 enter_room）。
		# 光留连接号不够 —— 连接一断，就再也认不出谁是房主了
		"host_id": str(_sessions.get(房主连接, {}).get("client_id", "")),
		# 房主的连接号：房主主动退房时据此判断「这间房该整间解散」（见 leave_room）
		"host_conn": 房主连接,
		"conn_of": {},          # player_id -> conn_id
		"client_of": {},        # player_id -> 客户端身份标识（认领座位用；局域网 = 昵称，Steam = SteamID）
		"watchers": [],         # 观战者 conn_id 列表（满员时进来的人，不占座位，可同时有多个）
		"watch_next_ms": 0,     # 观战流下次可发送的时刻（降频用）
		"watch_dirty": false,   # 有没有欠着还没发出去的观战快照
		"battle": battle,
	}
	battle.room_name = str(room["name"])
	battle.room_max_player = int(room["max_player"])
	battle.room_debug = bool(数据.get("debug", false))
	battle.seat_mode = int(room["seat_mode"])
	battle.send_cb = func(target: int, msg_type: int, fields: Dictionary) -> void:
		_engine_send(rid, target, msg_type, fields)
	return room


func enter_room(conn_id: int, room_id: int) -> void:
	if not _rooms.has(room_id):
		server.send(conn_id, GConst.Msg.Error, {"id": GConst.GE_INVALID_TABLEID, "dst_id": conn_id, "args": []})
		return
	# 已打完的房间会在几秒内解散（见 poll）：别再让人进来对着一个已经结束的局
	if _本局已结束(_rooms[room_id]):
		server.send(conn_id, GConst.Msg.Error, {"id": GConst.GE_INVALID_TABLEID, "dst_id": conn_id, "args": []})
		return
	var room: Dictionary = _rooms[room_id]
	var battle: BattleEngine = room["battle"]
	var s: Dictionary = _sessions[conn_id]
	# 已经在这间房里（例如同一条连接又发了一次进房请求）：直接补发快照。
	# 不能走下面「先退房再进」——退房会把没人的房间销毁掉，随后这次的进房就找不到房间了
	if int(s["room_id"]) == room_id:
		_broadcast_game(room)
		# 同一条连接又发了一次进房请求（断线重连最常见）：快照之外，选角请求与「当前该谁回话」
		# 也要补发，否则他重连回来会停在准备室、看不到该自己提交的选角弹层 / 回应询问
		var 重连pid: int = int(s.get("player_id", -1))
		if 重连pid >= 0:
			_补发选角请求(room, 重连pid)
			battle.重发当前询问(重连pid)
		return
	if int(s["room_id"]) >= 0:
		leave_room(conn_id)
	# 有座位就落座；满员则作为观战者进来（不占座位，能同时有多个）
	var pid: int = GConst.GUEST
	var 认领: int = _reclaim_seat(room, conn_id)
	if 认领 >= 0:
		# 认领回本进程此前在本房间的座位。
		# 座位要是还占在自己那条旧连接上（它还没被判掉线），先把它踢掉再坐回来
		pid = 认领
		_踢掉占座连接(room, pid, conn_id)
		(room["conn_of"] as Dictionary)[pid] = conn_id
		if not _留座阶段(room):
			# 准备室不留座：同一个人的旧连接还挂着座位时（掉线还没被判定出来 ——
			# Steam P2P 没有底层断连事件，得等心跳回声超时），只把座位号还给他，
			# 队伍与准备状态一律从零开始，与「离席后重新进房」的结果一致
			battle.set_color(pid, GConst.TEAM_NONE)
			battle.set_ready(pid, false)
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
	elif (room["watchers"] as Array).size() < 观战者上限:
		(room["watchers"] as Array).append(conn_id)
	else:
		# 观战席也满了：不进房（也不占座位），回一条「房间已满」让界面照常提示。
		# 此刻会话还没绑定房间，直接返回即可（下面那句 s["room_id"] = room_id 不会执行）
		server.send(conn_id, GConst.Msg.Error, {"id": GConst.GE_PLAYER_FULL, "dst_id": conn_id, "args": []})
		return
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
		# 房主本人回来了（按身份认，见 _建房间 里 host_id 的说明）：把「房主」重新绑到他这条新连接上。
		# 断线重连后 host_conn 指着一条已经不在的连接 —— 不重绑的话，玩家列表上房主星号会消失，
		# 而且他之后退房时不会被当成房主（那是「整间解散」的判据，见 leave_room）
		if str(room.get("host_id", "")) != "" and str(s.get("client_id", "")) == str(room["host_id"]):
			room["host_conn"] = conn_id
	_broadcast_game(room)
	if pid != GConst.GUEST:
		# 补发必须排在快照之后：客户端是「收到快照 → 切到准备室 / 战斗界面」，
		# 而切界面会把界面层清一遍（见 UI.goto），弹层要等那之后才建得起来
		_补发选角请求(room, pid)
		battle.重发当前询问(pid)


## 离开房间（掉线那条走 掉线=true，见 _on_client_disconnected）
func leave_room(conn_id: int, 掉线: bool = false) -> void:
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty():
		return
	var s: Dictionary = _sessions.get(conn_id, {})
	var pid: int = int(s.get("player_id", -1))
	# 房主主动走了：整间解散（房主一走，这间房就没人接着开了）。
	# 掉线不算「走」：他多半会重连回来，房间留着（座位按下面普通离席的规则处理）
	if not 掉线 and int(room.get("host_conn", -1)) == conn_id:
		if pid >= 0 and pid != GConst.GUEST:
			# 先按「准备室离席」把自己的座位摘掉：他这个连接也就脱离了房间，
			# 不会再收到这间房随后发的那句「房间不存在」（房间正是他这次退房拆掉的）
			_释放座位(room, pid)
		if not s.is_empty():
			_离房清会话(s)
		_房主离开(room)
		return
	var battle: BattleEngine = room["battle"]
	if pid == GConst.GUEST:
		# 观战者离席：从观战名单里去掉，不涉及座位
		(room["watchers"] as Array).erase(conn_id)
	elif pid >= 0:
		if _留座阶段(room):
			# 选角中 / 对局中：座位不可移除 —— 引擎状态机、等待对象、选角候选表都按座位号指着他，
			# 保留座位并标记掉线；他回来时凭身份认领回同一个座位（选角能接着选，对局接着打）
			(room["conn_of"] as Dictionary).erase(pid)
			battle.set_offline(pid, true)
			# 选角期间掉线：其余人都提交完就直接收尾，别让大家干等满 30 秒
			_on_pick_player_left(room, pid)
			print("[座位] 玩家 %d 对局中离席：座位与身份保留（身份=%s）" % [
				pid, str((room["client_of"] as Dictionary).get(pid, ""))])
		else:
			# 准备室：座位与身份绑定一并清除（未开局离席即放弃这个座位，回来按新玩家重新落座）
			_释放座位(room, pid)
			print("[座位] 玩家 %d 准备室离席：座位与身份一并清除" % pid)
	_离房清会话(s)
	_同步观战者名单(room)
	# 房间内已无在线玩家、也没有观战者：对局无从继续也无人在看，直接销毁房间
	if (room["conn_of"] as Dictionary).is_empty() and (room["watchers"] as Array).is_empty():
		_解绑房间(room)
		_rooms.erase(int(room["id"]))
		rooms_changed.emit()
	else:
		_broadcast_game(room)
		rooms_changed.emit()


## 房主主动离开：整间解散 —— 房主一走，这间房就没人接着开了（客户端各自回大厅）。
## 对局中被强拆时额外公告一句，让房里的人知道不是自己的问题。
func _房主离开(room: Dictionary) -> void:
	if _is_battle_playing(room):
		_broadcast_raw(room, GConst.Msg.Gossip, {
			"type": GConst.GossipType.Notice,
			"txt": "房主已离开，本局被迫结束",
			"id": 0,
		})
	_解散房间(room)


## 解散房间：把还留在房里的人（座位玩家 + 观战者）统统请回大厅，然后销毁房间。
## 用在哪：① 房主主动退房（见 leave_room / _房主离开）；② 一局打完（见 poll）。
## 主动退房那位不进这个循环：他的座位与连接在 leave_room 里已经摘掉，房间正是他这次退房拆掉的，
## 不该再回他一句「房间不存在」（见 leave_room 的房主分支）。
func _解散房间(room: Dictionary) -> void:
	for cid: int in _房间接收者(room):
		var s: Dictionary = _sessions.get(cid, {})
		if not s.is_empty():
			_离房清会话(s)
		# 房间已不存在：客户端据此清掉房间上下文、回大厅（见 client_logic 对 GE_INVALID_TABLEID 的处理）
		server.send(cid, GConst.Msg.Error, {"id": GConst.GE_INVALID_TABLEID, "dst_id": cid, "args": []})
	_解绑房间(room)
	_rooms.erase(int(room["id"]))
	rooms_changed.emit()


## 离开房间（或房间被解散）时清掉会话里的房间上下文：房间号 / 座位号，以及心跳状态。
## 心跳状态也要清：不清的话它会在下一次进房时被当成「等了很久都没回音」而立刻判掉线
## （见 _推心跳）；顺带也让重新进房时延迟重新测（先显示「测量中」）
func _离房清会话(s: Dictionary) -> void:
	s["room_id"] = -1
	s["player_id"] = -1
	s["ping_sent_ms"] = 0
	s["ping_last_ms"] = 0
	s["ping_since_ms"] = 0
	s["ping_ms"] = GConst.PING_未测


func _解绑房间(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	battle.send_cb = Callable()
	for 玩家: BattlePlayer in battle.players.values():
		玩家.解绑()
	battle.players.clear()
	battle.order.clear()
	battle._states.clear()
	battle._进度表.clear()


## 断线重连认领座位：找出本房间内属于该连接身份的座位（无则 -1）。
## 只按身份判 —— 座位表里的身份是唯一的，同身份就是同一个人，他那个座位就该还给他。
## 注意：身份由客户端自报、服务端不校验（本作不防改包）。局域网模式下的身份就是昵称，
## 所以同机多开测试时重名会互相认领座位、甚至把对方踢掉（见 _踢掉占座连接）——
## 那是调试用的测试模式，正常玩家走 Steam（身份是 SteamID，撞不上）。
## 房间列表的「可重连」也用它，所以这里必须是纯查询，不能顺手去踢连接（踢连接见 _踢掉占座连接）。
func _reclaim_seat(room: Dictionary, conn_id: int) -> int:
	var client_id: String = str(_sessions.get(conn_id, {}).get("client_id", ""))
	if client_id == "":
		return -1
	for pid: Variant in (room["client_of"] as Dictionary).keys():
		if str(room["client_of"][pid]) == client_id:
			return int(pid)
	return -1


## 座位还占在一条旧连接上时（掉线刚回来、旧连接还没被判掉线的那个窗口）把它踢掉。
## 必须先清旧连接的会话再断开它 —— 顺序不能反：直接断开会连锁触发 leave_room，
## 而那时座位已经归新连接了，leave_room 会按旧会话的座位号把新连接的座位一起删掉。
## 只有身份对得上才会走到这里，所以踢掉的确实是「同一个人那半死不活的旧连接」。
func _踢掉占座连接(room: Dictionary, pid: int, conn_id: int) -> void:
	var 占座: int = int((room["conn_of"] as Dictionary).get(pid, -1))
	if 占座 < 0 or 占座 == conn_id:
		return
	var s: Dictionary = _sessions.get(占座, {})
	if not s.is_empty():
		_离房清会话(s)
	print("[座位] 抢占座位 %d：踢掉还占着它的旧连接 %d" % [pid, 占座])
	server.close_conn(占座)


func join_team(conn_id: int, team: int) -> void:
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty():
		return
	# 开局后、以及选角开始后，队伍与座位就定死了（选角界面的座位条按它画），不再接受改边
	if bool(room["started"]) or room.has("pick"):
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
	# 选边可能刚好把两队调平：若已满员且全员都准备着，这一刻就该开始倒数（_try_start 会广播）
	_try_start(room)


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
	print("[房间] 玩家%d %s（房间 %d）" % [pid, "已准备" if 新值 else "取消准备", int(room["id"])])
	# 广播 + 开局判定都交给 _try_start（它末尾必定广播一次）
	_try_start(room)


## 开局倒计时时长（毫秒）：本地调试（F9~F11 多开脚本 / --auto）下取 0 —— 准备齐了下一拍立刻开局，
## 省掉等待、方便快速测试；正常联机仍倒数 默认开局倒计时_ms 再开局，给玩家一点反应时间
func _开局倒计时毫秒() -> int:
	return 0 if Cfg.本地模式 else 默认开局倒计时_ms


## 默认开局倒计时时长：条件齐备后先倒数 5 秒再开局（给玩家一点反应时间）
const 默认开局倒计时_ms: int = 5000


## 开局条件是否齐备：未开始、未进选角、满员、全员准备、两队人数对等。
## 注意它不只是判断 —— 会先把没选边的人补到人少的一边（balance_colors），
## 所以「人数是否对等」必须在补位之后才算得准。
func _开局齐备(room: Dictionary) -> bool:
	if bool(room["started"]) or room.has("pick"):
		# 已经开了 / 选角进行中（等各玩家提交）
		return false
	var battle: BattleEngine = room["battle"]
	if not battle.all_ready():
		return false
	if battle.order.size() != int(room["max_player"]):
		# 人数没坐满不开局：房间设定几人就得几人（2V2 必须凑齐 4 人），
		# 否则 2V2 的房间里两个人都准备了也会直接开成 1v1
		return false
	battle.balance_colors()
	# 手动选边不受人数约束，补位也补不平时会剩 3 红 1 蓝 / 4 红 0 蓝 —— 这种不对等的局不开
	return battle.is_team_balanced()


## 尝试起开局倒计时。由「准备」与「选边」两条上行共用 ——
## 队伍刚被调平的那一刻也要能立刻开始倒数；条件被打断则撤销倒计时。
## 末尾无条件广播一次：补位可能刚改了队伍色，客户端要据此显示「人数不对等」提示。
func _try_start(room: Dictionary) -> void:
	var battle: BattleEngine = room["battle"]
	if _开局齐备(room):
		# 还没开始倒数就起一个倒计时；已经在倒数就别重置时间
		if int(room.get("start_at", 0)) <= 0:
			var 倒计时: int = _开局倒计时毫秒()
			room["start_at"] = Time.get_ticks_msec() + 倒计时
			room["start_shown_sec"] = ceili(倒计时 / 1000.0)
			battle.start_countdown_ms = 倒计时
	else:
		room["start_at"] = 0
		room["start_shown_sec"] = -1
		battle.start_countdown_ms = 0
	_broadcast_game(room)


## 撤销开局倒计时（条件被打断时调）：清掉截止时间并广播一次，让客户端收起提示
func _取消开局倒计时(room: Dictionary) -> void:
	if int(room.get("start_at", 0)) <= 0:
		return
	room["start_at"] = 0
	room["start_shown_sec"] = -1
	var battle: BattleEngine = room["battle"]
	battle.start_countdown_ms = 0
	_broadcast_game(room)


## 推进开局倒计时（poll 中调用）：条件被打断就撤销，秒数变了才广播，到点真正开局
func _check_start_countdown(room: Dictionary) -> void:
	var 截止: int = int(room.get("start_at", 0))
	if 截止 <= 0:
		return
	if not _开局齐备(room):
		_取消开局倒计时(room)
		return
	var 剩余: int = 截止 - Time.get_ticks_msec()
	var battle: BattleEngine = room["battle"]
	if 剩余 <= 0:
		room["start_at"] = 0
		room["start_shown_sec"] = -1
		battle.start_countdown_ms = 0
		_开始本局(room, battle)
		return
	battle.start_countdown_ms = 剩余
	# 只在「显示的秒数」变化时广播：poll 每帧都跑，不拦的话一秒能发几十份全量快照
	var 秒: int = ceili(剩余 / 1000.0)
	if 秒 != int(room.get("start_shown_sec", -1)):
		room["start_shown_sec"] = 秒
		_broadcast_game(room)


## 真正开局：先排座（间隔 / 乱序），再按选角策略直接开局或进选角
func _开始本局(room: Dictionary, battle: BattleEngine) -> void:
	# 排座在定完队之后、进选角之前做，且整局只做一次：选角界面顶部的座位条才和实际座位一致
	battle.arrange_seats()
	if int(room["role_strategy"]) == GConst.RoleStrategy.Random:
		# Random 策略保持原样：不发询问、直接随机分配（自动测试依赖这条零交互路径）
		room["started"] = true
		battle.start(Data.role_pool.duplicate())
		rooms_changed.emit()
		return
	# 进选角前先广播一次：让选角界面带上刚定下的队伍色与座位顺序
	_broadcast_game(room)
	_begin_role_pick(room)


func _talk(conn_id: int, txt: String) -> void:
	# 长度按服务端上限截断：这段文本会广播给房内所有人，客户端输入框的限制挡不住改包
	txt = txt.left(聊天最大字符数)
	if txt.strip_edges() == "":
		return
	var room: Dictionary = _room_of(conn_id)
	if room.is_empty():
		return
	# 发言者的显示名由服务端拼好，格式统一「昵称[补充]」：
	#   · 座位玩家 —— 补充是角色名（准备室里还没选到角色就不带方括号）；
	#   · 观战者 —— 补充是「观战」。
	# 为什么不让客户端自己拼：观战者不在玩家表里，客户端拿 id 反查不到人（原来会显示成「9：…」）
	var s: Dictionary = _sessions[conn_id]
	var pid: int = int(s["player_id"])
	var 昵称: String = str(s["nickname"])
	var 补充: String = "观战"
	if pid != GConst.GUEST:
		var 玩家: BattlePlayer = (room["battle"] as BattleEngine).players.get(pid)
		补充 = Data.role_name(玩家.role_id) if 玩家 != null and 玩家.role_id > 0 else ""
	_broadcast_raw(room, GConst.Msg.Gossip, {
		"type": GConst.GossipType.Talk,
		"txt": txt,
		"id": pid,
		"name": 昵称 if 补充 == "" else "%s[%s]" % [昵称, 补充],
	})


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
		_发选角请求(room, pid, 候选表[pid], PICK_TIMEOUT_MS)
	_broadcast_game(room)


## 下发选角请求（候选 + 剩余倒计时）：开局时每人发一次；选角中途重新进房的人补发一次
func _发选角请求(room: Dictionary, pid: int, 候选: Array, 剩余_ms: int, 已选角色: int = 0) -> void:
	_engine_send(int(room["id"]), pid, GConst.Msg.RoleReq, {
		"id": pid,
		"strategy": int(room["role_strategy"]),
		"role_ids": 候选,
		# 选角倒计时：客户端据此画进度条（本地扩展字段，见 proto_schema 的 RoleReq）
		"wait_ms": 剩余_ms,
		"wait_total_ms": PICK_TIMEOUT_MS,
		# 非 0 = 这个人已经选过了：客户端据此直接进「已选好、等其他人」那一层
		"picked_role": 已选角色,
		"args": [],
		"opration": 0,
	})


## 选角阶段重新进房：把该玩家的选角请求再发一次（带他的候选、剩余倒计时，以及已选好的角色）。
## 已经提交过的也要发 —— 客户端要靠它弹回「已选好、等其他人」那一层，否则重连回来只剩准备室，
## 看不出自己已经选过（就是「离开再回来没回到已选择角色的等待界面」那个 bug）
func _补发选角请求(room: Dictionary, pid: int) -> void:
	if not room.has("pick"):
		return
	var pick: Dictionary = room["pick"]
	var 候选表: Dictionary = pick["candidates"]
	if not 候选表.has(pid):
		return
	var 已选角色: int = int((pick["picked"] as Dictionary).get(pid, 0))
	_发选角请求(room, pid, 候选表[pid],
		maxi(int(pick["deadline"]) - Time.get_ticks_msec(), 0), 已选角色)


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


## 31/Any 是否所有「还在线」的在房玩家都已提交。
## 掉线的先跳过（座位留着他回来接着选）：只要在线的都提交了就直接收尾，掉线那位由
## _分配角色 随机兜底 —— 否则一个人掉线，其余人都得干等满 30 秒。
func _pick_candidates_done(room: Dictionary) -> bool:
	var battle: BattleEngine = room["battle"]
	var 已选: Dictionary = room["pick"]["picked"]
	for pid: int in battle.order:
		if battle.offline_players.has(pid):
			continue
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
		# 人不够（选角期间走光了）：取消选角并广播一次，别让还留着的人停在「等待选角」那一层
		room.erase("pick")
		battle.room_picking = false
		_broadcast_game(room)
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
## 判定掉线的静默时长（毫秒）：连续这么久没收到回声就断开这条连接（只对 Steam 底座用）
const 掉线超时_ms: int = 16000


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
	# 房主座位号跟着快照下发（客户端「玩家列表」据此给房主标星号）：
	# 由 host_conn 反查一次（见 _房主座位），不在别处再维护一份冗余状态
	battle.host_seat = _房主座位(room)
	for pid: int in (room["conn_of"] as Dictionary).keys():
		var cid: int = int((room["conn_of"] as Dictionary)[pid])
		server.send(cid, GConst.Msg.Game, battle.game_info(pid))
	# 观战者看的是观战视角（player_id = GUEST），所有人共用同一份快照
	_请求观战快照(room)
	_同步大厅数据(room)


## Steam 模式：房主把自己房间的实况写进 Steam 大厅数据，别人在房间列表上就能看到人数与状态，
## 加入方也靠其中的「房间号」发进房请求（Steam 大厅号与服务端房间号是两回事）。
## 本地调试 / 局域网模式不碰 Steam，直接返回。
## 这里做两件事控制写入量（对局快照每次刷新都会走到这里，而 Steam 对大厅数据更新有限流）：
##   ① 内容没变就不写；② 变得太密先攒着，由 _推大厅数据 到点补写（最后一次变化一定送得出去）。
func _同步大厅数据(room: Dictionary) -> void:
	if Cfg.无Steam():
		return
	var battle: BattleEngine = room["battle"]
	# 「留了座位的身份」= 本房每个座位记着的身份（对局中离席/掉线的座位也还在表里），
	# 写进大厅数据供加入方判断「这间还留着我的座位」（Steam 模式下房间列表只能靠这份共享数据）
	var 留座身份: PackedStringArray = PackedStringArray()
	for 身份: Variant in (room["client_of"] as Dictionary).values():
		留座身份.append(str(身份))
	var 房间号: int = int(room["id"])
	var 在线人数: int = _统计在线人数(battle)
	var 座位数: int = battle.order.size()
	var 观战人数: int = (room["watchers"] as Array).size()
	var 进行中: bool = bool(room["started"])
	var 数据: String = "%d|%d|%d|%d|%s|%s" % [房间号, 在线人数, 座位数, 观战人数,
		"1" if 进行中 else "0", ",".join(留座身份)]
	# 内容一样、而且写的还是同一个大厅 → 不用写。
	# 大厅号也要比：Steam 掉线重连会新建一个空大厅，内容虽然一样也得重写一遍
	if 数据 == _大厅已写数据 and SteamNet.大厅id == _大厅已写大厅id:
		# 又变回「已经写出去的那个状态」了：欠着的那份已经过期，撤销（否则会把过时数据补写出去）
		_大厅待写.clear()
		return
	_大厅待写 = {
		"数据": 数据,
		"房间号": 房间号,
		"在线人数": 在线人数,
		"座位数": 座位数,
		"观战人数": 观战人数,
		"进行中": 进行中,
		"留座身份": 留座身份,
	}
	_推大厅数据()


## 把攒着的大厅数据写到 Steam（到写入间隔才真写）。由 poll 每帧调用
func _推大厅数据() -> void:
	if _大厅待写.is_empty():
		return
	# 房间已经没了（解散 / 退房）：这份数据作废。
	# 必须清掉：留着的话它会一直往回写「本房房间号」，Steam 掉线重连时就会照着一个
	# 已经不存在的房号把大厅重新开出来（见 SteamNet._重开大厅）
	if not _rooms.has(int(_大厅待写["房间号"])):
		_大厅待写.clear()
		return
	var 现在: int = Time.get_ticks_msec()
	if 现在 - _大厅写入时刻_ms < 大厅写入间隔_ms:
		return
	var 身份: PackedStringArray = _大厅待写["留座身份"]
	if not SteamNet.同步房间数据(
		int(_大厅待写["房间号"]),
		int(_大厅待写["在线人数"]),
		int(_大厅待写["座位数"]),
		int(_大厅待写["观战人数"]),
		bool(_大厅待写["进行中"]),
		身份
	):
		# 大厅还没建好（建房是异步的）：留着这份，等大厅建好后的下一拍再写
		return
	_大厅写入时刻_ms = 现在
	_大厅已写数据 = str(_大厅待写["数据"])
	_大厅已写大厅id = SteamNet.大厅id
	_大厅待写.clear()


func _room_of(conn_id: int) -> Dictionary:
	var s: Dictionary = _sessions.get(conn_id, {})
	if s.is_empty():
		return {}
	var rid: int = int(s.get("room_id", -1))
	if rid < 0 or not _rooms.has(rid):
		return {}
	return _rooms[rid]

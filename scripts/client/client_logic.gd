extends Node
## 客户端逻辑（autoload 名：Logic）
## 对照客户端 logic/Logic.cpp：把服务端下发的消息分派给界面，并把界面操作转成上行消息。

signal room_list_changed(rooms: Array)
signal error_received(err_id: int, msg: String)
signal gossip_received(txt: String)
## 系统公告（超时 / 掉线 / 重连 / 终局等）：界面只把它写进日志，不进聊天区。
## kind = GConst.GossipType，界面按它给这行日志上色
signal notice_received(txt: String, kind: int)
## 治疗事件（目标 id + 本次治疗点数）：战斗界面据此在目标头像上喷「+」特效
signal heal_received(pid: int, num: int)
## 弃牌事件（弃牌者 id + 弃牌张数）：战斗界面据此在他身上播「牌向下飞出并淡出」的弃牌特效
signal discard_received(pid: int, num: int)
signal game_info_updated(info: Dictionary)
signal command_received(data: Dictionary)
signal turn_changed(player_id: int, round_id: int)
signal hit_received(src_id: int, dst_id: int, hit: int)
signal card_shown(msg: Dictionary)
signal hurt_received(msg: Dictionary)
## 受伤飘字：本次伤害点数（含各类加成，尚未经治疗抵挡/抵御扣减）（dst_id、点数、伤害类型）
signal hurt_float_received(dst_id: int, point: int, harm_type: int)
signal skill_received(msg: Dictionary)
signal role_pick_required(data: Dictionary)
signal role_pick_submitted(strategy: int, role_ids: Array)
## 服务端驳回当前操作（ErrorInput）：战斗界面据此恢复待选并提示，不再靠反向持有界面引用来回调
signal invalid_input_received(data: Dictionary)

## 服务端心跳静默多久就认定这条连接废了（毫秒）。服务端在房内每 2 秒发一次心跳
## （见 LocalServer._推心跳），这里取 6 秒 = 连着 3 次都没到。
## 为什么需要：Steam P2P 没有「底层断连事件」，房主进程被杀 / 崩掉时本机收不到任何通知，
## 界面会一直卡在房间里、点什么都没反应；局域网 TCP 底座本来就能立刻发现，这条只是兜底。
## 判到之后走的是「断开 → 自动重连」这条路：房主只是卡了一下就能自己连回来，
## 房主真没了则重连失败，提示「重连失败，即将返回大厅」（见 _on_reconnect_failed）
const 心跳静默超时_ms: int = 6000

## 最近一次收到服务端消息的时刻（毫秒）；0 = 还没收到过
var _服务端消息_ms: int = 0

var lobby: Node = null
var my_player_id: int = -1
var in_room: bool = false
var started: bool = false
## 本局是否已经打完（终局快照里的 over）：打完房间随即被房主解散，
## 客户端据此留在结算界面把结果看完，而不是被踢回大厅
var 对局已结束: bool = false
var last_info: Dictionary = {}
var last_role_req: Dictionary = {}
## 当前所在房间 id；-1 表示不在任何房间（断线重连时据此自动回到原房间）
var current_room_id: int = -1
## 是否成功连上过房主（用于区分「首次连接」与「断线重连」）
var _ever_connected: bool = false
## 这条连接掉过线（收到过 disconnected）：只有掉过线之后重新连上才算「重连」，
## 主动换一台房主连不算（见 _on_connected / _on_disconnected）
var _断过线: bool = false
## 重连后已重发登录、正在等待回到原房间（收到 Game 视为成功，收到房间不存在错误视为失败）
var _pending_reenter: bool = false
## Steam 模式：正在加入的 Steam 大厅号（加入结果由 SteamNet.进房结果 回调，见 _on_steam_join）
var _待进房号: int = -1
## Steam 模式：已经发过进房请求、但还没收到对局快照（存「要发给房主的服务端房间号」）。
## 登录回执到达时补发一次：第一条进房请求可能与登录一起丢在「通道还没建好」的那一刻
## （见 SteamClient 的连接判定），不补发的话人会一直停在「正在进入房间…」。收到快照即清空
var _待重发进房号: int = -1
## 上一次「消息发送失败」提示的时刻（毫秒）：同一条提示 1 秒内只报一次（见 _on_send_failed）
var _上次发送失败_ms: int = 0
## 刚退房后的「丢快照」窗口（毫秒时刻，0 = 不在窗口里）：退房请求是异步送出的，在它到达服务端之前，
## 旧房主可能已经广播过一包含我的对局快照；那包不能当成「我回房了」（见 _on_game）。
## 玩家一有新的建房 / 进房动作就立刻关掉这个窗口（见 create_room / enter_room）
var _退房后忽略快照至_ms: int = 0


func _ready() -> void:
	Net.message_received.connect(_on_message)
	Net.disconnected.connect(_on_disconnected)
	Net.connected.connect(_on_connected)
	Net.reconnect_failed.connect(_on_reconnect_failed)
	Net.send_failed.connect(_on_send_failed)
	SteamNet.进房结果.connect(_on_steam_join)
	Data.nick_name = Cfg.nickname


## 有一条上行消息没发出去（连接断了 / 对端还没确认）：必须在画面上说一声，
## 否则玩家只看到「点了没反应」。同一条提示 1 秒内只报一次（一次点击可能连带发好几条消息）
func _on_send_failed(_msg_type: int) -> void:
	var 现在: int = Time.get_ticks_msec()
	if 现在 - _上次发送失败_ms < 1000:
		return
	_上次发送失败_ms = 现在
	notice_received.emit("消息发送失败：与房主的连接已断开", GConst.GossipType.Warn)


## 房内心跳静默检测（见 心跳静默超时_ms）：判到就当断线，走「断开 → 自动重连」这条路
func _process(_delta: float) -> void:
	if not in_room or _服务端消息_ms <= 0:
		return
	if Time.get_ticks_msec() - _服务端消息_ms <= 心跳静默超时_ms:
		return
	_服务端消息_ms = 0     # 先清零，免得每帧重复触发；下次收到消息会重新开始计时
	Net.client.标记断开()


# ============================================================
# 收包分派
# ============================================================
func _on_message(msg_type: int, data: Dictionary) -> void:
	# 收到任何服务端消息都算「它还活着」：上面的心跳静默检测据此判断连接是不是已经废了
	_服务端消息_ms = Time.get_ticks_msec()
	match msg_type:
		GConst.Msg.RoomListRep:
			room_list_changed.emit(data.get("rooms", []))
		GConst.Msg.Game:
			_on_game(data)
		GConst.Msg.CmdReq:
			command_received.emit(data)
		GConst.Msg.Error:
			var err_id: int = int(data.get("id", 0))
			error_received.emit(err_id, _error_text(err_id))
			# 房间不存在：房主离开 / 一局打完被解散送出来，或只是在列表里点了间已经没了的房。
			# 还在房间里（in_room / 正等重连回房）说明是被解散送走的 → 回大厅；
			# 只是点了陈旧房间的（本来就不在房里）交给界面的错误提示即可。
			# 延后一帧再切：这一包可能来自服务端处理我们上行请求的调用栈里，
			# 当场切界面会连带 Net.回到待机() 去拆正在跑的服务端
			if err_id == GConst.GE_INVALID_TABLEID and (_pending_reenter or in_room):
				# 一局打完、房主随即解散了房间：人留在结算界面把结果看完（只清房间上下文，
				# 他点「返回大厅」自然会回）；其余情况（房主离开等）回大厅并提示
				if 对局已结束:
					leave_room.call_deferred()
				else:
					_give_up_reconnect.call_deferred("房间已解散，即将返回大厅")
		GConst.Msg.Gossip:
			if int(data.get("type", 0)) == GConst.GossipType.Talk:
				# 聊天：显示名由服务端拼好（「昵称[角色名]」/「昵称[观战]」，见 LocalServer._talk）。
				# 不能像以前那样拿 id 去玩家表反查 —— 观战者不在表里，会显示成「9：…」
				gossip_received.emit("%s：%s" % [str(data.get("name", "")), str(data.get("txt", ""))])
			else:
				var kind: int = int(data.get("type", GConst.GossipType.Notice))
				# 治疗日志额外发一条事件给战斗界面播「+」特效（日志本身照常走 notice_received）
				if kind == GConst.GossipType.Heal:
					heal_received.emit(int(data.get("id", -1)), int(data.get("num", 0)))
				# 弃牌日志额外发一条事件给战斗界面播弃牌特效（num = 弃牌张数，其余 Discard 类日志不带）
				elif kind == GConst.GossipType.Discard and int(data.get("num", 0)) > 0:
					discard_received.emit(int(data.get("id", -1)), int(data.get("num", 0)))
				notice_received.emit(str(data.get("txt", "")), kind)
		GConst.Msg.HeartBeat:
			# 服务端心跳：原样回一声，服务端按「发包时刻 → 收到回声」算这一路的往返延迟
			Net.send(GConst.Msg.HeartBeat, {})
		GConst.Msg.TurnBegin:
			turn_changed.emit(int(data.get("id", -1)), int(data.get("round", 0)))
		GConst.Msg.Hit:
			hit_received.emit(int(data.get("src_id", 0)), int(data.get("dst_id", 0)), int(data.get("hit", 0)))
		GConst.Msg.Card:
			card_shown.emit(data)
		GConst.Msg.Hurt:
			hurt_received.emit(data)
		GConst.Msg.HurtFloat:
			hurt_float_received.emit(int(data.get("dst_id", -1)), int(data.get("point", 0)),
				int(data.get("type", 0)))
		GConst.Msg.Skill:
			skill_received.emit(data)
		GConst.Msg.RoleReq:
			_on_role_req(data)
		GConst.Msg.LoginRep:
			_on_login_rep()
		GConst.Msg.ErrorInput:
			gossip_received.emit("操作无效，请重新选择")
			invalid_input_received.emit(data)


func _on_game(data: Dictionary) -> void:
	# 刚退房的一小段窗口里丢掉快照：那多半是旧房主在我那条退房请求到达之前发出的在途包，
	# 拿它当「我回房了」会把人拽回刚退的房间（见 leave_room）
	if Time.get_ticks_msec() < _退房后忽略快照至_ms:
		return
	last_info = data
	# Game 是对局内权威快照：收到即代表已身处房间，记录房间上下文并结束重连等待。
	# Steam 模式下的房间上下文用 Steam 大厅号（进房请求要的服务端房间号另存于 SteamNet.房主房间号）。
	# 建房时「对局广播」会比「大厅创建回调」先到（见 SteamNet.本房房间号），那一刻大厅号还是 0 ——
	# 0 是「不在任何大厅」的哨兵、不是房号，别拿它当房间上下文（否则重连会照着它去进 0 号房）
	if Cfg.无Steam():
		current_room_id = int(data.get("room_id", current_room_id))
	elif SteamNet.大厅id != 0:
		current_room_id = SteamNet.大厅id
	else:
		# 不在任何 Steam 大厅却收到了快照（正常路径不会发生：进房总是先加了大厅的）：
		# 退回服务端房间号，至少给重连留一个可用的房间上下文
		current_room_id = int(data.get("room_id", current_room_id))
	_pending_reenter = false
	_待重发进房号 = -1     # 已经进了房：那条进房请求不必再补发了
	my_player_id = int(data.get("player_id", -1))
	Data.id = my_player_id
	Data.nick_name = Cfg.nickname
	Data.build_player_list(data)
	Data.apply_team_info(data)
	started = bool(data.get("is_started", false))
	对局已结束 = bool(data.get("over", false))
	if started:
		# 士气上限随快照下发（跟人数走：4 / 6 人局 15、8 人局 18，见 BattleEngine.士气上限）
		Data.init_team(int(data.get("morale_max", GConst.MORALE_DEFAULT)))
	in_room = true
	# 首条对局信息 → 交给 UI 管理器切到「房间准备室 / 战斗界面」
	UI.确保对局界面(started)
	game_info_updated.emit(data)


func _on_disconnected() -> void:
	# 界面保持原状（对局不立刻清空），等待自动重连；恢复后由 Game 消息刷新
	_断过线 = true
	gossip_received.emit("与房主的连接已断开，正在重连…")


## 连接建立：首次连接由界面继续后续流程；断线后的重连则自动回到原房间。
## 判据是「之前掉过线」（_断过线）：主动连一台新房主（刚点进房 / 迁移后跟去新主机）也会走到
## 这里，那种情况不能当重连 —— 否则会在刚进房时弹「已重新连接」并把进房请求重复发一遍。
func _on_connected() -> void:
	if not _ever_connected:
		_ever_connected = true
		_断过线 = false
		return
	var 是重连: bool = _断过线
	_断过线 = false
	if not 是重连 or current_room_id < 0:
		return
	# 准备室阶段不留座（退出就是退出）：掉线不留座位，直接回大厅，想继续就自己重新进房 ——
	# 不自动塞回原房间。与服务端 LocalServer._留座阶段 同一套规则。
	# 延后一帧再切界面：这条回调来自客户端 poll，当场 leave_room → 回到待机 会去拆正在跑的连接
	if not _留座阶段():
		_give_up_reconnect.call_deferred("准备阶段掉线不留座，即将返回大厅")
		return
	# 每次连接 Net 都会重发 LoginReq（见 net_manager），登录回执到达后再进房
	_pending_reenter = true
	notice_received.emit("已重新连接，正在回到房间…", GConst.GossipType.Notice)


## 本局是否已经进入「留座」阶段：选角开始之后（选角中 / 对局中都要留座）。
## 判据取自最后一份对局快照（准备室 = 未开局且不在选角），与服务端那边是同一套规则
## （见 LocalServer._留座阶段）：准备室不留座，所以重连后也不自动回房。
func _留座阶段() -> bool:
	return started or bool(last_info.get("picking", false))


## 登录回执：重连场合下紧接着重新进房（服务端对每条连接都会回一条 LoginRep）
func _on_login_rep() -> void:
	# 登录刚（又一次）到达：说明通道现在通了 —— 上一条进房请求可能丢在通道没通的那一刻，补发一次。
	# 补发是幂等的：人已经在房里时服务端只补一份快照，不会再进一次房
	if _待重发进房号 >= 0:
		Net.send(GConst.Msg.EnterRoomReq, {"room_id": _待重发进房号})
	if not _pending_reenter:
		return
	enter_room(current_room_id)


## 连续重连失败：提示玩家并返回大厅
func _on_reconnect_failed() -> void:
	if not _ever_connected:
		# 一次都没连上（地址不可达 / 房主没开服务端 / 连接超时）：也要说一声，
		# 否则玩家一直停在「正在进入房间」，看不出发生了什么
		gossip_received.emit("连接房主失败，请确认对方还在，或重新搜索房间")
		return
	_give_up_reconnect("重连失败，即将返回大厅")


## 重连无法完成（连续失败）/ 房间已被解散 / 准备阶段掉线不留座：清空房间上下文、回大厅并提示玩家。
## 直接复用 leave_room()：它会把 Steam 大厅一并退掉（不退的话列表里会留一个别人点进来
## 却进不去的幽灵房间），并按模式把待机状态摆回来（大厅正是靠那条连接才能建房 / 进房）
func _give_up_reconnect(txt: String) -> void:
	leave_room()
	# 先切回大厅再提示：旧界面随即被替换，提示才会落到新大厅上
	UI.goto_lobby()
	notice_received.emit(txt, GConst.GossipType.Warn)


# ============================================================
# 选将（RoleReq 下发 → 弹层 → PickBan 上行）
# ============================================================
func _on_role_req(data: Dictionary) -> void:
	last_role_req = data
	# 界面（UI 管理器）订阅本信号自行弹出选将层，Logic 不再直接操作界面
	role_pick_required.emit(data)


# ============================================================
# 上行操作
# ============================================================
func request_room_list() -> void:
	# Steam 模式：房间列表 = Steam 大厅列表（这时还没连上任何房主，走不了下面那条请求）
	if not Cfg.无Steam():
		SteamNet.查询大厅()
		return
	# 局域网联机还没连上房主时列表由「发现的主机」充当（见 lobby.gd），这里无请求可发
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.RoomListReq, {"role_strategy": GConst.RoleStrategy.All})


func create_room(room_name: String, max_player: int, role_strategy: int = GConst.RoleStrategy.Random, seat_mode: int = GConst.SeatMode.Random, debug: bool = false) -> void:
	# 玩家明确在建房了：退房后的「丢快照」窗口提前关掉，新房子的快照要收
	_退房后忽略快照至_ms = 0
	# 什么时候先补「大厅待机」：
	#   ·Steam：本机没在当房主（刚退房待机还没摆回来、或连接正指着别人的服务端）—— 建房必须建在
	#     自己那台服务端里，否则房会开在别人的进程里，那人一走房就没了；
	#   ·本地调试 / 局域网：连接没建立（局域网模式的待机本来就是「什么都不连」，建房由 lobby 自己开房）。
	# 补不上必须把原因写进状态栏 —— 不能静默 return：建房界面的状态栏会永远停在
	# 「正在创建房间…」，玩家只能对着它干等
	if (not Cfg.无Steam() and not Net.hosting) or not Net.is_connected_to_host():
		var 补不上原因: String = await _补齐待机连接()
		if 补不上原因 != "":
			gossip_received.emit("%s，无法创建房间" % 补不上原因)
			return
	# Steam 模式：本地照旧建服务端房间，另外开一个 Steam 大厅，别的玩家才搜得到
	# （选角 / 座位 / 作弊也写进大厅数据，房间列表要显示）
	# 同时向局域网广播本机有房：同一网段里没登 Steam 的机器也能搜到并连进来（见 MultiServer）
	if not Cfg.无Steam():
		SteamNet.建房(room_name, max_player, role_strategy, seat_mode, debug)
		Net.开始局域网广播()
	Net.send(GConst.Msg.CreateRoomReq, {
		"room_name": room_name,
		"max_player": max_player,
		"role_strategy": role_strategy,
		"seat_mode": seat_mode,
		"allow_guest": true,
		"debug": debug,
	})


## 补齐「大厅待机」那条连接（已经连着就不会走到这里）：建房 / 进房都得先有自己那台服务端，
## 才发得出请求。返回失败原因（调用方拼提示用），补上了返回空串。
func _补齐待机连接() -> String:
	# 局域网模式的待机本来就是「什么都不连」（列表列的是搜到的主机），补不了也不该补
	if Cfg.局域网模式:
		return "与房主的连接已断开"
	# Steam 还没连上时也补不了待机（自建服务端要用本机 SteamID 连自己）
	if not Cfg.无Steam() and not SteamNet.就绪:
		return "未连接 Steam 网络"
	Net.回到待机()
	# 最多等 6 秒（与客户端「首次连接总时限」一致；Steam 模式下自连很快）
	var 截止: int = Time.get_ticks_msec() + 6000
	while not Net.is_connected_to_host() and Time.get_ticks_msec() < 截止:
		await get_tree().create_timer(0.1).timeout
	if not Net.is_connected_to_host():
		return "与房主的连接已断开"
	return ""


## 选将结果上行：role_ids 里是自己选中的角色
func send_pick(strategy: int, role_ids: Array) -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.PickBan, {
		"strategy": strategy,
		"role_ids": role_ids,
	})
	role_pick_submitted.emit(strategy, role_ids)


func enter_room(room_id: int) -> void:
	# 玩家明确在进房了：退房后的「丢快照」窗口提前关掉，新房间的快照要收
	_退房后忽略快照至_ms = 0
	# Steam 模式：列表里的 room_id 是 Steam 大厅号。第一次进要先把 P2P 连接切到房主（见 _on_steam_join）；
	# 断线重连回来时大厅已经在了，连接也是现成的，直接发进房请求即可
	if not Cfg.无Steam():
		# 先把大厅加进去（才能拿到房主 SteamID）；这条路自己会把 P2P 连接切到房主，
		# 所以不要求「现在已经连着」。Steam 本身不可用时进房只会石沉大海，界面又没有任何反馈，先拦一下
		if not SteamNet.就绪:
			gossip_received.emit("未连接 Steam 网络，无法进入房间")
			return
		if SteamNet.大厅id == room_id:
			Net.send(GConst.Msg.EnterRoomReq, {"room_id": SteamNet.房主房间号})
		else:
			_待进房号 = room_id
			SteamNet.进房(room_id)
		return
	if not Net.is_connected_to_host():
		# 同 create_room：本机处于「无连接」的待机状态时进房请求发不出去 ——
		# 先按模式把待机摆回来再发
		var 补不上原因: String = await _补齐待机连接()
		if 补不上原因 != "":
			gossip_received.emit("%s，无法进入房间" % 补不上原因)
			return
	Net.send(GConst.Msg.EnterRoomReq, {"room_id": room_id})


## Steam 模式加入大厅的结果：成功了就把客户端连到房主（地址就是房主 SteamID），再发进房请求。
## 自己开的房不重连 —— 那会把本机房主停掉；本来就连着自己的服务端，直接进房。
func _on_steam_join(成功: bool, 说明: String) -> void:
	# 文案写进大厅状态栏 / 房间聊天：连房主那一段可能要试好几轮，
	# 不写点东西玩家只看到「正在进入房间…」一直不动
	gossip_received.emit(说明)
	if not 成功:
		_待进房号 = -1
		# 正在回原房间的路上却加不进大厅（原大厅已经没了 / 房主换了房）：别再吊在原房间里，
		# 清掉房间上下文回大厅
		if _pending_reenter:
			_give_up_reconnect("无法回到原房间，即将返回大厅")
		return
	var 房号: int = _待进房号
	_待进房号 = -1
	if SteamNet.房主steam_id != SteamNet.steam_id:
		Net.join_game(SteamNet.房主steam_id, 0)
	# 连接建立时 NetManager 会先发登录，两条消息在同一条可靠通道上顺序有保证；
	# 但通道还没建好时两条都可能丢，所以记下这条请求，等登录回执到了再补发一次（见 _on_login_rep）
	Net.send(GConst.Msg.EnterRoomReq, {"room_id": SteamNet.房主房间号})
	_待重发进房号 = SteamNet.房主房间号
	current_room_id = 房号


## 主动离开：清掉 Steam 大厅与待进房状态
func leave_room() -> void:
	if not Cfg.无Steam():
		SteamNet.离开大厅()
		# 房主退房了就别再广播：局域网里那台机器不该继续被搜到
		Net.停止局域网广播()
	_待进房号 = -1
	_待重发进房号 = -1
	if Net.is_connected_to_host():
		Net.send(GConst.Msg.LeaveRoomReq, {})
	# 主动离开即清除房间上下文：之后断线不再尝试回到该房间
	current_room_id = -1
	_pending_reenter = false
	in_room = false
	started = false
	对局已结束 = false
	# 退房后的短窗口里丢掉对局快照（见 _on_game）：退房请求还在路上时，旧房主可能刚发过一包
	# 含我的快照，不能拿它当「我回房了」。玩家一有新的进房 / 建房动作就立刻恢复
	_退房后忽略快照至_ms = Time.get_ticks_msec() + 800
	# 这条连接通的是别人的服务端（我进的是别人的房）：回大厅前先按模式摆回「大厅待机」。
	# 不断开的话，大厅里那条连接还指着别人的服务端 —— 接着点「创建房间」会把建房请求发给别人；
	# 局域网模式还会因为「已连上」而退出主机列表模式，刷新再也搜不到同一网段的其它主机。
	# 但这一步必须**延后一拍**做：退房请求是可靠包，而底座要等下一拍才真的把它发出去
	#（Steam 尤其：RunCallbacks 才 flush）—— 同一帧就 close 会把还没发出去的包一起丢掉，
	# 服务端于是收不到「我退房了」；Steam P2P 又没有底层断连事件，只能等心跳回声超时（十几秒）
	# 才发现，表现就是「我退了，房里的人还看得见我、座位还占着」。见 _摆回待机_延后
	#
	# 备注（已知限制，刻意不处理）：Net.hosting 为真（本机正端着服务端）时不摆回待机 ——
	# 于是本机当过房主之后，大厅列表会一直显示「自己那台服务端里的房间」，
	# 局域网模式下因此搜不到网段里别人的主机，要回登录界面重进才能回到「发现的主机」列表。
	# 局域网模式只用于开发 / 内网联调（正式环境只有 Steam 模式，见 Cfg.局域网模式），所以留着不管。
	if not Net.hosting:
		_摆回待机_延后(Net.target_host, Net.target_port)


## 退房后把「大厅待机」摆回来 —— 延后一拍再做，理由见 leave_room 的注释（退房包要先送出去）。
## 只有这期间玩家一直待在大厅、连接也没换目标时才真的摆：他要是已经又进房 / 又建房（界面已经切走）
## 或者自己连到别的房主上了，那条连接就不该再由这次退房来动。
func _摆回待机_延后(旧目标: String, 旧端口: int) -> void:
	# 半秒：足够底座把退房包真正发出去并送达（Steam 要等下一拍 RunCallbacks 才 flush，再走一趟网络）
	await get_tree().create_timer(0.5).timeout
	if UI.current == null or UI.current.name != "Lobby":
		return
	if Net.hosting:
		return
	if _待进房号 >= 0 or _待重发进房号 >= 0:
		return    # Steam 加大厅是异步的，正在进房就别拆连接
	if Net.target_host != 旧目标 or Net.target_port != 旧端口:
		return    # 已经连到别的房主去了
	Net.回到待机()


## 返回登录界面：退房包要先送出去再断连接（理由同 leave_room），否则房主那边只能等心跳回声超时
##（十几秒）才发现我走了。界面立刻切走（由调用方切），断连接延后半秒；这半秒里玩家要是又点了
##「进入游戏」连上了，就不再按旧计划断。
func 回登录界面() -> void:
	leave_room()
	await get_tree().create_timer(0.5).timeout
	if UI.current == null or UI.current.name != "Enter":
		return    # 已经不在登录界面了（又进大厅了）
	if Net.hosting or Net.is_connected_to_host():
		return    # 又连上了（例如刚点了「进入游戏」）
	Net.idle()


func join_team(team: int) -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.JoinTeamReq, {"team": team})


func set_ready(type: int) -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.ReadyForGameReq, {"type": type})


func talk(txt: String) -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.Talk, {"txt": txt})


## 测试用（战斗界面的测试按键）：kind 见 GConst.DebugKey。
## 服务端按连接认人，所以不用带 player_id。
func debug_key(kind: int) -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.DebugReq, {"kind": kind})


func send_action(action_type: int, action_id: int, dst_ids: Array, card_ids: Array, args: Array) -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.Action, {
		"action_type": action_type,
		"action_id": action_id,
		"src_id": my_player_id,
		"dst_ids": dst_ids,
		"card_ids": card_ids,
		"args": args,
	})


func send_respond(respond_id: int, dst_ids: Array, card_ids: Array, args: Array, partial: bool = false) -> void:
	if not Net.is_connected_to_host():
		return
	var 消息: Dictionary = {
		"respond_id": respond_id,
		"src_id": my_player_id,
		"dst_ids": dst_ids,
		"card_ids": card_ids,
		"args": args,
	}
	# partial = 分步应答：只报「这一步选好的值」（如【剑气斩】弹窗里选好剑气数），
	# 不算本次询问的最终回复；服务端超时兜底时才拿它继续
	if partial:
		消息["partial"] = true
	Net.send(GConst.Msg.Respond, 消息)


# ============================================================
# 错误码文本
# ============================================================
func _error_text(err_id: int) -> String:
	match err_id:
		GConst.GE_INVALID_TABLEID: return "房间不存在"
		GConst.GE_PLAYER_FULL: return "房间已满"
		GConst.GE_NOT_WELCOME: return "该房间不允许游客进入"
		GConst.GE_WRONG_PASSWORD: return "房间密码错误"
		GConst.GE_VIP_ONLY: return "无权限创建该类型房间"
		GConst.GE_DISCONNECTED: return "有玩家掉线"
		GConst.GE_VERSION_PEER_LOW: return "版本号过低，请更新游戏"
		GConst.GE_VERSION_PEER_HIGH: return "对方版本号过低"
		_: return "错误码 %d" % err_id

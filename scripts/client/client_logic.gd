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

## 选将弹层场景（叠在当前界面上，不参与 UI.goto 切换）
const SCENE_ROLE_PICK: String = "res://scenes/role_pick.tscn"

var lobby: Node = null
var battle: Node = null
var my_player_id: int = -1
var in_room: bool = false
var started: bool = false
var last_info: Dictionary = {}
var last_role_req: Dictionary = {}
var role_pick_layer: Node = null
## 当前所在房间 id；-1 表示不在任何房间（断线重连时据此自动回到原房间）
var current_room_id: int = -1
## 是否成功连上过房主（用于区分「首次连接」与「断线重连」）
var _ever_connected: bool = false
## 重连后已重发登录、正在等待回到原房间（收到 Game 视为成功，收到房间不存在错误视为失败）
var _pending_reenter: bool = false


func _ready() -> void:
	Net.message_received.connect(_on_message)
	Net.disconnected.connect(_on_disconnected)
	Net.connected.connect(_on_connected)
	Net.client.reconnect_failed.connect(_on_reconnect_failed)
	Data.nick_name = Cfg.nickname


# ============================================================
# 收包分派
# ============================================================
func _on_message(msg_type: int, data: Dictionary) -> void:
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
			# 重连后回原房间失败（房间已解散）：不再等待，提示并回大厅
			if _pending_reenter and err_id == GConst.GE_INVALID_TABLEID:
				_give_up_reconnect("原房间已不存在，即将返回大厅")
		GConst.Msg.Gossip:
			if int(data.get("type", 0)) == GConst.GossipType.Talk:
				# 聊天：把发送者昵称补全显示（服务端只下发 player_id）
				var pid: int = int(data.get("id", -1))
				var talker: GPlayer = Data.get_player_by_id(pid)
				var who: String = talker.nickname if talker != null else str(pid)
				gossip_received.emit("%s：%s" % [who, str(data.get("txt", ""))])
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
			if battle != null:
				battle.on_invalid_input(data)


func _on_game(data: Dictionary) -> void:
	last_info = data
	# Game 是对局内权威快照：收到即代表已身处房间，记录房间上下文并结束重连等待
	current_room_id = int(data.get("room_id", current_room_id))
	_pending_reenter = false
	my_player_id = int(data.get("player_id", -1))
	Data.id = my_player_id
	Data.nick_name = Cfg.nickname
	Data.build_player_list(data)
	Data.apply_team_info(data)
	started = bool(data.get("is_started", false))
	if started:
		Data.init_team(18 if Data.player_max == 8 else 15)
	in_room = true
	# 首条对局信息 → 切界面：未开局进「房间准备室」（ReadyRoom），开局切新版战斗界面
	var 目标界面名: String = "BattleUIMobile" if started else "ReadyRoom"
	if UI.current == null or UI.current.name != 目标界面名:
		if started:
			UI.goto_battle_mobile()
		else:
			UI.goto_ready_room()
	game_info_updated.emit(data)


func _on_disconnected() -> void:
	# 界面保持原状（对局不立刻清空），等待 NetClient 自动重连；恢复后由 Game 消息刷新
	gossip_received.emit("与房主的连接已断开，正在重连…")


## 连接建立：首次连接由界面继续后续流程；重连则在登录成功后自动回到原房间
func _on_connected() -> void:
	if not _ever_connected:
		_ever_connected = true
		return
	if current_room_id < 0:
		return
	# 每次连接 Net 都会重发 LoginReq（见 net_manager），登录回执到达后再进房
	_pending_reenter = true
	notice_received.emit("已重新连接，正在回到房间…", GConst.GossipType.Notice)


## 登录回执：重连场合下紧接着重新进房（服务端对每条连接都会回一条 LoginRep）
func _on_login_rep() -> void:
	if not _pending_reenter:
		return
	enter_room(current_room_id)


## 连续重连失败：提示玩家并返回大厅
func _on_reconnect_failed() -> void:
	if not _ever_connected:
		return
	_give_up_reconnect("重连失败，即将返回大厅")


## 重连无法完成（连续失败 / 原房间已不存在）：清空房间上下文、回大厅并提示玩家
func _give_up_reconnect(txt: String) -> void:
	current_room_id = -1
	_pending_reenter = false
	in_room = false
	started = false
	# 先切回大厅再提示：旧界面随即被替换，提示才会落到新大厅上
	UI.goto_lobby()
	notice_received.emit(txt, GConst.GossipType.Warn)


# ============================================================
# 选将（RoleReq 下发 → 弹层 → PickBan 上行）
# ============================================================
func _on_role_req(data: Dictionary) -> void:
	last_role_req = data
	role_pick_required.emit(data)
	_show_role_pick(data)


## 弹出选将界面；已有实例时只更新内容，不重复叠层
func _show_role_pick(data: Dictionary) -> void:
	if role_pick_layer != null and is_instance_valid(role_pick_layer):
		role_pick_layer.apply_request(data)
		return
	var ps: PackedScene = load(SCENE_ROLE_PICK)
	if ps == null:
		push_error("Logic: 无法加载选将界面 %s" % SCENE_ROLE_PICK)
		return
	var inst: Node = ps.instantiate()
	role_pick_layer = inst
	# 选将是满屏弹层，挂到「界面层」（屏幕坐标空间）。不能挂进当前界面：
	# 房间界面是按 1280x720 设计、整体放大 1.5 倍的（见 ReadyRoom.tscn 根节点 scale），
	# 挂进去会跟着放大 1.5 倍，整块版面溢出屏幕。
	UI.界面层.add_child(inst)
	inst.apply_request(data)


# ============================================================
# 上行操作
# ============================================================
func request_room_list() -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.RoomListReq, {"role_strategy": GConst.RoleStrategy.All})


func create_room(room_name: String, max_player: int, role_strategy: int = GConst.RoleStrategy.Random, debug: bool = false) -> void:
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.CreateRoomReq, {
		"room_name": room_name,
		"max_player": max_player,
		"role_strategy": role_strategy,
		"seat_mode": GConst.SeatMode.Random,
		"allow_guest": true,
		"debug": debug,
	})


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
	if not Net.is_connected_to_host():
		return
	Net.send(GConst.Msg.EnterRoomReq, {"room_id": room_id})


func leave_room() -> void:
	if Net.is_connected_to_host():
		Net.send(GConst.Msg.LeaveRoomReq, {})
	# 主动离开即清除房间上下文：之后断线不再尝试回到该房间
	current_room_id = -1
	_pending_reenter = false
	in_room = false
	started = false


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
		_: return "错误码 %d" % err_id

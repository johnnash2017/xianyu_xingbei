class_name SteamClient
extends NetworkClient
## 客户端传输层的 Steam 底座（SteamNetworkingMessages）。
## 通道划分见 SteamServer 顶部说明：客户端「发 0 号通道、收 1 号通道」。

const 发送通道: int = 0
const 接收通道: int = 1
## 单轮最多取几条：取完这轮，下一帧接着取
const 单轮取消息数: int = 64
## 重连上限与间隔（与 NetClient 保持一致）
const 最大重连次数: int = 3
const 重连间隔: float = 1.0

## 房主 SteamID：Steam 模式下的「地址」就是它（connect_to 传进来的十进制字符串）
var 房主steam_id: int = 0
## 本轮断开后已发起的重连次数（收到房主消息即清零）
var reconnect_attempts: int = 0
## 「连的是自己」时的进程内上行投递：把客户端发出的消息直接交给本机服务端（建房时由 Net 注入）。
## 房主自己这一路绝不能用 Steam 回环 —— 实测 SteamNetworkingMessages 的「发给自己」会被对端
## 当成关闭连接：发送返回 35（不是 1）并抛 network_messages_session_failed，
## 房主自己收不到任何下行包，还会被上层当成掉线、重连耗尽后踢回大厅（房间却已经建好了）。
var 本机投递: Callable = Callable()

var _重连计时: float = 0.0


func _init() -> void:
	# P2P 会话建立失败（对端不在线 / 打洞失败）：按掉线处理，交给上层重连
	SteamNet.P2P会话失败.connect(_on_p2p失败)


## 目标是不是本机（房主自己那一路）
func 连的是自己() -> bool:
	return 房主steam_id != 0 and 房主steam_id == int(SteamNet.steam_id)


func connect_to(host: String, _port: int) -> void:
	房主steam_id = int(host)
	reconnect_attempts = 0
	link_up = true
	connected.emit()


func close() -> void:
	if 房主steam_id != 0:
		Steam.closeSessionWithUser(房主steam_id)
	link_up = false


func sync_status() -> void:
	# Steam 没有 TCP 那种「刚连上时底层状态还是旧的」问题：link_up 由 connect_to 直接置位
	pass


func poll(delta: float) -> void:
	if not link_up:
		if auto_reconnect:
			_重连计时 -= delta
			if _重连计时 <= 0.0:
				_尝试重连()
		return
	# 房主自己那一路走进程内直连（见 本机投递）：Steam 这边没有东西可收
	if 连的是自己():
		return
	for 消息: Dictionary in Steam.receiveMessagesOnChannel(接收通道, 单轮取消息数):
		# 只认房主发来的：别的会话（例如别人也按 SteamID 给我们发消息）一律丢
		if int(消息.get("identity", 0)) != 房主steam_id:
			continue
		reconnect_attempts = 0
		var 载荷: PackedByteArray = 消息.get("payload", PackedByteArray())
		for f: Array in Framing.FrameDecoder.new().feed(载荷):
			var 协议号: int = int(f[0])
			message_received.emit(协议号, ProtoCodec.decode(协议号, f[1]))


## 服务端下行：进程内直连时由 SteamServer 直接塞进来，处理方式与收到网络包完全一致
func 收到下行(msg_type: int, fields: Dictionary) -> void:
	message_received.emit(msg_type, fields)


func send(msg_type: int, fields: Dictionary) -> bool:
	if not link_up or 房主steam_id == 0:
		return false
	if 连的是自己():
		# 延后到本帧 idle 阶段再交给本机服务端：不要在 UI 处理函数里同步跑完整套服务端逻辑
		# （局域网那套是走 TCP 回环的，服务端处理天然发生在下一帧的 _process 里，这里要保持一致）
		本机投递.call_deferred(msg_type, fields)
		return true
	var 帧: PackedByteArray = Framing.pack(msg_type, ProtoCodec.encode(msg_type, fields))
	# 注意用 NETWORKING_SEND_RELIABLE（= 8）：P2P_SEND_RELIABLE（= 2）是旧 ISteamNetworking 的枚举，不适用
	return Steam.sendMessageToUser(房主steam_id, 帧, Steam.NETWORKING_SEND_RELIABLE, 发送通道) == 1


func _尝试重连() -> void:
	if reconnect_attempts >= 最大重连次数:
		auto_reconnect = false
		reconnect_failed.emit()
		return
	reconnect_attempts += 1
	_重连计时 = 重连间隔
	# Steam P2P 没有「重新连接」这个动作：置位后再发包，Steam 会自己把会话重新建起来
	link_up = true
	connected.emit()


func _on_p2p失败(remote_steam_id: int) -> void:
	if remote_steam_id != 房主steam_id or not link_up:
		return
	link_up = false
	disconnected.emit()
	if auto_reconnect:
		_重连计时 = 0.0

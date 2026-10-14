class_name SteamServer
extends NetworkServer
## 服务端传输层的 Steam 底座（SteamNetworkingMessages）。
## 房主进程用它收各路玩家 / 观战者的消息：对端身份就是对方 SteamID，直接拿来当 conn_id。
##
## 通道划分（与服务端 / 客户端这两个角色绑定，避免同一进程里两个角色抢消息）：
##   服务端：收 0 号通道、发 1 号通道
##   客户端：发 0 号通道、收 1 号通道
## 房主进程里同时跑着「服务端 + 自己这个客户端」，靠通道把两边的队列分开。

## 本角色收 / 发用的通道号
const 接收通道: int = 0
const 发送通道: int = 1
## 单轮最多取几条：取完这轮，下一帧接着取
const 单轮取消息数: int = 64

## 已建立会话的对端（键 = 对方 SteamID）
var _对端: Dictionary = {}
## 房主自己那一路：不走 Steam，直接进程内递送（见 接入本地客户端）
var 本地客户端: SteamClient = null
## 房主自己那一路的连接号（= 本机 SteamID）；没接入时是 0，而 SteamID 不可能是 0
var 本地连接号: int = 0


## 接入房主自己那一路：像收到一条新连接那样登记，但收发都在进程内完成。
## 为什么不能用 Steam 回环：见 SteamClient.本机投递 的说明。
func 接入本地客户端(c: SteamClient, conn_id: int) -> void:
	本地客户端 = c
	本地连接号 = conn_id
	_对端[conn_id] = true
	client_connected.emit(conn_id)


func listen(p: int, _bind_addr: String = "0.0.0.0") -> int:
	# Steam P2P 不需要监听端口：对端能发消息过来就说明会话通了（Steam 自己建会话）
	port = p
	listening = true
	return OK


func stop() -> void:
	for conn_id: int in _对端.keys():
		关会话(conn_id)
	_对端.clear()
	listening = false


func poll() -> void:
	if not listening:
		return
	for 消息: Dictionary in Steam.receiveMessagesOnChannel(接收通道, 单轮取消息数):
		var 来自: int = int(消息.get("identity", 0))
		if 来自 == 0:
			continue
		# 第一次收到某个对端的消息 = 这条连接建立（对应 TCP 的 accept）
		if not _对端.has(来自):
			_对端[来自] = true
			client_connected.emit(来自)
		var 载荷: PackedByteArray = 消息.get("payload", PackedByteArray())
		for f: Array in Framing.FrameDecoder.new().feed(载荷):
			var 协议号: int = int(f[0])
			client_message.emit(来自, 协议号, ProtoCodec.decode(协议号, f[1]))


func close_conn(conn_id: int) -> void:
	_断开(conn_id)


func has_conn(conn_id: int) -> bool:
	return _对端.has(conn_id)


func send(conn_id: int, msg_type: int, fields: Dictionary) -> void:
	if 本地客户端 != null and conn_id == 本地连接号:
		本地客户端.收到下行(msg_type, fields)
		return
	if not _对端.has(conn_id):
		return
	var 帧: PackedByteArray = Framing.pack(msg_type, ProtoCodec.encode(msg_type, fields))
	if 帧.is_empty():
		return    # 帧过大：Framing 已报错，这里不发出坏帧
	# 注意：用 NETWORKING_SEND_RELIABLE（= 8，SteamNetworkingSockets 的发送标志）。
	# 别用 P2P_SEND_RELIABLE（= 2）—— 那是旧 ISteamNetworking 的枚举，这个 API 不认。
	Steam.sendMessageToUser(conn_id, 帧, Steam.NETWORKING_SEND_RELIABLE, 发送通道)


## 关掉与某个对端的 Steam 会话。房主自己那一路没有 Steam 会话，跳过。
func 关会话(conn_id: int) -> void:
	if conn_id != 本地连接号:
		Steam.closeSessionWithUser(conn_id)


## Steam P2P 没有底层断连事件，这些连接只能靠心跳回声超时判掉线（见 LocalServer._推心跳）
func 靠回声判掉线(conn_id: int) -> bool:
	return _对端.has(conn_id)


func _断开(conn_id: int) -> void:
	if not _对端.has(conn_id):
		return
	关会话(conn_id)
	_对端.erase(conn_id)
	client_disconnected.emit(conn_id)
	# 房主自己那一路（进程内直连）也把「断开」告诉那个客户端对象：
	# 它没有 Steam 会话、收不到任何底层断连事件，不告诉它就会一直以为连着（link_up 仍是 true），
	# 界面上建房 / 准备 / 退出全都没反应，也不会自动重连
	if conn_id == 本地连接号 and 本地客户端 != null:
		本地客户端.标记断开()

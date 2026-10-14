class_name SteamClient
extends NetworkClient
## 客户端传输层的 Steam 底座（SteamNetworkingMessages）。
## 通道划分见 SteamServer 顶部说明：客户端「发 0 号通道、收 1 号通道」。
##
## 连接判定：Steam P2P 没有「连上了」这种事件，发出去的第一条消息（登录）才把通道建起来。
## 所以 connect_to 之后先发「连接已发起」让上层把登录发出去，收到房主的任何一条消息才算真连上
## （link_up 置位 + connected）—— 这样不会出现「刚点连接就报成功、其实消息全发不出去」的假连上。

const 发送通道: int = 0
const 接收通道: int = 1
## 单轮最多取几条：取完这轮，下一帧接着取
const 单轮取消息数: int = 64
## 连着试这么多轮还没有房主的任何回应就放弃（含第一轮）：一轮等 确认超时 这么久，约 12 秒
const 最多尝试轮数: int = 3
const 重连间隔: float = 1.0
## 等房主回应的上限（秒）：到点还没收到任何回应就当这次连接失败，走重连。
## 每次重试都会重发登录，所以试满 3 次约 16 秒后报「重连失败」—— 别调得太短，
## 对端 NAT 打洞慢的时候几秒还没通是正常的
const 确认超时: float = 4.0

## 房主 SteamID：Steam 模式下的「地址」就是它（connect_to 传进来的十进制字符串）
var 房主steam_id: int = 0
## 本次连接已经试了几轮（含第一轮）；收到房主任何消息即清零
var 尝试轮数: int = 0
## 「连的是自己」时的进程内上行投递：把客户端发出的消息直接交给本机服务端（建房时由 Net 注入）。
## 房主自己这一路绝不能用 Steam 回环 —— 实测 SteamNetworkingMessages 的「发给自己」会被对端
## 当成关闭连接：发送返回 35（不是 1）并抛 network_messages_session_failed，
## 房主自己收不到任何下行包、还会被上层当成掉线、重连耗尽后踢回大厅（房间却已经建好了）。
var 本机投递: Callable = Callable()

var _重连计时: float = 0.0
## 已发出连接请求、正在等房主的第一条消息（这段期间 link_up 还是 false）
var _等待确认: bool = false
## 已经等了多久（秒），到 确认超时 就当这次连接失败
var _等待计时: float = 0.0


func _init() -> void:
	# P2P 会话建立失败（对端不在线 / 打洞失败）：按掉线处理，交给上层重连
	SteamNet.P2P会话失败.connect(_on_p2p失败)


## 目标是不是本机（房主自己那一路）。
## 比的是「本机 SteamID」：用 Cfg.身份标识()（一经取得就固定下来，见 Cfg 里同名函数的说明），
## 不能比 SteamNet.steam_id —— 它在 Steam 掉线时会被清空（见 SteamNet._标记掉线），
## 那会让房主自己那一路被误判成「连的是别人」，消息改走 Steam 回环
## （对自己发送必失败，见上面 本机投递 的说明），于是房主操作全丢、还会被判掉线踢回大厅。
func 连的是自己() -> bool:
	if 房主steam_id == 0 or Cfg.无Steam():
		return false
	return 房主steam_id == int(Cfg.身份标识())


func connect_to(host: String, _port: int) -> void:
	房主steam_id = int(host)
	尝试轮数 = 1
	link_up = false
	_等待确认 = true
	_等待计时 = 0.0
	# 立刻通知上层「可以发了」：那条登录消息本身就把 P2P 通道建起来。
	# 这里刻意不报 connected —— 还没收到房主的任何回应，不能算连上（见文件头说明）
	连接已发起.emit()


func close() -> void:
	if 房主steam_id != 0:
		Steam.closeSessionWithUser(房主steam_id)
	link_up = false
	_等待确认 = false


func sync_status() -> void:
	# Steam 不像 TCP 那样「刚连上时底层状态还是旧的」：link_up 由收到房主消息那一刻置位
	pass


func poll(delta: float) -> void:
	# 房主自己那一路走进程内直连（见 本机投递）：下行由 收到下行 直接递进来，这里没东西可收。
	# 但下面的「等确认超时 → 重试」照旧要对它生效：万一本机投递那条路没送达，
	# 也不能就这么一直卡在未连上（重试会再发一次登录，让它重新走一遍）
	if not 连的是自己() and (link_up or _等待确认):
		# 不管确认没确认，都要把队列取出来：房主回的第一条消息本身就是「通道通了」的证据
		for 消息: Dictionary in Steam.receiveMessagesOnChannel(接收通道, 单轮取消息数):
			# 只认房主发来的：别的会话（例如别人也按 SteamID 给我们发消息）一律丢
			if int(消息.get("identity", 0)) != 房主steam_id:
				continue
			_确认连接()
			_解析(消息.get("payload", PackedByteArray()))
	if link_up:
		return
	if _等待确认:
		# 通道还没通：等房主回第一条消息。等不到就当这次连接失败，走重连
		_等待计时 += delta
		if _等待计时 >= 确认超时:
			_尝试重连()
		return
	if auto_reconnect:
		_重连计时 -= delta
		if _重连计时 <= 0.0:
			_尝试重连()


## 服务端下行：进程内直连时由 SteamServer 直接塞进来，处理方式与收到网络包完全一致
func 收到下行(msg_type: int, fields: Dictionary) -> void:
	# 房主自己那一路：这条下行就是「通道通了」的证据
	_确认连接()
	message_received.emit(msg_type, fields)


## 上层判定连接不可用（服务端心跳静默）/ 服务端那侧把本机直连断掉了：关掉与房主的会话并通知上层，
## 之后由自动重连继续试。重连会重发登录，服务端据此重新登记这条连接
## （见 LocalServer._on_client_message 里对「会话不存在却收到登录」的处理）
func 标记断开() -> void:
	if 房主steam_id != 0:
		Steam.closeSessionWithUser(房主steam_id)
	link_up = false
	_等待确认 = false
	disconnected.emit()
	if auto_reconnect:
		_重连计时 = 0.0


func send(msg_type: int, fields: Dictionary) -> bool:
	if 房主steam_id == 0:
		return false
	# 正在等确认时也要能发：第一条登录消息就是用来把通道建起来的（见 connect_to）
	if not link_up and not _等待确认:
		return false
	if 连的是自己():
		# 延后到本帧 idle 阶段再交给本机服务端：不要在 UI 处理函数里同步跑完整套服务端逻辑
		# （局域网那套是走 TCP 回环的，服务端处理天然发生在下一帧的 _process 里，这里要保持一致）
		# 必须「深拷一份」再延后：上层发完常常立刻清空自己那些数组
		# （BattleMobile._发送行动 → _清空待选 会 _sel_cards.clear() / _sel_players.clear()），
		# 而这里只传引用的话，等 idle 阶段真去处理时数组已经空了 —— 表现就是「房主的行动被吞掉」
		# （手上的牌与目标都变成空 → 引擎按「牌或目标为空」直接结束回合）。
		# 走真实网络的客户端不受影响：它们是当场编码成字节再发，之后清空追不回来
		本机投递.call_deferred(msg_type, fields.duplicate(true))
		return true
	var 帧: PackedByteArray = Framing.pack(msg_type, ProtoCodec.encode(msg_type, fields))
	if 帧.is_empty():
		return false    # 帧过大：Framing 已报错，这里不发出坏帧
	# 注意用 NETWORKING_SEND_RELIABLE（= 8）：P2P_SEND_RELIABLE（= 2）是旧 ISteamNetworking 的枚举，不适用
	return Steam.sendMessageToUser(房主steam_id, 帧, Steam.NETWORKING_SEND_RELIABLE, 发送通道) == 1


## 收到房主的第一条消息：这才是真的连上了，通知上层
func _确认连接() -> void:
	if link_up:
		return
	link_up = true
	_等待确认 = false
	_等待计时 = 0.0
	尝试轮数 = 0
	connected.emit()


## 收到一批字节：分帧解码后派发（一条 P2P 消息里可能装着不止一帧）
func _解析(载荷: PackedByteArray) -> void:
	for f: Array in Framing.FrameDecoder.new().feed(载荷):
		var 协议号: int = int(f[0])
		message_received.emit(协议号, ProtoCodec.decode(协议号, f[1]))


## 重试一轮（通道建不起来 / 等不到房主回应）：再发一次登录探测、继续等；试满轮数就报失败
func _尝试重连() -> void:
	if 尝试轮数 >= 最多尝试轮数:
		auto_reconnect = false
		_等待确认 = false
		reconnect_failed.emit()
		return
	尝试轮数 += 1
	_重连计时 = 重连间隔
	link_up = false
	_等待确认 = true
	_等待计时 = 0.0
	连接已发起.emit()


func _on_p2p失败(remote_steam_id: int) -> void:
	if remote_steam_id != 房主steam_id:
		return
	if not link_up and not _等待确认:
		return
	link_up = false
	_等待确认 = false
	disconnected.emit()
	if auto_reconnect:
		_重连计时 = 0.0

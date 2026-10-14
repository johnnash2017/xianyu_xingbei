class_name NetClient
extends NetworkClient
## 客户端传输层的局域网 TCP 底座（对照客户端 client/Client.cpp：QTcpSocket 长连接）
## 职责：维护一条与「当前房主服务端」的 TCP 长连接；支持自动重连；收包分帧解码后派发。

## 重连上限与间隔
const MAX_RECONNECT_ATTEMPTS: int = 3
const RECONNECT_INTERVAL: float = 1.0
## 「连上房主」的总时限（秒）—— 到这个时刻还没连上就放弃这次连接并通知上层。
## 分两种情形（期望不同，所以两个值）：
##   · 首次连接（玩家点一台主机 / 点一间房）：6 秒。这是玩家的等待上限 —— 目标不可达
##     （对端已经关掉、SYN 被丢）时底层会长时间停在「正在连接」且没有内建超时，
##     旧写法「单次 6 秒 × 重连 3 次」要干等 20 秒才有结果；
##   · 掉线后的重连：20 秒。房主只是卡了一下（进程没死）时，玩家应该还连得回去。
## 两种情形都会保留「秒失败（端口上没人监听 = 连接被直接拒绝）时按 RECONNECT_INTERVAL 重试几次」
const 首次连接总时限: float = 6.0
const 重连总时限: float = 20.0

var target_host: String = "127.0.0.1"
var target_port: int = GConst.DEFAULT_PORT
## 本次断线后已发起的重连次数（连上即清零）
var reconnect_attempts: int = 0

var _tcp: StreamPeerTCP = null
var _decoder: Framing.FrameDecoder = Framing.FrameDecoder.new()
var _reconnect_timer: float = 0.0
var _ever_connected: bool = false
## 本次「连上房主」的起点（毫秒）与本次该用的总时限（毫秒）：
## connect_to 按首次连接填，掉线时按重连填（见 _on_lost / 标记断开）
var _连接起始_ms: int = 0
var _总时限_ms: int = 0


func connect_to(host: String, port: int) -> void:
	target_host = host
	target_port = port
	reconnect_attempts = 0
	_连接起始_ms = Time.get_ticks_msec()
	_总时限_ms = int(首次连接总时限 * 1000.0)
	_begin_connect()


## 断开旧连接并按 target_host/target_port 重新发起一次连接（不重置重连计数）
func _begin_connect() -> void:
	close()
	_tcp = StreamPeerTCP.new()
	var err: int = _tcp.connect_to_host(target_host, target_port)
	if err != OK:
		push_error("NetClient: 连接 %s:%d 失败（%d）" % [target_host, target_port, err])


## 重连一次：次数用尽或已经过了总时限，就放弃这次连接并通知上层
func _try_reconnect() -> void:
	if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS or _超时了():
		_放弃连接()
		return
	reconnect_attempts += 1
	_reconnect_timer = RECONNECT_INTERVAL
	_begin_connect()


## 本次连接是否已经超过总时限（见 首次连接总时限 / 重连总时限）
func _超时了() -> bool:
	if _连接起始_ms <= 0 or _总时限_ms <= 0:
		return false
	return Time.get_ticks_msec() - _连接起始_ms >= _总时限_ms


## 放弃这次连接：断掉半连接、不再自动重连，并通知上层（界面据此提示玩家）
func _放弃连接() -> void:
	auto_reconnect = false
	close()
	reconnect_failed.emit()


func close() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	link_up = false
	_ever_connected = false
	_decoder = Framing.FrameDecoder.new()


## 主动同步一次连接状态：刚连上的那一瞬间内部状态可能还是旧值，直接发包会被丢弃
func sync_status() -> void:
	if _tcp != null:
		_tcp.poll()
		_apply_status(_tcp.get_status())


func poll(delta: float) -> void:
	if _tcp == null:
		if auto_reconnect:
			_reconnect_timer -= delta
			if _reconnect_timer <= 0.0:
				_try_reconnect()
		return
	_tcp.poll()
	var st: int = _tcp.get_status()
	# 还在握手：对不可达地址底层可能长时间停在 CONNECTING（没有内建超时），
	# 超过总时限就当这次连接失败 —— 否则玩家会一直卡在「正在进入房间」，界面上毫无反馈
	if st == StreamPeerTCP.STATUS_CONNECTING:
		if _超时了():
			push_warning("NetClient: 连接 %s:%d 超时（%.1f 秒）" % [target_host, target_port, _总时限_ms / 1000.0])
			_放弃连接()
		return    # 握手期间没有数据可收
	_apply_status(st)
	if st == StreamPeerTCP.STATUS_CONNECTED:
		var avail: int = _tcp.get_available_bytes()
		while avail > 0:
			var res: Array = _tcp.get_partial_data(avail)
			if res[0] != OK:
				break
			_feed(res[1])
			# _feed 处理的消息可能触发断线（_on_lost 会把 _tcp 置空），此时不能再取可读字节数
			if _tcp == null:
				break
			avail = _tcp.get_available_bytes()


## 依据底层状态更新内部标志：连上只通知一次；断开则清连接并进入重连
func _apply_status(st: int) -> void:
	if st == StreamPeerTCP.STATUS_CONNECTED:
		if not link_up:
			link_up = true
			_ever_connected = true
			reconnect_attempts = 0
			connected.emit()
	elif st == StreamPeerTCP.STATUS_ERROR:
		_on_lost()
	elif st == StreamPeerTCP.STATUS_NONE and _ever_connected:
		_on_lost()


func _on_lost() -> void:
	var was_live: bool = link_up or _ever_connected
	link_up = false
	_ever_connected = false
	_tcp = null
	_decoder = Framing.FrameDecoder.new()
	if was_live:
		disconnected.emit()
	if auto_reconnect:
		_reconnect_timer = 0.0
		# 掉线后的重连另起一段：起点与总时限都换成重连那一档
		# （否则会拿上一次连接的起点去判超时，一上来就放弃）
		_连接起始_ms = Time.get_ticks_msec()
		_总时限_ms = int(重连总时限 * 1000.0)


func _feed(data: PackedByteArray) -> void:
	for f: Array in _decoder.feed(data):
		var msg_type: int = f[0]
		var body: PackedByteArray = f[1]
		var fields: Dictionary = ProtoCodec.decode(msg_type, body)
		message_received.emit(msg_type, fields)


## 上层判定连接不可用（服务端心跳静默）：断掉底层 TCP 并通知上层，之后由自动重连继续试
func 标记断开() -> void:
	var was_live: bool = link_up or _ever_connected
	close()
	if was_live:
		disconnected.emit()
	if auto_reconnect:
		_reconnect_timer = 0.0
		# 同 _on_lost：这一段重连有自己的起点与总时限
		_连接起始_ms = Time.get_ticks_msec()
		_总时限_ms = int(重连总时限 * 1000.0)


## 发送一条消息
func send(msg_type: int, fields: Dictionary) -> bool:
	if _tcp == null:
		return false
	var body: PackedByteArray = ProtoCodec.encode(msg_type, fields)
	var frame: PackedByteArray = Framing.pack(msg_type, body)
	if frame.is_empty():
		return false    # 帧过大：Framing 已报错，这里不发出坏帧
	var err: int = _tcp.put_data(frame)
	return err == OK

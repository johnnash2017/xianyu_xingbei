class_name NetClient
extends RefCounted
## 客户端网络节点（对照客户端 client/Client.cpp：QTcpSocket 长连接）
## 职责：维护一条与「当前房主服务端」的 TCP 长连接；支持自动重连；收包分帧解码后派发。

signal connected
signal disconnected
## 连续重连达到上限仍未成功：上层据此提示玩家并返回大厅
signal reconnect_failed
signal message_received(msg_type: int, data: Dictionary)

## 重连上限与间隔
const MAX_RECONNECT_ATTEMPTS: int = 3
const RECONNECT_INTERVAL: float = 1.0

var is_connected: bool = false
var auto_reconnect: bool = false
var target_host: String = "127.0.0.1"
var target_port: int = GConst.DEFAULT_PORT
## 本次断线后已发起的重连次数（连上即清零）
var reconnect_attempts: int = 0

var _tcp: StreamPeerTCP = null
var _decoder: Framing.FrameDecoder = Framing.FrameDecoder.new()
var _reconnect_timer: float = 0.0
var _ever_connected: bool = false


func connect_to(host: String, port: int) -> void:
	target_host = host
	target_port = port
	reconnect_attempts = 0
	_begin_connect()


## 断开旧连接并按 target_host/target_port 重新发起一次连接（不重置重连计数）
func _begin_connect() -> void:
	close()
	_tcp = StreamPeerTCP.new()
	var err: int = _tcp.connect_to_host(target_host, target_port)
	if err != OK:
		push_error("NetClient: 连接 %s:%d 失败（%d）" % [target_host, target_port, err])


## 重连一次：达到上限仍未成功则放弃自动重连并通知上层
func _try_reconnect() -> void:
	if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
		auto_reconnect = false
		reconnect_failed.emit()
		return
	reconnect_attempts += 1
	_reconnect_timer = RECONNECT_INTERVAL
	_begin_connect()


func close() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	is_connected = false
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
	_apply_status(st)
	if st == StreamPeerTCP.STATUS_CONNECTED:
		var avail: int = _tcp.get_available_bytes()
		while avail > 0:
			var res: Array = _tcp.get_partial_data(avail)
			if res[0] != OK:
				break
			_feed(res[1])
			avail = _tcp.get_available_bytes()


## 依据底层状态更新内部标志：连上只通知一次；断开则清连接并进入重连
func _apply_status(st: int) -> void:
	if st == StreamPeerTCP.STATUS_CONNECTED:
		if not is_connected:
			is_connected = true
			_ever_connected = true
			reconnect_attempts = 0
			connected.emit()
	elif st == StreamPeerTCP.STATUS_ERROR:
		_on_lost()
	elif st == StreamPeerTCP.STATUS_NONE and _ever_connected:
		_on_lost()


func _on_lost() -> void:
	var was_live: bool = is_connected or _ever_connected
	is_connected = false
	_ever_connected = false
	_tcp = null
	_decoder = Framing.FrameDecoder.new()
	if was_live:
		disconnected.emit()
	if auto_reconnect:
		_reconnect_timer = 0.0


func _feed(data: PackedByteArray) -> void:
	for f: Array in _decoder.feed(data):
		var msg_type: int = f[0]
		var body: PackedByteArray = f[1]
		var fields: Dictionary = ProtoCodec.decode(msg_type, body)
		message_received.emit(msg_type, fields)


## 发送一条消息
func send(msg_type: int, fields: Dictionary) -> bool:
	if _tcp == null:
		return false
	var body: PackedByteArray = ProtoCodec.encode(msg_type, fields)
	var frame: PackedByteArray = Framing.pack(msg_type, body)
	var err: int = _tcp.put_data(frame)
	return err == OK

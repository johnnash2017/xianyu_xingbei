class_name NetServer
extends NetworkServer
## 服务端传输层的局域网 TCP 底座（对照服务端 base/zTCPServer + zTCPTask + zSocket2）
## 职责：监听、接受新连接并登记、统一轮询收包、按帧切分解码、向上层派发。

## 单条连接
class Conn:
	var id: int = 0
	var tcp: StreamPeerTCP = null
	var decoder: Framing.FrameDecoder = Framing.FrameDecoder.new()

var _srv: TCPServer = null
var _conns: Dictionary = {}     # conn_id -> Conn
var _next_id: int = 1


func listen(p: int, bind_addr: String = "0.0.0.0") -> int:
	_srv = TCPServer.new()
	var err: int = _srv.listen(p, bind_addr)
	listening = err == OK
	if listening:
		port = p
	return err


func stop() -> void:
	for cid: int in _conns.keys():
		_conns[cid].tcp.disconnect_from_host()
	_conns.clear()
	if _srv != null:
		_srv.stop()
	_srv = null
	listening = false


func poll() -> void:
	if not listening:
		return
	# 先接受新连接并登记，再统一轮询（否则新连接会被误判为已断开）
	while _srv.is_connection_available():
		var tcp: StreamPeerTCP = _srv.take_connection()
		if tcp == null:
			break
		var c: Conn = Conn.new()
		c.id = _next_id
		_next_id += 1
		c.tcp = tcp
		_conns[c.id] = c
		client_connected.emit(c.id)
	# 再统一轮询
	for cid: int in _conns.keys():
		var c: Conn = _conns[cid]
		c.tcp.poll()
		if c.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(cid)
			continue
		var avail: int = c.tcp.get_available_bytes()
		while avail > 0:
			var res: Array = c.tcp.get_partial_data(avail)
			if res[0] != OK:
				break
			for f: Array in c.decoder.feed(res[1]):
				var body: PackedByteArray = f[1]
				var fields: Dictionary = ProtoCodec.decode(f[0], body)
				client_message.emit(cid, f[0], fields)
			avail = c.tcp.get_available_bytes()


func close_conn(conn_id: int) -> void:
	_drop(conn_id)


func has_conn(conn_id: int) -> bool:
	return _conns.has(conn_id)


func send(conn_id: int, msg_type: int, fields: Dictionary) -> void:
	var c: Conn = _conns.get(conn_id)
	if c == null:
		return
	var body: PackedByteArray = ProtoCodec.encode(msg_type, fields)
	var frame: PackedByteArray = Framing.pack(msg_type, body)
	c.tcp.put_data(frame)


func _drop(conn_id: int) -> void:
	if not _conns.has(conn_id):
		return
	var c: Conn = _conns[conn_id]
	c.tcp.disconnect_from_host()
	_conns.erase(conn_id)
	client_disconnected.emit(conn_id)

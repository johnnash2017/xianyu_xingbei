class_name Discovery
extends RefCounted
## 局域网发现（对照「多开与局域网实现说明.md」3.5 / 3.6）
## 两条互补路径：
##   其一，同机 TCP 连接探测（对回环地址与各网卡地址发探测，连上即说明有房，随即断开）
##   其二，跨机 UDP 广播（房主应答探测方，并再广播一次便于同网段其它客户端一起收到）

signal host_found(address: String, port: int, room_count: int, host_name: String)

const MAGIC: int = 0x47494C41          # "GILA"
const TYPE_PROBE: int = 1
const TYPE_REPLY: int = 2

var instance_id: int = 0               # 用于忽略自己发出的报文

var _udp: PacketPeerUDP = null
var _searching: bool = false
var _responding: bool = false
var _service_port: int = GConst.DEFAULT_PORT
var _host_name: String = ""
var _timer: float = 0.0
## 同机 TCP 探测：address -> 是否已发现
var _tcp_probes: Array = []
var _seen: Dictionary = {}


func _init() -> void:
	instance_id = randi()


# ============================================================
# 搜索方：周期性广播探测
# ============================================================
func start_search(my_name: String) -> void:
	stop_all()
	_host_name = my_name
	_udp = PacketPeerUDP.new()
	var err: int = _udp.bind(0, "0.0.0.0")
	if err != OK:
		push_warning("Discovery: 绑定搜索端口失败（%d）" % err)
	_udp.set_broadcast_enabled(true)
	_searching = true
	_seen.clear()
	_timer = 0.0


func stop_all() -> void:
	_searching = false
	_responding = false
	_tcp_probes.clear()
	if _udp != null:
		_udp.close()
	_udp = null


# ============================================================
# 房主方：应答探测
# ============================================================
func start_responder(service_port: int, host_name: String) -> void:
	stop_all()
	_service_port = service_port
	_host_name = host_name
	_udp = PacketPeerUDP.new()
	# 广播端口只会被其中一个窗口抢到，其余绑定失败属预期（同机走连接探测）
	var err: int = _udp.bind(GConst.DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		_udp = null
		return
	_udp.set_broadcast_enabled(true)
	_responding = true


# ============================================================
# 轮询
# ============================================================
func poll(delta: float) -> void:
	if _udp == null:
		return
	if _searching:
		_timer -= delta
		if _timer <= 0.0:
			_timer = 0.6
			_send_probe()
	_tcp_probes_poll(delta)
	while _udp.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _udp.get_packet()
		var from_ip: String = _udp.get_packet_ip()
		var from_port: int = _udp.get_packet_port()
		_handle_packet(pkt, from_ip, from_port)


func _send_probe() -> void:
	var pkt: PackedByteArray = _make_probe()
	if _udp == null:
		return
	_udp.set_dest_address("255.255.255.255", GConst.DISCOVERY_PORT)
	_udp.put_packet(pkt)
	_udp.set_dest_address("127.0.0.1", GConst.DISCOVERY_PORT)
	_udp.put_packet(pkt)


func _make_probe() -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	_push_u32(b, MAGIC)
	_push_u32(b, instance_id)
	b.append(TYPE_PROBE)
	return b


func _handle_packet(pkt: PackedByteArray, from_ip: String, from_port: int) -> void:
	if pkt.size() < 9:
		return
	var magic: int = _read_u32(pkt, 0)
	if magic != MAGIC:
		return
	var iid: int = _read_u32(pkt, 4)
	if iid == instance_id:
		return    # 忽略自己发出的报文
	var t: int = pkt[8]
	if t == TYPE_PROBE and _responding:
		_reply(from_ip, from_port)
	elif t == TYPE_REPLY and _searching and pkt.size() >= 15:
		var port: int = pkt[9] | (pkt[10] << 8)
		var room_count: int = pkt[11] | (pkt[12] << 8)
		var name_len: int = pkt[13]
		var host_name: String = pkt.slice(14, 14 + name_len).get_string_from_utf8()
		var key: String = "%s:%d" % [from_ip, port]
		if not _seen.has(key):
			_seen[key] = true
			host_found.emit(from_ip, port, room_count, host_name)


func _reply(to_ip: String, to_port: int) -> void:
	if _udp == null:
		return
	var b: PackedByteArray = PackedByteArray()
	_push_u32(b, MAGIC)
	_push_u32(b, instance_id)
	b.append(TYPE_REPLY)
	b.append(_service_port & 0xFF)
	b.append((_service_port >> 8) & 0xFF)
	b.append(0)
	b.append(0)
	var name_bytes: PackedByteArray = _host_name.to_utf8_buffer()
	b.append(name_bytes.size())
	b.append_array(name_bytes)
	# 定向回复探测方
	_udp.set_dest_address(to_ip, to_port)
	_udp.put_packet(b)
	# 再广播一次，便于同网段其它客户端一起收到
	_udp.set_dest_address("255.255.255.255", GConst.DISCOVERY_PORT)
	_udp.put_packet(b)


# ============================================================
# 同机 TCP 连接探测
# ============================================================
## 对回环地址与各网卡地址发起连接探测；连上即说明有房，随即断开
func probe_local(port: int) -> void:
	_tcp_probes.clear()
	var addrs: Array[String] = ["127.0.0.1"]
	for a: String in IP.get_local_addresses():
		if a.begins_with("127.") or a.contains(":"):
			continue
		if not addrs.has(a):
			addrs.append(a)
	for a: String in addrs:
		var tcp: StreamPeerTCP = StreamPeerTCP.new()
		tcp.connect_to_host(a, port)
		_tcp_probes.append({"tcp": tcp, "addr": a, "port": port, "age": 0.0, "done": false})


func _tcp_probes_poll(delta: float) -> void:
	if _tcp_probes.is_empty():
		return
	var alive: Array = []
	for pr: Dictionary in _tcp_probes:
		if pr["done"]:
			continue
		var tcp: StreamPeerTCP = pr["tcp"]
		tcp.poll()
		pr["age"] = float(pr["age"]) + delta
		var st: int = tcp.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			tcp.disconnect_from_host()
			var addr: String = str(pr["addr"])
			# 地址归一化：网卡地址折算为回环地址，避免同一个房主被算成两个房间
			var norm: String = "127.0.0.1"
			var key: String = "%s:%d" % [norm, int(pr["port"])]
			if not _seen.has(key):
				_seen[key] = true
				host_found.emit(norm, int(pr["port"]), 0, "本机房主")
			pr["done"] = true
		elif st == StreamPeerTCP.STATUS_ERROR or float(pr["age"]) > 1.0:
			tcp.disconnect_from_host()
			pr["done"] = true
		else:
			alive.append(pr)
	_tcp_probes = alive


# ============================================================
# 小工具
# ============================================================
func _push_u32(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 24) & 0xFF)


func _read_u32(b: PackedByteArray, off: int) -> int:
	return b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)

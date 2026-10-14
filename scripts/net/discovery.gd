class_name Discovery
extends RefCounted
## 局域网发现（对照「多开与局域网实现说明.md」3.5 / 3.6）
## 两条互补路径：
##   其一，同机 TCP 连接探测（对回环地址与各网卡地址发探测，连上即说明有房，随即断开）
##   其二，跨机 UDP 广播（房主应答探测方，并再广播一次便于同网段其它客户端一起收到）
##
## 「搜索」与「应答」各占一条独立 socket，互不影响：
##   房主一进房间，大厅界面退出时只会关掉「搜索」，房主必须继续应答别人的探测 ——
##   两条通道合用一条 socket 的话，关搜索会连应答一起关掉，房主进房后别人就再也搜不到他。

## 发现一台局域网房主。版本只用于列表显示 —— 刻意不参与过滤：
## 不同版本也要能互相看见（列表里显示对方版本），能不能进由登录时的版本校验决定（见 LocalServer 的 LoginReq）
signal host_found(address: String, port: int, room_count: int, host_name: String, 版本: String)

const MAGIC: int = 0x47494C41          # "GILA"
const TYPE_PROBE: int = 1
const TYPE_REPLY: int = 2
## 应答报文里「房主名」「版本号」各占一段**定长**字节（UTF-8，不足补 0）。
## 定长就不用再带长度字段了，也就不会再出现「名字比长度字段装得下」的问题；
## 名字最多占 32 字节（界面那一列本来也显示不下更多，超了按字符边界截断掉多余文字）。
## 版本号很短（如 1.0.36），16 字节够用很久
const REPLY_NAME_BYTES: int = 32
const REPLY_VER_BYTES: int = 16
## 应答报文固定长度：4 魔数 + 4 实例号 + 1 类型 + 2 端口 + 2 房间数 + 名字段 + 版本段
const REPLY_SIZE: int = 13 + REPLY_NAME_BYTES + REPLY_VER_BYTES

var instance_id: int = 0               # 用于忽略自己发出的报文

## 搜索用 socket（绑临时端口，收发探测与应答）
var _search_udp: PacketPeerUDP = null
## 应答用 socket（绑广播端口 DISCOVERY_PORT，收探测、回应答）
var _resp_udp: PacketPeerUDP = null
var _searching: bool = false
var _responding: bool = false
var _service_port: int = GConst.DEFAULT_PORT
var _host_name: String = ""
## 本进程的游戏版本号（start_responder 传入，见 _reply）。
## 只写进应答里给搜索方显示，不参与过滤：新旧版本互相看得见，能不能进由登录校验决定。
var _版本: String = ""
var _timer: float = 0.0
## 同机 TCP 探测：address -> 是否已发现
var _tcp_probes: Array = []
var _seen: Dictionary = {}


func _init() -> void:
	instance_id = randi()


# ============================================================
# 搜索方：周期性广播探测
# ============================================================
func start_search() -> void:
	stop_search()
	_search_udp = PacketPeerUDP.new()
	var err: int = _search_udp.bind(0, "0.0.0.0")
	if err != OK:
		push_warning("Discovery: 绑定搜索端口失败（%d）" % err)
	_search_udp.set_broadcast_enabled(true)
	_searching = true
	_seen.clear()
	_timer = 0.0


## 只停「搜索」：房主的应答通道不受影响（见文件头说明）
func stop_search() -> void:
	_searching = false
	_tcp_probes.clear()
	if _search_udp != null:
		_search_udp.close()
	_search_udp = null


# ============================================================
# 房主方：应答探测
# ============================================================
func start_responder(service_port: int, host_name: String, 版本: String) -> void:
	stop_responder()
	_service_port = service_port
	_host_name = host_name
	_版本 = 版本
	_resp_udp = PacketPeerUDP.new()
	# 广播端口只会被其中一个窗口抢到，其余绑定失败属预期（同机走连接探测）
	var err: int = _resp_udp.bind(GConst.DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		_resp_udp = null
		return
	_resp_udp.set_broadcast_enabled(true)
	_responding = true


## 只停「应答」：房主退房时才调（见 Net 的 stop_hosting / 停止局域网广播）
func stop_responder() -> void:
	_responding = false
	if _resp_udp != null:
		_resp_udp.close()
	_resp_udp = null


# ============================================================
# 轮询
# ============================================================
func poll(delta: float) -> void:
	if _searching:
		_timer -= delta
		if _timer <= 0.0:
			_timer = 0.6
			_send_probe()
	if _search_udp != null:
		_收包(_search_udp)
	if _resp_udp != null:
		_收包(_resp_udp)
	_tcp_probes_poll(delta)


func _收包(udp: PacketPeerUDP) -> void:
	while udp.get_available_packet_count() > 0:
		var pkt: PackedByteArray = udp.get_packet()
		_handle_packet(pkt, udp.get_packet_ip(), udp.get_packet_port())


func _send_probe() -> void:
	var pkt: PackedByteArray = _make_probe()
	if _search_udp == null:
		return
	_search_udp.set_dest_address("255.255.255.255", GConst.DISCOVERY_PORT)
	_search_udp.put_packet(pkt)
	_search_udp.set_dest_address("127.0.0.1", GConst.DISCOVERY_PORT)
	_search_udp.put_packet(pkt)


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
	elif t == TYPE_REPLY and _searching and pkt.size() >= REPLY_SIZE:
		var port: int = _read_u16(pkt, 9)
		var room_count: int = _read_u16(pkt, 11)
		var host_name: String = _读定长文本(pkt, 13, REPLY_NAME_BYTES)
		# 版本跟在名字后面（同样是定长段）：只用于列表显示，不参与过滤
		var ver: String = _读定长文本(pkt, 13 + REPLY_NAME_BYTES, REPLY_VER_BYTES)
		var key: String = "%s:%d" % [from_ip, port]
		if not _seen.has(key):
			_seen[key] = true
			host_found.emit(from_ip, port, room_count, host_name, ver)


func _reply(to_ip: String, to_port: int) -> void:
	if _resp_udp == null:
		return
	var b: PackedByteArray = PackedByteArray()
	_push_u32(b, MAGIC)
	_push_u32(b, instance_id)
	b.append(TYPE_REPLY)
	_push_u16(b, _service_port)
	_push_u16(b, 0)                 # 房间数：房间名单由连上后向服务端要，这里不填
	b.append_array(_定长字节(_host_name, REPLY_NAME_BYTES))
	b.append_array(_定长字节(_版本, REPLY_VER_BYTES))
	# 定向回复探测方
	_resp_udp.set_dest_address(to_ip, to_port)
	_resp_udp.put_packet(b)
	# 再广播一次，便于同网段其它客户端一起收到
	_resp_udp.set_dest_address("255.255.255.255", GConst.DISCOVERY_PORT)
	_resp_udp.put_packet(b)


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
		_tcp_probes.append({"tcp": tcp, "port": port, "age": 0.0, "done": false})


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
			# 地址归一化：网卡地址折算为回环地址，避免同一个房主被算成两个房间
			var norm: String = "127.0.0.1"
			var key: String = "%s:%d" % [norm, int(pr["port"])]
			if not _seen.has(key):
				_seen[key] = true
				# 同机 TCP 探测拿不到房主版本（只是连一下端口），版本留空，列表按「—」显示
				host_found.emit(norm, int(pr["port"]), 0, "本机房主", "")
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
## 把文本编成一段定长字节（UTF-8，不足补 0）：
## 超长时按「不切坏一个多字节字符」的原则截断 —— 否则截出来的半截字符解出来是乱码
## （界面上反正显示不下那么长，后头本来也是省略号）
static func _定长字节(文本: String, 长度: int) -> PackedByteArray:
	var 源: PackedByteArray = 文本.to_utf8_buffer()
	var 段: PackedByteArray = PackedByteArray()
	段.resize(长度)
	段.fill(0)
	var 取: int = mini(源.size(), 长度)
	# 截断点落在多字节字符中间时往前退到字符边界（UTF-8 的续字节形如 10xxxxxx）
	while 取 > 0 and 取 < 源.size() and (源[取] & 0xC0) == 0x80:
		取 -= 1
	for i: int in range(取):
		段[i] = 源[i]
	return 段


## 从定长段里读出文本：尾部补的 0 要切掉，否则字符串里会带上 NUL 字符
static func _读定长文本(b: PackedByteArray, off: int, 长度: int) -> String:
	var 段: PackedByteArray = b.slice(off, off + 长度)
	var 有效: int = 段.size()
	while 有效 > 0 and 段[有效 - 1] == 0:
		有效 -= 1
	return 段.slice(0, 有效).get_string_from_utf8()


func _push_u32(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 24) & 0xFF)


func _push_u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)


func _read_u32(b: PackedByteArray, off: int) -> int:
	return b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)


func _read_u16(b: PackedByteArray, off: int) -> int:
	return b[off] | (b[off + 1] << 8)

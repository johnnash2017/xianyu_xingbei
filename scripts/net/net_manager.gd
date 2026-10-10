extends Node
## 网络管理（autoload 名：Net）
## 编排「房主 / 加入」两条链路（对照说明文档 3.1 / 3.5）：
##   房主：本进程内起权威服务端，再把自己作为普通客户端连上本机服务端
##   加入：停掉本进程可能的房主身份，把连接目标切到指定房主地址

signal connected
signal disconnected
signal message_received(msg_type: int, data: Dictionary)
signal host_started
signal host_failed

var client: NetworkClient = null
var server: LocalServer = null
var discovery: Discovery = Discovery.new()
var hosting: bool = false

## 当前连接目标（供界面显示）。Steam 模式下是房主 SteamID
var target_host: String = "127.0.0.1"
var target_port: int = GConst.DEFAULT_PORT


func _ready() -> void:
	# 传输底座按启动模式装配：多开脚本（本地调试）走局域网 TCP，常规启动走 Steam P2P
	# （写成 if/else 而不是三元表达式：两个实现类型不同，三元会被判「分支类型不兼容」）
	if Cfg.本地模式:
		client = NetClient.new()
	else:
		client = SteamClient.new()
	client.message_received.connect(func(t: int, d: Dictionary) -> void: message_received.emit(t, d))
	client.connected.connect(_on_connected)
	client.disconnected.connect(func() -> void: disconnected.emit())


func _process(delta: float) -> void:
	client.poll(delta)
	if server != null:
		server.poll()
	discovery.poll(delta)


# ============================================================
# 房主
# ============================================================
func host_game() -> bool:
	if hosting:
		return true
	var s: LocalServer = LocalServer.new()
	# 局域网要占端口（同机多开靠端口区分房主）；Steam 模式走 P2P，不占端口
	var err: int = s.start(Cfg.server_port if Cfg.本地模式 else 0)
	if err != OK:
		push_warning("Net: 监听 %d 失败（%d），本机可能已有房主" % [Cfg.server_port, err])
		host_failed.emit()
		return false
	server = s
	hosting = true
	client.auto_reconnect = true
	if Cfg.本地模式:
		discovery.start_responder(Cfg.server_port, Cfg.nickname)
		target_host = "127.0.0.1"
		target_port = Cfg.server_port
		client.connect_to("127.0.0.1", Cfg.server_port)
	else:
		# Steam 模式：本进程既是房主也是自己的第一个玩家。房主自己这一路不能用 Steam 回环
		# （实测「发给自己」会被对端当成关闭连接），改走进程内直连（见 LocalServer.接入本地客户端）
		target_host = SteamNet.steam_id
		target_port = 0
		var 本机: SteamClient = client as SteamClient
		server.接入本地客户端(本机, int(SteamNet.steam_id))
		本机.connect_to(SteamNet.steam_id, 0)
	host_started.emit()
	return true


func stop_hosting() -> void:
	if server != null:
		server.stop()
		server = null
	hosting = false
	discovery.stop_all()


# ============================================================
# 加入
# ============================================================
## 连到指定房主。局域网传 host_addr = IP，Steam 模式传 host_addr = 房主 SteamID（port 无意义）
func join_game(host_addr: String, port: int) -> void:
	stop_hosting()
	target_host = host_addr
	target_port = port
	client.auto_reconnect = true
	client.connect_to(host_addr, port)


## 断开并停止自动重连（客户端启动时不盲目连接固定地址）
func idle() -> void:
	client.auto_reconnect = false
	client.close()
	stop_hosting()


# ============================================================
# 搜索
# ============================================================
func search_lan() -> void:
	discovery.start_search(Cfg.nickname)
	discovery.probe_local(Cfg.server_port)


func stop_search() -> void:
	discovery.stop_all()


# ============================================================
# 收发
# ============================================================
## 连接刚建立的一瞬间内部状态可能还是旧的，发包前先同步一次
func send(msg_type: int, fields: Dictionary) -> bool:
	client.sync_status()
	return client.send(msg_type, fields)


func is_connected_to_host() -> bool:
	return client.link_up


# ============================================================
# 内部
# ============================================================
func _on_connected() -> void:
	# 连上后补发一次「登录」：去登录后它只用于上报昵称与身份标识，服务端据此登记身份
	client.send(GConst.Msg.LoginReq, {"as_guest": true, "user_id": Cfg.nickname, "version": 161001, "client_id": Cfg.身份标识()})
	connected.emit()

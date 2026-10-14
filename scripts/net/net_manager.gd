extends Node
## 网络管理（autoload 名：Net）
## 编排「房主 / 加入」两条链路（对照说明文档 3.1 / 3.5）：
##   房主：本进程内起权威服务端，再把自己作为普通客户端连上本机服务端
##   加入：停掉本进程可能的房主身份，把连接目标切到指定房主地址

signal connected
signal disconnected
signal message_received(msg_type: int, data: Dictionary)
## 连续重连到上限仍未成功（底座的同名信号在这里转发一次，上层只认 Net 这一份）
signal reconnect_failed
## 一条上行消息没能发出去（连接断了 / 对端还没确认）：界面据此报错，
## 否则玩家只会看到「点了没反应」（见 send）
signal send_failed(msg_type: int)
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
	# 传输底座按启动模式装配：本地调试 / 局域网联机走局域网 TCP，其余走 Steam P2P
	# （写成 if/else 而不是三元表达式：两个实现类型不同，三元会被判「分支类型不兼容」）
	if Cfg.无Steam():
		client = NetClient.new()
	else:
		client = SteamClient.new()
	client.message_received.connect(func(t: int, d: Dictionary) -> void: message_received.emit(t, d))
	client.connected.connect(_on_connected)
	client.disconnected.connect(func() -> void: disconnected.emit())
	client.reconnect_failed.connect(func() -> void: reconnect_failed.emit())
	# Steam 底座「已开始连向房主、但通道还没通」：登录包要在这一刻就发出去，
	# 通道要靠这条消息本身建起来（见 SteamClient.connect_to / 连接已发起）
	if client is SteamClient:
		(client as SteamClient).连接已发起.connect(_发送登录)


## 每帧推进：收发包、重连、局域网广播。
## 窗口被切到后台 / 最小化时这个函数照旧每帧执行（引擎默认不进低功耗暂停模式，见 project.godot），
## 而心跳的收发与超时判定全都按绝对时刻算（Time.get_ticks_msec），不靠帧数累计 ——
## 所以房主切出游戏后照样和别人保持通信，不会因此被判掉线。
func _process(delta: float) -> void:
	client.poll(delta)
	if server != null:
		server.poll()
	discovery.poll(delta)


# ============================================================
# 房主
# ============================================================
## 起本机服务端（当房主），监听配置里的服务端口（Cfg.server_port）
func host_game() -> bool:
	if hosting:
		return true
	var s: LocalServer = LocalServer.new()
	# 局域网端口：本地调试 / 局域网联机要独占它（同机多开靠端口区分房主）；
	# Steam 模式虽然走 P2P，也用同一个端口接「同一局域网、没登 Steam」的机器（见 MultiServer）
	var err: int = s.start(Cfg.server_port)
	if err != OK:
		push_warning("Net: 监听 %d 失败（%d），本机可能已有房主" % [Cfg.server_port, err])
		host_failed.emit()
		return false
	server = s
	hosting = true
	client.auto_reconnect = true
	if Cfg.无Steam():
		# 本机开房后就不再需要搜索别人（搜索与应答是两条独立通道，这里只停搜索，
		# 下面起的应答通道要一直开着，进房间后别人还搜得到，见 Discovery）
		discovery.stop_search()
		discovery.start_responder(Cfg.server_port, Cfg.nickname, Cfg.游戏版本())
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
		# 服务端都拆了，客户端这条连接必然已经废掉 —— 必须在这里把它静默关干净。
		# 不关的话 Steam 底座会留下「僵尸连接」：P2P 没有底层断连事件，link_up 会一直为真，
		# 上层以为自己还连着，建房 / 进房发出去的消息全被吞掉（界面永远停在「正在创建房间…」）。
		# 用 close()（静默、不发 disconnected）而不是 标记断开()：拆服务端 / 主动退房都不是掉线，
		# 不该弹「与房主的连接已断开」这类提示 —— 需要重新连的调用方自己接着 connect_to
		client.auto_reconnect = false
		client.close()
	hosting = false
	# 退房了就不再应答别人的探测（搜索通道与这里无关，不动）
	discovery.stop_responder()


# ============================================================
# 局域网广播（Steam 模式的房主也要能被「同一局域网、没登 Steam」的机器搜到）
# ============================================================
## 开始向局域网广播「本机有房」。Steam 模式在建房成功后才调（只进大厅、还没开房的玩家不该被搜到）；
## 本地调试 / 局域网联机在开服时就已经在广播了，不必再调。
func 开始局域网广播() -> void:
	if Cfg.无Steam():
		return
	discovery.start_responder(Cfg.server_port, Cfg.nickname, Cfg.游戏版本())


## 停止局域网广播（房主退房 / 关掉房间时调）
func 停止局域网广播() -> void:
	if Cfg.无Steam():
		return
	discovery.stop_responder()


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


## 断开并停止自动重连（回登录界面时用，见 Logic.回登录界面）
func idle() -> void:
	client.auto_reconnect = false
	client.close()
	stop_hosting()
	# 局域网搜索也停掉：回登录界面后没人接 host_found 了，别让 UDP 探测白白继续发
	stop_search()


## 回到大厅的「待机」状态：断开当前那条连接，再按模式重新摆好。
## 为什么不能直接 idle()：Steam 模式进大厅时是「自己当房主 + 连自己」，
## 大厅的建房 / 进房全都建立在这条连接上；把它拆了就会变成
## 「已与房主断开连接，无法建房」。局域网联机则相反 —— 待机就是什么都不连（列表显示搜到的主机）。
func 回到待机() -> void:
	stop_hosting()
	client.auto_reconnect = false
	client.close()
	# 局域网联机：待机就是什么都不连（列表显示的是搜到的主机）
	if Cfg.局域网模式:
		return
	var 起好了: bool = host_game()
	if 起好了:
		return
	# 端口被占起不来：局域网 TCP 上多半是同机另一个窗口当了房主 —— 连过去。
	# Steam 模式绝不能走这条路：它的「地址」是 SteamID，拿回环 IP 去连会指向一个不存在的对端，
	# 白烧一轮「重连失败」提示，还会和 _on_reconnect_failed 反复摆待机形成来回循环；
	# 那种情况就留在「无连接待机」，由界面按需补（见 Logic._补齐待机连接）
	if Cfg.无Steam():
		join_game("127.0.0.1", Cfg.server_port)


# ============================================================
# 搜索
# ============================================================
func search_lan() -> void:
	discovery.start_search()
	discovery.probe_local(Cfg.server_port)


## 停止局域网搜索（只停搜索，本机要是房主，应答通道照旧开着）
func stop_search() -> void:
	discovery.stop_search()


# ============================================================
# 收发
# ============================================================
## 连接刚建立的一瞬间内部状态可能还是旧的，发包前先同步一次。
## 发不出去就发 send_failed 让界面上说一声 —— 静默丢掉的话，玩家看到的只是「点了没反应」。
## 只在「自己以为连着」的时候报（link_up 为真）：正在连接 / 正在等对端确认时本来就不通，
## 那属于「正在连接」，界面另有提示；心跳也不报（它是连接探测本身，逐条报会刷屏）
func send(msg_type: int, fields: Dictionary) -> bool:
	client.sync_status()
	var 连着: bool = client.link_up
	var 发出去: bool = client.send(msg_type, fields)
	if not 发出去 and 连着 and msg_type != GConst.Msg.HeartBeat:
		send_failed.emit(msg_type)
	return 发出去


func is_connected_to_host() -> bool:
	return client.link_up


# ============================================================
# 内部
# ============================================================
func _on_connected() -> void:
	# 局域网 TCP：连上后才发得出登录（未连上时底层写不进去）
	if not (client is SteamClient):
		_发送登录()
	connected.emit()


## 发一次「登录」：上报昵称、身份标识与游戏版本，服务端据此登记身份与认领座位。
## 这条也走 send：发不出去（例如 Steam 通道还没通）同样要在界面上报出来 ——
## 登录是所有人进游戏的必经一步，它悄悄丢了就等于「一直卡在正在进入」。
func _发送登录() -> void:
	send(GConst.Msg.LoginReq, {
		"as_guest": true,
		"user_id": Cfg.nickname,
		"version": 161001,
		"client_id": Cfg.身份标识(),
		"game_version": Cfg.游戏版本(),
	})

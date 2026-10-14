class_name MultiServer
extends NetworkServer
## 服务端传输层的「多路复用」底座：同时挂 Steam P2P 与局域网 TCP 两套底座，
## 把两边的连接汇进同一个权威服务端（LocalServer）。
## 于是 Steam 模式下开的房间，同一局域网里没登 Steam 的机器也能直接连进来。
##
## conn_id 天然不冲突：Steam 底座用对端 SteamID（约 7.6e16 量级），房主自己那条也用本机 SteamID；
## 局域网底座的编号从 1 起。这里按「哪个底座认这条连接」把操作路由过去。

var _steam: SteamServer = null
var _lan: NetServer = null


func listen(p: int, bind_addr: String = "0.0.0.0") -> int:
	_steam = SteamServer.new()
	_接信号(_steam)
	var steam_err: int = _steam.listen(0)
	_lan = NetServer.new()
	_接信号(_lan)
	# 局域网端口占不到（同机已有别的房主等）不算致命：Steam 那条路照旧可用，
	# 只是同局域网的机器连不进来，所以只警告、不让整个开房失败
	var lan_err: int = _lan.listen(p, bind_addr)
	if lan_err != OK:
		push_warning("MultiServer: 局域网监听 %d 失败（%d），Steam 联机不受影响" % [p, lan_err])
	listening = steam_err == OK
	port = p
	return steam_err


## 两个底座的三个契约信号都转发到自己身上：上层（LocalServer）只认这一份
func _接信号(底: NetworkServer) -> void:
	底.client_connected.connect(func(conn_id: int) -> void: client_connected.emit(conn_id))
	底.client_disconnected.connect(func(conn_id: int) -> void: client_disconnected.emit(conn_id))
	底.client_message.connect(
		func(conn_id: int, msg_type: int, data: Dictionary) -> void:
			client_message.emit(conn_id, msg_type, data))


func stop() -> void:
	if _steam != null:
		_steam.stop()
	if _lan != null:
		_lan.stop()
	listening = false


func poll() -> void:
	if _steam != null:
		_steam.poll()
	if _lan != null:
		_lan.poll()


func close_conn(conn_id: int) -> void:
	var 底: NetworkServer = _路由(conn_id)
	if 底 != null:
		底.close_conn(conn_id)


func has_conn(conn_id: int) -> bool:
	return _路由(conn_id) != null


func send(conn_id: int, msg_type: int, fields: Dictionary) -> void:
	var 底: NetworkServer = _路由(conn_id)
	if 底 != null:
		底.send(conn_id, msg_type, fields)


## 房主自己那一路归 Steam 底座（连接号是本机 SteamID），转交给它
func 接入本地客户端(c: SteamClient, conn_id: int) -> void:
	_steam.接入本地客户端(c, conn_id)


## 「靠心跳回声判掉线」只对 Steam 那条成立；局域网连接由 NetServer 自己发现断连
func 靠回声判掉线(conn_id: int) -> bool:
	return _steam.has_conn(conn_id)


func _路由(conn_id: int) -> NetworkServer:
	if _steam.has_conn(conn_id):
		return _steam
	if _lan.has_conn(conn_id):
		return _lan
	return null

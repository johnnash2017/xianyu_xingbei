@abstract
class_name NetworkServer
extends RefCounted
## 服务端传输层契约：房主进程内的权威服务端（LocalServer）用它收发包。
## 两种底座：
##   NetServer   —— 局域网 TCP 监听（多开脚本 / 本地调试）
##   SteamServer —— Steam P2P（SteamNetworkingMessages）
## conn_id 的含义由底座决定：TCP 是自己编的连接号，Steam 是对端的 SteamID。

## 这三个信号是「底座契约」：声明在这里，由各自的实现（NetServer / SteamServer）发出、上层连接。
## 本类自己不发信号，所以关掉「声明了却没用」的提示。
@warning_ignore("unused_signal")
signal client_connected(conn_id: int)
@warning_ignore("unused_signal")
signal client_disconnected(conn_id: int)
@warning_ignore("unused_signal")
signal client_message(conn_id: int, msg_type: int, data: Dictionary)

var listening: bool = false
## 监听端口。Steam 底座不占端口，恒为 0
var port: int = 0


## 开始监听；返回 OK / 错误码
@abstract func listen(p: int, bind_addr: String = "0.0.0.0") -> int


## 停止监听并断开所有连接
@abstract func stop() -> void


## 每帧推进：接受新连接 / 收包 / 断线检测
@abstract func poll() -> void


## 断开某条连接（主动踢人 / 心跳超时）
@abstract func close_conn(conn_id: int) -> void


## 这条连接是否还在
@abstract func has_conn(conn_id: int) -> bool


## 给某条连接发一条消息
@abstract func send(conn_id: int, msg_type: int, fields: Dictionary) -> void


## 接入房主自己那一路客户端（只有 Steam 底座有「本机直连」这回事，见 SteamServer）。
## 局域网 TCP 底座没有这个概念，默认什么都不做。
func 接入本地客户端(_c: SteamClient, _conn_id: int) -> void:
	pass


## 这条连接所在底座有没有「底层断连事件」：Steam P2P 没有，只能靠心跳回声超时判掉线；
## 局域网 TCP 有（底座自己会发现断连），默认返回 false。
func 靠回声判掉线(_conn_id: int) -> bool:
	return false

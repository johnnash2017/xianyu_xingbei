@abstract
class_name NetworkClient
extends RefCounted
## 客户端传输层契约（对照说明文档里「网络底座」那一层）。
## 两种底座：
##   NetClient   —— 局域网 TCP 长连接（多开脚本 / F9、F10、F11 的本地调试）
##   SteamClient —— Steam P2P（SteamNetworkingMessages，按 SteamID 寻址）
## 上层（Net / 界面）只依赖这层，换底座不动房间与对局逻辑。

## 这几个信号是「底座契约」：声明在这里，由各自的实现（NetClient / SteamClient）发出、上层连接。
## 本类自己不发信号，所以关掉「声明了却没用」的提示。
@warning_ignore("unused_signal")
signal connected
@warning_ignore("unused_signal")
signal disconnected
## 连续重连达到上限仍未成功：上层据此提示玩家并返回大厅
@warning_ignore("unused_signal")
signal reconnect_failed
@warning_ignore("unused_signal")
signal message_received(msg_type: int, data: Dictionary)

## 连接是否可用：true 时上层才允许发包
var link_up: bool = false
## 断开后是否自动重连
var auto_reconnect: bool = false


## 连到指定房主。Steam 模式下的「地址」是房主 SteamID 的十进制字符串，port 无意义
@abstract func connect_to(host: String, port: int) -> void


## 关闭连接（并让上层知道断了）
@abstract func close() -> void


## 每帧推进：收包 / 重连 / 超时
@abstract func poll(delta: float) -> void


## 立刻同步一次底层连接状态（TCP 刚连上时内部状态可能还是旧值）
@abstract func sync_status() -> void


## 发一条消息；返回是否发出去
@abstract func send(msg_type: int, fields: Dictionary) -> bool

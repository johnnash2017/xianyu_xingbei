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
## 已经朝目标发出连接请求、可以往外发消息了，但还没真正连上。
## 只有 Steam 底座会发它：Steam P2P 没有「连上了」这个事件，第一条消息本身才把通道建起来，
## 上层必须在这一刻就把登录发出去（等 connected 再发就永远等不到，见 SteamClient）
@warning_ignore("unused_signal")
signal 连接已发起
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


## 上层判定这条连接已经不可用了（服务端心跳静默 / 服务端那侧主动断开）：
## 各底座负责真正断掉底层连接并通知上层，之后交给自动重连继续试（与「底层掉线」同一条路）
@abstract func 标记断开() -> void

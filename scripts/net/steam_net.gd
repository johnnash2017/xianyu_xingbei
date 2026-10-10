extends Node
## Steam 接入（自动加载名 SteamNet）。
## 只在**非本地模式**（裸启动，见 Cfg.本地模式）下真正初始化；多开脚本（F9/F10/F11）完全不碰 Steam。
##
## 目前承担：Steam 初始化 + 身份（SteamID）、Steam 大厅（建房 / 找房）、P2P 会话收发。
## 传输层本体在 SteamClient / SteamServer（SteamNetworkingMessages），这里负责共用的大厅数据与信号接线。
##
## 接口名以本工程所装 GodotSteam 版本实测为准（4.23.1：camelCase，如 steamInit / createLobby）。

## 开发期 App ID：480（SpaceWar）——任何 Steam 账号都能跑，正式发布前换成自己的 AppID。
## 显式传它就不必依赖 steam_appid.txt（那个文件只在「不传 appid」时才需要）。
const 开发期_APPID: int = 480

## Steam 是否已就绪（初始化成功）
var 就绪: bool = false
## 初始化失败原因（只进日志，界面只显示「未登录」这个状态）
var 失败原因: String = ""
## 本机 SteamID（十进制字符串：64 位整数，用字符串过协议不会丢精度）
var steam_id: String = ""
## 掉线检查/重连的间隔（秒）
const 连接检查间隔: float = 1.0
var _检查计时: float = 0.0


func _ready() -> void:
	if Cfg.本地模式:
		return
	# 这些回调只接一次：掉线后会重复走 _初始化，接在里面会重复连同一个信号
	Steam.lobby_match_list.connect(_on_match_list)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	# P2P：对端要建会话就接受；会话建不起来（对端不在线 / 打洞失败）交给客户端底座判定掉线
	Steam.network_messages_session_request.connect(_on_session_request)
	Steam.network_messages_session_failed.connect(_on_session_failed)
	_初始化()


func _process(delta: float) -> void:
	# 本地调试（多开脚本 F9/F10/F11）完全不碰 Steam —— 连「看看客户端在不在」都不问
	if Cfg.本地模式:
		return
	# GodotSteam 要求每帧跑一次回调（大厅结果、P2P 消息都靠它派发）
	if 就绪:
		Steam.run_callbacks()
	# 定时对一次连接：Steam 退出登录 / 被关掉时我们要知道，并等它回来重新接上
	_检查计时 -= delta
	if _检查计时 <= 0.0:
		_检查计时 = 连接检查间隔
		_检查连接()


func _exit_tree() -> void:
	# 退出时显式关掉 Steam API：不关的话 Steam 客户端可能还挂着「正在玩 SpaceWar（480）」。
	# 注意强杀进程（编辑器「停止」按钮就是强杀）不会走到这里，那种情况只能等 Steam 客户端自己刷新。
	if 就绪:
		Steam.steamShutdown()


## 定时检查 Steam 连接：
##   已连上但 Steam 客户端没了（退出登录 / 被关掉）→ 标记掉线，等它回来；
##   没连上但 Steam 客户端在跑（刚登录，或掉线后又重新登录了）→ 重新初始化接上。
func _检查连接() -> void:
	if 就绪:
		if not Steam.isSteamRunning():
			_标记掉线("Steam 已退出登录，正在等待重新登录…")
		return
	if not Steam.isSteamRunning():
		return
	_初始化()


## 初始化 Steam；掉线之后也会重新走这里。失败不致命：只记原因，等下一轮再试
func _初始化() -> void:
	# 这个版本 steamInit 返回 bool；失败细节走 get_steam_init_result()
	if not Steam.steamInit(开发期_APPID, false):
		_记失败原因("Steam 初始化失败（%s）：请确认 Steam 客户端已启动、已登录" % str(Steam.get_steam_init_result()))
		return
	就绪 = true
	失败原因 = ""
	steam_id = str(Steam.get_current_steam_id())
	print("[SteamNet] Steam 已连接，SteamID = %s" % steam_id)
	_重开大厅()


## 标记掉线：与 Steam 会话绑在一起的状态全部作废（大厅、房主信息），等 Steam 回来重连
func _标记掉线(原因: String) -> void:
	就绪 = false
	steam_id = ""
	大厅id = 0
	房主steam_id = ""
	房主房间号 = -1
	Steam.steamShutdown()
	_记失败原因(原因)


## 重新接上 Steam 后：本进程之前要是开着房，就把大厅重新开出来（旧大厅已随掉线一起没了）。
## 房主自己那一路走的是进程内直连，不受影响；这里只管「别人还能不能在列表里搜到这间房」。
func _重开大厅() -> void:
	if 本房房间号 < 0 or _待建房名 == "":
		return
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, _待建人数)


## 失败原因变了才打日志：掉线期间每秒都会重试，逐次刷屏没意义
func _记失败原因(原因: String) -> void:
	if 原因 == 失败原因:
		return
	失败原因 = 原因
	push_warning("[SteamNet] " + 原因)


## 有人要和我们建 P2P 会话：一律接受（正式发布若要限制，可在这里加白名单）
func _on_session_request(remote_steam_id: int) -> void:
	Steam.acceptSessionWithUser(remote_steam_id)


func _on_session_failed(_reason: int, remote_steam_id: int, _connection_state: int, _debug_message: String) -> void:
	P2P会话失败.emit(remote_steam_id)


# ============================================================
# Steam 大厅（Steam 模式下的「找房间」）
# 房间状态全部写在大厅数据里（键都在下面），所以我们自己的房间列表 UI 能原样复用
# ============================================================
## 大厅数据键名：房主写，所有人读
const 键_房名: String = "room_name"
const 键_人数上限: String = "max_player"
const 键_在线人数: String = "now_player"
const 键_座位数: String = "seat_count"
const 键_观战人数: String = "watchers"
const 键_进行中: String = "playing"
## 房主 SteamID：进房后据此建立 P2P 连接（NetworkingMessages 按 SteamID 发消息）
const 键_房主: String = "host"
## 服务端房间号：加入方发进房请求要用（Steam 大厅号与服务端房间号是两回事）
const 键_房间号: String = "server_room"

## 本机所在大厅 id（0 = 不在大厅里）
var 大厅id: int = 0
## 房主 SteamID（进房时从大厅数据读到）
var 房主steam_id: String = ""
## 房主服务端的房间号（加入方读到后发给房主）
var 房主房间号: int = -1
## 房主侧：本房间在服务端里的编号。写进大厅数据用；
## 若「对局广播」早于「大厅创建回调」到达，先记在这，等回调回来补写
var 本房房间号: int = -1
## 正在查询大厅列表：Steam 对查询频率有限流，别连点
var _查询中: bool = false
## 建房时暂存，等 lobby_created 回调回来再写进大厅数据；
## 掉线重连后也靠它把大厅重新开出来（见 _重开大厅）
var _待建房名: String = ""
var _待建人数: int = 0

## 大厅列表就绪：房间信息的形状与局域网那套一致，房间列表 UI 直接复用
signal 大厅列表已就绪(房间列表: Array)
## 进房结果：加入大厅成功时，上层接着把 P2P 连接切到房主（见 Logic._on_steam_join）
signal 进房结果(成功: bool, 说明: String)
## 与某个对端的 P2P 会话建立失败：客户端底座据此判定掉线并重连
signal P2P会话失败(remote_steam_id: int)


## 查询大厅列表（Steam 模式下的「刷新房间列表」）；已在查询中就不重复发，Steam 会限流
func 查询大厅() -> void:
	if not 就绪 or _查询中:
		return
	_查询中 = true
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListResultCountFilter(50)
	Steam.requestLobbyList()


## 大厅列表回调：把每个大厅的大厅数据整理成「房间信息」
func _on_match_list(lobbies: Array) -> void:
	_查询中 = false
	var 列表: Array = []
	for 原始: Variant in lobbies:
		var id: int = int(原始)
		var 房名: String = Steam.getLobbyData(id, 键_房名)
		# 靠「有没有房名」筛掉不是本作开的大厅（距离过滤是全世界的，会混进别的游戏）
		if 房名 == "":
			continue
		列表.append({
			"room_id": id,
			"room_name": 房名,
			"max_player": int(Steam.getLobbyData(id, 键_人数上限)),
			"now_player": int(Steam.getLobbyData(id, 键_在线人数)),
			"seat_count": int(Steam.getLobbyData(id, 键_座位数)),
			"watchers": int(Steam.getLobbyData(id, 键_观战人数)),
			"playing": Steam.getLobbyData(id, 键_进行中) == "1",
			# 大厅数据是所有人共享的，看不出「谁留了座位」；认领座位在 Steam 模式下待接
			"can_reenter": false,
			"role_strategy": 0,
			"seat_mode": 0,
			"allow_guest": true,
		})
	大厅列表已就绪.emit(列表)


## 建房（房主）：开一个公开大厅。人数上限只算「战斗玩家」——
## 观战者不占大厅成员名额，他们只要从大厅数据里拿到房主 SteamID 就能收 P2P 消息
func 建房(房名: String, 人数上限: int) -> void:
	if not 就绪:
		return
	_待建房名 = 房名
	_待建人数 = 人数上限
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 人数上限)


func _on_lobby_created(返回码: int, lobby_id: int) -> void:
	if 返回码 != 1:      # 1 = Steam 的 Result.OK
		push_warning("[SteamNet] 建大厅失败，Steam 返回 %d" % 返回码)
		return
	大厅id = lobby_id
	房主steam_id = steam_id
	Steam.setLobbyData(lobby_id, 键_房主, steam_id)
	Steam.setLobbyData(lobby_id, 键_房名, _待建房名)
	Steam.setLobbyData(lobby_id, 键_人数上限, str(_待建人数))
	# 房间编号可能比对局广播来得晚（建房是异步的）：这时已经先记在 本房房间号 里，补写一次
	if 本房房间号 >= 0:
		Steam.setLobbyData(lobby_id, 键_房间号, str(本房房间号))
	print("[SteamNet] 已建大厅 %d（%s）" % [lobby_id, _待建房名])


## 房主同步房间实况到大厅数据（进人 / 退房 / 开局时由 LocalServer 调），列表上就能看到人数与状态；
## 「房间号」也在里面 —— 加入方拿它发进房请求。大厅还没建好时先记着，建好再补写（见 _on_lobby_created）
func 同步房间数据(房间号: int, 在线人数: int, 座位数: int, 观战人数: int, 进行中: bool) -> void:
	本房房间号 = 房间号
	if 大厅id == 0:
		return
	Steam.setLobbyData(大厅id, 键_房间号, str(房间号))
	Steam.setLobbyData(大厅id, 键_在线人数, str(在线人数))
	Steam.setLobbyData(大厅id, 键_座位数, str(座位数))
	Steam.setLobbyData(大厅id, 键_观战人数, str(观战人数))
	Steam.setLobbyData(大厅id, 键_进行中, "1" if 进行中 else "0")


## 进房（加入方）：加入大厅，并从大厅数据里取房主的 SteamID（P2P 连接下一步用它）
func 进房(大厅号: int) -> void:
	if not 就绪 or 大厅号 == 0:
		return
	Steam.joinLobby(大厅号)


func _on_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		进房结果.emit(false, "加入房间失败（Steam 返回 %d）" % response)
		return
	大厅id = lobby
	房主steam_id = Steam.getLobbyData(lobby, 键_房主)
	房主房间号 = int(Steam.getLobbyData(lobby, 键_房间号))
	进房结果.emit(true, "已加入房间，正在连接房主…")


## 离开大厅（退出房间时调）
func 离开大厅() -> void:
	if 大厅id != 0:
		Steam.leaveLobby(大厅id)
	大厅id = 0
	房主steam_id = ""
	房主房间号 = -1

extends Node
## 对局埋点上报（ThinkingAI / TA 的 RESTful API，raw 方式 /sync_json）。
##
## **谁上报：只有房主进程。** 一场战斗的权威状态只存在于房主的 BattleEngine 里；
## 让 4~6 个客户端各报一份会重复，而且客户端的数据可被改。
##
## **怎么接：引擎不碰网络。** BattleEngine 只把现算好的对局状态交给注入的 telemetry_cb
## （见 LocalServer._建房间），这里负责补上报侧字段、组包、批量、失败重试与落盘续传。
##
## **15 个属性怎么分工**：game_version / report_time / is_test_data 由这里补；
## 其余 12 个（battle_id / player_count / character_details / 双方士气 / 回合数 /
## 双方星杯 / 双方红蓝星石）由 BattleEngine 按对局状态现算。
##
## **什么时候不上报**：headless（自检 / CI），自动化用例不碰网络。
## **测试环境允许上报，但一定带测试标记**：本地调试与局域网模式（Cfg.无Steam()）算测试数据
## （is_test_data = true），Steam 正式对局算生产数据（false）。
##
## 事件名与属性名必须与埋点方案完全一致，而且只能是 ASCII：
## 属性类型在第一次上报时就被后台定死，之后同类事件必须传同样的类型
## （数值别一会儿 int 一会儿 float），类型对不上的那个属性会被直接丢弃。

## 上报地址与项目 APPID（「星杯传说」项目 352957）
const 上报地址: String = "https://ae-receiver.thinkingai.cn/sync_json"
const APPID: String = "33862e75ba494708b864ade41165d7fc"

## 单次请求最多带多少条（接口建议不超过 1000 条；一场对局只有几十条）
const 批量上限: int = 200
## 内存队列上限：满了丢最旧的 —— 上报是旁路，服务端挂了也不能把内存吃光
const 队列上限: int = 2000
## 攒批间隔（秒）：到点就把队列里的发出去，对局结束那条不用等太久
const 发送间隔秒: float = 3.0
## 失败后隔多久再试（一场对局事件量很小，固定 5 秒即可，不做指数退避）
const 重试间隔秒: float = 5.0
## 没发出去的事件落盘，下次启动续传（客户端数据的接收窗口只有前 10 天，别长期积压）
const 缓存路径: String = "user://telemetry_pending.json"

var _待发: Array = []
## 本次请求带出去的条数：成功回来才知道该从队头删多少
var _在途条数: int = 0
var _发送中: bool = false
## 下次允许发送的时刻（毫秒，Time.get_ticks_msec 口径）
var _下次可试时刻: float = 0.0
var _累计秒: float = 0.0
var _http: HTTPRequest = null


func _ready() -> void:
	# 切后台 / 暂停时也要把攒着的发出去
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_请求完成)
	_读缓存()


func _process(delta: float) -> void:
	if _待发.is_empty():
		return
	_累计秒 += delta
	if _累计秒 < 发送间隔秒:
		return
	_累计秒 = 0.0
	_发送()


## 上报一条对局事件（battle_start / round_end / battle_end）。
## 属性由 BattleEngine 按当前对局状态现算好传进来，这里补上报侧字段再包成 TA 的数据格式。
func 记录对局事件(事件名: String, 属性: Dictionary) -> void:
	if not _应上报():
		return
	# 上报侧的三个属性在这里补；引擎交过来的是一份新字典，直接往里加即可
	属性["game_version"] = Cfg.游戏版本()
	属性["report_time"] = _时间文本(false)
	属性["is_test_data"] = _是测试数据()
	var 身份: String = Cfg.身份标识()
	_待发.append({
		"appid": APPID,
		"data": {
			"#type": "track",
			"#event_name": 事件名,
			"#time": _时间文本(true),
			# 一场战斗只有一个「用户」：报给发起对局的房主；整场的人员名单在 character_details 里
			"#account_id": 身份,
			"#distinct_id": 身份,
			"properties": 属性,
		},
	})
	if _待发.size() > 队列上限:
		_待发 = _待发.slice(_待发.size() - 队列上限)
	# 每条都落一次盘：玩家打完直接关窗口时，攒着没发的那几条才不会丢（每场对局只有几十条，开销可忽略）
	_写缓存()
	if _待发.size() >= 批量上限:
		_发送()


## headless（自检 / CI）不上报：自动化用例不碰网络
func _应上报() -> bool:
	return DisplayServer.get_name() != "headless"


## 本地调试 / 局域网模式算测试环境：允许上报，但必须带 is_test_data = true
func _是测试数据() -> bool:
	return Cfg.无Steam()


func _发送() -> void:
	if _发送中 or _待发.is_empty():
		return
	if float(Time.get_ticks_msec()) < _下次可试时刻:
		return
	var 批: Array = _待发.slice(0, mini(_待发.size(), 批量上限))
	var 头: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	var err: int = _http.request(上报地址, 头, HTTPClient.METHOD_POST, JSON.stringify(批))
	if err != OK:
		_失败()
		return
	_发送中 = true
	_在途条数 = 批.size()


func _请求完成(result: int, 响应码: int, _头: PackedStringArray, 响应体: PackedByteArray) -> void:
	_发送中 = false
	if result != HTTPRequest.RESULT_SUCCESS or 响应码 != 200:
		# 网络 / 服务端临时故障：留住这批，过几秒重发
		_失败()
		return
	var 响应: Variant = JSON.parse_string(响应体.get_string_from_utf8())
	if not (响应 is Dictionary):
		# 返回体不是 JSON（代理 / 网关的错误页）：同样当临时故障重试
		_失败()
		return
	var 码: int = int((响应 as Dictionary).get("code", -1))
	if 码 != 0:
		# 数据本身被拒（属性名 / 类型不对）：重发也不会变好，丢掉这几条让后面的继续走。
		# 单独排查时把 debug 打开重打一条，返回里会逐条说明是哪个属性不对
		push_warning("[Telemetry] 上报被拒（code=%d）：%s" % [码, 响应体.get_string_from_utf8()])
	_丢弃在途()
	_下次可试时刻 = 0.0
	_写缓存()


## 请求已处理完（成功或数据被拒）：从队头删掉这批
func _丢弃在途() -> void:
	_待发 = _待发.slice(mini(_在途条数, _待发.size()))
	_在途条数 = 0


func _失败() -> void:
	_在途条数 = 0
	_下次可试时刻 = float(Time.get_ticks_msec()) + 重试间隔秒 * 1000.0
	_写缓存()


## #time（数据时间）带毫秒；report_time 按约定的 datetime 写秒级
func _时间文本(含毫秒: bool) -> String:
	var 时间: Dictionary = Time.get_datetime_dict_from_system()
	var 文本: String = "%04d-%02d-%02d %02d:%02d:%02d" % [
		时间.year, 时间.month, 时间.day, 时间.hour, 时间.minute, 时间.second]
	if not 含毫秒:
		return 文本
	var 秒: float = Time.get_unix_time_from_system()
	return 文本 + ".%03d" % int((秒 - floor(秒)) * 1000.0)


func _读缓存() -> void:
	if not FileAccess.file_exists(缓存路径):
		return
	var 文件: FileAccess = FileAccess.open(缓存路径, FileAccess.READ)
	if 文件 == null:
		return
	var 文本: String = 文件.get_as_text()
	var 解析: Variant = JSON.parse_string(文本)
	if 解析 is Array:
		_待发 = (解析 as Array).duplicate()


func _写缓存() -> void:
	if _待发.is_empty():
		var 目录: DirAccess = DirAccess.open("user://")
		if 目录 != null:
			目录.remove(缓存路径.get_file())
		return
	var 文件: FileAccess = FileAccess.open(缓存路径, FileAccess.WRITE)
	if 文件 == null:
		return
	文件.store_string(JSON.stringify(_待发))

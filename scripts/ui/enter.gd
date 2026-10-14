extends Control
## 登录界面（去登录：只收昵称）
## 对照参考项目 LoginBox 的局域网改造思路：
##   登录界面只做两件事 —— 收昵称 + 接上服务端；**不建房、不找房间**（那两件事都在大厅里做）。
## 接服务端的方式：本机已经有服务端就连它；没有就自己起一个；端口被同机另一个窗口占了就连 127.0.0.1。
## 界面结构全部在 enter.tscn 里（可在编辑器里所见即所得地改），本脚本只绑节点 + 跑逻辑。
## 连接进度与失败不再往界面上的 Label 写文字：失败时只把「进入游戏」恢复可点，玩家可再点一次重试。

@export var 昵称输入: LineEdit
@export var 进入按钮: Button
@export var 设置按钮: Button
## 底部那行 Steam 连接状态（本地调试模式下整行隐藏）
@export var Steam状态: Label
## 左下角的版本号（文字在 _ready 里用 Cfg.游戏版本() 填，来源是 project.godot，别在场景里写死）
@export var 版本标签: Label
## 登录卡片里的提示行（Steam 没连上时点「进入游戏」在这里写原因；平时隐藏）
@export var 提示: Label

## 防止连点「进入游戏」导致重复开服/连接
var _进入中: bool = false
## Steam 模式下点过「进入游戏」但 Steam 还没连上：连上后自动补进一次（见 _同步Steam昵称）
var _等Steam进入: bool = false


func _ready() -> void:
	UI.register(self)
	Net.connected.connect(_on_connected)
	Net.client.reconnect_failed.connect(_on_reconnect_failed)
	昵称输入.text_submitted.connect(func(_t: String) -> void: _on_enter_pressed())
	进入按钮.pressed.connect(_on_enter_pressed)
	设置按钮.pressed.connect(UI.切换设置)
	if Cfg.本地模式:
		# 本地调试：昵称必填（用来区分多个窗口），回填上次的昵称并聚焦
		昵称输入.text = Cfg.nickname
		昵称输入.grab_focus()
		# 光标停在昵称末尾：LineEdit 默认把光标放在第 0 列，回填上次昵称后
		# 看起来像要往名字最前面插字（同 lobby.gd 打开建房时的处理）
		昵称输入.caret_column = 昵称输入.text.length()
	else:
		# Steam 模式：昵称由 Steam 账号决定，输入框只做只读显示，禁止手输。
		# 玩家名是异步到的：没到之前点「进入游戏」会给出「未连接 Steam 网络」提示
		昵称输入.editable = false
		昵称输入.placeholder_text = "正在读取 Steam 昵称…"
		_同步Steam昵称()
	_设标题昵称(Cfg.nickname)
	版本标签.text = "版本 %s" % Cfg.游戏版本()


## 底部那行 Steam 连接状态：每帧对一次（登录界面就能看到连没连上）
func _process(_delta: float) -> void:
	UI.刷新Steam状态(Steam状态)
	# Steam 登录是异步的，玩家名到得晚：到了就补进只读输入框
	if not Cfg.本地模式:
		_同步Steam昵称()


## Steam 模式：把 Steam 玩家名同步进只读输入框与窗口标题。
## 名字到了 = Steam 已连上：清掉「未连接」提示；若刚才点过「进入游戏」，这时补进一次
func _同步Steam昵称() -> void:
	if SteamNet.玩家名 == "" or 昵称输入.text == SteamNet.玩家名:
		return
	昵称输入.text = SteamNet.玩家名
	_设标题昵称(SteamNet.玩家名)
	提示.visible = false
	if _等Steam进入:
		_等Steam进入 = false
		_on_enter_pressed()


## 本次要用的昵称：Steam 模式 = Steam 玩家名（不可手输）；本地调试 = 输入框内容
func _取昵称() -> String:
	if Cfg.本地模式:
		return 昵称输入.text.strip_edges()
	return SteamNet.玩家名


## 把昵称写进全局：本地调试持久化（下次仍预填），Steam 模式只改本次运行
## （不覆盖 config 里本地调试用的昵称，免得 F9 多开时预填成 Steam 名）
func _应用昵称(名: String) -> void:
	if Cfg.本地模式:
		Cfg.set_nickname(名)
	else:
		Cfg.nickname = 名
	Data.nick_name = Cfg.nickname


func _设标题昵称(名: String) -> void:
	var 尾: String = "（%s）" % 名 if 名 != "" else ""
	get_window().title = "星杯传说 — 窗口%d%s" % [Cfg.slot + 1, 尾]


# ============================================================
# 「进入游戏」：接上服务端（本机有就连、没有就开一个、端口被占就连本机房主）
# ============================================================
func _on_enter_pressed() -> void:
	if not Cfg.本地模式 and SteamNet.玩家名 == "":
		# Steam 还没连上：这次不进，给出明确提示；连上后自动补进一次（见 _同步Steam昵称）
		_等Steam进入 = true
		提示.text = "未连接 Steam 网络：请先启动并登录 Steam 客户端，连接成功后会自动进入"
		提示.visible = true
		return
	var 名: String = _取昵称()
	if 名 == "":
		if Cfg.本地模式:
			昵称输入.grab_focus()
		return
	if _进入中:
		return
	_进入中 = true
	进入按钮.disabled = true
	_应用昵称(名)
	_设标题昵称(名)
	# 已经在当房主（例如从大厅返回）：不需要重开，直接等连接
	if Net.hosting and Net.is_connected_to_host():
		UI.goto_lobby()
		return
	if not Net.hosting:
		# host_game 失败 = 本机端口已被另一个窗口占用 → 连那个窗口当房主
		if not Net.host_game():
			Net.join_game("127.0.0.1", Cfg.server_port)
	_等待连接()


## 等待连接建立（最多 6 秒）：连不上就把按钮恢复可点，让玩家能重试
func _等待连接() -> void:
	var 计时: float = 0.0
	while 计时 < 6.0 and not Net.is_connected_to_host():
		await get_tree().create_timer(0.1).timeout
		计时 += 0.1
	if Net.is_connected_to_host():
		return
	_进入中 = false
	进入按钮.disabled = false


func _on_connected() -> void:
	_进入中 = false
	UI.goto_lobby()


func _on_reconnect_failed() -> void:
	_进入中 = false
	进入按钮.disabled = false

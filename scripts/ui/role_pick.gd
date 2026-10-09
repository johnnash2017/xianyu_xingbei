extends Control
## 选角界面（弹层）
## 由 Logic 收到服务端 RoleReq 后实例化并叠在当前界面之上。
## 版面照搬参照工程的 RoleChoose31：全屏压黑遮罩 + 屏幕正中的候选面板（大立绘卡，一行 6 张、多的换行）
## + 面板上方的标题 + 面板下方的提示条（ui_notice 底图）。
## 点一下立绘即选定（参照工程就是这么做的，没有「确定」按钮）；选定后只留自己选中的那张卡。
## 遮罩/面板/标题/提示条等结构都在 role_pick.tscn 里（可所见即所得地改），
## 本脚本只负责「每个角色一张卡」这类动态内容与点击。

## 候选卡尺寸（与参照工程一致：立绘原图 260x363）
const ROLE_BTN_W: float = 260.0
const ROLE_BTN_H: float = 363.0
## 一行摆几张、面板最多显示几行（多于这个行数就滚动）
## 可见行数故意取小数（2.2）：填满时多露出第三行顶部，提示玩家还能向下滚动
const 每行张数: int = 6
const 可见行数: float = 2.2
## 面板宽（一行 每行张数 张卡正好铺满）
const 面板宽: float = ROLE_BTN_W * 每行张数
## 顶部座位条上的座位格尺寸（与 SeatMain.png / SeatBlue.png 一致）
const 座次格宽: float = 32.0
const 座次条高: float = 37.0
## 座位格里那层小队色菱形的尺寸（SeatBlue.png / SeatRed.png 原始尺寸）
const 座次内格宽: float = 26.0
const 座次内格高: float = 30.0
## 座位条自己画的横轨（照参照工程座位条的双线）：线粗、上下线 y、颜色
const 轨道线粗: float = 2.0
const 轨道上线y: float = 13.0
const 轨道下线y: float = 22.0
const 轨道色: Color = Color(0.78, 0.8, 0.88, 0.6)

# ---- 当前 RoleReq 数据 ----
var _strategy: int = 0
var _ask_id: int = -1
var _role_ids: Array[int] = []
## 是否轮到自己选（没轮到自己时卡片不可点）
var _interactive: bool = false

# ---- 场景里绑定的界面节点（结构在 role_pick.tscn 里，可所见即所得地改） ----
@export var 标题: Label
@export var 提示: Label
## 选角倒计时进度条（剩余时间由服务端在 RoleReq 里下发）
@export var 倒计时: ProgressBar
## 顶部「座位顺序」条：座位菱形的容器
@export var 座次条: Control
## 卡片容器：卡片由脚本按行列手动摆放（容器排不出「一行张数不足时居中」）
@export var 卡片区: Control
## 卡片外面的滚动框：高度按候选行数在脚本里改
@export var 滚动: ScrollContainer

## 自己是否已经提交过（提交后只留自己选中的那张卡）
var _已提交: bool = false
## 自己提交的角色 id
var _已选角色: int = -1
## 角色卡的悬浮说明框：与战斗界面同款（底板 / 排版 / 加宽与缩小兜底都在 说明提示框 里）
var _说明提示: 说明提示框 = null
## 倒计时剩余 / 总时长（毫秒），来自服务端 RoleReq 的 wait_ms / wait_total_ms
var _剩余毫秒: float = 0.0
var _总毫秒: float = 0.0


func _ready() -> void:
	# 说明框的宿主：照战斗界面同款坐标系（1280×720、缩放 1.5）——
	# 说明提示框 里的尺寸常量都是按这套坐标调的，这样选角与战斗的排版、字号完全一致
	var 说明宿主: Control = Control.new()
	说明宿主.size = Vector2(1280.0, 720.0)
	说明宿主.scale = Vector2.ONE * 1.5
	说明宿主.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(说明宿主)
	_说明提示 = 说明提示框.new()
	说明宿主.add_child(_说明提示)
	# 选将结束后（对局开始）自动关闭
	Logic.game_info_updated.connect(_on_game_info)


## 倒计时进度条：每秒把剩余时长减掉（到 0 就停住，收尾由服务端负责）
func _process(delta: float) -> void:
	if _剩余毫秒 <= 0.0:
		return
	_剩余毫秒 = maxf(_剩余毫秒 - delta * 1000.0, 0.0)
	倒计时.value = _剩余毫秒


# ============================================================
# 对外接口
# ============================================================
## 应用（或更新）一条 RoleReq 数据；重复收到时复用本实例刷新内容，避免叠层
func apply_request(data: Dictionary) -> void:
	_strategy = int(data.get("strategy", 0))
	_ask_id = int(data.get("id", -1))
	_role_ids.clear()
	var raw_roles: Array = data.get("role_ids", [])
	for rid: int in raw_roles:
		_role_ids.append(rid)
	_interactive = _ask_id == Logic.my_player_id
	# 倒计时（服务端下发的剩余时长）：进度条由 _process 每秒递减
	_总毫秒 = float(data.get("wait_total_ms", 0))
	_剩余毫秒 = float(data.get("wait_ms", 0))
	倒计时.visible = _总毫秒 > 0.0
	倒计时.max_value = _总毫秒
	倒计时.value = _剩余毫秒
	if _interactive:
		# 轮到自己：清掉上一次的提交状态，重新铺满候选
		_已提交 = false
		_已选角色 = -1
	# 只有轮到自己时才提示，避免重发快照反复响（对照参考项目 ChooseRole → sys-turn）
		Audio.播音效("sys-turn")
	_refresh()


# ============================================================
# 刷新内容
# ============================================================
func _refresh() -> void:
	标题.text = _mode_title()
	提示.text = _status_text()
	_刷新座次()

	# 卡片要重建，挂着的说明先收掉（它按旧卡片的位置摆，留着会飘在空处）
	_说明提示.收起()
	for c: Node in 卡片区.get_children():
		卡片区.remove_child(c)
		c.queue_free()
	# 卡片按「一行 每行张数 张」手动摆；一行张数不足时（任意选的最后一行）在这一行里居中。
	# 摆不下就滚动：可见区域最多 可见行数 行高，面板宽度固定。
	var 张数: int = _role_ids.size()
	var 行数: int = maxi(1, ceili(float(张数) / 每行张数))
	滚动.custom_minimum_size = Vector2(面板宽, minf(float(行数), 可见行数) * ROLE_BTN_H)
	卡片区.custom_minimum_size = Vector2(面板宽, 行数 * ROLE_BTN_H)
	for i: int in range(张数):
		var btn: Button = _build_role_button(_role_ids[i])
		卡片区.add_child(btn)
		@warning_ignore("integer_division")
		var 行: int = i / 每行张数
		var 本行张数: int = mini(每行张数, 张数 - 行 * 每行张数)
		btn.position = Vector2(
			(面板宽 - 本行张数 * ROLE_BTN_W) * 0.5 + (i % 每行张数) * ROLE_BTN_W,
			行 * ROLE_BTN_H)
	# 自己已经提交过：只留自己选中的那张卡
	if _已提交:
		_只留选中卡()


## 顶部「座位顺序」条：按服务端下发的座位顺序（Game 快照里 player_infos 的顺序）摆座位菱形，
## 自己那格用黄框 SeatMain，其余按队伍蓝/红；几个玩家就摆几格，在整条上均匀铺开。
## 轨道自己画：参照工程那张 b09_seat_1.png 里固定画了 6 个空位菱形，
## 人数不是 6 时（比如 2V2）会多出空位，所以不用它，改成自画双线横轨 + 只摆在场的玩家。
func _刷新座次() -> void:
	for c: Node in 座次条.get_children():
		座次条.remove_child(c)
		c.queue_free()
	var 条宽: float = 座次条.custom_minimum_size.x
	for 线y: float in [轨道上线y, 轨道下线y]:
		var 轨: ColorRect = ColorRect.new()
		轨.color = 轨道色
		轨.position = Vector2(0.0, 线y)
		轨.size = Vector2(条宽, 轨道线粗)
		轨.mouse_filter = Control.MOUSE_FILTER_IGNORE
		座次条.add_child(轨)
	var infos: Array = Data.game_info.get("player_infos", [])
	var 人数: int = infos.size()
	if 人数 <= 0:
		return
	var 间距: float = 0.0 if 人数 <= 1 else (条宽 - 座次格宽) / float(人数 - 1)
	for i: int in range(人数):
		var 数据: Dictionary = infos[i]
		var 队: int = int(数据.get("team", GConst.TEAM_NONE))
		var 是我: bool = int(数据.get("id", -1)) == Logic.my_player_id
		var 格: TextureRect = TextureRect.new()
		格.position = Vector2(i * 间距, 0.0)
		格.size = Vector2(座次格宽, 座次条高)
		格.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		格.texture = Art.ui(_座次贴图名(队, 是我))
		if not 是我 and 队 < 0:
			# 未分队：没有灰色的座位图，借蓝色的形状调灰
			格.self_modulate = Color(0.6, 0.6, 0.64, 1.0)
		座次条.add_child(格)
		if 队 < 0:
			continue
		var 内格: TextureRect = TextureRect.new()
		内格.position = Vector2((座次格宽 - 座次内格宽) * 0.5, (座次条高 - 座次内格高) * 0.5)
		内格.size = Vector2(座次内格宽, 座次内格高)
		内格.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		内格.texture = Art.ui(_座次贴图名(队, false))
		格.add_child(内格)


## 座位菱形的贴图名：自己用黄框 SeatMain，其余按队伍蓝/红
func _座次贴图名(队: int, 是我: bool) -> String:
	if 是我:
		return "SeatMain"
	return "SeatRed" if 队 == GConst.RED else "SeatBlue"


## 一张角色卡：整张立绘（无边框、无名字，角色名与技能在悬浮说明里）
func _build_role_button(rid: int) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(ROLE_BTN_W, ROLE_BTN_H)
	btn.size = Vector2(ROLE_BTN_W, ROLE_BTN_H)
	btn.flat = true
	btn.set_meta("role_id", rid)
	btn.pressed.connect(_on_role_pressed.bind(rid))
	btn.disabled = not _interactive

	# 悬停说明（角色名一行 + 技能说明，含 BBCode）走界面自己的 说明提示框 —— 与战斗界面同款；
	# 不用引擎自带 tooltip：它跟着光标走、贴近屏幕边会顶出去，排版也不好和战斗对齐
	btn.mouse_entered.connect(_悬停角色卡.bind(btn, rid))
	btn.mouse_exited.connect(_说明提示.收起)

	var face_size: Vector2 = Vector2(ROLE_BTN_W, ROLE_BTN_H)
	var face_tex: Texture2D = Art.role_hero(rid)
	if face_tex != null:
		var face: TextureRect = TextureRect.new()
		face.texture = face_tex
		face.size = face_size
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 大立绘（260x363）正好铺满；按比例放大裁切填满
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 还没轮到自己时把立绘压暗，表示点不动
		if not _interactive:
			face.modulate = Color(0.62, 0.62, 0.62, 1.0)
		btn.add_child(face)
	else:
		# 立绘缺失（尚无素材的角色）：用深色占位块，避免格子出现空洞
		var hole: ColorRect = ColorRect.new()
		hole.color = Color(0.18, 0.19, 0.24, 1.0)
		hole.size = face_size
		hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(hole)
	return btn


## 悬停某张角色卡：弹出战斗同款的角色技能说明
func _悬停角色卡(按钮: Button, rid: int) -> void:
	_说明提示.显示角色说明(rid, 按钮.get_global_rect())


func _mode_title() -> String:
	return "请选择角色" if _interactive and not _已提交 else "选角"


func _status_text() -> String:
	if _interactive and not _已提交:
		return "点一下立绘即选定"
	return "等待其他玩家选择角色…"


# ============================================================
# 交互
# ============================================================
## 点一下立绘就选定并上行（参照工程 RoleChoose31 的点击回调）
func _on_role_pressed(rid: int) -> void:
	Art.play_sfx("Equip")
	Logic.send_pick(_strategy, [rid])
	_set_submitted(rid)


## 已提交：锁定界面，只留下自己选中的那张卡，等对局开始
func _set_submitted(rid: int) -> void:
	_已提交 = true
	_已选角色 = rid
	for c: Node in 卡片区.get_children():
		if c is Button:
			(c as Button).disabled = true
	标题.text = _mode_title()
	提示.text = _status_text()
	_只留选中卡()


## 只留下自己选中的那张卡，并把它摆到面板正中（参照工程 RoleChoose31 的同名处理）
func _只留选中卡() -> void:
	var 选中: Button = null
	for c: Node in 卡片区.get_children():
		var b: Button = c as Button
		if int(b.get_meta("role_id", -1)) == _已选角色:
			选中 = b
		else:
			b.visible = false
	if 选中 == null:
		return
	# 面板收成一行高，把这唯一一张卡摆到正中（参照工程选定后面板也只剩一张卡那么大）
	滚动.custom_minimum_size = Vector2(面板宽, ROLE_BTN_H)
	卡片区.custom_minimum_size = Vector2(面板宽, ROLE_BTN_H)
	选中.position = Vector2((面板宽 - ROLE_BTN_W) * 0.5, 0.0)


func _on_game_info(info: Dictionary) -> void:
	if bool(info.get("is_started", false)):
		if Logic.role_pick_layer == self:
			Logic.role_pick_layer = null
		queue_free()

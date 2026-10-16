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
## 滚轮一格滚多少像素：整屏滚轮都滚候选列表（见 _input），一格约半行比较跟手
const 滚轮步长: float = ROLE_BTN_H * 0.5
## 面板宽（一行 每行张数 张卡正好铺满）
const 面板宽: float = ROLE_BTN_W * 每行张数
## 座次格预制体（挂 scripts/ui/SeatCell.gd，三种座位外观在场景里绑定）
const 座位格预制: PackedScene = preload("res://scenes/prefabs/ui/SeatCell.tscn")
## 角色卡预制体（挂 scripts/ui/RoleCard.gd）
const 角色卡预制: PackedScene = preload("res://scenes/prefabs/ui/RoleCard.tscn")
## 顶部座位条上的座位格宽度（与 SeatCell.tscn 里的格宽一致，算格间距要用）
const 座次格宽: float = 32.0

# ---- 当前 RoleReq 数据 ----
var _strategy: int = 0
var _ask_id: int = -1
var _role_ids: Array[int] = []
## 是否轮到自己选（没轮到自己时卡片不可点）
var _interactive: bool = false

# ---- 场景里绑定的界面节点（结构在 role_pick.tscn 里，可所见即所得地改） ----
@export var 标题: Label
## 底部提示那块底板（ui_notice）：没话可说时连它一起收掉，免得留个空框
@export var 提示条: TextureRect
@export var 提示: Label
## 选角倒计时进度条（剩余时间由服务端在 RoleReq 里下发）
@export var 倒计时: ProgressBar
## 锁定（收尾等开局那段锁定时间）时顶在倒计时位置上的那行字：「即将开始…」
@export var 即将开始文本: Label
## 顶部「座位顺序」条（整行：标签 + 座次条；全角色预览时整行收起来）
@export var 座次行: HBoxContainer
## 顶部「座位顺序」条：座位菱形的容器
@export var 座次条: Control
## 座次条里摆座位格的那层（横轨是场景里的静态装饰，不跟着刷新）
@export var 座位层: Control
## 卡片容器：卡片由脚本按行列手动摆放（容器排不出「一行张数不足时居中」）
@export var 卡片区: Control
## 卡片外面的滚动框：高度按候选行数在脚本里改
@export var 滚动: ScrollContainer
## 「返回」按钮：只有全角色预览（从设置窗进来）才显示，点了把这一层收掉
@export var 返回按钮: Button
## 底部「立即开始（x/X）」：点了＝我可以开始了（服务端记「已准备」），全部人就绪就直接结束选角。
## 点过之后照样能改选（见 _on_ready_pressed）
@export var 准备按钮: Button
## 角色卡的悬浮说明框（与战斗界面同款；结构在 TipBox.tscn 里，见 说明提示框）
@export var 说明提示: 说明提示框

## 是不是「全角色预览」（设置窗里进来的那条路，见 进入全角色预览）：
## 是的话不选人、不收快照影响，只铺出来给人看
var _预览模式: bool = false

## 自己当前点选的角色号（-1 ＝ 还没点过）：点别的立绘就换过去（见 _on_role_pressed）
var _已选角色: int = -1
## 这一轮选角是否已经锁住：倒计时归零（或服务端发来「剩余 0」那条收尾请求）后不再能改选。
## 服务端那边收尾后还要再等一会儿才真正开局（见 local_server.选角收尾等待毫秒）
var _锁定: bool = false
## 倒计时剩余 / 总时长（毫秒），来自服务端 RoleReq 的 wait_ms / wait_total_ms
var _剩余毫秒: float = 0.0
var _总毫秒: float = 0.0


func _ready() -> void:
	# 选将结束后（对局开始）自动关闭
	Logic.game_info_updated.connect(_on_game_info)
	返回按钮.pressed.connect(_on_back_pressed)
	准备按钮.pressed.connect(_on_ready_pressed)


## 倒计时进度条：每秒把剩余时长减掉；归零＝本轮选角结束，把立绘锁住等开局（收尾由服务端负责）
func _process(delta: float) -> void:
	if _剩余毫秒 <= 0.0:
		return
	_剩余毫秒 = maxf(_剩余毫秒 - delta * 1000.0, 0.0)
	倒计时.value = _剩余毫秒
	if _剩余毫秒 <= 0.0:
		# 倒计时归零＝本轮选角结束：锁住立绘、只留自己那张，等开局
		# （服务端那边还要等一会儿才真正开局，见 local_server.选角收尾等待毫秒）
		_锁定 = true
		_锁定界面()


## 滚轮：屏幕任何位置都能滚候选列表，不用先把光标放到列表上。
## 在 _input 里处理并吃掉事件 —— ScrollContainer 自己那套滚轮就不会再触发，
## 全屏只有这一份滚动逻辑，滚在哪儿手感都一致
func _input(事件: InputEvent) -> void:
	var 滚: InputEventMouseButton = 事件 as InputEventMouseButton
	if 滚 == null or not 滚.pressed:
		return
	var 方向: int = 0
	if 滚.button_index == MOUSE_BUTTON_WHEEL_UP:
		方向 = -1
	elif 滚.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		方向 = 1
	else:
		return
	# 越界由 ScrollContainer 自己夹住（滚到头就停）
	滚动.scroll_vertical = 滚动.scroll_vertical + 方向 * int(滚轮步长)
	get_viewport().set_input_as_handled()


# ============================================================
# 对外接口
# ============================================================
## 全角色预览（设置窗里点「全角色预览」进来）：复用选角这套版式，把整张角色表铺出来给玩家翻看。
## 与选角流程的差别：候选＝启用中的全部角色（Data.role_pool，不是本次的候选）、
## 座次条与倒计时收起来、点立绘不选人（只留悬停看技能说明）、右下多一颗「返回」。
## 本层是叠在设置浮层之上的一层（见 settings.gd），返回时把自己收掉即可
func 进入全角色预览() -> void:
	_预览模式 = true
	_interactive = false
	_锁定 = false
	_已选角色 = -1
	_role_ids.clear()
	for rid: int in Data.role_pool:
		_role_ids.append(rid)
	座次行.visible = false
	倒计时.visible = false
	返回按钮.visible = true
	_refresh()


## 点「返回」：收掉这一层，露出下面的设置面板（只有预览模式才有这颗按钮）
func _on_back_pressed() -> void:
	if _预览模式:
		queue_free()


## 应用（或更新）一条 RoleReq 数据；重复收到时复用本实例刷新内容，避免叠层
func apply_request(data: Dictionary) -> void:
	_strategy = int(data.get("strategy", 0))
	_ask_id = int(data.get("id", -1))
	_role_ids.clear()
	var raw_roles: Array = data.get("role_ids", [])
	for rid: int in raw_roles:
		_role_ids.append(rid)
	_interactive = _ask_id == Logic.my_player_id
	# 倒计时（服务端下发的剩余时长）：进度条由 _process 每秒递减。
	# 剩余 0 ＝ 服务端已经收尾（名单定了、界面锁住，等一会儿后开局）——
	# 收尾时会给每个人补发一条「剩余 0」的选角请求，锁的判定就放在这里：
	# 不管谁先选完，大家都同时锁住，也不会出现「界面还能点、服务端已经不理」的错位
	_总毫秒 = float(data.get("wait_total_ms", 0))
	_剩余毫秒 = float(data.get("wait_ms", 0))
	_锁定 = _剩余毫秒 <= 0.0
	# 锁住（收尾等开局那段锁定时间）时不摆倒计时：进度条已经走完，留着只剩一根空槽
	倒计时.visible = _总毫秒 > 0.0 and not _锁定
	倒计时.max_value = _总毫秒
	倒计时.value = _剩余毫秒
	# 重连补发时服务端会带上「我已经选过的角色」（picked_role）：直接把那张的黄框亮起来
	var 已选: int = int(data.get("picked_role", 0))
	if 已选 > 0:
		_已选角色 = 已选
	# 只有「轮到自己开始选」那一下响一次，避免重发快照反复响（对照参考项目 ChooseRole → sys-turn）；
	# 收尾那条（倒计时 0）不响：那不是轮到你选，而是锁住等待开局
	if _interactive and not _锁定:
		Audio.播音效("sys-turn")
	_refresh()


# ============================================================
# 刷新内容
# ============================================================
func _refresh() -> void:
	_刷新文案()
	_刷新座次()

	# 卡片要重建，挂着的说明先收掉（它按旧卡片的位置摆，留着会飘在空处）
	说明提示.收起()
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
	# 已经点选过：给那张亮起黄框（其余照旧摆着 —— 随时可以点别的立绘改选，见 _on_role_pressed）
	_标记选定卡()
	# 锁定期重建卡片（如断线重连补发的那条收尾请求）：直接按锁定版面摆
	if _锁定:
		_应用锁定外观()


## 把「已点选的那张」的黄框点亮、其余熄灭（改选、重连补发、重建卡片都走这里）
func _标记选定卡() -> void:
	for c: Node in 卡片区.get_children():
		var b: 角色卡 = c as 角色卡
		if b != null:
			b.设置选中(int(b.get_meta("role_id", -1)) == _已选角色)


## 顶部标题 + 底部提示 + 底部「准备」按钮一起刷新（重建卡片、改选、锁定三条路都走它）。
## 选角流程里标题与提示都是空的（见 _mode_title / _status_text）：该做什么看立绘上的黄框、
## 还剩多久看倒计时，顶部只留座次条、立绘与「准备」按钮之间不留文字
func _刷新文案() -> void:
	标题.text = _mode_title()
	标题.visible = not 标题.text.is_empty()
	提示.text = _status_text()
	提示条.visible = not 提示.text.is_empty()
	_刷新准备按钮()


## 底部「立即开始（x/X）」：x＝已准备人数、X＝选角人数，都现读当前对局快照（Data.game_info）——
## 断线重连时快照可能比选角层先到，只靠 game_info_updated 信号会漏掉那一次，现读就不会停在 (0/0)。
## 文案不随点击变：点过就地置灰，改成「已准备」这种词反而像还要再点一下别的。
## 锁住之后（收尾等开局那段）整颗收起来 —— 那会儿已经不能再点；全角色预览里同样不摆
func _刷新准备按钮() -> void:
	准备按钮.visible = not _预览模式 and not _锁定
	if not 准备按钮.visible:
		return
	准备按钮.text = "立即开始（%d/%d）" % [
		(Data.game_info.get("pick_ready", []) as Array).size(),
		(Data.game_info.get("player_infos", []) as Array).size()]
	准备按钮.disabled = _已准备()


## 我自己是不是已经点过「准备」（看最新快照里的已准备名单里有没有我）
func _已准备() -> bool:
	return (Data.game_info.get("pick_ready", []) as Array).has(Logic.my_player_id)


## 锁住（收尾等开局那段锁定时间）的界面：立绘改成点不动（不重建卡片，免得闪一下）+ 文案 + 锁定版面
func _锁定界面() -> void:
	for c: Node in 卡片区.get_children():
		var b: 角色卡 = c as 角色卡
		if b != null:
			# 锁住后立绘不压暗：别人已经不用再选，自己那张也要看得清（只是点不动了）
			b.设置外观(b.立绘.texture, false, not _interactive and not _预览模式)
	_刷新文案()
	_应用锁定外观()


## 锁定期的版面：倒计时位置改显示「即将开始…」，立绘只剩自己选定的那一张（摆到正中）
func _应用锁定外观() -> void:
	倒计时.visible = false
	即将开始文本.visible = true
	_只留选定卡()


## 只留自己选定的那张立绘，并把它摆到面板正中（锁定期用，见 _应用锁定外观）。
## 一张都没选定的（正常不会：收尾时服务端一定给了角色）就原样摆着
func _只留选定卡() -> void:
	var 选中: 角色卡 = null
	for c: Node in 卡片区.get_children():
		var b: 角色卡 = c as 角色卡
		if b != null and int(b.get_meta("role_id", -1)) == _已选角色:
			选中 = b
			break
	if 选中 == null:
		return
	for c: Node in 卡片区.get_children():
		var b: 角色卡 = c as 角色卡
		if b != null and b != 选中:
			b.visible = false
	# 面板收成一行高，把这唯一一张摆到正中
	滚动.custom_minimum_size = Vector2(面板宽, ROLE_BTN_H)
	卡片区.custom_minimum_size = Vector2(面板宽, ROLE_BTN_H)
	选中.position = Vector2((面板宽 - ROLE_BTN_W) * 0.5, 0.0)


## 顶部「座位顺序」条：按服务端下发的座位顺序（Game 快照里 player_infos 的顺序）摆座位菱形，
## 自己那格用黄框 SeatMain，其余按队伍蓝/红；几个玩家就摆几格，在整条上均匀铺开。
## 双线横轨是 role_pick.tscn 里的静态装饰（参照工程那张 b09_seat_1.png 固定画了 6 个空位菱形，
## 人数不是 6 时（比如 2V2）会多出空位，所以不用它）——这里只往 座位层 里摆在场的玩家。
func _刷新座次() -> void:
	# 全角色预览不是一局对局，没有座位顺序可言（座次行整行都收着）
	if _预览模式:
		return
	for c: Node in 座位层.get_children():
		座位层.remove_child(c)
		c.queue_free()
	var 条宽: float = 座次条.custom_minimum_size.x
	var infos: Array = Data.game_info.get("player_infos", [])
	var 人数: int = infos.size()
	if 人数 <= 0:
		return
	var 间距: float = 0.0 if 人数 <= 1 else (条宽 - 座次格宽) / float(人数 - 1)
	for i: int in range(人数):
		var 数据: Dictionary = infos[i]
		var 队: int = int(数据.get("team", GConst.TEAM_NONE))
		var 是我: bool = int(数据.get("id", -1)) == Logic.my_player_id
		var 格: 座位格 = 座位格预制.instantiate()
		格.position = Vector2(i * 间距, 0.0)
		格.设置(队, 是我)
		座位层.add_child(格)


## 一张角色卡（挂 scripts/ui/RoleCard.gd）：整张立绘（无边框、无名字，角色名与技能在悬浮说明里）
func _build_role_button(rid: int) -> Button:
	var btn: 角色卡 = 角色卡预制.instantiate()
	btn.custom_minimum_size = Vector2(ROLE_BTN_W, ROLE_BTN_H)
	btn.size = Vector2(ROLE_BTN_W, ROLE_BTN_H)
	btn.set_meta("role_id", rid)
	# 可点＝轮到自己、且本轮还没锁住；压暗＝还没轮到自己选（那时只是看）
	btn.设置外观(Art.role_hero(rid), _interactive and not _锁定, not _interactive and not _预览模式)
	btn.pressed.connect(_on_role_pressed.bind(rid))
	# 悬停说明（角色名一行 + 技能说明，含 BBCode）走界面自己的 说明提示框 —— 与战斗界面同款；
	# 不用引擎自带 tooltip：它跟着光标走、贴近屏幕边会顶出去，排版也不好和战斗对齐
	btn.mouse_entered.connect(_悬停角色卡.bind(btn, rid))
	btn.mouse_exited.connect(说明提示.收起)
	return btn


## 悬停某张角色卡：弹出战斗同款的角色技能说明
func _悬停角色卡(按钮: Button, rid: int) -> void:
	说明提示.显示角色说明(rid, 按钮.get_global_rect())


## 页面标题：只有「全角色预览」（从设置里进来那一路）拿它当页头；选角流程不摆标题
func _mode_title() -> String:
	return "全角色预览" if _预览模式 else ""


## 底部提示：只有全角色预览用得上（讲讲怎么翻看）。选角流程不摆提示 ——
## 选定了哪张看立绘上的黄框、还剩多久看倒计时，中间那块提示条就收着
func _status_text() -> String:
	if _预览模式:
		return "滚轮翻看，鼠标指向立绘看技能"
	return ""


# ============================================================
# 交互
# ============================================================
## 点一下立绘就选定并上行（参照工程 RoleChoose31 的点击回调）。
## 选定后其余立绘照旧摆着：倒计时结束前随时能点别的改选，服务端以最后一次提交为准
func _on_role_pressed(rid: int) -> void:
	if not _interactive or _锁定:
		return
	Art.play_sfx("Equip")
	Logic.send_pick(_strategy, [rid])
	_已选角色 = rid
	_刷新文案()
	_标记选定卡()


## 点底部「立即开始」：上行一次（带上当前选定的角色，还没选就空着）、服务端记「已准备」。
## 点过之后仍然可以点别的立绘改选 —— 改选只上报角色，服务端记的「已准备」不会被抹掉。
## 在场玩家全都准备好时，服务端会让倒计时直接归零（客户端随即锁住界面、等开局）
func _on_ready_pressed() -> void:
	if not _interactive or _锁定 or _已准备():
		return
	Art.play_sfx("Equip")
	Logic.send_ready(_strategy, [_已选角色] if _已选角色 > 0 else [])


func _on_game_info(info: Dictionary) -> void:
	# 全角色预览不是选角：对局快照照常往下发，不能因此把预览收掉（对战中途开预览就看不成了）
	if _预览模式:
		return
	if bool(info.get("is_started", false)):
		if UI.选角层 == self:
			UI.选角层 = null
		queue_free()
		return
	# 选角期间：底部「立即开始（x/X）」跟着快照刷新（人数直接读 Data.game_info，见 _刷新准备按钮）
	_刷新准备按钮()

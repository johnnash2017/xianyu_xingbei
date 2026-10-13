extends Control
## 房间准备室 —— 从参照工程 d:\星杯传说工程\星杯传说 的 scenes/prefabs/ui/ReadyRoom.tscn 搬过来
## 进房后、开局前由 client_logic 切到这里；开局后换成 BattleUIMobile。
## 界面结构全在 scenes/ReadyRoom.tscn 里（所见即所得地改），本脚本只绑节点 + 跑逻辑：
##   座位（队伍底色 / 昵称 / READY）来自服务端下发的 Game 快照；
##   准备 / 分队 / 退房 / 聊天走 Logic 的上行接口。

## 分队上行的协议取值（服务端 join_team：1 蓝队 / 2 红队 / 其它 未分队）
const 上行蓝队: int = 1
const 上行红队: int = 2
const 上行随机: int = 3
## 座位排距上限：参考工程三排座位用的就是 140
const 座位行距上限: float = 140.0
## 座位纵向能占到哪儿：再往下 y=195 起是「准备 / 返回大厅 / 选择队伍」那排按钮，座位不能压上去
const 座位区半高: float = 195.0
## 座位格高度（与 ReadyRoom.tscn 里 PlayerN 的 offset 差一致）
const 座位高: float = 88.0
## 聊天区最多保留的行数
const 聊天最大行: int = 200
## 开局提示的两种字色：倒计时用暖黄，队伍人数不对等的警告用橙红
const 倒计时色: Color = Color(1.0, 0.85, 0.4, 1.0)
const 警告色: Color = Color(1.0, 0.45, 0.4, 1.0)

## 顶部：房名 + 人数
@export var Title: Label
## 八个座位：偶数下标在左、奇数下标在右；同一侧里奇数排还往环外多错开一列，
## 相邻排一进一出，和参考工程一样是交错的，不是一条直线
@export var Seats: Array[TextureRect]
## 准备 / 返回大厅 / 选择队伍
@export var BtnReady: Button
@export var BtnExit: Button
@export var BtnChooseTeam: Button
@export var 设置按钮: Button
## 观战者的等待提示：观战者在准备室没有可操作的东西，只告诉他现在在等什么
@export var 观战提示: Label
## 开局提示：开局倒计时 / 两队人数不对等（摆在观战提示上方）
@export var 开局提示: Label
## 选择队伍面板与它的三个按钮
@export var ChooseTeamPanel: Control
@export var BtnRedTeam: Button
@export var BtnBlueTeam: Button
@export var BtnRandomTeam: Button
## 聊天区
@export var ChatLog: RichTextLabel
@export var ChatInput: LineEdit
@export var BtnSend: Button
## 中间的魔法阵与十二芒星：各自自转（原版 animation/Rotation.anim 的等价实现）
@export var Ring: Control
@export var Star: Control
## 自转角速度（度/秒），正值 = 屏幕上顺时针；十二芒星反向转
@export var DegPerSec: float = 12.0

## 聊天记录（RichTextLabel 的 text 是整块重写的，这里留一份行列表）
var _聊天行: PackedStringArray = PackedStringArray()


func _ready() -> void:
	UI.register(self)
	Logic.game_info_updated.connect(_刷新)
	Logic.gossip_received.connect(_聊天追加)
	# 系统公告（掉线 / 重连 / 超时…）也落进这块聊天区，别让玩家在房间里看不到任何反馈
	Logic.notice_received.connect(_聊天追加)
	BtnReady.pressed.connect(_on_ready_pressed)
	BtnExit.pressed.connect(_on_exit_pressed)
	BtnChooseTeam.pressed.connect(_on_choose_team_pressed)
	设置按钮.pressed.connect(UI.切换设置)
	BtnRedTeam.pressed.connect(func() -> void: _选队(上行红队))
	BtnBlueTeam.pressed.connect(func() -> void: _选队(上行蓝队))
	BtnRandomTeam.pressed.connect(func() -> void: _选队(上行随机))
	BtnSend.pressed.connect(_on_send_pressed)
	ChatInput.text_submitted.connect(func(_文本: String) -> void: _on_send_pressed())
	ChooseTeamPanel.visible = false
	# 进房时 Game 快照已经到过了（client_logic 先收 Game 再切界面），先按它刷一次
	_刷新(Logic.last_info)


func _process(delta: float) -> void:
	Ring.rotation += deg_to_rad(DegPerSec) * delta
	Star.rotation -= deg_to_rad(DegPerSec) * delta


# ============================================================
# 刷新（服务端每次广播 Game 都会调到这里）
# ============================================================
func _刷新(info: Dictionary) -> void:
	if info.is_empty():
		return
	var 玩家表: Array = info.get("player_infos", [])
	var 人数上限: int = int(info.get("max_player", 玩家表.size()))
	_摆座位(人数上限)
	清空座位()
	for 数据: Variant in 玩家表:
		_落座(数据 as Dictionary)
	# 准备按钮跟着自己的权威状态走（房主可能刚给我改了状态）
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	BtnReady.button_pressed = 我 != null and 我.ready
	# 顶部只写房名：空座位一开始就全摆出来了，已到几人一眼可见，不必再报人数
	Title.text = str(info.get("room_name", "房间"))
	_刷新观战提示(info)
	_刷新开局提示(info)


## 开局提示：开局倒计时（服务端每秒推一次剩余毫秒）或「两队人数不对等」。
## 判据全在 Game 快照里（倒计时毫秒 + 各玩家的队伍与准备状态），不必另开消息。
func _刷新开局提示(info: Dictionary) -> void:
	var 剩余: int = int(info.get("start_countdown_ms", 0))
	if 剩余 > 0:
		开局提示.visible = true
		开局提示.add_theme_color_override("font_color", 倒计时色)
		开局提示.text = "%d 秒后开始…" % ceili(剩余 / 1000.0)
		return
	var 玩家表: Array = info.get("player_infos", [])
	var 红: int = 0
	var 蓝: int = 0
	var 全准备: bool = not 玩家表.is_empty() and 玩家表.size() == int(info.get("max_player", 0))
	for 数据: Variant in 玩家表:
		match int((数据 as Dictionary).get("team", GConst.TEAM_NONE)):
			GConst.RED:
				红 += 1
			GConst.BLUE:
				蓝 += 1
		if not bool((数据 as Dictionary).get("ready", false)):
			全准备 = false
	# 只在「人数已齐、全员准备、两队却配不平」时提示：其余情况没开局是别的原因（人没到齐 /
	# 有人没准备），说了反而误导；队伍色在座位底色上本来也看得到
	var 该提示: bool = 全准备 and 红 != 蓝
	开局提示.visible = 该提示
	if 该提示:
		开局提示.add_theme_color_override("font_color", 警告色)
		开局提示.text = "队伍人数不对等，无法开始对战"


## 观战者入房后（可能正赶上等人、也可能正赶上选角）在屏幕中间给一句等待提示；
## 不是观战者就藏起来 —— 房内玩家的界面本来就有座位/准备/分队，不需要这句
func _刷新观战提示(info: Dictionary) -> void:
	观战提示.visible = Logic.my_player_id == GConst.GUEST
	if not 观战提示.visible:
		return
	观战提示.text = "【观战中】正在等待选角…" if bool(info.get("picking", false)) else "【观战中】正在等待开始…"


## 显示前 N 个座位，并把每侧的座位按个数均匀铺开
func _摆座位(人数上限: int) -> void:
	var 左侧数: int = 0
	var 右侧数: int = 0
	for i: int in range(Seats.size()):
		Seats[i].visible = i < 人数上限
		if i < 人数上限:
			if i % 2 == 0:
				左侧数 += 1
			else:
				右侧数 += 1
	_摆一侧(0, 左侧数)
	_摆一侧(1, 右侧数)


## 把某一侧（奇偶 0 = 左、1 = 右）的座位垂直居中铺开。
## 横向交错由 ReadyRoom.tscn 里各座位的横坐标决定（奇数排多错开一列），这里只管纵向：
## 排距照参考工程取 140；排数多到会压上下方按钮时，按可用高度等比压缩。
func _摆一侧(奇偶: int, 个数: int) -> void:
	var 行距: float = 0.0
	if 个数 > 1:
		行距 = minf(座位行距上限, (座位区半高 - 座位高 * 0.5) * 2.0 / float(个数 - 1))
	var 第几个: int = 0
	for i: int in range(Seats.size()):
		var 座: Control = Seats[i]
		if i % 2 != 奇偶 or not 座.visible:
			continue
		# 中心点：整列绕环心对称
		var 中心y: float = (float(第几个) + 0.5 - float(个数) * 0.5) * 行距
		座.offset_top = 中心y - 座位高 * 0.5
		座.offset_bottom = 中心y + 座位高 * 0.5
		第几个 += 1


func 清空座位() -> void:
	for 座: TextureRect in Seats:
		(座 as 准备座位).清空()


## 按玩家号落座（服务端分配的座位号就是玩家 id：房间里空出的号会被后来人补上）
func _落座(数据: Dictionary) -> void:
	var 座位号: int = int(数据.get("id", -1))
	if 座位号 < 0 or 座位号 >= Seats.size():
		return
	var 座: 准备座位 = Seats[座位号] as 准备座位
	var 昵称: String = str(数据.get("nickname", ""))
	# 自己不用加「（你）」后缀，直接把名字标成橙色（见 准备座位.设置昵称）
	座.设置昵称(昵称, 座位号 == Logic.my_player_id)
	座.设置队伍(_队伍号(int(数据.get("team", GConst.TEAM_NONE))))
	座.设置准备(bool(数据.get("ready", false)))


## 引擎的队伍色（0 蓝 / 1 红 / -1 未分队）→ 座位贴图下标（0 蓝 / 1 红 / 2 未分队）
func _队伍号(色: int) -> int:
	return 2 if 色 < 0 else 色


# ============================================================
# 房间操作
# ============================================================
## 准备 / 取消准备：服务端 ReadyForGameReq 里 1 = 准备、2 = 取消，
## 人数没坐满时服务端不会开局（房间设定几人就得几人）
func _on_ready_pressed() -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 已准备: bool = 我 != null and 我.ready
	Logic.set_ready(2 if 已准备 else 1)


func _on_choose_team_pressed() -> void:
	ChooseTeamPanel.visible = true


func _选队(队: int) -> void:
	Logic.join_team(队)
	ChooseTeamPanel.visible = false


func _on_exit_pressed() -> void:
	Logic.leave_room()
	UI.goto_lobby()


# ============================================================
# 聊天
# ============================================================
func _on_send_pressed() -> void:
	var 文本: String = ChatInput.text.strip_edges()
	if 文本 == "":
		return
	Logic.talk(文本)
	ChatInput.text = ""


## 聊天行的显示形如「昵称：内容」，直接把整块重写（RichTextLabel 会自己滚到底）
func _聊天追加(行: String, _kind: int = 0) -> void:
	_聊天行.append(行)
	while _聊天行.size() > 聊天最大行:
		_聊天行.remove_at(0)
	ChatLog.text = "\n".join(_聊天行)

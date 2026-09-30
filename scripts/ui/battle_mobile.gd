extends Control
## 战斗界面（手机版）容器 —— 把本项目的战斗数据灌进「参考工程搬来的」BattleUIMobile 控件里。
##
## 背景与取舍：
##  * 被搬过来的容器脚本 scripts/BattleUIMobile.gd 是参考工程原件，依赖 BattleData / Dialog /
##    Lobby / UIManager / GameManager / MessageSystem 等本工程不存在的单例，本脚本不再使用它，
##    只把它当作「控件结构与参考行为」的参考。
##  * 数据映射照本工程在用的 scripts/ui/battle.gd 抄：监听 Logic 的信号，读 Data.player_list 与
##    Logic.last_info 刷新界面。
##  * 本步骤只做「显示」。手牌区/出牌/选目标/技能/应战等交互是下一步（脚本里以「第三步」留白），
##    音频也下一步统一搬。
##  * 节点引用一律 @export 在检查器绑定（对应 scenes/BattleUIMobile.tscn 的 NodePath）。

# ---------------- 界面节点（@export 绑定） ----------------
## Root 目前只用于「出牌箭头」这类要挂到根上的动画节点（第三步）。
@export var Root: Control
@export var MainPlayer: 战斗玩家面板
@export var PlayerStatusMobileR: 战斗玩家面板
@export var PlayerStatusMobileUR: 战斗玩家面板
@export var PlayerStatusMobileU: 战斗玩家面板
@export var PlayerStatusMobileUL: 战斗玩家面板
@export var PlayerStatusMobileL: 战斗玩家面板
@export var BlueMorale: Label
@export var RedMorale: Label
@export var BlueEnergy: GridContainer
@export var RedEnergy: GridContainer
@export var BlueGrail: GridContainer
@export var RedGrail: GridContainer
@export var TxtTurn: Label
@export var TxtRID: Label
@export var TxtHint: Label
@export var Hint: Control
@export var Content_2: Label           # 日志 Label（场景里挂着 AutoClearLog.gd）
@export var Content: GridContainer     # 聊天条目容器
@export var InputField: LineEdit
@export var BtnSubmit: Button
@export var BtnLogExpand: Button
@export var BtnChatExpand: Button
@export var WinPanel: Control
@export var EndTxt: Label
@export var BtnBack: Button
@export var LogRoot: Control           # 日志面板根（展开/收起用）
@export var ChatRoot: Control          # 聊天面板根（展开/收起用）
# ---- 交互层用到的控件（第三步） ----
@export var HandArea: Control        # 我的手牌区（Root/HandArea；一行手排，位置由 刷新手牌 算）
@export var SkillArea: Control         # 技能区底图（Root/SkillArea）
@export var ChildrenSkillArea: GridContainer  # 技能按钮容器（Root/ChildrenSkillArea）
@export var ChooseArea: Control        # 盖牌选择区（Root/ChooseArea）
@export var BtnOK: Button              # 确定
@export var BtnCancel: Button          # 取消
@export var BtnCovered: Button         # 「盖牌」按钮（点开/收起查看自己的盖牌）
@export var BtnSpecila: Button         # 行动阶段＝「特殊行动」（购买/合成/提炼）；魔弹传递时＝「放弃」
@export var BtnResign: Button          # 行动阶段＝「放弃行动」（对照参考工程 PlayerAgentUI 的 BtnResign → ResignAction）
## 特殊行动专用窗口（购买/合成/提炼，搬自参考工程 SpecialActionUI）：预制体在 _ready 里挂到本界面最上层
const 特殊行动窗预制: PackedScene = preload("res://scenes/prefabs/battlemobile/SpecialActionUI.tscn")
var 特殊行动窗: 特殊行动窗口 = null
## 参数选择窗口（特殊行动的第二层「用哪些星石」，搬自参考工程 ChooseArgsUI）
const 参数选择窗预制: PackedScene = preload("res://scenes/prefabs/battlemobile/ChooseArgsUI.tscn")
var 参数选择窗: 参数选择窗口 = null
## 英雄详情窗（技能说明，搬自参考工程 InfomationUI）：平时点一名玩家的头像就弹它
const 英雄详情窗预制: PackedScene = preload("res://scenes/prefabs/battlemobile/InfomationUI.tscn")
var 英雄详情窗: 英雄详情窗口 = null
## 参数选择窗口是为哪个特殊行动打开的（选完星石要按它提交）
var _待定特殊行动: int = GConst.SpecialAction.Buy

## 预制体目录（格子/聊天条目与参考脚本一致）
const 预制目录: String = "res://scenes/prefabs/battlemobile/"
## 提示显示后自动隐藏的秒数（同参考工程的 Invoke("hideHint", 3f)）
const 提示停留秒: float = 3.0
## 日志最多保留的行数（同参考工程 AutoClearLog 的裁剪行数）
const 日志最大行: int = 233
## 宝石/水晶/星杯格子的最小尺寸（Unity 转过来的 Image 预制体是 0×0，必须给尺寸）
## 正方形：贴图本身近似正方形（宝石 29×30、水晶 29×30、星杯 23×23），
## 给 30×40 会把它们上下拉伸；队伍条容器高 30、5 列正好 5×30=150
const 格子最小尺寸: Vector2 = Vector2(30.0, 30.0)
## 卡牌预制体（挂 scripts/CardUI.gd，已解耦为「塞数据 + 点击回调」）
const 卡牌预制: PackedScene = preload("res://scenes/prefabs/battlemobile/Card.tscn")
## 技能按钮预制体（挂 scripts/SkillUI.gd，同上）
const 技能预制: PackedScene = preload("res://scenes/prefabs/battlemobile/Skill.tscn")
## 手牌卡面尺寸（参考脚本 showCard 用的 136×190，这里略窄一点好让 6 张能排下）
const 手牌尺寸: Vector2 = Vector2(130.0, 192.0)
## 手牌排布：牌少时彼此贴着排（空隙 0）并整体居中；一行放不下才压缩，压到负数就是相邻两张叠着放
const 手牌最多重叠比例: float = 0.45
## 盖牌缩略尺寸（盖牌选择区里手排用）
const 盖牌尺寸: Vector2 = Vector2(58.0, 83.0)
## 技能按钮最小尺寸（Skill.tscn 根按钮的实际尺寸是 110×90）
const 技能尺寸: Vector2 = Vector2(110.0, 90.0)
## 玩家面板：常态 / 选中（目标）颜色
const 面板常态色: Color = Color(1.0, 1.0, 1.0)
const 面板选中色: Color = Color(1.0, 1.0, 0.55)
## 当前不可选的玩家面板整体压暗（视觉上「点不动」，同卡牌那套置灰）
const 面板置灰色: Color = Color(0.5, 0.5, 0.5)

## 能把地系 / 火系牌当【魔弹】打出去的角色（【魔弹融合】803，对照 role_modao / role_spmodao）
const 地火可作魔弹角色: Array[int] = [8, 108]
## 拥有【魔弹掌握】（802）的角色：打【魔弹】/ 传递时左右两个方向都能选（对照 skillDB 802「可选逆向传递」）
const 魔弹掌握角色: Array[int] = [8]
## 【黑暗束缚】2903：不能用【魔弹】转弹、也不能用【圣光】格挡（对照 role_moqiang）
const 魔弹全禁角色: Array[int] = [29]
## 行动阶段不能使用法术牌的角色（【暗影抗拒】904，对照 role_mojian 的 v_allow_action）
const 行动阶段禁用法术牌角色: Array[int] = [9]

## 玩家面板顺序：自己的面板固定是 MainPlayer，其余按 Data.player_list 顺序依次填
var _面板列表: Array[战斗玩家面板] = []
## 日志缓冲：Content_2 上的 AutoClearLog 按行裁剪，需要整段文本
var _日志: String = ""
## 当前回合玩家 id（用于面板高亮）
var _当前回合: int = -1
## 当前「背后的 Turn 亮着」的玩家 id：轮到谁行动 / 在等谁回复都算，变了才重播动画
var _高亮玩家id: int = -2
## 正在等谁回复、还剩多少秒（由对局快照刷新）
var _等待方: int = -1
var _等待剩余: float = 0.0
## 本次等待的总时长（秒）：进度条按「剩余 / 总时长」画
var _等待总时长: float = 0.0
## 提示自动隐藏：token 变了说明来了新提示，旧的倒计时作废（同参考脚本的做法）
var _提示计时器: Timer = null
var _提示token: int = 0
var _当前提示token: int = 0
## 对局是否已开始：开局日志只写一次
var _已开局: bool = false
## 胜负是否已结算：公告与终局信号可能重复，只结算一次
var _胜负已定: bool = false
## 数值快照：判断士气 / 宝石水晶 / 治疗的变化并播对应音效（同 battle.gd）
var _上次士气: Array[int] = [0, 0]
var _上次宝石: Array[int] = [0, 0]
var _上次水晶: Array[int] = [0, 0]
var _上次治疗: int = 0

# ---------------- 交互状态（与旧界面 battle.gd 同构） ----------------
## 0 空闲 / 1 行动 / 2 响应 / 3 技能询问 / 4 发动技能
var _mode: int = 0
## 当前 CMD_REQ 的单条命令
var _pending: Dictionary = {}
## 当前询问的类型（GConst.Msg.Action / Msg.Respond）
var _pending_type: int = -1
## 本次要选几张牌 / 几个目标
var _need_cards: int = 0
var _need_players: int = 0
## 已选中
var _sel_cards: Array[int] = []
var _sel_players: Array[int] = []
## 技能询问：正在询问是否发动的技能号（>= 100 才是真的技能询问）
var _skill_ask_id: int = -1
var _skill_ask_need_card: int = 0
var _skill_ask_need_target: int = 0
## 技能询问的选牌来源（GConst.CardSource）
var _skill_ask_card_source: int = 0
## 本次询问是否要选盖牌（盖牌区可见且可点）
var _selecting_cover: bool = false
## 是否正在「查看盖牌」（点「盖牌」按钮打开，只读，不影响回合）
var _查看盖牌: bool = false
## 技能询问的可选项值（非空时渲染选项按钮）
var _skill_options: Array[int] = []
## 已选定要发动的技能号与它对应的 action_type
var _pending_skill_id: int = -1
var _pending_skill_type: int = -1
var _skill_need_card: int = 0
var _skill_need_target: int = 0
## 本次发动技能的合法目标（服务端在技能上给的 targets，非空时只让这几名玩家亮；
## 例：【魔弹融合】默认只有右手边最近的对手，有【魔弹掌握】时左右各一个）
var _skill_targets: Array[int] = []
## 本次发动技能的合法手牌（服务端在技能上给的 cards，非空时只让这几张牌可点；
## 例：【暗影流星】只能弃法术牌）
var _skill_cards: Array[int] = []
## 本次发动技能的点选上限（服务端在技能上给的 card_max，≥ 需牌数；如【欺诈】可弃 2~3 张）
var _skill_card_max: int = 0
## 本次发动技能的目标数上限（服务端在技能上给的 target_max，≥ 需目标数；省略＝刚好需目标数）
var _skill_target_max: int = 0
## 本次发动技能的选牌来源（GConst.CardSource：手牌 / 盖牌区 / 场上基础效果牌）
var _skill_card_source: int = GConst.CardSource.Hand
## 本次发动技能的参数选项（服务端在技能上给的 arg_choices：每项一个按钮，点它就用当前已选的牌/目标提交）
var _skill_arg_choices: Array = []
## 参数选项按钮 [{按钮, 需牌, 需目标}]：选项可以要求先选够牌/目标，没选够就压灰
var _参数按钮: Array = []
## 技能区当前渲染出来的按钮（行动阶段技能 / 选项 / 额外行动 / 特殊行动共用）
var _技能按钮: Array[Node] = []
## 本次行动询问下发的全部命令（取消技能/特殊行动时用它把技能按钮摆回来）
var _行动命令: Array = []
## 【地下法则】的持有者：冒险家（购买时只加宝石、一次可加 2 点，对照 role_maoxian.v_buy）
const 冒险家角色号: int = 12


func _ready() -> void:
	_面板列表 = [MainPlayer, PlayerStatusMobileR, PlayerStatusMobileUR,
		PlayerStatusMobileU, PlayerStatusMobileUL, PlayerStatusMobileL]
	Logic.game_info_updated.connect(_on_game_info)
	Logic.turn_changed.connect(_on_turn)
	Logic.card_shown.connect(_on_card)
	Logic.hit_received.connect(_on_hit)
	Logic.hurt_received.connect(_on_hurt)
	Logic.skill_received.connect(_on_skill)
	Logic.game_over.connect(_on_game_over)
	Logic.gossip_received.connect(_on_gossip)
	Logic.notice_received.connect(_on_notice)
	Logic.error_received.connect(_on_error)
	BtnSubmit.pressed.connect(_on_submit)
	InputField.text_submitted.connect(func(_t: String) -> void: _on_submit())
	BtnLogExpand.pressed.connect(_展开日志)
	BtnChatExpand.pressed.connect(_展开聊天)
	BtnBack.pressed.connect(_on_back)
	# 初始收起日志/聊天（同参考脚本 Start 里的处理）
	LogRoot.visible = false
	ChatRoot.visible = false
	# ---- 交互层（第三步）：接收询问 + 确定/取消/盖牌/特殊行动/放弃行动 ----
	Logic.command_received.connect(_on_command)
	# 让「操作无效」（ErrorInput）能回调到本界面（同旧界面 battle.gd 的做法）
	Logic.battle = self
	BtnOK.pressed.connect(_on_ok)
	BtnCancel.pressed.connect(_on_cancel)
	BtnCovered.pressed.connect(_on_cover_view)
	BtnSpecila.pressed.connect(_on_giveup)
	BtnResign.pressed.connect(_on_resign)
	# 特殊行动窗口挂在最上层（最后 add_child → 画在最上面），平时自己隐藏
	特殊行动窗 = 特殊行动窗预制.instantiate()
	add_child(特殊行动窗)
	特殊行动窗.选择了.connect(_on_special_action_chosen)
	特殊行动窗.取消了.connect(_on_special_action_cancelled)
	参数选择窗 = 参数选择窗预制.instantiate()
	add_child(参数选择窗)
	参数选择窗.选择了.connect(_on_参数选择)
	参数选择窗.取消了.connect(_on_参数选择取消)
	英雄详情窗 = 英雄详情窗预制.instantiate()
	add_child(英雄详情窗)
	for 面板: 战斗玩家面板 in _面板列表:
		面板.pressed.connect(_on_player_pressed.bind(面板))
		面板.基础效果牌点击.connect(_on_基础牌点击)
	ChooseArea.visible = false
	_隐藏技能区()
	# 手牌是按 HandArea 的实际宽度手排成一行的，尺寸一变（窗口缩放）就重排
	HandArea.resized.connect(刷新手牌)
	# 场景被重新挂上时，可能有已经到达的快照
	if not Logic.last_info.is_empty():
		_on_game_info(Logic.last_info)
	else:
		_刷新交互()


func _exit_tree() -> void:
	if Logic.battle == self:
		Logic.battle = null


# ============================================================
# 刷新（数据映射照 battle.gd）
# ============================================================
## 对局快照 → 刷新队伍数值、房间号、玩家面板
func _on_game_info(info: Dictionary) -> void:
	var started: bool = bool(info.get("is_started", false))
	# 留着「上一条快照是否已开局」：开局那一条只做记录，否则士气 0 → 初始值会白响一声
	var 之前已开局: bool = _已开局
	if started and not _已开局:
		_已开局 = true
		# 房间等待阶段仍是大厅音乐，真开打才换战斗曲（同旧界面 battle.gd）
		Audio.播放音乐(Audio.场景战斗)
		_日志追加("[房间 %d] 对局开始" % int(info.get("room_id", 0)))
	_播音效_数值变化(info, 之前已开局 and started)
	_刷新队伍(info)
	_刷新玩家面板()
	_读取等待(info)
	TxtRID.text = str(int(info.get("room_id", 0)))
	# 手牌/盖牌/目标可选状态跟着快照走（Data.build_player_list 已同步好）
	_刷新交互()


## 等待提示：读「正在等谁回复、还剩多久」，照 battle.gd 的 _读取等待 / _刷新等待提示
func _读取等待(info: Dictionary) -> void:
	_等待方 = int(info.get("wait_pid", -1))
	_等待总时长 = float(info.get("wait_total_ms", 0)) / 1000.0
	_等待剩余 = float(info.get("wait_ms", 0)) / 1000.0
	_刷新等待条()
	# 服务端已经在等别人了，说明挂在手上那条询问早已作废（最典型的是自己超时后服务端径自往下走）：
	# 立刻退回等待态 —— 手牌/目标置灰、技能收起，否则会出现「别人的回合我还能点还能选目标」
	if _等待方 >= 0 and _等待方 != Logic.my_player_id and _mode != 0:
		_清空待选()
	if _等待方 < 0:
		return
	# 在等谁回复（应战 / 圣盾 / 魔弹传递…）就把谁的面板高亮起来
	_高亮玩家(_等待方)
	# 自己手上正有询问时，提示交给交互层写，别被等待文案盖掉
	if _mode != 0:
		return
	var p: GPlayer = Data.get_player_by_id(_等待方)
	var 名: String = ("%d号 %s" % [p.id, p.nickname]) if p != null else ("%d号" % _等待方)
	var 文本: String = "正在等待你的操作…" if _等待方 == Logic.my_player_id else "正在等待 %s 操作…" % 名
	if _等待剩余 > 0.0:
		文本 += "（剩余 %d 秒）" % int(ceilf(_等待剩余))
	_提示(文本)


## 等待进度条：服务端只在「开始等待 / 等待结束」广播，剩余时间由客户端自己倒数
func _process(delta: float) -> void:
	if _等待方 < 0:
		return
	_等待剩余 = maxf(_等待剩余 - delta, 0.0)
	_刷新等待条()


## 超时进度条画在「正在被等的那名玩家」的名牌上方，其余面板收起（传负值）
func _刷新等待条() -> void:
	var 比例: float = -1.0
	if _等待方 >= 0 and _等待总时长 > 0.0:
		比例 = clampf(_等待剩余 / _等待总时长, 0.0, 1.0)
	for 面板: 战斗玩家面板 in _面板列表:
		面板.WaitProgress = 比例 if 面板.ID == _等待方 else -1.0


## 数值变化音效（对照参考项目 MoraleChange / GemChange / CrystalChange / PlayerHealChange）
func _播音效_数值变化(info: Dictionary, 生效: bool) -> void:
	var 士气: Array[int] = [int(info.get("red_morale", 0)), int(info.get("blue_morale", 0))]
	var 宝石: Array[int] = [int(info.get("red_gem", 0)), int(info.get("blue_gem", 0))]
	var 水晶: Array[int] = [int(info.get("red_crystal", 0)), int(info.get("blue_crystal", 0))]
	var 治疗: int = 0
	for p: GPlayer in Data.player_list:
		治疗 += p.cross_num
	if 生效:
		if 士气 != _上次士气:
			Audio.播音效("sys-morale")
		elif 宝石 != _上次宝石 or 水晶 != _上次水晶:
			Audio.播音效("sys-energy")
		if 治疗 != _上次治疗:
			Audio.播音效("sys-heal")
	_上次士气 = 士气
	_上次宝石 = 宝石
	_上次水晶 = 水晶
	_上次治疗 = 治疗


## 士气 / 宝石 / 水晶 / 星杯（读 Logic.last_info 的绝对值，同 battle.gd 的 _refresh_team_bar）
func _刷新队伍(info: Dictionary) -> void:
	BlueMorale.text = str(int(info.get("blue_morale", 0)))
	RedMorale.text = str(int(info.get("red_morale", 0)))
	_重建能量(BlueEnergy, int(info.get("blue_gem", 0)), int(info.get("blue_crystal", 0)))
	_重建能量(RedEnergy, int(info.get("red_gem", 0)), int(info.get("red_crystal", 0)))
	_重建格子(BlueGrail, int(info.get("blue_grail", 0)), "grail")
	_重建格子(RedGrail, int(info.get("red_grail", 0)), "grail")


## 能量格：宝石在前、水晶在后（与参考脚本 gemChange / crystalChange 的落位一致）
func _重建能量(容器: GridContainer, 宝石数: int, 水晶数: int) -> void:
	_清空格子(容器)
	for _i: int in range(maxi(宝石数, 0)):
		_加格子(容器, "gem")
	for _j: int in range(maxi(水晶数, 0)):
		_加格子(容器, "crystal")


## 单一贴图的格子（星杯）
func _重建格子(容器: GridContainer, 数量: int, 贴图名: String) -> void:
	_清空格子(容器)
	for _i: int in range(maxi(数量, 0)):
		_加格子(容器, 贴图名)


func _清空格子(容器: GridContainer) -> void:
	for c: Node in 容器.get_children():
		c.queue_free()


## 单个格子：用 battlemobile/Image.tscn，贴图交给 AssetIndex 按文件名取
func _加格子(容器: GridContainer, 贴图名: String) -> void:
	var ps: PackedScene = load(预制目录 + "Image.tscn")
	if ps == null:
		return
	var go: Node = ps.instantiate()
	if go is TextureRect:
		var 路径: String = AssetIndex.image(贴图名)
		if 路径 != "":
			(go as TextureRect).texture = load(路径)
	if go is Control:
		var 格子: Control = go as Control
		格子.custom_minimum_size = 格子最小尺寸
		# 队伍条是纯装饰、又排在玩家面板上层：格子必须放行点击，
		# 否则落在队伍条那一条（y<128）上的头像点击会被它吃掉
		格子.mouse_filter = Control.MOUSE_FILTER_IGNORE
	容器.add_child(go)


## 玩家面板：自己的面板固定是 MainPlayer，其余按 Data.player_list 顺序依次填。
## Data.build_player_list() 已按「我」的视角旋转过，player_list[0] 就是自己；这里仍显式按
## Logic.my_player_id 找到自己的下标，保证 MainPlayer 一定是自己。
## 注：参考工程 4 人房会把 U/UR 两个面板 queue_free 掉；本步骤改为「按顺序填、多出来的隐藏」，
## 不做销毁（避免刷新后无法恢复）。
func _刷新玩家面板() -> void:
	var 玩家列表: Array[GPlayer] = Data.player_list
	var n: int = 玩家列表.size()
	var 我的下标: int = 0
	for i: int in range(n):
		if 玩家列表[i].id == Logic.my_player_id:
			我的下标 = i
			break
	for idx: int in range(_面板列表.size()):
		var 面板: 战斗玩家面板 = _面板列表[idx]
		# 座位不够的面板藏起来（原来这行写在 continue 后面，是走不到的死代码，人一多就不会再显示）
		面板.visible = idx < n
		if idx >= n:
			continue
		_填面板(面板, 玩家列表[(我的下标 + idx) % n])


## 把一名玩家的视图数据塞进一块面板（setter 的取值形状见 PlayerStatusMobile.gd）
func _填面板(面板: 战斗玩家面板, p: GPlayer) -> void:
	面板.set("ID", p.id)
	面板.set("NickName", p.nickname)
	# 未分队时不改队色（参考工程的 Team 只有蓝 0 / 红 1，没有「未分队」）
	if p.color != GConst.TEAM_NONE:
		面板.set("Team", p.color)
	面板.set("RoleID", p.role_id)
	# HandCount 的入参语义是 (手牌上限, 当前手牌)，见 PlayerStatusMobile.set_HandCount
	面板.set("HandCount", Vector2i(p.hand_cards_max, p.hand_cards_num))
	面板.set("HealCount", p.cross_num)
	# Energy 的入参语义是 (宝石, 水晶)，见 PlayerStatusMobile.set_Energy
	面板.set("Energy", Vector2i(p.gem, p.crystal))
	面板.set("Knelt", p.tap)
	# 状态图标：基础效果（牌）+ 独有效果（GConst.Exclusive 下标）
	var 基础牌: Array = []
	for st: GPlayer.BasicStatus in p.basic_status_list:
		if st.card != null:
			基础牌.append(st.card.id)
	面板.set("BasicAndExCards", 基础牌)
	var 独有效果: Array = []
	for i: int in range(GConst.EXCLUSIVE_NUM):
		if p.specials[i]:
			独有效果.append(i)
	面板.set("ExclusiveCards", 独有效果)
	# 指示物：槽 0/1/2 → 面板的 token0/1/2（那三个 setter 的名字沿用原客户端对三个槽的叫法）
	for slot: int in range(3):
		var 值: int = 0
		if p.tokens[slot] != null:
			值 = int((p.tokens[slot] as GPlayer.Token).num)
		match slot:
			0: 面板.set("YellowToken", 值)
			1: 面板.set("BlueToken", 值)
			2: 面板.set("Covered", 值)
	面板.set("Turn", p.id == _高亮玩家id)
	# 本步骤只显示：IsEnable（能否点选为目标）留待第三步交互时驱动
	面板.set("IsEnable", false)


func _on_turn(player_id: int, round_id: int) -> void:
	_当前回合 = player_id
	# 别人的回合刚开始：自己若还停在上一条询问上（超时后被服务端推进），先退回等待态
	if player_id != Logic.my_player_id and _mode != 0:
		_清空待选()
	TxtTurn.text = str(round_id)
	_高亮玩家(player_id)
	var p: GPlayer = Data.get_player_by_id(player_id)
	# 轮到这个角色就放他自己的语音（同 battle.gd）；没有语音的角色（如 37 号）沿用界面提示音
	if p != null and Audio.有声效(str(p.role_id)):
		Audio.播音效(str(p.role_id))
	else:
		Art.play_sfx("It's your turn" if player_id == Logic.my_player_id else "TurnBegin")
	if p != null:
		_日志追加("[回合 %d] 轮到 %s（%s）" % [round_id, p.nickname, p.role_name])


## 把某个玩家面板背后的 Turn 点亮（自己 / 别人都有）。
## 动画在 PlayerStatusMobile.TurnBegin() 里：Turn 贴图先放大再缩回（同参考工程的 DOScale）。
## 只在「高亮目标变了」时才播，否则每次对局快照刷新都会重新弹一下。
func _高亮玩家(player_id: int) -> void:
	if player_id == _高亮玩家id:
		return
	_高亮玩家id = player_id
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID == player_id:
			面板.TurnBegin()
		else:
			面板.Turn = false


# ============================================================
# 提示
# ============================================================
## 顶部提示：显示后 3 秒自动隐藏（参考脚本用 Timer + token 的做法）
func _提示(txt: String) -> void:
	TxtHint.text = txt
	TxtHint.visible = true
	Hint.visible = true
	_提示token += 1
	_当前提示token = _提示token
	if _提示计时器 == null:
		_提示计时器 = Timer.new()
		_提示计时器.name = "提示计时器"
		_提示计时器.one_shot = true
		_提示计时器.timeout.connect(_on_提示超时)
		add_child(_提示计时器)
	_提示计时器.start(提示停留秒)


func _on_提示超时() -> void:
	if _当前提示token == _提示token:
		Hint.visible = false


## 常驻指令提示：交互提示不该 3 秒后消失（同参考脚本的 Invoke("hideHint") 只用于弹窗消息）
func _指令提示(txt: String) -> void:
	# 让上一轮「自动隐藏」的倒计时作废
	_提示token += 1
	TxtHint.text = txt
	TxtHint.visible = true
	Hint.visible = true


func _收起提示() -> void:
	_提示token += 1
	Hint.visible = false
	TxtHint.visible = false


func _on_error(_err_id: int, msg: String) -> void:
	_日志追加(msg)
	_提示(msg)


# ============================================================
# 广播消息 → 日志 / 聊天
# ============================================================
func _on_card(msg: Dictionary) -> void:
	var src: int = int(msg.get("src_id", -1))
	var dst: int = int(msg.get("dst_id", -1))
	# 展示（亮牌/超限换牌）没有「对谁使用」的概念，单独写一行
	var 是展示: bool = int(msg.get("type", 0)) == GConst.CardMsgType.Show
	var p: GPlayer = Data.get_player_by_id(src)
	var names: Array[String] = []
	var 首张: GCard = null
	for cid: Variant in msg.get("card_ids", []):
		var c: GCard = Data.get_card(int(cid))
		if c != null:
			names.append(c.card_name)
			if 首张 == null:
				首张 = c
	# 出牌音效（对照参考项目 AudioManager 的 CARDMSG 分支）：攻击牌 atk-<系别>，法术牌 spell-<卡名>
	if 首张 != null and not 是展示:
		if 首张.is_attack():
			Audio.播音效("atk-" + 首张.element)
		else:
			Audio.播音效("spell-" + 首张.card_name)
	var 谁: String = p.nickname if p != null else str(src)
	var 目标: GPlayer = Data.get_player_by_id(dst)
	if 是展示:
		_日志追加("%s 展示：%s" % [谁, ", ".join(names)])
		return
	if 目标 == null or dst == src:
		_日志追加("%s 对自己打出：%s" % [谁, ", ".join(names)])
	else:
		_日志追加("%s 对 %s 打出：%s" % [谁, 目标.nickname, ", ".join(names)])
	_播出手特效(src, dst, msg)


## 出手特效分发：这几种牌放专属粒子特效（打向别人时飞过去、对自己结算时原地炸开），
## 其它指向性牌退化成公用弹道。
func _播出手特效(src: int, dst: int, msg: Dictionary) -> void:
	if src < 0 or dst < 0:
		return
	var 牌号: int = _特效牌号(msg)
	if 牌号 >= 0:
		_粒子特效(src, dst, 牌号, dst != src)
	elif dst != src:
		_行动弹道(src, dst)


## 出手时放专属特效的牌 → 特效预制体（scenes/prefabs/effects/）
## 斩击类（水 / 火 / 地 / 风 / 雷 / 暗灭）是把 3D 斩击素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/斩击2D.gd；
## 魔弹同样是把 3D 弹道素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/魔弹2D.gd；
## 圣光是原生 2D 粒子（GPUParticles2D），见 scripts/effects/粒子特效.gd。
const 特效预制表: Dictionary = {
	GConst.CardName.WaterSlash: preload("res://scenes/prefabs/effects/水斩.tscn"),
	GConst.CardName.FireSlash: preload("res://scenes/prefabs/effects/火斩.tscn"),
	GConst.CardName.EarthSlash: preload("res://scenes/prefabs/effects/地斩.tscn"),
	GConst.CardName.WindSlash: preload("res://scenes/prefabs/effects/风斩.tscn"),
	GConst.CardName.ThunderSlash: preload("res://scenes/prefabs/effects/雷斩.tscn"),
	GConst.CardName.DarkSlash: preload("res://scenes/prefabs/effects/暗灭.tscn"),
	GConst.CardName.Missile: preload("res://scenes/prefabs/effects/魔弹.tscn"),
	GConst.CardName.HolyLight: preload("res://scenes/prefabs/effects/圣光.tscn"),
}


## 这条 Card 消息里有没有「要放特效」的牌，有就返回其牌号，没有返回 -1
func _特效牌号(msg: Dictionary) -> int:
	for raw: Variant in msg.get("card_ids", []):
		var 牌: GCard = Data.get_card(int(raw))
		if 牌 != null and 特效预制表.has(牌.card_name_enum()):
			return 牌.id
	return -1


## 出手特效：按卡名取专属预制体，放到出牌者 / 目标身上播一次。
## 飞行 = true 从出牌者飞向目标（攻击 / 应战反击 / 指向性法术）；
## 飞行 = false 在目标身上原地炸开（【圣光】抵挡：引擎广播的 src 与 dst 是同一人）。
func _粒子特效(src_id: int, dst_id: int, card_id: int, 飞行: bool) -> void:
	var 牌: GCard = Data.get_card(card_id)
	var 起点: 战斗玩家面板 = _玩家面板(src_id)
	var 终点: 战斗玩家面板 = _玩家面板(dst_id)
	if 牌 == null or 起点 == null or 终点 == null or Root == null:
		return
	var go: Node2D = (特效预制表[牌.card_name_enum()] as PackedScene).instantiate() as Node2D
	Root.add_child(go)
	go.call("播放", 起点.get_global_rect().get_center(), 终点.get_global_rect().get_center(), 飞行)


## 公用的出牌弹道：从出牌者面板飞一道粒子到目标面板（对照参考工程 BattleUIMobile.actionAnim）
func _行动弹道(src_id: int, dst_id: int) -> void:
	var 起点: 战斗玩家面板 = _玩家面板(src_id)
	var 终点: 战斗玩家面板 = _玩家面板(dst_id)
	if 起点 == null or 终点 == null or Root == null:
		return
	var ps: PackedScene = load(预制目录 + "Arrow.tscn")
	if ps == null:
		return
	var go: Node = ps.instantiate()
	Root.add_child(go)
	# 取面板中心（立绘所在处）而不是左上角：AnimationPos 在移植时退化成了面板自身
	var 起: Vector2 = 起点.get_global_rect().get_center()
	var 止: Vector2 = 终点.get_global_rect().get_center()
	go.call("SetParms", Vector3(起.x, 起.y, 0.0), Vector3(止.x, 止.y, 0.0))


## 按玩家 id 找面板（找不到返回 null）
func _玩家面板(player_id: int) -> 战斗玩家面板:
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID == player_id:
			return 面板
	return null


func _on_hit(src_id: int, dst_id: int, hit: int) -> void:
	# 命中判定：只在真命中时响（未命中不出声）；这两条 ogg 听感与文件名相反，故取 sys-hurt
	if hit == 1:
		Audio.播音效("sys-hurt")
	var s: GPlayer = Data.get_player_by_id(src_id)
	var d: GPlayer = Data.get_player_by_id(dst_id)
	_日志追加("%s 对 %s 的攻击%s" % [
		s.nickname if s != null else str(src_id),
		d.nickname if d != null else str(dst_id),
		"命中" if hit == 1 else "未命中",
	])


func _on_hurt(msg: Dictionary) -> void:
	# 受击音效：攻击伤害在 _on_hit（命中判定）里响过一次，法术伤害没有命中判定，这里补上同样的一声
	if int(msg.get("type", 0)) == GConst.HarmType.Magic:
		Audio.播音效("sys-hurt")
	Audio.播音效("sys-hit")   # 同 _on_hit：两条音按听感对调
	var dst: int = int(msg.get("dst_id", -1))
	var src: int = int(msg.get("src_id", -1))
	var d: GPlayer = Data.get_player_by_id(dst)
	var s: GPlayer = Data.get_player_by_id(src)
	_日志追加("%s 对 %s 造成 %d 点%s伤害" % [
		s.nickname if s != null else str(src),
		d.nickname if d != null else str(dst),
		int(msg.get("hurt", 0)),
		"法术" if int(msg.get("type", 0)) == GConst.HarmType.Magic else "攻击",
	])


func _on_skill(msg: Dictionary) -> void:
	var src: int = int(msg.get("src_id", -1))
	var p: GPlayer = Data.get_player_by_id(src)
	# 技能全称带分类，如「发动【独有技·响应】疾风技」（对照设计表「技能表」的派系/类型列）
	_日志追加("%s 发动%s" % [
		p.nickname if p != null else str(src),
		GConst.skill_title(int(msg.get("skill_id", 0))),
	])


## 玩家发言：既进日志，也在聊天区加一条
func _on_gossip(txt: String) -> void:
	_日志追加(txt)
	_加聊天(txt)
	_判胜负(txt)


## 系统公告（超时 / 掉线 / 重连 / 终局等）：只进日志，不进聊天区
func _on_notice(txt: String) -> void:
	_日志追加(txt)
	_判胜负(txt)


## 聊天条目：ChatItem.tscn（挂 ChatItem.gd，有 set_Msg / set_IsMainPlayer）
func _加聊天(txt: String) -> void:
	var ps: PackedScene = load(预制目录 + "ChatItem.tscn")
	if ps == null:
		return
	var go: Node = ps.instantiate()
	if go is Control:
		(go as Control).position = Vector2.ZERO
		(go as Control).scale = Vector2.ONE
	Content.add_child(go)
	go.call("set_Msg", txt)
	go.call("set_IsMainPlayer", false)


## 日志：攒进缓冲后交给 Content_2 上的 AutoClearLog 按行裁剪
func _日志追加(t: String) -> void:
	_日志 += t + "\n"
	if Content_2.has_method("AutoClearText"):
		Content_2.call("AutoClearText", _日志, 日志最大行)
	else:
		Content_2.text = _日志


# ============================================================
# 结算 / 返回
# ============================================================
func _on_game_over(winner: int) -> void:
	_结算(winner)


## 从公告里识别终局：本项目没有单独的终局信号（Logic.game_over 从未 emit），
## 旧界面 battle.gd 也是从公告文本里认「获胜」两个字
func _判胜负(txt: String) -> void:
	if _胜负已定 or not txt.contains("获胜"):
		return
	var 胜方: int = GConst.RED if txt.contains("红") else (GConst.BLUE if txt.contains("蓝") else GConst.TEAM_NONE)
	_结算(胜方)


## 结算：胜负音乐 + 结算面板（只做一次）
func _结算(胜方: int) -> void:
	if _胜负已定 or 胜方 == GConst.TEAM_NONE:
		return
	_胜负已定 = true
	var me: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 胜: bool = me != null and me.color == 胜方
	# 胜负切音乐（对照参考项目 AudioManager：Win/Lose → play_bgm_scene(2, 胜否)）
	Audio.播放音乐(Audio.场景战斗, 胜)
	EndTxt.text = "胜利" if 胜 else "失败"
	# WinPanel 及其子节点在场景里都是 visible=false，展开时一并打开
	# （同参考脚本 _show_win_children 的处理）
	WinPanel.visible = true
	EndTxt.visible = true
	BtnBack.visible = true
	_日志追加("游戏结束：%s" % ("红队获胜" if 胜方 == GConst.RED else "蓝队获胜"))


## 返回大厅（同 battle.gd 的 _on_leave）
func _on_back() -> void:
	Logic.leave_room()
	UI.goto_lobby()


# ============================================================
# 聊天输入
# ============================================================
func _on_submit() -> void:
	var txt: String = InputField.text.strip_edges()
	if txt == "":
		return
	InputField.text = ""
	Logic.talk(txt)


# ============================================================
# 日志 / 聊天面板展开、收起（同参考脚本 onBtnLogExpandClick / onBtnChatExpandClick）
# ============================================================
## 日志面板展开/收起：面板位置在场景里就已排好（LogRoot 锚在右边缘、offset_left = -面板宽，
## 所以它一直贴在右侧、开合只靠显隐）。参考工程那套 ±宽/2 是 Unity 的 anchoredPosition
## 语义，搬进 Godot 的 position 里算出来是错的，这里不再搬。
func _展开日志() -> void:
	LogRoot.visible = not LogRoot.visible


## 聊天面板展开/收起：同日志面板 —— 位置在场景里排好（ChatRoot_ 锚在左边缘、占左侧 641px），
## 开合只靠显隐。原来那套 ±宽/2 是照搬 Unity 的 anchoredPosition，在 Godot 里算出来跑到屏幕中间。
func _展开聊天() -> void:
	ChatRoot.visible = not ChatRoot.visible


# ============================================================
# 第三步：交互层（手牌 / 选目标 / 确定 / 取消 / 放弃 / 技能）
# 状态机与判定照旧界面 scripts/ui/battle.gd，渲染换成新界面的控件。
# 音频仍下一步统一搬。
# ============================================================

# ---------------- 收到服务端询问 ----------------
func _on_command(data: Dictionary) -> void:
	var cmds: Array = data.get("commands", [])
	if cmds.is_empty():
		return
	# 每次询问先清掉上一轮的技能按钮，避免残留
	_清空技能按钮()
	var cmd: Dictionary = cmds[0]
	var cmd_type: int = int(data.get("cmd_type", 0))
	var respond_id: int = int(cmd.get("respond_id", 0))
	if cmd_type == GConst.CmdType.Action:
		# 行动询问：第一项是通用行动，其余是角色可选技能
		if int(cmd.get("src_id", -1)) != Logic.my_player_id:
			return
		_构建技能按钮(cmds)
	else:
		# respond_id >= 100 视为「是否发动某技能」的询问
		if respond_id >= 100:
			if int(cmd.get("src_id", -1)) != Logic.my_player_id:
				return
			_skill_ask_id = respond_id
			_pending = cmd
			_pending_type = GConst.Msg.Respond
			_进入技能询问()
			return
		var args: Array = cmd.get("args", [])
		var target_id: int = -1
		if respond_id == GConst.RespondType.ReplyAttack and args.size() > 2:
			target_id = int(args[2])
		elif respond_id == GConst.RespondType.Discard or respond_id == GConst.RespondType.DiscardCover:
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.Weaken or respond_id == GConst.RespondType.Heal:
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.Bullet:
			# 魔弹传递询问：args[0] = 当前持有者（也就是该由谁来应答）
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.AdditionalAction:
			_进入额外行动(args)
			return
		if target_id != Logic.my_player_id:
			return
	_pending = cmd
	_pending_type = GConst.Msg.Action if cmd_type == GConst.CmdType.Action else GConst.Msg.Respond
	_进入待选()


## 进入待选状态（行动 / 各种响应）：决定要选几张牌、几个目标，并写提示
func _进入待选() -> void:
	_sel_cards.clear()
	_sel_players.clear()
	# 来了新询问：技能说明窗先收起来，别盖住操作
	英雄详情窗.visible = false
	_skill_targets.clear()
	_skill_cards.clear()
	_mode = 0
	var respond_id: int = int(_pending.get("respond_id", 0))
	var args: Array = _pending.get("args", [])
	if _pending_type == GConst.Msg.Action:
		# 行动阶段
		_mode = 1
		_need_cards = 1
		_need_players = 0
		_指令提示("轮到你了：先选一张手牌；攻击牌点敌方头像出手，法术牌点目标释放（不点目标＝对自己），也可点「特殊行动」「放弃行动」")
	else:
		match respond_id:
			GConst.RespondType.ReplyAttack:
				_mode = 2
				_need_cards = 1
				# 应战要指定「反击目标」（敌方、且不是原攻击者）
				_need_players = 1
				if _可应战():
					_指令提示("你被攻击了：先选出同系攻击牌，再点一名敌方玩家头像反击（不能选原攻击者）；或出【圣光】「抵挡」；或点「取消」放弃应战")
				else:
					_指令提示("你被攻击了：本次攻击无法应战，出【圣光】「抵挡」，或点「取消」放弃应战")
			GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
				_mode = 2
				_need_cards = int(args[2]) if args.size() > 2 else 1
				_指令提示("手牌超限：请选择 %d 张牌弃掉" % _need_cards)
			GConst.RespondType.Weaken:
				_mode = 2
				_need_cards = 0
				_指令提示("你被虚弱了：点「确定」强摸 %d 张牌，或点「取消」直接结束回合" % (int(args[1]) if args.size() > 1 else 0))
			GConst.RespondType.Heal:
				_mode = 2
				_need_cards = 0
				_指令提示("是否用治疗抵御本次 %d 点法术伤害？（点「确定」使用）" % (int(args[1]) if args.size() > 1 else 0))
			GConst.RespondType.Bullet:
				_mode = 2
				_need_cards = 1
				_指令提示("魔弹传递：出【魔弹】继续传递（选好牌后点亮起的敌人头像）、出【圣光】抵挡，或点「取消」承受伤害")
			_:
				_mode = 2
				_need_cards = 0
	_刷新交互()


## 是否发动技能的询问：确定=发动，取消=放弃
## args 编码：args[0]=需选牌 args[1]=需选目标 args[2]=选盖牌 args[3]=选项数 args[4..]=选项值
## 选项文案在命令的 notes 里；有选项时改为渲染选项按钮，点哪个就回哪个值
func _进入技能询问() -> void:
	_mode = 3
	var args: Array = _pending.get("args", [])
	_skill_ask_need_card = int(args[0]) if args.size() > 0 else 0
	_skill_ask_need_target = int(args[1]) if args.size() > 1 else 0
	_skill_ask_card_source = int(args[2]) if args.size() > 2 else GConst.CardSource.Hand
	# need_card 为需要选出的牌数（1 或 2），复用 _need_cards 驱动点选上限与「确定」可用性
	_need_cards = _skill_ask_need_card
	_need_players = _skill_ask_need_target
	var 选项数: int = int(args[3]) if args.size() > 3 else 0
	_skill_options.clear()
	for i: int in range(选项数):
		if args.size() > 4 + i:
			_skill_options.append(int(args[4 + i]))
	_selecting_cover = _skill_ask_card_source != GConst.CardSource.Hand
	_sel_cards.clear()
	_sel_players.clear()
	_清空技能按钮()
	# 技能询问同时写一行日志：它只挂在提示条上，错过就会一直等（看着像「点了确定没反应」）
	_日志追加("【%s】等你决定：点「确定」发动 / 点「取消」放弃" % GConst.skill_name(_skill_ask_id))
	if not _skill_options.is_empty():
		_构建选项按钮(_skill_options, _pending.get("notes", []))
	elif _selecting_cover:
		_指令提示("【%s】：请从盖牌区中选择一张" % GConst.skill_name(_skill_ask_id))
	else:
		_指令提示("是否发动【%s】？%s%s点「确定」发动，或点「取消」放弃" % [
			GConst.skill_name(_skill_ask_id),
			"（需选牌）" if _skill_ask_need_card > 0 else "",
			"（需选目标）" if _skill_ask_need_target > 0 else "",
		])
	_刷新交互()


## 额外行动询问：把每个可选 cause 变成一个按钮
func _进入额外行动(causes: Array) -> void:
	_mode = 3
	_skill_ask_id = -1
	_pending = {"args": causes}
	_pending_type = GConst.Msg.Respond
	_sel_cards.clear()
	_sel_players.clear()
	_清空技能按钮()
	for cause: Variant in causes:
		_加文本按钮(GConst.skill_name(int(cause)), _选择额外行动.bind(int(cause)))
	_指令提示("有额外行动可用，请选择（点「取消」跳过）")
	_刷新交互()


## 技能询问的选项按钮：每个可选值一个按钮，点击即回复该值
func _构建选项按钮(values: Array[int], labels: Array) -> void:
	_清空技能按钮()
	var 提示: String = "【%s】：先选好需要的牌/目标，再点选项" % GConst.skill_name(_skill_ask_id)
	if _selecting_cover:
		提示 += "（盖牌在盖牌区可点选）"
	_指令提示(提示)
	for i: int in range(values.size()):
		var v: int = values[i]
		var label: String = str(labels[i]) if i < labels.size() and str(labels[i]) != "" else GConst.skill_name(v)
		_加文本按钮(label, _选择技能选项.bind(v))


## 行动询问里附带的技能 → 生成技能按钮
func _构建技能按钮(cmds: Array) -> void:
	# 存一份，取消技能 / 取消特殊行动时要把这批技能按钮重新摆回来
	_行动命令 = cmds
	for i: int in range(1, cmds.size()):
		var c: Dictionary = cmds[i]
		var 技能类型: int = int(c.get("respond_id", 0))
		var args: Array = c.get("args", [])
		if args.is_empty():
			continue
		var 技能号: int = int(args[0])
		var 需牌: int = int(args[1]) if args.size() > 1 else 0
		var 需目标: int = int(args[2]) if args.size() > 2 else 0
		var 最多目标: int = int(args[3]) if args.size() > 3 else 0
		var 选牌来源: int = int(args[4]) if args.size() > 4 else GConst.CardSource.Hand
		var 合法目标: Array = c.get("dst_ids", [])
		var 合法牌: Array = c.get("card_ids", [])
		var 最多牌: int = int(c.get("card_max", 0))
		var 参数选项: Array = c.get("arg_choices", [])
		var go: Node = 技能预制.instantiate()
		if go is Control:
			(go as Control).custom_minimum_size = 技能尺寸
		ChildrenSkillArea.add_child(go)
		go.call("设置技能", 技能号, GConst.skill_name(技能号))
		go.connect("点击", _选择技能.bind(技能类型, 需牌, 需目标, 合法目标, 合法牌, 最多牌,
			最多目标, 选牌来源, 参数选项))
		_技能按钮.append(go)
		_显示技能区()


# ---------------- 点选 ----------------
func _on_card_clicked(card_id: int) -> void:
	# 置灰（不可用）的牌不做任何响应，也不弹提示
	if not _卡牌能点(card_id):
		return
	if _sel_cards.has(card_id):
		_sel_cards.erase(card_id)
	else:
		if _need_cards > 0 and _sel_cards.size() >= _need_cards:
			_sel_cards.clear()
		_sel_cards.append(card_id)
	# 换了牌，先前选中的目标可能不再合法（例如法术→攻击牌后队友不能再打），顺手清掉
	for pid: int in _sel_players.duplicate():
		if not _玩家可选(pid):
			_sel_players.erase(pid)
	刷新手牌()
	刷新盖牌()
	# 换了牌就要重算「哪些敌人能打」：攻击牌选出后目标才亮
	刷新选中面板()
	_更新按键()


func _on_player_pressed(面板: 战斗玩家面板) -> void:
	_on_player_clicked(面板.ID)


## 点玩家面板：只有亮起（_玩家可选）的玩家点得动；攻击 / 应战选中即出手，其余先累积选择再按「确定」。
## 点不动的时候（不是该选目标的时机 / 他不是合法目标）＝看他这名角色的技能说明
## （对照参考工程 PlayerStatusMobile.onClick：不可选就走 onLongPress → 打开英雄详情窗）
func _on_player_clicked(player_id: int) -> void:
	if not _玩家可选(player_id):
		_弹出角色技能说明(player_id)
		return
	# 攻击：选好攻击牌后点敌方头像就直接打出去，不用再按「确定」
	if _mode == 1 and _选中是攻击牌():
		_发送行动(GConst.ActionType.Attack, 0, [player_id], _sel_cards, [])
		return
	# 法术：选好法术牌后点目标就直接释放（不点目标＝对自己，那条走「确定」）
	if _mode == 1 and _选中是法术牌():
		_发送行动(GConst.ActionType.Magic, 0, [player_id], _sel_cards, [])
		return
	# 应战：选好应战牌后点反击目标就直接应战（【圣光】抵挡不需要目标，不会走到这里）
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
		_发送应答(GConst.RespondType.ReplyAttack, [player_id], _sel_cards, [GConst.Reattack.Attack])
		return
	# 魔弹传递：选好【魔弹】后点亮起的敌人头像就把伤害传下去
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.Bullet:
		_发送应答(GConst.RespondType.Bullet, [player_id], _sel_cards, [GConst.Reattack.Attack])
		return
	if _sel_players.has(player_id):
		_sel_players.erase(player_id)
	elif _need_players > 1:
		# 多目标：累积选择，超过上限则重新开始
		if _sel_players.size() >= _need_players:
			_sel_players.clear()
		_sel_players.append(player_id)
	else:
		_sel_players = [player_id]
	刷新选中面板()
	_更新按键()


## 这张牌此刻能不能点选（照 battle.gd 的 _on_card_clicked 判定）
## 同一条判定同时决定「是否置灰」与「点击是否响应」，两者不会不一致
func _卡牌能点(card_id: int) -> bool:
	# 技能询问里不要求选牌的（need_card <= 0）才整片置灰；需要选 2 张的技能同样要能点
	if _mode == 3 and _skill_ask_need_card <= 0:
		return false
	# 应答（应战/抵挡、弃牌、魔弹传递等）同样要能点手牌
	if _mode == 2 and _need_cards <= 0:
		return false
	if _mode != 1 and _mode != 2 and _mode != 3 and _mode != 4:
		return false
	# 选牌来源限制：盖牌询问只收盖牌，手牌询问只收手牌，两者皆可则都收
	if _mode == 3 and _skill_ask_id >= 100:
		if _skill_ask_card_source == GConst.CardSource.Cover and not _is_my_cover(card_id):
			return false
		if _skill_ask_card_source == GConst.CardSource.Hand and _is_my_cover(card_id):
			return false
	# 应战：只有「同系攻击牌」和【圣光】能用
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
		return _可应战牌(card_id)
	# 魔弹传递：只有【圣光】（抵挡）或【魔弹】/火系/地系牌（继续传递）能用
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.Bullet:
		return _可回魔弹牌(card_id)
	# 行动阶段：只有能主动出手的牌可点（【圣光】只作响应，回合内置灰点不动）
	if _mode == 1:
		return _可主动使用牌(card_id)
	# 发动技能：按服务端给的选牌来源过滤（手牌 / 盖牌区 / 场上基础效果牌），再看合法牌白名单
	if _mode == 4:
		match _skill_card_source:
			GConst.CardSource.Cover:
				if not _is_my_cover(card_id):
					return false
			GConst.CardSource.BasicEffect:
				if not _是场上基础效果牌(card_id):
					return false
			_:
				if _is_my_cover(card_id):
					return false
		return _skill_cards.is_empty() or _skill_cards.has(card_id)
	# 特殊行动（购买/合成/提炼）期间不点牌
	if _mode == 5 or _mode == 6:
		return false
	return true


## 行动阶段能不能拿这张牌出手：攻击牌，以及能主动施放的【圣盾 / 虚弱 / 中毒 / 魔弹】。
## 【圣光】只作响应（应战攻击 / 抵挡魔弹），回合内打出去只会被服务端拒，所以直接置灰。
func _可主动使用牌(card_id: int) -> bool:
	var 牌: GCard = Data.get_card(card_id)
	if 牌 == null:
		return false
	if 牌.is_attack():
		return true
	# 【暗影抗拒】（904）：行动阶段不能使用法术牌 —— 整片置灰，点了必被服务端拒
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 != null and 行动阶段禁用法术牌角色.has(我.role_id):
		return false
	match 牌.card_name_enum():
		GConst.CardName.Shield, GConst.CardName.Weaken, GConst.CardName.Poison, GConst.CardName.Missile:
			return true
		_:
			return false


## 这张牌能不能用来回应【魔弹】：
##   任何角色：出【魔弹】继续传递、出【圣光】抵挡；
##   魔导 / 特殊魔导（【魔弹融合】803）：地系、火系牌也能当【魔弹】打出去传递；
##   魔枪（【黑暗束缚】2903）：既不能转弹也不能圣光格挡，只能放弃。
## role_id 对照 battle_role.gd 的角色工厂与 role_modao / role_spmodao / role_moqiang 的校验覆写。
func _可回魔弹牌(card_id: int) -> bool:
	var 牌: GCard = Data.get_card(card_id)
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 牌 == null or 我 == null:
		return false
	if 魔弹全禁角色.has(我.role_id):
		return false
	var 卡名: int = 牌.card_name_enum()
	if 卡名 == GConst.CardName.HolyLight or 卡名 == GConst.CardName.Missile:
		return true
	if not 地火可作魔弹角色.has(我.role_id):
		return false
	var 元素: int = 牌.element_enum()
	return 元素 == GConst.CardElement.Fire or 元素 == GConst.CardElement.Earth


## 这张牌能不能用来应战本次攻击（规则对照服务端 BattlePlayer.base_v_reattack / base_v_block）：
## 需为攻击牌且与本次攻击同系（暗系攻击牌可替任意系）；本次攻击本身是暗系则一律不可应战；【圣光】走抵挡
func _可应战牌(card_id: int) -> bool:
	var 牌: GCard = Data.get_card(card_id)
	if 牌 == null:
		return false
	if 牌.card_name_enum() == GConst.CardName.HolyLight:
		return _可圣光抵挡()
	if not _可应战() or not 牌.is_attack():
		return false
	var args: Array = _pending.get("args", [])
	var 攻击牌: GCard = Data.get_card(int(args[1])) if args.size() > 1 else null
	if 攻击牌 == null or 攻击牌.element_enum() == GConst.CardElement.Darkness:
		return false
	return 牌.element_enum() == 攻击牌.element_enum() or 牌.element_enum() == GConst.CardElement.Darkness


## 本次攻击能否用【圣光】抵挡（args[4] = can_light，有技能会让对方无法抵挡）
func _可圣光抵挡() -> bool:
	var args: Array = _pending.get("args", [])
	return int(args[4]) != 0 if args.size() > 4 else true


# ---------------- 确定 / 取消 / 放弃 ----------------
func _on_ok() -> void:
	var respond_id: int = int(_pending.get("respond_id", 0))
	var args: Array = _pending.get("args", [])
	# 是否发动技能的询问
	if _mode == 3:
		if _skill_ask_id >= 100:
			_发送应答(_skill_ask_id, _sel_players, _sel_cards, [1])
		return
	# 发动技能
	if _mode == 4:
		_发送行动(_pending_skill_type, _pending_skill_id, _sel_players, _sel_cards, [])
		return
	if _pending_type == GConst.Msg.Action:
		if _sel_cards.is_empty():
			_指令提示("请先选择一张手牌")
			return
		var card: GCard = Data.get_card(_sel_cards[0])
		if card == null:
			_指令提示("这张牌已不在手里，请重新选一张")
			return
		if card.is_attack():
			if _sel_players.is_empty():
				_指令提示("攻击请点敌方头像出手（选好攻击牌后直接点要打的人）")
				return
			_发送行动(GConst.ActionType.Attack, 0, _sel_players, _sel_cards, [])
		else:
			var dst: Array = _sel_players
			if dst.is_empty():
				dst = [Logic.my_player_id]
			_发送行动(GConst.ActionType.Magic, 0, dst, _sel_cards, [])
		return
	match respond_id:
		GConst.RespondType.ReplyAttack:
			if _sel_cards.is_empty():
				_指令提示("请先选择一张手牌（同系攻击牌应战，或【圣光】抵挡）")
				return
			var card2: GCard = Data.get_card(_sel_cards[0])
			if card2 == null:
				_指令提示("这张牌已不在手里，请重新选一张")
				return
			# 【圣光】抵挡：不需要反击目标
			if card2.card_name_enum() == GConst.CardName.HolyLight:
				_发送应答(respond_id, [], _sel_cards, [GConst.Reattack.Block])
				return
			if not _可应战():
				_指令提示("本次攻击无法应战：请出【圣光】「抵挡」，或点「取消」放弃应战")
				return
			if _sel_players.is_empty():
				_指令提示("应战请点敌方头像出手（选好应战牌后直接点要反击的人），或点「取消」放弃应战")
				return
			_发送应答(respond_id, _sel_players, _sel_cards, [GConst.Reattack.Attack])
		GConst.RespondType.Bullet:
			# 出【圣光】＝抵挡（魔弹终止）；出【魔弹】＝点下一个落点把伤害传下去
			if _sel_cards.is_empty():
				_指令提示("请先选一张手牌：出【魔弹】继续传递，或出【圣光】抵挡")
				return
			if _选中是圣光():
				_发送应答(respond_id, [], _sel_cards, [GConst.Reattack.Block])
				return
			if _sel_players.is_empty():
				_指令提示("魔弹传递请点亮起的敌人头像（选好牌后直接点他），或点「取消」承受伤害")
				return
			_发送应答(respond_id, _sel_players, _sel_cards, [GConst.Reattack.Attack])
		GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
			_发送应答(respond_id, [], _sel_cards, [])
		GConst.RespondType.Weaken:
			_发送应答(respond_id, [], [], [1])
		GConst.RespondType.Heal:
			var harm: int = int(args[1]) if args.size() > 1 else 0
			_发送应答(respond_id, [], [], [harm])
		_:
			_发送应答(respond_id, [], _sel_cards, [])


func _on_cancel() -> void:
	var respond_id: int = int(_pending.get("respond_id", 0))
	# 技能询问：取消=放弃
	if _mode == 3:
		if _skill_ask_id >= 100:
			_发送应答(_skill_ask_id, [], [], [0])
		else:
			# 额外行动：空 args 表示跳过
			Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [])
			_清空待选()
		return
	# 发动技能 / 特殊行动三选一 / 特殊行动星石选择时取消：退回行动阶段
	if _mode == 4 or _mode == 5 or _mode == 6:
		_pending_skill_id = -1
		_回到行动阶段()
		return
	# 虚弱：取消＝不强摸
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Weaken:
		_发送应答(respond_id, [], [], [0])
		return
	# 应战：取消＝放弃应战（原先这一功能挂在「放弃行动」按钮上，挪到「取消」上）
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.ReplyAttack:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	# 魔弹传递：取消＝不转弹、不抵挡，直接承受这次魔弹伤害
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Bullet:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	# 其余：只清空已选，仍停留在本次询问
	_sel_cards.clear()
	_sel_players.clear()
	刷新手牌()
	刷新盖牌()
	刷新选中面板()
	_更新按键()


## 「盖牌」按钮（场景里的 BtnCovered，图标就是「盖牌」）：点开/收起自己的盖牌，只读，不结束回合
func _on_cover_view() -> void:
	if Data.cover_cards.is_empty():
		return
	_查看盖牌 = not _查看盖牌
	刷新盖牌()


## 弹出某名玩家的角色技能说明（点头像点不动时走这条：不是该选目标的时机 / 他不是合法目标）
func _弹出角色技能说明(player_id: int) -> void:
	var p: GPlayer = Data.get_player_by_id(player_id)
	if p == null or p.role_id <= 0:
		return
	英雄详情窗.打开(p.role_id)


## 放弃行动（场景里的 BtnResign；对照参考工程 RoleBase 的 ResignAction → ACTION_NONE）
func _on_resign() -> void:
	_发送行动(GConst.ActionType.None, 0, [], [], [])


## 特殊行动 / 放弃（场景 BtnSpecila，图标就是 action 键）
func _on_giveup() -> void:
	# 行动阶段：打开「购买 / 合成 / 提炼」（对照参考工程 PlayerAgentUI.onBtnSpecialClick → SpecialActionUI）
	if _mode == 1:
		_进入特殊行动()
		return
	var respond_id: int = int(_pending.get("respond_id", 0))
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.ReplyAttack:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Bullet:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	_发送行动(GConst.ActionType.None, 0, [], [], [])


# ---------------- 特殊行动（购买 / 合成 / 提炼） ----------------
## 行动阶段点「特殊行动」进来：三选一。
## 可用性逐条对照原客户端 Role::normal / Role::buy / Role::synthetize / Role::extract：
##   购买 = 手牌放得下 3 张；合成 = 放得下且我方战绩区星石 ≥ 3；提炼 = 自己能量没满且战绩区有星石
func _进入特殊行动() -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return
	_mode = 5
	_清空技能按钮()
	var 战绩: GTeam = Data.team_of(我.color)
	var 星石: int = 战绩.gem + 战绩.crystal
	var 放得下: bool = 我.hand_cards_num + 3 <= 我.hand_cards_max
	特殊行动窗.打开(放得下, 放得下 and 星石 >= 3, 我.get_energy() < 我.energy_max and 星石 > 0)
	# 窗口自带标题和三个写着「购买/合成/提炼」的大按钮，战斗界面的提示条要收起来：
	# 提示条就在窗口标题那一行上，不收就会两段文字叠在一起
	_收起提示()
	刷新选中面板()
	_更新按键()


## 特殊行动窗口里选中了一种行动：先关窗，再进入「用哪些星石」那一层（或直接提交）
func _on_special_action_chosen(action_id: int) -> void:
	特殊行动窗.visible = false
	_选特殊行动(action_id)


## 特殊行动窗口里点了取消：退回行动阶段
func _on_special_action_cancelled() -> void:
	特殊行动窗.visible = false
	_回到行动阶段()


## 参数选择窗口里选好了一组星石：按当初选的那个特殊行动提交
func _on_参数选择(参数: Array) -> void:
	if 参数.size() < 2:
		return
	_发送特殊行动(_待定特殊行动, int(参数[0]), int(参数[1]))


## 参数选择窗口里点了取消：退回上一层「购买 / 合成 / 提炼」三选一
func _on_参数选择取消() -> void:
	_进入特殊行动()


## 选定一种特殊行动后，再选「用哪些星石」——选项逐条对照原客户端
## Role::buy（战绩区 4 个时二选一、5 个已满）/ Role::synthetize / Role::extract 的选项盒
func _选特殊行动(action_id: int) -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return
	var 战绩: GTeam = Data.team_of(我.color)
	var 宝石: int = 战绩.gem
	var 水晶: int = 战绩.crystal
	var 组合: Array = []
	match action_id:
		GConst.SpecialAction.Buy:
			# 冒险家（【地下法则】）只加宝石、一次最多 2 点（role_maoxian.v_buy）
			var 地下法则: bool = 我.role_id == 冒险家角色号
			if 宝石 + 水晶 < 4:
				if 地下法则:
					组合.append({"text": "战绩区 +2 宝石", "gem": 2, "crystal": 0})
				else:
					组合.append({"text": "战绩区 +1 宝石 +1 水晶", "gem": 1, "crystal": 1})
			elif 宝石 + 水晶 == 4:
				组合.append({"text": "一个宝石", "gem": 1, "crystal": 0})
				if not 地下法则:
					组合.append({"text": "一个水晶", "gem": 0, "crystal": 1})
			else:
				组合.append({"text": "战绩区已满，不再加星石", "gem": 0, "crystal": 0})
		GConst.SpecialAction.Synthesize:
			if 水晶 >= 3:
				组合.append({"text": "三个水晶", "gem": 0, "crystal": 3})
			if 水晶 >= 2 and 宝石 >= 1:
				组合.append({"text": "两个水晶和一个宝石", "gem": 1, "crystal": 2})
			if 水晶 >= 1 and 宝石 >= 2:
				组合.append({"text": "一个水晶和两个宝石", "gem": 2, "crystal": 1})
			if 宝石 >= 3:
				组合.append({"text": "三个宝石", "gem": 3, "crystal": 0})
		_:
			var 余量: int = 我.energy_max - 我.get_energy()
			if 余量 >= 2:
				if 宝石 >= 2:
					组合.append({"text": "两个宝石", "gem": 2, "crystal": 0})
				if 水晶 >= 2:
					组合.append({"text": "两个水晶", "gem": 0, "crystal": 2})
				if 宝石 >= 1 and 水晶 >= 1:
					组合.append({"text": "一个宝石和一个水晶", "gem": 1, "crystal": 1})
			if 宝石 >= 1:
				组合.append({"text": "一个宝石", "gem": 1, "crystal": 0})
			if 水晶 >= 1:
				组合.append({"text": "一个水晶", "gem": 0, "crystal": 1})
	if 组合.is_empty():
		_指令提示("没有可用的星石组合")
		return
	if 组合.size() == 1:
		# 只有一种组合（如购买时的「+1 宝石 +1 水晶」「战绩区已满」）就不用再问一遍
		var 只: Dictionary = 组合[0]
		_发送特殊行动(action_id, int(只["gem"]), int(只["crystal"]))
		return
	_mode = 6
	_清空技能按钮()
	# 第二层（选「用哪些星石」）用从参考工程搬来的参数选择窗口 —— 对应 ChooseArgsUI 的 "Energy" 分支
	var 选项: Array = []
	for 项: Variant in 组合:
		var d: Dictionary = 项
		选项.append({"text": str(d["text"]), "args": [int(d["gem"]), int(d["crystal"])]})
	_待定特殊行动 = action_id
	# 合成 / 提炼是从战绩区把星石花掉，标题写「消耗能量」；购买是往战绩区加星石，写「选择能量」
	var 标题: String = "选择能量" if action_id == GConst.SpecialAction.Buy else "消耗能量"
	参数选择窗.打开(标题, 选项)
	_指令提示("请选择要使用的星石")
	刷新选中面板()
	_更新按键()


## 发出特殊行动：args = [宝石数, 水晶数]（服务端 _do_special 按这个口径结算）
func _发送特殊行动(action_id: int, gem: int, crystal: int) -> void:
	_发送行动(GConst.ActionType.Special, action_id, [], [], [gem, crystal])


## 退回行动阶段（取消发动技能 / 取消特殊行动时用），顺手把本回合的技能按钮摆回来
func _回到行动阶段() -> void:
	_mode = 1
	特殊行动窗.visible = false
	参数选择窗.visible = false
	英雄详情窗.visible = false
	_sel_cards.clear()
	_sel_players.clear()
	_清空技能按钮()
	if not _行动命令.is_empty():
		_构建技能按钮(_行动命令)
	_指令提示("轮到你了：选择一张手牌作为攻击/法术，或点「特殊行动」「放弃行动」")
	刷新手牌()
	刷新盖牌()
	刷新选中面板()
	_更新按键()


# ---------------- 技能动作 ----------------
## 选中并准备发动某个技能（行动阶段点技能按钮）
## 合法目标 / 合法牌由服务端的技能声明给出（targets / cards），非空时界面只让它们可点；
## 需牌是最少张数、最多牌（card_max）是点选上限（省略＝刚好 need_card 张），目标数同理走 target_max；
## 选牌来源 card_source 决定是从手牌、盖牌区还是场上基础效果牌里选；
## 参数选项 arg_choices 非空时改由选项按钮提交（服务端靠 args 的技能都走这条）
func _选择技能(技能号: int, 技能类型: int, 需牌: int, 需目标: int, 合法目标: Array = [], 合法牌: Array = [],
		最多牌: int = 0, 最多目标: int = 0, 选牌来源: int = GConst.CardSource.Hand, 参数选项: Array = []) -> void:
	_mode = 4
	_pending_skill_type = 技能类型
	_pending_skill_id = 技能号
	_skill_need_card = 需牌
	_skill_need_target = 需目标
	_skill_card_max = maxi(需牌, 最多牌)
	_skill_target_max = maxi(需目标, 最多目标)
	_skill_card_source = 选牌来源
	_skill_arg_choices = 参数选项
	# 复用 _need_cards / _need_players 驱动点选上限与「确定」可用性（同 _进入技能询问）
	_need_cards = _skill_card_max
	_need_players = _skill_target_max
	_skill_targets.clear()
	for t: Variant in 合法目标:
		_skill_targets.append(int(t))
	_skill_cards.clear()
	for 牌号: Variant in 合法牌:
		_skill_cards.append(int(牌号))
	_sel_cards.clear()
	_sel_players.clear()
	# 盖牌来源才让盖牌区亮起来；基础效果牌由玩家面板上的图标直接点
	_selecting_cover = 选牌来源 == GConst.CardSource.Cover
	if not 参数选项.is_empty():
		_构建技能参数按钮()
		_指令提示("发动【%s】：%s%s再点下面的选项" % [
			GConst.skill_name(技能号), _需选牌提示(需牌), _需选目标提示(需目标),
		])
	else:
		_指令提示("发动【%s】：%s%s点「确定」" % [
			GConst.skill_name(技能号), _需选牌提示(需牌), _需选目标提示(需目标),
		])
	_刷新交互()


## 「要选几张牌」的提示文案（含来源：手牌 / 盖牌 / 场上基础效果牌）
func _需选牌提示(需牌: int) -> String:
	if 需牌 <= 0:
		return ""
	var 来源: String = "手牌"
	match _skill_card_source:
		GConst.CardSource.Cover:
			来源 = "盖牌"
		GConst.CardSource.BasicEffect:
			来源 = "场上基础效果牌"
	return "从%s中选%d张，" % [来源, 需牌]


func _需选目标提示(需目标: int) -> String:
	if 需目标 <= 0:
		return ""
	if _skill_target_max > 需目标:
		return "选%d~%d名目标，" % [需目标, _skill_target_max]
	return "选%d名目标，" % 需目标


## 把服务端给的参数选项（arg_choices）渲染成按钮：点哪个就用当前已选的牌/目标提交该项 args
## 每项可带 need_card / need_target：要求先选够牌或目标才让点（如「对目标造成伤害」「弃光手牌」）
func _构建技能参数按钮() -> void:
	_清空技能按钮()
	for 项: Variant in _skill_arg_choices:
		var d: Dictionary = 项
		_加文本按钮(str(d.get("text", "")), _提交技能参数.bind(d.get("args", [])))
		_参数按钮.append({
			"按钮": _技能按钮[_技能按钮.size() - 1],
			"需牌": int(d.get("need_card", 0)),
			"需目标": int(d.get("need_target", 0)),
			"目标白名单": d.get("targets", []),
		})


func _提交技能参数(参数: Array) -> void:
	_发送行动(_pending_skill_type, _pending_skill_id, _sel_players, _sel_cards, 参数)


## 选择某技能选项：连同已选目标/卡牌一并回传
func _选择技能选项(值: int) -> void:
	_发送应答(_skill_ask_id, _sel_players, _sel_cards, [值])


func _选择额外行动(cause: int) -> void:
	Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [cause])
	_清空待选()


# ---------------- 提交 / 复位 ----------------
func _发送行动(action_type: int, action_id: int, dst: Array, cards: Array, args: Array) -> void:
	Logic.send_action(action_type, action_id, dst, cards, args)
	_清空待选()


func _发送应答(respond_id: int, dst: Array, cards: Array, args: Array) -> void:
	Logic.send_respond(respond_id, dst, cards, args)
	_清空待选()


func _清空待选() -> void:
	_pending = {}
	_pending_type = -1
	_mode = 0
	英雄详情窗.visible = false
	_行动命令.clear()
	_skill_ask_id = -1
	_skill_ask_need_card = 0
	_skill_ask_need_target = 0
	_skill_ask_card_source = 0
	_selecting_cover = false
	_skill_options.clear()
	_pending_skill_id = -1
	_pending_skill_type = -1
	_skill_target_max = 0
	_skill_card_source = GConst.CardSource.Hand
	_skill_arg_choices.clear()
	_查看盖牌 = false
	特殊行动窗.visible = false
	参数选择窗.visible = false
	_sel_cards.clear()
	_sel_players.clear()
	_清空技能按钮()
	_收起提示()
	_刷新交互()


## 操作无效（ErrorInput 由 Logic 回调进来）：提示并重新进入本次询问
func on_invalid_input(_data: Dictionary) -> void:
	_进入待选()
	# 放在 _进入待选 之后：那个函数会写「轮到你了…」，这里再盖成失败原因，
	# 不然玩家只看到选择被清空、完全不知道刚才那手为什么没生效（日志里也留一行）
	_指令提示("操作无效，请重新选择")
	_日志追加("操作无效，请重新选择")


# ---------------- 规则判定（照 battle.gd 抄） ----------------
## 本次应战询问是否允许应战（args[0] = 命中率：非普通命中率不允许应战）
func _可应战() -> bool:
	var args: Array = _pending.get("args", [])
	if args.is_empty():
		return true
	return int(args[0]) == GConst.HitRate.Normal


## 本次攻击的原攻击者（args[3]）：应战的反击目标不能是他
func _原攻击者() -> int:
	var args: Array = _pending.get("args", [])
	return int(args[3]) if args.size() > 3 else -1


## 应战的反击目标是否可选：敌方玩家、且不是原攻击者（规则同服务端 v_reattack）
func _可作反击目标(player_id: int) -> bool:
	if player_id == Logic.my_player_id or player_id == _原攻击者():
		return false
	return _是敌方(player_id)


## 是不是「敌方玩家」：双方都已分队、且队色不同。
## 服务端 v_attack 对同队直接回 GE_INVALID_ACTION（19），v_reattack 还要求目标非 TEAM_NONE ——
## 这里取两者的交集：不符合的玩家不亮、也点不动，不会等发出去了才被服务端拒。
func _是敌方(player_id: int) -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 他: GPlayer = Data.get_player_by_id(player_id)
	if 我 == null or 他 == null:
		return false
	return 我.color != GConst.TEAM_NONE and 他.color != GConst.TEAM_NONE and 我.color != 他.color


## 法术牌的可选目标：对照服务端 BattleEngine._do_magic 的分支
##   圣盾 / 虚弱：目标面前不能已有同名基础效果（v_shield / v_weaken 会拒）
##   中毒：任意玩家
##   魔弹：默认落点是右手边最近的敌人（服务端 _nearest_enemy 沿 post 方向找），只有他亮；
##         本地角色有【魔弹掌握】802 时左右各一个都能选
##   其余法术牌（如【圣光】只作响应）不能主动施放 → 谁都不亮
func _可作法术目标(牌: GCard, player_id: int) -> bool:
	match 牌.card_name_enum():
		GConst.CardName.Shield:
			return not _有基础效果(player_id, GConst.CardName.Shield)
		GConst.CardName.Weaken:
			return not _有基础效果(player_id, GConst.CardName.Weaken)
		GConst.CardName.Poison:
			return true
		GConst.CardName.Missile:
			# 默认只有右手边那个对手；有【魔弹掌握】时左手边那个也能选（逆向传递）
			return player_id == _魔弹目标() or (_有魔弹掌握() and player_id == _魔弹逆向目标())
		_:
			return false


## 【魔弹】的落点：右手边（post 方向）最近的一名敌人 —— 服务端 _nearest_enemy 就是这么走的。
## 没有【魔弹掌握】时目标就固定是他；界面只让他亮，点了他才释放。
func _魔弹目标() -> int:
	return _沿方向找敌人(1)


## 【魔弹】的逆向落点：左手边（pre 方向）最近的一名敌人 —— 只有【魔弹掌握】802 能选
func _魔弹逆向目标() -> int:
	return _沿方向找敌人(-1)


## 从自己在座位表里的位置出发，按 step（+1 = 右手边 / -1 = 左手边）找最近的一名敌人
func _沿方向找敌人(step: int) -> int:
	var 列表: Array[GPlayer] = Data.player_list
	var n: int = 列表.size()
	var 我的: int = -1
	for i: int in range(n):
		if 列表[i].id == Logic.my_player_id:
			我的 = i
			break
	if 我的 < 0:
		return -1
	for k: int in range(1, n):
		var p: GPlayer = 列表[(我的 + step * k + n * n) % n]
		if _是敌方(p.id):
			return p.id
	return -1


## 本地角色有没有【魔弹掌握】（802）：有的话打【魔弹】时左手边那个对手也亮
func _有魔弹掌握() -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	return 我 != null and 魔弹掌握角色.has(我.role_id)


## 魔弹传递的可选落点：服务端在询问的 dst_ids 里给（默认只有当前传出方向上那个人；
## 本地角色有【魔弹掌握】时左右各一个）。界面只把这些点亮，点谁就把魔弹传给谁。
func _魔弹传递目标列表() -> Array[int]:
	var out: Array[int] = []
	for t: Variant in _pending.get("dst_ids", []):
		out.append(int(t))
	return out


## 这名玩家面前是否已经有某个基础效果（取自快照里的 basic_cards）
func _有基础效果(player_id: int, 卡名: int) -> bool:
	var 他: GPlayer = Data.get_player_by_id(player_id)
	if 他 == null:
		return false
	for 效果: GPlayer.BasicStatus in 他.basic_status_list:
		if 效果.card != null and 效果.card.card_name_enum() == 卡名:
			return true
	return false


## 选中的手牌是否是【圣光】（抵挡用，不需要反击目标）
func _选中是圣光() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.card_name_enum() == GConst.CardName.HolyLight


## 选中的手牌是不是攻击牌（点目标即出手）
func _选中是攻击牌() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.is_attack()


## 选中的手牌是不是法术牌（同样点目标即释放，只是目标规则不同）
func _选中是法术牌() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.is_magic()


## 该卡牌是否为自己的盖牌
func _is_my_cover(card_id: int) -> bool:
	for cc: GCard in Data.cover_cards:
		if cc != null and cc.id == card_id:
			return true
	return false


# ============================================================
# 渲染：手牌 / 盖牌 / 玩家面板选中 / 按钮
# ============================================================
func _刷新交互() -> void:
	刷新手牌()
	刷新盖牌()
	刷新选中面板()
	_更新按键()
	# 只有「从场上基础效果牌里选牌」的技能才让面板上的基础效果图标可点
	var 基础可点: bool = _mode == 4 and _skill_card_source == GConst.CardSource.BasicEffect
	for 面板: 战斗玩家面板 in _面板列表:
		面板.set_基础牌可点(基础可点)


## 点了场上的某枚基础效果图标（【封印破碎】要选的就是它）：连它所在的玩家一起记下来
func _on_基础牌点击(玩家id: int, 牌id: int) -> void:
	if _mode != 4 or _skill_card_source != GConst.CardSource.BasicEffect:
		return
	if not _卡牌能点(牌id):
		return
	_sel_cards = [牌id]
	_sel_players = [玩家id]
	刷新盖牌()
	刷新选中面板()
	_更新按键()


## 我的手牌：固定排成一行并水平居中；位置够就摊开，不够才压间距（压到负数会叠着放），绝不换行
## 每张牌按 _卡牌能点 单独判定：够格的亮起来，其余的置灰且点不动
func 刷新手牌() -> void:
	for c: Node in HandArea.get_children():
		c.queue_free()
	var 张数: int = Data.hand_cards.size()
	if 张数 == 0:
		return
	var 可用宽: float = HandArea.size.x
	# 相邻两张之间的空隙：牌少时贴着排（0 是最好的），一行放不下才压成负数（叠着放）
	var 空隙: float = 0.0
	if 张数 > 1:
		空隙 = clampf((可用宽 - 手牌尺寸.x * float(张数)) / float(张数 - 1),
			-手牌尺寸.x * 手牌最多重叠比例, 0.0)
	# 两牌「左边」的距离 = 牌宽 + 空隙
	var 间距: float = 手牌尺寸.x + 空隙
	var 起点: float = (可用宽 - (手牌尺寸.x * float(张数) + 空隙 * float(张数 - 1))) * 0.5
	for i: int in range(张数):
		var card: GCard = Data.hand_cards[i]
		var go: Node = _加卡牌(HandArea, card, 手牌尺寸, _卡牌能点(card.id))
		go.call("设置选中", _sel_cards.has(card.id))
		var ctl: Control = go as Control
		ctl.position = Vector2(起点 + 间距 * float(i), (HandArea.size.y - 手牌尺寸.y) * 0.5)


## 我的盖牌渲染进 ChooseArea（它不是布局容器，所以这里手工排成一行）。
## 「要选盖牌」时可见且可点；点「盖牌」按钮查看时只可见、点不动。
func 刷新盖牌() -> void:
	for c: Node in ChooseArea.get_children():
		c.queue_free()
	var 个数: int = 0
	for cc: GCard in Data.cover_cards:
		if cc == null:
			continue
		var go: Node = _加卡牌(ChooseArea, cc, 盖牌尺寸, _selecting_cover and _卡牌能点(cc.id))
		if go is Control:
			(go as Control).position = Vector2(float(个数) * (盖牌尺寸.x + 6.0), 0.0)
		go.call("设置选中", _sel_cards.has(cc.id))
		个数 += 1
	ChooseArea.visible = (_selecting_cover or _查看盖牌) and 个数 > 0


## 造一张卡牌节点挂到指定容器下（Card.tscn + scripts/CardUI.gd），点击回调统一接进来
func _加卡牌(父: Node, card: GCard, 尺寸: Vector2, 可用: bool) -> Node:
	var go: Node = 卡牌预制.instantiate()
	var ctl: Control = go as Control
	ctl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctl.custom_minimum_size = 尺寸
	ctl.size = 尺寸
	ctl.scale = Vector2.ONE
	父.add_child(go)
	go.call("设置卡牌", card, 可用)
	go.connect("点击", _on_card_clicked)
	return go


## 玩家面板：选中的目标染黄；当前可选的目标保持常色并亮起「可选中」光圈；
## 其余在「自己正在操作」（行动 / 应答 / 技能询问）期间压暗置灰 —— 亮着才点得动。
## 不是自己操作时（_mode == 0）不压暗，免得把别人面板上的 Turn 高亮一起压下去。
func 刷新选中面板() -> void:
	for 面板: 战斗玩家面板 in _面板列表:
		var pid: int = 面板.ID
		var 可选: bool = _玩家可选(pid)
		if _sel_players.has(pid):
			面板.modulate = 面板选中色
		elif _mode != 0 and not 可选 and pid != Logic.my_player_id:
			面板.modulate = 面板置灰色
		else:
			面板.modulate = 面板常态色
		面板.set("IsEnable", 可选)


## 发动技能时选中的目标数是否合法：服务端给的最少~最多（target_max 省略＝必须刚好 need_target 个）
func _目标数合法() -> bool:
	if _skill_need_target <= 0:
		return _sel_players.is_empty()
	if _sel_players.size() < _skill_need_target:
		return false
	return _skill_target_max <= _skill_need_target or _sel_players.size() <= _skill_target_max


## 当前已选目标是否都落在给定白名单里（白名单为空＝不限制）
func _目标在白名单(白名单: Array) -> bool:
	if 白名单.is_empty():
		return true
	for pid: int in _sel_players:
		if not 白名单.has(pid):
			return false
	return true


## 参数选项各自目标白名单的并集：不同选项允许的目标可能不同（如【神圣领域】给队友加血 / 打敌方）
func _参数选项目标白名单() -> Array:
	var out: Array = []
	for 项: Variant in _skill_arg_choices:
		var 单: Array = (项 as Dictionary).get("targets", [])
		for pid: Variant in 单:
			if not out.has(int(pid)):
				out.append(int(pid))
	return out


## 这张牌此刻是否躺在某名玩家的基础效果区（【封印破碎】要选的就是它）
func _是场上基础效果牌(card_id: int) -> bool:
	for p: GPlayer in Data.player_list:
		for st: GPlayer.BasicStatus in p.basic_status_list:
			if st.card != null and st.card.id == card_id:
				return true
	return false


## 这名玩家此刻能不能被点选为目标：同时决定面板「可选中」箭头是否亮起、以及点下去是否生效
## （不亮就是点不动，不再靠「点到不能选的再提示」）
## 注意：**自己也可以是合法目标** —— 服务端 _do_magic 里【圣盾】【虚弱】【中毒】都允许指向自己
## （不给 dst 时它甚至默认就是自己），所以这里不再一律排除自己，改由各分支自己判：
##   攻击牌（v_attack 拒同队）、应战反击（v_reattack 拒自己与同队）、魔弹落点（只可能是敌人）天然不含自己。
func _玩家可选(player_id: int) -> bool:
	if player_id < 0 or player_id == GConst.GUEST:
		return false
	if _mode == 1:
		# 先选牌、再亮目标：还没选牌时谁都不亮
		var 牌: GCard = Data.get_card(_sel_cards[0]) if not _sel_cards.is_empty() else null
		if 牌 == null:
			return false
		# 攻击牌只能打敌方（服务端 v_attack 对同队直接拒）；法术按 _do_magic 的分支判
		if 牌.is_attack():
			return _是敌方(player_id)
		return _可作法术目标(牌, player_id)
	if _mode == 2:
		var rid: int = int(_pending.get("respond_id", 0))
		if rid == GConst.RespondType.ReplyAttack:
			# 应战同样先选牌；选【圣光】抵挡时不需要反击目标
			return not _sel_cards.is_empty() and not _选中是圣光() and _可作反击目标(player_id)
		if rid == GConst.RespondType.Bullet:
			# 魔弹传递：选好传递牌后，只有服务端给的那几个落点亮（【圣光】抵挡不需要目标）
			return not _sel_cards.is_empty() and not _选中是圣光() and _魔弹传递目标列表().has(player_id)
		return false
	if _mode == 3:
		return _skill_ask_need_target > 0
	if _mode == 4:
		if _skill_need_target <= 0 and _skill_target_max <= 0:
			return false
		# 参数选项带了各自的目标白名单时，按它们的并集点亮（如【神圣领域】两种用法打不同的人）
		var 选项白名单: Array = _参数选项目标白名单()
		if not 选项白名单.is_empty():
			return 选项白名单.has(player_id)
		# 服务端给了合法目标就只让这几名玩家亮（如【魔弹融合】只打右手边最近的对手）
		return _skill_targets.is_empty() or _skill_targets.has(player_id)
	return false


## 确定/取消/盖牌/放弃行动 的可见与可用（场景里那几个按钮默认都是 visible=false）
func _更新按键() -> void:
	BtnOK.visible = _mode != 0
	BtnCancel.visible = _mode != 0
	BtnOK.disabled = _确定不可用()
	BtnCancel.disabled = not _取消可用()
	# 「盖牌」按钮：只有自己有盖牌时才显示，点开只是查看盖牌（不结束回合）
	BtnCovered.visible = not Data.cover_cards.is_empty()
	BtnCovered.disabled = Data.cover_cards.is_empty()
	BtnResign.visible = _模式可放弃行动()
	BtnResign.disabled = not _模式可放弃行动()
	BtnSpecila.visible = _按钮是特殊行动() or _按钮是放弃()
	BtnSpecila.disabled = not BtnSpecila.visible
	# 参数选项按钮：选够它要求的牌/目标、且目标落在它自己的白名单里才让点
	for 项: Variant in _参数按钮:
		var d: Dictionary = 项
		var b: Button = d["按钮"] as Button
		if not is_instance_valid(b):
			continue
		var 缺: bool = _sel_cards.size() < int(d["需牌"]) or _sel_players.size() < int(d["需目标"])
		if not 缺 and not _目标在白名单(d["目标白名单"]):
			缺 = true
		b.disabled = 缺


func _确定不可用() -> bool:
	# 特殊行动（购买/合成/提炼）没有「确定」，由菜单里的按钮直接提交
	if _mode == 5 or _mode == 6:
		return true
	if _mode == 1:
		return _sel_cards.is_empty() and _sel_players.is_empty()
	if _mode == 3:
		if _skill_ask_id < 100:
			return true
		var 牌够: bool = _sel_cards.size() == _skill_ask_need_card if _skill_ask_need_card > 0 else true
		var 目标够: bool = _sel_players.size() == _skill_ask_need_target if _skill_ask_need_target > 0 else true
		# 有选项时「确定」始终不可用，由选项按钮提交
		return true if not _skill_options.is_empty() else not (牌够 and 目标够)
	if _mode == 4:
		# 有参数选项时「确定」始终不可用，由选项按钮提交（与技能询问同一套做法）
		if not _skill_arg_choices.is_empty():
			return true
		# 需牌是最少张数（如【暗影流星】要弃 2 张、【欺诈】可弃 2~3 张），选够才让点「确定」
		var 牌够: bool = _sel_cards.size() >= _skill_need_card if _skill_need_card > 0 else _sel_cards.is_empty()
		return not (牌够 and _目标数合法())
	if _mode == 2:
		match int(_pending.get("respond_id", 0)):
			GConst.RespondType.ReplyAttack:
				if _sel_cards.is_empty():
					return true
				if _选中是圣光():
					return false
				if not _可应战():
					return true
				return _sel_players.is_empty()
			GConst.RespondType.Bullet:
				if _sel_cards.is_empty():
					return true
				# 【圣光】抵挡不需要目标；【魔弹】要先点亮的落点
				return not _选中是圣光() and _sel_players.is_empty()
			GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
				return _sel_cards.size() != _need_cards
			GConst.RespondType.Weaken, GConst.RespondType.Heal:
				return false
			_:
				return false
	return true


## 行动阶段才能「无法行动」
func _模式可放弃行动() -> bool:
	return _mode == 1


## 场景 BtnSpecila 在行动阶段是「特殊行动」（购买 / 合成 / 提炼）
func _按钮是特殊行动() -> bool:
	return _mode == 1


## 场景 BtnSpecila 在魔弹传递的询问里仍是「放弃」（沿用旧用法；应战时的放弃已挪给「取消」）
func _按钮是放弃() -> bool:
	return _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.Bullet


## 「取消」是否可用：技能询问 / 发动技能 / 特殊行动 / 应战放弃 / 魔弹放弃传递 / 虚弱强摸 / 治疗抵御
func _取消可用() -> bool:
	if _mode == 3 or _mode == 4 or _mode == 5 or _mode == 6:
		return true
	if _mode == 2:
		var rid: int = int(_pending.get("respond_id", 0))
		return rid == GConst.RespondType.ReplyAttack \
			or rid == GConst.RespondType.Bullet \
			or rid == GConst.RespondType.Weaken \
			or rid == GConst.RespondType.Heal
	return false


# ---------------- 技能区 ----------------
## 加一个纯文字按钮（技能选项 / 额外行动 / 特殊行动用；技能本体走 Skill.tscn）
func _加文本按钮(文本: String, 回调: Callable, 可用: bool = true) -> void:
	var b: Button = Button.new()
	b.text = 文本
	b.custom_minimum_size = Vector2(164.0, 44.0)
	b.add_theme_font_size_override("font_size", 22)
	b.disabled = not 可用
	b.pressed.connect(回调)
	ChildrenSkillArea.add_child(b)
	_技能按钮.append(b)
	_显示技能区()


func _显示技能区() -> void:
	SkillArea.visible = true
	ChildrenSkillArea.visible = true


func _隐藏技能区() -> void:
	SkillArea.visible = false
	ChildrenSkillArea.visible = false


func _清空技能按钮() -> void:
	for b: Node in _技能按钮:
		if is_instance_valid(b):
			b.queue_free()
	_技能按钮.clear()
	_参数按钮.clear()
	_隐藏技能区()

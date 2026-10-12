## 战斗中的玩家状态面板 —— 对应 AGrail.PlayerStatusMobile
## 转换后的 scenes/BattleUIMobile.tscn 中，MainPlayer / PlayerStatusMobileL/UL/U/UR/R
## 这几个节点类型都是 Button，因此这里继承 Button。
## 角色技能说明不走 Godot 自带的 tooltip：本面板只把 悬停 / 离开悬停 报给容器，
## 由容器用统一的说明框摆在面板正上方（自带 tooltip 的大小、位置都不受控）。
##
## 待办：节点引用改成 @export 绑定（下面 @onready 里那批 _find_variant / _find_label_under /
## _find_child_script 仍是参考工程搬过来的按名查找写法，本步骤先保留）。
##
## 外部依赖：参考工程的 BattleData / RoleFactory / RoleBase / UIManager 等本工程没有，
## 已按「本步骤只显示信息」降级（用 Data / Logic 顶替），涉及技能系统的部分标「第三步」。
class_name 战斗玩家面板
extends Button

## 点了面板上的某枚基础效果图标（选牌来源为 CardSource.BasicEffect、从场上基础效果牌里选一张的技能用它）
signal 基础效果牌点击(玩家id: int, 牌id: int)
## 鼠标指向 / 离开这名玩家的面板（容器据此在面板上方显示 / 收起角色技能说明）
signal 悬停(面板: 战斗玩家面板)
signal 离开悬停()
## 鼠标指向 / 离开某枚状态图标（基础效果牌 / 指示物）：容器据此在图标上方弹提示 ——
## 指示物＝一行「名字 当前/上限」；基础效果牌＝摊出这张牌的完整卡面 + 一行「卡名（派系·元素）」
## （牌id >= 0 表示带上了卡牌；容器用图标的矩形摆位，保证提示不压住图标）
signal 状态图标悬停(图标: Control, 文本: String, 牌id: int)
signal 状态图标离开悬停()

## 消息类型枚举走全局 class_name Msg（见 scripts/framework/Msg.gd）。
## 原来这里有一份 `const Msg := preload(...)`，与全局类重名会被 Godot 报
## SHADOWED_GLOBAL_IDENTIFIER，删掉后 Msg.T.Xxx 的写法照常可用。

## 面板图标要区分的技能号统一放在 GConst（技能_天使之墙 / 技能_迅捷赐福 / 技能_威力赐福 /
## 技能_风之封印 ~ 技能_雷之封印），这里不再各写一份

## 对应 C# [SerializeField] private Image redTeam;  （场景里 TeamBG/Red、TeamBG_2/Red_2 …）
@onready var redTeam: TextureRect = _find_variant("Red") as TextureRect
## 对应 C# [SerializeField] private Image blueTeam;  （场景里 TeamBG/Blue、TeamBG_2/Blue_2 …）
@onready var blueTeam: TextureRect = _find_variant("Blue") as TextureRect
## 对应 C# [SerializeField] private Image turn;
@onready var turn: TextureRect = _find_variant("Turn") as TextureRect
## 对应 C# [SerializeField] private Image select;
@onready var select: TextureRect = _find_variant("Select") as TextureRect
## 对应 C# [SerializeField] private Image canSelect;
@onready var canSelect: TextureRect = _find_variant("CanSelect") as TextureRect
## 对应 C# [SerializeField] private Text selectTime;
@onready var selectTime: Label = _find_variant("selectTime") as Label
## 对应 C# private Button minusSelect;（selectTime 里那个「-」按钮；场景里它自己 visible=false，
## 多选时必须显式打开，否则点错目标无法取消 —— battle_audit H-6）
@onready var minusSelect: BaseButton = _find_variant("minusSelect") as BaseButton
## 对应 C# [SerializeField] private Image hero;
@onready var hero: TextureRect = _find_variant("Hero") as TextureRect
## 对应 C# [SerializeField] private Image property;  （场景里的 HeroProperty）
@onready var propertyImage: TextureRect = _find_variant("HeroProperty") as TextureRect
## 对应 C# [SerializeField] private Image knelt;（本工程改成 Label：状态名文字 + 自带底板）
@onready var knelt: Label = _find_variant("Knelt") as Label
## 对应 C# [SerializeField] private Text playerName;  （MainPlayer 是 Name/TxtName，其余是 PlayerName/Name_N）
@onready var playerName: Label = _find_label_under("PlayerName")
## 对应 C# [SerializeField] private Text chat;  （ChatPurple/ChatText、ChatPurple_2/ChatText_2 …）
@onready var chat: Label = _find_label_under("ChatPurple")
## 对应 C# [SerializeField] private Text waitAction;  （WaitAction/WaitAction_2、WaitAction_3/…）
@onready var waitAction: Label = _find_label_under("WaitAction")
## 名牌上方的行动超时进度条（本工程新增：Unity 原版这里只放倒计时文字）
@onready var waitProgress: ProgressBar = _find_variant("WaitProgress") as ProgressBar
## 对应 C# [SerializeField] private Transform handArea;  （场景里的 Hand）
@onready var handArea: Node = _find_variant("Hand")
## 对应 C# [SerializeField] private Transform healArea;  （场景里的 Heal）
@onready var healArea: Node = _find_variant("Heal")
## 对应 C# [SerializeField] private Transform energyArea;  （场景里的 Energy）
@onready var energyArea: Control = _find_variant("Energy") as Control
## 对应 C# [SerializeField] private Transform basicAndExCardArea;  （场景里的 BasicAndExCards）
@onready var basicAndExCardArea: Control = _find_variant("BasicAndExCards") as Control
## 对应 C# [SerializeField] private Transform recHandArea;  （场景里的 RecHandArea / HandArea__N_）
@onready var recHandArea: Node = null

## 对应 C# public Transform AnimationPos;  （场景里没有对应节点，用自身兜底；Button 不是 Node2D，故用 Node）
@onready var AnimationPos: Node = null

## 对应 C# private Button btnPlayer = GetComponent<Button>()（即是自身）
var btnPlayer: Button = null
## 当前时机「能不能选他当目标」（对应 C# 的 btnPlayer.interactable）。
## 为什么要单独记一份、而不是直接用 btnPlayer.disabled：Godot 里 disabled 的按钮**连 pressed
## 都不会发**，那样「点一个不可选的头像看他的角色技能」就永远触发不了（见 onClick）。
var is_selectable: bool = false
## 对应 C# private Text token0 / token1 / token2;
var token0: Label = null
var token1: Label = null
var token2: Label = null
## 对应 C# private Animator hurted;  （场景里没有 AnimationPlayer，做空实现）
var hurted: Node = null
## 状态图标（基础效果 / 独有效果）的边长：素材都是 20×20，放大到 28 显示（格子里居中）
const 状态图标尺寸: float = 28.0
## 名牌上「等待响应XX」那行字的字号（场景里是 20）与缩放下限：文案带技能名时会一行放不下，
## 由 _自适应等待字号 逐级缩小，见那里
const 等待文案基础字号: int = 20
const 等待文案最小字号: int = 12
## 「黄魂 / 蓝魂 / 盖牌」指示物也按状态图标看待，尺寸与基础效果图标对齐
## （素材 token0~2 是 20×20，拉伸到 28 显示，格子也是 28，图标之间不留缝）
const 指示物格尺寸: Vector2 = Vector2(状态图标尺寸, 状态图标尺寸)
## 手牌 / 治疗那排扁平小方块：素材 handcard / heal 都是 33×14，照原版横排、负间距互相叠着
const 扁平格尺寸: Vector2 = Vector2(33.0, 14.0)
const 扁平格叠放间距: int = -13
## 补牌动画（秒）：新补进手牌的格子先盖一层黄块，保持 补牌黄色时长 秒后，
## 再用 补牌渐变时长 秒淡出、露出下面的绿块（前面一直黄、只在最后一段渐变）
const 补牌黄色时长: float = 3.5
const 补牌渐变时长: float = 0.5
## 补牌黄块：素材、形状、颜色都收在预制体与它的材质里 —— 想调效果直接开这两个文件。
## 材质用的是「受击描边」着色器 + tint：只把素材里的绿色换成 tint 色，描边与明暗都保留
const 补牌黄块预制体: PackedScene = preload("res://scenes/prefabs/battlemobile/refillBlock.tscn")
const 补牌黄块材质: ShaderMaterial = preload("res://scripts/effects/refillBlockMaterial.tres")
## 新到手的宝石闪白时长（秒）：越短闪得越快
const 宝石闪白时长: float = 0.3
## 闪白的起始强度：从纯白（1.0）开始往下淡
const 宝石闪白起始强度: float = 1.0
## 角色身上的能量：素材 gem / crystal 都是 29×30（近似正方形），竖着一列排
const 能量格尺寸: Vector2 = Vector2(30.0, 30.0)
## 能量区的格子边长（原版 Unity 的 GridLayoutGroup cellSize 就是 30×30）
const 能量区图标格: Vector2 = Vector2(30.0, 30.0)
## 状态图标区的格子边长：就取图标本身的大小，图标之间不留缝（原来格子 40、图标 36，四周会空 4 像素）
const 状态图标格: Vector2 = Vector2(状态图标尺寸, 状态图标尺寸)
## 状态图标区排几列：它宽 80、格子 28 → 2 列
const 状态区列数: int = 2
## 状态图标区每列最多几格（原版 GridLayoutGroup 是「固定 4 行」＝一列 4 个，满了再往右一列）
const 状态区每列格数: int = 4
## 状态图标「弹出」动画（秒）：新挂上的状态图标先放大 状态弹出放大 倍，再缩回原大小
const 状态弹出时长: float = 0.35
const 状态弹出放大: float = 3.0
## 状态图标「弹出」起点表：键＝图标标识（"b:基础牌id" / "e:独有效果下标"），
## 值＝该标识各个实例的起点（毫秒，-1＝不播）。跨重建保留：同一帧可能刷新多次，
## 只挂一次性 tween 会被下一次重建连根清掉（同宝石闪白的做法）
var _状态弹出起点: Dictionary = {}
## 是否已经渲染过一次状态图标（进场第一次不播弹出动画）
var _状态已初始化: bool = false
## 状态图标的白描边材质（所有图标共用一份，参数一样）
var _状态描边材质: ShaderMaterial = null
## 三个指示物槽上一次的数值（-1＝还没设过）：用来判断这次是不是「变多」了
var _指示物数值: Array[int] = [-1, -1, -1]
## 状态图标区当前要显示的基础效果牌 / 独有效果下标（两个 setter 合成一次渲染，见 _刷新状态图标）
var _状态基础牌: Array = []
## 面板上的基础效果图标此刻是否可以点（选牌来源为 CardSource.BasicEffect 的技能期间打开）
var _基础牌可点: bool = false
var _状态独有效果: Array = []
## 对应 C# private RoleBase role = RoleFactory.Create(RoleID.Blank);
## 参考工程这里建的是角色对象（技能系统）。本工程没有该技能系统，本步骤只保留角色名用于显示。
## 第三步：技能系统。
var 角色名: String = ""
## 本面板当前角色号（形态图标要按角色取，见 set_Knelt）
var 角色号: int = 0
## 对应 C# private List<CardUI> cardUIs
var cardUIs: Array = []
## 对应 C# public bool seted;
var seted: bool = false
## 对应 C# private Coroutine chatCoro;  （Godot 用 Timer 代替）
var chatTimer: SceneTreeTimer = null
## 对应 C# public uint ID { get; set; }
var ID: int = 0

# ---------------------------------------------------------------------------
# 属性转发 —— 战斗界面（BattleUIMobile / BattleRecord）是用 Unity 的写法
# `playerStatus[i].set("Xxx", v)` 往面板上写值的，对应 C# 里 `public Xxx Xxx { set {...} }`。
# 端口里这些逻辑写成了 set_Xxx() 方法，**属性名本身并不存在**，于是 set() 静默变成
# no-op —— 表现就是「玩家名、角色立绘、手牌数、治疗数、阵营颜色、跪倒标记全都不显示」。
# 这里把属性名补上，统一转发给已有的 set_Xxx() 方法。
# ---------------------------------------------------------------------------
var NickName: String = "":
	set(value):
		set_NickName(value)
var Team: int = 0:
	set(value):
		set_Team(value)
var RoleID: int = 0:
	set(value):
		set_RoleID(value)
var Turn: bool = false:
	set(value):
		set_Turn(value)
var Knelt: bool = false:
	set(value):
		set_Knelt(value)
var YellowToken: int = 0:
	set(value):
		set_YellowToken(value)
var BlueToken: int = 0:
	set(value):
		set_BlueToken(value)
var Covered: int = 0:
	set(value):
		set_Covered(value)
var BasicAndExCards: Array = []:
	set(value):
		set_BasicAndExCards(value)
var ExclusiveCards: Array = []:
	set(value):
		set_ExclusiveCards(value)
var Energy: Vector2i = Vector2i.ZERO:
	set(value):
		set_Energy(value)
var HandCount: Vector2i = Vector2i.ZERO:
	set(value):
		set_HandCount(value)
var HealCount: int = 0:
	set(value):
		set_HealCount(value)
var IsEnable: bool = true:
	set(value):
		set_IsEnable(value)
var Chat: String = "":
	set(value):
		set_Chat(value)
var WaitAction: String = "":
	set(value):
		set_WaitAction(value)
## 等待进度（0~1；负值 = 收起进度条）。服务端只在等待开始/结束时广播，剩余时间由界面自己倒数
var WaitProgress: float = -1.0:
	set(value):
		set_WaitProgress(value)

## 预制体缓存（替代 AssetBundleManager.LoadAsset("battle", "Xxx")）
const PREFAB_DIR := "res://scenes/prefabs/battlemobile/"
static var _prefab_cache: Dictionary = {}

## 对应 C# private bool isShowCovered 等效的「上一次的显示状态」——本类只维护自己的状态
func _find_node(nm: String) -> Node:
	var n := find_child(nm, true, false)
	if n == null:
		push_warning("%s: 找不到节点 %s" % [name, nm])
	return n

## 转换器给同一预制体里重名的节点加了 _2/_3… 后缀（如 Red / Red_2 / Red_3），
## 这里先按精确名找，再按 "<名>_*" 兜底，等价于 Unity 里编辑器拖好的那个引用。
func _find_variant(base_name: String) -> Node:
	var direct := find_child(base_name, true, false)
	if direct != null:
		return direct
	var candidates := find_children(base_name + "_*", "", true, false)
	if not candidates.is_empty():
		return candidates[0]
	push_warning("%s: 找不到节点 %s（含 _N 变体）" % [name, base_name])
	return null

## 静默版（用于「有备选方案」的查找，避免刷无意义警告）
func _find_variant_quiet(base_name: String) -> Node:
	var direct := find_child(base_name, true, false)
	if direct != null:
		return direct
	var candidates := find_children(base_name + "_*", "", true, false)
	if not candidates.is_empty():
		return candidates[0]
	return null

## 对应 C# 里直接拖到 Text 上的引用；容器节点（如 PlayerName/WaitAction）下取第一个 Label
func _find_label_under(container_base: String) -> Label:
	var c := _find_variant_quiet(container_base)
	if c == null:
		# MainPlayer 面板另有布局：Name/TxtName
		if container_base == "PlayerName":
			return _find_variant_quiet("TxtName") as Label
		return null
	if c is Label:
		return c as Label
	var labels := c.find_children("*", "Label", true, false)
	if not labels.is_empty():
		return labels[0] as Label
	return null

## 对应 AssetBundleManager.LoadAsset(bundle, assetName) 的预制体加载
func _load_prefab(prefab_name: String) -> PackedScene:
	if _prefab_cache.has(prefab_name):
		return _prefab_cache[prefab_name]
	var p := PREFAB_DIR + prefab_name + ".tscn"
	var ps: PackedScene = null
	if ResourceLoader.exists(p):
		ps = load(p)
	_prefab_cache[prefab_name] = ps
	return ps

## 对应 AssetBundleManager.LoadAsset<Sprite>(bundle, assetName)
## Godot 侧由 AssetIndex 按文件名索引 assets/ 下的图片（bundle 名不参与查找）
func _load_sprite(asset_name: String) -> Texture2D:
	if asset_name == "":
		return null
	var path := AssetIndex.image(asset_name)
	if path == "":
		return null
	return load(path)

## 对应 C# private void Awake()
func _ready() -> void:
	btnPlayer = self
	# 预制体里这个按钮默认是 disabled = true（Unity 里靠 interactable 表达「不可选」），
	# 而 Godot 的 disabled 按钮不会发 pressed —— 那样「点不可选的头像看角色技能」永远没反应。
	# 这里让按钮**始终可点**，「能不能选他」改由 is_selectable 判断（见 onClick / set_IsEnable）。
	btnPlayer.disabled = false
	btnPlayer.pressed.connect(onClick)
	# 鼠标指向 / 离开：报给容器（容器用和点头像同一份说明框弹在面板正上方）
	mouse_entered.connect(func() -> void: 悬停.emit(self))
	mouse_exited.connect(func() -> void: 离开悬停.emit())
	# 这个面板自己就是那个 Button，而预制体里的队色底/头像/名牌都是它的子图、且带着
	# 转换时写死的 mouse_filter=STOP（Unity 里这些 Image 的 raycastTarget 是关的）——
	# 它们会把点击吃掉，表现就是「点在大头像中间没反应，只有点面板边缘才算点到」。
	# 先把装饰子图统一改成 IGNORE，点击才会落到面板按钮上（选目标 / 看信息都靠它）。
	ConversionFix.ignore_decorations(self)
	# 对应 C# GetComponent<LongPress>().OnLongPress.AddListener(onLongPress);
	# 但转换后的预制体把它变成了「面板底下的一个子节点」，而且 visible=false、0×0、mouse_filter=IGNORE ——
	# 这样它永远收不到鼠标事件，长按（原版看角色技能的入口）等于废掉。这里把它摊成盖住整个面板的
	# 一层并改成 PASS：事件先给它判长按，它不 accept_event，事件会继续传给面板按钮做点选（两边都不耽误）。
	# 注意顺序：必须在 ignore_decorations 之后设 PASS，否则会被那一步改成 IGNORE。
	var lp := _find_child_script("LongPress")
	if lp != null:
		if lp is Control:
			var lc := lp as Control
			lc.visible = true
			lc.mouse_filter = Control.MOUSE_FILTER_PASS
			lc.set_anchors_preset(Control.PRESET_FULL_RECT)
			lc.offset_left = 0.0
			lc.offset_top = 0.0
			lc.offset_right = 0.0
			lc.offset_bottom = 0.0
		if lp.has_signal("OnLongPress"):
			lp.connect("OnLongPress", Callable(self, "onLongPress"))
	# 对应 C# hurted = GetComponent<Animator>();
	for c in get_children():
		if c is AnimationPlayer:
			hurted = c
			break
	# 对应 C# [SerializeField] recHandArea；MainPlayer 上没有这个节点（只在其余 5 个面板上），属预期缺失
	recHandArea = find_child("RecHandArea", true, false)
	if recHandArea == null:
		# 转换器把重名后的 HandArea 变成 HandArea__N_，按名字前缀兜底查找
		for c in get_children():
			if c.name.begins_with("HandArea"):
				recHandArea = c
				break
	AnimationPos = self
	# 手牌 / 治疗那两排方块的受击描边材质（受击时把描边染红再淡回，见 Hurted）
	_手牌描边 = _造描边材质()
	_治疗描边 = _造描边材质()
	# 状态图标的白描边（只沿轮廓勾一圈白，见 scripts/effects/whiteOutline.gdshader）
	_状态描边材质 = ShaderMaterial.new()
	_状态描边材质.shader = 状态描边着色器
	# 参考工程在这里 role = RoleFactory.create(0)（技能系统）；本步骤不接。第三步：技能系统。
	# 对应 C# MessageSystem<MessageType>.Regist(AgentSelectPlayer / RecHandChange, this)
	MessageSystem.regist(Msg.T.AgentSelectPlayer, self, Callable(self, "on_event_trigger"))
	MessageSystem.regist(Msg.T.RecHandChange, self, Callable(self, "on_event_trigger"))

func _exit_tree() -> void:
	# 对应 C# OnDestroy()
	MessageSystem.unregist(Msg.T.AgentSelectPlayer, self)
	MessageSystem.unregist(Msg.T.RecHandChange, self)

## 在子节点里找挂了指定脚本的节点（替代 GetComponent<T>()）
func _find_child_script(script_basename: String) -> Node:
	for c in find_children("*", "", true, false):
		var s = c.get_script()
		if s != null and str(s.resource_path).get_file().get_basename() == script_basename:
			return c
	return null

## ---------------- 对应 C# 的属性 ----------------

## 对应 C# public bool IsEnable 的 setter
func set_IsEnable(value: bool) -> void:
	is_selectable = value
	# 只记状态、**不**给按钮设 disabled：Godot 的 disabled 会让按钮连 pressed 都不发，
	# 而「点可选的敌方头像直接出手」靠的就是 pressed。面板按钮自身是 alpha=0 的透明按钮
	# （预制体里 self_modulate 的 a 是 0），没有 hover/disabled 外观，所以这样做看不出差别。
	if canSelect != null:
		canSelect.visible = value
	# 参考工程按 BattleData.Agent.FSM 的当前状态决定是否把面板压灰（0.5）；本工程暂无该交互层，
	# 本步骤只控制「可选中」箭头，不压灰。第三步：出牌/选目标交互层。


## 「是否已被选中」：可选时亮绿框（canSelect），选中后绿框收掉、改亮黄框（select）——
## 两块贴图本身都是纯绿，黄色由 select 上的换色材质负责
func 设置已选中(值: bool) -> void:
	select.visible = 值
	canSelect.visible = is_selectable and not 值

## 对应 C# public string NickName 的 setter
func set_NickName(value: String) -> void:
	if playerName != null:
		playerName.text = value

## 对应 C# public uint RoleID 的 setter
func set_RoleID(value: int) -> void:
	if value == 0:
		return
	# 参考工程在这里 role = RoleFactory.create(value)（技能系统）；本工程不用技能系统，
	# 角色名与派系图标都直接查数据表。
	角色名 = Data.role_name(value)
	角色号 = value
	var main_id: int = Logic.my_player_id
	var player_id: int = main_id
	var first_id: int = Data.first_player_id
	# 对应 C# 的三元表达式：非自己、或（不是 0 号位、或自己不是观战者）时用 小图 hero_s
	var use_small: bool = ID != main_id and (ID != first_id or player_id != 9)
	var tex := _load_sprite("%s%s" % [str(value), "S" if use_small else "L"])
	# 真正显示头像的是 HeroIcon（就是那个「剪影」占位图所在的节点）。原版是靠代码把真立绘
	# 写到它上面，端口却写到了外层的 hero/Hero_N（队徽底图那一层），于是 HeroIcon 的剪影
	# 一直盖在真立绘上面。这里直接把 HeroIcon 的贴图换掉 —— 换掉就不用再想办法隐藏它了。
	var portrait := _find_variant_quiet("HeroIcon") as TextureRect
	if portrait == null:
		portrait = hero
	if tex != null and portrait != null:
		# 只换贴图，**不动尺寸/锚点**：之前把立绘改成 170×170 + clip 之后，自己那张大图
		# 被裁到看不见了。原版立绘节点的尺寸是调好的，端口丢的只是尺寸为 0 的情况。
		portrait.texture = tex
		portrait.visible = true
		if portrait.size.x < 1.0 or portrait.size.y < 1.0:
			portrait.custom_minimum_size = Vector2(170.0, 170.0)
	elif tex != null and hero != null:
		# 万一这个面板没有 HeroIcon，退回原来的做法（同样只换贴图）
		hero.texture = tex
		hero.visible = true
		if hero.size.x < 1.0 or hero.size.y < 1.0:
			hero.custom_minimum_size = Vector2(170.0, 170.0)
	# 名牌下方那排小方块（手牌数/治疗数/能量/状态图标）提到最前：
	# 立绘压在它们上面就会「挡住数量显示」，抬起来即可，不用去改立绘。
	for area in [handArea, healArea, energyArea, basicAndExCardArea]:
		if area is CanvasItem:
			(area as CanvasItem).move_to_front()


## 注意：这里**不要**再去「隐藏带 chara 贴图的节点」—— 头像背后那块背景板（队徽底图）
## 用的就是 battle/b02_chara_*.png，按贴图名去关会把背景板一起关掉（表现为「看不到头像
## 也看不到背景板」）。头像直接换 HeroIcon 的贴图就够了，不需要隐藏任何东西。
	# 派系（技 / 血 / 幻 / 咏 / 圣）图标贴到名牌左侧的 HeroProperty 上
	# （对照参考工程 PlayerStatusMobile 里 role.get_role_property() 那段）
	var 派系图: Texture2D = Art.role_property_icon(Data.role_property(value))
	if propertyImage != null:
		propertyImage.texture = 派系图
		propertyImage.visible = 派系图 != null
	if not seted:
		seted = true
		_create_tokens()

## 对应 C# RoleID setter 里创建 token0/1/2 的那段
func _create_tokens() -> void:
	token0 = _create_token("Token0", "token0", 0)
	token1 = _create_token("Token1", "token1", 1)
	token2 = _create_token("Token2", "token2", 2)

func _create_token(prefab_name: String, node_name: String, 槽: int) -> Label:
	var ps := _load_prefab(prefab_name)
	if ps == null or basicAndExCardArea == null:
		return null
	var go := ps.instantiate()
	go.name = node_name
	basicAndExCardArea.add_child(go)
	# Token 预制体同样是 0×0（expand_mode=1 的 TextureRect 落到 GridContainer 里最小尺寸为 0），
	# 不给最小尺寸的话 token 数字与它上面的 Text 都看不见。
	if go is Control:
		var 图标: Control = go as Control
		图标.custom_minimum_size = 指示物格尺寸
		# 指示物也算状态图标：套同一份白描边
		图标.material = _状态描边材质
		# 鼠标压上去时报给容器，由容器弹一条「名字 当前/上限」（和角色 / 技能说明同一份提示框）
		图标.mouse_entered.connect(func() -> void: _报告指示物悬停(槽, 图标))
		图标.mouse_exited.connect(func() -> void: 状态图标离开悬停.emit())
	var lbl: Label = go.find_child("Text", true, false) as Label
	if lbl != null:
		lbl.text = "0"
		# 指示物数字整体右移 5px（原来贴着格子左上角），并勾一圈黑描边，
		# 让白字叠在浅色底板上也看得清
		lbl.offset_left += 5.0
		lbl.offset_right += 5.0
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		lbl.add_theme_constant_override("outline_size", 6)
	if go is CanvasItem:
		(go as CanvasItem).visible = false
	_摆图标(basicAndExCardArea, 状态区列数, 状态区每列格数, 状态图标格)
	return lbl

## 鼠标指到某枚指示物图标：把「名字 当前/上限」报给容器（上限只在悬浮提示里露面）
func _报告指示物悬停(槽: int, 图标: Control) -> void:
	var 定义: Dictionary = Data.role_token_def(角色号, 槽)
	if 定义.is_empty():
		return
	状态图标悬停.emit(图标, "%s %d/%d" % [str(定义["name"]), _指示物数值[槽], int(定义["max"])], -1)


## 鼠标指到某枚基础效果牌图标：报出这张牌的 id（容器据此摊出完整卡面）+ 一行
## 「状态名（派系·元素）」（卡面贴图缺失时兜底用；同一状态有好几版牌，如【圣盾】有幻 / 圣 / 咏）
func _报告基础效果悬停(牌id: int, 图标: Control) -> void:
	var 牌: GCard = Data.get_card(牌id)
	if 牌 == null:
		return
	状态图标悬停.emit(图标,
		"%s（%s·%s）" % [状态名(牌), 牌.property, GConst.element_to_chinese(牌.element_enum())], 牌id)


## 这张牌摆在头像上当状态用时，那个状态叫什么。
## 多数牌牌名就是状态名；少数是「借牌当状态」——同一张【风神斩】放着可能在当【风之封印】、
## 【圣盾】、【威力赐福】用，这时该按状态叫，不能照牌名报。
## 判定与图标（_basic_card_sprite）同一套：先拿到图标名，再回 Art.STATUS_ICON 里反查状态名，
## 两边共用一份对照表，不会各写一份
func 状态名(牌: GCard) -> String:
	var 图标名: String = _basic_card_sprite(牌).to_lower()
	# 比大小写不敏感：两张表的大小写并不一致（Art.STATUS_ICON 写的是资源真名 fengFeng，
	# _basic_card_sprite 返回的是 fengfeng —— 贴图查找本身忽略大小写，所以一直没暴露）
	for 名: String in Art.STATUS_ICON:
		if str(Art.STATUS_ICON[名]).to_lower() == 图标名:
			return 名
	return 牌.card_name

## 对应 C# public Team Team 的 setter（Team: Blue=0, Red=1）
## 头像背后那块队伍底色就是同级的 Red/Blue 两张六边形底图，切可见性即可。
## 注意：同位置的「Hero/Hero_N」层只是给头像做裁剪的容器，它画在 Red/Blue 之后，
## 一旦它自己挂了 battle/b02_chara_*.png 底图，就会把队伍色整个盖住 ——
## 表现是「所有其他人都是同一个颜色，分不清队伍」。PlayerOtherPanel.tscn 里那行贴图已去掉。
func set_Team(value: int) -> void:
	if redTeam != null:
		redTeam.visible = value != 0
	if blueTeam != null:
		blueTeam.visible = value == 0

## 对应 C# public bool Turn 的 setter
func set_Turn(value: bool) -> void:
	if turn != null:
		turn.visible = value
## 对应 C# public bool Knelt 的 setter —— 形态名（如魔剑士的【暗影形态】）。
## 原来是往头像上贴一张「形态图」，现改成名牌正上方的一块文字底板：
## 文本取「角色表」的「横置形态」列，底板色取「状态底色」列（见 Data.role_status_bg），文字固定白。
func set_Knelt(value: bool) -> void:
	knelt.visible = value
	if not value:
		return
	var 形态列表: Array[String] = Data.role_forms(角色号)
	knelt.text = 形态列表[0] if not 形态列表.is_empty() else "横置"
	(knelt.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = Data.role_status_bg(角色号)

## 对应 C# public uint YellowToken 的 setter
func set_YellowToken(value: int) -> void:
	if token0 == null:
		return
	_设指示物(token0, 0, value)
	_摆图标(basicAndExCardArea, 状态区列数, 状态区每列格数, 状态图标格)

## 对应 C# public uint BlueToken 的 setter
func set_BlueToken(value: int) -> void:
	if token1 == null:
		return
	_设指示物(token1, 1, value)
	_摆图标(basicAndExCardArea, 状态区列数, 状态区每列格数, 状态图标格)

## 对应 C# public uint Covered 的 setter
func set_Covered(value: int) -> void:
	if token2 == null:
		return
	_设指示物(token2, 2, value)
	_摆图标(basicAndExCardArea, 状态区列数, 状态区每列格数, 状态图标格)


## 指示物数字同样算状态图标：刷新文字与显隐；数字变大（获得／叠层增加）时播一次「放大→缩回」。
## 数值为 0 时也把图标留着（否则玩家看不到自己有过什么指示物）；图标上只写当前层数，
## 「名字 当前/上限」放到悬浮提示里（见 _报告指示物悬停）。
## 角色表里没配这个槽位（＝这角色根本没有该指示物）才整格藏起来
func _设指示物(标签: Label, 槽: int, 值: int) -> void:
	var 旧值: int = _指示物数值[槽]
	_指示物数值[槽] = 值
	var 底板: Control = 标签.get_parent() as Control
	var 定义: Dictionary = Data.role_token_def(角色号, 槽)
	if 定义.is_empty():
		底板.visible = false
		return
	标签.text = str(值)
	底板.visible = true
	# 进场第一次（旧值 -1）不播；只有变多才算「获得 / 叠层增加」
	if 旧值 >= 0 and 值 > 旧值:
		_播状态弹出(底板)

## 对应 C# public List<uint> BasicAndExCards 的 setter
func set_BasicAndExCards(value: Array) -> void:
	_状态基础牌 = value.duplicate()
	_刷新状态图标()


## 独有效果（【五系束缚】【挑衅】【灵魂链接】【同生共死】【永恒乐章】）的 setter：
## 传 GConst.Exclusive 的下标数组，图标由 Art.exclusive_icon 取
func set_ExclusiveCards(value: Array) -> void:
	_状态独有效果 = value.duplicate()
	_刷新状态图标()


## 状态图标区（BasicAndExCards）里除 token 之外的图标 —— 基础效果 + 独有效果，一次渲染
func _刷新状态图标() -> void:
	if basicAndExCardArea == null:
		return
	for c in basicAndExCardArea.get_children():
		if not String(c.name).begins_with("token"):
			c.queue_free()
	var ps := _load_prefab("Image")
	if ps == null:
		return
	# 这次渲染后各图标的新起点表（键＝图标标识，值＝该标识各实例的起点），渲染完整体换掉旧的
	var 新起点: Dictionary = {}
	for item: Variant in _状态基础牌:
		var card: GCard = Data.get_card(int(item))
		if card == null:
			continue
		var sprite_name := _basic_card_sprite(card)
		if sprite_name == "":
			# 认不出贴图的牌只跳过它自己：原来这里是 break，一张没映射的牌会把排在它后面的
			# 全部标记（圣盾/封印…）一起丢掉（battle_audit C-2）。
			push_error("Basic card is error! CardID = %s" % str(item))
			continue
		_加状态图标(ps, _load_sprite(sprite_name), "b:%d" % int(item), 新起点, int(item))
	for idx: Variant in _状态独有效果:
		# 独有效果没有卡牌对象，报不出「哪一张牌」，提示里只写这个状态做什么；
		# 【五系束缚】把两个选项和「触发时会摸几张牌」一起写出来，供玩家判断要不要选摸牌继续行动
		var i: int = int(idx)
		var 名: String = GConst.独有效果名[i] if 0 <= i and i < GConst.独有效果名.size() else ""
		var 提示: String = 名
		if i == GConst.Exclusive.WuXiShuFu:
			# 状态名和效果说明分两行（提示框是 RichTextLabel，真换行即可）
			提示 = "%s\n摸 %d 张牌 或 跳过回合" % [名, 五系束缚应摸张数()]
		_加状态图标(ps, Art.exclusive_icon(i), "e:%d" % i, 新起点, -1, 提示)
	_状态已初始化 = true
	_状态弹出起点 = 新起点
	_摆图标(basicAndExCardArea, 状态区列数, 状态区每列格数, 状态图标格)


## 【五系束缚】触发时会摸几张牌：基数 + 场上封印数（封顶上限，口径同服务端 role_fengyin._wu_xi_draw_count）。
## 封印＝摆在任意玩家基础效果区的「幻」系攻击牌（同服务端 _is_seal_card），故要遍历全场玩家数；
## 状态区每次重渲染都会重算，封印增减立刻反映到悬停提示里
func 五系束缚应摸张数() -> int:
	var n: int = 0
	for p: GPlayer in Data.player_list:
		for st: GPlayer.BasicStatus in p.basic_status_list:
			var c: GCard = st.card
			if c != null and c.is_attack() and c.property_enum() == GConst.CardProperty.Phantom:
				n += 1
	return mini(GConst.五系束缚摸牌基数 + n, GConst.五系束缚摸牌上限)


## 往状态图标区加一枚图标（Image 预制体自身是 0×0，不给最小尺寸就什么都看不见）。
## 图标统一套白描边材质；新挂上的（含状态叠层多出来的那几枚）播一次「放大→缩回」，
## 起点记在 起点表 里跨重建续播（同一帧可能刷新多次，一次性 tween 会被下一次重建清掉）。
## 基础效果牌（基础牌id >= 0）在「基础牌可点」时变成可点的，点一下就上报给战斗界面；
## 提示 是给独有效果用的纯文字提示（它们没有卡牌对象，弹不出卡面）
func _加状态图标(ps: PackedScene, tex: Texture2D, 标识: String, 起点表: Dictionary,
		基础牌id: int = -1, 提示: String = "") -> void:
	if tex == null:
		return
	var go := ps.instantiate()
	if go is TextureRect:
		(go as TextureRect).texture = tex
		(go as TextureRect).custom_minimum_size = Vector2(状态图标尺寸, 状态图标尺寸)
		if 基础牌id >= 0 and _基础牌可点:
			(go as TextureRect).mouse_filter = Control.MOUSE_FILTER_STOP
			(go as TextureRect).gui_input.connect(_on_基础牌图标输入.bind(基础牌id))
	var 起点: int = -1
	if go is Control:
		(go as Control).material = _状态描边材质
		# 鼠标压上去各报各的：基础效果牌报「卡名（派系·元素）」+ 卡面，独有效果只有名字
		var 图标: Control = go as Control
		if 基础牌id >= 0:
			图标.mouse_entered.connect(func() -> void: _报告基础效果悬停(基础牌id, 图标))
		elif 提示 != "":
			图标.mouse_entered.connect(func() -> void: 状态图标悬停.emit(图标, 提示, -1))
		if 基础牌id >= 0 or 提示 != "":
			图标.mouse_exited.connect(func() -> void: 状态图标离开悬停.emit())
		var 旧列表: Array = _状态弹出起点.get(标识, [])
		var 本组: Array = 起点表.get(标识, [])
		var 序号: int = 本组.size()
		# 同一枚标识的第 n 个实例：上次还在就沿用它的起点（动画接着播），新出现的才记「现在」；
		# 进场第一次全记 -1（已有的状态当作早就挂上，不播）
		起点 = int(旧列表[序号]) if 序号 < 旧列表.size() \
				else (-1 if not _状态已初始化 else Time.get_ticks_msec())
		本组.append(起点)
		起点表[标识] = 本组
	# 必须先入树再播动画：_add_child_go 会把 scale 重置成 1，先摆好的放大态会被它抹掉
	_add_child_go(basicAndExCardArea, go)
	if go is Control and 起点 >= 0:
		var 图标: Control = go as Control
		var 已过: float = float(Time.get_ticks_msec() - 起点) / 1000.0
		_播状态弹出(图标, 已过)


## 状态图标「弹出」：先摆成放大态，再缩回原大小。
## 已过 是这一枚动画已经走过的时间（跨重建续播用），已经走完就不再播
func _播状态弹出(节点: Control, 已过: float = 0.0) -> void:
	if 节点 == null or 已过 >= 状态弹出时长:
		return
	节点.pivot_offset = Vector2(状态图标尺寸, 状态图标尺寸) * 0.5
	节点.scale = Vector2.ONE * lerpf(状态弹出放大, 1.0, 已过 / 状态弹出时长)
	var 缩回: Tween = 节点.create_tween()
	缩回.tween_property(节点, "scale", Vector2.ONE, 状态弹出时长 - 已过)


## 点了场上的一枚基础效果图标：把「谁的、哪张牌」报给战斗界面
func _on_基础牌图标输入(event: InputEvent, 基础牌id: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		基础效果牌点击.emit(ID, 基础牌id)


## 打开/关闭「面板上的基础效果图标可点」（选牌来源为 CardSource.BasicEffect 的技能期间由战斗界面打开）
func set_基础牌可点(value: bool) -> void:
	if _基础牌可点 == value:
		return
	_基础牌可点 = value
	_刷新状态图标()

## 对应 C# BasicAndExCards setter 里的一长串 if/else 贴图名映射
## 卡名用 CardName 枚举判断；技能用技能号判断（号来自卡表「技能1/技能2」的引用）
func _basic_card_sprite(card: GCard) -> String:
	match card.card_name_enum():
		GConst.CardName.Poison:
			return "du"
		GConst.CardName.Shield:
			return "dun"
		GConst.CardName.Weaken:
			return "xu"
		GConst.CardName.WuXiShuFu:
			return "shufu"
		GConst.CardName.TiaoXin:
			return "tiaoxin"
		GConst.CardName.LingHunLianJie:
			return "lianjie"
		GConst.CardName.TongShengGongSi:
			return "tongsheng"
		GConst.CardName.YongHengYueZhang:
			return "yuezhang"
	if card.has_skill_id(GConst.技能_天使之墙):
		return "dun"
	if card.has_skill_id(GConst.技能_威力赐福):
		return "wei"
	if card.has_skill_id(GConst.技能_迅捷赐福):
		return "xun"
	if card.has_skill_id(GConst.技能_地之封印):
		return "difeng"
	if card.has_skill_id(GConst.技能_火之封印):
		return "huofeng"
	if card.has_skill_id(GConst.技能_水之封印):
		return "shuifeng"
	if card.has_skill_id(GConst.技能_风之封印):
		return "fengfeng"
	if card.has_skill_id(GConst.技能_雷之封印):
		return "leifeng"
	return ""

## 对应 C# public KeyValuePair<uint,uint> Energy 的 setter（Key=宝石, Value=水晶）
func set_Energy(value: Vector2i) -> void:
	if energyArea == null:
		return
	# 宝石数变化：新到手的几格记下「现在」作为闪白起点；少了就丢最左边的（同手牌格的做法）
	var 旧数: int = _上次宝石数
	if 旧数 < 0:
		# 进场第一次：已有的宝石当作早就到手，不闪
		for _init: int in range(value.x):
			_宝石闪白起点.append(-1)
	elif value.x > 旧数:
		var 现在: int = Time.get_ticks_msec()
		for _add: int in range(value.x - 旧数):
			_宝石闪白起点.append(现在)
	elif value.x < 旧数:
		for _del: int in range(旧数 - value.x):
			_宝石闪白起点.remove_at(0)
	for c in energyArea.get_children():
		c.queue_free()
	var ps := _load_prefab("Image")
	for _i in range(value.x):
		var 宝石格: Control = _add_image(energyArea, ps, "gem", 能量格尺寸, false)
		_接格子提示(宝石格, "星石-宝石")
		_加闪白层(宝石格, _宝石闪白起点[_i] if _i < _宝石闪白起点.size() else -1)
	for _j in range(value.y):
		_接格子提示(_add_image(energyArea, ps, "crystal", 能量格尺寸, false), "星石-水晶")
	_上次宝石数 = value.x
	_摆图标(energyArea, 1, 0, 能量区图标格)


## 面板上那几排小方块（星石 / 手牌 / 治疗）：鼠标指上去弹一行说明（提示框由容器统一摆）。
## 这些方块都压在头像按钮上，所以不能只顾着收 hover 而把点击吃掉 ——
## 用 STOP 收 hover，同时把左键转发成面板按钮的 pressed（面板的点击有两个听众：
## 面板自己的 onClick 和容器的 _on_player_pressed，转发必须走信号而不是直接调方法）。
## 面板其余图标（基础效果 / 指示物）仍是 IGNORE / STOP 的老样子，本次不动
func _接格子提示(格: Control, 文本: String) -> void:
	if 格 == null:
		return
	格.mouse_filter = Control.MOUSE_FILTER_STOP
	格.mouse_entered.connect(func() -> void: 状态图标悬停.emit(格, 文本, -1))
	格.mouse_exited.connect(func() -> void: 状态图标离开悬停.emit())
	格.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit())


## 新到手宝石的闪白：给这一格套上闪白材质，按剩余时间把强度淡到 0。
## 用着色器只把「图形本身」推白，透明处不受影响 —— 直接铺一层白色方块会把整格都染白
func _加闪白层(格: Control, 闪白起点: int) -> void:
	if 格 == null or 闪白起点 < 0:
		return
	var 已过: float = float(Time.get_ticks_msec() - 闪白起点) / 1000.0
	if 已过 >= 宝石闪白时长:
		return
	var 强度: float = 宝石闪白起始强度 * (1.0 - 已过 / 宝石闪白时长)
	# 每格一份自己的材质：强度各不相同，共用一份会互相覆盖
	var 材质: ShaderMaterial = ShaderMaterial.new()
	材质.shader = 闪白着色器
	材质.set_shader_parameter("flash", 强度)
	格.material = 材质
	var 淡出: Tween = 格.create_tween()
	淡出.tween_method(_设闪白强度.bind(材质), 强度, 0.0, 宝石闪白时长 - 已过)


func _设闪白强度(值: float, 材质: ShaderMaterial) -> void:
	材质.set_shader_parameter("flash", 值)

## 手牌那一排每格的「补牌起点」（毫秒），下标从左到右、长度＝当前手牌数；
## -1 表示这一格早就补好了、不用播橙变绿。
var _手牌格起点: Array[int] = []
## 上一次显示的宝石数（-1＝还没显示过）：用来认出这次哪几格宝石是新到手的
var _上次宝石数: int = -1
## 宝石格「闪白起点」（毫秒），下标从左到右、长度＝当前宝石数；-1 表示这一格不用闪。
## 和手牌格的补牌起点一样，起点要跨「重建」留着：能量区同一帧可能被刷新好几次，
## 每次都清空重建，只挂一个一次性 tween 会被下一次重建连根清掉（那样就看不到闪白）
var _宝石闪白起点: Array[int] = []
## 是否已经收到过一次手牌数（区分「进场首次显示」（不播动画）与「之后补牌」）
var _手牌已初始化: bool = false


## 对应 C# public KeyValuePair<uint,uint> HandCount 的 setter（Key=手牌上限, Value=当前手牌）
func set_HandCount(value: Vector2i) -> void:
	if handArea == null:
		return
	# 手牌数变化：新增的格子记下「现在」作为黄变绿的起点；减少（弃牌）时丢最左边的旧牌，
	# 保住右边那几格正在播放的黄变绿动画不被中途打断。
	var 手牌数: int = value.y
	var 旧数: int = _手牌格起点.size()
	if not _手牌已初始化:
		# 进场第一次显示：已有的手牌当作早就补好，不播橙变绿
		_手牌已初始化 = true
		for _i: int in range(手牌数):
			_手牌格起点.append(-1)
	elif 手牌数 > 旧数:
		var 现在: int = Time.get_ticks_msec()
		for _j: int in range(手牌数 - 旧数):
			_手牌格起点.append(现在)
	elif 手牌数 < 旧数:
		for _k: int in range(旧数 - 手牌数):
			_手牌格起点.remove_at(0)
	for c in handArea.get_children():
		c.queue_free()
	var ps := _load_prefab("Image")
	# 原版语义（对照 Unity 预制体的 GridLayoutGroup：cellSize=33×14、spacing=-13 → 每格实际
	# 只前进 20px，所以方块是互相叠着的一排）。三张贴图的含义（按实际颜色核对）：
	#   handcard      绿色  → 当前手牌
	#   handcardempty 暗灰  → 上限之内、还没摸到的空位
	#   handcardfull  红色  → 超过手牌上限的部分（「爆牌」标记）
	# 所以空位要用暗灰的 handcardempty，不能用红色那张 —— 之前把空位画成红色，
	# 手牌不满时看起来像「超上限了」。
	# 顺序也一样重要：**先判「是否已超过上限」**，再判「这一格摸到没」。
	# 之前先判 j < 当前手牌，爆牌时（当前 > 上限）所有格子都落进第一个分支涂成绿色，
	# 红色的「爆牌」块永远不会出现。
	var total := maxi(value.x, value.y)
	# 这一排每格挂同一行悬停提示：「手牌 当前/上限」，空位格也能指（看得到差几张）
	var 提示: String = "手牌 %d/%d" % [value.y, value.x]
	for j in range(total):
		if j >= value.x:
			_接格子提示(_add_image(handArea, ps, "handcardfull", 扁平格尺寸, true, _手牌描边), 提示)
		elif j < value.y:
			_接格子提示(_加当前手牌格(ps, _手牌格起点[j]), 提示)
		else:
			_接格子提示(_add_image(handArea, ps, "handcardempty", 扁平格尺寸, true, _手牌描边), 提示)


## 一格「当前手牌」：绿块打底；若是刚补上来的（补牌起点 >= 0 且动画还没走完），
## 上面再盖一层黄块 —— 用与绿块同一张素材，只覆盖绿块的图形区域，
## 先整块黄保持 补牌黄色时长 秒，最后 补牌渐变时长 秒才淡出露出绿块。
## 返回打底的绿块（调用方要给它挂悬停提示）
func _加当前手牌格(ps: PackedScene, 补牌起点: int) -> Control:
	var 绿块: Control = _add_image(handArea, ps, "handcard", 扁平格尺寸, true, _手牌描边)
	if 绿块 == null or 补牌起点 < 0:
		return 绿块
	var 已过: float = float(Time.get_ticks_msec() - 补牌起点) / 1000.0
	if 已过 >= 补牌黄色时长 + 补牌渐变时长:
		return 绿块
	# 黄块整个来自预制体（素材 / 材质 / 尺寸设置都在里面）
	var 黄块: TextureRect = 补牌黄块预制体.instantiate() as TextureRect
	绿块.add_child(黄块)
	黄块.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 前 补牌黄色时长 秒整块黄、不动；只有最后 补牌渐变时长 秒才淡出露出绿块。
	# 颜色来自材质，这里只用 modulate 的 a 通道做淡出
	var 渐变已过: float = maxf(已过 - 补牌黄色时长, 0.0)
	黄块.modulate = Color(1.0, 1.0, 1.0, 1.0 - 渐变已过 / 补牌渐变时长)
	var 淡出: Tween = 黄块.create_tween()
	if 已过 < 补牌黄色时长:
		淡出.tween_interval(补牌黄色时长 - 已过)
	淡出.tween_property(黄块, "modulate:a", 0.0, 补牌渐变时长 - 渐变已过)
	淡出.tween_callback(黄块.queue_free)
	return 绿块

## 对应 C# public uint HealCount 的 setter
func set_HealCount(value: int) -> void:
	if healArea == null:
		return
	for c in healArea.get_children():
		c.queue_free()
	var ps := _load_prefab("Image")
	# 治疗同理：蓝块 = 当前治疗数，暗蓝块（handcardempty 那张） = 一直到治疗上限。
	# 注意没有 healfull 这张图（assets/textures/battle 下只有 heal / handcard / handcardfull /
	# handcardempty），所以补空格要用 handcardempty。
	# 上限：参考工程取 role.get_max_heal_count()（技能系统），本工程改用玩家视图 GPlayer.cross_max。
	var max_heal: int = 0
	var 玩家: GPlayer = Data.get_player_by_id(ID)
	if 玩家 != null:
		max_heal = 玩家.cross_max
	# 这一排每格挂同一行悬停提示：「治疗 当前/上限」（上限会随角色被动 / 星杯条件变）
	var 提示: String = "治疗 %d/%d" % [value, max_heal]
	for _j in range(value):
		_接格子提示(_add_image(healArea, ps, "heal", 扁平格尺寸, true, _治疗描边), 提示)
	for _k in range(maxi(max_heal - value, 0)):
		_接格子提示(_add_image(healArea, ps, "handcardempty", 扁平格尺寸, true, _治疗描边), 提示)

func _add_image(parent: Node, ps: PackedScene, sprite_name: String, 格尺寸: Vector2, 横向叠放: bool, 材质: Material = null) -> Control:
	if ps == null or parent == null:
		return null
	var go := ps.instantiate()
	var tex := _load_sprite(sprite_name)
	if tex != null and go is TextureRect:
		(go as TextureRect).texture = tex
	# 手牌 / 治疗那一排的方块挂上「受击描边」材质，受击时整排的深色描边一起染红
	if 材质 != null and go is CanvasItem:
		(go as CanvasItem).material = 材质
	# 从 Unity 转过来的 Image 预制体尺寸是 0×0（RectTransform 没带过来），名牌下方那排
	# 斜方块（手牌数/治疗/能量）因此全都看不见 —— 这里按素材的真实比例补尺寸与排布：
	#   手牌 / 治疗：原版 GridLayoutGroup cellSize 33×14、spacing −13（负间距 → 方块互相
	#   叠着、每格前进 20px），照抄成横向一排；
	#   能量（宝石 / 水晶）：素材近似正方形，竖着排成一列，别按横向扁条画。
	if go is Control:
		(go as Control).custom_minimum_size = 格尺寸
	if parent is GridContainer:
		var gc := parent as GridContainer
		gc.columns = 99 if 横向叠放 else 1
		gc.add_theme_constant_override("h_separation", 扁平格叠放间距 if 横向叠放 else 0)
		gc.add_theme_constant_override("v_separation", 0)
	_add_child_go(parent, go)
	return go as Control


## 对应 C# public string Chat 的 setter
func set_Chat(value: String) -> void:
	if chat == null:
		return
	# 对应 C#：StopCoroutine(chatCoro)（SceneTreeTimer 无法取消，用标志位代替）
	chat.set_meta("__cancel", true)
	# 场景里 ChatText 这个 Label 自己也是 visible=false（Unity 只关父节点 ChatPurple），
	# 只打开父节点的话气泡里没有任何文字（battle_audit H-8）。
	chat.visible = true
	chat.get_parent().visible = true
	chat.text = value
	chat.set_meta("__cancel", false)
	var t := get_tree().create_timer(5.0)
	chatTimer = t
	t.timeout.connect(_on_chat_timeout)

func _on_chat_timeout() -> void:
	if chat == null:
		return
	chat.get_parent().visible = false
	chatTimer = null

## 对应 C# public string WaitAction 的 setter
func set_WaitAction(value: String) -> void:
	if waitAction == null:
		return
	waitAction.text = value
	_自适应等待字号()
	# 场景里这个 Label 自己也是 visible=false（Unity 只关父节点），不显式打开的话
	# 「等待行动」这行字永远看不到。
	waitAction.visible = value != ""
	if value == "":
		waitAction.get_parent().visible = false
	else:
		waitAction.get_parent().visible = true


## 等待文案（名牌上那行「等待响应XX」）的字号自适应：
## 文案带着技能名，20 号字常常一行放不下，会折成两行压在头像上（名牌里那段宽度只有 160）。
## 这里按 Label 的实际宽度逐级缩小字号，尽量保持一行；放得下就还原成基础字号
## （否则上一条长文案会把后面的短文案也一直缩着）
func _自适应等待字号() -> void:
	if waitAction == null:
		return
	var 字体: Font = waitAction.get_theme_font("font")
	if 字体 == null:
		return
	var 允许宽: float = maxf(waitAction.size.x - 8.0, 60.0)
	var 字号: int = 等待文案基础字号
	while 字号 > 等待文案最小字号 \
			and 字体.get_string_size(waitAction.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 字号).x > 允许宽:
		字号 -= 1
	waitAction.add_theme_font_size_override("font_size", 字号)


## 名牌上方的超时进度条：负值收起，0~1 摆到对应长度
func set_WaitProgress(value: float) -> void:
	if waitProgress == null:
		return
	waitProgress.visible = value >= 0.0
	if value >= 0.0:
		waitProgress.value = value

## ---------------- 对应 C# 的回调 ----------------

## 对应 C# private void onClick()
func onClick() -> void:
	# 参考工程在这里通过 BattleData.Agent 选 / 取消选择目标。
	# 本工程交互层下一步再接。第三步：出牌/选目标技能交互层。
	pass

## 对应 C# public void onMinusClick()  （由 BattleUIMobile.tscn 的 [connection] 调用，逐字保留）
func onMinusClick() -> void:
	# 参考工程：BattleData.Agent.RemoveSelectPlayer(ID)。第三步：出牌/选目标技能交互层。
	pass

## 对应 C# private void onLongPress()
func onLongPress() -> void:
	# 参考工程在这里长按弹「角色信息」窗；本工程已改成鼠标指向头像（或点头像）即显示技能说明
	# （面板只报 悬停 / 离开悬停，说明框由容器 battle_mobile 摆），长按不再另做处理。
	pass

## 对应 C# public void OnEventTrigger(MessageType eventType, params object[] parameters)
func on_event_trigger(eventType: int, parameters: Array) -> void:
	match eventType:
		Msg.T.AgentSelectPlayer:
			# 参考工程按 BattleData.Agent 的选中列表切换选中框 / 可选框 / 多选计数。
			# 本工程交互层下一步再接。第三步：出牌/选目标技能交互层。
			pass
		Msg.T.RecHandChange:
			# 对应 C#：parameters[1] == PlayerIdxOrder.IndexOf(ID)。
			# 本工程面板顺序 = Data.player_list 顺序，故用它找下标。第三步：手牌区交互层。
			if parameters.size() < 2:
				return
			var 面板下标: int = -1
			for i: int in range(Data.player_list.size()):
				if Data.player_list[i].id == ID:
					面板下标 = i
					break
			if int(parameters[1]) == 面板下标:
				_rec_updata_card(parameters[0] as Array)

## 对应 C# private void RecUpdataCard(List<uint> cards)
func _rec_updata_card(cards: Array) -> void:
	for c in cardUIs:
		if is_instance_valid(c):
			c.queue_free()
	cardUIs.clear()
	if recHandArea == null:
		return
	var ps := _load_prefab("Card")
	if ps == null:
		return
	for card_id in cards:
		var go := ps.instantiate()
		recHandArea.add_child(go)
		var card: GCard = Data.get_card(int(card_id))
		# CardUI 对外只有「设置卡牌(new_card, 可用)」这一个入口，用 call 调它。
		# （原来写的是 go.set("CardData", card)：CardUI 没有这个属性，set 静默失效，
		# 别人亮出的手牌连数据都没设上，是空白牌。）
		go.call("设置卡牌", card, false)
		cardUIs.append(go)

## 头像背后那个魔法阵（Turn 那圈金色法阵，b02_sys_turn）的自转角速度：每秒 15°，
## 负值 = 屏幕上向左转（逆时针）；节点的 pivot 已在预制体里钉在正中，绕中心转
const 魔法阵角速度: float = -15.0


## 头像背后的魔法阵持续左转（只有轮到本玩家时才显示这圈法阵）
func _process(delta: float) -> void:
	if turn != null and turn.visible:
		turn.rotation += deg_to_rad(魔法阵角速度) * delta


## 对应 C# public void TurnBegin()
func TurnBegin() -> void:
	# 对应 C# Turn = true;
	set_Turn(true)
	var is_main: bool = false
	var my_id: int = Logic.my_player_id
	is_main = ID == my_id
	# 观战者（id == GConst.GUEST）视角下，0 号位算「自己」（同参考工程用 PlayerIdxOrder[0]）
	if my_id == GConst.GUEST and Data.player_list.size() > 0:
		is_main = ID == Data.player_list[0].id
	if turn == null:
		return
	# 对应 C# DOTween 的 DOScale
	if is_main:
		turn.scale = Vector2(2.5, 2.5)
		var tw := create_tween()
		tw.tween_property(turn, "scale", Vector2(2.0, 2.0), 1.5)
	else:
		turn.scale = Vector2(2.0, 2.0)
		var tw2 := create_tween()
		tw2.tween_property(turn, "scale", Vector2(1.2, 1.2), 1.5)

# ============================================================
# 受击反馈：泛红 + 抖动 + 画面扭曲震荡波 —— 都放在本面板里，方便在这个预制体上调参
# ============================================================
## 受击泛红色与泛红时长（秒）：命中瞬间点亮，再淡回常态
const 受击泛红色: Color = Color(1.0, 0.675, 0.675)
const 受击泛红时长: float = 1.0
## 受击抖动：初始幅度（像素）、单次时长（秒）、来回次数（幅度逐次衰减）
const 受击抖动幅度: float = 10.0
const 受击抖动单次时长: float = 0.1
const 受击抖动次数: int = 5
## 受击画面扭曲震荡波（着色器见 scripts/effects/hitShockwave.gdshader）：
## 时长（秒）、最大半径 / 波带厚度 / 波内位移强度（按屏幕高算的 UV 单位）
const 受击震荡波着色器: Shader = preload("res://scripts/effects/hitShockwave.gdshader")
const 震荡波时长: float = 0.60
const 震荡波半径: float = 0.60
const 震荡波波宽: float = 0.055
const 震荡波强度: float = 0.010
## 受击描边：把手牌 / 治疗方块贴图自带的深色描边染红，再用 受击描边时长 淡回原色
const 受击描边着色器: Shader = preload("res://scripts/effects/hitOutline.gdshader")
const 受击描边时长: float = 2.0
## 宝石闪白着色器：只把图形本身推白、透明处不动（见 scripts/effects/flashWhite.gdshader）
const 闪白着色器: Shader = preload("res://scripts/effects/flashWhite.gdshader")
## 状态图标的白描边着色器：沿 alpha 轮廓扩一圈白边（见 scripts/effects/whiteOutline.gdshader）
const 状态描边着色器: Shader = preload("res://scripts/effects/whiteOutline.gdshader")

## 头像初始位置：首次受击时记下，之后每次抖动都围绕它 —— 连续受击也不会把头像越抖越偏
var _头像原位: Vector2 = Vector2.ZERO
var _头像原位已记: bool = false
## 手牌 / 治疗那两排方块的受击描边材质（_ready 里建好；同一排共用一个，才会整排一起红）
var _手牌描边: ShaderMaterial = null
var _治疗描边: ShaderMaterial = null
## 描边淡回的补间：连续受击时先把旧的杀掉，免得两个补间抢同一个参数
var _描边淡出: Tween = null

## 对应 C# public void Hurted()：受击表现。
## 播放震荡波 = true 时额外叠一圈画面扭曲（只在「斩命中 / 魔弹命中」时由调用方传入）；
## 泛红、抖动则每次受击都播。
func Hurted(播放震荡波: bool = false) -> void:
	if hero == null:
		return
	# 对应 C# hurted.SetTrigger("Hurt")
	if hurted != null and hurted is AnimationPlayer:
		(hurted as AnimationPlayer).play("Hurt")
	if not _头像原位已记:
		_头像原位 = hero.position
		_头像原位已记 = true
	hero.modulate = 受击泛红色
	var 红: Tween = hero.create_tween()
	红.tween_property(hero, "modulate", Color.WHITE, 受击泛红时长)
	var 抖: Tween = hero.create_tween()
	for i: int in range(受击抖动次数):
		var 幅度: float = 受击抖动幅度 * (1.0 - float(i) / float(受击抖动次数))
		var 方向: float = 1.0 if i % 2 == 0 else -1.0
		抖.tween_property(hero, "position", _头像原位 + Vector2(方向 * 幅度, 0.0), 受击抖动单次时长)
	抖.tween_property(hero, "position", _头像原位, 受击抖动单次时长)
	_闪受击描边()
	if 播放震荡波:
		_播放受击震荡波()


## 建一份受击描边材质（描边染色强度初始为 0＝原色）
func _造描边材质() -> ShaderMaterial:
	var 材质: ShaderMaterial = ShaderMaterial.new()
	材质.shader = 受击描边着色器
	材质.set_shader_parameter("mix_amount", 0.0)
	return 材质


## 受击时把手牌 / 治疗两排方块的深色描边一起染红，再用 受击描边时长 淡回原色
func _闪受击描边() -> void:
	if _手牌描边 == null and _治疗描边 == null:
		return
	if _描边淡出 != null and _描边淡出.is_valid():
		_描边淡出.kill()
	if _手牌描边 != null:
		_手牌描边.set_shader_parameter("mix_amount", 1.0)
	if _治疗描边 != null:
		_治疗描边.set_shader_parameter("mix_amount", 1.0)
	# 正在播的补牌黄块：描边也是同一套着色器，跟着一起红、一起淡回
	补牌黄块材质.set_shader_parameter("mix_amount", 1.0)
	_描边淡出 = create_tween()
	_描边淡出.set_parallel(true)
	if _手牌描边 != null:
		_描边淡出.tween_method(_设描边强度.bind(_手牌描边), 1.0, 0.0, 受击描边时长)
	if _治疗描边 != null:
		_描边淡出.tween_method(_设描边强度.bind(_治疗描边), 1.0, 0.0, 受击描边时长)
	_描边淡出.tween_method(_设描边强度.bind(补牌黄块材质), 1.0, 0.0, 受击描边时长)


func _设描边强度(值: float, 材质: ShaderMaterial) -> void:
	材质.set_shader_parameter("mix_amount", 值)


## 在战斗界面根节点上叠一块铺满屏幕的透明 ColorRect，跑一圈从本面板中心扩散出去的画面扭曲。
## 面板在场景里是战斗界面根节点（Root）的直接子节点，故用 get_parent() 拿它；
## 波挂在 Root 下才铺得满整屏。
## 震荡波节点与材质「全局共用一份」：画面扭曲要采样整屏，是全屏开销最大的一块 ——
## 每次受击都新建、或多人同帧各播一张，就会叠出多张全屏 quad（弱机上明显卡顿）。
## 共用后同一时刻最多一次全屏采样，也免去运行期反复分配节点 / 材质与首次编译的卡顿。
static var _共享波: ColorRect = null
static var _共享波材质: ShaderMaterial = null
static var _共享波补间: Tween = null


func _播放受击震荡波() -> void:
	var 根: Control = get_parent() as Control
	if 根 == null or 根.size.x <= 0.0 or 根.size.y <= 0.0:
		return
	if _共享波 == null or not is_instance_valid(_共享波):
		_共享波 = ColorRect.new()
		_共享波.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_共享波材质 = ShaderMaterial.new()
		_共享波材质.shader = 受击震荡波着色器
		_共享波.material = _共享波材质
	if _共享波.get_parent() != 根:
		if _共享波.get_parent() != null:
			_共享波.get_parent().remove_child(_共享波)
		根.add_child(_共享波)
	# 只铺「波可能扫到的方框」（中心 ± (半径 + 波宽 + 强度)），不再铺满整屏：
	# 着色器照样按 SCREEN_UV 取屏、扭曲结果不变，但要着色的像素从整屏缩到这一小块
	var 半径像素: float = (震荡波半径 + 震荡波波宽 + 震荡波强度) * 根.size.y
	var 中心: Vector2 = get_rect().get_center()
	_共享波.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_共享波.position = 中心 - Vector2(半径像素, 半径像素)
	_共享波.size = Vector2(半径像素, 半径像素) * 2.0
	_共享波材质.set_shader_parameter("center_uv", 中心 / 根.size)
	_共享波材质.set_shader_parameter("aspect", 根.size.x / 根.size.y)
	_共享波材质.set_shader_parameter("radius", 震荡波半径)
	_共享波材质.set_shader_parameter("band", 震荡波波宽)
	_共享波材质.set_shader_parameter("strength", 震荡波强度)
	_共享波材质.set_shader_parameter("progress", 0.0)
	_共享波材质.set_shader_parameter("fade", 1.0)
	_共享波.visible = true
	if _共享波补间 != null and _共享波补间.is_valid():
		_共享波补间.kill()
	_共享波补间 = _共享波.create_tween()
	_共享波补间.set_parallel(true)
	_共享波补间.tween_method(_设震荡波进度.bind(_共享波材质), 0.0, 1.0, 震荡波时长)
	# 前 40% 保持不透明（波还没走远），之后再淡出
	_共享波补间.tween_method(_设震荡波淡出.bind(_共享波材质), 1.0, 0.0, 震荡波时长 * 0.6).set_delay(震荡波时长 * 0.4)
	_共享波补间.chain().tween_callback(_收起共享波)


func _收起共享波() -> void:
	if _共享波 != null and is_instance_valid(_共享波):
		_共享波.visible = false


func _设震荡波进度(值: float, 材质: ShaderMaterial) -> void:
	材质.set_shader_parameter("progress", 值)


func _设震荡波淡出(值: float, 材质: ShaderMaterial) -> void:
	材质.set_shader_parameter("fade", 值)


## 能量区 / 状态图标区自己算坐标（这两个区域在场景里是 Control）：
## 原版 Unity 的 GridLayoutGroup 是「第一枚贴底、后加的往上长」，而 Godot 的 GridContainer 只认
## 「左上角起、一行行往下排」，行不满时还排不出原版的形状，所以这里直接按格子摆。
## 每列格数 <= 0 表示一列到底；图标比格子小时在格子里居中（20×20 的图标落在 30×30 格里）。
## （列数 只保留原版 C# 的签名，实际排几列由 每列格数 决定。）
## 格尺寸：不同区域格子大小不同（状态图标区 28、能量区 30），由调用方传入。
func _摆图标(容器: Control, _列数: int, 每列格数: int, 格尺寸: Vector2) -> void:
	if 容器 == null:
		return
	var 可见: Array[Control] = []
	for c: Node in 容器.get_children():
		# 刷新时旧的图标是 queue_free 掉的，本帧还在树上 —— 必须跳过，否则会把它们算进格数，
		# 容器高度偏高、图标整体浮在上方（底下留出一段空）
		if c is Control and not c.is_queued_for_deletion() and (c as Control).visible:
			可见.append(c as Control)
	var 一列: int = 每列格数 if 每列格数 > 0 else maxi(可见.size(), 1)
	var 高格数: int = mini(一列, 可见.size())
	# 容器底边钉住不动，顶边按内容高度往上退 —— 于是后加的图标是「往上长」而不是往下
	容器.offset_top = 容器.offset_bottom - float(高格数) * 格尺寸.y
	for i: int in range(可见.size()):
		@warning_ignore("integer_division")
		var 列号: int = i / 一列
		var 行号: int = i % 一列
		var 格位: Vector2 = Vector2(float(列号) * 格尺寸.x, float(高格数 - 1 - 行号) * 格尺寸.y)
		var 自身: Vector2 = 可见[i].custom_minimum_size
		可见[i].position = 格位 + (格尺寸 - 自身) * 0.5


## 对应 C# private void addChildGO(Transform parent, GameObject go)
func _add_child_go(parent: Node, go: Node) -> void:
	parent.add_child(go)
	if go is Control:
		# 从 Unity 转过来的节点尺寸都是 0×0，而父节点多是 GridContainer（每帧把子节点 size
		# 重置成最小尺寸）—— 只设 size 没用，必须给 custom_minimum_size，否则整批看不见。
		# 已经由调用方给过尺寸的（比如手牌/治疗/能量那排小方块）不要覆盖。
		var ctl := go as Control
		if ctl.custom_minimum_size == Vector2.ZERO:
			ctl.custom_minimum_size = Vector2(30.0, 40.0)
		ctl.position = Vector2.ZERO
		ctl.scale = Vector2.ONE

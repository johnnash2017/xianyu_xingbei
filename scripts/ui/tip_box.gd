class_name 说明提示框
extends Control
## 通用悬浮说明框：深色圆角底板 + BBCode 富文本，摆在锚点正上方并夹在宿主控件内。
## 战斗界面（悬停头像 / 技能按钮）与选角界面（悬停角色卡）共用同一套外观与排版 ——
## 内容太长时先按宿主宽度上限加宽（少折行→更矮），仍塞不下就整框等比缩小兜底，内容永远全在。
##
## 用法：把它 add_child 到「作为坐标与剪裁基准的宿主控件」下（一般就是界面根节点），
## 再调 显示() / 显示角色说明()；框会挂在宿主下，共用宿主的坐标与缩放。
## 注意：本节点必须是 Control（CanvasItem）——若换成普通 Node，子控件不继承宿主缩放
## （会落到画布空间），_摆 算出的本地坐标就对不上，提示框会摆到离目标很远的错位处。
##
## 整块提示只是「看」的：所有子节点都设 mouse_filter = IGNORE（见 _全忽略），
## 不参与点击 / mouse_entered / mouse_exited，也不会挡住它下面的控件。

## 角色说明的默认排版（战斗 / 选角共用；宽度 / 字号改这里，整体大小走设置窗的「技能说明尺寸」）
const 角色说明宽度: float = 684.0
const 角色说明字号: int = 16
## 专属卡牌分组框 / 分组里每条技能 / 普通说明行（标题、姓名、脚注）/ 正文技能行的预制体
## （结构、字号、缩进、间距都在场景里调）
const 分组框预制: PackedScene = preload("res://scenes/prefabs/ui/SkillGroupBox.tscn")
const 分组技能预制: PackedScene = preload("res://scenes/prefabs/ui/SkillGroupItem.tscn")
const 说明行预制: PackedScene = preload("res://scenes/prefabs/ui/SkillTipRow.tscn")
const 正文行预制: PackedScene = preload("res://scenes/prefabs/ui/SkillTipBodyRow.tscn")
## 「原版说明（被角色改写后列出来对照）」的删除线：用字体自带的 [s]，位置 / 长度天然准；
## 只是它默认半透明（主题常量 strikethrough_alpha=50，见 _ready 改成不透明），不然压在灰字上看不清。
## 文字整块再压到 90%（角色名 36→32、标题 27→24、正文 18→16）
const 角色说明字号缩放: float = 0.9
## 整块缩放的范围（连底板、内边距、边框一起变档，靠节点整体缩放实现）：
## 设置窗滑杆 0% = 最小 0.6156，100% = 上限 1.3；默认 15%（约 0.7183）。
## 滑杆存的是 0~1 的档位，不是倍率；每次弹说明现读，改完设置下一次悬停就生效。
const 角色说明缩放_最小: float = 0.6156
const 角色说明缩放_最大: float = 1.3
## 本地配置键（Cfg 的 [设置] 段）：技能说明尺寸档位 0~1
const 设置键_角色说明缩放: String = "role_tip_scale"
## 没存过设置时用 15% 档（接近之前的观感）
const 默认角色说明缩放档: float = 0.15
## 当前档位缓存：设置窗拖动后立即写这里，全角色预览 / 之后弹出的说明马上按新尺寸，
## 不用等设置窗关闭落盘；启动后第一次用到时再从本地配置读回。
static var _当前缩放档: float = 默认角色说明缩放档
static var _已从配置读回: bool = false
## 内容放不下时最多加宽到「宿主宽 × 本比例」（留边距，整框仍在宿主内）
const 最大宽比例: float = 0.94
## 整框高超过「可用高 × 本比例」就加宽 —— 不等真放不下才加，长说明留出余量、更好读
const 高度阈值比例: float = 0.8
## 每次加宽的步长（像素）：一步一量，直到放得下或到上限
const 加宽步长: float = 120.0


## 深色圆角底板（结构在 TipBox.tscn 里，可所见即所得地改）
@export var 框: PanelContainer
## 底板里的富文本（【类型】要上色，普通 Label 会把颜色码原样显示出来）
@export var 文本: RichTextLabel
## 右上角星数（角色说明才显示；单独一个 Label 叠在富文本上，免得和角色名抢同一行）
@export var 星数标签: Label
## 自定义内容节点（如一张完整的卡牌视图，见 显示内容）；非空时文字隐藏，整框改按它的尺寸走
var 内容: Control = null
## 当前显示的是哪个角色 / 哪个缩放档：同一张卡反复悬停时直接不重排
var _说明角色号: int = -1
## 分块说明的内容容器：角色名 / 分段标题 / 每条技能 / 分组框都放这里。
## 常驻在 TipBox.tscn（不再运行时拼容器），行间距就是它的 separation，直接在场景里调。
@export var 块容器: VBoxContainer
## 当前显示的分块角色 / 缩放档（同一张卡反复悬停时不再重建）
var _块角色号: int = -1
var _块缩放: float = -1.0
## 这块内容这一帧还该不该显示（收起时清掉，防止迟到的回调把它又弹出来）
var _块要显示: bool = false
## 正在等下一帧量尺寸（RichTextLabel 刚进树那一帧内容高是 0）
var _块沉降中: bool = false
## 收起的缓冲计时器（见 收起缓冲）
var _收起计时: Timer = null
## 本次说明的「基准整体缩放」（角色说明按设置窗里的档位取）。摆框时若按它仍塞不进宿主，会在它基础上再等比缩小兜底
var _基缩放: float = 1.0
## 本次说明被上下夹住、和图标重叠时，是否横向让到图标一侧（角色说明用；
## 技能按钮 / 状态图标 / 卡面预览保持原来的正上方摆放）
var _让开图标: bool = false
## 显示的「轮次」：每次显示 / 收起都 +1，上一轮的沉降回调认不出版本就自己退出
var _轮次: int = 0
## 下一帧重摆要用的图标矩形：同帧多次显示只更新它，待摆回调始终只有一个（见 _排重摆）
var _待摆矩形: Rect2 = Rect2()
## 是否已挂了「下一帧再摆一次」的回调
var _待摆中: bool = false
## 是否已挂了「下一帧再显示」的回调
var _沉降中: bool = false
## 显示沉降属于哪一轮（_轮次 一变，这条就作废）
var _沉降轮次: int = 0
## 底板默认描边（TipBox.tscn 里 StyleBoxFlat 的 border_color / border_width）：
## 技能 / 状态 / 卡面提示都用它，只有「角色说明」会按命格换成别的颜色（见 显示角色说明）
var _默认描边: Color = Color(1, 1, 1, 0.22)
var _默认描边宽: int = 2
## 角色说明的描边加粗到多宽：命格色要一眼能分出来，默认那 2px 整框再缩一档就看不清了
const 角色说明描边宽: int = 3
## 收起前的缓冲（秒）：鼠标在卡片 / 头像之间快速移动时「离开 → 进入」是连着来的，
## 立刻收起再弹出看着就是闪。延后一点收，这期间只要又显示了就取消收起。
const 收起缓冲: float = 0.12
## 临时排查开关：角色说明的显示/收起在「输出」里打一行日志（问题定位完就改 false）
const 悬停调试: bool = false


## 行距：RichTextLabel 在字体行高之外还会加一截空隙（行间 / 段落间各一份），折半，别显得松散。
## 主题里的原值只有引擎知道，得运行期读出来再覆盖，故放在 _ready
func _ready() -> void:
	# 永远画在同层最上面：说明框虽然是后加的，但战斗界面之后还可能挂特效 / 飘字层，
	# 不抬高 z 的话大说明会被别的层压住（看起来就像「没弹出来 / 一闪就没」）
	z_index = 64
	# 提示框只是「看」的：整框不吃鼠标事件。
	# 否则框盖到被悬停的头像 / 技能按钮上时，鼠标一挪进去就把下面的控件判成「离开」，
	# 悬停说明被收起、鼠标又回到头像上重新弹出 —— 表现为框疯狂闪（分块说明更高，更容易碰到）
	框.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 只设根 / 底板不够：mouse_filter 是逐节点的，子节点默认 STOP 仍然会吃鼠标。
	# 整棵子树递归设成 IGNORE，点击 / mouse_entered / mouse_exited 都不会再在这块提示上触发。
	_全忽略(self)
	# 收起缓冲的计时器
	_收起计时 = Timer.new()
	_收起计时.one_shot = true
	_收起计时.wait_time = 收起缓冲
	_收起计时.timeout.connect(_真正收起)
	add_child(_收起计时)
	# 默认描边以场景里的底板为准（换了 TipBox.tscn 不用再来改这份代码）
	var 底板: StyleBoxFlat = _底板样式()
	if 底板 != null:
		_默认描边 = 底板.border_color
		_默认描边宽 = maxi(底板.border_width_left, 1)


## 底板样式（PanelContainer 的 panel）；不是 StyleBoxFlat（换成九宫格贴图）时返回 null
func _底板样式() -> StyleBoxFlat:
	return 框.get_theme_stylebox("panel") as StyleBoxFlat


## 整棵子树都设成「不吃鼠标」：提示框只负责看，所有点击 / 进入 / 离开都放给下面的控件。
## 只设根节点不够 —— mouse_filter 是逐节点的，子节点默认 STOP 照样会挡住鼠标信号。
## 新挂进框里的内容（分块、卡面预览等）在 add_child 之后都要再过一遍。
## 顺便把键盘焦点也关掉：提示框里的按钮 / 富文本不该被 Tab 聚焦，也不该响应回车。
func _全忽略(节点: Node) -> void:
	if 节点 is Control:
		var 控件: Control = 节点
		控件.mouse_filter = Control.MOUSE_FILTER_IGNORE
		控件.focus_mode = Control.FOCUS_NONE
	for 子: Node in 节点.get_children():
		_全忽略(子)


## 换提示框描边。底板的 StyleBoxFlat 是 resource_local_to_scene，每个提示框实例一份，
## 改它不会影响别的界面（战斗界面与选角界面各有一个提示框）
func _设描边(颜色: Color, 宽: int = -1) -> void:
	var 底板: StyleBoxFlat = _底板样式()
	if 底板 == null:
		return
	var 线宽: int = _默认描边宽 if 宽 < 0 else 宽
	底板.border_color = 颜色
	底板.border_width_left = 线宽
	底板.border_width_top = 线宽
	底板.border_width_right = 线宽
	底板.border_width_bottom = 线宽


## 显示一段说明：图标矩形取「视图坐标」，框摆在它正上方并夹在宿主内。
## 宽度 > 0：按这个宽度折行（角色 / 技能说明）；宽度 ≤ 0：不折行，整框按内容自适应
## （指示物那种一行短提示，不该为了填满固定宽度把底板撑大）
## 让开图标：上下都塞不下、框被夹到与图标重叠时，允许横向挪到图标一侧（角色说明用）
func 显示(说明: String, 图标矩形: Rect2, 宽度: float, 字号: int, 整体缩放: float = 1.0,
		可拓宽: bool = false, 让开图标: bool = false) -> void:
	_取消收起()
	if 说明.is_empty():
		return
	# 任何提示走这里都会被当成「不是某角色的说明」：避免下一次悬停同一角色时被误判成没变
	_说明角色号 = -1
	_卸内容()
	_隐藏星数()
	# 上一条可能是角色说明（按命格染过描边）：普通说明一律恢复默认描边
	_设描边(_默认描边)
	_基缩放 = 整体缩放
	_让开图标 = 让开图标
	文本.visible = true
	文本.add_theme_font_size_override("normal_font_size", 字号)
	文本.text = 说明
	# 折行宽度：角色说明这类长文本按「放得下为止尽量窄」同步定档（见 _算角色说明宽度）；其余按给定宽度
	# （宽度 ≤ 0 时也不折行，整框贴住内容 —— 指示物那种一行短提示不该为填满固定宽度把底板撑大）
	文本.autowrap_mode = TextServer.AUTOWRAP_OFF if 宽度 <= 0.0 else TextServer.AUTOWRAP_WORD_SMART
	文本.custom_minimum_size.x = _算角色说明宽度() if 可拓宽 else maxf(宽度, 0.0)
	_轮次 += 1
	_待摆矩形 = 图标矩形
	if 可拓宽:
		# 宽度已在上面同步算好；显示位置要等下一帧：容器的布局下一帧才生效，这一帧框还挂着上一个尺寸，
		# 直接显示会先闪一副错位的框
		框.visible = false
		_沉降轮次 = _轮次
		# 新的一轮：上一轮可能在飞的回调会按「轮次不符」自行退出；这里把在飞标记一并清掉，
		# 否则它会把 _排沉降 挡在门外、这一轮没人起链，框就一直不显示
		_沉降中 = false
		_排沉降()
	else:
		框.visible = true
		_摆(图标矩形)
		_排重摆(图标矩形)


## 设置窗滑杆的档位（0~1）换算成整框缩放：0 = 最小、1 = 上限
static func 档位到缩放(档: float) -> float:
	return lerpf(角色说明缩放_最小, 角色说明缩放_最大, clampf(档, 0.0, 1.0))


## 当前设置档位：没存过就是默认 15% 档。启动后第一次用到时读本地配置，
## 之后由设置窗拖动时调 设置角色说明缩放档 立即更新（全角色预览也能马上看到新尺寸）
func 当前角色说明缩放档() -> float:
	if not _已从配置读回:
		_当前缩放档 = clampf(float(Cfg.get_setting(
			设置键_角色说明缩放, 默认角色说明缩放档)), 0.0, 1.0)
		_已从配置读回 = true
	return _当前缩放档


## 设置窗拖动滑杆时调用：只改内存里的当前档位，落盘统一在设置窗收起时（见 settings._exit_tree）
static func 设置角色说明缩放档(档: float) -> void:
	_当前缩放档 = clampf(档, 0.0, 1.0)
	_已从配置读回 = true


## 显示角色说明（角色名一行 + 技能说明，含 BBCode）——战斗 / 选角同款
## 技能表里配了「专属卡牌」的角色走分块版：每组的技能套一个和整框同色的粗边框子面板；
## 其余角色仍走原来的整段富文本（一行没动）。
func 显示角色说明(角色号: int, 图标矩形: Rect2, 对局中: bool = false) -> void:
	_取消收起()
	var 缩放: float = 当前角色说明缩放档()
	# 同一张卡上反复悬停：内容、大小都没变，一个像素都不动（重排就是闪的来源）
	if _块角色号 == 角色号 and is_equal_approx(_块缩放, 缩放) and 框.visible \
			and 块容器 != null and 块容器.visible:
		return
	var 块: Array = 角色技能提示.悬浮提示块(角色号, 角色说明字号缩放, 对局中)
	if 块.is_empty():
		_块角色号 = 角色号
		_块缩放 = 缩放
		_清块容器()
		显示(角色技能提示.悬浮提示(角色号, 角色说明字号缩放, 对局中), 图标矩形,
			角色说明宽度, 角色说明字号, 档位到缩放(缩放), true, true)
		_命中描边与星数(角色号)
		return
	_建分块(块, 图标矩形, 角色号, 缩放)
	_命中描边与星数(角色号)


## 描边按命格换色 + 右上角星数
func _命中描边与星数(角色号: int) -> void:
	var 描边: Color = 角色技能提示.描边颜色(角色号)
	_设描边(描边 if 描边.a > 0.0 else _默认描边, 角色说明描边宽 if 描边.a > 0.0 else -1)
	if 星数标签 != null:
		var 星数: String = 角色技能提示.星数文本(角色号)
		星数标签.text = 星数
		星数标签.visible = 星数 != ""


## 建分块：角色名 / 分段标题 / 每条技能 / 标识物都各是一行（说明行预制体），
## 配了专属卡牌的分组换成 SkillGroupBox 预制体；行与行之间的间距＝块容器的 separation。
## 全部结构都在场景里（TipBox.tscn 的 块容器 / SkillTipRow.tscn / SkillGroupBox.tscn），
## 不在这里拼节点，方便直接在编辑器里调间距。
## 宽度固定用 角色说明宽度 —— 不做「一档档加宽重排」（那正是以前抖动 / 错位的来源）。
func _建分块(块: Array, 图标矩形: Rect2, 角色号: int, 缩放: float) -> void:
	_卸内容()
	# 星数标签是「文本」的子节点：这里不能把文本藏起来（会连星数一起藏掉），
	# 只把文字清空，占位高度自然为 0，星数照常显示在右上角
	文本.text = ""
	文本.visible = true
	_清块容器()
	var 描边: Color = 角色技能提示.描边颜色(角色号)
	if 描边.a <= 0.0:
		描边 = _默认描边
	for 项: Variant in 块:
		var d: Dictionary = 项
		if d.has("分组"):
			var 分组框: 专属卡牌分组框 = 分组框预制.instantiate() as 专属卡牌分组框
			分组框.mouse_filter = Control.MOUSE_FILTER_IGNORE
			分组框.设置标题(str(d.get("分组", "")))
			分组框.设描边(描边)
			# 组里每个技能各占一个节点（预制体里已经配好字号 / 行距 / 左侧缩进，这里只填文本）。
			# 注意：上色() 给正文套的是 [indent]，而 [indent] 出现在富文本最开头时会先另起一行
			# （等于凭空多一条空行，标题下面那截空隙的真因）。分组里每条技能都是独立富文本，
			# 所以这里把 [indent] 去掉，改用预制体 normal StyleBox 的 content_margin_left 缩进，
			# 首行和折行都对齐，也不会多出空行。
			for 技能: Variant in d.get("技能", []):
				var 条: RichTextLabel = 分组技能预制.instantiate() as RichTextLabel
				条.text = str(技能).replace("[indent]", "").replace("[/indent]", "")
				分组框.加技能(条)
			块容器.add_child(分组框)
		else:
			var 本条文案: String = str(d.get("文本", ""))
			var 条: RichTextLabel
			if 本条文案.contains("[indent]"):
				# 正文技能行：去掉 [indent]（它出现在富文本最开头会先另起一行，等于多一条空行），
				# 缩进改用正文行预制体 normal StyleBox 的 content_margin_left
				条 = 正文行预制.instantiate() as RichTextLabel
				条.text = 本条文案.replace("[indent]", "").replace("[/indent]", "")
			else:
				# 角色名 / 分段标题 / 右下角标识物：不缩进的说明行
				条 = 说明行预制.instantiate() as RichTextLabel
				条.text = 本条文案
			块容器.add_child(条)
	块容器.visible = true
	_全忽略(块容器)
	_块角色号 = 角色号
	_块缩放 = 缩放
	_块要显示 = true
	_待摆矩形 = 图标矩形
	框.visible = false
	# 下一帧量准尺寸再显示（RichTextLabel 刚进树那一帧量到的内容高是 0）
	if not _块沉降中:
		_块沉降中 = true
		get_tree().process_frame.connect(_块显示, CONNECT_ONE_SHOT)


## 分块内容建好后的第一帧收尾：给每个标签定宽（按这一档折好行）→ 显示 → 摆放
func _块显示() -> void:
	_块沉降中 = false
	if 块容器 == null or not is_inside_tree() or not _块要显示:
		return
	var 宽: float = 角色说明宽度
	_块总高(宽)
	块容器.custom_minimum_size.x = 宽
	框.visible = true
	框.reset_size()
	_摆(_待摆矩形)
	_排重摆(_待摆矩形)


## 把这一档宽度下每个标签都定好宽（RichTextLabel 必须同时改 size 才会按新宽度折行）
func _块总高(宽: float) -> float:
	if 块容器 == null:
		return 0.0
	var 总: float = 0.0
	var 子们: Array = 块容器.get_children()
	for 子: Node in 子们:
		if 子 is CanvasItem and not (子 as CanvasItem).visible:
			continue
		总 += _单块高(子, 宽)
	总 += float(块容器.get_theme_constant("separation")) * maxf(float(子们.size() - 1), 0.0)
	return 总


func _单块高(节点: Node, 宽: float) -> float:
	if 节点 is CanvasItem and not (节点 as CanvasItem).visible:
		return 0.0
	if 节点 is MarginContainer:
		var 边距: MarginContainer = 节点
		var 扣: float = float(边距.get_theme_constant("margin_left")) \
			+ float(边距.get_theme_constant("margin_right"))
		# 上下边距也算进这一行的高度（说明行的上下留白就在预制体里调）
		var 内高: float = float(边距.get_theme_constant("margin_top")) \
			+ float(边距.get_theme_constant("margin_bottom"))
		for 孙: Node in 边距.get_children():
			内高 += _单块高(孙, 宽 - 扣)
		return 内高
	if 节点 is PanelContainer:
		var 面板: PanelContainer = 节点
		var 样式: StyleBox = 面板.get_theme_stylebox("panel")
		var 内宽: float = 宽 - 样式.get_minimum_size().x
		var 高: float = 样式.get_minimum_size().y
		for 孙: Node in 面板.get_children():
			高 += _单块高(孙, 内宽)
		return 高
	if 节点 is Label:
		# 分组标题（Label）：高度就是字体行高，不改尺寸，让容器自己排
		return (节点 as Label).get_combined_minimum_size().y
	if 节点 is VBoxContainer:
		var 竖排: VBoxContainer = 节点
		var 合计: float = 0.0
		var 可见数: int = 0
		for 孙: Node in 竖排.get_children():
			if 孙 is CanvasItem and not (孙 as CanvasItem).visible:
				continue
			合计 += _单块高(孙, 宽)
			可见数 += 1
		合计 += float(竖排.get_theme_constant("separation")) \
			* maxf(float(可见数 - 1), 0.0)
		return 合计
	if 节点 is RichTextLabel:
		var 标签: RichTextLabel = 节点
		# 先把宽度定下来再量高度：RichTextLabel 的 get_content_height() 按当前宽度折行，
		# 只改 custom_minimum_size.x 时它还是按旧宽度（刚建时是 1px）算，高度会虚高很多 ——
		# 以前标题单独占一个节点时，这截虚高就全落在标题和第一条技能之间。
		标签.size = Vector2(宽, 标签.size.y)
		var 高: float = 标签.get_content_height()
		# 连最小高度一起写死：否则容器仍然按旧的（虚高的）最小高度排，空隙还在
		标签.custom_minimum_size = Vector2(宽, 高)
		return 高
	return 0.0


## 清空分块容器：容器本身是 TipBox.tscn 里的常驻节点，不删，只清掉上一轮的行
func _清块容器() -> void:
	_块角色号 = -1
	if 块容器 == null:
		return
	for 子: Node in 块容器.get_children():
		块容器.remove_child(子)
		子.queue_free()
	块容器.visible = false


func 显示内容(内容节点: Control, 图标矩形: Rect2) -> void:
	_取消收起()
	if 内容节点 == null:
		return
	_卸内容()
	_隐藏星数()
	# 自定义内容（卡面预览等）不属于角色说明，恢复默认描边
	_设描边(_默认描边)
	_基缩放 = 1.0
	_让开图标 = false
	内容 = 内容节点
	文本.visible = false
	框.add_child(内容)
	_全忽略(内容)
	_轮次 += 1
	框.visible = true
	_摆(图标矩形)
	_排重摆(图标矩形)


## 卸掉上一次递进来的自定义内容（与文字模式互斥）：框里只留一份内容
func _卸内容() -> void:
	# 短提示（技能 / 状态图标）顶上来时，分块内容先藏起来，别和文字叠在一起
	_块要显示 = false
	if 块容器 != null:
		块容器.visible = false
	if 内容 == null:
		return
	框.remove_child(内容)
	内容.queue_free()
	内容 = null


## 收起说明框：不立刻收，先等 收起缓冲 秒（见常量）。这期间只要又调了显示就直接取消 ——
## 鼠标在卡片 / 头像之间快速移动时会连着来一串「离开 → 进入」，立刻收起再弹出就是闪。
func 收起() -> void:
	if 悬停调试:
		print("[提示] 收起（角色=%d，延后 %.2fs）" % [_说明角色号, 收起缓冲])
	if _收起计时 == null:
		_真正收起()
		return
	_收起计时.start()


## 取消还在排队的收起（新的显示进来了）
func _取消收起() -> void:
	if _收起计时 != null:
		_收起计时.stop()


func _真正收起() -> void:
	_轮次 += 1
	_块要显示 = false
	框.visible = false
	_隐藏星数()


## 此刻是否正显示着
func 可见() -> bool:
	return 框.visible


func _隐藏星数() -> void:
	if 星数标签 != null:
		星数标签.visible = false


## 排一次「下一帧再摆」：同帧多次显示只记最新的图标矩形，回调始终只挂一个。
## 不能按老写法「每次 bind 一个矩形各挂一个回调」—— 引擎判定重复连接时不看 bind 的参数，
## 第二次连接会被直接丢弃（报 already connected），剩下那个绑着旧矩形的回调反而生效，
## 于是框被摆到上一个控件的位置上（快速掠过技能按钮再停到指示物上就会这样）。
func _排重摆(图标矩形: Rect2) -> void:
	_待摆矩形 = 图标矩形
	if _待摆中:
		return
	_待摆中 = true
	get_tree().process_frame.connect(_重摆, CONNECT_ONE_SHOT)


## 下一帧按最新的图标矩形再摆一次：容器的布局一帧后才更新，同步量出来的尺寸不作数
func _重摆() -> void:
	_待摆中 = false
	_摆(_待摆矩形)


## 排一次「下一帧再显示」（同上：只挂一个回调，避免重复连接被丢弃）
func _排沉降() -> void:
	if _沉降中:
		return
	_沉降中 = true
	get_tree().process_frame.connect(_沉降显示, CONNECT_ONE_SHOT)


## 沉降收尾：把框落到算好的折行宽度上并显示，再摆位。
## 框（容器）的尺寸不会跟着「最小尺寸」自己涨 —— Godot 只保证 size ≥ 最小尺寸，
## 所以这里要显式 reset_size 定回来（子标签此刻已按这一档宽度折行完毕）
func _沉降显示() -> void:
	_沉降中 = false
	if not is_inside_tree() or _沉降轮次 != _轮次:
		return
	框.reset_size()
	框.visible = true
	_摆(_待摆矩形)
	_排重摆(_待摆矩形)


## 角色说明的折行档宽：从基准宽一档一档往上加，直到「按这一档宽折行后的整框高 ≤ 可用高 × 阈值比例」
## 或到宽度上限。
## 高度必须同步量：把标签挪到这一档宽度后立刻读 get_content_height() —— RichTextLabel 的 fit_content
## 高度跟着它当前宽度即时重排，不用等帧。等帧再量量到的是**上一次布局**的宽度（上次若是一行指示物提示，
## 宽度很小，长文本会被误判成放不下、一路加宽到上限；上次若是别的角色说明，又停到另一档）——
## 同一份说明每次弹出来的宽窄都不一样，就是这么来的
func _算角色说明宽度() -> float:
	var 主: Control = 宿主()
	var 上限: float = 主.size.x * 最大宽比例
	var 可用高: float = (主.size.y - 24.0) * 高度阈值比例
	# 框比标签多出来的竖直部分（内边距 / 边框），换算整框高要用
	var 边距: float = 框.get_theme_stylebox("panel").get_minimum_size().y
	# 一档一档试：基准宽、基准宽 + 步长 …… 直到宽度上限（档数有限，不会卡住）
	var 档数: int = maxi(int(ceil((上限 - 角色说明宽度) / 加宽步长)), 0)
	for i: int in range(档数 + 1):
		var 宽: float = minf(角色说明宽度 + 加宽步长 * float(i), 上限)
		文本.custom_minimum_size.x = 宽
		文本.size = Vector2(宽, 文本.size.y)
		if (float(文本.get_content_height()) + 边距) * _基缩放 <= 可用高:
			return 宽
	文本.custom_minimum_size.x = 上限
	return 上限


## 宿主控件：框挂在它下面，坐标 / 缩放 / 可用范围都按它算
func 宿主() -> Control:
	return get_parent() as Control


## 摆在图标正上方并夹在宿主内，位置按「宿主的本地坐标」算：
## 战斗根节点是 1280×720 再缩放 1.5 适配 1920×1080，拿视图坐标当本地坐标会偏 1.5 倍。
## 传进来的是图标自己的矩形（不是左上角一个点）：翻到下方时要从图标的**底边**接着摆，
## 不然框会压在图标身上（头像旁那排状态图标只有 36×36，正是靠这条让开）
func _摆(图标矩形: Rect2) -> void:
	if not 框.visible or not is_inside_tree():
		return
	# 摆之前再过一遍：卡面预览之类的内容节点可能在挂进来之后才建子节点，
	# 这里兜住所有后来者，保证整块提示始终不吃鼠标
	_全忽略(框)
	var 主: Control = 宿主()
	# 换成更短的说明时 size 不会自己缩：Godot 只保证 size ≥ 最小尺寸，最小尺寸变小它不动。
	# 先按当前内容重置回最小尺寸，再量 —— 否则先看过（高的）角色说明，再指技能，框会一直那么大。
	框.reset_size()
	# 框按内容定大小：先按基准缩放；整框还是塞不进宿主，就再等比缩小兜底 ——
	# 缩的是整框（底板、内边距、字号一起缩），所以内容永远是「全都在」，不会切掉半截。
	var 未缩: Vector2 = 框.get_combined_minimum_size()
	var 缩放: float = _基缩放
	if 未缩.x > 1.0 and 未缩.y > 1.0:
		缩放 = minf(缩放, minf((主.size.x - 16.0) / 未缩.x, (主.size.y - 16.0) / 未缩.y))
	框.scale = Vector2.ONE * 缩放
	var 尺寸: Vector2 = 未缩 * 缩放
	var 变换: Transform2D = 主.get_global_transform().affine_inverse()
	var 左上: Vector2 = 变换 * 图标矩形.position
	var 图: Rect2 = Rect2(左上, 变换 * 图标矩形.end - 左上)
	var 左: float = 8.0
	var 上: float = 8.0
	var 右: float = maxf(主.size.x - 尺寸.x - 8.0, 左)
	var 下: float = maxf(主.size.y - 尺寸.y - 8.0, 上)
	var 位置: Vector2 = Vector2(图.position.x, 图.position.y - 尺寸.y - 10.0)
	# 上方塞不下、而下方放得下时就翻到图标下方（接着图标底边摆，不压住图标）——
	# 否则框会被顶到画面顶边，看着像出了界
	if 位置.y < 上 and 图.end.y + 10.0 <= 下:
		位置.y = 图.end.y + 10.0
	位置.x = clampf(位置.x, 左, 右)
	位置.y = clampf(位置.y, 上, 下)
	# 角色说明很高时，上方 / 下方都塞不下，会被夹到和头像同一行。
	# 这时横向让到图标一侧，别盖住正被查看的头像：优先摆到空间更大的一侧
	# （右侧头像自然落到左边，左侧头像落到右边）。技能按钮 / 状态图标 / 卡面预览不参与。
	if _让开图标 and Rect2(位置, 尺寸).intersects(图):
		var 左空: float = 图.position.x - 左
		var 右空: float = 主.size.x - 图.end.x - 8.0
		if 左空 >= 右空:
			位置.x = 图.position.x - 尺寸.x - 10.0
		else:
			位置.x = 图.end.x + 10.0
		位置.x = clampf(位置.x, 左, 右)
	框.position = 位置

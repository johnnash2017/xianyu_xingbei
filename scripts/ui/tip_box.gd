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

## 角色说明的默认排版（战斗 / 选角共用；宽度 / 字号改这里，整体大小走设置窗的「技能说明尺寸」）
const 角色说明宽度: float = 684.0
const 角色说明字号: int = 16
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
## 行距减半用的「压到多紧」：默认那截空隙本来就是 0 时（间距全来自字体行高），
## 往回压这么多像素，保证「减半」看得出效果。
const 行距下限: int = -3


## 深色圆角底板（结构在 TipBox.tscn 里，可所见即所得地改）
@export var 框: PanelContainer
## 底板里的富文本（【类型】要上色，普通 Label 会把颜色码原样显示出来）
@export var 文本: RichTextLabel
## 右上角星数（角色说明才显示；单独一个 Label 叠在富文本上，免得和角色名抢同一行）
@export var 星数标签: Label
## 自定义内容节点（如一张完整的卡牌视图，见 显示内容）；非空时文字隐藏，整框改按它的尺寸走
var 内容: Control = null
## 分块模式的容器（技能表配了「专属卡牌」的角色说明才用；见 显示角色说明）
var 块容器: VBoxContainer = null
## 分块模式当前显示的是哪个角色（-1＝没有）：同一个角色重复悬停时不重建，避免框闪
var _块角色号: int = -1
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


## 行距：RichTextLabel 在字体行高之外还会加一截空隙（行间 / 段落间各一份），折半，别显得松散。
## 主题里的原值只有引擎知道，得运行期读出来再覆盖，故放在 _ready
func _ready() -> void:
	# 提示框只是「看」的：整框不吃鼠标事件。
	# 否则框盖到被悬停的头像 / 技能按钮上时，鼠标一挪进去就把下面的控件判成「离开」，
	# 悬停说明被收起、鼠标又回到头像上重新弹出 —— 表现为框疯狂闪（分块说明更高，更容易碰到）
	框.mouse_filter = Control.MOUSE_FILTER_IGNORE
	文本.add_theme_constant_override("line_separation",
		_折半行距(文本.get_theme_constant("line_separation")))
	文本.add_theme_constant_override("paragraph_separation",
		_折半行距(文本.get_theme_constant("paragraph_separation")))
	# 默认描边以场景里的底板为准（换了 TipBox.tscn 不用再来改这份代码）
	var 底板: StyleBoxFlat = _底板样式()
	if 底板 != null:
		_默认描边 = 底板.border_color
		_默认描边宽 = maxi(底板.border_width_left, 1)


## 底板样式（PanelContainer 的 panel）；不是 StyleBoxFlat（换成九宫格贴图）时返回 null
func _底板样式() -> StyleBoxFlat:
	return 框.get_theme_stylebox("panel") as StyleBoxFlat


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
	if 说明.is_empty():
		return
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
## 对局中=true 时（只有战斗内头像悬停传）才按场上有没有剑之魔女动态改剑之子的技能说明。
func 显示角色说明(角色号: int, 图标矩形: Rect2, 对局中: bool = false) -> void:
	# 技能表里配了「专属卡牌」的角色：按块显示，专属卡牌相同的技能收进一个同色边框的子框
	var 块: Array = 角色技能提示.悬浮提示块(角色号, 角色说明字号缩放, 对局中)
	if not 块.is_empty():
		# 同一个角色重复触发悬停（鼠标在头像上轻移会反复 emit）：只重摆，不重建 ——
		# 重建会先隐藏框、下一帧再显示，看起来就是「整个悬停提示在闪」
		if _块角色号 == 角色号 and 块容器 != null:
			框.visible = true
			_排重摆(图标矩形)
			return
		_显示角色说明块(块, 图标矩形, 角色号)
	else:
		显示(角色技能提示.悬浮提示(角色号, 角色说明字号缩放, 对局中), 图标矩形,
			角色说明宽度, 角色说明字号, 档位到缩放(当前角色说明缩放档()), true, true)
	# 描边按命格换色（血红 / 咏橙 / 技绿 / 圣蓝 / 幻紫）；没配命格就保持默认描边
	var 描边: Color = 角色技能提示.描边颜色(角色号)
	_设描边(描边 if 描边.a > 0.0 else _默认描边, 角色说明描边宽 if 描边.a > 0.0 else -1)
	if 星数标签 != null:
		var 星数: String = 角色技能提示.星数文本(角色号)
		星数标签.text = 星数
		星数标签.visible = 星数 != ""


## 分块模式：一块一块富文本竖着排；分组块套一个和整框同色的小面板（标题＝专属卡牌名）。
## 布局（宽度档位 / 摆放 / 等比缩小兜底）沿用整段模式那一套，只是量高度改成量各块之和。
func _显示角色说明块(块: Array, 图标矩形: Rect2, 角色号: int) -> void:
	_卸内容()
	_隐藏星数()
	_基缩放 = 档位到缩放(当前角色说明缩放档())
	_让开图标 = true
	文本.visible = false
	块容器 = VBoxContainer.new()
	块容器.add_theme_constant_override("separation", 6)
	框.add_child(块容器)
	var 描边: Color = 角色技能提示.描边颜色(角色号)
	if 描边.a <= 0.0:
		描边 = _默认描边
	# 标题字号：比正文大一档、比「普通技 / 专属技」小一档（原来的 0.5 太小，取 0.75 折中）
	var 标题号: int = maxi(1, int(round(float(角色技能提示.提示框标题字号) * 角色说明字号缩放 * 0.75)))
	# 子框整体缩进两下（对齐正文的「　　」缩进），用左边距做，不靠空格
	var 缩进: int = int(round(float(角色说明字号) * 2.0))
	for 项: Variant in 块:
		var d: Dictionary = 项
		if bool(d.get("分组", false)):
			var 边距容器: MarginContainer = MarginContainer.new()
			边距容器.mouse_filter = Control.MOUSE_FILTER_IGNORE
			边距容器.add_theme_constant_override("margin_left", 缩进)
			var 面板: PanelContainer = PanelContainer.new()
			面板.mouse_filter = Control.MOUSE_FILTER_IGNORE
			面板.add_theme_stylebox_override("panel", _分组框样式(描边))
			var 竖排: VBoxContainer = VBoxContainer.new()
			竖排.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 标题和内容之间不留空隙
			竖排.add_theme_constant_override("separation", 0)
			var 标题标签: RichTextLabel = _新块标签()
			# 标题行不留行距 / 段距：否则标题和下面第一条技能之间会多出一截空隙
			标题标签.add_theme_constant_override("line_separation", 0)
			标题标签.add_theme_constant_override("paragraph_separation", 0)
			标题标签.text = "[font_size=%d]%s[/font_size]" % [
				标题号, str(d.get("标题", ""))]
			竖排.add_child(标题标签)
			var 正文标签: RichTextLabel = _新块标签()
			# 正文首行也不留段距，紧贴标题
			正文标签.add_theme_constant_override("paragraph_separation", 0)
			正文标签.text = str(d.get("文本", ""))
			竖排.add_child(正文标签)
			面板.add_child(竖排)
			边距容器.add_child(面板)
			块容器.add_child(边距容器)
		else:
			var 标签: RichTextLabel = _新块标签()
			标签.text = str(d.get("文本", ""))
			块容器.add_child(标签)
	var 宽: float = _算块宽度()
	块容器.custom_minimum_size.x = 宽
	_块角色号 = 角色号
	_轮次 += 1
	_待摆矩形 = 图标矩形
	# 直接显示再补摆：原来先隐藏、等下一帧沉降再显示 —— 沉降回调只要被打断（比如上一轮收起），
	# 框就一直藏着，要等鼠标再动一次才出来。这里先按当前尺寸摆一次，下一帧再补一次准确位置。
	框.visible = true
	框.reset_size()
	_摆(图标矩形)
	_排重摆(图标矩形)


## 分块模式用的富文本标签（样式与整段模式里的 文本 一致：字号 / 行距 / 自动换行）
func _新块标签() -> RichTextLabel:
	var 标签: RichTextLabel = RichTextLabel.new()
	标签.bbcode_enabled = true
	标签.fit_content = true
	标签.scroll_active = false
	标签.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	标签.mouse_filter = Control.MOUSE_FILTER_IGNORE
	标签.add_theme_font_size_override("normal_font_size", 角色说明字号)
	标签.add_theme_constant_override("line_separation",
		_折半行距(标签.get_theme_constant("line_separation")))
	标签.add_theme_constant_override("paragraph_separation",
		_折半行距(标签.get_theme_constant("paragraph_separation")))
	return 标签


## 分组子框的样式：和整框同样的圆角描边，颜色用整框的描边色（命格色），底子稍微提亮一点
func _分组框样式(描边: Color) -> StyleBoxFlat:
	var 样式: StyleBoxFlat = StyleBoxFlat.new()
	样式.bg_color = Color(0.06, 0.07, 0.1, 0.55)
	样式.set_border_width_all(2)
	样式.border_color = 描边
	样式.set_corner_radius_all(6)
	样式.content_margin_left = 8.0
	样式.content_margin_right = 8.0
	样式.content_margin_top = 4.0
	样式.content_margin_bottom = 6.0
	return 样式


## 分块模式按哪个宽度折行：与 算角色说明宽度 同一套「一档档加宽，直到整框高够用」
func _算块宽度() -> float:
	if 块容器 == null:
		return 角色说明宽度
	var 主: Control = 宿主()
	var 上限: float = 主.size.x * 最大宽比例
	var 可用高: float = (主.size.y - 24.0) * 高度阈值比例
	var 边距: float = 框.get_theme_stylebox("panel").get_minimum_size().y
	var 档数: int = maxi(int(ceil((上限 - 角色说明宽度) / 加宽步长)), 0)
	for i: int in range(档数 + 1):
		var 宽: float = minf(角色说明宽度 + 加宽步长 * float(i), 上限)
		if (_块总高(宽) + 边距) * _基缩放 <= 可用高:
			return 宽
	return 上限


## 这一档宽度下所有块加起来有多高（同步量：RichTextLabel 换宽后 get_content_height 立刻更新）
func _块总高(宽: float) -> float:
	if 块容器 == null:
		return 0.0
	var 总: float = 0.0
	var 子们: Array = 块容器.get_children()
	for 子: Node in 子们:
		总 += _单块高(子, 宽)
	总 += 6.0 * maxf(float(子们.size() - 1), 0.0)
	return 总


## 单个块在「宽」这一档下的高度：普通富文本＝内容高；分组块＝面板样式内边距 + 标题/正文高；
## 外面套了「缩进两下」的边距容器时，先把左右边距扣掉
func _单块高(节点: Node, 宽: float) -> float:
	if 节点 is MarginContainer:
		var 边距: MarginContainer = 节点
		var 扣: float = float(边距.get_theme_constant("margin_left")) \
			+ float(边距.get_theme_constant("margin_right"))
		var 内高: float = 0.0
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
	if 节点 is VBoxContainer:
		var 竖排: VBoxContainer = 节点
		var 合计: float = 0.0
		for 孙: Node in 竖排.get_children():
			合计 += _单块高(孙, 宽)
		合计 += float(竖排.get_theme_constant("separation")) \
			* maxf(float(竖排.get_child_count() - 1), 0.0)
		return 合计
	if 节点 is RichTextLabel:
		var 标签: RichTextLabel = 节点
		标签.custom_minimum_size.x = 宽
		return 标签.get_content_height()
	return 0.0


## 显示一段自定义内容（如一张完整的卡牌视图）：内容节点由调用方造好递进来，
## 摆位 / 反翻 / 夹边 / 收起这一套与文字提示完全共用 —— 整框按内容自己的尺寸走
func 显示内容(内容节点: Control, 图标矩形: Rect2) -> void:
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
	_轮次 += 1
	框.visible = true
	_摆(图标矩形)
	_排重摆(图标矩形)


## 卸掉上一次递进来的自定义内容（与文字模式互斥）：框里只留一份内容
func _卸内容() -> void:
	_清块容器()
	if 内容 == null:
		return
	框.remove_child(内容)
	内容.queue_free()
	内容 = null


## 卸掉「分块」模式的容器（技能表配了专属卡牌的角色说明才会用到）
func _清块容器() -> void:
	if 块容器 == null:
		return
	框.remove_child(块容器)
	块容器.queue_free()
	块容器 = null
	_块角色号 = -1


## 收起说明框（状态一变就不该再挂着）
func 收起() -> void:
	_轮次 += 1
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


## 把一段现有行距折半；现有值是 0（没额外空隙）就退到下限
func _折半行距(原值: int) -> int:
	if 原值 == 0:
		return 行距下限
	return int(round(float(原值) * 0.5))


## 摆在图标正上方并夹在宿主内，位置按「宿主的本地坐标」算：
## 战斗根节点是 1280×720 再缩放 1.5 适配 1920×1080，拿视图坐标当本地坐标会偏 1.5 倍。
## 传进来的是图标自己的矩形（不是左上角一个点）：翻到下方时要从图标的**底边**接着摆，
## 不然框会压在图标身上（头像旁那排状态图标只有 36×36，正是靠这条让开）
func _摆(图标矩形: Rect2) -> void:
	if not 框.visible or not is_inside_tree():
		return
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

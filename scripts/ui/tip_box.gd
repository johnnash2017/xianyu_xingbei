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

## 角色说明的默认排版（战斗 / 选角共用；要整体调档改这里）
const 角色说明宽度: float = 684.0
const 角色说明字号: int = 16
## 文字整块再压到 90%（角色名 36→32、标题 27→24、正文 18→16）
const 角色说明字号缩放: float = 0.9
## 整块再缩（连底板、内边距、边框一起变档，靠节点整体缩放实现）：
## 原来 5%、再缩 10% → 0.95 × 0.9 = 0.855；之后整体放大 20% → 0.855 × 1.2 = 1.026
const 角色说明整体缩放: float = 1.026
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
## 自定义内容节点（如一张完整的卡牌视图，见 显示内容）；非空时文字隐藏，整框改按它的尺寸走
var 内容: Control = null
## 本次说明的「基准整体缩放」（角色说明 0.855）。摆框时若按它仍塞不进宿主，会在它基础上再等比缩小兜底
var _基缩放: float = 1.0
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


## 行距：RichTextLabel 在字体行高之外还会加一截空隙（行间 / 段落间各一份），折半，别显得松散。
## 主题里的原值只有引擎知道，得运行期读出来再覆盖，故放在 _ready
func _ready() -> void:
	文本.add_theme_constant_override("line_separation",
		_折半行距(文本.get_theme_constant("line_separation")))
	文本.add_theme_constant_override("paragraph_separation",
		_折半行距(文本.get_theme_constant("paragraph_separation")))


## 显示一段说明：图标矩形取「视图坐标」，框摆在它正上方并夹在宿主内。
## 宽度 > 0：按这个宽度折行（角色 / 技能说明）；宽度 ≤ 0：不折行，整框按内容自适应
## （指示物那种一行短提示，不该为了填满固定宽度把底板撑大）
func 显示(说明: String, 图标矩形: Rect2, 宽度: float, 字号: int, 整体缩放: float = 1.0, 可拓宽: bool = false) -> void:
	if 说明.is_empty():
		return
	_卸内容()
	_基缩放 = 整体缩放
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


## 显示角色说明（角色名一行 + 技能说明，含 BBCode）——战斗 / 选角同款
func 显示角色说明(角色号: int, 图标矩形: Rect2) -> void:
	显示(角色技能提示.悬浮提示(角色号, 角色说明字号缩放), 图标矩形,
		角色说明宽度, 角色说明字号, 角色说明整体缩放, true)


## 显示一段自定义内容（如一张完整的卡牌视图）：内容节点由调用方造好递进来，
## 摆位 / 反翻 / 夹边 / 收起这一套与文字提示完全共用 —— 整框按内容自己的尺寸走
func 显示内容(内容节点: Control, 图标矩形: Rect2) -> void:
	if 内容节点 == null:
		return
	_卸内容()
	_基缩放 = 1.0
	内容 = 内容节点
	文本.visible = false
	框.add_child(内容)
	_轮次 += 1
	框.visible = true
	_摆(图标矩形)
	_排重摆(图标矩形)


## 卸掉上一次递进来的自定义内容（与文字模式互斥）：框里只留一份内容
func _卸内容() -> void:
	if 内容 == null:
		return
	框.remove_child(内容)
	内容.queue_free()
	内容 = null


## 收起说明框（状态一变就不该再挂着）
func 收起() -> void:
	_轮次 += 1
	框.visible = false


## 此刻是否正显示着
func 可见() -> bool:
	return 框.visible


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
	框.position = 位置

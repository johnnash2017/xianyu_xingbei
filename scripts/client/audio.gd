extends Node
## 音频（autoload 名：Audio）
## 只搬参考项目（D:\星杯传说工程\星杯传说）的音乐与战斗音效 —— assets/media/audio 下的 ogg：
##   * 主界面音乐 lobby、战斗音乐 battle1~6（随机且不与上一首重复）、胜负 win/lose
##   * 出牌 atk-<系别> / spell-<卡名>、命中 sys-hit（攻击 / 魔弹命中）、受伤 sys-hurt（法术 / 技能伤害）、
##     治疗 sys-heal、士气 sys-morale、宝石水晶 sys-energy、选将 sys-turn
##   * 角色语音 <角色id>（1~36、76）：轮到该角色回合时播他自己的那条
##   * 给牌（交牌动效配的那声，见 battle_mobile._给牌特效）：暂时拿参考工程的 draw.mp3 顶着，
##     换成正式音效时把 assets/media/audio/dealCard.ogg / dealCard.wav 放进去即可（找文件的顺序是 ogg → wav → mp3）
## 对照脚本：参考项目 scripts/game/AudioManager.gd
## 说明：界面上的 wav 音效（按钮点击 Equip）沿用 Art.play_sfx，
##      因为参考项目没有这些界面音（它的音频只有这张 ogg 表）。
## 多开时只有当前在用的那个窗口出声：窗口失焦就把声音压到听不见，回到前台再恢复。
## 「在不在后台」每 0.2 秒轮询一次（正式单窗口看窗口焦点；多开窗口上窗口焦点信号不可靠，
## 改看鼠标落点 / 输入去向，见 _随焦点切声音）。
## 这条「切出游戏就静音」是默认行为，设置窗里可以改成「后台播放」（后台照常出声，见 后台静音）。
## 用「音量置 0」而不是「禁音（bus_mute）」或「不播」：音频流水线照常走，切回前台时
## 本该在播的声音（BGM / 长音效）会接着放，不会因为后台期间被丢掉而断裂。

const 音频目录: String = "res://assets/media/audio/"
## 音量（线性 0~1）：默认值与参考项目 PlayerPrefs 里 BGM / SE 的默认值一致；
## 启动时从本地配置读回上次调的值，设置窗里可随时改（见 设置音乐音量 / 设置音效音量）
const 默认音乐音量: float = 0.5
const 默认音效音量: float = 0.5
## 总音量（整条 Master 总线，BGM 与音效一起受影响）：1 = 不衰减，保持改造前的听感
const 默认总音量: float = 1.0
## 本地配置键名（存在 Cfg 那份 config[_N].cfg 的 [设置] 段）
const 键_音乐音量: String = "bgm_volume"
const 键_音效音量: String = "se_volume"
const 键_总音量: String = "master_volume"
const 键_后台静音: String = "mute_in_background"
var 总音量: float = 默认总音量
var 音乐音量: float = 默认音乐音量
var 音效音量: float = 默认音效音量
## 切出游戏（窗口失焦 / 最小化）时是否静音：true＝把声音压到听不见（默认；多开时几个窗口里
## 只有当前在用的那个出声），false＝「后台播放」，切到后台也照常出声。
## 由设置窗里「后台静音 / 后台播放」这个二选一改（见 设置后台静音）
var 后台静音: bool = true
## 场景号（对照参考项目 GameManager 的 current_scene_index）
const 场景主界面: int = 1
const 场景战斗: int = 2
## 焦点轮询间隔（秒）：太短白忙，太长会让切窗口后声音慢半拍
const 焦点轮询间隔: float = 0.2
## 失焦时的音量（dB）：够低就是听不见，但不打断播放
const 失焦音量db: float = -80.0

var _bgm: AudioStreamPlayer = null
## 当前在播的场景号与胜负状态（胜负 null = 常规背景乐）：一首放完时据此决定接哪一首
var _当前场景: int = -1
var _当前胜负: Variant = null
var _音效池: Array[AudioStreamPlayer] = []
var _缓存: Dictionary = {}
## 上一首战斗曲编号：随机时避开它，避免连续两局同一首
var _上一首战斗: int = -1
var _随机: RandomNumberGenerator = RandomNumberGenerator.new()
## 此刻是否静音：窗口失焦（且设置里选的是「后台静音」）时为 true，回到前台再恢复
var _静音: bool = false
## 本进程启动之后，窗口有没有**真的**拿到过焦点。
## 为什么需要它：多开时被别的软件占着前台的那些窗口，从启动起就没被激活过，而 Godot 对
## 「从没激活过的窗口」仍然回报 window_is_focused() = true（默认值就是「有焦点」）——
## 只看这个接口就会以为它一直在前台，永远不会静音（需求方报的现象：
## 窗口弹出来但我在用别的软件，选了「后台静音」它们却照样出声）。
## 所以多开模式下「从启动起没拿到过焦点」一律按后台处理，见 _随焦点切声音。
var _拿过焦点: bool = false
## 最近一次焦点通知是「失去焦点」：有的平台 window_is_focused() 更新慢半拍，
## 通知说已经失焦就先按失焦算；拿到焦点时清掉
var _刚失焦: bool = false
## 最后一次收到输入事件（键盘 / 鼠标 / 触摸）的时刻：多开窗口上「鼠标在不在窗口里」之外的第二个证据
var _最后输入时刻: float = -100.0
## 临时诊断（多开模式才写）：把焦点判定的输入与结果记进 user://声音焦点_<槽位>.txt，
## 用来定位「多开窗口后台不静音」到底是哪个判据不对。查完这一段可以整块删。
const 焦点诊断: bool = true
var _焦点进入次数: int = 0
var _焦点离开次数: int = 0
var _上次诊断文本: String = ""
var _上次诊断时刻: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 焦点兜底要看「有没有真的在操作这个窗口」（见 _input）：显式打开输入处理，不靠编辑器自动推断
	set_process_input(true)
	_随机.randomize()
	# 读回上次在设置窗里调好的音量与「后台静音」（没存过就用默认值）
	总音量 = clampf(float(Cfg.get_setting(键_总音量, 默认总音量)), 0.0, 1.0)
	音乐音量 = clampf(float(Cfg.get_setting(键_音乐音量, 默认音乐音量)), 0.0, 1.0)
	音效音量 = clampf(float(Cfg.get_setting(键_音效音量, 默认音效音量)), 0.0, 1.0)
	后台静音 = bool(Cfg.get_setting(键_后台静音, 后台静音))
	_应用总音量()
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "BGM"
	_bgm.volume_db = linear_to_db(音乐音量)
	_bgm.finished.connect(_on_bgm_finished)
	add_child(_bgm)
	# 多开时几个窗口各自是独立进程，只有当前聚焦的那个出声；定时问窗口自己有没有焦点
	var 轮询: Timer = Timer.new()
	轮询.wait_time = 焦点轮询间隔
	轮询.autostart = true
	轮询.timeout.connect(_随焦点切声音)
	add_child(轮询)
	_随焦点切声音()


## 只有当前在用的那个窗口出声（设置成「后台播放」时不静音，切出去照常出声）。
## 每 焦点轮询间隔（0.2 秒）由 Timer 调一次；收到焦点通知时也立刻调一次。
## 「在后台」怎么判：
##   · 最小化 → 后台（window_is_focused() 在部分平台这时还报 true，所以单独问 window_get_mode）；
##   · 多开窗口 → 看「鼠标落点 + 最近输入」：实测这类窗口上 window_is_focused() 会四个窗口同时报
##     「有焦点」、焦点通知也收不到失焦，只有鼠标 / 键盘是真的只落在正在用的那个窗口上；
##   · 正式单窗口 → 照旧看窗口焦点（简单、够用）。
## headless（自检）没有窗口与音频输出，不做焦点静音。
func _随焦点切声音() -> void:
	if DisplayServer.get_name() == "headless":
		_切声音(false)
		return
	var 最小化: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	var 在前台: bool = false
	if not 最小化:
		if Cfg.本地模式:
			# 多开测试窗口上 window_is_focused() / 焦点通知都不可靠（实测四个窗口会同时「有焦点」、
			# 也收不到失焦通知），改用「鼠标在不在这块窗口里」＋「最近 1.5 秒有没有输入到它」——
			# 鼠标与键盘只会落在真正在用的那个窗口上，这才是实打实的「我在用它」。
			在前台 = _鼠标在窗口内() or Time.get_ticks_msec() / 1000.0 - _最后输入时刻 < 1.5
		else:
			# 正式单窗口：照旧用窗口焦点
			在前台 = not _刚失焦 and bool(DisplayServer.window_is_focused())
	_切声音(后台静音 and not 在前台)
	_写焦点诊断(最小化, 在前台)


## 焦点通知：拿到焦点的这一刻就记下来（此后 window_is_focused() 才可信），并立刻重算一次。
## 有些平台启动时不给「获得焦点」通知，所以 _input 里也补一刀（能收到输入就说明有焦点）。
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_焦点进入次数 += 1
			_拿过焦点 = true
			_刚失焦 = false
			_随焦点切声音()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_焦点离开次数 += 1
			_刚失焦 = true
			_随焦点切声音()


## 兜底「启动时不发获得焦点通知」的平台：只认键盘 / 鼠标按键 / 触摸这类**真的在操作**的事件。
## 不能用鼠标移动 —— 未激活的窗口在鼠标划过时也会收到 Motion 事件，那不能证明它有焦点。
func _input(event: InputEvent) -> void:
	# 输入只送到前台窗口：收到就说明这一手是打给它的（多开判后台时当第二证据用）
	_最后输入时刻 = Time.get_ticks_msec() / 1000.0
	if _拿过焦点:
		return
	if not (event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventScreenTouch):
		return
	_拿过焦点 = true
	_刚失焦 = false
	_随焦点切声音()


## 临时诊断：状态有变化、或每 2 秒，往 user://声音焦点_<槽位>.txt 覆盖写一份最近 40 行。
## 只在多开模式（Cfg.本地模式）写，正式玩家不留文件。
func _写焦点诊断(最小化: bool, 在前台: bool) -> void:
	if not 焦点诊断 or not Cfg.本地模式:
		return
	var 现在: float = Time.get_ticks_msec() / 1000.0
	var 文本: String = "%s 槽%d 焦点=%s 最小化=%s 鼠标在内=%s 输入距今=%.1fs 拿过焦点=%s 刚失焦=%s 进入=%d 离开=%d 后台静音=%s 静音=%s master=%.1fdB 前台=%s 窗口=%s 鼠标=%s" % [
		Time.get_time_string_from_system(), Cfg.slot,
		str(DisplayServer.window_is_focused()), str(最小化), str(_鼠标在窗口内()),
		Time.get_ticks_msec() / 1000.0 - _最后输入时刻,
		str(_拿过焦点), str(_刚失焦),
		_焦点进入次数, _焦点离开次数, str(后台静音), str(_静音),
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), str(在前台),
		str(DisplayServer.window_get_position()), str(DisplayServer.mouse_get_position())]
	if 文本 == _上次诊断文本 and 现在 - _上次诊断时刻 < 2.0:
		return
	_上次诊断文本 = 文本
	_上次诊断时刻 = 现在
	var 路径: String = "user://声音焦点_%d.txt" % Cfg.slot
	var 旧: String = FileAccess.get_file_as_string(路径) if FileAccess.file_exists(路径) else ""
	var 行: PackedStringArray = 旧.split("\n", false)
	行.append(文本)
	while 行.size() > 40:
		行.remove_at(0)
	var f: FileAccess = FileAccess.open(路径, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(行))
		f.close()


## 鼠标此刻在不在这个窗口的矩形里（多开判「我在用哪一块」的主要证据）。
## window_get_position 给的是客户区左上角，所以把标题栏那一条也算进来，别让鼠标停在标题栏被判成外面。
func _鼠标在窗口内() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var 位置: Vector2i = DisplayServer.window_get_position()
	var 尺寸: Vector2i = DisplayServer.window_get_size()
	var 矩形: Rect2i = Rect2i(位置 - Vector2i(0, 48), 尺寸 + Vector2i(0, 48))
	return 矩形.has_point(DisplayServer.mouse_get_position())


## 失焦就把声音压到听不见（BGM 与音效，含 Art.play_sfx 的界面 wav）；回到前台恢复。
## 注意不要用 bus_mute，也不要在这里跳过播放：这里只改音量，播放流水线不动。
func _切声音(静音: bool) -> void:
	if 静音 == _静音:
		return
	_静音 = 静音
	_应用总音量()


## 把总音量落到 Master 总线上（BGM 与音效一起走这条总线）。
## 失焦时压到听不见；拉到 0 也用同一档，别让 linear_to_db(0) 的 -inf 进总线。
func _应用总音量() -> void:
	var db: float = 失焦音量db if _静音 or 总音量 <= 0.0 else linear_to_db(总音量)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)


## 当前是否静音（联机测试与自检用来核对）
func 是否静音() -> bool:
	return _静音


# ============================================================
# 音效
# ============================================================
## 播放一次音效；名字对应 assets/media/audio 下的文件名（不带扩展名），如 "sys-hit" / "spell-holyLight"
## 失焦时照常播放（总线音量已被压到听不见），这样切回前台时还在响的会接着响
func 播音效(名字: String, 音量: float = 1.0) -> void:
	var 流: AudioStream = _取音频(名字)
	if 流 == null:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = 流
	p.volume_db = linear_to_db(音效音量 * 音量)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	_音效池.append(p)


## 是否存在该音效（角色语音等并非每个角色都有，调用前先问一下）
func 有声效(名字: String) -> bool:
	return _取音频(名字) != null


# ============================================================
# 音量与「后台静音」（设置窗调用）
# ============================================================
## 调总音量（0~1）：立即生效；拖动中只改内存，落盘统一在 保存声音设置
func 设置总音量(v: float) -> void:
	总音量 = clampf(v, 0.0, 1.0)
	_应用总音量()


## 调背景音乐音量（0~1）：立即生效；拖动中只改内存，落盘统一在 保存声音设置
func 设置音乐音量(v: float) -> void:
	音乐音量 = clampf(v, 0.0, 1.0)
	if _bgm != null:
		_bgm.volume_db = linear_to_db(音乐音量)


## 调效果音音量（0~1）：立即生效；拖动中只改内存，落盘统一在 保存声音设置
func 设置音效音量(v: float) -> void:
	音效音量 = clampf(v, 0.0, 1.0)


## 「后台静音 / 后台播放」二选一（true＝后台静音）：立即生效 —— 立刻按新设置重算一次
## 「这会儿该不该静音」；勾选过程只改内存，落盘统一在 保存声音设置
func 设置后台静音(v: bool) -> void:
	后台静音 = v
	_随焦点切声音()


## 把当前的音量与「后台静音」写进本地配置（设置窗收起时调一次，避免拖动过程频繁写盘）
func 保存声音设置() -> void:
	Cfg.set_setting(键_总音量, 总音量)
	Cfg.set_setting(键_音乐音量, 音乐音量)
	Cfg.set_setting(键_音效音量, 音效音量)
	Cfg.set_setting(键_后台静音, 后台静音)


# ============================================================
# 音乐
# ============================================================
## 播放场景音乐：主界面固定 lobby；战斗随机 battle1~6；胜负传 true/false 播 win / lose
## 同一首曲子已在播时不重头开始（对照参考项目 play_bgm_scene）
func 播放音乐(场景号: int, 胜负: Variant = null) -> void:
	if _bgm == null:
		return
	_当前场景 = 场景号
	_当前胜负 = 胜负
	if 场景号 == 场景战斗:
		if 胜负 != null:
			var 胜曲: AudioStream = _取音频("win" if 胜负 else "lose")
			if 胜曲 != null and _bgm.stream != 胜曲:
				_bgm.stream = 胜曲
		else:
			var n: int = _随机.randi_range(1, 6)
			while n == _上一首战斗:
				n = _随机.randi_range(1, 6)
			_上一首战斗 = n
			_bgm.stream = _取音频("battle%d" % n)
		_bgm.play()
	elif 场景号 == 场景主界面:
		_上一首战斗 = -1
		var 厅曲: AudioStream = _取音频("lobby")
		if 厅曲 != null and _bgm.stream != 厅曲:
			_bgm.stream = 厅曲
			_bgm.play()


## 一首背景乐放完：战斗就接着随机下一首（不重复上一首换一首），主界面就把 lobby 重放 ——
## 少了这一步，一首放完音乐就断了（战斗里最明显：曲子放完就整局没声音）
## 胜负曲是一次性结算音，放完不再续
func _on_bgm_finished() -> void:
	if _当前胜负 != null:
		return
	if _当前场景 == 场景战斗:
		播放音乐(场景战斗)
	elif _当前场景 == 场景主界面:
		_bgm.play()


# ============================================================
# 内部
# ============================================================
func _取音频(名字: String) -> AudioStream:
	if _缓存.has(名字):
		return _缓存[名字]
	var 流: AudioStream = null
	for 后缀: String in [".ogg", ".wav", ".mp3"]:
		var 路径: String = 音频目录 + 名字 + 后缀
		if ResourceLoader.exists(路径):
			var 资源: Resource = load(路径)
			if 资源 is AudioStream:
				流 = 资源
			break
	_缓存[名字] = 流
	return 流


## 退出时先停播、再断开对音频流的引用：避免退出时报「资源仍在使用 / 对象泄漏」的噪音（同参考项目）
func _exit_tree() -> void:
	if _bgm != null:
		_bgm.stop()
		_bgm.stream = null
	for p: AudioStreamPlayer in _音效池:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_音效池.clear()
	_缓存.clear()

extends Node
## 音频（autoload 名：Audio）
## 只搬参考项目（D:\星杯传说工程\星杯传说）的音乐与战斗音效 —— 资源/音频 下的 ogg：
##   * 主界面音乐 lobby、战斗音乐 battle1~6（随机且不与上一首重复）、胜负 win/lose
##   * 出牌 atk-<系别> / spell-<卡名>、命中 sys-hit（攻击 / 魔弹命中）、受伤 sys-hurt（法术 / 技能伤害）、
##     治疗 sys-heal、士气 sys-morale、宝石水晶 sys-energy、选将 sys-turn
##   * 角色语音 <角色id>（1~36、108）：轮到该角色回合时播他自己的那条
##   * 给牌（交牌动效配的那声，见 battle_mobile._给牌特效）：暂时拿参考工程的 draw.mp3 顶着，
##     换成正式音效时把 资源/音频/给牌.ogg / 给牌.wav 放进去即可（找文件的顺序是 ogg → wav → mp3）
## 对照脚本：参考项目 scripts/game/AudioManager.gd
## 说明：界面上的 wav 音效（按钮点击 Equip、轮到你 It's your turn、技能 Skill 等）沿用 Art.play_sfx，
##      因为参考项目没有这些界面音（它的音频只有这张 ogg 表）。
## 多开时只有当前在用的那个窗口出声：窗口失焦就把总音量临时压到 0，回到前台再恢复。
## 用「音量置 0」而不是「禁音（bus_mute）」或「不播」：音频流水线照常走，切回前台时
## 本该在播的声音（BGM / 长音效）会接着放，不会因为后台期间被丢掉而断裂。

const 音频目录: String = "res://资源/音频/"
## 音量（线性）：与参考项目 PlayerPrefs 里 BGM / SE 的默认值一致
const 音乐音量: float = 0.5
const 音效音量: float = 0.5
## 场景号（对照参考项目 GameManager 的 current_scene_index）
const 场景主界面: int = 1
const 场景战斗: int = 2
## 焦点轮询间隔（秒）：太短白忙，太长会让切窗口后声音慢半拍
const 焦点轮询间隔: float = 0.2
## 失焦时的总音量（dB）：够低就是听不见，但不打断播放
const 失焦音量db: float = -80.0

var _bgm: AudioStreamPlayer = null
var _音效池: Array[AudioStreamPlayer] = []
var _缓存: Dictionary = {}
## 上一首战斗曲编号：随机时避开它，避免连续两局同一首
var _上一首战斗: int = -1
var _随机: RandomNumberGenerator = RandomNumberGenerator.new()
## 是否静音：窗口失焦时为 true（多开时几个窗口只有当前在用的那个出声）
var _静音: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_随机.randomize()
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "BGM"
	_bgm.volume_db = linear_to_db(音乐音量)
	add_child(_bgm)
	# 多开时几个窗口各自是独立进程，只有当前聚焦的那个出声；定时问窗口自己有没有焦点
	var 轮询: Timer = Timer.new()
	轮询.wait_time = 焦点轮询间隔
	轮询.autostart = true
	轮询.timeout.connect(_随焦点切声音)
	add_child(轮询)
	_随焦点切声音()


## 只有当前聚焦的窗口出声。
## 不用失焦通知：后台启动、从没拿到过焦点的窗口收不到通知，会一直出声。
## headless（自检）没有窗口与音频输出，不做焦点静音。
func _随焦点切声音() -> void:
	_切声音(DisplayServer.get_name() != "headless" and not DisplayServer.window_is_focused())


## 失焦就把总音量临时压到 0（BGM 与音效，含 Art.play_sfx 的界面 wav）；回到前台恢复。
## 注意不要用 bus_mute，也不要在这里跳过播放：这里只改音量，播放流水线不动。
func _切声音(静音: bool) -> void:
	if 静音 == _静音:
		return
	_静音 = 静音
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), 失焦音量db if 静音 else 0.0)


## 当前是否静音（联机测试与自检用来核对）
func 是否静音() -> bool:
	return _静音


# ============================================================
# 音效
# ============================================================
## 播放一次音效；名字对应 资源/音频 下的文件名（不带扩展名），如 "sys-hit" / "spell-圣光"
## 失焦时照常播放（总音量已被压到 0），这样切回前台时还在响的会接着响
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
# 音乐
# ============================================================
## 播放场景音乐：主界面固定 lobby；战斗随机 battle1~6；胜负传 true/false 播 win / lose
## 同一首曲子已在播时不重头开始（对照参考项目 play_bgm_scene）
func 播放音乐(场景号: int, 胜负: Variant = null) -> void:
	if _bgm == null:
		return
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

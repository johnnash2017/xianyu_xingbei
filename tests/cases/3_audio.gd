extends 自检用例
## 用例 3：音频（参考项目的音乐与音效是否都接上）

const 音频目录: String = "res://media/audio/"
## 代码里会播的音频；改接入点时同步维护这里
const 会播: Array[String] = [
	"atk-darkness", "atk-earth", "atk-fire", "atk-thunder", "atk-water", "atk-wind",
	"spell-魔弹", "spell-圣盾", "spell-圣光", "spell-虚弱", "spell-中毒",
	"sys-hit", "sys-hurt", "sys-heal", "sys-morale", "sys-energy", "sys-turn",
	"lobby", "battle1", "battle2", "battle3", "battle4", "battle5", "battle6", "win", "lose",
]


func _init() -> void:
	名称 = "音频"


func 跑() -> void:
	await 等帧()
	var 缺: Array[String] = []
	for 名: String in 会播:
		if not ResourceLoader.exists(音频目录 + 名 + ".ogg"):
			缺.append(名)
	检(缺.is_empty(), "缺音频文件：%s" % str(缺))

	# 角色语音：按角色 id 命名，1~36 与 108 都要在（37 号原工程就没有这条；101/102/103 未接）
	var 缺语音: Array[String] = []
	for rid: int in range(1, 37) + [108]:
		if not ResourceLoader.exists(音频目录 + str(rid) + ".ogg"):
			缺语音.append(str(rid))
	检(缺语音.is_empty(), "缺角色语音：%s" % str(缺语音))
	检(Audio.有声效("1") and Audio.有声效("108"), "角色语音存在性判断不对")
	检(not Audio.有声效("37"), "没有语音的角色被误判为有语音")
	检(not Audio.是否静音(), "自检进程没有失焦，不应处于静音状态")

	# 登录 / 大厅 / 房间等待阶段：都应该还是主界面音乐
	UI.goto_enter()
	await 等帧(2)
	检(_当前曲() == "lobby.ogg", "登录界面音乐不是 lobby：%s" % _当前曲())
	UI.goto_lobby()
	await 等帧(2)
	检(_当前曲() == "lobby.ogg", "大厅音乐不是 lobby：%s" % _当前曲())
	UI.goto_ready_room()
	await 等帧(2)
	检(_当前曲() == "lobby.ogg", "进房间（还没开打）就换音乐了：%s" % _当前曲())

	# 战斗 / 胜负
	Audio.播放音乐(Audio.场景战斗)
	await 等帧()
	检(_当前曲().begins_with("battle"), "战斗音乐不是 battle1~6：%s" % _当前曲())
	Audio.播放音乐(Audio.场景战斗, true)
	await 等帧()
	检(_当前曲() == "win.ogg", "获胜音乐不是 win：%s" % _当前曲())
	Audio.播放音乐(Audio.场景战斗, false)
	await 等帧()
	检(_当前曲() == "lose.ogg", "失败音乐不是 lose：%s" % _当前曲())

	# 音效：播一个应生成一个播放器
	var 之前: int = Audio.get_child_count()
	Audio.播音效("sys-hit")
	await 等帧()
	检(Audio.get_child_count() == 之前 + 1, "播音效没有生成播放器")

	print("[自检] 会用到的音频 %d 个" % 会播.size())


func _当前曲() -> String:
	var bgm: AudioStreamPlayer = Audio.get("_bgm")
	if bgm == null or bgm.stream == null:
		return "<无>"
	return bgm.stream.resource_path.get_file()

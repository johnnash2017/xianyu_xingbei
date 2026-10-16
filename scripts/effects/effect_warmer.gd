extends Node
## 出手特效预热（autoload 名：EffectWarmer）
## 启动游戏时就把各类出手特效的着色器管线一次性编好 —— 管线在首次真正 draw 时才同步编译，
## 机器上还没有对应缓存时（玩家的机器、刚导出的包）最明显，不预热的话第一次放特效那一帧会卡。
##
## 特效预制表也放在这里：战斗界面（battle_mobile.gd）直接引用，避免同一份表两处维护。

## 出手时放专属特效的牌 → 特效预制体（scenes/prefabs/effects/）
## 斩击类（水 / 火 / 地 / 风 / 雷 / 暗灭）是把 3D 斩击素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/slash2D.gd；
## 魔弹同样是把 3D 弹道素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/magicBullet2D.gd；
## 圣光是原生 2D 粒子（GPUParticles2D），见 scripts/effects/particleEffect.gd。
const 特效预制表: Dictionary = {
	GConst.CardName.WaterSlash: preload("res://scenes/prefabs/effects/waterSlash.tscn"),
	GConst.CardName.FireSlash: preload("res://scenes/prefabs/effects/fireSlash.tscn"),
	GConst.CardName.EarthSlash: preload("res://scenes/prefabs/effects/earthSlash.tscn"),
	GConst.CardName.WindSlash: preload("res://scenes/prefabs/effects/windSlash.tscn"),
	GConst.CardName.ThunderSlash: preload("res://scenes/prefabs/effects/thunderSlash.tscn"),
	GConst.CardName.DarkSlash: preload("res://scenes/prefabs/effects/darkAnnihilation.tscn"),
	GConst.CardName.Missile: preload("res://scenes/prefabs/effects/magicBullet.tscn"),
	GConst.CardName.HolyLight: preload("res://scenes/prefabs/effects/holyLight.tscn"),
}


func _ready() -> void:
	_预热()


## 离屏预热：把每种特效各实例化一次，放进一个不显示的 SubViewport 里渲染两帧，
## 让各自的着色器管线一次性编好。视口必须用 UPDATE_ALWAYS：WHEN_VISIBLE 时离屏不渲染，预热就等于白做。
## 预热完立即释放；玩家看不到，因为这个视口从不显示。
func _预热() -> void:
	var 视口: SubViewport = SubViewport.new()
	视口.size = Vector2i(512, 512)
	视口.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(视口)
	for 预制: PackedScene in 特效预制表.values():
		var go: Node2D = 预制.instantiate() as Node2D
		视口.add_child(go)
		# 原地炸开（飞行=false），起止都给视口中心：落在视口矩形内才不会被 2D 裁剪掉，保证真的画了一帧
		go.call("播放", Vector2(256, 256), Vector2(256, 256), false)
	# 等两帧让每种特效都真正渲染过一次（管线编译完成），再整体释放
	await get_tree().process_frame
	await get_tree().process_frame
	视口.queue_free()

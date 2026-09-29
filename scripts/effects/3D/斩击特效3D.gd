@tool
extends 特效发射器3D
class_name 斩击特效3D
## 3D 斩击特效（原 BinbunVFX 的 VFXBattleSlash）。
## 检查器里的参数改完会立刻写到子节点（斩痕网格 / 粒子）的着色器上，可以边看边调。
##
## 参数名保持英文（.tscn 里写的覆盖值只有 ASCII 名字才读得回来），
## 每个参数上面的中文注释就是它的含义；用中文速查表见文件末尾的「参数速查」。

var audio_stream_player : AudioStreamPlayer3D:
	get():
		if audio_stream_player:
			return audio_stream_player
		
		var result = get_node_or_null("AudioStreamPlayer3D")
		
		if !Engine.is_editor_hint():
			audio_stream_player = result
		
		return result


## ===== 颜色 =====

## primary_color —— 主色：斩痕最亮的颜色
@export var primary_color : Color:
	set(v):
		primary_color = v
		_set_shader_param("primary_color", primary_color)

## secondary_color —— 次色：主色往它过渡，一般是中间调
@export var secondary_color : Color:
	set(v):
		secondary_color = v
		_set_shader_param("secondary_color", secondary_color)

## tertiary_color —— 暗色：最暗的颜色，压在下面当底色
@export var tertiary_color : Color:
	set(v):
		tertiary_color = v
		_set_shader_param("tertiary_color", tertiary_color)

## emission —— 发光强度：越高越亮，大于 1 会吃到辉光（bloom）
@export var emission : float = 1.0:
	set(v):
		emission = v
		_set_shader_param("emission", emission)


## ===== 形状 =====

## noise_texture —— 噪声贴图：斩痕的纹理来源，换一张就是另一种纹路
@export var noise_texture : Texture2D:
	set(v):
		noise_texture = v
		_set_shader_param("noise_texture", noise_texture)

## noise_scale —— 噪声缩放：值越大纹理越细密
@export var noise_scale : Vector2 = Vector2(1.0, 1.0):
	set(v):
		noise_scale = v
		_set_shader_param("noise_scale", noise_scale)

## noise_scroll —— 噪声滚动：纹理流动的方向与速度（x = 水平，y = 垂直）
@export var noise_scroll : Vector2 = Vector2(1.0, 0.0):
	set(v):
		noise_scroll = v
		_set_shader_param("noise_scroll", noise_scroll)

## noise_shape —— 噪声对比：对噪声取的指数，越大黑白越分明
@export_exp_easing("inout") var noise_shape : float = 1.0:
	set(v):
		noise_shape = v
		_set_shader_param("noise_shape", noise_shape)

## pulse_frequency —— 脉冲频率：波纹快慢
@export var pulse_frequency : float = 1.0:
	set(v):
		pulse_frequency = v
		_set_shader_param("pulse_frequency", pulse_frequency)

## pulse_amount —— 脉冲幅度：波纹强弱
@export_range(0.0, 1.0, 0.01) var pulse_amount : float = 0.6:
	set(v):
		pulse_amount = v
		_set_shader_param("pulse_amount", pulse_amount)


## ===== 透明度 =====

## edge_position —— 透明边缘位置：越大整条斩痕越透明
@export_range(0.0, 1.0, 0.01) var edge_position : float = 0.05:
	set(v):
		edge_position = v
		_set_shader_param("edge_position", edge_position)

## edge_hardness —— 边缘锐度：越大边缘越硬，越小越柔
@export_range(0.0, 1.0, 0.01) var edge_hardness : float = 0.0:
	set(v):
		edge_hardness = v
		_set_shader_param("edge_hardness", edge_hardness)


## ===== 音效（本游戏的音效走 Audio 自动播放，这套用不上）=====

## audio_stream —— 音效：要播的音频文件
@export var audio_stream : AudioStream:
	set(v):
		audio_stream = v
		if audio_stream_player: audio_stream_player.stream = audio_stream

## attenuation_model —— 衰减模式：3D 音效的距离衰减方式
@export var attenuation_model : AudioStreamPlayer3D.AttenuationModel:
	set(v):
		attenuation_model = v
		if audio_stream_player: audio_stream_player.attenuation_model = attenuation_model

## volume_animation —— 音量动画值（由 open / close 动画驱动，不用手改）
var volume_animation : float = 1.0:
	set(v):
		volume_animation = v
		if audio_stream_player: audio_stream_player.volume_db = lerpf(-24.0, volume_db, volume_animation)

## animate_volume —— 音量随发射淡入淡出
@export var animate_volume : bool = true

## volume_db —— 音量分贝
@export_range(-80.0, 80.0, 0.01, "suffix:dB") var volume_db : float = 0.0:
	set(v):
		volume_db = v
		if audio_stream_player: audio_stream_player.volume_db = lerpf(-24.0, volume_db, volume_animation)

## unit_size —— 响度距离：数值越大，声音传得越远
@export_range(0.1, 100.0, 0.01) var unit_size : float = 10.0:
	set(v):
		unit_size = v
		if audio_stream_player: audio_stream_player.unit_size = unit_size

## max_db —— 最大响度：近距离时最多能加到多少分贝
@export_range(-24.0, 6.0, 0.01, "suffix:dB") var max_db : float = 3.0:
	set(v):
		max_db = v
		if audio_stream_player: audio_stream_player.max_db = max_db

## pitch_scale —— 音调：1.0 为原速
@export_range(0.01, 4.0, 0.01) var pitch_scale : float = 1.0:
	set(v):
		pitch_scale = v
		if audio_stream_player: audio_stream_player.pitch_scale = pitch_scale

## audio_playing —— 播放音效
@export var audio_playing : bool = false:
	set(v):
		audio_playing = v
		if audio_stream_player: audio_stream_player.playing = audio_playing

## autoplay —— 自动播放
@export var autoplay : bool = false:
	set(v):
		autoplay = v
		if audio_stream_player: audio_stream_player.autoplay = autoplay

## stream_paused —— 暂停音效
@export var stream_paused : bool = false:
	set(v):
		stream_paused = v
		if audio_stream_player: audio_stream_player.stream_paused = stream_paused

## audio_max_distance —— 音效最远距离
@export_range(0.0, 2000.0, 0.01, "suffix:m") var audio_max_distance : float = 3.0:
	set(v):
		audio_max_distance = v
		if audio_stream_player: audio_stream_player.max_distance = audio_max_distance

## max_polyphony —— 最大同时播放数
@export var max_polyphony : int = 1:
	set(v):
		max_polyphony = v
		if audio_stream_player: audio_stream_player.max_polyphony = max_polyphony

## panning_strength —— 环绕强度
@export_range(0.0, 3.0, 0.01) var panning_strength : float = 1.0:
	set(v):
		panning_strength = v
		if audio_stream_player: audio_stream_player.panning_strength = panning_strength

## bus —— 音频总线：走哪条音频通道
@export var bus : StringName = &"Master":
	set(v):
		bus = v
		if audio_stream_player: audio_stream_player.bus = bus


# ============================================================
# 参数速查（中文 → 英文名）
#   主色 = primary_color      次色 = secondary_color     暗色 = tertiary_color
#   发光强度 = emission        噪声贴图 = noise_texture   噪声缩放 = noise_scale
#   噪声滚动 = noise_scroll    噪声对比 = noise_shape     脉冲频率 = pulse_frequency
#   脉冲幅度 = pulse_amount    透明边缘位置 = edge_position  边缘锐度 = edge_hardness
#   音效相关（本游戏不用）：audio_stream / attenuation_model / animate_volume /
#   volume_db / unit_size / max_db / pitch_scale / audio_playing / autoplay /
#   stream_paused / audio_max_distance / max_polyphony / panning_strength / bus
# ============================================================

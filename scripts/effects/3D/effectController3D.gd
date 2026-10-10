@tool
extends Node3D
class_name 特效控制器3D

## 3D 特效控制器（原 BinbunVFX 的 VFXController）。
## 它把下面这些参数同步写到子节点的材质（着色器参数）、灯光与动画上：
##   - speed_scale：整体播放速度（着色器 time_scale + 动画 + 粒子同步加速）
##   - 主色 / 次色 / 暗色：三个着色器颜色
##   - 灯光：开关、颜色、亮度（写在 Light 子节点上）
##   - 近距离淡出（proximity_fade）：靠近相机时淡出，2D 转制里用不到
##   - 精度（mesh_resolutions）：球/圆柱/平面的细分段数，越高越圆滑也越费
## 编辑器里勾 preview 可以直接预览播效果。
## 注意：参数名保持英文（中文名的 @export 在 .tscn 里写的覆盖值读不回来），中文含义写在注释里。

## 编辑器预览开关（只在编辑器里有意义，勾上就播）
@export var preview : bool = true:
	set(value):
		if Engine.is_editor_hint():
			if one_shot && value == true:
				play()
			else:
				preview = value
				if value == true:
					play()

## 单次播放：播放 "oneshot"（出现→消失）而不是循环 "main"
@export var one_shot : bool = false:
	set(value):
		if Engine.is_editor_hint():
			one_shot = value
			preview = false

## 进场自动播放
@export var autoplay : bool = true

## 动画循环时是否重置粒子
@export var reset_particles : bool = true

@export_group("General")
## 粒子用局部坐标（跟随节点移动）
@export var local_coords : bool = false:
	set(value):
		local_coords = value
		for p in _get_particles(): if is_instance_valid(p): p.local_coords = value
## 整体播放速度倍率
@export_range(0, 10, 0.01) var speed_scale : float = 1.0:
	set(value):
		speed_scale = value
		_set_shader_params("time_scale", speed_scale)
		_get_anim().speed_scale = value
		for p in _get_particles(): if is_instance_valid(p): p.speed_scale = value

@export_group("Colors")
## 主色（最亮的那层）
@export var primary_color : Color:
	set(value):
		primary_color = value
		_set_shader_params("primary_color", primary_color)
## 次色（中间调）
@export var secondary_color : Color:
	set(value):
		secondary_color = value
		_set_shader_params("secondary_color", secondary_color)
## 暗色（底色）
@export var tertiary_color : Color:
	set(value):
		tertiary_color = value
		_set_shader_params("tertiary_color", tertiary_color)

@export_group("Light")
## 灯光开关
@export var light_enable : bool = true:
	set(value):
		light_enable = value
		_set_light_prop("visible", value)
## 灯光颜色
@export var light_color : Color:
	set(value):
		light_color = value
		_set_light_prop("light_color", value)
## 灯光亮度
@export var light_energy : float = 4.0:
	set(value):
		light_energy = value
		_set_light_prop("base_energy", value)
## 灯光的间接光强度
@export var light_indirect_energy : float = 1.0:
	set(value):
		light_indirect_energy = value
		_set_light_prop("light_indirect_energy", value)
## 灯光的体积雾强度
@export var light_volumetric_fog_energy : float = 1.0:
	set(value):
		light_volumetric_fog_energy = value
		_set_light_prop("light_volumetric_fog_energy", value)

@export_group("Proximity Fade")
## 靠近相机时淡出
@export var proximity_fade : bool = false:
	set(value):
		proximity_fade = value
		_set_shader_params("proximity_fade", proximity_fade)
## 淡出开始的相机距离
@export var proximity_fade_distance : float = 1.0:
	set(value):
		proximity_fade_distance = value
		_set_shader_params("proximity_fade_distance", proximity_fade_distance)


@export_group("LODs")
enum Alpha_Mode {
	## 平滑透明，效果最好、最费
	SMOOTH, 
	## 抖动透明（点阵），省一些
	DITHER, 
	## 硬切（类似 Alpha Scissor），最省
	CUT, 
	## 抖动 + 硬切
	HYBRID
}
## 透明度的处理方式
@export var alpha_mode : Alpha_Mode = Alpha_Mode.SMOOTH:
	set(value):
		alpha_mode = value
		_set_shader_params("alpha_mode", alpha_mode)
## 硬切的阈值
@export_range(0.0,1.0,0.01) var alpha_cutoff : float = 0.02:
	set(value):
		alpha_cutoff = value
		_set_shader_params("alpha_cutoff", alpha_cutoff)
## 抖动阈值
@export_range(0.0,1.0,0.01) var dither_cutoff : float = 0.8:
	set(value):
		dither_cutoff = value
		_set_shader_params("dither_cutoff", dither_cutoff)
## 网格精度：球/圆柱的细分段数、平面的细分格数，越高越圆滑也越费
@export var mesh_resolutions : int = 32:
	set(value):
		mesh_resolutions = value
		_set_mesh_resolutions(mesh_resolutions)

var particles : Array[GPUParticles3D] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	if autoplay: play()

func _enter_tree() -> void:
	if autoplay: preview = true

func play():
	var anim : AnimationPlayer = _get_anim()
	
	if !one_shot:
		if reset_particles: _reset_particles()
		anim.play("main")
		anim.seek(0.0)
		await _get_anim().animation_finished
		if Engine.is_editor_hint() && !preview:
			return
		play()
	else:
		_reset_particles()
		if anim.has_animation("oneshot"):
			anim.play("oneshot")
			anim.seek(0.0)
		else:
			anim.play("main")

## Util
func _get_anim() -> AnimationPlayer:
	return get_node("AnimationPlayer")

func _get_particles() -> Array[GPUParticles3D]:
	var result : Array[GPUParticles3D] = []
	for p in get_children():
		if p is GPUParticles3D:
			result.append(p)
	return result

func _get_meshinstances() -> Array[MeshInstance3D]:
	var result : Array[MeshInstance3D] = []
	for m in get_children():
		if m is MeshInstance3D:
			result.append(m)
	return result

func _get_meshes() -> Array[Mesh]:
	var result : Array[Mesh]
	for p in _get_particles(): if is_instance_valid(p):
		result.append(p.draw_pass_1)
	for m in _get_meshinstances(): if is_instance_valid(m):
		result.append(m.mesh)
	return result

func _set_light_prop(pname : String, value) -> void:
	var light = get_node_or_null("Light")
	if light != null:
		light.set(pname, value)

func _reset_particles():
	for p in _get_particles():
		p.restart()

func _set_shader_params(参数名 : String, value) -> void:
	for p in _get_particles():
		if is_instance_valid(p):
			if p.material_override is ShaderMaterial:
				p.material_override.set("shader_parameter/" + 参数名, value)
	for m in _get_meshinstances():
		if is_instance_valid(m):
			if m.material_override is ShaderMaterial:
				m.material_override.set("shader_parameter/" + 参数名, value)

func _set_mesh_resolutions(value : int) -> void:
	for m in _get_meshes(): if is_instance_valid(m):
		if m is SphereMesh:
			m.radial_segments = value
			@warning_ignore("integer_division")
			m.rings = value/2
		if m is CylinderMesh:
			m.radial_segments = value
		if m is PlaneMesh:
			m.subdivide_width = value
			m.subdivide_depth = value

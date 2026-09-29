@tool
extends Node3D
class_name 特效发射器3D
## 3D 特效发射器基类（原 BinbunVFX 的 VFXEmitterBB）。
## 子节点里挂的着色器材质 / 网格 / 粒子会自动收集，改下面的参数会同步写到它们身上。
##
## 注意：参数名保持英文（emitting / speed_scale）。中文名的 @export 在 .tscn 里写的覆盖值
## 读不回来（Godot 对非 ASCII 属性名匹配不上），所以名字不改，中文含义写在每个参数上面的注释里。

var materials : Array[ShaderMaterial]:
	get():
		if !materials.is_empty():
			return materials
		
		var result : Array[ShaderMaterial]
		for c in get_children():
			if c is GPUParticles3D || c is MeshInstance3D:
				if c.material_override:
					result.append(c.material_override)
		if !Engine.is_editor_hint():
			materials = result
		return result

var meshes : Array[MeshInstance3D]:
	get():
		if !meshes.is_empty():
			return meshes
		
		var result : Array[MeshInstance3D]
		for c in get_children():
			if c is MeshInstance3D:
				result.append(c)
		if !Engine.is_editor_hint():
			meshes = result
		return result

var particles : Array[GPUParticles3D]:
	get():
		if !particles.is_empty():
			return particles
		
		var result : Array[GPUParticles3D]
		for c in get_children():
			if c is GPUParticles3D:
				result.append(c)
		if !Engine.is_editor_hint():
			particles = result
		return result

var anim : AnimationPlayer:
	get():
		if get_node("AnimationPlayer"):
			if !Engine.is_editor_hint() && anim:
				return anim
			return $AnimationPlayer
		else:
			return null

## emitting —— 是否正在发射：置 true 播「出现」动画（open）并让粒子开始喷；
## 置 false 播「消失」动画（close）并让粒子停止喷
@export var emitting : bool = true:
	set(v):
		emitting = v
		for p in particles:
			p.emitting = emitting
		if emitting:
			open()
		else:
			close()

## speed_scale —— 播放倍速：粒子速度与着色器动画一起加速/减速（1.0 = 原速）
@export_range(0.0, 8.0, 0.01) var speed_scale : float = 1.0:
	set(v):
		speed_scale = v
		for p in particles:
			p.speed_scale = speed_scale
		_set_shader_param("speed_scale", speed_scale)

func _restart_particles() -> void:
	for p in particles:
		p.restart()

func _set_particle_param(key : String, value : Variant) -> void:
	var parts : Array[GPUParticles3D] = particles
	for p in parts:
		p.set(key, value)

func _set_shader_param(key : String, value : Variant) -> void:
	var mats : Array[ShaderMaterial] = materials
	for m in mats:
		m.set_shader_parameter(key, value)

## 播「出现」动画（斩痕淡入）
func open() -> void:
	anim.play("open")

## 播「消失」动画（斩痕淡出）
func close() -> void:
	anim.play("close")

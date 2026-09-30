@tool
extends OmniLight3D
class_name 特效灯光3D

## 3D 特效里的点光源（原 BinbunVFX 的 VFX_Light）：
## 把「基础亮度 × 亮度倍率」写进 light_energy，倍率由动画（出现/消失）驱动。

## 基础亮度
@export var base_energy : float = 2.0:
	set(value):
		base_energy = value
		light_energy = base_energy * light_multiplier
## 亮度倍率（动画驱动）
@export_range(0.0,1.0,0.01) var light_multiplier : float = 1.0:
	set(value):
		light_multiplier = value
		light_energy = base_energy * light_multiplier

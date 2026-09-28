class_name GTeam
extends RefCounted
## 队伍（对照客户端 data/Team.h）

var is_red: bool = false
var grail: int = 0      # 星杯
var crystal: int = 0    # 战绩区水晶
var gem: int = 0        # 战绩区宝石
var morale: int = 0     # 士气
var morale_max: int = 0


func _init(red: bool = false) -> void:
	is_red = red


func set_grail(v: int) -> void:
	grail = v


func set_crystal(v: int) -> void:
	crystal = v


func set_gem(v: int) -> void:
	gem = v


func set_morale(v: int) -> void:
	morale = v


func set_morale_max(v: int) -> void:
	morale_max = v
	morale = v


func get_energy() -> int:
	return gem + crystal


func get_color() -> int:
	return GConst.RED if is_red else GConst.BLUE

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


## 只记上限，不动当前士气：当前士气一律以服务端快照（Data.apply_team_info）写入的为准。
## 注意 init_team 是随每份对局快照调用的（它还负责刷新 my_team / other_team）——
## 若在这里顺手 morale = v，每收到一次快照就会把真实士气刷回上限，
## 读 Data.team_of(...).morale 的判断（如【天火断空】士气落后时伤害 +1）就永远不成立
func set_morale_max(v: int) -> void:
	morale_max = v


func get_energy() -> int:
	return gem + crystal


func get_color() -> int:
	return GConst.RED if is_red else GConst.BLUE

## 战斗状态枚举 —— 对应 AGrail.StateEnum（值顺序与 C# 一致，UIStateChange 的 case 号就是它）
class_name StateEnum
extends RefCounted

enum {
	Idle = 0,
	Attack = 1,
	Magic = 2,
	Attacked = 3,
	Modaned = 4,
	Drop = 5,
	Weaken = 6,
	Heal = 7,
	DropCover = 8,
	Any = 10,
	AttackAndMagic = 11,
	Buy = 12,
	Extract = 13,
	Synthetize = 14,
	AdditionalAction = 15,
}

## 对应 C# StateEnum.ToString()（SkillRunner/StateHint 里按名字查表）
static func name_of(v: int) -> String:
	match v:
		Idle: return "Idle"
		Attack: return "Attack"
		Magic: return "Magic"
		Attacked: return "Attacked"
		Modaned: return "Modaned"
		Drop: return "Drop"
		Weaken: return "Weaken"
		Heal: return "Heal"
		DropCover: return "DropCover"
		Any: return "Any"
		AttackAndMagic: return "AttackAndMagic"
		Buy: return "Buy"
		Extract: return "Extract"
		Synthetize: return "Synthetize"
		AdditionalAction: return "AdditionalAction"
	return str(v)

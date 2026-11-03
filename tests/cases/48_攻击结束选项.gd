extends 自检用例
## 「攻击行动结束时」的技能只能在攻击行动结束时摆出来。
##
## 行动聚合器在攻击 / 法术行动结束时都会调 role.action_end_options()（见 battle_engine._push_action_end_hooks），
## 角色必须用 BattleRole.是攻击行动结束(ctx) 按 ctx.kind 过滤；否则法术结束也会冒出红色响应按钮。
## 风之剑圣【剑影】踩过：法术牌打完后也出现「剑影」选项。

const 用例表: Array = [
	{"名": "风之剑圣【剑影】", "路径": "res://scripts/battle/roles/role_jiansheng.gd"},
	{"名": "猎巫人【偷袭】", "路径": "res://scripts/battle/roles/role_liewuren.gd"},
	{"名": "魔弓【多重射击】", "路径": "res://scripts/battle/roles/role_mogong.gd"},
	{"名": "剑之魔女【剑影*断念】", "路径": "res://scripts/battle/roles/role_jianzhimoni.gd"},
	{"名": "剑之子【剑残影 / 剑影*断念】", "路径": "res://scripts/battle/roles/role_jianzhizi.gd"},
]

var 引擎: BattleEngine = null
var 玩家1: BattlePlayer = null


func _init() -> void:
	名称 = "攻击结束选项不出现在法术结束"


func 跑() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.start_with_roles({})
	玩家1 = 引擎.p(1)
	for 条: Dictionary in 用例表:
		var 名: String = str(条.get("名", "?"))
		var 类: GDScript = load(str(条.get("路径", ""))) as GDScript
		检(类 != null, "%s：脚本应能加载" % 名)
		if 类 == null:
			continue
		var 角色: BattleRole = 类.new()
		角色.setup(玩家1, 引擎)
		# 法术行动结束：不能出现「攻击行动结束时」的技能选项
		检(角色.action_end_options({"kind": "magic", "player": 玩家1.id}).is_empty(),
			"%s：法术行动结束不应摆出攻击结束选项" % 名)
		# 攻击行动结束：照常摆出来（是否 enabled 由各自条件决定，这里只看有没有）
		检(not 角色.action_end_options({"kind": "attack", "player": 玩家1.id}).is_empty(),
			"%s：攻击行动结束应照常摆出选项" % 名)
		# 解绑：这只是一次性检查用的实例，不要留在玩家身上
		角色.player = null
		角色.engine = null
	引擎._states.clear()
	引擎._清空等待()

extends 自检用例
## 用例 90：灵魂术士【灵魂转换】——目标色满了不能转，两色都满不询问
##
## 规则（用户口径）：
##   - 某色灵魂满了，就不能再往那个颜色转；
##   - 两个方向都转不了（两色都满，或没魂 / 目标色满）时，完全不弹询问。
##
## 覆盖：
##   黄 1 / 蓝 0        → 只有「黄→蓝」可点
##   黄 0 / 蓝 1        → 只有「蓝→黄」可点
##   黄 1 / 蓝满        → 不问
##   黄满 / 蓝 1        → 不问
##   黄 1 / 蓝 1（都没满）→ 两个方向都可点
##   两色都满            → 不问

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_linghun.gd")
const 黄: int = 0
const 蓝: int = 1

func _init() -> void:
	名称 = "灵魂转换满色"


func 跑() -> void:
	await 等帧(1)

	# 黄 1 / 蓝 0：只有黄→蓝
	var 场景: Dictionary = _开(1, 0)
	检(场景["问"] != null, "黄有魂、蓝没满时应询问")
	if 场景["问"] != null:
		var 可用: Array = 场景["问"].get("option_enabled", [])
		检(可用.size() == 2 and bool(可用[0]) and not bool(可用[1]),
			"黄 1 / 蓝 0 时应只有「黄→蓝」可点：%s" % str(可用))

	# 黄 0 / 蓝 1：只有蓝→黄
	场景 = _开(0, 1)
	检(场景["问"] != null, "蓝有魂、黄没满时应询问")
	if 场景["问"] != null:
		var 可用2: Array = 场景["问"].get("option_enabled", [])
		检(可用2.size() == 2 and not bool(可用2[0]) and bool(可用2[1]),
			"黄 0 / 蓝 1 时应只有「蓝→黄」可点：%s" % str(可用2))

	# 黄 1 / 蓝满：只能蓝→黄（不能往满的蓝转）
	场景 = _开(1, -1)
	检(场景["问"] != null, "蓝满但黄没满时仍可蓝→黄，应该询问")
	if 场景["问"] != null:
		var 可用满蓝: Array = 场景["问"].get("option_enabled", [])
		检(可用满蓝.size() == 2 and not bool(可用满蓝[0]) and bool(可用满蓝[1]),
			"蓝魂满时「黄→蓝」应置灰、只留「蓝→黄」：%s" % str(可用满蓝))

	# 黄满 / 蓝 1：只能黄→蓝（不能往满的黄转）
	场景 = _开(-1, 1)
	检(场景["问"] != null, "黄满但蓝没满时仍可黄→蓝，应该询问")
	if 场景["问"] != null:
		var 可用满黄: Array = 场景["问"].get("option_enabled", [])
		检(可用满黄.size() == 2 and bool(可用满黄[0]) and not bool(可用满黄[1]),
			"黄魂满时「蓝→黄」应置灰、只留「黄→蓝」：%s" % str(可用满黄))

	# 两色都满：不问
	场景 = _开(-1, -1)
	检(场景["问"] == null, "两色都满时不该询问")

	# 都没满：两个方向都可点
	场景 = _开(1, 1)
	检(场景["问"] != null, "两色都有余量时应询问")
	if 场景["问"] != null:
		# 两个方向都可用时引擎不下发 option_enabled（缺省＝全可点）
		var 可用3: Array = 场景["问"].get("option_enabled", [])
		检(可用3.is_empty() or (可用3.size() == 2 and bool(可用3[0]) and bool(可用3[1])),
			"两色都没满时两个方向都应可点：%s" % str(可用3))


## 造一局并触发一次灵魂转换询问。黄/蓝 传 -1 表示「填到上限」，否则设成该值。
## 返回 {"问": 询问命令或 null}
func _开(黄值: int, 蓝值: int) -> Dictionary:
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "灵魂术士")
	引擎.add_player(2, GConst.RED, "敌人")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	var 玩家: BattlePlayer = 引擎.p(1)
	玩家.role_id = 22
	var 角色: BattleRole = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	var 黄上限: int = int(玩家.tokens[黄]["max"])
	var 蓝上限: int = int(玩家.tokens[蓝]["max"])
	检(黄上限 > 0 and 蓝上限 > 0, "灵魂术士的魂上限没有初始化（前提不成立）")
	玩家.tokens[黄]["num"] = 黄上限 if 黄值 < 0 else 黄值
	玩家.tokens[蓝]["num"] = 蓝上限 if 蓝值 < 0 else 蓝值
	var 返回: int = int(角色.p_timeline_1({"src": 1, "is_active": true}))
	var 命令表: Array = (引擎._最后询问.get(1, {}) as Dictionary).get("commands", [])
	var 问: Variant = 命令表[0] if (返回 == BattleRole.WAIT and not 命令表.is_empty()) else null
	return {"问": 问}

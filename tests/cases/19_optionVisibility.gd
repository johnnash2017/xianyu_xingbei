extends 自检用例
## 固定选项不能“做不了就消失”：这些角色的选项集合必须始终完整，只把不可用项标 enabled=false。
## 这里覆盖本轮排查出的几处：御魂流居合式 / 神圣领域 / 希望赋格曲 / 暗影流星 / 军神威光。

func _init() -> void:
	名称 = "固定选项完整下发"


func _新引擎() -> BattleEngine:
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "蓝一")
	引擎.add_player(2, GConst.RED, "红二")
	引擎.add_player(3, GConst.BLUE, "蓝三")
	return 引擎


func _造角色(引擎: BattleEngine, rid: int) -> BattleRole:
	var 玩家: BattlePlayer = 引擎.p(1)
	玩家.role_id = rid
	return BattleRole.create(rid, 玩家, 引擎)


func 跑() -> void:
	await 等帧(1)

	# 兽灵武士：御魂流居合式固定三档，手牌为空时只有“弃 1 张手牌”置灰
	var 引擎: BattleEngine = _新引擎()
	var 角色: BattleRole = _造角色(引擎, 36)
	检(角色 != null, "兽灵武士脚本没有创建出来")
	if 角色 != null:
		var 选项: Array = 角色.call("_yu_hun_boot_choices")
		检(选项.size() == 3, "御魂流居合式应固定三档，实际 %d" % 选项.size())
		if 选项.size() == 3:
			检(not bool(选项[0].get("enabled", true)), "空手时“弃 1 张手牌”应置灰")
			检(bool(选项[1].get("enabled", true)) and bool(选项[2].get("enabled", true)),
				"空手时“摸 1 张 / 不调整”仍应可点")

	# 神官：神圣领域固定两档，没有治疗时“打伤害”置灰而不是消失
	引擎 = _新引擎()
	角色 = _造角色(引擎, 15)
	检(角色 != null, "神官脚本没有创建出来")
	if 角色 != null:
		var 选项2: Array = 角色.call("_ling_yu_choices")
		检(选项2.size() == 2, "神圣领域应固定两档，实际 %d" % 选项2.size())
		if 选项2.size() == 2:
			检(not bool(选项2[1].get("enabled", true)), "没有治疗时伤害档应置灰")
		引擎.p(1).cross_num = 1
		选项2 = 角色.call("_ling_yu_choices")
		if 选项2.size() == 2:
			检(bool(选项2[1].get("enabled", false)), "有治疗时伤害档应恢复可点")

	# 吟游诗人：希望赋格曲固定“放置 / 转移”两档，本场没有乐章/没有手牌时转移档置灰
	引擎 = _新引擎()
	角色 = _造角色(引擎, 31)
	检(角色 != null, "吟游诗人脚本没有创建出来")
	if 角色 != null:
		var 选项3: Array = 角色.call("_xi_wang_effect_options")
		检(选项3.size() == 2, "希望赋格曲应固定两档，实际 %d" % 选项3.size())
		if 选项3.size() == 2:
			检(not bool(选项3[1].get("enabled", true)), "没有乐章/手牌时转移档应置灰")
			检(not bool(角色.call("_can_xi_wang")), "没有可用档时希望赋格曲本体应置灰")

	# 魔剑士：暗影流星三种星石组合固定展示，没星石时全置灰
	引擎 = _新引擎()
	角色 = _造角色(引擎, 9)
	检(角色 != null, "魔剑士脚本没有创建出来")
	if 角色 != null:
		var 选项4: Array = 角色.call("_liu_xing_组合选项")
		检(选项4.size() == 3, "暗影流星应固定三种组合，实际 %d" % 选项4.size())
		var 全灰: bool = true
		for 项: Dictionary in 选项4:
			if bool(项.get("enabled", true)):
				全灰 = false
		检(全灰, "没有星石时暗影流星三种组合应全部置灰")
		引擎.team_crystal[引擎.p(1).color] = 2
		选项4 = 角色.call("_liu_xing_组合选项")
		if 选项4.size() == 3:
			检(bool(选项4[0].get("enabled", false)), "两水晶时第一组应可点")

	# 女武神：军神威光固定两档 / 五种组合；没星石时只置灰不消失
	引擎 = _新引擎()
	角色 = _造角色(引擎, 25)
	检(角色 != null, "女武神脚本没有创建出来")
	if 角色 != null:
		var 选项5: Array = 角色.call("_jun_shen_wei_guang_choices")
		检(选项5.size() == 2, "军神威光第一段应固定两档，实际 %d" % 选项5.size())
		if 选项5.size() == 2:
			检(not bool(选项5[1].get("enabled", true)), "没有星石时移除星石档应置灰")
		var 组合: Array = 角色.call("_jun_shen_wei_guang_energy_choices")
		检(组合.size() == 5, "军神威光第二段应固定五种组合，实际 %d" % 组合.size())
		var 全灰2: bool = true
		for 项: Dictionary in 组合:
			if bool(项.get("enabled", true)):
				全灰2 = false
		检(全灰2, "没有星石时军神威光五种组合应全部置灰")
		# 第一段询问不再带「二选一，选好后点确定」这类操作说明：ask_text 留空，
		# 客户端按「被动技能」的默认口径显示技能说明（见 battle_mobile._进入技能询问）
		角色.call("_jun_shen_wen_guo_ju")
		var 军神问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		检(not 军神问.is_empty(), "军神威光第一段应下发询问")
		if not 军神问.is_empty():
			检(str((军神问[0] as Dictionary).get("ask_text", "")) == "",
				"军神威光第一段不应再带「二选一」提示：%s"
				% str((军神问[0] as Dictionary).get("ask_text", "")))

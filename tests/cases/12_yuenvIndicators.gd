extends 自检用例
## 用例 12e：月女各技能的头像指示器配置 —— 法术伤害 / 治疗要画在正确目标上，
## 并验证【苍白之月】第二项的 X+1 现算。

func _init() -> void:
	名称 = "月女头像指示器"


func 跑() -> void:
	await 等帧(2)
	var 美杜莎: Dictionary = GConst.技能指示器[GConst.技能_美杜莎之眼]
	检((美杜莎.get("选项提示", {}) as Dictionary).has(1), "美杜莎缺少普通分支提示")
	检(((美杜莎["选项提示"] as Dictionary)[1] as Dictionary).has("自身"), "美杜莎普通分支应给自己 +1 治疗提示")
	检(int((((美杜莎["选项提示"] as Dictionary)[2] as Dictionary).get("每目标", 0))) == 1,
		"美杜莎法术牌分支应对目标造成 1 点法术伤害")
	检(((美杜莎["选项提示"] as Dictionary)[2] as Dictionary).has("自身"),
		"美杜莎法术牌分支应保留自己的 +1 治疗提示")

	var 轮回: Dictionary = GConst.技能指示器[GConst.技能_月之轮回]
	检(int((((轮回["选项提示"] as Dictionary)[1] as Dictionary).get("每目标", 0))) == 1,
		"月之轮回第一项应对目标 +1 治疗")
	检(str((((轮回["选项提示"] as Dictionary)[2] as Dictionary).get("自身", {}) as Dictionary).get("文案", "")) == "移除 %d 治疗",
		"月之轮回第二项应在自己头像写移除治疗")
	检(not (((轮回["选项提示"] as Dictionary)[2] as Dictionary)).has("每目标"),
		"月之轮回第二项没有目标，不应有目标伤害/治疗提示")

	var 月渎: Dictionary = GConst.技能指示器[GConst.技能_月渎]
	检(int(月渎.get("每目标", 0)) == 1 and str(月渎.get("文案", "")) == "%d 法术伤害",
		"月渎应在目标头像写 1 点法术伤害")
	检(str((月渎.get("自身", {}) as Dictionary).get("文案", "")) == "移除 %d 治疗",
		"月渎应在自己头像写移除治疗")

	var 暗月斩: Dictionary = GConst.技能指示器[GConst.技能_暗月斩]
	检(str(暗月斩.get("自动选目标", "")) == "询问目标",
		"暗月斩应自动选中本次攻击目标，头像才亮")
	检(GConst.技能指示器.has(GConst.技能_血影狂刀),
		"血影狂刀应保留头像指示器配置（伤害数字改由服务端给）")
	检(str((GConst.技能指示器.get(GConst.技能_撕裂, {}) as Dictionary).get("自动选目标", "")) == "询问目标",
		"撕裂应自动选中本次攻击目标，头像才亮");

	var 苍白: Dictionary = GConst.技能指示器[GConst.技能_苍白之月]
	检((((苍白["选项提示"] as Dictionary)[2] as Dictionary)).get("加参数下标", -1) == 1,
		"苍白之月第二项应取 args[1] 的新月数来算 X+1")

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	add_child(窗)
	await 等帧(2)
	窗.set("_已选参数", [2, 3])
	检(int(窗.call("_提示数值", (苍白["选项提示"] as Dictionary)[2], 1)) == 4,
		"苍白之月 X=3 时，目标提示应为 4 点法术伤害")

	# 实际走 _头像提示配置：美杜莎法术牌分支应同时有目标伤害和自己的治疗
	窗.set("_mode", 3)
	窗.set("_skill_ask_id", GConst.技能_美杜莎之眼)
	窗.set("_已选参数", [2])
	var 美配: Dictionary = 窗.call("_头像提示配置")
	检(int(美配.get("每目标", 0)) == 1 and 美配.has("自身"),
		"美杜莎法术牌分支的头像配置应同时含目标伤害和自己的治疗")

	# 月之轮回第二项只有自己「移除治疗」，没有目标提示
	窗.set("_skill_ask_id", GConst.技能_月之轮回)
	窗.set("_已选参数", [2])
	var 轮回二配: Dictionary = 窗.call("_头像提示配置")
	检(轮回二配.has("自身") and not 轮回二配.has("每目标"),
		"月之轮回第二项应只在自己头像写移除治疗")

	# 苍白之月第二项取 args[1] 现算
	窗.set("_mode", 4)
	窗.set("_pending_skill_id", GConst.技能_苍白之月)
	窗.set("_已选参数", [2, 3])
	var 苍配: Dictionary = 窗.call("_头像提示配置")
	检(int(苍配.get("每目标", 0)) == 1 and int(苍配.get("加参数下标", -1)) == 1,
		"苍白之月第二项的头像配置应接 X 现算")

	# 暗月斩：目标固定，选 1 张暗月后头像从原伤害变成 +1 伤害（规则 preview_rule＝card）
	窗.set("_mode", 3)
	窗.set("_skill_ask_id", GConst.技能_暗月斩)
	var 目标们: Array[int] = [2]
	var 未选牌: Array[int] = []
	var 选一张: Array[int] = [1]
	窗.set("_skill_targets", 目标们)
	窗.set("_pending", {"preview_base": 2, "preview_rule": "card", "preview_ids": [2]})
	窗.set("_sel_players", [] as Array[int])
	窗.set("_need_cards", 0)
	窗.set("_skill_ask_need_target", 0)
	窗.set("_sel_cards", 未选牌)
	var 暗月斩原: Dictionary = 窗.call("_预览伤害头像提示")
	检(str(暗月斩原.get(2, "")) == "2 攻击伤害",
		"暗月斩未选暗月时应写原攻击伤害")
	窗.set("_sel_cards", 选一张)
	var 暗月斩加: Dictionary = 窗.call("_攻击伤害头像提示")
	检(str(暗月斩加.get(2, "")) == "[zwj]2 攻击伤害\n3 攻击伤害",
		"暗月斩选 1 张暗月后应写原伤害划掉、+1 后伤害")

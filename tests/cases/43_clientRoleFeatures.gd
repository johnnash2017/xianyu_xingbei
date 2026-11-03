extends 自检用例
## 用例 43：13 名 3★ / 3.5★ 角色的客户端收口 ——
##   1) 角色特性集中表（GConst.角色特性）与查询函数：魔弹系别 / 临时魔弹掌控 / 基础效果免疫；
##   2) 额外行动的牌白名单 / 目标白名单（F2 下发，客户端置灰）与额外行动提示；
##   3) 4601 不能成为基础效果目标 → 目标头像置灰；
##   4) 10702 的临时【魔弹掌控】只在它那份额外法术行动内有效；
##   5) 技能指示器条目（4103 / 4705 / 7504 / 9305 / 10602 …）与通用 preview 头像提示；
##   6) 额外回合展示、角色卡替换展示。
## 不按单一角色写死：角色特性按 GConst.本批角色 / 系别遍历校验，白名单与临时掌控用多个角色交叉验证。

func _init() -> void:
	名称 = "客户端角色特性收口（13 角色）"


func _找牌名(卡名: int) -> GCard:
	for 牌: GCard in Data.card_db:
		if 牌 != null and not 牌.is_virtual and 牌.card_name_enum() == 卡名:
			return 牌
	return null


## 卡表里同一卡名的两张不同牌（如两张【圣光】：卡名相同、id 不同）
func _找两张牌名(卡名: int) -> Array[GCard]:
	var out: Array[GCard] = []
	for 牌: GCard in Data.card_db:
		if 牌 != null and not 牌.is_virtual and 牌.card_name_enum() == 卡名:
			out.append(牌)
			if out.size() >= 2:
				break
	return out


func _找系别(元素: int, 排除: Array = []) -> GCard:
	for 牌: GCard in Data.card_db:
		if 牌 == null or 牌.is_virtual or 排除.has(牌.id):
			continue
		# 【魔弹】/【圣光】本身带系别，任何角色都放行；测「系别过滤」要排除它们
		var 卡名: int = 牌.card_name_enum()
		if 卡名 == GConst.CardName.Missile or 卡名 == GConst.CardName.HolyLight:
			continue
		if 牌.element_enum() == 元素:
			return 牌
	return null


func _找攻击牌(排除: Array = []) -> GCard:
	for 牌: GCard in Data.card_db:
		if 牌 == null or 牌.is_virtual or 排除.has(牌.id):
			continue
		if 牌.is_attack() and 牌.element_enum() > 0:
			return 牌
	return null


func 跑() -> void:
	await 等帧(2)
	UI.goto_lobby()
	await 等帧(2)

	# ---------------- 1. 常量 / 角色特性（不依赖界面） ----------------
	检(GConst.本批角色.size() == 13, "本批角色应有 13 名，实际 %d" % GConst.本批角色.size())
	# 13 名角色的 59 颗技能：号码必须都能在技能表里查到（防止本表抄错号）
	var 技能号们: Array[int] = [
		GConst.技能_精灵赠礼, GConst.技能_元素射击SORA, GConst.技能_二重剑影,
		GConst.技能_附魔之术, GConst.技能_精灵的剑舞,
		GConst.技能_符文置换, GConst.技能_附魔打击, GConst.技能_熵变, GConst.技能_魔力熵增,
		GConst.技能_技之剑意, GConst.技能_臆想剑, GConst.技能_梦想剑, GConst.技能_剑影断念,
		GConst.技能_灵枝旨意, GConst.技能_邪灵退散, GConst.技能_伴响魂灵,
		GConst.技能_波涌之力, GConst.技能_怒潮荒涛, GConst.技能_海神御巫,
		GConst.技能_甜点冲击, GConst.技能_食欲的黑洞, GConst.技能_美味融合,
		GConst.技能_三秒原则, GConst.技能_美食风暴,
		GConst.技能_神风矢, GConst.技能_疾风追射, GConst.技能_弓神候补, GConst.技能_狙击EX,
		GConst.技能_高岭之花, GConst.技能_魔法入门, GConst.技能_Magic,
		GConst.技能_强予愿行, GConst.技能_友情羁绊,
		GConst.技能_贪欲黑洞, GConst.技能_殓金魔法, GConst.技能_炼金术, GConst.技能_亡女的金库,
		GConst.技能_元子吸收, GConst.技能_元子重塑, GConst.技能_元素学徒,
		GConst.技能_雷击变异, GConst.技能_月陨,
		GConst.技能_喧哗上等, GConst.技能_夜露死苦, GConst.技能_爱死天流, GConst.技能_灭茶苦茶,
		GConst.技能_别烦我, GConst.技能_让我躺平, GConst.技能_想用魔弹,
		GConst.技能_不想提炼, GConst.技能_再睡一下,
		GConst.技能_醋意羞心, GConst.技能_虚荣掌握, GConst.技能_相思病, GConst.技能_嫉妒追放,
		GConst.技能_倾慕, GConst.技能_风之剑, GConst.技能_剑守誓言, GConst.技能_剑残影,
	]
	检(技能号们.size() == 59, "13 角色技能数应为 59，实际 %d" % 技能号们.size())
	for 技能号: int in 技能号们:
		检(not GConst.技能行(技能号).is_empty(), "技能号 %d 在技能表里查不到" % 技能号)

	# 魔弹系别：47 水/火、87 雷/火、107 地/风；旧 8/76 地/火仍保留
	检(GConst.可当魔弹(GConst.角色_暴食少女, GConst.CardElement.Water), "47 应能用水系牌传递魔弹")
	检(GConst.可当魔弹(GConst.角色_暴食少女, GConst.CardElement.Fire), "47 应能用火系牌传递魔弹")
	检(not GConst.可当魔弹(GConst.角色_暴食少女, GConst.CardElement.Thunder), "47 不应能用雷系牌")
	检(GConst.可当魔弹(GConst.角色_贪婪少女, GConst.CardElement.Thunder), "87 应能用雷系牌")
	检(GConst.可当魔弹(GConst.角色_贪婪少女, GConst.CardElement.Fire), "87 应能用火系牌")
	检(not GConst.可当魔弹(GConst.角色_贪婪少女, GConst.CardElement.Water), "87 不应能用水系牌")
	检(GConst.可当魔弹(GConst.角色_忌妒少女, GConst.CardElement.Earth), "107 应能用地系牌")
	检(GConst.可当魔弹(GConst.角色_忌妒少女, GConst.CardElement.Wind), "107 应能用风系牌")
	检(not GConst.可当魔弹(GConst.角色_忌妒少女, GConst.CardElement.Water), "107 不应能用水系牌")
	检(GConst.可当魔弹(8, GConst.CardElement.Earth), "旧魔导师 8 的地系牌回归")
	检(GConst.可当魔弹(76, GConst.CardElement.Fire), "旧节日魔导 76 的火系牌回归")
	检(not GConst.可当魔弹(41, GConst.CardElement.Fire), "41 不应有魔弹系别")

	# 魔弹掌控：8/76 常驻；107 只在 10702 那份额外法术行动内
	检(GConst.魔弹掌控(8, 0), "8 应有常驻【魔弹掌控】")
	检(not GConst.魔弹掌控(GConst.角色_忌妒少女, 0), "107 没有额外行动时不应有【魔弹掌控】")
	检(GConst.魔弹掌控(GConst.角色_忌妒少女, GConst.技能_虚荣掌握), "107 在 10702 额外行动里应有【魔弹掌控】")
	检(not GConst.魔弹掌控(GConst.角色_忌妒少女, GConst.技能_嫉妒追放), "107 的临时掌控不适用于 10704")

	# 基础效果免疫 / 双张魔弹 / 旧名单回归
	检(GConst.基础效果免疫(GConst.角色_灵熙之潮), "46 应不能成为基础效果目标")
	检(not GConst.基础效果免疫(GConst.角色_剑之魔女), "45 不应有基础效果免疫")
	检(GConst.双张魔弹(GConst.角色_怠惰少女), "106 应有 10603 的双张魔弹")
	检(GConst.魔弹全禁(29), "29 应魔弹全禁")
	检(GConst.行动阶段禁用法术牌(9), "9 行动阶段应禁用法术牌")
	检(not GConst.行动阶段禁用法术牌(8), "8 行动阶段不应禁用法术牌")

	# 额外行动提示（10702 / 10704 / 10804 / 3803 / 4501）
	for 原因: int in [GConst.技能_虚荣掌握, GConst.技能_嫉妒追放, GConst.技能_剑残影,
			GConst.技能_二重剑影, GConst.技能_技之剑意]:
		检(GConst.额外行动提示.has(原因), "额外行动提示缺少 cause=%d" % 原因)
	检(str(GConst.额外行动提示.get(GConst.技能_虚荣掌握, "")).contains("魔弹"),
		"10702 的额外行动提示应点名只能使用【魔弹】")
	检(str(GConst.额外行动提示.get(GConst.技能_嫉妒追放, "")).contains("手牌数大于"),
		"10704 的额外行动提示应点名只能攻击手牌数大于你的对手")

	# 额外行动按钮的整段文案（3602 一击无念）：效果特殊，规则直接写在按钮上
	var 一击无念文案: String = str(GConst.额外行动按钮文案.get(GConst.技能_一击无念, ""))
	检(一击无念文案.contains("无视【圣盾】") and 一击无念文案.contains("无法使用【圣光】格挡")
		and 一击无念文案.contains("技类命格"),
		"3602 一击无念的按钮文案应写清无视圣盾 / 不能用圣光格挡 / 技类命格强制命中：%s"
		% 一击无念文案)

	# 技能指示器条目：每颗都要有文案 + 数值键
	var 期望指示器: Dictionary = {
		GConst.技能_熵变: {"每目标": 1},
		GConst.技能_魔力熵增: {"每目标": 1},
		GConst.技能_邪灵退散: {"每目标": 1},
		GConst.技能_甜点冲击: {"每目标": 2},
		GConst.技能_美食风暴: {"每目标": 2},
		GConst.技能_狙击EX: {"每目标": 5},
		GConst.技能_强予愿行: {"每目标": 4},
		GConst.技能_贪欲黑洞: {"每目标": 2},
		GConst.技能_亡女的金库: {"每目标": 1},
		GConst.技能_月陨: {"每能量": 1},
		# 10601 别烦我……：队友替她指定目标时，目标头像上写「摸 1 张牌」；
		# 10603 想用魔弹和魔弹融合一样，落点头像上写基础伤害
		GConst.技能_别烦我: {"每目标": 1},
		GConst.技能_让我躺平: {"每目标": 1},
		GConst.技能_想用魔弹: {"每目标": GConst.魔弹基础伤害},
		GConst.技能_剑残影: {"每目标": 1},
	}
	for 技能号: int in 期望指示器:
		var 配置: Dictionary = GConst.技能指示器.get(技能号, {})
		检(not 配置.is_empty(), "技能指示器缺少 %d" % 技能号)
		if not 配置.is_empty():
			# 每颗都要有文案（用例头注释承诺的校验：放进非空分支里执行，别写成 continue 后的死断言）
			检(not str(配置.get("文案", "")).is_empty(), "技能指示器 %d 缺少头像文案" % 技能号)
			for 键: String in 期望指示器[技能号]:
				检(int(配置.get(键, -1)) == int(期望指示器[技能号][键]),
					"技能指示器 %d 的 %s 应为 %d，实际 %s" % [
						技能号, 键, int(期望指示器[技能号][键]), str(配置.get(键))])

	# 客户端不再散写旧名单
	var 源文件: FileAccess = FileAccess.open("res://scripts/ui/battle_mobile.gd", FileAccess.READ)
	if 源文件 != null:
		var 源码: String = 源文件.get_as_text()
		for 旧名单: String in ["地火可作魔弹角色", "魔弹掌控角色", "魔弹全禁角色", "行动阶段禁用法术牌角色"]:
			检(not 源码.contains(旧名单), "battle_mobile.gd 仍残留硬编码名单：%s" % 旧名单)
		检(源码.contains("GConst.角色特性") or 源码.contains("GConst.可当魔弹"),
			"battle_mobile.gd 没有接入 GConst 的角色特性")
		# 额外行动牌 / 目标白名单与通用 preview 必须真的接进客户端
		for 新接口: String in ["_行动手牌白名单", "_行动目标白名单", "GConst.额外行动提示",
				"_预览伤害头像提示"]:
			检(源码.contains(新接口), "battle_mobile.gd 缺少客户端接口：%s" % 新接口)

	# ---------------- 2. 界面数据准备 ----------------
	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	var 旧手牌: Array[GCard] = Data.hand_cards
	var 旧盖牌: Array[GCard] = Data.cover_cards
	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "敌A"),
		GPlayer.new(3, GConst.BLUE, "队友"),
		GPlayer.new(4, GConst.RED, "敌B"),
	]
	Data.player_list = 玩家
	Data.hand_cards = []
	Data.cover_cards = []

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	# 额外行动按钮文案配了整段的（3602 一击无念）：按钮上直接显示整段，不再拼「额外【攻击行动】」
	检(str(窗.call("_额外行动按钮文本", GConst.技能_一击无念, GConst.ActionType.Attack, 0)) == 一击无念文案,
		"3602 的额外行动按钮应显示整段文案：%s"
		% str(窗.call("_额外行动按钮文本", GConst.技能_一击无念, GConst.ActionType.Attack, 0)))
	检(str(窗.call("_额外行动按钮文本", GConst.技能_剑影断念, GConst.ActionType.Attack, 0)) == "额外【攻击行动】",
		"没配整段文案的额外行动仍按放行种类拼默认按钮文字")
	Logic.game_info_updated.emit({"is_started": true, "room_id": 43,
		"blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 1, "red_gem": 1, "red_crystal": 2})
	await 等帧(2)

	var 魔弹牌: GCard = _找牌名(GConst.CardName.Missile)
	var 圣光牌: GCard = _找牌名(GConst.CardName.HolyLight)
	var 圣盾牌: GCard = _找牌名(GConst.CardName.Shield)
	var 中毒牌: GCard = _找牌名(GConst.CardName.Poison)
	var 攻击牌: GCard = _找攻击牌()
	var 火牌: GCard = _找系别(GConst.CardElement.Fire)
	var 水牌: GCard = _找系别(GConst.CardElement.Water)
	var 水牌2: GCard = _找系别(GConst.CardElement.Water, [水牌.id] if 水牌 != null else [])
	var 雷牌: GCard = _找系别(GConst.CardElement.Thunder)
	var 地牌: GCard = _找系别(GConst.CardElement.Earth)
	var 风牌: GCard = _找系别(GConst.CardElement.Wind)
	检(魔弹牌 != null and 圣光牌 != null and 圣盾牌 != null and 中毒牌 != null,
		"卡表缺少魔弹 / 圣光 / 圣盾 / 中毒")
	检(攻击牌 != null and 火牌 != null and 水牌 != null and 水牌2 != null
		and 雷牌 != null and 地牌 != null and 风牌 != null, "卡表缺少测试所需系别的牌")
	if 魔弹牌 == null or 圣盾牌 == null or 中毒牌 == null or 攻击牌 == null \
			or 火牌 == null or 水牌 == null or 水牌2 == null or 雷牌 == null \
			or 地牌 == null or 风牌 == null:
		窗.queue_free()
		Logic.my_player_id = 旧id
		Data.player_list = 旧玩家
		Data.hand_cards = 旧手牌
		Data.cover_cards = 旧盖牌
		return

	# ---------------- 3. 魔弹响应 / 传递的出牌过滤 ----------------
	窗.set("_pending", {"card_max": 1})
	玩家[0].role_id = GConst.角色_暴食少女
	检(bool(窗.call("_可回魔弹牌", 水牌.id)), "47 应能用水系牌传递魔弹")
	检(bool(窗.call("_可回魔弹牌", 火牌.id)), "47 应能用火系牌传递魔弹")
	检(not bool(窗.call("_可回魔弹牌", 雷牌.id)), "47 不应用雷系牌传递魔弹")
	检(bool(窗.call("_可回魔弹牌", 魔弹牌.id)), "任何角色都应能用【魔弹】本体传递")
	检(bool(窗.call("_可回魔弹牌", 圣光牌.id)), "任何角色都应能用【圣光】抵挡")
	玩家[0].role_id = GConst.角色_贪婪少女
	检(bool(窗.call("_可回魔弹牌", 雷牌.id)), "87 应能用雷系牌传递魔弹")
	检(not bool(窗.call("_可回魔弹牌", 水牌.id)), "87 不应用水系牌传递魔弹")
	玩家[0].role_id = GConst.角色_忌妒少女
	检(bool(窗.call("_可回魔弹牌", 地牌.id)), "107 应能用地系牌传递魔弹")
	检(bool(窗.call("_可回魔弹牌", 风牌.id)), "107 应能用风系牌传递魔弹")
	检(not bool(窗.call("_可回魔弹牌", 水牌.id)), "107 不应用水系牌传递魔弹")
	玩家[0].role_id = 41
	检(not bool(窗.call("_可回魔弹牌", 火牌.id)), "41 不应用火系牌传递魔弹")
	玩家[0].role_id = 29
	检(not bool(窗.call("_可回魔弹牌", 魔弹牌.id)), "29 魔弹全禁：不应能用【魔弹】传递")
	检(not bool(窗.call("_可回魔弹牌", 圣光牌.id)), "29 魔弹全禁：不应能用【圣光】格挡")

	# 10603：服务端 card_max=2 时可选两张同系牌
	玩家[0].role_id = GConst.角色_怠惰少女
	Data.hand_cards = [水牌, 水牌2]
	窗.set("_pending", {"card_max": 2})
	窗.set("_sel_cards", [] as Array[int])
	检(bool(窗.call("_可回魔弹牌", 水牌.id)), "10603 第一张水系牌应可选（手里有同系搭档）")
	检(not bool(窗.call("_可回魔弹牌", 火牌.id)), "10603 第一张火系牌没有同系搭档，不应可选")
	窗.set("_sel_cards", [水牌.id] as Array[int])
	检(bool(窗.call("_可回魔弹牌", 水牌2.id)), "10603 第二张同系牌应可选")
	检(not bool(窗.call("_可回魔弹牌", 火牌.id)), "10603 第二张不同系牌不应可选")
	# 选满 2 张后已选的牌仍要能点（再点＝取消），不能被「size() >= 2」整片置灰卡死
	窗.set("_sel_cards", [水牌.id, 水牌2.id] as Array[int])
	检(bool(窗.call("_可回魔弹牌", 水牌.id)), "10603 选满 2 张后点已选的牌应能取消")
	检(bool(窗.call("_可回魔弹牌", 水牌2.id)), "10603 选满 2 张后另一张已选牌也应能取消")
	检(not bool(窗.call("_可回魔弹牌", 地牌.id)), "10603 选满 2 张后未选的牌不应再可选")
	# 提交方式：单张同系牌不能算（服务端 v_remissile 只认真【魔弹】，会当放弃）
	窗.set("_sel_cards", [水牌.id] as Array[int])
	检(int(窗.call("_魔弹响应提交方式")) == -1, "10603 只选 1 张同系牌时不应允许提交")
	窗.set("_sel_cards", [水牌.id, 水牌2.id] as Array[int])
	检(int(窗.call("_魔弹响应提交方式")) == GConst.Reattack.Attack,
		"10603 两张同系牌应以 Attack 继续传递")
	窗.set("_sel_cards", [水牌.id, 火牌.id] as Array[int])
	检(int(窗.call("_魔弹响应提交方式")) == -1, "10603 两张不同系牌不应允许提交")
	窗.set("_sel_cards", [魔弹牌.id] as Array[int])
	检(int(窗.call("_魔弹响应提交方式")) == GConst.Reattack.Attack, "10603 单张真【魔弹】仍应能继续传递")
	窗.set("_sel_cards", [圣光牌.id] as Array[int])
	检(int(窗.call("_魔弹响应提交方式")) == GConst.Reattack.Block, "10603 单张【圣光】应按抵挡提交")
	# 其他角色（card_max=1）单张系别牌照旧能传：别把 10603 的限制带出去
	玩家[0].role_id = 8
	窗.set("_pending", {"card_max": 1})
	窗.set("_sel_cards", [火牌.id] as Array[int])
	检(int(窗.call("_魔弹响应提交方式")) == GConst.Reattack.Attack,
		"8（card_max=1）单张火系牌仍应以 Attack 继续传递")
	玩家[0].role_id = GConst.角色_怠惰少女

	var 魔弹询问: Dictionary = {
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.RespondType.Bullet, "src_id": 1,
			"dst_ids": [2, 4], "args": [1, 2, 3], "card_max": 2,
			"ask_text": "受到 2 伤害魔弹攻击，出【魔弹】继续传递，或弃 2 张同系牌视为【魔弹】，或出【圣光】抵挡，或点「取消」承受伤害",
		}],
	}
	# 真实点击链路：1 张同系牌不能点落点 / 确定置灰；2 张同系牌可点落点直接提交；已选牌可取消
	Data.hand_cards = [水牌, 水牌2]
	Logic.command_received.emit(魔弹询问)
	await 等帧(2)
	检(int(窗.get("_mode")) == 2, "10603 的魔弹响应没有进入应答态（_mode=%s）" % str(窗.get("_mode")))
	var 确定钮: Button = 窗.get("BtnOK")
	窗.call("_on_card_clicked", 水牌.id)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [水牌.id], "点第一张水系牌后没有被选中")
	# 10603：只选 1 张同系牌时落点也点亮（让人看得到会传到哪），但这时点它只提示、不提交，
	# 「确定」也仍然灰着（服务端只认两张同系牌）
	检(bool(窗.call("_玩家可选", 2)), "选 1 张同系牌时落点也应点亮（看得见会传到哪）")
	检(确定钮.disabled, "只选 1 张同系牌时「确定」应置灰")
	# 只选 1 张时点落点：没反应（不提交、也不换提示）
	var 提示前: String = str(窗.get("_提示原文"))
	窗.call("_on_player_clicked", 2)
	await 等帧()
	检(int(窗.get("_mode")) == 2, "只选 1 张同系牌时点落点不应提交")
	检(str(窗.get("_提示原文")) == 提示前, "只选 1 张同系牌时点落点不应弹新提示")

	窗.call("_on_card_clicked", 水牌2.id)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [水牌.id, 水牌2.id], "第二张同系牌没有选中")
	检(bool(窗.call("_玩家可选", 2)), "两张同系牌选好后应点亮魔弹落点")
	检(确定钮.disabled, "落点有多个时「确定」仍应先点一个落点")
	# 再点已选的牌＝取消：不能卡在「选满 2 张改不了牌」
	窗.call("_on_card_clicked", 水牌.id)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [水牌2.id], "再点已选的牌应能取消这一张")
	检(bool(窗.call("_玩家可选", 2)), "取消到只剩 1 张同系牌后落点仍亮着（但不能提交）")
	检(确定钮.disabled, "取消到只剩 1 张同系牌后「确定」应置灰")
	窗.call("_on_card_clicked", 水牌.id)
	await 等帧()
	检((窗.get("_sel_cards") as Array).size() == 2, "重新点回被取消的牌后应恢复 2 张")
	# 点落点＝一次性提交（两张同系牌以 Attack 交上去）
	窗.call("_on_player_clicked", 2)
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "点落点后没有提交本次魔弹响应（_mode=%s）" % str(窗.get("_mode")))

	# 两张同系【圣光】：必须按 Attack（2 张同系视为魔弹）提交，旧代码会按 Block 只交第一张
	var 圣光们: Array[GCard] = _找两张牌名(GConst.CardName.HolyLight)
	检(圣光们.size() == 2, "卡表里应至少有两张【圣光】")
	if 圣光们.size() == 2:
		Data.hand_cards = [圣光们[0], 圣光们[1]]
		Logic.command_received.emit(魔弹询问)
		await 等帧(2)
		窗.call("_on_card_clicked", 圣光们[0].id)
		await 等帧()
		窗.call("_on_card_clicked", 圣光们[1].id)
		await 等帧()
		检((窗.get("_sel_cards") as Array).size() == 2, "两张【圣光】没有都选中")
		检(int(窗.call("_魔弹响应提交方式")) == GConst.Reattack.Attack,
			"两张同系【圣光】应按 Attack 视为魔弹提交（按 Block 提交服务端只处理第一张）")
		检(bool(窗.call("_玩家可选", 2)), "两张【圣光】选好后应点亮魔弹落点")
		窗.call("_on_player_clicked", 2)
		await 等帧(2)
		检(int(窗.get("_mode")) == 0, "两张【圣光】没有提交")
		# 单张【圣光】仍是抵挡：不需要落点，「确定」直接可用
		Data.hand_cards = [圣光们[0]]
		Logic.command_received.emit(魔弹询问)
		await 等帧(2)
		窗.call("_on_card_clicked", 圣光们[0].id)
		await 等帧()
		检(int(窗.call("_魔弹响应提交方式")) == GConst.Reattack.Block, "单张【圣光】应按抵挡提交")
		检(not 确定钮.disabled, "单张【圣光】抵挡时「确定」应可用")
		窗.call("_on_ok")
		await 等帧(2)
		检(int(窗.get("_mode")) == 0, "单张【圣光】抵挡没有提交")

	# 单张真【魔弹】照旧能继续传递
	Data.hand_cards = [魔弹牌]
	Logic.command_received.emit(魔弹询问)
	await 等帧(2)
	窗.call("_on_card_clicked", 魔弹牌.id)
	await 等帧()
	检(int(窗.call("_魔弹响应提交方式")) == GConst.Reattack.Attack, "单张真【魔弹】应以 Attack 继续传递")
	检(bool(窗.call("_玩家可选", 2)), "单张真【魔弹】选好后应点亮落点")
	窗.call("_on_player_clicked", 2)
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "单张真【魔弹】没有提交")

	# 硬提交单张同系牌（模拟按钮状态过期 / 强点）：拦下来，别清空成「已提交」
	Data.hand_cards = [水牌, 水牌2]
	Logic.command_received.emit(魔弹询问)
	await 等帧(2)
	窗.call("_on_card_clicked", 水牌.id)
	await 等帧()
	窗.set("_sel_players", [2] as Array[int])
	窗.call("_on_ok")
	await 等帧()
	检(int(窗.get("_mode")) == 2, "单张同系牌硬提交不应被发出（界面被清空）")
	检(str(窗.get("_提示原文")).contains("同系"), "单张同系牌硬提交应提示「再选一张同系牌」")
	窗.call("_清空待选")
	await 等帧()
	窗.set("_pending", {"card_max": 1})
	窗.set("_sel_cards", [] as Array[int])
	Data.hand_cards = []

	# 出牌播报：真牌系别决定是否算「魔弹融合出牌」（107 的地/风，而非任意牌）
	var 播报名: Dictionary = {"type": GConst.CardMsgType.Use, "src_id": 1, "as_card_id": 魔弹牌.id}
	玩家[0].role_id = GConst.角色_忌妒少女
	播报名["card_ids"] = [地牌.id]
	检(bool(窗.call("_是魔弹融合出牌", 播报名)), "107 用地系牌当魔弹应算魔弹融合出牌")
	播报名["card_ids"] = [火牌.id]
	检(not bool(窗.call("_是魔弹融合出牌", 播报名)), "107 用火系牌当魔弹不应算魔弹融合出牌")
	玩家[0].role_id = 41
	播报名["card_ids"] = [地牌.id]
	检(not bool(窗.call("_是魔弹融合出牌", 播报名)), "41 不应算魔弹融合出牌")

	# ---------------- 4. 额外行动的牌 / 目标白名单 ----------------
	# 按钮文案要按「放行的动作种类」写：
	#   只放行攻击 → 额外【攻击行动】；只放行法术 → 额外【法术行动】；
	#   两类都放行（AttackMagic，如【偷天换日】【圣疗】）→ 额外【攻击行动】或【法术行动】。
	检(String(窗.call("_额外行动按钮文本", 0, GConst.ActionType.Attack, 0)) == "额外【攻击行动】",
		"只放行攻击的额外行动应写成「额外【攻击行动】」")
	检(String(窗.call("_额外行动按钮文本", 0, GConst.ActionType.Magic, 0)) == "额外【法术行动】",
		"只放行法术的额外行动应写成「额外【法术行动】」")
	检(String(窗.call("_额外行动按钮文本", 0, GConst.ActionType.AttackMagic, 0))
		== "额外【攻击行动】或【法术行动】",
		"既能攻击又能施法的额外行动应写成「额外【攻击行动】或【法术行动】」")
	检(String(窗.call("_额外行动按钮文本", 0, GConst.ActionType.AttackMagic, GConst.CardElement.Fire))
		== "额外【攻击行动】或【法术行动】：火系",
		"带系别且两类都放行时，系别写在冒号后的「说明」里")
	# 切换额外行动后，手牌点亮要按「选中那一份」的放行种类算：
	# 从「攻击或法术」的【偷天换日】切到只能攻击的【迅捷赐福】→ 手里的法术牌必须立刻暗掉。
	窗.set("_mode", 1)
	窗.set("_行动允许", GConst.ActionType.AttackMagic)
	窗.set("_行动命令", [{"card_ids": [], "dst_ids": []}])
	窗.set("_当前额外攻击选择", 1)
	窗.set("_额外攻击切换项", [{"uid": 1}])
	窗.set("_额外手牌白名单_选择", [])
	窗.set("_额外目标白名单_选择", [])
	窗.set("_额外行动放行_选择", GConst.ActionType.AttackMagic)
	检(bool(窗.call("_可主动使用牌", 魔弹牌.id)),
		"选中「攻击或法术」的额外行动时，法术牌应点亮")
	窗.set("_额外行动放行_选择", GConst.ActionType.Attack)
	检(not bool(窗.call("_可主动使用牌", 魔弹牌.id)),
		"切到只能攻击的额外行动后，法术牌应暗掉")
	检(bool(窗.call("_可主动使用牌", 攻击牌.id)),
		"切到只能攻击的额外行动后，攻击牌仍应点亮")
	窗.set("_额外行动放行_选择", 0)
	窗.set("_当前额外攻击选择", 0)
	窗.set("_额外攻击切换项", [])
	# 技能进二级栏时，把「这一手要消耗的额外行动」带进来，摆在本体前面
	# （点技能是 mode 4，不是 mode 1；这里就是欺诈/任何带选项的攻击技能的路径）
	窗.set("_mode", 4)
	窗.set("_当前额外攻击选择", 11)
	窗.set("_额外攻击切换项", [{"按钮": null, "uid": 11, "cause": GConst.技能_迅捷赐福,
		"allow": GConst.ActionType.Attack, "element": 0, "card_ids": [], "dst_ids": []}])
	窗.call("_进入二级技能栏", GConst.技能_欺诈, null, [], Color.WHITE, Callable(窗, "_on_cancel"))
	var 行动钮: Variant = 窗.get("_二级栏行动钮")
	var 父钮: Variant = 窗.get("_二级栏父按钮")
	检(行动钮 != null and is_instance_valid(行动钮),
		"技能进二级栏时应把要消耗的额外行动带进来")
	if 行动钮 != null and 父钮 != null:
		检((行动钮 as Control).get_index() < (父钮 as Control).get_index(),
			"要消耗的行动应摆在本体前面（行动 %d / 本体 %d）"
			% [(行动钮 as Control).get_index(), (父钮 as Control).get_index()])
	# 「返回」必须始终在本体右侧，不能被「要消耗的行动」挤到中间
	var 返回钮: Variant = null
	for b: Node in 窗.get("_技能按钮"):
		if b is Control and String((b as 技能按钮).说明文本) == "返回上一级":
			返回钮 = b
			break
	检(返回钮 != null and is_instance_valid(返回钮), "二级栏应摆出「返回」按钮")
	if 返回钮 != null and 父钮 != null:
		检((返回钮 as Control).get_index() > (父钮 as Control).get_index(),
			"「返回」应摆在本体右侧（返回 %d / 本体 %d）"
			% [(返回钮 as Control).get_index(), (父钮 as Control).get_index()])
	窗.set("_额外攻击切换项", [])
	窗.set("_当前额外攻击选择", 0)
	窗.call("_清空技能按钮")
	# 切换额外行动时：已经选好的牌 / 目标只要在新行动下仍合法就保留，不合法才收回
	窗.set("_mode", 1)
	窗.set("_行动允许", GConst.ActionType.AttackMagic)
	窗.set("_行动命令", [{"card_ids": [], "dst_ids": []}])
	窗.set("_额外行动放行_选择", 0)
	窗.set("_额外攻击切换项", [
		{"按钮": null, "uid": 21, "cause": GConst.技能_迅捷赐福, "allow": GConst.ActionType.Attack,
			"element": 0, "card_ids": [], "dst_ids": []},
	])
	# _sel_cards / _sel_players 是带类型的 Array，用 get 拿到同一个数组再改
	(窗.get("_sel_cards") as Array).clear()
	(窗.get("_sel_players") as Array).clear()
	(窗.get("_sel_cards") as Array).append(攻击牌.id)
	(窗.get("_sel_players") as Array).append(2)
	窗.call("_本地选择额外攻击", 0, 21, GConst.技能_迅捷赐福, [], [], GConst.ActionType.Attack)
	检((窗.get("_sel_cards") as Array).has(攻击牌.id),
		"切到仍放行攻击牌的行动时，已选攻击牌应保留：%s" % str(窗.get("_sel_cards")))
	检(not (窗.get("_sel_players") as Array).is_empty(),
		"新行动仍允许打该目标时，已选目标应保留")
	(窗.get("_sel_cards") as Array).clear()
	(窗.get("_sel_cards") as Array).append(魔弹牌.id)
	窗.call("_本地选择额外攻击", 0, 21, GConst.技能_迅捷赐福, [], [], GConst.ActionType.Attack)
	检((窗.get("_sel_cards") as Array).is_empty(),
		"新行动不放行法术牌时，已选法术牌应收回：%s" % str(窗.get("_sel_cards")))
	(窗.get("_sel_cards") as Array).clear()
	(窗.get("_sel_players") as Array).clear()
	窗.set("_额外攻击切换项", [])
	窗.set("_当前额外攻击选择", 0)
	窗.set("_额外行动放行_选择", 0)
	# 切换额外行动时技能栏也要跟着过滤：切到只放行攻击的行动后，法术技能按钮必须置灰
	# （不然按钮亮着、点下去会被服务端按新行动的种类驳回）。技能按钮把「要求的动作种类」记在
	# 元数据上：元数据名必须是 ASCII，写中文会被 Godot 拒绝、set_meta 静默失败，过滤整段失效。
	窗.set("_mode", 1)
	窗.set("_行动允许", GConst.ActionType.Magic)
	窗.call("_构建技能按钮", [
		{"respond_id": GConst.ActionType.Magic, "src_id": 1, "is_extra": true,
			"extra_cause": GConst.技能_元素点燃, "extra_uid": 501,
			"extra_attack_causes": [GConst.技能_元素点燃, GConst.技能_迅捷赐福],
			"extra_attack_uids": [501, 502],
			"allow_actions": [GConst.ActionType.Magic, GConst.ActionType.Attack],
			"extra_attack_cards": [{"ids": []}, {"ids": []}],
			"extra_attack_targets": [{"ids": []}, {"ids": []}],
			"extra_attack_elements": [0, 0],
			"dst_ids": [], "card_ids": [], "args": []},
		{"respond_id": GConst.ActionType.MagicSkill, "src_id": 1, "enabled": true,
			"dst_ids": [], "card_ids": [], "args": [GConst.技能_元素点燃, 0, 0, 0, 0]},
		{"respond_id": GConst.ActionType.MagicSkill, "src_id": 1, "enabled": true,
			"dst_ids": [], "card_ids": [], "args": [GConst.技能_冰冻, 0, 0, 0, 0]},
		{"respond_id": GConst.ActionType.AttackSkill, "src_id": 1, "enabled": true,
			"dst_ids": [], "card_ids": [], "args": [GConst.技能_迅捷赐福, 0, 0, 0, 0]},
	])
	await 等帧(2)
	var 法技能钮: 技能按钮 = null
	var 攻技能钮: 技能按钮 = null
	for b: Node in 窗.get("_技能按钮"):
		if not (b is 技能按钮):
			continue
		var 号: int = int((b as 技能按钮).技能号)
		if 号 == GConst.技能_元素点燃:
			法技能钮 = b
		elif 号 == GConst.技能_迅捷赐福:
			攻技能钮 = b
	检(法技能钮 != null and 攻技能钮 != null, "技能栏应摆出法术技能 / 攻击技能按钮")
	if 法技能钮 != null and 攻技能钮 != null:
		检(not 法技能钮.plateButton.disabled, "当前是法术额外行动：法术技能按钮应可点")
		检(攻技能钮.plateButton.disabled, "当前是法术额外行动：攻击技能按钮应置灰")
		窗.call("_本地选择额外攻击", 0, 502, GConst.技能_迅捷赐福, [], [], GConst.ActionType.Attack)
		检(法技能钮.plateButton.disabled, "切到只放行攻击的额外行动后：法术技能按钮必须置灰")
		检(not 攻技能钮.plateButton.disabled, "切到只放行攻击的额外行动后：攻击技能按钮应可点")
		窗.call("_本地选择额外攻击", 0, 501, GConst.技能_元素点燃, [], [], GConst.ActionType.Magic)
		检(not 法技能钮.plateButton.disabled, "切回只放行法术的额外行动后：法术技能按钮应可点")
		检(攻技能钮.plateButton.disabled, "切回只放行法术的额外行动后：攻击技能按钮应置灰")
	# 点「没有二级技能栏」的技能时，要消耗的那份额外行动按钮必须继续发光：
	# 额外行动按钮标的是「这一手消耗哪份行动」，不能随技能高亮一起熄灭（见 _标记选中技能）。
	var 法额外行动按钮: 技能按钮 = null
	var 攻额外行动按钮: 技能按钮 = null
	for 项: Dictionary in 窗.get("_额外攻击切换项"):
		if 项.get("按钮") is 技能按钮 and int(项.get("uid", 0)) == 501:
			法额外行动按钮 = 项.get("按钮")
		elif 项.get("按钮") is 技能按钮 and int(项.get("uid", 0)) == 502:
			攻额外行动按钮 = 项.get("按钮")
	检(法额外行动按钮 != null and 攻额外行动按钮 != null, "技能栏应摆出两份额外行动按钮")
	# 行动选项统一红底：法术额外行动以前按技能类型显示成响应紫，现在必须和攻击行动一样是红。
	var 行动红: Color = Color("c0392b")
	if 法额外行动按钮 != null and 攻额外行动按钮 != null:
		检((法额外行动按钮.plateButton.material as ShaderMaterial).get_shader_parameter("button_color") == 行动红,
			"法术额外行动的选项按钮应为红底")
		检((攻额外行动按钮.plateButton.material as ShaderMaterial).get_shader_parameter("button_color") == 行动红,
			"攻击额外行动的选项按钮应为红底")
	if 法额外行动按钮 != null and 攻额外行动按钮 != null and 法技能钮 != null:
		检(法额外行动按钮.selectedGlow.visible, "当前额外行动按钮应处于选中发光状态")
		窗.call("_选择技能", GConst.技能_元素点燃, GConst.ActionType.MagicSkill, 0, 0, [], [], 0, 0, 0,
			GConst.CardSource.Hand, "", 0, 0, [], 法技能钮, 0)
		检(法技能钮.selectedGlow.visible, "点中的技能应发光")
		检(法额外行动按钮.selectedGlow.visible, "点没有二级栏的技能后，要消耗的额外行动按钮应继续发光")
		窗.call("_本地选择额外攻击", 0, 502, GConst.技能_迅捷赐福, [], [], GConst.ActionType.Attack)
		检(not 法额外行动按钮.selectedGlow.visible, "切换额外行动后，旧额外行动按钮应熄灭")
		检(攻额外行动按钮.selectedGlow.visible, "切换额外行动后，新额外行动按钮应发光")
	# 切换额外行动时，已经点开、但新行动不放行的技能要整手取消（不能继续选目标）；
	# 新行动仍放行时原样保留。见 _取消失效的当前技能。
	var 冰冻钮: 技能按钮 = null
	for b: Node in 窗.get("_技能按钮"):
		if b is 技能按钮 and int((b as 技能按钮).技能号) == GConst.技能_冰冻:
			冰冻钮 = b
	检(冰冻钮 != null, "技能栏应摆出冰冻技能按钮")
	if 冰冻钮 != null and 法额外行动按钮 != null and 攻额外行动按钮 != null:
		窗.call("_本地选择额外攻击", 0, 501, GConst.技能_元素点燃, [], [], GConst.ActionType.Magic)
		窗.call("_选择技能", GConst.技能_冰冻, GConst.ActionType.MagicSkill, 0, 0, [], [], 0, 0, 0,
			GConst.CardSource.Hand, "", 0, 0, [], 冰冻钮, 0)
		(窗.get("_sel_players") as Array).append(2)
		检(int(窗.get("_mode")) == 4, "点冰冻后应进入技能准备态")
		检(冰冻钮.selectedGlow.visible, "冰冻应发光")
		# 新行动仍放行法术：技能保持准备态，已选目标不动
		窗.call("_本地选择额外攻击", 0, 501, GConst.技能_元素点燃, [], [], GConst.ActionType.Magic)
		检(int(窗.get("_mode")) == 4 and int(窗.get("_pending_skill_id")) == GConst.技能_冰冻,
			"新行动仍放行法术时，已经点开的技能应保留")
		(窗.get("_sel_players") as Array).clear()
		(窗.get("_sel_players") as Array).append(2)
		# 切成只放行攻击的行动：技能整手取消
		窗.call("_本地选择额外攻击", 0, 502, GConst.技能_迅捷赐福, [], [], GConst.ActionType.Attack)
		检(int(窗.get("_mode")) == 1, "切到不放行法术的行动后，应退回普通行动阶段")
		检(int(窗.get("_pending_skill_id")) == -1, "取消技能后不应还认着冰冻")
		检((窗.get("_sel_players") as Array).is_empty(), "取消技能后不应还留着冰冻的目标")
		检(not 冰冻钮.selectedGlow.visible, "取消技能后冰冻不应继续发光")
		检(not 法额外行动按钮.selectedGlow.visible and 攻额外行动按钮.selectedGlow.visible,
			"取消技能只取消技能，额外行动仍应切换成功")
	窗.call("_清空技能按钮")
	玩家[0].role_id = 41
	窗.set("_mode", 1)
	窗.set("_行动允许", GConst.ActionType.Any)
	窗.set("_行动命令", [{"card_ids": [攻击牌.id], "dst_ids": []}])
	检(bool(窗.call("_可主动使用牌", 攻击牌.id)), "白名单内的攻击牌应可点")
	检(not bool(窗.call("_可主动使用牌", 魔弹牌.id)), "白名单外的牌应置灰（10702 只能出魔弹的同类逻辑）")
	窗.set("_行动命令", [{"card_ids": [GConst.手牌白名单_全禁], "dst_ids": []}])
	检(not bool(窗.call("_可主动使用牌", 攻击牌.id)), "白名单＝全禁时攻击牌也不应可点")
	检(not bool(窗.call("_可主动使用牌", 魔弹牌.id)), "白名单＝全禁时魔弹也不应可点")
	# 10702 实例：地/风牌可以做魔弹，普通攻击牌不在白名单
	玩家[0].role_id = GConst.角色_忌妒少女
	窗.set("_行动命令", [{"card_ids": [风牌.id, 地牌.id], "dst_ids": []}])
	检(bool(窗.call("_可主动使用牌", 风牌.id)), "10702 的额外法术行动应放行风系牌（10703 当魔弹）")
	检(not bool(窗.call("_可主动使用牌", 攻击牌.id)), "10702 的额外法术行动不应放行普通攻击牌")
	窗.set("_行动命令", [{"card_ids": [], "dst_ids": []}])
	检(bool(窗.call("_可主动使用牌", 攻击牌.id)), "没有白名单时攻击牌照常可点（回归）")

	# 目标白名单：10704 / 10804 的额外攻击只能打服务端指定的人
	窗.set("_sel_cards", [攻击牌.id] as Array[int])
	窗.set("_行动命令", [{"card_ids": [], "dst_ids": [2]}])
	玩家[0].role_id = GConst.角色_忌妒少女
	检(bool(窗.call("_玩家可选", 2)), "10704 的额外攻击应能打白名单内的对手")
	检(not bool(窗.call("_玩家可选", 4)), "10704 的额外攻击不应能打白名单外的对手")
	玩家[0].role_id = GConst.角色_剑之子
	检(bool(窗.call("_玩家可选", 2)), "10804 的额外攻击应能打指定目标")
	检(not bool(窗.call("_玩家可选", 4)), "10804 的额外攻击不应能打其他对手")
	窗.set("_行动命令", [{"card_ids": [], "dst_ids": [GConst.目标白名单_无]}])
	检(not bool(窗.call("_玩家可选", 2)), "目标白名单＝无时应一个都点不亮")
	窗.set("_行动命令", [{"card_ids": [], "dst_ids": []}])
	玩家[0].role_id = 41
	检(bool(窗.call("_玩家可选", 2)) and bool(窗.call("_玩家可选", 4)),
		"没有目标白名单时两名对手都应可点（回归）")
	检(not bool(窗.call("_玩家可选", 3)), "队友不应能被主动攻击选中（回归）")

	# ---------------- 5. 4601 基础效果目标免疫 ----------------
	玩家[1].role_id = GConst.角色_灵熙之潮
	玩家[2].role_id = GConst.角色_剑之魔女
	检(not bool(窗.call("_可作法术目标", 圣盾牌, 2)), "46 不能被【圣盾】指定")
	检(not bool(窗.call("_可作法术目标", 中毒牌, 2)), "46 不能被【中毒】指定")
	检(bool(窗.call("_可作法术目标", 圣盾牌, 3)), "45 仍可被【圣盾】指定")
	检(bool(窗.call("_可作法术目标", 中毒牌, 3)), "45 仍可被【中毒】指定")

	# ---------------- 6. 10702 临时掌控 / 额外行动提示 ----------------
	玩家[0].role_id = GConst.角色_忌妒少女
	窗.set("_pending_type", GConst.Msg.Action)
	窗.set("_pending", {"is_extra": true, "extra_cause": GConst.技能_虚荣掌握})
	检(bool(窗.call("_有魔弹掌控")), "107 在 10702 的额外法术行动里应有【魔弹掌控】")
	窗.set("_pending", {"is_extra": true, "extra_cause": GConst.技能_嫉妒追放})
	检(not bool(窗.call("_有魔弹掌控")), "107 的临时掌控不应漏到 10704")
	窗.set("_pending", {"is_extra": false, "extra_cause": 0})
	检(not bool(窗.call("_有魔弹掌控")), "107 普通行动里不应有【魔弹掌控】")
	玩家[0].role_id = 8
	窗.set("_pending", {"is_extra": false, "extra_cause": 0})
	检(bool(窗.call("_有魔弹掌控")), "8 的常驻【魔弹掌控】回归")

	玩家[0].role_id = GConst.角色_忌妒少女
	窗.set("_pending_type", GConst.Msg.Action)
	窗.set("_pending", {"respond_id": GConst.ActionType.Magic, "is_extra": true,
		"extra_cause": GConst.技能_虚荣掌握, "args": [], "dst_ids": [], "card_ids": []})
	窗.call("_进入待选")
	await 等帧()
	检(str(窗.get("_提示原文")).contains("魔弹"), "10702 的额外法术行动提示没写「只能使用【魔弹】」")
	检(str(窗.get("_提示原文")).contains("逆向"), "10702 的额外法术行动提示没提「可逆向传递」")
	玩家[0].role_id = GConst.角色_剑之子
	窗.set("_pending_type", GConst.Msg.Action)
	窗.set("_pending", {"respond_id": GConst.ActionType.Attack, "is_extra": true,
		"extra_cause": GConst.技能_剑残影, "args": [], "dst_ids": [2], "card_ids": []})
	窗.call("_进入待选")
	await 等帧()
	检(str(窗.get("_提示原文")).contains("该目标"),
		"10804 的额外攻击提示没点名「只能攻击该目标对手」")

	# ---------------- 7. 通用 preview 头像提示（4701 / 4702 / 9704 共用） ----------------
	窗.set("_mode", 3)
	窗.set("_sel_players", [] as Array[int])
	窗.set("_skill_ask_id", GConst.技能_灭茶苦茶)
	窗.set("_pending", {"preview_base": 5, "preview_kind": GConst.HarmType.Attack, "preview_ids": [2]})
	var 预览: Dictionary = 窗.call("_预览伤害头像提示")
	检(str(预览.get(2, "")) == "5 攻击伤害", "9704 的通用 preview 头像提示不对：%s" % str(预览.get(2, "")))
	窗.set("_skill_ask_id", GConst.技能_食欲的黑洞)
	窗.set("_pending", {"preview_base": 3, "preview_kind": GConst.HarmType.Magic, "preview_ids": [1]})
	预览 = 窗.call("_预览伤害头像提示")
	检(str(预览.get(1, "")) == "3 法术伤害", "4702 的通用 preview 头像提示不对：%s" % str(预览.get(1, "")))
	# 已经选了目标、由静态指示器负责时不重复画
	窗.set("_skill_ask_id", GConst.技能_甜点冲击)
	窗.set("_sel_players", [2] as Array[int])
	窗.set("_pending", {"preview_base": 2, "preview_kind": GConst.HarmType.Magic, "preview_ids": [2]})
	预览 = 窗.call("_预览伤害头像提示")
	检(预览.is_empty(), "有静态指示器且已选目标时 preview 不应重复画")
	# 3301 / 3306 的 preview_base 是「本次攻击牌 id」，不是伤害：不能把牌号画成「107 攻击伤害」
	for 应战技能号: int in [GConst.技能_式神咒束, GConst.技能_阴阳转换]:
		窗.set("_skill_ask_id", 应战技能号)
		窗.set("_sel_players", [] as Array[int])
		窗.set("_pending", {"preview_base": 攻击牌.id, "preview_ids": [2], "preview_damage": 2})
		var 误画: Dictionary = 窗.call("_预览伤害头像提示")
		检(误画.is_empty(), "%d 的 preview_base 是攻击牌号 %d，不应画成头像伤害：%s" % [
			应战技能号, 攻击牌.id, str(误画)])
	窗.set("_mode", 0)
	窗.set("_skill_ask_id", -1)
	窗.set("_sel_players", [] as Array[int])

	# ---------------- 8. 额外回合 / 角色替换展示 ----------------
	# 额外回合走真实的 TurnBegin 消息：服务端显式下发 extra_turn，客户端以它为准。
	var 轮到条数0: int = str(窗.get("_日志")).count("轮到")
	Logic._on_message(GConst.Msg.TurnBegin, {"id": 1, "round": 5, "extra_turn": false})
	await 等帧()
	检(not bool(窗.get("_额外回合中")), "第一回合不应被判成额外回合")
	检(str(窗.get("_日志")).count("轮到") == 轮到条数0 + 1, "普通回合日志应写「轮到」")
	Logic._on_message(GConst.Msg.TurnBegin, {"id": 1, "round": 5, "extra_turn": true,
		"extra_cause": GConst.技能_剑守誓言, "attack_bonus": 1})
	await 等帧()
	检(bool(窗.get("_额外回合中")), "带 extra_turn 的 TurnBegin 应判成额外回合")
	检(str(窗.get("_提示原文")).contains("额外回合"), "额外回合没有提示")
	检(str(窗.get("_提示原文")).contains("剑守誓言"), "额外回合提示应带来源技能")
	检(str(窗.get("_日志")).contains("额外回合"), "额外回合没有写进日志")
	# 回归：剑之子在别人回合结束时拿额外回合、下一位又正好是他自己 ——
	# 两个回合的「玩家 + 回合号」完全一样，但第二个是他的正常回合，
	# 不能因为「同玩家 + 同回合号」被再判成额外回合（旧的猜法踩过）。
	var 轮到条数1: int = str(窗.get("_日志")).count("轮到")
	Logic._on_message(GConst.Msg.TurnBegin, {"id": 1, "round": 5, "extra_turn": false})
	await 等帧()
	检(not bool(窗.get("_额外回合中")),
		"同一玩家、同一回合号的正常回合（extra_turn=false）不应判成额外回合")
	检(str(窗.get("_日志")).count("轮到") == 轮到条数1 + 1, "这个正常回合的日志应写「轮到」")
	Logic._on_message(GConst.Msg.TurnBegin, {"id": 2, "round": 6, "extra_turn": false})
	await 等帧()
	检(not bool(窗.get("_额外回合中")), "下家正常回合不应判成额外回合")

	# 角色卡替换：快照里的 role_id 变了 → 面板重画；顶部提示不再弹「谁替换成了谁」
	var 替换前提示: String = str(窗.get("_提示原文"))
	玩家[2].role_id = GConst.角色_剑之子
	Logic.game_info_updated.emit({"is_started": true, "room_id": 43,
		"blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 1, "red_gem": 1, "red_crystal": 2})
	await 等帧(2)
	玩家[2].role_id = 1
	Logic.game_info_updated.emit({"is_started": true, "room_id": 43,
		"blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 1, "red_gem": 1, "red_crystal": 2})
	await 等帧(2)
	var 面板列表: Array = 窗.get("_面板列表")
	var 队友面板: 战斗玩家面板 = null
	for 面板: 战斗玩家面板 in 面板列表:
		if 面板.ID == 3:
			队友面板 = 面板
			break
	检(队友面板 != null, "找不到队友（id 3）的面板")
	if 队友面板 != null:
		检(int(队友面板.get("角色号")) == 1,
			"角色替换后面板角色号没刷新（=%s）" % str(队友面板.get("角色号")))
	检(str(窗.get("_提示原文")) == 替换前提示, "角色替换不应再弹顶部提示")

	# ---------------- 8.5 行动结束响应的默认选项 ----------------
	# 聚合器把一排可选行动摆出来时，服务端标 default_option=0 → 客户端默认选中第一项，
	# 不用先点一次选项才能按「确定」。第一项不可发动时顺延到第一个可用项。
	var 菜单询问: Dictionary = {
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": 105, "src_id": 1, "is_skill": true,
			"args": [0, 0, GConst.CardSource.Hand, 2, 105, GConst.技能_迅捷赐福],
			"notes": ["剑影", "迅捷赐福"], "default_option": 0,
		}],
	}
	Logic.command_received.emit(菜单询问)
	await 等帧(2)
	检(int(窗.get("_二级选中")) == 0, "带 default_option 的响应选项应默认选中第一项")
	var 选项表: Array = 窗.get("_二级选项")
	if 选项表.size() >= 1:
		检((选项表[0]["按钮"] as 技能按钮).selectedGlow.visible, "默认选中的第一项应发光")
	# 第一项不可发动：顺延到第一个可用项
	(菜单询问["commands"][0] as Dictionary)["option_enabled"] = [false, true]
	Logic.command_received.emit(菜单询问)
	await 等帧(2)
	检(int(窗.get("_二级选中")) == 1, "第一项不可发动时应顺延选中第一个可用项")
	窗.call("_清空技能按钮")

	# ---------------- 8.6 行动结束响应不摆「被问技能」本体 ----------------
	# 回归：聚合器询问的 respond_id 只是列表里的第一项（如神圣追击 2501，它没有「无父技能」配置）。
	# 客户端曾把「被问技能」本体和它的选项各摆一颗，出现两个一模一样的神圣追击按钮。
	# 排查：把会出现在行动结束响应里的全部 cause 各问一遍（角色登记项 + 队列授予项），
	# 每一条都必须只摆一颗按钮（本体被 no_parent 抑制）。
	for 技能号: int in [1601, 1606, 1907, 2501, 2603, 2808, 3402, 3602, 3802, 3803, 4205,
			4501, 4504, 10804, 105]:
		窗.call("_清空技能按钮")
		Logic.command_received.emit({
			"cmd_type": GConst.CmdType.Respond,
			"commands": [{
				"respond_id": 技能号, "src_id": 1, "is_skill": true,
				"args": [0, 0, GConst.CardSource.Hand, 1, 技能号],
				"notes": [GConst.skill_name(技能号)], "option_skill_ids": [技能号],
				"no_parent": true,
			}],
		})
		await 等帧(2)
		var 颗数: int = (窗.get("_技能按钮") as Array).size()
		检(颗数 == 1, "行动结束响应的 %d（%s）应只摆一颗按钮（本体被 no_parent 抑制），实际 %d 颗"
			% [技能号, GConst.skill_name(技能号), 颗数])
	窗.call("_清空技能按钮")

	# ---------------- 8.7 响应阶段：红色额外行动按钮只展示、置灰不可点 ----------------
	# 新规则：响应阶段不能使用行动；已获得的额外行动仍按原样摆成红色按钮（数量可见），
	# 但必须 disabled，真正使用留到响应结束后的额外行动阶段。
	# 当前正在消耗的那份额外行动按钮（如元素点燃给的法术行动）同样属于「行动」，也要置灰。
	窗.set("_当前额外攻击选择", 0)
	窗.set("_额外攻击切换项", [])
	窗.set("_已提交额外行动", {"cause": 1106, "allow": GConst.ActionType.Magic, "element": 0})
	# 真实流程：提交技能行动时置 _等待技能选项，紧接着的技能询问才把这份额外行动按钮带出来
	窗.set("_等待技能选项", true)
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": 2501, "src_id": 1, "is_skill": true,
			"args": [0, 0, GConst.CardSource.Hand, 1, 2501],
			"notes": ["神圣追击"], "option_skill_ids": [2501],
			"no_parent": true,
			"extra_attack_causes": [2501],
			"extra_attack_uids": [9001],
			"allow_actions": [GConst.ActionType.Attack],
			"extra_attack_cards": [{"ids": []}],
			"extra_attack_targets": [{"ids": []}],
			"extra_attack_elements": [0],
		}],
	})
	await 等帧(2)
	var 快捷按钮组: Array = 窗.get("_额外攻击响应按钮")
	检(快捷按钮组.size() == 1, "响应里的红色额外行动按钮应保留（数量可见），实际 %d 颗"
		% 快捷按钮组.size())
	var 额外行动按钮: 技能按钮 = 窗.get("_二级栏行动钮")
	检(额外行动按钮 != null, "响应里应摆出当前正在消耗的额外行动按钮（元素点燃）")
	if 额外行动按钮 != null:
		检(额外行动按钮.plateButton.disabled,
			"响应阶段当前额外行动按钮也必须置灰（不能在这里使用行动）")
		检(not 额外行动按钮.selectedGlow.visible,
			"响应阶段额外行动按钮不应是选中高亮状态（只有响应选项可选）")
	if 快捷按钮组.size() == 1:
		var 快捷按钮: 技能按钮 = 快捷按钮组[0]["按钮"]
		检(快捷按钮.plateButton.disabled,
			"响应阶段红色额外行动按钮必须置灰（不能在这里使用行动）")
		var 快捷色: Variant = (快捷按钮.plateButton.material as ShaderMaterial) \
			.get_shader_parameter("button_color")
		检(快捷色 == Color("c0392b"), "置灰的额外行动按钮仍应保持红色底色：%s" % str(快捷色))
		# 行动在左、响应在右：快捷行动按钮必须排在响应选项按钮之前
		var 选项组: Array = 窗.get("_二级选项")
		var 选项钮: 技能按钮 = (选项组[0]["按钮"] as 技能按钮) if not 选项组.is_empty() else null
		if 选项钮 != null:
			var 快捷索引: int = 快捷按钮.get_index()
			var 选项索引: int = 选项钮.get_index()
			检(快捷索引 < 选项索引,
				"红色行动按钮应排在响应选项左边（快捷=%d 选项=%d）" % [快捷索引, 选项索引])
			if 额外行动按钮 != null:
				检(额外行动按钮.get_index() < 快捷索引,
					"当前额外行动按钮应排在最左（按钮=%d 快捷=%d）" % [额外行动按钮.get_index(), 快捷索引])
	窗.set("_已提交额外行动", {})
	窗.call("_清空技能按钮")

	# ---------------- 收尾 ----------------
	窗.queue_free()
	await 等帧(3)
	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌

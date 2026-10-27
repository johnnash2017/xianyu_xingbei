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
	检(GConst.可当魔弹(GConst.角色_爆食少女, GConst.CardElement.Water), "47 应能用水系牌传递魔弹")
	检(GConst.可当魔弹(GConst.角色_爆食少女, GConst.CardElement.Fire), "47 应能用火系牌传递魔弹")
	检(not GConst.可当魔弹(GConst.角色_爆食少女, GConst.CardElement.Thunder), "47 不应能用雷系牌")
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
		GConst.技能_别烦我: {"每目标": 1},
		GConst.技能_让我躺平: {"每目标": 1},
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
	玩家[0].role_id = GConst.角色_爆食少女
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
	检(not bool(窗.call("_玩家可选", 2)), "只选 1 张同系牌时不应点亮魔弹落点（服务端会按放弃处理）")
	检(确定钮.disabled, "只选 1 张同系牌时「确定」应置灰")
	窗.call("_on_card_clicked", 水牌2.id)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [水牌.id, 水牌2.id], "第二张同系牌没有选中")
	检(bool(窗.call("_玩家可选", 2)), "两张同系牌选好后应点亮魔弹落点")
	检(确定钮.disabled, "还没点落点时「确定」应先置灰（点落点直接提交）")
	# 再点已选的牌＝取消：不能卡在「选满 2 张改不了牌」
	窗.call("_on_card_clicked", 水牌.id)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [水牌2.id], "再点已选的牌应能取消这一张")
	检(not bool(窗.call("_玩家可选", 2)), "取消到只剩 1 张同系牌后落点应重新置灰")
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
	检(str(预览.get(2, "")) == "5 点攻击伤害", "9704 的通用 preview 头像提示不对：%s" % str(预览.get(2, "")))
	窗.set("_skill_ask_id", GConst.技能_食欲的黑洞)
	窗.set("_pending", {"preview_base": 3, "preview_kind": GConst.HarmType.Magic, "preview_ids": [1]})
	预览 = 窗.call("_预览伤害头像提示")
	检(str(预览.get(1, "")) == "3 点法术伤害", "4702 的通用 preview 头像提示不对：%s" % str(预览.get(1, "")))
	# 已经选了目标、由静态指示器负责时不重复画
	窗.set("_skill_ask_id", GConst.技能_甜点冲击)
	窗.set("_sel_players", [2] as Array[int])
	窗.set("_pending", {"preview_base": 2, "preview_kind": GConst.HarmType.Magic, "preview_ids": [2]})
	预览 = 窗.call("_预览伤害头像提示")
	检(预览.is_empty(), "有静态指示器且已选目标时 preview 不应重复画")
	# 3301 / 3306 的 preview_base 是「本次攻击牌 id」，不是伤害：不能把牌号画成「107 点攻击伤害」
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
	窗.call("_on_turn", 1, 5)
	await 等帧()
	检(not bool(窗.get("_额外回合中")), "第一回合不应被判成额外回合")
	窗.call("_on_turn", 1, 5)
	await 等帧()
	检(bool(窗.get("_额外回合中")), "同一玩家同一回合号的第二次 TurnBegin 应判成额外回合")
	检(str(窗.get("_提示原文")).contains("额外回合"), "额外回合没有提示")
	检(str(窗.get("_日志")).contains("额外回合"), "额外回合没有写进日志")
	窗.call("_on_turn", 2, 6)
	await 等帧()
	检(not bool(窗.get("_额外回合中")), "下家正常回合不应判成额外回合")

	# 角色卡替换：快照里的 role_id 变了 → 面板重画 + 提示一次
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
	检(str(窗.get("_提示原文")).contains("角色卡替换"), "角色替换没有提示")
	检(int((窗.get("_上次角色号") as Dictionary).get(3, 0)) == 1, "角色替换检测没有记住新角色号")

	# ---------------- 收尾 ----------------
	窗.queue_free()
	await 等帧(3)
	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌

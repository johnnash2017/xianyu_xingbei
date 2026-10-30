extends 自检用例
## 用例 45：卡牌实例号（身份迁移）
## · 实例号编码：序号 0 的实例号就是牌号，克隆牌（序号 ≥ 1）能折回同一牌面；
## · 测试指令连发同一牌面：手牌里的实例号必须唯一，牌面可以重复；
## · 取牌 / 弃牌按实例号走，动一份不影响另一份同牌面副本；
## · 客户端手牌节点按实例号建：同牌面两张各占一个节点，选中一份不会带着另一份一起亮。

const 圣光: int = GConst.CardName.HolyLight


func _init() -> void:
	名称 = "卡牌实例号"


func 跑() -> void:
	await 等帧(2)

	# ---- 编码本身 ----
	检(GConst.实例号(3, 0) == 3, "序号 0 的实例号应等于牌号")
	检(GConst.牌号(GConst.实例号(3, 0)) == 3, "实例号应能折回牌面")
	检(GConst.牌号(GConst.实例号(3, 2)) == 3, "克隆牌的实例号应折回同一牌面")
	检(GConst.实例号(3, 1) != GConst.实例号(3, 2), "不同序号的实例号应不同")
	检(GConst.牌号(GConst.实例号(1003, 1)) == 1003, "虚拟牌（1000+）折回牌面也应正确")

	# ---- 服务端：测试指令克隆同牌面 ----
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.start_with_roles({1: 0, 2: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	var 甲: BattlePlayer = 引擎.p(1)
	甲.hand_cards.clear()
	甲.hand_cards_max = 40
	var 乙: BattlePlayer = 引擎.p(2)
	乙.hand_cards.clear()

	# 圣光只有 11 张实体：连按 6 次（每次 4 张）必然走到克隆
	for _i: int in range(6):
		引擎.debug_key(1, GConst.DebugKey.GiveHolyLight)
	var 手牌: Array[int] = 甲.hand_cards.duplicate()
	检(手牌.size() == 24, "发 6 次应得到 24 张（实际 %d）" % 手牌.size())

	var 见过: Dictionary = {}
	var 重复: int = 0
	for 号: int in 手牌:
		if 见过.has(号):
			重复 += 1
		见过[号] = true
	检(重复 == 0, "手牌里不应出现重复实例号（%d 个重复）" % 重复)

	var 面表: Dictionary = {}
	for 号2: int in 手牌:
		面表[GConst.牌号(号2)] = true
	检(面表.size() < 手牌.size(),
		"应出现同牌面的多份副本（牌面 %d 种 / 手牌 %d 张）" % [面表.size(), 手牌.size()])

	var 末: GCard = Data.get_card(手牌[手牌.size() - 1])
	检(末 != null, "克隆牌的实例号应能查到牌面")
	检(末 != null and 末.card_name_enum() == 圣光, "克隆牌应仍是【圣光】")

	# ---- 取牌按实例号：动一份不影响另一份 ----
	# 牌面是随机挑的（测试指令每次从全部同名牌里抽），所以不能拿「手牌第一张的牌面」当样本：
	# 要扫出一个确实有 ≥2 份副本的牌面（前面已断言 24 张里牌面种类更少，必然存在）。
	var 面计数: Dictionary = {}
	for 号7: int in 手牌:
		var 面7: int = GConst.牌号(号7)
		面计数[面7] = int(面计数.get(面7, 0)) + 1
	var 样本面: int = -1
	for 面8: int in 面计数:
		if int(面计数[面8]) >= 2:
			样本面 = 面8
			break
	var 两张: Array[int] = []
	for 号3: int in 手牌:
		if GConst.牌号(号3) == 样本面:
			两张.append(号3)
	检(两张.size() >= 2, "应能凑到同一牌面的两份副本")
	if 两张.size() >= 2:
		检(引擎.take_from_hand(1, [两张[0]]), "按实例号取牌应成功")
		检(not 甲.hand_cards.has(两张[0]), "被取走的那一份应已离手")
		检(甲.hand_cards.has(两张[1]), "另一份同牌面副本应还在手里")

		# 按牌面删：只删一份副本（同牌面默认删最先找到的那份）
		var 份数前: int = 0
		for 号4: int in 甲.hand_cards:
			if GConst.牌号(号4) == 样本面:
				份数前 += 1
		甲.remove_hand_cards([样本面])
		var 份数后: int = 0
		for 号5: int in 甲.hand_cards:
			if GConst.牌号(号5) == 样本面:
				份数后 += 1
		检(份数后 == 份数前 - 1,
			"按牌面删应只删掉一份副本（%d → %d）" % [份数前, 份数后])

		# 弃牌按实例号进弃牌堆
		var 剩下: int = -1
		for 号6: int in 甲.hand_cards:
			if GConst.牌号(号6) == 样本面:
				剩下 = 号6
				break
		if 剩下 >= 0:
			甲.remove_hand_cards([剩下])
			引擎.to_discard([剩下], {"owner": 1, "source": "hand"})
			检((引擎.deck.discard as Array).has(剩下), "弃掉的克隆牌应按实例号进弃牌堆")

	# ---- 出牌 / 弃牌的身份：提交上来的是实例号，弃牌堆必须保住它 ----
	# 反例（审计发现的老问题）：按牌面提交时，克隆牌进弃牌堆会变成牌面，而同牌面的原件
	# 可能还在别人手里 → 两个同 id 实体，洗回牌库后又会「选中一张、好几张一起亮」。
	var 克隆号: int = GConst.实例号(样本面, 1)
	甲.hand_cards = [克隆号]
	乙.hand_cards = [样本面]
	引擎.deck.discard.clear()
	检(引擎.take_from_hand(1, [克隆号]), "按实例号取牌应成功")
	引擎.to_discard([克隆号], {"owner": 1, "source": "hand"})
	检((引擎.deck.discard as Array).has(克隆号), "弃牌堆应保住实例号")
	检(not (引擎.deck.discard as Array).has(样本面), "弃牌堆不应把克隆牌折成牌面")

	# ---- 下发白名单折面：角色白名单可能取自手牌（实例号），下发前要折成牌面 ----
	引擎.ask_skill(1, 9999, 0, 0, GConst.CardSource.Hand, [], 0, "", [克隆号])
	var 询问表: Array = (引擎._最后询问.get(1, {}) as Dictionary).get("commands", [])
	检(not 询问表.is_empty() and (询问表[0].get("card_ids", []) as Array) == [样本面],
		"技能白名单下发前应折成牌面（实际 %s）" % str(询问表[0].get("card_ids", []) if not 询问表.is_empty() else []))

	# ---- 客户端：同牌面两张各占一个节点，选中一份不带亮另一份 ----
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	var 旧手牌: Array[GCard] = Data.hand_cards
	var 旧实例: Array[int] = Data.hand_iids
	var 面: GCard = Data.get_card(样本面)
	Data.hand_cards = [面, 面] as Array[GCard]
	Data.hand_iids = [样本面, GConst.实例号(样本面, 1)]
	窗.call("刷新手牌")
	await 等帧(1)
	var 手区: Node = 窗.get("HandArea")
	检(手区 != null and 手区.get_child_count() == 2,
		"两张同牌面副本应各建一个手牌节点（实际 %d 个）" % (0 if 手区 == null else 手区.get_child_count()))
	if 手区 != null and 手区.get_child_count() == 2:
		var 号A: int = int(手区.get_child(0).get("实例号"))
		var 号B: int = int(手区.get_child(1).get("实例号"))
		检(号A != 号B, "两个手牌节点的实例号应不同（%d / %d）" % [号A, 号B])
		# 只选中第一份：第二份不应跟着变选中
		窗.set("_sel_cards", [号A] as Array[int])
		窗.call("刷新手牌")
		await 等帧(1)
		var 选A: bool = bool(手区.get_child(0).get("_选中"))
		var 选B: bool = bool(手区.get_child(1).get("_选中"))
		检(选A and not 选B, "只选中一份副本时另一份不应一起亮（选中：%s / %s）" % [str(选A), str(选B)])
	Data.hand_cards = 旧手牌
	Data.hand_iids = 旧实例
	窗.queue_free()
	await 等帧(1)

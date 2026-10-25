extends 自检用例
## 12 号冒险家新版技能：欺诈两档（2 张非暗 / 3 张暗）与冒险者天堂（整份给一名队友）。

func _init() -> void:
	名称 = "冒险家新版技能"


func 跑() -> void:
	await 等帧(1)
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "我")
	引擎.add_player(2, GConst.RED, "敌人")
	引擎.add_player(3, GConst.BLUE, "队友")
	var 玩家: BattlePlayer = 引擎.p(1)
	玩家.role_id = 12
	var 角色: BattleRole = BattleRole.create(12, 玩家, 引擎)
	检(角色 != null, "12 号冒险家脚本没有创建出来")
	if 角色 == null:
		return

	# 找 3 张同系非暗牌（新版 3 张档不要求牌本身是暗系）
	var 同系: Array[int] = []
	var 按系: Dictionary = {}
	for c: GCard in Data.card_db:
		if c.element_enum() == GConst.CardElement.Darkness:
			continue
		var 系列: Array = 按系.get(c.element_enum(), [])
		系列.append(c.id)
		按系[c.element_enum()] = 系列
		if 系列.size() >= 3:
			for id: Variant in 系列.slice(0, 3):
				同系.append(int(id))
			break
	检(同系.size() == 3, "卡库找不到 3 张同系非暗牌，测试前提不成立")
	if 同系.size() != 3:
		return
	玩家.hand_cards.clear()
	玩家.hand_cards.append_array(同系)

	var 欺诈: Dictionary = {}
	for 技能: Dictionary in 角色.available_skills():
		if int(技能.get("id", 0)) == 1201:
			欺诈 = 技能
			break
	检(not 欺诈.is_empty(), "12 号冒险家没有欺诈技能")
	检(int(欺诈.get("need_card", 0)) == 2 and int(欺诈.get("card_max", 0)) == 3,
		"欺诈应允许选 2~3 张牌：need_card=%s card_max=%s" % [欺诈.get("need_card"), 欺诈.get("card_max")])
	var 选项: Array = 角色.call("_qi_zha_options")
	检(选项.size() == 6, "欺诈应摆出五种非暗虚牌 + 一种暗系虚牌，实际 %d" % 选项.size())
	if 选项.size() == 6:
		检(bool(选项[0].get("enabled", false)), "有同系牌时非暗虚牌应可用")
		检(bool(选项[5].get("enabled", false)), "有 3 张同系牌时暗系虚牌应可用")
		检(int(选项[0].get("card_max", 0)) == 2 and int(选项[5].get("card_max", 0)) == 3,
			"欺诈两档的选牌上限不对")

	# 2 张同系 + 非暗虚牌；3 张同系 + 暗系虚牌
	var 两张: Array = 同系.slice(0, 2)
	var 攻击目标: Array = [2]
	检(角色.call("v_attack_skill", {
		"src_id": 1, "action_id": 1201, "card_ids": 两张,
		"args": [66], "dst_ids": 攻击目标,
	}) == BattleRole.SUCCESS, "2 张同系牌走非暗虚牌应通过校验")
	检(角色.call("v_attack_skill", {
		"src_id": 1, "action_id": 1201, "card_ids": 同系,
		"args": [39], "dst_ids": 攻击目标,
	}) == BattleRole.SUCCESS, "3 张同系牌走暗系虚牌应通过校验")
	检(角色.call("v_attack_skill", {
		"src_id": 1, "action_id": 1201, "card_ids": 同系,
		"args": [66], "dst_ids": 攻击目标,
	}) != BattleRole.SUCCESS, "3 张牌不能走非暗虚牌")
	检(角色.call("v_attack_skill", {
		"src_id": 1, "action_id": 1201, "card_ids": 两张,
		"args": [39], "dst_ids": 攻击目标,
	}) != BattleRole.SUCCESS, "2 张牌不能走暗系虚牌")

	# 冒险者天堂：提炼出的 1~2 颗全部交给唯一一名队友
	检(角色.call("v_extract", [1202, 0, 0, 1, 1, 0, 2], 1, 1, [3]) == BattleRole.SUCCESS,
		"冒险者天堂：1 宝石 1 水晶交给一名队友应通过")
	检(角色.call("v_extract", [1202, 0, 0, 2, 0, 0, 2], 2, 0, [3]) == BattleRole.SUCCESS,
		"冒险者天堂：2 宝石交给一名队友应通过")
	检(角色.call("v_extract", [1202, 0, 0, 2, 1, 0, 3], 2, 1, [3]) != BattleRole.SUCCESS,
		"冒险者天堂不能一次提炼 3 颗")
	检(角色.call("v_extract", [1202, 0, 0, 1, 1, 0, 2], 1, 1, [1]) != BattleRole.SUCCESS,
		"冒险者天堂不能把星石交给自己")
	检(角色.call("v_extract", [1202, 0, 0, 1, 1, 0, 2], 1, 1, [2]) != BattleRole.SUCCESS,
		"冒险者天堂不能把星石交给敌人")
	检(角色.call("v_extract", [1202, 0, 0, 1, 1, 0, 2], 1, 1, [2, 3]) != BattleRole.SUCCESS,
		"冒险者天堂只能交给一名队友")

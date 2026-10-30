extends 自检用例
## 用例 44：精灵射手【精灵密仪】（3203，启动）——「牌库顶 3 张面朝下作为【祝福】」：
##   1) 直接从牌库顶取，不经过手牌：手牌满时也不会被顶到上限之上（以前用 engine.draw
##      先摸进手再拿走，超限判定被绕过，还顺带触发「摸牌前」响应）；
##   2) 牌库不足只取实际张数，不把弃牌堆洗回（F8 的「牌库顶」口径）。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_jinglingsheshou.gd")
const 精灵密仪: int = 3203


func _init() -> void:
	名称 = "精灵密仪取牌库顶"


func 跑() -> void:
	await 等帧(2)

	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "精灵射手")
	引擎.add_player(2, GConst.RED, "对手")
	引擎.start_with_roles({})
	var 我: BattlePlayer = 引擎.p(1)
	我.role_id = 32
	var 角色: BattleRole = 角色脚本.new()
	角色.setup(我, 引擎)
	我.role = 角色
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	我.hand_cards.clear()
	我.cover_cards.clear()
	我.cross_num = 0

	# ---- 牌库顶 3 张 → 全部作为【祝福】，手牌一张不动 ----
	我.set_gem(1)
	引擎.deck.pile = [11, 12, 13]
	引擎.deck.discard = [90, 91]
	角色.p_special_skill({"action_id": 精灵密仪})
	检(我.hand_cards.is_empty(), "精灵密仪不应把牌摸进手牌（实际 %d 张）" % 我.hand_cards.size())
	检(我.cover_cards.size() == 3, "应把牌库顶 3 张放进【祝福】，实际 %d 张" % 我.cover_cards.size())
	检(引擎.deck.pile.is_empty(), "牌库顶 3 张应被取走")
	检(引擎.deck.discard.size() == 2, "弃牌堆不应被洗回牌库：%s" % str(引擎.deck.discard))
	检(我.tap, "发动后应【横置】进入【精灵祝福形态】")
	检(我.get_energy() == 0, "发动应支付 1 宝石，实际剩 %d" % 我.get_energy())

	# ---- 手牌满 6 张时发动：手牌不能被顶过上限（也不该触发超限弃牌 / 掉士气）----
	var 六张: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 六张.has(c.id):
			continue
		六张.append(c.id)
		if 六张.size() >= GConst.HAND_CARDS_MAX:
			break
	检(六张.size() == GConst.HAND_CARDS_MAX, "卡库找不到 6 张实体牌")
	引擎.team_morale[GConst.BLUE] = 15
	我.hand_cards.clear()
	for cid: int in 六张:
		我.hand_cards.append(cid)
	我.tap = false
	我.set_gem(1)
	引擎.deck.pile = [21, 22, 23]
	角色.p_special_skill({"action_id": 精灵密仪})
	检(我.hand_cards.size() == 六张.size(),
		"手牌满时发动精灵密仪，手牌不应变化（实际 %d 张）" % 我.hand_cards.size())
	检(引擎._await_id == -1, "手牌满时发动精灵密仪不应压入任何等待（超限）")
	检(int(引擎.team_morale[GConst.BLUE]) == 15, "不应掉士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))

	# ---- 牌库不足：只取实际张数，不把弃牌堆洗回 ----
	我.cover_cards.clear()
	我.tap = false
	我.set_gem(1)
	引擎.deck.pile = [31]
	引擎.deck.discard = [91, 92, 93]
	角色.p_special_skill({"action_id": 精灵密仪})
	检(我.cover_cards.size() == 1, "牌库只剩 1 张时只应放 1 张【祝福】，实际 %d 张" % 我.cover_cards.size())
	检(引擎.deck.pile.is_empty(), "牌库那 1 张应被取走")
	检(引擎.deck.discard.size() == 3,
		"牌库不足时不应把弃牌堆洗回：弃牌堆 %s" % str(引擎.deck.discard))
	检(我.hand_cards.size() == 六张.size(), "第二次发动同样不应碰手牌")

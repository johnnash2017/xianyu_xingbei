extends 自检用例
## 用例 8：兽灵武士【逆反居合斩】的强制弃牌。
## 目标不能取消；超时（空回复）时按手牌顺序自动补满，不能出现「弃 0 张还照样抵御伤害」。

const 逆反居合斩: int = 3606
const 兽灵武士: int = 36


func _init() -> void:
	名称 = "逆反居合斩强制弃牌"


func 跑() -> void:
	await 等帧()
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "攻方")
	引擎.add_player(2, GConst.RED, "守方")
	var 攻方: BattlePlayer = 引擎.p(1)
	var 守方: BattlePlayer = 引擎.p(2)
	守方.hand_cards.clear()
	for i: int in range(5):
		守方.hand_cards.append(int(Data.card_db[i].id))
	var 兽灵: BattleRole = BattleRole.create(兽灵武士, 攻方, 引擎)
	攻方.role = 兽灵

	var 前: int = 守方.hand_cards.size()
	var r: int = 兽灵._request_discard(2, 2, 逆反居合斩, true)
	检(r == BattleRole.WAIT, "强制弃牌没有进入等待（返回 %d）" % r)
	检(not bool(引擎.get("_pending_skill_can_cancel")), "逆反居合斩的弃牌询问仍允许取消")
	var 最后询问: Dictionary = 引擎.get("_最后询问").get(2, {})
	var 询问命令: Array = 最后询问.get("commands", [])
	检(not 询问命令.is_empty() and str((询问命令[0] as Dictionary).get("ask_text", ""))
		== "弃掉 2 张牌，若弃少于 2 则士气 -1",
		"弃牌询问没有下发「弃掉 X 张牌，若弃少于 X 则士气 -1」的专属提示")
	# 超时兜底：引擎给的是不带牌的空回复
	引擎.set("_reply", {"respond_id": 逆反居合斩, "card_ids": [], "args": [], "is_timeout": true})
	引擎.set("_has_reply", true)
	var r2: int = 兽灵._request_discard(2, 2, 逆反居合斩, true)
	检(r2 != BattleRole.WAIT, "超时后强制弃牌没有结算完（返回 %d）" % r2)
	检(守方.hand_cards.size() == 前 - 2, "超时没有自动弃满 2 张（%d → %d）" % [前, 守方.hand_cards.size()])

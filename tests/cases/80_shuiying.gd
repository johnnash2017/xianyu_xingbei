extends 自检用例
## 用例 80：暗杀者【水影】502 —— 潜行（横置）时的第二段「额外弃 1 张法术牌」
##
## 回归点（用户报的 bug）：第二段的「跳过」用 `_有效水系牌(答案[0])` 校验第一段有没有真的弃出水系牌，
## 而 `_有效水系牌` 要求牌**还在手里**——第一段的答完已经把这些牌弃掉了，于是永远判成
## 「水影没成立」→ 潜行下第二段永远不问。
##
## 覆盖：
##   - 潜行 + 手里还有法术牌 → 第一段弃水系牌后，第二段必须问（card_rule = magic，白名单＝剩余法术牌）；
##   - 选 1 张法术牌 → 结算里再弃它【展示】；
##   - 非潜行（未横置）→ 第二段不问；
##   - 潜行但手里没法术牌 → 第二段不问；
##   - 潜行但第一段取消（空回复）→ 水影不成立，第二段不问。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_ansha.gd")

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null
var 水攻击: GCard = null
var 水法术: GCard = null
var 火攻击: GCard = null
var 发送记录: Array = []
## 同一次摸牌事件必须用同一个 ctx（角色靠 ctx["shui_ying_taken"] 认「这枚摸牌已经被接管」）
var 上下文: Dictionary = {}


func _init() -> void:
	名称 = "暗杀者水影"


func _取牌(条件: Callable) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if bool(条件.call(c)):
			return c
	return null


func 跑() -> void:
	await 等帧(1)
	水攻击 = _取牌(func(c: GCard) -> bool:
		return c.is_attack() and c.element_enum() == GConst.CardElement.Water)
	水法术 = _取牌(func(c: GCard) -> bool:
		return c.is_magic() and c.element_enum() == GConst.CardElement.Water \
			and c.card_name_enum() != GConst.CardName.Shield)
	火攻击 = _取牌(func(c: GCard) -> bool:
		return c.is_attack() and c.element_enum() != GConst.CardElement.Water)
	检(水攻击 != null and 水法术 != null and 火攻击 != null,
		"卡库缺「水系攻击 / 水系法术 / 非水攻击」中的某一张")
	if 水攻击 == null or 水法术 == null or 火攻击 == null:
		return
	_建引擎()

	# ---- 1) 潜行 + 有剩余法术牌：第二段必须问 ----
	_重置战斗()
	玩家.tap = true
	玩家.hand_cards = [水攻击.id, 水法术.id, 火攻击.id] as Array[int]
	角色.p_before_draw(上下文)
	检(_等待号() == 1 and not _最后询问(1).is_empty(), "潜行时水影第一段没有下发询问")
	_喂回复({"respond_id": 502, "args": [], "card_ids": [水攻击.id], "dst_ids": []})
	_推进水影()
	检(_等待号() == 1, "潜行下弃完水系牌后没有挂起第二段询问（链已收尾）")
	var 第二问: Dictionary = _命令(1)
	检(not 第二问.is_empty(), "潜行下弃完水系牌后，第二段「额外弃法术牌」没有问")
	if not 第二问.is_empty():
		检(int(第二问.get("respond_id", 0)) == 502, "第二段询问号不是 502")
		检(str(第二问.get("card_rule", "")) == "magic",
			"第二段没有按「只能选法术牌」限制：%s" % str(第二问.get("card_rule", "")))
		var 白: Array = 第二问.get("card_ids", [])
		检(白.has(水法术.id), "第二段白名单里没有手里那张水系法术牌：%s" % str(白))
		检(not 白.has(水攻击.id), "第二段白名单里还留着第一步已弃掉的水系牌：%s" % str(白))
		# 选那张法术牌 → 结算里应再弃它
		_喂回复({"respond_id": 502, "args": [1], "card_ids": [水法术.id], "dst_ids": []})
		_推进水影()
		检(_等待号() == -1, "第二段答完应整条链收尾，仍有挂起询问")
		检(引擎.deck.discard.has(水法术.id), "选中的法术牌没有进弃牌堆（第二段效果没结算）")
		检(not 玩家.hand_cards.has(水法术.id), "选中的法术牌还留在手里")

	# ---- 2) 非潜行：第二段不问 ----
	_重置战斗()
	玩家.tap = false
	玩家.hand_cards = [水攻击.id, 水法术.id] as Array[int]
	角色.p_before_draw(上下文)
	_喂回复({"respond_id": 502, "args": [], "card_ids": [水攻击.id], "dst_ids": []})
	_推进水影()
	检(_等待号() == -1, "未横置时不应该问第二段，却挂起了询问：%s" % str(_命令(1)))

	# ---- 3) 潜行但没有法术牌：第二段不问 ----
	_重置战斗()
	玩家.tap = true
	玩家.hand_cards = [水攻击.id, 火攻击.id] as Array[int]
	角色.p_before_draw(上下文)
	_喂回复({"respond_id": 502, "args": [], "card_ids": [水攻击.id], "dst_ids": []})
	_推进水影()
	检(_等待号() == -1, "潜行但没法术牌时不该问第二段，却挂起了询问：%s" % str(_命令(1)))

	# ---- 4) 潜行 + 第一段取消：水影不成立，第二段不问 ----
	_重置战斗()
	玩家.tap = true
	玩家.hand_cards = [水攻击.id, 水法术.id] as Array[int]
	角色.p_before_draw(上下文)
	_喂回复({"respond_id": 502, "args": [], "card_ids": [], "dst_ids": []})
	_推进水影()
	检(_等待号() == -1, "第一步取消后不该再问第二段，却挂起了询问：%s" % str(_命令(1)))
	var 播报: bool = false
	for 条: Dictionary in 发送记录:
		if int(条.get("msg", -1)) == GConst.Msg.Skill \
				and int((条.get("data", {}) as Dictionary).get("skill_id", 0)) == 502:
			播报 = true
	检(not 播报, "第一步取消时不该播报水影发动")


## 只有链还在时才重入钩子；链已经结算掉（例如第二段被错误跳过）就不要再调，
## 否则会开一条新链、把「没问第二段」伪装成「又在问第一段」
func _推进水影() -> void:
	if 角色.多步询问进行中(502) or 角色.多步询问待收尾(502):
		角色.p_before_draw(上下文)
# ============================================================
# 引擎 / 询问辅助
# ============================================================
func _建引擎() -> void:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "暗杀者")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 5
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色


func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	角色._多步链.clear()
	角色._多步收尾.clear()
	角色._多步不收尾.clear()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	发送记录.clear()
	发送记录.clear()
	上下文 = {"player": 1}
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.round_id = 1
	引擎.deck.pile.clear()
	引擎.deck.discard.clear()
	for pid: int in [1, 2, 3, 4]:
		var p: BattlePlayer = 引擎.p(pid)
		p.hand_cards.clear()
		p.cover_cards.clear()
		p.tap = false


func _等待号() -> int:
	return int(引擎.get("_await_id"))


func _最后询问(pid: int) -> Dictionary:
	return (引擎.get("_最后询问") as Dictionary).get(pid, {})


func _命令(pid: int) -> Dictionary:
	var 问: Dictionary = _最后询问(pid)
	var 表: Array = 问.get("commands", [])
	if 表.is_empty():
		return {}
	return 表[0] as Dictionary


## 直接走引擎的应答入口（与真实客户端同路径）
func _喂回复(数据: Dictionary) -> void:
	var pid: int = _等待号()
	if pid < 0:
		pid = 1
	引擎.on_message(pid, GConst.Msg.Respond, 数据)

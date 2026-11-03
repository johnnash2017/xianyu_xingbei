extends 自检用例
## 异教徒（95）实际跑测：末日预言的【预言】堆、翻面、天雷劫火 / 地裂波涛的「展示时」、
## 【贪婪】两项都发动、【灾殃止息】移除、【献祭】、【放逐】（无视手牌上限）。
##
## 驱动方式与其它角色用例一致：直接调角色钩子 / 技能入口，把回复塞进引擎后 run()，
## 由状态栈自己推进（与线上同一条路径，不在用例里复制规则）。

const 角色路径: String = "res://scripts/battle/roles/role_yijiaotu.gd"

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "异教徒（95）：末日预言 / 天雷劫火 / 地裂波涛 / 贪婪 / 灾殃止息"


func 跑() -> void:
	_检开局与手牌上限()
	_检献祭同系()
	_检献祭异系()
	_检翻面天雷()
	_检贪婪两项()
	_检灾殃止息()
	_检放逐()
	引擎 = null


# ============================================================
# 建局
# ============================================================
func _建引擎() -> void:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles({})
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.role = null
		p0.hand_cards.clear()
		p0.cross_num = 0
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	角色 = (load(角色路径) as GDScript).new()
	角色.setup(玩家1, 引擎)
	玩家1.role = 角色
	玩家1.role_id = 95
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.round_id = 1


## 把一条回复塞进引擎（随后 run() 由状态栈取走）
func _应答(args: Array = [], dsts: Array = [], cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": dsts, "respond_id": 0}
	引擎._has_reply = true


## 跑到「问目标对手」的询问为止：途中的「治疗抵挡」询问一律答不用治疗
func _等到目标询问() -> bool:
	for i: int in range(10):
		引擎.run()
		if 引擎._await_id < 0:
			return false
		if 引擎._pending_respond_id == GConst.RespondType.Heal:
			_应答([0])
			continue
		return 引擎._await_id == 1 and 引擎._pending_respond_id == 9507
	return false


## 跑一段伤害结算：只在「治疗抵挡」询问时回答不用治疗，其它询问一律留着给用例自己答
func _收伤害() -> void:
	for i: int in range(8):
		引擎.run()
		if 引擎._await_id < 0 or 引擎._pending_respond_id != GConst.RespondType.Heal:
			return
		_应答([0])


## 给某玩家 n 张指定系别的牌（牌库牌的实例号 == 牌面），返回实例号
func _发牌(p: BattlePlayer, 元素: int, n: int) -> Array:
	var out: Array = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element_enum() != 元素:
			continue
		p.add_hand_cards([c.id])
		out.append(c.id)
		if out.size() >= n:
			break
	return out


func _放末日(预言: Array = []) -> void:
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 预言.size(), "counter_max": 6, "state": 0, "pile": 预言})


func _场卡(名: String) -> Dictionary:
	return 引擎.取场卡(名) if 引擎.有场卡(名) else {}


# ============================================================
# 1. 异端邪说：开局 +1 水晶；【末日预言】在场时手牌上限 -1
# ============================================================
func _检开局与手牌上限() -> void:
	_建引擎()
	检(玩家1.crystal == 1, "【异端邪说】开局应 +1 水晶：%d" % 玩家1.crystal)
	_放末日([101])
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == GConst.HAND_CARDS_MAX - 1,
		"【末日预言】在场时手牌上限应 -1：%d" % 玩家1.hand_cards_max)
	引擎.移除场卡("末日预言")
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == GConst.HAND_CARDS_MAX,
		"【末日预言】离场后手牌上限应恢复：%d" % 玩家1.hand_cards_max)


# ============================================================
# 2. 献祭：同系 → 移除该预言、+1 宝石
# ============================================================
func _检献祭同系() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	var 两张: Array = _发牌(玩家1, GConst.CardElement.Wind, 2)
	_放末日(两张)
	var rc: int = 角色.p_magic_skill({"action_id": 9503, "src_id": 1})
	检(rc == BattleRole.URGENT, "【献祭】应压入展示流程并返回 URGENT")
	引擎.run()
	检(引擎._await_id == 1, "【献祭】应先问系别（等待 %s）" % str(引擎._await_id))
	_应答([GConst.CardElement.Wind])
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	检(int(表.get("pile", []).size()) == 1, "同系应移除 1 张【预言】：%d" % int(表.get("pile", []).size()))
	检(引擎.team_gem[GConst.BLUE] == 1, "同系应让战绩区 +1【宝石】")
	检(引擎.deck.discard.has(int(两张[1])), "被移除的【预言】应进弃牌堆")


# ============================================================
# 3. 献祭：异系 → 与牌库顶交换、该【预言】加入手牌
# ============================================================
func _检献祭异系() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	var 风: Array = _发牌(玩家1, GConst.CardElement.Wind, 1)
	var 牌库顶前: int = int(引擎.deck.pile.back())
	_放末日([int(风[0])])
	角色.p_magic_skill({"action_id": 9503, "src_id": 1})
	引擎.run()
	_应答([GConst.CardElement.Fire])
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	var 堆: Array = 表.get("pile", [])
	检(堆.size() == 1, "异系交换后【预言】堆应仍是 1 张：%d" % 堆.size())
	检(int(堆.back()) == 牌库顶前, "交换后堆顶应是原牌库顶那张：%d / %d" % [int(堆.back()), 牌库顶前])
	检(玩家1.有手牌(int(风[0])), "异系的【预言】应加入你手牌")
	检(引擎.team_gem[GConst.BLUE] == 0, "异系不应 +宝石")


# ============================================================
# 4. 翻面 + 天雷劫火「展示时」（无贪婪）
# ============================================================
func _检翻面天雷() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	玩家1.set_gem(0)
	var 雷: Array = _发牌(玩家1, GConst.CardElement.Thunder, 2)
	var 敌雷: Array = _发牌(玩家2, GConst.CardElement.Thunder, 1)
	var 敌手牌前: int = 玩家2.hand_cards.size()
	_放末日([])
	角色._检查预言取空()
	引擎.run()
	检(引擎._await_id == 1, "【预言】取空后应问翻面（等待 %s）" % str(引擎._await_id))
	_应答([1])          # 1 = 天雷劫火
	引擎.run()
	检(引擎.有场卡("天雷劫火") and not 引擎.有场卡("末日预言"),
		"翻面后场卡应变成【天雷劫火】")
	检(引擎._await_id == 1, "能量为 0 时应跳过贪婪、直接问系别")
	_应答([GConst.CardElement.Thunder])
	引擎.run()
	检(引擎._await_id == 1, "选完系别应问弃几张该系牌（等待 %s）" % str(引擎._await_id))
	_应答([], [], 雷)
	引擎.run()
	检(引擎._await_id == 1, "弃牌后应问目标对手（等待 %s）" % str(引擎._await_id))
	_应答([], [2])
	引擎.run()
	检(引擎._await_id == 2, "应问目标对手弃任意张该系牌（等待 %s / %s）"
		% [str(引擎._await_id), str(引擎._await_kind)])
	_应答([], [], 敌雷)
	_收伤害()
	检(引擎.deck.discard.has(int(敌雷[0])), "目标对手弃掉的牌应进弃牌堆")
	检(玩家2.hand_cards.size() == 敌手牌前 - 1 + 3,
		"目标应弃 1 张、再因 3 点法术伤害摸 3 张：%d → %d"
		% [敌手牌前, 玩家2.hand_cards.size()])
	检(玩家1.hand_cards.size() == 雷.size() - 2 + 2, "你弃 2 张再摸 2 张")
	检(引擎.有场卡("天雷劫火"), "展示结算完后【天雷劫火】应留在场上（等灾殃止息移除）")


# ============================================================
# 5. 贪婪：两项都发动、顺序由玩家选
# ============================================================
func _检贪婪两项() -> void:
	_建引擎()
	检(玩家1.get_energy() >= 1, "开局应有 1 点能量可供【贪婪】")
	var 敌手牌前: int = 玩家2.hand_cards.size()
	_放末日([])
	角色._检查预言取空()
	引擎.run()
	_应答([1])          # 天雷劫火
	引擎.run()
	检(引擎._await_id == 1, "有能量时应先问是否发动【贪婪】（等待 %s）" % str(引擎._await_id))
	_应答([1])          # 发动贪婪
	引擎.run()
	检(玩家1.get_energy() == 0, "【贪婪】应消耗 1 点能量")
	检(引擎._await_id == 1, "贪婪应再问两项顺序（等待 %s）" % str(引擎._await_id))
	_应答([1])          # 先雷后火
	# 两项都不弃牌（手里没有该系牌）：各造成 X+1 = 1 点法术伤害。
	# 中间可能插入目标方的「治疗抵挡」询问，必须先答掉、等到真正问目标时才提交。
	for i: int in range(2):
		检(_等到目标询问(), "第 %d 项应问目标对手（等待 %s / 号 %s）"
			% [i + 1, str(引擎._await_id), str(引擎._pending_respond_id)])
		_应答([], [2])
	_收伤害()
	检(玩家2.hand_cards.size() == 敌手牌前 + 2,
		"两项各 1 点伤害，目标应摸 2 张：%d → %d" % [敌手牌前, 玩家2.hand_cards.size()])
	检(引擎.有场卡("天雷劫火"), "两项结算完后场卡仍在")


# ============================================================
# 6. 灾殃止息：异教徒回合开始移除天雷 / 地裂
# ============================================================
func _检灾殃止息() -> void:
	_建引擎()
	引擎.加场卡({"id": "天雷劫火", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 0, "state": 1})
	引擎.加场卡({"id": "地裂波涛", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 0, "state": 2})
	角色.p_before_turn_begin({"player": 1})
	检(not 引擎.有场卡("天雷劫火") and not 引擎.有场卡("地裂波涛"),
		"【灾殃止息】应移除【天雷劫火】/【地裂波涛】")
	var 有通知: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Skill and int((r["data"] as Dictionary).get("skill_id", 0)) == 9509:
			有通知 = true
	检(有通知, "【灾殃止息】移除时应播技能通知")


# ============================================================
# 7. 放逐：无视手牌上限摸 6、6 张手牌作【预言】、额外行动
# ============================================================
func _检放逐() -> void:
	_建引擎()
	# 手里没有牌、场上没有【末日预言】（手牌上限 6）：摸 6 张不会触发超限，
	# 单看放逐本身的流程；「无视手牌上限」另外用引擎入口单独验。
	检(玩家1.hand_cards.is_empty(), "放逐前手牌应为空")
	var rc: int = 角色.p_magic_skill({"action_id": 9505, "src_id": 1})
	检(rc == BattleRole.URGENT, "【放逐】应进入摸牌流程")
	引擎.run()
	检(引擎._await_id == 1, "【放逐】应先问摸几张（等待 %s）" % str(引擎._await_id))
	_应答([6])
	引擎.run()
	检(引擎._await_id == 1, "摸完牌后应问额外行动（等待 %s）" % str(引擎._await_id))
	var 表: Dictionary = _场卡("末日预言")
	检(int(表.get("pile", []).size()) == 6, "应把 6 张手牌面朝下作为【预言】：%d"
		% int(表.get("pile", []).size()))
	检(玩家1.hand_cards.is_empty(), "6 张手牌变成【预言】后手牌应为空：%d" % 玩家1.hand_cards.size())
	_应答([GConst.ActionType.Attack])
	引擎.run()
	var 有额外: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 9505:
			有额外 = true
	检(有额外, "【放逐】应给 1 份额外行动")
	检(玩家1.get_energy() == 0, "【放逐】应消耗 1 点能量")



extends 自检用例
## F4 基础效果目标 / 触发钩子：
## - v_basic_effect_target（默认成功）：目标角色自己判定能不能被放上基础效果；
##   引擎在【圣盾】/【虚弱】/【中毒】的出牌校验、技能行动的基础效果放置声明
##   （BattleRole.basic_effect_placements）与 add_basic_effect 兜底里统一走它，
##   被拒时必须在扣牌 / 挂效果之前拦下（4601 可用）。
## - p_basic_effect_triggered：基础效果因自身效果被触发、且这次效果结算完成后触发一次；
##   p_basic_effect_change 的 remove 带 triggered=true 供角色区分「触发」与「被拿走」（4604 可用）。
## - 触发点覆盖：中毒结算、虚弱结算、圣盾挡下攻击、封印 / 赐福这类「cause＝牌自身技能号」的消耗；
##   「被拿走」的移除（cause 是拿走者的技能号）不算触发。
## - 4602 可用：放置基础效果后 p_basic_effect_change(add=true, doer=放置者) 照常送达。
## - 不回归：普通角色仍能正常放圣盾 / 虚弱 / 中毒，新增钩子不影响既有路径。

## 地之封印：放在目标面前的基础效果，牌上带该技能号（触发时 cause 就是它）
const 地之封印技能号: int = 404
## 威力赐福：同为牌载基础效果（验证赐福类触发也能被自动识别）
const 威力赐福技能号: int = 1602


## dummy 目标免疫角色：模拟 46 的 4601「你无法成为基础效果的目标」
class 免疫角色:
	extends BattleRole

	## 每次被问到目标资格时的记录 [{dst, card}]，用来确认引擎确实走了这个钩子
	var 被问记录: Array = []

	func v_basic_effect_target(dst: BattlePlayer, card_id: int) -> int:
		被问记录.append({"dst": dst.id if dst != null else -1, "card": card_id})
		return GConst.GE_INVALID_PLAYERID


## dummy 观察角色：记录基础效果变动 / 触发与伤害结算的先后（模拟 4602 / 4604 要做的事）
class 观察角色:
	extends BattleRole

	## 按发生顺序记录的事件（change_add / change_remove / triggered / harm_end / timeline2_miss）
	var 事件: Array = []
	var 触发记录: Array = []
	var 变动记录: Array = []
	## 自己放置基础效果后的记录（4602 的口径：ctx.add=true 且 doer＝自己）
	var 自己放置记录: Array = []
	## 最近一次触发时，基础效果拥有者的手牌数（验证虚弱触发时牌已经摸到手）
	var 触发时拥有者手牌数: int = -1

	func p_basic_effect_change(ctx: Dictionary) -> int:
		变动记录.append(ctx.duplicate())
		事件.append("change_add" if bool(ctx.get("add", false)) else "change_remove")
		if bool(ctx.get("add", false)) and int(ctx.get("doer", -1)) == player.id:
			自己放置记录.append(ctx.duplicate())
		return SUCCESS

	func p_basic_effect_triggered(ctx: Dictionary) -> int:
		触发记录.append(ctx.duplicate())
		事件.append("triggered")
		var 拥有者: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
		if 拥有者 != null:
			触发时拥有者手牌数 = 拥有者.hand_cards.size()
		return SUCCESS

	func p_harm_end(_ctx: Dictionary) -> int:
		事件.append("harm_end")
		return SUCCESS

	func p_timeline_2_miss(_ctx: Dictionary) -> int:
		事件.append("timeline2_miss")
		return SUCCESS


## dummy 放置技能角色：验证技能行动「会把牌放到谁面前」也走同一套目标资格校验
class 放牌技能角色:
	extends BattleRole

	const 技能号: int = 9401

	func basic_effect_placements(action: Dictionary) -> Array:
		if int(action.get("action_id", 0)) != 技能号:
			return []
		var cards: Array = action.get("card_ids", [])
		var dsts: Array = action.get("dst_ids", [])
		if cards.is_empty() or dsts.is_empty():
			return []
		return [{"card": int(cards[0]), "dst": int(dsts[0])}]

	func v_magic_skill(action: Dictionary) -> int:
		if int(action.get("action_id", 0)) != 技能号:
			return GConst.GE_EMPTY_HANDLE
		var cards: Array = action.get("card_ids", [])
		if cards.is_empty() or not player.has_hand_card(int(cards[0])):
			return GConst.GE_INVALID_CARDID
		return GConst.GE_SUCCESS

	func p_magic_skill(action: Dictionary) -> int:
		var cards: Array = action.get("card_ids", [])
		var dsts: Array = action.get("dst_ids", [])
		if cards.is_empty() or dsts.is_empty():
			return SUCCESS
		engine.add_basic_effect(int(dsts[0]), int(cards[0]), player.id, 技能号)
		engine.take_from_hand(player.id, [int(cards[0])], true)
		engine._broadcast_game()
		return URGENT


var 引擎: BattleEngine = null
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 玩家3: BattlePlayer = null
var 玩家4: BattlePlayer = null
var 观察: 观察角色 = null
var 免疫: 免疫角色 = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []
var 圣盾牌: GCard = null
var 虚弱牌: GCard = null
var 中毒牌: GCard = null
var 攻击牌: GCard = null
var 封印牌: GCard = null
var 赐福牌: GCard = null


func _init() -> void:
	名称 = "基础效果目标与触发钩子"


# ============================================================
# 取样 / 断言工具
# ============================================================
## 卡库里第一张指定卡名的非虚拟牌
func _取卡名(卡名: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.card_name_enum() == 卡名:
			return c
	return null


## 卡库里第一张带指定技能号的非虚拟牌
func _取带技能牌(技能号: int, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and not 排除.has(c.id) and c.has_skill_id(技能号):
			return c
	return null


## 卡库里第一张非暗系攻击牌（暗系攻击无法应战，这里要能走到圣盾抵挡）
func _取攻击牌() -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() == GConst.CardElement.Darkness:
			continue
		return c
	return null


## 是否给某玩家发过「操作无效」错误
func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == pid and int(r["msg"]) == GConst.Msg.ErrorInput:
			return true
	return false


## 发送记录里有没有一条「基础效果被移除」日志：带指定牌面、且 triggered 与期望一致
func _有基础效果移除日志(牌面: int, 触发: bool) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Gossip:
			continue
		var d: Dictionary = r["data"]
		if int(d.get("card", -1)) == 牌面 and bool(d.get("triggered", false)) == 触发:
			return true
	return false


## 观察记录里某事件第一次出现的下标（没有返回 -1）
func _事件位置(名称: String) -> int:
	for i: int in range(观察.事件.size()):
		if str(观察.事件[i]) == 名称:
			return i
	return -1


## 清空战斗状态：回到「轮到玩家 1、行动阶段、无手牌 / 无基础效果」的同一起点
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.测试跳过回合 = -1
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.additional_actions.clear()
		p0.reset_action_counts()
	观察.事件.clear()
	观察.触发记录.clear()
	观察.变动记录.clear()
	观察.自己放置记录.clear()
	观察.触发时拥有者手牌数 = -1
	免疫.被问记录.clear()


## 把一个角色的手牌换成指定的几张
func _换手牌(p0: BattlePlayer, cards: Array) -> void:
	p0.hand_cards.clear()
	for c: Variant in cards:
		p0.hand_cards.append(int(c))


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)
	圣盾牌 = _取卡名(GConst.CardName.Shield)
	虚弱牌 = _取卡名(GConst.CardName.Weaken)
	中毒牌 = _取卡名(GConst.CardName.Poison)
	攻击牌 = _取攻击牌()
	封印牌 = _取带技能牌(地之封印技能号)
	赐福牌 = _取带技能牌(威力赐福技能号)
	检(圣盾牌 != null and 虚弱牌 != null and 中毒牌 != null, "卡库里找不到圣盾 / 虚弱 / 中毒")
	检(攻击牌 != null, "卡库里找不到非暗系攻击牌")
	检(封印牌 != null, "卡库里找不到 404 地之封印的牌")
	检(赐福牌 != null, "卡库里找不到 1602 威力赐福的牌")
	if 圣盾牌 == null or 虚弱牌 == null or 中毒牌 == null or 攻击牌 == null \
			or 封印牌 == null or 赐福牌 == null:
		return

	# 4 人交替座次：1 / 4 蓝，2 / 3 红；1 号挂观察 dummy（记录所有钩子），2 号待挂免疫 dummy
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "观察者")
	引擎.add_player(2, GConst.RED, "免疫者")
	引擎.add_player(3, GConst.RED, "普通对手")
	引擎.add_player(4, GConst.BLUE, "队友")
	引擎.start_with_roles({})
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	玩家3 = 引擎.p(3)
	玩家4 = 引擎.p(4)
	观察 = 观察角色.new()
	观察.setup(玩家1, 引擎)
	玩家1.role = 观察
	免疫 = 免疫角色.new()
	免疫.setup(玩家2, 引擎)
	玩家2.role = 免疫
	_重置战斗()

	# ---- 场景 1：目标资格（4601）默认成功 / 免疫角色拒绝 ----
	检(引擎.v_basic_effect_target(2, 圣盾牌.id) == GConst.GE_INVALID_PLAYERID,
		"免疫角色面前的基础效果目标资格应被拒绝")
	检(引擎.v_basic_effect_target(3, 圣盾牌.id) == GConst.GE_SUCCESS,
		"普通角色的基础效果目标资格应默认成功")
	检(玩家2.v_basic_effect_target(圣盾牌.id) == GConst.GE_INVALID_PLAYERID,
		"BattlePlayer.v_basic_effect_target 应转发给目标角色")
	检(玩家3.v_basic_effect_target(圣盾牌.id) == GConst.GE_SUCCESS,
		"没有角色脚本的玩家应默认可以成为基础效果目标")
	检(not 免疫.被问记录.is_empty(), "引擎没有把目标资格询问交给目标角色")

	# ---- 场景 2：圣盾 / 虚弱 / 中毒打向免疫目标：扣牌之前驳回、不挂效果 ----
	_重置战斗()
	_换手牌(玩家1, [圣盾牌.id])
	引擎.resolve_action(GConst.ActionType.Magic, {"card_ids": [圣盾牌.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(_有错误输入(1), "把圣盾放到免疫目标身上应被驳回")
	检(玩家1.hand_cards.has(圣盾牌.id), "被驳回的圣盾不应离手")
	检(玩家2.basic_effects.is_empty(), "被驳回的圣盾不应挂到免疫目标面前")
	检(_事件位置("change_add") < 0, "被驳回的圣盾不应触发基础效果变更钩子")

	_重置战斗()
	_换手牌(玩家1, [虚弱牌.id])
	引擎.resolve_action(GConst.ActionType.Magic, {"card_ids": [虚弱牌.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(_有错误输入(1), "把虚弱放到免疫目标身上应被驳回")
	检(玩家1.hand_cards.has(虚弱牌.id), "被驳回的虚弱不应离手")
	检(玩家2.basic_effects.is_empty(), "被驳回的虚弱不应挂到免疫目标面前")

	_重置战斗()
	_换手牌(玩家1, [中毒牌.id])
	引擎.resolve_action(GConst.ActionType.Magic, {"card_ids": [中毒牌.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(_有错误输入(1), "把中毒放到免疫目标身上应被驳回")
	检(玩家1.hand_cards.has(中毒牌.id), "被驳回的中毒不应离手")
	检(玩家2.basic_effects.is_empty(), "被驳回的中毒不应挂到免疫目标面前")

	# 免疫角色自己也不能把基础效果放到自己面前（A14：只挡成为目标，自己也不例外）
	_重置战斗()
	引擎.current_id = 2
	_换手牌(玩家2, [圣盾牌.id])
	引擎.resolve_action(GConst.ActionType.Magic, {"card_ids": [圣盾牌.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(_有错误输入(2), "免疫角色把圣盾放到自己身上应被驳回")
	检(玩家2.hand_cards.has(圣盾牌.id) and 玩家2.basic_effects.is_empty(),
		"自己指定自己时应保持牌与基础效果都不变")

	# add_basic_effect 兜底：即使调用方漏了上游校验，也不能把基础效果挂到免疫目标身上
	检(引擎.add_basic_effect(2, 圣盾牌.id, 1) == GConst.GE_INVALID_PLAYERID,
		"add_basic_effect 应返回目标资格错误码")
	检(玩家2.basic_effects.is_empty(), "add_basic_effect 被拒时不应挂效果")

	# ---- 场景 3：普通目标照常放置；4602 的放置钩子可用 ----
	_重置战斗()
	玩家2.role = null   # 移除免疫角色，让 3 号普通目标的场景不互相干扰
	_换手牌(玩家1, [圣盾牌.id])
	引擎.resolve_action(GConst.ActionType.Magic, {"card_ids": [圣盾牌.id], "dst_ids": [3], "args": []})
	引擎.run()
	检(not _有错误输入(1), "普通目标不应被目标资格校验驳回")
	var 挂上: bool = false
	for 效果: Dictionary in 玩家3.basic_effects:
		if int(效果["card"]) == 圣盾牌.id and int(效果["src"]) == 1:
			挂上 = true
	检(挂上, "普通目标的圣盾应正常挂到基础效果区（来源＝放置者）")
	检(not 玩家1.hand_cards.has(圣盾牌.id), "正常放置的圣盾应离手")
	var 放置变动: Dictionary = 观察.变动记录[-1] if not 观察.变动记录.is_empty() else {}
	检(bool(放置变动.get("add", false)), "放置基础效果应触发 p_basic_effect_change(add=true)")
	检(int(放置变动.get("dst", -1)) == 3 and int(放置变动.get("doer", -1)) == 1,
		"4602 需要的放置钩子上下文不对：%s" % str(放置变动))
	检(int(放置变动.get("card", -1)) == 圣盾牌.id and int(放置变动.get("cause", -1)) == GConst.CAUSE_USE,
		"放置钩子应带基础效果牌号与来源：%s" % str(放置变动))
	检(not bool(放置变动.get("triggered", false)), "放置不是触发，triggered 应为 false")
	检(观察.自己放置记录.size() == 1, "4602 的「自己放置后」记录应为 1 条")
	# 普通移除（不是触发）不带 triggered
	引擎.remove_basic_effect(3, 圣盾牌.id, GConst.CAUSE_USE, 1)
	引擎.run()
	检(观察.变动记录.size() >= 2 and not bool(观察.变动记录[-1].get("add", true)),
		"移除基础效果应触发 p_basic_effect_change(add=false)")
	检(not bool(观察.变动记录[-1].get("triggered", true)), "被拿走的普通移除不应标成触发")
	检(观察.触发记录.is_empty(), "普通移除不应触发 p_basic_effect_triggered")

	# ---- 场景 4：圣盾挡下攻击 = 触发，且触发通知在落空结算之后 ----
	_重置战斗()
	检(引擎.add_basic_effect(2, 圣盾牌.id, 1) == GConst.GE_SUCCESS, "普通目标应能放上圣盾")
	引擎.run()
	观察.事件.clear()
	观察.触发记录.clear()
	观察.变动记录.clear()
	_换手牌(玩家1, [攻击牌.id])
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [攻击牌.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(引擎._await_id == 2, "攻击宣告后应等玩家 2 应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(玩家2.basic_effects.is_empty(), "圣盾挡下攻击后应被移除")
	检(_有基础效果移除日志(圣盾牌.id, true),
		"圣盾抵挡时应广播带牌面 + triggered 的移除日志（客户端据此播盾牌音效）")
	检(引擎.deck.discard.has(圣盾牌.id), "挡下攻击的圣盾应进弃牌堆")
	检(观察.触发记录.size() == 1, "圣盾挡下攻击应触发一次 p_basic_effect_triggered")
	var 盾触发: Dictionary = 观察.触发记录[0] if not 观察.触发记录.is_empty() else {}
	检(int(盾触发.get("dst", -1)) == 2 and int(盾触发.get("card", -1)) == 圣盾牌.id,
		"圣盾触发上下文应指向目标与圣盾牌：%s" % str(盾触发))
	检(int(盾触发.get("doer", 0)) == -1, "引擎内部结算的圣盾触发 doer 应为 -1")
	检(_事件位置("change_remove") >= 0 and _事件位置("triggered") > _事件位置("change_remove"),
		"触发通知应在基础效果变更之后：%s" % str(观察.事件))
	检(_事件位置("timeline2_miss") >= 0 and _事件位置("triggered") > _事件位置("timeline2_miss"),
		"触发通知应在本次落空结算之后：%s" % str(观察.事件))

	# ---- 场景 5：中毒在回合开始结算 = 触发，且伤害结算完成后才通知 ----
	_重置战斗()
	检(引擎.add_basic_effect(2, 中毒牌.id, 1) == GConst.GE_SUCCESS, "普通目标应能放上中毒")
	引擎.run()
	观察.事件.clear()
	观察.触发记录.clear()
	观察.变动记录.clear()
	引擎.current_id = 2
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	检(玩家2.basic_effects.is_empty(), "中毒结算后应从目标面前移除")
	检(引擎.deck.discard.has(中毒牌.id), "结算后的中毒牌应进弃牌堆")
	检(观察.触发记录.size() == 1, "中毒结算应触发一次 p_basic_effect_triggered")
	var 毒触发: Dictionary = 观察.触发记录[0] if not 观察.触发记录.is_empty() else {}
	检(int(毒触发.get("dst", -1)) == 2 and int(毒触发.get("card", -1)) == 中毒牌.id,
		"中毒触发上下文应指向目标与中毒牌：%s" % str(毒触发))
	检(int(毒触发.get("cause", 0)) == GConst.CAUSE_POISON, "中毒触发来源应为 CAUSE_POISON")
	检(_事件位置("harm_end") >= 0 and _事件位置("triggered") > _事件位置("harm_end"),
		"中毒触发通知应在伤害结算完成之后：%s" % str(观察.事件))
	检(not 观察.变动记录.is_empty() and bool(观察.变动记录[-1].get("triggered", false)),
		"中毒的这次移除应在变更钩子里标成 triggered=true")

	# ---- 场景 6：虚弱在回合开始结算 = 触发，摸牌结算完成后才通知 ----
	_重置战斗()
	检(引擎.add_basic_effect(2, 虚弱牌.id, 1) == GConst.GE_SUCCESS, "普通目标应能放上虚弱")
	引擎.run()
	观察.事件.clear()
	观察.触发记录.clear()
	观察.变动记录.clear()
	引擎.current_id = 2
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	检(引擎._await_id == 2, "虚弱应询问玩家 2 是否摸牌取消（等待 %s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Weaken, "src_id": 2,
		"args": [1], "card_ids": [], "dst_ids": [],
	})
	检(玩家2.basic_effects.is_empty(), "虚弱结算后应从目标面前移除")
	检(引擎.deck.discard.has(虚弱牌.id), "结算后的虚弱牌应进弃牌堆")
	检(观察.触发记录.size() == 1, "虚弱结算应触发一次 p_basic_effect_triggered")
	检(观察.触发时拥有者手牌数 == 3,
		"虚弱触发通知应在摸牌之后（触发时手牌 %d，应为 3）" % 观察.触发时拥有者手牌数)
	检(观察.事件.size() >= 2 and str(观察.事件[-1]) == "triggered",
		"虚弱的触发通知应是最后一步：%s" % str(观察.事件))
	检(not 观察.变动记录.is_empty() and bool(观察.变动记录[-1].get("triggered", false)),
		"虚弱的这次移除应在变更钩子里标成 triggered=true")

	# ---- 场景 7：封印 / 赐福这类「cause＝牌自身技能号」的移除自动识别为触发 ----
	_重置战斗()
	检(引擎.add_basic_effect(2, 封印牌.id, 1, 地之封印技能号) == GConst.GE_SUCCESS,
		"普通目标应能放上地之封印")
	引擎.run()
	观察.触发记录.clear()
	观察.变动记录.clear()
	# 封印 helper 的触发点就是这个写法：cause＝牌自身带的封印技能号
	引擎.remove_basic_effect(2, 封印牌.id, 地之封印技能号, 1)
	引擎.run()
	检(观察.触发记录.size() == 1, "封印被自身技能号触发时应发 p_basic_effect_triggered")
	var 封触发: Dictionary = 观察.触发记录[0] if not 观察.触发记录.is_empty() else {}
	检(int(封触发.get("dst", -1)) == 2 and int(封触发.get("doer", -1)) == 1,
		"封印触发上下文不对：%s" % str(封触发))
	检(bool(观察.变动记录[-1].get("triggered", false)), "封印的触发移除应标成 triggered=true")
	# 被拿走（cause＝拿走者的技能号，不是牌自身技能号）不算触发
	检(引擎.add_basic_effect(3, 封印牌.id, 1, 地之封印技能号) == GConst.GE_SUCCESS,
		"普通目标应能再放一张地之封印")
	引擎.run()
	观察.触发记录.clear()
	观察.变动记录.clear()
	引擎.remove_basic_effect(3, 封印牌.id, GConst.技能_封印破碎, 1)
	引擎.run()
	检(观察.触发记录.is_empty(), "被【封印破碎】拿走的基础效果不应算触发")
	检(not bool(观察.变动记录[-1].get("triggered", true)),
		"被拿走的移除不应标成 triggered=true")
	# 赐福类（1602）同样按牌自身技能号识别触发
	检(引擎.add_basic_effect(3, 赐福牌.id, 1, 威力赐福技能号) == GConst.GE_SUCCESS,
		"普通目标应能放上威力赐福")
	引擎.run()
	观察.触发记录.clear()
	引擎.remove_basic_effect(3, 赐福牌.id, 威力赐福技能号, 1)
	引擎.run()
	检(观察.触发记录.size() == 1, "赐福被自身技能号触发时应发 p_basic_effect_triggered")

	# ---- 场景 8：技能行动声明「把牌放到谁面前」也走同一套目标资格校验 ----
	_重置战斗()
	var 放牌角色: 放牌技能角色 = 放牌技能角色.new()
	放牌角色.setup(玩家1, 引擎)
	玩家1.role = 放牌角色
	免疫.setup(玩家2, 引擎)
	玩家2.role = 免疫
	_换手牌(玩家1, [封印牌.id])
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"action_id": 放牌技能角色.技能号, "card_ids": [封印牌.id], "dst_ids": [2], "args": [],
	})
	引擎.run()
	检(_有错误输入(1), "技能把基础效果放向免疫目标应被驳回")
	检(玩家1.hand_cards.has(封印牌.id), "被驳回的技能不应扣掉发动牌")
	检(玩家2.basic_effects.is_empty(), "被驳回的技能不应挂上基础效果")
	检(not 免疫.被问记录.is_empty(), "技能行动的基础效果放置没有走目标资格校验")
	# 换普通目标后同一技能应通过（技能自己的 v_magic_skill 也要能跑）
	_重置战斗()
	_换手牌(玩家1, [封印牌.id])
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"action_id": 放牌技能角色.技能号, "card_ids": [封印牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(not _有错误输入(1), "普通目标不应被技能行动的目标资格校验驳回")
	var 技能挂上: bool = false
	for 效果: Dictionary in 玩家3.basic_effects:
		if int(效果["card"]) == 封印牌.id and int(效果["src"]) == 1:
			技能挂上 = true
	检(技能挂上, "技能放置的基础效果应正常挂到普通目标面前")
	检(not 玩家1.hand_cards.has(封印牌.id), "技能放置成功后发动牌应离手")

	# 收尾：清掉状态栈与等待，避免退出时残留询问
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()

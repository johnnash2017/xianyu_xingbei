extends 自检用例
## F6 伤害转移 / 弃牌拦截（spike）：
## - ⑥ 伤害转移：p_timeline_6 里把本次伤害改由自己承受，并声明「这次伤害」不因手牌超限掉士气；
##   治疗回应已过，之后的摸牌 / 超限弃牌都按新目标走，原目标不再摸牌。
## - 转移后的后续伤害钩子：p_timeline_6_drawn / p_harm_end 的 ctx 由引擎在触发时按 harm 现算，
##   ctx.dst / ctx.harm.dst 必须都是新目标、harm["redirect_from"] 记录原目标；原目标不再被当成目标
##   （dummy 角色各挂一个，按 ctx.dst 是否等于自己判断「触发」）。
## - 弃牌前拦截：to_discard(cards, ctx) 在有角色 wants_before_discard 时推迟成 p_before_discard 钩子
##   （可等待玩家），认领的牌不进弃牌堆、加进认领者手牌；无人响应时保持原来的同步弃牌。
## - 边界：免士气只作用于这次伤害（普通超限照旧掉士气）；拦截不重复触发、拦截代价的弃牌不递归拦截；
##   非【魔弹】 / 非队友 / 未知牌主 / 玩家拒绝 / 弃不出代价 都不拦截。

## dummy 伤害转移角色（模拟 4702）：队友（不含自己）承受伤害时，把这次伤害转给自己。
class 转移角色:
	extends BattleRole

	## 是否响应（false 用来验证「没有转移时由原目标正常掉士气」）
	var 启用: bool = true
	## 是否声明「本次伤害不掉士气」
	var 免士气: bool = true
	## 每次转移的记录 {from, to, point}
	var 转移记录: Array = []
	## 转移失败次数（非法目标等）
	var 失败次数: int = 0
	## p_timeline_6_drawn / p_harm_end 看到的上下文 [{hook, dst, harm_dst, redirect_from}]
	var 钩子记录: Array = []
	## 上面两个钩子里 ctx.dst == 自己的次数（验证引擎把转移后的新目标当成目标）
	var 命中次数: int = 0

	func p_timeline_6(ctx: Dictionary) -> int:
		var harm: Dictionary = ctx.get("harm", {})
		var 原目标: BattlePlayer = engine.p(int(harm.get("dst", -1)))
		# 只接「队友正在承受」的伤害；自己已经是目标时不能再转给自己
		if 原目标 == null or 原目标.color != player.color or 原目标.id == player.id:
			return SUCCESS
		if not 启用 or int(harm.get("point", 0)) <= 0:
			return SUCCESS
		var rc: int = 转移伤害(harm, player.id, 免士气)
		if rc != GConst.GE_SUCCESS:
			失败次数 += 1
			return SUCCESS
		转移记录.append({"from": 原目标.id, "to": player.id, "point": int(harm.get("point", 0))})
		return SUCCESS

	## 摸牌 / 超限结算之后：引擎应在这里按转移后的 harm 现算 ctx
	func p_timeline_6_drawn(ctx: Dictionary) -> int:
		_记钩子("drawn", ctx)
		return SUCCESS

	## 伤害流水线末尾：同样要看到转移后的最终目标
	func p_harm_end(ctx: Dictionary) -> int:
		_记钩子("end", ctx)
		return SUCCESS

	func _记钩子(hook: String, ctx: Dictionary) -> void:
		var harm: Dictionary = ctx.get("harm", {})
		钩子记录.append({
			"hook": hook,
			"dst": int(ctx.get("dst", -1)),
			"harm_dst": int(harm.get("dst", -1)),
			"redirect_from": int(harm.get("redirect_from", -1)),
		})
		if int(ctx.get("dst", -1)) == player.id:
			命中次数 += 1


## dummy「原目标」观察角色：挂在原伤害目标身上，记录 p_timeline_6_drawn / p_harm_end 的上下文。
## 两个钩子对全体角色都会调用，但转移后 ctx.dst 已不是原目标，按 ctx.dst 判断的角色不应触发。
class 伤害钩子观察角色:
	extends BattleRole

	var 钩子记录: Array = []
	var 命中次数: int = 0

	func p_timeline_6_drawn(ctx: Dictionary) -> int:
		_记钩子("drawn", ctx)
		return SUCCESS

	func p_harm_end(ctx: Dictionary) -> int:
		_记钩子("end", ctx)
		return SUCCESS

	func _记钩子(hook: String, ctx: Dictionary) -> void:
		var harm: Dictionary = ctx.get("harm", {})
		钩子记录.append({
			"hook": hook,
			"dst": int(ctx.get("dst", -1)),
			"harm_dst": int(harm.get("dst", -1)),
			"redirect_from": int(harm.get("redirect_from", -1)),
		})
		if int(ctx.get("dst", -1)) == player.id:
			命中次数 += 1


## dummy 弃牌拦截角色（模拟 4704）：队友手牌 / 盖牌里的【魔弹】进弃牌前，弃 1 张牌获得它。
class 拦截角色:
	extends BattleRole

	const 技能号: int = 9901

	## wants_before_discard 被调次数
	var 预判次数: int = 0
	## p_before_discard 被调次数
	var 钩子次数: int = 0
	## 真正问玩家的次数
	var 询问次数: int = 0
	## 收到的上下文（每次拦截询问一条）
	var 上下文记录: Array = []
	## false＝玩家在询问里选不发动
	var 同意: bool = true

	func wants_before_discard(ctx: Dictionary) -> bool:
		预判次数 += 1
		var 牌主: BattlePlayer = engine.p(int(ctx.get("owner", -1)))
		# 只拦队友（不含自己）的牌；已经有人认领就不再抢
		if 牌主 == null or 牌主.color != player.color or 牌主.id == player.id:
			return false
		if int(ctx.get("taker", -1)) >= 0:
			return false
		return _有魔弹(ctx.get("cards", []))

	func _有魔弹(cards: Array) -> bool:
		for c: Variant in cards:
			var 牌: GCard = Data.get_card(int(c))
			if 牌 != null and 牌.card_name_enum() == GConst.CardName.Missile:
				return true
		return false

	func p_before_discard(ctx: Dictionary) -> int:
		钩子次数 += 1
		if not wants_before_discard(ctx):
			return SUCCESS
		if step == 0:
			上下文记录.append(ctx.duplicate())
			step = 1
			询问次数 += 1
			# 弃 1 张手牌为代价：选牌交给客户端；测试直接走同一个询问入口
			engine.ask_skill(player.id, 技能号, 1, 0, GConst.CardSource.Hand)
			return WAIT
		step = 0
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if not 同意 or args.is_empty() or int(args[0]) != 1:
			return SUCCESS
		var 代价: Array = []
		for c: Variant in r.get("card_ids", []):
			if 代价.is_empty() and player.has_discard_card(int(c)):
				代价.append(int(c))
		if 代价.is_empty():
			return SUCCESS
		# 付代价（钩子期间产生的弃牌不再二次拦截）
		engine.take_from_hand(player.id, 代价)
		engine.to_discard(代价, {"owner": player.id, "source": "hand"})
		for c2: Variant in ctx.get("cards", []):
			var 牌: GCard = Data.get_card(int(c2))
			if 牌 != null and 牌.card_name_enum() == GConst.CardName.Missile:
				ctx["taker"] = player.id
				ctx["taken"] = [int(c2)]
				break
		return SUCCESS


## 测试驱动：在引擎推进中调用 to_discard（to_discard 只在 run 内才走拦截分支）
class 触发弃牌:
	extends RefCounted

	var 牌表: Array
	var 上下文: Dictionary

	func _init(cards: Array, ctx: Dictionary) -> void:
		牌表 = cards
		上下文 = ctx

	func handle(e: BattleEngine) -> int:
		e.to_discard(牌表, 上下文)
		return BattleEngine.CONTINUE


var 引擎: BattleEngine = null
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 玩家3: BattlePlayer = null
var 玩家4: BattlePlayer = null
var 转移: 转移角色 = null
var 原目标观察: 伤害钩子观察角色 = null
var 拦截: 拦截角色 = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "伤害转移与弃牌拦截"


# ============================================================
# 取样 / 断言工具
# ============================================================
## 卡库里第一张指定卡名的非虚拟牌
func _取卡名(卡名: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.card_name_enum() == 卡名:
			return c
	return null


## 卡库里第一张不是指定卡名的非虚拟牌
func _取非卡名(卡名: int, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.card_name_enum() == 卡名 or 排除.has(c.id):
			continue
		return c
	return null


## 连取 数量 张互不相同的非虚拟牌
func _取实体牌号(数量: int, 排除: Array = []) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id) or out.has(c.id):
			continue
		out.append(c.id)
		if out.size() >= 数量:
			break
	return out


func _换手牌(p0: BattlePlayer, cards: Array) -> void:
	p0.hand_cards.clear()
	for c: Variant in cards:
		p0.hand_cards.append(int(c))


## 挂角色：BattlePlayer.role 的 setter 在卸下旧角色时会把它的 player / engine 置空，
## 重新挂同一个实例前必须再 setup 一次（测试里反复换角色，容易踩到）。
func _挂角色(p0: BattlePlayer, 角色: BattleRole) -> void:
	角色.setup(p0, 引擎)
	p0.role = 角色


## 是否有发给某玩家的「操作无效」
func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == pid and int(r["msg"]) == GConst.Msg.ErrorInput:
			return true
	return false


## 清空战斗状态：轮到玩家 1、行动阶段、无手牌 / 无等待
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
	引擎.deck.discard.clear()
	引擎.last_harm_cause = 0
	引擎.last_harm_type = 0
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 10
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.additional_actions.clear()
		p0.cross_num = 0
		p0.reset_action_counts()
		p0.boot_skill_used = false
	转移.转移记录.clear()
	转移.失败次数 = 0
	转移.启用 = true
	转移.免士气 = true
	转移.钩子记录.clear()
	转移.命中次数 = 0
	原目标观察.钩子记录.clear()
	原目标观察.命中次数 = 0
	拦截.预判次数 = 0
	拦截.钩子次数 = 0
	拦截.询问次数 = 0
	拦截.上下文记录.clear()
	拦截.同意 = true


## 解析一次超限弃牌询问：从玩家手里挑 数量 张交给引擎
func _交超限牌(pid: int, 数量: int) -> Array:
	var 玩家: BattlePlayer = 引擎.p(pid)
	var 牌: Array = []
	if 玩家 == null:
		return 牌
	for i: int in range(mini(数量, 玩家.hand_cards.size())):
		牌.append(玩家.hand_cards[i])
	if 引擎._await_id == pid:
		引擎.on_message(pid, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.Discard, "src_id": pid,
			"args": [数量, GConst.CAUSE_OVERLOAD, 数量],
			"card_ids": 牌, "dst_ids": [pid],
		})
	return 牌


## 跑一次伤害：dst 原目标，point 点物理伤害
func _跑伤害(dst: int, point: int) -> void:
	引擎.push_harm({
		"src": 3, "dst": dst, "point": point, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "is_active": true,
	})
	引擎.run()


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "受伤者")
	引擎.add_player(2, GConst.BLUE, "转移者")
	引擎.add_player(3, GConst.RED, "红三")
	引擎.add_player(4, GConst.RED, "红四")
	引擎.start_with_roles({})
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	玩家3 = 引擎.p(3)
	玩家4 = 引擎.p(4)
	转移 = 转移角色.new()
	转移.setup(玩家2, 引擎)
	原目标观察 = 伤害钩子观察角色.new()
	原目标观察.setup(玩家1, 引擎)
	拦截 = 拦截角色.new()
	拦截.setup(玩家2, 引擎)

	_测试伤害转移()
	_测试弃牌拦截()

	# 收尾：清掉状态栈与等待，避免退出时残留询问
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()


# ============================================================
# ⑥ 伤害转移
# ============================================================
func _测试伤害转移() -> void:
	玩家1.role = null
	_挂角色(玩家2, 转移)
	_挂角色(玩家1, 原目标观察)

	# ---- 场景 1：转移成功：摸牌 / 超限弃牌都归新目标，且本次不掉士气 ----
	_重置战斗()
	_换手牌(玩家1, _取实体牌号(4))
	_换手牌(玩家2, _取实体牌号(4, 玩家1.hand_cards))
	var 伤害前弃牌数: int = 引擎.deck.discard_size()
	_跑伤害(1, 4)
	检(引擎._await_id == 2, "转移后应由新目标（2 号）结算手牌超限，实际等待 %s" % str(引擎._await_id))
	检(转移.转移记录.size() == 1, "p_timeline_6 应记录一次伤害转移")
	if not 转移.转移记录.is_empty():
		var 转移记录: Dictionary = 转移.转移记录[0]
		检(int(转移记录.get("from", -1)) == 1 and int(转移记录.get("to", -1)) == 2,
			"转移记录应从 1 号改到 2 号：%s" % str(转移记录))
	_交超限牌(2, 2)
	检(玩家2.hand_cards.size() == 6, "新目标摸 4 张后超限弃 2 张，手牌应剩 6，实际 %d" % 玩家2.hand_cards.size())
	检(玩家1.hand_cards.size() == 4, "原目标不应再摸牌 / 弃牌，手牌应保持 4，实际 %d" % 玩家1.hand_cards.size())
	检(int(引擎.team_morale[GConst.BLUE]) == 10,
		"声明不掉士气后本次超限不应扣士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))
	检(引擎.deck.discard_size() - 伤害前弃牌数 == 2,
		"超限弃的 2 张应进弃牌堆，实际增加 %d" % (引擎.deck.discard_size() - 伤害前弃牌数))
	检(转移.失败次数 == 0, "合法转移不应失败")

	# 转移后的后续伤害钩子：ctx 必须由引擎按转移后的 harm 现算，不能是流水线开头 / p_timeline_6 之前的快照
	var 期望钩子: Array = ["drawn", "end"]
	检(转移.钩子记录.size() == 期望钩子.size(),
		"转移后 p_timeline_6_drawn / p_harm_end 应各触发一次，实际 %d 次" % 转移.钩子记录.size())
	for i: int in range(mini(转移.钩子记录.size(), 期望钩子.size())):
		var 钩子: Dictionary = 转移.钩子记录[i]
		检(str(钩子.get("hook", "")) == str(期望钩子[i]),
			"钩子顺序应为 p_timeline_6_drawn → p_harm_end，第 %d 个是 %s" % [i, str(钩子.get("hook", ""))])
		检(int(钩子.get("dst", -1)) == 2 and int(钩子.get("harm_dst", -1)) == 2,
			"转移后 %s 的 ctx.dst / ctx.harm.dst 都应是新目标 2：%s" % [str(钩子.get("hook", "")), str(钩子)])
		检(int(钩子.get("redirect_from", -1)) == 1,
			"转移后 %s 应带 redirect_from = 原目标 1：%s" % [str(钩子.get("hook", "")), str(钩子)])
	检(转移.命中次数 == 2,
		"新目标应在这两个钩子里各被当成一次目标，实际 %d 次" % 转移.命中次数)
	# 原目标身上的角色仍会收到这两个钩子（对全体角色按座位序调用），但看到的 dst 已是新目标 → 不应触发
	检(原目标观察.钩子记录.size() == 期望钩子.size(),
		"原目标角色也会收到这两个钩子轮次，实际 %d 次" % 原目标观察.钩子记录.size())
	for 钩子2: Dictionary in 原目标观察.钩子记录:
		检(int(钩子2.get("dst", -1)) == 2 and int(钩子2.get("harm_dst", -1)) == 2,
			"原目标看到的 ctx.dst / ctx.harm.dst 应已是新目标 2：%s" % str(钩子2))
	检(原目标观察.命中次数 == 0,
		"转移后原目标不应再被当成伤害目标，实际命中 %d 次" % 原目标观察.命中次数)

	# ---- 场景 2：没有转移时，原目标正常摸牌、超限掉士气（对照组） ----
	_重置战斗()
	玩家2.role = null
	_换手牌(玩家1, _取实体牌号(4))
	_换手牌(玩家2, _取实体牌号(4, 玩家1.hand_cards))
	_跑伤害(1, 4)
	检(引擎._await_id == 1, "没有转移时由原目标（1 号）结算超限，实际等待 %s" % str(引擎._await_id))
	_交超限牌(1, 2)
	检(玩家1.hand_cards.size() == 6, "对照组原目标应摸 4 弃 2，手牌 6，实际 %d" % 玩家1.hand_cards.size())
	检(int(引擎.team_morale[GConst.BLUE]) == 8,
		"对照组超限应正常掉 2 点士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))
	# 对照组：没有发生转移，两个钩子的 dst 应仍是原目标、不能带 redirect_from
	检(原目标观察.钩子记录.size() == 期望钩子.size() and 原目标观察.命中次数 == 2,
		"没有转移时原目标应在这两个钩子里各被当成一次目标，实际 %d 条记录 / %d 次命中"
		% [原目标观察.钩子记录.size(), 原目标观察.命中次数])
	for 钩子3: Dictionary in 原目标观察.钩子记录:
		检(int(钩子3.get("dst", -1)) == 1 and int(钩子3.get("harm_dst", -1)) == 1,
			"没有转移时 ctx.dst / ctx.harm.dst 都应是原目标 1：%s" % str(钩子3))
		检(int(钩子3.get("redirect_from", -1)) == -1,
			"没有转移时不应出现 redirect_from：%s" % str(钩子3))

	# ---- 场景 3：免士气=false 时转移成功，超限仍掉士气 ----
	_重置战斗()
	_挂角色(玩家2, 转移)
	转移.免士气 = false
	_换手牌(玩家1, _取实体牌号(4))
	_换手牌(玩家2, _取实体牌号(4, 玩家1.hand_cards))
	_跑伤害(1, 4)
	_交超限牌(2, 2)
	检(玩家2.hand_cards.size() == 6, "不免士气时新目标仍应弃到 6 张")
	检(int(引擎.team_morale[GConst.BLUE]) == 8,
		"免士气=false 时本次超限应正常掉 2 点士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))

	# ---- 场景 4：新目标手牌不超限：只摸牌，不进超限 ----
	_重置战斗()
	转移.免士气 = true
	_换手牌(玩家1, _取实体牌号(4))
	_换手牌(玩家2, _取实体牌号(2, 玩家1.hand_cards))
	_跑伤害(1, 3)
	检(引擎._await_id == -1, "新目标手牌不超限时不应再弹弃牌询问")
	检(玩家2.hand_cards.size() == 5, "新目标应摸 3 张（2→5），实际 %d" % 玩家2.hand_cards.size())
	检(玩家1.hand_cards.size() == 4, "原目标不应摸牌")
	检(int(引擎.team_morale[GConst.BLUE]) == 10, "没有超限时士气不变")
	检(引擎.deck.discard_size() == 0, "没有超限时弃牌堆不变")

	# ---- 场景 5：非法新目标 / 同一目标 ----
	var 假伤害: Dictionary = {"src": 3, "dst": 1, "point": 2, "cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack}
	检(引擎.转移伤害(假伤害, 99) == GConst.GE_INVALID_PLAYERID, "不存在的玩家不能作为转移目标")
	检(int(假伤害["dst"]) == 1, "转移失败时应保持原目标")
	检(引擎.转移伤害(假伤害, 1) == GConst.GE_SUCCESS, "同一目标重复设置应视为成功")
	检(bool(假伤害.get("no_morale", false)), "转移应带上本次不掉士气标记")

	# ---- 场景 6：这次的免士气不残留：之后普通超限照常掉士气 ----
	_重置战斗()
	玩家2.role = null
	_换手牌(玩家2, _取实体牌号(8))
	引擎.push(BattleEngine.SHandOverflow.new())
	引擎.run()
	检(引擎._await_id == 2, "普通超限应由 2 号选牌")
	_交超限牌(2, 2)
	检(int(引擎.team_morale[GConst.BLUE]) == 8,
		"普通超限仍应掉 2 点士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))
	检(not _有错误输入(2), "转移 / 超限流程不应给玩家发操作无效")


# ============================================================
# 弃牌前拦截
# ============================================================
func _测试弃牌拦截() -> void:
	玩家1.role = null
	_挂角色(玩家2, 拦截)
	var 魔弹: GCard = _取卡名(GConst.CardName.Missile)
	var 普通牌: GCard = _取非卡名(GConst.CardName.Missile)
	var 普通牌2: GCard = _取非卡名(GConst.CardName.Missile, [普通牌.id if 普通牌 != null else -1])
	检(魔弹 != null and 普通牌 != null and 普通牌2 != null, "卡库里找不到【魔弹】或普通牌做拦截用例")

	# ---- 场景 1：队友的【魔弹】进弃牌前被拦截：弃 1 张代价，获得该魔弹 ----
	_重置战斗()
	_换手牌(玩家1, [魔弹.id])
	_换手牌(玩家2, [普通牌.id])
	玩家1.remove_hand_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], {"owner": 1, "source": "hand", "face_up": true}))
	引擎.run()
	检(引擎._await_id == 2, "队友的【魔弹】进弃牌前应询问 2 号是否拦截，实际等待 %s" % str(引擎._await_id))
	检(int(引擎._pending_respond_id) == 拦截角色.技能号, "拦截询问应带拦截技能号")
	检(引擎.deck.discard.is_empty(), "拦截询问期间牌不应已经进弃牌堆")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 拦截角色.技能号, "src_id": 2, "args": [1],
		"card_ids": [普通牌.id], "dst_ids": [],
	})
	检(not 引擎.deck.discard.has(魔弹.id), "被认领的【魔弹】不应进弃牌堆")
	检(引擎.deck.discard.has(普通牌.id), "拦截者支付的代价牌应进弃牌堆")
	检(引擎.deck.discard_size() == 1, "本次弃牌结算后弃牌堆应只有代价牌一张，实际 %d" % 引擎.deck.discard_size())
	检(玩家2.hand_cards.has(魔弹.id), "拦截者应获得被拦截的【魔弹】")
	检(not 玩家2.hand_cards.has(普通牌.id), "拦截者支付的代价牌应离手")
	检(玩家1.hand_cards.is_empty(), "牌主的牌应已离手")
	检(拦截.询问次数 == 1, "同一次弃牌只应询问一次，实际 %d" % 拦截.询问次数)
	检(拦截.上下文记录.size() == 1, "同一次弃牌只应记录一次拦截上下文")
	if not 拦截.上下文记录.is_empty():
		var 上下文: Dictionary = 拦截.上下文记录[0]
		检(int(上下文.get("owner", -1)) == 1, "拦截上下文应带牌主 1：%s" % str(上下文))
		检(str(上下文.get("source", "")) == "hand", "拦截上下文应带来源 hand：%s" % str(上下文))
		检(bool(上下文.get("face_up", false)), "拦截上下文应带正面朝上标记：%s" % str(上下文))
		检(上下文.get("cards", []).has(魔弹.id), "拦截上下文应带待弃的魔弹")

	# ---- 场景 2：玩家拒绝：魔弹正常进弃牌堆 ----
	_重置战斗()
	_换手牌(玩家1, [魔弹.id])
	_换手牌(玩家2, [普通牌.id])
	玩家1.remove_hand_cards([魔弹.id])
	拦截.同意 = false
	引擎.push(触发弃牌.new([魔弹.id], {"owner": 1, "source": "hand"}))
	引擎.run()
	检(引擎._await_id == 2, "拒绝场景也应先询问是否拦截")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 拦截角色.技能号, "src_id": 2, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(引擎.deck.discard.has(魔弹.id), "拒绝拦截后【魔弹】应正常进弃牌堆")
	检(not 玩家2.hand_cards.has(魔弹.id), "拒绝拦截时不应获得魔弹")
	检(玩家2.hand_cards.has(普通牌.id), "拒绝拦截时不应支付代价")

	# ---- 场景 3：同意但交不出代价：不认领，魔弹正常进弃牌堆 ----
	_重置战斗()
	_换手牌(玩家1, [魔弹.id])
	_换手牌(玩家2, [])
	玩家1.remove_hand_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], {"owner": 1, "source": "hand"}))
	引擎.run()
	检(引擎._await_id == 2, "空手拦截场景也应先询问")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 拦截角色.技能号, "src_id": 2, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(引擎.deck.discard.has(魔弹.id), "交不出代价时【魔弹】应正常进弃牌堆")

	# ---- 场景 4：非队友的【魔弹】不拦截（保持同步弃牌） ----
	_重置战斗()
	_换手牌(玩家3, [魔弹.id])
	玩家3.remove_hand_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], {"owner": 3, "source": "hand"}))
	引擎.run()
	检(引擎._await_id == -1 and 引擎.deck.discard.has(魔弹.id), "非队友的牌不应触发拦截")
	检(拦截.钩子次数 == 0, "非队友的牌不应进入 p_before_discard")

	# ---- 场景 5：非【魔弹】不拦截（保持同步弃牌） ----
	_重置战斗()
	_换手牌(玩家1, [普通牌.id])
	玩家1.remove_hand_cards([普通牌.id])
	引擎.push(触发弃牌.new([普通牌.id], {"owner": 1, "source": "hand"}))
	引擎.run()
	检(引擎._await_id == -1 and 引擎.deck.discard.has(普通牌.id), "非魔弹不应触发拦截")
	检(拦截.钩子次数 == 0, "非魔弹不应进入 p_before_discard")

	# ---- 场景 6：未知牌主（没有 owner）不拦截 ----
	_重置战斗()
	引擎.push(触发弃牌.new([魔弹.id], {}))
	引擎.run()
	检(引擎._await_id == -1 and 引擎.deck.discard.has(魔弹.id), "未知牌主的牌不应触发拦截")

	# ---- 场景 7：一次弃多张，只认领其中 1 张【魔弹】，其余正常进弃牌堆 ----
	_重置战斗()
	_换手牌(玩家1, [魔弹.id, 普通牌2.id])
	_换手牌(玩家2, [普通牌.id])
	玩家1.remove_hand_cards([魔弹.id, 普通牌2.id])
	引擎.push(触发弃牌.new([魔弹.id, 普通牌2.id], {"owner": 1, "source": "hand"}))
	引擎.run()
	检(引擎._await_id == 2, "多张弃牌里有魔弹时应询问拦截")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 拦截角色.技能号, "src_id": 2, "args": [1],
		"card_ids": [普通牌.id], "dst_ids": [],
	})
	检(not 引擎.deck.discard.has(魔弹.id), "被认领的魔弹不应进弃牌堆")
	检(引擎.deck.discard.has(普通牌2.id), "同一批里未被认领的牌应正常进弃牌堆")
	检(引擎.deck.discard.has(普通牌.id), "代价牌应进弃牌堆")
	检(玩家2.hand_cards.has(魔弹.id), "拦截者应获得这一张魔弹")

	# ---- 场景 8：盖牌来源的【魔弹】也能拦截 ----
	_重置战斗()
	玩家1.cover_cards.append(魔弹.id)
	玩家1.remove_cover_cards([魔弹.id])
	_换手牌(玩家2, [普通牌.id])
	引擎.push(触发弃牌.new([魔弹.id], {"owner": 1, "source": "cover"}))
	引擎.run()
	检(引擎._await_id == 2, "盖牌里的魔弹进弃牌前也应询问拦截")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 拦截角色.技能号, "src_id": 2, "args": [1],
		"card_ids": [普通牌.id], "dst_ids": [],
	})
	检(not 引擎.deck.discard.has(魔弹.id), "盖牌魔弹被拦截后不应进弃牌堆")
	检(玩家2.hand_cards.has(魔弹.id), "拦截者应获得盖牌里的魔弹")
	if not 拦截.上下文记录.is_empty():
		var 末次上下文: Dictionary = 拦截.上下文记录[-1]
		检(str(末次上下文.get("source", "")) == "cover", "盖牌来源应在拦截上下文里标成 cover")

	检(not _有错误输入(2), "弃牌拦截流程不应给玩家发操作无效")

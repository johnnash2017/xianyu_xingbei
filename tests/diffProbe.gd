extends Node
## 行为差探针（第四轮复核专用）：同一份脚本分别放进「重构前」与「当前」两棵树跑，
## 把「问了什么 / 回了什么 / 发生了什么 / 最后什么状态」转录成文本，两边 diff。
##
## 只用两版都有的 API：
##   BattleEngine.add_player / start_with_roles / push / on_message / run / _states /
##   _清空等待 / _最后询问 / _await_id / p() / send_cb
## 角色钩子按场景直接调用，不碰各版本的内部状态变量。

var 引擎: BattleEngine = null
var 记: Array[String] = []
var 应答序: Array = []
var 应答位: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_场景异象剑()
	_场景英灵召唤()
	_场景军神威光_选一()
	_场景军神威光_选二()
	_场景收魔术()
	_场景法术剥离()
	_场景魔纹融合()
	_场景圣剑()
	print("[PROBE] DONE")
	get_tree().quit(0)


# ---------------- 通用 ----------------

func _新引擎(映射: Dictionary) -> void:
	引擎 = BattleEngine.new()
	记.clear()
	应答位 = 0
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		_录消息(pid, msg, data)
	引擎._rng.seed = 20261111
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles(映射)
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.round_id = 1
	# 开局发牌是随机的：两棵树都清空手牌 / 盖牌，场景自己按需放牌，转录才可比
	for pid: int in [1, 2, 3, 4]:
		var pp: BattlePlayer = 引擎.p(pid)
		if pp != null:
			pp.hand_cards.clear()
			pp.cover_cards.clear()
	# 牌库也固定：否则两棵树洗牌 / 发牌消耗的随机数不同，摸到的牌不一样，state 没法比
	引擎.deck.pile.clear()
	引擎.deck.pile.append_array(range(0, 40))
	引擎.deck.discard.clear()


func _找攻击牌(系: int) -> int:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() and c.element_enum() == 系:
			return c.id
	return -1


func _找法术牌(系: int) -> int:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic() and c.element_enum() == 系:
			return c.id
	return -1


func _答(args: Array, cards: Array = [], dsts: Array = []) -> Dictionary:
	return {"args": args, "cards": cards, "dsts": dsts}


## 调角色钩子，并把它压入的状态跑干净；引擎重入钩子（SUSPEND 回来）也在这里模拟：
## 钩子返回非 SUCCESS 且没有新询问时，继续重入，直到 SUCCESS / 出现询问 / 到上限。
func _调钩子(钩子: Callable) -> void:
	for _i: int in range(20):
		var r: int = int(钩子.call())
		var n: int = 0
		while not 引擎._states.is_empty() and 引擎._await_id < 0 and n < 40:
			n += 1
			引擎.run()
		if 引擎._await_id >= 0:
			return
		if r == 0:
			return


## 按顺序把应答序里的答复喂给引擎；每次喂完都重入一次钩子（相当于引擎重入 SHook）
func _跑(钩子: Callable) -> void:
	_调钩子(钩子)
	var 上限: int = 0
	while 引擎._await_id >= 0 and 上限 < 40:
		上限 += 1
		var pid: int = int(引擎._await_id)
		var 问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(pid, {})
		var 命令表: Array = 问.get("commands", [])
		_记询问(pid, int(问.get("cmd_type", 0)), 命令表)
		if 应答位 >= 应答序.size():
			break
		var 答: Dictionary = 应答序[应答位]
		应答位 += 1
		var rid: int = 0
		if not 命令表.is_empty():
			rid = int((命令表[0] as Dictionary).get("respond_id", 0))
		# kind 必须用 GConst.Msg.Respond（与 wait_for 的 kind 对齐），不能用 CmdType 里的编号
		引擎.on_message(pid, GConst.Msg.Respond, {
			"respond_id": rid, "src_id": pid,
			"args": 答.get("args", []), "card_ids": 答.get("cards", []), "dst_ids": 答.get("dsts", []),
		})
		if 引擎._await_id < 0:
			# 询问是引擎状态里发的（_await_state = 那个状态）：必须让状态自己接着跑；
			# 直接重入角色钩子会让 _当前状态 变回 null，回复永远取不到（探针踩过）。
			if not 引擎._states.is_empty():
				引擎.run()
			else:
				_调钩子(钩子)


func _记询问(pid: int, cmd_type: int, 命令表: Array) -> void:
	if 命令表.is_empty():
		记.append("ASK pid=%d tc=%d <空>" % [pid, cmd_type])
		return
	var c: Dictionary = 命令表[0]
	var args: Array = c.get("args", [])
	var 选项值: Array = args.slice(4) if args.size() > 4 else []
	var 牌: Array = c.get("card_ids", [])
	牌.sort()
	var 目标: Array = c.get("dst_ids", [])
	目标.sort()
	记.append("ASK pid=%d tc=%d rid=%d nc=%d nt=%d src=%d 选项数=%d 选项值=%s 取消=%s 牌=%s 目标=%s 可用=%s 选项需牌=%s 选项需目标=%s" % [
		pid, cmd_type, int(c.get("respond_id", 0)),
		int(args[0]) if args.size() > 0 else -1,
		int(args[1]) if args.size() > 1 else -1,
		int(args[2]) if args.size() > 2 else -1,
		int(args[3]) if args.size() > 3 else -1,
		str(选项值), str(c.get("can_cancel", true)), str(牌), str(目标),
		str(c.get("option_enabled", [])), str(c.get("option_need_cards", [])),
		str(c.get("option_need_targets", [])),
	])


func _录消息(pid: int, msg: int, data: Dictionary) -> void:
	if msg == GConst.Msg.CmdReq:
		return
	if msg == GConst.Msg.Skill:
		记.append("MSG Skill pid=%d 技能=%d 目标=%s" % [
			pid, int(data.get("skill_id", 0)), str(data.get("dst_ids", []))])
	elif msg == GConst.Msg.Card:
		var 牌: Array = data.get("card_ids", [])
		牌.sort()
		记.append("MSG Card pid=%d type=%d 牌=%s as=%d 数=%d" % [
			pid, int(data.get("type", 0)), str(牌), int(data.get("as_card_id", -1)),
			int(data.get("count", -1))])
	elif msg == GConst.Msg.Hurt:
		var 键: Array = data.keys()
		键.sort()
		记.append("MSG Hurt pid=%d 点=%d 类型=%d dst=%d src=%d 键=%s" % [
			pid, int(data.get("point", -1)), int(data.get("type", -1)),
			int(data.get("dst", -1)), int(data.get("src", -1)), str(键)])
	elif msg == GConst.Msg.Gossip:
		记.append("MSG Gossip pid=%d txt=%s" % [pid, str(data.get("txt", ""))])


func _录状态() -> void:
	for pid: int in [1, 2, 3, 4]:
		var p: BattlePlayer = 引擎.p(pid)
		if p == null:
			continue
		var 手: Array = p.hand_cards.duplicate()
		手.sort()
		var 盖: Array = p.cover_cards.duplicate()
		盖.sort()
		var 行动: Array = []
		for a: Dictionary in p.additional_actions:
			行动.append(int(a.get("cause", 0)))
		记.append("STATE p=%d 手=%s 盖=%s tap=%s 治疗=%d 水晶=%d 宝石=%d 指示物=%s 额外=%s" % [
			pid, str(手), str(盖), str(p.tap), p.cross_num, p.crystal, p.gem,
			str(_指示物(p)), str(行动)])
	var 弃: Array = 引擎.deck.discard.duplicate()
	弃.sort()
	记.append("STATE 牌库=%d 弃牌=%s 队宝石=%s 队水晶=%s 士气=%s" % [引擎.deck.pile.size(), str(弃), str(引擎.team_gem), str(引擎.team_crystal), str(引擎.team_morale)])


func _指示物(p: BattlePlayer) -> Array:
	var out: Array = []
	for t: Variant in p.tokens:
		if t == null:
			out.append(-1)
		else:
			out.append(int((t as Dictionary).get("num", 0)))
	return out


func _输出(场景: String) -> void:
	print("[PROBE] ==== %s ====" % 场景)
	for s: String in 记:
		print("[PROBE] %s" % s)


# ---------------- 场景 ----------------


## 收魔术 4202：攻击命中前问是否发动 → 目标弃 1 张牌收进魔瓶（盖牌区）
func _场景收魔术() -> void:
	_新引擎({1: 42})
	var 火攻: int = _找攻击牌(GConst.CardElement.Fire)
	var 水攻: int = _找攻击牌(GConst.CardElement.Water)
	引擎.p(2).hand_cards = [火攻, 水攻] as Array[int]
	var ctx: Dictionary = {"src": 1, "dst": 2, "is_active": true}
	引擎.p(1).role.p_timeline_1(ctx)
	应答序 = [_答([1]), _答([], [水攻])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_1(ctx)))
	_录状态()
	_输出("收魔术4202")


## 法术剥离 4203：攻击命中时问是否发动 → 目标弃 1 张牌收进【魔力瓶】
func _场景法术剥离() -> void:
	_新引擎({1: 42})
	var 火攻: int = _找攻击牌(GConst.CardElement.Fire)
	var 水攻: int = _找攻击牌(GConst.CardElement.Water)
	引擎.p(2).hand_cards = [火攻, 水攻] as Array[int]
	var ctx: Dictionary = {"src": 1, "dst": 2, "is_active": true,
		"harm": {"src": 1, "dst": 2, "point": 2, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": 火攻, "card_id_instance": 火攻}}
	引擎.p(1).role.p_timeline_2_hit(ctx)
	应答序 = [_答([1]), _答([], [水攻])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_2_hit(ctx)))
	_录状态()
	_输出("法术剥离4203")
## 魔纹融合 2701：攻击未命中时问是否发动 → 选牌 / 翻转档
func _场景魔纹融合() -> void:
	_新引擎({1: 27})
	var 火攻: int = _找攻击牌(GConst.CardElement.Fire)
	var 水攻: int = _找攻击牌(GConst.CardElement.Water)
	引擎.p(1).hand_cards = [火攻, 水攻] as Array[int]
	var ctx: Dictionary = {"src": 1, "dst": 2, "is_active": true,
		"harm": {"src": 1, "dst": 2, "point": 1, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": 火攻, "card_id_instance": 火攻}}
	引擎.p(1).role.p_timeline_2_miss(ctx)
	应答序 = [_答([1]), _答([], [水攻]), _答([1])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_2_miss(ctx)))
	_录状态()
	_输出("魔纹融合2701")

## 圣剑 104（风之剑圣）：本回合第 3 次攻击强制命中 → 攻击行动结束先摸 X 张、再弃 X 张（X=1~3）
func _场景圣剑() -> void:
	_新引擎({1: 1})
	var 我: BattlePlayer = 引擎.p(1)
	var 火攻: int = _找攻击牌(GConst.CardElement.Fire)
	var 水攻: int = _找攻击牌(GConst.CardElement.Water)
	var 风攻: int = _找攻击牌(GConst.CardElement.Wind)
	我.hand_cards = [火攻, 水攻, 风攻] as Array[int]
	# 直接调「圣剑摸弃链」：绕开 timeline_1 的烈风/疾风分支（那两步两棵树都在，不是本轮重点）
	应答序 = [_答([2]), _答([], [水攻, 风攻])]
	_跑(func() -> int: return int(引擎.p(1).role.call("_sheng_jian_cycle")))
	_录状态()
	_输出("圣剑104")
## 异象剑 4502：发动 → 目标弃 1 张【展示】→ 法术牌 +2 伤害 / 攻击牌 +1 攻击行动并问要不要拿走
func _场景异象剑() -> void:
	_新引擎({1: 45})
	var 攻击牌: int = _找攻击牌(GConst.CardElement.Fire)
	var 目标牌: int = _找攻击牌(GConst.CardElement.Water)
	引擎.p(1).hand_cards = [攻击牌] as Array[int]
	引擎.p(2).hand_cards = [目标牌] as Array[int]
	var ctx: Dictionary = {
		"src": 1, "dst": 2, "is_active": true,
		"harm": {"src": 1, "dst": 2, "point": 2, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": 攻击牌, "card_id_instance": 攻击牌},
	}
	引擎.p(1).role.p_timeline_2_hit(ctx)
	应答序 = [_答([1]), _答([], [目标牌]), _答([1])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_2_hit(ctx)))
	_录状态()
	_输出("异象剑4502-发动-攻击牌")


## 英灵召唤 2505：耗 1 能量 → 伤害 +1 → 弃 1 张法术牌【展示】→ 选 1 名角色 +1 治疗
func _场景英灵召唤() -> void:
	_新引擎({1: 25})
	var 法术牌: int = _找法术牌(GConst.CardElement.Fire)
	引擎.p(1).hand_cards = [法术牌] as Array[int]
	引擎.p(1).set_crystal(1)
	var ctx: Dictionary = {
		"is_active": true,
		"harm": {"src": 1, "dst": 2, "point": 1, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": _找攻击牌(GConst.CardElement.Fire),
			"card_id_instance": _找攻击牌(GConst.CardElement.Fire)},
	}
	引擎.p(1).role.p_timeline_2_hit(ctx)
	应答序 = [_答([1]), _答([], [法术牌], [3])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_2_hit(ctx)))
	_记录伤害点(ctx)
	_录状态()
	_输出("英灵召唤2505")


func _记录伤害点(ctx: Dictionary) -> void:
	var harm: Dictionary = ctx.get("harm", {})
	记.append("CHECK harm.point=%d" % int(harm.get("point", -1)))


## 军神威光 2504：回合开始且横置 → ① 或 ②
func _场景军神威光_选一() -> void:
	_新引擎({1: 25})
	var p: BattlePlayer = 引擎.p(1)
	p.tap = true
	引擎.set_team_gem(GConst.BLUE, 2)
	引擎.set_team_crystal(GConst.BLUE, 1)
	引擎.current_id = 1
	p.role.p_turn_begin({})
	应答序 = [_答([1])]
	_跑(func() -> int: return int(引擎.p(1).role.p_turn_begin({})))
	_录状态()
	_输出("军神威光2504-选①")


func _场景军神威光_选二() -> void:
	_新引擎({1: 25})
	var p: BattlePlayer = 引擎.p(1)
	p.tap = true
	引擎.set_team_gem(GConst.BLUE, 2)
	引擎.set_team_crystal(GConst.BLUE, 1)
	引擎.current_id = 1
	p.role.p_turn_begin({})
	应答序 = [_答([2]), _答([1], [], [3])]
	_跑(func() -> int: return int(引擎.p(1).role.p_turn_begin({})))
	_录状态()
	_输出("军神威光2504-选②")

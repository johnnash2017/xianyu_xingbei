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
## 只记录「钩子驱动期间」的消息：开局被动的展示牌随洗牌变化，是噪声
var 记录中: bool = false


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
	_场景精灵剑舞()
	_场景神之子()
	_场景魑魅魍魉()
	_场景圣炎祈愿()
	_场景剑影断念()
	_场景水影()
	_场景共振()
	_场景侍奉之道()
	_场景双重回响()
	_场景启示()
	_场景弥撒()
	_场景异教徒展示()
	_场景异教徒展示地裂()
	_场景放逐()
	_场景灾殃止息()
	_场景白二羯磨()
	_扫全角色()
	print("[PROBE] DONE")
	get_tree().quit(0)


# ---------------- 通用 ----------------

func _新引擎(映射: Dictionary) -> void:
	引擎 = BattleEngine.new()
	记.clear()
	记录中 = false
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
	记录中 = true
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
	if not 记录中:
		return
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
		var 文本: String = str(data.get("txt", ""))
		# 「操作无效，请重新选择」是第三次审查补的校验日志（旧树静默重问），属登记差异
		if 文本.contains("操作无效"):
			return
		记.append("MSG Gossip pid=%d txt=%s" % [pid, 文本])


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

## 全角色 × 钩子序列扫描：按真实回合顺序串钩子（先 timeline_1 再 hit/miss、先 before_special 再 after_special），
## 单钩子孤立调用会漏掉「上游先记状态」的响应技（试过：忌妒少女 107 / 英灵人形 27 会假阳）。
## 两棵树用同一串钩子 + 同一串应答，diff 出「哪条序列的行为变了」。
const 序列表: Array = [
	# 真实攻击从「攻击牌宣告」开始：漏了 p_attack_card，靠它记状态的响应技会假阳（107 / 27 就是这么发现的）
	["p_attack_card", "p_timeline_1", "p_timeline_2_hit", "p_timeline_3", "p_after_attack"],
	["p_attack_card", "p_timeline_1", "p_timeline_2_miss", "p_after_attack"],
	["p_before_special", "p_after_special"],
	["p_before_turn_begin", "p_turn_begin", "p_before_draw", "p_before_discard", "p_heal_overflow", "p_turn_end"],
]


func _扫全角色() -> void:
	for 角色号: int in Data.role_pool:
		for 序号: int in range(序列表.size()):
			_扫一序(角色号, 序号, 序列表[序号])


func _扫一序(角色号: int, 序号: int, 钩子表: Array) -> void:
	_新引擎({1: 角色号})
	var p: BattlePlayer = 引擎.p(1)
	# 手里放一对同系牌：【战纹碎击】这类「弃 2 张同系牌」的校验才过得去，
	# 否则两棵树都判校验失败（旧静默 / 新重问），diff 出假差异
	var 同系: Array[int] = _同系一对()
	p.hand_cards = [同系[0], 同系[1], 87, 129] as Array[int]
	p.tap = true
	引擎.current_id = 1
	var ctx: Dictionary = {"src": 1, "dst": 2, "player": 1, "pid": 1, "is_active": true,
		"card_id": 66, "card_id_instance": 66,
		"harm": {"src": 1, "dst": 2, "point": 2, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": 66, "card_id_instance": 66}}
	for 钩子: String in 钩子表:
		记.append("---- %d seq%d %s" % [角色号, 序号, 钩子])
		# 每条应答都带上牌和目标：只给 args 的畸形回复会走「校验失败重问」，两棵树处理不同（旧静默 / 新重问），属预期差异
		应答序 = [_答([1], [同系[0], 同系[1]], [3]), _答([1], [同系[0], 同系[1]], [2]),
			_答([1], [同系[0]], [3]), _答([1], [同系[1]], [2])]
		_跑(func() -> int: return int(p.role.call(钩子, ctx)))
		_录简况()
	_输出("扫 %d seq%d" % [角色号, 序号])



## 两张水系牌（供【水影】这类「弃水系牌」的技能用）
func _水系两张() -> Array[int]:
	var 出: Array[int] = []
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.element_enum() == GConst.CardElement.Water:
			出.append(c.id)
			if 出.size() >= 2:
				break
	if 出.size() < 2:
		return [87, 129]
	return 出

## 找两张同系牌（同一元素）
func _同系一对() -> Array[int]:
	var 按系: Dictionary = {}
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		var 系: int = c.element_enum()
		if not 按系.has(系):
			按系[系] = []
		(按系[系] as Array).append(c.id)
	for 系: Variant in 按系:
		var 列: Array = 按系[系]
		if 列.size() >= 2:
			return [int(列[0]), int(列[1])]
	return [66, 87]


## 扫角色时用的一行状态，避免输出爆炸
func _录简况() -> void:
	var p: BattlePlayer = 引擎.p(1)
	var 行: Array = p.hand_cards.duplicate()
	行.sort()
	记.append("STATE1 手数=%d 手=%s 盖=%d tap=%s 治疗=%d 水晶=%d 指示物=%s 额外=%d 牌库=%d" % [
		p.hand_cards.size(), str(行), p.cover_cards.size(), str(p.tap), p.cross_num,
		p.crystal, str(_指示物(p)), p.additional_actions.size(), 引擎.deck.pile.size()])



## 精灵的剑舞 3805（游击士）：支付 1 能量 + 指定一名对手，本次攻击按风系虚牌 66 结算
func _场景精灵剑舞() -> void:
	_新引擎({1: 38})
	var 火攻: int = _找攻击牌(GConst.CardElement.Fire)
	引擎.p(1).hand_cards = [火攻] as Array[int]
	引擎.p(1).set_crystal(1)
	var 动作: Dictionary = {"src_id": 1, "action_id": 3805, "card_ids": [火攻], "dst_ids": [2]}
	应答序 = [_答([1], [], [2])]
	_跑(func() -> int: return int(引擎.p(1).role.p_attack_skill(动作)))
	_录状态()
	_输出("精灵的剑舞3805")

## 神之子 4305（圣殿骑士）：攻击宣告时二选一（神威 / 圣裁），这里走「神威」一支
func _场景神之子() -> void:
	_新引擎({1: 43})
	var 我: BattlePlayer = 引擎.p(1)
	# 圣印放在哪个指示物槽由角色表决定：这里把所有槽都填 2，保证「圣印 ≥ 2」成立
	for tt: Variant in 我.tokens:
		if tt != null:
			(tt as Dictionary)["num"] = 2
	var ctx: Dictionary = {"src": 1, "dst": 2, "is_active": true,
		"card_id": 66, "card_id_instance": 66,
		"harm": {"src": 1, "dst": 2, "point": 2, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": 66, "card_id_instance": 66}}
	应答序 = [_答([1]), _答([1], [], [2])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_1(ctx)))
	_录状态()
	_输出("神之子4305")

## 魑魅魍魉 8404（咒符师）：命中时选符 → 选目标/费用 → 展示 → 逐个转移治疗
func _场景魑魅魍魉() -> void:
	_新引擎({1: 84})
	var 我: BattlePlayer = 引擎.p(1)
	我.hand_cards = [66, 22] as Array[int]
	我.cover_cards = [87, 129] as Array[int]
	var ctx: Dictionary = {"src": 1, "dst": 2, "is_active": true,
		"card_id": 66, "card_id_instance": 66,
		"harm": {"src": 1, "dst": 2, "point": 2, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": 66, "card_id_instance": 66}}
	引擎.p(1).role.p_timeline_1(ctx)
	应答序 = [_答([8401], [], [2]), _答([1], [87], [3]), _答([1], [], [2]), _答([1], [66], [3])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_2_hit(ctx)))
	_录状态()
	_输出("魑魅魍魉8404")

## 圣炎祈愿 4307（圣殿骑士）：圣炎收尾 → 先对 1 名敌人 1 点法术伤害 → 再问祈愿（耗 1 能量 +2 治疗）
func _场景圣炎祈愿() -> void:
	_新引擎({1: 43})
	var 我: BattlePlayer = 引擎.p(1)
	我.set_crystal(1)
	引擎.p(1).role.set("_圣炎收尾", 1)
	应答序 = [_答([1], [], [2]), _答([1], [], [3])]
	_跑(func() -> int: return int(引擎.p(1).role.p_sheng_dian_ask({"player": 1})))
	_录状态()
	_输出("圣炎祈愿4307")

## 剑影断念 4504（剑之魔女）：攻击行动结束 → 聚合器摆选项 → 选 4504（付 1 宝石 + 弃 2 张）→ 结算
func _场景剑影断念() -> void:
	_新引擎({1: 45})
	var 我: BattlePlayer = 引擎.p(1)
	我.hand_cards = [66, 87, 129, 22] as Array[int]
	我.set_gem(1)
	var ctx: Dictionary = {}
	var 选项: Array = 引擎.p(1).role.action_end_options(ctx)
	var 摘要: Array = []
	for o: Dictionary in 选项:
		摘要.append([int(o.get("value", -1)), int(o.get("skill_id", -1)),
			bool(o.get("enabled", true)), int(o.get("need_card", -1))])
	记.append("OPTIONS 数=%d %s" % [选项.size(), str(摘要)])
	var 回: Dictionary = {"args": [4504], "card_ids": [66, 87], "dst_ids": [3]}
	应答序 = []
	_跑(func() -> int: return int(引擎.p(1).role.resolve_action_end_option(4504, 回, ctx)))
	_录状态()
	_输出("剑影断念4504")

## 水影 502（暗杀者）：摸牌前弃 X 张水系牌【展示】→ 摸 X+1？；不横置时第二步（额外弃法术牌）跳过
func _场景水影() -> void:
	_新引擎({1: 5})
	var 水: Array[int] = _水系两张()
	var p: BattlePlayer = 引擎.p(1)
	p.hand_cards = [水[0], 水[1]] as Array[int]
	p.tap = false
	var ctx: Dictionary = {"player": 1}
	应答序 = [_答([], [水[0], 水[1]])]
	_跑(func() -> int: return int(引擎.p(1).role.p_before_draw(ctx)))
	_录状态()
	_输出("水影502")

## 共振 7907（噬神者）：受到法术伤害 → 耗 1 能量 + 弃 2 张同系牌 → 四选一（刃 / 伤害 / 治疗）
func _场景共振() -> void:
	_新引擎({1: 79})
	var 同系: Array[int] = _同系一对()
	var p: BattlePlayer = 引擎.p(1)
	p.hand_cards = [同系[0], 同系[1], 87, 129] as Array[int]
	p.set_crystal(1)
	var ctx: Dictionary = {"harm": {"src": 2, "dst": 1, "point": 2,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Magic, "card_id": 87}}
	应答序 = [_答([], [同系[0], 同系[1]]), _答([1], [], [2]), _答([1], [], [2])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_3(ctx)))
	_录状态()
	_输出("共振7907")

## 侍奉之道 8105（女仆长）：回合结束移除 2 张【影】→ +1【糸】；两张同系时把 1 张交给目标并横置
func _场景侍奉之道() -> void:
	_新引擎({1: 81})
	var 同系: Array[int] = _同系一对()
	var p: BattlePlayer = 引擎.p(1)
	p.cover_cards = [同系[0], 同系[1]] as Array[int]
	应答序 = [_答([1], [同系[0], 同系[1]]), _答([1], [], [3])]
	_跑(func() -> int: return int(引擎.p(1).role.p_turn_end({"player": 1})))
	_录状态()
	_输出("侍奉之道8105")

## 双重回响 2706（英灵人形）：对目标造成伤害时 → 耗 1 能量 → 对另一名角色复制等量伤害（≤3）
func _场景双重回响() -> void:
	_新引擎({1: 27})
	var p: BattlePlayer = 引擎.p(1)
	p.set_crystal(1)
	var ctx: Dictionary = {"harm": {"src": 1, "dst": 2, "point": 2,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Magic, "card_id": 87}}
	应答序 = [_答([1], [], [3])]
	_跑(func() -> int: return int(引擎.p(1).role.p_timeline_3(ctx)))
	_录状态()
	_输出("双重回响2706")

## 启示 9604（传教士）：虔诚 ≥2 → 二选一（目标 +1 治疗 / 摸 1 张试图取消转移）→ 选 1 名目标
func _场景启示() -> void:
	_新引擎({1: 96})
	var p: BattlePlayer = 引擎.p(1)
	for tt: Variant in p.tokens:
		if tt != null:
			(tt as Dictionary)["num"] = 2
	应答序 = [_答([1]), _答([1], [], [3])]
	# 走公开入口 _转移路标：两棵树都有它，_启示链 只是新树的内部拆分
	_跑(func() -> int: return int(引擎.p(1).role.call("_转移路标", 3)))
	_录状态()
	_输出("启示9604")


## 弥撒 9608（传教士）：路标转移后 +1 虔诚 → 二选一（弃 1 张展示挂在持有者面前 / 收回 1 张基础效果）
func _场景弥撒() -> void:
	_新引擎({1: 96})
	var p: BattlePlayer = 引擎.p(1)
	p.hand_cards = [66, 87] as Array[int]
	应答序 = [_答([1], [66]), _答([1], [66])]
	_跑(func() -> int: return int(引擎.p(1).role.call("_弥撒")))
	_录状态()
	_输出("弥撒9608")


## 异教徒「展示」链（9506 贪婪 / 9507 天雷劫火 / 9508 地裂波涛）：
## 场卡【末日预言】带 front → 置 _翻面步=1 → p_yi_jiao_tu_ask 翻面并进入展示
func _场景异教徒展示() -> void:
	_新引擎({1: 95})
	# 展示的选项值是「系别枚举值」，且只放行当前正面（天雷）的两系：雷 / 火
	var 对: Array[int] = _同系一对限定([GConst.CardElement.Thunder, GConst.CardElement.Fire])
	var 系: int = GConst.CardElement.Thunder
	if not 对.is_empty():
		系 = Data.get_card(对[0]).element_enum()
	var p: BattlePlayer = 引擎.p(1)
	p.hand_cards = [0, 1, 2, 3, 4, 5, 对[0], 对[1]] as Array[int]
	var 表: Dictionary = 引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 6, "counter_max": 6, "state": 0})
	if not 表.is_empty():
		表["front"] = "天雷劫火"
		表["pile"] = [0, 1, 2, 3, 4, 5]
	p.role.set("_翻面步", 1)
	应答序 = [_答([1], [], [2]), _答([系], [对[0], 对[1]], [2]), _答([1], [], [2]), _答([1], [], [2])]
	_跑(func() -> int: return int(引擎.p(1).role.p_yi_jiao_tu_ask({"player": 1})))
	_录状态()
	_输出("异教徒展示9507")


## 指定几系里找两张同系牌
func _同系一对限定(系列: Array) -> Array[int]:
	for 系: Variant in 系列:
		var 出: Array[int] = []
		for c: GCard in Data.card_db:
			if c != null and not c.is_virtual and c.element_enum() == int(系):
				出.append(c.id)
				if 出.size() >= 2:
					return [出[0], 出[1]]
	return []



## 同一条展示链的地裂分支（9508 地裂波涛正面：只放行地 / 水两系）
func _场景异教徒展示地裂() -> void:
	_新引擎({1: 95})
	var 对: Array[int] = _同系一对限定([GConst.CardElement.Earth, GConst.CardElement.Water])
	var 系: int = GConst.CardElement.Earth
	if not 对.is_empty():
		系 = Data.get_card(对[0]).element_enum()
	var p: BattlePlayer = 引擎.p(1)
	p.hand_cards = [0, 1, 2, 3, 4, 5, 对[0], 对[1]] as Array[int]
	var 表: Dictionary = 引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 6, "counter_max": 6, "state": 0})
	if not 表.is_empty():
		表["front"] = "地裂波涛"
		表["pile"] = [0, 1, 2, 3, 4, 5]
	p.role.set("_翻面步", 1)
	应答序 = [_答([1], [], [2]), _答([系], [对[0], 对[1]], [2]), _答([1], [], [2]), _答([1], [], [2])]
	_跑(func() -> int: return int(引擎.p(1).role.p_yi_jiao_tu_ask({"player": 1})))
	_录状态()
	_输出("异教徒展示9508-地裂")

## 放逐 9505（异教徒）：法术行动 → 摸 6~8 张 → 选正面（天雷 / 地裂）→ 6 张手牌作【预言】→ 放【末日预言】
func _场景放逐() -> void:
	_新引擎({1: 95})
	var p: BattlePlayer = 引擎.p(1)
	var 手: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
	p.hand_cards = 手.duplicate()
	p.set_crystal(1)
	var 动作: Dictionary = {"src_id": 1, "action_id": 9505, "args": [6]}
	应答序 = [_答([1], [0, 1, 2, 3, 4, 5], [2]), _答([2], [6, 7, 8, 9, 10, 11], [2])]
	_跑(func() -> int: return int(引擎.p(1).role.p_magic_skill(动作)))
	_录状态()
	_输出("放逐9505")

## 灾殃止息 9509（异教徒）：回合开始时，场上有【天雷劫火】/【地裂波涛】→ 移除
func _场景灾殃止息() -> void:
	_新引擎({1: 95})
	引擎.加场卡({"id": "天雷劫火", "owner": 1, "attached": 2, "counter": 3})
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1, "counter": 6})
	应答序 = []
	_跑(func() -> int: return int(引擎.p(1).role.p_before_turn_begin({"player": 1})))
	_录状态()
	_输出("灾殃止息9509")


## 白二羯磨 8208（结界师）：【绝界】持有者攻击行动结束 → 问持有者发不发动 → 他选 1 个【结界】
func _场景白二羯磨() -> void:
	_新引擎({1: 82})
	var p: BattlePlayer = 引擎.p(1)
	p.cover_cards = [87, 129] as Array[int]
	引擎.加场卡({"id": "绝界", "owner": 1, "attached": 2, "counter": 0})
	应答序 = [_答([1], [], []), _答([87], [], [])]
	_跑(func() -> int: return int(引擎.p(1).role.p_action_end({"kind": "attack", "player": 2})))
	_录状态()
	_输出("白二羯磨8208")
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

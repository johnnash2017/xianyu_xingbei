extends 自检用例
## 用例 12：原初之弓Trick（88）—— 旧版圣弓技能回归：选项/目标/资源校验、圣屑飓暴圣光与队友、天之弓应战信仰、
## 圣煌辉光炮翻面状态/攻法额外行动、自动填充资源门槛与超时兜底。

func _init() -> void:
	名称 = "原初之弓Trick技能对齐"


func _取牌(数量: int, 排除: Array = []) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if c.is_virtual or out.has(c.id) or 排除.has(c.id):
			continue
		out.append(c.id)
		if out.size() >= 数量:
			break
	return out


func _按号(技能表: Array) -> Dictionary:
	var out: Dictionary = {}
	for sk: Dictionary in 技能表:
		out[int(sk.get("id", 0))] = sk
	return out


## 把自动填充的起始状态摆好并让 p_turn_end 发问；返回 8807 的询问（没发问返回空字典）。
func _问自动填充(引擎: BattleEngine, 角色: BattleRole, 弓: BattlePlayer,
		水晶: int, 宝石: int, 治疗: int, 信仰: int) -> Dictionary:
	弓.cross_num = 治疗
	弓.set_gem(0)
	弓.set_crystal(0)
	弓.set_gem(宝石)
	弓.set_crystal(水晶)
	弓.tokens[0]["num"] = 信仰
	角色.no_tian_chong = false
	角色._持久进度 = 0
	引擎._清空等待()
	if 角色.p_turn_end({"player": 1}) != BattleRole.WAIT:
		return {}
	var 问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 8807:
			问 = r
	return 问


## 直接塞一条自动填充回复，让 p_turn_end 结算。
func _答自动填充(引擎: BattleEngine, 角色: BattleRole, args: Array) -> int:
	引擎._reply = {"args": args, "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	return 角色.p_turn_end({"player": 1})


func 跑() -> void:
	await 等帧(2)

	var 圣光: Array[int] = []
	var 非圣攻击: GCard = null
	for c: GCard in Data.card_db:
		if c.is_virtual:
			continue
		if c.element_enum() == GConst.CardElement.Light and not 圣光.has(c.id):
			圣光.append(c.id)
		if 非圣攻击 == null and c.is_attack() and c.fate_pattern_enum() != GConst.FatePattern.Holy:
			非圣攻击 = c
	检(圣光.size() >= 2, "找不到两张【圣光】给圣屑飓暴测试")
	检(非圣攻击 != null, "找不到非【圣】命格攻击牌给天之弓/圣流星弹测试")
	if 圣光.size() < 2 or 非圣攻击 == null:
		return

	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "圣弓")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({1: 88, 2: 0, 3: 0, 4: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	var 弓: BattlePlayer = 引擎.p(1)
	var 队友: BattlePlayer = 引擎.p(2)
	var 对手甲: BattlePlayer = 引擎.p(3)
	var 对手乙: BattlePlayer = 引擎.p(4)
	if 弓 == null or 弓.role == null:
		检(false, "原初之弓Trick角色脚本没有挂上")
		return
	var 角色: BattleRole = 弓.role

	# 初始：正面辉光炮可用（士气落后），背面余辉置灰；圣光牌应进入圣屑飓暴的合法牌白名单。
	var 初始手牌: Array[int] = [圣光[0], 圣光[1]]
	初始手牌.append_array(_取牌(3, 圣光))
	弓.hand_cards = 初始手牌
	弓.cross_num = 2
	弓.tokens[0]["num"] = 9
	弓.tap = true
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 15
	检(GConst.技能指示器.has(GConst.技能_圣屑飓暴Trick), "缺少圣屑飓暴的头像指示器配置")
	检(GConst.技能指示器.has(GConst.技能_圣光爆裂Trick), "缺少圣光爆裂的头像指示器配置")
	检(GConst.技能指示器.has(GConst.技能_圣流星弹Trick), "缺少圣流星弹的头像指示器配置")
	检(ResourceLoader.exists(GConst.圣煌辉光炮图标), "缺少圣煌辉光炮状态图标")
	检(ResourceLoader.exists(GConst.圣煌余辉图标), "缺少圣煌余辉状态图标")
	检(GConst.提示原文(8802, 1).contains("队友"), "圣屑飓暴未命中提示应已改成指定队友")
	var 技能表: Array = 角色.available_skills()
	var 技能: Dictionary = _按号(技能表)
	检(技能.has(8806), "技能栏缺少圣煌辉光炮")
	检(技能.has(8808), "技能栏缺少圣煌余辉")
	检(bool((技能.get(8806, {}) as Dictionary).get("enabled", false)), "士气落后且信仰足够时圣煌辉光炮应可用")
	检(not bool((技能.get(8808, {}) as Dictionary).get("enabled", true)), "未翻面前圣煌余辉应置灰")
	检(int(弓.to_proto(1).get("sheng_huang_side", -1)) == 0,
		"初始快照应带【圣煌辉光炮】状态（0）")
	var 飓暴: Dictionary = 技能.get(8802, {})
	检((飓暴.get("cards", []) as Array).has(圣光[0]) and (飓暴.get("cards", []) as Array).has(圣光[1]),
		"圣屑飓暴的合法牌应包含两张【圣光】：%s" % str(飓暴.get("cards", [])))

	# 两张【圣光】应能通过圣屑飓暴校验，并以暗系【暗灭】作为虚拟攻击牌。
	var 飓暴动作: Dictionary = {
		"src_id": 1, "action_id": 8802, "card_ids": [圣光[0], 圣光[1]], "dst_ids": [3],
	}
	检(角色.v_magic_skill(飓暴动作) == GConst.GE_SUCCESS, "两张【圣光】应能发动圣屑飓暴")
	检(角色._sheng_xie_virtual_card(GConst.CardElement.Light) == 39,
		"两张【圣光】应视为暗系【暗灭】（39）")

	# 虚拟攻击要像【欺诈】一样发一条 Use（is_real=false），客户端才会播攻击特效。
	var 特效引擎: BattleEngine = BattleEngine.new()
	var 特效记录: Array = []
	特效引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		特效记录.append({"pid": pid, "msg": msg, "data": data})
	特效引擎.add_player(1, GConst.BLUE, "原初之弓Trick")
	特效引擎.add_player(2, GConst.RED, "靶子")
	特效引擎.start_with_roles({1: 88, 2: 0})
	var 特效弓: BattlePlayer = 特效引擎.p(1)
	特效弓.hand_cards = [圣光[0], 圣光[1]] as Array[int]
	特效记录.clear()
	特效弓.role._sheng_xie_ju_bao({
		"src_id": 1, "action_id": 8802,
		"card_ids": [圣光[0], 圣光[1]], "dst_ids": [2],
	})
	var 有虚拟攻击: bool = false
	for r: Dictionary in 特效记录:
		if int(r["msg"]) != GConst.Msg.Card:
			continue
		var d: Dictionary = r["data"]
		if int(d.get("type", 0)) == GConst.CardMsgType.Use \
				and not bool(d.get("is_real", true)) \
				and (d.get("card_ids", []) as Array) == [39] \
				and int(d.get("dst_id", -1)) == 2:
			有虚拟攻击 = true
	检(有虚拟攻击, "圣屑飓暴应广播虚拟攻击 Use（is_real=false，card=暗灭，目标=2）")

	# 圣屑飓暴·未命中只认自己的攻击来源；X 最高 2。
	var 弃牌日志: Array = []
	var 原发送回调: Callable = 引擎.send_cb
	引擎.send_cb = func(_pid: int, msg: int, data: Dictionary) -> void:
		if msg == GConst.Msg.Gossip and int(data.get("type", 0)) == GConst.GossipType.Discard:
			弃牌日志.append(data)
	引擎._清空等待()
	角色._miss_step = 0
	检(角色.p_timeline_2_miss({"src": 1, "harm": {"cause": GConst.CAUSE_ATTACK}}) == BattleRole.SUCCESS,
		"别的攻击未命中不应触发圣屑飓暴·未命中")
	检(引擎._await_id < 0, "别的攻击未命中不应发出询问")
	角色._miss_step = 0
	引擎._清空等待()
	检(角色.p_timeline_2_miss({"src": 1, "harm": {"cause": 8802}}) == BattleRole.WAIT,
		"圣屑飓暴未命中应询问弃/摸与目标")
	var 未命中问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 88021:
			未命中问 = r
	检(not 未命中问.is_empty(), "没有发出圣屑飓暴·未命中询问")
	var 未命中args: Array = 未命中问.get("args", [])
	检(未命中args.size() == 6, "圣屑飓暴·未命中应只有 X=1/2 两个弃牌选项：%s" % str(未命中args))
	检((未命中问.get("dst_ids", []) as Array) == [2],
		"圣屑飓暴·未命中只能选队友（不含自己）：%s" % str(未命中问.get("dst_ids", [])))
	检(bool(未命中问.get("can_cancel", false)), "圣屑飓暴·未命中应允许取消")
	检(not 未命中args.has(3) and not 未命中args.has(4), "不应再有摸牌选项：%s" % str(未命中args))
	for 项: Dictionary in 角色.call("_sheng_xie_miss_choices"):
		检(str(项.get("label", "")).contains("目标友方"), "圣屑未命中选项应写明是目标友方弃牌：%s" % str(项.get("label", "")))
	# 答复第一步（X=1、队友 2），应继续向队友发出弃 1 张牌的询问；答复后队友真的弃掉。
	队友.hand_cards = _取牌(3, 弓.hand_cards + 对手甲.hand_cards + 对手乙.hand_cards)
	var 队友手牌前: int = 队友.hand_cards.size()
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": [2]}
	引擎._has_reply = true
	检(角色.p_timeline_2_miss({"src": 1, "harm": {"cause": 8802}}) == BattleRole.WAIT,
		"选完 X 和队友后应继续等队友弃牌")
	var 弃牌问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(2, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 88021:
			弃牌问 = r
	检(not 弃牌问.is_empty(), "没有向队友发出弃牌询问")
	检(int((弃牌问.get("args", [0]) as Array)[0]) == 1, "队友弃牌询问应要求 1 张")
	引擎._reply = {"args": [], "card_ids": [队友.hand_cards[0]], "dst_ids": []}
	引擎._has_reply = true
	检(角色.p_timeline_2_miss({"src": 1, "harm": {"cause": 8802}}) == BattleRole.SUCCESS,
		"队友答复后未命中弃牌应结算完成")
	检(队友.hand_cards.size() == 队友手牌前 - 1, "队友应真的弃掉 1 张手牌")
	检(not 弃牌日志.is_empty(), "队友弃牌应写战斗日志")
	if not 弃牌日志.is_empty():
		检(str(弃牌日志[-1].get("txt", "")).contains("弃掉 1 张牌")
			and int(弃牌日志[-1].get("num", 0)) == 1,
			"队友弃牌日志应写「弃掉 1 张牌」并带弃牌特效张数：%s" % str(弃牌日志[-1]))
	角色._miss_step = 0
	引擎.send_cb = 原发送回调
	引擎._清空等待()

	# 圣煌模式：两种支付方式都下发，资源不足的一项置灰。
	弓.tap = false
	弓.cross_num = 2
	弓.tokens[0]["num"] = 1
	技能 = _按号(角色.available_skills())
	var 模式选项: Array = (技能.get(8803, {}) as Dictionary).get("arg_choices", [])
	检(模式选项.size() == 2, "圣煌模式应有两个支付选项")
	if 模式选项.size() == 2:
		检(int(模式选项[0].get("args", [0])[0]) == 1 and bool(模式选项[0].get("enabled", false)),
			"有 2 治疗时“移除 2 治疗”应可用")
		检(not bool(模式选项[1].get("enabled", true)), "只有 1 信仰时“移除 2 信仰”应置灰")

	# 圣光爆裂：单体目标看「摸 1 张后」的手牌数；群体目标看「你的手牌数 - X」。
	弓.tap = true
	弓.cross_num = 2
	弓.hand_cards = _取牌(4)
	对手甲.hand_cards = _取牌(3, 弓.hand_cards)
	对手乙.hand_cards = _取牌(5, 弓.hand_cards + 对手甲.hand_cards)
	技能 = _按号(角色.available_skills())
	var 爆裂选项: Array = (技能.get(8804, {}) as Dictionary).get("arg_choices", [])
	检(爆裂选项.size() == 2, "圣光爆裂第一层应有单体 / 群体两个选项")
	if 爆裂选项.size() == 2:
		var 单体: Dictionary = 爆裂选项[0]
		检((单体.get("targets", []) as Array) == [3], "单体目标应只有手牌 3 张的对手甲：%s" % str(单体.get("targets", [])))
		检(int(单体.get("target_max", 0)) == 1, "单体目标上限应为 1")
		检(str(单体.get("text", "")) == "发动单体攻击，移除 1 治疗，摸 1 牌",
			"圣光爆裂单体选项文案不对：%s" % str(单体.get("text", "")))
		检(str(单体.get("说明", "")) == "【圣光爆裂】：摸 1 牌，对 1 名手牌数小于 5 的对手造成 2 点攻击伤害，你 +1【信仰】。",
			"圣光爆裂单体说明应写摸牌和手牌阈值 5：%s" % str(单体.get("说明", "")))
		var 群体: Dictionary = 爆裂选项[1]
		检((群体.get("args", []) as Array) == [2], "群体第一层应只提交群体标记，X 留到第二层")
		检(int(群体.get("need_card", -1)) == 0 and int(群体.get("target_max", -1)) == 0,
			"群体第一层不应先要求弃牌或目标")
		检(str(群体.get("text", "")) == "发动群体攻击，移除 X 治疗，弃 X 牌",
			"圣光爆裂群体选项文案不对：%s" % str(群体.get("text", "")))
	# 单体分支：目标手牌 3、自己 4，摸 1 后 3 < 5，合法；对手乙 5 不合法。
	var 单体动作: Dictionary = {
		"src_id": 1, "action_id": 8804, "args": [1], "card_ids": [], "dst_ids": [3],
	}
	检(角色.v_magic_skill(单体动作) == GConst.GE_SUCCESS, "圣光爆裂单体应接受手牌数少于你的对手")
	单体动作["dst_ids"] = [4]
	检(角色.v_magic_skill(单体动作) != GConst.GE_SUCCESS, "圣光爆裂单体不应接受手牌数不小于你的对手")
	# 群体 X=2：对手甲手牌 3 > 4-2，不合法；改成 2 张后合法。
	对手甲.hand_cards = _取牌(2, 弓.hand_cards)
	var 群体动作: Dictionary = {
		"src_id": 1, "action_id": 8804, "args": [2, 2],
		"card_ids": [弓.hand_cards[0], 弓.hand_cards[1]], "dst_ids": [3],
	}
	检(角色.v_magic_skill(群体动作) == GConst.GE_SUCCESS, "圣光爆裂群体 X=2 应接受手牌 <=2 的对手")
	群体动作["dst_ids"] = [3, 4]
	检(角色.v_magic_skill(群体动作) != GConst.GE_SUCCESS, "群体目标数不应超过 X")
	# 单体摸牌后的手牌阈值要受手牌上限约束：6 张时为 6，不能写成 7；
	# 因而 6 张手牌的目标也不再满足「小于 6」。
	var 原手牌: Array[int] = 弓.hand_cards.duplicate()
	var 原手牌上限: int = 弓.hand_cards_max
	var 原敌手: Array[int] = 对手甲.hand_cards.duplicate()
	弓.hand_cards = _取牌(6)
	弓.hand_cards_max = 6
	对手甲.hand_cards = _取牌(6, 弓.hand_cards)
	技能 = _按号(角色.available_skills())
	爆裂选项 = (技能.get(8804, {}) as Dictionary).get("arg_choices", [])
	if not 爆裂选项.is_empty():
		检(str((爆裂选项[0] as Dictionary).get("说明", "")).contains("小于 6"),
			"6 张手牌时单体阈值应封顶为 6：%s" % str((爆裂选项[0] as Dictionary).get("说明", "")))
	var 上限单体动作: Dictionary = {
		"src_id": 1, "action_id": 8804, "args": [1], "card_ids": [], "dst_ids": [3],
	}
	检(角色.v_magic_skill(上限单体动作) != GConst.GE_SUCCESS,
		"6 张手牌时目标 6 张不应满足「小于 6」")
	弓.hand_cards.assign(原手牌)
	弓.hand_cards_max = 原手牌上限
	对手甲.hand_cards.assign(原敌手)

	# 两个分支都没有合法目标时，圣光爆裂技能本体也应置灰。
	var 无目标手牌: Array[int] = 弓.hand_cards.duplicate()
	var 无目标甲手牌: Array[int] = 对手甲.hand_cards.duplicate()
	var 无目标乙手牌: Array[int] = 对手乙.hand_cards.duplicate()
	对手甲.hand_cards = _取牌(5, 弓.hand_cards)
	对手乙.hand_cards = _取牌(6, 弓.hand_cards + 对手甲.hand_cards)
	技能 = _按号(角色.available_skills())
	var 无目标爆裂: Dictionary = 技能.get(8804, {})
	检(not bool(无目标爆裂.get("enabled", true)), "单体/群体都没有合法目标时，圣光爆裂应整颗置灰")
	for 项: Dictionary in (无目标爆裂.get("arg_choices", []) as Array):
		检(not bool(项.get("enabled", true)), "没有合法目标时，圣光爆裂各分支都应置灰")
	弓.hand_cards.assign(无目标手牌)
	对手甲.hand_cards.assign(无目标甲手牌)
	对手乙.hand_cards.assign(无目标乙手牌)

	# 圣流星弹：圣煌形态下主动攻击前询问；目标只能是友方（含自己）。
	弓.tap = true
	弓.cross_num = 1
	弓.tokens[0]["num"] = 1
	角色._timeline_1_step = 0
	引擎._清空等待()
	var 攻击上下文: Dictionary = {
		"src": 1, "is_active": true, "card_id": 非圣攻击.id,
		"harm": {"src": 1, "dst": 3, "point": 2, "cause": GConst.CAUSE_ATTACK,
			"type": GConst.HarmType.Attack, "card_id": 非圣攻击.id, "is_active": true},
	}
	检(角色.p_timeline_1(攻击上下文) == BattleRole.WAIT, "主动攻击宣告后应询问圣流星弹")
	var 流星问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 8805:
			流星问 = r
	检(not 流星问.is_empty(), "没有发出圣流星弹询问")
	检((流星问.get("dst_ids", []) as Array) == [1, 2],
		"圣流星弹目标应只有自己和队友：%s" % str(流星问.get("dst_ids", [])))
	var 流星可用: Array = 流星问.get("option_enabled", [])
	检(流星可用.is_empty() or 流星可用 == [true, true],
		"治疗和信仰都有时两个支付选项都应可用：%s" % str(流星可用))
	# 只有治疗、没有信仰时：信仰项置灰，但选项仍然摆出来。
	弓.tokens[0]["num"] = 0
	角色._timeline_1_step = 0
	引擎._清空等待()
	检(角色.p_timeline_1(攻击上下文) == BattleRole.WAIT, "只有治疗时仍应询问圣流星弹")
	var 流星问二: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 8805:
			流星问二 = r
	检((流星问二.get("option_enabled", []) as Array) == [true, false],
		"没有信仰时“移除 1 信仰”应置灰：%s" % str(流星问二.get("option_enabled", [])))
	角色._timeline_1_step = 0
	引擎._清空等待()

	# 圣煌辉光炮翻面：正面用完切背面，背面用完移除；两颗技能始终摆出，只改 enabled。
	弓.tap = true
	弓.tokens[0]["num"] = 9
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 15
	弓.sheng_huang_side = 0
	技能 = _按号(角色.available_skills())
	检(bool((技能.get(8806, {}) as Dictionary).get("enabled", false)), "翻面前辉光炮应可用")
	检(not bool((技能.get(8808, {}) as Dictionary).get("enabled", true)), "翻面前余辉应置灰")
	检(角色._hui_guang_cost() == 9, "落后 5 士气时信仰消耗应为 5+4=9")
	var 逆时针: Array = 角色._ids_from_self()
	检(逆时针.size() == 4 and int(逆时针[0]) == 1 and int(逆时针[1]) == 弓.pre_id,
		"辉光炮应从圣弓开始逆时针结算：%s，pre=%d" % [str(逆时针), 弓.pre_id])
	对手乙.hand_cards_max = 3
	检(角色._hui_guang_target_hand(对手乙) == 3, "手牌上限小于 4 时应只补到上限")
	对手乙.hand_cards_max = GConst.HAND_CARDS_MAX
	var 炮选项: Array = (技能.get(8806, {}) as Dictionary).get("arg_choices", [])
	检(炮选项.size() == 2, "辉光炮应只保留两个士气方向选项")
	if 炮选项.size() == 2:
		检((炮选项[0].get("args", []) as Array) == [1]
			and (炮选项[1].get("args", []) as Array) == [0],
			"辉光炮选项只携带士气方向，不再携带额外行动：%s" % str(炮选项))
	弓.sheng_huang_side = 1
	技能 = _按号(角色.available_skills())
	检(not bool((技能.get(8806, {}) as Dictionary).get("enabled", true)), "翻面后辉光炮应置灰")
	检(bool((技能.get(8808, {}) as Dictionary).get("enabled", false)), "翻面后余辉应可用")
	# 辉光炮会把双方士气拉平；余辉不能因为“不再落后”而被卡死。
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 10
	弓.tokens[0]["num"] = 4
	技能 = _按号(角色.available_skills())
	检(bool((技能.get(8808, {}) as Dictionary).get("enabled", false)),
		"士气相等时余辉仍应可用（只付 4 信仰）")
	检(角色._hui_guang_cost() == 4, "士气相等时信仰消耗应为 4")

	# 执行正面：全体手牌已是 4 张，跳过弃/摸；检查星杯、士气、治疗、额外攻击、翻面。
	弓.tap = true
	弓.cross_num = 0
	队友.cross_num = 0
	弓.tokens[0]["num"] = 9
	弓.additional_actions.clear()
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 15
	引擎.team_grail[GConst.BLUE] = 0
	弓.hand_cards = _取牌(4)
	队友.hand_cards = _取牌(4, 弓.hand_cards)
	对手甲.hand_cards = _取牌(4, 弓.hand_cards + 队友.hand_cards)
	对手乙.hand_cards = _取牌(4, 弓.hand_cards + 队友.hand_cards + 对手甲.hand_cards)
	弓.sheng_huang_side = 0
	角色.hui_guang_index = -1
	检(角色._hui_guang_pao({"action_id": 8806, "args": [0]}) == BattleRole.SUCCESS,
		"辉光炮在执行条件满足时应直接结算完成")
	检(引擎.team_grail[GConst.BLUE] == 1, "辉光炮应让我方星杯 +1")
	检(引擎.team_morale[GConst.RED] == 10, "选择第一项后敌方士气应拉平到我方")
	检(弓.cross_num == 1 and 队友.cross_num == 1, "辉光炮应让我方所有角色各 +1 治疗")
	检(弓.tokens[0]["num"] == 0, "士气落后 5 时应消耗 9 信仰")
	检(弓.sheng_huang_side == 1, "辉光炮用完后应翻面成余辉")
	检(int(弓.to_proto(1).get("sheng_huang_side", -1)) == 1,
		"翻面后快照应换成【圣煌余辉】状态（1）")
	检(弓.contains_action()
		and int(弓.additional_actions[0].get("allow_action", 0)) == GConst.ActionType.AttackMagic,
		"辉光炮应给自己额外攻击或法术行动")
	弓.additional_actions.clear()
	# 余辉的弃牌询问要和辉光炮一样，不能退化成「是否发动」。
	检(GConst.提示原文(8808, 0).contains("弃") and GConst.提示原文(8808, 0).contains("{n}"),
		"圣煌余辉应复用弃牌提示：%s" % GConst.提示原文(8808, 0))

	# 执行背面：不再给治疗和额外行动，只做星杯/士气并移除余辉。
	弓.cross_num = 0
	队友.cross_num = 0
	弓.tokens[0]["num"] = 4
	弓.additional_actions.clear()
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 10
	引擎.team_grail[GConst.BLUE] = 0
	弓.sheng_huang_side = 1
	角色.hui_guang_index = -1
	检(角色._hui_guang_pao({"action_id": 8808, "args": [0]}) == BattleRole.SUCCESS,
		"余辉在执行条件满足时应直接结算完成")
	检(弓.cross_num == 0 and 队友.cross_num == 0, "余辉不应给任何角色加治疗")
	检(弓.sheng_huang_side == 2, "余辉用完后应被移除")
	检(int(弓.to_proto(1).get("sheng_huang_side", -1)) == 2,
		"余辉用完后快照应为已移除（2）")
	检(not 弓.contains_action(), "余辉不应给额外行动")
	检(引擎.team_grail[GConst.BLUE] == 1, "余辉仍应让我方星杯 +1")
	技能 = _按号(角色.available_skills())
	检(not bool((技能.get(8806, {}) as Dictionary).get("enabled", true))
		and not bool((技能.get(8808, {}) as Dictionary).get("enabled", true)),
		"余辉用掉后两颗技能都应置灰")

	# 天之弓：应战反击（is_active=false）命中圣类命格也应 +1 信仰。
	弓.tokens[0]["num"] = 0
	角色._持久进度 = 0
	检(角色.p_timeline_2_hit({"src": 1, "is_active": false, "card_id": 圣光[0]}) == BattleRole.SUCCESS,
		"应战命中结算不应报错")
	检(int(弓.tokens[0]["num"]) == 1, "应战反击命中圣类命格也应 +1 信仰")

	# 自动填充第一层只选资源，第二层再手选治疗/信仰；超时才按空位自动选。
	# 这两句是按钮文案：P4 时挂在「提示」列第 2/3 条，已按新口径搬进「按钮」列（idx0/1）。
	检(GConst.按钮原文(8807, 0).contains("水晶")
		and GConst.按钮原文(8807, 0).contains("治疗")
		and GConst.按钮原文(8807, 0).contains("信仰")
		and not GConst.按钮原文(8807, 0).contains("宝石")
		and not GConst.按钮原文(8807, 0).contains("（")
		and not GConst.按钮原文(8807, 0).contains("→"),
		"自动填充第一层水晶项不应再写括号里的宝石替代和箭头")
	检(GConst.按钮原文(8807, 1).contains("宝石")
		and GConst.按钮原文(8807, 1).contains("水晶")
		and GConst.按钮原文(8807, 1).contains("治疗")
		and GConst.按钮原文(8807, 1).contains("信仰")
		and not GConst.按钮原文(8807, 1).contains("→"),
		"自动填充第一层宝石项应写清扣除宝石、+1 水晶和两种效果，且不用箭头")
	# 第二层选项：玩家手选，治疗/信仰都始终可选（空位不足不置灰）；args=[资源, 效果]。
	var 填充窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	var 水晶二层: Array = 填充窗.call("_自动填充第二层选项", 1)
	检(水晶二层.size() == 2, "自动填充水晶第二层应有两个选项")
	检((水晶二层[0].get("args", []) as Array) == [1, 1]
		and bool(水晶二层[0].get("enabled", false)),
		"水晶 + 治疗应始终可选")
	检((水晶二层[1].get("args", []) as Array) == [1, 2]
		and bool(水晶二层[1].get("enabled", false)),
		"水晶 + 信仰应始终可选")
	var 宝石二层: Array = 填充窗.call("_自动填充第二层选项", 2)
	检((宝石二层[0].get("args", []) as Array) == [2, 1]
		and bool(宝石二层[0].get("enabled", false)),
		"宝石 +2 治疗应始终可选")
	检((宝石二层[1].get("args", []) as Array) == [2, 2]
		and bool(宝石二层[1].get("enabled", false)),
		"宝石 + 信仰应始终可选")

	# 头像指示器：未命中「移除治疗 / 目标弃牌」、圣流星弹「目标+治疗 / 自己付代价」、
	# 圣光爆裂群体「自己移除治疗+弃牌」、圣煌模式「自己付代价」。
	var 头像窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	var 我: int = Logic.my_player_id
	var 目标提示id: int = 3 if 我 != 3 else 4
	头像窗._mode = 3
	头像窗._skill_ask_id = 88021
	头像窗._已选参数 = [1]
	头像窗._sel_players.append(目标提示id)
	var 未中提示: Dictionary = 头像窗.call("_圣屑飓暴未命中头像提示")
	检(str(未中提示.get(我, "")) == "移除 1 治疗", "未命中应在自己头像写移除治疗")
	检(str(未中提示.get(目标提示id, "")) == "弃 1 张牌", "未命中应在队友头像写弃牌")
	头像窗._skill_ask_id = GConst.技能_圣流星弹Trick
	头像窗._已选参数 = [2]
	var 流星提示: Dictionary = 头像窗.call("_圣流星弹头像提示")
	检(str(流星提示.get(目标提示id, "")) == "+1 治疗", "圣流星弹应在目标头像写 +1 治疗")
	检(str(流星提示.get(我, "")).contains("移除 1 信仰"), "圣流星弹应在自己头像写信仰代价")
	头像窗._mode = 4
	头像窗._pending_skill_id = GConst.技能_圣光爆裂Trick
	头像窗._已选参数 = [1]
	头像窗._sel_players.clear()
	头像窗._sel_players.append(目标提示id)
	var 单爆裂提示: Dictionary = 头像窗.call("_圣光爆裂头像提示")
	检(str(单爆裂提示.get(我, "")).contains("+1 信仰"), "圣光爆裂单体应写自己会加的信仰")
	检(str(单爆裂提示.get(目标提示id, "")) == "2 攻击伤害", "圣光爆裂单体应写目标受到 2 点攻击伤害")
	头像窗._已选参数 = [2, 1]
	头像窗._sel_players.clear()
	var 爆裂提示: Dictionary = 头像窗.call("_圣光爆裂头像提示")
	检(str(爆裂提示.get(我, "")).contains("弃 1 张牌"), "圣光爆裂群体应写自己的弃牌代价")
	检(str(爆裂提示.get(我, "")).contains("+1 信仰"), "圣光爆裂群体应写自己会加的信仰")
	var 爆裂二层: Array = 头像窗.call("_圣光爆裂第二层选项", 3)
	检(爆裂二层.size() == 3, "圣光爆裂群体第二层应有 X=1/2/3 三档")
	if 爆裂二层.size() == 3:
		检(str(爆裂二层[0].get("text", "")) == "移除 1 治疗，弃 1 张牌，最多 1 名目标",
			"圣光爆裂 X=1 文案不对：%s" % str(爆裂二层[0].get("text", "")))
		检(str(爆裂二层[1].get("text", "")) == "移除 2 治疗，弃 2 张牌，最多 2 名目标",
			"圣光爆裂 X=2 文案不对：%s" % str(爆裂二层[1].get("text", "")))
		检(str(爆裂二层[2].get("text", "")) == "移除 3 治疗，弃 3 张牌，最多 3 名目标",
			"圣光爆裂 X=3 文案不对：%s" % str(爆裂二层[2].get("text", "")))
	var 爆裂说明: String = str(头像窗.call("_圣光爆裂群体说明", 2, 5))
	检(爆裂说明 == "选择最多 2 名手牌数小于 4 的对手，你弃 2 张牌，然后对他们造成（Y+2）点攻击伤害，Y为目标中拥有【治疗】的人数，你获得 2 点【信仰】。",
		"圣光爆裂群体说明应补齐目标、弃牌、手牌阈值和 Y 的定义：%s" % 爆裂说明)
	var 爆裂词缀: String = GConst.词缀文本(爆裂说明)
	检(not 爆裂词缀.contains("【治疗】") and 爆裂词缀.contains("[img="),
		"提示条动态说明里的【治疗】也应换成词缀图标：%s" % 爆裂词缀)
	检(str(头像窗.call("_圣光爆裂群体说明", 3, 2)).contains("无法发动"),
		"手牌不足支付弃牌时说明应写明无法发动")
	# 只要 1 名目标符合手牌条件，X=1/2/3 都应可选；不要求凑满 X 名目标。
	var 原玩家列表: Array[GPlayer] = []
	原玩家列表.append_array(Data.player_list)
	var 原我id: int = Logic.my_player_id
	Data.player_list.clear()
	var 假我: GPlayer = GPlayer.new(1, GConst.BLUE, "我")
	假我.hand_cards_num = 5
	假我.cross_num = 3
	var 假敌: GPlayer = GPlayer.new(2, GConst.RED, "敌")
	假敌.hand_cards_num = 2
	Data.player_list.append(假我)
	Data.player_list.append(假敌)
	Logic.my_player_id = 1
	var 少目标二层: Array = 头像窗.call("_圣光爆裂第二层选项", 3)
	var 少目标全可: bool = 少目标二层.size() == 3
	for 项: Dictionary in 少目标二层:
		少目标全可 = 少目标全可 and bool(项.get("enabled", false))
	检(少目标全可, "只有 1 名合法目标时，X=1/2/3 都应可选")
	Logic.my_player_id = 原我id
	Data.player_list.clear()
	Data.player_list.append_array(原玩家列表)
	头像窗._pending_skill_id = GConst.技能_圣煌模式Trick
	头像窗._已选参数 = [1]
	var 模式提示: Dictionary = 头像窗.call("_圣煌模式头像提示")
	检(str(模式提示.get(我, "")) == "移除 2 治疗", "圣煌模式应写自己的治疗代价")
	头像窗.free()
	填充窗.free()
	弓.tap = false

	# 只有水晶、治疗满：扣水晶，+1 信仰。
	var 问满治疗 := _问自动填充(引擎, 角色, 弓, 1, 0, 3, 0)
	检(not 问满治疗.is_empty(), "有能量时回合结束应询问自动填充")
	检(int((问满治疗.get("args", []) as Array)[3]) == 2, "自动填充应只发两个选项")
	检((问满治疗.get("option_enabled", []) as Array) == [true, false],
		"只有水晶时应只开放水晶项：%s" % str(问满治疗.get("option_enabled", [])))
	检(bool(问满治疗.get("can_cancel", true)) == false, "自动填充应要求选一项，不能取消")
	检(_答自动填充(引擎, 角色, [1, 2]) == BattleRole.SUCCESS, "手动选择水晶 + 信仰应结算完成")
	检(弓.crystal == 0 and 弓.cross_num == 3 and int(弓.tokens[0]["num"]) == 1,
		"水晶 + 信仰应扣水晶并 +1 信仰")
	引擎._清空等待()

	# 只有水晶、有 1 个空位：+1 治疗。
	_问自动填充(引擎, 角色, 弓, 1, 0, 2, 0)
	检(_答自动填充(引擎, 角色, [1, 1]) == BattleRole.SUCCESS, "水晶 + 治疗应结算")
	检(弓.crystal == 0 and 弓.cross_num == 3 and int(弓.tokens[0]["num"]) == 0,
		"水晶 + 治疗应扣水晶并 +1 治疗")
	引擎._清空等待()

	# 只有宝石：水晶/宝石两项都开放；选水晶项时用宝石替代，有 3 个空位 → +1 治疗。
	var 问宝石 := _问自动填充(引擎, 角色, 弓, 0, 1, 0, 0)
	var 宝石可用: Array = 问宝石.get("option_enabled", [])
	检(宝石可用.is_empty() or 宝石可用 == [true, true],
		"只有宝石时水晶/宝石两项都应开放：%s" % str(宝石可用))
	检(_答自动填充(引擎, 角色, [1, 1]) == BattleRole.SUCCESS, "只有宝石时选水晶 + 治疗应结算")
	检(弓.gem == 0 and 弓.crystal == 0 and 弓.cross_num == 1,
		"没有水晶时选水晶 + 治疗应改用 1 宝石换 1 治疗")
	引擎._清空等待()

	# 宝石项、2 个空位：+1 水晶 +2 治疗。
	_问自动填充(引擎, 角色, 弓, 0, 1, 1, 0)
	检(_答自动填充(引擎, 角色, [2, 1]) == BattleRole.SUCCESS, "宝石 + 治疗应结算")
	检(弓.gem == 0 and 弓.crystal == 1 and 弓.cross_num == 3
		and int(弓.tokens[0]["num"]) == 0,
		"宝石 + 治疗应 +2 治疗，不加信仰")
	引擎._清空等待()

	# 宝石项、只有 1 个空位（治疗 2/3）：+1 水晶 +2 信仰（例子）。
	_问自动填充(引擎, 角色, 弓, 0, 1, 2, 0)
	检(_答自动填充(引擎, 角色, [2, 2]) == BattleRole.SUCCESS, "宝石 + 信仰应结算")
	检(弓.gem == 0 and 弓.crystal == 1 and 弓.cross_num == 2
		and int(弓.tokens[0]["num"]) == 2,
		"宝石 + 信仰应 +1 水晶 +2 信仰")
	引擎._清空等待()

	# 玩家手选治疗，即使空位不足也只加治疗，不自动改信仰。
	_问自动填充(引擎, 角色, 弓, 1, 0, 3, 0)
	检(_答自动填充(引擎, 角色, [1, 1]) == BattleRole.SUCCESS, "手选水晶 + 治疗应结算")
	检(弓.crystal == 0 and 弓.cross_num == 3 and int(弓.tokens[0]["num"]) == 0,
		"治疗满时手选治疗应只扣水晶，不自动加信仰")
	引擎._清空等待()
	_问自动填充(引擎, 角色, 弓, 0, 1, 2, 0)
	检(_答自动填充(引擎, 角色, [2, 1]) == BattleRole.SUCCESS, "手选宝石 + 治疗应结算")
	检(弓.gem == 0 and 弓.crystal == 1 and 弓.cross_num == 3
		and int(弓.tokens[0]["num"]) == 0,
		"只有 1 个空位时手选 +2 治疗应只补到上限，不自动加信仰")
	引擎._清空等待()

	# 超时同时有水晶和宝石、2 个空位：优先宝石，+1 水晶 +2 治疗。
	_问自动填充(引擎, 角色, 弓, 1, 1, 1, 0)
	检(_答自动填充(引擎, 角色, [0]) == BattleRole.SUCCESS, "超时应结算")
	检(弓.gem == 0 and 弓.crystal == 2 and 弓.cross_num == 3
		and int(弓.tokens[0]["num"]) == 0,
		"同时有水晶/宝石且有空位时，超时应优先用宝石加治疗")
	引擎._清空等待()

	# 超时同时有水晶和宝石、只有 1 个空位：优先宝石，+1 水晶 +2 信仰（例子）。
	_问自动填充(引擎, 角色, 弓, 1, 1, 2, 0)
	检(_答自动填充(引擎, 角色, [0]) == BattleRole.SUCCESS, "超时空位不足应结算")
	检(弓.gem == 0 and 弓.crystal == 2 and 弓.cross_num == 2
		and int(弓.tokens[0]["num"]) == 2,
		"治疗 2/3 时超时应用宝石改 +2 信仰")
	引擎._清空等待()

	# 超时只有水晶、治疗满：扣水晶，+1 信仰。
	_问自动填充(引擎, 角色, 弓, 1, 0, 3, 0)
	检(_答自动填充(引擎, 角色, [0]) == BattleRole.SUCCESS, "只有水晶时超时应结算")
	检(弓.crystal == 0 and 弓.cross_num == 3 and int(弓.tokens[0]["num"]) == 1,
		"只有水晶且治疗满时，超时应 +1 信仰")
	引擎._清空等待()

	# 超时只有宝石、只有 1 个空位：+1 水晶 +2 信仰。
	_问自动填充(引擎, 角色, 弓, 0, 1, 2, 0)
	检(_答自动填充(引擎, 角色, [0]) == BattleRole.SUCCESS, "只有宝石时超时应结算")
	检(弓.gem == 0 and 弓.crystal == 1 and 弓.cross_num == 2
		and int(弓.tokens[0]["num"]) == 2,
		"只有宝石且空位不足时，超时应 +2 信仰")
	引擎._清空等待()

	# 没有水晶也没有宝石时根本不问。
	检(_问自动填充(引擎, 角色, 弓, 0, 0, 0, 0).is_empty(), "没有能量时不应发问")
	检(引擎._await_id < 0, "没有能量时不应发出自动填充询问")

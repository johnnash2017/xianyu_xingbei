extends 自检用例
## R87 贪婪少女（87）：8701 贪欲黑洞 / 8702 殓金魔法 / 8703 炼金术 / 8704 亡女的金库。
##
## 任务范围只有 role + test：角色表「脚本」列、技能表「提示」列留给 DATA 任务，
## 所以这里手动把角色挂到玩家 1 身上，提示文案只检查「有下发询问 / 选项 / 固定目标」。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 四颗技能行 / 技能说明 / 脚本文件；
##   - 8703：技能栏入口、雷/火系牌可当【魔弹】（主动使用 + 响应传递），水系牌不行；
##            发动牌与落点校验；真实结算（弃发动牌 → 魔弹传递询问 → 目标放弃吃 2 点法术伤害）；
##   - 8702：自己使用【魔弹】造成伤害后⑥ → 我方战绩区 +1 水晶；非魔弹来源 / 别人 /
##            0 点伤害不触发；完整魔弹流水线里真实触发；
##   - 8701：技能栏 / 校验（法术牌 / 对手 / 重复 / 不在手牌 / 回合限定）；
##            目标弃牌 → 不结算惩罚；目标不弃（取消 / 非法牌 / 没有法术牌）→ 2 点法术伤害
##            + 自己 +1 法术行动；发动后本回合 8704 置灰并被校验驳回，回合开始解锁；
##   - 8704：校验（能量 / 2 名对手 / 重复 / 队友 / 被 8701 锁）；无星石不弹额外移除询问；
##            额外移除全部星石：每 2 星石 +1 伤害、宝石 ≥2 时伤害结算完后转移对方 1 点士气；
##            宝石只有 1 颗不转移；选择「不额外移除」时战绩区不动、伤害不成长；
##            额外移除询问取消＝这次不发动（不扣费、不结算、不消耗行动计数）；
##   - 回合边界：p_before_turn_begin 清回合限定与 8701 对 8704 的封锁。
##
## 提示列 8701~8704 目前为空（DATA 任务补齐），用例不依赖提示文案。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_tanlanshaonv.gd")

const 技能贪欲黑洞: int = 8701
const 技能殓金魔法: int = 8702
const 技能炼金术: int = 8703
const 技能亡女的金库: int = 8704

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 靶: BattlePlayer = null
var 队友: BattlePlayer = null
## 第二名对手（玩家 4）
var 靶2: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 魔弹牌: GCard = null
var 雷攻击: GCard = null
var 火攻击: GCard = null
var 水攻击: GCard = null
var 火法术: GCard = null
var 雷法术: GCard = null
var 水法术: GCard = null


func _init() -> void:
	名称 = "贪婪少女"


# ============================================================
# 找牌 / 查消息
# ============================================================
## 卡库里第一张满足条件的非虚拟牌
func _取牌(条件: Callable) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if bool(条件.call(c)):
			return c
	return null


## 把一张牌从牌堆 / 弃牌堆移到某人手里（模拟真实持有）
func _给牌(持有者: BattlePlayer, cid: int) -> void:
	引擎.deck.remove_one(cid)
	持有者.add_hand_cards([cid])


func _找技能(表: Array, id: int) -> Dictionary:
	for sk: Dictionary in 表:
		if int(sk.get("id", 0)) == id:
			return sk
	return {}


## 最近一次下发给某玩家的询问里，是否有指定 respond_id 的那条
func _取询问(pid: int, respond_id: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == respond_id:
			return r
	return {}


## 给某玩家下发过几次指定 respond_id 的询问（按实际发送记录数，重发也算）
func _询问次数(pid: int, respond_id: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.CmdReq or int(r.get("pid", -1)) != pid:
			continue
		for c: Dictionary in (r.get("data", {}) as Dictionary).get("commands", []):
			if int(c.get("respond_id", 0)) == respond_id:
				n += 1
	return n


## 在发送记录里找一条满足条件的广播消息
func _找消息(消息类型: int, 条件: Callable) -> Dictionary:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != 消息类型:
			continue
		var 数据: Dictionary = r.get("data", {})
		if bool(条件.call(数据)):
			return 数据
	return {}


## 某技能号播报过几次
func _播报次数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Skill:
			continue
		if int((r.get("data", {}) as Dictionary).get("skill_id", 0)) == 技能号:
			n += 1
	return n


## 某技能号造成的伤害有几条
func _伤害条数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Hurt:
			continue
		if int((r.get("data", {}) as Dictionary).get("cause", 0)) == 技能号:
			n += 1
	return n


## 发送记录里有没有「把 cid 视为【魔弹】打出」的用牌广播（as_card_id 是【魔弹】牌号）
func _有视为魔弹(cid: int, 魔弹id: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Card:
			continue
		var 数据: Dictionary = r.get("data", {})
		if int(数据.get("as_card_id", 0)) == 魔弹id \
				and (数据.get("card_ids", []) as Array).has(cid):
			return true
	return false


## 状态栈里找一条指定来源 / 目标的伤害，返回它的伤害字典；找不到返回空字典
func _找伤害(cause: int, dst: int) -> Dictionary:
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var h: Variant = st.get("harm")
		if h is Dictionary and int((h as Dictionary).get("cause", 0)) == cause \
				and int((h as Dictionary).get("dst", -1)) == dst:
			return h as Dictionary
	return {}


## 当前状态栈顶若是行动阶段，返回它的关键字段（不是就返回空字典）
func _取行动阶段() -> Dictionary:
	var 顶: Variant = 引擎._states[-1] if not 引擎._states.is_empty() else null
	if not (顶 is BattleEngine.SActionPhase):
		return {}
	var 阶段: BattleEngine.SActionPhase = 顶
	return {
		"额外": bool(阶段.get("额外")),
		"允许": int(阶段.get("允许")),
		"来源": int(阶段.get("额外来源")),
		"可放弃": bool(阶段.get("可放弃")),
	}


# ============================================================
# 战斗重置 / 上下文
# ============================================================
func _清空玩家(p0: BattlePlayer) -> void:
	p0.hand_cards.clear()
	p0.cover_cards.clear()
	p0.basic_effects.clear()
	p0.cross_num = 0
	p0.set_crystal(0)
	p0.set_gem(0)
	p0.additional_actions.clear()
	p0.boot_skill_used = false
	p0.hand_cards_max = GConst.HAND_CARDS_MAX
	p0.reattacker = -1
	p0.reset_action_counts()


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
	引擎.本回合跳过行动阶段 = false
	引擎.team_gem = [0, 0]
	引擎.team_crystal = [0, 0]
	引擎.team_grail = [0, 0]
	引擎.team_morale = [引擎.士气上限(), 引擎.士气上限()]
	发送记录.clear()
	_清空玩家(玩家)
	_清空玩家(靶)
	_清空玩家(队友)
	_清空玩家(靶2)
	角色.p_before_turn_begin({})


## 直接给角色钩子喂一条回复（不经过引擎的 run 循环）
func _应答(args: Array, cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": []}
	引擎._has_reply = true


func _魔法动作(aid: int, cards: Array, dsts: Array, args: Array = []) -> Dictionary:
	var 动作: Dictionary = {"src_id": 1, "action_id": aid, "card_ids": cards, "dst_ids": dsts}
	if not args.is_empty():
		动作["args"] = args
	return 动作


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 ----
	检(str(Data.role_list.get(87, "")) == "贪婪少女", "87 号角色名不是「贪婪少女」")
	检(Data.role_personal_name(87) == "妮亚", "87 号角色姓名不是「妮亚」")
	检(absf(Data.role_star(87) - 3.0) < 0.01, "贪婪少女应是 3.0 星，实际 %s" % str(Data.role_star(87)))
	检(Data.role_skills(87) == [8701, 8702, 8703, 8704],
		"贪婪少女技能号不对：%s" % str(Data.role_skills(87)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_tanlanshaonv.gd"),
		"贪婪少女的角色脚本文件不存在")
	for 技能号: int in [8701, 8702, 8703, 8704]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	检(GConst.技能号("技能#贪婪少女#贪欲黑洞") == 8701, "【贪欲黑洞】技能号应为 8701")
	检(GConst.技能号("技能#贪婪少女#殓金魔法") == 8702, "【殓金魔法】技能号应为 8702")
	检(GConst.技能号("技能#贪婪少女#炼金术") == 8703, "【炼金术】技能号应为 8703")
	检(GConst.技能号("技能#贪婪少女#亡女的金库") == 8704, "【亡女的金库】技能号应为 8704")
	var 技能说明: String = Data.role_skill_info(87)
	for 技能名: String in ["贪欲黑洞", "殓金魔法", "炼金术", "亡女的金库"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提 ----
	魔弹牌 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() == GConst.CardName.Missile)
	雷攻击 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.element_enum() == GConst.CardElement.Thunder)
	火攻击 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.element_enum() == GConst.CardElement.Fire)
	水攻击 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.element_enum() == GConst.CardElement.Water)
	火法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Fire and c.card_name_enum() != GConst.CardName.Missile)
	雷法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Thunder and c.card_name_enum() != GConst.CardName.Missile)
	水法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Water and c.card_name_enum() != GConst.CardName.Missile)
	检(魔弹牌 != null, "卡库找不到【魔弹】牌")
	检(雷攻击 != null, "卡库找不到雷系攻击牌")
	检(火攻击 != null, "卡库找不到火系攻击牌")
	检(水攻击 != null, "卡库找不到水系攻击牌")
	检(火法术 != null, "卡库找不到非魔弹的火系法术牌")
	检(雷法术 != null, "卡库找不到非魔弹的雷系法术牌")
	检(水法术 != null, "卡库找不到非魔弹的水系法术牌")
	if 魔弹牌 == null or 雷攻击 == null or 火攻击 == null or 水攻击 == null \
			or 火法术 == null or 雷法术 == null or 水法术 == null:
		return

	# ---- 建引擎：1 / 3 蓝，2 / 4 红；角色表脚本列留给 DATA，用例里手动挂上角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "贪婪")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "对手2")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	靶 = 引擎.p(2)
	队友 = 引擎.p(3)
	靶2 = 引擎.p(4)
	玩家.role_id = 87
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	_重置战斗()

	# ============================================================
	# 技能栏：8701 / 8703 / 8704 都照常下发，条件不满足只置灰
	# ============================================================
	var 栏: Array = 角色.available_skills()
	检(栏.size() == 3, "贪婪少女技能栏应有 3 项（8701 / 8703 / 8704），实际 %d 项：%s"
		% [栏.size(), str(栏)])
	var 黑洞项: Dictionary = _找技能(栏, 技能贪欲黑洞)
	var 炼金项: Dictionary = _找技能(栏, 技能炼金术)
	var 金库项: Dictionary = _找技能(栏, 技能亡女的金库)
	检(not 黑洞项.is_empty() and not 炼金项.is_empty() and not 金库项.is_empty(),
		"技能栏缺少 8701 / 8703 / 8704 中的某一项：%s" % str(栏))
	if 黑洞项.is_empty() or 炼金项.is_empty() or 金库项.is_empty():
		return
	检(int(黑洞项.get("type", 0)) == GConst.ActionType.MagicSkill, "8701 应作为法术技能按钮下发")
	检(int(黑洞项.get("need_card", 0)) == 1 and int(黑洞项.get("need_target", 0)) == 1,
		"8701 应要求 1 张法术牌 + 1 名目标")
	检(not bool(黑洞项.get("enabled", true)), "手里没有法术牌时 8701 应置灰")
	检(int(炼金项.get("type", 0)) == GConst.ActionType.MagicSkill, "8703 应作为法术技能按钮下发")
	检(int(炼金项.get("need_card", 0)) == 1 and int(炼金项.get("need_target", 0)) == 1,
		"8703 应要求 1 张发动牌 + 1 名目标")
	检(not bool(炼金项.get("enabled", true)), "手里没有雷/火系牌时 8703 应置灰")
	检(int(金库项.get("type", 0)) == GConst.ActionType.MagicSkill, "8704 应作为法术技能按钮下发")
	检(int(金库项.get("need_card", 0)) == 0 and int(金库项.get("need_target", 0)) == 0,
		"8704 应要求 0 张发动牌，目标由二级技能栏的选项给（本体 need_target = 0）")
	检(not bool(金库项.get("enabled", true)), "没有能量时 8704 应置灰")

	_给牌(玩家, 火法术.id)
	黑洞项 = _找技能(角色.available_skills(), 技能贪欲黑洞)
	检(bool(黑洞项.get("enabled", false)), "有法术牌与对手时 8701 应可点")
	检((黑洞项.get("cards", []) as Array).has(火法术.id), "8701 的牌表应包含手里的法术牌")
	检((黑洞项.get("targets", []) as Array) == [2, 4],
		"8701 的目标白名单应是两名对手：%s" % str(黑洞项.get("targets", [])))

	_给牌(玩家, 雷攻击.id)
	_给牌(玩家, 火攻击.id)
	_给牌(玩家, 水攻击.id)
	_给牌(玩家, 魔弹牌.id)
	炼金项 = _找技能(角色.available_skills(), 技能炼金术)
	检(bool(炼金项.get("enabled", false)), "有雷/火系牌与对手时 8703 应可点")
	检((炼金项.get("cards", []) as Array).has(雷攻击.id), "8703 的牌表应包含雷系牌")
	检((炼金项.get("cards", []) as Array).has(火攻击.id), "8703 的牌表应包含火系牌")
	检(not (炼金项.get("cards", []) as Array).has(水攻击.id), "8703 的牌表不应包含水系牌")
	检(not (炼金项.get("cards", []) as Array).has(魔弹牌.id),
		"8703 的融合牌表不应包含【魔弹】本体（它走普通魔弹行动）")
	检(角色.missile_targets(1) == [2], "没有【魔弹掌控】时落点只有右手边最近的对手：%s"
		% str(角色.missile_targets(1)))

	玩家.set_crystal(1)
	金库项 = _找技能(角色.available_skills(), 技能亡女的金库)
	检(bool(金库项.get("enabled", false)), "有能量与 2 名对手时 8704 应可点")
	检((金库项.get("targets", []) as Array) == [2, 4],
		"8704 的目标白名单应是两名对手：%s" % str(金库项.get("targets", [])))

	# ============================================================
	# 8703 炼金术：系别配置 / 牌类校验 / 发动校验
	# ============================================================
	检(角色.missile_fusion_elements() == [GConst.CardElement.Thunder, GConst.CardElement.Fire],
		"8703 的可当魔弹系别应为雷 / 火：%s" % str(角色.missile_fusion_elements()))
	检(int(角色.missile_fusion_skill()) == 8703, "8703 的魔弹融合播报号应为 8703，不借用 803/7602")
	# 头像提示：落点要写「2 法术伤害」（同魔弹融合 803 / 节日魔导 7602）
	var 融合提示: Dictionary = GConst.技能指示器.get(8703, {})
	检(int(融合提示.get("每目标", 0)) == GConst.魔弹基础伤害
		and str(融合提示.get("文案", "")) == "%d 法术伤害",
		"8703 的头像提示应按魔弹基础伤害写「%%d 法术伤害」：%s" % str(融合提示))
	检(角色.v_missile(雷攻击.id, 2) == GConst.GE_SUCCESS, "雷系牌应能当【魔弹】使用")
	检(角色.v_missile(火攻击.id, 2) == GConst.GE_SUCCESS, "火系牌应能当【魔弹】使用")
	检(角色.v_missile(魔弹牌.id, 2) == GConst.GE_SUCCESS, "【魔弹】本体应能使用")
	检(角色.v_missile(水攻击.id, 2) != GConst.GE_SUCCESS, "水系牌不能当【魔弹】使用")
	检(角色.v_remissile(雷攻击.id) == GConst.GE_SUCCESS, "雷系牌应能继续传递魔弹")
	检(角色.v_remissile(火攻击.id) == GConst.GE_SUCCESS, "火系牌应能继续传递魔弹")
	检(角色.v_remissile(水攻击.id) != GConst.GE_SUCCESS, "水系牌不能继续传递魔弹")

	var 炼金动作: Dictionary = _魔法动作(技能炼金术, [雷攻击.id], [2])
	检(角色.v_magic_skill(炼金动作) == GConst.GE_SUCCESS, "合法的 8703 应通过校验")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 8703, "card_ids": [雷攻击.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "别人的 8703 行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8701, "card_ids": [雷攻击.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "不是 8703 的法术技能行动不应通过校验（雷系攻击牌不是法术牌）")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8703, "card_ids": [水攻击.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "水系牌不能作为 8703 的发动牌")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8703, "card_ids": [雷攻击.id], "dst_ids": [4]})
		!= GConst.GE_SUCCESS, "没有【魔弹掌控】时不能把落点选成逆向那个对手")

	# ============================================================
	# 8703 炼金术：完整结算（魔弹传递 → 目标放弃 → 8702 加水晶）
	# ============================================================
	_重置战斗()
	_给牌(玩家, 雷攻击.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 炼金动作)
	引擎.run()
	检(not 玩家.has_hand_card(雷攻击.id), "8703 的发动牌应离手")
	检(引擎.deck.discard.has(雷攻击.id), "8703 的发动牌应进弃牌堆")
	检(引擎._await_id == 2, "8703 打出后应等目标应答魔弹（等待 %s）" % str(引擎._await_id))
	检(not _取询问(2, GConst.RespondType.Bullet).is_empty(), "没有下发魔弹传递询问")
	检(_播报次数(技能炼金术) == 1, "8703 发动应播报一次，实际 %d 次" % _播报次数(技能炼金术))
	检(_有视为魔弹(雷攻击.id, 魔弹牌.id),
		"雷系牌当魔弹打出时应把 as_card_id 标成【魔弹】")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(靶.hand_cards.size() == BattleEngine.MISSILE_BASE_POINT,
		"8703 的魔弹 2 点法术伤害应让目标摸 2 张，实际 %d 张" % 靶.hand_cards.size())
	检(引擎.team_crystal[GConst.BLUE] == 1,
		"8703 的魔弹造成伤害后 8702 应让我方战绩区 +1 水晶，实际 %d"
		% 引擎.team_crystal[GConst.BLUE])
	检(_播报次数(技能殓金魔法) == 1,
		"8702 应播报一次，实际 %d 次" % _播报次数(技能殓金魔法))
	检(_伤害条数(GConst.CAUSE_MISSILE) == 1, "应有一条【魔弹】来源的伤害")

	# ============================================================
	# 8702 殓金魔法：直接喂⑥钩子
	# ============================================================
	_重置战斗()
	发送记录.clear()
	var 魔弹伤害: Dictionary = {
		"src": 1, "dst": 2, "point": 2,
		"cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic,
	}
	检(角色.p_timeline_6({"harm": 魔弹伤害, "src": 1, "dst": 2}) == BattleRole.SUCCESS,
		"8702 的⑥钩子应正常返回")
	检(引擎.team_crystal[GConst.BLUE] == 1, "8702 应给我方战绩区 +1 水晶")
	检(_播报次数(技能殓金魔法) == 1, "8702 应播报一次")
	检(角色.p_timeline_6({"harm": {"src": 1, "dst": 2, "point": 1,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack}, "src": 1, "dst": 2})
		== BattleRole.SUCCESS, "非魔弹伤害不应报错")
	检(引擎.team_crystal[GConst.BLUE] == 1, "非魔弹来源的伤害不应触发 8702")
	检(角色.p_timeline_6({"harm": {"src": 2, "dst": 1, "point": 2,
		"cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic}, "src": 2, "dst": 1})
		== BattleRole.SUCCESS, "别人使用的魔弹不应报错")
	检(引擎.team_crystal[GConst.BLUE] == 1, "别人使用的魔弹不应触发本角色的 8702")
	检(角色.p_timeline_6({"harm": {"src": 1, "dst": 2, "point": 0,
		"cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic}, "src": 1, "dst": 2})
		== BattleRole.SUCCESS, "0 点伤害不应报错")
	检(引擎.team_crystal[GConst.BLUE] == 1, "0 点伤害不应触发 8702")

	# ============================================================
	# 8701 贪欲黑洞：校验
	# ============================================================
	_重置战斗()
	_给牌(玩家, 火法术.id)
	_给牌(玩家, 水法术.id)
	_给牌(玩家, 水攻击.id)
	var 黑洞动作: Dictionary = _魔法动作(技能贪欲黑洞, [火法术.id], [2])
	检(角色.v_magic_skill(黑洞动作) == GConst.GE_SUCCESS, "合法的 8701 应通过校验")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 8701, "card_ids": [火法术.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "别人的 8701 行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8704, "card_ids": [火法术.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "不是 8701 的法术技能行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8701, "card_ids": [水攻击.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "攻击牌不能作为 8701 的代价（技能原文是弃法术牌）")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8701,
		"card_ids": [火法术.id, 水法术.id], "dst_ids": [2]}) != GConst.GE_SUCCESS,
		"8701 只能弃 1 张法术牌")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8701,
		"card_ids": [火法术.id], "dst_ids": [2, 4]}) != GConst.GE_SUCCESS,
		"8701 只能指定 1 名目标对手")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8701,
		"card_ids": [火法术.id], "dst_ids": [3]}) != GConst.GE_SUCCESS,
		"8701 不能指定队友为目标")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8701,
		"card_ids": [火法术.id], "dst_ids": []}) != GConst.GE_SUCCESS,
		"8701 没有目标时应驳回")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 8701,
		"card_ids": [火法术.id, 火法术.id], "dst_ids": [2]}) != GConst.GE_SUCCESS,
		"8701 同一张牌提交两次应驳回")
	var 不在手牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic() and not 玩家.hand_cards.has(c.id):
			不在手牌 = c
			break
	检(不在手牌 != null, "找不到一张不在手里的法术牌")
	if 不在手牌 != null:
		检(角色.v_magic_skill({"src_id": 1, "action_id": 8701,
			"card_ids": [不在手牌.id], "dst_ids": [2]}) != GConst.GE_SUCCESS,
			"不在手里的牌不能作为 8701 的代价")

	# ============================================================
	# 8701 贪欲黑洞：目标弃牌 → 不结算惩罚；发动后本回合锁 8704
	# ============================================================
	_重置战斗()
	_给牌(玩家, 火法术.id)
	_给牌(靶, 水法术.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 黑洞动作)
	引擎.run()
	检(引擎._await_id == 2, "8701 结算后应让目标选择弃牌（等待 %s）" % str(引擎._await_id))
	检(not 玩家.has_hand_card(火法术.id), "8701 的代价牌应离手")
	检(引擎.deck.discard.has(火法术.id), "8701 的代价牌应进弃牌堆")
	检(引擎.team_crystal[GConst.BLUE] == 1, "8701 应让我方战绩区 +1 水晶")
	检(_播报次数(技能贪欲黑洞) == 1, "8701 发动应播报一次，实际 %d 次" % _播报次数(技能贪欲黑洞))
	检(not _找消息(GConst.Msg.Card,
		func(数据: Dictionary) -> bool:
			return int(数据.get("type", 0)) == GConst.CardMsgType.Show \
				and (数据.get("card_ids", []) as Array).has(火法术.id)).is_empty(),
		"8701 的代价牌应【展示】给所有人")
	var 弃牌问: Dictionary = _取询问(2, 技能贪欲黑洞)
	检(not 弃牌问.is_empty(), "没有向目标下发 8701 弃牌询问")
	检(str(弃牌问.get("card_rule", "")) == "magic", "8701 让目标弃的必须是法术牌")
	检(bool(弃牌问.get("can_cancel", false)), "8701 的目标可以选择不弃（技能原文「若他不如此做」）")
	# 和 801 一样不额外下发白名单：靠 card_rule = magic 让界面把非法术牌置灰
	检((弃牌问.get("card_ids", []) as Array).is_empty(),
		"8701 的询问不再下发牌白名单（靠 card_rule 置灰）：%s" % str(弃牌问.get("card_ids", [])))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 8701, "src_id": 2, "args": [1], "card_ids": [水法术.id], "dst_ids": [],
	})
	检(not 靶.hand_cards.has(水法术.id), "目标弃出的法术牌应离手")
	检(引擎.deck.discard.has(水法术.id), "目标弃出的法术牌应进弃牌堆")
	检(_伤害条数(技能贪欲黑洞) == 0, "目标弃牌后不应再造成 8701 的伤害")
	检(玩家.additional_actions.is_empty(), "目标弃牌后不应给额外法术行动")
	# 回合限定 + 本回合锁 8704：能量拉满也发不动
	玩家.set_crystal(1)
	检(角色.v_magic_skill(黑洞动作) != GConst.GE_SUCCESS, "8701 回合限定用过后不应再通过校验")
	检(not bool(_找技能(角色.available_skills(), 技能亡女的金库).get("enabled", true)),
		"8701 发动后本回合 8704 应置灰")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 4])) != GConst.GE_SUCCESS,
		"8701 发动后本回合 8704 的硬提交应被驳回")
	# 回合开始解锁
	引擎.current_id = 1
	角色.p_before_turn_begin({})
	检(bool(_找技能(角色.available_skills(), 技能亡女的金库).get("enabled", false)),
		"新回合 8704 应重新可点")
	_给牌(玩家, 火法术.id)
	检(bool(_找技能(角色.available_skills(), 技能贪欲黑洞).get("enabled", false)),
		"新回合 8701 应重新可点")

	# ============================================================
	# 8701 贪欲黑洞：目标不弃（取消）→ 2 点法术伤害 + 自己 +1 法术行动
	# ============================================================
	_重置战斗()
	_给牌(玩家, 火法术.id)
	_给牌(靶, 水法术.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 黑洞动作)
	引擎.run()
	检(引擎._await_id == 2, "8701 结算后应等目标选择弃牌")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 8701, "src_id": 2, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(靶.hand_cards.has(水法术.id), "目标不弃时其法术牌应留在手里")
	检(_伤害条数(技能贪欲黑洞) == 1, "目标不弃时应造成 1 条 8701 法术伤害")
	var 黑洞伤害条: Dictionary = _找消息(GConst.Msg.Hurt,
		func(数据: Dictionary) -> bool: return int(数据.get("cause", 0)) == 8701)
	检(not 黑洞伤害条.is_empty(), "没有找到 8701 的伤害广播")
	检(int(黑洞伤害条.get("hurt", 0)) == 2, "8701 的伤害应为 2 点：%s" % str(黑洞伤害条))
	检(int(黑洞伤害条.get("type", -1)) == GConst.HarmType.Magic, "8701 的伤害应是法术伤害")
	检(int(黑洞伤害条.get("src_id", -1)) == 1, "8701 的伤害来源应是发动者")
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 技能贪欲黑洞,
		"8701 应直接进入自己的额外法术行动（当前 %d / 额外 %s / 来源 %s）"
		% [引擎.current_id, str(引擎.行动额外), str(引擎.行动额外来源)])
	var 额外阶段: Dictionary = _取行动阶段()
	检(not 额外阶段.is_empty(), "8701 的额外行动应进入行动阶段")
	检(int(额外阶段.get("允许", 0)) == GConst.ActionType.Magic, "8701 的额外行动应只允许法术")
	检(bool(额外阶段.get("可放弃", false)), "8701 的额外行动阶段应允许放弃")
	检(玩家.magic_action_count == 1, "8701 本身应记 1 次法术行动")
	# 放弃额外行动，正常结束回合
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.None, "action_id": 0, "src_id": 1,
		"card_ids": [], "dst_ids": [], "args": [],
	})
	检(引擎.current_id == 2, "放弃 8701 的额外行动后应轮到下家，实际 %d" % 引擎.current_id)

	# 目标没有法术牌：也照问一次（参考 801），界面上无牌可点，只能取消 → 结算惩罚
	_重置战斗()
	_给牌(玩家, 火法术.id)
	_给牌(靶, 雷攻击.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 黑洞动作)
	引擎.run()
	检(_询问次数(2, 技能贪欲黑洞) == 1, "目标没有法术牌时也要下发弃牌询问")
	var 空问: Dictionary = _取询问(2, 技能贪欲黑洞)
	检(not 空问.is_empty(), "目标没有法术牌时也应下发询问")
	检(bool(空问.get("can_cancel", false)), "没有法术牌时可取消（＝不弃）")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 技能贪欲黑洞, "src_id": 2, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(_伤害条数(技能贪欲黑洞) == 1, "目标没有法术牌（取消）时应结算 2 点法术伤害")
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 技能贪欲黑洞,
		"目标没有法术牌时也应给自己 +1 法术行动（当前 %d / 额外 %s / 来源 %s）"
		% [引擎.current_id, str(引擎.行动额外), str(引擎.行动额外来源)])
	检(靶.hand_cards.size() == 1 + 2, "目标挨 2 点法术伤害应摸 2 张（1+2=3），实际 %d 张"
		% 靶.hand_cards.size())

	# 硬提交非法牌（攻击牌）：按「不弃」处理
	_重置战斗()
	_给牌(玩家, 火法术.id)
	_给牌(靶, 水法术.id)
	_给牌(靶, 雷攻击.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 黑洞动作)
	引擎.run()
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 8701, "src_id": 2, "args": [1], "card_ids": [雷攻击.id], "dst_ids": [],
	})
	检(靶.hand_cards.has(雷攻击.id), "硬提交的非法术牌不应离手")
	检(靶.hand_cards.has(水法术.id), "硬提交非法术牌时目标应保留自己的法术牌")
	检(_伤害条数(技能贪欲黑洞) == 1, "硬提交非法术牌应按「不弃」结算 2 点法术伤害")
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 技能贪欲黑洞,
		"硬提交非法术牌时也应给自己 +1 法术行动（当前 %d / 额外 %s / 来源 %s）"
		% [引擎.current_id, str(引擎.行动额外), str(引擎.行动额外来源)])

	# ============================================================
	# 8704 亡女的金库：校验（选项值随 action 一起提交，args[0] = 0 不移除 / 1 额外移除）
	# ============================================================
	_重置战斗()
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 4], [0])) != GConst.GE_SUCCESS,
		"没有能量时 8704 应被驳回")
	玩家.set_crystal(1)
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 4], [0])) == GConst.GE_SUCCESS,
		"有能量 + 2 名对手 + 合法选项值时 8704 应通过校验")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 4], [1])) == GConst.GE_SUCCESS,
		"额外移除那一档也应通过校验")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 4])) != GConst.GE_SUCCESS,
		"没带选项值（没在二级技能栏选档）应驳回")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 4], [2])) != GConst.GE_SUCCESS,
		"选项值越界应驳回")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 2], [0])) != GConst.GE_SUCCESS,
		"8704 不能把同一名对手点两次")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2], [0])) != GConst.GE_SUCCESS,
		"8704 必须指定 2 名目标对手")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 3], [0])) != GConst.GE_SUCCESS,
		"8704 不能指定队友")
	检(角色.v_magic_skill(_魔法动作(技能亡女的金库, [], [2, 4, 3], [0])) != GConst.GE_SUCCESS,
		"8704 不能指定 3 名目标")

	# 技能栏：同【魔眼】一样带选项进二级技能栏，本体不给目标数（选完档才放开点头像）
	var 栏金库: Dictionary = _找技能(角色.available_skills(), 技能亡女的金库)
	检(int(栏金库.get("need_target", -1)) == 0, "8704 本体不应要求先选目标（选完档才放开）")
	var 栏选项: Array = 栏金库.get("arg_choices", [])
	检(栏选项.size() == 2, "8704 应下发两个星石档选项：%s" % str(栏选项))
	if 栏选项.size() == 2:
		检(str((栏选项[0] as Dictionary).get("text", "")).contains("【战绩区】"),
			"8704 选项文案应写【战绩区】：%s" % str(栏选项[0]))
		检(int((栏选项[0] as Dictionary).get("need_target", 0)) == 2
			and int((栏选项[1] as Dictionary).get("need_target", 0)) == 2,
			"两档都应带「选 2 名对手」")
		检(not (栏选项[0] as Dictionary).get("text", "").contains("士气转移"),
			"宝石不够时不应追加士气转移说明")

	# 宝石 ≥ 2 时，额外移除那一档后面要追加士气转移的说明
	引擎.set_team_gem(GConst.BLUE, 2)
	var 宝石项: Array = _找技能(角色.available_skills(), 技能亡女的金库).get("arg_choices", [])
	检(宝石项.size() == 2
		and str((宝石项[1] as Dictionary).get("text", "")).contains("将对方 1 点士气转移给我方"),
		"宝石 ≥ 2 时额外移除档应追加士气转移说明：%s" % str(宝石项))

	# ============================================================
	# 8704：战绩区为空、选「不额外移除」→ 每目标 1 点法术伤害、扣 1 能量、不弹询问
	# ============================================================
	_重置战斗()
	玩家.set_crystal(1)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _魔法动作(技能亡女的金库, [], [2, 4], [0]))
	引擎.run()
	检(_询问次数(1, 技能亡女的金库) == 0, "选完档直接结算，不应再补问一次")
	检(玩家.get_energy() == 0, "8704 应支付 1 点能量，实际剩 %d" % 玩家.get_energy())
	检(靶.hand_cards.size() == 1 and 靶2.hand_cards.size() == 1,
		"8704 应对两名目标各造成 1 点法术伤害（各摸 1 张），实际 %d / %d 张"
		% [靶.hand_cards.size(), 靶2.hand_cards.size()])
	检(_伤害条数(技能亡女的金库) == 2, "8704 应广播 2 条法术伤害，实际 %d 条"
		% _伤害条数(技能亡女的金库))
	检(_播报次数(技能亡女的金库) == 1, "8704 应播报一次")
	var 支付快照: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Game:
			continue
		for info: Dictionary in (r.get("data", {}) as Dictionary).get("player_infos", []):
			if int(info.get("id", -1)) == 1 \
					and int(info.get("gem", 0)) + int(info.get("crystal", 0)) == 0:
				支付快照 = r.get("data", {})
				break
		if not 支付快照.is_empty():
			break
	检(not 支付快照.is_empty(), "8704 支付 1 能量后应立刻补发对局快照（快照能量应为 0）")

	# ============================================================
	# 8704：选「额外移除」（3 星石含 2 宝石）→ 伤害 2；结算完转移对方 1 点士气
	# ============================================================
	_重置战斗()
	玩家.set_crystal(1)
	引擎.set_team_gem(GConst.BLUE, 2)
	引擎.set_team_crystal(GConst.BLUE, 1)
	引擎.team_morale = [引擎.士气上限() - 2, 引擎.士气上限()]
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _魔法动作(技能亡女的金库, [], [2, 4], [1]))
	引擎.run()
	检(引擎.team_gem[GConst.BLUE] == 0 and 引擎.team_crystal[GConst.BLUE] == 0,
		"8704 额外移除应清空我方战绩区，实际 宝石 %d / 水晶 %d"
		% [引擎.team_gem[GConst.BLUE], 引擎.team_crystal[GConst.BLUE]])
	检(靶.hand_cards.size() == 1 + 1 and 靶2.hand_cards.size() == 1 + 1,
		"3 星石应让 8704 的每次伤害变成 2 点（各摸 2 张），实际 %d / %d 张"
		% [靶.hand_cards.size(), 靶2.hand_cards.size()])
	检(引擎.team_morale[GConst.BLUE] == 引擎.士气上限() - 1
		and 引擎.team_morale[GConst.RED] == 引擎.士气上限() - 1,
		"宝石 ≥2 时应在伤害结算完后转移对方 1 点士气，实际 蓝 %d / 红 %d"
		% [引擎.team_morale[GConst.BLUE], 引擎.team_morale[GConst.RED]])

	# ============================================================
	# 8704：只移除出 1 颗宝石（共 2 星石）→ 伤害 2，但不转移士气
	# ============================================================
	_重置战斗()
	玩家.set_crystal(1)
	引擎.set_team_gem(GConst.BLUE, 1)
	引擎.set_team_crystal(GConst.BLUE, 1)
	引擎.team_morale = [引擎.士气上限() - 2, 引擎.士气上限()]
	引擎.resolve_action(GConst.ActionType.MagicSkill, _魔法动作(技能亡女的金库, [], [2, 4], [1]))
	引擎.run()
	检(靶.hand_cards.size() == 2 and 靶2.hand_cards.size() == 2,
		"2 星石应让每名目标受到 2 点法术伤害（各摸 2 张），实际 %d / %d 张"
		% [靶.hand_cards.size(), 靶2.hand_cards.size()])
	检(引擎.team_morale[GConst.BLUE] == 引擎.士气上限() - 2
		and 引擎.team_morale[GConst.RED] == 引擎.士气上限(),
		"本次只移除出 1 颗宝石，不应转移士气，实际 蓝 %d / 红 %d"
		% [引擎.team_morale[GConst.BLUE], 引擎.team_morale[GConst.RED]])

	# ============================================================
	# 8704：选择「不额外移除」→ 战绩区不动、伤害不成长
	# ============================================================
	_重置战斗()
	玩家.set_crystal(1)
	引擎.set_team_gem(GConst.BLUE, 2)
	引擎.resolve_action(GConst.ActionType.MagicSkill, _魔法动作(技能亡女的金库, [], [2, 4], [0]))
	引擎.run()
	检(引擎.team_gem[GConst.BLUE] == 2, "选择不额外移除时战绩区不应变动")
	检(靶.hand_cards.size() == 1 and 靶2.hand_cards.size() == 1,
		"选择不额外移除时每名目标只受 1 点法术伤害，实际 %d / %d 张"
		% [靶.hand_cards.size(), 靶2.hand_cards.size()])

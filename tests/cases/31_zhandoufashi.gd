extends 自检用例
## R41 战斗法师（41）：4101 符文置换 / 4102 附魔打击 / 4103 熵变 / 4104 魔力熵增。
##
## 任务范围只有 role + test：角色表「脚本」列、技能表「提示」列留给 DATA 任务，
## 所以这里手动把角色挂到玩家 1 身上，提示文案只检查「有下发询问 / 选项 / 固定目标」。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 技能号 / 技能行 / 技能说明 / 脚本文件；
##   - 4101：技能栏（可点牌表只含能凑同系的牌、缺牌与回合限定只置灰）、
##            校验（来源 / 技能号 / 张数 / 同系 / 重复 / 不在手牌）、
##            结算（展示 + 弃牌 + 摸 1 张；含咏类或法术牌 → 额外攻击行动；不含则不给）、回合限定；
##   - 4102：命中 / 未命中（咏类攻击牌）询问；未命中且非咏、非主动攻击、已发动过 → 不询问；
##            取消不生效；完整攻击流水线里命中后进入额外法术行动；
##   - 4103：第 3 次行动结束才问；支付来源选项（宝石 / 队友能量）不可用时置灰；
##            两种支付各完成一次完整结算（2 名对手各 1 点法术伤害）；取消 / 都不可支付时不结算；
##   - 4104：额外行动结束才问；支付 1 水晶（宝石可顶）→ 1 名目标对手 1 点法术伤害；
##            未掉士气 → 我方战绩区 +1 宝石；掉士气 → 不加宝石；无能量 / 非额外行动 → 不询问；
##   - 4103 + 4104 同一次（第 3 次行动就是额外行动）两次询问依次下发、两份伤害都结算；
##   - 回合开始清回合限定标记。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_zhandoufashi.gd")

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 队友: BattlePlayer = null
var 对手甲: BattlePlayer = null
var 对手乙: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 法术甲: GCard = null
var 同系任一张: GCard = null
var 非咏同系甲: GCard = null
var 非咏同系乙: GCard = null
var 咏攻击牌: GCard = null
var 非咏攻击牌: GCard = null
var 圣盾牌: GCard = null


func _init() -> void:
	名称 = "战斗法师"


# ============================================================
# 卡库 / 消息 / 询问工具
# ============================================================
func _取法术() -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic():
			return c
	return null


func _取同系任一张(元素: int, 排除: int) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.id == 排除:
			continue
		if c.element_enum() == 元素:
			return c
	return null


## 两张同系、且都不是咏类命格的攻击牌（4101「不额外给攻击行动」的分支）
func _取非咏同系攻击对() -> Array:
	for a: GCard in Data.card_db:
		if a == null or a.is_virtual or not a.is_attack():
			continue
		if a.fate_pattern_enum() == GConst.FatePattern.Cast:
			continue
		for b: GCard in Data.card_db:
			if b == null or b.is_virtual or not b.is_attack() or b.id == a.id:
				continue
			if b.element_enum() != a.element_enum():
				continue
			if b.fate_pattern_enum() == GConst.FatePattern.Cast:
				continue
			return [a, b]
	return []


func _取攻击牌(需要咏: bool) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		# 暗系攻击自带「无法应战」，完整攻击流水线会跳过应战询问，用例统一避开
		if c.element_enum() == GConst.CardElement.Darkness:
			continue
		if (c.fate_pattern_enum() == GConst.FatePattern.Cast) == 需要咏:
			return c
	return null


func _取卡名(卡名: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.card_name_enum() == 卡名:
			return c
	return null


func _取技能(表: Array, id: int) -> Dictionary:
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


## 当前状态栈顶若是额外行动阶段，返回它的关键字段（不是就返回空字典）
func _取额外阶段() -> Dictionary:
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


## 直接给角色钩子喂一条回复（不经过引擎的 run 循环）
func _应答(args: Array, cards: Array = [], dsts: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": dsts}
	引擎._has_reply = true


## 攻击宣告 / 命中 / 未命中用的上下文（与引擎 harm_ctx 同形）
func _攻击上下文(牌: GCard, src: int, dst: int, 主动: bool) -> Dictionary:
	var harm: Dictionary = {
		"src": src, "dst": dst, "point": BattleEngine.ATTACK_BASE_POINT, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 牌.id, "is_active": 主动,
	}
	return {
		"card_id": 牌.id, "dst": dst, "src": src, "is_active": 主动,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": harm,
	}


## 清空战斗状态：回到「轮到玩家 1、行动阶段、无手牌」的同一起点
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
	引擎.team_gem[0] = 0
	引擎.team_gem[1] = 0
	引擎.team_crystal[0] = 0
	引擎.team_crystal[1] = 0
	引擎.team_grail[0] = 0
	引擎.team_grail[1] = 0
	引擎.team_morale[0] = GConst.MORALE_DEFAULT
	引擎.team_morale[1] = GConst.MORALE_DEFAULT
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.cross_num = 0
		p0.set_crystal(0)
		p0.set_gem(0)
		p0.additional_actions.clear()
		p0.boot_skill_used = false
		p0.hand_cards_max = GConst.HAND_CARDS_MAX
		p0.reset_action_counts()
	角色.p_before_turn_begin({})


func _填手牌(p0: BattlePlayer, 张数: int) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if out.size() >= 张数:
			break
		if c != null and not c.is_virtual and not out.has(c.id):
			out.append(c.id)
	p0.hand_cards = out
	return out


## 调一次魔法行动（圣盾给自己），让本回合行动数 +1：用于把玩家推到「第 3 次行动」
func _打一张圣盾() -> void:
	玩家.hand_cards.append(圣盾牌.id)
	引擎.resolve_action(GConst.ActionType.Magic, {
		"card_ids": [圣盾牌.id], "dst_ids": [1], "args": [],
	})
	引擎.run()


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 ----
	检(str(Data.role_list.get(41, "")) == "战斗法师", "41 号角色名不是「战斗法师」")
	检(Data.role_personal_name(41) == "路尔莉嘉", "41 号角色姓名不是「路尔莉嘉」")
	检(absf(Data.role_star(41) - 3.0) < 0.01, "战斗法师应是 3.0 星，实际 %s" % str(Data.role_star(41)))
	检(Data.role_skills(41) == [4101, 4102, 4103, 4104],
		"战斗法师技能号不对：%s" % str(Data.role_skills(41)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_zhandoufashi.gd"), "战斗法师的角色脚本文件不存在")
	for 技能号: int in [4101, 4102, 4103, 4104]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	var 技能说明: String = Data.role_skill_info(41)
	for 技能名: String in ["符文置换", "附魔打击", "熵变", "魔力熵增"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提 ----
	法术甲 = _取法术()
	非咏同系甲 = null
	非咏同系乙 = null
	var 对: Array = _取非咏同系攻击对()
	if 对.size() == 2:
		非咏同系甲 = 对[0] as GCard
		非咏同系乙 = 对[1] as GCard
	咏攻击牌 = _取攻击牌(true)
	非咏攻击牌 = _取攻击牌(false)
	圣盾牌 = _取卡名(GConst.CardName.Shield)
	检(法术甲 != null, "卡库里找不到法术牌")
	检(非咏同系甲 != null and 非咏同系乙 != null, "卡库里找不到两张同系、非咏类命格的攻击牌")
	检(咏攻击牌 != null, "卡库里找不到咏类命格的攻击牌")
	检(非咏攻击牌 != null, "卡库里找不到非咏类命格的攻击牌")
	检(圣盾牌 != null, "卡库里找不到【圣盾】")
	if 法术甲 == null or 非咏同系甲 == null or 咏攻击牌 == null \
			or 非咏攻击牌 == null or 圣盾牌 == null:
		return
	同系任一张 = _取同系任一张(法术甲.element_enum(), 法术甲.id)
	检(同系任一张 != null, "卡库里找不到与「%s」同系的第二张牌" % 法术甲.card_name)

	# ---- 建引擎：1 / 2 蓝，3 / 4 红；角色表脚本列留给 DATA，用例里手动挂上角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "战斗法师")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({1: 0, 2: 0, 3: 0, 4: 0})
	玩家 = 引擎.p(1)
	队友 = 引擎.p(2)
	对手甲 = 引擎.p(3)
	对手乙 = 引擎.p(4)
	玩家.role_id = 41
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	_重置战斗()

	# ============================================================
	# 4101 符文置换：技能栏
	# ============================================================
	var 栏: Array = 角色.available_skills()
	检(栏.size() == 1, "技能栏应只有【符文置换】一项，实际 %d 项：%s" % [栏.size(), str(栏)])
	var 符文项: Dictionary = _取技能(栏, 4101)
	检(not 符文项.is_empty(), "【符文置换】(4101) 应下发到技能栏")
	检(int(符文项.get("type", 0)) == GConst.ActionType.MagicSkill, "4101 应作为法术技能按钮下发")
	检(int(符文项.get("need_card", 0)) == 2 and int(符文项.get("need_target", 0)) == 0,
		"【符文置换】应要求 2 张手牌、不要目标")
	检(not bool(符文项.get("enabled", true)), "手里没有牌时【符文置换】应置灰")
	玩家.hand_cards.append(法术甲.id)
	检(not bool(_取技能(角色.available_skills(), 4101).get("enabled", true)),
		"只有一张牌、凑不成同系时【符文置换】应置灰")
	玩家.hand_cards.append(同系任一张.id)
	符文项 = _取技能(角色.available_skills(), 4101)
	检(bool(符文项.get("enabled", false)), "有两张同系牌时【符文置换】应可点")
	检((符文项.get("cards", []) as Array).has(法术甲.id)
		and (符文项.get("cards", []) as Array).has(同系任一张.id),
		"可点牌表应包含这两张同系牌：%s" % str(符文项.get("cards", [])))
	# 加一张不同系的牌：它凑不成同系，不该出现在可点牌表里
	var 别系: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.element_enum() != 法术甲.element_enum():
			别系 = c
			break
	检(别系 != null, "卡库里找不到不同系别的牌")
	if 别系 != null:
		玩家.hand_cards.append(别系.id)
		检(not ( _取技能(角色.available_skills(), 4101).get("cards", []) as Array).has(别系.id),
			"凑不成同系的牌不应出现在可点牌表里")

	# ============================================================
	# 4101 符文置换：校验
	# ============================================================
	_重置战斗()
	玩家.hand_cards = [法术甲.id, 同系任一张.id]
	var 合法动作: Dictionary = {"src_id": 1, "action_id": 4101, "card_ids": [法术甲.id, 同系任一张.id]}
	检(角色.v_magic_skill(合法动作) == GConst.GE_SUCCESS, "合法的【符文置换】应通过校验")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 4101, "card_ids": [法术甲.id, 同系任一张.id]})
		!= GConst.GE_SUCCESS, "别人的【符文置换】行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 4102, "card_ids": [法术甲.id, 同系任一张.id]})
		!= GConst.GE_SUCCESS, "不是 4101 的法术技能行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 4101, "card_ids": [法术甲.id]})
		!= GConst.GE_SUCCESS, "只弃 1 张牌不应通过校验")
	var 异系牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.element_enum() != 法术甲.element_enum():
			异系牌 = c
			break
	检(异系牌 != null, "卡库里找不到不同系别的牌")
	if 异系牌 != null:
		玩家.hand_cards.append(异系牌.id)
		检(角色.v_magic_skill({"src_id": 1, "action_id": 4101,
			"card_ids": [法术甲.id, 异系牌.id]}) != GConst.GE_SUCCESS,
			"两张不同系的牌不应通过校验")
		玩家.hand_cards.erase(异系牌.id)
	检(角色.v_magic_skill({"src_id": 1, "action_id": 4101, "card_ids": [法术甲.id, 法术甲.id]})
		!= GConst.GE_SUCCESS, "同一张牌重复提交不应通过校验")
	var 不在手牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and not 玩家.hand_cards.has(c.id):
			不在手牌 = c
			break
	检(不在手牌 != null, "找不到一张不在手里的牌")
	if 不在手牌 != null:
		检(角色.v_magic_skill({"src_id": 1, "action_id": 4101,
			"card_ids": [法术甲.id, 不在手牌.id]}) != GConst.GE_SUCCESS,
			"不在手里的牌不应通过校验")

	# ============================================================
	# 4101 符文置换：结算（含咏 / 法术牌 → 额外攻击行动）
	# ============================================================
	_重置战斗()
	玩家.hand_cards = [法术甲.id, 同系任一张.id]
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 合法动作)
	引擎.run()
	检(not 玩家.hand_cards.has(法术甲.id) and not 玩家.hand_cards.has(同系任一张.id),
		"【符文置换】的两张弃牌应离手")
	检(引擎.deck.discard.has(法术甲.id) and 引擎.deck.discard.has(同系任一张.id),
		"【符文置换】的两张弃牌应进弃牌堆")
	检(玩家.hand_cards.size() == 1, "【符文置换】弃 2 张后应摸 1 张，实际手牌 %d 张" % 玩家.hand_cards.size())
	检(玩家.magic_action_count == 1 and 玩家.action_count() == 1,
		"【符文置换】应记 1 次法术行动：%s" % str(引擎.行动计数(1)))
	检(_播报次数(4101) == 1, "【符文置换】结算应播报 4101")
	var 展示: Dictionary = _找消息(GConst.Msg.Card,
		func(数据: Dictionary) -> bool:
			return int(数据.get("type", 0)) == GConst.CardMsgType.Show \
				and (数据.get("card_ids", []) as Array).has(法术甲.id))
	检(not 展示.is_empty(), "【符文置换】应把弃掉的 2 张牌【展示】出来")
	var 阶段: Dictionary = _取额外阶段()
	检(not 阶段.is_empty(), "【符文置换】含咏类 / 法术牌时应进入额外攻击行动（栈顶：%s）"
		% str(引擎._states[-1] if not 引擎._states.is_empty() else null))
	检(bool(阶段.get("额外", false)) and int(阶段.get("允许", 0)) == GConst.ActionType.Attack,
		"【符文置换】的额外行动应只允许攻击：%s" % str(阶段))
	检(int(阶段.get("来源", 0)) == 4101, "【符文置换】额外行动阶段的来源应为 4101：%s" % str(阶段))
	# 回合限定：本回合再提交应被驳回
	检(角色.v_magic_skill(合法动作) != GConst.GE_SUCCESS, "【符文置换】回合限定用过后不应再通过校验")
	# 手里重新凑出同系两张，置灰只能来自「本回合已发动」
	玩家.hand_cards = [非咏同系甲.id, 非咏同系乙.id]
	检(not bool(_取技能(角色.available_skills(), 4101).get("enabled", true)),
		"【符文置换】用过后技能栏应置灰（与手牌无关）")

	# ============================================================
	# 4101 符文置换：不额外给攻击行动
	# ============================================================
	_重置战斗()
	玩家.hand_cards = [非咏同系甲.id, 非咏同系乙.id]
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 4101, "card_ids": [非咏同系甲.id, 非咏同系乙.id],
	})
	引擎.run()
	检(玩家.hand_cards.size() == 1, "不含咏类 / 法术牌时【符文置换】仍应摸 1 张")
	检(玩家.additional_actions.is_empty(), "不含咏类 / 法术牌时不应给额外攻击行动")
	检(引擎.current_id == 2, "没有额外行动时应正常结束本回合、轮到下家，实际 %d" % 引擎.current_id)

	# ============================================================
	# 4102 附魔打击：直接调用钩子
	# ============================================================
	# 命中：询问并发动 → 额外法术行动
	_重置战斗()
	var 命中上下文: Dictionary = _攻击上下文(非咏攻击牌, 1, 3, true)
	检(角色.p_timeline_1(命中上下文) == BattleRole.SUCCESS, "攻击宣告不应产生副作用")
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.WAIT, "主动攻击命中时应先问是否发动【附魔打击】")
	检(not _取询问(1, 4102).is_empty(), "命中时没有下发【附魔打击】询问")
	_应答([0])
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS, "取消【附魔打击】应正常收尾")
	检(玩家.additional_actions.is_empty(), "取消【附魔打击】不应给额外行动")
	# 再问一次并发动
	角色.p_timeline_1(命中上下文)
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.WAIT, "命中时应再次询问【附魔打击】")
	_应答([1])
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS, "发动【附魔打击】后应正常收尾")
	检(玩家.additional_actions.size() == 1, "发动【附魔打击】应给 1 份额外行动")
	var 额外: Dictionary = 玩家.additional_actions[0] if not 玩家.additional_actions.is_empty() else {}
	检(int(额外.get("allow_action", 0)) == GConst.ActionType.Magic and int(额外.get("cause", 0)) == 4102,
		"【附魔打击】的额外行动应是法术、来源 4102：%s" % str(额外))
	检(_播报次数(4102) == 1, "【附魔打击】发动应播报 4102")
	# 回合限定：同一回合的第二次攻击不再询问
	引擎._最后询问.clear()
	角色.p_timeline_1(命中上下文)
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS, "本回合已发动过【附魔打击】时不应再询问")
	检(_取询问(1, 4102).is_empty(), "本回合已发动过【附魔打击】时不应再次下发询问")

	# 未命中 + 非咏类命格攻击牌：不询问
	_重置战斗()
	var 非咏未命中: Dictionary = _攻击上下文(非咏攻击牌, 1, 3, true)
	角色.p_timeline_1(非咏未命中)
	检(角色.p_timeline_2_miss(非咏未命中) == BattleRole.SUCCESS,
		"未命中且攻击牌不是咏类命格时不应触发【附魔打击】")
	检(_取询问(1, 4102).is_empty(), "未命中且非咏类命格时不应下发【附魔打击】询问")

	# 未命中 + 咏类命格攻击牌：询问并发动
	var 咏未命中: Dictionary = _攻击上下文(咏攻击牌, 1, 3, true)
	角色.p_timeline_1(咏未命中)
	检(角色.p_timeline_2_miss(咏未命中) == BattleRole.WAIT,
		"未命中且攻击牌是咏类命格时应先问是否发动【附魔打击】")
	_应答([1])
	检(角色.p_timeline_2_miss(咏未命中) == BattleRole.SUCCESS, "发动【附魔打击】后应正常收尾")
	检(玩家.additional_actions.size() == 1, "未命中的咏类命格攻击也应给 1 份额外法术行动")

	# 非主动攻击（应战反击）：不询问
	_重置战斗()
	var 应战命中: Dictionary = _攻击上下文(非咏攻击牌, 1, 3, false)
	角色.p_timeline_1(应战命中)
	检(角色.p_timeline_2_hit(应战命中) == BattleRole.SUCCESS, "非主动攻击命中不应触发【附魔打击】")
	检(_取询问(1, 4102).is_empty(), "非主动攻击命中不应下发【附魔打击】询问")
	var 应战未命中: Dictionary = _攻击上下文(咏攻击牌, 1, 3, false)
	检(角色.p_timeline_2_miss(应战未命中) == BattleRole.SUCCESS, "非主动攻击未命中不应触发【附魔打击】")

	# 别人的攻击：不管
	_重置战斗()
	var 别家命中: Dictionary = _攻击上下文(非咏攻击牌, 3, 1, true)
	检(角色.p_timeline_2_hit(别家命中) == BattleRole.SUCCESS, "别人的命中不应触发【附魔打击】")
	检(_取询问(1, 4102).is_empty(), "别人的命中不应由本角色下发询问")

	# ============================================================
	# 4102 附魔打击：完整攻击流水线（命中 → 询问 → 额外法术行动阶段）
	# ============================================================
	_重置战斗()
	玩家.hand_cards.append(咏攻击牌.id)
	对手甲.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.Attack, {
		"card_ids": [咏攻击牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 3, "攻击宣告后应等对手应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == 1, "主动攻击命中后应问攻击者是否发动【附魔打击】（等待 %s）" % str(引擎._await_id))
	检(not _取询问(1, 4102).is_empty(), "完整流水线里没有下发【附魔打击】询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4102, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(玩家.attack_action_count == 1, "本次攻击应记 1 次攻击行动：%s" % str(引擎.行动计数(1)))
	var 流水线阶段: Dictionary = _取额外阶段()
	检(not 流水线阶段.is_empty(), "【附魔打击】结算完应直接进入额外法术行动阶段")
	检(int(流水线阶段.get("允许", 0)) == GConst.ActionType.Magic,
		"【附魔打击】的额外行动应只允许法术：%s" % str(流水线阶段))
	检(int(流水线阶段.get("来源", 0)) == 4102, "【附魔打击】额外行动阶段的来源应为 4102")
	检(对手甲.hand_cards.size() == BattleEngine.ATTACK_BASE_POINT,
		"攻击命中应让目标摸 %d 张，实际 %d 张"
		% [BattleEngine.ATTACK_BASE_POINT, 对手甲.hand_cards.size()])

	# ============================================================
	# 4103 熵变：第 3 次行动结束 → 支付 + 2 名目标对手各 1 点法术伤害
	# ============================================================
	# 第 2 次行动结束：不询问
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.attack_action_count = 1
	发送记录.clear()
	_打一张圣盾()
	检(玩家.action_count() == 2, "第 2 次行动后计数应为 2，实际 %d" % 玩家.action_count())
	检(_取询问(1, 4103).is_empty(), "第 2 次行动结束不应询问【熵变】")
	检(_伤害条数(4103) == 0, "第 2 次行动结束不应造成【熵变】伤害")

	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.attack_action_count = 1
	玩家.magic_action_count = 1
	发送记录.clear()
	_打一张圣盾()
	检(玩家.action_count() == 3, "第 3 次行动后计数应为 3，实际 %d" % 玩家.action_count())
	检(引擎._await_id == 1, "第 3 次行动结束应问是否发动【熵变】（等待 %s）" % str(引擎._await_id))
	var 熵变支付问: Dictionary = _取询问(1, 4103)
	检(not 熵变支付问.is_empty(), "第 3 次行动结束没有下发【熵变】支付询问")
	检(int((熵变支付问.get("args", []) as Array)[1]) == 0, "【熵变】第一步不应要求目标")
	检(int(熵变支付问.get("args", [])[3] if (熵变支付问.get("args", []) as Array).size() > 3 else 0) == 2,
		"【熵变】支付应有 2 个固定选项：%s" % str(熵变支付问.get("args", [])))
	检((熵变支付问.get("option_enabled", []) as Array) == [true, false],
		"只有我方战绩区有宝石时，队友能量项应置灰：%s" % str(熵变支付问.get("option_enabled", [])))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == 1, "选完支付方式后应继续问【熵变】的目标（等待 %s）" % str(引擎._await_id))
	var 熵变目标问: Dictionary = _取询问(1, 4103)
	检(int((熵变目标问.get("args", []) as Array)[1]) == 2, "【熵变】第二步应要求 2 名目标对手")
	检((熵变目标问.get("dst_ids", []) as Array) == [3, 4],
		"【熵变】的目标白名单应是两名对手：%s" % str(熵变目标问.get("dst_ids", [])))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3, 4],
	})
	检(int(引擎.team_gem[GConst.BLUE]) == 0, "【熵变】应消耗我方战绩区 1 宝石")
	检(对手甲.hand_cards.size() == 1 and 对手乙.hand_cards.size() == 1,
		"【熵变】应对两名对手各造成 1 点法术伤害（各摸 1 张），实际 %d / %d 张"
		% [对手甲.hand_cards.size(), 对手乙.hand_cards.size()])
	检(_伤害条数(4103) == 2, "【熵变】应广播 2 条法术伤害，实际 %d 条" % _伤害条数(4103))
	检(_播报次数(4103) == 1, "【熵变】应播报 4103")

	# ---- 4103：队友能量支付 ----
	_重置战斗()
	队友.set_crystal(1)
	玩家.attack_action_count = 1
	玩家.magic_action_count = 1
	发送记录.clear()
	_打一张圣盾()
	检(引擎._await_id == 1, "第 3 次行动结束应问【熵变】（等待 %s）" % str(引擎._await_id))
	检((_取询问(1, 4103).get("option_enabled", []) as Array) == [false, true],
		"只有队友有能量时，我方宝石项应置灰")
	var 支付问: Dictionary = _取询问(1, 4103)
	检((支付问.get("dst_ids", []) as Array) == [队友.id],
		"支付询问应把有能量的队友列入可点头像：%s" % str(支付问.get("dst_ids", [])))
	检((支付问.get("option_need_targets", []) as Array) == [0, 1],
		"「队友能量」选项应自带需目标 1：%s" % str(支付问.get("option_need_targets", [])))
	var 队友手牌前: int = 队友.hand_cards.size()
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [2], "card_ids": [], "dst_ids": [队友.id],
	})
	检(引擎._await_id == 1, "选完支付来源与队友后应继续问【熵变】的 2 名目标对手")
	var 目标问: Dictionary = _取询问(1, 4103)
	检(int((目标问.get("args", []) as Array)[1]) == 2
		and (目标问.get("dst_ids", []) as Array) == [3, 4],
		"【熵变】第二步应只亮两名对手：%s" % str(目标问))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3, 4],
	})
	检(队友.hand_cards.size() == 队友手牌前, "被消耗能量的队友不应受到【熵变】伤害（不应摸牌）")
	检(队友.get_energy() == 0, "选队友支付时【熵变】应消耗队友 1 点能量")
	检(int(引擎.team_gem[GConst.BLUE]) == 0, "选队友支付时不应扣我方宝石")
	检(对手甲.hand_cards.size() == 1 and 对手乙.hand_cards.size() == 1,
		"队友支付时【熵变】仍应对两名对手各造成 1 点法术伤害")

	# ---- 4103：两种支付都不可行时不询问 ----
	_重置战斗()
	玩家.attack_action_count = 1
	玩家.magic_action_count = 1
	发送记录.clear()
	_打一张圣盾()
	检(_取询问(1, 4103).is_empty(), "没有宝石、队友也没有能量时不应询问【熵变】")
	检(_伤害条数(4103) == 0, "不能支付时【熵变】不应造成伤害")
	检(_播报次数(4103) == 0, "不能支付时【熵变】不应播报")

	# ---- 客户端：熵变支付「先弹选项」——选「队友能量」后点队友头像，按确定一次性提交 ----
	_重置战斗()
	队友.set_crystal(1)
	玩家.attack_action_count = 1
	玩家.magic_action_count = 1
	发送记录.clear()
	_打一张圣盾()
	var 客户端支付问: Dictionary = _取询问(1, 4103)
	检(not 客户端支付问.is_empty(), "客户端用例：应先下发【熵变】支付询问")
	引擎._清空等待()
	Logic.my_player_id = 1
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(1)
	窗.call("_on_command", {"cmd_type": GConst.CmdType.Respond, "commands": [客户端支付问]})
	await 等帧(1)
	检(bool(窗.call("_确定不可用")), "熵变支付未选来源时不能确定")
	窗.call("_选中二级选项", GConst.技能_熵变, 1)
	await 等帧(1)
	检(bool(窗.call("_确定不可用")), "选了队友能量但没点队友时不能确定")
	窗.call("_on_player_clicked", 队友.id)
	await 等帧(1)
	检(not bool(窗.call("_确定不可用")), "点了队友后应可确定")
	检((窗.get("_sel_players") as Array) == [队友.id], "应只选中被点的那名队友")
	窗.queue_free()
	await 等帧(1)

	# ---- 4103：取消支付 → 不结算 ----
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.attack_action_count = 1
	玩家.magic_action_count = 1
	发送记录.clear()
	_打一张圣盾()
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(int(引擎.team_gem[GConst.BLUE]) == 1, "取消【熵变】不应扣我方宝石")
	检(对手甲.hand_cards.is_empty() and 对手乙.hand_cards.is_empty(), "取消【熵变】不应造成伤害")
	检(_伤害条数(4103) == 0, "取消【熵变】不应广播伤害")

	# ============================================================
	# 4104 魔力熵增：额外行动结束 → 支付 1 水晶 → 1 名目标对手 1 点法术伤害
	# ============================================================
	_重置战斗()
	玩家.set_crystal(1)
	引擎.行动额外 = true
	引擎.行动额外来源 = 9001
	发送记录.clear()
	_打一张圣盾()
	检(引擎._await_id == 1, "额外行动结束应问是否发动【魔力熵增】（等待 %s）" % str(引擎._await_id))
	var 魔力问: Dictionary = _取询问(1, 4104)
	检(not 魔力问.is_empty(), "额外行动结束没有下发【魔力熵增】询问")
	检(int((魔力问.get("args", []) as Array)[1]) == 1, "【魔力熵增】应要求 1 名目标对手")
	检((魔力问.get("dst_ids", []) as Array) == [3, 4],
		"【魔力熵增】的目标白名单应是两名对手：%s" % str(魔力问.get("dst_ids", [])))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4104, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3],
	})
	检(玩家.get_energy() == 0, "【魔力熵增】应支付 1 点水晶")
	检(对手甲.hand_cards.size() == 1, "【魔力熵增】应对目标对手造成 1 点法术伤害")
	检(_伤害条数(4104) == 1, "【魔力熵增】应广播 1 条法术伤害")
	检(_播报次数(4104) == 1, "【魔力熵增】应播报 4104")
	检(int(引擎.team_gem[GConst.BLUE]) == 1,
		"本次伤害没有造成士气下降，我方战绩区应 +1 宝石，实际 %d" % int(引擎.team_gem[GConst.BLUE]))

	# ---- 4104：同回合第二次额外行动结束应再次询问 ----
	_重置战斗()
	玩家.set_crystal(2)
	引擎.行动额外 = true
	引擎.行动额外来源 = 9001
	_打一张圣盾()
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4104, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3],
	})
	检(int(引擎.team_gem[GConst.BLUE]) == 1, "第一次【魔力熵增】应 +1 宝石")
	# 第二次额外行动结束：引擎此时已把回合交给下家，这里直接喂同一份行动结束上下文验证钩子按次数重新触发
	引擎._states.clear()
	引擎._清空等待()
	引擎.current_id = 1
	引擎.行动额外 = true
	var 二次上下文: Dictionary = {
		"player": 1, "kind": "magic", "is_extra": true,
		"extra_cause": 9001, "action_count": 2,
	}
	检(角色.p_action_end(二次上下文) == BattleRole.WAIT, "第二次额外行动结束应再次询问【魔力熵增】")
	_应答([], [], [3])
	检(角色.p_action_end(二次上下文) == BattleRole.SUCCESS, "第二次【魔力熵增】应正常收尾")
	引擎.run()
	检(玩家.get_energy() == 0, "第二次【魔力熵增】也应支付 1 点水晶")
	检(int(引擎.team_gem[GConst.BLUE]) == 2, "第二次没掉士气也应 +1 宝石，实际 %d"
		% int(引擎.team_gem[GConst.BLUE]))
	检(对手甲.hand_cards.size() == 2, "两次【魔力熵增】应对目标造成 2 点法术伤害，实际手牌 %d 张"
		% 对手甲.hand_cards.size())

	# ---- 4104：宝石可顶水晶 ----
	_重置战斗()
	玩家.set_gem(1)
	引擎.行动额外 = true
	引擎.行动额外来源 = 9001
	_打一张圣盾()
	检(not _取询问(1, 4104).is_empty(), "用宝石顶水晶时也应询问【魔力熵增】")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4104, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3],
	})
	检(玩家.get_energy() == 0 and 玩家.gem == 0, "【水晶】费用应允许用宝石支付")

	# ---- 4104：没有能量时不询问 ----
	_重置战斗()
	引擎.行动额外 = true
	引擎.行动额外来源 = 9001
	发送记录.clear()
	_打一张圣盾()
	检(_取询问(1, 4104).is_empty(), "没有能量时不应询问【魔力熵增】")
	检(_播报次数(4104) == 0, "没有能量时不应播报【魔力熵增】")

	# ---- 4104：普通行动结束不询问 ----
	_重置战斗()
	玩家.set_crystal(1)
	发送记录.clear()
	_打一张圣盾()
	检(_取询问(1, 4104).is_empty(), "普通行动结束不应触发【魔力熵增】")
	检(_播报次数(4104) == 0, "普通行动结束不应播报【魔力熵增】")

	# ---- 4104：这次伤害造成士气下降时，不加宝石 ----
	_重置战斗()
	玩家.set_crystal(1)
	引擎.行动额外 = true
	引擎.行动额外来源 = 9001
	var 满手牌: Array[int] = _填手牌(对手甲, GConst.HAND_CARDS_MAX)
	发送记录.clear()
	_打一张圣盾()
	检(not _取询问(1, 4104).is_empty(), "额外行动结束应问【魔力熵增】")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4104, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3],
	})
	检(引擎._await_id == 3, "【魔力熵增】让目标超限时应让目标选择弃牌（等待 %s）" % str(引擎._await_id))
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Discard, "src_id": 3,
		"args": [3, GConst.CAUSE_OVERLOAD, 1],
		"card_ids": [满手牌[0]], "dst_ids": [3],
	})
	检(int(引擎.team_morale[GConst.RED]) == GConst.MORALE_DEFAULT - 1,
		"超限掉士气后红队士气应为 %d，实际 %d"
		% [GConst.MORALE_DEFAULT - 1, int(引擎.team_morale[GConst.RED])])
	检(int(引擎.team_gem[GConst.BLUE]) == 0,
		"这次伤害造成了士气下降，我方战绩区不应 +1 宝石，实际 %d" % int(引擎.team_gem[GConst.BLUE]))

	# ============================================================
	# 4103 + 4104 同一次行动结束（第 3 次行动就是额外行动）
	# ============================================================
	_重置战斗()
	玩家.set_crystal(1)
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.attack_action_count = 1
	玩家.magic_action_count = 1
	引擎.行动额外 = true
	引擎.行动额外来源 = 9001
	发送记录.clear()
	_打一张圣盾()
	检(not _取询问(1, 4103).is_empty(), "第 3 次（额外）行动结束应先问【熵变】")
	检(_取询问(1, 4104).is_empty(), "【熵变】的选择还没完成时不应先问【魔力熵增】")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3, 4],
	})
	检(not _取询问(1, 4104).is_empty(), "【熵变】选完后应继续问【魔力熵增】")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4104, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3],
	})
	检(int(引擎.team_gem[GConst.BLUE]) == 1,
		"熵变支付 1 宝石、魔力熵增没掉士气 +1 宝石，我方战绩区应为 1，实际 %d"
		% int(引擎.team_gem[GConst.BLUE]))
	检(对手甲.hand_cards.size() == 2, "对手甲应受【魔力熵增】1 点 +【熵变】1 点，实际手牌 %d 张"
		% 对手甲.hand_cards.size())
	检(对手乙.hand_cards.size() == 1, "对手乙应只受【熵变】1 点，实际手牌 %d 张"
		% 对手乙.hand_cards.size())
	检(_伤害条数(4103) == 2 and _伤害条数(4104) == 1,
		"同一次行动结束应结算 2 条【熵变】伤害 + 1 条【魔力熵增】伤害")

	# ============================================================
	# 回合开始清回合限定标记
	# ============================================================
	_重置战斗()
	玩家.hand_cards = [法术甲.id, 同系任一张.id]
	引擎.resolve_action(GConst.ActionType.MagicSkill, 合法动作)
	引擎.run()
	检(not bool(_取技能(角色.available_skills(), 4101).get("enabled", true)),
		"【符文置换】用过后应置灰")
	# 重置时手里仍有同系两张，置灰只可能来自「回合限定」标记
	玩家.hand_cards = [法术甲.id, 同系任一张.id]
	角色.p_before_turn_begin({})
	检(bool(_取技能(角色.available_skills(), 4101).get("enabled", false)),
		"新回合开始时【符文置换】的回合限定应重置")

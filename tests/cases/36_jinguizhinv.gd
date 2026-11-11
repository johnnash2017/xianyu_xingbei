extends 自检用例
## R78 矜贵之女（78）：7801 高岭之花 / 7802 魔法入门 / 7803 Magic! /
## 7804 强予愿行 / 7805 友情羁绊。
##
## 口径（data-audit A27~A30）：
##   - 7802 摸 1 张【强制】【展示】，按展示集合依序触发「法术牌 → 咏类命格 → 水系牌」三组效果，
##     X＝展示集合里满足条件的张数；7805 改写后展示集合是 2 张弃牌；
##   - 7803 三个触发独立、各自可选；第 3 次每回合只问一次；弃 2 张是可选代价；
##   - 7804 是「启动」技能，水晶费用可用宝石顶；可选额外移除 1 星石，再由牌主自己选手牌调整到 4；
##   - 7805 每回合一次、必须真宝石、我方 2 名角色各弃 1 张【展示】，技能结束前各摸 1 张【强制】。
##
## 覆盖：数据 / 7801 提炼（直接钩子 + 引擎真实提炼）/ 7802 三组效果 / 7803 三分支（含第 3 次只一次）/
## 7804 主路径 + 无星石 + 放弃额外移除 + 子询问取消 / 超时 + 能量不足 /
## 7805 改写 + 不满足条件时不询问 + 7805↔7803 牌数守恒 + 7803 只弃还留手里的牌 / 回合重置。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_jinguizhinv.gd")

const 高岭之花: int = 7801
const 魔法入门: int = 7802
const MAGIC_BANG: int = 7803
const 强予愿行: int = 7804
const 友情羁绊: int = 7805

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 敌甲: BattlePlayer = null
var 敌乙: BattlePlayer = null
var 队友: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 法术牌: GCard = null
var 咏牌: GCard = null
var 水系牌: GCard = null
var 水系牌乙: GCard = null
var 无效果牌: GCard = null
var 全能牌: GCard = null


func _init() -> void:
	名称 = "矜贵之女"


# ============================================================
# 取样 / 断言工具
# ============================================================
func _取卡(条件: Callable, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		if bool(条件.call(c)):
			return c
	return null


func _是法术牌(c: GCard) -> bool:
	return c.is_magic() and c.fate_pattern_enum() != GConst.FatePattern.Cast \
		and c.element_enum() != GConst.CardElement.Water


func _是咏牌(c: GCard) -> bool:
	return not c.is_magic() and c.fate_pattern_enum() == GConst.FatePattern.Cast \
		and c.element_enum() != GConst.CardElement.Water


func _是水系牌(c: GCard) -> bool:
	return not c.is_magic() and c.fate_pattern_enum() != GConst.FatePattern.Cast \
		and c.element_enum() == GConst.CardElement.Water


func _是三组都不触发(c: GCard) -> bool:
	return not c.is_magic() and c.fate_pattern_enum() != GConst.FatePattern.Cast \
		and c.element_enum() != GConst.CardElement.Water


func _是全能牌(c: GCard) -> bool:
	return c.is_magic() and c.fate_pattern_enum() == GConst.FatePattern.Cast \
		and c.element_enum() == GConst.CardElement.Water


func _找技能(表: Array, 技能号: int) -> Dictionary:
	for sk: Dictionary in 表:
		if int(sk.get("id", 0)) == 技能号:
			return sk
	return {}


## 最近一次下发给某玩家的询问里，是否有指定 respond_id 的那条
func _取询问(pid: int, respond_id: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == respond_id:
			return r
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


func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("pid", 0)) == pid and int(r.get("msg", 0)) == GConst.Msg.ErrorInput:
			return true
	return false


## 某目标的伤害记录（Hurt 广播）
func _伤害记录(dst: int, cause: int) -> Array:
	var out: Array = []
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Hurt:
			continue
		var data: Dictionary = r.get("data", {})
		if int(data.get("dst_id", -1)) == dst and int(data.get("cause", 0)) == cause:
			out.append(data)
	return out


func _填手牌(p0: BattlePlayer, ids: Array) -> void:
	p0.hand_cards.clear()
	for cid: Variant in ids:
		p0.hand_cards.append(int(cid))


## 把牌库顶换成 顶牌（下面垫 40 张别的牌，避免伤害摸牌 / 强制摸牌时把弃牌堆洗回来影响断言）。
## 场上手牌里的牌号一律排掉：同一牌号同时出现在牌库与手牌会让弃牌 / 摸牌断言失真。
func _置牌库顶(顶牌: GCard) -> void:
	var 排除: Array = [顶牌.id]
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		if p0 == null:
			continue
		for cid: int in p0.hand_cards:
			排除.append(cid)
	引擎.deck.pile.clear()
	引擎.deck.discard.clear()
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		引擎.deck.pile.append(c.id)
		if 引擎.deck.pile.size() >= 40:
			break
	引擎.deck.pile.append(顶牌.id)


## 回复一次技能询问（on_message 只认 pid + kind）
func _回复(pid: int, respond_id: int, args: Array = [], cards: Array = [], dsts: Array = []) -> void:
	引擎.on_message(pid, GConst.Msg.Respond, {
		"respond_id": respond_id, "src_id": pid,
		"args": args, "card_ids": cards, "dst_ids": dsts,
	})


## 清空战斗状态：四个座位固定（1 / 3 蓝，2 / 4 红），78 重新挂一份角色脚本；
## 手牌 / 基础效果 / 额外行动 / 能量 / 士气 / 弃牌堆 / 牌库都回到同一起点。
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	引擎._hand_counts.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.跳过行动阶段来源 = 0
	引擎.本回合跳过行动阶段 = false
	引擎.本回合跳过行动阶段来源 = 0
	引擎.测试跳过回合 = -1
	引擎.set_morale(GConst.BLUE, GConst.MORALE_DEFAULT)
	引擎.set_morale(GConst.RED, GConst.MORALE_DEFAULT)
	引擎.set_team_gem(GConst.BLUE, 0)
	引擎.set_team_gem(GConst.RED, 0)
	引擎.set_team_crystal(GConst.BLUE, 0)
	引擎.set_team_crystal(GConst.RED, 0)
	引擎.deck.pile.clear()
	引擎.deck.discard.clear()
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.additional_actions.clear()
		p0.hand_cards_max = GConst.HAND_CARDS_MAX
		p0.cross_num = 0
		p0.set_crystal(0)
		p0.set_gem(0)
		p0.reset_action_counts()
		p0.boot_skill_used = false
		p0.role = null
	玩家.role_id = 78
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色


## 发起一次 7802 技能行动并推进到下一次等待
## 发起一次 7802 技能行动（选项 1 普通 / 2 响应友情羁绊，2 名角色随行动一起提交）
func _开魔法入门(选择: int = 1, dsts: Array = []) -> void:
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 魔法入门, "args": [选择], "card_ids": [], "dst_ids": dsts,
	})
	引擎.run()


## 发起一次 7804 技能行动（选项 / 弃牌 / 目标随行动一起提交）并推进到下一次等待
func _开强予愿行(选择: int = 1, cards: Array = [], dsts: Array = []) -> void:
	引擎.resolve_action(GConst.ActionType.ActivateSkill, {
		"src_id": 1, "action_id": 强予愿行, "args": [选择], "card_ids": cards, "dst_ids": dsts,
	})
	引擎.run()


## 从当前行动命令里取某个技能的命令（技能栏按钮数据，含 arg_choices）
func _技能命令(技能号: int) -> Dictionary:
	for 命令: Dictionary in 引擎.action_commands(1, GConst.ActionType.Any, false, false, false, 0):
		var 参数: Array = 命令.get("args", [])
		if not 参数.is_empty() and int(参数[0]) == 技能号:
			return 命令
	return {}


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 五颗技能行 / 脚本存在 ----
	检(str(Data.role_list.get(78, "")) == "矜贵之女", "78 号角色名不是「矜贵之女」")
	检(Data.role_personal_name(78) == "艾丽卡", "78 号角色姓名不是「艾丽卡」")
	检(absf(Data.role_star(78) - 3.0) < 0.01, "矜贵之女应是 3.0 星，实际 %s" % str(Data.role_star(78)))
	检(Data.role_skills(78) == [7801, 7802, 7803, 7804, 7805],
		"矜贵之女技能号不对：%s" % str(Data.role_skills(78)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_jinguizhinv.gd"),
		"矜贵之女的角色脚本文件不存在")
	for 技能号: int in [7801, 7802, 7803, 7804, 7805]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	检(GConst.技能号("技能#矜贵之女#魔法入门") == 7802, "魔法入门的技能号不是 7802")
	检(GConst.技能号("技能#矜贵之女#强予愿行") == 7804, "强予愿行的技能号不是 7804")
	var 技能说明: String = Data.role_skill_info(78)
	for 技能名: String in ["高岭之花", "魔法入门", "Magic!", "强予愿行", "友情羁绊"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提：四类展示牌 ----
	法术牌 = _取卡(_是法术牌)
	咏牌 = _取卡(_是咏牌)
	水系牌 = _取卡(_是水系牌)
	水系牌乙 = _取卡(_是水系牌, [水系牌.id] if 水系牌 != null else [])
	无效果牌 = _取卡(_是三组都不触发)
	全能牌 = _取卡(_是全能牌)
	检(法术牌 != null, "卡库找不到「法术牌」样本（魔法 + 非咏 + 非水）")
	检(咏牌 != null, "卡库找不到「咏类非魔法牌」样本")
	检(水系牌 != null and 水系牌乙 != null, "卡库找不到两张「水系非魔法非咏牌」样本")
	检(无效果牌 != null, "卡库找不到「三组效果都不触发」的牌样本")
	检(全能牌 != null, "卡库找不到「法术 + 咏 + 水」三效果样本")
	if 法术牌 == null or 咏牌 == null or 水系牌 == null or 水系牌乙 == null \
			or 无效果牌 == null or 全能牌 == null:
		return

	# ---- 建引擎：1 / 3 蓝，2 / 4 红；角色表脚本列留给 DATA，用例里手动挂 78 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "矜贵")
	引擎.add_player(2, GConst.RED, "敌甲")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "敌乙")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	敌甲 = 引擎.p(2)
	队友 = 引擎.p(3)
	敌乙 = 引擎.p(4)
	_重置战斗()

	# ============================================================
	# 技能栏 / 校验 / 启动认定
	# ============================================================
	var 列表: Array = 角色.available_skills()
	var 技能7802: Dictionary = _找技能(列表, 魔法入门)
	var 技能7804: Dictionary = _找技能(列表, 强予愿行)
	检(not 技能7802.is_empty(), "技能栏应下发 7802【魔法入门】")
	检(int(技能7802.get("type", 0)) == GConst.ActionType.MagicSkill, "7802 应是法术技能")
	检(bool(技能7802.get("enabled", true)), "7802 应默认可发动")
	检(not 技能7804.is_empty(), "技能栏应下发 7804【强予愿行】")
	检(int(技能7804.get("type", 0)) == GConst.ActionType.ActivateSkill, "7804 应是特殊技能（启动）")
	检(not bool(技能7804.get("enabled", true)), "能量 0 时 7804 应置灰")
	玩家.set_crystal(1)
	检(bool(_找技能(角色.available_skills(), 强予愿行).get("enabled", false)),
		"有 1 点能量时 7804 应可发动")
	玩家.set_crystal(0)
	检(角色.is_free_skill(强予愿行), "7804 应被认定为「启动」技能")
	检(not 角色.is_free_skill(魔法入门), "7802 不是启动技能")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 魔法入门}) == GConst.GE_SUCCESS,
		"7802 校验：正常参数应通过")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 魔法入门}) == GConst.GE_INVALID_PLAYERID,
		"7802 校验：不是自己的行动应拒绝")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 9999}) == GConst.GE_INVALID_ACTION,
		"7802 校验：技能号不对应拒绝")
	检(角色.v_special_skill({"src_id": 1, "action_id": 强予愿行, "args": [1]}) == GConst.GE_INVALID_ACTION,
		"7804 校验：能量 0 时应收敛为无效")
	玩家.set_crystal(1)
	检(角色.v_special_skill({"src_id": 1, "action_id": 强予愿行, "args": [1]}) == GConst.GE_SUCCESS,
		"7804 校验：1 点能量应通过（宝石可顶水晶）")
	检(角色.v_special_skill({"src_id": 1, "action_id": 强予愿行, "args": [2], "dst_ids": [3]})
		== GConst.GE_INVALID_ARGUMENT,
		"7804 校验：战绩区没有水晶时选「-1 水晶」档应拒绝")
	玩家.set_crystal(0)

	# ============================================================
	# 7801 高岭之花：提炼含宝石 → +1 水晶
	# ============================================================
	_重置战斗()
	角色.p_after_extract({"player": 1, "gem": 1, "crystal": 0, "args": [1, 0], "dst_ids": [], "is_heaven": false})
	检(玩家.crystal == 1 and 玩家.gem == 0, "7801：提炼含 1 宝石后应 +1 水晶")
	检(_播报次数(高岭之花) == 1, "7801：触发后应播报一次")
	角色.p_after_extract({"player": 1, "gem": 0, "crystal": 1, "args": [0, 1], "dst_ids": [], "is_heaven": false})
	检(玩家.crystal == 1, "7801：本次提炼不含宝石不应再 +1 水晶")
	角色.p_after_extract({"player": 2, "gem": 1, "crystal": 0, "args": [1, 0], "dst_ids": [], "is_heaven": false})
	检(玩家.crystal == 1, "7801：别人提炼不应给自己 +1 水晶")
	玩家.set_gem(2)
	检(玩家.get_energy() == 3, "7801：前置能量应已满")
	角色.p_after_extract({"player": 1, "gem": 1, "crystal": 0, "args": [1, 0], "dst_ids": [], "is_heaven": false})
	检(玩家.crystal == 1 and 玩家.get_energy() == 3, "7801：能量已满时不应突破能量上限")

	# 真实提炼入口：引擎 _do_special 的 p_after_extract 也要生效
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 2)
	引擎.resolve_action(GConst.ActionType.Special, {
		"src_id": 1, "action_id": GConst.SpecialAction.Extract,
		"args": [1, 0], "dst_ids": [], "card_ids": [],
	})
	引擎.run()
	检(玩家.gem == 1 and 玩家.crystal == 1,
		"7801：真实提炼 1 宝石后应 +1 水晶，实际 宝石 %d / 水晶 %d" % [玩家.gem, 玩家.crystal])
	检(_播报次数(高岭之花) == 1, "7801：真实提炼后应播报一次")

	# ============================================================
	# 7802 + 7803 分支 1：展示法术牌 → 2 名对手各 1 法术伤害；可弃 2 张牌
	# ============================================================
	_重置战斗()
	玩家.set_gem(0)   # 没有宝石 → 不询问 7805
	_填手牌(玩家, [无效果牌.id, 咏牌.id])
	_置牌库顶(法术牌)
	_开魔法入门()
	var 问法术: Dictionary = _取询问(1, 魔法入门)
	检(not 问法术.is_empty(), "7802：展示法术牌后应先询问 2 名目标对手")
	检(int((问法术.get("args", []) as Array)[1]) == 2, "7802：法术效果应要求 2 名目标")
	检((问法术.get("dst_ids", []) as Array).has(2) and (问法术.get("dst_ids", []) as Array).has(4),
		"7802：法术效果目标应是对手 2 / 4")
	检(玩家.hand_cards.has(法术牌.id), "7802：摸到的展示牌应进入自己手牌")
	_回复(1, 魔法入门, [], [], [2, 4])
	var 问7803: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问7803.is_empty(), "7803：展示牌触发效果后应询问 Magic! 选项")
	# 三项固定下发：触发效果时只有「弃 2 张牌」可点，另外两项置灰
	检((问7803.get("notes", []) as Array) == ["弃 2 张牌", "额外+1【法术行动】", "我方【战绩区】+2【宝石】"],
		"7803：三项选项文案不对：%s" % str(问7803.get("notes", [])))
	检((问7803.get("option_enabled", []) as Array) == [true, false, false],
		"7803：触发效果时应只允许「弃 2 张牌」：%s" % str(问7803.get("option_enabled", [])))
	# 「弃 2 张牌」的需牌挂在选项上（同一问里选牌，不再另发一条选牌询问）
	检((问7803.get("option_need_cards", []) as Array) == [2, 0, 0],
		"7803：「弃 2 张牌」应自带 need_card=2：%s" % str(问7803.get("option_need_cards", [])))
	_回复(1, MAGIC_BANG, [1], [无效果牌.id, 咏牌.id])
	检(玩家.hand_cards.size() == 1 and 玩家.hand_cards.has(法术牌.id),
		"7803：弃 2 张后应只剩摸到的展示牌，实际 %s" % str(玩家.hand_cards))
	检(引擎.deck.discard.has(无效果牌.id) and 引擎.deck.discard.has(咏牌.id),
		"7803：弃掉的 2 张牌应进弃牌堆")
	var 伤害2: Array = _伤害记录(2, 魔法入门)
	var 伤害4: Array = _伤害记录(4, 魔法入门)
	检(伤害2.size() == 1 and 伤害4.size() == 1,
		"7802：法术效果应对 2 名对手各造成 1 点伤害")
	if 伤害2.size() == 1:
		检(int(伤害2[0].get("hurt", 0)) == 1
			and int(伤害2[0].get("type", 0)) == GConst.HarmType.Magic,
			"7802：法术伤害应为 1 点法术伤害")
	检(_播报次数(魔法入门) == 1, "7802：应播报一次")
	检(_播报次数(MAGIC_BANG) == 1, "7803：分支 1 应播报一次")
	检(玩家.additional_actions.is_empty(), "7803：触发效果的分支不应额外授予法术行动")
	检(引擎.team_gem[GConst.BLUE] == 0, "7803：分支 1 不应给战绩区宝石")

	# ============================================================
	# 7802：摸到的展示牌把手牌摸超上限 → 先超限弃牌 + 掉士气，再接着问法术目标
	# ============================================================
	_重置战斗()
	玩家.set_gem(0)   # 没有宝石 → 不询问 7805
	var 满手六张: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 满手六张.has(c.id) or c.id == 法术牌.id:
			continue
		满手六张.append(c.id)
		if 满手六张.size() >= GConst.HAND_CARDS_MAX:
			break
	检(满手六张.size() == GConst.HAND_CARDS_MAX, "卡库找不到 6 张实体牌")
	if 满手六张.size() == GConst.HAND_CARDS_MAX:
		_填手牌(玩家, 满手六张)
		_置牌库顶(法术牌)
		引擎.team_morale[GConst.BLUE] = 15
		_开魔法入门()
		检(引擎._await_id == 1 and int(引擎._pending_respond_id) == GConst.RespondType.Discard,
			"7802：摸到 7 张时应先走超限弃牌，实际等待 %s / 询问号 %s"
			% [str(引擎._await_id), str(引擎._pending_respond_id)])
		检(玩家.hand_cards.size() == GConst.HAND_CARDS_MAX + 1,
			"7802：摸牌后手牌应为 7 张，实际 %d" % 玩家.hand_cards.size())
		_回复(1, GConst.RespondType.Discard, [1, GConst.CAUSE_OVERLOAD, 1], [满手六张[0]], [1])
		检(int(引擎.team_morale[GConst.BLUE]) == 14,
			"7802：超限 1 张应掉 1 点士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))
		检(玩家.hand_cards.size() == GConst.HAND_CARDS_MAX,
			"7802：超限弃牌后应回到上限 6，实际 %d" % 玩家.hand_cards.size())
		var 问法术2: Dictionary = _取询问(1, 魔法入门)
		检(not 问法术2.is_empty(), "7802：超限结算完应继续问法术目标")
		检(玩家.hand_cards.has(法术牌.id), "7802：展示牌应还在手里")

	# ============================================================
	# 7802 三组效果依序触发（法术 + 咏 + 水）
	# ============================================================
	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [无效果牌.id, 咏牌.id, 法术牌.id])
	_置牌库顶(全能牌)
	_开魔法入门()
	var 问全法术: Dictionary = _取询问(1, 魔法入门)
	检(not 问全法术.is_empty(), "7802 三效果：应先询问法术伤害目标")
	检(str(问全法术.get("ask_text", "")).contains("对 2 名目标对手造成 1 点法术伤害"),
		"7802 法术效果提示不对：%s" % str(问全法术.get("ask_text", "")))
	# 头像提示：法术 / 咏都是「1 法术伤害」，按服务端下发的预览类型现算
	检(int(问全法术.get("preview_base", 0)) == 1
		and int(问全法术.get("preview_kind", -1)) == GConst.HarmType.Magic,
		"7802 法术效果应带「1 法术伤害」的头像提示基准：%s" % str(问全法术))
	_回复(1, 魔法入门, [], [], [2, 4])
	# 一个效果一个效果结算：法术伤害应先结算完，才轮到咏类效果的询问
	检(_伤害记录(2, 魔法入门).size() == 1 and _伤害记录(4, 魔法入门).size() == 1,
		"7802 三效果：法术效果应先结算完再问下一个效果")
	检(_伤害记录(3, 魔法入门).is_empty(), "7802 三效果：咏类伤害不应在法术效果之前结算")
	var 问全咏: Dictionary = _取询问(1, 魔法入门)
	检(not 问全咏.is_empty(), "7802 三效果：随后应询问咏类目标")
	检(int((问全咏.get("args", []) as Array)[1]) == 1, "7802 三效果：展示 1 张咏牌应指定 1 名目标")
	检(str(问全咏.get("ask_text", "")).contains("对 1 名目标各造成 1 点法术伤害"),
		"7802 咏类效果提示不对：%s" % str(问全咏.get("ask_text", "")))
	检(int(问全咏.get("preview_base", 0)) == 1
		and int(问全咏.get("preview_kind", -1)) == GConst.HarmType.Magic,
		"7802 咏类效果也应带「1 法术伤害」的头像提示基准：%s" % str(问全咏))
	_回复(1, 魔法入门, [], [], [3])
	检(_伤害记录(3, 魔法入门).size() == 1, "7802 三效果：咏类效果应先结算完再问水系效果")
	检(敌甲.cross_num == 0, "7802 三效果：水系治疗不应在选治疗目标之前结算")
	var 问全水: Dictionary = _取询问(1, 魔法入门)
	检(not 问全水.is_empty(), "7802 三效果：最后应询问水系治疗目标")
	检(int((问全水.get("args", []) as Array)[1]) == 1, "7802 三效果：展示 1 张水系牌应指定 1 名目标")
	检(str(问全水.get("ask_text", "")).contains("指定 1 名目标角色各 +1 【治疗】"),
		"7802 水系效果提示不对：%s" % str(问全水.get("ask_text", "")))
	# 水系效果的头像提示是「+1 治疗」，预览类型必须是治疗（不能按伤害算）
	检(int(问全水.get("preview_base", 0)) == 1
		and int(问全水.get("preview_kind", -1)) == GConst.预览类型_治疗,
		"7802 水系效果应带「+1 治疗」的头像提示基准：%s" % str(问全水))
	# 治疗目标选刚被打过的敌甲：治疗必须在伤害之后结算，否则会白挡掉它自己的 1 点伤害
	_回复(1, 魔法入门, [], [], [2])
	# 触发效果 → 直接问弃 2 张；这里取消（不弃）
	_回复(1, MAGIC_BANG, [])
	检(_伤害记录(2, 魔法入门).size() == 1 and _伤害记录(4, 魔法入门).size() == 1,
		"7802 三效果：法术效果应对 2 名对手各 1 点伤害")
	检(_伤害记录(3, 魔法入门).size() == 1, "7802 三效果：咏类效果应对 3 号造成 1 点伤害")
	检(敌甲.cross_num == 1, "7802 三效果：水系治疗应在伤害结算后 +1（不能被自己那 1 点伤害白挡），实际 %d"
		% 敌甲.cross_num)
	检(玩家.cross_num == 0, "7802 三效果：未选中的自己不应获得治疗")
	检(队友.cross_num == 0, "7802 三效果：未选中的队友不应获得治疗")
	检(玩家.hand_cards.has(全能牌.id), "7802 三效果：展示牌应留在手牌")
	检(_播报次数(MAGIC_BANG) == 0, "7802 三效果：放弃 7803 不应播报")

	# 7802 目标超时 / 跳过：伤害类自动补敌人，治疗类自动补自己 / 队友
	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [法术牌.id])
	_置牌库顶(咏牌)
	_开魔法入门()
	var 问咏超时: Dictionary = _取询问(1, 魔法入门)
	检(not 问咏超时.is_empty(), "7802：咏类展示牌应先问伤害目标")
	引擎.wait_deadline_ms = maxi(Time.get_ticks_msec() - 1, 1)
	引擎.tick()
	var 咏伤害敌: int = _伤害记录(2, 魔法入门).size() + _伤害记录(4, 魔法入门).size()
	检(咏伤害敌 == 1, "7802：咏类目标超时应自动选敌人（实际敌人受伤 %d 人）" % 咏伤害敌)
	检(_伤害记录(1, 魔法入门).is_empty() and _伤害记录(3, 魔法入门).is_empty(),
		"7802：咏类伤害不能补到自己 / 队友")

	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [法术牌.id])
	_置牌库顶(水系牌)
	_开魔法入门()
	var 问水超时: Dictionary = _取询问(1, 魔法入门)
	检(not 问水超时.is_empty(), "7802：水系展示牌应先问治疗目标")
	引擎.wait_deadline_ms = maxi(Time.get_ticks_msec() - 1, 1)
	引擎.tick()
	var 治疗我方: int = 玩家.cross_num + 队友.cross_num
	检(治疗我方 == 1, "7802：水系治疗超时应自动补自己 / 队友（实际我方治疗 %d）" % 治疗我方)
	检(敌甲.cross_num == 0 and 敌乙.cross_num == 0, "7802：水系治疗不能补到敌人")

	# ============================================================
	# 7803 分支 2：展示牌未触发任何效果 → 可选额外 +1 法术行动
	# ============================================================
	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [法术牌.id])
	_置牌库顶(无效果牌)
	_开魔法入门()
	var 问未触发: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问未触发.is_empty(), "7803：展示牌未触发效果时应询问 Magic! 选项")
	检((问未触发.get("option_enabled", []) as Array) == [false, true, false],
		"7803：未触发效果时应只允许「额外+1【法术行动】」：%s" % str(问未触发.get("option_enabled", [])))
	_回复(1, MAGIC_BANG, [2])
	检(引擎._await_id == 1, "7803：额外法术行动应直接进入额外行动阶段")
	检(引擎.行动额外 and int(引擎.行动允许) == GConst.ActionType.Magic,
		"7803：额外行动阶段应只允许法术行动")
	检(int(引擎.行动额外来源) == MAGIC_BANG, "7803：额外行动来源应是 7803")
	检(玩家.hand_cards.size() == 2, "7803：额外行动前应已摸到展示牌")
	检(_播报次数(MAGIC_BANG) == 1, "7803：分支 2 应播报一次")
	检(引擎.team_gem[GConst.BLUE] == 0, "7803：分支 2 不应给战绩区宝石")

	# 第二次发动【魔法入门】（作为 7803 给的额外法术行动）：必须照常走完整流程。
	# 曾经把上一次发动留下的「已结算」标记当成本次 URGENT 后的重入，第二次起技能本体直接返回，
	# 什么都不做、回合直接结束（表现就是「第二次开始放魔法入门会跳过自己回合」）。
	_置牌库顶(全能牌)
	var 次数前: int = 角色._本回合魔法入门次数
	_开魔法入门()
	检(角色._本回合魔法入门次数 == 次数前 + 1,
		"7802 第二次发动：技能本体没进（次数 %d → %d）" % [次数前, 角色._本回合魔法入门次数])
	var 问第二次: Dictionary = _取询问(1, 魔法入门)
	检(not 问第二次.is_empty(), "7802 第二次发动：应照常询问法术伤害目标，实际等待 %s" % str(引擎._await_id))
	检(int(引擎._await_id) == 1, "7802 第二次发动：应等自己选目标，实际 %s" % str(引擎._await_id))
	检((问第二次.get("dst_ids", []) as Array).has(2) and (问第二次.get("dst_ids", []) as Array).has(4),
		"7802 第二次发动：法术目标仍应是两名对手")

	# ============================================================
	# 7803 分支 3：本回合第 3 次【魔法入门】结算 → 战绩区 +2 宝石（第 4 次不再问）
	# ============================================================
	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [法术牌.id])
	角色._本回合魔法入门次数 = 2
	_置牌库顶(无效果牌)
	_开魔法入门()
	var 问第3: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问第3.is_empty(), "7803：第 3 次魔法入门应先询问 Magic! 选项")
	# 第 3 次的宝石奖励要等前一档结算完、下一次弹出的选项才亮（同一问里只亮一档）
	检((问第3.get("option_enabled", []) as Array) == [false, true, false],
		"7803：第 3 次的第一问只应亮「额外+1【法术行动】」，+2【宝石】留到下一问：%s"
		% str(问第3.get("option_enabled", [])))
	_回复(1, MAGIC_BANG, [2])
	var 问第3宝石: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问第3宝石.is_empty(), "7803：选完 +1 法术行动后应再问剩余的 +2 宝石分支")
	检((问第3宝石.get("option_enabled", []) as Array) == [false, false, true],
		"7803：已经选过的分支应置灰：%s" % str(问第3宝石.get("option_enabled", [])))
	_回复(1, MAGIC_BANG, [3])
	检(引擎.team_gem[GConst.BLUE] == 2, "7803：第 3 次应给战绩区 +2 宝石，实际 %d"
		% 引擎.team_gem[GConst.BLUE])
	检(引擎.行动额外 and int(引擎.行动额外来源) == MAGIC_BANG, "7803：第 3 次同时授予的额外法术行动应生效")

	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [法术牌.id])
	角色._本回合魔法入门次数 = 3
	_置牌库顶(无效果牌)
	_开魔法入门()
	var 问第4: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问第4.is_empty(), "7803：第 4 次魔法入门应询问 Magic! 选项")
	检((问第4.get("option_enabled", []) as Array) == [false, true, false],
		"7803：第 4 次时不应再出现 +2 宝石选项：%s" % str(问第4.get("option_enabled", [])))
	_回复(1, MAGIC_BANG, [])
	检(引擎.team_gem[GConst.BLUE] == 0, "7803：第 4 次不应再给 +2 宝石（每回合只在第 3 次问一次）")
	检(引擎._await_id == 2, "7803：放弃后应正常结束行动并轮到下家")

	# 7803 第 3 次 + 触发效果：先弃 2 张、弃完才弹宝石档（不能把弃牌拖到宝石确定之后）
	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [法术牌.id, 咏牌.id, 无效果牌.id])
	角色._本回合魔法入门次数 = 2
	_置牌库顶(水系牌)
	_开魔法入门()
	var 问第三水: Dictionary = _取询问(1, 魔法入门)
	检(not 问第三水.is_empty(), "7803：第 3 次触发效果应先结算水系治疗目标")
	_回复(1, 魔法入门, [], [], [1])
	var 问第三弃: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问第三弃.is_empty(), "7803：应先问弃 2 张牌")
	检((问第三弃.get("option_enabled", []) as Array) == [true, false, false],
		"7803：第 3 次触发效果的第一问只应亮「弃 2 张牌」：%s" % str(问第三弃.get("option_enabled", [])))
	_回复(1, MAGIC_BANG, [1], [法术牌.id, 咏牌.id])
	# 弃牌应已经真正结算（入弃牌堆），此时才应弹宝石档 —— 不能先弹宝石再一起弃
	检(引擎.deck.discard.has(法术牌.id) and 引擎.deck.discard.has(咏牌.id),
		"7803：选完弃 2 张后应先弃掉再问宝石档（实际弃牌堆 %s）" % str(引擎.deck.discard))
	检(玩家.hand_cards.size() == 2 and not 玩家.hand_cards.has(法术牌.id),
		"7803：弃 2 张后手里不应还留着那两张，实际 %s" % str(玩家.hand_cards))
	var 问第三宝石: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问第三宝石.is_empty(), "7803：弃完牌后应再问宝石档")
	检((问第三宝石.get("option_enabled", []) as Array) == [false, false, true],
		"7803：弃完牌后的下一问应只亮宝石档：%s" % str(问第三宝石.get("option_enabled", [])))
	_回复(1, MAGIC_BANG, [3])
	检(引擎.team_gem[GConst.BLUE] == 2, "7803：确定宝石档后应 +2 宝石")

	# ============================================================
	# 7805 友情羁绊：2 名角色各弃 1 张【展示】，技能结束前各摸 1 张
	# ============================================================
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [水系牌.id])
	_填手牌(队友, [水系牌乙.id, 无效果牌.id])
	_置牌库顶(法术牌)
	# 友情羁绊作为魔法入门的一个选项下发（2 档）：选项 2 绑 7805、按钮按响应紫显示，
	# 2 名角色随行动一起提交（同魔眼/强予愿行的 arg_choices）。
	var 入门选项: Array = _技能命令(魔法入门).get("arg_choices", [])
	检(入门选项.size() == 2, "7802：应下发两个选项（实际 %d）" % 入门选项.size())
	if 入门选项.size() == 2:
		检(str((入门选项[0] as Dictionary).get("text", "")) == "你摸 1 张牌【强制】",
			"7802：第 1 档文案不对：%s" % str(入门选项[0]))
		检(int((入门选项[1] as Dictionary).get("skill_id", 0)) == 友情羁绊,
			"7802：第 2 档应绑 7805 的技能号（按钮按响应紫显示）")
		检(str((入门选项[1] as Dictionary).get("text", ""))
			== "-1【宝石】改为我方 2 名角色各弃 1 张牌【强制】，技能效果结束前各摸 1 张牌【强制】",
			"7802：第 2 档文案不对：%s" % str(入门选项[1]))
		检(bool((入门选项[1] as Dictionary).get("enabled", false)),
			"7802：有真宝石且我方 2 名角色有手牌时应可响应友情羁绊")
		检(int((入门选项[1] as Dictionary).get("need_target", 0)) == 2,
			"7802：响应友情羁绊应要求选 2 名角色")
		检(((入门选项[1] as Dictionary).get("targets", []) as Array).has(3),
			"7802：可选角色白名单应含队友")
	_开魔法入门(2, [1, 3])
	检(玩家.gem == 0, "7805：发动友情羁绊应支付 1 真宝石")
	var 问友情弃1: Dictionary = _取询问(1, GConst.RespondType.Discard)
	检(not 问友情弃1.is_empty(), "7805：应先问 1 号弃 1 张牌")
	检(int((问友情弃1.get("args", []) as Array)[2]) == 1, "7805：弃牌询问应各要求 1 张")
	_回复(1, GConst.RespondType.Discard, [1, 友情羁绊, 1], [水系牌.id], [1])
	var 问友情弃3: Dictionary = _取询问(3, GConst.RespondType.Discard)
	检(not 问友情弃3.is_empty(), "7805：应再问队友 3 弃 1 张牌")
	_回复(3, GConst.RespondType.Discard, [3, 友情羁绊, 1], [水系牌乙.id], [3])
	# 展示集合是 2 张水系牌 → 水系效果 X=2；1 号已无手牌，不满足 7803 弃 2 张；第 1 次魔法入门无第 3 次奖励
	var 问友情水: Dictionary = _取询问(1, 魔法入门)
	检(not 问友情水.is_empty(), "7805：改写后的 2 张展示牌应触发水系效果目标询问")
	检(int((问友情水.get("args", []) as Array)[1]) == 2, "7805：2 张水系牌应要求 2 名治疗目标")
	_回复(1, 魔法入门, [], [], [1, 3])
	检(玩家.cross_num == 1 and 队友.cross_num == 1, "7805：2 名角色应各 +1 治疗")
	检(玩家.hand_cards.size() == 1, "7805：技能结束前 1 号应摸 1 张【强制】")
	检(队友.hand_cards.size() == 2, "7805：技能结束前队友应摸 1 张【强制】")
	检(引擎.deck.discard.has(水系牌.id) and 引擎.deck.discard.has(水系牌乙.id),
		"7805：展示的 2 张牌应进弃牌堆")
	检(_伤害记录(2, 魔法入门).is_empty() and _伤害记录(4, 魔法入门).is_empty(),
		"7805：水系牌展示不应造成伤害")
	检(_播报次数(友情羁绊) == 1 and _播报次数(魔法入门) == 1, "7805：应各播报一次")
	# 7805 的 2 张弃牌是同一次【展示】：必须整批发一条 Show 消息。
	# 分两条发时客户端的展示区会「新一拨顶掉上一拨」，实际只能看到最后一张。
	var 展示条数: int = 0
	var 展示两张: bool = false
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Card:
			continue
		var 展示数据: Dictionary = r.get("data", {})
		if int(展示数据.get("type", 0)) != GConst.CardMsgType.Show:
			continue
		展示条数 += 1
		if (展示数据.get("card_ids", []) as Array).size() == 2:
			展示两张 = true
	检(展示条数 == 1 and 展示两张,
		"7805：两张展示牌应整批发一条 Show 消息（实际 %d 条，含两张=%s）" % [展示条数, str(展示两张)])

	# 7805 弃牌是强制的（原文「我方 2 名角色各弃 1 张牌【强制】【展示】」）：
	# 目标超时（空回复）也要按手牌顺序自动补弃 1 张，不能白跳过（少一张会连带改变 X）
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [水系牌.id, 无效果牌.id])
	_填手牌(队友, [水系牌乙.id])
	_置牌库顶(法术牌)
	_开魔法入门(2, [1, 3])
	var 弃前: int = 玩家.hand_cards.size()
	_回复(1, GConst.RespondType.Discard, [1, 友情羁绊, 1], [], [1])   # 1 号超时：空回复
	检(玩家.hand_cards.size() == 弃前 - 1,
		"7805：1 号超时也应自动补弃 1 张（%d → %d）" % [弃前, 玩家.hand_cards.size()])
	检(not _取询问(3, GConst.RespondType.Discard).is_empty(), "7805：1 号超时后应继续问 3 号弃牌")
	var 展示记录: Array = 角色._7802友情弃牌
	检(展示记录.size() >= 1 and int((展示记录[0] as Dictionary).get("card", -1)) == 水系牌.id,
		"7805：1 号超时自动补弃的牌应记进展示集合：%s" % str(展示记录))
	_回复(3, GConst.RespondType.Discard, [3, 友情羁绊, 1], [水系牌乙.id], [3])
	检((角色._7802友情弃牌 as Array).size() == 2,
		"7805：2 名角色的展示弃牌都应有真实牌：%s" % str(角色._7802友情弃牌))

	# 7805 不满足条件时不询问
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [水系牌.id])
	_填手牌(队友, [])   # 队友没有手牌 → 可选的「我方角色」不足 2 名
	_置牌库顶(法术牌)
	var 不足选项: Array = _技能命令(魔法入门).get("arg_choices", [])
	检(不足选项.size() == 2 and not bool((不足选项[1] as Dictionary).get("enabled", true)),
		"7802：可选角色不足 2 名时友情羁绊档应置灰")
	_开魔法入门(1)
	检(not _取询问(1, 魔法入门).is_empty(), "7805：不发动时应走普通【魔法入门】目标询问")
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [水系牌.id])
	_填手牌(队友, [无效果牌.id])
	角色._本回合已用友情羁绊 = true
	_置牌库顶(法术牌)
	var 已用选项: Array = _技能命令(魔法入门).get("arg_choices", [])
	检(已用选项.size() == 2 and not bool((已用选项[1] as Dictionary).get("enabled", true)),
		"7802：本回合已发动过友情羁绊时应置灰")

	# ============================================================
	# 7805 + 7803 牌数守恒：7805 的 2 张弃牌在 7803「弃 2 张」询问前就离手，
	# 且每张牌在弃牌堆里只出现一次（旧实现要等技能结算才弃，7803 还能选到、结算时重复入弃）。
	# ============================================================
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [水系牌.id, 法术牌.id, 无效果牌.id])
	_填手牌(队友, [水系牌乙.id, 咏牌.id])
	_置牌库顶(全能牌)
	_开魔法入门(2, [1, 3])
	_回复(1, GConst.RespondType.Discard, [1, 友情羁绊, 1], [水系牌.id], [1])
	检(not 玩家.hand_cards.has(水系牌.id),
		"7805+7803：1 号选定的弃牌应立即离手，实际手牌 %s" % str(玩家.hand_cards))
	检(玩家.hand_cards.size() == 2 and 玩家.hand_cards.has(法术牌.id) and 玩家.hand_cards.has(无效果牌.id),
		"7805+7803：1 号只应扣掉选定的那 1 张，实际手牌 %s" % str(玩家.hand_cards))
	_回复(3, GConst.RespondType.Discard, [3, 友情羁绊, 1], [水系牌乙.id], [3])
	检(not 队友.hand_cards.has(水系牌乙.id),
		"7805+7803：队友选定的弃牌应立即离手，实际手牌 %s" % str(队友.hand_cards))
	# 入弃牌堆统一在结算做（避免「弃牌前拦截」插进后续询问链），这里只要求 2 张牌都已离手
	检(not 玩家.hand_cards.has(水系牌.id) and not 队友.hand_cards.has(水系牌乙.id),
		"7805+7803：2 张弃牌在 7803 询问前都应已离手")
	var 问守恒水: Dictionary = _取询问(1, 魔法入门)
	检(not 问守恒水.is_empty(), "7805+7803：2 张水系展示牌应触发水系目标询问")
	_回复(1, 魔法入门, [], [], [1, 3])
	var 问守恒7803: Dictionary = _取询问(1, MAGIC_BANG)
	检(not 问守恒7803.is_empty(), "7805+7803：展示牌触发效果后应询问 Magic! 选项")
	检((问守恒7803.get("option_enabled", []) as Array) == [true, false, false],
		"7805+7803：触发效果时应只允许「弃 2 张牌」：%s" % str(问守恒7803.get("option_enabled", [])))
	检(not 玩家.hand_cards.has(水系牌.id),
		"7805+7803：7803 弃牌询问时不能再看到 7805 已弃的牌")
	# 7803 的选牌跟选项合在同一个询问里：这里直接选 2 张还留在手里的牌一起提交
	_回复(1, MAGIC_BANG, [1], [法术牌.id, 无效果牌.id])
	检(玩家.hand_cards.size() == 1 and 玩家.hand_cards.has(全能牌.id),
		"7805+7803：结算后 1 号手里应只剩技能结束前摸的 1 张，实际 %s" % str(玩家.hand_cards))
	检(队友.hand_cards.size() == 2, "7805+7803：队友弃 1 摸 1 后应仍是 2 张，实际 %d" % 队友.hand_cards.size())
	for 牌: GCard in [水系牌, 水系牌乙, 法术牌, 无效果牌]:
		检(引擎.deck.discard.count(牌.id) == 1,
			"7805+7803：%s 在弃牌堆应恰好 1 张，实际 %d" % [牌.card_name, 引擎.deck.discard.count(牌.id)])
		检(not 玩家.hand_cards.has(牌.id) and not 队友.hand_cards.has(牌.id),
			"7805+7803：已弃的 %s 不应还留在任何人手里" % 牌.card_name)
		# 牌数守恒：每张牌在「手牌 + 弃牌堆 + 牌库」里合计只能有 1 张
		var 总张数: int = 引擎.deck.discard.count(牌.id) + 引擎.deck.pile.count(牌.id)
		if 玩家.hand_cards.has(牌.id):
			总张数 += 1
		if 队友.hand_cards.has(牌.id):
			总张数 += 1
		检(总张数 == 1, "7805+7803：%s 的总张数应为 1，实际 %d" % [牌.card_name, 总张数])
	检(_播报次数(友情羁绊) == 1, "7805+7803：7805 应播报一次")

	# 7803 结算只处理实际离手的牌：组里混入一张已不在手里的牌时，不能整组塞进弃牌堆
	_重置战斗()
	玩家.set_gem(0)
	_填手牌(玩家, [无效果牌.id, 咏牌.id])
	引擎.deck.discard.append(法术牌.id)   # 模拟：这张牌在结算前（如被别的效果弃掉）已经离手
	var 陈旧弃牌: Array[int] = [法术牌.id, 咏牌.id]
	角色._7802_7803弃牌 = 陈旧弃牌
	角色._结算魔法入门()
	检(引擎.deck.discard.count(法术牌.id) == 1,
		"7803：已在弃牌堆的牌不应被重复塞进弃牌堆，实际 %d" % 引擎.deck.discard.count(法术牌.id))
	检(引擎.deck.discard.count(咏牌.id) == 1, "7803：还在手里的那 1 张应正常进弃牌堆")
	检(玩家.hand_cards.size() == 1 and 玩家.hand_cards.has(无效果牌.id),
		"7803：只应移除还真实在手里的牌，实际手牌 %s" % str(玩家.hand_cards))
	检(_播报次数(MAGIC_BANG) == 1, "7803：实际弃掉 1 张后应播报一次")

	# ============================================================
	# 7804 强予愿行：三档选项走 available_skills 的 arg_choices（同魔眼：点技能直接进二级栏），
	# 选中选项后同一步选牌 / 选角色，最后随行动一次提交
	# ============================================================
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [法术牌.id, 咏牌.id, 水系牌.id, 无效果牌.id, 全能牌.id])
	_填手牌(队友, [法术牌.id, 咏牌.id, 水系牌.id, 无效果牌.id, 全能牌.id])
	引擎.set_team_gem(GConst.BLUE, 1)
	引擎.set_team_crystal(GConst.BLUE, 1)
	# 技能栏直接下发三个选项：点技能即可进二级栏，不再走服务端的选项询问
	var 强予命令: Dictionary = _技能命令(强予愿行)
	检(not 强予命令.is_empty(), "7804：技能栏应下发强予愿行")
	var 强予选项表: Array = 强予命令.get("arg_choices", [])
	检(强予选项表.size() == 3, "7804：应下发三个选项（实际 %d）" % 强予选项表.size())
	if 强予选项表.size() == 3:
		检((强予选项表[0] as Dictionary).get("args", []) == [1]
			and str((强予选项表[0] as Dictionary).get("text", "")) == "仅调整自己手牌为 4",
			"7804：第一档文案 / 参数不对：%s" % str(强予选项表[0]))
		检(str((强予选项表[1] as Dictionary).get("text", "")) == "【战绩区】-1【水晶】调整其他角色手牌为 4"
			and int((强予选项表[1] as Dictionary).get("need_card", 0)) == 1
			and int((强予选项表[1] as Dictionary).get("need_target", 0)) == 1,
			"7804：第二档应带弃 1 张 + 选 1 名角色：%s" % str(强予选项表[1]))
		检(str((强予选项表[2] as Dictionary).get("text", "")) == "【战绩区】-1【宝石】调整其他角色手牌为 4"
			and ((强予选项表[2] as Dictionary).get("targets", []) as Array).has(3),
			"7804：第三档应带其他角色白名单：%s" % str(强予选项表[2]))
	# 选「-1 水晶」+ 弃 1 张 + 选队友 3，一次行动提交
	_开强予愿行(2, [咏牌.id], [3])
	检(引擎._await_id == 3, "7804：先由目标牌主 3 选择要弃的牌")
	检(玩家.get_energy() == 0, "7804：应已支付 1 能量（宝石顶水晶）")
	检(引擎.team_gem[GConst.BLUE] == 1 and 引擎.team_crystal[GConst.BLUE] == 0,
		"7804：应额外移除 1 颗水晶，宝石保留")
	检(玩家.hand_cards.size() == 4 and not 玩家.hand_cards.has(咏牌.id),
		"7804：自己的弃牌应随行动一起交掉，实际 %s" % str(玩家.hand_cards))
	检(玩家.boot_skill_used, "7804：发动启动技能后应置 boot_skill_used")
	_回复(3, GConst.RespondType.Discard, [3, 强予愿行, 1], [法术牌.id], [3])
	检(玩家.hand_cards.size() == 4 and 队友.hand_cards.size() == 4,
		"7804：双方手牌都应调整为 4 张，实际 %d / %d" % [玩家.hand_cards.size(), 队友.hand_cards.size()])
	检(引擎.deck.discard.has(咏牌.id) and 引擎.deck.discard.has(法术牌.id),
		"7804：双方弃掉的牌应进弃牌堆")
	检(_播报次数(强予愿行) == 1, "7804：应播报一次")
	检(引擎._await_id == 1, "7804：启动技能结算完应重新进入自己的行动阶段")
	var 启动后技能: Dictionary = _技能命令(强予愿行)
	检(not 启动后技能.is_empty() and not bool(启动后技能.get("enabled", true)),
		"7804：本回合发动过启动技能后应置灰")

	# 7804：没有战绩区星石 → 后两档置灰，选「仅调整自己」
	_重置战斗()
	玩家.set_crystal(1)
	_填手牌(玩家, [法术牌.id, 咏牌.id, 水系牌.id])
	_置牌库顶(无效果牌)
	var 无石选项: Array = _技能命令(强予愿行).get("arg_choices", [])
	检(无石选项.size() == 3
		and bool((无石选项[0] as Dictionary).get("enabled", true))
		and not bool((无石选项[1] as Dictionary).get("enabled", true))
		and not bool((无石选项[2] as Dictionary).get("enabled", true)),
		"7804：没有星石时后两档应置灰：%s" % str(无石选项))
	检(int((无石选项[0] as Dictionary).get("need_card", -1)) == 0,
		"7804：手牌不足 4 张时不需要弃牌：%s" % str(无石选项))
	_开强予愿行(1)
	检(玩家.crystal == 0 and 玩家.get_energy() == 0, "7804：应支付 1 水晶")
	检(玩家.hand_cards.size() == 4, "7804：自己不足 4 张时应强制摸到 4 张")
	检(队友.hand_cards.is_empty(), "7804：选「仅调整自己」不应调整其他角色")
	检(引擎._await_id == 1, "7804：选「仅调整自己」后应回到行动阶段")
	检(_播报次数(强予愿行) == 1, "7804：应播报一次")

	# 7804：有星石但选「仅调整自己」→ 不扣星石、不调整他人
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [法术牌.id, 咏牌.id, 水系牌.id])
	引擎.set_team_gem(GConst.BLUE, 1)
	_置牌库顶(无效果牌)
	_开强予愿行(1)
	检(引擎.team_gem[GConst.BLUE] == 1, "7804：选「仅调整自己」不应移除星石")
	检(玩家.hand_cards.size() == 4 and 队友.hand_cards.is_empty(),
		"7804：选「仅调整自己」只调整自己")
	检(玩家.get_energy() == 0, "7804：仍应支付 1 能量")

	# 7804：硬提交非法目标（选自己）被驳回，不扣费、不调整手牌
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [法术牌.id, 咏牌.id, 水系牌.id])
	引擎.set_team_crystal(GConst.BLUE, 1)
	_置牌库顶(无效果牌)
	_开强予愿行(2, [], [1])
	检(_有错误输入(1), "7804：目标选自己应被驳回")
	检(玩家.get_energy() == 1 and 引擎.team_crystal[GConst.BLUE] == 1,
		"7804：被驳回时能量 / 星石都不应扣")
	检(玩家.hand_cards.size() == 3 and 队友.hand_cards.is_empty(),
		"7804：被驳回时不应调整任何人的手牌")
	检(引擎._await_id == 1, "7804：被驳回后应回到行动阶段")

	# 7804：弃到 4 张的张数不对（手牌 5 张但一张都不弃）→ 驳回
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [法术牌.id, 咏牌.id, 水系牌.id, 无效果牌.id, 全能牌.id])
	_置牌库顶(无效果牌)
	_开强予愿行(1)
	检(_有错误输入(1), "7804：弃牌张数不足应被驳回")
	检(玩家.hand_cards.size() == 5 and 玩家.get_energy() == 1,
		"7804：被驳回时手牌 / 能量都不应变化")

	# 7804：战绩区没有对应星石时硬提交那一档 → 驳回
	_重置战斗()
	玩家.set_gem(1)
	_填手牌(玩家, [法术牌.id, 咏牌.id, 水系牌.id])
	引擎.set_team_gem(GConst.BLUE, 1)
	_置牌库顶(无效果牌)
	_开强予愿行(2, [], [3])
	检(_有错误输入(1), "7804：没有水晶时选水晶档应被驳回")
	检(玩家.get_energy() == 1 and 引擎.team_gem[GConst.BLUE] == 1,
		"7804：被驳回时能量 / 宝石都不应扣")

	# 7804：能量不足时被引擎驳回
	_重置战斗()
	引擎.resolve_action(GConst.ActionType.ActivateSkill, {
		"src_id": 1, "action_id": 强予愿行, "card_ids": [], "dst_ids": [], "args": [1],
	})
	引擎.run()
	检(_有错误输入(1), "7804：能量 0 时硬提交应被驳回")
	检(_播报次数(强予愿行) == 0, "7804：被驳回时不应播报")

	# ============================================================
	# 回合重置：魔法入门次数 / 友情羁绊回合限定
	# ============================================================
	_重置战斗()
	角色._本回合魔法入门次数 = 2
	角色._本回合已用友情羁绊 = true
	角色.p_before_turn_begin({})
	检(角色._本回合魔法入门次数 == 0, "回合开始应清零本回合【魔法入门】次数")
	检(not 角色._本回合已用友情羁绊, "回合开始应清零 7805 的回合限定标记")

	# 收尾：清掉状态栈与等待，避免退出时残留询问
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()

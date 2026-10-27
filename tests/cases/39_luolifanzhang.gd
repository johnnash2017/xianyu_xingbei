extends 自检用例
## R97 萝莉番长（97）：9701 喧哗上等 / 9702 夜露死苦 / 9703 爱死天流 / 9704 灭茶苦茶。
##
## 任务范围只有 role + test：角色表「脚本」列留给 DATA，用例里手动挂角色脚本。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 四颗技能行 / 技能说明 / 脚本文件；
##   - 9701：血类命格法术牌连续移除（第 3 张必停）、遇到非血或非法术牌停下、
##            血类攻击牌 / 非血攻击牌各移除 1 张、牌库不足不洗回、牌库空 X=0、
##            非自己 / 非法术伤害不触发、应战反击（is_active=false）也触发、同一次命中只结算一次；
##   - 9702：借用 201 血影狂刀 / 202 血腥咆哮，询问与播报都用本角色 9702；
##            目标手牌 2/3 张的加伤、取消、目标非主动攻击不触发；
##   - 9703：目标「拥有治疗」（>0）即可发动【血腥咆哮】；效果改为关闭【圣光】抵挡，
##            不再改为强制命中；目标没有治疗时不询问；
##   - 9704：宝石 +2 / 水晶 +1 的支付与加伤、宝石可顶水晶、取消不扣资源、
##            选项按资源置灰、两项都不可用时不询问、非法回复兜底、同一次命中只问一次；
##            与 9701 同一次命中时的先后（9704 的预览基准含 9701 加伤）。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_luolifanzhang.gd")
const 狂战士helper: GDScript = preload("res://scripts/battle/skills/skill_berserker.gd")

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 靶: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 血魔牌: Array = []
var 血攻牌: GCard = null
var 非血魔牌: GCard = null
var 非血攻牌: GCard = null
var 血影牌: GCard = null
var 咆哮牌: GCard = null


func _init() -> void:
	名称 = "萝莉番长"


# ============================================================
# 找牌 / 查消息
# ============================================================
## 卡库里第一张满足条件的牌（排除虚拟牌）
func _取牌(条件: Callable) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if bool(条件.call(c)):
			return c
	return null


## 卡库里所有满足条件的牌（排除虚拟牌）
func _取牌表(条件: Callable) -> Array:
	var out: Array = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if bool(条件.call(c)):
			out.append(c)
	return out


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


## 展示（CardMsgType.Show）过指定牌几次
func _展示次数(牌号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Card:
			continue
		var 数据: Dictionary = r.get("data", {})
		if int(数据.get("type", -1)) != GConst.CardMsgType.Show:
			continue
		if (数据.get("card_ids", []) as Array).has(牌号):
			n += 1
	return n


# ============================================================
# 建引擎 / 重置
# ============================================================
func _建引擎() -> void:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "番长")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	靶 = 引擎.p(2)
	玩家.role_id = 97
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色


## 清空战斗状态：回到「轮到玩家 1、行动阶段、无资源、牌库空」的同一起点
func _重置() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.skip_action_phase = false
	发送记录.clear()
	_清空玩家(玩家)
	_清空玩家(靶)
	引擎.deck.pile.clear()
	引擎.deck.discard.clear()
	角色.p_before_turn_begin({})


func _清空玩家(p0: BattlePlayer) -> void:
	p0.hand_cards.clear()
	p0.basic_effects.clear()
	p0.cross_num = 0
	p0.set_crystal(0)
	p0.set_gem(0)
	p0.additional_actions.clear()
	p0.reset_action_counts()


## 把牌库设成「从顶到底」的给定顺序（pile 末尾才是牌库顶）
func _设牌库顶(从顶到底: Array) -> void:
	引擎.deck.pile.clear()
	引擎.deck.discard.clear()
	for i: int in range(从顶到底.size() - 1, -1, -1):
		引擎.deck.pile.append(int(从顶到底[i]))


## 命中上下文（p_timeline_2_hit / p_timeline_1 共用同一份结构）
func _攻击上下文(牌号: int, 伤害: int, 类型: int = GConst.HarmType.Attack, 主动: bool = true) -> Dictionary:
	var harm: Dictionary = {
		"src": 1, "dst": 2, "point": 伤害, "cause": GConst.CAUSE_ATTACK,
		"type": 类型, "card_id": 牌号, "is_active": 主动,
	}
	return {
		"card_id": 牌号, "dst": 2, "src": 1, "is_active": 主动,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": harm,
	}


## 直接调用角色钩子时预置一份回复（对应玩家在客户端点了确定 / 取消）
func _应答(args: Array) -> void:
	引擎._reply = {"args": args, "card_ids": [], "dst_ids": []}
	引擎._has_reply = true


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 ----
	检(str(Data.role_list.get(97, "")) == "萝莉番长", "97 号角色名不是「萝莉番长」")
	检(Data.role_personal_name(97) == "柠歌", "97 号角色姓名不是「柠歌」")
	检(absf(Data.role_star(97) - 3.0) < 0.01, "萝莉番长应是 3.0 星，实际 %s" % str(Data.role_star(97)))
	检(Data.role_skills(97) == [9701, 9702, 9703, 9704],
		"萝莉番长技能号不对：%s" % str(Data.role_skills(97)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_luolifanzhang.gd"),
		"萝莉番长的角色脚本文件不存在")
	检(ResourceLoader.exists("res://scripts/battle/skills/skill_berserker.gd"),
		"狂战士独有技 helper 文件不存在")
	for 技能号: int in [9701, 9702, 9703, 9704]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	var 技能说明: String = Data.role_skill_info(97)
	for 技能名: String in ["喧哗上等", "夜露死苦", "爱死天流", "灭茶苦茶"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提 ----
	血魔牌 = _取牌表(func(c: GCard) -> bool:
		return c.is_magic() and c.fate_pattern_enum() == GConst.FatePattern.Blood)
	血攻牌 = _取牌(func(c: GCard) -> bool:
		return c.is_attack() and c.fate_pattern_enum() == GConst.FatePattern.Blood)
	非血魔牌 = _取牌(func(c: GCard) -> bool:
		return c.is_magic() and c.fate_pattern_enum() != GConst.FatePattern.Blood)
	非血攻牌 = _取牌(func(c: GCard) -> bool:
		return c.is_attack() and c.fate_pattern_enum() != GConst.FatePattern.Blood)
	血影牌 = _取牌(func(c: GCard) -> bool:
		return c.is_attack() and c.has_skill_id(201))
	咆哮牌 = _取牌(func(c: GCard) -> bool:
		return c.is_attack() and c.has_skill_id(202))
	检(血魔牌.size() >= 3, "卡库里的血类命格法术牌不足 3 张（实际 %d）" % 血魔牌.size())
	检(血攻牌 != null, "卡库找不到血类命格攻击牌")
	检(非血魔牌 != null, "卡库找不到非血类命格法术牌")
	检(非血攻牌 != null, "卡库找不到非血类命格攻击牌")
	检(血影牌 != null, "卡库找不到带【血影狂刀】的攻击牌")
	检(咆哮牌 != null, "卡库找不到带【血腥咆哮】的攻击牌")
	if 血魔牌.size() < 3 or 血攻牌 == null or 非血魔牌 == null or 非血攻牌 == null \
			or 血影牌 == null or 咆哮牌 == null:
		return

	_建引擎()
	_测喧哗上等()
	_测灭茶苦茶()
	_测夜露死苦与爱死天流()


# ============================================================
# 9701 喧哗上等
# ============================================================
func _测喧哗上等() -> void:
	# 血类命格法术牌：连续移除，第 3 张必停
	_重置()
	var 三张: Array = [血魔牌[0].id, 血魔牌[1].id, 血魔牌[2].id]
	_设牌库顶(三张)
	var 上下文: Dictionary = _攻击上下文(非血攻牌.id, 3)
	var 伤害: Dictionary = 上下文["harm"]
	var r: int = 角色.p_timeline_2_hit(上下文)
	检(r == BattleRole.SUCCESS, "9701 结算是自动的，不应等待（返回 %d）" % r)
	检(int(伤害["point"]) == 6, "连续移除 3 张血类命格法术牌应 +3 伤害，实际 %d" % int(伤害["point"]))
	检(引擎.deck.pile.is_empty(), "连续移除 3 张后牌库应为空，实际 %s" % str(引擎.deck.pile))
	检(引擎.deck.discard == 三张, "移除的 3 张牌应按移除顺序进弃牌堆，实际 %s" % str(引擎.deck.discard))
	for 牌号: int in 三张:
		检(_展示次数(牌号) == 1, "牌库顶的 %d 应【展示】一次，实际 %d 次" % [牌号, _展示次数(牌号)])
	检(_播报次数(9701) == 1, "【喧哗上等】触发应播报一次，实际 %d 次" % _播报次数(9701))

	# 同一次命中的钩子重入不应重复结算
	发送记录.clear()
	角色.p_timeline_2_hit(上下文)
	检(int(伤害["point"]) == 6, "同一次命中重入不应再加伤，实际 %d" % int(伤害["point"]))
	检(_播报次数(9701) == 0, "同一次命中重入不应再播报【喧哗上等】")

	# 遇到非血类命格法术牌：移除 2 张停下
	_重置()
	_设牌库顶([血魔牌[0].id, 非血魔牌.id])
	上下文 = _攻击上下文(非血攻牌.id, 3)
	伤害 = 上下文["harm"]
	角色.p_timeline_2_hit(上下文)
	检(int(伤害["point"]) == 5, "血类法术牌后遇到非血法术牌应移除 2 张（+2），实际 %d"
		% int(伤害["point"]))
	检(引擎.deck.discard == [血魔牌[0].id, 非血魔牌.id],
		"移除的 2 张牌应进弃牌堆，实际 %s" % str(引擎.deck.discard))

	# 遇到血类命格攻击牌（非法术）：移除 1 张停下
	_重置()
	_设牌库顶([血攻牌.id])
	上下文 = _攻击上下文(非血攻牌.id, 3)
	伤害 = 上下文["harm"]
	角色.p_timeline_2_hit(上下文)
	检(int(伤害["point"]) == 4, "血类命格攻击牌不是法术牌，应只移除 1 张（+1），实际 %d"
		% int(伤害["point"]))
	检(引擎.deck.discard == [血攻牌.id], "移除的血类攻击牌应进弃牌堆")

	# 遇到非血类命格攻击牌：也移除 1 张停下
	_重置()
	_设牌库顶([非血攻牌.id])
	上下文 = _攻击上下文(非血攻牌.id, 3)
	伤害 = 上下文["harm"]
	角色.p_timeline_2_hit(上下文)
	检(int(伤害["point"]) == 4, "非血类命格攻击牌应只移除 1 张（+1），实际 %d"
		% int(伤害["point"]))

	# 牌库不足 / 空牌库：不洗回弃牌堆，X=0
	_重置()
	_设牌库顶([])
	引擎.deck.discard.append(非血攻牌.id)
	上下文 = _攻击上下文(非血攻牌.id, 3)
	伤害 = 上下文["harm"]
	角色.p_timeline_2_hit(上下文)
	检(int(伤害["point"]) == 3, "空牌库时 X=0，伤害不应变化，实际 %d" % int(伤害["point"]))
	检(引擎.deck.discard == [非血攻牌.id], "空牌库不应把弃牌堆洗回，实际 %s" % str(引擎.deck.discard))
	检(_播报次数(9701) == 0, "没有移除任何牌时不应播报【喧哗上等】")

	# 别人的攻击命中 / 非法术伤害：不触发
	_重置()
	_设牌库顶([血魔牌[0].id])
	上下文 = _攻击上下文(非血攻牌.id, 3)
	上下文["src"] = 2
	(上下文["harm"] as Dictionary)["src"] = 2
	角色.p_timeline_2_hit(上下文)
	检(int((上下文["harm"] as Dictionary)["point"]) == 3, "别人的攻击命中不应触发【喧哗上等】")
	检(引擎.deck.pile.size() == 1, "别人的攻击命中不应移除牌库顶")
	_重置()
	_设牌库顶([血魔牌[0].id])
	上下文 = _攻击上下文(非血攻牌.id, 3, GConst.HarmType.Magic)
	角色.p_timeline_2_hit(上下文)
	检(int((上下文["harm"] as Dictionary)["point"]) == 3, "非法术伤害不应触发【喧哗上等】")
	检(引擎.deck.pile.size() == 1, "非法术伤害不应移除牌库顶")

	# 应战反击（is_active=false）也按原文「攻击命中」触发
	_重置()
	_设牌库顶([血魔牌[0].id])
	上下文 = _攻击上下文(非血攻牌.id, 3, GConst.HarmType.Attack, false)
	角色.p_timeline_2_hit(上下文)
	检(int((上下文["harm"] as Dictionary)["point"]) == 4,
		"应战反击命中也应触发【喧哗上等】（+1），实际 %d"
		% int((上下文["harm"] as Dictionary)["point"]))


# ============================================================
# 9704 灭茶苦茶
# ============================================================
func _测灭茶苦茶() -> void:
	# 宝石选项：+2，扣 1 真宝石
	_重置()
	玩家.set_gem(1)
	_设牌库顶([])
	var 上下文: Dictionary = _攻击上下文(非血攻牌.id, 2)
	var 伤害: Dictionary = 上下文["harm"]
	var r: int = 角色.p_timeline_2_hit(上下文)
	检(r == BattleRole.WAIT, "有宝石且攻击命中时应先问是否发动【灭茶苦茶】")
	var 问: Dictionary = _取询问(1, 9704)
	检(not 问.is_empty(), "没有下发【灭茶苦茶】询问")
	检(int(问.get("preview_base", 0)) == 2, "【灭茶苦茶】应下发本次攻击原伤害作为预览基准")
	检(int(问.get("preview_kind", 0)) == GConst.HarmType.Attack, "【灭茶苦茶】预览类型应是攻击伤害")
	检((问.get("dst_ids", []) as Array).has(2), "【灭茶苦茶】应把本次攻击目标作为头像提示目标")
	检((问.get("notes", []) as Array).size() == 2, "【灭茶苦茶】应完整下发两个固定选项")
	_应答([1])
	r = 角色.p_timeline_2_hit(上下文)
	检(r == BattleRole.SUCCESS, "选择【宝石】后【灭茶苦茶】应结算完")
	检(int(伤害["point"]) == 4, "选择【宝石】应让本次伤害 +2，实际 %d" % int(伤害["point"]))
	检(玩家.gem == 0, "选择【宝石】应扣 1 点真宝石，实际剩 %d" % 玩家.gem)
	检(_播报次数(9704) == 1, "【灭茶苦茶】发动应播报一次，实际 %d 次" % _播报次数(9704))
	# 同一次命中只问一次
	发送记录.clear()
	角色.p_timeline_2_hit(上下文)
	检(int(伤害["point"]) == 4, "同一次命中重入不应再加伤")
	检(_播报次数(9704) == 0, "同一次命中重入不应再播报")

	# 水晶选项：+1，先扣水晶
	_重置()
	玩家.set_crystal(1)
	_设牌库顶([])
	上下文 = _攻击上下文(非血攻牌.id, 2)
	伤害 = 上下文["harm"]
	检(角色.p_timeline_2_hit(上下文) == BattleRole.WAIT, "有水晶时应先问是否发动【灭茶苦茶】")
	问 = _取询问(1, 9704)
	检(问.get("option_enabled", []) == [false, true],
		"只有水晶时选项应下发为「宝石置灰 / 水晶可用」：%s" % str(问.get("option_enabled", [])))
	_应答([2])
	检(角色.p_timeline_2_hit(上下文) == BattleRole.SUCCESS, "选择【水晶】后应结算完")
	检(int(伤害["point"]) == 3, "选择【水晶】应让本次伤害 +1，实际 %d" % int(伤害["point"]))
	检(玩家.crystal == 0 and 玩家.gem == 0, "选择【水晶】应扣 1 点能量，实际 %d/%d"
		% [玩家.crystal, 玩家.gem])

	# 【水晶】费用可由宝石顶：只有宝石时也能选水晶档，扣宝石
	_重置()
	玩家.set_gem(1)
	_设牌库顶([])
	上下文 = _攻击上下文(非血攻牌.id, 2)
	伤害 = 上下文["harm"]
	检(角色.p_timeline_2_hit(上下文) == BattleRole.WAIT, "有宝石时应先问是否发动【灭茶苦茶】")
	_应答([2])
	检(角色.p_timeline_2_hit(上下文) == BattleRole.SUCCESS, "用宝石顶水晶后应结算完")
	检(int(伤害["point"]) == 3, "用宝石顶水晶应 +1，实际 %d" % int(伤害["point"]))
	检(玩家.gem == 0 and 玩家.crystal == 0, "用宝石顶水晶应扣 1 点宝石，实际 %d/%d"
		% [玩家.gem, 玩家.crystal])

	# 取消：不扣资源、不加伤
	_重置()
	玩家.set_gem(1)
	_设牌库顶([])
	上下文 = _攻击上下文(非血攻牌.id, 2)
	伤害 = 上下文["harm"]
	检(角色.p_timeline_2_hit(上下文) == BattleRole.WAIT, "有宝石时应先问是否发动【灭茶苦茶】")
	_应答([])
	检(角色.p_timeline_2_hit(上下文) == BattleRole.SUCCESS, "取消【灭茶苦茶】应直接收尾")
	检(int(伤害["point"]) == 2, "取消【灭茶苦茶】不应加伤")
	检(玩家.gem == 1, "取消【灭茶苦茶】不应扣宝石")
	检(_播报次数(9704) == 0, "取消【灭茶苦茶】不应播报")

	# 两项都付不起：不弹无用询问
	_重置()
	_设牌库顶([])
	上下文 = _攻击上下文(非血攻牌.id, 2)
	发送记录.clear()
	检(角色.p_timeline_2_hit(上下文) == BattleRole.SUCCESS, "没有能量时【灭茶苦茶】不应等待")
	检(_取询问(1, 9704).is_empty(), "没有能量时不应下发【灭茶苦茶】询问")
	检(_播报次数(9704) == 0, "没有能量时不应播报【灭茶苦茶】")

	# 非法回复 / 支付前资源已变化：不扣资源、不加伤
	_重置()
	玩家.set_gem(1)
	_设牌库顶([])
	上下文 = _攻击上下文(非血攻牌.id, 2)
	伤害 = 上下文["harm"]
	检(角色.p_timeline_2_hit(上下文) == BattleRole.WAIT, "有宝石时应先问是否发动【灭茶苦茶】")
	_应答([9])
	检(角色.p_timeline_2_hit(上下文) == BattleRole.SUCCESS, "非法选项应直接收尾")
	检(int(伤害["point"]) == 2 and 玩家.gem == 1, "非法选项不应加伤 / 扣资源")

	# 与 9701 同一次命中：9701 先加伤，9704 的预览基准应含它
	_重置()
	玩家.set_gem(1)
	_设牌库顶([血魔牌[0].id])
	上下文 = _攻击上下文(非血攻牌.id, 2)
	伤害 = 上下文["harm"]
	检(角色.p_timeline_2_hit(上下文) == BattleRole.WAIT,
		"9701 结算后仍有宝石时，9704 应接着询问")
	问 = _取询问(1, 9704)
	检(int(问.get("preview_base", 0)) == 3, "9704 的预览基准应包含 9701 的加伤（2+1=3）：%s"
		% str(问.get("preview_base", 0)))
	_应答([1])
	角色.p_timeline_2_hit(上下文)
	检(int(伤害["point"]) == 5, "9701 +1 再 9704 +2，本次伤害应为 5，实际 %d" % int(伤害["point"]))


# ============================================================
# 9702 夜露死苦 / 9703 爱死天流（借用狂战士 201 / 202）
# ============================================================
func _测夜露死苦与爱死天流() -> void:
	# ---- 201 血影狂刀：询问 / 播报都按 9702，按目标手牌 2 张 +2 ----
	_重置()
	玩家.hand_cards = [血影牌.id]
	靶.hand_cards = [非血攻牌.id, 非血魔牌.id]
	靶.cross_num = 0
	var 上下文: Dictionary = _攻击上下文(血影牌.id, 3)
	var 伤害: Dictionary = 上下文["harm"]
	var r: int = 角色.p_timeline_1(上下文)
	检(r == BattleRole.WAIT, "带【血影狂刀】的攻击应询问是否发动")
	检(not _取询问(1, 9702).is_empty(), "借用【血影狂刀】的询问应按本角色 9702 下发")
	检(_取询问(1, 201).is_empty(), "借用时不应再按狂战士 201 下发询问")
	检(int(_取询问(1, 9702).get("preview_base", 0)) == 3,
		"【血影狂刀】询问应下发本次攻击原伤害作为预览基准")
	_应答([1])
	r = 角色.p_timeline_1(上下文)
	检(r == BattleRole.SUCCESS, "确认【血影狂刀】后应结算完")
	检(int(伤害["point"]) == 5, "目标手牌 2 张时【血影狂刀】应 +2，实际 %d" % int(伤害["point"]))
	检(_播报次数(9702) == 1, "借用【血影狂刀】应按 9702 播报一次，实际 %d 次" % _播报次数(9702))
	检(_播报次数(201) == 0, "借用时不应播报狂战士的 201")

	# 取消发动：不加伤
	_重置()
	玩家.hand_cards = [血影牌.id]
	靶.hand_cards = [非血攻牌.id, 非血魔牌.id]
	上下文 = _攻击上下文(血影牌.id, 3)
	伤害 = 上下文["harm"]
	检(角色.p_timeline_1(上下文) == BattleRole.WAIT, "应询问【血影狂刀】")
	_应答([0])
	检(角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "取消【血影狂刀】应直接收尾")
	检(int(伤害["point"]) == 3, "取消【血影狂刀】不应加伤")

	# ---- 202 血腥咆哮：目标治疗 2 时同样套用 9703 的改写（不再强制命中） ----
	_重置()
	玩家.hand_cards = [咆哮牌.id]
	靶.hand_cards = [非血攻牌.id]
	靶.cross_num = 2
	上下文 = _攻击上下文(咆哮牌.id, 3)
	检(角色.p_timeline_1(上下文) == BattleRole.WAIT, "带【血腥咆哮】的攻击应询问是否发动")
	检(not _取询问(1, 9702).is_empty(), "借用【血腥咆哮】的询问应按本角色 9702 下发")
	_应答([1])
	检(角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "确认【血腥咆哮】后应结算完")
	检(int(上下文.get("hit_rate", -1)) == GConst.HitRate.Normal,
		"9703 把「治疗为 2 → 强制命中」整句替换掉，治疗为 2 也不应再改命中率（实际 %s）"
		% str(上下文.get("hit_rate", -1)))
	检(not bool(上下文.get("can_light", true)), "9703 应关闭本次攻击的【圣光】抵挡")

	# ---- 9703 爱死天流：目标治疗 1 也能发动，效果改为关闭【圣光】抵挡（不再强制命中） ----
	_重置()
	玩家.hand_cards = [咆哮牌.id]
	靶.hand_cards = [非血攻牌.id]
	靶.cross_num = 1
	上下文 = _攻击上下文(咆哮牌.id, 3)
	检(角色.p_timeline_1(上下文) == BattleRole.WAIT,
		"目标拥有 1 点治疗时，9703 改写后也应能发动【血腥咆哮】")
	_应答([1])
	检(角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "确认【血腥咆哮】后应结算完")
	检(int(上下文.get("hit_rate", -1)) == GConst.HitRate.Normal,
		"9703 用「无法暗灭应战 / 无法圣光抵挡」替代强制命中，不应再改命中率")
	检(not bool(上下文.get("can_light", true)), "9703 应关闭本次攻击的【圣光】抵挡")

	# 目标没有治疗：不询问
	_重置()
	玩家.hand_cards = [咆哮牌.id]
	靶.hand_cards = [非血攻牌.id]
	靶.cross_num = 0
	上下文 = _攻击上下文(咆哮牌.id, 3)
	检(角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "目标没有治疗时【血腥咆哮】不应询问")
	检(_取询问(1, 9702).is_empty(), "目标没有治疗时不应下发 9702 询问")

	# 别人的攻击 / 应战反击：不触发借用的独有技
	_重置()
	玩家.hand_cards = [血影牌.id]
	靶.hand_cards = [非血攻牌.id, 非血魔牌.id]
	上下文 = _攻击上下文(血影牌.id, 3)
	上下文["src"] = 2
	检(角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "别人的攻击宣告不应触发萝莉番长的借用独有技")
	检(_取询问(1, 9702).is_empty(), "别人的攻击宣告不应下发 9702 询问")
	_重置()
	玩家.hand_cards = [血影牌.id]
	靶.hand_cards = [非血攻牌.id, 非血魔牌.id]
	上下文 = _攻击上下文(血影牌.id, 3, GConst.HarmType.Attack, false)
	检(角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "应战反击不应触发借用独有技")

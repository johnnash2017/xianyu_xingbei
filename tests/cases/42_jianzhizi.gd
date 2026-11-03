extends 自检用例
## R108 剑之子（108）：10801 倾慕 / 10802 风之剑 / 10803 剑守誓言 / 10804 剑残影。
##
## 任务范围只有 role + test：角色表「脚本」列留给 DATA，用例里手动挂角色脚本。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 四颗技能行 / 技能说明 / 脚本文件；
##   - 10802：技类命格主动攻击才触发；星石类型二选一（宝石 / 水晶，做不了的置灰）；
##            101 给额外攻击行动、102 在目标有圣盾时禁止应战且不查圣盾；取消 / 无星石 /
##            非技类牌 / 应战反击 不触发；
##   - 10804：攻击行动结束后问发动 → 选目标 → 目标强制弃 1 张 → 扣 1 能量、额外 +1 攻击行动；
##            本回合下次主动攻击只能打该目标（目标白名单写进行动规格 + v_attack 兜底，命中一次后解除）；
##            取消发动 / 取消目标不扣费；无能量 / 无目标 / 回合限定不询问；
##   - 10801：剑之魔女在场时获得 4503 / 4504，且 10803 不发动；
##            4503 第 1/2/4 次攻击行动后的档位；4504 支付宝石 + 弃 2 + 摸 1 + 额外攻击；
##   - 10803：主动攻击命中 / 任一方星杯增加的回合结束后触发；X＝双方星杯和、牌库顶 X+1 不洗回；
##            选项选 1 张入手、其余进弃牌；有法术牌时 +2 水晶、安排 +1 额外回合、永久替换为风之剑圣；
##            取消发动 / 无触发条件 / 剑之魔女在场时不发动。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_jianzhizi.gd")
const 卡牌UI脚本: GDScript = preload("res://scripts/CardUI.gd")

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 靶: BattlePlayer = null
var 队友: BattlePlayer = null
var 敌二: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 疾风牌: GCard = null
var 烈风牌: GCard = null
var 非技击牌: GCard = null
var 盾牌: GCard = null
var 魔法牌: GCard = null
var 非魔牌表: Array = []


func _init() -> void:
	名称 = "剑之子"


# ============================================================
# 找牌 / 查消息
# ============================================================
func _取牌(条件: Callable) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if bool(条件.call(c)):
			return c
	return null


func _取牌表(条件: Callable, 数量: int = 0) -> Array:
	var out: Array = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if bool(条件.call(c)):
			out.append(c)
			if 数量 > 0 and out.size() >= 数量:
				break
	return out


## 连取 数量 张互不相同的实体牌（排除虚拟牌 / 指定牌）
func _取实体牌号(数量: int, 排除: Array = []) -> Array:
	var out: Array = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id) or out.has(c.id):
			continue
		out.append(c.id)
		if out.size() >= 数量:
			break
	return out


func _取询问(pid: int, respond_id: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == respond_id:
			return r
	return {}


## 聚合器把全部选项塞在同一条询问里，respond_id 只是第一项；按选项值找那条询问。
func _取选项询问(pid: int, 选项值: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if (r.get("args", []) as Array).slice(4).has(选项值):
			return r
	return {}


func _播报次数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Skill:
			continue
		if int((r.get("data", {}) as Dictionary).get("skill_id", 0)) == 技能号:
			n += 1
	return n


## 展示（CardMsgType.Show）里是否一次展示过这些牌
func _展示过(牌表: Array) -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Card:
			continue
		var 数据: Dictionary = r.get("data", {})
		if int(数据.get("type", -1)) != GConst.CardMsgType.Show:
			continue
		var 发牌: Array = 数据.get("card_ids", [])
		var 全含: bool = true
		for c: Variant in 牌表:
			if not 发牌.has(int(c)):
				全含 = false
				break
		if 全含:
			return true
	return false


## 最近一条展示这些牌的 Show 消息（没有返回空字典）
func _展示消息(牌表: Array) -> Dictionary:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r.get("msg", 0)) != GConst.Msg.Card:
			continue
		var 数据: Dictionary = r.get("data", {})
		if int(数据.get("type", -1)) != GConst.CardMsgType.Show:
			continue
		var 发牌: Array = 数据.get("card_ids", [])
		var 全含: bool = true
		for c: Variant in 牌表:
			if not 发牌.has(int(c)):
				全含 = false
				break
		if 全含:
			return 数据
	return {}


## 某张牌「从展示区选走」（CardMsgType.Pick）的消息；没有返回空字典
func _选走消息(牌号: int) -> Dictionary:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Card:
			continue
		var 数据: Dictionary = r.get("data", {})
		if int(数据.get("type", -1)) != GConst.CardMsgType.Pick:
			continue
		if (数据.get("card_ids", []) as Array).has(牌号):
			return 数据
	return {}


# ============================================================
# 建引擎 / 重置
# ============================================================
func _建引擎() -> void:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "剑之子")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	靶 = 引擎.p(2)
	队友 = 引擎.p(3)
	敌二 = 引擎.p(4)
	玩家.role_id = 108
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色


## 清空战斗状态：轮到玩家 1、行动阶段、无资源 / 无牌、无额外行动
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.round_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.额外回合玩家 = -1
	引擎.额外回合攻击加伤 = 0
	引擎.额外回合来源 = 0
	引擎.当前额外回合玩家 = -1
	引擎.当前额外回合攻击加伤 = 0
	引擎.当前额外回合来源 = 0
	引擎.额外回合续位 = -1
	引擎.deck.pile.clear()
	引擎.deck.discard.clear()
	引擎.team_gem[GConst.BLUE] = 0
	引擎.team_crystal[GConst.BLUE] = 0
	引擎.team_gem[GConst.RED] = 0
	引擎.team_crystal[GConst.RED] = 0
	引擎.team_grail = [0, 0]
	发送记录.clear()
	队友.role_id = 0
	for pid: int in 引擎.order:
		_清空玩家(引擎.p(pid))
	角色.p_before_turn_begin({})


func _清空玩家(p0: BattlePlayer) -> void:
	p0.hand_cards.clear()
	p0.cover_cards.clear()
	p0.basic_effects.clear()
	p0.additional_actions.clear()
	p0.cross_num = 0
	p0.set_crystal(0)
	p0.set_gem(0)
	p0.tap = false
	p0.boot_skill_used = false
	p0.跳过额外攻击行动 = false
	p0.reset_action_counts()


## 剑之魔女「在场」：本工程没有离场机制，只需要把队友的角色卡设成 45
func _挂剑之魔女() -> void:
	队友.role_id = 45


func _设牌库顶(从顶到底: Array) -> void:
	引擎.deck.pile.clear()
	for i: int in range(从顶到底.size() - 1, -1, -1):
		引擎.deck.pile.append(int(从顶到底[i]))


## 攻击上下文（p_timeline_1 / p_timeline_2_hit 共用）
func _攻击上下文(牌号: int, 伤害: int = 2, 主动: bool = true, 目标: int = 2) -> Dictionary:
	var harm: Dictionary = {
		"src": 1, "dst": 目标, "point": 伤害, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 牌号, "is_active": 主动,
	}
	return {
		"card_id": 牌号, "dst": 目标, "src": 1, "is_active": 主动,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": harm,
	}


## 直接调用角色钩子时预置一份回复
func _应答(args: Array, dst_ids: Array = [], cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": dst_ids}
	引擎._has_reply = true


## 通过行动聚合器入口驱动一次「攻击结束」响应（等价于生产流程里的 _push_action_end_hooks）。
func _驱动攻击结束(上下文: Dictionary = {}) -> void:
	var ctx: Dictionary = {"player": 1, "kind": "attack"}
	ctx.merge(上下文, true)
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", ctx, false, 0)
	引擎.run()


## 通过聚合器下发的询问回复一条；on_message 内部会继续 run。
func _应答询问(pid: int, respond_id: int, args: Array, cards: Array = [], dsts: Array = []) -> void:
	引擎.on_message(pid, GConst.Msg.Respond, {
		"respond_id": respond_id, "src_id": pid, "args": args,
		"card_ids": cards, "dst_ids": dsts,
	})


func _有额外行动(cause: int) -> bool:
	for a: Dictionary in 玩家.additional_actions:
		if int(a.get("cause", 0)) == cause:
			return true
	return false


## 本轮是否给玩家 1 回过「操作无效」（ErrorInput）
func _有错误输入() -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) == GConst.Msg.ErrorInput:
			return true
	return false


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据 ----
	检(str(Data.role_list.get(108, "")) == "剑之子", "108 号角色名不是「剑之子」")
	检(Data.role_personal_name(108) == "威斯特姆", "108 号角色姓名不是「威斯特姆」")
	检(absf(Data.role_star(108) - 3.0) < 0.01, "剑之子应是 3.0 星，实际 %s" % str(Data.role_star(108)))
	检(Data.role_skills(108) == [10801, 10802, 10803, 10804],
		"剑之子技能号不对：%s" % str(Data.role_skills(108)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_jianzhizi.gd"),
		"剑之子的角色脚本文件不存在")
	for 技能号: int in [10801, 10802, 10803, 10804]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	var 技能说明: String = Data.role_skill_info(108)
	for 技能名: String in ["倾慕", "风之剑", "剑守誓言", "剑残影"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提 ----
	疾风牌 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.fate_pattern_enum() == GConst.FatePattern.Martial and c.has_skill_id(101))
	烈风牌 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.fate_pattern_enum() == GConst.FatePattern.Martial and c.has_skill_id(102))
	非技击牌 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.fate_pattern_enum() != GConst.FatePattern.Martial)
	盾牌 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() == GConst.CardName.Shield)
	魔法牌 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.card_name_enum() != GConst.CardName.Shield)
	非魔牌表 = _取牌表(func(c: GCard) -> bool: return c.is_attack(), 6)
	检(疾风牌 != null, "卡库找不到带【疾风技】的技类攻击牌")
	检(烈风牌 != null, "卡库找不到带【烈风技】的技类攻击牌")
	检(非技击牌 != null, "卡库找不到非技类攻击牌")
	检(盾牌 != null, "卡库找不到【圣盾】")
	检(魔法牌 != null, "卡库找不到法术牌")
	检(非魔牌表.size() >= 4, "卡库找不到足够的非法术牌")
	if 疾风牌 == null or 烈风牌 == null or 非技击牌 == null \
			or 盾牌 == null or 魔法牌 == null or 非魔牌表.size() < 4:
		return

	_建引擎()
	_测风之剑()
	_测剑残影()
	_测倾慕与梦想剑断念()
	_测攻击结束二选一()
	_测剑守誓言条件()
	_测剑守誓言结算()
	_测剑守誓言替换角色()
	_测剑之子说明书()


# ============================================================
# 10802 风之剑
# ============================================================
func _测风之剑() -> void:
	# 101 疾风技：选宝石 → 扣 1 宝石 + 额外攻击行动
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.hand_cards = [疾风牌.id]
	var 上下文: Dictionary = _攻击上下文(疾风牌.id)
	var r: int = 角色.p_timeline_1(上下文)
	检(r == BattleRole.WAIT, "技类牌主动攻击应询问【风之剑】是否发动")
	var 问: Dictionary = _取询问(1, 10802)
	检(not 问.is_empty(), "没有下发【风之剑】询问")
	检((问.get("notes", []) as Array).size() == 2, "【风之剑】应完整下发宝石 / 水晶两个星石选项")
	检(问.get("option_enabled", []) == [true, false],
		"只有宝石时选项应为「宝石可用 / 水晶置灰」：%s" % str(问.get("option_enabled", [])))
	_应答([1])
	r = 角色.p_timeline_1(上下文)
	检(r == BattleRole.SUCCESS, "确认【风之剑】后应结算完")
	检(引擎.team_gem[GConst.BLUE] == 0, "选宝石应扣战绩区 1 宝石，实际 %d"
		% 引擎.team_gem[GConst.BLUE])
	检(_有额外行动(101), "101 疾风技应额外 +1 攻击行动（来源记 101）")
	检(_播报次数(101) == 1, "101 疾风技发动应播报一次，实际 %d 次" % _播报次数(101))
	检(_播报次数(10802) == 0, "只应播报实际发动的 101，不应再播报 10802")
	检(int(上下文.get("hit_rate", -1)) == GConst.HitRate.Normal, "101 不应改命中率")

	# 102 烈风技 + 目标有圣盾：选水晶 → 扣 1 水晶、无法应战、不查圣盾
	_重置战斗()
	引擎.set_team_crystal(GConst.BLUE, 1)
	玩家.hand_cards = [烈风牌.id]
	引擎.add_basic_effect(2, 盾牌.id, 1)
	上下文 = _攻击上下文(烈风牌.id)
	r = 角色.p_timeline_1(上下文)
	检(r == BattleRole.WAIT, "目标有【圣盾】时 102 应询问是否发动【风之剑】")
	问 = _取询问(1, 10802)
	检(问.get("option_enabled", []) == [false, true],
		"只有水晶时选项应为「宝石置灰 / 水晶可用」：%s" % str(问.get("option_enabled", [])))
	_应答([2])
	r = 角色.p_timeline_1(上下文)
	检(r == BattleRole.SUCCESS, "确认【风之剑】后应结算完")
	检(引擎.team_crystal[GConst.BLUE] == 0, "选水晶应扣 1 水晶，实际 %d"
		% 引擎.team_crystal[GConst.BLUE])
	检(int(上下文.get("hit_rate", -1)) == GConst.HitRate.NoReattack,
		"102 烈风技应让本次攻击无法应战")
	检(not bool(上下文.get("check_shield", true)), "102 烈风技应不查 / 不消耗圣盾")
	检(_有额外行动(101) == false, "102 不应给额外攻击行动")
	检(_播报次数(102) == 1, "102 烈风技发动应播报一次，实际 %d 次" % _播报次数(102))

	# 卡面技能名：剑之子拿到带 101/102 的牌时，应像风之剑圣本人一样显示为「会」
	var 剑之子显示: Array[int] = 卡牌UI脚本.显示技能(108, Data.role_skills(108))
	检(剑之子显示.has(101) and 剑之子显示.has(102),
		"剑之子卡面应把 101/102 视为自己会的技能：%s" % str(剑之子显示))
	var 剑圣显示: Array[int] = 卡牌UI脚本.显示技能(1, Data.role_skills(1))
	检(剑圣显示.has(101) and 剑圣显示.has(102), "风之剑圣本人应显示 101/102")
	检(not 卡牌UI脚本.显示技能(38, Data.role_skills(38)).has(101),
		"其他角色不应把 101 视为自己会的技能")
	# 测试指令 2：按 2 应能拿到剑圣 101/102 的发动牌（与卡面 / 角色说明同一张表）
	_重置战斗()
	引擎.debug_key(1, GConst.DebugKey.SkillCards)
	var 有101: bool = false
	var 有102: bool = false
	for cid: int in 玩家.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		有101 = 有101 or c.has_skill_id(101)
		有102 = 有102 or c.has_skill_id(102)
	检(有101 and 有102, "测试指令 2 应给剑之子发 101/102 技能牌：%s" % str(玩家.hand_cards))

	# 取消：不扣星石
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.hand_cards = [疾风牌.id]
	检(角色.p_timeline_1(_攻击上下文(疾风牌.id)) == BattleRole.WAIT, "应询问【风之剑】")
	_应答([])
	检(角色.p_timeline_1(_攻击上下文(疾风牌.id)) == BattleRole.SUCCESS, "取消【风之剑】应直接收尾")
	检(引擎.team_gem[GConst.BLUE] == 1, "取消【风之剑】不应扣星石")
	检(_有额外行动(10802) == false, "取消【风之剑】不应给额外攻击行动")

	# 不满足条件：无星石 / 非技类牌 / 应战反击 / 102 目标无圣盾
	_重置战斗()
	玩家.hand_cards = [疾风牌.id]
	发送记录.clear()
	检(角色.p_timeline_1(_攻击上下文(疾风牌.id)) == BattleRole.SUCCESS, "没有星石时不应询问")
	检(_取询问(1, 10802).is_empty(), "没有星石时不应下发【风之剑】询问")
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.hand_cards = [非技击牌.id]
	检(角色.p_timeline_1(_攻击上下文(非技击牌.id)) == BattleRole.SUCCESS, "非技类命格牌不应触发【风之剑】")
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.hand_cards = [疾风牌.id]
	检(角色.p_timeline_1(_攻击上下文(疾风牌.id, 2, false)) == BattleRole.SUCCESS,
		"应战反击不应触发【风之剑】")
	_重置战斗()
	引擎.set_team_gem(GConst.BLUE, 1)
	玩家.hand_cards = [烈风牌.id]
	检(角色.p_timeline_1(_攻击上下文(烈风牌.id)) == BattleRole.SUCCESS,
		"只有 102 且目标没有【圣盾】时不应询问")


# ============================================================
# 10804 剑残影
# ============================================================
func _测剑残影() -> void:
	# 完整流程：聚合器发选项 → 选目标 → 目标弃 1 张 → 扣能量 + 额外攻击 + 目标限制
	_重置战斗()
	玩家.set_crystal(1)
	靶.hand_cards = [非魔牌表[0].id, 非魔牌表[1].id]
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"攻击行动结束后应通过聚合器询问是否发动【剑残影】")
	var 发动问: Dictionary = _取询问(1, 10804)
	检(not 发动问.is_empty(), "没有下发【剑残影】发动询问")
	var 目标需求: Array = 发动问.get("option_need_targets", [])
	检(目标需求.size() >= 1 and int(目标需求[0]) == 1,
		"【剑残影】选项应要求选 1 名目标：%s" % str(目标需求))
	检((发动问.get("option_enabled", []) as Array) == [true, false],
		"没有剑之魔女时应把 4504 一并置灰下发：%s" % str(发动问.get("option_enabled", [])))
	_应答询问(1, 10804, [10804], [], [2])
	检(引擎._await_id == 2 and 引擎._await_kind == GConst.Msg.Respond,
		"选好目标后应等待目标弃 1 张牌")
	var 弃牌问: Dictionary = _取询问(2, 10804)
	检(not 弃牌问.is_empty(), "没有向目标下发【剑残影】弃牌询问")
	检(int((弃牌问.get("args", [0]) as Array)[0]) == 1, "【剑残影】目标应弃 1 张牌")
	检(not bool(弃牌问.get("can_cancel", true)), "【剑残影】的目标弃牌是强制的，不能取消")
	var 目标弃牌号: int = 靶.hand_cards[1]
	_应答询问(2, 10804, [1], [目标弃牌号])
	检(引擎._await_id == -1, "【剑残影】应结算完")
	检(玩家.get_energy() == 0, "【剑残影】应支付 1 能量，实际 %d" % 玩家.get_energy())
	检(_有额外行动(10804), "【剑残影】应额外 +1 攻击行动")
	检(_播报次数(10804) == 1, "【剑残影】发动应播报一次，实际 %d 次" % _播报次数(10804))
	检(靶.hand_cards.size() == 1, "目标应弃 1 张手牌，实际剩 %d 张" % 靶.hand_cards.size())
	检(not 靶.hand_cards.has(目标弃牌号), "目标弃掉的牌应离开手牌")
	检(引擎.deck.discard.has(目标弃牌号),
		"目标弃的牌应进弃牌堆，实际弃牌堆 %s" % str(引擎.deck.discard))
	# 剑残影给的是「最普通的攻击行动」：限制是本回合的玩家级标记（attack_lock），
	# 不写进行动规格 —— 否则限制被别的主动攻击消费掉之后，这份行动还会一直锁着那个目标。
	检((玩家.额外行动数据(10804).get("targets", []) as Array).is_empty(),
		"【剑残影】给的应是普通攻击行动，不该自带目标白名单：%s" % str(玩家.额外行动数据(10804)))
	检(玩家.v_attack(非技击牌.id, 4, 引擎.players) == GConst.GE_INVALID_PLAYERID,
		"其他额外行动的主动攻击同样受「下次主动攻击只打该目标」限制")
	# 普通攻击行动不下发目标白名单：目标限制由玩家身上的标记在提交时校验
	var 额外命令: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false, 10804)
	检(not 额外命令.is_empty() and (额外命令[0].get("dst_ids", []) as Array).is_empty(),
		"【剑残影】的额外攻击行动是普通攻击行动，不该下发目标白名单：%s"
		% str(额外命令[0].get("dst_ids", []) if not 额外命令.is_empty() else []))
	# 标记本身：服务端校验 + 随快照下发（客户端据此把其余敌方头像置灰）
	玩家.hand_cards = [非技击牌.id]
	检(玩家.attack_lock_id == 2, "【剑残影】结算后应留下「下次主动攻击只能打 2」的标记")
	检(玩家.v_attack(非技击牌.id, 4, 引擎.players) == GConst.GE_INVALID_PLAYERID,
		"本回合下次主动攻击打其他对手应被驳回")
	检(玩家.v_attack(非技击牌.id, 2, 引擎.players) == GConst.GE_SUCCESS,
		"打【剑残影】指定目标应通过")
	var 玩家信息: Dictionary = 玩家.to_proto(1)
	检(int(玩家信息.get("attack_lock", 0)) == 2, "快照应带 attack_lock：%s" % str(玩家信息.get("attack_lock", -1)))
	var 信息编码: PackedByteArray = ProtoCodec.encode_named("SinglePlayerInfo", 玩家信息)
	var 信息解码: Dictionary = ProtoCodec.decode_named("SinglePlayerInfo", 信息编码)
	检(int(信息解码.get("attack_lock", 0)) == 2, "SinglePlayerInfo 协议应包含 attack_lock")
	# 打出下一次主动攻击：引擎在 _do_attack 里消费标记（不是靠这份行动 / 这张牌的规格）
	引擎._do_attack(玩家, {"card_ids": [非技击牌.id], "dst_ids": [2]})
	检(玩家.attack_lock_id == 0, "主动攻击打出后应消费「下次主动攻击只能打该目标」的标记")
	玩家.hand_cards = [非技击牌.id]
	检(玩家.v_attack(非技击牌.id, 4, 引擎.players) == GConst.GE_SUCCESS,
		"限制解除后打其他对手应通过")

	# 目标没有手牌：选完目标直接结算，仍给额外攻击行动
	_重置战斗()
	玩家.set_gem(1)
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond, "应询问【剑残影】")
	_应答询问(1, 10804, [10804], [], [2])
	检(引擎._await_id == -1, "目标没有手牌时应直接结算完（不弹弃牌询问）")
	检(_取询问(2, 10804).is_empty(), "目标没有手牌时不应向目标下发弃牌询问")
	检(_有额外行动(10804), "目标没有手牌也应给额外攻击行动")
	检(玩家.gem == 0, "【剑残影】可用宝石顶水晶，实际剩 %d" % 玩家.gem)

	# 取消发动 / 取消目标：都不扣费、不给额外行动
	_重置战斗()
	玩家.set_crystal(1)
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond, "应询问【剑残影】")
	_应答询问(1, 10804, [])
	检(引擎._await_id == -1, "取消发动应直接收尾")
	检(玩家.get_energy() == 1 and not _有额外行动(10804), "取消发动不应扣费 / 给额外行动")
	_重置战斗()
	玩家.set_crystal(1)
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond, "应询问【剑残影】")
	# 选了一项却没选目标：驳回重选（不能静默结束、也不能把这一项用掉），不扣费
	_应答询问(1, 10804, [10804], [], [])
	检(引擎._await_id == 1 and not _取询问(1, 10804).is_empty(),
		"没选目标应驳回并重新询问【剑残影】")
	检(玩家.get_energy() == 1 and not _有额外行动(10804), "没选目标不应扣费 / 给额外行动")
	检(角色._used_剑残影 == false, "没选目标不应消耗回合限定")
	# 再按「取消」（空应答）＝不发动，直接收尾
	_应答询问(1, 10804, [])
	检(引擎._await_id == -1, "取消发动应直接收尾")

	# 无能量 / 回合限定：不询问
	_重置战斗()
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == -1, "没有能量时不应询问【剑残影】")
	检(_取询问(1, 10804).is_empty(), "没有能量时不应下发【剑残影】询问")
	_重置战斗()
	玩家.set_crystal(1)
	角色._used_剑残影 = true
	发送记录.clear()
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == -1, "本回合已发动过【剑残影】后不应再询问")
	检(_取询问(1, 10804).is_empty(), "回合限定时不应下发【剑残影】询问")
	# 新回合重置
	角色.p_before_turn_begin({})
	玩家.set_crystal(1)
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"新回合应重新可以发动【剑残影】")


# ============================================================
# 10801 倾慕：借用 4503 梦想剑 / 4504 剑影*断念
# ============================================================
func _测倾慕与梦想剑断念() -> void:
	# ---- 4503 梦想剑：第 1 / 2 / 4 次攻击行动后的档位 ----
	_重置战斗()
	_挂剑之魔女()
	玩家.reset_action_counts()
	for 次数: int in range(1, 5):
		# 记录行动在攻击宣告前 +1；宣告时不应变绿，等攻击结算完进入「攻击结束」响应才推进
		var 宣告前档: int = 角色.dream_tier()
		玩家.record_action("attack", false)
		角色.p_timeline_1(_攻击上下文(非技击牌.id))
		检(角色.dream_tier() == 宣告前档,
			"第 %d 次攻击宣告时不应提前变绿" % 次数)
		# 展示档是 p_after_attack 自身的职责（行动选项已交给聚合器），这里单独验证钩子推进
		角色.p_after_attack({"player": 1, "kind": "attack"})
		if 次数 == 1:
			检(角色.dream_tier() == 1 and not 角色._dream_ignore_shield,
				"第 1 次攻击结束响应时应显示档位 1，但效果尚未生效")
		elif 次数 == 2:
			检(角色.dream_tier() == 2 and not 角色._dream_no_reattack,
				"第 2 次攻击结束响应时应显示档位 2，但效果尚未生效")
		elif 次数 == 3:
			检(角色.dream_tier() == 2, "第 3 次攻击结束响应时展示档仍应为 2")
		else:
			检(角色.dream_tier() == 3 and not 角色._dream_no_miss,
				"第 4 次攻击结束响应时应显示档位 3，但效果尚未生效")
		角色.p_action_end({"player": 1, "kind": "attack"})
		if 次数 == 1:
			检(角色._dream_ignore_shield, "第 1 次攻击行动后梦想剑应激活「无视圣盾」")
			检(not 角色._dream_no_reattack and not 角色._dream_no_miss,
				"第 1 次攻击行动后不应同时激活后两档")
			检(角色.dream_tier() == 1, "第 1 档 dream_tier 应为 1")
		elif 次数 == 2:
			检(角色._dream_no_reattack, "第 2 次攻击行动后梦想剑应激活「无法应战」")
			检(not 角色._dream_no_miss, "第 2 次攻击行动后不应已激活「强制命中」")
			检(角色.dream_tier() == 2, "第 2 档 dream_tier 应为 2")
		elif 次数 == 3:
			检(not 角色._dream_no_miss, "第 3 次攻击行动后不应有新档位")
			检(角色.dream_tier() == 2, "第 3 次攻击行动后 dream_tier 仍应为 2")
		else:
			检(角色._dream_no_miss, "第 4 次攻击行动后梦想剑应激活「强制命中」")
			检(角色.dream_tier() == 3, "第 4 档 dream_tier 应为 3")
	检(_播报次数(4503) == 3, "梦想剑第 1 / 2 / 4 档各应播报一次，实际 %d 次" % _播报次数(4503))
	检(int(玩家.to_proto(1).get("dream_tier", 0)) == 3,
		"快照应下发 dream_tier=3，供角色说明标绿")
	# 第 4 档：主动攻击强制命中 + 无视圣盾；应战反击不受影响
	var 梦想主动: Dictionary = _攻击上下文(非技击牌.id)
	角色.p_timeline_1(梦想主动)
	检(int(梦想主动.get("hit_rate", -1)) == GConst.HitRate.NoMiss,
		"梦想剑第 4 档应把主动攻击置为强制命中")
	检(not bool(梦想主动.get("check_shield", true)), "梦想剑第 1 档应让主动攻击无视圣盾")
	var 梦想应战: Dictionary = _攻击上下文(非技击牌.id, 2, false)
	角色.p_timeline_1(梦想应战)
	检(int(梦想应战.get("hit_rate", -1)) == GConst.HitRate.Normal,
		"梦想剑不应改应战反击的命中率")
	检(bool(梦想应战.get("check_shield", true)), "梦想剑不应改应战反击的圣盾检查")
	# 新回合清空；剑之魔女不在场时不触发
	角色.p_before_turn_begin({})
	检(not 角色._dream_ignore_shield and not 角色._dream_no_reattack and not 角色._dream_no_miss,
		"新回合应清空梦想剑档位")
	队友.role_id = 0
	玩家.reset_action_counts()
	玩家.record_action("attack", false)
	角色.p_action_end({"player": 1, "kind": "attack"})
	检(not 角色._dream_ignore_shield, "剑之魔女不在场时不应获得梦想剑")

	# ---- 4504 剑影*断念：支付 1 真宝石 → 弃 2 张 → 摸 1 张 → 额外攻击行动 ----
	_重置战斗()
	_挂剑之魔女()
	# 本用例只看 4504：把 10804 标成本回合已发动，避免它先用掉宝石并弹出自己的询问
	角色._used_剑残影 = true
	玩家.set_gem(1)
	玩家.hand_cards = [非魔牌表[0].id, 非魔牌表[1].id, 非魔牌表[2].id]
	# 牌库顶预置 1 张，避免 4504 摸牌时把刚弃的牌洗回牌库、导致弃牌堆被清空
	_设牌库顶([非魔牌表[5].id])
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"剑之魔女在场时攻击结束应询问【剑影*断念】")
	var 断念问: Dictionary = _取选项询问(1, 4504)
	检(not 断念问.is_empty(), "没有下发【剑影*断念】二选一询问")
	检((断念问.get("option_need_cards", []) as Array) == [2],
		"【剑影*断念】选项应要求选 2 张弃牌：%s" % str(断念问.get("option_need_cards", [])))
	检(玩家.gem == 1, "未确认弃牌前不应扣宝石，实际剩 %d" % 玩家.gem)
	_应答询问(1, 4504, [4504], [非魔牌表[0].id, 非魔牌表[1].id])
	检(引擎._await_id == -1, "【剑影*断念】应结算完")
	检(玩家.gem == 0, "选完弃牌按确定后才扣 1 真宝石，实际剩 %d" % 玩家.gem)
	检(_播报次数(4504) == 1, "【剑影*断念】发动应播报一次，实际 %d 次" % _播报次数(4504))
	检(_有额外行动(4504), "【剑影*断念】应额外 +1 攻击行动")
	检(引擎.deck.discard.has(非魔牌表[0].id) and 引擎.deck.discard.has(非魔牌表[1].id),
		"【剑影*断念】弃的 2 张牌应进弃牌堆")
	检(玩家.hand_cards.size() == 2, "弃 2 张再摸 1 张后手牌应为 2 张，实际 %d 张"
		% 玩家.hand_cards.size())

	# 剑之魔女不在场：不询问（同样先跳过 10804）
	_重置战斗()
	角色._used_剑残影 = true
	玩家.set_gem(1)
	玩家.hand_cards = [非魔牌表[0].id, 非魔牌表[1].id]
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == -1, "剑之魔女不在场时不应获得 / 发动【剑影*断念】")
	检(_取询问(1, 4504).is_empty(), "剑之魔女不在场时不应下发 4504 询问")

	# 只有水晶没有宝石：4504 的真宝石费用不能用【水晶】顶
	_重置战斗()
	_挂剑之魔女()
	角色._used_剑残影 = true
	玩家.set_crystal(2)
	玩家.hand_cards = [非魔牌表[0].id, 非魔牌表[1].id]
	发送记录.clear()
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == -1, "没有真宝石时不应询问【剑影*断念】")
	检(_取询问(1, 4504).is_empty(), "没有真宝石时不应下发 4504 询问")

	# 手牌不足 2 张：不询问
	_重置战斗()
	_挂剑之魔女()
	角色._used_剑残影 = true
	玩家.set_gem(1)
	玩家.hand_cards = [非魔牌表[0].id]
	发送记录.clear()
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == -1, "手牌不足 2 张时不应询问【剑影*断念】")
	检(_取询问(1, 4504).is_empty(), "手牌不足 2 张时不应下发 4504 询问")

	# 取消发动：不扣宝石、不弃牌、不给额外行动
	_重置战斗()
	_挂剑之魔女()
	角色._used_剑残影 = true
	玩家.set_gem(1)
	玩家.hand_cards = [非魔牌表[0].id, 非魔牌表[1].id]
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond, "应询问【剑影*断念】")
	_应答询问(1, 4504, [])
	检(引擎._await_id == -1, "取消【剑影*断念】应直接收尾")
	检(玩家.gem == 1, "取消【剑影*断念】不应扣宝石")
	检(玩家.hand_cards.size() == 2, "取消【剑影*断念】不应弃牌")
	检(_有额外行动(4504) == false, "取消【剑影*断念】不应给额外攻击行动")


# ============================================================
# 10804 / 4504 攻击结束二选一
# ============================================================
func _测攻击结束二选一() -> void:
	_重置战斗()
	_挂剑之魔女()
	玩家.set_crystal(1)
	玩家.set_gem(1)
	玩家.hand_cards = [非魔牌表[0].id, 非魔牌表[1].id]
	靶.hand_cards.clear()
	_驱动攻击结束({"card_id": 非技击牌.id, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"两项都可发动时应弹二选一")
	var 问: Dictionary = _取询问(1, 10804)
	检(not 问.is_empty(), "没有下发 10804 / 4504 的二选一询问")
	var 参数: Array = 问.get("args", [])
	检(参数.size() >= 6 and int(参数[3]) == 2,
		"应同时下发两个选项：%s" % str(参数))
	检(int(参数[4]) == 10804 and int(参数[5]) == 4504,
		"选项值应是 10804 / 4504：%s" % str(参数))
	检((问.get("option_skill_ids", []) as Array) == [10804, 4504],
		"两项都应带技能号供客户端悬停说明：%s" % str(问.get("option_skill_ids", [])))
	检((问.get("option_need_targets", []) as Array) == [1, 0],
		"剑残影项要求 1 名目标、4504 项不要求目标：%s" % str(问.get("option_need_targets", [])))
	检((问.get("option_need_cards", []) as Array) == [0, 2],
		"4504 项要求 2 张弃牌、剑残影项不要求：%s" % str(问.get("option_need_cards", [])))
	# 选项自带的目标白名单：聚合器把整条响应包成同一次询问，客户端只能靠它只点亮对手头像
	var 选项目标: Array = 问.get("option_targets", [])
	检(选项目标.size() == 2 and (选项目标[0] as Dictionary).get("ids", []) == [2, 4],
		"【剑残影】选项应带敌方目标白名单（1 号自己、3 号队友不能点）：%s" % str(选项目标))
	检((选项目标[1] as Dictionary).get("ids", []).is_empty(),
		"【剑影*断念】不选目标，白名单应为空：%s" % str(选项目标))
	# 两项需求都必须过协议：否则联机时客户端不知道选中后要放开目标还是弃牌
	var 二选一编码: PackedByteArray = ProtoCodec.encode_named("Command", 问)
	var 二选一解码: Dictionary = ProtoCodec.decode_named("Command", 二选一编码)
	检((二选一解码.get("option_need_targets", []) as Array) == [1, 0],
		"Command 协议应包含 option_need_targets：%s" % str(二选一解码.get("option_need_targets", [])))
	检((二选一解码.get("option_need_cards", []) as Array) == [0, 2],
		"Command 协议应包含 option_need_cards：%s" % str(二选一解码.get("option_need_cards", [])))
	检(bool(GConst.技能指示器.get(10804, {}).get("攻击结束二选一", false)),
		"10804 二选一应配「攻击结束二选一」")
	检(bool(GConst.技能指示器.get(4504, {}).get("攻击结束二选一", false)),
		"4504 二选一应配「攻击结束二选一」")
	# 点了自己 / 队友（非敌方）：驳回重选，不扣费、不消耗这一项
	发送记录.clear()
	_应答询问(1, 10804, [10804], [], [1])
	检(_有错误输入(), "选了非敌方目标应回 ErrorInput")
	检(引擎._await_id == 1 and not _取询问(1, 10804).is_empty(),
		"选了非敌方目标应驳回并重新询问【剑残影】")
	检(玩家.get_energy() == 2 and not _有额外行动(10804), "非法目标不应扣费 / 给额外行动")
	检(角色._used_剑残影 == false, "非法目标不应消耗回合限定")
	# 目标没有手牌：同一条回复里选 10804 + 目标即可结算，然后应继续问 4504
	_应答询问(1, 10804, [10804], [], [2])
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"10804 结算完应继续问 4504")
	检(_有额外行动(10804), "选 10804 应获得额外攻击行动")
	var 二问: Dictionary = _取询问(1, 4504)
	检(not 二问.is_empty(), "10804 用掉后应只剩 4504 询问")
	var 二问参数: Array = 二问.get("args", [])
	检(二问参数.size() >= 5 and int(二问参数[3]) == 1 and int(二问参数[4]) == 4504,
		"第二问应只剩 4504：%s" % str(二问参数))
	# 弃牌不足 2 张：驳回重选，不扣宝石、不消耗这一项
	发送记录.clear()
	_应答询问(1, 4504, [4504], [非魔牌表[0].id])
	检(_有错误输入(), "【剑影*断念】弃牌不足应回 ErrorInput")
	检(玩家.gem == 1, "弃牌不足不应扣宝石，实际剩 %d" % 玩家.gem)
	检(引擎._await_id == 1 and not _取询问(1, 4504).is_empty(),
		"弃牌不足应驳回并重新询问 4504")
	检(角色._used_剑影断念 == false, "弃牌不足不应消耗回合限定")
	_应答询问(1, 4504, [])
	检(引擎._await_id == -1, "取消剩余的 4504 应收尾")


# ============================================================
# 10803 剑守誓言：触发条件 / 10801 封锁 / 取消
# ============================================================
func _测剑守誓言条件() -> void:
	# 没有主动攻击命中、星杯也没增加：不触发
	_重置战斗()
	发送记录.clear()
	角色.p_after_turn_end({})
	检(_取询问(1, 10803).is_empty(), "没有触发条件时不应下发【剑守誓言】询问")

	# 主动攻击命中：回合结束后触发
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id))
	_设牌库顶([非魔牌表[0].id])
	角色.p_after_turn_end({})
	检(not _取询问(1, 10803).is_empty(), "主动攻击命中的回合结束后应询问【剑守誓言】")

	# 应战反击命中不算「主动攻击命中」
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id, 2, false))
	角色.p_after_turn_end({})
	检(_取询问(1, 10803).is_empty(), "应战反击命中不应触发【剑守誓言】")

	# 任意一方星杯数增加：回合结束后触发
	_重置战斗()
	角色.p_before_turn_begin({})
	引擎.team_grail[GConst.RED] += 1
	_设牌库顶([非魔牌表[0].id])
	角色.p_after_turn_end({})
	检(not _取询问(1, 10803).is_empty(), "任一方星杯数增加后应询问【剑守誓言】")

	# 10801：剑之魔女在场时无法发动
	_重置战斗()
	_挂剑之魔女()
	引擎.team_grail[GConst.BLUE] += 1
	_设牌库顶([非魔牌表[0].id])
	发送记录.clear()
	角色.p_after_turn_end({})
	检(_取询问(1, 10803).is_empty(), "剑之魔女在场时不应询问【剑守誓言】")
	检(引擎.deck.pile.size() == 1, "剑之魔女在场时不应动牌库")

	# 牌库为空：没有任何牌可弃置 / 加入手牌，不弹无用询问
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id))
	发送记录.clear()
	角色.p_after_turn_end({})
	检(_取询问(1, 10803).is_empty(), "牌库为空时不应下发【剑守誓言】询问")

	# 取消发动：牌库不动
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id))
	_设牌库顶([非魔牌表[0].id])
	var 上下文: Dictionary = {}
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "应询问【剑守誓言】")
	_应答([])
	检(角色.p_after_turn_end(上下文) == BattleRole.SUCCESS, "取消【剑守誓言】应直接收尾")
	检(引擎.deck.pile == [非魔牌表[0].id] and 引擎.deck.discard.is_empty(),
		"取消【剑守誓言】不应动牌库")


# ============================================================
# 10803 剑守誓言：X+1 弃置展示、选 1 张入手、有法术牌的额外回合 / 角色替换
# ============================================================
func _测剑守誓言结算() -> void:
	# ---- 无 45：X=2（双方各 1 星杯）→ 牌库顶 3 张，选第 2 张；
	#      这批牌无法术牌 → 不 +水晶、不额外回合、不替换角色 ----
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id))
	引擎.team_grail = [1, 1]
	var 三张: Array = [非魔牌表[0].id, 非魔牌表[1].id, 非魔牌表[2].id]
	_设牌库顶(三张)
	引擎.deck.discard.append(非魔牌表[3].id)
	玩家.set_crystal(0)
	发送记录.clear()
	var 上下文: Dictionary = {}
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "应询问【剑守誓言】")
	_应答([1])
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT,
		"发动后应先移除并展示牌库顶，再让玩家选 1 张")
	检(引擎.deck.pile.is_empty(), "X=2 时应移除 3 张，牌库应为空（实际 %s）" % str(引擎.deck.pile))
	检(_展示过(三张), "移除的牌应一次展示给全场：%s" % str(发送记录))
	var 展示消息: Dictionary = _展示消息(三张)
	检(not 展示消息.is_empty(), "应能查到整批展示消息")
	检(bool(展示消息.get("persist", false)),
		"整批展示应持久保留到选牌（不能 6.4 秒自动收起）")
	var 选择问: Dictionary = _取询问(1, 10803)
	检((选择问.get("notes", []) as Array).size() == 3, "应完整下发 3 张牌的选项")
	检((选择问.get("option_card_ids", []) as Array) == 三张,
		"选牌选项应逐项带 card_id，供客户端悬停摊卡面：%s" % str(选择问.get("option_card_ids", [])))
	检(not bool(选择问.get("can_cancel", true)),
		"剑守誓言选牌不能取消，只能选择或超时自动选")
	# 光服务端命令里有还不够：必须真的能过协议编码，否则联机时客户端收到的是空数组
	var 选择命令编码: PackedByteArray = ProtoCodec.encode_named("Command", 选择问)
	var 选择命令解码: Dictionary = ProtoCodec.decode_named("Command", 选择命令编码)
	检((选择命令解码.get("option_card_ids", []) as Array) == 三张,
		"Command 协议应包含 option_card_ids，客户端才能悬停摊卡面：%s"
		% str(选择命令解码.get("option_card_ids", [])))
	# 持久展示标记也必须过协议，否则联机时客户端仍会 6.4 秒自动收起
	var 展示卡编码: PackedByteArray = ProtoCodec.encode(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "card_ids": [三张[0], 三张[1]], "persist": true,
	})
	var 展示卡解码: Dictionary = ProtoCodec.decode(GConst.Msg.Card, 展示卡编码)
	检(bool(展示卡解码.get("persist", false)),
		"Card 协议应包含 persist，展示才能一直留到选牌")
	检(_播报次数(10803) == 1, "【剑守誓言】发动应播报一次，实际 %d 次" % _播报次数(10803))
	_应答([2])
	检(角色.p_after_turn_end(上下文) == BattleRole.SUCCESS, "选好牌后【剑守誓言】应结算完")
	检(玩家.hand_cards.has(三张[1]), "选中的第 2 张应加入手牌")
	# 选中的牌不再二次展示：整批展示一次 + 一条 Pick 飞向角色头像
	var 选中牌: int = int(三张[1])
	var 展示次数: int = 0
	var 获得日志: String = ""
	for r: Dictionary in 发送记录:
		var 数据: Dictionary = r.get("data", {})
		if int(r.get("msg", 0)) == GConst.Msg.Card \
				and int(数据.get("type", -1)) == GConst.CardMsgType.Show \
				and (数据.get("card_ids", []) as Array).has(选中牌):
			展示次数 += 1
		if int(r.get("msg", 0)) == GConst.Msg.Gossip:
			var 文案: String = str(数据.get("txt", ""))
			if 文案.contains("获得") and 文案.contains(非魔牌表[1].card_name):
				获得日志 = 文案
	检(展示次数 == 1, "整批展示一次即可；选中的牌不再二次展示，实际 %d 次" % 展示次数)
	var 选走消息: Dictionary = _选走消息(选中牌)
	检(not 选走消息.is_empty(), "选中后应发 Pick，让牌从展示位飞向角色头像")
	检(int(选走消息.get("src_id", -1)) == 1 and int(选走消息.get("dst_id", -1)) == 1,
		"Pick 的起点/终点都应是选牌者（1 号）")
	检(not 获得日志.is_empty(), "战斗日志应写一条「谁 获得【什么】」")
	检(获得日志.contains("剑之子") and 获得日志.contains(非魔牌表[1].card_name),
		"获得日志应包含角色与牌名：%s" % 获得日志)
	检(引擎.deck.discard.has(三张[0]) and 引擎.deck.discard.has(三张[2]),
		"其余牌应进弃牌堆")
	检(引擎.deck.discard.has(非魔牌表[3].id), "牌库不足不应把原有弃牌洗回 / 清掉")
	检(_有额外行动(10803) == false, "没有法术牌时不应给额外回合")
	检(引擎.额外回合玩家 == -1, "没有法术牌时不应安排额外回合")
	检(玩家.role_id == 108, "没有法术牌时不应替换角色")
	检(玩家.crystal == 0, "没有法术牌时不应 +2 水晶")

	# ---- 超时 / 空回复：自动选第 1 张（不能取消） ----
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id))
	引擎.team_grail = [1, 1]
	_设牌库顶(三张)
	上下文 = {}
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "应询问【剑守誓言】")
	_应答([1])
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "应让玩家选 1 张")
	_应答([])
	检(角色.p_after_turn_end(上下文) == BattleRole.SUCCESS, "超时/空回复应自动选第 1 张并收尾")
	检(玩家.hand_cards.has(三张[0]), "超时/空回复应自动把第 1 张加入手牌")
	检(not 玩家.hand_cards.has(三张[1]) and not 玩家.hand_cards.has(三张[2]),
		"其余两张不应进手牌")
	检(引擎.deck.discard.has(三张[1]) and 引擎.deck.discard.has(三张[2]),
		"其余两张应进弃牌堆")
	检(not _选走消息(三张[0]).is_empty(), "自动选择也应发 Pick，让牌飞向头像")

	# ---- 牌库不足：X+1=4，实际只有 2 张；不洗回，按实际张数结算 ----
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id))
	引擎.team_grail = [1, 2]
	_设牌库顶([非魔牌表[0].id, 非魔牌表[1].id])
	上下文 = {}
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "应询问【剑守誓言】")
	_应答([1])
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "牌库不足也应先移除展示")
	检(引擎.deck.pile.is_empty(), "牌库不足时应只取实际张数")
	检((_取询问(1, 10803).get("notes", []) as Array).size() == 2,
		"应按实际取到的 2 张下发选项")
	_应答([1])
	检(角色.p_after_turn_end(上下文) == BattleRole.SUCCESS, "牌库不足时也应正常结算")
	检(玩家.hand_cards.has(非魔牌表[0].id), "选中的牌应加入手牌")


# ============================================================
# 10803：有法术牌 → +2 水晶、额外回合 +1、替换为风之剑圣（放最后：会解绑旧角色）
# ============================================================
func _测剑守誓言替换角色() -> void:
	_重置战斗()
	角色.p_timeline_2_hit(_攻击上下文(非技击牌.id))
	引擎.team_grail = [1, 2]
	# 第 2 张放法术牌；选第 1 张（非法术），弃牌中仍留有法术牌 → 触发额外回合 / 替换。
	# 实现按「这次从牌库顶弃置的整批牌」判定（含被选入手的 1 张）；本用例两种口径下都成立。
	var 四张: Array = [非魔牌表[0].id, 魔法牌.id, 非魔牌表[1].id, 非魔牌表[2].id]
	_设牌库顶(四张)
	玩家.set_crystal(0)
	var 上下文: Dictionary = {}
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "应询问【剑守誓言】")
	_应答([1])
	检(角色.p_after_turn_end(上下文) == BattleRole.WAIT, "应移除牌库顶 4 张并让玩家选 1 张")
	检(引擎.deck.pile.is_empty(), "X=3 时应移除 4 张（双方星杯和 3 + 1）")
	_应答([1])
	检(角色.p_after_turn_end(上下文) == BattleRole.SUCCESS, "选牌后【剑守誓言】应结算完")
	检(玩家.hand_cards.has(四张[0]), "选中的非法术牌应加入手牌")
	检(引擎.deck.discard.has(魔法牌.id), "没被选中的法术牌应进弃牌堆")
	检(玩家.crystal == 2, "有法术牌应 +2 水晶，实际 %d" % 玩家.crystal)
	检(引擎.额外回合玩家 == 1, "有法术牌应安排 1 个自己的额外回合")
	检(引擎.额外回合攻击加伤 == 1, "额外回合的攻击伤害应 +1")
	检(引擎.额外回合来源 == 10803, "额外回合来源应记为 10803")
	检(玩家.role_id == 1, "有法术牌应永久替换为风之剑圣（角色号 1）")
	检(Data.role_name(玩家.role_id) == "风之剑圣", "替换后的角色名应是「风之剑圣」")
	检(玩家.role != null and 玩家.role.player == 玩家 and 玩家.role.engine == 引擎,
		"替换后的新角色应重新绑定到玩家")
	检(角色.player == null and 角色.engine == null, "替换后旧角色应解绑，不再收到钩子")
	检(玩家.role.available_skills().is_empty(), "风之剑圣没有技能栏主动技，available_skills 应为空")
	# 额外回合真的能开始：正常走一次回合结束，进入 1 号的额外回合
	引擎._states.clear()
	引擎._清空等待()
	引擎.current_id = 1
	引擎.phase = BattleEngine.Phase.Playing
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎.当前额外回合玩家 == 1 and 引擎.是否额外回合(),
		"替换后的额外回合应正常开始（当前 %s）" % str(引擎.当前额外回合玩家))
	检(引擎.额外回合加伤(1) == 1, "额外回合里 1 号攻击应 +1")
	检(引擎.攻击基础伤害(1) == 3, "额外回合的攻击基础伤害应为 3，实际 %d"
		% 引擎.攻击基础伤害(1))


# ============================================================
# 角色说明的动态部分：剑之魔女在场 / 不在场
# ============================================================
func _测剑之子说明书() -> void:
	var 原文: String = Data.role_skill_info(108)
	检(原文.contains("倾慕") and 原文.contains("剑守誓言"),
		"108 的角色说明应包含倾慕 / 剑守誓言")
	var 在场: String = 角色技能提示.剑之子对局说明(原文, true)
	var 不在场: String = 角色技能提示.剑之子对局说明(原文, false)
	# 剑之魔女在场：剑守誓言失效（每行标记用于置灰）；4503/4504 正常
	检(在场.contains(角色技能提示.失效行标记 + "剑守誓言"),
		"剑守誓言应带每行失效标记（用于置灰）")
	检(在场.contains("剑影*断念") and 在场.contains("梦想剑"),
		"剑之魔女在场时应追加获得的技能说明")
	检(not 在场.contains(角色技能提示.失效行标记 + "剑影*断念")
		and not 在场.contains(角色技能提示.失效行标记 + "梦想剑"),
		"剑之魔女在场时追加的借用技不应置灰")
	# 剑之魔女不在场：剑守誓言正常；4503/4504 仍追加但失效
	检(not 不在场.contains(角色技能提示.失效行标记 + "剑守誓言"),
		"剑之魔女不在场时【剑守誓言】不应置灰")
	检(不在场.contains("【被动】" + 角色技能提示.失效行标记 + "梦想剑")
		and 不在场.contains("【响应】" + 角色技能提示.失效行标记 + "剑影*断念"),
		"剑之魔女不在场时追加的借用技应带失效标记：%s" % 不在场)
	# 按技能表「大类」追加：4503 梦想剑（普通）在普通技底部；4504 剑影*断念（必杀技）在必杀技底部
	var 普通位置: int = 在场.find("普通技")
	var 必杀位置: int = 在场.find("必杀技")
	var 梦想位置: int = 在场.find("【被动】梦想剑")
	var 剑影位置: int = 在场.find("【响应】剑影*断念")
	检(普通位置 >= 0 and 梦想位置 > 普通位置 and 梦想位置 < 必杀位置,
		"梦想剑应追加在普通技底部：%d / %d / %d" % [普通位置, 梦想位置, 必杀位置])
	检(剑影位置 > 必杀位置, "剑影*断念应追加在必杀技底部：%d / %d" % [必杀位置, 剑影位置])
	检(梦想位置 > 在场.find("【响应】剑守誓言") and 剑影位置 > 在场.find("【响应】剑残影"),
		"借用技不能在倾慕下面，应分别在普通技 / 必杀技最后")
	# 角色说明里补「独有技」分段，放入风之剑圣的 101 / 102
	# （与卡面标绿、测试指令 2 读同一张表：GConst.角色借用独有技，见 追加借用独有技）
	var 在场完整: String = 角色技能提示.追加借用独有技(在场, 108)
	var 不在场完整: String = 角色技能提示.追加借用独有技(不在场, 108)
	var 普通位置2: int = 在场完整.find("普通技")
	var 必杀位置2: int = 在场完整.find("必杀技")
	var 独有位置: int = 在场完整.find("\n独有技\n")
	var 疾风位置: int = 在场完整.find(角色技能提示.失效行标记 + "疾风技")
	var 烈风位置: int = 在场完整.find(角色技能提示.失效行标记 + "烈风技")
	检(独有位置 > 普通位置2 and 独有位置 < 必杀位置2,
		"独有技分段应在普通技之后、必杀技之前：%d / %d / %d" % [普通位置2, 独有位置, 必杀位置2])
	检(疾风位置 > 独有位置 and 疾风位置 < 必杀位置2 and 烈风位置 > 疾风位置,
		"101 / 102 应追加在独有技分段底部：%d / %d / %d" % [独有位置, 疾风位置, 烈风位置])
	检(在场完整.contains(角色技能提示.失效行标记 + "疾风技")
		and 在场完整.contains(角色技能提示.失效行标记 + "烈风技"),
		"剑之子继承的剑圣独有技应置灰")
	检(不在场完整.contains(角色技能提示.失效行标记 + "疾风技")
		and 不在场完整.contains(角色技能提示.失效行标记 + "烈风技"),
		"剑之魔女是否在场都不影响继承独有技的置灰")
	# 置灰排版：失效行外层半透明白（保留类型色、整体变淡）
	var 在场色: String = 角色技能提示.上色(在场, 18, 24, true)
	检(在场色.contains("[color=#FFFFFF8C]"), "失效技能应加半透明白做置灰（保留原色）")
	var 置灰位: int = 在场色.find("[color=#FFFFFF8C]")
	var 失效剑守位: int = 在场色.find(角色技能提示.失效行标记 + "剑守誓言")
	检(置灰位 >= 0 and 失效剑守位 > 置灰位,
		"置灰颜色应包住失效的剑守誓言：%d / %d" % [置灰位, 失效剑守位])
	# 梦想剑按档位逐段标绿：第 1 段 / 第 2 段 / 第 3 段
	var 句1: String = "[color=#A9FF00]回合内你的主动攻击无视【圣盾】[/color]"
	var 句2: String = "[color=#A9FF00]回合内你的主动攻击对方无法应战[/color]"
	var 句3: String = "[color=#A9FF00]回合内你的主动攻击强制命中[/color]"
	var 绿1: String = 角色技能提示.梦想剑标绿(Data.role_skill_info(45), 1)
	检(绿1.contains(句1) and not 绿1.contains(句2) and not 绿1.contains(句3),
		"档位 1 只应标绿「无视圣盾」")
	var 绿2: String = 角色技能提示.梦想剑标绿(Data.role_skill_info(45), 2)
	检(绿2.contains(句1) and 绿2.contains(句2) and not 绿2.contains(句3),
		"档位 2 应标绿前两段")
	var 绿3: String = 角色技能提示.梦想剑标绿(Data.role_skill_info(45), 3)
	检(绿3.contains(句1) and 绿3.contains(句2) and 绿3.contains(句3),
		"档位 3 应标绿三段")
	检(not 角色技能提示.梦想剑标绿(Data.role_skill_info(45), 0).contains(句1),
		"档位 0 不应标绿")
	var 绿108: String = 角色技能提示.梦想剑标绿(在场, 2)
	检(绿108.contains(句1) and 绿108.contains(句2) and not 绿108.contains(句3),
		"剑之子档位 2 应标绿前两段")
	# 用客户端快照里的 dream_tier 驱动 45 / 108 的悬停说明
	var 旧列表: Array[GPlayer] = Data.player_list.duplicate()
	var 假45: GPlayer = GPlayer.new()
	假45.role_id = 45
	假45.dream_tier = 1
	var 假108: GPlayer = GPlayer.new()
	假108.role_id = 108
	假108.dream_tier = 1
	Data.player_list = [假45, 假108]
	检(角色技能提示.悬浮提示(45, 1.0, true).contains(句1),
		"剑之魔女档位 1 时应标绿第一段")
	检(角色技能提示.悬浮提示(108, 1.0, true).contains(句1),
		"剑之子档位 1 时应标绿第一段")
	假108.dream_tier = 2
	检(角色技能提示.悬浮提示(108, 1.0, true).contains(句2),
		"剑之子档位 2 时应标绿第二段")
	假108.dream_tier = 3
	检(角色技能提示.悬浮提示(108, 1.0, true).contains(句3),
		"剑之子档位 3 时应标绿第三段")
	# 剑之魔女不在场：108 的梦想剑是置灰借用技，不应标绿
	Data.player_list = [假108]
	检(not 角色技能提示.悬浮提示(108, 1.0, true).contains(句1),
		"剑之魔女不在场时剑之子的梦想剑不应标绿")
	Data.player_list = 旧列表
	# 协议层必须真的带上 dream_tier；否则服务端有档位、客户端永远收不到
	var 编码: PackedByteArray = ProtoCodec.encode_named("SinglePlayerInfo", {"id": 1, "dream_tier": 2})
	var 解码: Dictionary = ProtoCodec.decode_named("SinglePlayerInfo", 编码)
	检(int(解码.get("dream_tier", -1)) == 2,
		"SinglePlayerInfo 协议应包含 dream_tier")

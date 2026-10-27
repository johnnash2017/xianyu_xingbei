extends 自检用例
## F5-B：狂战士（2）独有技 helper（201 血影狂刀 / 202 血腥咆哮）自检。
## 覆盖：数据与牌载技能、直接转发（询问 / 加伤 / 取消 / 不满足条件）、
## 伤害与命中效果覆盖点、dummy 借用角色走完整攻击流程的一次结算。

const 技能脚本 = preload("res://scripts/battle/skills/skill_berserker.gd")


## dummy 借用角色：只把 p_timeline_1 转给 helper（97 萝莉番长以后也这么接）
class 借用角色:
	extends BattleRole

	var 借用技能: RefCounted = null

	func p_timeline_1(ctx: Dictionary) -> int:
		if 借用技能 == null:
			return SUCCESS
		return int(借用技能.call("响应攻击", ctx))


func _init() -> void:
	名称 = "F5狂战士独有技"


func _找带技能攻击牌(技能号: int) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if c.is_attack() and c.has_skill_id(技能号):
			return c
	return null


func _建引擎() -> BattleEngine:
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "借用者")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.start_with_roles({1: 0, 2: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	return 引擎


## 给 1 号玩家挂上 dummy 借用角色，返回它的 helper
func _挂借用角色(引擎: BattleEngine) -> Variant:
	var 我: BattlePlayer = 引擎.p(1)
	var 借用: 借用角色 = 借用角色.new()
	借用.setup(我, 引擎)
	我.role = 借用
	var 技能: Variant = 技能脚本.new(借用)
	借用.借用技能 = 技能
	return 技能


func _取询问(引擎: BattleEngine, pid: int, 技能号: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 技能号:
			return r
	return {}


func _攻击伤害(卡: GCard) -> Dictionary:
	return {
		"src": 1, "dst": 2, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
		"card_id": 卡.id, "is_active": true,
	}


func _攻击上下文(卡: GCard, 伤害: Dictionary) -> Dictionary:
	return {
		"src": 1, "dst": 2, "is_active": true, "card_id": 卡.id,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true,
		"harm": 伤害,
	}


func _发牌(玩家: BattlePlayer, 卡号: Array) -> void:
	玩家.hand_cards.clear()
	for c: Variant in 卡号:
		玩家.hand_cards.append(int(c))


func 跑() -> void:
	await 等帧(1)
	# ---- 数据 ----
	检(GConst.skill_name(201) == "血影狂刀", "201 不是【血影狂刀】")
	检(GConst.skill_name(202) == "血腥咆哮", "202 不是【血腥咆哮】")
	var 血影卡: GCard = _找带技能攻击牌(201)
	var 咆哮卡: GCard = _找带技能攻击牌(202)
	检(血影卡 != null, "卡库找不到带【血影狂刀】的攻击牌")
	检(咆哮卡 != null, "卡库找不到带【血腥咆哮】的攻击牌")
	检(Data.role_skills(2).has(201) and Data.role_skills(2).has(202), "狂战士技能表应引用 201 / 202")
	检(Data.role_skills(97).has(9702) and Data.role_skills(97).has(9703),
		"萝莉番长技能表应有 9702 / 9703（借用目标）")
	if 血影卡 == null or 咆哮卡 == null:
		return

	# ---- 直接转发：201 询问 → 加伤 ----
	var 引擎: BattleEngine = _建引擎()
	var 技能: Variant = _挂借用角色(引擎)
	var 靶: BattlePlayer = 引擎.p(2)
	_发牌(靶, [血影卡.id, 咆哮卡.id])
	靶.cross_num = 0
	var 伤害: Dictionary = _攻击伤害(血影卡)
	var ctx: Dictionary = _攻击上下文(血影卡, 伤害)
	检(bool(技能.call("可发动血影狂刀", ctx)), "目标手牌 2 张时应能发动【血影狂刀】")
	检(int(技能.call("响应攻击", ctx)) == BattleRole.WAIT, "【血影狂刀】应先询问发动者")
	var 问: Dictionary = _取询问(引擎, 1, 201)
	检(not 问.is_empty(), "没有向发动者下发【血影狂刀】询问")
	检(int(问.get("preview_base", 0)) == BattleEngine.ATTACK_BASE_POINT,
		"【血影狂刀】询问应下发本次攻击原伤害作为头像预览基准：%s" % str(问))
	检((问.get("dst_ids", []) as Array).has(2), "【血影狂刀】询问应把本次攻击目标作为提示目标")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(int(技能.call("响应攻击", ctx)) == BattleRole.SUCCESS, "确认后【血影狂刀】应结算完")
	检(int(伤害["point"]) == BattleEngine.ATTACK_BASE_POINT + 2, "目标手牌 2 张时【血影狂刀】应额外 +2")
	检(int(技能.call("当前进度")) == 0, "结算完进度应清回未开始")

	# 目标手牌 3 张 → +1
	_发牌(靶, [血影卡.id, 咆哮卡.id, 血影卡.id])
	技能.call("重置")
	var 伤害3: Dictionary = _攻击伤害(血影卡)
	var ctx3: Dictionary = _攻击上下文(血影卡, 伤害3)
	检(int(技能.call("响应攻击", ctx3)) == BattleRole.WAIT, "目标手牌 3 张时也应询问【血影狂刀】")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	技能.call("响应攻击", ctx3)
	检(int(伤害3["point"]) == BattleEngine.ATTACK_BASE_POINT + 1, "目标手牌 3 张时【血影狂刀】应额外 +1")

	# 取消发动：不加伤
	_发牌(靶, [血影卡.id, 咆哮卡.id])
	技能.call("重置")
	var 拒伤: Dictionary = _攻击伤害(血影卡)
	var 拒ctx: Dictionary = _攻击上下文(血影卡, 拒伤)
	检(int(技能.call("响应攻击", 拒ctx)) == BattleRole.WAIT, "手牌 2 张时应询问【血影狂刀】")
	引擎._reply = {"args": [0], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(int(技能.call("响应攻击", 拒ctx)) == BattleRole.SUCCESS, "取消发动后应直接跳过")
	检(int(拒伤["point"]) == BattleEngine.ATTACK_BASE_POINT, "取消发动不应加伤")

	# 不满足条件：目标手牌 4 张 / 非主动攻击 / 牌不带技能
	_发牌(靶, [血影卡.id, 血影卡.id, 咆哮卡.id, 咆哮卡.id])
	技能.call("重置")
	var 四张ctx: Dictionary = _攻击上下文(血影卡, _攻击伤害(血影卡))
	检(not bool(技能.call("可发动血影狂刀", 四张ctx)), "目标手牌 4 张时不应能发动【血影狂刀】")
	检(int(技能.call("响应攻击", 四张ctx)) == BattleRole.SUCCESS, "不满足条件时【血影狂刀】不应询问")
	# 非主动攻击（应战反击）：即使牌 / 手牌都满足也不发动
	_发牌(靶, [血影卡.id, 咆哮卡.id])
	var 应战ctx: Dictionary = _攻击上下文(血影卡, _攻击伤害(血影卡))
	应战ctx["is_active"] = false
	检(not bool(技能.call("可发动血影狂刀", 应战ctx)), "应战反击时【血影狂刀】也应为不可发动")
	检(int(技能.call("响应攻击", 应战ctx)) == BattleRole.SUCCESS, "应战反击（is_active=false）不应触发独有技")
	var 别的牌ctx: Dictionary = _攻击上下文(咆哮卡, _攻击伤害(咆哮卡))
	检(not bool(技能.call("可发动血影狂刀", 别的牌ctx)), "不带【血影狂刀】的攻击牌不应能发动")

	# ---- 202 强制命中 ----
	_发牌(靶, [血影卡.id, 咆哮卡.id])
	靶.cross_num = 2
	技能.call("重置")
	var 咆哮伤害: Dictionary = _攻击伤害(咆哮卡)
	var 咆哮ctx: Dictionary = _攻击上下文(咆哮卡, 咆哮伤害)
	检(bool(技能.call("可发动血腥咆哮", 咆哮ctx)), "目标【治疗】为 2 时应能发动【血腥咆哮】")
	检(int(技能.call("响应攻击", 咆哮ctx)) == BattleRole.WAIT, "【血腥咆哮】应先询问发动者")
	检(int(咆哮ctx["hit_rate"]) == GConst.HitRate.Normal, "发动前不应提前改命中率")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(int(技能.call("响应攻击", 咆哮ctx)) == BattleRole.SUCCESS, "确认后【血腥咆哮】应结算完")
	检(int(咆哮ctx["hit_rate"]) == GConst.HitRate.NoMiss, "【血腥咆哮】应把本次攻击改为强制命中")

	# 目标【治疗】不为 2：不询问、不变命中率
	靶.cross_num = 1
	技能.call("重置")
	var 一治疗ctx: Dictionary = _攻击上下文(咆哮卡, _攻击伤害(咆哮卡))
	检(not bool(技能.call("可发动血腥咆哮", 一治疗ctx)), "目标【治疗】不是 2 时不应能发动【血腥咆哮】")
	检(int(技能.call("响应攻击", 一治疗ctx)) == BattleRole.SUCCESS, "不满足条件时【血腥咆哮】不应询问")
	检(int(一治疗ctx["hit_rate"]) == GConst.HitRate.Normal, "不满足条件时不应改命中率")

	# ---- 覆盖点（9702 / 9703 这类改写） ----
	技能.血影狂刀加伤 = func(_dst: BattlePlayer) -> int:
		return 5
	_发牌(靶, [血影卡.id, 咆哮卡.id])
	技能.call("重置")
	var 覆盖伤害: Dictionary = _攻击伤害(血影卡)
	var 覆盖ctx: Dictionary = _攻击上下文(血影卡, 覆盖伤害)
	检(int(技能.call("响应攻击", 覆盖ctx)) == BattleRole.WAIT, "覆盖加伤后仍应先询问【血影狂刀】")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	技能.call("响应攻击", 覆盖ctx)
	检(int(覆盖伤害["point"]) == BattleEngine.ATTACK_BASE_POINT + 5, "【血影狂刀】加伤覆盖应生效")
	技能.血影狂刀加伤 = Callable()

	# 9703 口径：目标「拥有治疗」即可发动，效果改成无法用【暗灭】应战 / 无法用【圣光】抵挡
	技能.血腥咆哮条件 = func(dst: BattlePlayer) -> bool:
		return dst.cross_num > 0
	技能.血腥咆哮效果 = func(效果ctx: Dictionary, _dst: BattlePlayer) -> int:
		效果ctx["hit_rate"] = GConst.HitRate.NoReattack
		效果ctx["can_light"] = false
		return BattleRole.SUCCESS
	靶.cross_num = 1
	技能.call("重置")
	var 改写ctx: Dictionary = _攻击上下文(咆哮卡, _攻击伤害(咆哮卡))
	检(bool(技能.call("可发动血腥咆哮", 改写ctx)), "覆盖条件后目标有 1 点治疗也应能发动【血腥咆哮】")
	检(int(技能.call("响应攻击", 改写ctx)) == BattleRole.WAIT, "覆盖条件后仍应先询问发动者")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(int(技能.call("响应攻击", 改写ctx)) == BattleRole.SUCCESS, "覆盖效果后【血腥咆哮】应结算完")
	检(int(改写ctx["hit_rate"]) == GConst.HitRate.NoReattack, "覆盖效果应能改命中 / 应战限制")
	检(not bool(改写ctx["can_light"]), "覆盖效果应能关闭【圣光】抵挡")
	技能.血腥咆哮条件 = Callable()
	技能.血腥咆哮效果 = Callable()

	# ---- 借用方换成自己的技能行（97 萝莉番长两颗都走 9702） ----
	var 借引擎: BattleEngine = _建引擎()
	var 借技能: Variant = _挂借用角色(借引擎)
	var 借靶: BattlePlayer = 借引擎.p(2)
	var 借用播报: Array = []
	借引擎.send_cb = func(_pid: int, msg: int, data: Dictionary) -> void:
		if msg == GConst.Msg.Skill:
			借用播报.append(int(data.get("skill_id", 0)))
	借技能.技能号血影狂刀 = 9702
	借技能.技能号血腥咆哮 = 9702
	_发牌(借靶, [血影卡.id, 咆哮卡.id])
	var 借ctx: Dictionary = _攻击上下文(血影卡, _攻击伤害(血影卡))
	检(int(借技能.call("响应攻击", 借ctx)) == BattleRole.WAIT, "借用方【血影狂刀】应先询问")
	检(not _取询问(借引擎, 1, 9702).is_empty(), "借用方询问应按自己的技能行 9702 下发")
	借引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	借引擎._has_reply = true
	借技能.call("响应攻击", 借ctx)
	检(借用播报.has(9702), "借用方技能播报应按 9702 下发：%s" % str(借用播报))
	检(not 借用播报.has(201), "借用方不应再播狂战士的 201")
	借靶.cross_num = 2
	var 借咆哮ctx: Dictionary = _攻击上下文(咆哮卡, _攻击伤害(咆哮卡))
	检(int(借技能.call("响应攻击", 借咆哮ctx)) == BattleRole.WAIT, "借用方【血腥咆哮】应先询问")
	检(not _取询问(借引擎, 1, 9702).is_empty(), "借用方【血腥咆哮】询问也应按 9702 下发")
	借引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	借引擎._has_reply = true
	借技能.call("响应攻击", 借咆哮ctx)
	检(int(借咆哮ctx["hit_rate"]) == GConst.HitRate.NoMiss, "借用方【血腥咆哮】应把本次攻击改为强制命中")

	# ---- dummy 借用角色走一次完整攻击结算 ----
	var 引擎2: BattleEngine = _建引擎()
	var 技能2: Variant = _挂借用角色(引擎2)
	var 消息: Array = []
	引擎2.send_cb = func(_pid: int, msg: int, data: Dictionary) -> void:
		消息.append({"msg": msg, "data": data})
	var 攻: BattlePlayer = 引擎2.p(1)
	var 靶2: BattlePlayer = 引擎2.p(2)
	_发牌(攻, [血影卡.id])
	_发牌(靶2, [血影卡.id, 咆哮卡.id])
	靶2.cross_num = 0
	引擎2.current_id = 1
	引擎2._do_attack(攻, {"card_ids": [血影卡.id], "dst_ids": [2]})
	引擎2.run()
	检(引擎2._await_id == 1, "完整攻击里应在等借用者决定是否发动【血影狂刀】")
	var 攻击问: Dictionary = _取询问(引擎2, 1, 201)
	检(not 攻击问.is_empty(), "完整攻击里应下发【血影狂刀】询问")
	引擎2._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎2._has_reply = true
	引擎2.run()
	检(引擎2._await_id == 2, "加伤后应轮到目标决定应战 / 放弃")
	引擎2._reply = {"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": []}
	引擎2._has_reply = true
	引擎2.run()
	var 命中伤害: int = -1
	var 有技能播报: bool = false
	for 条: Dictionary in 消息:
		var 数据: Dictionary = 条["data"]
		if int(条["msg"]) == GConst.Msg.Hurt and int(数据.get("dst_id", -1)) == 2:
			命中伤害 = int(数据.get("hurt", -1))
		if int(条["msg"]) == GConst.Msg.Skill and int(数据.get("skill_id", 0)) == 201:
			有技能播报 = true
	检(有技能播报, "【血影狂刀】发动应播技能通知")
	检(命中伤害 == BattleEngine.ATTACK_BASE_POINT + 2,
		"完整攻击结算应造成 %d 点伤害，实际 %d" % [BattleEngine.ATTACK_BASE_POINT + 2, 命中伤害])
	检(靶2.hand_cards.size() == 6,
		"目标 2 张手牌受 4 点伤害后应摸到 6 张，实际 %d" % 靶2.hand_cards.size())
	检(int(技能2.call("当前进度")) == 0, "完整攻击结算后 helper 进度应清回未开始")

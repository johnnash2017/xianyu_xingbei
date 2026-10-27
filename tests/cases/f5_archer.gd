extends 自检用例
## F5-A：神箭手（弓之女神，角色 3）独有技 helper ——【301 精准射击】/【302 闪光陷阱】。
##
## 用一个 dummy「借用角色」把 helper 接进 BattleRole 的四个入口（模拟 75 EX魔弓【弓神候补】），
## 验证：
##   1. 302 的发动牌 / 目标校验、技能栏置灰、完整结算（弃牌 → 2 点法术伤害 → 目标摸 2 张）；
##   2. 301 只在带 301 的攻击牌上询问，发动后强制命中且本次伤害 -1，并走完一次完整攻击结算；
##   3. 301 不发动、攻击牌不带 301、同一张牌处理完再入时都不重复询问、不改伤害。

const 神箭手技能脚本: GDScript = preload("res://scripts/battle/skills/skill_archer.gd")


## dummy 借用角色：只把 helper 转发到技能栏 / 法术技能 / 攻击宣告三个入口，
## 角色本身没有其它技能，便于把 helper 的行为和原角色 role_gongnv.gd 隔离开测。
class 借用弓女 extends BattleRole:
	const 弓女技能脚本: GDScript = preload("res://scripts/battle/skills/skill_archer.gd")

	var 神箭手 = null

	func _init() -> void:
		神箭手 = 弓女技能脚本.new(self)

	func available_skills() -> Array:
		return 神箭手.可用技能()

	func v_magic_skill(action: Dictionary) -> int:
		return 神箭手.v_magic_skill(action)

	func p_magic_skill(action: Dictionary) -> int:
		return 神箭手.p_magic_skill(action)

	func p_timeline_1(ctx: Dictionary) -> int:
		return 神箭手.应答攻击(ctx)


var 引擎: BattleEngine
var 发送记录: Array = []


func _init() -> void:
	名称 = "神箭手独有技helper"


## 在发送记录里找「发给 pid、询问号为 询问号」的一条技能 / 应答询问命令
func _找询问(pid: int, 询问号: int) -> Dictionary:
	for r: Dictionary in 发送记录:
		if int(r.get("pid", 0)) != pid or int(r.get("msg", 0)) != GConst.Msg.CmdReq:
			continue
		var 数据: Dictionary = r.get("data", {})
		for cmd: Dictionary in 数据.get("commands", []):
			if int(cmd.get("respond_id", 0)) == 询问号:
				return cmd
	return {}


## 在发送记录里找一条满足条件（条件 收到 data）的广播消息
func _找消息(消息类型: int, 条件: Callable) -> Dictionary:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != 消息类型:
			continue
		var 数据: Dictionary = r.get("data", {})
		if bool(条件.call(数据)):
			return 数据
	return {}


func 跑() -> void:
	await 等帧(2)

	# ---- 卡库前提：至少 3 张不同的 301 牌、1 张 302 牌、1 张与神箭手无关的牌 ----
	var 精准牌: Array[GCard] = []
	var 陷阱牌: GCard = null
	var 其他牌: GCard = null
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if c.has_skill_id(301) and 精准牌.size() < 3:
			精准牌.append(c)
		if c.has_skill_id(302) and 陷阱牌 == null:
			陷阱牌 = c
		if 其他牌 == null and not c.has_skill_id(301) and not c.has_skill_id(302):
			其他牌 = c
	检(精准牌.size() >= 3, "卡库里的 301 攻击牌不足 3 张（实际 %d），用例前提不成立" % 精准牌.size())
	检(陷阱牌 != null, "卡库找不到带 302【闪光陷阱】的牌")
	检(其他牌 != null, "卡库找不到与神箭手无关的对照牌")
	if 精准牌.size() < 3 or 陷阱牌 == null or 其他牌 == null:
		return

	# ---- 建引擎：1 / 3 同队，2 是对手；玩家 1 换成 dummy 借用角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "借用者")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.start_with_roles({1: 0, 2: 0, 3: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	var 玩家: BattlePlayer = 引擎.p(1)
	var 靶: BattlePlayer = 引擎.p(2)
	玩家.role_id = 75
	var 借用角色 = 借用弓女.new()
	借用角色.setup(玩家, 引擎)
	玩家.role = 借用角色
	var 神箭手 = 借用角色.神箭手
	检(神箭手 != null, "helper 没有构造出来")
	if 神箭手 == null:
		return
	检(神箭手.技能号() == [301, 302], "helper 应负责 301 / 302，实际 %s" % str(神箭手.技能号()))

	# ---- 技能栏：302 一直下发，手里没有带 302 的牌时置灰 ----
	玩家.hand_cards.clear()
	var 栏: Array = 借用角色.available_skills()
	检(栏.size() == 1, "可用技能() 应只给 302 一颗（301 不是技能栏按钮），实际 %d 项" % 栏.size())
	var 陷阱项: Dictionary = 栏[0] if not 栏.is_empty() else {}
	检(int(陷阱项.get("type", 0)) == GConst.ActionType.MagicSkill, "302 应作为法术技能按钮下发")
	检(int(陷阱项.get("id", 0)) == 302, "技能栏项不是【闪光陷阱】(302)")
	检(int(陷阱项.get("need_card", 0)) == 1 and int(陷阱项.get("need_target", 0)) == 1,
		"【闪光陷阱】应要求 1 张发动牌 + 1 名目标")
	检(not bool(陷阱项.get("enabled", true)), "没有 302 牌时【闪光陷阱】应置灰，不是消失")
	检((陷阱项.get("cards", []) as Array).is_empty(), "没有 302 牌时 cards 应为空")
	玩家.hand_cards.append(陷阱牌.id)
	栏 = 借用角色.available_skills()
	陷阱项 = 栏[0] if not 栏.is_empty() else {}
	检(bool(陷阱项.get("enabled", false)), "手里有 302 牌时【闪光陷阱】应可点")
	检((陷阱项.get("cards", []) as Array).has(陷阱牌.id), "可点牌表应包含这张 302 牌")

	# ---- 302 校验：发动牌、目标、来源、技能号归属 ----
	var 动作: Dictionary = {"src_id": 1, "action_id": 302, "card_ids": [陷阱牌.id], "dst_ids": [2]}
	检(神箭手.v_magic_skill(动作) == GConst.GE_SUCCESS, "合法的【闪光陷阱】应通过校验")
	var 别家动作: Dictionary = {"src_id": 2, "action_id": 302, "card_ids": [陷阱牌.id], "dst_ids": [2]}
	检(神箭手.v_magic_skill(别家动作) != GConst.GE_SUCCESS, "别人的 302 行动不应通过校验")
	检(神箭手.v_magic_skill({"src_id": 1, "action_id": 7504, "card_ids": [], "dst_ids": []})
		== BattleRole.V_NOT_OVERRIDE, "不是 302 的动作应返回 V_NOT_OVERRIDE，交回借用角色")
	玩家.hand_cards.append(其他牌.id)
	检(神箭手.v_magic_skill({"src_id": 1, "action_id": 302, "card_ids": [其他牌.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "不带【闪光陷阱】的牌不能发动 302")
	玩家.hand_cards = [其他牌.id] as Array[int]
	检(神箭手.v_magic_skill(动作) != GConst.GE_SUCCESS, "不在手里的 302 牌不能发动")
	玩家.hand_cards = [陷阱牌.id] as Array[int]
	检(神箭手.v_magic_skill({"src_id": 1, "action_id": 302, "card_ids": [陷阱牌.id], "dst_ids": [99]})
		!= GConst.GE_SUCCESS, "目标不存在时不能发动 302")
	检(神箭手.v_magic_skill({"src_id": 1, "action_id": 302, "card_ids": [陷阱牌.id], "dst_ids": []})
		!= GConst.GE_SUCCESS, "没有目标时不能发动 302")

	# ---- 302 完整结算：亮牌 → 弃置 → 2 点法术伤害 → 目标摸 2 张 ----
	引擎._states.clear()
	引擎._清空等待()
	发送记录.clear()
	玩家.hand_cards = [陷阱牌.id] as Array[int]
	靶.hand_cards.clear()
	靶.cross_num = 0
	引擎.current_id = 1
	var 弃牌前: int = 引擎.deck.discard_size()
	引擎.push(BattleEngine.SkillRun.new("magic", 动作))
	引擎.run()
	检(引擎._await_id == -1, "302 结算完不应还在等回复（await=%s）" % str(引擎._await_id))
	检(not 玩家.hand_cards.has(陷阱牌.id), "302 的发动牌应离手")
	检(引擎.deck.discard.has(陷阱牌.id), "302 的发动牌应进弃牌堆")
	检(引擎.deck.discard_size() == 弃牌前 + 1, "302 应只弃 1 张发动牌")
	检(靶.hand_cards.size() == 2, "302 的 2 点伤害应让目标摸 2 张，实际 %d 张" % 靶.hand_cards.size())
	var 伤害广播: Dictionary = _找消息(GConst.Msg.Hurt,
		func(数据: Dictionary) -> bool: return int(数据.get("dst_id", -1)) == 2)
	检(not 伤害广播.is_empty(), "302 结算没有广播伤害")
	检(int(伤害广播.get("hurt", 0)) == 2, "302 的伤害应为 2 点，实际 %s" % str(伤害广播.get("hurt")))
	检(int(伤害广播.get("type", -1)) == GConst.HarmType.Magic, "302 的伤害应是法术伤害")
	检(int(伤害广播.get("cause", 0)) == 302, "302 的伤害来源应为技能号 302")
	var 亮牌: Dictionary = _找消息(GConst.Msg.Card,
		func(数据: Dictionary) -> bool: return (数据.get("card_ids", []) as Array).has(陷阱牌.id))
	检(not 亮牌.is_empty(), "302 应先把发动牌亮给所有人")
	var 播报: Dictionary = _找消息(GConst.Msg.Skill,
		func(数据: Dictionary) -> bool: return int(数据.get("skill_id", 0)) == 302)
	检(not 播报.is_empty(), "302 应播报技能号 302")

	# ---- 301 单钩子：带 301 的攻击牌先问，发动后强制命中 + 伤害 -1 ----
	引擎._states.clear()
	引擎._清空等待()
	发送记录.clear()
	玩家.hand_cards.clear()
	引擎.current_id = 1
	var 伤害: Dictionary = {"src": 1, "dst": 2, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
		"card_id": 精准牌[0].id, "is_active": true}
	var 上下文: Dictionary = {"card_id": 精准牌[0].id, "dst": 2, "src": 1, "is_active": true,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": 伤害}
	检(借用角色.p_timeline_1(上下文) == BattleRole.WAIT, "带 301 的攻击牌应先问是否发动【精准射击】")
	var 问301: Dictionary = _找询问(1, 301)
	检(not 问301.is_empty(), "没有向攻击者发出 301 询问")
	检((问301.get("dst_ids", []) as Array) == [2], "301 询问应点名本次攻击目标：%s" % str(问301.get("dst_ids", [])))
	检(int(问301.get("preview_base", 0)) == BattleEngine.ATTACK_BASE_POINT,
		"301 询问应带上发动前的本次攻击伤害，供客户端在头像上现算 -1")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(借用角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "回复发动后 301 应正常收尾")
	检(int(上下文.get("hit_rate", -1)) == GConst.HitRate.NoMiss, "301 应把本次攻击改成强制命中")
	检(int(伤害.get("point", 0)) == BattleEngine.ATTACK_BASE_POINT - 1, "301 应让本次攻击伤害 -1")
	发送记录.clear()
	检(借用角色.p_timeline_1(上下文) == BattleRole.SUCCESS, "同一张攻击牌处理完后再入应收尾")
	检(_找询问(1, 301).is_empty(), "同一张攻击牌不应重复询问 301")

	# ---- 301 不发动：命中与伤害都不变 ----
	var 伤害2: Dictionary = {"src": 1, "dst": 2, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
		"card_id": 精准牌[1].id, "is_active": true}
	var 上下文2: Dictionary = {"card_id": 精准牌[1].id, "dst": 2, "src": 1, "is_active": true,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": 伤害2}
	检(借用角色.p_timeline_1(上下文2) == BattleRole.WAIT, "换一张 301 攻击牌应重新询问")
	引擎._reply = {"args": [], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(借用角色.p_timeline_1(上下文2) == BattleRole.SUCCESS, "301 不发动时应正常收尾")
	检(int(上下文2.get("hit_rate", -1)) == GConst.HitRate.Normal, "不发动 301 不应改命中率")
	检(int(伤害2.get("point", 0)) == BattleEngine.ATTACK_BASE_POINT, "不发动 301 不应改伤害")

	# ---- 不带 301 的攻击牌：完全不管 ----
	var 伤害3: Dictionary = {"src": 1, "dst": 2, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
		"card_id": 其他牌.id, "is_active": true}
	var 上下文3: Dictionary = {"card_id": 其他牌.id, "dst": 2, "src": 1, "is_active": true,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": 伤害3}
	发送记录.clear()
	检(借用角色.p_timeline_1(上下文3) == BattleRole.SUCCESS, "不带 301 的攻击牌不应触发询问")
	检(_找询问(1, 301).is_empty(), "不带 301 的攻击牌不应发出 301 询问")
	检(int(伤害3.get("point", 0)) == BattleEngine.ATTACK_BASE_POINT, "不带 301 的攻击牌不应改伤害")

	# ---- 301 完整攻击结算：强制命中，不再问应战，伤害按 -1 结算 ----
	引擎._states.clear()
	引擎._清空等待()
	发送记录.clear()
	引擎.current_id = 1
	玩家.hand_cards.clear()
	靶.hand_cards.clear()
	靶.cross_num = 0
	靶.basic_effects.clear()
	靶.cover_cards.clear()
	引擎.team_gem[GConst.BLUE] = 0
	var 完整伤害: Dictionary = {"src": 1, "dst": 2, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
		"card_id": 精准牌[2].id, "is_active": true}
	引擎.push(BattleEngine.SAttackCard.new(1, 2, 精准牌[2].id, 完整伤害))
	引擎.run()
	检(引擎._await_id == 1, "攻击宣告后应等攻击者回复 301（await=%s）" % str(引擎._await_id))
	检(not _找询问(1, 301).is_empty(), "完整攻击流程里没有发出 301 询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 301, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == -1, "301 强制命中后不应再等应战（await=%s）" % str(引擎._await_id))
	检(_找询问(2, GConst.RespondType.ReplyAttack).is_empty(), "301 强制命中后不应再问目标应战")
	检(靶.hand_cards.size() == BattleEngine.ATTACK_BASE_POINT - 1,
		"301 后本次攻击应造成 1 点伤害（目标摸 1 张），实际 %d 张" % 靶.hand_cards.size())
	检(int(引擎.team_gem[GConst.BLUE]) == 1, "攻击命中后攻击方战绩区应 +1 宝石")
	var 命中伤害: Dictionary = _找消息(GConst.Msg.Hurt,
		func(数据: Dictionary) -> bool: return int(数据.get("dst_id", -1)) == 2)
	检(not 命中伤害.is_empty(), "完整攻击没有广播伤害")
	检(int(命中伤害.get("hurt", 0)) == BattleEngine.ATTACK_BASE_POINT - 1,
		"精准射击后的伤害应为 1，实际 %s" % str(命中伤害.get("hurt")))

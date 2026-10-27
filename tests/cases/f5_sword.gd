extends 自检用例
## F5-F 剑圣独有技 helper（101 疾风技 / 102 烈风技）
##
## 用一个只把 p_timeline_1 转给 helper 的 dummy 借用角色，跑真实攻击流水线：
## - 102：目标有【圣盾】时先问攻击者；发动后对手无法应战、圣盾不被消耗、攻击照常命中；
## - 101：主动攻击带【疾风技】时先问攻击者；发动后挂上额外攻击行动，行动结束直接进入额外攻击阶段；
## - 边界：目标没圣盾不问 102、应战攻击（is_active=false）不触发 101、【天使之墙】等同圣盾、
##   取消不生效、只有攻击者本人的攻击宣告才处理。

## dummy 借用角色：只转发攻击宣告（p_timeline_1），其余钩子全部走基类
class 借用角色:
	extends BattleRole

	const 剑圣技能类 = preload("res://scripts/battle/skills/skill_sword.gd")

	var 剑圣: 剑圣技能类

	func setup(p: BattlePlayer, e: BattleEngine) -> void:
		super.setup(p, e)
		剑圣 = 剑圣技能类.new(self)

	func p_timeline_1(ctx: Dictionary) -> int:
		return 剑圣.p_timeline_1(ctx)


var 引擎: BattleEngine = null
var 借用者: BattlePlayer = null
var 靶: BattlePlayer = null
var 角色: 借用角色 = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []


func _init() -> void:
	名称 = "剑圣独有技借用"


## 卡库里第一张带指定技能号的攻击牌
func _取攻击牌(技能号: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() and c.has_skill_id(技能号):
			return c
	return null


## 卡库里第一张指定卡名的牌
func _取卡名(卡名: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.card_name_enum() == 卡名:
			return c
	return null


## 最近一次下发给某玩家的询问里，是否有指定 respond_id 的那条
func _取询问(pid: int, respond_id: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == respond_id:
			return r
	return {}


## 最近一条落到某玩家身上的伤害点数（没有则 -1）
func _收到伤害(dst: int) -> int:
	var 值: int = -1
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Hurt and int((r["data"] as Dictionary).get("dst_id", -1)) == dst:
			值 = int((r["data"] as Dictionary).get("hurt", -1))
	return 值


## 是否向某玩家问过应战
func _有应战询问(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["pid"]) != pid or int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		for cmd: Dictionary in (r["data"] as Dictionary).get("commands", []):
			if int(cmd.get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
				return true
	return false


## 是否播报过某技能
func _播报过(技能号: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Skill \
				and int((r["data"] as Dictionary).get("skill_id", 0)) == 技能号:
			return true
	return false


## 清空战斗状态：只保留 dummy 借用攻击者与靶子，靶子无手牌 / 无治疗 / 无基础效果
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.skip_action_phase = false
	发送记录.clear()
	借用者.hand_cards.clear()
	借用者.additional_actions.clear()
	靶.hand_cards.clear()
	靶.basic_effects.clear()
	靶.cross_num = 0
	角色.剑圣.重置()


## 正常走一次攻击行动（与客户端提交攻击用的是同一个入口），并把状态机推到等待 / 结算完
func _发起攻击(牌: GCard) -> void:
	借用者.hand_cards.append(牌.id)
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [牌.id], "dst_ids": [2], "args": []})
	引擎.run()


func 跑() -> void:
	await 等帧(1)
	var 疾风牌: GCard = _取攻击牌(101)
	var 烈风牌: GCard = _取攻击牌(102)
	var 圣盾牌: GCard = _取卡名(GConst.CardName.Shield)
	var 天使之墙牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_天使之墙):
			天使之墙牌 = c
			break
	检(疾风牌 != null, "卡库里找不到带【疾风技】的攻击牌")
	检(烈风牌 != null, "卡库里找不到带【烈风技】的攻击牌")
	检(圣盾牌 != null, "卡库里找不到【圣盾】")
	检(天使之墙牌 != null, "卡库里找不到【天使之墙】")
	# 101 / 102 是剑圣的技能行；helper 播报、询问都按这两个号
	检(not GConst.技能行(101).is_empty() and GConst.skill_name(101).contains("疾风技"),
		"技能表里查不到 101 疾风技")
	检(not GConst.技能行(102).is_empty() and GConst.skill_name(102).contains("烈风技"),
		"技能表里查不到 102 烈风技")
	if 疾风牌 == null or 烈风牌 == null or 圣盾牌 == null or 天使之墙牌 == null:
		return

	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "借用者")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.start_with_roles({1: 0, 2: 0})
	借用者 = 引擎.p(1)
	靶 = 引擎.p(2)
	角色 = 借用角色.new()
	角色.setup(借用者, 引擎)
	借用者.role = 角色
	检(角色.剑圣 != null, "dummy 借用角色没有建好剑圣 helper")

	# ---- 场景 1：102 烈风技（真实攻击流水线，完整结算一次攻击）----
	_重置战斗()
	借用者.hand_cards.append(烈风牌.id)
	靶.basic_effects.append({"card": 圣盾牌.id, "src": 2})
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [烈风牌.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(引擎._await_id == 1,
		"目标有【圣盾】时，攻击宣告后应先问攻击者是否发动【烈风技】（等待 %s）" % str(引擎._await_id))
	检(not _取询问(1, 102).is_empty(), "目标有【圣盾】时没有下发【烈风技】询问")
	检(not _有应战询问(2), "【烈风技】还没结算就先问了目标应战")
	引擎.on_message(1, GConst.Msg.Respond,
		{"respond_id": 102, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": []})
	检(_播报过(102), "【烈风技】发动后没有技能播报")
	# 对手仍会收到应战询问（客户端据 args[0] 只留「放弃」），但服务端必须拒绝任何应战
	检(引擎._await_id == 2, "【烈风技】结算后应由目标应答（等待 %s）" % str(引擎._await_id))
	var 应战问: Dictionary = _取询问(2, GConst.RespondType.ReplyAttack)
	检(int((应战问.get("args", []) as Array)[0] if not 应战问.is_empty() else -1)
		== GConst.HitRate.NoReattack, "【烈风技】的应战询问应标记「无法应战」：%s" % str(应战问))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.Attack], "card_ids": [疾风牌.id], "dst_ids": [1],
	})
	检(引擎._await_id == 2, "【烈风技】下提交应战应被驳回并重新询问（等待 %s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(_收到伤害(2) == BattleEngine.ATTACK_BASE_POINT,
		"发动【烈风技】后攻击应照常命中 %d 点，实际 %d 点" % [BattleEngine.ATTACK_BASE_POINT, _收到伤害(2)])
	检(靶.check_basic_effect_name(GConst.CardName.Shield),
		"【烈风技】的「无视圣盾」是不查 / 不消耗它，圣盾不应被移除")

	# ---- 场景 2：101 疾风技（发动 → 应战 → 命中 → 额外攻击阶段）----
	_重置战斗()
	_发起攻击(疾风牌)
	检(引擎._await_id == 1,
		"主动打出带【疾风技】的攻击牌后应先问攻击者是否发动（等待 %s）" % str(引擎._await_id))
	检(not _取询问(1, 101).is_empty(), "主动攻击没有下发【疾风技】询问")
	检(_取询问(1, 102).is_empty(), "目标没有圣盾时不应问【烈风技】")
	引擎.on_message(1, GConst.Msg.Respond,
		{"respond_id": 101, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": []})
	检(_播报过(101), "【疾风技】发动后没有技能播报")
	var 挂上额外攻击: bool = false
	for a: Dictionary in 借用者.additional_actions:
		if int(a.get("cause", -1)) == 101 and int(a.get("allow_action", -1)) == GConst.ActionType.Attack:
			挂上额外攻击 = true
	检(挂上额外攻击, "【疾风技】发动后没有挂上额外攻击行动：%s" % str(借用者.additional_actions))
	检(引擎._await_id == 2, "【疾风技】结算后应等目标应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(_收到伤害(2) == BattleEngine.ATTACK_BASE_POINT, "【疾风技】的本次攻击应照常命中")
	# direct 的额外行动：本次攻击行动结束后直接进入额外攻击阶段，等攻击者出牌 / 放弃
	var 顶: Variant = 引擎._states[-1] if not 引擎._states.is_empty() else null
	检(顶 is BattleEngine.SActionPhase, "【疾风技】的额外攻击行动应直接进入行动阶段")
	if 顶 is BattleEngine.SActionPhase:
		检(bool((顶 as BattleEngine.SActionPhase).get("额外")), "【疾风技】进入的行动阶段应标记为额外行动")
		检(int((顶 as BattleEngine.SActionPhase).get("额外来源")) == 101,
			"【疾风技】额外行动阶段的来源应为 101")
		检(int((顶 as BattleEngine.SActionPhase).get("允许")) == GConst.ActionType.Attack,
			"【疾风技】的额外行动应只允许攻击")
	检(引擎._await_id == 1, "【疾风技】的额外攻击阶段应在等攻击者行动")

	# ---- 场景 3a：目标没有圣盾时 102 不询问 ----
	_重置战斗()
	var 无盾宣告: Dictionary = {
		"card_id": 烈风牌.id, "src": 1, "dst": 2, "is_active": true,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "harm": {},
	}
	检(角色.p_timeline_1(无盾宣告) == BattleRole.SUCCESS, "目标没有圣盾时【烈风技】不应发动")
	检(_取询问(1, 102).is_empty(), "目标没有圣盾时不应下发【烈风技】询问")
	检(int(无盾宣告["hit_rate"]) == GConst.HitRate.Normal and bool(无盾宣告["check_shield"]),
		"未发动【烈风技】不应改命中率 / 圣盾检查")

	# ---- 场景 3b：应战打出的攻击（is_active=false）不触发 101 ----
	_重置战斗()
	var 应战宣告: Dictionary = {
		"card_id": 疾风牌.id, "src": 1, "dst": 2, "is_active": false,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "harm": {},
	}
	检(角色.p_timeline_1(应战宣告) == BattleRole.SUCCESS, "应战攻击不应触发【疾风技】")
	检(_取询问(1, 101).is_empty(), "应战攻击不应下发【疾风技】询问")
	检(借用者.additional_actions.is_empty(), "应战攻击不应获得额外攻击行动")

	# ---- 场景 3c：【天使之墙】等同圣盾；取消发动后不改本次攻击 ----
	_重置战斗()
	靶.basic_effects.append({"card": 天使之墙牌.id, "src": 2})
	var 墙宣告: Dictionary = {
		"card_id": 烈风牌.id, "src": 1, "dst": 2, "is_active": true,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "harm": {},
	}
	检(角色.p_timeline_1(墙宣告) == BattleRole.WAIT, "目标有【天使之墙】时应询问【烈风技】")
	检(not _取询问(1, 102).is_empty(), "目标有【天使之墙】时没有下发【烈风技】询问")
	引擎._reply = {"args": [0], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(角色.p_timeline_1(墙宣告) == BattleRole.SUCCESS, "取消【烈风技】应直接放行")
	检(int(墙宣告["hit_rate"]) == GConst.HitRate.Normal and bool(墙宣告["check_shield"]),
		"取消【烈风技】不应改命中率 / 圣盾检查")
	检(_取询问(1, 101).is_empty(), "烈风技牌上没有疾风技，取消后不应再问【疾风技】")

	# ---- 场景 3d：只由攻击者本人发动，别人的攻击宣告不掺和 ----
	_重置战斗()
	靶.basic_effects.append({"card": 圣盾牌.id, "src": 2})
	var 他人宣告: Dictionary = {
		"card_id": 烈风牌.id, "src": 2, "dst": 1, "is_active": true,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "harm": {},
	}
	检(角色.p_timeline_1(他人宣告) == BattleRole.SUCCESS, "不是自己发起的攻击不应触发剑圣独有技")
	检(_取询问(1, 102).is_empty() and _取询问(2, 102).is_empty(),
		"别人的攻击宣告下不应询问自己的【烈风技】")

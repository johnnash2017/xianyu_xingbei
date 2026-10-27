extends 自检用例
## R107 忌妒少女（107）：10701 醋意羞心 / 10702 虚荣掌握 / 10703 相思病 / 10704 嫉妒追放。
##
## 任务范围只有 role + test：角色表「脚本」列留给 DATA，用例里手动挂角色脚本。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 四颗技能行 / 技能说明 / 脚本文件；
##   - 10703：技能栏入口、地/风系牌可当【魔弹】（主动使用 + 响应传递），火系牌不行；
##            发动牌与落点校验；真实结算（弃发动牌 → 魔弹传递询问 → 目标放弃吃 2 点法术伤害）；
##            10702 的额外法术行动内用 10703 把地/风系法术牌当【魔弹】打出（技能行动白名单）；
##   - 10701：主动攻击未命中才问；先问发动者；目标强制弃法术牌（A46，询问不可取消），
##            弃出则不结算，弃不出（没有 / 硬提交非法牌 / 硬提交取消 / 超时回空）则 2 点法术伤害
##            + 我方战绩区 +1 水晶；非主动 / 别人的攻击 / 目标不存在不触发；
##            完整攻击流水线（圣光格挡造成未命中）走一遍；
##   - 10702：主动攻击命中才问；额外 +1 法术行动（direct）；临时逆向只在它的额外行动内生效；
##            「只能使用【魔弹】」两套白名单：普通法术行动只放行【魔弹】本体（地/风系【圣盾】
##            等法术牌既不点亮也会被引擎驳回），10703 技能行动放行地/风系牌当【魔弹】；
##            完整流水线：真实攻击命中 → 发动 → 额外法术行动阶段 → 逆向打出魔弹；
##   - 10704：攻击 / 法术行动结束才问；支付 1 能量（宝石可顶水晶）并立即补发对局快照；
##            额外 +1 攻击行动；本次攻击只能打手牌数大于你的对手（引擎兜底校验）；回合限定；
##            完整流水线。
##
## 提示列 10701~10704 目前为空（DATA 任务补齐），用例不依赖提示文案。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_jidushaonv.gd")

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 靶: BattlePlayer = null
var 队友: BattlePlayer = null
## 第二名对手（放在玩家 1 的 pre 方向，用来验证「逆向传递」）
var 靶2: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 魔弹牌: GCard = null
var 地攻击: GCard = null
var 风攻击: GCard = null
var 火攻击: GCard = null
## 第二张攻击牌（10704 的额外攻击行动要用掉一张新的）
var 副攻击: GCard = null
var 火法术: GCard = null
## 地 / 风系法术牌（【圣盾】/【虚弱】/【中毒】之一）：10702 的额外行动里不能当普通法术结算，
## 只能走 10703 技能当【魔弹】
var 地法术: GCard = null
var 风法术: GCard = null
var 圣光牌: GCard = null


func _init() -> void:
	名称 = "忌妒少女"


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


## 行动命令表（action_commands）里找某个技能按钮：技能号写在 args[0]（第 0 条通用行动 args 为空）
func _取技能命令(表: Array, id: int) -> Dictionary:
	for cmd: Dictionary in 表:
		var args: Array = cmd.get("args", [])
		if not args.is_empty() and int(args[0]) == id:
			return cmd
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


## 某条额外行动还在不在待办里
func _有额外行动(cause: int) -> bool:
	for a: Dictionary in 玩家.additional_actions:
		if int(a.get("cause", 0)) == cause:
			return true
	return false


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


## 状态栈里找第一条魔弹传递询问
func _取魔弹询问() -> BattleEngine.SMissileAsk:
	for st: Variant in 引擎._states:
		if st is BattleEngine.SMissileAsk:
			return st as BattleEngine.SMissileAsk
	return null


# ============================================================
# 战斗重置 / 上下文
# ============================================================
func _清空玩家(p0: BattlePlayer) -> void:
	p0.hand_cards.clear()
	p0.additional_actions.clear()
	p0.basic_effects.clear()
	p0.cross_num = 0
	p0.set_crystal(0)
	p0.set_gem(0)
	p0.reset_action_counts()


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
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.测试跳过回合 = -1
	引擎.team_gem = [0, 0]
	引擎.team_crystal = [0, 0]
	引擎.team_morale = [引擎.士气上限(), 引擎.士气上限()]
	发送记录.clear()
	_清空玩家(玩家)
	_清空玩家(靶)
	_清空玩家(队友)
	_清空玩家(靶2)
	角色.p_before_turn_begin({})


func _攻击上下文(牌: GCard, src: int, dst: int, 主动: bool, 伤害: int) -> Dictionary:
	var harm: Dictionary = {
		"src": src, "dst": dst, "point": 伤害, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 牌.id, "is_active": 主动,
	}
	return {
		"card_id": 牌.id, "dst": dst, "src": src, "is_active": 主动,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": harm,
	}


## 用一张攻击牌宣告一次新攻击：清掉角色身上上一次攻击的分步标记
func _新一次攻击宣告() -> void:
	角色.p_timeline_1(_攻击上下文(火攻击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT))


## 直接调用角色钩子时预置一份回复（对应玩家在客户端点了确定）
func _应答(args: Array, cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": []}
	引擎._has_reply = true


## 给某玩家手牌补 count 张火系法术牌（用于「手牌数比你多」的对手）
func _补法术牌(p0: BattlePlayer, count: int) -> void:
	for _i: int in range(count):
		_给牌(p0, 火法术.id)


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 ----
	检(str(Data.role_list.get(107, "")) == "忌妒少女", "107 号角色名不是「忌妒少女」")
	检(Data.role_personal_name(107) == "妮亚", "107 号角色姓名不是「妮亚」")
	检(absf(Data.role_star(107) - 3.0) < 0.01, "忌妒少女应是 3.0 星，实际 %s" % str(Data.role_star(107)))
	检(Data.role_skills(107) == [10701, 10702, 10703, 10704],
		"忌妒少女技能号不对：%s" % str(Data.role_skills(107)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_jidushaonv.gd"), "忌妒少女的角色脚本文件不存在")
	for 技能号: int in [10701, 10702, 10703, 10704]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	检(GConst.技能号("技能#忌妒少女#醋意羞心") == 10701, "【醋意羞心】技能号应为 10701")
	检(GConst.技能号("技能#忌妒少女#虚荣掌握") == 10702, "【虚荣掌握】技能号应为 10702")
	检(GConst.技能号("技能#忌妒少女#相思病") == 10703, "【相思病】技能号应为 10703")
	检(GConst.技能号("技能#忌妒少女#嫉妒追放") == 10704, "【嫉妒追放】技能号应为 10704")
	var 技能说明: String = Data.role_skill_info(107)
	for 技能名: String in ["醋意羞心", "虚荣掌握", "相思病", "嫉妒追放"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提 ----
	魔弹牌 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() == GConst.CardName.Missile)
	地攻击 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.element_enum() == GConst.CardElement.Earth)
	风攻击 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.element_enum() == GConst.CardElement.Wind)
	火攻击 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.element_enum() == GConst.CardElement.Fire)
	var 火攻击号: int = 火攻击.id if 火攻击 != null else -1
	副攻击 = _取牌(func(c: GCard) -> bool: return c.is_attack() and c.id != 火攻击号)
	火法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Fire and c.card_name_enum() != GConst.CardName.Missile)
	地法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Earth and c.card_name_enum() != GConst.CardName.Missile)
	风法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Wind and c.card_name_enum() != GConst.CardName.Missile)
	圣光牌 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() == GConst.CardName.HolyLight)
	检(魔弹牌 != null, "卡库找不到【魔弹】牌")
	检(地攻击 != null, "卡库找不到地系攻击牌")
	检(风攻击 != null, "卡库找不到风系攻击牌")
	检(火攻击 != null, "卡库找不到火系攻击牌")
	检(副攻击 != null and 副攻击.id != 火攻击.id, "卡库找不到第二张攻击牌")
	检(火法术 != null, "卡库找不到非魔弹的火系法术牌")
	检(地法术 != null, "卡库找不到非魔弹的地系法术牌（【圣盾】等）")
	检(风法术 != null, "卡库找不到非魔弹的风系法术牌（【圣盾】等）")
	检(圣光牌 != null, "卡库找不到【圣光】牌")
	if 魔弹牌 == null or 地攻击 == null or 风攻击 == null or 火攻击 == null \
			or 副攻击 == null or 火法术 == null or 地法术 == null or 风法术 == null or 圣光牌 == null:
		return

	# ---- 建引擎：1 / 3 同队，2 与 4 是对手；4 在 1 的 pre 方向（逆向传递用） ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "忌妒")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "对手2")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	靶 = 引擎.p(2)
	队友 = 引擎.p(3)
	靶2 = 引擎.p(4)
	玩家.role_id = 107
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	_重置战斗()

	# ============================================================
	# 10703 相思病：技能栏 / 牌类校验 / 完整结算
	# ============================================================
	var 栏: Array = 角色.available_skills()
	检(栏.size() == 1, "忌妒少女技能栏只应有 10703 一项，实际 %d 项：%s" % [栏.size(), str(栏)])
	var 相思项: Dictionary = _找技能(栏, 10703)
	检(not 相思项.is_empty(), "【相思病】(10703) 应下发到技能栏")
	检(int(相思项.get("type", 0)) == GConst.ActionType.MagicSkill, "10703 应作为法术技能按钮下发")
	检(int(相思项.get("need_card", 0)) == 1 and int(相思项.get("need_target", 0)) == 1,
		"10703 应要求 1 张发动牌 + 1 名目标")
	检(not bool(相思项.get("enabled", true)), "手里没有地/风系牌时 10703 应置灰，不是消失")
	检(角色.missile_fusion_elements() == [GConst.CardElement.Earth, GConst.CardElement.Wind],
		"10703 的可当魔弹系别应为地 / 风：%s" % str(角色.missile_fusion_elements()))
	检(int(角色.missile_fusion_skill()) == 10703, "10703 的魔弹融合播报号应为 10703，不借用 803/7602")

	_给牌(玩家, 火攻击.id)
	相思项 = _找技能(角色.available_skills(), 10703)
	检(not bool(相思项.get("enabled", true)), "只有火系牌时 10703 应置灰")
	检((相思项.get("cards", []) as Array).is_empty(), "只有火系牌时 10703 的牌表应为空")
	_给牌(玩家, 地攻击.id)
	_给牌(玩家, 风攻击.id)
	_给牌(玩家, 魔弹牌.id)
	栏 = 角色.available_skills()
	相思项 = _找技能(栏, 10703)
	检(bool(相思项.get("enabled", false)), "有地/风系牌与对手时 10703 应可点")
	检((相思项.get("cards", []) as Array).has(地攻击.id), "10703 的牌表应包含地系牌")
	检((相思项.get("cards", []) as Array).has(风攻击.id), "10703 的牌表应包含风系牌")
	检(not (相思项.get("cards", []) as Array).has(火攻击.id), "10703 的牌表不应包含火系牌")
	检(角色.missile_targets(1) == [2], "没有【魔弹掌控】时落点只有右手边最近的对手：%s"
		% str(角色.missile_targets(1)))

	# 牌类校验：地 / 风系牌（与【魔弹】本体）可以当魔弹使用 / 响应传递，火系不行
	检(角色.v_missile(地攻击.id, 2) == GConst.GE_SUCCESS, "地系牌应能当【魔弹】使用")
	检(角色.v_missile(风攻击.id, 2) == GConst.GE_SUCCESS, "风系牌应能当【魔弹】使用")
	检(角色.v_missile(魔弹牌.id, 2) == GConst.GE_SUCCESS, "【魔弹】本体应能使用")
	检(角色.v_missile(火攻击.id, 2) != GConst.GE_SUCCESS, "火系牌不能当【魔弹】使用")
	检(角色.v_remissile(地攻击.id) == GConst.GE_SUCCESS, "地系牌应能继续传递魔弹")
	检(角色.v_remissile(风攻击.id) == GConst.GE_SUCCESS, "风系牌应能继续传递魔弹")
	检(角色.v_remissile(火攻击.id) != GConst.GE_SUCCESS, "火系牌不能继续传递魔弹")

	var 相思动作: Dictionary = {"src_id": 1, "action_id": 10703,
		"card_ids": [地攻击.id], "dst_ids": [2]}
	检(角色.v_magic_skill(相思动作) == GConst.GE_SUCCESS, "合法的 10703 应通过校验")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 10703, "card_ids": [地攻击.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "别人的 10703 行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10701, "card_ids": [地攻击.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "不是 10703 的法术技能行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10703, "card_ids": [火攻击.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "火系牌不能作为 10703 的发动牌")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10703, "card_ids": [地攻击.id], "dst_ids": [4]})
		!= GConst.GE_SUCCESS, "没有【魔弹掌控】时不能把落点选成逆向那个对手")

	# 完整结算：地系牌当【魔弹】打出 → 弃发动牌 → 目标应答魔弹传递 → 放弃吃 2 点法术伤害
	_重置战斗()
	_给牌(玩家, 地攻击.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, 相思动作)
	引擎.run()
	检(not 玩家.has_hand_card(地攻击.id), "10703 的发动牌应离手")
	检(引擎.deck.discard.has(地攻击.id), "10703 的发动牌应进弃牌堆")
	检(引擎._await_id == 2, "10703 打出后应等目标应答魔弹（等待 %s）" % str(引擎._await_id))
	检(not _取询问(2, GConst.RespondType.Bullet).is_empty(), "没有下发魔弹传递询问")
	检(_播报次数(10703) == 1, "10703 发动应播报一次，实际 %d 次" % _播报次数(10703))
	var 视为魔弹: Dictionary = _找消息(GConst.Msg.Card,
		func(数据: Dictionary) -> bool: return int(数据.get("as_card_id", 0)) == 魔弹牌.id and (数据.get("card_ids", []) as Array).has(地攻击.id))
	检(not 视为魔弹.is_empty(), "地系牌当魔弹打出时应把 as_card_id 标成【魔弹】")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(靶.hand_cards.size() == BattleEngine.MISSILE_BASE_POINT,
		"10703 的魔弹 2 点法术伤害应让目标摸 2 张，实际 %d 张" % 靶.hand_cards.size())

	# ============================================================
	# 10701 醋意羞心
	# ============================================================
	# 取消发动：不结算、不播报
	_重置战斗()
	_给牌(靶, 火法术.id)
	_新一次攻击宣告()
	发送记录.clear()
	var 未命中上下文: Dictionary = _攻击上下文(火攻击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT,
		"主动攻击未命中时应问是否发动【醋意羞心】")
	检(not _取询问(1, 10701).is_empty(), "没有下发【醋意羞心】发动询问")
	_应答([0])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.SUCCESS, "不发动【醋意羞心】应直接收尾")
	检(_找伤害(10701, 2).is_empty(), "不发动【醋意羞心】不应压入伤害")
	检(引擎.team_crystal[GConst.BLUE] == 0, "不发动【醋意羞心】不应给我方战绩区加水晶")
	检(_播报次数(10701) == 0, "不发动【醋意羞心】不应播报")

	# 发动 + 目标弃法术牌：不造成伤害、不加水晶
	_重置战斗()
	_给牌(靶, 火法术.id)
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "未命中时应先问【醋意羞心】")
	_应答([1])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "发动后应让目标选择弃 1 张法术牌")
	var 弃牌问: Dictionary = _取询问(2, 10701)
	检(not 弃牌问.is_empty(), "没有向目标下发【醋意羞心】弃牌询问")
	检(str(弃牌问.get("card_rule", "")) == "magic", "【醋意羞心】只能弃法术牌")
	检(not bool(弃牌问.get("can_cancel", true)),
		"【醋意羞心】的弃牌是强制的（data-audit A46），客户端取消应置灰")
	检((弃牌问.get("card_ids", []) as Array).has(火法术.id),
		"【醋意羞心】的可点牌表应包含目标手里的法术牌")
	检(_播报次数(10701) == 1, "发动【醋意羞心】应播报一次，实际 %d 次" % _播报次数(10701))
	_应答([1], [火法术.id])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.SUCCESS, "目标弃牌后应正常收尾")
	检(not 靶.hand_cards.has(火法术.id), "目标弃出的法术牌应离手")
	检(引擎.deck.discard.has(火法术.id), "目标弃出的法术牌应进弃牌堆")
	检(_找伤害(10701, 2).is_empty(), "目标弃牌后不应再造成伤害")
	检(引擎.team_crystal[GConst.BLUE] == 0, "目标弃牌后不应再给我方加水晶")
	检(not _找消息(GConst.Msg.Card,
		func(数据: Dictionary) -> bool: return (数据.get("card_ids", []) as Array).has(火法术.id)).is_empty(),
		"目标弃出的牌应【展示】给所有人")

	# 强制弃（A46）：客户端取消已置灰，这里模拟改包硬提交「取消」→ 按没弃出结算惩罚
	_重置战斗()
	_给牌(靶, 火法术.id)
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "未命中时应先问【醋意羞心】")
	_应答([1])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "发动后应让目标选择弃牌")
	检(not bool(_取询问(2, 10701).get("can_cancel", true)),
		"【醋意羞心】的弃牌询问应不可取消")
	_应答([0])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.URGENT,
		"硬提交取消（没弃出）时应压入 2 点法术伤害")
	var 羞心伤害: Dictionary = _找伤害(10701, 2)
	检(not 羞心伤害.is_empty(), "【醋意羞心】没有压入目标伤害")
	检(int(羞心伤害.get("point", 0)) == 2, "【醋意羞心】的伤害应为 2 点")
	检(int(羞心伤害.get("type", -1)) == GConst.HarmType.Magic, "【醋意羞心】的伤害应是法术伤害")
	检(int(羞心伤害.get("src", -1)) == 1, "【醋意羞心】的伤害来源应是发动者")
	检(引擎.team_crystal[GConst.BLUE] == 1, "目标没弃出牌时应给我方战绩区 +1 水晶")
	检(靶.hand_cards.has(火法术.id), "目标没弃出牌时其法术牌应留在手里")
	引擎.run()
	var 水晶: int = 引擎.team_crystal[GConst.BLUE]
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.SUCCESS,
		"伤害结算完回到本钩子时应直接收尾，不能重复结算")
	检(引擎.team_crystal[GConst.BLUE] == 水晶, "重入不应重复给我方加水晶")
	检(_找伤害(10701, 2).is_empty(), "重入不应重复压入伤害")
	检(靶.hand_cards.size() == 3, "目标挨 2 点法术伤害应摸 2 张（1+2=3），实际 %d 张"
		% 靶.hand_cards.size())

	# 目标手里没有法术牌：发动后直接结算惩罚，不再白问目标
	_重置战斗()
	_给牌(靶, 火攻击.id)
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "未命中时应先问【醋意羞心】")
	_应答([1])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.URGENT,
		"目标没有法术牌时应直接结算 2 点法术伤害")
	检(_取询问(2, 10701).is_empty(), "目标没有法术牌时不应再下发弃牌询问")
	检(not _找伤害(10701, 2).is_empty(), "目标没有法术牌时应压入伤害")
	检(引擎.team_crystal[GConst.BLUE] == 1, "目标没有法术牌时应给我方 +1 水晶")

	# 硬提交非法牌（不是法术牌）：按不弃处理，牌不离手
	_重置战斗()
	_给牌(靶, 火法术.id)
	_给牌(靶, 火攻击.id)
	_新一次攻击宣告()
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "未命中时应先问【醋意羞心】")
	_应答([1])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.WAIT, "发动后应让目标选择弃牌")
	_应答([1], [火攻击.id])
	检(角色.p_timeline_2_miss(未命中上下文) == BattleRole.URGENT,
		"硬提交非法术牌应按「不弃」处理并结算惩罚")
	检(靶.hand_cards.has(火攻击.id), "硬提交的非法术牌不应离手")
	检(靶.hand_cards.has(火法术.id), "硬提交非法术牌时目标应保留自己的法术牌")
	检(not _找伤害(10701, 2).is_empty(), "硬提交非法术牌时应压入伤害")
	检(引擎.team_crystal[GConst.BLUE] == 1, "硬提交非法术牌时应给我方 +1 水晶")

	# 非主动攻击 / 别人的未命中 / 目标不存在：一律不问
	_重置战斗()
	_给牌(靶, 火法术.id)
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_miss(_攻击上下文(火攻击, 1, 2, false, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "应战反击（非主动攻击）未命中不应触发【醋意羞心】")
	检(_询问次数(1, 10701) == 0, "非主动攻击未命中不应下发 10701 询问")
	检(角色.p_timeline_2_miss(_攻击上下文(火攻击, 2, 1, true, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "别人的未命中不应触发【醋意羞心】")
	检(_询问次数(1, 10701) == 0, "别人的未命中不应下发 10701 询问")
	_重置战斗()
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_miss(_攻击上下文(火攻击, 1, 99, true, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "目标不存在时应安全收尾")
	检(_询问次数(1, 10701) == 0, "目标不存在时不应下发 10701 询问")

	# 完整攻击流水线：目标用【圣光】格挡 → 未命中 → 发动 10701 → 目标硬提交取消（没弃出）→ 伤害 + 水晶
	_重置战斗()
	_给牌(玩家, 火攻击.id)
	_给牌(靶, 圣光牌.id)
	_给牌(靶, 火法术.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.Attack,
		{"card_ids": [火攻击.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(引擎._await_id == 2, "攻击宣告后应先等目标应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.Block], "card_ids": [圣光牌.id], "dst_ids": [],
	})
	检(引擎._await_id == 1, "圣光格挡造成未命中后应问发动者是否发动【醋意羞心】（等待 %s）"
		% str(引擎._await_id))
	检(not _取询问(1, 10701).is_empty(), "完整流水线没有下发【醋意羞心】发动询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 10701, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == 2, "发动后应让目标选择弃法术牌（等待 %s）" % str(引擎._await_id))
	检(not bool(_取询问(2, 10701).get("can_cancel", true)),
		"完整流水线里【醋意羞心】的弃牌询问也应不可取消（A46）")
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 10701, "src_id": 2, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(引擎.team_crystal[GConst.BLUE] == 1, "完整流水线里目标没弃出牌应给我方 +1 水晶")
	检(靶.hand_cards.size() == 3,
		"格挡后目标手里 1 张 + 10701 的 2 点伤害摸 2 张 = 3，实际 %d 张" % 靶.hand_cards.size())

	# ============================================================
	# 10702 虚荣掌握
	# ============================================================
	# 取消发动：不给额外行动
	_重置战斗()
	_给牌(玩家, 魔弹牌.id)
	_新一次攻击宣告()
	发送记录.clear()
	var 命中上下文: Dictionary = _攻击上下文(火攻击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.WAIT,
		"主动攻击命中且有可当魔弹的牌时应问是否发动【虚荣掌握】")
	检(not _取询问(1, 10702).is_empty(), "没有下发【虚荣掌握】询问")
	_应答([0])
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS, "不发动【虚荣掌握】应直接收尾")
	检(not _有额外行动(10702), "不发动【虚荣掌握】不应给额外法术行动")
	检(_播报次数(10702) == 0, "不发动【虚荣掌握】不应播报")

	# 发动：额外 +1 法术行动（direct）
	_重置战斗()
	_给牌(玩家, 魔弹牌.id)
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.WAIT, "命中时应先问【虚荣掌握】")
	_应答([1])
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS, "发动【虚荣掌握】后应正常收尾")
	检(_有额外行动(10702), "【虚荣掌握】应额外 +1 法术行动")
	检(_播报次数(10702) == 1, "【虚荣掌握】发动应播报一次，实际 %d 次" % _播报次数(10702))
	var 额外: Dictionary = 玩家.additional_actions[0] if not 玩家.additional_actions.is_empty() else {}
	检(int(额外.get("allow_action", 0)) == GConst.ActionType.Magic, "【虚荣掌握】的额外行动应是法术行动")
	检(bool(额外.get("direct", false)), "【虚荣掌握】已问过，额外行动应标记 direct 不再二次询问")

	# 手里没有可当魔弹的牌：不问
	_重置战斗()
	_给牌(玩家, 火攻击.id)
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS,
		"手里没有可当魔弹的牌时不应询问【虚荣掌握】")
	检(_询问次数(1, 10702) == 0, "手里没有可当魔弹的牌时不应下发 10702 询问")
	# 非主动攻击 / 别人的命中：不问
	_重置战斗()
	_给牌(玩家, 魔弹牌.id)
	_新一次攻击宣告()
	发送记录.clear()
	检(角色.p_timeline_2_hit(_攻击上下文(火攻击, 1, 2, false, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "应战反击命中不应触发【虚荣掌握】")
	检(角色.p_timeline_2_hit(_攻击上下文(火攻击, 2, 1, true, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "别人的主动攻击命中不应触发【虚荣掌握】")
	检(_询问次数(1, 10702) == 0, "非主动 / 别人的命中不应下发 10702 询问")

	# 临时【魔弹掌控】与「只能使用【魔弹】」两套白名单（普通法术行动 / 10703 技能行动）
	_重置战斗()
	_给牌(玩家, 魔弹牌.id)
	_给牌(玩家, 地攻击.id)
	_给牌(玩家, 风攻击.id)
	_给牌(玩家, 地法术.id)
	_给牌(玩家, 风法术.id)
	_给牌(玩家, 火攻击.id)
	_给牌(玩家, 火法术.id)
	检(not 角色.has_missile_mastery(), "非 10702 的额外行动里不应有【魔弹掌控】")
	检(角色.missile_targets(1) == [2], "非额外行动时落点只有右手边最近对手")
	引擎.行动额外 = true
	引擎.行动额外来源 = 10702
	检(角色.has_missile_mastery(), "10702 的额外法术行动内应临时获得【魔弹掌控】")
	检(角色.missile_targets(1) == [2, 4],
		"临时【魔弹掌控】应让左右两个对手都能选：%s" % str(角色.missile_targets(1)))
	var 白名单: Array = 角色.extra_action_card_ids(10702, GConst.ActionType.Magic)
	检(白名单.has(魔弹牌.id), "10702 普通法术行动的白名单应包含【魔弹】本体")
	检(not 白名单.has(地攻击.id), "普通法术行动的白名单不应包含地系攻击牌（那只能走 10703 技能）")
	检(not 白名单.has(风攻击.id), "普通法术行动的白名单不应包含风系攻击牌（那只能走 10703 技能）")
	检(not 白名单.has(地法术.id),
		"普通法术行动的白名单不应包含地系法术牌（否则会按【圣盾】/【虚弱】等普通法术结算）")
	检(not 白名单.has(风法术.id),
		"普通法术行动的白名单不应包含风系法术牌（否则会按【圣盾】/【虚弱】等普通法术结算）")
	检(not 白名单.has(火攻击.id), "普通法术行动的白名单不应包含火系攻击牌")
	检(not 白名单.has(火法术.id), "普通法术行动的白名单不应包含不能当魔弹的法术牌")
	# 客户端行动命令：普通法术行动只亮【魔弹】；地/风系牌只在 10703 技能按钮里亮
	var 额外命令表: Array = 引擎.action_commands(1, GConst.ActionType.Magic, false, true, false, 10702)
	var 普通命令: Dictionary = 额外命令表[0] if not 额外命令表.is_empty() else {}
	检((普通命令.get("card_ids", []) as Array).has(魔弹牌.id),
		"10702 额外法术行动的普通出牌命令应亮出【魔弹】")
	检(not (普通命令.get("card_ids", []) as Array).has(地法术.id),
		"10702 额外法术行动的普通出牌命令不应点亮地系法术牌")
	检(not (普通命令.get("card_ids", []) as Array).has(风法术.id),
		"10702 额外法术行动的普通出牌命令不应点亮风系法术牌")
	检(not (普通命令.get("card_ids", []) as Array).has(地攻击.id),
		"10702 额外法术行动的普通出牌命令不应点亮地系攻击牌")
	var 相思命令: Dictionary = _取技能命令(额外命令表, 10703)
	检(not 相思命令.is_empty(), "10702 额外法术行动的命令表里应有 10703 技能按钮")
	检((相思命令.get("card_ids", []) as Array).has(地攻击.id), "10703 技能按钮应亮出地系攻击牌")
	检((相思命令.get("card_ids", []) as Array).has(地法术.id), "10703 技能按钮应亮出地系法术牌（可当魔弹）")
	检((相思命令.get("card_ids", []) as Array).has(风法术.id), "10703 技能按钮应亮出风系法术牌（可当魔弹）")
	# 引擎兜底：普通法术行动用地/风系牌一律驳回
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Magic, [魔弹牌.id], [2], 1, 10702)
		== GConst.GE_SUCCESS, "10702 的额外法术行动使用【魔弹】应通过引擎兜底校验")
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Magic, [地法术.id], [2], 1, 10702)
		!= GConst.GE_SUCCESS, "普通法术行动里用地系【圣盾】应被引擎驳回")
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Magic, [风法术.id], [2], 1, 10702)
		!= GConst.GE_SUCCESS, "普通法术行动里用风系【圣盾】应被引擎驳回")
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Magic, [地攻击.id], [2], 1, 10702)
		!= GConst.GE_SUCCESS, "普通法术行动里用地系攻击牌应被引擎驳回")
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Magic, [火法术.id], [2], 1, 10702)
		!= GConst.GE_SUCCESS, "10702 的额外法术行动使用非魔弹法术牌应被引擎驳回")
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Magic, [火法术.id], [2], 0, 0)
		== GConst.GE_SUCCESS, "普通法术行动不应受 10702 白名单限制")
	检(角色.extra_action_card_ids(10702, GConst.ActionType.Attack).is_empty(),
		"10702 只限制法术行动")
	检(角色.extra_action_card_ids(10704, GConst.ActionType.Magic).is_empty(),
		"10704 不应限制法术行动的出牌")
	玩家.hand_cards.clear()
	检(角色.extra_action_card_ids(10702, GConst.ActionType.Magic) == [GConst.手牌白名单_全禁],
		"一张能当魔弹的牌都没有时应下发全禁白名单")
	引擎.行动额外 = false
	引擎.行动额外来源 = 0

	# 真实额外行动阶段：地系【圣盾】当普通法术硬提交 → 引擎驳回、不放置、牌不离手；
	# 驳回后引擎把阶段重置成普通行动，10702 的「只能使用【魔弹】」仍要生效（p_before_magic 兜底）
	_重置战斗()
	_给牌(玩家, 地法术.id)
	_新一次攻击宣告()
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.WAIT,
		"主动攻击命中且有可当魔弹的牌时应问【虚荣掌握】")
	_应答([1])
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS, "发动【虚荣掌握】应授予额外法术行动")
	引擎._清空等待()
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎._await_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 10702,
		"10702 的额外行动应直接进入额外法术行动阶段（等待 %s / 额外 %s / 来源 %s）"
		% [str(引擎._await_id), str(引擎.行动额外), str(引擎.行动额外来源)])
	发送记录.clear()
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Magic, "action_id": 0, "src_id": 1,
		"card_ids": [地法术.id], "dst_ids": [2], "args": [],
	})
	检(not _找消息(GConst.Msg.ErrorInput, func(_数据: Dictionary) -> bool: return true).is_empty(),
		"10702 额外法术行动里把地系【圣盾】当普通法术打应被驳回")
	检(玩家.has_hand_card(地法术.id), "被驳回的地系【圣盾】不应离手")
	检(not 靶.check_basic_effect_name(GConst.CardName.Shield),
		"被驳回的地系【圣盾】不应放置成基础效果")
	# 驳回后引擎压回的是默认（普通）行动阶段：改包再提交一次也不许按【圣盾】结算
	发送记录.clear()
	检(引擎._await_id == 1, "驳回应重新进入行动询问（等待 %s）" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Magic, "action_id": 0, "src_id": 1,
		"card_ids": [地法术.id], "dst_ids": [2], "args": [],
	})
	检(not _找消息(GConst.Msg.ErrorInput, func(_数据: Dictionary) -> bool: return true).is_empty(),
		"驳回后重开的普通行动里再打地系【圣盾】也应被 10702 兜底驳回")
	检(玩家.has_hand_card(地法术.id), "兜底驳回后地系【圣盾】仍不应离手")
	检(not 靶.check_basic_effect_name(GConst.CardName.Shield), "兜底驳回后仍不应放置【圣盾】")

	# 真实额外行动阶段：10703 技能行动把地系法术牌当【魔弹】打出（技能行动走另一套白名单）
	_重置战斗()
	_给牌(玩家, 地法术.id)
	玩家.add_action(GConst.ActionType.Magic, 10702, true, true)
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎._await_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 10702,
		"10702 的额外行动应直接进入额外法术行动阶段")
	发送记录.clear()
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.MagicSkill, "action_id": 10703, "src_id": 1,
		"card_ids": [地法术.id], "dst_ids": [4], "args": [],
	})
	检(引擎._await_id == 4, "10703 在额外行动内打出地系牌后应等逆向对手应答（等待 %s）"
		% str(引擎._await_id))
	检(not 玩家.has_hand_card(地法术.id), "10703 打出的地系法术牌应离手")
	检(引擎.deck.discard.has(地法术.id), "10703 打出的地系法术牌应进弃牌堆")
	检(_播报次数(10703) == 1, "10703 在额外行动内应播报一次，实际 %d 次" % _播报次数(10703))
	检(_找消息(GConst.Msg.ErrorInput, func(_数据: Dictionary) -> bool: return true).is_empty(),
		"10703 在 10702 额外行动内不应被引擎驳回")
	检(_有视为魔弹(地法术.id, 魔弹牌.id),
		"地系法术牌当魔弹打出时应把 as_card_id 标成【魔弹】")
	var 技能魔弹: BattleEngine.SMissileAsk = _取魔弹询问()
	检(技能魔弹 != null and 技能魔弹.holder == 4, "10703 的魔弹应交给逆向对手 4")
	if 技能魔弹 != null:
		检(not 技能魔弹.post_dir, "地系牌当魔弹的逆向落点应沿 pre 方向传递")
	引擎.on_message(4, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 4,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(靶2.hand_cards.size() == BattleEngine.MISSILE_BASE_POINT,
		"10703 在额外行动内的 2 点魔弹应让 4 摸 2 张，实际 %d 张" % 靶2.hand_cards.size())

	# 完整流水线：真实攻击命中 → 发动 10702 → 额外法术行动 → 逆向打出魔弹
	_重置战斗()
	_给牌(玩家, 火攻击.id)
	_给牌(玩家, 魔弹牌.id)
	_给牌(玩家, 地攻击.id)
	_给牌(玩家, 地法术.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.Attack,
		{"card_ids": [火攻击.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(引擎._await_id == 2, "攻击宣告后应先等目标应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == 1, "命中后应问发动者是否发动【虚荣掌握】（等待 %s）" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 10702, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 10702,
		"发动【虚荣掌握】后应进入 10702 的额外法术行动（当前 %d / 额外 %s / 来源 %s）"
		% [引擎.current_id, str(引擎.行动额外), str(引擎.行动额外来源)])
	var 额外阶段: Dictionary = _取额外阶段()
	检(not 额外阶段.is_empty(), "【虚荣掌握】应进入额外行动阶段")
	检(int(额外阶段.get("允许", 0)) == GConst.ActionType.Magic, "【虚荣掌握】的额外行动应只允许法术")
	检(bool(额外阶段.get("可放弃", true)), "【虚荣掌握】的额外行动阶段应允许放弃")
	检(角色.has_missile_mastery(), "10702 的额外法术行动内应有临时【魔弹掌控】")
	检(角色.missile_targets(1) == [2, 4], "10702 的额外行动内左右两个对手都应能选")
	var 相思栏: Dictionary = _找技能(角色.available_skills(), 10703)
	检((相思栏.get("targets", []) as Array).has(4),
		"10702 的额外行动里 10703 的落点应包含逆向对手")
	var 额外命令: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 行动命令: Dictionary = 额外命令[0] if not 额外命令.is_empty() else {}
	检(bool(行动命令.get("is_extra", false)), "额外法术行动的命令应标记 is_extra")
	检(int(行动命令.get("extra_cause", 0)) == 10702, "额外法术行动的来源应是 10702")
	检((行动命令.get("card_ids", []) as Array).has(魔弹牌.id), "额外法术行动的牌表应包含【魔弹】")
	检(not (行动命令.get("card_ids", []) as Array).has(地攻击.id),
		"额外法术行动的普通牌表不应包含地系攻击牌（只能走 10703 技能）")
	检(not (行动命令.get("card_ids", []) as Array).has(地法术.id),
		"额外法术行动的普通牌表不应包含地系法术牌（不能按【圣盾】结算）")
	# 逆向打出魔弹：落点选 4（逆向），传递状态应记录 post_dir=false
	发送记录.clear()
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Magic, "action_id": 0, "src_id": 1,
		"card_ids": [魔弹牌.id], "dst_ids": [4], "args": [],
	})
	检(引擎._await_id == 4, "逆向打出魔弹后应等逆向那个对手应答（等待 %s）" % str(引擎._await_id))
	检(not _取询问(4, GConst.RespondType.Bullet).is_empty(), "没有向逆向对手下发魔弹传递询问")
	var 魔弹询问: BattleEngine.SMissileAsk = _取魔弹询问()
	检(魔弹询问 != null, "逆向打出魔弹后状态栈里没有魔弹传递询问")
	if 魔弹询问 != null:
		检(魔弹询问.holder == 4, "逆向魔弹的持有者应是 4，实际 %d" % 魔弹询问.holder)
		检(not 魔弹询问.post_dir, "10702 的逆向落点应让魔弹沿 pre 方向传递")
		检(魔弹询问.point == BattleEngine.MISSILE_BASE_POINT, "初始魔弹伤害应为 2 点")
	引擎.on_message(4, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 4,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(靶2.hand_cards.size() == BattleEngine.MISSILE_BASE_POINT,
		"逆向魔弹的 2 点法术伤害应落在 4 身上（摸 2 张），实际 %d 张" % 靶2.hand_cards.size())
	检(靶.hand_cards.size() == BattleEngine.ATTACK_BASE_POINT,
		"逆向魔弹不应打到原本命中的目标 2（只吃攻击伤害摸 2 张），实际 %d 张" % 靶.hand_cards.size())

	# ============================================================
	# 10704 嫉妒追放
	# ============================================================
	# 攻击行动结束：问是否发动；取消不付费
	_重置战斗()
	玩家.set_crystal(1)
	_给牌(玩家, 火攻击.id)
	_补法术牌(靶, 2)
	var 追放上下文: Dictionary = {"player": 1, "kind": "attack"}
	发送记录.clear()
	检(角色.p_action_end(追放上下文) == BattleRole.WAIT, "攻击行动结束且有能量时应问【嫉妒追放】")
	检(not _取询问(1, 10704).is_empty(), "没有下发【嫉妒追放】询问")
	_应答([0])
	检(角色.p_action_end(追放上下文) == BattleRole.SUCCESS, "不发动【嫉妒追放】应直接收尾")
	检(玩家.get_energy() == 1, "不发动【嫉妒追放】不应支付能量")
	检(not _有额外行动(10704), "不发动【嫉妒追放】不应给额外攻击行动")

	# 发动：支付 1 能量 → 额外 +1 攻击行动，目标限制生效
	# （每次行动结束是一份新的 ctx：上一次「不发动」已经把那份 ctx 标成已处理）
	var 追放上下文2: Dictionary = {"player": 1, "kind": "attack"}
	发送记录.clear()
	检(角色.p_action_end(追放上下文2) == BattleRole.WAIT, "攻击行动结束且有能量时应问【嫉妒追放】")
	_应答([1])
	检(角色.p_action_end(追放上下文2) == BattleRole.SUCCESS, "发动【嫉妒追放】后应正常收尾")
	检(玩家.get_energy() == 0, "【嫉妒追放】应支付 1 点能量，实际剩 %d" % 玩家.get_energy())
	检(_有额外行动(10704), "【嫉妒追放】应额外 +1 攻击行动")
	检(_播报次数(10704) == 1, "【嫉妒追放】发动应播报一次，实际 %d 次" % _播报次数(10704))
	# 支付后应立即补一次对局快照（7504 / 4504 同口径）：客户端能量显示不能滞后到下一次快照
	var 支付快照: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Game:
			continue
		for info: Dictionary in (r.get("data", {}) as Dictionary).get("player_infos", []):
			var 能量: int = int(info.get("gem", 0)) + int(info.get("crystal", 0))
			if int(info.get("id", -1)) == 1 and 能量 == 0:
				支付快照 = r.get("data", {})
				break
		if not 支付快照.is_empty():
			break
	检(not 支付快照.is_empty(),
		"【嫉妒追放】支付 1 能量后应立刻补发对局快照（快照里的能量应是扣除后的 0）")
	检(角色.extra_action_targets(10704) == [2],
		"【嫉妒追放】的目标应只有手牌数大于你的对手：%s" % str(角色.extra_action_targets(10704)))
	引擎.行动额外 = true
	引擎.行动额外来源 = 10704
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Attack, [火攻击.id], [2], 1, 10704)
		== GConst.GE_SUCCESS, "【嫉妒追放】的额外攻击打手牌更多的对手应通过")
	检(引擎.校验额外行动限制(玩家, GConst.ActionType.Attack, [火攻击.id], [3], 1, 10704)
		!= GConst.GE_SUCCESS, "【嫉妒追放】的额外攻击不能打队友")
	引擎.行动额外 = false
	引擎.行动额外来源 = 0

	# 回合限定：本回合发动过就不再问；新回合重置
	玩家.set_crystal(1)
	发送记录.clear()
	检(角色.p_action_end({"player": 1, "kind": "attack"}) == BattleRole.SUCCESS,
		"回合限定：本回合发动过【嫉妒追放】后不应再询问")
	检(_询问次数(1, 10704) == 0, "回合限定期间不应下发 10704 询问")
	角色.p_before_turn_begin({})
	检(角色.p_action_end({"player": 1, "kind": "attack"}) == BattleRole.WAIT,
		"新回合应重新可以发动【嫉妒追放】")
	引擎._清空等待()

	# 法术行动结束也触发；特殊行动 / 别人的行动不触发
	_重置战斗()
	玩家.set_crystal(1)
	_给牌(玩家, 火攻击.id)
	_补法术牌(靶, 2)
	检(角色.p_action_end({"player": 1, "kind": "magic"}) == BattleRole.WAIT,
		"法术行动结束也应可以发动【嫉妒追放】")
	引擎._清空等待()
	_重置战斗()
	玩家.set_crystal(1)
	_给牌(玩家, 火攻击.id)
	_补法术牌(靶, 2)
	发送记录.clear()
	检(角色.p_action_end({"player": 1, "kind": "special"}) == BattleRole.SUCCESS,
		"特殊行动结束不应触发【嫉妒追放】")
	检(角色.p_action_end({"player": 2, "kind": "attack"}) == BattleRole.SUCCESS,
		"别人的攻击行动结束不应触发【嫉妒追放】")
	检(_询问次数(1, 10704) == 0, "特殊 / 别人的行动不应下发 10704 询问")

	# 没有能量 / 没有手牌更多的对手：不问
	_重置战斗()
	_给牌(玩家, 火攻击.id)
	_补法术牌(靶, 2)
	检(角色.p_action_end({"player": 1, "kind": "attack"}) == BattleRole.SUCCESS,
		"没有能量时不应询问【嫉妒追放】")
	玩家.set_crystal(1)
	靶.hand_cards.clear()
	检(角色.p_action_end({"player": 1, "kind": "attack"}) == BattleRole.SUCCESS,
		"没有手牌数大于你的对手时不应询问【嫉妒追放】")
	检(角色.extra_action_targets(10704) == [-1],
		"没有合法目标时应下发占位 -1，避免空表被当成不限制")
	检(角色.extra_action_targets(10702).is_empty(), "10704 的目标限制不应影响别的额外行动")

	# 完整流水线：真实攻击结束 → 发动 10704 → 额外攻击行动（目标白名单）→ 额外攻击结算
	_重置战斗()
	玩家.set_crystal(1)
	_给牌(玩家, 火攻击.id)
	_给牌(玩家, 副攻击.id)
	_补法术牌(靶, 2)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.Attack,
		{"card_ids": [火攻击.id], "dst_ids": [2], "args": []})
	引擎.run()
	检(引擎._await_id == 2, "攻击宣告后应先等目标应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == 1, "攻击行动结束后应问是否发动【嫉妒追放】（等待 %s）" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 10704, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 10704,
		"发动【嫉妒追放】后应进入 10704 的额外攻击行动（当前 %d / 额外 %s / 来源 %s）"
		% [引擎.current_id, str(引擎.行动额外), str(引擎.行动额外来源)])
	var 追放阶段: Dictionary = _取额外阶段()
	检(not 追放阶段.is_empty(), "【嫉妒追放】应进入额外行动阶段")
	检(int(追放阶段.get("允许", 0)) == GConst.ActionType.Attack, "【嫉妒追放】的额外行动应只允许攻击")
	var 追放命令: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 追放首条: Dictionary = 追放命令[0] if not 追放命令.is_empty() else {}
	检((追放首条.get("dst_ids", []) as Array).has(2),
		"额外攻击行动的命令应把合法目标 2 下发给客户端")
	# 额外攻击：打手牌更多的对手 2，正常结算
	检(玩家.has_hand_card(副攻击.id), "额外攻击阶段手里应还有第二张攻击牌")
	if 玩家.has_hand_card(副攻击.id):
		引擎.resolve_action(GConst.ActionType.Attack,
			{"card_ids": [副攻击.id], "dst_ids": [2], "args": []})
		引擎.run()
		检(引擎._await_id == 2, "额外攻击宣告后应等目标应战（等待 %s）" % str(引擎._await_id))
		发送记录.clear()
		引擎.on_message(2, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.ReplyAttack, "src_id": 2,
			"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
		})
		检(_询问次数(1, 10704) == 0, "同一回合的额外攻击结束不应再次询问【嫉妒追放】")

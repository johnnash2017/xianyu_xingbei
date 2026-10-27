extends 自检用例
## R47 爆食少女（47）：4701 甜点冲击 / 4702 食欲的黑洞 / 4703 美味融合 /
## 4704 三秒原则 / 4705 美食风暴。
##
## 任务范围只有 role + test：角色表「脚本 / 启用」列留给 DATA，用例里手动挂角色脚本。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 五颗技能行 / 技能说明 / 脚本文件 / 无指示物；
##   - 4701：技能栏（牌表 / 目标 / 置灰）、发动牌与两名目标的校验（含重复 / 队友 / 不存在）、
##            完整结算：弃发动牌【展示】+ 战绩区 +1 宝石 → 逐个问目标弃法术牌 →
##            不弃者各 2 点法术伤害 + 你各弃 1 张（手牌不足时不问、直接弃现有的）；
##            目标弃 / 取消 / 硬提交非法牌 / 没有法术牌四种边界，两人都弃时不惩罚；
##   - 4702：敌方受伤 / 自己受伤 / 没【魔弹】/ 0 点伤害都不问；队友受伤时先问；
##            取消不转移；发动时弃【魔弹】【展示】并改 harm.dst、带 redirect_from 与免士气；
##            硬提交非法牌不转移；同一次伤害只问一次；完整伤害流水线：转移后由自己摸牌、
##            超限不掉士气、原目标不摸牌；
##   - 4703：水系 / 火系牌可当【魔弹】响应传递（v_remissile），地 / 雷 / 攻击牌不行；
##            不提供主动使用入口（A21）；真实魔弹传递链：水牌传递成功并按 4703 播报，
##            地牌传递被拒后按放弃承受结算；
##   - 4704：wants_before_discard 的同步预判（队友 / 手牌 / 盖牌 / 正面朝上 / 非魔弹 /
##            没有代价牌 / 敌方 / 自己 / 已被认领）；真实拦截：弃 1 张牌获得魔弹、
##            拒绝 / 交不出代价 / 多张魔弹取第一张 / 盖牌来源；
##   - 4705：技能栏与校验（真宝石、恰好 2 名不同对手、不能用水晶顶）、完整结算（扣宝石、
##            两目标各 2 点法术伤害）。
##
## 4701~4705 的提示列目前为空（DATA 任务补齐），用例不依赖提示文案。
## 4701 的逐目标流程走自定义钩子 p_tian_dian_ask，这里按真实引擎入口驱动。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_baoshishaonv.gd")


## 测试驱动：在引擎推进中调用 to_discard（只有 run 内才走弃牌前拦截分支）
class 触发弃牌:
	extends RefCounted

	var 牌表: Array
	var 上下文: Dictionary

	func _init(cards: Array, ctx: Dictionary) -> void:
		牌表 = cards
		上下文 = ctx

	func handle(e: BattleEngine) -> int:
		e.to_discard(牌表, 上下文)
		return BattleEngine.CONTINUE


var 引擎: BattleEngine = null
var 玩家1: BattlePlayer = null   # 47 爆食少女（蓝）
var 玩家2: BattlePlayer = null   # 队友（蓝）
var 玩家3: BattlePlayer = null   # 对手甲（红）
var 玩家4: BattlePlayer = null   # 对手乙（红）
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 魔弹: GCard = null
var 魔弹2: GCard = null
var 水法术: GCard = null
var 水法术2: GCard = null
var 火法术: GCard = null
var 地法术: GCard = null
var 雷法术: GCard = null
var 攻击牌: GCard = null
var 攻击牌2: GCard = null
var 普通牌: GCard = null
var 普通牌2: GCard = null


func _init() -> void:
	名称 = "爆食少女"


# ============================================================
# 取样 / 查消息
# ============================================================
## 卡库里第一张满足条件的非虚拟牌（可用排除表避开已取过的牌号）
func _取牌(条件: Callable, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
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


## 某技能号播报过几次
func _播报次数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Skill:
			continue
		if int((r.get("data", {}) as Dictionary).get("skill_id", 0)) == 技能号:
			n += 1
	return n


## 发送记录里有没有「把这张牌【展示】给所有人」的广播
func _有展示(cid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Card:
			continue
		var 数据: Dictionary = r.get("data", {})
		if int(数据.get("type", 0)) == GConst.CardMsgType.Show 				and (数据.get("card_ids", []) as Array).has(cid):
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


## 状态栈里找一条指定持有者的魔弹传递询问（找不到返回 null）
func _找魔弹询问(holder: int) -> BattleEngine.SMissileAsk:
	for st: Variant in 引擎._states:
		if st is BattleEngine.SMissileAsk and int(st.get("holder")) == holder:
			return st as BattleEngine.SMissileAsk
	return null


## 直接调用角色钩子时预置一份回复（对应玩家在客户端点了确定）
func _应答(args: Array, cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": []}
	引擎._has_reply = true


func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("pid", -1)) == pid and int(r.get("msg", 0)) == GConst.Msg.ErrorInput:
			return true
	return false


# ============================================================
# 战斗重置 / 上下文
# ============================================================
func _清空玩家(p0: BattlePlayer) -> void:
	p0.hand_cards.clear()
	p0.cover_cards.clear()
	p0.basic_effects.clear()
	p0.additional_actions.clear()
	p0.cross_num = 0
	p0.set_gem(0)
	p0.set_crystal(0)
	p0.reset_action_counts()
	p0.boot_skill_used = false


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
	引擎.deck.discard.clear()
	引擎.last_harm_cause = 0
	引擎.last_harm_type = 0
	引擎.team_gem = [0, 0]
	引擎.team_crystal = [0, 0]
	引擎.team_morale = [10, 10]
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		if p0 != null:
			_清空玩家(p0)
	角色._4701阶段 = 0
	角色._4701目标.clear()
	角色._4701下标 = 0
	角色._4701不弃.clear()


## 直接跑一次伤害（走完整流水线）
func _跑伤害(src: int, dst: int, point: int, htype: int = GConst.HarmType.Attack) -> void:
	引擎.push_harm({
		"src": src, "dst": dst, "point": point,
		"cause": GConst.CAUSE_ATTACK if htype == GConst.HarmType.Attack else GConst.CAUSE_MISSILE,
		"type": htype, "is_active": true,
	})
	引擎.run()


## 解析一次超限弃牌询问：从玩家手里挑 数量 张交给引擎
func _交超限牌(pid: int, 数量: int) -> Array:
	var p0: BattlePlayer = 引擎.p(pid)
	var 牌: Array = []
	if p0 == null:
		return 牌
	for i: int in range(mini(数量, p0.hand_cards.size())):
		牌.append(p0.hand_cards[i])
	if 引擎._await_id == pid:
		引擎.on_message(pid, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.Discard, "src_id": pid,
			"args": [数量, GConst.CAUSE_OVERLOAD, 数量],
			"card_ids": 牌, "dst_ids": [pid],
		})
	return 牌


func _甜点动作(cid: int, dsts: Array) -> Dictionary:
	return {"src_id": 1, "action_id": 4701, "card_ids": [cid], "dst_ids": dsts}


func _美食动作(dsts: Array) -> Dictionary:
	return {"src_id": 1, "action_id": 4705, "card_ids": [], "dst_ids": dsts}


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	_准备()

	_测试数据()
	if 失败.size() > 0:
		return
	_建引擎()
	_测试4701()
	_测试4702()
	_测试4703()
	_测试4704()
	_测试4705()

	# 收尾：清掉状态栈与等待、解绑角色，避免退出时残留询问 / 对象
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		if p0 != null:
			p0.role = null
	引擎 = null
	角色 = null
	玩家1 = null
	玩家2 = null
	玩家3 = null
	玩家4 = null


## 取牌 + 建数据前置；卡片缺失时直接记失败并让调用方收尾
func _准备() -> void:
	魔弹 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() == GConst.CardName.Missile)
	var 魔弹号: int = 魔弹.id if 魔弹 != null else -1
	魔弹2 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() == GConst.CardName.Missile, [魔弹号])
	水法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Water and c.card_name_enum() != GConst.CardName.Missile)
	var 水法术号: int = 水法术.id if 水法术 != null else -1
	水法术2 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Water and c.card_name_enum() != GConst.CardName.Missile, [水法术号])
	火法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Fire and c.card_name_enum() != GConst.CardName.Missile)
	地法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Earth and c.card_name_enum() != GConst.CardName.Missile)
	雷法术 = _取牌(func(c: GCard) -> bool: return c.is_magic() and c.element_enum() == GConst.CardElement.Thunder and c.card_name_enum() != GConst.CardName.Missile)
	攻击牌 = _取牌(func(c: GCard) -> bool: return c.is_attack())
	var 攻击号: int = 攻击牌.id if 攻击牌 != null else -1
	攻击牌2 = _取牌(func(c: GCard) -> bool: return c.is_attack(), [攻击号])
	普通牌 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() != GConst.CardName.Missile)
	var 普通号: int = 普通牌.id if 普通牌 != null else -1
	普通牌2 = _取牌(func(c: GCard) -> bool: return c.card_name_enum() != GConst.CardName.Missile, [普通号])
	检(魔弹 != null and 魔弹2 != null, "卡库里找不到两张【魔弹】")
	检(水法术 != null and 水法术2 != null, "卡库里找不到两张非魔弹的水系法术牌")
	检(火法术 != null, "卡库里找不到非魔弹的火系法术牌")
	检(地法术 != null, "卡库里找不到非魔弹的地系法术牌")
	检(雷法术 != null, "卡库里找不到非魔弹的雷系法术牌")
	检(攻击牌 != null and 攻击牌2 != null, "卡库里找不到两张攻击牌")
	检(普通牌 != null and 普通牌2 != null, "卡库里找不到两张普通牌")


## 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 / 无指示物
func _测试数据() -> void:
	检(str(Data.role_list.get(47, "")) == "爆食少女", "47 号角色名不是「爆食少女」")
	检(Data.role_personal_name(47) == "妮亚", "47 号角色姓名不是「妮亚」")
	检(absf(Data.role_star(47) - 3.0) < 0.01, "爆食少女应是 3.0 星，实际 %s" % str(Data.role_star(47)))
	检(Data.role_skills(47) == [4701, 4702, 4703, 4704, 4705],
		"爆食少女技能号不对：%s" % str(Data.role_skills(47)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_baoshishaonv.gd"),
		"爆食少女的角色脚本文件不存在")
	for 技能号: int in [4701, 4702, 4703, 4704, 4705]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	检(GConst.技能号("技能#爆食少女#甜点冲击") == 4701, "【甜点冲击】技能号应为 4701")
	检(GConst.技能号("技能#爆食少女#食欲的黑洞") == 4702, "【食欲的黑洞】技能号应为 4702")
	检(GConst.技能号("技能#爆食少女#美味融合") == 4703, "【美味融合】技能号应为 4703")
	检(GConst.技能号("技能#爆食少女#三秒原则") == 4704, "【三秒原则】技能号应为 4704")
	检(GConst.技能号("技能#爆食少女#美食风暴") == 4705, "【美食风暴】技能号应为 4705")
	var 技能说明: String = Data.role_skill_info(47)
	for 技能名: String in ["甜点冲击", "食欲的黑洞", "美味融合", "三秒原则", "美食风暴"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])
	检(Data.role_token_def(47, 0).is_empty() and Data.role_token_def(47, 1).is_empty()
		and Data.role_token_def(47, 2).is_empty(), "爆食少女不应配置指示物 / 盖牌槽")


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "爆食")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({})
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	玩家3 = 引擎.p(3)
	玩家4 = 引擎.p(4)
	玩家1.role_id = 47
	角色 = 角色脚本.new()
	角色.setup(玩家1, 引擎)
	玩家1.role = 角色
	检(引擎.p(1) != null and 引擎.p(1).role == 角色, "47 的角色脚本没挂上")
	_重置战斗()


# ============================================================
# 4701 甜点冲击
# ============================================================
func _测试4701() -> void:
	# ---- 技能栏：两张法术技能都常驻下发，条件不满足只置灰 ----
	_重置战斗()
	var 栏: Array = 角色.available_skills()
	检(栏.size() == 2, "爆食少女技能栏只应有 4701 / 4705 两项，实际 %d 项：%s" % [栏.size(), str(栏)])
	var 甜点项: Dictionary = _找技能(栏, 4701)
	检(not 甜点项.is_empty(), "【甜点冲击】(4701) 应下发到技能栏")
	检(int(甜点项.get("type", 0)) == GConst.ActionType.MagicSkill, "4701 应作为法术技能按钮下发")
	检(int(甜点项.get("need_card", 0)) == 1 and int(甜点项.get("need_target", 0)) == 2,
		"4701 应要求 1 张发动牌 + 2 名目标")
	检(not bool(甜点项.get("enabled", true)), "手里没有法术牌时 4701 应置灰，不是消失")
	var 美食项: Dictionary = _找技能(栏, 4705)
	检(not 美食项.is_empty(), "【美食风暴】(4705) 应下发到技能栏")
	检(int(美食项.get("type", 0)) == GConst.ActionType.MagicSkill, "4705 应作为法术技能按钮下发")
	检(int(美食项.get("need_target", 0)) == 2, "4705 应要求 2 名目标")
	检(not bool(美食项.get("enabled", true)), "没有宝石时 4705 应置灰，不是消失")

	_给牌(玩家1, 火法术.id)
	甜点项 = _找技能(角色.available_skills(), 4701)
	检(bool(甜点项.get("enabled", false)), "有法术牌 + 2 名对手时 4701 应可点")
	检((甜点项.get("cards", []) as Array).has(火法术.id), "4701 的牌表应包含手里的法术牌")
	检((甜点项.get("targets", []) as Array) == [3, 4], "4701 的目标应只有两名对手：%s"
		% str(甜点项.get("targets", [])))
	玩家1.set_gem(1)
	美食项 = _找技能(角色.available_skills(), 4705)
	检(bool(美食项.get("enabled", false)), "有宝石 + 2 名对手时 4705 应可点")
	检((美食项.get("targets", []) as Array) == [3, 4], "4705 的目标应只有两名对手")

	# ---- 校验：发动牌 / 目标 ----
	var 合法: Dictionary = _甜点动作(火法术.id, [3, 4])
	检(角色.v_magic_skill(合法) == GConst.GE_SUCCESS, "合法的 4701 应通过校验")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 4701, "card_ids": [火法术.id], "dst_ids": [3, 4]})
		== GConst.GE_INVALID_PLAYERID, "别人的 4701 行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 4702, "card_ids": [火法术.id], "dst_ids": [3, 4]})
		== GConst.GE_INVALID_ACTION, "不是 4701 的法术技能行动不应通过校验")
	检(角色.v_magic_skill(_甜点动作(攻击牌.id, [3, 4])) == GConst.GE_INVALID_CARDID,
		"非法术牌不能作为 4701 的发动牌")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 4701, "card_ids": [], "dst_ids": [3, 4]})
		== GConst.GE_INVALID_CARDID, "4701 必须弃 1 张发动牌")
	检(角色.v_magic_skill(_甜点动作(火法术.id, [3])) == GConst.GE_INVALID_PLAYERID,
		"4701 必须恰好 2 名目标")
	检(角色.v_magic_skill(_甜点动作(火法术.id, [3, 4, 2])) == GConst.GE_INVALID_PLAYERID,
		"4701 不能有 3 名目标")
	检(角色.v_magic_skill(_甜点动作(火法术.id, [3, 3])) == GConst.GE_INVALID_PLAYERID,
		"4701 的两名目标不能重复")
	检(角色.v_magic_skill(_甜点动作(火法术.id, [2, 3])) == GConst.GE_INVALID_PLAYERID,
		"4701 不能指定队友")
	检(角色.v_magic_skill(_甜点动作(火法术.id, [3, 99])) == GConst.GE_INVALID_PLAYERID,
		"4701 不能指定不存在的玩家")

	# ---- 完整结算 1：目标甲弃、目标乙没有法术牌 → 乙吃 2 点，你弃 1 张 ----
	_重置战斗()
	_给牌(玩家1, 火法术.id)
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家3, 水法术.id)
	_给牌(玩家4, 攻击牌.id)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _甜点动作(火法术.id, [3, 4]))
	引擎.run()
	检(not 玩家1.has_hand_card(火法术.id), "4701 的发动牌应离手")
	检(引擎.deck.discard.has(火法术.id), "4701 的发动牌应进弃牌堆")
	检(引擎.team_gem[GConst.BLUE] == 1, "4701 应让我方战绩区 +1 宝石")
	检(_播报次数(4701) == 1, "4701 发动应播报一次，实际 %d 次" % _播报次数(4701))
	检(_有展示(火法术.id), "4701 的发动牌应【展示】给所有人")
	检(引擎._await_id == 3, "4701 应先问目标甲是否弃法术牌，实际等待 %s" % str(引擎._await_id))
	var 问甲: Dictionary = _取询问(3, 4701)
	检(not 问甲.is_empty(), "没有向目标甲下发 4701 弃牌询问")
	检(str(问甲.get("card_rule", "")) == "magic", "4701 的目标只能弃法术牌")
	检(bool(问甲.get("can_cancel", false)), "目标可以选不弃（吃 2 点伤害），询问应可取消")
	检((问甲.get("card_ids", []) as Array).has(水法术.id), "4701 的可点牌表应包含目标甲的法术牌")
	检(int(问甲.get("preview_base", 0)) == 2 and int(问甲.get("preview_kind", 0)) == GConst.HarmType.Magic
		and (问甲.get("preview_ids", []) as Array).has(3),
		"4701 应把 2 点法术伤害的提示下发给目标甲：%s" % str(问甲))
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 3, "args": [1], "card_ids": [水法术.id], "dst_ids": [],
	})
	检(not 玩家3.hand_cards.has(水法术.id), "目标甲弃出的法术牌应离手")
	检(引擎.deck.discard.has(水法术.id), "目标甲弃出的法术牌应进弃牌堆")
	# 目标乙没有法术牌：不问，直接进入「你弃 1 张」
	检(_询问次数(4, 4701) == 0, "目标乙没有法术牌时不应白问")
	检(引擎._await_id == 1, "有一名目标不弃时应让发动者弃 1 张牌，实际等待 %s" % str(引擎._await_id))
	var 问自己: Dictionary = _取询问(1, 4701)
	检(not 问自己.is_empty(), "没有向发动者下发 4701 弃牌询问")
	检(not bool(问自己.get("can_cancel", true)), "4701 的「你弃 1 张牌」是强制弃，取消应置灰")
	检(int((问自己.get("args", []) as Array)[0]) == 1, "目标乙不弃 → 你弃 1 张（不是 2 张）")
	检((问自己.get("card_ids", []) as Array).has(普通牌.id), "4701 的弃牌白名单应包含自己的手牌")
	检(_找伤害(4701, 4).is_empty(), "自己的弃牌还没结算前不应先压伤害")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 1, "args": [1], "card_ids": [普通牌.id], "dst_ids": [],
	})
	检(not 玩家1.has_hand_card(普通牌.id), "4701 让自己弃的牌应离手")
	检(引擎.deck.discard.has(普通牌.id), "4701 让自己弃的牌应进弃牌堆")
	# 回复后引擎会一路跑完伤害：目标乙原有 1 张牌 + 2 点伤害摸 2 张 = 3；目标甲已弃牌不受伤
	检(玩家4.hand_cards.size() == 3, "目标乙原有 1 张牌 + 2 点伤害摸 2 张 = 3，实际 %d"
		% 玩家4.hand_cards.size())
	检(玩家3.hand_cards.size() == 0, "目标甲已弃掉唯一的法术牌，不应再因伤害摸牌，实际 %d"
		% 玩家3.hand_cards.size())
	检(not _有错误输入(1), "4701 的完整流程不应给发动者发操作无效")

	# ---- 完整结算 2：两名目标都弃 → 不惩罚、不问自己弃牌 ----
	_重置战斗()
	_给牌(玩家1, 火法术.id)
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家3, 水法术.id)
	_给牌(玩家4, 地法术.id)
	引擎.resolve_action(GConst.ActionType.MagicSkill, _甜点动作(火法术.id, [3, 4]))
	引擎.run()
	检(引擎._await_id == 3, "两人都弃的场景应先问目标甲，实际等待 %s" % str(引擎._await_id))
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 3, "args": [1], "card_ids": [水法术.id], "dst_ids": [],
	})
	检(引擎._await_id == 4, "目标甲弃完后应接着问目标乙，实际等待 %s" % str(引擎._await_id))
	引擎.on_message(4, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 4, "args": [1], "card_ids": [地法术.id], "dst_ids": [],
	})
	检(not 玩家3.hand_cards.has(水法术.id) and not 玩家4.hand_cards.has(地法术.id),
		"两名目标弃出的法术牌都应离手")
	检(引擎.team_gem[GConst.BLUE] == 1, "两人都弃时我方仍应 +1 宝石")
	检(_找伤害(4701, 3).is_empty() and _找伤害(4701, 4).is_empty(),
		"两名目标都弃法术牌时不应造成伤害")
	检(_询问次数(1, 4701) == 0, "两名目标都弃时不应再问发动者弃牌")
	检(_播报次数(4701) == 1, "4701 应只播报一次")

	# ---- 完整结算 3：两人都没法术牌 → 直接问自己弃 2 张，然后各 2 点伤害 ----
	_重置战斗()
	_给牌(玩家1, 火法术.id)
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家1, 普通牌2.id)
	_给牌(玩家3, 攻击牌.id)
	_给牌(玩家4, 攻击牌2.id)
	引擎.resolve_action(GConst.ActionType.MagicSkill, _甜点动作(火法术.id, [3, 4]))
	引擎.run()
	检(_询问次数(3, 4701) == 0 and _询问次数(4, 4701) == 0,
		"两名目标都没有法术牌时不应下发弃牌询问")
	检(引擎._await_id == 1, "两人都弃不出时应让发动者弃 2 张，实际等待 %s" % str(引擎._await_id))
	var 问自己2: Dictionary = _取询问(1, 4701)
	检(not 问自己2.is_empty(), "两人都不弃时应向发动者下发弃牌询问")
	检(int((问自己2.get("args", []) as Array)[0]) == 2, "两名目标不弃 → 你应弃 2 张")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 1, "args": [1],
		"card_ids": [普通牌.id, 普通牌2.id], "dst_ids": [],
	})
	检(not 玩家1.has_hand_card(普通牌.id) and not 玩家1.has_hand_card(普通牌2.id),
		"两人都不弃时发动者应弃掉 2 张牌")
	# 回复后引擎会一路跑完两段伤害：两人各摸 2 张
	检(玩家3.hand_cards.size() == 3 and 玩家4.hand_cards.size() == 3,
		"两人各摸 2 张，手牌应为 1+2=3，实际 %d / %d" % [玩家3.hand_cards.size(), 玩家4.hand_cards.size()])

	# ---- 边界：目标取消（不弃）→ 直接结算惩罚 ----
	_重置战斗()
	_给牌(玩家1, 火法术.id)
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家3, 水法术.id)
	_给牌(玩家4, 攻击牌.id)
	引擎.resolve_action(GConst.ActionType.MagicSkill, _甜点动作(火法术.id, [3, 4]))
	引擎.run()
	检(引擎._await_id == 3, "取消场景应先问目标甲")
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 3, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(玩家3.hand_cards.has(水法术.id), "目标取消时不应弃掉法术牌")
	检(引擎._await_id == 1, "目标取消（不弃）后应问发动者弃 1 张，实际等待 %s" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 1, "args": [1], "card_ids": [普通牌.id], "dst_ids": [],
	})
	# 目标甲取消（不弃）、目标乙没有法术牌：两人各吃 2 点法术伤害（各摸 2 张）
	检(玩家3.hand_cards.size() == 3, "取消弃牌的目标应吃 2 点法术伤害并摸 2 张，实际 %d"
		% 玩家3.hand_cards.size())
	检(玩家4.hand_cards.size() == 3, "没有法术牌的目标应吃 2 点法术伤害并摸 2 张，实际 %d"
		% 玩家4.hand_cards.size())

	# ---- 边界：目标硬提交非法牌（不是法术牌）→ 按不弃处理 ----
	_重置战斗()
	_给牌(玩家1, 火法术.id)
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家3, 水法术.id)
	_给牌(玩家3, 攻击牌.id)
	_给牌(玩家4, 攻击牌2.id)
	引擎.resolve_action(GConst.ActionType.MagicSkill, _甜点动作(火法术.id, [3, 4]))
	引擎.run()
	检(引擎._await_id == 3, "非法牌场景应先问目标甲")
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 3, "args": [1], "card_ids": [攻击牌.id], "dst_ids": [],
	})
	检(玩家3.hand_cards.has(攻击牌.id) and 玩家3.hand_cards.has(水法术.id),
		"硬提交非法牌时目标的手牌不应离手")
	检(引擎._await_id == 1, "硬提交非法牌应按不弃处理并让发动者弃 1 张")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4701, "src_id": 1, "args": [1], "card_ids": [普通牌.id], "dst_ids": [],
	})
	# 目标甲按不弃处理：原有 2 张 + 摸 2 = 4；目标乙原有 1 张 + 摸 2 = 3
	检(玩家3.hand_cards.size() == 4, "硬提交非法牌的目标应吃 2 点法术伤害并摸 2 张，实际 %d"
		% 玩家3.hand_cards.size())
	检(玩家4.hand_cards.size() == 3, "没有法术牌的目标应吃 2 点法术伤害并摸 2 张，实际 %d"
		% 玩家4.hand_cards.size())

	# ---- 边界：自己手里没有别的牌 → 不白问，直接结算伤害 ----
	_重置战斗()
	_给牌(玩家1, 火法术.id)
	_给牌(玩家3, 攻击牌.id)
	_给牌(玩家4, 攻击牌2.id)
	引擎.resolve_action(GConst.ActionType.MagicSkill, _甜点动作(火法术.id, [3, 4]))
	引擎.run()
	检(_询问次数(1, 4701) == 0, "发动者没有别的牌可弃时不应再下发弃牌询问")
	检(引擎._await_id != 1, "发动者没有别的牌可弃时不应等待 1 号")
	检(玩家3.hand_cards.size() == 3 and 玩家4.hand_cards.size() == 3,
		"发动者没有别的牌可弃时仍应结算两名目标的伤害（各摸 2 张），实际 %d / %d"
		% [玩家3.hand_cards.size(), 玩家4.hand_cards.size()])


# ============================================================
# 4702 食欲的黑洞
# ============================================================
func _伤害(src: int, dst: int, point: int = 2, htype: int = GConst.HarmType.Attack) -> Dictionary:
	return {
		"src": src, "dst": dst, "point": point,
		"cause": GConst.CAUSE_ATTACK if htype == GConst.HarmType.Attack else GConst.CAUSE_MISSILE,
		"type": htype, "is_active": true,
	}


func _测试4702() -> void:
	# ---- 敌方受伤 / 自己受伤 / 没魔弹 / 0 点伤害：都不问 ----
	_重置战斗()
	_给牌(玩家1, 魔弹.id)
	检(角色.p_timeline_6({"harm": _伤害(3, 3)}) == BattleRole.SUCCESS, "敌方受伤不应触发 4702")
	检(_询问次数(1, 4702) == 0, "敌方受伤不应下发 4702 询问")
	检(角色.p_timeline_6({"harm": _伤害(3, 1)}) == BattleRole.SUCCESS, "自己受伤时不应触发 4702")
	检(_询问次数(1, 4702) == 0, "自己受伤不应下发 4702 询问")
	var 零伤害: Dictionary = _伤害(3, 2, 0)
	检(角色.p_timeline_6({"harm": 零伤害}) == BattleRole.SUCCESS, "0 点伤害不应触发 4702")
	检(_询问次数(1, 4702) == 0, "0 点伤害不应下发 4702 询问")
	_重置战斗()
	_给牌(玩家1, 火法术.id)
	检(角色.p_timeline_6({"harm": _伤害(3, 2)}) == BattleRole.SUCCESS,
		"手里没有【魔弹】时不应触发 4702")
	检(_询问次数(1, 4702) == 0, "手里没有【魔弹】时不应下发 4702 询问")

	# ---- 取消：不弃牌、不转移 ----
	_重置战斗()
	_给牌(玩家1, 魔弹.id)
	_给牌(玩家1, 普通牌.id)
	var 取消伤害: Dictionary = _伤害(3, 2)
	var 取消ctx: Dictionary = {"harm": 取消伤害}
	检(角色.p_timeline_6(取消ctx) == BattleRole.WAIT, "队友受伤且有【魔弹】时应先问是否发动 4702")
	var 取消问: Dictionary = _取询问(1, 4702)
	检(not 取消问.is_empty(), "没有向 47 下发 4702 询问")
	检((取消问.get("card_ids", []) as Array) == [魔弹.id], "4702 只应让【魔弹】可点")
	检(bool(取消问.get("can_cancel", false)), "4702 是响应技能，应可取消")
	检(int(取消问.get("preview_base", 0)) == 2 and int(取消问.get("preview_kind", 0)) == GConst.HarmType.Attack
		and (取消问.get("preview_ids", []) as Array).has(1),
		"4702 应把本次伤害与转移后的目标下发给客户端：%s" % str(取消问))
	_应答([0])
	检(角色.p_timeline_6(取消ctx) == BattleRole.SUCCESS, "取消 4702 应直接收尾")
	检(int(取消伤害.get("dst", -1)) == 2, "取消 4702 不应改动伤害目标")
	检(not bool(取消伤害.get("no_morale", false)), "取消 4702 不应带免士气标记")
	检(玩家1.has_hand_card(魔弹.id), "取消 4702 不应弃掉魔弹")
	检(_播报次数(4702) == 0, "取消 4702 不应播报")

	# ---- 发动：弃魔弹【展示】→ 转移给自己、带 redirect_from 与免士气 ----
	_重置战斗()
	_给牌(玩家1, 魔弹.id)
	_给牌(玩家1, 普通牌.id)
	发送记录.clear()
	var 转移伤害数据: Dictionary = _伤害(3, 2)
	var 转移ctx: Dictionary = {"harm": 转移伤害数据}
	检(角色.p_timeline_6(转移ctx) == BattleRole.WAIT, "发动前应先问 4702")
	_应答([1], [魔弹.id])
	检(角色.p_timeline_6(转移ctx) == BattleRole.URGENT,
		"发动 4702 后应压入展示 / 弃牌状态并挂起")
	检(not 玩家1.has_hand_card(魔弹.id), "4702 的【魔弹】应离手")
	检(引擎.deck.discard.has(魔弹.id), "4702 的【魔弹】应进弃牌堆")
	检(int(转移伤害数据.get("dst", -1)) == 1, "4702 应把伤害目标改到自己身上")
	检(int(转移伤害数据.get("redirect_from", -1)) == 2, "4702 应记录原目标（redirect_from）")
	检(bool(转移伤害数据.get("no_morale", false)), "4702 应声明本次伤害不因超限掉士气")
	检(_播报次数(4702) == 1, "4702 发动应播报一次，实际 %d 次" % _播报次数(4702))
	检(_有展示(魔弹.id), "4702 弃掉的【魔弹】应【展示】给所有人")
	# 同一次伤害只问一次（再回到本钩子时靠 ctx 里的进度挡住）
	_重置战斗()
	_给牌(玩家1, 魔弹.id)
	var 重入伤害: Dictionary = _伤害(3, 2)
	var 重入ctx: Dictionary = {"harm": 重入伤害}
	角色.p_timeline_6(重入ctx)
	_应答([1], [魔弹.id])
	角色.p_timeline_6(重入ctx)
	检(角色.p_timeline_6(重入ctx) == BattleRole.SUCCESS, "同一次伤害转移完后不应再问第二次")
	检(_询问次数(1, 4702) == 1, "同一次伤害只应问一次 4702，实际 %d 次" % _询问次数(1, 4702))

	# ---- 边界：硬提交非法牌（不是魔弹）→ 不转移、牌不离手 ----
	_重置战斗()
	_给牌(玩家1, 魔弹.id)
	_给牌(玩家1, 攻击牌.id)
	var 非法伤害: Dictionary = _伤害(3, 2)
	var 非法ctx: Dictionary = {"harm": 非法伤害}
	角色.p_timeline_6(非法ctx)
	_应答([1], [攻击牌.id])
	检(角色.p_timeline_6(非法ctx) == BattleRole.SUCCESS, "硬提交非法牌时 4702 应直接收尾")
	检(int(非法伤害.get("dst", -1)) == 2, "硬提交非法牌不应转移伤害")
	检(玩家1.has_hand_card(攻击牌.id), "硬提交的非法牌不应离手")
	检(玩家1.has_hand_card(魔弹.id), "硬提交非法牌时【魔弹】应留在手里")

	# ---- 完整伤害流水线：转移后自己摸 4 张、超限弃牌但不掉士气，原目标不摸牌 ----
	_重置战斗()
	_给牌(玩家1, 魔弹.id)
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家1, 普通牌2.id)
	_给牌(玩家1, 攻击牌.id)
	_给牌(玩家2, 普通牌.id)
	_给牌(玩家2, 普通牌2.id)
	_给牌(玩家2, 攻击牌.id)
	_给牌(玩家2, 攻击牌2.id)
	_跑伤害(3, 2, 4)
	检(引擎._await_id == 1, "转移后应由 47 自己结算，实际等待 %s" % str(引擎._await_id))
	检(not _取询问(1, 4702).is_empty(), "完整流水线没有下发 4702 询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4702, "src_id": 1, "args": [1], "card_ids": [魔弹.id], "dst_ids": [],
	})
	# 转移后自己摸 4 张：剩 3 张 + 4 = 7 → 超限弃 1 张（不掉士气）
	检(引擎._await_id == 1, "转移后 47 手牌超限，应等自己选弃 1 张，实际等待 %s" % str(引擎._await_id))
	_交超限牌(1, 1)
	检(玩家1.hand_cards.size() == 6, "转移后 47 应摸 4 弃 1，手牌 6，实际 %d" % 玩家1.hand_cards.size())
	检(玩家2.hand_cards.size() == 4, "原目标不应再摸牌 / 弃牌，手牌应保持 4，实际 %d"
		% 玩家2.hand_cards.size())
	检(int(引擎.team_morale[GConst.BLUE]) == 10,
		"4702 的免士气应让本次超限不扣士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))


# ============================================================
# 4703 美味融合
# ============================================================
func _测试4703() -> void:
	_重置战斗()
	_给牌(玩家1, 水法术.id)
	_给牌(玩家1, 火法术.id)
	_给牌(玩家1, 魔弹.id)
	_给牌(玩家1, 地法术.id)
	_给牌(玩家1, 雷法术.id)
	_给牌(玩家1, 攻击牌.id)
	检(角色.missile_fusion_elements() == [GConst.CardElement.Water, GConst.CardElement.Fire],
		"4703 的魔弹材料应是水 / 火：%s" % str(角色.missile_fusion_elements()))
	检(int(角色.missile_fusion_skill()) == 4703, "4703 的传递播报号应为 4703，不借用 803 / 7602")
	检(角色.v_remissile(水法术.id) == GConst.GE_SUCCESS, "水系牌应能继续传递魔弹")
	检(角色.v_remissile(火法术.id) == GConst.GE_SUCCESS, "火系牌应能继续传递魔弹")
	检(角色.v_remissile(魔弹.id) == GConst.GE_SUCCESS, "【魔弹】本体应能继续传递")
	检(角色.v_remissile(地法术.id) != GConst.GE_SUCCESS, "地系牌不能继续传递魔弹")
	检(角色.v_remissile(雷法术.id) != GConst.GE_SUCCESS, "雷系牌不能继续传递魔弹")
	检(角色.v_remissile(攻击牌.id) != GConst.GE_SUCCESS, "攻击牌不能继续传递魔弹")
	检(角色.v_remissile(水法术2.id) != GConst.GE_SUCCESS, "不在手里的牌不能继续传递魔弹")
	# 4703 只扩展「响应传递」：不提供主动使用入口（A21），也不覆写 v_missile
	检(角色.v_missile(水法术.id, 3) == BattleRole.V_NOT_OVERRIDE,
		"4703 不应把水系牌扩展成可以主动使用（A21）")
	检(_找技能(角色.available_skills(), 4703).is_empty(), "4703 不应出现在技能栏里")

	# ---- 真实魔弹传递链：水牌可以继续传递，按 4703 播报 ----
	_重置战斗()
	_给牌(玩家1, 水法术.id)
	发送记录.clear()
	# 1 号是当前持有者（被 3 号打出的魔弹指向），本轮已参与过 3 / 1
	引擎.push(BattleEngine.SMissileAsk.new(1, 3, 2, true, [3, 1]))
	引擎.run()
	检(引擎._await_id == 1, "魔弹传递应先问持有者 1，实际等待 %s" % str(引擎._await_id))
	检(not _取询问(1, GConst.RespondType.Bullet).is_empty(), "没有下发魔弹传递询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 1,
		"args": [GConst.Reattack.Attack], "card_ids": [水法术.id], "dst_ids": [],
	})
	检(not 玩家1.has_hand_card(水法术.id), "继续传递打出的水系牌应离手")
	检(引擎.deck.discard.has(水法术.id), "继续传递打出的水系牌应进弃牌堆")
	检(_播报次数(4703) == 1, "用水系牌传递应播报 4703，实际 %d 次" % _播报次数(4703))
	var 下一问: BattleEngine.SMissileAsk = _找魔弹询问(4)
	检(下一问 != null, "水系牌传递后应把魔弹交给下一个对手（4 号）")
	if 下一问 != null:
		检(int(下一问.point) == 3, "魔弹每传递一次伤害 +1，应为 3 点，实际 %d" % int(下一问.point))
	# 4 号放弃承受：3 点法术伤害 → 摸 3 张
	检(引擎._await_id == 4, "传递后应等 4 号决定是否继续，实际等待 %s" % str(引擎._await_id))
	引擎.on_message(4, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 4,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(玩家4.hand_cards.size() == 3, "4 号承受 3 点魔弹伤害应摸 3 张，实际 %d" % 玩家4.hand_cards.size())

	# ---- 地系牌不能继续传递：按放弃承受结算，牌留在手里 ----
	_重置战斗()
	_给牌(玩家1, 地法术.id)
	发送记录.clear()
	引擎.push(BattleEngine.SMissileAsk.new(1, 3, 2, true, [3, 1]))
	引擎.run()
	检(引擎._await_id == 1, "地系牌场景应先问持有者 1")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 1,
		"args": [GConst.Reattack.Attack], "card_ids": [地法术.id], "dst_ids": [],
	})
	检(玩家1.has_hand_card(地法术.id), "不能继续传递的地系牌应留在手里")
	检(not 引擎.deck.discard.has(地法术.id), "不能继续传递的地系牌不应进弃牌堆")
	检(_播报次数(4703) == 0, "地系牌被拒时不应播报 4703")
	检(玩家1.hand_cards.size() == 3, "1 号承受 2 点魔弹伤害应摸 2 张（1+2=3），实际 %d"
		% 玩家1.hand_cards.size())


# ============================================================
# 4704 三秒原则
# ============================================================
func _拦截上下文(owner: int, cards: Array, source: String = "hand", face_up: bool = true) -> Dictionary:
	return {
		"owner": owner, "cards": cards, "source": source, "cause": 0,
		"face_up": face_up, "taker": -1, "taken": [],
	}


func _测试4704() -> void:
	# ---- 同步预判：只有「队友手牌 / 盖牌里、正面朝上的【魔弹】」且自己有代价牌时参与 ----
	_重置战斗()
	_给牌(玩家1, 普通牌.id)
	检(角色.wants_before_discard(_拦截上下文(2, [魔弹.id])),
		"队友手牌里的【魔弹】进弃牌前应参与拦截")
	检(角色.wants_before_discard(_拦截上下文(2, [魔弹.id], "cover")),
		"队友盖牌里的【魔弹】进弃牌前应参与拦截")
	检(not 角色.wants_before_discard(_拦截上下文(3, [魔弹.id])), "敌方牌不应拦截")
	检(not 角色.wants_before_discard(_拦截上下文(1, [魔弹.id])), "自己的牌不应拦截")
	检(not 角色.wants_before_discard(_拦截上下文(-1, [魔弹.id])), "未知牌主不应拦截")
	检(not 角色.wants_before_discard(_拦截上下文(2, [魔弹.id], "hand", false)),
		"未正面朝上的牌不应拦截")
	检(not 角色.wants_before_discard(_拦截上下文(2, [魔弹.id], "deck")),
		"不是手牌 / 盖牌来源的牌不应拦截")
	检(not 角色.wants_before_discard(_拦截上下文(2, [普通牌.id])), "非【魔弹】不应拦截")
	var 已认领: Dictionary = _拦截上下文(2, [魔弹.id])
	已认领["taker"] = 4
	检(not 角色.wants_before_discard(已认领), "已被认领的弃牌不应再参与拦截")
	玩家1.hand_cards.clear()
	检(not 角色.wants_before_discard(_拦截上下文(2, [魔弹.id])),
		"自己手里没有代价牌时不应参与拦截")

	# ---- 真实拦截：弃 1 张牌 → 获得队友手牌里的【魔弹】 ----
	_重置战斗()
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家2, 魔弹.id)
	玩家2.remove_hand_cards([魔弹.id])
	发送记录.clear()
	引擎.push(触发弃牌.new([魔弹.id], _拦截上下文(2, [魔弹.id])))
	引擎.run()
	检(引擎._await_id == 1, "队友的【魔弹】进弃牌前应询问 47，实际等待 %s" % str(引擎._await_id))
	var 拦截问: Dictionary = _取询问(1, 4704)
	检(not 拦截问.is_empty(), "没有向 47 下发 4704 询问")
	检((拦截问.get("card_ids", []) as Array).has(普通牌.id), "4704 的代价应能选自己的手牌")
	检((拦截问.get("dst_ids", []) as Array).has(2), "4704 应把来源队友的提示下发到客户端")
	检(引擎.deck.discard.is_empty(), "拦截询问期间【魔弹】不应已经进弃牌堆")
	检(_播报次数(4704) == 0, "还没确认发动时不应播报 4704")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4704, "src_id": 1, "args": [1], "card_ids": [普通牌.id], "dst_ids": [],
	})
	检(玩家1.hand_cards.has(魔弹.id), "4704 应从队友那里获得被拦截的【魔弹】")
	检(not 玩家1.has_hand_card(普通牌.id), "4704 的代价牌应离手")
	检(引擎.deck.discard.has(普通牌.id), "4704 的代价牌应进弃牌堆")
	检(not 引擎.deck.discard.has(魔弹.id), "被认领的【魔弹】不应进弃牌堆")
	检(引擎.deck.discard_size() == 1, "本次弃牌结算后弃牌堆应只有代价牌一张，实际 %d"
		% 引擎.deck.discard_size())
	检(_播报次数(4704) == 1, "4704 发动应播报一次，实际 %d 次" % _播报次数(4704))
	检(not _有错误输入(1), "4704 拦截流程不应给玩家发操作无效")

	# ---- 拒绝：魔弹正常进弃牌堆 ----
	_重置战斗()
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家2, 魔弹.id)
	玩家2.remove_hand_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], _拦截上下文(2, [魔弹.id])))
	引擎.run()
	检(引擎._await_id == 1, "拒绝场景也应先问 47")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4704, "src_id": 1, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(引擎.deck.discard.has(魔弹.id), "拒绝拦截后【魔弹】应正常进弃牌堆")
	检(not 玩家1.has_hand_card(魔弹.id), "拒绝拦截时不应获得魔弹")
	检(玩家1.has_hand_card(普通牌.id), "拒绝拦截时不应支付代价")

	# ---- 交不出代价（硬提交不在手里的牌）：不认领，魔弹正常进弃牌堆 ----
	_重置战斗()
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家2, 魔弹.id)
	玩家2.remove_hand_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], _拦截上下文(2, [魔弹.id])))
	引擎.run()
	检(引擎._await_id == 1, "交不出代价场景也应先问 47")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4704, "src_id": 1, "args": [1], "card_ids": [普通牌2.id], "dst_ids": [],
	})
	检(引擎.deck.discard.has(魔弹.id), "交不出代价时【魔弹】应正常进弃牌堆")
	检(not 玩家1.has_hand_card(魔弹.id), "交不出代价时不应获得魔弹")
	检(玩家1.has_hand_card(普通牌.id), "交不出代价时自己的牌不应离手")

	# ---- 没有代价牌：不参与拦截，直接同步弃牌 ----
	_重置战斗()
	_给牌(玩家2, 魔弹.id)
	玩家2.remove_hand_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], _拦截上下文(2, [魔弹.id])))
	引擎.run()
	检(引擎._await_id == -1, "自己手里没有代价牌时不应弹 4704 询问")
	检(引擎.deck.discard.has(魔弹.id), "不拦截时【魔弹】应正常进弃牌堆")

	# ---- 一次多张魔弹：取待弃顺序里的第一张，其余正常进弃牌堆 ----
	_重置战斗()
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家2, 魔弹.id)
	_给牌(玩家2, 魔弹2.id)
	玩家2.remove_hand_cards([魔弹.id, 魔弹2.id])
	引擎.push(触发弃牌.new([魔弹.id, 魔弹2.id], _拦截上下文(2, [魔弹.id, 魔弹2.id])))
	引擎.run()
	检(引擎._await_id == 1, "多张魔弹场景也应先问 47")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4704, "src_id": 1, "args": [1], "card_ids": [普通牌.id], "dst_ids": [],
	})
	检(玩家1.hand_cards.has(魔弹.id), "多张魔弹时应获得待弃顺序里的第一张")
	检(not 玩家1.has_hand_card(魔弹2.id), "多张魔弹时只应获得一张")
	检(引擎.deck.discard.has(魔弹2.id), "未被认领的其余魔弹应正常进弃牌堆")

	# ---- 盖牌来源：也能拦截 ----
	_重置战斗()
	_给牌(玩家1, 普通牌.id)
	玩家2.cover_cards.append(魔弹.id)
	玩家2.remove_cover_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], _拦截上下文(2, [魔弹.id], "cover")))
	引擎.run()
	检(引擎._await_id == 1, "盖牌里的魔弹进弃牌前也应询问 47")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4704, "src_id": 1, "args": [1], "card_ids": [普通牌.id], "dst_ids": [],
	})
	检(玩家1.hand_cards.has(魔弹.id), "盖牌来源的魔弹也应能被 4704 获得")
	检(not 引擎.deck.discard.has(魔弹.id), "被认领的盖牌魔弹不应进弃牌堆")

	# ---- 非正面朝上：不参与拦截，直接同步弃牌 ----
	_重置战斗()
	_给牌(玩家1, 普通牌.id)
	_给牌(玩家2, 魔弹.id)
	玩家2.remove_hand_cards([魔弹.id])
	引擎.push(触发弃牌.new([魔弹.id], _拦截上下文(2, [魔弹.id], "hand", false)))
	引擎.run()
	检(引擎._await_id == -1, "未正面朝上的魔弹不应弹 4704 询问")
	检(引擎.deck.discard.has(魔弹.id), "不拦截时【魔弹】应正常进弃牌堆")


# ============================================================
# 4705 美食风暴
# ============================================================
func _测试4705() -> void:
	# ---- 技能栏与校验 ----
	_重置战斗()
	检(not bool(_找技能(角色.available_skills(), 4705).get("enabled", true)),
		"没有宝石时 4705 应置灰")
	玩家1.set_gem(1)
	var 风暴项: Dictionary = _找技能(角色.available_skills(), 4705)
	检(bool(风暴项.get("enabled", false)), "有宝石时 4705 应可点")
	var 合法: Dictionary = _美食动作([3, 4])
	检(角色.v_magic_skill(合法) == GConst.GE_SUCCESS, "合法的 4705 应通过校验")
	检(角色.v_magic_skill(_美食动作([3])) == GConst.GE_INVALID_PLAYERID, "4705 必须恰好 2 名目标")
	检(角色.v_magic_skill(_美食动作([3, 4, 2])) == GConst.GE_INVALID_PLAYERID, "4705 不能有 3 名目标")
	检(角色.v_magic_skill(_美食动作([3, 3])) == GConst.GE_INVALID_PLAYERID, "4705 的两名目标不能重复")
	检(角色.v_magic_skill(_美食动作([2, 3])) == GConst.GE_INVALID_PLAYERID, "4705 不能指定队友")
	玩家1.set_gem(0)
	检(角色.v_magic_skill(合法) == GConst.GE_INVALID_ACTION, "没有真宝石时 4705 不应通过校验")
	玩家1.set_crystal(1)
	检(角色.v_magic_skill(合法) == GConst.GE_INVALID_ACTION,
		"4705 的【宝石】不能用【水晶】顶")
	玩家1.set_crystal(0)

	# ---- 完整结算：扣 1 宝石，两名目标各 2 点法术伤害 ----
	_重置战斗()
	玩家1.set_gem(1)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, _美食动作([3, 4]))
	引擎.run()
	检(玩家1.gem == 0, "4705 应消耗 1 颗宝石")
	检(引擎.team_gem[GConst.BLUE] == 0, "4705 的宝石费用不应进我方战绩区")
	检(_播报次数(4705) == 1, "4705 发动应播报一次，实际 %d 次" % _播报次数(4705))
	检(玩家3.hand_cards.size() == 2 and 玩家4.hand_cards.size() == 2,
		"4705 应对 2 名目标各造成 2 点法术伤害（各摸 2 张），实际 %d / %d"
		% [玩家3.hand_cards.size(), 玩家4.hand_cards.size()])
	检(int(引擎.team_morale[GConst.BLUE]) == 10 and int(引擎.team_morale[GConst.RED]) == 10,
		"4705 的 2 点伤害不应扣士气")
	检(not _有错误输入(1), "4705 的完整流程不应给发动者发操作无效")

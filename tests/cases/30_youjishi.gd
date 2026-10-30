extends 自检用例
## R38 游击士（38）：3801 精灵赠礼 / 3802 元素射击*SORA / 3803 二重剑影 /
## 3804 附魔之术 / 3805 精灵的剑舞。
##
## 任务范围只有 role + test：角色表「脚本」列、技能表「提示」列留给 DATA 任务，
## 所以用例里手动把角色挂到玩家 1 身上，提示文案只检查「有下发询问 / 选项」。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 技能号 / 技能行 / 技能说明 / 脚本 / 【子弹】槽；
##   - 3801：开局从牌库顶取 6 张进盖牌区，牌面互不相同且不再留在牌堆；
##   - 3802：无子弹 / 非主动攻击 / 别人的攻击不询问；取消（选子弹即发动）不生效；
##            火 +1 伤害、水命中后玩家选目标 +1 治疗、风行动结束直接给 +1 攻击行动（不再弹响应）、
##            雷无法应战、地命中后玩家选目标 1 点法术伤害、光/暗子弹选择视为系别；
##            移除后进弃牌堆、播报一次、URGENT 重入不重复结算；子弹系别与 3805 的攻击牌系别互相独立；
##            完整攻击流水线：选子弹（一步发动）→ 应战提示伤害 +1 → 结算后进弃牌堆；
##   - 3803：命中后给 1 份「同系攻击行动」、未命中不给、回合限定只给一次、回合开始重置、
##            白名单只含同系攻击牌 / 无同系牌时全禁；3805 视为风系后白名单按风系；
##            额外行动阶段里服务端兜底校验同系限制；
##   - 3804：提炼时没有子弹才问；扣 1 能量 + 1 张手牌进盖牌区；没有子弹 / 提炼 0 能量 /
##            非提炼不询问；取消不扣；完整提炼流水线里能发动；
##   - 3805：技能栏置灰规则、校验（来源 / 技能号 / 能量 / 牌 / 目标）、
##            目标白名单 / 服务端校验都排除横置（潜行）的暗杀者、支付 1 能量（宝石可顶）、
##            真牌进弃牌堆、本次攻击按风系【风神斩】结算
##            （目标用风系牌可应战、火系牌不可应战），并让 3803 的同系白名单变成风系；
##            虚牌命格口径：harm 标 virtual_no_fate，阴阳师【阴阳转换】不能被 66 的【幻】命格误触发。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_youjishi.gd")

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 队友: BattlePlayer = null
var 对手甲: BattlePlayer = null
var 对手乙: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 火攻击牌: GCard = null
var 火攻击牌2: GCard = null
var 风攻击牌: GCard = null
var 水攻击牌: GCard = null
var 法术牌: GCard = null
var 火子弹: GCard = null
var 水子弹: GCard = null
var 风子弹: GCard = null
var 雷子弹: GCard = null
var 地子弹: GCard = null
var 光子弹: GCard = null
var 暗子弹: GCard = null


func _init() -> void:
	名称 = "游击士"


# ============================================================
# 卡库 / 消息 / 询问工具
# ============================================================
## 卡库里第一张指定系别的攻击牌（排除暗系：暗系攻击自带无法应战，会跳过应战询问）
func _取攻击牌(元素: int, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() != 元素 or 排除.has(c.id):
			continue
		return c
	return null


## 卡库里第一张指定系别的牌（子弹可以是任意牌，不限于攻击牌）
func _取任意牌(元素: int, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if c.element_enum() != 元素 or 排除.has(c.id):
			continue
		return c
	return null


## 卡库里第一张法术牌（3804 的扣置手牌）
func _取法术牌() -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic():
			return c
	return null


## 二级技能栏里的选项是不是全部置灰（元素射击的「视为系别」用）
func _选项全灰(窗: Control) -> bool:
	var 项们: Array = 窗.get("_二级选项")
	if 项们.is_empty():
		return false
	for 项: Dictionary in 项们:
		if bool(项.get("可用", true)):
			return false
	return true


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


## 攻击宣告 / 命中 / 未命中用的上下文（与引擎 harm_ctx / SAttackCard 同形）
func _攻击上下文(牌: GCard, src: int, dst: int, 主动: bool) -> Dictionary:
	var harm: Dictionary = {
		"src": src, "dst": dst, "point": BattleEngine.ATTACK_BASE_POINT, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 牌.id, "is_active": 主动,
	}
	return {
		"card_id": 牌.id, "dst": dst, "src": src, "is_active": 主动,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": harm,
	}


## 把一张牌从牌库拿走、放进玩家 1 的盖牌区作为【子弹】
func _放子弹(牌: GCard) -> void:
	引擎.deck.remove_one(牌.id)
	玩家.cover_cards.append(牌.id)


## 清空战斗状态：回到「轮到玩家 1、行动阶段、无手牌 / 无子弹 / 无额外行动」的同一起点
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


## 3802：走完「是否发动 → 选子弹」两步询问（返回第二步的询问）
func _发动3802(ctx: Dictionary, 子弹: GCard, 视为: int = 0) -> Dictionary:
	检(角色.p_timeline_1(ctx) == BattleRole.WAIT, "有【子弹】时主动攻击宣告应直接问选【子弹】")
	var 问: Dictionary = _取询问(1, 3802)
	检(not 问.is_empty(), "没有下发【元素射击】询问")
	var 参数: Array = 问.get("args", [])
	检(参数.size() >= 3 and int(参数[0]) == 1 and int(参数[2]) == GConst.CardSource.Cover,
		"【元素射击】应一步到位（直接要求选 1 张盖牌子弹）：%s" % str(参数))
	检(参数.size() > 3 and int(参数[3]) == 5,
		"【元素射击】应同时下发 5 个视为系别选项（光/暗子弹用）：%s" % str(参数))
	_应答([1] if 视为 <= 0 else [视为], [子弹.id])
	return 问


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 / 子弹槽 ----
	检(str(Data.role_list.get(38, "")) == "游击士", "38 号角色名不是「游击士」")
	检(Data.role_personal_name(38) == "索拉", "38 号角色姓名不是「索拉」")
	检(absf(Data.role_star(38) - 3.5) < 0.01, "游击士应是 3.5 星，实际 %s" % str(Data.role_star(38)))
	检(Data.role_skills(38) == [3801, 3802, 3803, 3804, 3805],
		"游击士技能号不对：%s" % str(Data.role_skills(38)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_youjishi.gd"), "游击士的角色脚本文件不存在")
	for 技能号: int in [3801, 3802, 3803, 3804, 3805]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	var 技能说明: String = Data.role_skill_info(38)
	for 技能名: String in ["精灵赠礼", "元素射击", "二重剑影", "附魔之术", "精灵的剑舞"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])
	var 子弹定义: Dictionary = Data.role_token_def(38, 2)
	检(str(子弹定义.get("name", "")) == "子弹" and int(子弹定义.get("max", 0)) == 6,
		"游击士【子弹】槽配置不对：%s" % str(子弹定义))

	# ---- 卡库前提 ----
	火攻击牌 = _取攻击牌(GConst.CardElement.Fire)
	风攻击牌 = _取攻击牌(GConst.CardElement.Wind)
	水攻击牌 = _取攻击牌(GConst.CardElement.Water)
	if 火攻击牌 != null:
		火攻击牌2 = _取攻击牌(GConst.CardElement.Fire, [火攻击牌.id])
	法术牌 = _取法术牌()
	var 已用攻击牌: Array = []
	for 牌: GCard in [火攻击牌, 火攻击牌2, 风攻击牌, 水攻击牌]:
		if 牌 != null:
			已用攻击牌.append(牌.id)
	火子弹 = _取任意牌(GConst.CardElement.Fire, 已用攻击牌)
	水子弹 = _取任意牌(GConst.CardElement.Water, 已用攻击牌)
	风子弹 = _取任意牌(GConst.CardElement.Wind, 已用攻击牌)
	雷子弹 = _取任意牌(GConst.CardElement.Thunder)
	地子弹 = _取任意牌(GConst.CardElement.Earth)
	光子弹 = _取任意牌(GConst.CardElement.Light)
	暗子弹 = _取任意牌(GConst.CardElement.Darkness)
	检(火攻击牌 != null and 风攻击牌 != null and 水攻击牌 != null, "卡库找不到火 / 风 / 水系攻击牌")
	检(火攻击牌2 != null, "卡库找不到第二张火系牌")
	检(法术牌 != null, "卡库找不到法术牌")
	for 牌: GCard in [火子弹, 水子弹, 风子弹, 雷子弹, 地子弹, 光子弹, 暗子弹]:
		检(牌 != null, "卡库找不到某种系别的【子弹】候选牌")
	if 火攻击牌 == null or 风攻击牌 == null or 水攻击牌 == null or 火攻击牌2 == null \
			or 法术牌 == null or 火子弹 == null or 水子弹 == null or 风子弹 == null \
			or 雷子弹 == null or 地子弹 == null or 光子弹 == null or 暗子弹 == null:
		return

	# ---- 建引擎：1 / 2 蓝，3 / 4 红；角色表脚本列留给 DATA，用例里手动挂上角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "游击士")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({1: 0, 2: 0, 3: 0, 4: 0})
	玩家 = 引擎.p(1)
	队友 = 引擎.p(2)
	对手甲 = 引擎.p(3)
	对手乙 = 引擎.p(4)

	# ============================================================
	# 3801 精灵赠礼：开局 6 张【子弹】
	# ============================================================
	var 牌堆前: int = 引擎.deck.pile_size()
	玩家.role_id = 38
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	检(玩家.cover_cards_max == 6, "游击士的盖牌上限应为 6，实际 %d" % 玩家.cover_cards_max)
	检(玩家.cover_count() == 6, "开局应从牌库顶取 6 张作为【子弹】，实际 %d 张" % 玩家.cover_count())
	检(引擎.deck.pile_size() == 牌堆前 - 6,
		"开局【子弹】应从牌库顶取，牌堆 %d → %d" % [牌堆前, 引擎.deck.pile_size()])
	var 子弹去重: Dictionary = {}
	for cid: int in 玩家.cover_cards:
		子弹去重[cid] = true
		检(not 引擎.deck.pile.has(cid), "作为【子弹】的牌不应还留在牌堆里：%d" % cid)
	检(子弹去重.size() == 6, "6 张【子弹】不应有重复：%s" % str(玩家.cover_cards))
	_重置战斗()

	# ============================================================
	# 3802 元素射击*SORA
	# ============================================================
	# 没有【子弹】：不询问
	发送记录.clear()
	var 无弹上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, true)
	检(角色.p_timeline_1(无弹上下文) == BattleRole.SUCCESS, "没有【子弹】时不触发【元素射击】")
	检(_取询问(1, 3802).is_empty(), "没有【子弹】时不应下发【元素射击】询问")

	# 别人的主动攻击 / 自己的应战反击：不询问
	_重置战斗()
	_放子弹(火子弹)
	var 别家上下文: Dictionary = _攻击上下文(火攻击牌, 3, 1, true)
	检(角色.p_timeline_1(别家上下文) == BattleRole.SUCCESS, "别人的攻击不应由本角色处理【元素射击】")
	检(_取询问(1, 3802).is_empty(), "别人的攻击不应下发本角色的【元素射击】询问")
	var 应战上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, false)
	检(角色.p_timeline_1(应战上下文) == BattleRole.SUCCESS, "应战反击不应触发【元素射击】")
	检(_取询问(1, 3802).is_empty(), "应战反击不应下发【元素射击】询问")

	# 取消（一步到位：取消选子弹＝不发动）：子弹保留、不播报
	_重置战斗()
	_放子弹(火子弹)
	发送记录.clear()
	var 火上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, true)
	检(角色.p_timeline_1(火上下文) == BattleRole.WAIT, "有【子弹】时主动攻击宣告应直接问选【子弹】")
	_应答([])
	检(角色.p_timeline_1(火上下文) == BattleRole.SUCCESS, "取消选子弹应按不发动收尾")
	检(玩家.cover_count() == 1, "取消选子弹不应移除【子弹】")
	检(_播报次数(3802) == 0, "取消选子弹不应播报")

	# 火系：本次攻击伤害 +1，子弹移除进弃牌堆，播报一次；URGENT 重入不重复结算
	_重置战斗()
	_放子弹(火子弹)
	发送记录.clear()
	火上下文 = _攻击上下文(火攻击牌, 1, 3, true)
	_发动3802(火上下文, 火子弹)
	检(角色.p_timeline_1(火上下文) == BattleRole.SUCCESS, "火系【子弹】应正常收尾")
	检(int((火上下文.get("harm", {}) as Dictionary).get("point", 0)) == BattleEngine.ATTACK_BASE_POINT + 1,
		"火系【子弹】应让本次攻击伤害 +1：%s" % str(火上下文.get("harm", {})))
	检(玩家.cover_count() == 0, "发动【元素射击】后应移除 1 个【子弹】")
	检(引擎.deck.discard.has(火子弹.id), "移除的【子弹】应进入弃牌堆")
	检(_播报次数(3802) == 1, "【元素射击】应播报一次，实际 %d 次" % _播报次数(3802))
	引擎._最后询问.clear()
	检(角色.p_timeline_1(火上下文) == BattleRole.SUCCESS, "同一次攻击重入【元素射击】应直接跳过")
	检(_取询问(1, 3802).is_empty(), "同一次攻击不应重复询问【元素射击】")

	# 水系：命中后由玩家选 1 名角色 +1 治疗（不是固定给被攻击者）
	_重置战斗()
	_放子弹(水子弹)
	发送记录.clear()
	var 水上下文: Dictionary = _攻击上下文(水攻击牌, 1, 3, true)
	_发动3802(水上下文, 水子弹)
	检(角色.p_timeline_1(水上下文) == BattleRole.SUCCESS, "水系【子弹】应正常收尾")
	检(对手甲.cross_num == 0, "水系【子弹】命中前不应加治疗")
	检(角色.p_timeline_2_hit(水上下文) == BattleRole.WAIT, "水系【子弹】命中后应先问选哪名角色加治疗")
	var 水问: Dictionary = _取询问(1, 3802)
	检(not 水问.is_empty(), "水系【子弹】没有下发选目标询问")
	var 水参数: Array = 水问.get("args", [])
	检(水参数.size() >= 2 and int(水参数[1]) == 1, "水系【子弹】应要求选 1 名目标：%s" % str(水参数))
	_应答([1], [], [队友.id])
	检(角色.p_timeline_2_hit(水上下文) == BattleRole.SUCCESS, "水系【子弹】选完目标应结算")
	检(队友.cross_num == 1, "水系【子弹】应对玩家选的目标 +1 治疗，实际 %d" % 队友.cross_num)
	检(对手甲.cross_num == 0, "水系【子弹】不应把治疗加给被攻击者")
	检(角色.p_timeline_2_hit(水上下文) == BattleRole.SUCCESS, "水系【子弹】已结算过，重入不应再加治疗")
	检(队友.cross_num == 1, "水系【子弹】重入不应重复加治疗")
	# 取消选目标：退回被攻击者（子弹已经花掉，效果不能白弃）
	_重置战斗()
	_放子弹(水子弹)
	水上下文 = _攻击上下文(水攻击牌, 1, 3, true)
	_发动3802(水上下文, 水子弹)
	检(角色.p_timeline_1(水上下文) == BattleRole.SUCCESS, "水系【子弹】应正常收尾")
	检(角色.p_timeline_2_hit(水上下文) == BattleRole.WAIT, "水系【子弹】命中后应先问选目标")
	_应答([])
	检(角色.p_timeline_2_hit(水上下文) == BattleRole.SUCCESS, "水系【子弹】取消选目标应正常结算")
	检(对手甲.cross_num == 1, "水系【子弹】取消选目标应退回被攻击者，实际 %d" % 对手甲.cross_num)

	# 风系：攻击行动结束后额外 +1 攻击行动
	_重置战斗()
	_放子弹(风子弹)
	var 风上下文: Dictionary = _攻击上下文(风攻击牌, 1, 3, true)
	_发动3802(风上下文, 风子弹)
	检(角色.p_timeline_1(风上下文) == BattleRole.SUCCESS, "风系【子弹】应正常收尾")
	检(玩家.additional_actions.is_empty(), "风系【子弹】不应在宣告阶段就给额外行动")
	检(角色.p_after_attack({"player": 1, "card_id": 风攻击牌.id, "dst": 3}) == BattleRole.SUCCESS,
		"风系【子弹】的攻击行动结束应正常收尾")
	检(玩家.additional_actions.size() == 1, "风系【子弹】应在攻击行动结束后给 1 份额外行动")
	if 玩家.additional_actions.size() == 1:
		var 风行动: Dictionary = 玩家.additional_actions[0]
		检(int(风行动.get("cause", 0)) == 3802,
			"风系【子弹】的额外行动来源应是 3802：%s" % str(风行动))
		检(bool(风行动.get("direct", false)),
			"风系【子弹】的额外攻击行动应直接给出（direct），不能再弹一次响应询问：%s" % str(风行动))
		检(not bool(风行动.get("in_end_response", false)),
			"风系【子弹】不应再作为行动结束响应下发：%s" % str(风行动))

	# 雷系：本次攻击无法应战
	_重置战斗()
	_放子弹(雷子弹)
	var 雷上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, true)
	_发动3802(雷上下文, 雷子弹)
	检(角色.p_timeline_1(雷上下文) == BattleRole.SUCCESS, "雷系【子弹】应正常收尾")
	检(int(雷上下文.get("hit_rate", -1)) == GConst.HitRate.NoReattack,
		"雷系【子弹】应把本次攻击置为「无法应战」，实际 %s" % str(雷上下文.get("hit_rate")))

	# 地系：命中后由玩家选 1 名角色，对其造成 1 点法术伤害③
	_重置战斗()
	_放子弹(地子弹)
	发送记录.clear()
	var 地上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, true)
	_发动3802(地上下文, 地子弹)
	检(角色.p_timeline_1(地上下文) == BattleRole.SUCCESS, "地系【子弹】应正常收尾")
	检(角色.p_timeline_2_hit(地上下文) == BattleRole.WAIT, "地系【子弹】命中后应先问选哪名角色承受伤害")
	var 地问: Dictionary = _取询问(1, 3802)
	检(not 地问.is_empty(), "地系【子弹】没有下发选目标询问")
	var 地参数: Array = 地问.get("args", [])
	检(地参数.size() >= 2 and int(地参数[1]) == 1, "地系【子弹】应要求选 1 名目标：%s" % str(地参数))
	_应答([1], [], [队友.id])
	检(角色.p_timeline_2_hit(地上下文) == BattleRole.URGENT, "地系【子弹】选完目标应压入 1 点法术伤害")
	var 地伤害: Dictionary = _找伤害(3802, 队友.id)
	检(not 地伤害.is_empty(), "地系【子弹】没有压入法术伤害")
	if not 地伤害.is_empty():
		检(int(地伤害.get("point", 0)) == 1, "地系【子弹】应是 1 点伤害：%s" % str(地伤害))
		检(int(地伤害.get("type", 0)) == GConst.HarmType.Magic, "地系【子弹】应是法术伤害")
	检(_找伤害(3802, 对手甲.id).is_empty(), "地系【子弹】不应把伤害直接给被攻击者")
	检(角色.p_timeline_2_hit(地上下文) == BattleRole.SUCCESS, "地系【子弹】已结算过，重入不应再加伤害")

	# 光系子弹：同一次询问里选子弹＋视为水系 → 命中 +1 治疗
	_重置战斗()
	_放子弹(光子弹)
	var 光上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, true)
	检(角色.p_timeline_1(光上下文) == BattleRole.WAIT, "有光系【子弹】时应直接问选【子弹】")
	var 光问: Dictionary = _取询问(1, 3802)
	var 光参数: Array = 光问.get("args", [])
	检(光参数.size() > 3 and int(光参数[3]) == 5,
		"光/暗【子弹】的视为系别选项应与选子弹在同一次询问里：%s" % str(光参数))
	检((光问.get("notes", []) as Array).size() == 5, "光系【子弹】的 5 个选项应都有文案")
	_应答([GConst.CardElement.Water], [光子弹.id])
	检(角色.p_timeline_1(光上下文) == BattleRole.SUCCESS, "选完视为系别后应正常收尾")
	检(玩家.cover_count() == 0, "光系【子弹】也应按移除 1 个子弹结算")
	检(引擎.deck.discard.has(光子弹.id), "光系【子弹】移除后应进入弃牌堆")
	检(角色.p_timeline_2_hit(光上下文) == BattleRole.WAIT, "光系子弹视为水系后命中应先问选目标")
	_应答([1], [], [队友.id])
	检(角色.p_timeline_2_hit(光上下文) == BattleRole.SUCCESS, "光系子弹视为水系后命中应结算")
	检(队友.cross_num == 1, "光系子弹视为水系后应对玩家选的目标 +1 治疗，实际 %d" % 队友.cross_num)

	# 暗系子弹：选项里选视为雷系 → 本次攻击无法应战
	_重置战斗()
	_放子弹(暗子弹)
	var 暗上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, true)
	角色.p_timeline_1(暗上下文)
	检(角色.p_timeline_1(暗上下文) == BattleRole.WAIT, "暗系【子弹】应先问选【子弹】")
	_应答([GConst.CardElement.Thunder], [暗子弹.id])
	检(角色.p_timeline_1(暗上下文) == BattleRole.SUCCESS, "暗系子弹选完视为系别后应正常收尾")
	检(int(暗上下文.get("hit_rate", -1)) == GConst.HitRate.NoReattack,
		"暗系子弹视为雷系后本次攻击应无法应战")

	# 光暗子弹的系别选项可以取消：子弹保留
	_重置战斗()
	_放子弹(光子弹)
	var 取消上下文: Dictionary = _攻击上下文(火攻击牌, 1, 3, true)
	角色.p_timeline_1(取消上下文)
	检(角色.p_timeline_1(取消上下文) == BattleRole.WAIT, "光系【子弹】应先问选【子弹】")
	_应答([], [光子弹.id])
	检(角色.p_timeline_1(取消上下文) == BattleRole.SUCCESS, "光/暗子弹没选视为系别应按不发动收尾")
	检(玩家.cover_count() == 1, "没选视为系别不应移除【子弹】")

	# 子弹系别独立于 3805 的攻击牌系别（A3）：攻击牌视为风系，火系子弹仍 +1 伤害
	_重置战斗()
	_放子弹(火子弹)
	# 用风系虚牌 66 模拟 3805 视为风系的攻击上下文
	var 剑舞攻击: Dictionary = _攻击上下文(Data.get_card(66), 1, 3, true)
	_发动3802(剑舞攻击, 火子弹)
	检(角色.p_timeline_1(剑舞攻击) == BattleRole.SUCCESS, "3805 视为风系时的【子弹】应正常收尾")
	检(int((剑舞攻击.get("harm", {}) as Dictionary).get("point", 0)) == BattleEngine.ATTACK_BASE_POINT + 1,
		"3805 视为风系只改攻击牌，火系子弹仍应 +1 伤害")

	# 完整攻击流水线：选子弹（一步发动）→ 应战提示伤害 +1 → 结算后子弹进弃牌堆
	_重置战斗()
	_放子弹(火子弹)
	玩家.hand_cards = [火攻击牌.id]
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.Attack, {
		"card_ids": [火攻击牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "完整攻击流水线里应先问攻击者选哪个【子弹】（等待 %s）" % str(引擎._await_id))
	检(not _取询问(1, 3802).is_empty(), "完整攻击流水线没有下发【元素射击】询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3802, "src_id": 1, "args": [1], "card_ids": [火子弹.id], "dst_ids": [],
	})
	检(引擎._await_id == 3, "选完【子弹】后应等对手应战（等待 %s）" % str(引擎._await_id))
	var 应战询问: Dictionary = _取询问(3, GConst.RespondType.ReplyAttack)
	检(not 应战询问.is_empty(), "选完【子弹】后没有下发应战询问")
	var 应战参数: Array = 应战询问.get("args", [])
	检(应战参数.size() > 5 and int(应战参数[5]) == BattleEngine.ATTACK_BASE_POINT + 1,
		"火系【子弹】的应战提示伤害应为 %d：%s" % [BattleEngine.ATTACK_BASE_POINT + 1, str(应战参数)])
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(玩家.cover_count() == 0, "完整流水线结算后应移除【子弹】")
	检(引擎.deck.discard.has(火子弹.id), "完整流水线结算后【子弹】应进入弃牌堆")
	检(对手甲.hand_cards.size() == 3,
		"本次攻击 3 点伤害应让目标摸 3 张，实际 %d 张" % 对手甲.hand_cards.size())

	# ============================================================
	# 3803 二重剑影
	# ============================================================
	# 命中：给 1 份「同系攻击行动」，白名单只含同系攻击牌
	_重置战斗()
	玩家.hand_cards = [风攻击牌.id, 火攻击牌.id]
	var 命中上下文: Dictionary = _攻击上下文(风攻击牌, 1, 3, true)
	检(角色.p_timeline_1(命中上下文) == BattleRole.SUCCESS, "没有子弹时攻击宣告应正常收尾")
	检(角色.p_timeline_2_hit(命中上下文) == BattleRole.SUCCESS, "命中②应正常收尾")
	发送记录.clear()
	检(角色.p_after_attack({"player": 1, "card_id": 风攻击牌.id, "dst": 3}) == BattleRole.SUCCESS,
		"攻击行动结束应正常收尾")
	检(_播报次数(3803) == 1, "【二重剑影】应播报一次")
	检(玩家.additional_actions.size() == 1, "命中后应给 1 份额外攻击行动")
	if 玩家.additional_actions.size() == 1:
		检(int(玩家.additional_actions[0].get("cause", 0)) == 3803, "额外行动来源应是 3803")
	var 白名单: Array = 引擎.额外行动出牌白名单(玩家.额外行动数据(3803))
	检(白名单.has(风攻击牌.id) and not 白名单.has(火攻击牌.id),
		"3803 的额外攻击应只允许同系攻击牌：%s" % str(白名单))
	检(int(玩家.额外行动数据(3803).get("element", 0)) == GConst.CardElement.Wind,
		"3803 的额外行动应把「与本次攻击同系」写进规格：%s" % str(玩家.额外行动数据(3803)))
	# 同一次回合的第二次命中不再给（【回合限定】）
	玩家.additional_actions.clear()
	玩家.reset_action_counts()
	var 命中上下文2: Dictionary = _攻击上下文(风攻击牌, 1, 3, true)
	角色.p_timeline_1(命中上下文2)
	角色.p_timeline_2_hit(命中上下文2)
	发送记录.clear()
	角色.p_after_attack({"player": 1, "card_id": 风攻击牌.id, "dst": 3})
	检(玩家.additional_actions.is_empty(), "【二重剑影】回合限定：同回合第二次命中不应再给额外行动")
	检(_播报次数(3803) == 0, "回合限定的第二次命中不应再播报 3803")
	# 回合开始后重置
	角色.p_before_turn_begin({})
	var 命中上下文3: Dictionary = _攻击上下文(风攻击牌, 1, 3, true)
	角色.p_timeline_1(命中上下文3)
	角色.p_timeline_2_hit(命中上下文3)
	角色.p_after_attack({"player": 1, "card_id": 风攻击牌.id, "dst": 3})
	检(玩家.additional_actions.size() == 1, "回合开始后【二重剑影】应能再次发动")

	# 未命中：不给额外行动
	_重置战斗()
	玩家.hand_cards = [风攻击牌.id]
	var 未命中上下文: Dictionary = _攻击上下文(风攻击牌, 1, 3, true)
	角色.p_timeline_1(未命中上下文)
	发送记录.clear()
	角色.p_after_attack({"player": 1, "card_id": 风攻击牌.id, "dst": 3})
	检(玩家.additional_actions.is_empty(), "未命中时【二重剑影】不应给额外行动")
	检(_播报次数(3803) == 0, "未命中时不应播报 3803")
	# 限定系别是规则不是手牌快照：手里此刻没有风系攻击牌，规则仍只放行风系攻击牌
	# （之后再摸到风系攻击牌也能出；以前这里会算成「全禁」，把玩家手里的风系牌全灰掉）
	_重置战斗()
	玩家.hand_cards = [火攻击牌.id]
	角色.p_timeline_1(_攻击上下文(风攻击牌, 1, 3, true))
	角色.p_timeline_2_hit(_攻击上下文(风攻击牌, 1, 3, true))
	角色.p_after_attack({"player": 1, "card_id": 风攻击牌.id, "dst": 3})
	白名单 = 引擎.额外行动出牌白名单(玩家.额外行动数据(3803))
	检(白名单.has(风攻击牌.id) and not 白名单.has(火攻击牌.id),
		"手里没有风系攻击牌时，3803 的白名单仍应只含风系攻击牌：%s" % str(白名单))

	# ============================================================
	# 3805 精灵的剑舞
	# ============================================================
	_重置战斗()
	玩家.hand_cards = []
	发送记录.clear()
	var 栏: Array = 角色.available_skills()
	检(栏.size() == 1, "游击士的技能栏应只有【精灵的剑舞】一项，实际 %d 项：%s" % [栏.size(), str(栏)])
	var 剑舞项: Dictionary = _取技能(栏, 3805)
	检(not 剑舞项.is_empty(), "【精灵的剑舞】(3805) 应下发到技能栏")
	检(int(剑舞项.get("type", 0)) == GConst.ActionType.AttackSkill, "3805 应作为攻击技能按钮下发")
	检(int(剑舞项.get("need_card", 0)) == 1 and int(剑舞项.get("need_target", 0)) == 1,
		"【精灵的剑舞】应要求 1 张攻击牌 + 1 名目标")
	检(not bool(剑舞项.get("enabled", true)), "手里没有攻击牌时【精灵的剑舞】应置灰")
	玩家.hand_cards = [火攻击牌.id]
	检(not bool(_取技能(角色.available_skills(), 3805).get("enabled", true)),
		"没有能量时【精灵的剑舞】应置灰")
	玩家.set_crystal(1)
	剑舞项 = _取技能(角色.available_skills(), 3805)
	检(bool(剑舞项.get("enabled", false)), "有能量且有攻击牌时【精灵的剑舞】应可点")
	检((剑舞项.get("cards", []) as Array).has(火攻击牌.id), "3805 的可点牌表应包含手里的攻击牌")
	检((剑舞项.get("targets", []) as Array) == [3, 4], "3805 的目标白名单应是两名对手：%s"
		% str(剑舞项.get("targets", [])))
	玩家.set_crystal(0)
	玩家.set_gem(1)
	检(bool(_取技能(角色.available_skills(), 3805).get("enabled", false)),
		"只有宝石时【精灵的剑舞】也应可点（宝石可顶水晶）")

	# 3805 校验
	var 剑舞动作: Dictionary = {"src_id": 1, "action_id": 3805, "card_ids": [火攻击牌.id], "dst_ids": [3]}
	检(角色.v_attack_skill(剑舞动作) == GConst.GE_SUCCESS, "合法的【精灵的剑舞】应通过校验")
	检(角色.v_attack_skill({"src_id": 2, "action_id": 3805, "card_ids": [火攻击牌.id], "dst_ids": [3]})
		!= GConst.GE_SUCCESS, "别人的【精灵的剑舞】行动不应通过校验")
	检(角色.v_attack_skill({"src_id": 1, "action_id": 3802, "card_ids": [火攻击牌.id], "dst_ids": [3]})
		!= GConst.GE_SUCCESS, "不是 3805 的攻击技能行动不应通过校验")
	检(角色.v_attack_skill({"src_id": 1, "action_id": 3805, "card_ids": [], "dst_ids": [3]})
		!= GConst.GE_SUCCESS, "没选攻击牌时不能发动【精灵的剑舞】")
	检(角色.v_attack_skill({"src_id": 1, "action_id": 3805, "card_ids": [火攻击牌.id], "dst_ids": [2]})
		!= GConst.GE_SUCCESS, "不能对队友发动【精灵的剑舞】")
	检(角色.v_attack_skill({"src_id": 1, "action_id": 3805, "card_ids": [法术牌.id], "dst_ids": [3]})
		!= GConst.GE_SUCCESS, "非攻击牌不能作为【精灵的剑舞】的攻击牌")
	玩家.set_gem(0)
	检(角色.v_attack_skill(剑舞动作) != GConst.GE_SUCCESS, "没有能量时不能发动【精灵的剑舞】")

	# 暗杀者潜行（横置）期间「不能成为主动攻击的目标」：技能栏目标与服务端校验都要拦住 3805
	_重置战斗()
	玩家.set_crystal(1)
	玩家.hand_cards = [火攻击牌.id]
	对手甲.role_id = 5
	var 暗杀角色: BattleRole = BattleRole.create(5, 对手甲, 引擎)
	检(暗杀角色 != null, "无法创建暗杀者角色（role_ansha）")
	if 暗杀角色 != null:
		对手甲.role = 暗杀角色
		对手甲.tap = true
		var 潜行目标: Array = _取技能(角色.available_skills(), 3805).get("targets", [])
		检(潜行目标 == [4],
			"横置（潜行）的暗杀者不应出现在 3805 的目标白名单：%s" % str(潜行目标))
		var 打潜行: Dictionary = {"src_id": 1, "action_id": 3805,
			"card_ids": [火攻击牌.id], "dst_ids": [3]}
		检(角色.v_attack_skill(打潜行) != GConst.GE_SUCCESS,
			"不能对潜行中（横置）的暗杀者发动 3805")
		检(角色.v_attack_skill({"src_id": 1, "action_id": 3805,
			"card_ids": [火攻击牌.id], "dst_ids": [4]}) == GConst.GE_SUCCESS,
			"对另一名可被攻击的对手仍可发动 3805")
		对手甲.tap = false
		检((_取技能(角色.available_skills(), 3805).get("targets", []) as Array) == [3, 4],
			"对手解除潜行后应重新回到 3805 的目标白名单")
		检(角色.v_attack_skill(打潜行) == GConst.GE_SUCCESS,
			"对手解除潜行后可以对它发动 3805")
		对手甲.role = null
	对手甲.role_id = 0

	# 3805 的命格口径：本次攻击按风系虚牌结算，虚牌既不继承真实攻击牌的命格，
	# 也不采用 66 卡面的【幻】命格 → harm 必须标 virtual_no_fate（阴阳转换等「同命格」判定不能匹配）
	_重置战斗()
	玩家.set_crystal(1)
	玩家.hand_cards = [火攻击牌.id]
	检(角色.p_attack_skill({"src_id": 1, "action_id": 3805,
		"card_ids": [火攻击牌.id], "dst_ids": [3]}) == BattleRole.URGENT,
		"发动 3805 后应压入本次攻击状态")
	var 剑舞状态: Variant = null
	for i: int in range(引擎._states.size() - 1, -1, -1):
		if 引擎._states[i] is BattleEngine.SAttackCard:
			剑舞状态 = 引擎._states[i]
			break
	检(剑舞状态 is BattleEngine.SAttackCard, "3805 应压入一次攻击状态（实际 %s）" % str(引擎._states))
	if 剑舞状态 is BattleEngine.SAttackCard:
		var 剑舞牌状态: BattleEngine.SAttackCard = 剑舞状态
		检(int(剑舞牌状态.card) == 66, "3805 本次攻击应按风系虚牌 66 结算，实际 %d" % int(剑舞牌状态.card))
		检(int(剑舞牌状态.harm.get("card_id", 0)) == 66, "3805 的 harm 应按 66 结算")
		检(bool(剑舞牌状态.harm.get("virtual_no_fate", false)),
			"3805 的虚牌攻击必须标 virtual_no_fate（不吃真实牌 / 66 卡面的命格）：%s"
			% str(剑舞牌状态.harm))
	_重置战斗()

	# 3805 完整流水线：支付能量、本次攻击按风系【风神斩】结算、3803 白名单变风系
	_重置战斗()
	玩家.set_crystal(1)
	玩家.hand_cards = [火攻击牌.id, 风攻击牌.id, 火攻击牌2.id]
	对手甲.hand_cards = [风攻击牌.id, 火攻击牌2.id]
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.AttackSkill, {
		"src_id": 1, "action_id": 3805, "card_ids": [火攻击牌.id], "dst_ids": [3],
	})
	引擎.run()
	检(玩家.get_energy() == 0, "【精灵的剑舞】应支付 1 点能量，实际还剩 %d" % 玩家.get_energy())
	检(not 玩家.hand_cards.has(火攻击牌.id), "【精灵的剑舞】打出的攻击牌应离手")
	检(引擎.deck.discard.has(火攻击牌.id), "【精灵的剑舞】打出的真牌应进入弃牌堆")
	检(_播报次数(3805) == 1, "【精灵的剑舞】应播报一次")
	检(引擎._await_id == 3, "【精灵的剑舞】的主动攻击应等对手应战（等待 %s）" % str(引擎._await_id))
	var 剑舞应战: Dictionary = _取询问(3, GConst.RespondType.ReplyAttack)
	检(not 剑舞应战.is_empty(), "【精灵的剑舞】没有下发应战询问")
	var 剑舞应战参数: Array = 剑舞应战.get("args", [])
	检(剑舞应战参数.size() > 1 and int(剑舞应战参数[1]) == 66,
		"【精灵的剑舞】本次攻击牌应视为风系【风神斩】(66)：%s" % str(剑舞应战参数))
	# 视为风系：目标用风系牌可应战、用火系牌不可应战（对照：若按真实火牌结算，火系牌才可应战）
	var 目标: BattlePlayer = 引擎.p(3)
	检(目标.v_reattack(风攻击牌.id, 66) == GConst.GE_SUCCESS, "风系攻击应允许风系牌应战")
	检(目标.v_reattack(火攻击牌2.id, 66) != GConst.GE_SUCCESS, "视为风系后火系牌不能应战")
	检(目标.v_reattack(火攻击牌2.id, 火攻击牌.id) == GConst.GE_SUCCESS,
		"对照：真实火系攻击牌才允许火系牌应战（证明本次攻击牌已被视为风系）")
	# 目标放弃应战 → 命中 → 3803 给「同系（风）」的额外攻击行动
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(玩家.additional_actions.size() == 1, "3805 攻击命中后【二重剑影】应给 1 份额外攻击行动")
	if 玩家.additional_actions.size() == 1:
		检(int(玩家.additional_actions[0].get("cause", 0)) == 3803, "3805 攻击后的额外行动来源应是 3803")
	白名单 = 引擎.额外行动出牌白名单(玩家.额外行动数据(3803))
	检(白名单.has(风攻击牌.id) and not 白名单.has(火攻击牌.id),
		"3805 视为风系后，3803 的额外攻击应只允许风系攻击牌：%s" % str(白名单))
	检(引擎.校验额外行动限制(玩家, 玩家.额外行动数据(3803), GConst.ActionType.Attack,
		[火攻击牌2.id], [3]) != GConst.GE_SUCCESS,
		"额外攻击行动里提交火系攻击牌应被服务端驳回")
	检(引擎.校验额外行动限制(玩家, 玩家.额外行动数据(3803), GConst.ActionType.Attack,
		[风攻击牌.id], [3]) == GConst.GE_SUCCESS,
		"额外攻击行动里提交风系攻击牌应通过校验")

	# 3805 的费用【水晶】可用宝石顶（完整流水线再验一次）
	_重置战斗()
	玩家.set_gem(1)
	玩家.hand_cards = [火攻击牌.id]
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.AttackSkill, {
		"src_id": 1, "action_id": 3805, "card_ids": [火攻击牌.id], "dst_ids": [3],
	})
	引擎.run()
	检(玩家.get_energy() == 0 and 玩家.gem == 0,
		"只有宝石时【精灵的剑舞】应扣 1 点宝石，实际能量 %d / 宝石 %d" % [玩家.get_energy(), 玩家.gem])
	检(引擎._await_id == 3, "用宝石支付时【精灵的剑舞】也应进入应战询问（等待 %s）" % str(引擎._await_id))

	# 命格实测：真实攻击牌（火系，不是【幻】命格）经 3805 视为风系后，不能被 66 卡面的
	# 【幻】命格误触发阴阳师的【阴阳转换】；对照：真实【风神斩】(66) 的【幻】命格攻击可以发动。
	# 67【风神斩】也是【幻】命格攻击牌，放在阴阳师手里作对照。
	_重置战斗()
	玩家.set_crystal(1)
	玩家.hand_cards = [火攻击牌.id]
	对手甲.role_id = 33
	var 阴阳角色: BattleRole = BattleRole.create(33, 对手甲, 引擎)
	检(阴阳角色 != null, "无法创建阴阳师角色（role_yinyang）")
	if 阴阳角色 != null:
		对手甲.role = 阴阳角色
		对手甲.hand_cards = [67]
		发送记录.clear()
		引擎.resolve_action(GConst.ActionType.AttackSkill, {
			"src_id": 1, "action_id": 3805, "card_ids": [火攻击牌.id], "dst_ids": [3],
		})
		引擎.run()
		var 阴阳问: Dictionary = _取询问(3, GConst.技能_阴阳转换)
		检(not 阴阳问.is_empty(), "3805 的攻击应照常询问阴阳师【阴阳转换】（用不了的档位置灰也要问）")
		var 阴阳可用: Array = 阴阳问.get("option_enabled", [])
		检(阴阳可用.size() == 3 and not bool(阴阳可用[1]) and not bool(阴阳可用[2]),
			"3805 的虚牌攻击不应允许【阴阳转换】：%s" % str(阴阳可用))
		# 对照：直接的真实 66（【幻】）攻击 + 手里同命格的 67 → 3306 的阴阳转换档位可用
		_重置战斗()
		对手甲.hand_cards = [67]
		引擎.push(BattleEngine.SAttackCard.new(1, 3, 66, {
			"src": 1, "dst": 3, "point": BattleEngine.ATTACK_BASE_POINT,
			"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
			"card_id": 66, "is_active": true,
		}))
		引擎.run()
		var 对照问: Dictionary = _取询问(3, GConst.技能_阴阳转换)
		检(not 对照问.is_empty(), "对照攻击也应询问【阴阳转换】")
		var 对照可用: Array = 对照问.get("option_enabled", [true, true, true])
		检(对照可用.size() == 3 and bool(对照可用[1]),
			"对照：真实【幻】命格攻击应允许【阴阳转换】：%s" % str(对照问))
		对手甲.role = null
	对手甲.role_id = 0

	# ============================================================
	# 3804 附魔之术
	# ============================================================
	# 提炼时没有子弹：直接问选 1 张手牌扣置（选中＋确定即发动），扣 1 能量
	_重置战斗()
	玩家.hand_cards = [法术牌.id]
	玩家.set_gem(1)   # 模拟提炼刚拿到的 1 点能量
	检(角色.v_extract([1, 0], 1, 0, []) == GConst.GE_SUCCESS, "常规提炼应通过校验")
	发送记录.clear()
	检(角色.p_after_special({"player": 1, "special_action": true}) == BattleRole.WAIT,
		"提炼后没有【子弹】时应直接问选 1 张手牌扣置")
	var 附魔问: Dictionary = _取询问(1, 3804)
	检(not 附魔问.is_empty(), "没有下发【附魔之术】询问")
	var 附魔参数: Array = 附魔问.get("args", [])
	检(附魔参数.size() >= 1 and int(附魔参数[0]) == 1, "【附魔之术】应要求 1 张手牌：%s" % str(附魔参数))
	_应答([1], [法术牌.id])
	检(角色.p_after_special({"player": 1, "special_action": true}) == BattleRole.SUCCESS,
		"选完手牌后【附魔之术】应正常收尾")
	检(玩家.get_energy() == 0, "【附魔之术】应消耗 1 点能量，实际还剩 %d" % 玩家.get_energy())
	检(not 玩家.hand_cards.has(法术牌.id), "扣置的牌应离手")
	检(玩家.cover_count() == 1 and 玩家.cover_cards.has(法术牌.id),
		"扣置的牌应面朝下成为【子弹】：%s" % str(玩家.cover_cards))
	检(_播报次数(3804) == 1, "【附魔之术】应播报一次")

	# 已有子弹：不询问
	_重置战斗()
	玩家.hand_cards = [法术牌.id]
	玩家.set_gem(1)
	_放子弹(火子弹)
	角色.v_extract([1, 0], 1, 0, [])
	检(角色.p_after_special({"player": 1, "special_action": true}) == BattleRole.SUCCESS,
		"已有【子弹】时【附魔之术】不应发动")

	# 提炼 0 能量：不询问
	_重置战斗()
	玩家.hand_cards = [法术牌.id]
	玩家.set_gem(1)
	角色.v_extract([0, 0], 1, 1, [])
	检(角色.p_after_special({"player": 1, "special_action": true}) == BattleRole.SUCCESS,
		"提炼出 0 能量时【附魔之术】不应发动")

	# 不是提炼（如购买 / 技能行动）：不询问
	_重置战斗()
	玩家.hand_cards = [法术牌.id]
	玩家.set_gem(1)
	检(角色.p_after_special({"player": 1}) == BattleRole.SUCCESS,
		"不是特殊行动（提炼）时不应询问【附魔之术】")
	检(角色.p_after_special({"player": 1, "kind": "special", "is_skill": true, "action_id": 3805})
		== BattleRole.SUCCESS, "特殊技能行动不是提炼，不应询问【附魔之术】")

	# 提炼时取消：不扣能量 / 不扣手牌
	_重置战斗()
	玩家.hand_cards = [法术牌.id]
	玩家.set_gem(1)
	角色.v_extract([1, 0], 1, 0, [])
	角色.p_after_special({"player": 1, "special_action": true})
	_应答([])
	检(角色.p_after_special({"player": 1, "special_action": true}) == BattleRole.SUCCESS,
		"取消【附魔之术】应正常收尾")
	检(玩家.get_energy() == 1 and 玩家.cover_count() == 0 and 玩家.hand_cards.has(法术牌.id),
		"取消【附魔之术】不应扣能量 / 扣手牌")

	# 完整提炼流水线：提炼 → 问【附魔之术】 → 扣 1 能量把 1 张手牌变成子弹
	_重置战斗()
	玩家.hand_cards = [法术牌.id]
	引擎.set_team_gem(GConst.BLUE, 1)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [1, 0], "card_ids": [], "dst_ids": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "完整提炼流水线里应直接问选 1 张手牌扣置（等待 %s）" % str(引擎._await_id))
	检(not _取询问(1, 3804).is_empty(), "完整提炼流水线没有下发【附魔之术】询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3804, "src_id": 1, "args": [1], "card_ids": [法术牌.id], "dst_ids": [],
	})
	检(玩家.get_energy() == 0, "完整提炼流水线里【附魔之术】应扣掉提炼出的 1 能量，实际 %d" % 玩家.get_energy())
	检(玩家.cover_count() == 1 and 玩家.cover_cards.has(法术牌.id),
		"完整提炼流水线里扣置的牌应成为【子弹】：%s" % str(玩家.cover_cards))
	检(int(引擎.team_gem[GConst.BLUE]) == 0, "提炼应已把战绩区 1 宝石取走")

	# 客户端：3803 按钮文案（与修罗连斩同口径）＋ 3802 水 / 地选目标的头像预览
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(1)
	检(str(窗.call("_额外行动按钮文本", GConst.技能_二重剑影, GConst.ActionType.Attack,
		GConst.CardElement.Wind)) == "额外风系【攻击行动】",
		"二重剑影按钮应只写「额外风系【攻击行动】」：%s" % str(窗.call("_额外行动按钮文本",
			GConst.技能_二重剑影, GConst.ActionType.Attack, GConst.CardElement.Wind)))
	窗.set("_mode", 3)
	窗.set("_skill_ask_id", GConst.技能_元素射击SORA)
	窗.set("_skill_ask_need_target", 1)
	窗.set("_pending", {"preview_base": 1, "preview_kind": GConst.预览类型_治疗, "preview_ids": [1, 2]})
	窗.set("_sel_players", [] as Array[int])
	检((窗.call("_预览伤害头像提示") as Dictionary).is_empty(),
		"还没选目标时不应给每个候选人画治疗预览")
	窗.set("_sel_players", [2] as Array[int])
	var 提示: Dictionary = 窗.call("_预览伤害头像提示")
	检(str(提示.get(2, "")) == "+1 治疗" and not 提示.has(1),
		"只应在点选的目标头像上预览「+1 治疗」：%s" % str(提示))
	窗.set("_pending", {"preview_base": 1, "preview_kind": GConst.HarmType.Magic, "preview_ids": [1]})
	窗.set("_sel_players", [1] as Array[int])
	提示 = 窗.call("_预览伤害头像提示")
	检(str(提示.get(1, "")) == "1 点法术伤害", "地系选目标应预览「1 点法术伤害」：%s" % str(提示))
	窗.set("_sel_players", [] as Array[int])
	检((窗.call("_预览伤害头像提示") as Dictionary).is_empty(),
		"取消选中后不应再画伤害预览")
	窗.queue_free()
	await 等帧(1)

	# 客户端：选子弹与视为系别合成一次询问 —— 选项默认置灰，只有选中光/暗子弹才亮
	_重置战斗()
	_放子弹(水子弹)
	_放子弹(光子弹)
	var 合成上下文: Dictionary = _攻击上下文(水攻击牌, 1, 3, true)
	角色.p_timeline_1(合成上下文)
	var 合成命令: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	Logic.my_player_id = 1
	var 旧盖牌: Array[GCard] = Data.cover_cards
	var 旧盖牌实例: Array[int] = Data.cover_iids
	Data.cover_cards = [Data.get_card(水子弹.id), Data.get_card(光子弹.id)] as Array[GCard]
	Data.cover_iids = [水子弹.id, 光子弹.id]
	var 窗2: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗2)
	await 等帧(1)
	窗2.call("_on_command", {"cmd_type": GConst.CmdType.Respond, "commands": 合成命令})
	await 等帧(1)
	检((窗2.get("_二级选项") as Array).size() == 5, "元素射击应把 5 个视为系别选项摆出来")
	检(_选项全灰(窗2), "还没选子弹时 5 个视为系别选项应全灰")
	检(bool(窗2.call("_确定不可用")), "还没选子弹时不能点确定")
	窗2.call("_on_card_clicked", 水子弹.id)
	await 等帧(1)
	检(not bool(窗2.call("_选中子弹是光暗")), "普通子弹不应被认作光/暗")
	检(_选项全灰(窗2), "选中普通子弹时视为系别选项应仍全灰")
	检(not bool(窗2.call("_确定不可用")), "普通子弹选中后应可直接确定")
	窗2.call("_on_card_clicked", 光子弹.id)
	await 等帧(1)
	检(bool(窗2.call("_选中子弹是光暗")), "光子弹应被认作光/暗")
	检(not _选项全灰(窗2), "选中光子弹后 5 个视为系别选项应点亮")
	检(bool(窗2.call("_确定不可用")), "光子弹还没选视为系别时不能确定")
	窗2.queue_free()
	await 等帧(1)
	Data.cover_cards = 旧盖牌
	Data.cover_iids = 旧盖牌实例

	# 收尾：清掉本次用例留下的等待 / 状态
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()

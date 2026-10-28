extends 自检用例
## R46 灵熙之潮（46）：4601 灵枝旨意 / 4602 邪灵退散 / 4603 伴响魂灵 /
## 4604 波涌之力 / 4605 怒潮荒涛 / 4606 海神御巫。
##
## 任务范围只有 role + test；4606 的封印 / 赐福借用走 F5-seal / F5-bless 的 helper，
## 4601 走 F4 的 v_basic_effect_target，4602 / 4604 走 F4 的 p_basic_effect_change /
## p_basic_effect_triggered。覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 六颗技能行 / 角色表灵涌槽（上限 4）/ 脚本未启用；
##   - 4601：46 不能成为基础效果目标；自己给自己放也被驳回且不扣牌；
##   - 4602：自己放置基础效果后选 1 名目标对手 1 点法术伤害；取消不造成伤害；
##            别人放置不触发；4606 借用放置也会触发；
##   - 4603：自己回合内对手因自己造成的伤害掉士气 → 其余对手各 1 点法术伤害；
##            每回合最多一次；不是自己回合 / 队友掉士气 / 别人造成的伤害都不触发；
##   - 4604：任意角色触发基础效果并结算完成后 +1 灵涌；上限 4；被拿走不算触发；
##   - 4605：灵涌满时回合结束清空并给场上每名角色 1 点法术伤害，目标每有 1 个基础效果 +1；
##            灵涌不满不触发；
##   - 4606：水晶费用（宝石可顶）、固定 7 个来源技能选项（不可用只置灰）、
##            选牌 + 目标 → 借用封印 / 赐福 → 4602 → 必弃 1 张牌；非法目标 / 缺能量被拒。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_lingxizhichao.gd")

const 灵枝旨意: int = 4601
const 邪灵退散: int = 4602
const 伴响魂灵: int = 4603
const 波涌之力: int = 4604
const 怒潮荒涛: int = 4605
const 海神御巫: int = 4606
const 地之封印技能号: int = 404
const 迅捷赐福技能号: int = 1601
const 威力赐福技能号: int = 1602

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 敌甲: BattlePlayer = null
var 敌乙: BattlePlayer = null
var 队友: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 封印牌: GCard = null
var 迅捷牌: GCard = null
var 威力牌: GCard = null
var 圣盾牌: GCard = null
var 普通牌: GCard = null


func _init() -> void:
	名称 = "灵熙之潮"


# ============================================================
# 取样 / 断言工具
# ============================================================
func _取带技能牌(技能号: int, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		if c.has_skill_id(技能号):
			return c
	return null


func _取卡名(卡名: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.card_name_enum() == 卡名:
			return c
	return null


## 一张不带 401~405 / 1601 / 1602 的普通牌（4606 的「弃 1 张牌」用）
func _取普通牌(排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		var 是来源: bool = false
		for 技能号: int in [401, 402, 403, 404, 405, 1601, 1602]:
			if c.has_skill_id(技能号):
				是来源 = true
				break
		if not 是来源:
			return c
	return null


## 任意一张指定系别的牌（4606 借用封印的「展示同系 / 异系牌」触发用）
func _取元素牌(元素值: int, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		if c.element_enum() == 元素值:
			return c
	return null


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


## 状态栈里找一条指定来源 / 目标的伤害（借用封印触发后的 3 点法术伤害用）
func _找伤害(cause: int, dst: int) -> Dictionary:
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var harm: Variant = st.get("harm")
		if harm is Dictionary:
			var h: Dictionary = harm
			if int(h.get("cause", 0)) == cause and int(h.get("dst", -1)) == dst:
				return h
	return {}


func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("pid", 0)) == pid and int(r.get("msg", 0)) == GConst.Msg.ErrorInput:
			return true
	return false


func _填手牌(p0: BattlePlayer, 张数: int, card_id: int) -> void:
	p0.hand_cards.clear()
	for _i: int in range(张数):
		p0.hand_cards.append(card_id)


## 清空战斗状态：四个座位固定（1 / 3 蓝，2 / 4 红），46 重新挂一份角色脚本；
## 手牌 / 基础效果 / 额外行动 / 能量 / 士气 / 弃牌堆都回到同一起点。
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
	引擎.set_morale(GConst.BLUE, GConst.MORALE_DEFAULT)
	引擎.set_morale(GConst.RED, GConst.MORALE_DEFAULT)
	引擎.set_team_gem(GConst.BLUE, 0)
	引擎.set_team_gem(GConst.RED, 0)
	引擎.set_team_crystal(GConst.BLUE, 0)
	引擎.set_team_crystal(GConst.RED, 0)
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
	玩家.role_id = 46
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色


## 让目标手牌超限，然后吃 1 点法术伤害；返回时引擎在等目标选超限弃牌
func _压伤害并等超限弃牌(攻击者: int, 目标: BattlePlayer, cause: int) -> void:
	_填手牌(目标, GConst.HAND_CARDS_MAX, 普通牌.id)
	引擎.push_harm({
		"src": 攻击者, "dst": 目标.id, "point": 1,
		"cause": cause, "type": GConst.HarmType.Magic,
	})
	引擎.run()


## 回复目标的超限弃牌（弃 1 张）
func _回复超限弃牌(目标: BattlePlayer) -> void:
	引擎.on_message(目标.id, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Discard, "src_id": 目标.id,
		"args": [目标.id, GConst.CAUSE_OVERLOAD, 1],
		"card_ids": [普通牌.id], "dst_ids": [目标.id],
	})


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能行 / 灵涌槽 / 脚本未启用 ----
	检(str(Data.role_list.get(46, "")) == "灵熙之潮", "46 号角色名不是「灵熙之潮」")
	检(Data.role_personal_name(46) == "濯香姬", "46 号角色姓名不是「濯香姬」")
	检(absf(Data.role_star(46) - 3.5) < 0.01, "灵熙之潮应是 3.5 星，实际 %s" % str(Data.role_star(46)))
	检(Data.role_skills(46) == [4601, 4602, 4603, 4604, 4605, 4606],
		"灵熙之潮技能号不对：%s" % str(Data.role_skills(46)))
	var 灵涌: Dictionary = Data.role_token_def(46, 0)
	检(str(灵涌.get("name", "")) == "灵涌", "46 号槽 0 指示物名应是「灵涌」：%s" % str(灵涌))
	检(int(灵涌.get("max", 0)) == 4, "46 号灵涌上限应是 4：%s" % str(灵涌))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_lingxizhichao.gd"),
		"灵熙之潮的角色脚本文件不存在")
	for 技能号: int in [4601, 4602, 4603, 4604, 4605, 4606]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	检(GConst.技能号("技能#灵熙之潮#海神御巫") == 4606, "海神御巫的技能号不是 4606")
	var 技能说明: String = Data.role_skill_info(46)
	for 技能名: String in ["灵枝旨意", "邪灵退散", "伴响魂灵", "波涌之力", "怒潮荒涛", "海神御巫"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])
	# 借用的源技能行必须都在（4606 播报 / 提示按源技能号取）
	for 源号: int in [401, 402, 403, 404, 405, 1601, 1602]:
		检(not GConst.技能行(源号).is_empty(), "技能表里查不到借用的源技能 %d" % 源号)

	# ---- 卡库前提 ----
	封印牌 = _取带技能牌(地之封印技能号)
	迅捷牌 = _取带技能牌(迅捷赐福技能号)
	威力牌 = _取带技能牌(威力赐福技能号)
	圣盾牌 = _取卡名(GConst.CardName.Shield)
	普通牌 = _取普通牌()
	检(封印牌 != null, "卡库找不到带 404【地之封印】的牌")
	检(迅捷牌 != null, "卡库找不到带 1601【迅捷赐福】的牌")
	检(威力牌 != null, "卡库找不到带 1602【威力赐福】的牌")
	检(圣盾牌 != null, "卡库找不到【圣盾】")
	检(普通牌 != null, "卡库找不到普通牌")
	if 封印牌 == null or 迅捷牌 == null or 威力牌 == null or 圣盾牌 == null or 普通牌 == null:
		return

	# ---- 建引擎：1 / 3 蓝，2 / 4 红；角色表脚本列留给 DATA，用例里手动挂 46 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "灵熙")
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
	# 4601 灵枝旨意：无法成为基础效果的目标
	# ============================================================
	检(玩家.token_num(0) == 0, "开局灵涌应为 0，实际 %d" % 玩家.token_num(0))
	检(玩家.v_basic_effect_target(圣盾牌.id) == GConst.GE_INVALID_PLAYERID,
		"4601：46 自己必须拒绝成为基础效果的目标")
	检(引擎.v_basic_effect_target(1, 圣盾牌.id) == GConst.GE_INVALID_PLAYERID,
		"4601：引擎对 46 的基础效果目标资格应被拒")
	检(引擎.v_basic_effect_target(3, 圣盾牌.id) == GConst.GE_SUCCESS,
		"普通角色应仍可作为基础效果目标")
	检(引擎.add_basic_effect(1, 圣盾牌.id, 2) == GConst.GE_INVALID_PLAYERID,
		"4601：add_basic_effect 兜底应拒绝把基础效果挂到 46 面前")
	检(玩家.basic_effects.is_empty(), "4601：被拒的基础效果不应挂到 46 面前")

	_重置战斗()
	发送记录.clear()
	玩家.hand_cards.append(圣盾牌.id)
	引擎.resolve_action(GConst.ActionType.Magic, {
		"card_ids": [圣盾牌.id], "dst_ids": [1], "args": [],
	})
	引擎.run()
	检(_有错误输入(1), "4601：46 把圣盾放到自己身上应被驳回")
	检(玩家.hand_cards.has(圣盾牌.id), "4601：被驳回的圣盾不应离手")
	检(玩家.basic_effects.is_empty(), "4601：被驳回的圣盾不应挂到自己面前")

	# ============================================================
	# 4602 邪灵退散：自己放置基础效果后 → 1 名目标对手 1 点法术伤害
	# ============================================================
	_重置战斗()
	玩家.hand_cards.append(圣盾牌.id)
	引擎.resolve_action(GConst.ActionType.Magic, {
		"card_ids": [圣盾牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(队友.basic_effects.size() == 1, "4602：46 放到队友面前的圣盾应正常挂上")
	检(引擎._await_id == 1, "4602：放置基础效果后应询问 46 选目标对手（等待 %s）" % str(引擎._await_id))
	var 邪灵问: Dictionary = _取询问(1, 邪灵退散)
	检(not 邪灵问.is_empty(), "4602：没有下发【邪灵退散】的目标询问")
	检((邪灵问.get("dst_ids", []) as Array).has(2) and (邪灵问.get("dst_ids", []) as Array).has(4),
		"4602：目标白名单应包含两名对手：%s" % str(邪灵问.get("dst_ids", [])))
	检(not (邪灵问.get("dst_ids", []) as Array).has(1)
		and not (邪灵问.get("dst_ids", []) as Array).has(3),
		"4602：不能选自己或队友")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [2],
	})
	检(敌甲.hand_cards.size() == 1, "4602：目标应受 1 点法术伤害（摸 1 张），实际 %d 张"
		% 敌甲.hand_cards.size())
	检(_播报次数(邪灵退散) == 1, "4602：发动后应播报 1 次，实际 %d 次" % _播报次数(邪灵退散))

	# 取消：不造成伤害
	_重置战斗()
	玩家.hand_cards.append(圣盾牌.id)
	引擎.resolve_action(GConst.ActionType.Magic, {
		"card_ids": [圣盾牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "4602：取消场景应先询问 46")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [],
	})
	检(敌甲.hand_cards.is_empty(), "4602：取消后不应造成伤害")
	检(_播报次数(邪灵退散) == 0, "4602：取消后不应播报")

	# 别人放置基础效果：不触发 46 的 4602
	_重置战斗()
	引擎.current_id = 2
	敌甲.hand_cards.append(圣盾牌.id)
	引擎.resolve_action(GConst.ActionType.Magic, {
		"card_ids": [圣盾牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(_取询问(1, 邪灵退散).is_empty(), "4602：别人放置基础效果不应由 46 触发")
	检(引擎._await_id != 1, "4602：别人放置时不应等 46 回复")

	# ============================================================
	# 4603 伴响魂灵：自己回合内对手因自己造成的伤害掉士气 → 其余对手各 1 点
	# ============================================================
	_重置战斗()
	引擎.current_id = 1
	发送记录.clear()
	_压伤害并等超限弃牌(1, 敌甲, 邪灵退散)
	检(引擎._await_id == 2, "4603：目标超限时应等目标选弃牌（等待 %s）" % str(引擎._await_id))
	_回复超限弃牌(敌甲)
	检(_播报次数(伴响魂灵) == 1, "4603：对手因 46 的伤害掉士气后应播报 1 次，实际 %d 次"
		% _播报次数(伴响魂灵))
	检(敌乙.hand_cards.size() == 1, "4603：除该对手外其余对手应各受 1 点法术伤害（摸 1 张），实际 %d 张"
		% 敌乙.hand_cards.size())
	检(int(引擎.team_morale[GConst.RED]) == GConst.MORALE_DEFAULT - 1,
		"4603：红队士气应下降 1，实际 %d" % int(引擎.team_morale[GConst.RED]))

	# 每回合最多一次：同一回合再掉一次士气不再触发
	敌乙.hand_cards.clear()
	_压伤害并等超限弃牌(1, 敌甲, 邪灵退散)
	检(引擎._await_id == 2, "4603：第二次超限也应等目标弃牌")
	_回复超限弃牌(敌甲)
	检(_播报次数(伴响魂灵) == 1, "4603：同一回合第二次掉士气不应再次触发（回合限定）")
	检(敌乙.hand_cards.is_empty(), "4603：同一回合第二次掉士气不应再对其余对手造成伤害")

	# 不是自己的回合：不触发
	_重置战斗()
	引擎.current_id = 2
	发送记录.clear()
	_压伤害并等超限弃牌(1, 敌乙, 邪灵退散)
	if 引擎._await_id == 4:
		_回复超限弃牌(敌乙)
	检(_播报次数(伴响魂灵) == 0, "4603：不是 46 的回合不应触发")

	# 队友掉士气：不触发
	_重置战斗()
	引擎.current_id = 1
	发送记录.clear()
	_压伤害并等超限弃牌(1, 队友, 邪灵退散)
	if 引擎._await_id == 3:
		_回复超限弃牌(队友)
	检(_播报次数(伴响魂灵) == 0, "4603：队友掉士气（目标不是对手）不应触发")

	# 别人造成的伤害：不触发
	_重置战斗()
	引擎.current_id = 1
	发送记录.clear()
	_压伤害并等超限弃牌(2, 敌乙, 邪灵退散)
	if 引擎._await_id == 4:
		_回复超限弃牌(敌乙)
	检(_播报次数(伴响魂灵) == 0, "4603：不是 46 造成的伤害不应触发")

	# ============================================================
	# 4604 波涌之力：任意角色触发基础效果并结算完成后 +1 灵涌
	# ============================================================
	_重置战斗()
	检(玩家.token_name(0) == "灵涌" and 玩家.token_max(0) == 4,
		"4604：灵涌名称 / 上限应来自角色表：%s / %s" % [玩家.token_name(0), str(玩家.token_max(0))])
	检(引擎.add_basic_effect(2, 圣盾牌.id, 2) == GConst.GE_SUCCESS, "4604：前置圣盾应能放上")
	引擎.run()
	for i: int in range(4):
		检(引擎.add_basic_effect(2, 圣盾牌.id, 2) == GConst.GE_SUCCESS, "4604：第 %d 次放置圣盾失败" % (i + 1))
		引擎.run()
		引擎.remove_basic_effect(2, 圣盾牌.id, GConst.CAUSE_ATTACK, -1, true)
		引擎.run()
		检(玩家.token_num(0) == i + 1, "4604：第 %d 次基础效果触发后灵涌应为 %d，实际 %d"
			% [i + 1, i + 1, 玩家.token_num(0)])
	# 上限 4：再触发不涨
	检(引擎.add_basic_effect(2, 圣盾牌.id, 2) == GConst.GE_SUCCESS, "4604：上限测试放置圣盾失败")
	引擎.run()
	引擎.remove_basic_effect(2, 圣盾牌.id, GConst.CAUSE_ATTACK, -1, true)
	引擎.run()
	检(玩家.token_num(0) == 4, "4604：灵涌上限应为 4，实际 %d" % 玩家.token_num(0))
	# 被拿走（不是触发）不加灵涌
	检(引擎.add_basic_effect(2, 圣盾牌.id, 2) == GConst.GE_SUCCESS, "4604：非触发移除测试放置圣盾失败")
	引擎.run()
	引擎.remove_basic_effect(2, 圣盾牌.id, GConst.CAUSE_USE, 2)
	引擎.run()
	检(玩家.token_num(0) == 4, "4604：被拿走的基础效果不应算触发、不应加灵涌")

	# ============================================================
	# 4605 怒潮荒涛：回合结束灵涌满 → 清空并对场上所有角色各 1 点（每 1 个基础效果 +1）
	# ============================================================
	_重置战斗()
	玩家.set_token_num(0, 4)
	敌甲.add_basic_effect(圣盾牌.id, 2)
	敌甲.add_basic_effect(封印牌.id, 2)
	队友.add_basic_effect(圣盾牌.id, 1)
	发送记录.clear()
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(玩家.token_num(0) == 0, "4605：触发后应移除所有灵涌，实际 %d" % 玩家.token_num(0))
	检(_播报次数(怒潮荒涛) == 1, "4605：触发应播报 1 次，实际 %d 次" % _播报次数(怒潮荒涛))
	检(玩家.hand_cards.size() == 1, "4605：自己 0 个基础效果应受 1 点法术伤害（摸 1 张），实际 %d 张"
		% 玩家.hand_cards.size())
	检(敌甲.hand_cards.size() == 3, "4605：2 个基础效果的对手应受 1+2=3 点（摸 3 张），实际 %d 张"
		% 敌甲.hand_cards.size())
	检(队友.hand_cards.size() == 2, "4605：1 个基础效果的队友应受 1+1=2 点（摸 2 张），实际 %d 张"
		% 队友.hand_cards.size())
	检(敌乙.hand_cards.size() == 1, "4605：0 个基础效果的对手应受 1 点（摸 1 张），实际 %d 张"
		% 敌乙.hand_cards.size())

	# 灵涌不满：不触发
	_重置战斗()
	玩家.set_token_num(0, 3)
	发送记录.clear()
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(玩家.token_num(0) == 3, "4605：灵涌不满时不应清空，实际 %d" % 玩家.token_num(0))
	检(_播报次数(怒潮荒涛) == 0, "4605：灵涌不满时不应播报")
	检(玩家.hand_cards.is_empty() and 敌甲.hand_cards.is_empty(),
		"4605：灵涌不满时不应造成伤害")
	# 不是自己的回合结束：不触发
	_重置战斗()
	玩家.set_token_num(0, 4)
	发送记录.clear()
	引擎.current_id = 2
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(玩家.token_num(0) == 4 and _播报次数(怒潮荒涛) == 0,
		"4605：不是 46 的回合结束不应触发")

	# ============================================================
	# 4606 海神御巫：技能栏 / 校验
	# ============================================================
	_重置战斗()
	var 海神项: Dictionary = _找技能(角色.available_skills(), 海神御巫)
	检(not 海神项.is_empty(), "4606：技能栏应下发【海神御巫】")
	检(int(海神项.get("type", 0)) == GConst.ActionType.MagicSkill, "4606：应作为法术技能按钮下发")
	检(int(海神项.get("need_card", 0)) == 0 and int(海神项.get("need_target", 0)) == 0,
		"4606：牌与目标由服务端询问，技能按钮本身不预选")
	检(not bool(海神项.get("enabled", true)), "4606：没有能量 / 可用独有技牌时应置灰，不是消失")
	玩家.hand_cards.append(封印牌.id)
	玩家.set_crystal(1)
	海神项 = _找技能(角色.available_skills(), 海神御巫)
	检(bool(海神项.get("enabled", false)), "4606：有 1 点水晶 + 独有技牌时应可点")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 海神御巫, "card_ids": [], "dst_ids": []})
		== GConst.GE_SUCCESS, "4606：合法的技能行动应通过校验")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 海神御巫, "card_ids": [], "dst_ids": []})
		!= GConst.GE_SUCCESS, "4606：别人的海神御巫行动不应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 9999, "card_ids": [], "dst_ids": []})
		!= GConst.GE_SUCCESS, "4606：不是海神御巫的法术技能行动不应通过校验")
	检(角色.v_magic_skill({
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [封印牌.id], "dst_ids": [3],
	}) != GConst.GE_SUCCESS, "4606：封印牌不能放到同色队友面前")
	玩家.hand_cards.append(迅捷牌.id)
	检(角色.v_magic_skill({
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [迅捷牌.id], "dst_ids": [2],
	}) != GConst.GE_SUCCESS, "4606：赐福牌不能放到对手面前")
	玩家.set_crystal(0)
	检(角色.v_magic_skill({"src_id": 1, "action_id": 海神御巫, "card_ids": [], "dst_ids": []})
		!= GConst.GE_SUCCESS, "4606：没有能量时不能发动（宝石可顶水晶，见下一个场景）")

	# ---- 4606：选独有技时取消 → 不扣能量 / 不扣牌，退回行动阶段 ----
	_重置战斗()
	玩家.hand_cards.append(迅捷牌.id)
	玩家.set_crystal(1)
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [], "dst_ids": [], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "4606：取消场景应先下发独有技询问")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 海神御巫, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [],
	})
	检(玩家.get_energy() == 1 and 玩家.hand_cards.has(迅捷牌.id),
		"4606：取消选择后不应扣能量 / 扣牌")
	检(引擎._await_kind == GConst.Msg.Action, "4606：取消技能行动后应退回行动阶段重新选择行动")

	# ---- 4606：水晶费用 + 佩戴 404 地之封印（客户端一次带齐牌 / 目标）----
	_重置战斗()
	玩家.hand_cards.append(封印牌.id)
	玩家.hand_cards.append(普通牌.id)
	玩家.set_gem(1)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [封印牌.id], "dst_ids": [2], "args": [],
	})
	引擎.run()
	检(玩家.get_energy() == 0 and 玩家.gem == 0, "4606：【水晶】费用应允许用宝石支付")
	检(敌甲.basic_effects.size() == 1 and int(敌甲.basic_effects[0].get("card", -1)) == 封印牌.id,
		"4606：404 地之封印应放到目标对手面前")
	检(not 玩家.hand_cards.has(封印牌.id), "4606：借用的独有技牌应离手")
	检(引擎._await_id == 1, "4606：放置封印后应先询问 4602（等待 %s）" % str(引擎._await_id))
	检(not _取询问(1, 邪灵退散).is_empty(), "4606：借用放置也应触发 4602")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == 1, "4606：4602 之后应询问弃 1 张牌（等待 %s）" % str(引擎._await_id))
	var 弃牌问: Dictionary = _取询问(1, 海神御巫)
	检(not 弃牌问.is_empty(), "4606：没有下发「你弃 1 张牌」的询问")
	检(int((弃牌问.get("args", []) as Array)[0]) == 1, "4606：弃牌询问应要求 1 张牌")
	检(not bool(弃牌问.get("can_cancel", true)), "4606：弃 1 张牌是必付代价，客户端取消应置灰")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 海神御巫, "src_id": 1,
		"args": [], "card_ids": [普通牌.id], "dst_ids": [],
	})
	检(玩家.hand_cards.is_empty(), "4606：结算后手里的牌应已用掉 / 弃掉，实际 %d 张" % 玩家.hand_cards.size())
	检(引擎.deck.discard.has(普通牌.id), "4606：你弃的 1 张牌应进弃牌堆")
	检(_播报次数(海神御巫) == 1, "4606：应播报 1 次海神御巫，实际 %d 次" % _播报次数(海神御巫))
	检(_播报次数(地之封印技能号) == 1, "4606：借用封印应按源技能号 404 播报，实际 %d 次"
		% _播报次数(地之封印技能号))

	# ---- 4606：服务端先问「用哪一张独有技」，缺牌选项只置灰；借用 1601 赐福 ----
	_重置战斗()
	玩家.hand_cards.append(迅捷牌.id)
	玩家.hand_cards.append(普通牌.id)
	玩家.set_crystal(1)
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [], "dst_ids": [], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "4606：点击技能后应下发独有技询问（等待 %s）" % str(引擎._await_id))
	var 选技问: Dictionary = _取询问(1, 海神御巫)
	检(not 选技问.is_empty(), "4606：没有下发选择独有技的询问")
	var 备注: Array = 选技问.get("notes", [])
	检(备注.size() == 7, "4606：固定选项应完整下发 7 个来源技能，实际 %d 个" % 备注.size())
	检(备注.has("迅捷赐福"), "4606：选项里应有「迅捷赐福」：%s" % str(备注))
	var 选项可用: Array = 选技问.get("option_enabled", [])
	检(选项可用.size() == 7, "4606：应下发 7 个选项的可用状态：%s" % str(选项可用))
	检(选项可用.count(true) == 1, "4606：手里只有 1601 时只有一个选项可用：%s" % str(选项可用))
	检((选技问.get("card_ids", []) as Array) == [迅捷牌.id],
		"4606：可点牌应只有带来源技能的那张：%s" % str(选技问.get("card_ids", [])))
	检((选技问.get("dst_ids", []) as Array) == [3],
		"4606：1601 的可点目标应只有同色队友 3：%s" % str(选技问.get("dst_ids", [])))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 海神御巫, "src_id": 1,
		"args": [迅捷赐福技能号], "card_ids": [迅捷牌.id], "dst_ids": [3],
	})
	检(引擎._await_id == 1, "4606：借用赐福放置后应先询问 4602（等待 %s）" % str(引擎._await_id))
	检(not _取询问(1, 邪灵退散).is_empty(), "4606：借用赐福放置也应触发 4602")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [2],
	})
	检(引擎._await_id == 1, "4606：4602 之后应继续询问弃 1 张牌（等待 %s）" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 海神御巫, "src_id": 1,
		"args": [], "card_ids": [普通牌.id], "dst_ids": [],
	})
	检(队友.basic_effects.size() == 1 and int(队友.basic_effects[0].get("card", -1)) == 迅捷牌.id,
		"4606：1601 迅捷赐福应放到目标队友面前")
	检(玩家.get_energy() == 0, "4606：发动应支付 1 点能量")
	检(敌甲.hand_cards.size() == 1, "4606：借用放置触发的 4602 应对目标对手造成 1 点法术伤害")
	检(引擎.deck.discard.has(普通牌.id), "4606：借用赐福后同样要弃 1 张牌")
	检(_播报次数(迅捷赐福技能号) == 1, "4606：借用赐福应按源技能号 1601 播报，实际 %d 次"
		% _播报次数(迅捷赐福技能号))

	# ---- 4606：只有 1 张发动牌、弃牌时手里已空 → 跳过弃牌，不卡流程 ----
	_重置战斗()
	玩家.hand_cards.append(封印牌.id)
	玩家.set_crystal(1)
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [封印牌.id], "dst_ids": [2], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "4606：单牌场景应先询问 4602")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id != 1 or 引擎.phase == BattleEngine.Phase.Over,
		"4606：发动牌用完后手里没牌时不应再问弃牌，也不应卡住等待")
	检(玩家.hand_cards.is_empty(), "4606：单牌场景结算后手牌应为空")

	# ============================================================
	# 4606 借用技的「触发」：本尊（4 封印师 / 16 祈祷师）不在场时，
	# 也必须由 46 自己转发 helper 的 p_show_hand / p_timeline_2_hit /
	# p_after_attack / p_after_magic / v_additional_action / p_additional_action
	# ============================================================
	# ---- 借用的 404：目标展示同系牌 → 3 点法术伤害 + 移除；异系不触发 ----
	var 地系牌: GCard = _取元素牌(封印牌.element_enum(), [封印牌.id, 圣盾牌.id, 普通牌.id])
	var 异系牌: GCard = _取元素牌(GConst.CardElement.Fire, [封印牌.id])
	检(地系牌 != null and 异系牌 != null, "卡库找不到地系 / 火系展示牌样本")
	if 地系牌 == null or 异系牌 == null:
		return
	_重置战斗()
	玩家.hand_cards.append(封印牌.id)
	玩家.set_crystal(1)
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [封印牌.id], "dst_ids": [2], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "借用封印：放置后应先询问 4602")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [],
	})
	检(敌甲.basic_effects.size() == 1 and int(敌甲.basic_effects[0].get("card", -1)) == 封印牌.id,
		"借用封印：404 应挂到敌甲面前")
	发送记录.clear()
	检(角色.p_show_hand({"player": 2, "cards": [异系牌.id]}) == BattleRole.SUCCESS,
		"借用封印：展示异系牌不应触发")
	检(敌甲.basic_effects.size() == 1, "借用封印：异系展示不应移除封印")
	检(角色.p_show_hand({"player": 2, "cards": [地系牌.id]}) == BattleRole.URGENT,
		"借用封印：展示同系牌应由 46 的 p_show_hand 触发（先结算伤害）")
	检(敌甲.basic_effects.is_empty(), "借用封印：触发后封印应被移除")
	检(引擎.deck.discard.has(封印牌.id), "借用封印：触发后的封印牌应进弃牌堆")
	var 封印伤害: Dictionary = _找伤害(地之封印技能号, 2)
	检(not 封印伤害.is_empty(), "借用封印：触发应对目标压入伤害")
	检(int(封印伤害.get("point", 0)) == 3, "借用封印：触发伤害应为 3 点，实际 %d"
		% int(封印伤害.get("point", 0)))
	检(int(封印伤害.get("type", 0)) == GConst.HarmType.Magic, "借用封印：触发的是法术伤害")
	检(int(封印伤害.get("src", -1)) == 1, "借用封印：伤害来源应是借用者 46")
	检(_播报次数(地之封印技能号) == 1, "借用封印：触发应按源技能号 404 播报")
	引擎._states.clear()
	引擎._清空等待()

	# ---- 借用的 1602：4606 放置 + 4602 + 弃牌照常走完，命中时 +2 并移除 ----
	_重置战斗()
	玩家.hand_cards.append(威力牌.id)
	玩家.hand_cards.append(普通牌.id)
	玩家.set_crystal(1)
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [威力牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "借用 1602：放置后应先询问 4602")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [2],
	})
	检(引擎._await_id == 1, "借用 1602：4602 之后应继续询问弃 1 张牌")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 海神御巫, "src_id": 1,
		"args": [], "card_ids": [普通牌.id], "dst_ids": [],
	})
	检(玩家.hand_cards.is_empty(), "借用 1602：4606 的弃牌代价应已付")
	检(引擎.deck.discard.has(普通牌.id), "借用 1602：弃掉的牌应进弃牌堆")
	检(队友.basic_effects.size() == 1 and int(队友.basic_effects[0].get("card", -1)) == 威力牌.id,
		"借用 1602：1602 应挂到队友面前")
	var 伤害: Dictionary = {
		"src": 3, "dst": 2, "point": 2,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
	}
	var 伤害上下文: Dictionary = {"harm": 伤害, "src": 3, "dst": 2, "is_active": true}
	检(角色.p_timeline_2_hit(伤害上下文) == BattleRole.WAIT,
		"借用 1602：命中时应先询问牌的所有者（队友 3）")
	var 威力问: Dictionary = _取询问(3, 威力赐福技能号)
	检(not 威力问.is_empty(), "借用 1602：没有向队友 3 下发【威力赐福】询问")
	检(int(威力问.get("preview_base", 0)) == 2, "借用 1602：询问应带原伤害 2")
	检((威力问.get("dst_ids", []) as Array).has(2), "借用 1602：受伤目标应作为固定目标下发")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(角色.p_timeline_2_hit(伤害上下文) == BattleRole.URGENT,
		"借用 1602：发动后应返回 URGENT（移除赐福要压基础效果钩子）")
	检(int(伤害.get("point", 0)) == 4, "借用 1602：命中伤害应 +2（2 → 4），实际 %d"
		% int(伤害.get("point", 0)))
	检(队友.basic_effects.is_empty(), "借用 1602：发动后威力赐福应被移除")
	检(引擎.deck.discard.has(威力牌.id), "借用 1602：移除的威力赐福应进弃牌堆")
	引擎._states.clear()
	引擎._清空等待()

	# ---- 借用的 1601：行动结束授予 +1 攻击行动，选中该行动时移除赐福 ----
	_重置战斗()
	玩家.hand_cards.append(迅捷牌.id)
	玩家.set_crystal(1)
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 海神御巫,
		"card_ids": [迅捷牌.id], "dst_ids": [3], "args": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "借用 1601：放置后应先询问 4602")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 邪灵退散, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [],
	})
	检(队友.basic_effects.size() == 1 and int(队友.basic_effects[0].get("card", -1)) == 迅捷牌.id,
		"借用 1601：1601 应挂到队友面前")
	队友.hand_cards.clear()
	队友.hand_cards.append(普通牌.id)
	队友.additional_actions.clear()
	检(角色.p_after_attack({"player": 3, "card_id": 普通牌.id, "dst": 2}) == BattleRole.SUCCESS,
		"借用 1601：行动结束钩子本身应返回 SUCCESS")
	检(队友.additional_actions.size() == 1, "借用 1601：持有者行动结束应获得 1 个额外行动")
	if 队友.additional_actions.size() == 1:
		检(int(队友.additional_actions[0].get("cause", 0)) == 迅捷赐福技能号
			and int(队友.additional_actions[0].get("allow_action", 0)) == GConst.ActionType.Attack,
			"借用 1601：额外行动应是 1601 授予的 1 次攻击")
	角色.p_after_magic({"player": 3, "card_id": 普通牌.id})
	检(队友.additional_actions.size() == 1, "借用 1601：同一份额外行动不应重复授予")
	检(角色.v_additional_action(迅捷赐福技能号) == GConst.GE_INVALID_ACTION,
		"借用 1601：46 自己面前不可能有赐福，二次校验应拒绝")
	检(角色.v_additional_action(9999) == BattleRole.V_NOT_OVERRIDE,
		"借用 1601：非迅捷赐福的额外行动必须回退 V_NOT_OVERRIDE，不能覆写成失败")
	引擎._确认基础效果额外行动(3, 迅捷赐福技能号)
	检(队友.basic_effects.is_empty(), "借用 1601：确认额外行动后迅捷赐福应被移除")
	检(引擎.deck.discard.has(迅捷牌.id), "借用 1601：移除的迅捷赐福应进弃牌堆")
	引擎._确认基础效果额外行动(3, 迅捷赐福技能号)
	检(队友.basic_effects.is_empty(), "借用 1601：赐福已移除后重复确认应安全")
	引擎._states.clear()
	引擎._清空等待()

	# 收尾：清掉状态栈与等待，避免退出时残留询问
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()

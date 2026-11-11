extends BattleRole
## 魔剑（roleID 9）—— 移植自服务端 role/MoJian.cpp
## 形态：tap = [暗影形态]（行动阶段点技能栏【暗影凝聚】进入，下个行动阶段开始时解除）
## 技能：修罗连斩（901，响应：[攻击行动]结束时追加 1 次火系攻击行动）、
##       暗影凝聚（902，启动：对自身 1 点法术伤害，进入[暗影形态]）、
##       暗影之力（903，被动：仅[暗影形态]下，自身发动的攻击伤害 +1）、
##       暗影抗拒（904，被动：你的行动阶段始终不能使用法术牌，含【圣光】—— 由 v_allow_action / v_block 覆写实现）、
##       暗影流星（905，法术：仅[暗影形态]下，弃 2 张法术牌[展示]，对目标 2 点法术伤害；
##                 可额外移除我方【战绩区】2 星石 → 脱离[暗影形态]并 +1【宝石】）、
##       黄泉震颤（906，响应：带此特技的攻击牌作为主动攻击打出时可选，耗 1 宝石，本次攻击对方无法应战；
##                 若命中则手牌补到上限（9061，多则弃、少则摸），随后再弃 2 张牌）

const XIU_LUO_LIAN_ZHAN: int = 901
const AN_YING_NING_JU: int = 902
const AN_YING_ZHI_LI: int = 903
const AN_YING_KANG_JU: int = 904
const AN_YING_LIU_XING: int = 905
const HEI_AN_ZHEN_CHAN: int = 906
const HEI_AN_ZHEN_CHAN_BU_PAI: int = 9061
## 【黄泉震颤】补牌之后的「再弃 2 张牌」阶段标记（不是独立技能，仅作流程子步骤号）
const HEI_AN_ZHEN_CHAN_QI_PAI: int = 9062

var used_xiu_luo_lian_zhan: bool = false
## 当前这一刀修罗连斩已经从技能响应进入行动队列（尚未结算完）
var active_xiu_luo_lian_zhan: bool = false
var used_hei_an_zhen_chan: bool = false
var using_hei_an_zhen_chan: bool = false


func available_skills() -> Array:
	var out: Array = []
	# 暗影凝聚（启动）：未处于[暗影形态]（未横置）时可发动；已横置时按钮仍摆出、置灰
	out.append({"type": GConst.ActionType.SpecialSkill, "id": AN_YING_NING_JU, "need_card": 0, "need_target": 0,
		"enabled": not player.tap})
	# 暗影流星（905）：仅[暗影形态]（tap）下可用，代价是弃 2 张法术牌（服务端 v_magic_skill 也按 2 张校验）；
	# 条件不满足时按钮仍摆出、置灰
	out.append({"type": GConst.ActionType.MagicSkill, "id": AN_YING_LIU_XING, "need_card": 2, "need_target": 1,
		"cards": magic_hand_ids(), "enabled": player.tap and _magic_card_count() >= 2})
	return out


## 手牌中法术牌数量
func _magic_card_count() -> int:
	var n: int = 0
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			n += 1
	return n


# ============================================================
# 牌类校验覆写（对照服务端 MoJian::v_missile / v_shield / v_weaken / v_attack）
# 【暗影抗拒】（904）：服务端恒返回 GE_INVALID_CARDID，即不能使用魔弹/圣盾/虚弱；
# 【修罗连斩】（901）的额外攻击行动期间，服务端限定只能用火系攻击牌。
# 暗影流星（905）属法术技能（走 v_magic_skill），不受上述限制。
# 说明：服务端只覆写了上面这三个法术牌，中毒等其它法术牌没拦（技能原文是「行动阶段不能使用法术牌」），
# 这里补一个动作总闸 v_allow_action 把整个「法术」行动一并禁掉 —— 法术技能照常可用。
# ============================================================
## 【暗影抗拒】（904）：行动阶段不能用法术牌（法术技能不算）
func v_allow_action(action_type: int, _args: Array, _allow: int, _can_give_up: bool) -> int:
	if action_type != GConst.ActionType.Magic:
		return V_NOT_OVERRIDE
	return GConst.GE_INVALID_ACTION


## 【暗影抗拒】（904）：在自己的行动阶段，他连【圣光】也不能用来抵挡/格挡
## （对照参考客户端 MoJian::attacked 的 if(isMyTurn) handArea->disableMagic()）。
## 走引擎的通用钩子：攻击询问 / 魔弹询问都会把 can_light 下发成 false，客户端把【圣光】置灰；
## v_block 也统一拒绝，不用自己再写 p_attacked / v_block 两条
func 能否使用圣光() -> bool:
	return engine.current_id != player.id


func v_missile(_card_id: int, _dst_id: int) -> int:
	return GConst.GE_INVALID_CARDID


func v_shield(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


func v_weaken(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


## 修罗连斩额外攻击行动的火系限制由它自己的规格（cards 白名单）承担，这里不再按来源分支。
## 手里能用于【修罗连斩】的火系攻击牌（供调试 / 提示）
func _fire_attack_card_ids() -> Array:
	return 按系攻击牌(GConst.CardElement.Fire)


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_xiu_luo_lian_zhan = false
	active_xiu_luo_lian_zhan = false
	used_hei_an_zhen_chan = false
	using_hei_an_zhen_chan = false
	return SUCCESS


# ============================================================
# 行动阶段入口（p_before_action）：解除[暗影形态]（对照服务端 MoJian::p_before_action）
# ============================================================
func p_before_action(_ctx: Dictionary) -> int:
	# 本回合「拒绝虚弱」等已跳过行动阶段：服务端此时不跑 p_before_action，这里同样不解除形态
	if engine.skip_action_phase:
		return SUCCESS
	if engine.current_id != player.id:
		return SUCCESS
	if player.tap:
		player.tap = false
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 启动技能（行动阶段按钮）：暗影凝聚（902）
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验技能自身条件）
# ============================================================
## 暗影凝聚为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == AN_YING_NING_JU


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != AN_YING_NING_JU:
		return GConst.GE_INVALID_ACTION
	# 已处于[暗影形态]（横置）：不能发动
	if player.tap:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 暗影凝聚：横置进入[暗影形态]，并对自己造成 1 点法术伤害
func p_special_skill(_action: Dictionary) -> int:
	notice_skill(AN_YING_NING_JU, [player.id])
	player.boot_skill_used = true
	engine.set_tap(player.id, true)
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 1,
		"cause": AN_YING_NING_JU, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击前（timeline_1）：黄泉震颤（906）
# ============================================================
## 【黄泉震颤】的推进阶段（0＝还没问 / 处理完本次询问后清回 0）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0


## 结算【黄泉震颤】：耗 1 宝石，本次攻击对方无法应战，并置本回合/本次发动标记
func _huang_quan_zhen_chan(ctx: Dictionary) -> void:
	notice_skill(HEI_AN_ZHEN_CHAN, [int(ctx.get("dst", -1))])
	player.set_gem(player.gem - 1)
	used_hei_an_zhen_chan = true
	using_hei_an_zhen_chan = true
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	engine._broadcast_game()


func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 普通出牌攻击：询问是否发动【黄泉震颤】
	if player.gem <= 0 or used_hei_an_zhen_chan:
		return SUCCESS
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 这次只问「要不要发动」，用客户端自带的那句「是否发动【黄泉震颤】？」即可 ——
		# 序号给 1（表里只配了第 1 条提示，留给下面「弃 2 张牌」那次），取不到就退回默认文案
		询问(player.id, HEI_AN_ZHEN_CHAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true, 1)
		return WAIT
	_timeline_1_step = 0
	if not take_skill_reply():
		return SUCCESS
	_huang_quan_zhen_chan(ctx)
	return SUCCESS


# ============================================================
# 主动攻击命中后：暗影之力（903）→ 黄泉震颤补牌（9061）
# ============================================================
## 【暗影之力 / 黄泉震颤补牌】的推进阶段（0＝还没开始 / AN_YING_ZHI_LI＝结算暗影之力 /
## HEI_AN_ZHEN_CHAN_BU_PAI＝结算黄泉震颤补牌（可能跨一次弃牌询问））。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击命中（p_timeline_2_hit）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_2_hit_step: int = 0


func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if _timeline_2_hit_step >= STEP_DONE:
		return SUCCESS
	if _timeline_2_hit_step == 0:
		_timeline_2_hit_step = AN_YING_ZHI_LI
	if _timeline_2_hit_step == AN_YING_ZHI_LI:
		if player.tap:
			notice_skill(AN_YING_ZHI_LI, [int(harm.get("dst", -1))])
			harm["point"] = int(harm.get("point", 0)) + 1
		_timeline_2_hit_step = HEI_AN_ZHEN_CHAN_BU_PAI
	if _timeline_2_hit_step == HEI_AN_ZHEN_CHAN_BU_PAI:
		var r: int = _hei_an_zhen_chan_bu_pai()
		if r == WAIT:
			return WAIT
		if r == URGENT:
			# 补牌已压进状态栈但还没结算：先让引擎把摸牌（含水影响应）跑完，再回来走「再弃 2 张」
			return URGENT
	if _timeline_2_hit_step == HEI_AN_ZHEN_CHAN_QI_PAI:
		return _hei_an_zhen_chan_qi_pai()
	return SUCCESS


## 攻击预告加伤：暗影形态（横置）下，自己发动的攻击命中时会 +1
## （对应 p_timeline_2_hit 里的【暗影之力】；只用于被攻击者提示，不改变实际结算）
func p_attack_preview(_ctx: Dictionary) -> int:
	return 1 if player.tap else 0


## 黄泉震颤补牌：命中后把手牌补到上限（多于上限则弃、少于上限则摸），随后进入「再弃 2 张牌」阶段
func _hei_an_zhen_chan_bu_pai() -> int:
	if not using_hei_an_zhen_chan:
		_timeline_2_hit_step = 0
		return SUCCESS
	var num: int = player.hand_cards.size() - player.hand_cards_max
	if num > 0:
		if not engine.has_reply():
			询问(player.id, HEI_AN_ZHEN_CHAN_BU_PAI, num, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_timeline_2_hit_step = HEI_AN_ZHEN_CHAN_QI_PAI
		using_hei_an_zhen_chan = false
		_discard_exact(num, r.get("card_ids", []))
		engine._broadcast_game()
		return SUCCESS
	_timeline_2_hit_step = HEI_AN_ZHEN_CHAN_QI_PAI
	using_hei_an_zhen_chan = false
	if num < 0:
		# 9061 只是黄泉震颤的内部补牌子步骤，不是独立技能，不能 notice_skill(9061)
		# 先摸牌（push_draw，含【水影】等摸牌前响应）再弃 2 张：这里返回 URGENT，让引擎先把摸牌跑完，
		# 之后再回到本钩子走 QI_PAI 那一步 —— 摸牌改走 push_draw 后是延迟结算的，
		# 直接往下走会变成先弃 2 张、最后才补牌
		engine.push_draw(player.id, -num)
		engine._broadcast_game()
		return URGENT
	return SUCCESS


## 黄泉震颤：补手牌至上限之后，再弃 2 张牌（玩家自选，强制弃满 2 张）
## 文案取技能表【黄泉震颤】「提示」列第 1 条（序号 0）
func _hei_an_zhen_chan_qi_pai() -> int:
	if not engine.has_reply():
		询问(player.id, HEI_AN_ZHEN_CHAN, 2, 0, GConst.CardSource.Hand, [], 0, "", [], false, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_timeline_2_hit_step = 0
	_discard_exact(2, r.get("card_ids", []))
	engine._broadcast_game()
	return SUCCESS


func p_timeline_2_miss(_ctx: Dictionary) -> int:
	using_hei_an_zhen_chan = false
	return SUCCESS


# ============================================================
# 攻击行动结束后：修罗连斩（901）自动生效，追加 1 次「只能用火系攻击牌」的攻击行动
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 【修罗连斩】不再弹确认：攻击行动一结束就自动生效（与封印师【法术激荡】同一套体验）。
	# 这份行动带 direct，引擎会直接进入；不想打就在那个阶段点「放弃行动」。
	if used_xiu_luo_lian_zhan or active_xiu_luo_lian_zhan \
			or _contains_action(XIU_LUO_LIAN_ZHAN) or player.跳过额外攻击行动:
		return SUCCESS
	active_xiu_luo_lian_zhan = true
	notice_skill(XIU_LUO_LIAN_ZHAN, [])
	# 修罗连斩限火系攻击牌：只写系别，引擎按「该系攻击牌」规则算可用牌与校验
	# （不写手牌快照：授予之后再摸到 / 留下的火系攻击牌都要能出）
	player.add_action(GConst.ActionType.Attack, XIU_LUO_LIAN_ZHAN, true, true, {
		"element": GConst.CardElement.Fire,
	})
	engine._broadcast_game()
	return SUCCESS


func p_action_end(ctx: Dictionary) -> int:
	if bool(ctx.get("is_extra", false)) and int(ctx.get("extra_cause", 0)) == XIU_LUO_LIAN_ZHAN:
		used_xiu_luo_lian_zhan = true
		active_xiu_luo_lian_zhan = false
	return SUCCESS


func p_additional_action(_ctx: Dictionary) -> int:
	return SUCCESS


# ============================================================
# 主动法术技能：暗影流星（905）
# ============================================================
## 暗影流星追加效果的推进标记（跨询问，不能停在引擎 step 上）：
## 0＝还没问 / 1＝在等「要不要移除」 / 2＝在等「移除哪两颗」


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != AN_YING_LIU_XING or not player.tap:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2:
		return GConst.GE_INVALID_ACTION
	for c: Variant in cards:
		var cid: int = int(c)
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != AN_YING_LIU_XING:
		return GConst.GE_INVALID_ACTION
	# 可选追加：额外移除我方【战绩区】2 星石 → 脱离[暗影形态]并 +1【宝石】（跨两次询问）。
	# 任意一步取消（没回值）＝这次不发动暗影流星：牌不弃、不造成伤害，直接退回行动阶段重来。
	# 用多步询问：第 1 段问「要不要移除」（没有可行组合就跳过），第 2 段问「移除哪两颗」。
	return 多步询问(AN_YING_LIU_XING, [
		{"选项": _暗影流星追加选项(), "取消": _取消暗影流星,
		 "跳过": func(_答案: Array) -> bool: return not _liu_xing_any_combo()},
		{"选项": func(_答案: Array) -> Array: return _liu_xing_组合选项(),
		 # 第二段只显示技能说明：不要再提示「要不要移除我方战绩区的星石」（第一段已经问过）
		 "询问文案": GConst.skill_desc(AN_YING_LIU_XING),
		 "取消": _取消暗影流星,
		 "跳过": func(答案: Array) -> bool: return _暗影流星第一段值(答案) != 1},
	], func(答案: Array) -> int: return _暗影流星结算(action, 答案))


## 第 1 段的两个选项：不移除 / 移除 2 星石并脱离暗影形态
func _暗影流星追加选项() -> Array:
	return [
		{"value": 0, "label": GConst.按钮原文(AN_YING_LIU_XING, 0)},
		{"value": 1, "label": GConst.按钮原文(AN_YING_LIU_XING, 1)},
	]


## 第 1 段选了什么（没答过就是 0＝不移除）
func _暗影流星第一段值(答案: Array) -> int:
	if 答案.is_empty():
		return 0
	var args: Array = (答案[0] as Dictionary).get("args", [])
	return int(args[0]) if not args.is_empty() else 0


## 任意一步取消：这次不发动暗影流星，退回行动阶段重新来
func _取消暗影流星() -> int:
	engine.取消技能行动()
	return SUCCESS


## 两段都答完（或跳过）：先应用追加，再结算暗影流星本体
func _暗影流星结算(action: Dictionary, 答案: Array) -> int:
	if 答案.size() > 1:
		var args1: Array = (答案[1] as Dictionary).get("args", [])
		if not args1.is_empty():
			_应用暗影流星追加(int(args1[0]))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(AN_YING_LIU_XING, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": AN_YING_LIU_XING, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards, {"owner": player.id, "source": "hand"})
	# 牌已在上面展示过：只写日志、不播弃牌特效
	engine._log_discard(player.id, cards, false)
	engine._broadcast_game()
	return URGENT


## 【暗影流星】第二步的可选项：三种组合始终摆出来，当前凑不出/不可用的置灰
## （value 1＝两水晶 / 2＝一宝石一水晶 / 3＝两宝石）。
## 文案统一走「战绩区 -数量【星石类型】」的消耗写法（如 战绩区 -2【水晶】），界面按词缀表画成图标
func _liu_xing_组合选项() -> Array:
	var 宝石: int = engine.team_gem[player.color]
	var 水晶: int = engine.team_crystal[player.color]
	return [
		{"value": 1, "label": GConst.按钮原文(AN_YING_LIU_XING, 2), "enabled": 水晶 >= 2},
		{"value": 2, "label": GConst.按钮原文(AN_YING_LIU_XING, 3), "enabled": 宝石 >= 1 and 水晶 >= 1},
		{"value": 3, "label": GConst.按钮原文(AN_YING_LIU_XING, 4), "enabled": 宝石 >= 2},
	]


## 三种组合里至少有一种当前可做（决定要不要问「是否追加移除」）
func _liu_xing_any_combo() -> bool:
	return engine.team_crystal[player.color] >= 2 \
		or (engine.team_gem[player.color] >= 1 and engine.team_crystal[player.color] >= 1) \
		or engine.team_gem[player.color] >= 2


## 结算【暗影流星】的追加效果：按 选择 移除我方【战绩区】两颗星石，脱离[暗影形态]并 +1【宝石】。
## 选择 不是三种组合之一（玩家在第二步取消 / 回了空值）时什么也不做，只走原效果
func _应用暗影流星追加(选择: int) -> void:
	# 服务端兜底：置灰项即使被硬提交也不扣资源，按“不追加”处理
	var 宝石: int = engine.team_gem[player.color]
	var 水晶: int = engine.team_crystal[player.color]
	if (选择 == 1 and 水晶 < 2) \
			or (选择 == 2 and (宝石 < 1 or 水晶 < 1)) \
			or (选择 == 3 and 宝石 < 2):
		return
	match 选择:
		1:
			engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 2)
		2:
			engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
			engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 1)
		3:
			engine.set_team_gem(player.color, engine.team_gem[player.color] - 2)
		_:
			return
	player.tap = false
	player.set_gem(player.gem + 1)
	engine._broadcast_game()


# ============================================================
# 工具
# ============================================================
## 是否已存在某来源的额外行动
func _contains_action(cause: int) -> bool:
	for a: Dictionary in player.additional_actions:
		if int(a.get("cause", -1)) == cause:
			return true
	return false


## 精确弃 num 张牌（客户端优先给出要弃的牌，不足时从手牌补齐）
func _discard_exact(num: int, cards: Array) -> void:
	var chosen: Array = []
	for c: Variant in cards:
		if chosen.size() < num and player.has_hand_card(int(c)):
			chosen.append(int(c))
	if chosen.size() < num:
		for cid: int in player.hand_cards:
			if chosen.size() >= num:
				break
			if not chosen.has(cid):
				chosen.append(cid)
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen, {"owner": player.id, "source": "hand"})
	engine._log_discard(player.id, chosen)

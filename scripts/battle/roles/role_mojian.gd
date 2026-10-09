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
var using_xiu_luo_lian_zhan: bool = false
var used_hei_an_zhen_chan: bool = false
var using_hei_an_zhen_chan: bool = false


func available_skills() -> Array:
	var out: Array = []
	# 暗影凝聚（启动）：未处于[暗影形态]（未横置）时可发动
	if not player.tap:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": AN_YING_NING_JU, "need_card": 0, "need_target": 0})
	# 暗影流星（905）：仅[暗影形态]（tap）下可用，代价是弃 2 张法术牌（服务端 v_magic_skill 也按 2 张校验）
	if player.tap and _magic_card_count() >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": AN_YING_LIU_XING, "need_card": 2, "need_target": 1,
			"cards": magic_hand_ids()})
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
## 被攻击时把下发给界面的 can_light 置 0，界面就会把【圣光】置灰、点不动
func p_attacked(ctx: Dictionary) -> int:
	if engine.current_id == player.id and int(ctx.get("dst", -1)) == player.id:
		ctx["can_light"] = false
	return SUCCESS


## 【暗影抗拒】（904）：同上，服务端兜底拒绝用【圣光】抵挡（格挡攻击与抵挡魔弹都走 v_block）
func v_block(_card_id: int) -> int:
	if engine.current_id == player.id:
		return GConst.GE_INVALID_CARDID
	return V_NOT_OVERRIDE


func v_missile(_card_id: int, _dst_id: int) -> int:
	return GConst.GE_INVALID_CARDID


func v_shield(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


func v_weaken(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


## 修罗连斩额外攻击行动期间只能用火系攻击牌
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	var rc: int = player.base_v_attack(card_id, dst_id, players)
	if rc != GConst.GE_SUCCESS:
		return rc
	if using_xiu_luo_lian_zhan:
		var card: GCard = Data.get_card(card_id)
		if card.element_enum() != GConst.CardElement.Fire:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 【修罗连斩】的额外攻击行动期间只能出火系攻击牌：给界面一份合法手牌白名单，其余牌置灰
## （同【风怒追击】：一张火系攻击牌都没有时显式发「全禁」白名单，
##   免得空列表被当成「不限制」、手牌又全亮起来）
func action_card_ids(action_type: int) -> Array:
	if not using_xiu_luo_lian_zhan or action_type != GConst.ActionType.Attack:
		return []
	var out: Array = _fire_attack_card_ids()
	return out if not out.is_empty() else [GConst.手牌白名单_全禁]


## 手里能用于【修罗连斩】的火系攻击牌（一张都没有时这次额外攻击行动出不了任何牌，只能放弃行动）
func _fire_attack_card_ids() -> Array:
	var out: Array = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_attack() and c.element_enum() == GConst.CardElement.Fire:
			out.append(cid)
	return out


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_xiu_luo_lian_zhan = false
	using_xiu_luo_lian_zhan = false
	used_hei_an_zhen_chan = false
	using_hei_an_zhen_chan = false
	return SUCCESS


# ============================================================
# 回合开始（p_boot）：解除[暗影形态]
# 服务端在 p_before_action 里解除[暗影形态]（MoJian::p_before_action）；
# 本实现仍并入 p_boot 首段——引擎中 p_boot 先于 p_before_action 执行，两者都在行动阶段之前，行为等价
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
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
		notice_skill(HEI_AN_ZHEN_CHAN_BU_PAI, [player.id])
		_discard_exact(num, r.get("card_ids", []))
		engine._broadcast_game()
		return SUCCESS
	_timeline_2_hit_step = HEI_AN_ZHEN_CHAN_QI_PAI
	using_hei_an_zhen_chan = false
	if num < 0:
		notice_skill(HEI_AN_ZHEN_CHAN_BU_PAI, [player.id])
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
# 攻击行动结束后：修罗连斩（901，追加 1 次火系攻击行动）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	if used_xiu_luo_lian_zhan:
		return SUCCESS
	if _contains_action(XIU_LUO_LIAN_ZHAN):
		return SUCCESS
	# 不以「直接」方式授予：回合结束时统一询问玩家是否发动（对照服务端 addAction 不带直接标志）。
	# 手里有没有火系牌都照问，发动后由 v_attack 限定只能出火系攻击牌
	player.add_action(GConst.ActionType.Attack, XIU_LUO_LIAN_ZHAN)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 玩家选中额外行动时的二次校验（服务端 MoJian::v_additional_action）：
# 修罗连斩本回合限一次
# ============================================================
func v_additional_action(cause: int) -> int:
	if cause != XIU_LUO_LIAN_ZHAN:
		return V_NOT_OVERRIDE
	# 只限「本回合一次」；手里有没有火系攻击牌不再拦「确定」——
	# 没有火系牌时也照样给这一份额外攻击行动（出牌时才由 v_attack 要求火系，没牌就只能放弃行动）
	if used_xiu_luo_lian_zhan:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


# ============================================================
# 玩家选中额外行动时：置「修罗连斩」标记供 v_attack 限制火系牌
# （对照服务端 p_additional_action：选中修罗连斩置位 used/using，其余额外行动清除 using）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var cause: int = int(ctx.get("cause", 0))
	using_xiu_luo_lian_zhan = cause == XIU_LUO_LIAN_ZHAN
	if using_xiu_luo_lian_zhan:
		used_xiu_luo_lian_zhan = true
	return SUCCESS


# ============================================================
# 主动法术技能：暗影流星（905）
# ============================================================
## 暗影流星追加效果的推进标记（跨询问，不能停在引擎 step 上）：
## 0＝还没问 / 1＝在等「要不要移除」 / 2＝在等「移除哪两颗」
var _liu_xing_step: int = 0


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
	# 这两步都是「释放暗影流星」的一部分：任意一步取消（没回值）＝这次不发动暗影流星，
	# 牌不弃、不造成伤害，直接退回行动阶段重新来（同【不谐和弦】，见 engine.取消技能行动）。
	# 第一步只问「要不要移除」（第一项固定是「不移除」，选了才继续走原效果；
	# 一颗可行组合都没有时干脆不问）；选定要移除后第二步再问「移除哪两颗」。
	if _liu_xing_step == 0:
		if not _liu_xing_组合选项().is_empty():
			询问(player.id, AN_YING_LIU_XING, 0, 0, GConst.CardSource.Hand, [
				{"value": 0, "label": "不移除"},
				{"value": 1, "label": "扣除 2 个星石（脱离【暗影形态】，+1【宝石】）"},
			], 0, "", [], true, 0)
			_liu_xing_step = 1
			return WAIT
	elif _liu_xing_step == 1:
		var r0: Dictionary = take_skill_reply_full()
		var args0: Array = r0.get("args", [])
		_liu_xing_step = 0
		if args0.is_empty():
			engine.取消技能行动()
			return SUCCESS
		if int(args0[0]) == 1:
			询问(player.id, AN_YING_LIU_XING, 0, 0, GConst.CardSource.Hand, _liu_xing_组合选项(), 0, "", [], true, 1)
			_liu_xing_step = 2
			return WAIT
	else:
		var r1: Dictionary = take_skill_reply_full()
		var args1: Array = r1.get("args", [])
		_liu_xing_step = 0
		if args1.is_empty():
			engine.取消技能行动()
			return SUCCESS
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
	engine.to_discard(cards)
	# 牌已在上面展示过：只写日志、不播弃牌特效
	engine._log_discard(player.id, cards, false)
	engine._broadcast_game()
	return URGENT


## 【暗影流星】第二步的可选项：按我方【战绩区】现有的星石，列出能凑出的两颗组合
## （value 1＝两水晶 / 2＝一宝石一水晶 / 3＝两宝石）；一颗可行组合都没有时返回空
func _liu_xing_组合选项() -> Array:
	var 宝石: int = engine.team_gem[player.color]
	var 水晶: int = engine.team_crystal[player.color]
	var out: Array = []
	if 水晶 >= 2:
		out.append({"value": 1, "label": "移除 2 水晶"})
	if 宝石 >= 1 and 水晶 >= 1:
		out.append({"value": 2, "label": "移除 1 宝石 + 1 水晶"})
	if 宝石 >= 2:
		out.append({"value": 3, "label": "移除 2 宝石"})
	return out


## 结算【暗影流星】的追加效果：按 选择 移除我方【战绩区】两颗星石，脱离[暗影形态]并 +1【宝石】。
## 选择 不是三种组合之一（玩家在第二步取消 / 回了空值）时什么也不做，只走原效果
func _应用暗影流星追加(选择: int) -> void:
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
	engine.to_discard(chosen)
	engine._log_discard(player.id, chosen)

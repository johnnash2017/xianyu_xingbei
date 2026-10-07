extends BattleRole
## 魔剑（roleID 9）—— 移植自服务端 role/MoJian.cpp
## 形态：tap = [暗影形态]（行动阶段点技能栏【暗影凝聚】进入，下个行动阶段开始时解除）
## 技能：修罗连斩（901，响应：[攻击行动]结束时追加 1 次火系攻击行动）、
##       暗影凝聚（902，启动：对自身 1 点法术伤害，进入[暗影形态]）、
##       暗影之力（903，被动：仅[暗影形态]下，自身发动的攻击伤害 +1）、
##       暗影抗拒（904，被动：你的行动阶段始终不能使用法术牌，含【圣光】—— 由 v_allow_action / v_block 覆写实现）、
##       暗影流星（905，法术：仅[暗影形态]下，弃 2 张法术牌[展示]，对目标 2 点法术伤害）、
##       黄泉震颤（906，攻击技能：选一张攻击牌+一名对手直接发起攻击，耗 1 宝石，本次攻击对方无法应战；
##                 若命中则手牌补到上限（9061，多则弃、少则摸））

const XIU_LUO_LIAN_ZHAN: int = 901
const AN_YING_NING_JU: int = 902
const AN_YING_ZHI_LI: int = 903
const AN_YING_KANG_JU: int = 904
const AN_YING_LIU_XING: int = 905
const HEI_AN_ZHEN_CHAN: int = 906
const HEI_AN_ZHEN_CHAN_BU_PAI: int = 9061

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
func action_card_ids(action_type: int) -> Array:
	if not using_xiu_luo_lian_zhan or action_type != GConst.ActionType.Attack:
		return []
	return _fire_attack_card_ids()


## 手里能用于【修罗连斩】的火系攻击牌（一张都没有就发不出这次额外攻击）
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
# 黄泉震颤（906，攻击技能）：选一张攻击牌 + 一名对手，直接发起一次主动攻击
# ============================================================
## 本次主动攻击预选的「攻击技能」号（0＝普通攻击）：由 p_attack_skill 在发起攻击前写入，
## p_timeline_1 据此直接结算黄泉震颤，用完即清
var _预选攻击技能: int = 0


func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != HEI_AN_ZHEN_CHAN:
		return GConst.GE_INVALID_ACTION
	# 技能自身条件：宝石 ≥ 1 且本回合未发动过
	if player.gem <= 0 or used_hei_an_zhen_chan:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	# 复用通用主动攻击校验（持有该攻击牌、目标不同队、面前【挑衅】限制等）
	if player.v_attack(cid, dst_id, engine.players) != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 黄泉震颤：打出所选攻击牌发起一次主动攻击。
## 回合结束由引擎的技能行动入栈（与普通技能一致），这里只补这次攻击本身；
## 攻击宣告后 p_timeline_1 会依据 _预选攻击技能 直接结算（不再弹窗询问）
func p_attack_skill(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	_预选攻击技能 = HEI_AN_ZHEN_CHAN
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": BattleEngine.ATTACK_BASE_POINT, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": cid, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, cid, harm))
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true,
	})
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
	# 本次主动攻击是否由技能栏【黄泉震颤】发起（预选命中）：是则直接结算，不再弹窗询问
	var 预选: int = _预选攻击技能
	_预选攻击技能 = 0
	if 预选 == HEI_AN_ZHEN_CHAN:
		if player.gem <= 0 or used_hei_an_zhen_chan:
			return SUCCESS
		_huang_quan_zhen_chan(ctx)
		return SUCCESS
	# 普通出牌攻击（预选为 0）：询问是否发动【黄泉震颤】
	if player.gem <= 0 or used_hei_an_zhen_chan:
		return SUCCESS
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, HEI_AN_ZHEN_CHAN, 0, 0)
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
		return _hei_an_zhen_chan_bu_pai()
	return SUCCESS


## 黄泉震颤补牌：命中后把手牌补到上限（多于上限则弃、少于上限则摸）
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
		_timeline_2_hit_step = 0
		using_hei_an_zhen_chan = false
		notice_skill(HEI_AN_ZHEN_CHAN_BU_PAI, [player.id])
		_discard_exact(num, r.get("card_ids", []))
		engine._broadcast_game()
		return SUCCESS
	_timeline_2_hit_step = 0
	using_hei_an_zhen_chan = false
	if num < 0:
		notice_skill(HEI_AN_ZHEN_CHAN_BU_PAI, [player.id])
		engine.draw(player.id, -num)
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
	if used_xiu_luo_lian_zhan:
		return GConst.GE_INVALID_ACTION
	# 手里没有火系攻击牌：发动了也出不了牌 —— 让界面把「确定」置灰（「取消」仍可跳过）
	if _fire_attack_card_ids().is_empty():
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

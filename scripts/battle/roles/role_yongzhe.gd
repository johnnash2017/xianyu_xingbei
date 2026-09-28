extends BattleRole
## 勇者（roleID 21）—— 移植自服务端 role/YongZhe.cpp
## 技能：挑衅（专属法术 2101：移除 1 怒气，将【挑衅】放到目标对手面前，自己 +1 知性）、
##       怒吼（响应 2103：主动攻击前移除 1 怒气，本次伤害 +2；未命中则 +1 知性）、
##       明镜止水（响应 2104：主动攻击前移除 4 知性，本次攻击对方无法应战）、
##       禁断之力（必杀响应 2102：主动攻击命中/未命中后，能量 ×1，弃掉所有手牌）、
##       精疲力竭（被动 2106：发动禁断之力后强制横置，额外 +1 攻击行动、手牌上限恒定为 4）、
##       死斗（响应 2105：每当你承受法术伤害时，宝石 ×1，怒气 +3）
## 被动：勇者之心（游戏初始 +2 水晶）。
## 【怒气】tokens[0]、【知性】tokens[1]，上限各为 4；【精疲力竭】用 tap 表示。
## 覆写校验：v_attack——面前有【挑衅】时只能攻击勇者（服务端 PlayerEntity::v_attack）

const TIAO_XIN: int = 2101           # 挑衅（法术技能）
const JIN_DUAN_ZHI_LI: int = 2102    # 禁断之力（响应）
const NU_HOU: int = 2103             # 怒吼（响应）
const MING_JING_ZHI_SHUI: int = 2104 # 明镜止水（响应）
const SI_DOU: int = 2105             # 死斗（响应）
const JING_PI_LI_JIE: int = 2106     # 精疲力竭（被动 / 形态）

const TOKEN_NU_QI: int = 0           # 「怒气」指示物下标
const TOKEN_ZHI_XING: int = 1        # 「知性」指示物下标
const TOKEN_MAX: int = 4

const JING_PI_HAND_MAX: int = 4      # 精疲力竭期间的手牌上限
const HAND_MAX_DEFAULT: int = 6      # 恢复后的默认手牌上限


var using_NuHou: bool = false        # 本次攻击是否发动了怒吼
var toRemoveTiaoXin: bool = false    # 本回合结束是否移除当前玩家面前的挑衅


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.set_crystal(2)
	p.tokens[TOKEN_NU_QI] = {"name": "怒气", "max": TOKEN_MAX, "num": 0}
	p.tokens[TOKEN_ZHI_XING] = {"name": "知性", "max": TOKEN_MAX, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if _nu_qi() > 0:
		out.append({"type": GConst.ActionType.MagicSkill, "id": TIAO_XIN, "need_card": 0, "need_target": 1})
	return out


# ============================================================
# 指示物：怒气 / 知性
# ============================================================
func _nu_qi() -> int:
	return int(player.tokens[TOKEN_NU_QI]["num"])


func _zhi_xing() -> int:
	return int(player.tokens[TOKEN_ZHI_XING]["num"])


func _set_nu_qi(v: int) -> void:
	player.tokens[TOKEN_NU_QI]["num"] = clampi(v, 0, TOKEN_MAX)


func _set_zhi_xing(v: int) -> void:
	player.tokens[TOKEN_ZHI_XING]["num"] = clampi(v, 0, TOKEN_MAX)


# ============================================================
# 回合开始 / 启动
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	toRemoveTiaoXin = false
	return SUCCESS


## 精疲力竭的解除时机与挑衅标记（服务端在 p_before_action 中处理；本实现改挂 p_boot，
## 引擎中 p_boot 先于 p_before_action 执行，两者都在行动阶段之前，行为等价）
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		# 记录当前玩家是否带有【挑衅】，供其回合结束时移除
		var other: BattlePlayer = engine.p(engine.current_id)
		if other != null and other.check_exclusive_effect(GConst.Exclusive.TiaoXin):
			toRemoveTiaoXin = true
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	if not player.tap:
		return SUCCESS
	# 解除精疲力竭：恢复手牌上限并对自己造成 3 点法术伤害
	notice_skill(JING_PI_LI_JIE, [player.id])
	player.hand_cards_max = HAND_MAX_DEFAULT
	engine.set_tap(player.id, false)
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 3,
		"cause": JING_PI_LI_JIE, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击宣告后：怒吼 → 明镜止水
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = NU_HOU
	if step == NU_HOU:
		var r: int = _nu_hou(ctx)
		if r == WAIT:
			return WAIT
		step = MING_JING_ZHI_SHUI
	if step == MING_JING_ZHI_SHUI:
		var r2: int = _ming_jing_zhi_shui(ctx)
		if r2 == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 怒吼：移除 1 怒气，本次攻击伤害 +2
func _nu_hou(ctx: Dictionary) -> int:
	if _nu_qi() <= 0:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, NU_HOU, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(NU_HOU, [int(ctx.get("dst", -1))])
	_set_nu_qi(_nu_qi() - 1)
	using_NuHou = true
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + 2
	engine._broadcast_game()
	return SUCCESS


## 明镜止水：移除 4 知性，本次攻击对方无法应战
func _ming_jing_zhi_shui(ctx: Dictionary) -> int:
	if _zhi_xing() != TOKEN_MAX:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, MING_JING_ZHI_SHUI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(MING_JING_ZHI_SHUI, [int(ctx.get("dst", -1))])
	_set_zhi_xing(0)
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击命中后：禁断之力
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = JIN_DUAN_ZHI_LI
	if step == JIN_DUAN_ZHI_LI:
		var r: int = _jin_duan_zhi_li(ctx, true)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
		if r == URGENT:
			return URGENT
	return SUCCESS


## 攻击未命中后：怒吼补正 → 禁断之力
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = NU_HOU
	if step == NU_HOU:
		_nu_hou_miss()
		step = JIN_DUAN_ZHI_LI
	if step == JIN_DUAN_ZHI_LI:
		var r: int = _jin_duan_zhi_li(ctx, false)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
		if r == URGENT:
			return URGENT
	return SUCCESS


## 怒吼未命中补正：+1 知性
func _nu_hou_miss() -> void:
	if not using_NuHou:
		return
	using_NuHou = false
	_set_zhi_xing(_zhi_xing() + 1)
	engine._broadcast_game()


## 禁断之力：能量 ×1，弃掉所有手牌【展示】
## hit=true：每有 1 张法术牌 +1 怒气；每有 1 张火系牌本次伤害 +1，并对自己造成等量法术伤害
## hit=false：每有 1 张法术牌 +1 怒气；每有 1 张水系牌 +1 知性
func _jin_duan_zhi_li(ctx: Dictionary, hit: bool) -> int:
	if player.get_energy() <= 0:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, JIN_DUAN_ZHI_LI, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	notice_skill(JIN_DUAN_ZHI_LI, [int(ctx.get("dst", -1))])
	_consume_one_energy()
	var magic_num: int = 0
	var elem_num: int = 0
	var want_elem: int = GConst.CardElement.Fire if hit else GConst.CardElement.Water
	for c: Variant in cards:
		var card: GCard = Data.get_card(int(c))
		if card == null:
			continue
		if card.is_magic():
			magic_num += 1
		if card.element_enum() == want_elem:
			elem_num += 1
	_set_nu_qi(_nu_qi() + magic_num)
	if not hit:
		_set_zhi_xing(_zhi_xing() + elem_num)
	else:
		var harm: Dictionary = ctx.get("harm", {})
		harm["point"] = int(harm.get("point", 0)) + elem_num
	# 发动精疲力竭
	_jing_pi_li_jie()
	if hit and elem_num > 0:
		engine.push_harm({
			"src": player.id, "dst": player.id, "point": elem_num,
			"cause": JIN_DUAN_ZHI_LI, "type": GConst.HarmType.Magic,
		})
	if not cards.is_empty():
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": cards, "is_real": true,
		})
		engine.take_from_hand(player.id, cards)
		engine.to_discard(cards)
	engine._broadcast_game()
	return URGENT


## 精疲力竭：横置，额外 +1 攻击行动，手牌上限恒定为 4
func _jing_pi_li_jie() -> void:
	player.hand_cards_max = JING_PI_HAND_MAX
	player.add_action(GConst.ActionType.Attack, JING_PI_LI_JIE)
	engine.set_tap(player.id, true)


# ============================================================
# 承受法术伤害：死斗
# ============================================================
func p_timeline_6_drawn(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("point", 0)) <= 0 or int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if player.gem <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SI_DOU
	if step == SI_DOU:
		var r: int = _si_dou()
		if r == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 死斗：消耗 1 宝石，怒气 +3
func _si_dou() -> int:
	if not engine.has_reply():
		engine.ask_skill(player.id, SI_DOU, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(SI_DOU, [player.id])
	player.set_gem(player.gem - 1)
	_set_nu_qi(_nu_qi() + 3)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 回合结束：移除当前玩家面前的挑衅
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if not toRemoveTiaoXin:
		return SUCCESS
	toRemoveTiaoXin = false
	var cur: BattlePlayer = engine.p(int(ctx.get("player", -1)))
	if cur != null and cur.check_exclusive_effect(GConst.Exclusive.TiaoXin):
		cur.remove_exclusive_effect(GConst.Exclusive.TiaoXin)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击校验覆写：面前有【挑衅】时必须攻击勇者
# 对应服务端 PlayerEntity::v_attack：
#   若攻击者面前存在【挑衅】独有效果，则目标只能是勇者（roleID 21），否则非法
# 说明：本钩子由「攻击者的角色」实现，故仅在勇者本人发动攻击时生效；
#   其他角色被【挑衅】时的同类限制应由通用实现（base_v_attack）承担
# ============================================================
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	var base: int = player.base_v_attack(card_id, dst_id, players)
	if base != GConst.GE_SUCCESS:
		return base
	if player.check_exclusive_effect(GConst.Exclusive.TiaoXin):
		var dst: BattlePlayer = players.get(dst_id)
		if dst.role_id != 21:
			return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


# ============================================================
# 挑衅（法术技能）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != TIAO_XIN:
		return GConst.GE_INVALID_ACTION
	if _nu_qi() <= 0:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != TIAO_XIN:
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else -1
	_set_nu_qi(_nu_qi() - 1)
	_set_zhi_xing(_zhi_xing() + 1)
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null:
		dst.add_exclusive_effect(GConst.Exclusive.TiaoXin)
	notice_skill(TIAO_XIN, [dst_id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 消耗 1 点个人能量（优先扣水晶，与服务端一致）
func _consume_one_energy() -> void:
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)

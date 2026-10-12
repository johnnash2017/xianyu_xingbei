extends BattleRole
## 勇者（roleID 21）—— 移植自服务端 role/YongZhe.cpp
## 技能：挑衅（专属法术 2101：移除 1 怒气，将【挑衅】放到目标对手面前，自己 +1 知性）、
##       怒吼（响应 2103：移除 1 怒气，摸 0-1 张牌，本次主动攻击伤害 +2；未命中则 +1 知性）、
##       明镜止水（响应 2104：知性满 4 时清零，本次主动攻击对方无法应战；本次攻击结束时 +1 水晶）、
##       禁断之力（必杀响应 2102：主动攻击命中/未命中后，能量 ×1，弃掉所有手牌）、
##       精疲力竭（被动 2106：发动禁断之力后强制横置，额外 +1 攻击行动、手牌上限恒定为 4）、
##       死斗（响应 2105：每当你承受法术伤害时，宝石 ×1，怒气 +3；若本次伤害造成我方士气下降，本次下降恒定为 1）
## 被动：勇者之心（游戏初始 +2 水晶）。
## 【怒气】tokens[0]、【知性】tokens[1】，上限见角色表；【精疲力竭】用 tap 表示。
## 挑衅的限制在服务端 BattlePlayer.base_v_attack：被挑衅的人只能主动攻击「放挑衅的那个玩家」

const TIAO_XIN: int = 2101           # 挑衅（法术技能）
const JIN_DUAN_ZHI_LI: int = 2102    # 禁断之力（响应）
const NU_HOU: int = 2103             # 怒吼（响应）
const MING_JING_ZHI_SHUI: int = 2104 # 明镜止水（响应）
const SI_DOU: int = 2105             # 死斗（响应）
const JING_PI_LI_JIE: int = 2106     # 精疲力竭（被动 / 形态）

const TOKEN_NU_QI: int = 0           # 「怒气」指示物下标
const TOKEN_ZHI_XING: int = 1        # 「知性」指示物下标

const JING_PI_HAND_MAX: int = 4      # 精疲力竭期间的手牌上限
const HAND_MAX_DEFAULT: int = 6      # 恢复后的默认手牌上限


var using_NuHou: bool = false        # 本次攻击是否发动了怒吼
var toRemoveTiaoXin: bool = false    # 本回合结束是否移除当前玩家面前的挑衅
var ming_jing_used: bool = false     # 本次攻击是否发动了明镜止水（攻击结束时 +1 水晶）
var si_dou_morale_lock: bool = false # 本次承受的法术伤害是否发动了死斗（本次士气下降恒定为 1）


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.set_crystal(2)


func available_skills() -> Array:
	var out: Array = []
	if _nu_qi() > 0:
		# 技能描述写的是「目标对手」：只能放到对手面前（targets 白名单决定头像上谁亮）
		out.append({"type": GConst.ActionType.MagicSkill, "id": TIAO_XIN, "need_card": 0,
			"need_target": 1, "targets": enemy_ids()})
	# 【怒吼 / 明镜止水】不再提供技能栏按钮：它们只能在主动攻击宣告时响应发动
	return out


# ============================================================
# 指示物：怒气 / 知性
# ============================================================
func _nu_qi() -> int:
	return int(player.tokens[TOKEN_NU_QI]["num"])


func _zhi_xing() -> int:
	return int(player.tokens[TOKEN_ZHI_XING]["num"])


func _token_max() -> int:
	return int(player.tokens[TOKEN_NU_QI]["max"])


func _set_nu_qi(v: int) -> void:
	player.tokens[TOKEN_NU_QI]["num"] = clampi(v, 0, _token_max())


func _set_zhi_xing(v: int) -> void:
	player.tokens[TOKEN_ZHI_XING]["num"] = clampi(v, 0, _token_max())


# ============================================================
# 回合开始 / 启动
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	toRemoveTiaoXin = false
	return SUCCESS


## 行动阶段入口（p_before_action）：精疲力竭的解除时机与挑衅标记（对照服务端 YongZhe::p_before_action）
func p_before_action(_ctx: Dictionary) -> int:
	# 本回合「拒绝虚弱」等已跳过行动阶段：服务端此时不跑 p_before_action —— 不解除【精疲力竭】、
	# 也不吃那 3 点自伤，挑衅标记同样留到真正进入行动阶段的那一回合再记
	if engine.skip_action_phase:
		return SUCCESS
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
# 主动攻击宣告后：怒吼 / 明镜止水（响应）
# 【怒吼 / 明镜止水】不再提供技能栏按钮，只能在主动攻击宣告时响应发动：
# 恢复原版询问链，先问怒吼、再问明镜止水（T1_ASK_NU_HOU → T1_ASK_MING）。
# 用自有变量推进而不是引擎 step：钩子轮次开始会把 step 清零，而这条流程要跨若干次询问。
# ============================================================
## 推进阶段：0＝还没开始；T1_ASK_NU_HOU → T1_ASK_MING。收尾清回 0
var _timeline_1_step: int = 0
const T1_ASK_NU_HOU: int = 1  # 在问怒吼
const T1_ASK_MING: int = 2     # 在问明镜止水


func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _timeline_1_step == 0:
		# 恢复原版询问链（先问怒吼、再问明镜止水）
		_timeline_1_step = T1_ASK_NU_HOU
	# 先问怒吼
	if _timeline_1_step == T1_ASK_NU_HOU:
		var r: int = _询问怒吼(ctx)
		if r == WAIT:
			return WAIT
		_timeline_1_step = T1_ASK_MING
		if r == URGENT:
			# 怒吼的摸牌刚经 push_draw 排进状态栈：报 URGENT 让引擎先把摸牌结算掉
			# （引擎一 WAIT 就停住，否则摸牌会拖到问完明镜止水才结算）。回到本钩子时 step 已是 T1_ASK_MING
			return URGENT
	# 再问明镜止水
	if _timeline_1_step == T1_ASK_MING:
		var r2: int = _询问明镜止水(ctx)
		if r2 == WAIT:
			return WAIT
		_timeline_1_step = 0
		return SUCCESS
	return SUCCESS


# ============================================================
# 怒吼 / 明镜止水的响应结算辅助（询问、读取回复、结算）
# ============================================================


## 怒吼（直接结算）：移除 1 怒气，摸 0-1 张牌（由玩家在询问里选定），本次攻击伤害 +2
## （未命中补正见 _nu_hou_miss）
func _发动怒吼(ctx: Dictionary, 摸牌数: int) -> void:
	if _nu_qi() <= 0:
		return
	notice_skill(NU_HOU, [int(ctx.get("dst", -1))])
	_set_nu_qi(_nu_qi() - 1)
	if 摸牌数 > 0:
		engine.push_draw(player.id, 摸牌数)
	using_NuHou = true
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + GConst.怒吼加伤
	engine._broadcast_game()


## 怒吼的两个选项：摸 0 张 / 摸 1 张（选项值即摸牌数；取消＝不发动）
func _怒吼摸牌选项() -> Array:
	return [
		{"value": 0, "label": "发动怒吼：摸 0 张牌"},
		{"value": 1, "label": "发动怒吼：摸 1 张牌"},
	]


## 弹询问是否发动怒吼：选项给「摸 0 张 / 摸 1 张」，并把本次攻击的目标与「发动前的伤害」一并下发，
## 客户端据此在目标头像上现算「原伤害 + 怒吼加伤」
func _问怒吼(ctx: Dictionary) -> void:
	var dst: int = int(ctx.get("dst", -1))
	# 座位号从 0 起：0 号也是合法对手，判「没取到」只能用 < 0
	询问(player.id, NU_HOU, 0, 0, GConst.CardSource.Hand, _怒吼摸牌选项(), 0, "", [], true,
		0, -1, [dst] if dst >= 0 else [], -1, {}, int(ctx.get("harm", {}).get("point", 0)))


## 读取怒吼询问回复：返回 -1＝不发动（取消），0/1＝发动并摸对应张数
func _读取怒吼回复() -> int:
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty():
		return -1
	return int(args[0])


## 怒吼（原版询问）：普通出牌攻击时弹窗询问是否发动。
## 返回 WAIT＝正在等回复；URGENT＝已发动并压入了「摸牌」状态（调用方先让引擎跑完它再往下）；
## SUCCESS＝没发动 / 摸 0 张，无需额外推进
func _询问怒吼(ctx: Dictionary) -> int:
	if _nu_qi() <= 0:
		return SUCCESS
	if not engine.has_reply():
		_问怒吼(ctx)
		return WAIT
	var 摸牌数: int = _读取怒吼回复()
	if 摸牌数 < 0:
		return SUCCESS
	_发动怒吼(ctx, 摸牌数)
	# 摸牌走的是 push_draw（要触发 p_before_draw 的响应），状态排在栈里 —— 报 URGENT 让引擎先跑完它
	return URGENT if 摸牌数 > 0 else SUCCESS


## 明镜止水（直接结算）：知性满 4 时清零，本次攻击对方无法应战；置标记供攻击结束 +1 水晶
func _发动明镜止水(ctx: Dictionary) -> void:
	if _zhi_xing() != _token_max():
		return
	notice_skill(MING_JING_ZHI_SHUI, [int(ctx.get("dst", -1))])
	_set_zhi_xing(0)
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	ming_jing_used = true
	engine._broadcast_game()


## 明镜止水（原版询问）：普通出牌攻击时弹窗询问是否发动
func _询问明镜止水(ctx: Dictionary) -> int:
	if _zhi_xing() != _token_max():
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, MING_JING_ZHI_SHUI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	_发动明镜止水(ctx)
	return SUCCESS


# ============================================================
# 攻击行动结束后：明镜止水 +1 水晶
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not ming_jing_used:
		return SUCCESS
	ming_jing_used = false
	player.set_crystal(player.crystal + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击命中后：禁断之力
# ============================================================
## 【禁断之力（命中）】的推进阶段（0＝还没开始 / JIN_DUAN_ZHI_LI＝在问是否发动）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击命中（p_timeline_2_hit）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 发动后会返回 URGENT（压入了自伤与精疲力竭），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _jin_duan_hit_step: int = 0


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if _jin_duan_hit_step == 0:
		_jin_duan_hit_step = JIN_DUAN_ZHI_LI
	if _jin_duan_hit_step == JIN_DUAN_ZHI_LI:
		var r: int = _jin_duan_zhi_li(ctx, true)
		if r == WAIT:
			return WAIT
		_jin_duan_hit_step = 0
		if r == URGENT:
			step = STEP_DONE
			return URGENT
	return SUCCESS


## 攻击未命中后：怒吼补正 → 禁断之力
## 【怒吼补正 / 禁断之力（未命中）】的推进阶段（0＝还没开始 / NU_HOU＝怒吼未命中补正 /
## JIN_DUAN_ZHI_LI＝在问是否发动禁断之力）。用自有变量而不是引擎的 step：
## 钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，中途一旦被别的钩子轮次
## （改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击未命中（p_timeline_2_miss）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 发动后会返回 URGENT（压入了自伤与精疲力竭），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _jin_duan_miss_step: int = 0


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if _jin_duan_miss_step == 0:
		_jin_duan_miss_step = NU_HOU
	if _jin_duan_miss_step == NU_HOU:
		_nu_hou_miss()
		_jin_duan_miss_step = JIN_DUAN_ZHI_LI
	if _jin_duan_miss_step == JIN_DUAN_ZHI_LI:
		var r: int = _jin_duan_zhi_li(ctx, false)
		if r == WAIT:
			return WAIT
		_jin_duan_miss_step = 0
		if r == URGENT:
			step = STEP_DONE
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
		# 服务端按客户端回传的全部手牌统计：这里要求玩家选齐所有手牌（弃掉全部手牌）。
		# need_card 直接用当前手牌数：手里没牌时是 0，那也照问 —— 空手照样能发动它，
		# 换来【精疲力竭】（横置 + 额外攻击 + 手牌上限 4），弃牌统计自然是 0。
		# 命中那条会因弃火系牌加伤并反噬自己，故把攻击目标与「发动前伤害」（已含怒吼等）下发：
		# 客户端据此在敌人头像现算「本次攻击伤害」、在自己头像现算反噬的法术伤害。未命中那条不发。
		var dst: int = int(ctx.get("dst", -1))
		var 攻击目标: Array = [dst] if hit and dst >= 0 else []
		var 发动前伤害: int = int(ctx.get("harm", {}).get("point", 0)) if hit else 0
		询问(player.id, JIN_DUAN_ZHI_LI, player.hand_cards.size(), 0,
			GConst.CardSource.Hand, [], 0, "", [], true, 0, -1, 攻击目标, -1, {}, 发动前伤害)
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
		engine.take_from_hand(player.id, cards, true)
		engine.to_discard(cards)
	engine._broadcast_game()
	return URGENT


## 精疲力竭：横置，额外 +1 攻击行动，手牌上限恒定为 4
func _jing_pi_li_jie() -> void:
	player.hand_cards_max = JING_PI_HAND_MAX
	player.add_action(GConst.ActionType.Attack, JING_PI_LI_JIE, true)
	engine.set_tap(player.id, true)


# ============================================================
# 承受法术伤害：死斗
# ============================================================
## 【死斗】的推进阶段（0＝还没开始 / SI_DOU＝在问是否发动）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 在「按点数摸牌之前」（p_timeline_6）询问：本次伤害若把手牌顶过上限而掉士气，
## p_fix_morale 才能把本次下降压到 1（摸牌与掉士气都发生在 p_timeline_6_drawn 之前）。
var _si_dou_step: int = 0


func p_timeline_6(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("point", 0)) <= 0 or int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if player.gem <= 0:
		return SUCCESS
	if _si_dou_step == 0:
		_si_dou_step = SI_DOU
	if _si_dou_step == SI_DOU:
		var r: int = _si_dou()
		if r == WAIT:
			return WAIT
		_si_dou_step = 0
	return SUCCESS


## 本次伤害流水线收尾（p_timeline_6_drawn 在摸牌与掉士气之后触发）：清掉【死斗】的士气上限标记
func p_timeline_6_drawn(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	si_dou_morale_lock = false
	return SUCCESS


## 死斗：消耗 1 宝石，怒气 +3；本次伤害造成的我方士气下降恒定为 1（见 p_fix_morale）
func _si_dou() -> int:
	if not engine.has_reply():
		询问(player.id, SI_DOU, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(SI_DOU, [player.id])
	player.set_gem(player.gem - 1)
	_set_nu_qi(_nu_qi() + 3)
	si_dou_morale_lock = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 掉士气链：死斗把本次（因法术伤害的）士气下降恒定为 1
# ============================================================
func p_fix_morale(ctx: Dictionary) -> int:
	if not si_dou_morale_lock:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	if int(ctx.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if int(ctx.get("amount", 0)) > 1:
		ctx["amount"] = 1
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
		# 记下「是谁放的」：被挑衅的人只能主动攻击放牌者本人（多勇者时也锁死他，见 base_v_attack）
		dst.add_exclusive_effect(GConst.Exclusive.TiaoXin, player.id)
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

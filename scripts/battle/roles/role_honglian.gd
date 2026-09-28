extends BattleRole
## 红莲骑士（roleID 28）—— 移植自服务端 role/HongLian.cpp
## 形态：tap（血印形态）+ 血印指示物（上限 2）；cross_max = 4
## 技能：腥红圣约（2801，主动攻击宣告后可选：治疗未满且本回合未用 → +1 治疗）、
##       腥红信仰（2802，被动：被他人伤害且可治疗时，放弃治疗结算）、
##       血腥祷言（2803，启动：把治疗转移给其他角色，转移一次 +1 血印，自身承受等量法术伤害）、
##       杀戮盛宴（2806，主动攻击命中后可选：耗 1 血印，伤害 +2，自身受 4 点法术伤害）、
##       热血沸腾（2807，被动：血印形态下不损失士气；未横置时受伤进入血印形态；回合结束解除并 +2 治疗）、
##       戒骄戒躁（2808，额外行动：血印形态且能量≥1 时追加一次攻击/法术行动）、
##       腥红十字（2809，法术技能：弃 2 张法术牌 + 1 能量 + 1 血印，目标 3 点、自身 4 点法术伤害）

const XING_HONG_SHENG_YUE: int = 2801
const XING_HONG_XIN_YANG: int = 2802
const XUE_XING_DAO_YAN: int = 2803
const SHA_LU_SHENG_YAN: int = 2806
const RE_XUE_FEI_TENG: int = 2807
const JIE_JIAO_JIE_ZAO: int = 2808
const XING_HONG_SHI_ZI: int = 2809

## 引擎 p_timeline_4 无 crossAvailable 字段（服务端用于关闭治疗结算）：
## 改为「p_timeline_4 临时清空目标治疗，p_timeline_5 还原」，与 role_xuejian.gd 共用同一键
const HARM_NO_CROSS_KEY: String = "no_cross_backup"


var used_xing_hong_sheng_yue: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.cross_max = 4
	p.tokens[0] = {"name": "血印", "max": 2, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if player.get_energy() >= 1 and int(player.tokens[0]["num"]) >= 1 and _magic_card_count() >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": XING_HONG_SHI_ZI, "need_card": 1, "need_target": 1})
	return out


## 手牌中法术牌数量
func _magic_card_count() -> int:
	var n: int = 0
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			n += 1
	return n


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_xing_hong_sheng_yue = false
	return SUCCESS


# ============================================================
# 启动：血腥祷言（自身回合且有治疗时询问）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or player.cross_num == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, XUE_XING_DAO_YAN, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) == 0:
		return SUCCESS
	var dsts: Array = r.get("dst_ids", [])
	var total: int = 0
	for i: int in range(dsts.size()):
		total += int(args[i]) if i < args.size() else 0
	if total <= 0 or player.cross_num < total:
		return SUCCESS
	notice_skill(XUE_XING_DAO_YAN, dsts)
	player.sub_cross_num(total)
	for i: int in range(dsts.size()):
		var dp: BattlePlayer = engine.p(int(dsts[i]))
		if dp != null:
			dp.add_cross_num(int(args[i]) if i < args.size() else 0)
	if int(player.tokens[0]["num"]) < 2:
		player.tokens[0]["num"] = int(player.tokens[0]["num"]) + 1
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": total,
		"cause": XUE_XING_DAO_YAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 攻击宣告后：腥红圣约（主动攻击可选，治疗未满上限时 +1 治疗）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.cross_num >= player.cross_max or used_xing_hong_sheng_yue:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, XING_HONG_SHENG_YUE, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(XING_HONG_SHENG_YUE, [int(ctx.get("dst", -1))])
	player.add_cross_num(1)
	used_xing_hong_sheng_yue = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后：杀戮盛宴（耗 1 血印，伤害 +2，自身受 4 点法术伤害）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)) or int(player.tokens[0]["num"]) == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, SHA_LU_SHENG_YAN, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(SHA_LU_SHENG_YAN, [int(harm.get("dst", -1))])
	harm["point"] = int(harm.get("point", 0)) + 2
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 1
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 4,
		"cause": SHA_LU_SHENG_YAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 腥红信仰：被他人伤害且可用治疗时，关闭治疗结算（p_timeline_4 → p_timeline_5 还原）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("src", -1)) == player.id:
		return SUCCESS
	if player.cross_num <= 0 or harm.has(HARM_NO_CROSS_KEY):
		return SUCCESS
	notice_skill(XING_HONG_XIN_YANG, [player.id])
	harm[HARM_NO_CROSS_KEY] = player.cross_num
	player.cross_num = 0
	return SUCCESS


func p_timeline_5(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	_restore_cross(harm)
	return SUCCESS


## 还原被腥红信仰临时清空的治疗
func _restore_cross(harm: Dictionary) -> void:
	if not harm.has(HARM_NO_CROSS_KEY):
		return
	var dst: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if dst != null:
		dst.cross_num = int(harm[HARM_NO_CROSS_KEY])
	harm.erase(HARM_NO_CROSS_KEY)


# ============================================================
# 攻击/法术行动结束后：戒骄戒躁（血印形态 + 能量≥1 时追加一次攻击/法术行动）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	return _jie_jiao_jie_zao(int(ctx.get("player", -1)))


func p_after_magic(ctx: Dictionary) -> int:
	return _jie_jiao_jie_zao(int(ctx.get("player", ctx.get("src", -1))))


## 授予额外行动（服务端 JieJiaoJieZao 仅 addAction，代价改在玩家选择时结算）
func _jie_jiao_jie_zao(pid: int) -> int:
	if pid != player.id or not player.tap or player.get_energy() < 1:
		return SUCCESS
	player.add_action(GConst.ActionType.AttackMagic, JIE_JIAO_JIE_ZAO)
	return SUCCESS


# ============================================================
# 玩家选择额外行动时：戒骄戒躁扣 1 能量（优先水晶）并解除血印形态
# （引擎已在选中时广播该额外行动的技能宣告，此处不再重复）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or int(ctx.get("cause", 0)) != JIE_JIAO_JIE_ZAO:
		return SUCCESS
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	player.tap = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 热血沸腾：血印形态下不受士气损失；未横置时因伤害掉士气则进入血印形态；
# 回合结束解除并 +2 治疗（服务端要求 harm.type != HARM_NONE）
# ============================================================
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if not player.tap or int(ctx.get("amount", 0)) <= 0:
		return SUCCESS
	if int(ctx.get("type", 0)) == GConst.HarmType.None:
		return SUCCESS
	ctx["amount"] = 0
	return SUCCESS


func p_true_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id or player.tap:
		return SUCCESS
	if int(ctx.get("amount", 0)) <= 0:
		return SUCCESS
	if int(ctx.get("type", 0)) == GConst.HarmType.None:
		return SUCCESS
	notice_skill(RE_XUE_FEI_TENG, [player.id])
	player.tap = true
	engine._broadcast_game()
	return SUCCESS


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not player.tap:
		return SUCCESS
	player.tap = false
	player.add_cross_num(2)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能：腥红十字
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XING_HONG_SHI_ZI:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2 or player.get_energy() < 1 or int(player.tokens[0]["num"]) == 0:
		return GConst.GE_INVALID_ACTION
	for c: Variant in cards:
		var cid: int = int(c)
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != XING_HONG_SHI_ZI:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(XING_HONG_SHI_ZI, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 1
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 3,
		"cause": XING_HONG_SHI_ZI, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 4,
		"cause": XING_HONG_SHI_ZI, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	engine._broadcast_game()
	return URGENT

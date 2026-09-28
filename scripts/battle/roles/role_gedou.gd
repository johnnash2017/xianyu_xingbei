extends BattleRole
## 格斗家（roleID 20）—— 移植自服务端 role/GeDou.cpp
## 技能：念气力场（被动，所有对自己造成的伤害每次最高 4 点）、
##       蓄力一击（主动攻击前，+1 斗气且本次伤害 +1；未命中则对自己造成等同斗气数的法术伤害）、
##       苍炎之魂（主动攻击前，移除 1 斗气，本次攻击无法应战；攻击结束后对自己造成等同斗气数的法术伤害）、
##       念弹（法术行动结束时，+1 斗气并对目标造成 1 点法术伤害；若目标治疗为 0 则同时自伤）、
##       百式幻龙拳（启动，移除 3 斗气并横置：主动攻击伤害 +2、应战攻击伤害 +1，须连续攻击同一目标）、
##       斗神天驱（启动，1 能量：+2 治疗并弃到 3 张牌）
## 【斗气】为格斗家专属指示物，放置于 tokens[0]，上限 6。

const NIAN_QI_LI_CHANG: int = 2001      # 念气力场（被动）
const XU_LI_YI_JI: int = 2002           # 蓄力一击
const NIAN_DAN: int = 2003              # 念弹
const BAI_SHI_HUAN_LONG_QUAN: int = 2004  # 百式幻龙拳
const CANG_YAN_ZHI_HUN: int = 2005      # 苍炎之魂
const DOU_SHEN_TIAN_QU: int = 2006      # 斗神天驱
const XU_LI_CANG_YAN: int = 2025        # 蓄力苍炎（服务端用于「蓄力一击/苍炎之魂」二选一的询问号）
const BAI_SHI_DOU_SHEN: int = 2046      # 百式斗神（服务端用于「百式幻龙拳/斗神天驱」二选一的询问号）

const TOKEN_DOU_QI: int = 0             # 「斗气」指示物下标
const TOKEN_DOU_QI_MAX: int = 6
const DOU_SHEN_KEEP_HAND: int = 3       # 斗神天驱弃到 3 张牌

var xu_li_used: bool = false
var cang_yan_used: bool = false
var bai_shi_used: bool = false
var bai_shi_target: int = -1

## 单次询问内的临时标记
var _xu_li_applied: bool = false
var _bai_shi_activated: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_DOU_QI] = {"name": "斗气", "max": TOKEN_DOU_QI_MAX, "num": 0}


## 格斗家的技能全部在钩子内触发，行动阶段无主动可选技能
func available_skills() -> Array:
	return []


# ============================================================
# 指示物
# ============================================================
func _dou_qi() -> int:
	var t: Dictionary = player.tokens[TOKEN_DOU_QI]
	return int(t["num"])


func _set_dou_qi(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_DOU_QI]
	t["num"] = clampi(v, 0, int(t["max"]))


# ============================================================
# 启动（自己回合开始）：百式幻龙拳 / 斗神天驱
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		_bai_shi_activated = false
		step = BAI_SHI_HUAN_LONG_QUAN
	if step == BAI_SHI_HUAN_LONG_QUAN:
		var r: int = _ask_bai_shi()
		if r == WAIT:
			return WAIT
		step = DOU_SHEN_TIAN_QU if (player.get_energy() > 0 and not _bai_shi_activated) else STEP_DONE
	if step == DOU_SHEN_TIAN_QU:
		var r2: int = _ask_dou_shen()
		if r2 == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 百式幻龙拳：移除 3 点斗气并横置
func _ask_bai_shi() -> int:
	if _dou_qi() < 3:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, BAI_SHI_HUAN_LONG_QUAN, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(BAI_SHI_HUAN_LONG_QUAN, [player.id])
	bai_shi_used = true
	_bai_shi_activated = true
	_set_dou_qi(_dou_qi() - 3)
	player.tap = true
	engine._broadcast_game()
	return SUCCESS


## 斗神天驱：1 能量，+2 治疗，弃到 3 张牌
func _ask_dou_shen() -> int:
	if player.get_energy() <= 0:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, DOU_SHEN_TIAN_QU, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(DOU_SHEN_TIAN_QU, [player.id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	player.add_cross_num(2)
	var over: int = player.hand_cards.size() - DOU_SHEN_KEEP_HAND
	if over > 0:
		var chosen: Array = _pick_cards(r.get("card_ids", []), over)
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": chosen, "is_real": true,
		})
		engine.take_from_hand(player.id, chosen)
		engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS


## 从给定卡牌中挑至多 n 张手牌（不足时按手牌顺序补齐）
func _pick_cards(ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if player.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in player.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


# ============================================================
# 主动攻击宣告后：蓄力一击 / 苍炎之魂 → 百式幻龙拳加成
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		_xu_li_applied = false
		step = XU_LI_CANG_YAN
	if step == XU_LI_CANG_YAN:
		if not bool(ctx.get("is_active", false)):
			step = BAI_SHI_HUAN_LONG_QUAN
		elif _dou_qi() < TOKEN_DOU_QI_MAX:
			step = XU_LI_YI_JI
		else:
			step = CANG_YAN_ZHI_HUN
	if step == XU_LI_YI_JI:
		var r: int = _xu_li_yi_ji(ctx)
		if r == WAIT:
			return WAIT
		step = BAI_SHI_HUAN_LONG_QUAN if _xu_li_applied else CANG_YAN_ZHI_HUN
	if step == CANG_YAN_ZHI_HUN:
		var r2: int = _cang_yan_zhi_hun(ctx)
		if r2 == WAIT:
			return WAIT
		step = BAI_SHI_HUAN_LONG_QUAN
	if step == BAI_SHI_HUAN_LONG_QUAN:
		_bai_shi_harm(ctx)
		step = STEP_DONE
	return SUCCESS


func _xu_li_yi_ji(ctx: Dictionary) -> int:
	if not engine.has_reply():
		engine.ask_skill(player.id, XU_LI_YI_JI, 0, 0)
		return WAIT
	_xu_li_applied = take_skill_reply()
	if not _xu_li_applied:
		return SUCCESS
	notice_skill(XU_LI_YI_JI, [int(ctx.get("dst", -1))])
	xu_li_used = true
	_set_dou_qi(_dou_qi() + 1)
	# 新的主动攻击会打断「百式幻龙拳」
	if player.tap:
		player.tap = false
		bai_shi_target = -1
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + 1
	engine._broadcast_game()
	return SUCCESS


func _cang_yan_zhi_hun(ctx: Dictionary) -> int:
	if _dou_qi() <= 0:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, CANG_YAN_ZHI_HUN, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(CANG_YAN_ZHI_HUN, [int(ctx.get("dst", -1))])
	cang_yan_used = true
	_set_dou_qi(_dou_qi() - 1)
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	engine._broadcast_game()
	return SUCCESS


## 百式幻龙拳：主动攻击伤害 +2（且必须与上次目标相同），应战攻击伤害 +1
func _bai_shi_harm(ctx: Dictionary) -> void:
	if not player.tap:
		return
	var harm: Dictionary = ctx.get("harm", {})
	var dst_id: int = int(ctx.get("dst", -1))
	if bool(ctx.get("is_active", false)):
		if bai_shi_used:
			bai_shi_target = dst_id
			bai_shi_used = false
		if bai_shi_target != dst_id:
			# 目标改变：取消百式幻龙拳
			player.tap = false
			bai_shi_target = -1
			engine._broadcast_game()
			return
		notice_skill(BAI_SHI_HUAN_LONG_QUAN, [dst_id])
		harm["point"] = int(harm.get("point", 0)) + 2
	else:
		notice_skill(BAI_SHI_HUAN_LONG_QUAN, [dst_id])
		harm["point"] = int(harm.get("point", 0)) + 1


# ============================================================
# 主动攻击未命中：蓄力一击反噬（对自己造成等同斗气数的法术伤害）
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	if _dou_qi() == 0 or not xu_li_used:
		return SUCCESS
	xu_li_used = false
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": _dou_qi(),
		"cause": XU_LI_YI_JI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 承受伤害：念气力场（每次伤害最高 4 点）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("point", 0)) <= 4:
		return SUCCESS
	notice_skill(NIAN_QI_LI_CHANG, [player.id])
	harm["point"] = 4
	return SUCCESS


# ============================================================
# 攻击行动结束后：苍炎之魂反噬（对自己造成等同斗气数的法术伤害）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	# 蓄力一击标记随攻击结束清空
	xu_li_used = false
	if _dou_qi() == 0 or not cang_yan_used:
		cang_yan_used = false
		return SUCCESS
	cang_yan_used = false
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": _dou_qi(),
		"cause": CANG_YAN_ZHI_HUN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 法术行动结束后：念弹
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	# 法术牌行动传 src，法术技能传 player
	if int(ctx.get("player", ctx.get("src", -1))) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = NIAN_DAN
	if step == NIAN_DAN:
		var r: int = _nian_dan()
		if r == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


func _nian_dan() -> int:
	if _dou_qi() >= TOKEN_DOU_QI_MAX:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, NIAN_DAN, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
		return SUCCESS
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return SUCCESS
	notice_skill(NIAN_DAN, [dst_id])
	_set_dou_qi(_dou_qi() + 1)
	# 目标治疗为 0 时，同时对自己造成等同斗气数的法术伤害
	if dst.cross_num == 0:
		engine.push_harm({
			"src": player.id, "dst": player.id, "point": _dou_qi(),
			"cause": NIAN_DAN, "type": GConst.HarmType.Magic,
		})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 1,
		"cause": NIAN_DAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 法术 / 特殊行动前：解除【百式幻龙拳】（服务端 GeDou::p_before_magic / p_before_special）
# ============================================================
func p_before_magic(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap:
		return SUCCESS
	player.tap = false
	bai_shi_target = -1
	engine._broadcast_game()
	return SUCCESS


func p_before_special(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap:
		return SUCCESS
	player.tap = false
	bai_shi_target = -1
	engine._broadcast_game()
	return SUCCESS

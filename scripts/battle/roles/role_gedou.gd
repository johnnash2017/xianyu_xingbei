extends BattleRole
## 格斗家（roleID 20）—— 移植自服务端 role/GeDou.cpp
## 技能：念气力场（被动，所有对自己造成的伤害每次最高 4 点）、
##       蓄力一击（主动攻击前，+1 斗气且本次伤害 +1；未命中则对自己造成等同斗气数的法术伤害）、
##       气绝崩击（主动攻击前，移除 1 斗气，本次攻击无法应战；攻击结束后对自己造成等同斗气数的法术伤害）、
##       念弹（法术行动结束时，+1 斗气并对目标造成 1 点法术伤害；若目标治疗为 0 则同时自伤）、
##       百式幻龙拳（启动，移除 3 斗气并横置：主动攻击伤害 +2、应战攻击伤害 +1，须连续攻击同一目标）、
##       斗神天驱（启动，1 能量：+2 治疗并弃到 3 张牌）
## 【斗气】为格斗家专属指示物，放置于 tokens[0]，上限见角色表。

const NIAN_QI_LI_CHANG: int = 2001      # 念气力场（被动）
const XU_LI_YI_JI: int = 2002           # 蓄力一击
const NIAN_DAN: int = 2003              # 念弹
const BAI_SHI_HUAN_LONG_QUAN: int = 2004  # 百式幻龙拳
const QI_JUE_BENG_JI: int = 2005        # 气绝崩击
const DOU_SHEN_TIAN_QU: int = 2006      # 斗神天驱

const TOKEN_DOU_QI: int = 0             # 「斗气」指示物下标
const DOU_SHEN_KEEP_HAND: int = 3       # 斗神天驱弃到 3 张牌

var xu_li_used: bool = false
var qi_jue_used: bool = false
var bai_shi_used: bool = false
var bai_shi_target: int = -1


## 行动阶段可发动的技能：【百式幻龙拳】【斗神天驱】为「启动」，不消耗行动
## （is_free_skill 认可，发动后引擎重新进入行动阶段让玩家继续本回合行动）
func available_skills() -> Array:
	var out: Array = []
	# （「本回合是否已发动过启动技能」由引擎统一过滤，这里只判各技能自己的条件）
	# 百式幻龙拳：未横置（不在形态里）且斗气 ≥ 3 时才能发动（移除 3 斗气并横置）
	if not player.tap and _dou_qi() >= 3:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": BAI_SHI_HUAN_LONG_QUAN,
			"need_card": 0, "need_target": 0})
	# 斗神天驱：有能量（水晶/宝石）时才能发动（耗 1 能量、+2 治疗、弃到 3 张手牌）
	if player.get_energy() > 0:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": DOU_SHEN_TIAN_QU,
			"need_card": maxi(player.hand_cards.size() - DOU_SHEN_KEEP_HAND, 0), "need_target": 0})
	# 【蓄力一击 / 气绝崩击】不再提供技能栏按钮：它们只能在主动攻击宣告时响应发动
	return out


## 【百式幻龙拳】【斗神天驱】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == BAI_SHI_HUAN_LONG_QUAN or skill_id == DOU_SHEN_TIAN_QU


# ============================================================
# 指示物
# ============================================================
func _dou_qi() -> int:
	var t: Dictionary = player.tokens[TOKEN_DOU_QI]
	return int(t["num"])


func _dou_qi_max() -> int:
	return int(player.tokens[TOKEN_DOU_QI]["max"])


## 【斗气】是否已达上限：已达上限时不能发动【蓄力一击】/【念弹】（两处条件共用这一个判断）
func _dou_qi_full() -> bool:
	return _dou_qi() >= _dou_qi_max()


func _set_dou_qi(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_DOU_QI]
	t["num"] = clampi(v, 0, int(t["max"]))


# ============================================================
# 启动技能（行动阶段按钮）：百式幻龙拳 / 斗神天驱
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验各技能自己的条件）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		BAI_SHI_HUAN_LONG_QUAN:
			# 已在形态里（横置）/ 斗气不足 3 点：不能发动
			if player.tap or _dou_qi() < 3:
				return GConst.GE_INVALID_ACTION
		DOU_SHEN_TIAN_QU:
			if player.get_energy() <= 0:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		BAI_SHI_HUAN_LONG_QUAN:
			_apply_bai_shi()
		DOU_SHEN_TIAN_QU:
			_apply_dou_shen(action)
	return SUCCESS


## 百式幻龙拳：移除 3 点斗气并横置（进入形态）
func _apply_bai_shi() -> void:
	notice_skill(BAI_SHI_HUAN_LONG_QUAN, [player.id])
	player.boot_skill_used = true
	bai_shi_used = true
	_set_dou_qi(_dou_qi() - 3)
	player.tap = true
	engine._broadcast_game()


## 斗神天驱：1 能量，+2 治疗，弃到 3 张牌（弃哪些牌从行动回复里取）
func _apply_dou_shen(action: Dictionary) -> void:
	var 弃牌数: int = maxi(player.hand_cards.size() - DOU_SHEN_KEEP_HAND, 0)
	notice_skill(DOU_SHEN_TIAN_QU, [player.id])
	player.boot_skill_used = true
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	施加治疗(player.id, 2)
	if 弃牌数 > 0:
		var chosen: Array = _pick_cards(action.get("card_ids", []), 弃牌数)
		engine.take_from_hand(player.id, chosen)
		engine.to_discard(chosen)
		engine._log_discard(player.id, chosen)
	engine._broadcast_game()


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


## 【蓄力一击 / 气绝崩击 / 百式幻龙拳】的推进阶段
enum 攻击阶段 { 未开始, 判定, 百式 }

## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 未开始
var _攻击阶段: int = 攻击阶段.未开始


# ============================================================
# 主动攻击宣告后：先问「蓄力一击 / 气绝崩击」→ 百式幻龙拳加成
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if _攻击阶段 == 攻击阶段.未开始:
		_攻击阶段 = 攻击阶段.判定
	if _攻击阶段 == 攻击阶段.判定:
		# 普通攻击（打出攻击牌）按原版问一次「要发动蓄力一击 / 气绝崩击吗」；
		# 应战反击不走（原版只问主动攻击）。正在等答复时 _攻击阶段 停在 判定，下次进本钩子继续
		if bool(ctx.get("is_active", false)):
			var r: int = _询问攻击加成(ctx)
			if r == WAIT:
				return WAIT
		_攻击阶段 = 攻击阶段.百式
	if _攻击阶段 == 攻击阶段.百式:
		_bai_shi_harm(ctx)
		_攻击阶段 = 攻击阶段.未开始
	return SUCCESS


## 主动攻击宣告后的询问（对照原版客户端 GeDouJia::XuLiCangYan 的「请选择要发动的技能」）：
## 斗气未满才可给【蓄力一击】、斗气 ≥ 1 才可给【气绝崩击】，两个都给不了就不问（照旧只算百式加成）。
## 只有一个可发动时直接问「是否发动【X】？」；两个都可发动时才进二级技能栏二选一。
## 点「取消」＝不发动。选中了就地下结算加成（_结算蓄力一击 / _结算气绝崩击）。
## 返回 WAIT 表示正在等玩家答复。
func _询问攻击加成(ctx: Dictionary) -> int:
	var 可蓄力: bool = not _dou_qi_full()
	var 可气绝: bool = _dou_qi() >= 1
	if 可蓄力 and not 可气绝:
		return _问单项加成(XU_LI_YI_JI, ctx)
	if 可气绝 and not 可蓄力:
		return _问单项加成(QI_JUE_BENG_JI, ctx)
	if not 可蓄力 and not 可气绝:
		return SUCCESS
	# 两个都能发动：进二级技能栏二选一。选项本身就是两颗技能，
	# 故不再摆「技能本体」那一颗（见 const.技能指示器「无父技能」）
	if not engine.has_reply():
		engine.ask_skill(player.id, XU_LI_YI_JI, 0, 0, GConst.CardSource.Hand, _攻击加成选项(), 0, "", [], true,
			"主动攻击：请选择要发动的技能（点「取消」＝都不发动）",
			[int(ctx.get("dst", -1))], int(ctx.get("harm", {}).get("point", 0)))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 选: int = int(args[0]) if not args.is_empty() else 0
	if 选 == XU_LI_YI_JI:
		_结算蓄力一击(ctx)
	elif 选 == QI_JUE_BENG_JI:
		_结算气绝崩击(ctx)
	return SUCCESS


## 只有一个可发动时的直接询问：不打二级技能栏，一问一答（确定＝发动、取消＝不发动）
func _问单项加成(技能号: int, ctx: Dictionary) -> int:
	if not engine.has_reply():
		engine.ask_skill(player.id, 技能号, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			"是否发动【%s】？" % GConst.skill_name(技能号),
			[int(ctx.get("dst", -1))], int(ctx.get("harm", {}).get("point", 0)))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	if 技能号 == XU_LI_YI_JI:
		_结算蓄力一击(ctx)
	else:
		_结算气绝崩击(ctx)
	return SUCCESS


## 二级技能栏里的两个选项（供两技能都可发动时二选一用）。
## 带上 skill_id：这两项本身就是技能，客户端鼠标指向选项按钮时据此弹技能说明
func _攻击加成选项() -> Array:
	return [
		{"value": XU_LI_YI_JI, "label": GConst.skill_name(XU_LI_YI_JI), "skill_id": XU_LI_YI_JI},
		{"value": QI_JUE_BENG_JI, "label": GConst.skill_name(QI_JUE_BENG_JI), "skill_id": QI_JUE_BENG_JI},
	]


## 蓄力一击：+1 斗气、本次伤害 +1；新的主动攻击会打断【百式幻龙拳】
func _结算蓄力一击(ctx: Dictionary) -> void:
	notice_skill(XU_LI_YI_JI, [int(ctx.get("dst", -1))])
	xu_li_used = true
	_set_dou_qi(_dou_qi() + 1)
	if player.tap:
		player.tap = false
		bai_shi_target = -1
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + 1
	engine._broadcast_game()


## 气绝崩击：移除 1 斗气、本次攻击对方无法应战（攻击后的自伤见 p_after_attack）
func _结算气绝崩击(ctx: Dictionary) -> void:
	notice_skill(QI_JUE_BENG_JI, [int(ctx.get("dst", -1))])
	qi_jue_used = true
	_set_dou_qi(_dou_qi() - 1)
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	engine._broadcast_game()


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
		harm["point"] = int(harm.get("point", 0)) + GConst.百式幻龙拳主动加成
	else:
		notice_skill(BAI_SHI_HUAN_LONG_QUAN, [dst_id])
		harm["point"] = int(harm.get("point", 0)) + GConst.百式幻龙拳应战加成


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
# 承受伤害：念气力场（每次伤害最高 GConst.念气力场上限 点，客户端据此画两行飘字）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("point", 0)) <= GConst.念气力场上限:
		return SUCCESS
	notice_skill(NIAN_QI_LI_CHANG, [player.id])
	harm["point"] = GConst.念气力场上限
	return SUCCESS


# ============================================================
# 攻击行动结束后：气绝崩击反噬（对自己造成等同斗气数的法术伤害）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	# 蓄力一击标记随攻击结束清空
	xu_li_used = false
	if _dou_qi() == 0 or not qi_jue_used:
		qi_jue_used = false
		return SUCCESS
	qi_jue_used = false
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": _dou_qi(),
		"cause": QI_JUE_BENG_JI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 【念弹】的推进阶段（0＝还没开始 / NIAN_DAN＝正在询问并结算念弹）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己法术行动结束（p_after_magic）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _nian_dan_step: int = 0


# ============================================================
# 法术行动结束后：念弹
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 本次行动已处理：URGENT 回来后引擎会用同一 ctx 再进本钩子，直接挡掉，别重复询问/重复伤害
	if bool(ctx.get("nian_dan_done", false)):
		return SUCCESS
	if _nian_dan_step >= STEP_DONE:
		return SUCCESS
	if _nian_dan_step == 0:
		_nian_dan_step = NIAN_DAN
	if _nian_dan_step == NIAN_DAN:
		var r: int = _nian_dan()
		if r == WAIT:
			return WAIT
		_nian_dan_step = 0
		if r == URGENT:
			# 念弹已 push_harm：标记本次已处理再返回 URGENT，让引擎先把伤害结算完再继续本回合
			# （原先吞掉 URGENT 直接 return SUCCESS，与「先压栈再返回 URGENT」的惯例不一致）
			ctx["nian_dan_done"] = true
			return URGENT
	return SUCCESS


func _nian_dan() -> int:
	if not engine.has_reply():
		# 【法术行动】结束即 +1【斗气】，且要在「选择目标」之前完成：
		# 念弹的自伤＝斗气数，客户端选目标时的指示器必须按加过 1 的值算；斗气已满则不能发动
		if _dou_qi_full():
			return SUCCESS
		_set_dou_qi(_dou_qi() + 1)
		engine._broadcast_game()
		询问(player.id, NIAN_DAN, 0, 1)
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
	# 目标治疗为 0 时，同时对自己造成等同斗气数（已含本次 +1）的法术伤害
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

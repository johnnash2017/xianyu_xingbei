extends BattleRole
## 剑帝（roleID 19）—— 移植自服务端 role/JianDi.cpp
## 指示物：【剑气】(tokens[0]，上限 5)；盖牌：【剑魂】(cover_cards_max = 3)
## 技能：剑魂守护（1901，被动：主动攻击未命中时把本次打出的攻击牌作为【剑魂】；
##                 【剑魂】已满 3 张、或本回合已发动天使之魂/恶魔之魂时不可发动）、
##       佯攻（1902，被动：主动攻击未命中时 +1 剑气）、
##       剑气斩（1903，响应：主动攻击命中后移除 X 点【剑气】，对指定角色造成 X 点法术伤害）、
##       天使之魂（1905，响应：主动攻击前移除 1 张【剑魂】；命中则 +2 治疗，未命中则我方 +1 士气）、
##       恶魔之魂（1906，响应：主动攻击前移除 1 张【剑魂】；命中则本次伤害 +1，未命中则 +2 剑气）、
##       不屈意志（1907，额外攻击行动：耗 1 点能量，摸 1 张牌并 +1 剑气）
## 【剑魂】的视为对象由当前能量单双决定（奇数为天使之魂、双数为恶魔之魂、无能量则都不是），
## 对应服务端 TianShiYuEMo() 的 flag。

const JIAN_HUN_SHOU_HU: int = 1901
const YANG_GONG: int = 1902
const JIAN_QI_ZHAN: int = 1903
const TIAN_SHI_ZHI_HUN: int = 1905
const E_MO_ZHI_HUN: int = 1906
const BU_QU_YI_ZHI: int = 1907

## 天使之魂未命中时加士气的上限（服务端硬编码 15）
const MORALE_LIMIT: int = 15


var used_tian_shi_zhi_hun: bool = false
var used_e_mo_zhi_hun: bool = false
## 本回合是否已授予【不屈意志】的额外行动（服务端 added_BU_QU_YI_ZHI）
var added_bu_qu_yi_zhi: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.cover_cards_max = 3
	p.tokens[0] = {"name": "剑气", "max": 5, "num": 0}


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_tian_shi_zhi_hun = false
	used_e_mo_zhi_hun = false
	added_bu_qu_yi_zhi = false
	return SUCCESS


## 【剑魂】的视为对象：0 = 都不属于 / 1 = 天使之魂 / 2 = 恶魔之魂
func _soul_form() -> int:
	var energy: int = player.get_energy()
	if energy == 0:
		return 0
	if energy % 2 != 0:
		return 1
	return 2


## 取回复中第一张自己真实拥有的盖牌（无则 -1）
func _cover_card_of(ids: Array) -> int:
	for c: Variant in ids:
		if player.cover_cards.has(int(c)):
			return int(c)
	return -1


# ============================================================
# 主动攻击宣告前：天使之魂 / 恶魔之魂（移除 1 张【剑魂】）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.cover_count() == 0:
		return SUCCESS
	# 同一轮钩子内只询问一次（ctx 在钩子轮次内保持不变）
	if bool(ctx.get("jian_di_hun_done", false)) or step >= STEP_DONE:
		return SUCCESS
	var form: int = _soul_form()
	if form == 0:
		return SUCCESS
	var skill_id: int = TIAN_SHI_ZHI_HUN if form == 1 else E_MO_ZHI_HUN
	if step == 0:
		step = skill_id
	if step != skill_id:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, skill_id, 1, 0, GConst.CardSource.Cover)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	ctx["jian_di_hun_done"] = true
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cid: int = _cover_card_of(r.get("card_ids", []))
	if cid < 0:
		return SUCCESS
	notice_skill(skill_id, [int(ctx.get("dst", -1))])
	player.remove_cover_cards([cid])
	engine.to_discard([cid])
	if skill_id == TIAN_SHI_ZHI_HUN:
		used_tian_shi_zhi_hun = true
	else:
		used_e_mo_zhi_hun = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后：剑气斩 → 恶魔之魂（+1 伤害）→ 天使之魂（+2 治疗）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	var urgent: bool = false
	if step == 0:
		step = JIAN_QI_ZHAN
	if step == JIAN_QI_ZHAN:
		if int(player.tokens[0]["num"]) <= 0 or bool(ctx.get("jian_di_jqz_done", false)):
			step = E_MO_ZHI_HUN
		else:
			if not engine.has_reply():
				engine.ask_skill(player.id, JIAN_QI_ZHAN, 0, 1)
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			ctx["jian_di_jqz_done"] = true
			var args: Array = r.get("args", [])
			var dsts: Array = r.get("dst_ids", [])
			if not args.is_empty() and int(args[0]) == 1 and not dsts.is_empty():
				# 服务端 args(1) 为移除的【剑气】数，客户端未提供时按最低 1 点处理
				var count: int = int(args[1]) if args.size() > 1 else 1
				count = mini(maxi(count, 0), int(player.tokens[0]["num"]))
				if count > 0:
					notice_skill(JIAN_QI_ZHAN, [int(dsts[0])])
					player.tokens[0]["num"] = int(player.tokens[0]["num"]) - count
					engine.push_harm({
						"src": player.id, "dst": int(dsts[0]), "point": count,
						"cause": JIAN_QI_ZHAN, "type": GConst.HarmType.Magic,
					})
					urgent = true
			step = E_MO_ZHI_HUN
	if step == E_MO_ZHI_HUN:
		if used_e_mo_zhi_hun and not bool(ctx.get("jian_di_emo_done", false)):
			ctx["jian_di_emo_done"] = true
			used_e_mo_zhi_hun = false
			notice_skill(E_MO_ZHI_HUN, [int(harm.get("dst", -1))])
			harm["point"] = int(harm.get("point", 0)) + 1
		step = TIAN_SHI_ZHI_HUN
	if step == TIAN_SHI_ZHI_HUN:
		if used_tian_shi_zhi_hun and not bool(ctx.get("jian_di_tianshi_done", false)):
			ctx["jian_di_tianshi_done"] = true
			used_tian_shi_zhi_hun = false
			notice_skill(TIAN_SHI_ZHI_HUN, [player.id])
			player.add_cross_num(2)
		step = STEP_DONE
	engine._broadcast_game()
	return URGENT if urgent else SUCCESS


# ============================================================
# 主动攻击未命中后：佯攻（+1 剑气）→ 剑魂守护 → 天使之魂 / 恶魔之魂的未命中效果
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = YANG_GONG
	if step == YANG_GONG:
		notice_skill(YANG_GONG, [player.id])
		if int(player.tokens[0]["num"]) < int(player.tokens[0]["max"]):
			player.tokens[0]["num"] = int(player.tokens[0]["num"]) + 1
		step = JIAN_HUN_SHOU_HU
	if step == JIAN_HUN_SHOU_HU:
		_jian_hun_shou_hu(ctx)
		step = TIAN_SHI_ZHI_HUN
	if step == TIAN_SHI_ZHI_HUN:
		if used_tian_shi_zhi_hun:
			used_tian_shi_zhi_hun = false
			_tian_shi_zhi_hun_miss()
		step = E_MO_ZHI_HUN
	if step == E_MO_ZHI_HUN:
		if used_e_mo_zhi_hun:
			used_e_mo_zhi_hun = false
			notice_skill(E_MO_ZHI_HUN, [player.id])
			var cap: int = int(player.tokens[0]["max"])
			player.tokens[0]["num"] = mini(int(player.tokens[0]["num"]) + 2, cap)
		step = STEP_DONE
	engine._broadcast_game()
	return SUCCESS


## 剑魂守护：把本次打出的攻击牌从弃牌堆移入盖牌区作为【剑魂】
func _jian_hun_shou_hu(ctx: Dictionary) -> void:
	if player.cover_count() >= 3 or used_tian_shi_zhi_hun or used_e_mo_zhi_hun:
		return
	var cid: int = int(ctx.get("card_id", -1))
	if Data.get_card(cid) == null:
		return
	notice_skill(JIAN_HUN_SHOU_HU, [player.id])
	engine.deck.remove_one(cid)
	player.add_cover_cards([cid])


## 天使之魂未命中：我方士气 +1（未达上限时）
func _tian_shi_zhi_hun_miss() -> void:
	if engine.team_morale[player.color] >= MORALE_LIMIT:
		return
	notice_skill(TIAN_SHI_ZHI_HUN, [player.id])
	engine.set_morale(player.color, engine.team_morale[player.color] + 1)


# ============================================================
# 攻击行动结束后：不屈意志（有能量时授予额外攻击行动，代价在玩家选中时结算）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if added_bu_qu_yi_zhi or player.get_energy() <= 0:
		return SUCCESS
	added_bu_qu_yi_zhi = true
	player.add_action(GConst.ActionType.Attack, BU_QU_YI_ZHI)
	return SUCCESS


# ============================================================
# 玩家选择额外行动时：不屈意志（耗 1 点能量，摸 1 张牌并 +1 剑气；服务端 JianDi::BuQuYiZhi）
# （引擎已在选中时广播该额外行动的技能宣告，此处不再重复）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or int(ctx.get("cause", 0)) != BU_QU_YI_ZHI:
		return SUCCESS
	# 扣 1 点能量（优先水晶）
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	# +1 剑气（上限封顶）
	if int(player.tokens[0]["num"]) < int(player.tokens[0]["max"]):
		player.tokens[0]["num"] = int(player.tokens[0]["num"]) + 1
	engine.draw(player.id, 1)
	engine._broadcast_game()
	return SUCCESS

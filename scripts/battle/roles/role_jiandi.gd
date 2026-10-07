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


## 行动阶段可发动的技能：天使之魂 / 恶魔之魂
##（用一张手牌攻击牌发起主动攻击，并把 1 张【剑魂】从盖牌区移除弃置作为代价）。
## 形态由当前能量单双决定，一次只会出对应的那一个按钮；对照原版只要盖牌区还有【剑魂】，
## 同一回合的每一次主动攻击都可以再发动（受剑魂数量限制），故这里不按 used_ 标记收口
func available_skills() -> Array:
	var out: Array = []
	var form: int = _soul_form()
	if form == 0 or player.cover_cards.is_empty():
		return out
	var 攻击牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.is_attack())
	var 目标: Array[int] = enemy_ids()
	if 攻击牌.is_empty() or 目标.is_empty():
		return out
	if form == 1:
		out.append({"type": GConst.ActionType.AttackSkill, "id": TIAN_SHI_ZHI_HUN, "need_card": 1, "need_target": 1,
			"cards": 攻击牌, "targets": 目标})
	elif form == 2:
		out.append({"type": GConst.ActionType.AttackSkill, "id": E_MO_ZHI_HUN, "need_card": 1, "need_target": 1,
			"cards": 攻击牌, "targets": 目标})
	return out


## 剑气斩的可选目标：除「本次攻击目标」外的所有角色（对照原客户端 playerArea->enableAll + disablePlayerItem(本次目标)）
func _可选目标(本次目标: int) -> Array:
	var out: Array = []
	for pid: int in engine.players:
		if pid != 本次目标:
			out.append(pid)
	return out


## 剑气斩超时自动选取的目标：优先「本次攻击目标」以外的一名敌方；没有就取第一个不是本次攻击目标的角色
func _超时自动目标(本次目标: int) -> int:
	var 备选: int = -1
	for pid: int in engine.players:
		if pid == 本次目标:
			continue
		var p: BattlePlayer = engine.players[pid]
		if p != null and p.color != player.color:
			return pid
		if 备选 < 0:
			备选 = pid
	return 备选


# ============================================================
# 主动攻击宣告前：天使之魂 / 恶魔之魂（移除 1 张【剑魂】）
# ============================================================
## 本次主动攻击预选的「天使之魂 / 恶魔之魂」技能号（0＝普通攻击）：由 p_attack_skill 在发起攻击前写入，
## p_timeline_1 据此判断本次攻击是否由技能栏按钮发起（是则直接置 used 标记，不再弹窗），用完即清
var _预选攻击技能: int = 0

## 普通出牌攻击的询问流程推进阶段（0＝还没开始 / TIAN_SHI_ZHI_HUN 或 E_MO_ZHI_HUN＝已定形态、等回复）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0


# ============================================================
# 天使之魂 / 恶魔之魂（攻击技能）：选一张【剑魂】（盖牌区）+ 一名对手，发起一次主动攻击
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	if aid != TIAN_SHI_ZHI_HUN and aid != E_MO_ZHI_HUN:
		return GConst.GE_INVALID_ACTION
	# 形态必须与技能匹配（能量奇数＝天使之魂 / 偶数＝恶魔之魂）；对照原版不做「本回合已发动」限制
	var form: int = _soul_form()
	if aid == TIAN_SHI_ZHI_HUN:
		if form != 1:
			return GConst.GE_INVALID_ACTION
	elif form != 2:
		return GConst.GE_INVALID_ACTION
	# 代价：盖牌区必须有【剑魂】可移除
	if player.cover_cards.is_empty():
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	# 攻击牌来自手牌：通用攻击校验（含持有该牌、目标不同队、被挑衅限制）
	if player.v_attack(cid, dst_id, engine.players) != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 天使之魂 / 恶魔之魂：打出所选手牌攻击牌发起一次主动攻击，并把 1 张【剑魂】从盖牌区移除弃置作为代价。
## 攻击宣告后 p_timeline_1 依据 _预选攻击技能 直接置 used 标记（不再弹窗询问）
func p_attack_skill(action: Dictionary) -> int:
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	# 代价：【剑魂】只存在于盖牌区且彼此等价，直接取第一张
	var 剑魂: int = int(player.cover_cards[0])
	_预选攻击技能 = aid
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": BattleEngine.ATTACK_BASE_POINT, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": cid, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, cid, harm))
	# 攻击牌从手牌打出
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	# 【剑魂】作为代价从盖牌区移除并弃置
	engine.to_discard([剑魂])
	engine.remove_cover(player.id, [剑魂], player.id, aid)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true,
	})
	return URGENT


# ============================================================
# 主动攻击宣告后：天使之魂 / 恶魔之魂
# (A) 技能栏按钮发起（_预选攻击技能 命中 1905/1906）：代价已在 p_attack_skill 付掉，这里只置 used 标记；
# (B) 普通出牌攻击（_预选攻击技能 == 0）：按 _soul_form() 弹窗询问是否发动，并从盖牌区选 1 张【剑魂】作代价
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	var 预选: int = _预选攻击技能
	_预选攻击技能 = 0
	# (A) 技能栏按钮发起：直接置 used 标记，不再弹窗
	if 预选 == TIAN_SHI_ZHI_HUN or 预选 == E_MO_ZHI_HUN:
		if not bool(ctx.get("is_active", false)):
			return SUCCESS
		if 预选 == TIAN_SHI_ZHI_HUN:
			used_tian_shi_zhi_hun = true
			notice_skill(TIAN_SHI_ZHI_HUN, [int(ctx.get("dst", -1))])
		else:
			used_e_mo_zhi_hun = true
			notice_skill(E_MO_ZHI_HUN, [int(ctx.get("dst", -1))])
		engine._broadcast_game()
		return SUCCESS
	# (B) 普通出牌攻击：恢复原版询问流程
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.cover_count() == 0:
		return SUCCESS
	# 同一轮钩子内只询问一次（ctx 在钩子轮次内保持不变）
	if bool(ctx.get("jian_di_hun_done", false)) or _timeline_1_step >= STEP_DONE:
		return SUCCESS
	var form: int = _soul_form()
	if form == 0:
		return SUCCESS
	var skill_id: int = TIAN_SHI_ZHI_HUN if form == 1 else E_MO_ZHI_HUN
	if _timeline_1_step == 0:
		_timeline_1_step = skill_id
	if _timeline_1_step != skill_id:
		return SUCCESS
	if not engine.has_reply():
		# 目标与发动前的伤害一并下发：客户端据此在目标头像上现算「本次攻击伤害」
		询问(player.id, skill_id, 1, 0, GConst.CardSource.Cover, [], 0, "", [], true,
			0, -1, [int(ctx.get("dst", -1))], -1, {}, int(ctx.get("harm", {}).get("point", 0)))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_timeline_1_step = 0
	ctx["jian_di_hun_done"] = true
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cid: int = _cover_card_of(r.get("card_ids", []))
	if cid < 0:
		return SUCCESS
	notice_skill(skill_id, [int(ctx.get("dst", -1))])
	engine.to_discard([cid])
	engine.remove_cover(player.id, [cid], player.id, skill_id)
	if skill_id == TIAN_SHI_ZHI_HUN:
		used_tian_shi_zhi_hun = true
	else:
		used_e_mo_zhi_hun = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后：剑气斩 → 恶魔之魂（+1 伤害）→ 天使之魂（+2 治疗）
# ============================================================
## 【剑气斩 / 恶魔之魂 / 天使之魂】的推进阶段（0＝还没开始 / JIAN_QI_ZHAN＝在问剑气斩 /
## E_MO_ZHI_HUN＝结算恶魔之魂 / TIAN_SHI_ZHI_HUN＝结算天使之魂）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击命中（p_timeline_2_hit）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_2_hit_step: int = 0


func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _timeline_2_hit_step >= STEP_DONE:
		return SUCCESS
	var urgent: bool = false
	if _timeline_2_hit_step == 0:
		_timeline_2_hit_step = JIAN_QI_ZHAN
	if _timeline_2_hit_step == JIAN_QI_ZHAN:
		if int(player.tokens[0]["num"]) <= 0 or bool(ctx.get("jian_di_jqz_done", false)):
			_timeline_2_hit_step = E_MO_ZHI_HUN
		else:
			# 原版上限 min(3, 当前剑气)；通用客户端只回一维 args，原版「args=[1, 数量]」的第二维拿不到，
			# 故把数量直接作为选项值，服务端改读 args[0]
			var 上限: int = mini(3, int(player.tokens[0]["num"]))
			if not engine.has_reply():
				# 先弹居中窗选「移除几点【剑气】」（指示器配了「先弹选项 / 选项提示」），
				# 选完再点目标头像、头像上写「X 法术伤害」。
				# 目标只能是「本次攻击目标」以外的角色（对照原客户端 playerArea->disablePlayerItem(本次目标)）；
				# 弹窗带「取消」，点「取消」＝这次不发动
				var 选项: Array = []
				for n: int in range(1, 上限 + 1):
					选项.append({"value": n, "label": 提示(JIAN_QI_ZHAN, 1, n)})
				询问(player.id, JIAN_QI_ZHAN, 0, 1, GConst.CardSource.Hand, 选项, 0, "", [], true,
					0, -1, _可选目标(int(ctx.get("dst", -1))))
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			ctx["jian_di_jqz_done"] = true
			var args: Array = r.get("args", [])
			var dsts: Array = r.get("dst_ids", [])
			var count: int = int(args[0]) if not args.is_empty() else 0
			if count <= 0 or dsts.is_empty():
				if bool(r.get("is_timeout", false)) and count > 0:
					# 选好剑气数、选目标时超时：自动挑一名目标，按选好的数量释放
					var 自动: int = _超时自动目标(int(ctx.get("dst", -1)))
					if 自动 >= 0:
						dsts = [自动]
				else:
					# 弹窗还没选就超时（空回复），或玩家点了「取消」：这次不发动
					count = 0
			count = mini(maxi(count, 0), int(player.tokens[0]["num"]))
			if count > 0 and not dsts.is_empty():
				notice_skill(JIAN_QI_ZHAN, [int(dsts[0])])
				player.tokens[0]["num"] = int(player.tokens[0]["num"]) - count
				engine.push_harm({
					"src": player.id, "dst": int(dsts[0]), "point": count,
					"cause": JIAN_QI_ZHAN, "type": GConst.HarmType.Magic,
				})
				urgent = true
			_timeline_2_hit_step = E_MO_ZHI_HUN
	if _timeline_2_hit_step == E_MO_ZHI_HUN:
		if used_e_mo_zhi_hun and not bool(ctx.get("jian_di_emo_done", false)):
			ctx["jian_di_emo_done"] = true
			used_e_mo_zhi_hun = false
			notice_skill(E_MO_ZHI_HUN, [int(harm.get("dst", -1))])
			harm["point"] = int(harm.get("point", 0)) + 1
		_timeline_2_hit_step = TIAN_SHI_ZHI_HUN
	if _timeline_2_hit_step == TIAN_SHI_ZHI_HUN:
		if used_tian_shi_zhi_hun and not bool(ctx.get("jian_di_tianshi_done", false)):
			ctx["jian_di_tianshi_done"] = true
			used_tian_shi_zhi_hun = false
			notice_skill(TIAN_SHI_ZHI_HUN, [player.id])
			施加治疗(player.id, 2)
		_timeline_2_hit_step = 0
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
	engine.add_cover(player.id, [cid], player.id, JIAN_HUN_SHOU_HU)


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
	# 服务端 BuQuYiZhi 结束时复位标记：本次额外攻击结算完后，若仍有能量可再次获得
	added_bu_qu_yi_zhi = false
	return SUCCESS

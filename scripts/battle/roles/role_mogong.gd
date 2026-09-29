extends BattleRole
## 魔弓（roleID 26）—— 移植自服务端 role/MoGong.cpp
## 【响应】魔贯冲击（2601）：主动攻击前移除 1 个火系【充能】，本次伤害 +1；不能攻击手牌达到上限的对手；
##                  若命中可再移除 1 个火系【充能】使伤害再 +1；若未命中则对对方造成 3 点法术伤害③
## 【法术】雷光散射（2602）：移除雷系【充能】，对所有对手各 1 点法术伤害③；
##                  若额外移除 X 个雷系【充能】，指定一名对手额外受 X 点
## 【响应】多重射击（2603）：【攻击行动】结束时移除 1 个【充能】，视为额外 1 次暗系主动攻击，
##                  不能攻击上次的目标且伤害 -1
## 【启动】充能（2604）：耗 1 能量，弃到四张、摸 X 张牌，可将至多 X 张手牌作为【充能】
## 【启动】魔眼（2605）：耗 1 宝石，目标角色弃 1 张牌或自己摸 3 张牌，然后将 1 张手牌作为【充能】，+1 水晶
## 【充能】为专属盖牌，上限 8

const MO_GUAN_CHONG_JI: int = 2601
const MO_GUAN_CHONG_JI_HIT: int = 26011
const LEI_GUANG_SAN_SHE: int = 2602
const LEI_GUANG_SAN_SHE_EXTRA: int = 26021
const DUO_CHONG_SHE_JI: int = 2603
const CHONG_NENG: int = 2604
const CHONG_NENG_GAI_PAI: int = 26041
const MO_YAN: int = 2605
const MO_YAN_GAI_PAI: int = 26051
const CHONG_NENG_MO_YAN: int = 2606

## 【多重射击】使用的虚拟攻击牌（服务端 virtualCardID = 39，重击）
const VIRTUAL_DUO_CHONG_CARD: int = 39

## 本回合是否发动过【充能】/【魔眼】/【魔贯冲击】/【多重射击】
var _using_chong_neng: bool = false
var _using_mo_yan: bool = false
var _using_mo_guan: bool = false
var _using_duo_chong: bool = false
## 本回合是否还能发动【魔贯冲击】/【雷光散射】/【多重射击】
var _available_mo_guan: bool = true
var _available_lei_guang: bool = true
var _available_duo_chong: bool = true
## 【多重射击】已选中该额外行动、可在其额外行动阶段使用（p_additional_action 置位）
var _duo_chong_ready: bool = false
## 【充能】的摸牌数（决定【充能改牌】可放入盖牌区的手牌数）
var _chong_neng_num: int = 0
## 上次主动攻击的目标（【多重射击】不能攻击同一目标）
var _last_target: int = -1
## 【魔眼】待结算的「目标弃 1 张牌」
var _mo_yan_dst: int = -1


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【充能】为专属盖牌，上限 8（对应服务端 coverCardsMax = 8）
	p.cover_cards_max = 8


func available_skills() -> Array:
	var out: Array = []
	if _available_lei_guang:
		# 雷光散射：只从盖牌区选雷系牌（服务端 v_magic_skill 校验盖牌区存在雷系牌）
		var 雷系盖牌: Array[int] = _cover_ids_of_element(GConst.CardElement.Thunder)
		if not 雷系盖牌.is_empty():
			out.append({"type": GConst.ActionType.MagicSkill, "id": LEI_GUANG_SAN_SHE, "need_card": 1,
				"card_source": GConst.CardSource.Cover, "cards": 雷系盖牌, "card_max": 雷系盖牌.size()})
	if _duo_chong_ready and not player.cover_cards.is_empty():
		# 多重射击：所出的牌须属于盖牌区（服务端 v_attack_skill），目标限敌方
		out.append({"type": GConst.ActionType.AttackSkill, "id": DUO_CHONG_SHE_JI, "need_card": 1, "need_target": 1,
			"card_source": GConst.CardSource.Cover, "cards": player.cover_cards, "targets": enemy_ids()})
	return out


# ============================================================
# 回合开始：重置本回合限用标记（服务端在 p_before_turn_begin 无条件重置）
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_using_chong_neng = false
	_using_mo_yan = false
	_using_mo_guan = false
	_using_duo_chong = false
	_available_mo_guan = true
	_available_lei_guang = true
	_available_duo_chong = true
	_duo_chong_ready = false
	_chong_neng_num = 0
	_last_target = -1
	_mo_yan_dst = -1
	return SUCCESS


# ============================================================
# 主动法术技能：雷光散射
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != LEI_GUANG_SAN_SHE:
		return GConst.GE_INVALID_ACTION
	if not _available_lei_guang:
		return GConst.GE_INVALID_ACTION
	# 服务端要求盖牌区存在雷系牌
	if not _cover_has_element(GConst.CardElement.Thunder):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != LEI_GUANG_SAN_SHE:
		return GConst.GE_INVALID_ACTION
	return _lei_guang_san_she(action)


## 雷光散射：移除雷系【充能】，对所有对手各 1 点法术伤害；指定一名对手额外受（移除数）点
func _lei_guang_san_she(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dest_id: int = int(dsts[0]) if not dsts.is_empty() else -1
	var used: Array = []
	for c: Variant in action.get("card_ids", []):
		var cid: int = int(c)
		var card: GCard = Data.get_card(cid)
		if card != null and card.element_enum() == GConst.CardElement.Thunder and player.cover_cards.has(cid):
			if not used.has(cid):
				used.append(cid)
	# 全部敌方角色（从自己的下家开始）
	var enemies: Array[int] = []
	var nid: int = player.post_id
	for _i: int in range(engine.order.size() - 1):
		var ep: BattlePlayer = engine.p(nid)
		if ep != null and ep.color != player.color:
			enemies.append(nid)
		nid = engine.next_id(nid)
	notice_skill(LEI_GUANG_SAN_SHE, enemies)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": used, "is_real": true,
	})
	_remove_cover(used)
	var extra: int = used.size()
	for e: int in enemies:
		var point: int = extra if e == dest_id else 1
		engine.push_harm({
			"src": player.id, "dst": e, "point": point,
			"cause": LEI_GUANG_SAN_SHE, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击校验（服务端 v_attack）：基类通用校验 + 追加限制
# 追加限制：【多重射击】期间不得攻击上次主动攻击的目标（服务端 using_DUO_CHONG_SHE_JI / lastTarget）
# ============================================================
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	var rc: int = player.base_v_attack(card_id, dst_id, players)
	if rc != GConst.GE_SUCCESS:
		return rc
	if _using_duo_chong and dst_id == _last_target:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


# ============================================================
# 攻击技能：多重射击（服务端 v_attack_skill / p_attack_skill）
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != DUO_CHONG_SHE_JI:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 1:
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	if not player.cover_cards.has(cid):
		return GConst.GE_INVALID_CARDID
	if not _available_duo_chong:
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_PLAYERID
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	# 不能攻击上次的目标
	if dst_id == _last_target:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_attack_skill(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_PLAYERID
	var dst_id: int = int(dsts[0])
	notice_skill(DUO_CHONG_SHE_JI, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	_remove_cover([cid])
	_duo_chong_ready = false
	# 视为额外 1 次暗系主动攻击（伤害在 p_timeline_1 中 -1）
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": DUO_CHONG_SHE_JI, "type": GConst.HarmType.Attack,
		"card_id": VIRTUAL_DUO_CHONG_CARD, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, VIRTUAL_DUO_CHONG_CARD, harm))
	engine._broadcast_game()
	return URGENT


# ============================================================
# 攻击宣告后：魔贯冲击 / 多重射击的伤害修正
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	var src: int = int(ctx.get("src", -1))
	if src != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	_last_target = int(ctx.get("dst", -1))
	if _using_duo_chong:
		# 多重射击：暗系攻击，对方无法应战且伤害 -1
		ctx["hit_rate"] = GConst.HitRate.NoReattack
		var h0: Dictionary = ctx.get("harm", {})
		h0["point"] = int(h0.get("point", 0)) - 1
		_using_duo_chong = false
		return SUCCESS
	if step == 0:
		step = MO_GUAN_CHONG_JI
	if step == MO_GUAN_CHONG_JI:
		var r: int = _mo_guan_chong_ji(ctx)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 魔贯冲击：移除 1 个火系【充能】，本次伤害 +1
func _mo_guan_chong_ji(ctx: Dictionary) -> int:
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or not _available_mo_guan:
		return SUCCESS
	# 不能攻击手牌达到上限的对手
	if dst.hand_cards.size() == dst.hand_cards_max:
		return SUCCESS
	if not _cover_has_element(GConst.CardElement.Fire):
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, MO_GUAN_CHONG_JI, 1, 0, GConst.CardSource.Cover)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cid: int = _cover_card_of_element(r.get("card_ids", []), GConst.CardElement.Fire)
	if cid < 0:
		return SUCCESS
	notice_skill(MO_GUAN_CHONG_JI, [dst.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	_remove_cover([cid])
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + 1
	_using_mo_guan = true
	_available_duo_chong = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 命中 / 未命中的追加效果
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not _using_mo_guan:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = MO_GUAN_CHONG_JI_HIT
	if step == MO_GUAN_CHONG_JI_HIT:
		if not engine.has_reply():
			engine.ask_skill(player.id, MO_GUAN_CHONG_JI_HIT, 1, 0, GConst.CardSource.Cover)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		_using_mo_guan = false
		step = STEP_DONE
		if args.is_empty() or int(args[0]) != 1:
			return SUCCESS
		var cid: int = _cover_card_of_element(r.get("card_ids", []), GConst.CardElement.Fire)
		if cid < 0:
			return SUCCESS
		notice_skill(MO_GUAN_CHONG_JI_HIT, [int(ctx.get("dst", -1))])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		_remove_cover([cid])
		var harm: Dictionary = ctx.get("harm", {})
		harm["point"] = int(harm.get("point", 0)) + 1
		engine._broadcast_game()
		return SUCCESS
	return SUCCESS


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not _using_mo_guan:
		return SUCCESS
	_using_mo_guan = false
	step = STEP_DONE
	engine.push_harm({
		"src": player.id, "dst": int(ctx.get("dst", -1)), "point": 3,
		"cause": MO_GUAN_CHONG_JI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 攻击行动结束后：授予【多重射击】的额外攻击行动
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	if not _available_duo_chong or player.cover_cards.is_empty():
		return SUCCESS
	player.add_action(GConst.ActionType.Attack, DUO_CHONG_SHE_JI)
	return SUCCESS


# ============================================================
# 玩家选择额外行动时的二次校验（服务端 MoGong::v_additional_action）：
# 多重射击需仍可用且盖牌区（【充能】）非空
# ============================================================
func v_additional_action(cause: int) -> int:
	if cause != DUO_CHONG_SHE_JI:
		return V_NOT_OVERRIDE
	if not _available_duo_chong or player.cover_cards.is_empty():
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


# ============================================================
# 玩家选择额外行动时：多重射击（开启本次额外攻击的暗系修正并禁用魔贯冲击）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or int(ctx.get("cause", 0)) != DUO_CHONG_SHE_JI:
		return SUCCESS
	_using_duo_chong = true
	_available_mo_guan = false
	_duo_chong_ready = true
	return SUCCESS


# ============================================================
# 回合开始（boot）：充能 / 魔眼
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if player.get_energy() > 0 and step == 0:
		step = CHONG_NENG_MO_YAN
	if step == CHONG_NENG_MO_YAN:
		if not engine.has_reply():
			engine.ask_skill(player.id, CHONG_NENG_MO_YAN, 0, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		if choice == 1:
			_using_chong_neng = true
		elif choice == 2:
			_using_mo_yan = true
		if _using_chong_neng:
			step = CHONG_NENG
		elif _using_mo_yan:
			step = MO_YAN
		else:
			step = STEP_DONE
			return SUCCESS
	if step == CHONG_NENG:
		var r2: int = _chong_neng()
		if r2 == WAIT:
			return WAIT
		step = CHONG_NENG_GAI_PAI
	if step == MO_YAN:
		var r3: int = _mo_yan()
		if r3 == WAIT:
			return WAIT
		if _mo_yan_dst >= 0:
			return SUCCESS
		step = MO_YAN_GAI_PAI
	if step == CHONG_NENG_GAI_PAI:
		var r4: int = _gai_pai(CHONG_NENG_GAI_PAI, _chong_neng_num)
		if r4 == WAIT:
			return WAIT
		step = STEP_DONE
		return SUCCESS
	if step == MO_YAN_GAI_PAI:
		var r5: int = _gai_pai(MO_YAN_GAI_PAI, 1)
		if r5 == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 充能：耗 1 能量（优先水晶），弃 args(1) 张手牌、摸 args(2) 张牌
func _chong_neng() -> int:
	if not engine.has_reply():
		engine.ask_skill(player.id, CHONG_NENG, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(CHONG_NENG, [player.id])
	_available_mo_guan = false
	_available_lei_guang = false
	_using_chong_neng = true
	var discard_n: int = int(args[1]) if args.size() > 1 else 0
	var draw_n: int = int(args[2]) if args.size() > 2 else 0
	_chong_neng_num = draw_n
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	if draw_n > 0:
		engine.draw(player.id, draw_n)
	_discard_hand_cards(r.get("card_ids", []), discard_n)
	engine._broadcast_game()
	return SUCCESS


## 魔眼：耗 1 宝石、+1 水晶；args(1)=0 时自己摸 3 张牌，否则指定目标弃 1 张牌
func _mo_yan() -> int:
	if _mo_yan_dst >= 0:
		# 目标弃 1 张牌的续阶段
		var r0: int = _force_discard_one(_mo_yan_dst)
		if r0 == WAIT:
			return WAIT
		_mo_yan_dst = -1
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, MO_YAN, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(MO_YAN, [player.id])
	player.set_gem(player.gem - 1)
	player.set_crystal(player.crystal + 1)
	_using_mo_yan = true
	var choice: int = int(args[1]) if args.size() > 1 else 0
	var dsts: Array = r.get("dst_ids", [])
	if choice != 0 and not dsts.is_empty():
		_mo_yan_dst = int(dsts[0])
		engine._broadcast_game()
		return _force_discard_one(_mo_yan_dst)
	# 未选择目标角色：自己摸 3 张牌
	engine.draw(player.id, 3)
	_chong_neng_num = 1
	engine._broadcast_game()
	return SUCCESS


## 充能改牌 / 魔眼改牌：把至多 max_n 张手牌作为【充能】
func _gai_pai(skill_id: int, max_n: int) -> int:
	if not engine.has_reply():
		engine.ask_skill(player.id, skill_id, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = []
	for c: Variant in r.get("card_ids", []):
		if cards.size() >= max_n:
			break
		if player.has_hand_card(int(c)) and not cards.has(int(c)):
			cards.append(int(c))
	if cards.is_empty():
		return SUCCESS
	notice_skill(skill_id, [player.id])
	engine.take_from_hand(player.id, cards)
	_add_cover(cards)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 盖牌区某系别的全部牌 id（雷光散射的 cards 用它限制只能选雷系盖牌）
func _cover_ids_of_element(elem: int) -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.cover_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == elem:
			out.append(cid)
	return out


## 盖牌区是否有某系别的【充能】
func _cover_has_element(elem: int) -> bool:
	return not _cover_ids_of_element(elem).is_empty()


## 取回复中第一张指定系别的盖牌
func _cover_card_of_element(cards: Array, elem: int) -> int:
	for c: Variant in cards:
		var cid: int = int(c)
		if not player.cover_cards.has(cid):
			continue
		var card: GCard = Data.get_card(cid)
		if card != null and card.element_enum() == elem:
			return cid
	return -1


## 把牌作为【充能】加入盖牌区；达到上限时替换最早的盖牌
func _add_cover(cards: Array) -> void:
	if cards.is_empty():
		return
	player.add_cover_cards(cards)
	if player.cover_cards_max <= 0:
		return
	var replaced: Array = []
	while player.cover_cards.size() > player.cover_cards_max:
		replaced.append(player.cover_cards[0])
		player.cover_cards.remove_at(0)
	if not replaced.is_empty():
		engine.to_discard(replaced)


## 从盖牌区移除【充能】并弃置
func _remove_cover(cards: Array) -> void:
	if cards.is_empty():
		return
	player.remove_cover_cards(cards)
	engine.to_discard(cards)


## 弃掉至多 n 张手牌（客户端未给出合法牌时从手牌补齐）
func _discard_hand_cards(cards: Array, n: int) -> void:
	if n <= 0:
		return
	var chosen: Array = []
	for c: Variant in cards:
		if chosen.size() >= n:
			break
		if player.has_hand_card(int(c)) and not chosen.has(int(c)):
			chosen.append(int(c))
	while chosen.size() < n and chosen.size() < player.hand_cards.size():
		for cid: int in player.hand_cards:
			if chosen.size() >= n:
				break
			if not chosen.has(cid):
				chosen.append(cid)
	if chosen.is_empty():
		return
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen)


## 强制某玩家弃 1 张手牌（对应服务端 StateRequestHand → DECK_DISCARD）
func _force_discard_one(pid: int) -> int:
	var tp: BattlePlayer = engine.p(pid)
	if tp == null or tp.hand_cards.is_empty():
		return SUCCESS
	if not engine.has_reply():
		engine.ask_respond(pid, GConst.RespondType.Discard, [pid, GConst.CAUSE_USE, 1], [pid])
		engine.wait_for(pid, GConst.Msg.Respond)
		return WAIT
	var r: Dictionary = engine.take_reply()
	var chosen: Array = []
	for c: Variant in r.get("card_ids", []):
		if chosen.size() < 1 and tp.has_hand_card(int(c)):
			chosen.append(int(c))
	if chosen.is_empty():
		chosen.append(tp.hand_cards[0])
	engine.take_from_hand(pid, chosen)
	engine.to_discard(chosen)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
		"card_ids": chosen, "is_real": true,
	})
	engine._broadcast_game()
	return SUCCESS

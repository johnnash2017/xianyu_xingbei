extends BattleRole
## 魔导师（roleID 8）—— 移植自服务端 role/MoDao.cpp
## 技能：
##   魔爆冲击（801）——【法术】弃 1 张法术牌【展示】，指定 2 名对手各弃 1 张法术牌【展示】；
##        若其中有人不如此做，则对其造成 2 点法术伤害③；只要有对手未弃牌，我方【战绩区】+1【宝石】
##   魔弹融合（803）——【响应】你的地系或火系牌可以当【魔弹】使用（p_magic_skill：打出后成为魔弹，
##        沿最近对手的方向传递；被指向者可打出【魔弹】/地系/火系牌继续传递（每传递一次伤害 +1）、
##        用【圣光】抵挡（效果终止），或不如此做而承受伤害（其拥有【圣盾】/【天使之墙】时改为移除之并视作未命中））
##   毁灭风暴（804）——【法术·宝石】对 2 名对手各造成 2 点法术伤害③
##
## 牌类校验覆写：服务端 MoDao.cpp 覆写 v_missile / v_remissile（手中【魔弹】或地系/火系牌
## 可当【魔弹】使用与响应），已按服务端移植于本文件。
## 引擎限制说明：服务端 MoDao.cpp 并未实现【魔弹掌握】(802)，故本文件不实现该技能（不凭空编造）。
## 变通说明：服务端用 StateRequestHand / StateMissiled 状态处理「请求手牌」「魔弹传递」，
## 本引擎无对应状态，改用 ask_skill 逐一询问相关玩家（回复 args[0]==1 表示照做，card_ids 给出所弃/所打出的牌）。

const MO_BAO_CHONG_JI: int = 801
const MO_DAN_RONG_HE: int = 803
const HUI_MIE_FENG_BAO: int = 804

const TAG_TIAN_SHI_ZHI_QIANG: String = "天使之墙"

const MO_BAO_HARM_POINT: int = 2        # 魔爆冲击：不弃法术牌的对手受到的法术伤害
const MISSILE_BASE_POINT: int = 2       # 魔弹初始伤害
const HUI_MIE_HARM_POINT: int = 2       # 毁灭风暴：每名对手受到的法术伤害

## 魔爆冲击的多目标询问进度
var _mo_bao_targets: Array[int] = []
var _mo_bao_damage: Array[int] = []
var _mo_bao_gem: bool = false

## 魔弹传递的临时状态
var _missile_holder: int = -1
var _missile_src: int = -1
var _missile_point: int = 0
var _missile_post_dir: bool = true
var _missile_used: Array[int] = []


# ============================================================
# 行动阶段可选技能
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	var enemies: int = _enemy_count()
	if _hand_has_magic() and enemies >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": MO_BAO_CHONG_JI, "need_card": 1, "need_target": 1})
	if _hand_has_fire_or_earth() and enemies >= 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": MO_DAN_RONG_HE, "need_card": 1, "need_target": 1})
	if player.gem > 0 and enemies >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": HUI_MIE_FENG_BAO, "need_card": 0, "need_target": 1})
	return out


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	match aid:
		MO_BAO_CHONG_JI:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or not card.is_magic():
				return GConst.GE_INVALID_CARDID
			return _check_two_target(action)
		MO_DAN_RONG_HE:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid2: int = int(cards[0])
			var card2: GCard = Data.get_card(cid2)
			if not player.has_hand_card(cid2) or card2 == null:
				return GConst.GE_INVALID_CARDID
			if card2.element_enum() != GConst.CardElement.Fire and card2.element_enum() != GConst.CardElement.Earth:
				return GConst.GE_INVALID_CARDID
			return GConst.GE_SUCCESS
		HUI_MIE_FENG_BAO:
			if player.gem <= 0:
				return GConst.GE_INVALID_ACTION
			return _check_two_target(action)
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		MO_BAO_CHONG_JI:
			return _mo_bao_chong_ji(action)
		MO_DAN_RONG_HE:
			return _mo_dan_rong_he(action)
		HUI_MIE_FENG_BAO:
			return _hui_mie_feng_bao(action)
	return GConst.GE_INVALID_ACTION


## 魔爆冲击：弃 1 张法术牌，2 名对手各弃 1 张法术牌，未弃者受 2 点法术伤害；有人未弃则我方 +1 宝石
func _mo_bao_chong_ji(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if step == 0:
		_mo_bao_targets.clear()
		for d: Variant in dsts:
			_mo_bao_targets.append(int(d))
		_mo_bao_damage.clear()
		_mo_bao_gem = false
		var cid: int = int(cards[0])
		notice_skill(MO_BAO_CHONG_JI, _mo_bao_targets)
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [cid])
		engine.to_discard([cid])
		step = 1
	while step >= 1 and step <= _mo_bao_targets.size():
		var tid: int = _mo_bao_targets[step - 1]
		if not engine.has_reply():
			engine.ask_skill(tid, MO_BAO_CHONG_JI, 1, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		if not _target_discard_magic(tid, r):
			_mo_bao_damage.append(tid)
			_mo_bao_gem = true
		step += 1
	step = STEP_DONE
	if _mo_bao_gem:
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	for tid2: int in _mo_bao_damage:
		engine.push_harm({
			"src": player.id, "dst": tid2, "point": MO_BAO_HARM_POINT,
			"cause": MO_BAO_CHONG_JI, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	if _mo_bao_damage.is_empty():
		return SUCCESS
	return URGENT


## 魔弹融合：把一张地系/火系牌当成【魔弹】打出并沿方向传递
func _mo_dan_rong_he(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if step == 0:
		var cid: int = int(cards[0])
		var dst_id: int = int(dsts[0])
		notice_skill(MO_DAN_RONG_HE, [dst_id])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": dst_id,
			"card_ids": [cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [cid])
		engine.to_discard([cid])
		# 传递方向：若指定目标就是 post 方向最近的对手则沿 post 传递，否则沿 pre（对照 StateMissiled::create）
		_missile_post_dir = dst_id == _nearest_enemy(player.id, true)
		_missile_holder = dst_id
		_missile_src = player.id
		_missile_point = MISSILE_BASE_POINT
		_missile_used.clear()
		_missile_used.append(player.id)
		_missile_used.append(dst_id)
		step = 1
	if step != 1:
		return SUCCESS
	while true:
		var holder: BattlePlayer = engine.p(_missile_holder)
		if holder == null:
			step = STEP_DONE
			return SUCCESS
		if not engine.has_reply():
			engine.ask_skill(holder.id, MO_DAN_RONG_HE, 1, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var given: Array = r.get("card_ids", [])
		var use_card: int = -1
		if not args.is_empty() and int(args[0]) == 1 and not given.is_empty():
			var gid: int = int(given[0])
			if holder.has_hand_card(gid):
				use_card = gid
		if use_card < 0:
			return _missile_give_up(holder)
		var ucard: GCard = Data.get_card(use_card)
		if ucard == null:
			return _missile_give_up(holder)
		if ucard.card_name_enum() == GConst.CardName.HolyLight:
			# 圣光抵挡：魔弹效果终止，不造成伤害
			step = STEP_DONE
			_use_missile_card(holder.id, use_card)
			return SUCCESS
		if not _can_remissile(ucard):
			# 打出的牌既不是圣光也不能继续传递：视为放弃（服务端校验失败等价于此）
			return _missile_give_up(holder)
		_use_missile_card(holder.id, use_card)
		_missile_point += 1
		_missile_src = holder.id
		var nxt: int = _next_missile_target(holder.id, _missile_post_dir, _missile_used)
		if nxt < 0:
			# 无人可继续传递：由当前持有者承受伤害
			_missile_holder = holder.id
			return _missile_give_up(holder)
		_missile_used.append(nxt)
		_missile_holder = nxt
	return SUCCESS


## 放弃传递：有【圣盾】/【天使之墙】则移除之（视作未命中），否则承受当前魔弹伤害
func _missile_give_up(holder: BattlePlayer) -> int:
	step = STEP_DONE
	if _missile_block_by_basic(holder.id):
		engine._broadcast_game()
		return SUCCESS
	engine.push_harm({
		"src": _missile_src, "dst": holder.id, "point": _missile_point,
		"cause": GConst.CAUSE_MISSILE, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 毁灭风暴：消耗 1 宝石，对 2 名对手各造成 2 点法术伤害
func _hui_mie_feng_bao(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	notice_skill(HUI_MIE_FENG_BAO, dsts)
	player.set_gem(player.gem - 1)
	for d: Variant in dsts:
		engine.push_harm({
			"src": player.id, "dst": int(d), "point": HUI_MIE_HARM_POINT,
			"cause": HUI_MIE_FENG_BAO, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 牌类校验覆写：魔弹融合（803）——你的地系或火系牌可以当【魔弹】使用
# 对照服务端 MoDao::v_missile / v_remissile：手中牌为【魔弹】或地系/火系则通过，
# 否则恒返回 GE_INVALID_CARDID（服务端把「不在手牌」与「牌型不符」合并为同一错误码）。
# ============================================================
func v_missile(card_id: int, _dst_id: int) -> int:
	if not _can_use_missile(card_id):
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


func v_remissile(card_id: int) -> int:
	if not _can_use_missile(card_id):
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


# ============================================================
# 工具
# ============================================================
## 校验「恰好 2 名互不相同的对手」（服务端 checkTwoTarget）
func _check_two_target(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != 2:
		return GConst.GE_INVALID_PLAYERID
	var d1: int = int(dsts[0])
	var d2: int = int(dsts[1])
	var p1: BattlePlayer = engine.p(d1)
	var p2: BattlePlayer = engine.p(d2)
	if p1 == null or p2 == null or d1 == d2:
		return GConst.GE_INVALID_PLAYERID
	if p1.color == player.color or p2.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 让目标弃 1 张法术牌【展示】；成功返回 true
func _target_discard_magic(tid: int, r: Dictionary) -> bool:
	var args: Array = r.get("args", [])
	var given: Array = r.get("card_ids", [])
	if args.is_empty() or int(args[0]) != 1 or given.is_empty():
		return false
	var gid: int = int(given[0])
	var target: BattlePlayer = engine.p(tid)
	var card: GCard = Data.get_card(gid)
	if target == null or card == null or not card.is_magic() or not target.has_hand_card(gid):
		return false
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": tid, "dst_id": tid,
		"card_ids": [gid], "is_real": true,
	})
	engine.take_from_hand(tid, [gid])
	engine.to_discard([gid])
	engine._broadcast_game()
	return true


## 打出一张牌（魔弹传递/圣光抵挡用）
func _use_missile_card(pid: int, cid: int) -> void:
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": pid, "dst_id": pid,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(pid, [cid])
	engine.to_discard([cid])
	engine._broadcast_game()


## 手中牌能否当作【魔弹】使用／响应（服务端 v_missile / v_remissile 的判定）
func _can_use_missile(card_id: int) -> bool:
	if not player.has_hand_card(card_id):
		return false
	var card: GCard = Data.get_card(card_id)
	if card == null:
		return false
	return _can_remissile(card)


## 该牌能否继续传递魔弹（【魔弹】或地系/火系牌，对照 v_remissile）
func _can_remissile(card: GCard) -> bool:
	if card.card_name_enum() == GConst.CardName.Missile:
		return true
	var e: int = card.element_enum()
	return e == GConst.CardElement.Fire or e == GConst.CardElement.Earth


## 目标若拥有【圣盾】或【天使之墙】，移除之并返回 true（魔弹视作未命中）
func _missile_block_by_basic(target_id: int) -> bool:
	var target: BattlePlayer = engine.p(target_id)
	if target == null:
		return false
	var cid: int = -1
	if target.check_basic_effect_name(GConst.CardName.Shield):
		cid = engine._find_basic_card(target, GConst.CardName.Shield)
	else:
		for e: Dictionary in target.basic_effects:
			var c: GCard = Data.get_card(int(e["card"]))
			if c != null and c.has_speciality_name(TAG_TIAN_SHI_ZHI_QIANG):
				cid = int(e["card"])
				break
	if cid < 0:
		return false
	engine.remove_basic_effect(target_id, cid, GConst.CAUSE_MISSILE)
	engine.to_discard([cid])
	return true


## 指定方向上最近的一名对手
func _nearest_enemy(from_id: int, post_dir: bool) -> int:
	var cur: BattlePlayer = engine.p(from_id)
	if cur == null:
		return -1
	var nid: int = cur.post_id if post_dir else cur.pre_id
	for _i: int in range(engine.order.size()):
		var pp: BattlePlayer = engine.p(nid)
		if pp == null:
			return -1
		if pp.color != cur.color:
			return nid
		nid = pp.post_id if post_dir else pp.pre_id
	return -1


## 指定方向上最近的、且尚未参与过本轮传递的对手
func _next_missile_target(from_id: int, post_dir: bool, used: Array) -> int:
	var cur: BattlePlayer = engine.p(from_id)
	if cur == null:
		return -1
	var nid: int = cur.post_id if post_dir else cur.pre_id
	for _i: int in range(engine.order.size()):
		var pp: BattlePlayer = engine.p(nid)
		if pp == null:
			return -1
		if pp.color != cur.color and not used.has(nid):
			return nid
		nid = pp.post_id if post_dir else pp.pre_id
	return -1


func _enemy_count() -> int:
	var n: int = 0
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color:
			n += 1
	return n


func _hand_has_magic() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			return true
	return false


func _hand_has_fire_or_earth() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		var e: int = c.element_enum()
		if e == GConst.CardElement.Fire or e == GConst.CardElement.Earth:
			return true
	return false

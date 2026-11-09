extends BattleRole
## 猎巫人（roleID 42）—— 异端业火版本
## 技能：
##   转换（4201，响应/被动）：除【圣光】外，法术牌可作为对应系别攻击牌使用
##   狩魔刺（4202，响应）：主动攻击手牌<4的目标时，目标弃 1 张牌【展示】，面朝下成为【魔力瓶】
##   法术剥离（4203，响应）：主动攻击命中时，目标弃 1 张牌，面朝下成为【魔力瓶】
##   灌银毒刃（4204，响应）：目标承受你造成的伤害时，移除 1 个【魔力瓶】抵挡 1 点伤害，
##                              将该瓶强制加入目标手牌，你 +1 治疗
##   偷袭（4205，必杀技/响应，回合限定）：攻击行动结束时，支付 1 水晶并移除 2 个【魔力瓶】，
##                              按手牌法术牌数对 X 名对手各造成 1 点法术伤害；
##                              有 2 张攻击牌时额外 +1 攻击行动；2 张攻击牌同系时对原目标追加 1 点法术伤害
##
##【魔力瓶】使用 player.cover_cards 存实际弃牌，上限由角色表槽 2 配置为 4。
## 达到上限后不能再发动【狩魔刺】/【法术剥离】。

const ZHUAN_HUAN: int = 4201
const SHOU_MO_CI: int = 4202
const FA_SHU_BO_LI: int = 4203
const GUAN_YIN_DU_REN: int = 4204
const TOU_XI: int = 4205

var _shou_step: int = 0
var _shou_target: int = -1
var _boshi_step: int = 0
var _boshi_target: int = -1
var _guanyin_step: int = 0
var _touxi_step: int = 0
var _touxi_target: int = -1
var _touxi_x: int = 0
var _touxi_same: bool = false
var _touxi_two_attack: bool = false
var _touxi_same_step: int = 0
var _used_touxi: bool = false
## 【转换】作为攻击技能时，p_after_attack 的 ctx 只有 player/action_id，没有 dst；
## 把这次攻击的目标记下来，供后面的【偷袭】使用。
var _last_attack_dst: int = -1


func p_before_turn_begin(_ctx: Dictionary) -> int:
	_shou_step = 0
	_boshi_step = 0
	_guanyin_step = 0
	_touxi_step = 0
	_touxi_same_step = 0
	_used_touxi = false
	_last_attack_dst = -1
	return SUCCESS


# ============================================================
# 转换：法术牌（圣光除外）可当同系攻击牌
# ============================================================
func _is_conversion_card(card: GCard) -> bool:
	return card != null and card.is_magic() and card.card_name_enum() != GConst.CardName.HolyLight


## 该系别用来承接「转换」的虚拟攻击牌；找不到（如光系）就不能转换
func _virtual_attack(element: int) -> int:
	for c: GCard in Data.card_db:
		if not c.is_virtual and c.is_attack() and c.element_enum() == element:
			return c.id
	return -1


## 【转换】是技能栏里可选发的响应：只把手牌里除【圣光】外的法术牌列为本技能的可选牌，
## 不会改变这些牌原本作为法术使用的入口。
func available_skills() -> Array:
	var 可转: Array[int] = []
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if _is_conversion_card(card) and _virtual_attack(card.element_enum()) >= 0:
			可转.append(cid)
	return [{
		"type": GConst.ActionType.AttackSkill,
		"id": ZHUAN_HUAN,
		"need_card": 1,
		"need_target": 1,
		"cards": 可转,
		"targets": enemy_ids(),
		"enabled": not 可转.is_empty(),
	}]


func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != ZHUAN_HUAN:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 1:
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not _is_conversion_card(card):
		return GConst.GE_INVALID_CARDID
	if not player.has_hand_card(cid):
		return GConst.GE_HANDCARD_NOT_FOUND
	if _virtual_attack(card.element_enum()) < 0:
		return GConst.GE_INVALID_CARDID
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null or dst.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	if player.check_exclusive_effect(GConst.Exclusive.TiaoXin) \
			and dst.id != player.exclusive_owner(GConst.Exclusive.TiaoXin):
		return GConst.GE_INVALID_PLAYERID
	if dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_attack_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != ZHUAN_HUAN:
		return GConst.GE_INVALID_ACTION
	var cid: int = int((action.get("card_ids", []) as Array)[0])
	var dst_id: int = int((action.get("dst_ids", []) as Array)[0])
	_last_attack_dst = dst_id
	var card: GCard = Data.get_card(cid)
	var 攻击牌: int = _virtual_attack(card.element_enum()) if card != null else -1
	if 攻击牌 < 0:
		return GConst.GE_INVALID_CARDID
	notice_skill(ZHUAN_HUAN, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true, "as_card_id": 攻击牌,
	})
	# 结算用的 card_id 仍是原法术牌：转换只改变「按攻击结算」，不改变原牌的系别 / 命格。
	# 客户端表现用 as_card_id 播对应系的斩击特效。
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": 2, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": cid, "is_active": true,
		# 这次攻击背后就是玩家真实打出的那张牌：记录实体实例，供「真实 / 虚拟攻击」判定
		"card_id_instance": cid,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, cid, harm))
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid], {"owner": player.id, "source": "hand"})
	return URGENT


# ============================================================
# 魔力瓶工具
# ============================================================
func _bottle_count() -> int:
	return player.cover_cards.size()


func _can_bottle() -> bool:
	return player.cover_cards_max > 0 and _bottle_count() < player.cover_cards_max


## 让目标选 1 张手牌弃掉【展示】，再面朝下放进猎巫人的盖牌区。
## 返回 true＝实际拿到了一张牌。
func _take_target_card_to_bottle(target_id: int, cid: int, cause: int) -> bool:
	var target: BattlePlayer = engine.p(target_id)
	if target == null or not target.has_hand_card(cid) or not _can_bottle():
		return false
	if not engine.take_from_hand(target_id, [cid], true):
		return false
	engine.add_cover(player.id, [cid], player.id, cause)
	notice_skill(cause, [target_id])
	engine._broadcast_game()
	return true


## 解析目标「弃 1 张牌」的回复：回复里没有合法牌（超时 / 取消 / 改包 / 牌已离手）时
## 按手牌顺序补一张。这两颗技能的弃牌是强制的（原文没有「可」也没有「否则」），
## 不能因为目标超时跳过，否则白少一张牌、瓶子也拿不到。
func _回复里的一张牌(target: BattlePlayer, r: Dictionary) -> int:
	if target == null:
		return -1
	for v: Variant in r.get("card_ids", []):
		var cid: int = int(v)
		if target.has_discard_card(cid):
			return cid
	for cid2: int in target.hand_cards:
		if target.has_discard_card(cid2):
			return cid2
	return -1


func _take_first_bottle() -> int:
	if player.cover_cards.is_empty():
		return -1
	return int(player.cover_cards[0])


# ============================================================
# 狩魔刺：主动攻击手牌 < 4 的目标时，目标弃 1 张牌成瓶
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _shou_step < 0:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.hand_cards.size() >= 4 or dst.hand_cards.is_empty() or not _can_bottle():
		_shou_step = 0
		return SUCCESS
	if _shou_step == 0:
		_shou_target = dst.id
		_shou_step = 1
		if not engine.has_reply():
			# 先问发动者是否发动；确认＝发动，右下角「取消」＝不发动。
			询问(player.id, SHOU_MO_CI, 0, 0)
			return WAIT
	if _shou_step == 1:
		if not engine.has_reply():
			return WAIT
		if not take_skill_reply():
			_shou_step = 0
			_shou_target = -1
			return SUCCESS
		var target: BattlePlayer = engine.p(_shou_target)
		if target == null or target.hand_cards.is_empty() or not _can_bottle():
			_shou_step = 0
			_shou_target = -1
			return SUCCESS
		_shou_step = 2
		if not engine.has_reply():
			# 发动者同意后，才轮到目标选择弃哪张牌。
			询问(_shou_target, SHOU_MO_CI, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false)
			return WAIT
	if _shou_step == 2:
		if not engine.has_reply():
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		_shou_step = 0
		var 目标: BattlePlayer = engine.p(_shou_target)
		var cid: int = _回复里的一张牌(目标, r2)
		if cid >= 0:
			_take_target_card_to_bottle(_shou_target, cid, SHOU_MO_CI)
		_shou_target = -1
	return SUCCESS


# ============================================================
# 法术剥离：主动攻击命中时，目标弃 1 张牌成瓶
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", true)):
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.hand_cards.is_empty() or not _can_bottle():
		_boshi_step = 0
		return SUCCESS
	if _boshi_step == 0:
		_boshi_target = dst.id
		_boshi_step = 1
		if not engine.has_reply():
			# 常规响应：确认＝发动，右下角「取消」＝不发动，不再额外摆「不发动」选项。
			询问(player.id, FA_SHU_BO_LI, 0, 0)
			return WAIT
	if _boshi_step == 1:
		if not engine.has_reply():
			return WAIT
		# 常规响应：确认＝发动，右下角「取消」＝不发动，不再额外摆「不发动」选项。
		if not take_skill_reply():
			_boshi_step = 0
			_boshi_target = -1
			return SUCCESS
		_boshi_step = 2
		if not engine.has_reply():
			询问(_boshi_target, FA_SHU_BO_LI, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false)
			return WAIT
	if _boshi_step == 2:
		if not engine.has_reply():
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		var 目标: BattlePlayer = engine.p(_boshi_target)
		var cid: int = _回复里的一张牌(目标, r2)
		if cid >= 0:
			_take_target_card_to_bottle(_boshi_target, cid, FA_SHU_BO_LI)
		_boshi_step = 0
		_boshi_target = -1
	return SUCCESS


# ============================================================
# 灌银毒刃：目标承受你造成的伤害时，移除 1 瓶，伤害 -1，瓶入其手牌，+1 治疗
# ============================================================
func p_timeline_6(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("point", 0)) <= 0 or player.cover_cards.is_empty():
		_guanyin_step = 0
		return SUCCESS
	if _guanyin_step == 0:
		_guanyin_step = 1
		var dst_id: int = int(harm.get("dst", -1))
		if not engine.has_reply():
			# 确认发动的同一步直接选盖牌：选中【魔力瓶】再点「确定」即发动；
			# 右下角「取消」＝不发动，不再单独问一次「是否发动」。
			# 把受伤目标作为展示目标下发，让头像提示能画出「原伤害 → 减 1 后伤害」；
			# 同时带上伤害类型，攻击伤害/法术伤害分别用不同颜色与措辞。
			询问(player.id, GUAN_YIN_DU_REN, 1, 0, GConst.CardSource.Cover, [], 0, "", [], true,
				0, -1, [dst_id] if dst_id >= 0 else [], -1, {},
				int(harm.get("point", 0)), int(harm.get("type", GConst.HarmType.Attack)), false,
				[dst_id] if dst_id >= 0 else [])
			return WAIT
	if _guanyin_step == 1:
		if not engine.has_reply():
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var chosen: Array = r.get("card_ids", [])
		_guanyin_step = 0
		if chosen.is_empty():
			return SUCCESS
		var bottle: int = int(chosen[0])
		if bottle < 0 or not player.有盖牌(bottle):
			return SUCCESS
		# 移动要带实例号：先认出盖牌区里实际那一份，删除与交给受伤者用同一个号
		var 实例: int = player.盖牌实例(bottle)
		if 实例 < 0:
			return SUCCESS
		engine.remove_cover(player.id, [实例], player.id, GUAN_YIN_DU_REN)
		harm["point"] = maxi(int(harm.get("point", 0)) - 1, 0)
		var dst: BattlePlayer = engine.p(int(harm.get("dst", -1)))
		if dst != null:
			dst.add_hand_cards([实例])
		施加治疗(player.id, 1)
		notice_skill(GUAN_YIN_DU_REN, [int(harm.get("dst", player.id))])
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 偷袭：攻击行动结束，移除并展示 2 个【魔力瓶】，按这 2 张牌本身的类别结算：
#   · 每有 1 张法术牌 → 对 1 名目标对手造成 1 点法术伤害
#   · 若这 2 张都是攻击牌 → 额外 +1 攻击行动
#   · 若这 2 张同系 → 对原攻击目标追加 1 点法术伤害
# ============================================================
func p_after_attack(_ctx: Dictionary) -> int:
	return SUCCESS


func action_end_options(ctx: Dictionary) -> Array:
	# 偷袭写的是「攻击行动结束时」：法术行动结束不能摆出来
	if not 是攻击行动结束(ctx):
		return []
	if _touxi_step != 0 or _used_touxi:
		return []
	var 可用: bool = player.get_energy() > 0 and player.cover_cards.size() >= 2
	return [{"value": TOU_XI, "label": GConst.skill_name(TOU_XI), "skill_id": TOU_XI,
		"need_card": 2, "card_source": GConst.CardSource.Cover, "enabled": 可用}]


func resolve_action_end_option(cause: int, reply: Dictionary, ctx: Dictionary) -> int:
	if cause != TOU_XI:
		return resolve_queued_extra_action(cause)
	if _touxi_step == 0:
		_touxi_step = 1
		_touxi_target = int(ctx.get("dst", _last_attack_dst))
		return _touxi_process_cards(reply)
	if _touxi_step == 2:
		return _touxi_process_targets(reply)
	return SUCCESS


func _touxi_process_cards(r: Dictionary) -> int:
	var chosen: Array = r.get("card_ids", [])
	var bottles: Array[int] = []
	for c: Variant in chosen:
		var cid: int = int(c)
		if player.有盖牌(cid) and not bottles.has(cid):
			bottles.append(cid)
		if bottles.size() >= 2:
			break
	if bottles.size() < 2:
		_touxi_step = 0
		_touxi_target = -1
		return SUCCESS
	player.remove_energy(1)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": bottles, "is_real": true,
	})
	engine.remove_cover(player.id, bottles, player.id, TOU_XI)
	engine.to_discard(bottles, {"owner": player.id, "source": "cover", "cause": TOU_XI})
	_used_touxi = true
	_touxi_step = 2
	var 法术数: int = 0
	var 攻击数: int = 0
	var 系别: int = -1
	var 同系: bool = true
	for cid2: int in bottles:
		var card: GCard = Data.get_card(cid2)
		if card == null:
			同系 = false
			continue
		if card.is_magic():
			法术数 += 1
		if card.is_attack():
			攻击数 += 1
		if 系别 < 0:
			系别 = card.element_enum()
		elif card.element_enum() != 系别:
			同系 = false
	_touxi_x = mini(法术数, enemy_ids().size())
	_touxi_two_attack = 攻击数 >= 2
	_touxi_same = 同系 and bottles.size() == 2
	if _touxi_x > 0:
		var 候选: Array[int] = enemy_ids()
		询问(player.id, TOU_XI, 0, _touxi_x, GConst.CardSource.Hand, [], 0,
			"", [], true, 1, -1, 候选, _touxi_x)
		return WAIT
	return _touxi_process_targets({})


func _touxi_process_targets(r: Dictionary) -> int:
	var 目标: Array = []
	if _touxi_x > 0:
		for d: Variant in r.get("dst_ids", []):
			var pid: int = int(d)
			if not 目标.has(pid) and enemy_ids().has(pid):
				目标.append(pid)
			if 目标.size() >= _touxi_x:
				break
	var 压了状态: bool = false
	if _touxi_same:
		engine.push(BattleEngine.SHook.new("p_touxi_same", {"player": player.id}, []))
		压了状态 = true
	for pid2: int in 目标:
		engine.push_harm({
			"src": player.id, "dst": pid2, "point": 1,
			"cause": TOU_XI, "type": GConst.HarmType.Magic, "is_active": false,
		})
		压了状态 = true
	if _touxi_two_attack:
		player.add_action(GConst.ActionType.Attack, TOU_XI, true, true)
	notice_skill(TOU_XI, 目标)
	engine._broadcast_game()
	_touxi_step = 0
	_touxi_target = -1
	_touxi_x = 0
	_touxi_same = false
	_touxi_two_attack = false
	# 压了伤害 / 同系追加钩子就必须返回 URGENT：聚合器会挂起，等这些状态结算完再继续问
	# 剩余的行动结束响应（迅捷赐福等）。返回 SUCCESS 会让聚合器立刻把下一个响应问出来，
	# 玩家会先看到「是否发动迅捷赐福」，伤害还没落地（踩过）。
	return URGENT if 压了状态 else SUCCESS


## 【偷袭】同系追加：等 X 点法术伤害结算完再询问一次追加目标，然后造成 1 点法术伤害。
func p_touxi_same(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _touxi_same_step == 0:
		_touxi_same_step = 1
		if not engine.has_reply():
			var 候选: Array[int] = enemy_ids()
			# 序号 2：对目标角色造成 1 点法术伤害（同系追加）。
			询问(player.id, TOU_XI, 0, 1, GConst.CardSource.Hand, [], 0,
				"", [], true, 2, -1, 候选)
			return WAIT
	if _touxi_same_step == 1:
		if not engine.has_reply():
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var dsts: Array = r.get("dst_ids", [])
		_touxi_same_step = 0
		if dsts.is_empty():
			return SUCCESS
		var dst: int = int(dsts[0])
		if not enemy_ids().has(dst):
			return SUCCESS
		engine.push_harm({
			"src": player.id, "dst": dst, "point": 1,
			"cause": TOU_XI, "type": GConst.HarmType.Magic, "is_active": false,
		})
		notice_skill(TOU_XI, [dst])
		engine._broadcast_game()
	return SUCCESS

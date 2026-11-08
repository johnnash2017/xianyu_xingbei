extends BattleRole
## 神秘学者（roleID 80）
##
## 【言灵】＝角色旁面朝上的牌（盖牌区 open=true，上限 3）；【秘术】＝0 号指示物（上限 4）。
##
## 技能：
##   言灵术 8001（法术）：将 1~2 张手牌面朝上作为【言灵】；你摸 1 张牌【强制】；
##       （摸牌后，若你额外弃 1 张与现存【言灵】系别相同的牌【展示】）你 +1【秘术】。
##   守护灵 8002（被动）：【言灵】>0 且你被主动攻击命中②（其他角色结算效果前）→ 移除 1 个【言灵】；
##       若【秘术】>0，移除 1 点【秘术】，把 1 张手牌面朝上作为【言灵】（护住这一击）。
##   真言术 8003（法术）：把 1 个除光系外的【言灵】当手牌打出，执行对应行动；
##       若该【言灵】是咏类命格或法术牌（或你额外移除 1 点【秘术】），行动结算完对目标对手 1 点法术伤害③。
##   禁忌秘法 8004（响应）：你的回合开始前，移除 3 点【秘术】→ 指定 2 名角色各弃 1 张牌，
##       你把弃牌面朝上作为【言灵】。
##   妖精秘术 8005（响应【回合限定】）：【真言术】结算后，立即执行一次【攻击行动】；若命中，你 +2【秘术】。
##   真言压制 8006（响应·必杀【水晶】）：【真言术】结算后，对目标角色 1 点法术伤害③。
##       （「你可立即执行一次【真言术】」需要再造一次技能行动，本轮未实现）

const YAN_LING_SHU: int = 8001
const SHOU_HU_LING: int = 8002
const ZHEN_YAN_SHU: int = 8003
const JIN_JI_MI_FA: int = 8004
const YAO_JING_MI_SHU: int = 8005
const ZHEN_YAN_YA_ZHI: int = 8006

const 秘术槽: int = 0
const 言灵上限: int = 3

## 言灵术：1＝等选牌（放言灵）/ 2＝等摸牌后选弃牌
var _言灵术阶段: int = 0
## 真言术：1＝等选言灵 / 2＝等额外移除 1 秘术
var _真言阶段: int = 0
var _真言牌: int = -1
var _真言加伤: bool = false
## 禁忌秘法：1＝等选 2 名目标
var _禁忌阶段: int = 0
## 妖精秘术：本回合已用
var _妖精已用: bool = false
## 妖精秘术给的攻击命中后要 +2 秘术
var _妖精攻击中: bool = false
## 真言术的行动结束后要结算的 1 点法术伤害（目标在行动结束时选）
var _真言待伤: bool = false


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 可用言灵: Array = _可用言灵()
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": YAN_LING_SHU,
			"need_card": 1,
			"need_target": 0,
			"cards": player.hand_cards.duplicate(),
			"enabled": not player.hand_cards.is_empty() and _言灵数() < 言灵上限,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": ZHEN_YAN_SHU,
			"need_card": 0,
			"need_target": 0,
			"enabled": not 可用言灵.is_empty(),
		},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == YAN_LING_SHU:
		var cards: Array = action.get("card_ids", [])
		if cards.is_empty() or cards.size() > 2 or _言灵数() + cards.size() > 言灵上限:
			return GConst.GE_INVALID_ACTION
		for c: Variant in cards:
			if not player.has_hand_card(int(c)):
				return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if 技能号 == ZHEN_YAN_SHU:
		if _可用言灵().is_empty():
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == YAN_LING_SHU:
		return _言灵术(action)
	if 技能号 == ZHEN_YAN_SHU:
		return _真言术()
	return EMPTY_HANDLE


# ============================================================
# 言灵术：放 1~2 张言灵 → 摸 1 → 可再弃 1 张同系牌 +1 秘术
# ============================================================
func _言灵术(action: Dictionary) -> int:
	if _言灵术阶段 == 0:
		var cards: Array = action.get("card_ids", [])
		notice_skill(YAN_LING_SHU, [player.id])
		engine.take_from_hand(player.id, cards)
		engine.add_cover(player.id, cards, player.id, YAN_LING_SHU, true)
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": cards, "is_real": true,
		})
		engine._broadcast_game()
		_言灵术阶段 = 1
		engine.push_强制摸牌(player.id, 1, YAN_LING_SHU)
		return URGENT
	# 摸完：可额外弃 1 张与现存言灵同系的牌，+1 秘术
	_言灵术阶段 = 0
	if player.hand_cards.is_empty() or _言灵数() == 0:
		return SUCCESS
	if not engine.has_reply():
		_言灵术阶段 = 2
		询问(player.id, YAN_LING_SHU, 1, 0, GConst.CardSource.Hand, [], 0, "", _同系手牌(), true,
			0, -1, [], -1, {})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var cards2: Array = r.get("card_ids", [])
	_言灵术阶段 = 0
	if args.is_empty() or cards2.is_empty():
		return SUCCESS
	var 弃: int = int(cards2[0])
	if not player.has_hand_card(弃):
		return SUCCESS
	notice_skill(YAN_LING_SHU, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [弃], "is_real": true,
	})
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": YAN_LING_SHU})
	player.add_token(秘术槽, 1)
	engine._broadcast_game()
	return SUCCESS


## 手牌里与现存【言灵】同系的牌（选弃牌的白名单）
func _同系手牌() -> Array:
	var 系们: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 != null:
			系们.append(牌.element_enum())
	var out: Array = []
	for cid: int in player.hand_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 != null and 系们.has(牌.element_enum()):
			out.append(cid)
	return out


# ============================================================
# 真言术：把 1 个非光系言灵当手牌打出
# ============================================================
func _真言术() -> int:
	if _真言阶段 == 0:
		var 可用: Array = _可用言灵()
		if 可用.is_empty():
			return SUCCESS
		_真言阶段 = 1
		var 选项: Array = []
		for i: int in range(可用.size()):
			var cid: int = int(可用[i])
			var 牌: GCard = Data.get_card(cid)
			if 牌 == null:
				continue
			选项.append({
				"value": i + 1,
				"label": "%s %s" % [牌.card_name, GConst.element_to_chinese(牌.element_enum())],
				"card_id": cid,
			})
		询问(player.id, ZHEN_YAN_SHU, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _真言阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var 可用2: Array = _可用言灵()
		_真言阶段 = 0
		if args.is_empty():
			return SUCCESS
		var 档: int = int(args[0])
		if 档 < 1 or 档 > 可用2.size():
			return SUCCESS
		_真言牌 = int(可用2[档 - 1])
		var 牌: GCard = Data.get_card(_真言牌)
		if 牌 == null:
			return SUCCESS
		notice_skill(ZHEN_YAN_SHU, [player.id])
		# 把言灵从盖牌区拿到手里，再给一份只能用它的对应行动
		engine.remove_cover(player.id, [_真言牌], player.id, ZHEN_YAN_SHU)
		player.add_hand_cards([_真言牌])
		engine.播获得牌日志(player.id, [_真言牌])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [_真言牌], "is_real": true,
		})
		_真言加伤 = 牌.is_magic() or 牌.fate_pattern_enum() == GConst.FatePattern.Cast
		var 种类: int = GConst.ActionType.Attack if 牌.is_attack() else GConst.ActionType.Magic
		player.add_action(种类, ZHEN_YAN_SHU, true, false, {"cards": [GConst.牌号(_真言牌)]})
		_真言待伤 = _真言加伤
		engine._broadcast_game()
		return SUCCESS
	return SUCCESS


## 【真言术】结算后的可选响应：妖精秘术（攻击行动）/ 真言压制（水晶 1 点法术伤害）
func action_end_options(ctx: Dictionary) -> Array:
	if int(ctx.get("extra_cause", 0)) != ZHEN_YAN_SHU:
		return []
	var out: Array = []
	if not _妖精已用:
		out.append({
			"value": YAO_JING_MI_SHU,
			"label": GConst.按钮原文(YAO_JING_MI_SHU, 0),
			"skill_id": YAO_JING_MI_SHU,
			"enabled": true,
		})
	out.append({
		"value": ZHEN_YAN_YA_ZHI,
		"label": GConst.按钮原文(ZHEN_YAN_YA_ZHI, 0),
		"skill_id": ZHEN_YAN_YA_ZHI,
		"need_target": 1,
		"targets": 敌人(),
		"enabled": player.get_energy() >= 1,
	})
	return out


func resolve_action_end_option(cause: int, reply: Dictionary, _ctx: Dictionary) -> int:
	if cause == YAO_JING_MI_SHU:
		_妖精已用 = true
		_妖精攻击中 = true
		notice_skill(YAO_JING_MI_SHU, [player.id])
		player.add_action(GConst.ActionType.Attack, YAO_JING_MI_SHU, true)
		engine._broadcast_game()
		return SUCCESS
	if cause == ZHEN_YAN_YA_ZHI:
		var dsts: Array = reply.get("dst_ids", [])
		if dsts.is_empty() or player.get_energy() < 1:
			return GConst.GE_INVALID_ARGUMENT
		var dst: int = int(dsts[0])
		if engine.p(dst) == null:
			return GConst.GE_INVALID_PLAYERID
		notice_skill(ZHEN_YAN_YA_ZHI, [dst])
		player.remove_energy(1)
		engine.push_harm({"src": player.id, "dst": dst, "point": 1,
			"cause": ZHEN_YAN_YA_ZHI, "type": GConst.HarmType.Magic})
		engine._broadcast_game()
		return URGENT
	return resolve_queued_extra_action(cause)


## 真言术的行动结算完：若该言灵是咏类/法术牌（或已付 1 秘术），对目标对手 1 点法术伤害
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("extra_cause", 0)) == ZHEN_YAN_SHU and _真言待伤:
		_真言待伤 = false
		if not engine.has_reply():
			询问(player.id, ZHEN_YAN_SHU, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
				0, -1, 敌人(), -1, {}, 1, GConst.HarmType.Magic)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var dsts: Array = r.get("dst_ids", [])
		if not dsts.is_empty():
			engine.push_harm({"src": player.id, "dst": int(dsts[0]), "point": 1,
				"cause": ZHEN_YAN_SHU, "type": GConst.HarmType.Magic})
			return URGENT
	if int(ctx.get("extra_cause", 0)) == YAO_JING_MI_SHU:
		_妖精攻击中 = false
	return SUCCESS


## 命中②：守护灵（被主动攻击）先拆言灵；妖精秘术给的攻击命中则 +2 秘术
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	# 守护灵：你被主动攻击命中②，其他角色结算效果前
	if int(harm.get("dst", -1)) == player.id and bool(ctx.get("is_active", false)) and _言灵数() > 0:
		notice_skill(SHOU_HU_LING, [player.id])
		var 第一个: int = int(player.cover_cards[0])
		engine.remove_cover(player.id, [第一个], player.id, SHOU_HU_LING)
		engine.to_discard([第一个], {"owner": player.id, "source": "cover", "cause": SHOU_HU_LING})
		if player.token_num(秘术槽) > 0 and not player.hand_cards.is_empty() and _言灵空间() > 0:
			player.remove_token(秘术槽, 1)
			var 补: int = int(player.hand_cards[0])
			engine.take_from_hand(player.id, [补])
			engine.add_cover(player.id, [补], player.id, SHOU_HU_LING, true)
		engine._broadcast_game()
	if _妖精攻击中 and int(harm.get("src", -1)) == player.id and bool(ctx.get("is_active", false)):
		player.add_token(秘术槽, 2)
		notice_skill(YAO_JING_MI_SHU, [player.id])
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 禁忌秘法：回合开始前移 3 秘术 → 2 名角色各弃 1，弃牌作言灵
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_妖精已用 = false
	if _禁忌阶段 != 0:
		return _禁忌秘法()
	if player.token_num(秘术槽) < 3 or _言灵空间() <= 0:
		return SUCCESS
	_禁忌阶段 = 1
	询问(player.id, JIN_JI_MI_FA, 0, 2, GConst.CardSource.Hand, [], 0, "", [], true,
		0, -1, 全部角色(), -1, {}, 0, 0)
	return WAIT


func _禁忌秘法() -> int:
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	_禁忌阶段 = 0
	if args.is_empty() or dsts.size() < 2:
		return SUCCESS
	if player.token_num(秘术槽) < 3:
		return SUCCESS
	player.remove_token(秘术槽, 3)
	notice_skill(JIN_JI_MI_FA, dsts)
	var 得: Array = []
	for i: int in range(mini(2, dsts.size())):
		var dp: BattlePlayer = engine.p(int(dsts[i]))
		if dp == null or dp.hand_cards.is_empty():
			continue
		var 弃: int = int(dp.hand_cards[0])
		engine.take_from_hand(dp.id, [弃])
		engine.to_discard([弃], {"owner": dp.id, "source": "hand", "cause": JIN_JI_MI_FA})
		engine._log_discard(dp.id, [弃], true)
		得.append(弃)
	if 得.is_empty():
		return SUCCESS
	# 弃牌面朝上作为【言灵】（受言灵上限约束）
	var 收: Array = []
	for c: Variant in 得:
		if 收.size() >= _言灵空间():
			break
		收.append(int(c))
	if not 收.is_empty():
		for c2: Variant in 收:
			engine.deck.取出实例(int(c2))
		engine.add_cover(player.id, 收, player.id, JIN_JI_MI_FA, true)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _言灵数() -> int:
	return player.cover_cards.size()


func _言灵空间() -> int:
	return maxi(言灵上限 - _言灵数(), 0)


## 可当【真言术】素材的言灵（除光系外）
func _可用言灵() -> Array:
	var out: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		if 牌.element_enum() == GConst.CardElement.Light:
			continue
		out.append(cid)
	return out


func 敌人() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color:
			out.append(pid)
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

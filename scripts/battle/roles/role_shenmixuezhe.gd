extends BattleRole
## 神秘学者（roleID 80）
##
## 【言灵】＝角色旁面朝上的牌（盖牌区 open=true，上限读角色表盖牌槽：3）；【秘术】＝0 号指示物（上限 4）。
##
## 技能：
##   言灵术 8001（法术）：将 1~2 张手牌面朝上作为【言灵】；你摸 1 张牌【强制】；
##       （摸牌后，若你额外弃 1 张与现存【言灵】系别相同的牌【展示】）你 +1【秘术】。
##   守护灵 8002（被动）：【言灵】数>0 且你被主动攻击命中②（其他角色结算效果前）→ 移除 1 个【言灵】；
##       若【秘术】>0，移除 1 点【秘术】，把 1 张手牌面朝上作为【言灵】。
##   真言术 8003（法术）：把 1 个除光系外的【言灵】当手牌打出，执行对应行动；
##       若该【言灵】是咏类命格或法术牌（或你额外移除 1 点【秘术】），行动结算完对目标对手 1 点法术伤害③。
##   禁忌秘法 8004（响应）：你的回合开始前，移除 3 点【秘术】→ 指定 2 名角色各弃 1 张牌，
##       你把弃牌面朝上作为【言灵】。
##   妖精秘术 8005（响应【回合限定】）：【真言术】或【真言压制】结算后，立即执行一次【攻击行动】；
##       若本次执行的攻击命中②，你 +2【秘术】。
##   真言压制 8006（响应·必杀【水晶】）：【真言术】结算后，对目标角色 1 点法术伤害③，
##       你可立即执行一次【真言术】。
##
## 参考实现：9303 / 8601 的「把牌作为相应行动发出」（加入手牌 + direct 额外行动 + 白名单），
## 7802 的多步询问与「摸牌后重入技能本体」（技能URGENT后重入），7805 的「别人弃牌先问本人」。

const YAN_LING_SHU: int = 8001
const SHOU_HU_LING: int = 8002
const ZHEN_YAN_SHU: int = 8003
const JIN_JI_MI_FA: int = 8004
const YAO_JING_MI_SHU: int = 8005
const ZHEN_YAN_YA_ZHI: int = 8006

const 秘术槽: int = 0

## 言灵术：0＝未开始 / 1＝已放言灵等摸牌 / 2＝等额外弃牌 / 3＝完成
var _言灵术阶段: int = 0
## 真言术：0＝未开始 / 1＝等选言灵 / 2＝等是否额外移除 1 秘术 / 3＝完成
var _真言阶段: int = 0
## 真言术选中的言灵、是否加伤、加伤待结算
var _真言牌: int = -1
var _真言加伤: bool = false
var _真言待伤: bool = false
## 真言术给出的额外行动还没打出去时，这张牌在手里（回合结束放回【言灵】）
var _真言待打: int = -1
## 禁忌秘法：0＝未开始 / 1＝等选 2 名目标 / 2＝等两名目标各弃 1 张
var _禁忌阶段: int = 0
var _禁忌目标: Array = []
var _禁忌弃牌: Array = []
## 真言压制给出的「立即执行一次【真言术】」还挂着：此时行动阶段只放行 8003
var _真言压制重真言: bool = false
## 妖精秘术：本回合已用；给出的攻击行动进行中
var _妖精已用: bool = false
var _妖精攻击中: bool = false
## 守护灵：0＝未问 / 1＝等选言灵（+手牌）
var _守护灵阶段: int = 0


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	if _真言压制重真言:
		# 「你可立即执行一次【真言术】」：这一手只给真言术，别的技能按钮都不摆
		return [{
			"type": GConst.ActionType.MagicSkill,
			"id": ZHEN_YAN_SHU,
			"need_card": 0,
			"need_target": 0,
			"enabled": not _可用言灵().is_empty(),
		}]
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": YAN_LING_SHU,
			"need_card": 1,
			"card_max": 2,
			"need_target": 0,
			"enabled": not player.hand_cards.is_empty() and player.cover_space() > 0,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": ZHEN_YAN_SHU,
			"need_card": 0,
			"need_target": 0,
			"enabled": not _可用言灵().is_empty(),
		},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if _真言压制重真言 and 技能号 != ZHEN_YAN_SHU:
		return GConst.GE_INVALID_ACTION
	if 技能号 == YAN_LING_SHU:
		var cards: Array = action.get("card_ids", [])
		if cards.is_empty() or cards.size() > 2 or cards.size() > player.cover_space():
			return GConst.GE_INVALID_ACTION
		for c: Variant in cards:
			if player.手牌实例(int(c)) < 0:
				return GConst.GE_INVALID_ACTION
		_言灵术阶段 = 0
		return GConst.GE_SUCCESS
	if 技能号 == ZHEN_YAN_SHU:
		if _可用言灵().is_empty():
			return GConst.GE_INVALID_ACTION
		_真言阶段 = 0
		_真言牌 = -1
		_真言加伤 = false
		_真言待伤 = false
		_真言压制重真言 = false
		_真言待打 = -1
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == YAN_LING_SHU:
		return _言灵术(action)
	if 技能号 == ZHEN_YAN_SHU:
		return _真言术()
	return EMPTY_HANDLE


## 言灵术：放 1~2 张言灵 → 摸 1 张（状态版）→ 回来问「额外弃 1 张同系牌」
func _言灵术(action: Dictionary) -> int:
	if _言灵术阶段 == 3:
		return SUCCESS
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
	if _言灵术阶段 == 1:
		# 摸牌（含超限弃牌）结算完回来：还有同系手牌才问额外弃牌
		var 同系: Array = _同系手牌()
		if 同系.is_empty():
			_言灵术阶段 = 3
			return SUCCESS
		_言灵术阶段 = 2
		询问(player.id, YAN_LING_SHU, 1, 0, GConst.CardSource.Hand, [], 0, "", 同系, true,
			0, -1, [], -1, {})
		return WAIT
	# 阶段 2：额外弃 1 张同系牌 → +1【秘术】
	var r: Dictionary = take_skill_reply_full()
	_言灵术阶段 = 3
	var cards2: Array = r.get("card_ids", [])
	if cards2.is_empty():
		return SUCCESS
	var 弃: int = -1
	for c: Variant in cards2:
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0 and _同系手牌().has(实例):
			弃 = 实例
			break
	if 弃 < 0:
		return SUCCESS
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [弃], "is_real": true,
	})
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": YAN_LING_SHU})
	engine._log_discard(player.id, [弃], false)
	player.add_token(秘术槽, 1)
	engine._broadcast_game()
	return SUCCESS


## 摸完牌要回来接着问「额外弃牌」：只放行 8001 的这一步
func 技能URGENT后重入(action: Dictionary = {}) -> bool:
	return int(action.get("action_id", 0)) == YAN_LING_SHU and _言灵术阶段 == 1


# ============================================================
# 真言术：把 1 个非光系【言灵】当手牌打出
# ============================================================
func _真言术() -> int:
	if _真言阶段 == 3:
		return SUCCESS
	if _真言阶段 == 0:
		var 可用: Array = _可用言灵()
		if 可用.is_empty():
			return SUCCESS
		_真言阶段 = 1
		询问(player.id, ZHEN_YAN_SHU, 0, 0, GConst.CardSource.Hand, _言灵选项(可用), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _真言阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var 可用2: Array = _可用言灵()
		if args.is_empty():
			_真言阶段 = 3
			return SUCCESS
		var 档: int = int(args[0])
		if 档 < 1 or 档 > 可用2.size():
			engine.报错("【真言术】选项号越界", player.id)
			_真言阶段 = 3
			return SUCCESS
		_真言牌 = int(可用2[档 - 1])
		var 牌: GCard = Data.get_card(_真言牌)
		if 牌 == null:
			engine.报错("【真言术】言灵不存在", player.id)
			_真言阶段 = 3
			return SUCCESS
		_真言加伤 = 牌.is_magic() or 牌.fate_pattern_enum() == GConst.FatePattern.Cast
		if not _真言加伤 and player.token_num(秘术槽) > 0:
			# 不是咏类 / 法术牌时，才可以额外移除 1 点【秘术】换那 1 点伤害
			_真言阶段 = 2
			询问(player.id, ZHEN_YAN_SHU, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {})
			return WAIT
		return _真言出牌()
	# 阶段 2：是否额外移除 1 点【秘术】
	var r2: Dictionary = take_skill_reply_full()
	if _真言出牌_是否确认(r2):
		player.remove_token(秘术槽, 1)
		_真言加伤 = true
	return _真言出牌()


## 「是否额外移除 1 点秘术」的确认：players 点「确定」时客户端回 args[0]=1
func _真言出牌_是否确认(r: Dictionary) -> bool:
	var args: Array = r.get("args", [])
	return args.size() > 0 and int(args[0]) == 1


## 言灵离开【言灵】区 → 加入手牌 → 给一份「只能用这张牌」的立刻行动
func _真言出牌() -> int:
	_真言阶段 = 3
	var 牌: GCard = Data.get_card(_真言牌)
	if 牌 == null:
		return SUCCESS
	notice_skill(ZHEN_YAN_SHU, [player.id])
	engine.remove_cover(player.id, [_真言牌], player.id, ZHEN_YAN_SHU)
	player.add_hand_cards([_真言牌])
	engine.播获得牌日志(player.id, [_真言牌])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [_真言牌], "is_real": true,
	})
	_真言待打 = _真言牌
	_真言待伤 = _真言加伤
	var 种类: int = GConst.ActionType.Attack if 牌.is_attack() else GConst.ActionType.Magic
	player.add_action(种类, ZHEN_YAN_SHU, true, false, {"cards": [GConst.牌号(_真言牌)]})
	engine._broadcast_game()
	return SUCCESS


## 真言术 / 真言压制 结算后的响应：妖精秘术（攻击行动）/ 真言压制（水晶 1 点法术伤害）
func action_end_options(ctx: Dictionary) -> Array:
	var cause: int = int(ctx.get("extra_cause", 0))
	if int(ctx.get("player", -1)) != player.id or (cause != ZHEN_YAN_SHU and cause != ZHEN_YAN_YA_ZHI):
		return []
	if not bool(ctx.get("is_extra", false)):
		return []
	var out: Array = []
	if not _妖精已用:
		out.append({
			"value": YAO_JING_MI_SHU,
			"label": GConst.按钮原文(YAO_JING_MI_SHU, 0),
			"text": GConst.按钮原文(YAO_JING_MI_SHU, 0),
			"skill_id": YAO_JING_MI_SHU,
			"enabled": true,
			"need_target": 0,
		})
	out.append({
		"value": ZHEN_YAN_YA_ZHI,
		"label": GConst.按钮原文(ZHEN_YAN_YA_ZHI, 0),
		"text": GConst.按钮原文(ZHEN_YAN_YA_ZHI, 0),
		"skill_id": ZHEN_YAN_YA_ZHI,
		"need_target": 1,
		"targets": 全部角色(),
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
		# 「你可立即执行一次【真言术】」：给一份只放行 8003 的立刻法术行动
		_真言压制重真言 = true
		player.add_action(GConst.ActionType.Magic, ZHEN_YAN_YA_ZHI, true, false,
			{"cards": [GConst.手牌白名单_全禁]})
		engine.push_harm({"src": player.id, "dst": dst, "point": 1,
			"cause": ZHEN_YAN_YA_ZHI, "type": GConst.HarmType.Magic})
		engine._broadcast_game()
		return URGENT
	return resolve_queued_extra_action(cause)


## 真言术给出的行动结算完：加伤则对目标对手 1 点法术伤害③；妖精秘术的攻击结束则收尾
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_extra", false)):
		return SUCCESS
	match int(ctx.get("extra_cause", 0)):
		ZHEN_YAN_SHU:
			_真言待打 = -1
			if not _真言待伤:
				return SUCCESS
			_真言待伤 = false
			if not engine.has_reply():
				询问(player.id, ZHEN_YAN_SHU, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
					0, -1, enemy_ids(), -1, {}, 1, GConst.HarmType.Magic)
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			var dsts: Array = r.get("dst_ids", [])
			if dsts.is_empty():
				return SUCCESS
			var dst: int = int(dsts[0])
			if not enemy_ids().has(dst):
				return SUCCESS
			engine.push_harm({"src": player.id, "dst": dst, "point": 1,
				"cause": ZHEN_YAN_SHU, "type": GConst.HarmType.Magic})
			return URGENT
		YAO_JING_MI_SHU:
			_妖精攻击中 = false
	return SUCCESS


## 回合结束：真言术给出的行动没打出去时，把那张牌放回【言灵】区（不白拿一张手牌）
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_妖精攻击中 = false
	_真言压制重真言 = false
	_真言待伤 = false
	if _真言待打 < 0:
		return SUCCESS
	var 牌: int = _真言待打
	_真言待打 = -1
	if player.手牌实例(牌) < 0 or player.cover_space() <= 0:
		return SUCCESS
	engine.take_from_hand(player.id, [牌])
	engine.add_cover(player.id, [牌], player.id, ZHEN_YAN_SHU, true)
	engine._broadcast_game()
	return SUCCESS


## 命中②：守护灵（自己被主动攻击命中，先拆 1 个言灵、可再用 1 秘术补 1 张）；
## 妖精秘术给出的攻击命中则 +2【秘术】
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if _妖精攻击中 and int(harm.get("src", -1)) == player.id and bool(ctx.get("is_active", false)):
		player.add_token(秘术槽, 2)
		notice_skill(YAO_JING_MI_SHU, [player.id])
		engine._broadcast_game()
	if int(harm.get("dst", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if int(harm.get("src", -1)) < 0:
		return SUCCESS
	if _言灵数() == 0:
		return SUCCESS
	var 可补: bool = player.token_num(秘术槽) > 0 and not player.hand_cards.is_empty()
	if _守护灵阶段 == 0:
		_守护灵阶段 = 1
		if 可补:
			# 一个言灵 + 一张手牌，同一步选完（cover_need=1 / hand_need=1 走混选）
			询问(player.id, SHOU_HU_LING, 2, 0, GConst.CardSource.HandOrCover, [], 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 1, "", -1, "", [], [], 0, 1)
		else:
			询问(player.id, SHOU_HU_LING, 1, 0, GConst.CardSource.Cover, [], 0, "", [], false,
				0, -1, [], -1, {})
		return WAIT
	_守护灵阶段 = 0
	var r: Dictionary = take_skill_reply_full()
	var 拆: int = -1
	var 补: int = -1
	for c: Variant in r.get("card_ids", []):
		var 盖实例: int = player.盖牌实例(int(c))
		if 盖实例 >= 0 and 拆 < 0:
			拆 = 盖实例
			continue
		var 手实例: int = player.手牌实例(int(c))
		if 手实例 >= 0 and 补 < 0:
			补 = 手实例
	if 拆 < 0:
		# 强制项：超时 / 空回复按言灵顺序补一个
		拆 = int(player.cover_cards[0])
	notice_skill(SHOU_HU_LING, [player.id])
	engine.remove_cover(player.id, [拆], player.id, SHOU_HU_LING)
	engine.to_discard([拆], {"owner": player.id, "source": "cover", "cause": SHOU_HU_LING})
	engine._log_discard(player.id, [拆], false)
	if 可补 and player.token_num(秘术槽) > 0:
		if 补 < 0:
			补 = int(player.hand_cards[0])
		player.remove_token(秘术槽, 1)
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [补], "is_real": true,
		})
		engine.take_from_hand(player.id, [补])
		engine.add_cover(player.id, [补], player.id, SHOU_HU_LING, true)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 禁忌秘法：回合开始前移 3 秘术 → 2 名角色各弃 1 张，弃牌作言灵
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_妖精已用 = false
	_真言压制重真言 = false
	if _禁忌阶段 == 2:
		return _禁忌弃牌推进()
	if _禁忌阶段 == 1:
		return _禁忌秘法()
	if player.token_num(秘术槽) < 3 or player.cover_space() <= 0:
		return SUCCESS
	_禁忌阶段 = 1
	询问(player.id, JIN_JI_MI_FA, 0, 2, GConst.CardSource.Hand, [], 0, "", [], true,
		0, -1, 全部角色(), -1, {})
	return WAIT


func _禁忌秘法() -> int:
	var r: Dictionary = take_skill_reply_full()
	var dsts: Array = r.get("dst_ids", [])
	_禁忌阶段 = 0
	if dsts.is_empty():
		return SUCCESS
	if player.token_num(秘术槽) < 3:
		return SUCCESS
	var 选: Array = []
	for d: Variant in dsts:
		if engine.p(int(d)) != null and not 选.has(int(d)):
			选.append(int(d))
		if 选.size() >= 2:
			break
	if 选.size() < 2:
		engine.报错("【禁忌秘法】目标不足 2 名", player.id)
		return SUCCESS
	player.remove_token(秘术槽, 3)
	notice_skill(JIN_JI_MI_FA, 选)
	_禁忌弃牌 = []
	_禁忌目标 = 选
	_禁忌阶段 = 2
	return _禁忌弃牌推进()


## 两名目标依次由本人选 1 张牌弃掉（标准弃牌应答），弃牌再面朝上作为【言灵】
func _禁忌弃牌推进() -> int:
	while _禁忌弃牌.size() < _禁忌目标.size():
		var dp: BattlePlayer = engine.p(int(_禁忌目标[_禁忌弃牌.size()]))
		if dp == null:
			_禁忌弃牌.append({})
			continue
		if dp.hand_cards.is_empty():
			_禁忌弃牌.append({})
			continue
		if not engine.has_reply():
			engine.ask_respond(dp.id, GConst.RespondType.Discard, [dp.id, JIN_JI_MI_FA, 1], [dp.id])
			engine.wait_for(dp.id, GConst.Msg.Respond)
			return WAIT
		var r弃: Dictionary = take_skill_reply_full()
		var 弃: int = -1
		for c: Variant in r弃.get("card_ids", []):
			var 实例: int = dp.手牌实例(int(c))
			if 实例 >= 0:
				弃 = 实例
				break
		if 弃 < 0:
			for c0: int in dp.hand_cards:
				if dp.has_discard_card(c0):
					弃 = c0
					break
		if 弃 < 0:
			_禁忌弃牌.append({})
			continue
		engine.take_from_hand(dp.id, [弃])
		engine.to_discard([弃], {"owner": dp.id, "source": "hand", "cause": JIN_JI_MI_FA})
		engine._log_discard(dp.id, [弃])
		_禁忌弃牌.append({"pid": dp.id, "card": 弃})
	# 弃牌都进弃牌堆之后，把它们面朝上放到自己角色旁作为【言灵】
	var 得: Array = []
	for 项: Dictionary in _禁忌弃牌:
		var cid: int = int(项.get("card", -1))
		if cid < 0:
			continue
		var 取回: int = engine.deck.取出实例(cid)
		if 取回 < 0:
			continue
		if 得.size() >= player.cover_space():
			engine.to_discard([取回], {"owner": player.id, "source": "other", "cause": JIN_JI_MI_FA})
			continue
		得.append(取回)
	_禁忌弃牌 = []
	_禁忌目标 = []
	_禁忌阶段 = 0
	if 得.is_empty():
		engine._broadcast_game()
		return SUCCESS
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": 得, "is_real": true,
	})
	engine.add_cover(player.id, 得, player.id, JIN_JI_MI_FA, true)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _言灵数() -> int:
	return player.cover_cards.size()


## 可当【真言术】素材的言灵（除光系外）。0 是合法实例号，判空只能用 < 0
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


## 手牌里与现存【言灵】系别相同的牌（言灵术「额外弃 1 张」的可选牌）
func _同系手牌() -> Array:
	var 系们: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 != null and not 系们.has(牌.element_enum()):
			系们.append(牌.element_enum())
	var out: Array = []
	for cid: int in player.hand_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 != null and 系们.has(牌.element_enum()):
			out.append(cid)
	return out


func _言灵选项(可用: Array) -> Array:
	var out: Array = []
	for i: int in range(可用.size()):
		var cid: int = int(可用[i])
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		var 文案: String = "%s %s" % [牌.card_name, GConst.element_to_chinese(牌.element_enum())]
		out.append({"value": i + 1, "label": 文案, "card_id": cid})
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

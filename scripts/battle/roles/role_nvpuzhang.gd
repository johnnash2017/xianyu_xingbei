extends BattleRole
## 女仆长（roleID 81）
##
## 【影】＝角色旁的盖牌（面朝下，角色表「盖牌槽」3 张）；【糸】＝0 号指示物（上限 4）；
## 【风穴】＝挂在对手面前的场卡（专属卡，owner 始终是女仆长）。
##
## 技能：
##   影之穴 8101（启动）：移除 1 点【糸】，把【风穴】转移 / 放到目标对手面前，他弃 1 张牌。
##   秘术·摹影 8102（响应）：主动攻击命中②，把这次攻击牌面朝下作为【影】。
##   瞬·影·杀 8103（响应【回合限定】）：主动攻击未命中②，移除 1 个【影】→ 额外 +1【攻击行动】；
##       本回合你的主动攻击无法应战、也不能再发动【秘术·摹影】。
##   影缝 8104（响应）：持有【风穴】的对手回合开始时，移除 X 点【糸】（X<4）→ 他弃 X 张牌，
##       你从中挑 1 张面朝下作为【影】；若他实际弃牌数小于 X，对方士气 -1。
##   侍奉之道 8105（响应）：你的回合结束时，移除 2 个【影】【展示】→ +1【糸】；
##       若两张【影】同系，把其中 1 张交给目标角色【强制】，然后你【横置】。
##   禁术·影牢 8106（响应）：其他角色【特殊行动】结束时 +1【糸】；若你已【横置】，
##       可额外移除 3 点【糸】→【重置】，对目标对手 2 点法术伤害③，或指定目标队友弃 1 张牌。
##   影之风 8107（专属技·被动）：拥有【风穴】时，主动攻击命中的攻击牌进弃牌堆后作为【影】；
##       你每次【攻击行动】结束时 +1【糸】。
##   风止 8109（专属技·响应）：拥有【风穴】时，你的回合结束可发动：手牌补到上限【强制】，
##       弃 2 张牌作为【影】，然后移除【风穴】。
##   真·摹影 8108（启动·必杀技【宝石】）：把 2 张手牌面朝下作为【影】。

const YING_ZHI_XUE: int = 8101
const MI_SHU_MO_YING: int = 8102
const SHUN_YING_SHA: int = 8103
const YING_FENG: int = 8104
const SHI_FENG_ZHI_DAO: int = 8105
const JIN_SHU_YING_LAO: int = 8106
const YING_ZHI_FENG: int = 8107
const ZHEN_MO_YING: int = 8108
const FENG_ZHI: int = 8109

const 糸槽: int = 0
const 风穴名: String = "风穴"

## 影之穴：0＝还没付代价 / 1＝等对手弃牌
var _影之穴阶段: int = 0
## 秘术·摹影：0＝未问 / 1＝等是否发动
var _摹影阶段: int = 0
## 瞬·影·杀：0＝未问 / 1＝等选影
var _瞬影杀阶段: int = 0
## 瞬·影·杀：本回合主动攻击无法应战、不能再发动秘术·摹影
var _本回合禁应战: bool = false
var _本回合禁摹影: bool = false
var _瞬影杀已用: bool = false
## 影缝：1＝等选 X / 2＝等对手弃牌 / 3＝等从弃牌里挑 1 张
var _影缝阶段: int = 0
var _影缝X: int = 0
var _影缝目标: int = -1
var _影缝弃牌: Array = []
## 侍奉之道：第一段选的两张【影】同不同系（同系才问「交给谁」）
var _侍奉同系: bool = false
var _侍奉牌: Array = []
## 禁术·影牢：0＝未问 / 1＝等「是否发动」 / 2＝已 +1 糸、等下一拍弹第二段 / 3＝等选效果+目标
var _影牢阶段: int = 0
## 风止：0＝未问 / 1＝等「是否发动」 / 2＝等补手牌后弃 2 张 / 3＝已问弃牌、等答复
var _风止阶段: int = 0


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 对手: Array[int] = 敌人()
	return [
		{
			"type": GConst.ActionType.ActivateSkill,
			"id": YING_ZHI_XUE,
			"need_card": 0,
			"need_target": 1,
			# 不能放到「【风穴】现在正挂着的那个对手」身上（转移必须换人）
			"targets": _影之穴可选目标(),
			"enabled": player.token_num(糸槽) >= 1 and not _影之穴可选目标().is_empty(),
		},
		{
			"type": GConst.ActionType.ActivateSkill,
			"id": ZHEN_MO_YING,
			"need_card": 2,
			"need_target": 0,
			"cards": player.hand_cards.duplicate(),
			"enabled": player.gem > 0 and player.hand_cards.size() >= 2,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == YING_ZHI_XUE or skill_id == ZHEN_MO_YING


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == YING_ZHI_XUE:
		if player.token_num(糸槽) < 1:
			return GConst.GE_INVALID_ACTION
		var dsts: Array = action.get("dst_ids", [])
		if dsts.is_empty():
			return GConst.GE_INVALID_ARGUMENT
		var dp: BattlePlayer = engine.p(int(dsts[0]))
		if dp == null or dp.color == player.color:
			return GConst.GE_INVALID_ACTION
		# 不能放在【风穴】当前挂着的那个人身上（只能转移给别人）
		if 持有风穴(dp.id):
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if 技能号 == ZHEN_MO_YING:
		var cards: Array = action.get("card_ids", [])
		# 不再看盖牌槽够不够：可以超出上限，多出来的由引擎「盖牌超限」询问让玩家自己选着弃
		if player.gem <= 0 or cards.size() != 2:
			return GConst.GE_INVALID_ACTION
		for c: Variant in cards:
			if not player.has_discard_card(int(c)):
				return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_special_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == ZHEN_MO_YING:
		return _真摹影(action)
	if 技能号 == YING_ZHI_XUE:
		return _影之穴(action)
	return SUCCESS


## 真·摹影：付 1 宝石，2 张手牌面朝下作为【影】
func _真摹影(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	player.boot_skill_used = true
	notice_skill(ZHEN_MO_YING, [player.id])
	player.set_gem(player.gem - 1)
	engine.take_from_hand(player.id, cards)
	engine.add_cover(player.id, cards, player.id, ZHEN_MO_YING, false)
	engine._broadcast_game()
	return SUCCESS


## 影之穴：移 1【糸】，把【风穴】放到目标对手面前，他弃 1 张牌
func _影之穴(action: Dictionary) -> int:
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	var dp: BattlePlayer = engine.p(dst)
	player.boot_skill_used = true
	if _影之穴阶段 == 0:
		player.remove_token(糸槽, 1)
		# 同一张【风穴】只存在一份：加场卡按 id 顶掉旧的（转移＝换个 attached）
		engine.加场卡({"id": 风穴名, "owner": player.id, "attached": dst})
		notice_skill(YING_ZHI_XUE, [dst])
		_影之穴阶段 = 1
		engine._broadcast_game()
	if _影之穴阶段 == 1:
		if not engine.has_reply():
			engine.ask_respond(dst, GConst.RespondType.Discard, [dst, YING_ZHI_XUE, 1], [dst])
			engine.wait_for(dst, GConst.Msg.Respond)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_影之穴阶段 = 0
		var 弃: int = -1
		var cards: Array = r.get("card_ids", [])
		if not cards.is_empty() and dp != null and dp.has_discard_card(int(cards[0])):
			弃 = int(cards[0])
		elif dp != null and not dp.hand_cards.is_empty():
			# 强制弃牌：超时 / 空回复按手牌顺序补一张
			弃 = int(dp.hand_cards[0])
		if 弃 >= 0 and dp != null:
			engine.take_from_hand(dp.id, [弃])
			engine.to_discard([弃], {"owner": dp.id, "source": "hand", "cause": YING_ZHI_XUE})
			engine._log_discard(dp.id, [弃], false)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击命中② / 未命中②：影之风（自动）、秘术·摹影（响应）、瞬·影·杀（响应）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	var 攻方: int = int(harm.get("src", -1))
	# 影之风：挂着【风穴】的那个人主动攻击命中后，他这次打出的**真实**攻击牌变成女仆长的【影】。
	# 「你」＝拥有【风穴】的人（卡挂在谁面前就是谁），不是女仆长自己。
	# 真实性看 harm.card_id_instance（真正打出去的实体牌）：普通出牌 / 「视为某系斩击」的攻击都有；
	# 虚拟攻击（如【多重射击】按虚拟暗灭打出）没有 → 不触发。
	if 持有风穴(攻方):
		var 实体: int = int(harm.get("card_id_instance", -1))
		if 实体 >= 0:
			_把弃牌变成影(实体, YING_ZHI_FENG)
		return SUCCESS
	if 攻方 != player.id:
		return SUCCESS
	var 牌: int = int(harm.get("card_id", -1))
	if 牌 < 0:
		return SUCCESS
	if _本回合禁摹影:
		return SUCCESS
	if _摹影阶段 == 0:
		_摹影阶段 = 1
		询问(player.id, MI_SHU_MO_YING, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	_摹影阶段 = 0
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	_把弃牌变成影(牌, MI_SHU_MO_YING)
	return SUCCESS


## 瞬·影·杀：主动攻击未命中②，移除 1 个【影】→ 额外 +1 攻击行动；本回合主动攻击无法应战、禁【秘术·摹影】
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _瞬影杀已用 or player.cover_cards.is_empty():
		return SUCCESS
	if _瞬影杀阶段 == 0:
		_瞬影杀阶段 = 1
		询问(player.id, SHUN_YING_SHA, 1, 0, GConst.CardSource.Cover, [], 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	_瞬影杀阶段 = 0
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	if args.is_empty() or int(args[0]) != 1 or cards.is_empty():
		return SUCCESS
	var cid: int = int(cards[0])
	if not player.有盖牌(cid):
		return SUCCESS
	_瞬影杀已用 = true
	_本回合禁应战 = true
	_本回合禁摹影 = true
	notice_skill(SHUN_YING_SHA, [player.id])
	engine.remove_cover(player.id, [cid], player.id, SHUN_YING_SHA)
	engine.to_discard([cid], {"owner": player.id, "source": "cover", "cause": SHUN_YING_SHA})
	engine._log_discard(player.id, [cid], false)
	player.add_action(GConst.ActionType.Attack, SHUN_YING_SHA, true)
	engine._broadcast_game()
	return SUCCESS


## 把刚打完的攻击牌从弃牌堆取出来，面朝下放到自己角色旁作为【影】
func _把弃牌变成影(牌: int, cause: int) -> void:
	var 实例: int = engine.deck.取出实例(牌)
	if 实例 < 0:
		return
	notice_skill(cause, [player.id])
	engine.add_cover(player.id, [实例], player.id, cause, false)
	engine._broadcast_game()


## 影之风：挂着【风穴】的那个人每次【攻击行动】结束 → 女仆长 +1【糸】
## （专属技跟着卡走：「你」＝拥有【风穴】的人，卡不在场上就没这条被动）
func p_after_attack(ctx: Dictionary) -> int:
	if not 持有风穴(int(ctx.get("player", -1))):
		return SUCCESS
	if step == 0:
		step = 1
		player.add_token(糸槽, 1)
		engine._broadcast_game()
	return SUCCESS


## 瞬·影·杀生效期间：本回合你的主动攻击无法应战
func p_before_attack(ctx: Dictionary) -> int:
	if _本回合禁应战 and int(ctx.get("src", -1)) == player.id and bool(ctx.get("is_active", false)):
		ctx["hit_rate"] = GConst.HitRate.NoReattack
	return SUCCESS


func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_本回合禁应战 = false
		_本回合禁摹影 = false
		_瞬影杀已用 = false
		_摹影阶段 = 0
		_瞬影杀阶段 = 0
		_影牢阶段 = 0
	return SUCCESS


# ============================================================
# 影缝：持有【风穴】的对手回合开始时
# ============================================================
func p_turn_begin(ctx: Dictionary) -> int:
	if _影缝阶段 != 0:
		return _影缝()
	var 当前: int = int(ctx.get("player", -1))
	if 当前 != player.id and 持有风穴(当前) and player.token_num(糸槽) >= 1:
		_影缝目标 = 当前
		_影缝阶段 = 1
		return _影缝()
	return SUCCESS


func _影缝() -> int:
	if _影缝阶段 == 1:
		if not engine.has_reply():
			_询问影缝X()
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty():
			_影缝阶段 = 0
			return SUCCESS
		_影缝X = int(args[0])
		if _影缝X < 1 or _影缝X > player.token_num(糸槽):
			engine.报错("【影缝】提交的 X 不合法", player.id)
			_影缝阶段 = 0
			return SUCCESS
		player.remove_token(糸槽, _影缝X)
		notice_skill(YING_FENG, [_影缝目标])
		engine._broadcast_game()
		_影缝弃牌.clear()
		_影缝阶段 = 2
	if _影缝阶段 == 2:
		var dp: BattlePlayer = engine.p(_影缝目标)
		if dp == null:
			_影缝阶段 = 0
			return SUCCESS
		if not engine.has_reply():
			# 手牌不够 X 张时「有多少弃多少」：按手牌数收缩询问张数，
			# 否则客户端会卡在「凑不满 X 张不能确定」。
			# 实际弃牌数小于 X 仍按原规则让对方士气 -1（见下面结算）。
			var 要弃: int = mini(_影缝X, dp.hand_cards.size())
			if 要弃 > 0:
				engine.ask_respond(_影缝目标, GConst.RespondType.Discard,
					[_影缝目标, YING_FENG, 要弃], [_影缝目标])
				engine.wait_for(_影缝目标, GConst.Msg.Respond)
				return WAIT
			# 一张都没有：跳过弃牌，直接按「弃牌数小于 X」处理（没有弃牌可看，到这里就结束）
			_影缝阶段 = 0
			_影缝弃牌 = []
			engine.lose_morale(dp, 1, YING_FENG)
			engine._broadcast_game()
			return SUCCESS
		var r2: Dictionary = take_skill_reply_full()
		var cards: Array = r2.get("card_ids", [])
		var 可用: Array = []
		for c: Variant in cards:
			if dp.has_discard_card(int(c)) and not 可用.has(int(c)) and 可用.size() < _影缝X:
				可用.append(int(c))
		# 强制弃满 X 张：不够就按手牌顺序补
		for cid: int in dp.hand_cards:
			if 可用.size() >= _影缝X:
				break
			if not 可用.has(cid):
				可用.append(cid)
		_影缝弃牌 = 可用.duplicate()
		if 可用.size() < _影缝X:
			# 实际弃牌数小于 X：对方士气 -1
			engine.lose_morale(dp, 1, YING_FENG)
		engine.take_from_hand(_影缝目标, 可用)
		engine.to_discard(可用, {"owner": _影缝目标, "source": "hand", "cause": YING_FENG})
		engine._log_discard(_影缝目标, 可用, true)
		engine._broadcast_game()
		if 可用.is_empty():
			_影缝阶段 = 0
			return SUCCESS
		_影缝阶段 = 3
	if _影缝阶段 == 3:
		if _影缝弃牌.size() == 1:
			_影缝收入影(int(_影缝弃牌[0]))
			_影缝阶段 = 0
			return SUCCESS
		if not engine.has_reply():
			询问(player.id, YING_FENG, 0, 0, GConst.CardSource.Hand, _影缝挑牌选项(), 0, "", [], false,
				0, -1, [], -1, {})
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var args3: Array = r3.get("args", [])
		_影缝阶段 = 0
		if not args3.is_empty():
			var idx: int = int(args3[0])
			if idx >= 0 and idx < _影缝弃牌.size():
				_影缝收入影(int(_影缝弃牌[idx]))
	return SUCCESS


## 影缝的 X 选项（X<4，且不超过当前【糸】）
func _询问影缝X() -> void:
	var 上限: int = mini(3, player.token_num(糸槽))
	var out: Array = []
	for x: int in range(1, 4):
		out.append({
			"value": x,
			"label": GConst.按钮原文(YING_FENG, x - 1),
			"text": GConst.按钮原文(YING_FENG, x - 1),
			"enabled": x <= 上限,
		})
	询问(player.id, YING_FENG, 0, 0, GConst.CardSource.Hand, out, 0, "", [], true, 0, -1, [], -1, {})


## 影缝：从这些弃牌里挑 1 张（选项带 card_id，客户端悬停能摊出牌面）
func _影缝挑牌选项() -> Array:
	var out: Array = []
	for i: int in range(_影缝弃牌.size()):
		var cid: int = int(_影缝弃牌[i])
		var 牌: GCard = Data.get_card(cid)
		var 名: String = 牌.card_name if 牌 != null else ""
		out.append({
			"value": i,
			"label": "%s %s" % [名, GConst.element_to_chinese(牌.element_enum()) if 牌 != null else ""],
			"card_id": cid,
		})
	return out


## 从弃牌堆里取一张作为自己的【影】
func _影缝收入影(cid: int) -> void:
	var 实例: int = engine.deck.取出实例(cid)
	if 实例 < 0:
		return
	engine.add_cover(player.id, [实例], player.id, YING_FENG, false)
	engine._broadcast_game()


# ============================================================
# 侍奉之道：回合结束移 2 个影
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	var 谁: int = int(ctx.get("player", -1))
	if 谁 == player.id:
		# 她自己的回合结束：侍奉之道
		return _侍奉之道()
	# 别人的回合结束：只有「拥有【风穴】」的那个人（卡挂在他面前）才要跑风止
	if _风止阶段 != 0 or 持有风穴(谁):
		return _风止(谁)
	return SUCCESS


func _侍奉之道() -> int:
	# 跨段状态只在新的一次发动时初始化：第一段答完已经把两张【影】移出盖牌区，
	# 重入（等第二段回复）时盖牌数会不足 2，不能再拿它当入口门槛
	if not 多步询问进行中(SHI_FENG_ZHI_DAO):
		if player.cover_cards.size() < 2:
			return SUCCESS
		_侍奉同系 = false
	return 多步询问(SHI_FENG_ZHI_DAO, [
		# 第 1 段：选 2 个【影】（答完里展示、移出盖牌区、+1【糸】）
		{"需牌": 2, "来源": GConst.CardSource.Cover, "答完": _侍奉取影答完},
		# 第 2 段：同系才问「把哪一张交给谁」（选项在问的时候按 _侍奉牌 现造）
		{"选项": func(_答案: Array) -> Array: return _侍奉选项(), "需目标": 1, "可取消": false,
		 "跳过": func(_答案: Array) -> bool: return not _侍奉同系 or _侍奉牌.is_empty()},
	], _侍奉结算)


## 第 1 段答完：两张【影】展示 + 移出盖牌区 + +1【糸】；不同系就直接都进弃牌堆，不再问交给谁
func _侍奉取影答完(回: Dictionary, _答案: Array) -> int:
	var args1: Array = 回.get("args", [])
	# 旧实现只认 args[0] == 1（take_skill_reply 口径）：构造客户端回 [0] 不能照样把两张影移出盖牌区
	if args1.is_empty() or int(args1[0]) != 1:
		return SUCCESS
	var cards: Array = 回.get("cards", [])
	if cards.size() != 2:
		return SUCCESS
	var 甲: int = player.盖牌实例(int(cards[0]))
	var 乙: int = player.盖牌实例(int(cards[1]))
	if 甲 < 0 or 乙 < 0 or 甲 == 乙:
		return SUCCESS
	var 甲牌: GCard = Data.get_card(甲)
	var 乙牌: GCard = Data.get_card(乙)
	if 甲牌 == null or 乙牌 == null:
		return SUCCESS
	notice_skill(SHI_FENG_ZHI_DAO, [player.id])
	# 这两张是盖牌区的【影】（不是从手里展示出来的），只广播、不压展示钩子
	engine.展示牌(player.id, [甲, 乙])
	engine.remove_cover(player.id, [甲, 乙], player.id, SHI_FENG_ZHI_DAO)
	player.add_token(糸槽, 1)
	_侍奉牌 = [甲, 乙]
	# 这两张是盖牌区的【影】（不是从手中展示出），封印类「从手中展示出」不触发
	engine._broadcast_game()
	if 甲牌.element_enum() != 乙牌.element_enum():
		# 系别不同：没有「交给谁」这一步，两张影都进弃牌堆（原来会凭空消失）
		_侍奉弃掉两张()
		return SUCCESS
	_侍奉同系 = true
	return SUCCESS


## 第 2 段答完：把选中的那张交给目标角色，另一张进弃牌堆；横置
func _侍奉结算(答案: Array) -> int:
	if not _侍奉同系 or 答案.size() < 2:
		_侍奉牌 = []
		return SUCCESS
	var args: Array = (答案[1] as Dictionary).get("args", [])
	var dsts: Array = (答案[1] as Dictionary).get("dsts", [])
	if args.is_empty() or dsts.is_empty():
		_侍奉弃掉两张()
		return SUCCESS
	var 选: int = int(args[0])
	var dst: int = int(dsts[0])
	var dp: BattlePlayer = engine.p(dst)
	if dp == null or 选 < 1 or 选 > _侍奉牌.size():
		engine.报错("【侍奉之道】提交的参数不合法", player.id)
		_侍奉弃掉两张()
		return SUCCESS
	var 给: int = int(_侍奉牌[选 - 1])
	var 另一: int = int(_侍奉牌[0]) if 选 == 2 else int(_侍奉牌[1])
	dp.add_hand_cards([给])
	engine.播获得牌日志(dst, [给])
	engine.to_discard([另一], {"owner": player.id, "source": "cover", "cause": SHI_FENG_ZHI_DAO})
	_侍奉牌 = []
	player.tap = true
	engine._broadcast_game()
	return SUCCESS


## 两张【影】都没交出去：进弃牌堆，不留死牌
func _侍奉弃掉两张() -> void:
	if not _侍奉牌.is_empty():
		engine.to_discard(_侍奉牌, {"owner": player.id, "source": "cover", "cause": SHI_FENG_ZHI_DAO})
		engine._log_discard(player.id, _侍奉牌, false)
		_侍奉牌 = []
	engine._broadcast_game()


## 同系时选「哪一张交给谁」：选项＝交给哪张影，目标＝任意角色
func _侍奉选项() -> Array:
	var out: Array = []
	for i: int in range(_侍奉牌.size()):
		var cid: int = int(_侍奉牌[i])
		var 牌: GCard = Data.get_card(cid)
		var 文案: String = "%s %s" % [牌.card_name if 牌 != null else "",
			GConst.element_to_chinese(牌.element_enum()) if 牌 != null else ""]
		out.append({
			"value": i + 1,
			"label": 文案,
			"card_id": cid,
			"need_target": 1,
			"targets": 全部角色(),
		})
	return out


# ============================================================
# 禁术·影牢：其他角色【特殊行动】结束时
# ============================================================
func p_after_special(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		return SUCCESS
	# 只认真正的【特殊行动】（购买 / 合成 / 提炼）：ctx.special_action 由 _do_special 写。
	# 「启动」技能也走 p_after_special，但它不是特殊行动（如魔弓的启动技不该让影牢发动）。
	if not bool(ctx.get("special_action", false)):
		return SUCCESS
	# 【禁术·影牢】是响应：先问发不发动（+1【糸】属于发动效果，不再自动加）
	if _影牢阶段 == 0:
		_影牢阶段 = 1
		询问(player.id, JIN_SHU_YING_LAO, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _影牢阶段 != 1:
		return SUCCESS
	var r: Dictionary = take_skill_reply_full()
	_影牢阶段 = 0
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(JIN_SHU_YING_LAO, [player.id])
	player.add_token(糸槽, 1)
	engine._broadcast_game()
	if not player.tap or player.token_num(糸槽) < 3:
		return SUCCESS
	# 第二段（移除 3 点【糸】+ 重置 + 打 2 / 令队友弃 1）要延后一拍再问：
	# 上面 +1【糸】的播报得先发出去，否则界面看上去「没加糸却可以移除 3 糸」。
	# 这里只 push 一个下一拍的钩子并返回 SUCCESS —— 本钩子轮次跑完后引擎才会结算
	# 指示物变化（_check_token_change 只在 CONTINUE 时跑），播报先发，随后才弹询问。
	_影牢阶段 = 2
	engine.push(BattleEngine.SHook.new("p_影牢续", {}, []))
	return SUCCESS


## 影牢第二段的「下一拍」：+1【糸】的播报已经发出去，这时才弹效果 / 目标询问
func p_影牢续(_ctx: Dictionary) -> int:
	if _影牢阶段 == 2:
		_影牢阶段 = 3
		询问(player.id, JIN_SHU_YING_LAO, 0, 0, GConst.CardSource.Hand, _影牢选项(), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _影牢阶段 == 3:
		_影牢阶段 = 0
		return _影牢结算(take_skill_reply_full())
	return SUCCESS


## 影牢第二段结算：移除 3【糸】、重置，然后对目标对手 2 点法术伤害 或 指定目标队友弃 1 张
func _影牢结算(r: Dictionary) -> int:
	var args: Array = r.get("args", [])
	if args.is_empty():
		return SUCCESS
	var 选择: int = int(args[0])
	var dsts: Array = r.get("dst_ids", [])
	var dst: int = int(dsts[0]) if not dsts.is_empty() else -1
	var dp: BattlePlayer = engine.p(dst)
	var 合法: bool = dp != null and (dp.color != player.color if 选择 == 1 else dp.color == player.color)
	if not 合法:
		engine.报错("【禁术·影牢】提交的目标不合法", player.id)
		return SUCCESS
	player.remove_token(糸槽, 3)
	player.tap = false
	if 选择 == 1:
		engine.push_harm({"src": player.id, "dst": dst, "point": 2,
			"cause": JIN_SHU_YING_LAO, "type": GConst.HarmType.Magic})
		return URGENT
	engine.push(BattleEngine.SRequestDiscard.new(dst, 1, 0, JIN_SHU_YING_LAO))
	return URGENT

func _影牢选项() -> Array:
	return [
		{
			"value": 1,
			"label": GConst.按钮原文(JIN_SHU_YING_LAO, 0),
			"text": GConst.按钮原文(JIN_SHU_YING_LAO, 0),
			"need_target": 1,
			"targets": 敌人(),
		},
		{
			"value": 2,
			"label": GConst.按钮原文(JIN_SHU_YING_LAO, 1),
			"text": GConst.按钮原文(JIN_SHU_YING_LAO, 1),
			"need_target": 1,
			"targets": 队友(),
		},
	]


# ============================================================
# 风止：拥有【风穴】时，回合结束可发动
# ============================================================
## 风止：拥有【风穴】的那个人（卡挂在他面前）回合结束时发动 ——
## 他的手牌补到上限【强制】→ 弃 2 张 → 弃牌面朝下作为女仆长的【影】→ 移除【风穴】。
## 「响应者」是持有【风穴】的人，不是女仆长自己；补手牌 / 弃牌都作用在他的手牌上。
## 风止：拥有【风穴】的那个人（卡挂在他面前）回合结束时**先问他发不发动** ——
## 发动才有效果：他的手牌补到上限【强制】→ 弃 2 张 → 弃牌面朝下作为女仆长的【影】→ 移除【风穴】。
## 不发动 / 取消：什么都不发生，【风穴】留在原处。
## 「响应者」是持有【风穴】的人，不是女仆长自己；补手牌 / 弃牌都作用在他的手牌上。
func _风止(host: int) -> int:
	var hp: BattlePlayer = engine.p(host)
	if hp == null:
		_风止阶段 = 0
		return SUCCESS
	if _风止阶段 == 0:
		_风止阶段 = 1
		询问(host, FENG_ZHI, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true, 0, -1, [], -1, {})
		return WAIT
	if _风止阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		_风止阶段 = 0
		if args.is_empty() or int(args[0]) != 1:
			return SUCCESS
		notice_skill(FENG_ZHI, [host])
		_风止阶段 = 2
		var 需: int = maxi(hp.hand_cards_max - hp.hand_cards.size(), 0)
		if 需 > 0:
			engine.push_强制摸牌(host, 需, FENG_ZHI)
			return URGENT
	if _风止阶段 == 2:
		var 要弃: int = mini(2, hp.hand_cards.size())
		if 要弃 <= 0:
			_风止阶段 = 0
			engine.移除场卡(风穴名)
			engine._broadcast_game()
			return SUCCESS
		_风止阶段 = 3
		engine.ask_respond(host, GConst.RespondType.Discard, [host, FENG_ZHI, 要弃], [host])
		engine.wait_for(host, GConst.Msg.Respond)
		return WAIT
	if _风止阶段 == 3:
		var r2: Dictionary = take_skill_reply_full()
		_风止阶段 = 0
		var 弃: Array = []
		for c: Variant in r2.get("card_ids", []):
			var 实例: int = hp.手牌实例(int(c))
			if 实例 >= 0 and not 弃.has(实例) and 弃.size() < 2:
				弃.append(实例)
		# 强制弃 2 张：不够就按手牌顺序补
		for cid: int in hp.hand_cards:
			if 弃.size() >= 2:
				break
			if not 弃.has(cid):
				弃.append(cid)
		if not 弃.is_empty():
			# 两张都面朝下变【影】；超出盖牌上限的部分由引擎「盖牌超限」询问让玩家自己选着弃
			engine.take_from_hand(host, 弃)
			engine.add_cover(player.id, 弃, player.id, FENG_ZHI, false)
		engine.移除场卡(风穴名)
		engine._broadcast_game()
		return SUCCESS
	_风止阶段 = 0
	return SUCCESS

# ============================================================
# 小工具
# ============================================================
## 【风穴】现在挂在谁面前（没人持有返回 -1）
func 持有风穴者() -> int:
	var 表: Dictionary = engine.取场卡(风穴名)
	return int(表.get("attached", -1)) if not 表.is_empty() else -1


## 影之穴能放的目标：对手，且不能是【风穴】现在挂着的那个人
func _影之穴可选目标() -> Array:
	var 当前: int = 持有风穴者()
	var out: Array = []
	for pid: int in 敌人():
		if pid != 当前:
			out.append(pid)
	return out

## 场上有没有【风穴】（不论挂在谁面前）
func 拥有风穴() -> bool:
	return engine.有场卡(风穴名)


## 【风穴】是不是挂在这名玩家面前
func 持有风穴(pid: int) -> bool:
	var 表: Dictionary = engine.取场卡(风穴名)
	return not 表.is_empty() and int(表.get("attached", -1)) == pid


func 敌人() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color:
			out.append(pid)
	return out


func 队友() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color == player.color and p0.id != player.id:
			out.append(pid)
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

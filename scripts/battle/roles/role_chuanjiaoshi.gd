extends BattleRole
## 传教士（roleID 96）
##
## 【路标】＝挂在角色面前的场卡（owner 始终是传教士）；【虔诚】＝0 号指示物（上限 4）。
## 左右手约定：座位链的 post_id 是右手边下家、pre_id 是左手边上家。
##
## 技能：
##   神的门徒 9601（被动）：你无法成为【路标】的目标【恒定】。2V2 中无效。
##       （「行动顺序改为拥有【路标】的角色之后」需要改全局座位顺序，本轮未实现）
##   信仰之路 9602（被动）：你的第一回合开始把【路标】放到你左手边最近的角色面前；
##       你的回合结束若本回合未执行【特殊行动】，把【路标】转移到持有者左手边最近的角色面前。
##   传道 9603（启动）：摸 0~1 张牌、弃 1 张牌【展示】，你 +1【虔诚】；持有【路标】的角色弃 1 张牌
##       【展示】，你获得该牌【强制】；若该牌与你弃牌的系别或命格相同，你 +1【虔诚】。
##   启示 9604（响应）：【路标】转移前，移除 2 点【虔诚】→ 二选一：目标角色 +1【治疗】；
##       或你摸 1 张牌【强制】【展示】（若该牌为法术牌或圣类命格）取消本次转移、移除【路标】，
##       然后把【路标】放到目标角色面前。
##   事奉 9605（响应）：你因自身技能弃的牌置入弃牌堆时，移除你 1【治疗】→ 把该弃牌加入
##       拥有【路标】的角色手牌【强制】。
##       （「若没有因此造成士气下降 → 指定角色 +1 治疗」本轮未实现）
##   路标 9606（告解式，响应【回合限定】）：此卡被转移至你面前时，你摸 2 张牌【强制】，
##       我方【战绩区】+1【水晶】，然后把此卡转移至你左手边最近的角色面前，传教士弃 1 张牌。
##   属灵恩赐 9607（启动·必杀【水晶】）：你 +1【治疗】，弃 1 张牌。
##   弥撒 9608（响应·必杀【水晶】）：【路标】转移或放置后，你 +1【虔诚】，二选一：
##       弃 1 张牌【展示】，（若为【虚弱】/【中毒】/【圣盾】）放到持有【路标】的角色面前作为基础效果；
##       或（把持有【路标】的角色面前 1 张基础效果牌收入自己手中）你 +1【虔诚】。

const SHEN_DE_MEN_TU: int = 9601
const XIN_YANG_ZHI_LU: int = 9602
const CHUAN_DAO: int = 9603
const QI_SHI: int = 9604
const SHI_FENG: int = 9605
const LU_BIAO: int = 9606
const SHU_LING_EN_CI: int = 9607
const MI_SA: int = 9608

const 虔诚槽: int = 0
const 路标名: String = "路标"

var _首回合已放: bool = false
var _告解已用: bool = false
## 路标放置后的后续（告解 / 弥撒）阶段：0＝无 / 1＝告解摸牌 / 2＝告解收尾 / 3＝弥撒
var _路标阶段: int = 0
var _路标持有者: int = -1
## 传道：1＝等选摸几张 / 2＝等弃自己的牌 / 3＝等持有者弃牌
var _传道阶段: int = 0
var _传道摸: int = 0
var _传道弃: int = -1
## 启示：转移前的可选响应（0＝未开始 / 1＝等选效果 / 2＝等选目标 / 3＝等看摸到的牌）
var _转移阶段: int = 0
var _转移目标: int = -1
var _启示分支: int = 1
var _启示目标: int = -1
var _启示摸前: Array = []


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": CHUAN_DAO,
			"need_card": 0,
			"need_target": 0,
			"enabled": true,
		},
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": SHU_LING_EN_CI,
			"need_card": 1,
			"need_target": 0,
			"enabled": player.get_energy() >= 1 and not player.hand_cards.is_empty(),
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == CHUAN_DAO or skill_id == SHU_LING_EN_CI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == SHU_LING_EN_CI:
		if player.get_energy() < 1 or player.hand_cards.is_empty():
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if 技能号 == CHUAN_DAO:
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_special_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == SHU_LING_EN_CI:
		return _属灵恩赐(action)
	if 技能号 == CHUAN_DAO:
		return _传道()
	return SUCCESS


# ============================================================
# 属灵恩赐：水晶 → +1 治疗、弃 1 张
# ============================================================
func _属灵恩赐(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	player.boot_skill_used = true
	notice_skill(SHU_LING_EN_CI, [player.id])
	player.remove_energy(1)
	施加治疗(player.id, 1)
	var 弃: Array = []
	for c: Variant in cards:
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0 and not 弃.has(实例):
			弃.append(实例)
	engine.take_from_hand(player.id, 弃)
	engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": SHU_LING_EN_CI})
	engine._log_discard(player.id, 弃)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 传道（启动）：摸 0~1、弃 1【展示】；持有者弃 1，你获得该牌；同系/同命格再 +1 虔诚
# ============================================================
func _传道() -> int:
	if _传道阶段 == 0:
		# 「启动」技能：本回合只能发动一个（引擎只校验这个标记）
		player.boot_skill_used = true
		_传道阶段 = 1
		询问(player.id, CHUAN_DAO, 0, 0, GConst.CardSource.Hand, _传道摸牌选项(), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _传道阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty():
			_传道阶段 = 0
			return SUCCESS
		_传道摸 = int(args[0])
		_传道阶段 = 2
		if _传道摸 > 0:
			engine.push_强制摸牌(player.id, _传道摸, CHUAN_DAO)
			return URGENT
	if _传道阶段 == 2:
		if not engine.has_reply():
			_传道阶段 = 3
			engine.ask_respond(player.id, GConst.RespondType.Discard, [player.id, CHUAN_DAO, 1], [player.id])
			engine.wait_for(player.id, GConst.Msg.Respond)
			return WAIT
	if _传道阶段 == 3:
		var r2: Dictionary = take_skill_reply_full()
		var cards: Array = r2.get("card_ids", [])
		var 弃: int = _取一张(cards, player)
		if 弃 < 0:
			_传道阶段 = 0
			return SUCCESS
		_传道弃 = 弃
		notice_skill(CHUAN_DAO, [player.id])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [弃], "is_real": true,
		})
		engine.take_from_hand(player.id, [弃])
		engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": CHUAN_DAO})
		engine._log_discard(player.id, [弃], false)
		player.add_token(虔诚槽, 1)
		engine._broadcast_game()
		_传道阶段 = 4
		var 持有者: int = 路标持有者()
		if 持有者 < 0 or 持有者 == player.id or engine.p(持有者) == null:
			_传道阶段 = 0
			return SUCCESS
		engine.ask_respond(持有者, GConst.RespondType.Discard, [持有者, CHUAN_DAO, 1], [持有者])
		engine.wait_for(持有者, GConst.Msg.Respond)
		return WAIT
	# 阶段 4：持有者弃的那张牌归你
	var r3: Dictionary = take_skill_reply_full()
	var cards3: Array = r3.get("card_ids", [])
	var 持有者2: int = 路标持有者()
	_传道阶段 = 0
	if 持有者2 < 0 or engine.p(持有者2) == null:
		return SUCCESS
	var 得: int = _取一张(cards3, engine.p(持有者2))
	if 得 < 0:
		return SUCCESS
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": 持有者2, "dst_id": 持有者2,
		"card_ids": [得], "is_real": true,
	})
	engine.take_from_hand(持有者2, [得])
	player.add_hand_cards([得])
	engine.播获得牌日志(player.id, [得])
	# 与你弃掉的牌同系别或同命格 → 额外 +1 虔诚
	var 我: GCard = Data.get_card(_传道弃)
	var 他: GCard = Data.get_card(得)
	if 我 != null and 他 != null and (我.element_enum() == 他.element_enum() \
			or 我.fate_pattern_enum() == 他.fate_pattern_enum()):
		player.add_token(虔诚槽, 1)
	engine._broadcast_game()
	return SUCCESS


func _传道摸牌选项() -> Array:
	return [
		{"value": 0, "label": GConst.按钮原文(CHUAN_DAO, 0), "text": GConst.按钮原文(CHUAN_DAO, 0)},
		{"value": 1, "label": GConst.按钮原文(CHUAN_DAO, 1), "text": GConst.按钮原文(CHUAN_DAO, 1)},
	]


## 从回复里认一张持有者手牌（超时按手牌第一张；没有手牌返回 -1）
func _取一张(cards: Array, 主人: BattlePlayer) -> int:
	for c: Variant in cards:
		if 主人.has_discard_card(int(c)):
			return int(c)
	if not 主人.hand_cards.is_empty():
		return int(主人.hand_cards[0])
	return -1


# ============================================================
# 信仰之路：第一回合放路标；回合结束（未执行特殊行动）转移路标
# ============================================================
func p_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_告解已用 = false
	if _弥撒阶段 != 0:
		return _弥撒()
	if _路标阶段 != 0:
		return _路标后续()
	if not _首回合已放:
		var 左: int = 左手边(player.id)
		if 左 >= 0 and 左 != player.id:
			_首回合已放 = true
			return _放置路标(左)
	return SUCCESS


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _弥撒阶段 != 0:
		return _弥撒()
	if _路标阶段 != 0:
		return _路标后续()
	if player.action_count_of("special") > 0:
		return SUCCESS
	var 持有者: int = 路标持有者()
	if 持有者 < 0:
		return SUCCESS
	var 左: int = 左手边(持有者)
	if 左 < 0 or 左 == 持有者:
		return SUCCESS
	return _转移路标(左)


# ============================================================
# 路标放置 / 转移：放置后依次跑【告解式】与【弥撒】
# ============================================================
func _放置路标(目标: int) -> int:
	if _路标阶段 != 0:
		return _路标后续()
	if 目标 == player.id:
		# 神的门徒：传教士自己不能成为【路标】的目标
		return SUCCESS
	engine.加场卡({"id": 路标名, "owner": player.id, "attached": 目标})
	_路标持有者 = 目标
	engine._broadcast_game()
	_路标阶段 = 1
	return _路标后续()


## 把【路标】转移到某人面前（保留 owner）
func _路标放下(目标: int) -> void:
	engine.加场卡({"id": 路标名, "owner": player.id, "attached": 目标})
	_路标持有者 = 目标
	engine._broadcast_game()


## 路标到达之后的后续：先【告解式】9606，再【弥撒】9608
## 阶段：1＝告解式摸牌 / 2＝告解式传牌与传教士弃牌 / 3＝弥撒
func _路标后续() -> int:
	if _路标阶段 == 1:
		var 到: int = 路标持有者()
		if _告解已用 or 到 < 0 or 到 == player.id:
			_路标阶段 = 3
			return _路标后续()
		_告解已用 = true
		notice_skill(LU_BIAO, [到])
		_路标阶段 = 2
		engine.push_强制摸牌(到, 2, LU_BIAO)
		return URGENT
	if _路标阶段 == 2:
		# 我方【战绩区】+1【水晶】→ 此卡转移到到达者左手边 → 传教士弃 1 张牌
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
		var 到2: int = 路标持有者()
		var 左: int = 左手边(到2)
		if 左 >= 0 and 左 != player.id and 左 != 到2:
			_路标放下(左)
		_路标阶段 = 3
		if player.hand_cards.is_empty():
			return _路标后续()
		engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, LU_BIAO))
		return URGENT
	if _路标阶段 == 3:
		_路标阶段 = 0
		if player.get_energy() < 1:
			return SUCCESS
		return _弥撒()
	_路标阶段 = 0
	return SUCCESS


# ============================================================
# 弥撒 9608（响应·必杀【水晶】）：路标转移/放置后，+1 虔诚，二选一
# ============================================================
## 0＝未问 / 1＝等选效果 / 2＝等选收入哪张基础效果
var _弥撒阶段: int = 0


func _弥撒() -> int:
	if _弥撒阶段 == 0:
		_弥撒阶段 = 1
		询问(player.id, MI_SA, 0, 0, GConst.CardSource.Hand, _弥撒选项(), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _弥撒阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var cards: Array = r.get("card_ids", [])
		_弥撒阶段 = 0
		if args.is_empty():
			return SUCCESS
		var 持有: int = 路标持有者()
		var dp: BattlePlayer = engine.p(持有)
		player.remove_energy(1)
		player.add_token(虔诚槽, 1)
		notice_skill(MI_SA, [持有])
		engine._broadcast_game()
		if int(args[0]) == 1:
			# ·弃 1 张牌【展示】；（若为【虚弱】/【中毒】/【圣盾】）放到持有者面前作为基础效果
			var 弃: int = -1
			for c: Variant in cards:
				var 实例: int = player.手牌实例(int(c))
				if 实例 >= 0:
					弃 = 实例
					break
			if 弃 < 0:
				return SUCCESS
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": [弃], "is_real": true,
			})
			engine.take_from_hand(player.id, [弃], true)
			var 牌: GCard = Data.get_card(弃)
			if dp != null and 牌 != null and _是基础效果牌(牌):
				engine.add_basic_effect(持有, 弃, player.id, MI_SA)
			else:
				engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": MI_SA})
				engine._log_discard(player.id, [弃], false)
			engine._broadcast_game()
			return SUCCESS
		# ·把持有者面前 1 张基础效果收入手中，你 +1【虔诚】
		if dp == null:
			return SUCCESS
		var 可选: Array = _基础效果列表(dp)
		if 可选.is_empty():
			return SUCCESS
		player.add_token(虔诚槽, 1)
		if 可选.size() == 1:
			_收入基础效果(dp.id, int(可选[0]))
			return SUCCESS
		_弥撒阶段 = 2
		询问(player.id, MI_SA, 0, 0, GConst.CardSource.Hand, _收入选项(可选), 0, "", [], false,
			0, -1, [], -1, {})
		return WAIT
	# 阶段 2：从多张基础效果里选一张
	var r2: Dictionary = take_skill_reply_full()
	var args2: Array = r2.get("args", [])
	_弥撒阶段 = 0
	if args2.is_empty():
		return SUCCESS
	var 持有2: int = 路标持有者()
	var dp2: BattlePlayer = engine.p(持有2)
	if dp2 == null:
		return SUCCESS
	var 表: Array = _基础效果列表(dp2)
	var 序: int = int(args2[0]) - 1
	if 序 < 0 or 序 >= 表.size():
		engine.报错("【弥撒】选项号越界", player.id)
		return SUCCESS
	_收入基础效果(持有2, int(表[序]))
	return SUCCESS


func _弥撒选项() -> Array:
	var 持有: int = 路标持有者()
	var dp: BattlePlayer = engine.p(持有)
	var 有基础: bool = dp != null and not _基础效果列表(dp).is_empty()
	return [
		{
			"value": 1,
			"label": GConst.按钮原文(MI_SA, 0),
			"text": GConst.按钮原文(MI_SA, 0),
			"need_card": 1 if not player.hand_cards.is_empty() else 0,
			"enabled": not player.hand_cards.is_empty(),
		},
		{
			"value": 2,
			"label": GConst.按钮原文(MI_SA, 1),
			"text": GConst.按钮原文(MI_SA, 1),
			"enabled": 有基础,
		},
	]


## 持有者面前的基础效果牌（跳过 Tricky 占位，避免与捣蛋萝莉的脚本状态脱节）
func _基础效果列表(dp: BattlePlayer) -> Array:
	var out: Array = []
	for be: Dictionary in dp.basic_effects:
		if int(be["card"]) != 1008:
			out.append(int(be["card"]))
	return out


func _收入选项(表: Array) -> Array:
	var out: Array = []
	for i: int in range(表.size()):
		var 牌: GCard = Data.get_card(int(表[i]))
		var 文案: String = 牌.card_name if 牌 != null else ""
		out.append({"value": i + 1, "label": 文案, "text": 文案, "card_id": int(表[i])})
	return out


func _收入基础效果(持有: int, 牌: int) -> void:
	var dp: BattlePlayer = engine.p(持有)
	if dp == null:
		return
	engine.remove_basic_effect(持有, 牌, MI_SA, player.id)
	player.add_hand_cards([牌])
	engine.播获得牌日志(player.id, [牌])
	engine._broadcast_game()


## 【虚弱】/【中毒】/【圣盾】：这三张是「放到角色面前」的基础效果牌
func _是基础效果牌(牌: GCard) -> bool:
	match 牌.card_name_enum():
		GConst.CardName.Shield, GConst.CardName.Weaken, GConst.CardName.Poison:
			return true
	return false


## 转移＝先跑【启示】（可选，移 2 虔诚），再放置路标
func _转移路标(目标: int) -> int:
	if _路标阶段 != 0:
		return _路标后续()
	if _转移阶段 == 0:
		_转移目标 = 目标
		if player.token_num(虔诚槽) >= 2:
			_转移阶段 = 1
			询问(player.id, QI_SHI, 0, 0, GConst.CardSource.Hand, _启示选项(), 0, "", [], true,
				0, -1, [], -1, {})
			return WAIT
		return _放置路标(目标)
	if _转移阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty():
			_转移阶段 = 0
			return _放置路标(_转移目标)
		player.remove_token(虔诚槽, 2)
		notice_skill(QI_SHI, [player.id])
		_启示分支 = int(args[0])
		_转移阶段 = 2
		询问(player.id, QI_SHI, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, 全部角色(), -1, {}, 1, GConst.预览类型_治疗)
		return WAIT
	if _转移阶段 == 2:
		var r2: Dictionary = take_skill_reply_full()
		var dsts: Array = r2.get("dst_ids", [])
		_启示目标 = int(dsts[0]) if not dsts.is_empty() else -1
		if _启示目标 < 0 or engine.p(_启示目标) == null:
			_转移阶段 = 0
			return SUCCESS
		if _启示分支 == 1:
			_转移阶段 = 0
			施加治疗(_启示目标, 1)
			engine._broadcast_game()
			return _放置路标(_转移目标)
		_转移阶段 = 3
		_启示摸前 = player.hand_cards.duplicate()
		engine.push_强制摸牌(player.id, 1, QI_SHI)
		return URGENT
	# 阶段 3：看这次摸到的牌是不是法术牌 / 圣类命格
	_转移阶段 = 0
	var 新牌: int = -1
	for c: Variant in player.hand_cards:
		if not _启示摸前.has(int(c)):
			新牌 = int(c)
			break
	var 牌: GCard = Data.get_card(新牌) if 新牌 >= 0 else null
	if 新牌 >= 0:
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [新牌], "is_real": true,
		})
	if 牌 != null and (牌.is_magic() or 牌.fate_pattern_enum() == GConst.FatePattern.Holy):
		# 取消本次转移：移除【路标】，改放到启示选中的目标面前
		engine.移除场卡(路标名)
		engine.加场卡({"id": 路标名, "owner": player.id, "attached": _启示目标})
		_路标持有者 = _启示目标
		engine._broadcast_game()
		return SUCCESS
	return _放置路标(_转移目标)


func _启示选项() -> Array:
	return [
		{"value": 1, "label": GConst.按钮原文(QI_SHI, 0), "text": GConst.按钮原文(QI_SHI, 0)},
		{"value": 2, "label": GConst.按钮原文(QI_SHI, 1), "text": GConst.按钮原文(QI_SHI, 1)},
	]


# ============================================================
# 事奉：因自身技能弃牌时，移除 1 治疗把该牌交给路标持有者
# ============================================================
## 只有 wants_before_discard 返回 true，引擎才会推迟这次弃牌、跑下面的 p_before_discard
func wants_before_discard(ctx: Dictionary) -> bool:
	if int(ctx.get("owner", -1)) != player.id:
		return false
	if str(ctx.get("source", "")) != "hand":
		return false
	if not [CHUAN_DAO, SHU_LING_EN_CI, MI_SA].has(int(ctx.get("cause", 0))):
		return false
	if player.cross_num <= 0:
		return false
	var 持有者: int = 路标持有者()
	return 持有者 >= 0 and 持有者 != player.id


func p_before_discard(ctx: Dictionary) -> int:
	if int(ctx.get("owner", -1)) != player.id:
		return SUCCESS
	if str(ctx.get("source", "")) != "hand":
		return SUCCESS
	if not [CHUAN_DAO, SHU_LING_EN_CI, MI_SA].has(int(ctx.get("cause", 0))):
		return SUCCESS
	if player.cross_num <= 0:
		return SUCCESS
	var 持有者: int = 路标持有者()
	if 持有者 < 0 or 持有者 == player.id:
		return SUCCESS
	var 键: String = "_事奉_%d" % int(ctx.get("cause", 0))
	if bool(ctx.get(键, false)):
		return SUCCESS
	ctx[键] = true
	var 取: Array = []
	for c: Variant in ctx.get("cards", []):
		取.append(int(c))
	if 取.is_empty():
		return SUCCESS
	ctx["taken"] = 取
	ctx["taker"] = 持有者
	player.sub_cross_num(1)
	notice_skill(SHI_FENG, [持有者])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 小工具
# ============================================================
## 左手边最近的玩家（座位链的 pre_id）；找不到返回 -1
func 左手边(pid: int) -> int:
	var p0: BattlePlayer = engine.p(pid)
	if p0 == null:
		return -1
	return p0.pre_id


func 路标持有者() -> int:
	var 表: Dictionary = engine.取场卡(路标名)
	if 表.is_empty():
		return -1
	return int(表.get("attached", -1))


## 除自己以外的全部在场角色（神之门徒：路标不能放在传教士自己面前）
func 除自己() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if pid != player.id:
			out.append(pid)
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

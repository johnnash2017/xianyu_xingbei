extends BattleRole
## 记录者（roleID 94）
##
## 【遗迹】＝角色旁面朝上的牌（盖牌区，open=true，上限 8）；【史料】＝0 号指示物（上限 3）；
## 【史书】＝卡表#1007（地系·幻类命格攻击牌，用掉 / 弃掉就移出游戏）。
##
## 技能：
##   传说之地 9401（被动）：开局把牌库顶 3 张面朝上放在角色旁作为【遗迹】。
##   知行合一 9402（法术）：展示牌库顶 2 张，你选 1 张并弃 1 张手牌；选中的牌加入手牌并获得一次
##       「只能用这张牌」的对应行动；其余展示牌弃掉，你 +X【史料】。
##   稽古识典 9403（被动）：【史料】满时移除所有【史料】，你弃 1 张牌，把【史书】加入手牌【强制】。
##   遗迹论破 9404（响应【回合限定】）：主动攻击①，移除与攻击牌同系的 X 个【遗迹】→
##       本次攻击伤害 +（X-1）；（若 X>1）额外 +1【法术行动】；（若遗迹因此为 0）我方【战绩区】+1【宝石】。
##   选淬精炼 9405（被动）：光系与暗系的【遗迹】视为任意系别。
##   秘境万象 9406（法术）：移除【史书】与所有【遗迹】，展示牌库顶牌直到出现同系的两张；
##       展示的 X 张都作为【遗迹】；（若 X>3）对（X-3）名目标角色各 2 点法术伤害③。
##   以史为镜 9407（被动）：【史书】视为地系幻类命格攻击牌；被使用 / 打出 / 弃置时移出游戏。
##   古今互鉴 9408（启动·必杀【水晶】）：你 +2【史料】；（若手牌 >1）可将 2 张手牌与 X 个【遗迹】交换，X>0。
##   引稽编鉴 9409（响应）：使用【史书】进行主动攻击①，指定攻击目标将 1 张手牌加入【遗迹】，
##       然后将你手上 X 张牌与 X 个【遗迹】交换，X<3。

const CHUAN_SHUO_ZHI_DI: int = 9401
const ZHI_XING_HE_YI: int = 9402
const JI_GU_SHI_DIAN: int = 9403
const YI_JI_LUN_PO: int = 9404
const XUAN_CUI_JING_LIAN: int = 9405
const MI_JING_WAN_XIANG: int = 9406
const YI_SHI_WEI_JING: int = 9407
const GU_JIN_HU_JIAN: int = 9408
const YIN_JI_BIAN_JIAN: int = 9409

const 史料槽: int = 0
const 史书号: int = 1007

var _遗迹论破已用: bool = false
var _遗迹论破同系: Array = []
var _知行牌: Array = []
var _知行阶段: int = 0
var _秘境阶段: int = 0
var _秘境X: int = 0
var _引稽阶段: int = 0
var _引稽目标: int = -1


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【传说之地】：牌库顶 3 张面朝上作为【遗迹】
	var cards: Array[int] = engine.deck.remove_top(3)
	if not cards.is_empty():
		engine.add_cover(player.id, cards, player.id, CHUAN_SHUO_ZHI_DI, true)
		engine.展示牌库顶(player.id, cards, false)
		engine._broadcast_game()


# ============================================================
# 技能栏：古今互鉴（启动·必杀）
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": ZHI_XING_HE_YI,
			"need_card": 0,
			"need_target": 0,
			"enabled": engine.deck.pile_size() > 0 and not player.hand_cards.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": MI_JING_WAN_XIANG,
			"need_card": 0,
			"need_target": 0,
			"enabled": _史书在手(),
		},
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": GU_JIN_HU_JIAN,
			"need_card": 0,
			"need_target": 0,
			"enabled": player.get_energy() >= 1,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == GU_JIN_HU_JIAN


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != GU_JIN_HU_JIAN:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != GU_JIN_HU_JIAN:
		return GConst.GE_INVALID_ACTION
	if _古今阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		_古今阶段 = 0
		return _古今交换(r)
	player.boot_skill_used = true
	notice_skill(GU_JIN_HU_JIAN, [player.id])
	player.remove_energy(1)
	player.add_token(史料槽, 2)
	engine._broadcast_game()
	_检查稽古()
	if player.hand_cards.size() > 1 and _遗迹数() > 0:
		_古今阶段 = 1
		询问(player.id, GU_JIN_HU_JIAN, 2, 0, GConst.CardSource.Hand, _交换选项(GU_JIN_HU_JIAN), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	return SUCCESS


var _古今阶段: int = 0


# ============================================================
# 法术技能：知行合一 / 秘境万象
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == ZHI_XING_HE_YI:
		if engine.deck.pile_size() <= 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if 技能号 == MI_JING_WAN_XIANG:
		if not _史书在手():
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == ZHI_XING_HE_YI:
		return _知行合一()
	if 技能号 == MI_JING_WAN_XIANG:
		return _秘境万象()
	return EMPTY_HANDLE


## 知行合一：展示 2 张 → 选 1 张（同时弃 1 张手牌）→ 加入手牌 + 一笔只能用它的额外行动
func _知行合一() -> int:
	if _知行阶段 == 0:
		_知行牌 = engine.移除牌库顶(2)
		if _知行牌.is_empty():
			return SUCCESS
		engine.展示牌库顶(player.id, _知行牌, true)
		_知行阶段 = 1
		var 选项: Array = []
		for i: int in range(_知行牌.size()):
			var 牌: GCard = Data.get_card(int(_知行牌[i]))
			if 牌 == null:
				continue
			选项.append({
				"value": i + 1,
				"label": "%s %s" % [牌.card_name, GConst.element_to_chinese(牌.element_enum())],
				"card_id": int(_知行牌[i]),
			})
		询问(player.id, ZHI_XING_HE_YI, 1, 0, GConst.CardSource.Hand, 选项, 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	_知行阶段 = 0
	if args.is_empty() or cards.is_empty():
		return SUCCESS
	var 档: int = int(args[0])
	if 档 < 1 or 档 > _知行牌.size():
		return SUCCESS
	var 选中: int = int(_知行牌[档 - 1])
	var 牌: GCard = Data.get_card(选中)
	if 牌 == null:
		return SUCCESS
	notice_skill(ZHI_XING_HE_YI, [player.id])
	var 弃: int = int(cards[0])
	if player.has_hand_card(弃):
		engine.take_from_hand(player.id, [弃])
		engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": ZHI_XING_HE_YI})
	player.add_hand_cards([选中])
	engine.播获得牌日志(player.id, [选中])
	# 「作为相应行动发出」：给一份只能用这张牌的额外行动（牌已在手，白名单按牌面）
	var 种类: int = GConst.ActionType.Attack if 牌.is_attack() else GConst.ActionType.Magic
	player.add_action(种类, ZHI_XING_HE_YI, true, false, {"cards": [GConst.牌号(选中)]})
	var 余: Array = []
	for c: Variant in _知行牌:
		if int(c) != 选中:
			余.append(int(c))
	if not 余.is_empty():
		engine.to_discard(余, {"owner": player.id, "source": "deck", "cause": ZHI_XING_HE_YI, "face_up": true})
		player.add_token(史料槽, 余.size())
	_知行牌 = []
	engine._broadcast_game()
	_检查稽古()
	return SUCCESS


## 秘境万象：移除史书与所有遗迹 → 逐张翻牌库顶直到出现同系的两张 → 都作为遗迹
func _秘境万象() -> int:
	if _秘境阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var dsts: Array = r.get("dst_ids", [])
		_秘境阶段 = 0
		if dsts.size() != _秘境X - 3:
			engine.报错("【秘境万象】目标数不对", player.id)
			return SUCCESS
		for d: Variant in dsts:
			engine.push_harm({"src": player.id, "dst": int(d), "point": 2,
				"cause": MI_JING_WAN_XIANG, "type": GConst.HarmType.Magic})
		engine._broadcast_game()
		return URGENT
	notice_skill(MI_JING_WAN_XIANG, [player.id])
	_移除史书()
	var 旧: Array = player.cover_cards.duplicate()
	if not 旧.is_empty():
		engine.remove_cover(player.id, 旧, player.id, MI_JING_WAN_XIANG)
		engine.to_discard(旧, {"owner": player.id, "source": "cover", "cause": MI_JING_WAN_XIANG, "face_up": true})
	var 展示: Array = []
	var 已见: Array = []
	while engine.deck.pile_size() > 0:
		var 一张: Array[int] = engine.deck.remove_top(1)
		if 一张.is_empty():
			break
		var cid: int = int(一张[0])
		展示.append(cid)
		var 牌: GCard = Data.get_card(cid)
		var 系: int = 牌.element_enum() if 牌 != null else 0
		if 已见.has(系):
			break
		已见.append(系)
	if 展示.is_empty():
		return SUCCESS
	engine.展示牌库顶(player.id, 展示, false)
	engine.add_cover(player.id, 展示, player.id, MI_JING_WAN_XIANG, true)
	_秘境X = 展示.size()
	engine._broadcast_game()
	if _秘境X > 3:
		_秘境阶段 = 1
		询问(player.id, MI_JING_WAN_XIANG, 0, _秘境X - 3, GConst.CardSource.Hand, [], 0, "", [], false,
			0, -1, 全部角色(), -1, {}, 2, GConst.HarmType.Magic)
		return WAIT
	return SUCCESS


func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_遗迹论破已用 = false
	return SUCCESS


# ============================================================
# 遗迹论破：主动攻击① 移除同系遗迹加伤（回合限定）
# ============================================================
func p_before_attack(ctx: Dictionary) -> int:
	if _遗迹论破已用:
		return SUCCESS
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	var 牌: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 牌 == null:
		return SUCCESS
	var 同系: Array = _同系遗迹(牌.element_enum())
	if 同系.is_empty():
		return SUCCESS
	if not engine.has_reply():
		_遗迹论破同系 = 同系
		询问(player.id, YI_JI_LUN_PO, 0, 0, GConst.CardSource.Hand, _遗迹论破选项(同系.size()), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	_遗迹论破同系 = []
	if args.is_empty():
		return SUCCESS
	var X: int = int(args[0])
	if X <= 0 or X > 同系.size():
		return SUCCESS
	_遗迹论破已用 = true
	var 取: Array = []
	for i: int in range(X):
		取.append(int(同系[i]))
	notice_skill(YI_JI_LUN_PO, [player.id])
	engine.remove_cover(player.id, 取, player.id, YI_JI_LUN_PO)
	engine.to_discard(取, {"owner": player.id, "source": "cover", "cause": YI_JI_LUN_PO})
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + (X - 1)
	if X > 1:
		player.add_action(GConst.ActionType.Magic, YI_JI_LUN_PO, true)
	if _遗迹数() == 0:
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	engine._broadcast_game()
	return SUCCESS


func _遗迹论破选项(上限: int) -> Array:
	var 选项: Array = []
	for x: int in range(1, 4):
		选项.append({
			"value": x,
			"label": GConst.按钮原文(YI_JI_LUN_PO, x - 1),
			"text": GConst.按钮原文(YI_JI_LUN_PO, x - 1),
			"enabled": x <= 上限,
		})
	return 选项


# ============================================================
# 引稽编鉴：用【史书】主动攻击①
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if GConst.牌号(int(ctx.get("card_id", -1))) != 史书号:
		return SUCCESS
	if _引稽阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var cards: Array = r.get("card_ids", [])
		var dp: BattlePlayer = engine.p(_引稽目标)
		var 入: int = -1
		if dp != null:
			for c: Variant in cards:
				if dp.has_hand_card(int(c)):
					入 = int(c)
					break
			if 入 < 0 and not dp.hand_cards.is_empty():
				入 = int(dp.hand_cards[0])
		_引稽阶段 = 0
		if 入 < 0:
			return SUCCESS
		if dp != null:
			engine.take_from_hand(dp.id, [入])
		engine.add_cover(player.id, [入], player.id, YIN_JI_BIAN_JIAN, true)
		engine._broadcast_game()
		if player.cover_cards.is_empty() or player.hand_cards.is_empty():
			return SUCCESS
		_引稽阶段 = 2
		询问(player.id, YIN_JI_BIAN_JIAN, 1, 0, GConst.CardSource.Hand, [], 0, ", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _引稽阶段 == 2:
		var r2: Dictionary = take_skill_reply_full()
		var args2: Array = r2.get("args", [])
		var cards2: Array = r2.get("card_ids", [])
		_引稽阶段 = 0
		if args2.is_empty() or cards2.is_empty():
			return SUCCESS
		_交换遗迹(player.id, cards2.size(), cards2, YIN_JI_BIAN_JIAN)
		return SUCCESS
	var dst: int = int(ctx.get("dst", -1))
	var dp2: BattlePlayer = engine.p(dst)
	if dp2 == null or dp2.hand_cards.is_empty():
		return SUCCESS
	notice_skill(YIN_JI_BIAN_JIAN, [dst])
	_引稽目标 = dst
	_引稽阶段 = 1
	engine.ask_respond(dst, GConst.RespondType.Discard, [dst, YIN_JI_BIAN_JIAN, 1], [dst])
	engine.wait_for(dst, GConst.Msg.Respond)
	return WAIT




# ============================================================
# 古今互鉴的交换
# ============================================================
func _古今交换(r: Dictionary) -> int:
	var cards: Array = r.get("card_ids", [])
	var args: Array = r.get("args", [])
	_古今阶段 = 0
	if cards.size() < 2 or args.is_empty():
		return SUCCESS
	_交换遗迹(player.id, int(args[0]), cards, GU_JIN_HU_JIAN)
	return SUCCESS


## 把 2 张手牌放进遗迹，取回 X 个遗迹
func _交换遗迹(_pid: int, X: int, 给牌: Array, cause: int) -> void:
	var 遗迹: Array = player.cover_cards.duplicate()
	if X <= 0 or X > 遗迹.size():
		return
	var 取: Array = []
	for i: int in range(X):
		取.append(int(遗迹[i]))
	var 给: Array = []
	for c: Variant in 给牌:
		if player.has_hand_card(int(c)) and not 给.has(int(c)) and 给.size() < 2:
			给.append(int(c))
	if 给.is_empty():
		return
	engine.remove_cover(player.id, 取, player.id, cause)
	player.add_hand_cards(取)
	engine.播获得牌日志(player.id, 取)
	engine.take_from_hand(player.id, 给)
	engine.add_cover(player.id, 给, player.id, cause, true)
	engine._broadcast_game()


func _交换选项(技能号: int) -> Array:
	var 上限: int = mini(2, _遗迹数())
	var 选项: Array = []
	for x: int in range(1, 3):
		选项.append({
			"value": x,
			"label": GConst.按钮原文(技能号, x - 1),
			"text": GConst.按钮原文(技能号, x - 1),
			"enabled": x <= 上限,
		})
	return 选项


# ============================================================
# 稽古识典：史料满时换【史书】
# ============================================================
func _检查稽古() -> void:
	if player.token_num(史料槽) < player.token_max(史料槽):
		return
	notice_skill(JI_GU_SHI_DIAN, [player.id])
	player.clear_token(史料槽)
	if not player.hand_cards.is_empty():
		engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, JI_GU_SHI_DIAN))
	if not player.has_hand_card(史书号):
		player.add_hand_cards([史书号])
		engine.播获得牌日志(player.id, [史书号])
	engine._broadcast_game()


# ============================================================
# 以史为镜：史书被弃置 / 打出时移出游戏
# ============================================================
func wants_before_discard(ctx: Dictionary) -> bool:
	for c: Variant in ctx.get("cards", []):
		if GConst.牌号(int(c)) == 史书号:
			return true
	return false


func p_before_discard(ctx: Dictionary) -> int:
	var 移: Array = []
	for c: Variant in ctx.get("cards", []):
		if GConst.牌号(int(c)) == 史书号 and not 移.has(int(c)):
			移.append(int(c))
	if 移.is_empty():
		return SUCCESS
	ctx["removed"] = 移
	notice_skill(YI_SHI_WEI_JING, [player.id])
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _遗迹数() -> int:
	return player.cover_cards.size()


## 与给定系别同系的遗迹：光系 / 暗系遗迹视为任意系别（选淬精炼）
func _同系遗迹(系: int) -> Array:
	var out: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		var 牌系: int = 牌.element_enum()
		if 牌系 == 系 or 牌系 == GConst.CardElement.Light or 牌系 == GConst.CardElement.Darkness:
			out.append(cid)
	return out


func _史书在手() -> bool:
	return player.has_hand_card(史书号)


func _移除史书() -> void:
	if not player.has_hand_card(史书号):
		return
	engine.take_from_hand(player.id, [史书号])
	engine.放入移除牌堆(史书号)


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

extends BattleRole
## 捣蛋萝莉（roleID 86）
##
## 【Tricky】＝面朝下放在角色面前的基础效果：客户端只看得到占位牌 卡表#1008（无卡面），
## 真实牌面只存在服务端（本脚本的 _trickies）。场上 Tricky 用 basic_effects 里的 1008 占位，
## 一张占位对应 _trickies 里的一条 {dst, card}。
##
## 技能：
##   天使？ 8601（响应）：你可将手牌里带【天使之墙】的牌当作【圣盾】使用
##       （照 7 号守护天使 701 的做法：牌本身放进目标的基础效果区，引擎把它视作【圣盾】格挡）。
##   叛逆之墙 8602（法术）：将手牌 1 个【圣盾】【展示】与场上 1 个基础效果交换；你弃 1 张牌。
##   神秘伏笔 8603（被动）：【法术行动】结束后，牌库顶 1~2 张面朝下放到 X 名角色面前作为【Tricky】。
##   T-r-i-c-k-y! 8604（响应）：主动攻击未命中②，查看 1 个【Tricky】；
##       若你移除该【Tricky】并额外弃 1 张同系牌，对原拥有者造成 2 点法术伤害③。
##   Trick or Treat 8605（被动）：你的回合结束时若场上【Tricky】>4，展示全部【Tricky】，
##       所有人各弃 1 张与面前【Tricky】同系的牌，然后移除所有【Tricky】；每有人不如此做吃 2 点法术伤害③；
##       再按双方弃牌数比大小给战绩区星石 / 额外回合。
##   Surprise! 8606（法术·必杀【水晶】）：弃 1 张牌，本回合手牌上限 +5，收走场上所有【Tricky】，
##       再把 X 张手牌面朝下放到 X 名角色面前作为【Tricky】。
##
## 参考实现：守护天使 701（牌本身当【圣盾】放基础效果）、矜贵之女 7802（多步询问 + 逐人问弃牌）、
## 10803【剑守誓言】（展示牌库顶后选目标）。

const TIAN_SHI: int = 8601
const PAN_NI_ZHI_QIANG: int = 8602
const SHEN_MI_FU_BI: int = 8603
const TRICKY: int = 8604
const TRICK_OR_TREAT: int = 8605
const SURPRISE: int = 8606

const Tricky占位牌: int = 1008
const 手牌上限来源: String = "Surprise"

## [{dst, card}]
var _trickies: Array = []
## 神秘伏笔：1＝等选放 1 还是 2 张 / 2＝等选目标
var _伏笔阶段: int = 0
var _伏笔张数: int = 0
var _伏笔牌: Array = []
## Surprise!：1＝等选手牌放回 / 2＝等选目标
var _惊爆阶段: int = 0
var _惊爆牌: Array = []
## Trick or Treat：1＝等逐人弃牌 / 2＝等选结算分支
var _糖果阶段: int = 0
var _糖果已用: bool = false
var _糖果对象: Array = []
var _糖果下标: int = 0
var _糖果我方: int = 0
var _糖果敌方: int = 0
var _糖果未做: Array = []
## T-r-i-c-k-y!：0＝未问 / 1＝等选查看哪个 / 2＝等选同系弃牌
var _垂迹阶段: int = 0
var _垂迹选中: int = -1
## 叛逆之墙：0＝未问 / 1＝等选要弃的牌
var _叛逆阶段: int = 0


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 墙牌: Array[int] = hand_ids_with_skill(GConst.技能_天使之墙)
	var 圣盾牌: Array[int] = _手牌圣盾()
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": TIAN_SHI,
			"need_card": 1,
			"need_target": 1,
			"cards": 墙牌,
			"targets": player_ids_where(func(p: BattlePlayer) -> bool:
				return not p.check_basic_effect_name(GConst.CardName.Shield) \
					and not p.check_basic_effect_skill(GConst.技能_天使之墙) \
					and 目标可接收基础效果(p.id, GConst.技能_天使之墙), true),
			"enabled": not 墙牌.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": PAN_NI_ZHI_QIANG,
			"need_card": 1,
			"need_target": 1,
			"cards": 圣盾牌,
			"targets": _有基础效果者(),
			"enabled": not 圣盾牌.is_empty() and not _有基础效果者().is_empty() \
				and not player.hand_cards.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": SURPRISE,
			"need_card": 1,
			"need_target": 0,
			"enabled": player.get_energy() >= 1 and not player.hand_cards.is_empty(),
		},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if 技能号 == TIAN_SHI:
		if cards.is_empty() or not _是天使之墙(int(cards[0])):
			return GConst.GE_INVALID_ACTION
		if dsts.is_empty() or engine.p(int(dsts[0])) == null:
			return GConst.GE_INVALID_ARGUMENT
		if not _墙目标可收(int(dsts[0])):
			return GConst.GE_INVALID_PLAYERID
		return GConst.GE_SUCCESS
	if 技能号 == PAN_NI_ZHI_QIANG:
		if cards.is_empty() or player.手牌实例(int(cards[0])) < 0 or not _是圣盾(int(cards[0])):
			return GConst.GE_INVALID_ACTION
		if dsts.is_empty() or engine.p(int(dsts[0])) == null:
			return GConst.GE_INVALID_ARGUMENT
		if not _有基础效果者().has(int(dsts[0])):
			return GConst.GE_INVALID_PLAYERID
		if player.hand_cards.size() < 2:
			return GConst.GE_INVALID_ACTION
		_叛逆阶段 = 0
		return GConst.GE_SUCCESS
	if 技能号 != SURPRISE:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1 or cards.is_empty():
		return GConst.GE_INVALID_ACTION
	_惊爆阶段 = 0
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == TIAN_SHI:
		return _天使(action)
	if 技能号 == PAN_NI_ZHI_QIANG:
		return _叛逆之墙(action)
	return _惊爆(action)


# ============================================================
# 天使？ 8601：带【天使之墙】的牌当【圣盾】放到目标面前
# ============================================================
func _天使(action: Dictionary) -> int:
	var 牌: int = int((action.get("card_ids", []) as Array)[0])
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	if not _是天使之墙(牌) or not _墙目标可收(dst):
		return SUCCESS
	notice_skill(TIAN_SHI, [dst])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [牌], "is_real": true,
	})
	# 牌本身进目标的基础效果区：引擎把【天使之墙】视作【圣盾】格挡（base_v_shield）
	engine.add_basic_effect(dst, 牌, player.id, GConst.CAUSE_USE)
	engine.take_from_hand(player.id, [牌], true)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 叛逆之墙 8602：手牌【圣盾】与场上 1 个基础效果交换，然后你弃 1 张牌
# ============================================================
func _叛逆之墙(action: Dictionary) -> int:
	if _叛逆阶段 == 1:
		return _叛逆弃牌()
	var 牌: int = int((action.get("card_ids", []) as Array)[0])
	var 目标: int = int((action.get("dst_ids", []) as Array)[0])
	var dp: BattlePlayer = engine.p(目标)
	if dp == null or player.手牌实例(牌) < 0 or not _是圣盾(牌):
		return SUCCESS
	notice_skill(PAN_NI_ZHI_QIANG, [目标])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [牌], "is_real": true,
	})
	# 拿走对方面前 1 个基础效果（跳过 Tricky 占位，避免与 _trickies 脱节）
	var 拿: int = -1
	for be: Dictionary in dp.basic_effects:
		if int(be["card"]) != Tricky占位牌:
			拿 = int(be["card"])
			break
	if 拿 >= 0:
		engine.remove_basic_effect(目标, 拿, PAN_NI_ZHI_QIANG, player.id)
		player.add_hand_cards([拿])
		engine.播获得牌日志(player.id, [拿])
	# 自己的圣盾放到对方面前（技能表写的是「手牌【圣盾】【展示】」：走展示手牌钩子）
	engine.take_from_hand(player.id, [牌], true)
	engine.add_basic_effect(目标, 牌, player.id, PAN_NI_ZHI_QIANG)
	engine._broadcast_game()
	# 你弃 1 张牌（由本人选）
	if player.hand_cards.is_empty():
		return SUCCESS
	_叛逆阶段 = 1
	询问(player.id, PAN_NI_ZHI_QIANG, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false,
		0, -1, [], -1, {})
	return WAIT


func _叛逆弃牌() -> int:
	var r: Dictionary = take_skill_reply_full()
	_叛逆阶段 = 0
	var 弃: int = -1
	for c: Variant in r.get("card_ids", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	if 弃 < 0:
		# 强制弃 1 张：超时 / 空回复按手牌顺序补一张
		for cid: int in player.hand_cards:
			if player.has_discard_card(cid):
				弃 = cid
				break
	if 弃 < 0:
		return SUCCESS
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": PAN_NI_ZHI_QIANG})
	engine._log_discard(player.id, [弃])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 神秘伏笔 8603：法术行动结束后放 Tricky
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _伏笔阶段 == 0:
		if engine.deck.pile_size() <= 0:
			return SUCCESS
		var 上限: int = mini(2, engine.deck.pile_size())
		_伏笔阶段 = 1
		var 选项: Array = []
		for n: int in range(1, 3):
			选项.append({
				"value": n,
				"label": GConst.按钮原文(SHEN_MI_FU_BI, n - 1),
				"text": GConst.按钮原文(SHEN_MI_FU_BI, n - 1),
				"enabled": n <= 上限,
			})
		询问(player.id, SHEN_MI_FU_BI, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], false,
			0, -1, [], -1, {})
		return WAIT
	if _伏笔阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		_伏笔阶段 = 0
		if args.is_empty():
			return SUCCESS
		_伏笔张数 = int(args[0])
		if _伏笔张数 < 1 or _伏笔张数 > mini(2, engine.deck.pile_size()):
			engine.报错("【神秘伏笔】张数不合法", player.id)
			return SUCCESS
		_伏笔牌 = engine.移除牌库顶(_伏笔张数)
		if _伏笔牌.is_empty():
			return SUCCESS
		_伏笔阶段 = 2
		询问(player.id, SHEN_MI_FU_BI, 0, _伏笔张数, GConst.CardSource.Hand, [], 0, "", [], false,
			0, -1, 全部角色(), -1, {})
		return WAIT
	# 阶段 2：给每个目标放 1 张
	var r2: Dictionary = take_skill_reply_full()
	var dsts: Array = r2.get("dst_ids", [])
	_伏笔阶段 = 0
	if dsts.size() != _伏笔张数:
		engine.报错("【神秘伏笔】目标数不对", player.id)
		for c: Variant in _伏笔牌:
			engine.to_discard([int(c)], {"owner": player.id, "source": "deck", "cause": SHEN_MI_FU_BI})
		_伏笔牌 = []
		return SUCCESS
	notice_skill(SHEN_MI_FU_BI, dsts)
	for i: int in range(_伏笔张数):
		_放Tricky(int(dsts[i]), int(_伏笔牌[i]))
	_伏笔牌 = []
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# T-r-i-c-k-y! 8604：主动攻击未命中② → 查看 1 个【Tricky】→ 可移除并弃 1 张同系牌 → 2 点法术伤害
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _trickies.is_empty():
		return SUCCESS
	if _垂迹阶段 == 0:
		_垂迹阶段 = 1
		询问(player.id, TRICKY, 0, 0, GConst.CardSource.Hand, _垂迹选项(), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _垂迹阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		_垂迹阶段 = 0
		if args.is_empty():
			return SUCCESS
		var 档: int = int(args[0])
		if 档 < 1 or 档 > _trickies.size():
			engine.报错("【T-r-i-c-k-y!】选项号越界", player.id)
			return SUCCESS
		_垂迹选中 = 档 - 1
		var 项: Dictionary = _trickies[_垂迹选中]
		var 真牌: int = int(项["card"])
		var 牌: GCard = Data.get_card(真牌)
		if 牌 == null:
			_垂迹选中 = -1
			return SUCCESS
		# 查看：只把这张牌给发动者本人看
		engine.send(player.id, GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": int(项["dst"]), "dst_id": player.id,
			"card_ids": [真牌], "is_real": true,
		})
		var 同系: Array = hand_ids_where(func(_cid: int, c: GCard) -> bool:
			return c.element_enum() == 牌.element_enum())
		if 同系.is_empty():
			_垂迹选中 = -1
			return SUCCESS
		_垂迹阶段 = 2
		询问(player.id, TRICKY, 1, 0, GConst.CardSource.Hand, [], 0, "", 同系, true,
			0, -1, [], -1, {})
		return WAIT
	# 阶段 2：移除该 Tricky + 弃 1 张同系牌 → 对原拥有者 2 点法术伤害③
	var r2: Dictionary = take_skill_reply_full()
	var cards2: Array = r2.get("card_ids", [])
	_垂迹阶段 = 0
	var 序: int = _垂迹选中
	_垂迹选中 = -1
	if cards2.is_empty() or 序 < 0 or 序 >= _trickies.size():
		return SUCCESS
	var 项2: Dictionary = _trickies[序]
	var 真牌2: int = int(项2["card"])
	var 牌2: GCard = Data.get_card(真牌2)
	var 弃: int = -1
	for c: Variant in cards2:
		var 实例: int = player.手牌实例(int(c))
		if 实例 < 0 or 牌2 == null:
			continue
		var 弃牌: GCard = Data.get_card(实例)
		if 弃牌 != null and 弃牌.element_enum() == 牌2.element_enum():
			弃 = 实例
			break
	if 弃 < 0:
		engine.报错("【T-r-i-c-k-y!】弃的牌与 Tricky 不同系", player.id)
		return SUCCESS
	var 目标: int = int(项2["dst"])
	notice_skill(TRICKY, [目标])
	_trickies.remove_at(序)
	var dp2: BattlePlayer = engine.p(目标)
	if dp2 != null:
		dp2.remove_basic_effect(Tricky占位牌)
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": TRICKY})
	engine._log_discard(player.id, [弃])
	engine.push_harm({"src": player.id, "dst": 目标, "point": 2,
		"cause": TRICKY, "type": GConst.HarmType.Magic})
	engine._broadcast_game()
	return URGENT


func _垂迹选项() -> Array:
	var out: Array = []
	for i: int in range(_trickies.size()):
		var 项: Dictionary = _trickies[i]
		var dp: BattlePlayer = engine.p(int(项["dst"]))
		var 名: String = Data.role_name(dp.role_id) if dp != null else ""
		var 文案: String = GConst.按钮原文(TRICKY, 0) % 名
		out.append({
			"value": i + 1,
			"label": 文案,
			"text": 文案,
		})
	return out


# ============================================================
# Surprise! 8606（法术·必杀【水晶】）
# ============================================================
func _惊爆(action: Dictionary) -> int:
	if _惊爆阶段 != 0:
		return _惊爆放回()
	var 弃: Array = []
	for c: Variant in action.get("card_ids", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0 and not 弃.has(实例):
			弃.append(实例)
	if 弃.size() != 1:
		return SUCCESS
	notice_skill(SURPRISE, [player.id])
	player.remove_energy(1)
	engine.take_from_hand(player.id, 弃)
	engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": SURPRISE})
	engine._log_discard(player.id, 弃)
	# 本回合手牌上限 +5（自己的回合结束时清，见 p_turn_end）
	player.设手牌上限修正(手牌上限来源, 5)
	# 收走场上所有【Tricky】
	var 收: Array = []
	for 项: Dictionary in _trickies:
		var dp: BattlePlayer = engine.p(int(项["dst"]))
		if dp != null:
			dp.remove_basic_effect(Tricky占位牌)
		收.append(int(项["card"]))
	_trickies.clear()
	if not 收.is_empty():
		player.add_hand_cards(收)
		engine.播获得牌日志(player.id, 收)
	engine._broadcast_game()
	if player.hand_cards.is_empty():
		return SUCCESS
	_惊爆牌 = []
	_惊爆阶段 = 1
	询问(player.id, SURPRISE, 1, 0, GConst.CardSource.Hand, [], player.hand_cards.size(), "", [], true,
		0, -1, [], -1, {})
	return WAIT


func _惊爆放回() -> int:
	if _惊爆阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var 选: Array = []
		for c: Variant in r.get("card_ids", []):
			var 实例: int = player.手牌实例(int(c))
			if 实例 >= 0 and not 选.has(实例):
				选.append(实例)
		_惊爆阶段 = 0
		if 选.is_empty():
			return SUCCESS
		_惊爆牌 = 选
		_惊爆阶段 = 2
		询问(player.id, SURPRISE, 0, 选.size(), GConst.CardSource.Hand, [], 0, "", [], false,
			0, -1, 全部角色(), -1, {})
		return WAIT
	# 阶段 2：收目标
	var r2: Dictionary = take_skill_reply_full()
	var dsts: Array = r2.get("dst_ids", [])
	_惊爆阶段 = 0
	if dsts.size() != _惊爆牌.size():
		engine.报错("【Surprise!】目标数不对", player.id)
		_惊爆牌 = []
		return SUCCESS
	engine.take_from_hand(player.id, _惊爆牌)
	for i: int in range(_惊爆牌.size()):
		_放Tricky(int(dsts[i]), int(_惊爆牌[i]))
	_惊爆牌 = []
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# Trick or Treat 8605：回合结束时场上有 >4 个【Tricky】
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# Surprise! 的「本回合手牌上限 +5」只在本次回合内有效
	player.清手牌上限修正(手牌上限来源)
	if _糖果阶段 != 0:
		return _糖果推进()
	if _糖果已用 or _trickies.size() <= 4:
		return SUCCESS
	_糖果已用 = true
	notice_skill(TRICK_OR_TREAT, [player.id])
	_糖果对象 = []
	_糖果下标 = 0
	_糖果我方 = 0
	_糖果敌方 = 0
	_糖果未做 = []
	var 已列: Array = []
	for 项: Dictionary in _trickies:
		var dst: int = int(项["dst"])
		var 真牌: int = int(项["card"])
		# 展示所有【Tricky】
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": dst, "dst_id": dst,
			"card_ids": [真牌], "is_real": true,
		})
		if 已列.has(dst):
			continue
		已列.append(dst)
		var 牌: GCard = Data.get_card(真牌)
		_糖果对象.append({"pid": dst, "card": 真牌, "element": 牌.element_enum() if 牌 != null else 0})
	# 【Tricky】是早已放在场上的暗牌（不是手牌），封印类「从手中展示出」不触发
	engine._broadcast_game()
	_糖果阶段 = 1
	return _糖果推进()


## 逐人问「弃 1 张与面前【Tricky】同系的牌」；没人有同系牌就算「不如此做」
func _糖果推进() -> int:
	if _糖果阶段 == 2:
		return _糖果结算(take_skill_reply_full())
	if _糖果阶段 == 1:
		while _糖果下标 < _糖果对象.size():
			var 项: Dictionary = _糖果对象[_糖果下标]
			var dp: BattlePlayer = engine.p(int(项["pid"]))
			if dp == null:
				_糖果下标 += 1
				continue
			var 系: int = int(项["element"])
			var 同系: Array = []
			for cid: int in dp.hand_cards:
				var c: GCard = Data.get_card(cid)
				if c != null and c.element_enum() == 系:
					同系.append(cid)
			if 同系.is_empty():
				_糖果未做.append(dp.id)
				_糖果下标 += 1
				continue
			if not engine.has_reply():
				询问(dp.id, TRICK_OR_TREAT, 1, 0, GConst.CardSource.Hand, [], 0, "", 同系, false,
					0, -1, [], -1, {})
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			var 弃: int = -1
			for c2: Variant in r.get("card_ids", []):
				var 实例: int = dp.手牌实例(int(c2))
				if 实例 >= 0 and 同系.has(实例):
					弃 = 实例
					break
			if 弃 < 0:
				# 强制：超时 / 空回复按手牌顺序补一张同系牌
				for c3: int in 同系:
					if dp.has_discard_card(c3):
						弃 = c3
						break
			if 弃 < 0:
				_糖果未做.append(dp.id)
			else:
				engine.take_from_hand(dp.id, [弃])
				engine.to_discard([弃], {"owner": dp.id, "source": "hand",
					"cause": TRICK_OR_TREAT, "face_up": true})
				engine._log_discard(dp.id, [弃], false)
				if dp.color == player.color:
					_糖果我方 += 1
				else:
					_糖果敌方 += 1
			_糖果下标 += 1
		# 逐人问完：先移除所有【Tricky】，再对「不如此做」的人造成 2 点法术伤害③
		_糖果阶段 = 3
		for 项2: Dictionary in _trickies:
			var dp2: BattlePlayer = engine.p(int(项2["dst"]))
			if dp2 != null:
				dp2.remove_basic_effect(Tricky占位牌)
		_trickies.clear()
		engine._broadcast_game()
		var 有罚: bool = not _糖果未做.is_empty()
		for dst2: Variant in _糖果未做:
			engine.push_harm({"src": player.id, "dst": int(dst2), "point": 2,
				"cause": TRICK_OR_TREAT, "type": GConst.HarmType.Magic})
		_糖果未做 = []
		if 有罚:
			return URGENT
	if _糖果阶段 != 3:
		return SUCCESS
	_糖果阶段 = 0
	if _糖果我方 < _糖果敌方:
		engine.set_team_gem(1 - player.color, engine.team_gem[1 - player.color] + 1)
		return SUCCESS
	if _糖果我方 == _糖果敌方:
		return SUCCESS
	_糖果阶段 = 2
	询问(player.id, TRICK_OR_TREAT, 0, 0, GConst.CardSource.Hand, _糖果选项(), 0, "", [], true,
		0, -1, [], -1, {})
	return WAIT


func _糖果选项() -> Array:
	return [
		{"value": 1, "label": GConst.按钮原文(TRICK_OR_TREAT, 0), "text": GConst.按钮原文(TRICK_OR_TREAT, 0),
			"need_card": 0},
		{"value": 2, "label": GConst.按钮原文(TRICK_OR_TREAT, 1), "text": GConst.按钮原文(TRICK_OR_TREAT, 1),
			"need_card": 1},
	]


func _糖果结算(r: Dictionary) -> int:
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	_糖果阶段 = 0
	if args.is_empty():
		return SUCCESS
	if int(args[0]) == 1:
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
		player.set_crystal(player.crystal + 1)
		engine._broadcast_game()
		return SUCCESS
	# 分支 2：你弃 1 张牌，并额外获得一个回合
	var 弃: int = -1
	for c: Variant in cards:
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	if 弃 < 0:
		for cid: int in player.hand_cards:
			if player.has_discard_card(cid):
				弃 = cid
				break
	if 弃 >= 0:
		engine.take_from_hand(player.id, [弃])
		engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": TRICK_OR_TREAT})
		engine._log_discard(player.id, [弃])
	安排额外回合(0, TRICK_OR_TREAT)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 回合开始：清零【回合限定】标记
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_糖果已用 = false
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _放Tricky(dst: int, card: int) -> void:
	var dp: BattlePlayer = engine.p(dst)
	if dp == null:
		return
	dp.add_basic_effect(Tricky占位牌, player.id)
	_trickies.append({"dst": dst, "card": card})


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out


func _是圣盾(cid: int) -> bool:
	var 牌: GCard = Data.get_card(cid)
	return 牌 != null and 牌.card_name_enum() == GConst.CardName.Shield


## 手牌里【圣盾】的实例号
func _手牌圣盾() -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		if _是圣盾(cid):
			out.append(cid)
	return out


## 面前有基础效果（不含纯 Tricky 占位）的角色
func _有基础效果者() -> Array:
	var out: Array = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null:
			continue
		for be: Dictionary in p0.basic_effects:
			if int(be["card"]) != Tricky占位牌:
				out.append(pid)
				break
	return out


## 手牌里带【天使之墙】的牌（圣命格攻击牌）
func _是天使之墙(cid: int) -> bool:
	var 牌: GCard = Data.get_card(cid)
	if 牌 == null or not 牌.is_attack():
		return false
	return 牌.fate_pattern_enum() == GConst.FatePattern.Holy and 牌.has_skill_id(GConst.技能_天使之墙)


## 目标能不能接收这张【天使之墙】（当作【圣盾】）：面前已有【圣盾】/【天使之墙】就不行
func _墙目标可收(dst: int) -> bool:
	var dp: BattlePlayer = engine.p(dst)
	if dp == null:
		return false
	if dp.check_basic_effect_name(GConst.CardName.Shield):
		return false
	if dp.check_basic_effect_skill(GConst.技能_天使之墙):
		return false
	return 目标可接收基础效果(dst, GConst.技能_天使之墙)

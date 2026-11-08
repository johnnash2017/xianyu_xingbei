extends BattleRole
## 捣蛋萝莉（roleID 86）
##
## 【Tricky】＝面朝下放在角色面前的基础效果：客户端只看得到占位牌 卡表#1008（无卡面），
## 真实牌面只存在服务端（本脚本的 _trickies）。场上 Trickies 用 basic_effects 里的 1008 占位，
## 一张占位对应 _trickies 里的一条 {dst, card}。
##
## 本轮实现：
##   神秘伏笔 8603（被动）：【法术行动】结束时，牌库顶 1~2 张面朝下放到 X 名角色面前作为【Tricky】。
##   T-r-i-c-k-y! 8604（响应）：主动攻击未命中②，可移走 1 个【Tricky】并额外弃 1 张同系牌，
##       对原拥有者造成 2 点法术伤害③。
##   Surprise! 8606（法术·必杀【水晶】）：弃 1 张牌，本回合手牌上限 +5，
##       将场上所有【Tricky】加入手牌。
## 未实现（见《新角色实现-进度与遗留》）：
##   天使？ 8601（圣命格攻击牌当【圣盾】）、叛逆之墙 8602、
##   Trick or Treat 8605、Surprise! 的「再放回 X 张」一半。

const TIAN_SHI: int = 8601
const PAN_NI_ZHI_QIANG: int = 8602
const SHEN_MI_FU_BI: int = 8603
const TRICKY: int = 8604
const TRICK_OR_TREAT: int = 8605
const SURPRISE: int = 8606

const Tricky占位牌: int = 1008
const 手牌上限来源: String = "Surprise"

var _trickies: Array = []          # [{dst, card}]
## 神秘伏笔：1＝等选放 1 张还是 2 张 / 2＝等选目标
var _伏笔阶段: int = 0
var _伏笔张数: int = 0
var _伏笔牌: Array = []
## Surprise!：1＝等选手牌放回 / 2＝等选目标
var _惊爆阶段: int = 0
var _惊爆牌: Array = []
## Trick or Treat：1＝等选结算分支
var _糖果阶段: int = 0
var _糖果已用: bool = false


# ============================================================
# 技能栏：Surprise!（法术·必杀）
# ============================================================
func available_skills() -> Array:
	return [{
		"type": GConst.ActionType.MagicSkill,
		"id": SURPRISE,
		"need_card": 1,
		"need_target": 0,
		"enabled": player.get_energy() >= 1 and not player.hand_cards.is_empty(),
	}]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == TIAN_SHI:
		var 牌0: Array = action.get("card_ids", [])
		if 牌0.is_empty() or not _是天使之墙(int(牌0[0])):
			return GConst.GE_INVALID_ACTION
		var dst0: Array = action.get("dst_ids", [])
		if dst0.is_empty() or engine.p(int(dst0[0])) == null:
			return GConst.GE_INVALID_ARGUMENT
		return GConst.GE_SUCCESS
	if 技能号 == PAN_NI_ZHI_QIANG:
		var 牌: Array = action.get("card_ids", [])
		if 牌.is_empty() or not _是圣盾(int(牌[0])):
			return GConst.GE_INVALID_ACTION
		var dsts: Array = action.get("dst_ids", [])
		if dsts.is_empty() or engine.p(int(dsts[0])) == null:
			return GConst.GE_INVALID_ARGUMENT
		return GConst.GE_SUCCESS
	if 技能号 != SURPRISE:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	if (action.get("card_ids", []) as Array).is_empty():
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) == TIAN_SHI:
		return _天使(action)
	if int(action.get("action_id", 0)) == PAN_NI_ZHI_QIANG:
		return _叛逆之墙(action)
	if _惊爆阶段 != 0:
		return _惊爆放回()
	player.remove_energy(1)
	notice_skill(SURPRISE, [player.id])
	# 弃 1 张牌
	var 弃: Array = action.get("card_ids", [])
	engine.take_from_hand(player.id, 弃)
	engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": SURPRISE})
	engine._log_discard(player.id, 弃, false)
	# 本回合手牌上限 +5（回合开始清）
	player.设手牌上限修正(手牌上限来源, 5)
	# 收走场上所有【Tricky】
	var 收: Array = []
	for i: int in range(_trickies.size()):
		var 项: Dictionary = _trickies[i]
		var dp: BattlePlayer = engine.p(int(项["dst"]))
		if dp != null:
			dp.remove_basic_effect(Tricky占位牌)
		收.append(int(项["card"]))
	_trickies.clear()
	if not 收.is_empty():
		player.add_hand_cards(收)
		engine.播获得牌日志(player.id, 收)
	engine._broadcast_game()
	# 再把 X 张手牌面朝下放回 X 名角色面前
	if not player.hand_cards.is_empty():
		_惊爆阶段 = 1
		询问(player.id, SURPRISE, 1, 0, GConst.CardSource.Hand, [], 2, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	return SUCCESS


# ============================================================
# 神秘伏笔：法术行动结束后放 Trickies
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
		询问(player.id, SHEN_MI_FU_BI, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _伏笔阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty():
			_伏笔阶段 = 0
			return SUCCESS
		_伏笔张数 = int(args[0])
		_伏笔牌 = engine.deck.remove_top(_伏笔张数)
		if _伏笔牌.is_empty():
			_伏笔阶段 = 0
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
		_伏笔牌 = []
		return SUCCESS
	notice_skill(SHEN_MI_FU_BI, dsts)
	for i: int in range(_伏笔张数):
		_放Tricky(int(dsts[i]), int(_伏笔牌[i]))
	_伏笔牌 = []
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# T-r-i-c-k-y!：主动攻击未命中②
# ============================================================
func p_timeline_2_miss(_ctx: Dictionary) -> int:
	if _trickies.is_empty():
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		step = 1
		var 选项: Array = []
		for i: int in range(_trickies.size()):
			var 项: Dictionary = _trickies[i]
			var dp: BattlePlayer = engine.p(int(项["dst"]))
			var 名: String = Data.role_name(dp.role_id) if dp != null else ""
			选项.append({
				"value": i + 1,
				"label": GConst.按钮原文(TRICKY, 0) % 名,
				"text": GConst.按钮原文(TRICKY, 0) % 名,
				"need_card": 1,
			})
		询问(player.id, TRICKY, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	if args.is_empty() or cards.is_empty():
		return SUCCESS
	var 档: int = int(args[0])
	if 档 < 1 or 档 > _trickies.size():
		return SUCCESS
	var 项2: Dictionary = _trickies[档 - 1]
	var 真牌: int = int(项2["card"])
	var 实牌: GCard = Data.get_card(真牌)
	var 弃: int = int(cards[0])
	var 弃牌: GCard = Data.get_card(弃)
	if 实牌 == null or 弃牌 == null or not player.has_hand_card(弃):
		return SUCCESS
	if 实牌.element_enum() != 弃牌.element_enum():
		engine.报错("【T-r-i-c-k-y!】弃的牌与 Tricky 不同系", player.id)
		return SUCCESS
	var 目标: int = int(项2["dst"])
	notice_skill(TRICKY, [目标])
	_trickies.remove_at(档 - 1)
	var dp2: BattlePlayer = engine.p(目标)
	if dp2 != null:
		dp2.remove_basic_effect(Tricky占位牌)
	engine.to_discard([真牌], {"owner": player.id, "source": "other", "cause": TRICKY})
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": TRICKY})
	engine.push_harm({"src": player.id, "dst": 目标, "point": 2,
		"cause": TRICKY, "type": GConst.HarmType.Magic})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 回合开始：清 Surprise 的手牌上限、清观看记录
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		player.清手牌上限修正(手牌上限来源)
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


# ============================================================
# 叛逆之墙（法术）：把手牌 1 个【圣盾】与场上 1 个基础效果交换，然后弃 1 张牌
# ============================================================
func _叛逆之墙(action: Dictionary) -> int:
	var 牌: int = int((action.get("card_ids", []) as Array)[0])
	var 目标: int = int((action.get("dst_ids", []) as Array)[0])
	var dp: BattlePlayer = engine.p(目标)
	if dp == null or not player.has_hand_card(牌) or not _是圣盾(牌):
		return GConst.GE_INVALID_ACTION
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
	# 自己的圣盾放到对方面前
	engine.take_from_hand(player.id, [牌])
	engine.add_basic_effect(目标, 牌, player.id, PAN_NI_ZHI_QIANG)
	engine._broadcast_game()
	# 你弃 1 张牌（强制，超时按手牌顺序补）
	var 弃: Array = []
	for cid: int in player.hand_cards:
		弃.append(cid)
		break
	if not 弃.is_empty():
		engine.take_from_hand(player.id, 弃)
		engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": PAN_NI_ZHI_QIANG})
		engine._log_discard(player.id, 弃, false)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# Surprise! 的放回：1＝等选手牌 / 2＝等选目标 / 3＝落 Tricky
# ============================================================
func _惊爆放回() -> int:
	if _惊爆阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var cards: Array = r.get("card_ids", [])
		var 选: Array = []
		for c: Variant in cards:
			if player.has_hand_card(int(c)) and not 选.has(int(c)) and 选.size() < 2:
				选.append(int(c))
		if 选.is_empty():
			_惊爆阶段 = 0
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
# 小工具
# ============================================================
func _是圣盾(cid: int) -> bool:
	var 牌: GCard = Data.get_card(cid)
	return 牌 != null and 牌.card_name_enum() == GConst.CardName.Shield


func _手牌圣盾() -> Array:
	var out: Array = []
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


# ============================================================
# Trick or Treat（被动）：行动阶段结束时（这里用回合结束时点）场上 Tricky>4
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _糖果阶段 == 1:
		return _糖果结算(take_skill_reply_full())
	if _糖果已用 or _trickies.size() <= 4:
		return SUCCESS
	_糖果已用 = true
	notice_skill(TRICK_OR_TREAT, [player.id])
	# 展示所有 Trickies，并逐人结算「弃 1 张同系牌」
	var 我方数: int = 0
	var 敌方数: int = 0
	var 未做: Array = []
	for 项: Dictionary in _trickies:
		var dst: int = int(项["dst"])
		var 真牌: int = int(项["card"])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": dst, "dst_id": dst,
			"card_ids": [真牌], "is_real": true,
		})
		var dp: BattlePlayer = engine.p(dst)
		if dp == null:
			continue
		var 牌: GCard = Data.get_card(真牌)
		var 系: int = 牌.element_enum() if 牌 != null else 0
		var 弃: int = -1
		for cid: int in dp.hand_cards:
			var c: GCard = Data.get_card(cid)
			if c != null and c.element_enum() == 系:
				弃 = cid
				break
		if 弃 < 0:
			未做.append(dst)
			continue
		engine.take_from_hand(dst, [弃])
		engine.to_discard([弃], {"owner": dst, "source": "hand", "cause": TRICK_OR_TREAT, "face_up": true})
		if dp.color == player.color:
			我方数 += 1
		else:
			敌方数 += 1
	# 每有人不如此做：2 点法术伤害
	for dst2: Variant in 未做:
		engine.push_harm({"src": player.id, "dst": int(dst2), "point": 2,
			"cause": TRICK_OR_TREAT, "type": GConst.HarmType.Magic})
	# 移除所有 Trickies
	for 项2: Dictionary in _trickies:
		var dp2: BattlePlayer = engine.p(int(项2["dst"]))
		if dp2 != null:
			dp2.remove_basic_effect(Tricky占位牌)
	_trickies.clear()
	engine._broadcast_game()
	# 我方弃得更多 / 更少
	if 我方数 < 敌方数:
		engine.set_team_gem(1 - player.color, engine.team_gem[1 - player.color] + 1)
		return SUCCESS
	if 我方数 > 敌方数:
		_糖果阶段 = 1
		询问(player.id, TRICK_OR_TREAT, 0, 0, GConst.CardSource.Hand, _糖果选项(), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	return SUCCESS


func _糖果选项() -> Array:
	return [
		{"value": 1, "label": GConst.按钮原文(TRICK_OR_TREAT, 0), "text": GConst.按钮原文(TRICK_OR_TREAT, 0)},
		{"value": 2, "label": GConst.按钮原文(TRICK_OR_TREAT, 1), "text": GConst.按钮原文(TRICK_OR_TREAT, 1)},
	]


func _糖果结算(r: Dictionary) -> int:
	var args: Array = r.get("args", [])
	_糖果阶段 = 0
	if args.is_empty():
		return SUCCESS
	if int(args[0]) == 1:
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
		player.set_crystal(player.crystal + 1)
		engine._broadcast_game()
		return SUCCESS
	# 分支 2：你弃 1 张牌，并额外获得一个回合
	var 弃: Array = []
	for cid: int in player.hand_cards:
		弃.append(cid)
		break
	if not 弃.is_empty():
		engine.take_from_hand(player.id, 弃)
		engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": TRICK_OR_TREAT})
		engine._log_discard(player.id, 弃, false)
	安排额外回合(0, TRICK_OR_TREAT)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 天使？（法术）：把有【天使之墙】的圣命格攻击牌当【圣盾】使用
# 做法：这张牌照常离手进弃牌堆，改为在目标面前放一张【圣盾】基础效果（用卡表#0 的牌面）。
# 没有动引擎的「牌型视为」，因此它不是法术行动、也不消耗法术行动。
# ============================================================
func _天使(action: Dictionary) -> int:
	var 牌: int = int((action.get("card_ids", []) as Array)[0])
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	if not player.has_hand_card(牌) or not _是天使之墙(牌):
		return SUCCESS
	if engine.v_basic_effect_target(dst, 0) != GConst.GE_SUCCESS:
		engine.报错("【天使？】目标不能接收基础效果", player.id)
		return SUCCESS
	player.boot_skill_used = true
	notice_skill(TIAN_SHI, [dst])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [牌], "is_real": true,
	})
	engine.take_from_hand(player.id, [牌])
	engine.to_discard([牌], {"owner": player.id, "source": "hand", "cause": TIAN_SHI})
	engine._log_discard(player.id, [牌], false)
	engine.add_basic_effect(dst, 0, player.id, TIAN_SHI)
	engine._broadcast_game()
	return SUCCESS


## 手牌里带【天使之墙】的圣命格攻击牌
func _天使之墙牌() -> Array:
	var out: Array = []
	for cid: int in player.hand_cards:
		if _是天使之墙(cid):
			out.append(cid)
	return out


func _是天使之墙(cid: int) -> bool:
	var 牌: GCard = Data.get_card(cid)
	if 牌 == null or not 牌.is_attack():
		return false
	return 牌.fate_pattern_enum() == GConst.FatePattern.Holy and 牌.has_skill_id(703)

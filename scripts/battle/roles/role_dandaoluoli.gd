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
## 惊爆：1＝等弃 1 张牌
var _惊爆阶段: int = 0


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
	if int(action.get("action_id", 0)) != SURPRISE:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	if (action.get("card_ids", []) as Array).is_empty():
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
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

extends BattleRole
## 吟游诗人（roleID 31）—— 移植自服务端 role/ShiRen.cpp
## 指示物：tokens[0] = 灵感（上限 4）
## 独有效果：【永恒乐章】GConst.Exclusive.YongHengYueZhang（放置于某名角色面前，由持有者触发）
## 技能：沉沦协奏曲（3101，响应：一回合内我方对 ≥2 名敌方角色造成法术伤害并结算完后，
##                 弃 2 张同系牌【展示】→ 对目标造成 1 点法术伤害）、
##       不谐和弦（3102，法术：移除 X 点灵感（X＞1）→ 你与目标各摸 X－1 张牌，或各弃 X－1 张牌）、
##       歌咏天赋（3103，被动：永恒乐章被触发后 +1 灵感并把乐章收回；
##                 若灵感已达上限则横置并对自己造成 3 点法术伤害）、
##       暴风前奏曲（3104，服务端仅有枚举、无任何实现，故未移植）、
##       激昂狂想曲（31052，响应：回合开始时若当前角色持有永恒乐章 →
##                 对两名目标各 1 点法术伤害，或弃 2 张牌）、
##       胜利交响诗（31061，响应：回合结束时若当前角色持有永恒乐章 →
##                 将我方 1 星石提炼为自身能量，或我方 +1 宝石且自身 +1 治疗）、
##       希望赋格曲（3107，启动：耗 1 能量把永恒乐章转移到一名队友面前）
##
## 变通说明：
## - 服务端在 STATE_TURN_BEGIN_SHIREN 调用 p_turn_begin_shiren；本引擎只在回合开始调用
##   p_turn_begin，故「激昂狂想曲」并入 p_turn_begin（判定当前回合角色是否为乐章持有者）。
## - 灵感上限：服务端 tokenMax[0] = 3，技能文本与任务要求均为 4，此处取 4。
## - 服务端构造时「诗人初始拥有永恒乐章」的语句被注释掉（YueZhangDst = -1），
##   即开局乐章不在任何人面前，需靠希望赋格曲放置；此处与服务端保持一致。

const CHEN_LUN_XIE_ZOU_QU: int = 3101
const BU_XIE_HE_XIAN: int = 3102
const GE_YONG_TIAN_FU: int = 3103
const BAO_FENG_QIAN_ZOU_QU: int = 3104
const JI_ANG_KUANG_XIANG_QU: int = 3105
const JI_ANG_KUANG_XIANG_QU_2: int = 31052
const SHENG_LI_JIAO_XIANG_SHI: int = 3106
const SHENG_LI_JIAO_XIANG_SHI_2: int = 31061
const XI_WANG_FU_GE_QU: int = 3107

## 本引擎自有的分步标记（服务端把子步骤实现为压栈状态，此处用角色的自有分步变量记录进度）
const JI_ANG_DISCARD: int = 31054          # 激昂狂想曲：当前角色弃 2 张牌
const SHENG_LI_STONE: int = 31062          # 胜利交响诗：选完「提炼星石」后问提炼哪种星石

const TOKEN_LING_GAN: int = 0
const LING_GAN_MAX: int = 3
const GE_YONG_HARM: int = 3                # 歌咏天赋：灵感已满时的自伤
const CHEN_LUN_NEED_KINDS: int = 2         # 沉沦协奏曲：需要命中的敌方角色种类数

var yue_zhang_dst: int = -1                # 永恒乐章当前所在角色（-1 表示不在任何人面前）
var use_yue_zhang: bool = false            # 本次触发是否使用了永恒乐章
var chen_lun_used: bool = false            # 本回合是否已发动沉沦协奏曲
var chen_lun_dsts: Array = []              # 本回合我方法术伤害命中的敌方角色

## 不谐和弦的进度（主动法术技能不在钩子轮次内，step 不会被重置，故单独记阶段）
var bu_xie_phase: int = 0
var bu_xie_dst: int = -1
var bu_xie_num: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_LING_GAN] = {"name": "灵感", "max": LING_GAN_MAX, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if _ling_gan() > 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": BU_XIE_HE_XIAN, "need_card": 0, "need_target": 1,
			"arg_choices": _bu_xie_choices()})
	return out


# ============================================================
# 指示物与工具
# ============================================================
func _ling_gan() -> int:
	var t: Dictionary = player.tokens[TOKEN_LING_GAN]
	return int(t["num"])


func _set_ling_gan(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_LING_GAN]
	t["num"] = clampi(v, 0, int(t["max"]))


## 不谐和弦的参数选项：num 从 2 到当前灵感；choice=1 双方各摸 num-1 张，choice=2 双方各弃 num-1 张
func _bu_xie_choices() -> Array:
	var out: Array = []
	for num: int in range(2, _ling_gan() + 1):
		out.append({"text": "移除 %d 点灵感，双方各摸 %d 张牌" % [num, num - 1],
			"args": [num, 1], "need_target": 1})
		out.append({"text": "移除 %d 点灵感，双方各弃 %d 张牌" % [num, num - 1],
			"args": [num, 2], "need_target": 1})
	return out


## 从 ids 中挑出 n 张目标手牌（不足时按其手牌顺序补齐）
func _pick_cards(target: BattlePlayer, ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if target.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in target.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


## 请某名角色弃 n 张牌（服务端 StateRequestHand）
func _request_discard(pid: int, n: int, cause: int) -> int:
	var target: BattlePlayer = engine.p(pid)
	if target == null or n <= 0 or target.hand_cards.is_empty():
		return SUCCESS
	# 要弃的张数最多到他的手牌数（问超过手牌数会让他永远选不够、只能放弃）
	var want: int = mini(n, target.hand_cards.size())
	if not engine.has_reply():
		询问(pid, cause, want)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var chosen: Array = _pick_cards(target, r.get("card_ids", []), want)
	engine.take_from_hand(pid, chosen)
	engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS


func _all_hand_light() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null or c.element_enum() != GConst.CardElement.Light:
			return false
	return true


## 希望赋格曲的发动条件（服务端含一段 do-while 条件）
func _can_xi_wang() -> bool:
	if player.get_energy() < 1 or yue_zhang_dst != -1:
		return false
	if _ling_gan() > 1:
		return true
	if player.hand_cards.is_empty():
		return false
	if _all_hand_light() and player.hand_cards.size() < 4:
		return false
	return true


func p_before_turn_begin(_ctx: Dictionary) -> int:
	chen_lun_used = false
	chen_lun_dsts.clear()
	use_yue_zhang = false
	return SUCCESS


# ============================================================
# 回合开始：激昂狂想曲（31052）+ 歌咏天赋（3103）
# （服务端由 p_turn_begin_shiren 触发，本引擎并入 p_turn_begin）
# ============================================================
## 【激昂狂想曲 / 歌咏天赋】的推进阶段（0＝还没开始 / JI_ANG_KUANG_XIANG_QU_2＝在问是否发动 /
## JI_ANG_DISCARD＝等当前角色弃 2 张牌 / GE_YONG_TIAN_FU＝结算歌咏天赋）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合开始（p_turn_begin）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 末段会返回 URGENT（歌咏天赋压入了伤害状态），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _ji_ang_step: int = 0


func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != yue_zhang_dst:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if _ji_ang_step == 0:
		_ji_ang_step = JI_ANG_KUANG_XIANG_QU_2
	if _ji_ang_step == JI_ANG_KUANG_XIANG_QU_2:
		if not engine.has_reply():
			# 两个分支各做一个选项：1=对两名目标各 1 点法术伤害、2=弃 2 张牌；
			# 「取消」回空 args＝不发动（通用客户端不再拿 0 当取消）
			询问(engine.current_id, JI_ANG_KUANG_XIANG_QU_2, 0, 1, GConst.CardSource.Hand, [
				{"value": 1, "label": "对两名目标各 1 点法术伤害"},
				{"value": 2, "label": "弃 2 张牌"},
			])
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		if choice == 1:
			# 对两名目标各 1 点法术伤害
			use_yue_zhang = true
			_ji_ang_harm(r.get("dst_ids", []))
			_ji_ang_step = GE_YONG_TIAN_FU
			return URGENT
		if choice == 2:
			_ji_ang_step = JI_ANG_DISCARD
		else:
			_ji_ang_step = 0
	if _ji_ang_step == JI_ANG_DISCARD:
		# 由当前角色（乐章持有者）弃 2 张牌
		if _request_discard(engine.current_id, 2, JI_ANG_KUANG_XIANG_QU) == WAIT:
			return WAIT
		use_yue_zhang = true
		_ji_ang_step = GE_YONG_TIAN_FU
	if _ji_ang_step == GE_YONG_TIAN_FU:
		var r2: int = SUCCESS
		if use_yue_zhang:
			r2 = _ge_yong_tian_fu()
		_ji_ang_step = 0
		if r2 == URGENT:
			step = STEP_DONE
			return URGENT
	return SUCCESS


## 激昂狂想曲的伤害：按玩家点选顺序结算
func _ji_ang_harm(dsts: Array) -> void:
	# 伤害状态是栈（后压先算）→ 逆序压栈，点选顺序才会最先
	for i: int in range(dsts.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": int(dsts[i]), "point": 1,
			"cause": JI_ANG_KUANG_XIANG_QU, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()


## 歌咏天赋：乐章被触发后 +1 灵感并收回乐章；灵感已满则横置并自伤 3 点
func _ge_yong_tian_fu() -> int:
	notice_skill(GE_YONG_TIAN_FU, [player.id])
	use_yue_zhang = false
	if _ling_gan() < LING_GAN_MAX:
		_set_ling_gan(_ling_gan() + 1)
		var holder: BattlePlayer = engine.p(yue_zhang_dst)
		if holder != null:
			holder.remove_exclusive_effect(GConst.Exclusive.YongHengYueZhang)
		yue_zhang_dst = -1
		engine._broadcast_game()
		return SUCCESS
	if not player.tap:
		player.tap = true
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": GE_YONG_HARM,
		"cause": GE_YONG_TIAN_FU, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 回合结束：胜利交响诗（31061）+ 歌咏天赋（3103）
# ============================================================
## 【胜利交响诗 / 歌咏天赋】的推进阶段（0＝还没开始 / SHENG_LI_JIAO_XIANG_SHI_2＝选发动方式 /
## SHENG_LI_STONE＝选提炼哪种星石 / GE_YONG_TIAN_FU＝结算歌咏天赋）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合结束（p_turn_end）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 末段会返回 URGENT（歌咏天赋压入了伤害状态），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _jiao_xiang_step: int = 0


func p_turn_end(_ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	if _jiao_xiang_step == 0:
		_jiao_xiang_step = SHENG_LI_JIAO_XIANG_SHI_2
	if _jiao_xiang_step == SHENG_LI_JIAO_XIANG_SHI_2:
		if yue_zhang_dst != engine.current_id:
			return SUCCESS
		# 第一步：选发动方式；返回 WAIT（等回复）或下一步的 step
		var r: int = _jiao_xiang_choose()
		if r == WAIT:
			return WAIT
		_jiao_xiang_step = r
	if _jiao_xiang_step == SHENG_LI_STONE:
		# 第二步：选了「提炼星石」后，再问提炼哪种（取消＝不发动，沿用第一步的 step 收尾）
		if _jiao_xiang_stone() == WAIT:
			return WAIT
		_jiao_xiang_step = GE_YONG_TIAN_FU
	if _jiao_xiang_step == GE_YONG_TIAN_FU:
		var r2: int = SUCCESS
		if use_yue_zhang:
			r2 = _ge_yong_tian_fu()
		_jiao_xiang_step = 0
		if r2 == URGENT:
			step = STEP_DONE
			return URGENT
	return SUCCESS


## 胜利交响诗第一步的选项：1＝提炼星石（我方战绩区有星石时才提供）、2＝战绩区 +1 宝石且你 +1 治疗
func _jiao_xiang_options(color: int) -> Array:
	var out: Array = []
	if engine.team_gem[color] + engine.team_crystal[color] > 0:
		out.append({"value": 1, "label": "将己方【战绩区】的 1 星石提炼为你的能量"})
	out.append({"value": 2, "label": "己方【战绩区】+1【宝石】，你 +1【治疗】"})
	return out


## 胜利交响诗第二步的选项：1＝水晶、2＝宝石（我方战绩区里有那种星石才提供）
func _stone_options(color: int) -> Array:
	var out: Array = []
	if engine.team_crystal[color] > 0:
		out.append({"value": 1, "label": "提炼 1 个【水晶】"})
	if engine.team_gem[color] > 0:
		out.append({"value": 2, "label": "提炼 1 个【宝石】"})
	return out


## 胜利交响诗第一步：选发动方式。返回 WAIT（等回复）或下一步的 step：
##   选 1（提炼星石）→ SHENG_LI_STONE（继续问提炼哪种石头）
##   选 2（战绩区 +1 宝石且你 +1 治疗）/ 取消 → GE_YONG_TIAN_FU
## 客户端选项约定：点某项回 args=[该项 value]，取消回 args=[0]
func _jiao_xiang_choose() -> int:
	var holder: BattlePlayer = engine.p(engine.current_id)
	if holder == null:
		return GE_YONG_TIAN_FU
	var color: int = holder.color
	if not engine.has_reply():
		询问(engine.current_id, SHENG_LI_JIAO_XIANG_SHI_2, 0, 0, GConst.CardSource.Hand, _jiao_xiang_options(color))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var answer: int = int(args[0]) if not args.is_empty() else 0
	if answer == 1:
		return SHENG_LI_STONE
	if answer == 2:
		engine.set_team_gem(color, engine.team_gem[color] + 1)
		施加治疗(holder.id, 1)
		use_yue_zhang = true
		engine._broadcast_game()
	# 取消（args[0] <= 0）＝不发动，不置 use_yue_zhang
	return GE_YONG_TIAN_FU


## 胜利交响诗第二步：选提炼哪种星石（1＝水晶、2＝宝石）。取消＝不发动。返回下一步的 step。
func _jiao_xiang_stone() -> int:
	var holder: BattlePlayer = engine.p(engine.current_id)
	if holder == null:
		return GE_YONG_TIAN_FU
	var color: int = holder.color
	if not engine.has_reply():
		询问(engine.current_id, SHENG_LI_JIAO_XIANG_SHI_2, 0, 0, GConst.CardSource.Hand, _stone_options(color), 0, "", [], true, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var kind: int = int(args[0]) if not args.is_empty() else 0
	if kind == 1:
		holder.set_crystal(holder.crystal + 1)
		engine.set_team_crystal(color, engine.team_crystal[color] - 1)
	elif kind == 2:
		holder.set_gem(holder.gem + 1)
		engine.set_team_gem(color, engine.team_gem[color] - 1)
	else:
		# 取消＝不发动，不置 use_yue_zhang
		return GE_YONG_TIAN_FU
	use_yue_zhang = true
	engine._broadcast_game()
	return GE_YONG_TIAN_FU


# ============================================================
# 伤害结算后：沉沦协奏曲（3101）
# ============================================================
## 【沉沦协奏曲】的推进阶段（0＝还没开始 / CHEN_LUN_XIE_ZOU_QU＝在问是否弃牌发动）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次我方对敌方造成法术伤害并结算后（p_harm_end）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _chen_lun_step: int = 0


func p_harm_end(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if _chen_lun_step >= STEP_DONE:
		return SUCCESS
	if _chen_lun_step == 0:
		_chen_lun_step = CHEN_LUN_XIE_ZOU_QU
	if _chen_lun_step == CHEN_LUN_XIE_ZOU_QU:
		var dst_id: int = int(ctx.get("dst", -1))
		var src_id: int = int(harm.get("src", -1))
		var dst_p: BattlePlayer = engine.p(dst_id)
		var src_p: BattlePlayer = engine.p(src_id)
		if dst_p == null or src_p == null:
			return SUCCESS
		# 受伤者须为敌方、施害者须为我方，且自身未横置、本回合未发动过
		if dst_p.color == player.color or src_p.color != player.color:
			return SUCCESS
		if chen_lun_used or player.tap:
			return SUCCESS
		if not chen_lun_dsts.has(dst_id):
			chen_lun_dsts.append(dst_id)
		if chen_lun_dsts.size() < CHEN_LUN_NEED_KINDS:
			_chen_lun_step = 0
			return SUCCESS
		if not engine.has_reply():
			# 要弃 2 张同系手牌（校验里 cards.size() != 2 且两张必须同系）：
			# need_card 必须是 2，并让客户端只让同系牌可点
			询问(player.id, CHEN_LUN_XIE_ZOU_QU, 2, 1, GConst.CardSource.Hand, [], 0, "same")
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_chen_lun_step = 0
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		var cards: Array = r.get("card_ids", [])
		if args.is_empty() or int(args[0]) != 1 or dsts.is_empty() or cards.size() != 2:
			return SUCCESS
		if not player.has_hand_card(int(cards[0])) or not player.has_hand_card(int(cards[1])):
			return SUCCESS
		var c0: GCard = Data.get_card(int(cards[0]))
		var c1: GCard = Data.get_card(int(cards[1]))
		if c0 == null or c1 == null or c0.element_enum() != c1.element_enum():
			return SUCCESS
		var use_cards: Array = [int(cards[0]), int(cards[1])]
		chen_lun_used = true
		notice_skill(CHEN_LUN_XIE_ZOU_QU, dsts)
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": use_cards, "is_real": true,
		})
		if c0.is_magic() or c1.is_magic():
			engine.push_harm({
				"src": player.id, "dst": int(dsts[0]), "point": 1,
				"cause": CHEN_LUN_XIE_ZOU_QU, "type": GConst.HarmType.Magic,
			})
		engine.take_from_hand(player.id, use_cards, true)
		engine.to_discard(use_cards)
		engine._broadcast_game()
		if c0.is_magic() or c1.is_magic():
			return URGENT
	return SUCCESS


# ============================================================
# 启动（自己回合）：希望赋格曲（3107）
# ============================================================
## 【希望赋格曲】的推进阶段（0＝还没开始 / XI_WANG_FU_GE_QU＝在问是否把乐章转移给队友）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合开始（p_boot）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _fu_ge_step: int = 0


func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if _fu_ge_step >= STEP_DONE:
		return SUCCESS
	if _fu_ge_step == 0:
		_fu_ge_step = XI_WANG_FU_GE_QU
	if not _can_xi_wang():
		_fu_ge_step = 0
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, XI_WANG_FU_GE_QU, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_fu_ge_step = 0
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null or dst.color != player.color:
		return SUCCESS
	notice_skill(XI_WANG_FU_GE_QU, [dst.id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	if yue_zhang_dst != -1:
		var old: BattlePlayer = engine.p(yue_zhang_dst)
		if old != null:
			old.remove_exclusive_effect(GConst.Exclusive.YongHengYueZhang)
	yue_zhang_dst = dst.id
	dst.add_exclusive_effect(GConst.Exclusive.YongHengYueZhang)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能：不谐和弦（3102）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		BU_XIE_HE_XIAN:
			var args: Array = action.get("args", [])
			if args.size() < 2:
				return GConst.GE_INVALID_ARGUMENT
			var num: int = int(args[0])
			var choice: int = int(args[1])
			if num <= 1 or num > _ling_gan() or choice < 1 or choice > 2:
				return GConst.GE_INVALID_ARGUMENT
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != BU_XIE_HE_XIAN:
		return GConst.GE_INVALID_ACTION
	return _bu_xie_he_xian(action)


## 不谐和弦：移除 X 点灵感，你与目标各摸 X－1 张牌（或各弃 X－1 张牌）
func _bu_xie_he_xian(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var num: int = int(args[0])
	var choice: int = int(args[1])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	if bu_xie_phase == 0:
		if player.tap:
			player.tap = false
		_set_ling_gan(_ling_gan() - num)
		notice_skill(BU_XIE_HE_XIAN, [dst_id])
		bu_xie_num = num
		bu_xie_dst = dst_id
		engine._broadcast_game()
		if choice == 1:
			engine.draw(dst_id, num - 1)
			engine.draw(player.id, num - 1)
			engine._broadcast_game()
			return SUCCESS
		bu_xie_phase = 1
	if bu_xie_phase == 1:
		# 服务端先压目标弃牌、后压自己弃牌（LIFO）→ 自己先弃，再让目标弃
		if _request_discard(player.id, bu_xie_num - 1, BU_XIE_HE_XIAN) == WAIT:
			return WAIT
		bu_xie_phase = 2
	if bu_xie_phase == 2:
		if _request_discard(bu_xie_dst, bu_xie_num - 1, BU_XIE_HE_XIAN) == WAIT:
			return WAIT
		bu_xie_phase = 0
	return SUCCESS

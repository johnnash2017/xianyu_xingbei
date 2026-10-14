extends BattleRole
## 吟游诗人（roleID 31）—— 移植自服务端 role/ShiRen.cpp
## 指示物：tokens[0] = 灵感（上限 3）
## 独有效果：【永恒乐章】GConst.Exclusive.YongHengYueZhang（放置于某名角色面前，由持有者触发）
## 技能：沉沦协奏曲（3101，响应：一回合内我方对 ≥2 名敌方角色造成法术伤害并结算完后，
##                 弃 2 张同系牌【展示】→ 对目标造成 1 点法术伤害）、
##       不谐和弦（3102，法术：点开技能先选「移除几点灵感」（X＞1，只是选择、先不扣），
##                 按「确定」发动后服务端再问一步 —— 选「你与目标各摸 X－1 张牌」或
##                 「各弃 X－1 张牌」+ 点目标；那一步可取消，取消就退回行动阶段重来）、
##       禁忌诗篇（3103，被动：永恒乐章被触发后 +1 灵感并把乐章收回；
##                 若灵感已达上限则横置并对自己造成 3 点法术伤害）、
##       激昂狂想曲（3105，响应：回合开始时若当前角色持有永恒乐章 →
##                 对两名目标各 1 点法术伤害，或弃 2 张牌）、
##       胜利交响诗（3106，响应：回合结束时若当前角色持有永恒乐章 →
##                 将我方 1 星石提炼为自身能量，或我方 +1 宝石且自身 +1 治疗）、
##       希望赋格曲（3107，启动：点开技能先选「摸不摸 1 张牌」，按「确定」发动后服务端再问两步 ——
##                 ① 选效果 + 点角色：「放置」只能点除自己外的队友、「转移」可点除当前持有者外的
##                 我方（含自己），乐章不在场上时不显示「转移」；
##                 ② 选了「转移」才问：弃 1 张牌 + 选 +1【治疗】或 +1【灵感】）
##
## 变通说明：
## - 服务端在 STATE_TURN_BEGIN_SHIREN 调用 p_turn_begin_shiren；本引擎只在回合开始调用
##   p_turn_begin，故「激昂狂想曲」并入 p_turn_begin（判定当前回合角色是否为乐章持有者）。
## - 灵感上限：以服务端 tokenMax[0] 与角色表为准取 3（技能旧文本里的「上限 4」不采用）。
## - 开局乐章不在任何人面前：设计表里没有【歌咏天赋】那条被动（服务端构造里
##   「诗人初始拥有永恒乐章」的语句也是注释掉的，YueZhangDst = -1），
##   所以要靠【希望赋格曲】把它放出去（可以放在自己面前）。

const CHEN_LUN_XIE_ZOU_QU: int = 3101
const BU_XIE_HE_XIAN: int = 3102
const GE_YONG_TIAN_FU: int = 3103
const JI_ANG_KUANG_XIANG_QU: int = 3105
const SHENG_LI_JIAO_XIANG_SHI: int = 3106
const XI_WANG_FU_GE_QU: int = 3107

## 本引擎自有的分步标记（服务端把子步骤实现为压栈状态，此处用角色的自有分步变量记录进度）
const SHENG_LI_STONE: int = 31062          # 胜利交响诗：选完「提炼星石」后问提炼哪种星石

const TOKEN_LING_GAN: int = 0
const GE_YONG_HARM: int = 3                # 禁忌诗篇：灵感已满时的自伤
const CHEN_LUN_NEED_KINDS: int = 2         # 沉沦协奏曲：需要命中的敌方角色种类数

## 希望赋格曲的两种效果（按乐章当前在不在别人面前自动区分，玩家不用再选一次）
const XI_WANG_PLACE: int = 1               # ① 放置：乐章不在任何人面前
const XI_WANG_MOVE: int = 2                # ② 转移：乐章已在某队友面前（要弃 1 张牌 + 得 1 点收益）
## 希望赋格曲两处询问的选项值（「摸不摸牌」「+1 治疗还是 +1 灵感」）
const XI_WANG_DRAW_YES: int = 1
const XI_WANG_DRAW_NO: int = 0
const XI_WANG_HEAL: int = 1
const XI_WANG_LING_GAN: int = 2

var yue_zhang_dst: int = -1                # 永恒乐章当前所在角色（-1 表示不在任何人面前）
var use_yue_zhang: bool = false            # 本次触发是否使用了永恒乐章
var chen_lun_used: bool = false            # 本回合是否已发动沉沦协奏曲
var chen_lun_dsts: Array = []              # 本回合我方法术伤害命中的敌方角色

## 不谐和弦的进度（主动法术技能不在钩子轮次内，step 不会被重置，故单独记阶段）：
## 0＝刚收到行动（灵感数在行动 args 里）/ 1＝在问「哪个效果 + 点目标」/ 2＝自己弃牌 / 3＝目标弃牌
var bu_xie_phase: int = 0
var bu_xie_dst: int = -1
var bu_xie_num: int = 0

## 希望赋格曲的进度（同上：启动技能里也要连着问玩家几次，靠自有阶段推进）：
## 0＝刚收到发动（扣费、按选项摸牌）/ 1＝在问「选效果 + 点角色」/ 2＝在问「弃牌 + 收益」
var xi_wang_phase: int = 0
var xi_wang_dst: int = -1
var xi_wang_kind: int = 0


func available_skills() -> Array:
	var out: Array = []
	# 不谐和弦（法术）：点开技能先选「移除几点灵感」（技能自带选项，选完按「确定」发动），
	# 之后服务端再问一步「各摸还是各弃 x 张牌」+ 点目标（那步可取消，退回行动阶段重来）
	if _ling_gan() > 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": BU_XIE_HE_XIAN,
			"need_card": 0, "need_target": 0, "arg_choices": _bu_xie_num_choices()})
	# 希望赋格曲（启动）：点开技能就先问「摸不摸牌」（技能自带选项，选完按「确定」发动），
	# 之后由服务端接着问「选效果 + 点角色」与（转移时）「弃 1 张牌 + 选收益」
	if _can_xi_wang():
		out.append({"type": GConst.ActionType.SpecialSkill, "id": XI_WANG_FU_GE_QU,
			"need_card": 0, "need_target": 0, "arg_choices": _xi_wang_draw_choices()})
	return out


## 希望赋格曲点开技能时的那个选项（描述：「你可以选择摸 1 张牌」）——
## args[0] 随行动一起回来，服务端在 p_special_skill 里结算
func _xi_wang_draw_choices() -> Array:
	return [
		{"text": "摸 1 张牌", "args": [XI_WANG_DRAW_YES]},
		{"text": "不摸牌", "args": [XI_WANG_DRAW_NO]},
	]


## 【希望赋格曲】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == XI_WANG_FU_GE_QU


# ============================================================
# 指示物与工具
# ============================================================
func _ling_gan() -> int:
	var t: Dictionary = player.tokens[TOKEN_LING_GAN]
	return int(t["num"])


func _ling_gan_max() -> int:
	return int(player.tokens[TOKEN_LING_GAN]["max"])


func _set_ling_gan(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_LING_GAN]
	t["num"] = clampi(v, 0, int(t["max"]))


## 不谐和弦点开技能时的选项：移除几点【灵感】（X＞1，且手里的灵感花得起）。
## 这一步只是选择，先不扣灵感 —— 后面那步取消的话退回行动阶段，重新点技能再选
func _bu_xie_num_choices() -> Array:
	var out: Array = []
	for num: int in range(2, _ling_gan() + 1):
		out.append({"text": "移除 %d 点灵感" % num, "args": [num]})
	return out


## 第二步的选项：双方各摸 / 各弃 x 张牌，x＝第一步选的灵感数 - 1
## （技能表原文：「你和目标角色各摸 (X-1) 张牌」「各弃 (X-1) 张牌」）
func _bu_xie_effect_options() -> Array:
	var x: int = bu_xie_num - 1
	return [
		{"value": 1, "label": "你和目标角色各摸 %d 张牌" % x},
		{"value": 2, "label": "你和目标角色各弃 %d 张牌" % x},
	]


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
	engine._log_discard(pid, chosen)
	engine._broadcast_game()
	return SUCCESS


## 「放置」可点的角色：除自己以外的队友（描述：「放置于目标队友面前」）
func _xi_wang_place_targets() -> Array:
	return ally_ids()


## 「转移」可点的角色：除当前持有者以外的我方角色（含自己；描述：「转移给我方另一目标角色」）
func _xi_wang_move_targets() -> Array:
	var out: Array = []
	if player.id != yue_zhang_dst:
		out.append(player.id)
	for pid: int in ally_ids():
		if pid != yue_zhang_dst:
			out.append(pid)
	return out


## 第二步的两个效果（值 → 文案 + 各自可点的角色）：
##   ① 放置：把乐章放到一名队友面前（不能是自己）；
##   ② 转移：转移给「另一名」我方角色（含自己、不含当前持有者），要弃 1 张牌并 +1 一点收益 ——
##      乐章不在场上就没得转、手上没牌也弃不出，这两种情况都不发这一项
func _xi_wang_effect_options() -> Array:
	var out: Array = []
	var 放置目标: Array = _xi_wang_place_targets()
	if not 放置目标.is_empty():
		out.append({
			"value": XI_WANG_PLACE, "label": "将【永恒乐章】放置于目标队友面前",
			"targets": 放置目标,
		})
	var 转移目标: Array = _xi_wang_move_targets()
	if yue_zhang_dst != -1 and not player.hand_cards.is_empty() and not 转移目标.is_empty():
		out.append({
			"value": XI_WANG_MOVE,
			"label": "将【永恒乐章】转移给我方另一目标角色，你弃 1 张牌，+1【治疗】或 +1【灵感】",
			"targets": 转移目标,
		})
	return out


## 第二步那次询问里可点角色的并集（还没选效果时用；选定某项后客户端按该项自己的白名单收紧）
func _xi_wang_targets() -> Array:
	var out: Array = []
	for 项: Dictionary in _xi_wang_effect_options():
		for pid: Variant in 项["targets"]:
			if not out.has(int(pid)):
				out.append(int(pid))
	return out


## 希望赋格曲的发动条件：耗 1 能量，且至少有一个发得出来的效果（可放对象或可转对象）。
## （服务端那段 do-while 里「手牌为空不能发」「全是光系且不足 4 张不能发」之类的条件已随旧流程去掉：
##   手牌为空时只是发不出「转移」那一项，照样能「放置」）
func _can_xi_wang() -> bool:
	return player.get_energy() >= 1 and not _xi_wang_effect_options().is_empty()


## 某名玩家的对手 id（激昂狂想曲的伤害分支只能选对手）
func _enemies_of(pid: int) -> Array[int]:
	var out: Array[int] = []
	var actor: BattlePlayer = engine.p(pid)
	if actor == null:
		return out
	for other_id: int in engine.order:
		var other: BattlePlayer = engine.p(other_id)
		if other != null and other.color != actor.color:
			out.append(other_id)
	return out


func p_before_turn_begin(_ctx: Dictionary) -> int:
	chen_lun_used = false
	chen_lun_dsts.clear()
	use_yue_zhang = false
	return SUCCESS


# ============================================================
# 回合开始：激昂狂想曲（3105）+ 禁忌诗篇（3103）
# （服务端由 p_turn_begin_shiren 触发，本引擎并入 p_turn_begin）
# ============================================================
## 【激昂狂想曲 / 禁忌诗篇】的推进阶段（0＝还没开始 / JI_ANG_KUANG_XIANG_QU＝在问是否发动 /
## GE_YONG_TIAN_FU＝结算禁忌诗篇）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合开始（p_turn_begin）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 末段会返回 URGENT（禁忌诗篇压入了伤害状态），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _ji_ang_step: int = 0


func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != yue_zhang_dst:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if _ji_ang_step == 0:
		_ji_ang_step = JI_ANG_KUANG_XIANG_QU
	if _ji_ang_step == JI_ANG_KUANG_XIANG_QU:
		if not engine.has_reply():
			# 一步到位：分支和它要选的东西都在这一个询问里 ——
			# 伤害分支（值 1）选 2 名对手：目标数由客户端的「选项目标数」给成 2、白名单＝对手；
			# 弃牌分支（值 2）选 2 张手牌：选项自带 need_card＝2，选中后手牌才可点。
			# 「取消」回空 args＝不发动（通用客户端不再拿 0 当取消）
			# 顶部提示取技能表序号 2（「对两名目标各 1 点法术伤害」）：序号 1 那条写的是
			# 「选 1 名目标造伤」，与实际「对 2 名目标各 1 点」不符
			询问(engine.current_id, JI_ANG_KUANG_XIANG_QU, 0, 0, GConst.CardSource.Hand, [
				{"value": 1, "label": 提示(JI_ANG_KUANG_XIANG_QU, 2)},
				{"value": 2, "label": 提示(JI_ANG_KUANG_XIANG_QU, 3), "need_card": 2},
			], 2, "", [], true, 2, -1, _enemies_of(engine.current_id))
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		if choice == 1:
			var dsts: Array = r.get("dst_ids", [])
			# 场上不足 2 名对手时选不出 2 个目标，视为不发动
			if dsts.size() >= 2:
				use_yue_zhang = true
				_ji_ang_harm(dsts)
				_ji_ang_step = GE_YONG_TIAN_FU
				return URGENT
			_ji_ang_step = 0
			return SUCCESS
		if choice == 2:
			# 由当前角色（乐章持有者）弃 2 张牌（手牌不足 2 张时能弃几张弃几张）
			var 弃: Array = _pick_cards(engine.p(engine.current_id), r.get("card_ids", []), 2)
			if not 弃.is_empty():
				engine.take_from_hand(engine.current_id, 弃)
				engine.to_discard(弃)
				engine._log_discard(engine.current_id, 弃)
			use_yue_zhang = true
			_ji_ang_step = GE_YONG_TIAN_FU
		else:
			_ji_ang_step = 0
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


## 禁忌诗篇：乐章被触发后 +1 灵感并收回乐章；灵感已满则横置并自伤 3 点
func _ge_yong_tian_fu() -> int:
	notice_skill(GE_YONG_TIAN_FU, [player.id])
	use_yue_zhang = false
	if _ling_gan() < _ling_gan_max():
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
# 回合结束：胜利交响诗（3106）+ 禁忌诗篇（3103）
# ============================================================
## 【胜利交响诗 / 禁忌诗篇】的推进阶段（0＝还没开始 / SHENG_LI_JIAO_XIANG_SHI＝选发动方式 /
## SHENG_LI_STONE＝选提炼哪种星石 / GE_YONG_TIAN_FU＝结算禁忌诗篇）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合结束（p_turn_end）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 末段会返回 URGENT（禁忌诗篇压入了伤害状态），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _jiao_xiang_step: int = 0


func p_turn_end(_ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	if _jiao_xiang_step == 0:
		_jiao_xiang_step = SHENG_LI_JIAO_XIANG_SHI
	if _jiao_xiang_step == SHENG_LI_JIAO_XIANG_SHI:
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


## 胜利交响诗第一步的选项：1＝提炼星石、2＝战绩区 +1 宝石且你 +1 治疗（第 2 项始终提供）。
## 第 1 项是把战绩区的星石换成当前角色的能量：我方战绩区没有星石、或他能量已满（换了也进不去）
## 时都不提供这一项
func _jiao_xiang_options(color: int) -> Array:
	var out: Array = []
	var holder: BattlePlayer = engine.p(engine.current_id)
	var 能量没满: bool = holder != null and holder.get_energy() < holder.energy_max
	if engine.team_gem[color] + engine.team_crystal[color] > 0 and 能量没满:
		out.append({"value": 1, "label": 提示(SHENG_LI_JIAO_XIANG_SHI, 1)})
	out.append({"value": 2, "label": 提示(SHENG_LI_JIAO_XIANG_SHI, 2)})
	return out


## 胜利交响诗第二步的选项：1＝水晶、2＝宝石（我方战绩区里有那种星石才提供）
func _stone_options(color: int) -> Array:
	var out: Array = []
	if engine.team_crystal[color] > 0:
		out.append({"value": 1, "label": 提示(SHENG_LI_JIAO_XIANG_SHI, 3)})
	if engine.team_gem[color] > 0:
		out.append({"value": 2, "label": 提示(SHENG_LI_JIAO_XIANG_SHI, 4)})
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
		询问(engine.current_id, SHENG_LI_JIAO_XIANG_SHI, 0, 0, GConst.CardSource.Hand, _jiao_xiang_options(color))
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
		询问(engine.current_id, SHENG_LI_JIAO_XIANG_SHI, 0, 0, GConst.CardSource.Hand, _stone_options(color), 0, "", [], true, 1)
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
			询问(player.id, CHEN_LUN_XIE_ZOU_QU, 2, 1, GConst.CardSource.Hand, [], 0, "same", [], true, 0, -1, enemy_ids())
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_chen_lun_step = 0
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		var cards: Array = r.get("card_ids", [])
		if args.is_empty() or int(args[0]) != 1 or cards.size() != 2:
			return SUCCESS
		if not player.has_hand_card(int(cards[0])) or not player.has_hand_card(int(cards[1])):
			return SUCCESS
		var c0: GCard = Data.get_card(int(cards[0]))
		var c1: GCard = Data.get_card(int(cards[1]))
		if c0 == null or c1 == null or c0.element_enum() != c1.element_enum():
			return SUCCESS
		var use_cards: Array = [int(cards[0]), int(cards[1])]
		# 弃的牌里有法术牌才有那 1 点法术伤害；有它就必须指定目标（客户端「目标需法术牌」也这么拦），
		# 没有它时本来就没伤害，不选目标也照旧发动（弃 2 张同系牌、只拿 +1【灵感】）
		var 有法术牌: bool = c0.is_magic() or c1.is_magic()
		if 有法术牌 and dsts.is_empty():
			return SUCCESS
		chen_lun_used = true
		notice_skill(CHEN_LUN_XIE_ZOU_QU, dsts)
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": use_cards, "is_real": true,
		})
		var 打出伤害: bool = false
		if 有法术牌:
			# 目标必须是场上的对手（说明写「对目标对手」；改包点了队友就不结算这 1 点伤害）
			var 伤害目标: BattlePlayer = engine.p(int(dsts[0]))
			if 伤害目标 != null and 伤害目标.color != player.color:
				engine.push_harm({
					"src": player.id, "dst": int(dsts[0]), "point": 1,
					"cause": CHEN_LUN_XIE_ZOU_QU, "type": GConst.HarmType.Magic,
				})
				打出伤害 = true
		engine.take_from_hand(player.id, use_cards, true)
		engine.to_discard(use_cards)
		# 技能描述：弃完 2 张同系牌【展示】之后「你+1【灵感】」（以描述为准，先加再结算伤害）
		_set_ling_gan(_ling_gan() + 1)
		engine._broadcast_game()
		if 打出伤害:
			return URGENT
	return SUCCESS


# ============================================================
# 启动技能（行动阶段按钮）：希望赋格曲（3107）
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验本技能自己的条件）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XI_WANG_FU_GE_QU:
		return GConst.GE_INVALID_ACTION
	if not _can_xi_wang():
		return GConst.GE_INVALID_ACTION
	# 随行动回来的只有「摸不摸牌」这个选项值（1＝摸、0＝不摸）：点开技能就得选它，没选不算数。
	# 效果与目标由服务端在后面几步里问，不随行动提交
	var args: Array = action.get("args", [])
	if args.is_empty() or (int(args[0]) != XI_WANG_DRAW_YES and int(args[0]) != XI_WANG_DRAW_NO):
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	return _xi_wang_fu_ge_qu(action)


## 把【永恒乐章】挂到目标面前（放置与转移在这里合一：先从旧持有者身上取下）
func _xi_wang_attach(dst_id: int) -> void:
	if yue_zhang_dst != -1:
		var old: BattlePlayer = engine.p(yue_zhang_dst)
		if old != null:
			old.remove_exclusive_effect(GConst.Exclusive.YongHengYueZhang)
	yue_zhang_dst = dst_id
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null:
		dst.add_exclusive_effect(GConst.Exclusive.YongHengYueZhang)


## 希望赋格曲：点开技能时先选「摸不摸牌」（技能自带选项，随行动 args 回来），
## 之后由服务端再问两步，各一个「确定」——
##   ① 选哪个效果 + 点哪名角色 →（选了「转移」才有的）② 弃 1 张牌 + 选 +1【治疗】或 +1【灵感】。
## 两步都是不能取消的询问（中途没有回退）。超时由引擎回一条空 args 的回复兜底，据此自动代打：
##   ①＝第一项效果 + 它的第一个可点角色；②＝随机一项收益 + 随机弃一张。
## 「已执行过」由引擎的 SkillRun.checked 记着：回复后引擎会再进来一次接着走 xi_wang_phase
func _xi_wang_fu_ge_qu(action: Dictionary) -> int:
	if xi_wang_phase == 0:
		# 扣费、按选项摸牌与广播只在开头做一次，后面几步都只是选东西
		var args: Array = action.get("args", [])
		notice_skill(XI_WANG_FU_GE_QU, [player.id])
		player.boot_skill_used = true
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
		if not args.is_empty() and int(args[0]) == XI_WANG_DRAW_YES:
			# 先压「接着走第一步询问」的钩子、后压摸牌（状态栈后进先出）→ 摸牌（含【水影】响应）
			# 先结算，再问「选效果」；摸牌改走 push_draw 之后是延迟结算的，
			# 直接往下走会变成先问效果、最后才摸牌
			engine.push(BattleEngine.SHook.new("p_xi_wang_effects", {"player": player.id}, []))
			engine.push_draw(player.id, 1)
			engine._broadcast_game()
			xi_wang_phase = 1
			return SUCCESS
		engine._broadcast_game()
		xi_wang_phase = 1
	return _xi_wang_effects()


## 希望赋格曲：摸了那 1 张牌（含【水影】等摸牌前响应）结算完之后，接着走第一步询问
func p_xi_wang_effects(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	return _xi_wang_effects()


## 希望赋格曲：第一步起（选效果 + 点角色 →「转移」才有的第二步：弃 1 张牌 + 选收益）。
## 选了摸牌时它由 p_xi_wang_effects 钩子在摸牌之后调用；没选摸牌时 _xi_wang_fu_ge_qu 直接调用
func _xi_wang_effects() -> int:
	if xi_wang_phase == 1:
		# 第一个确认：选效果 + 点角色（两项各自的可点角色随选项下发，见 _xi_wang_effect_options）
		var 选项: Array = _xi_wang_effect_options()
		if 选项.is_empty():
			xi_wang_phase = 0
			return SUCCESS
		if not engine.has_reply():
			询问(player.id, XI_WANG_FU_GE_QU, 0, 1, GConst.CardSource.Hand, 选项, 0, "", [], false, 0, -1,
				_xi_wang_targets())
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		var 效果args: Array = r2.get("args", [])
		var 目标s: Array = r2.get("dst_ids", [])
		var 效果: int = int(效果args[0]) if not 效果args.is_empty() else int(选项[0]["value"])
		var 白名单: Array = _xi_wang_option_targets(效果)
		var 目标: int = int(目标s[0]) if not 目标s.is_empty() else -1
		if not 白名单.has(目标):
			# 超时兜底（或选了个不合法的）：按第一项效果 + 它的第一个可点角色代打
			效果 = int(选项[0]["value"])
			白名单 = _xi_wang_option_targets(效果)
			目标 = int(白名单[0]) if not 白名单.is_empty() else -1
		if 目标 < 0:
			xi_wang_phase = 0
			return SUCCESS
		xi_wang_kind = 效果
		xi_wang_dst = 目标
		if 效果 == XI_WANG_PLACE:
			# 放置：把乐章挂到目标面前，到此结束
			_xi_wang_attach(目标)
			xi_wang_phase = 0
			engine._broadcast_game()
			return SUCCESS
		xi_wang_phase = 2
	if xi_wang_phase == 2:
		# 第二个确认（只有「转移」）：弃 1 张牌 + 选 +1【治疗】或 +1【灵感】——
		# 弃牌是这一步的代价，和收益在同一个询问里选，不能取消
		if not engine.has_reply():
			询问(player.id, XI_WANG_FU_GE_QU, 1, 0, GConst.CardSource.Hand, [
				{"value": XI_WANG_HEAL, "label": "+1 治疗"},
				{"value": XI_WANG_LING_GAN, "label": "+1 灵感"},
			], 1, "", [], false, 0)
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		xi_wang_phase = 0
		var 回复args: Array = r3.get("args", [])
		var 回复牌: Array = r3.get("card_ids", [])
		# 超时兜底：引擎给的 args / card_ids 都是空的 → 收益随机挑一项、手牌随机抽一张
		var 收益: int = int(回复args[0]) if not 回复args.is_empty() \
			else (XI_WANG_HEAL if randi() % 2 == 0 else XI_WANG_LING_GAN)
		var 候选: Array = 回复牌
		if 候选.is_empty():
			# _pick_cards 按给定顺序补齐，先洗一遍手牌即是「随机弃一张」
			候选 = player.hand_cards.duplicate()
			候选.shuffle()
		var 弃: Array = _pick_cards(player, 候选, 1)
		if not 弃.is_empty():
			engine.take_from_hand(player.id, 弃)
			engine.to_discard(弃)
			engine._log_discard(player.id, 弃)
		if 收益 == XI_WANG_HEAL:
			施加治疗(player.id, 1)
		else:
			_set_ling_gan(_ling_gan() + 1)
		_xi_wang_attach(xi_wang_dst)
		engine._broadcast_game()
	return SUCCESS


## 某个效果可点的角色（放置＝除自己外的队友；转移＝除当前持有者外的我方，含自己）
func _xi_wang_option_targets(效果: int) -> Array:
	return _xi_wang_move_targets() if 效果 == XI_WANG_MOVE else _xi_wang_place_targets()


# ============================================================
# 主动法术技能：不谐和弦（3102）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != BU_XIE_HE_XIAN:
		return GConst.GE_INVALID_ACTION
	# 随行动回来的只有「移除几点灵感」这个选项值：点开技能就得选它，没选不算数。
	# 效果与目标由服务端再问一步，不随行动提交
	var args: Array = action.get("args", [])
	if args.is_empty() or int(args[0]) <= 1 or int(args[0]) > _ling_gan():
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	return _bu_xie_he_xian(action)


## 不谐和弦：点技能时先选「移除几点灵感」（技能自带选项，随行动 args 回来），
## 再问一步「各摸还是各弃 x 张牌」+ 点目标。
## 那一步可以取消 —— 取消＝这次不算发动（灵感也还没扣），退回行动阶段重新点技能来一遍
func _bu_xie_he_xian(action: Dictionary) -> int:
	if bu_xie_phase == 0:
		var args: Array = action.get("args", [])
		bu_xie_num = int(args[0]) if not args.is_empty() else 0
		if bu_xie_num <= 1 or bu_xie_num > _ling_gan():
			engine.取消技能行动()
			return SUCCESS
		bu_xie_phase = 1
	if bu_xie_phase == 1:
		# 第二步：选效果 + 点目标（可取消 → 退回行动阶段重新来）
		if not engine.has_reply():
			# 提示取技能表 3102「提示2」那条：张数传 bu_xie_num 填 {n}，额外传 n2 填 {n2}，
			# 避免客户端露出「移除 0 点灵感，双方各摸 {n2} 张牌」这种裸露占位符
			询问(player.id, BU_XIE_HE_XIAN, 0, 1, GConst.CardSource.Hand, _bu_xie_effect_options(), 0, "", [], true,
				1, -1, [], bu_xie_num, {"n2": bu_xie_num - 1})
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var 效args: Array = r.get("args", [])
		var 目标s: Array = r.get("dst_ids", [])
		if 效args.is_empty() or 目标s.is_empty():
			bu_xie_phase = 0
			engine.取消技能行动()
			return SUCCESS
		var choice: int = int(效args[0])
		bu_xie_dst = int(目标s[0])
		# 到这一步才真的扣灵感：点技能时那一步只是选择，取消掉就当没发动过
		if player.tap:
			player.tap = false
		_set_ling_gan(_ling_gan() - bu_xie_num)
		notice_skill(BU_XIE_HE_XIAN, [bu_xie_dst])
		engine._broadcast_game()
		if choice == 1:
			engine.push_draw(bu_xie_dst, bu_xie_num - 1)
			engine.push_draw(player.id, bu_xie_num - 1)
			engine._broadcast_game()
			bu_xie_phase = 0
			return SUCCESS
		bu_xie_phase = 2
	if bu_xie_phase == 2:
		# 服务端先压目标弃牌、后压自己弃牌（LIFO）→ 自己先弃，再让目标弃
		if _request_discard(player.id, bu_xie_num - 1, BU_XIE_HE_XIAN) == WAIT:
			return WAIT
		bu_xie_phase = 3
	if bu_xie_phase == 3:
		if _request_discard(bu_xie_dst, bu_xie_num - 1, BU_XIE_HE_XIAN) == WAIT:
			return WAIT
		bu_xie_phase = 0
	return SUCCESS

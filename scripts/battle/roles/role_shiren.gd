extends BattleRole
## 吟游诗人（roleID 31）—— 移植自服务端 role/ShiRen.cpp
## 指示物：tokens[0] = 灵感（上限 3）
## 独有效果：【永恒乐章】GConst.Exclusive.YongHengYueZhang（放置于某名角色面前，由持有者触发）
## 技能：沉沦协奏曲（3101，响应：一回合内我方对 ≥2 名敌方角色造成法术伤害并结算完后，
##                 弃 2 张同系牌【展示】→ 对目标造成 1 点法术伤害）、
##       不谐和弦（3102，法术：点开技能先选「移除几点灵感」（X＞1，只是选择、先不扣），
##                 按「确定」发动后服务端再问一步 —— 选「你与目标各摸 X－1 张牌」或
##                 「各弃 X－1 张牌」+ 点目标；那一步「返回」＝退回上一步重选，
##                 只有在第一步取消才退回行动阶段（这时不扣灵感、不消耗本回合行动））、
##       禁忌诗篇（3103，被动：永恒乐章被触发后 +1 灵感并把乐章收回；
##                 若灵感已达上限则横置并对自己造成 3 点法术伤害）、
##       激昂狂想曲（3105，响应：回合开始时若当前角色持有永恒乐章 →
##                 对两名目标各 1 点法术伤害，或弃 2 张牌）、
##       胜利交响诗（3106，响应：回合结束时若当前角色持有永恒乐章 →
##                 将我方 1 星石提炼为自身能量，或我方 +1 宝石且自身 +1 治疗）、
##       希望赋格曲（3107，启动：客户端本地走三步 ——「摸不摸 1 张牌」→「放置 / 转移」→
##                 （转移才有的）「+1【治疗】 / +1【灵感】 + 弃 1 张牌」——每步都能返回，
##                 全部选完按一次「确定」随行动一起提交；服务端 v_/p_ 一次校验、一次结算。
##                 「放置」只能点除自己外的队友、「转移」可点除当前持有者外的我方（含自己），
##                 乐章不在场上时「转移」置灰）
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

## 不谐和弦本次选定的目标角色（-1＝还没到第二步）；两步询问的进度由 多步询问 自己保存
var bu_xie_dst: int = -1


func available_skills() -> Array:
	var out: Array = []
	# 不谐和弦（法术）：点技能直接发动（客户端配「点技能即提交」，不用按确定），
	# 两步都由服务端问 —— ① 移除几点灵感 ② 各摸/各弃 + 点目标；
	# 两步都有「返回」：①退回行动阶段（技能栏），②退回①重选灵感数。
	# 灵感不多于 1 点时置灰
	out.append({"type": GConst.ActionType.MagicSkill, "id": BU_XIE_HE_XIAN,
		"need_card": 0, "need_target": 0, "enabled": _ling_gan() > 1})
	# 希望赋格曲（启动）：点开技能就先问「摸不摸牌」（技能自带选项，选完按「确定」发动），
	# 之后由服务端接着问「选效果 + 点角色」与（转移时）「弃 1 张牌 + 选收益」；不满足条件时置灰
	out.append({"type": GConst.ActionType.ActivateSkill, "id": XI_WANG_FU_GE_QU,
		"need_card": 0, "need_target": 0, "arg_choices": _xi_wang_draw_choices(),
		"enabled": _can_xi_wang()})
	return out


## 希望赋格曲点开技能时的那个选项（描述：「你可以选择摸 1 张牌」）——
## args[0] 随行动一起回来，服务端在 p_special_skill 里结算
func _xi_wang_draw_choices() -> Array:
	return [
		{"text": GConst.按钮原文(XI_WANG_FU_GE_QU, 2), "args": [XI_WANG_DRAW_YES]},
		{"text": GConst.按钮原文(XI_WANG_FU_GE_QU, 3), "args": [XI_WANG_DRAW_NO]},
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


## 第一步（服务端询问）的选项：移除几点【灵感】（X＞1，且手里的灵感花得起）。
## 这一步只是选择、先不扣灵感：点「返回」＝退回行动阶段（技能栏），第二步的「返回」＝回到这一步重选
func _bu_xie_num_choices() -> Array:
	var out: Array = []
	for num: int in range(2, _ling_gan() + 1):
		out.append({"value": num, "label": GConst.按钮原文(BU_XIE_HE_XIAN, 0) % num})
	return out


## 第二步的选项：双方各摸 / 各弃 x 张牌，x＝第一步选的灵感数 - 1
## （技能表原文：「你和目标角色各摸 (X-1) 张牌」「各弃 (X-1) 张牌」）
## 每项自带提示条文案：取技能说明里对应那一分支的原文（摸牌那句带【强制】，弃牌那句没有）
func _bu_xie_effect_options(答案: Array) -> Array:
	var x: int = _bu_xie_张数(答案)
	var 名: String = GConst.skill_name(BU_XIE_HE_XIAN)
	return [
		{"value": 1, "label": GConst.按钮原文(BU_XIE_HE_XIAN, 1) % x,
		 "提示": "【%s】：你和目标角色各摸 %d 张牌【强制】" % [名, x]},
		{"value": 2, "label": GConst.按钮原文(BU_XIE_HE_XIAN, 2) % x,
		 "提示": "【%s】：你和目标角色各弃 %d 张牌" % [名, x]},
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
##   ② 转移：转移给「另一名」我方角色（含自己、不含当前持有者），要弃 1 张牌并 +1 一点收益。
## 两项始终下发；当前做不了的那项 enabled=false，由界面置灰，不整项消失。
func _xi_wang_effect_options() -> Array:
	var 放置目标: Array = _xi_wang_place_targets()
	var 转移目标: Array = _xi_wang_move_targets()
	return [
		{
			"value": XI_WANG_PLACE, "label": GConst.按钮原文(XI_WANG_FU_GE_QU, 0),
			"targets": 放置目标, "enabled": not 放置目标.is_empty(),
		},
		{
			"value": XI_WANG_MOVE,
			"label": GConst.按钮原文(XI_WANG_FU_GE_QU, 1),
			"targets": 转移目标,
			"enabled": yue_zhang_dst != -1 and not player.hand_cards.is_empty() and not 转移目标.is_empty(),
		},
	]


## 按效果值取第二步选项（用于校验玩家是否选了当前可用的项）
func _xi_wang_option(效果: int) -> Dictionary:
	for 项: Dictionary in _xi_wang_effect_options():
		if int(项.get("value", -1)) == 效果:
			return 项
	return {}


## 希望赋格曲的发动条件：耗 1 能量，且至少有一个 enabled 的效果（可放对象或可转对象）。
func _can_xi_wang() -> bool:
	if player.get_energy() < 1:
		return false
	for 项: Dictionary in _xi_wang_effect_options():
		if bool(项.get("enabled", true)):
			return true
	return false


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
			# 顶部提示取技能表序号 0（「对两名目标各 1 点法术伤害」）
			询问(engine.current_id, JI_ANG_KUANG_XIANG_QU, 0, 0, GConst.CardSource.Hand, [
				{"value": 1, "label": GConst.按钮文本(JI_ANG_KUANG_XIANG_QU, 0),
					"enabled": _enemies_of(engine.current_id).size() >= 2},
				{"value": 2, "label": GConst.按钮文本(JI_ANG_KUANG_XIANG_QU, 1), "need_card": 2,
					"enabled": engine.p(engine.current_id).hand_count() >= 2},
			], 2, "", [], true, 0, -1, _enemies_of(engine.current_id))
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
				engine.to_discard(弃, {"owner": engine.current_id, "source": "hand"})
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
	var holder: BattlePlayer = engine.p(engine.current_id)
	var 能量没满: bool = holder != null and holder.get_energy() < holder.energy_max
	var 可提炼: bool = engine.team_gem[color] + engine.team_crystal[color] > 0 and 能量没满
	return [
		{"value": 1, "label": GConst.按钮文本(SHENG_LI_JIAO_XIANG_SHI, 0), "enabled": 可提炼},
		{"value": 2, "label": GConst.按钮文本(SHENG_LI_JIAO_XIANG_SHI, 1)},
	]


## 胜利交响诗第二步的选项：1＝水晶、2＝宝石（我方战绩区里有那种星石才提供）
func _stone_options(color: int) -> Array:
	return [
		{"value": 1, "label": GConst.按钮文本(SHENG_LI_JIAO_XIANG_SHI, 2),
			"enabled": engine.team_crystal[color] > 0},
		{"value": 2, "label": GConst.按钮文本(SHENG_LI_JIAO_XIANG_SHI, 3),
			"enabled": engine.team_gem[color] > 0},
	]


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
		engine.to_discard(use_cards, {"owner": player.id, "source": "hand"})
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
## 一次提交的内容（客户端本地走完「摸不摸 → 放置/转移 → 收益」再提交，每个中间步都能返回）：
##   args     = [摸不摸(1 摸 / 0 不摸), 效果(1 放置 / 2 转移), 收益(1 +1治疗 / 2 +1灵感；放置时为 0)]
##   dst_ids  = [目标角色]（放置＝队友；转移＝我方除当前持有者，含自己）
##   card_ids = [转移时弃的那 1 张手牌]（放置时为空）
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XI_WANG_FU_GE_QU:
		return GConst.GE_INVALID_ACTION
	if not _can_xi_wang():
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	if args.size() != 3:
		return GConst.GE_INVALID_ARGUMENT
	var 摸: int = int(args[0])
	var 效果: int = int(args[1])
	var 收益: int = int(args[2])
	if 摸 != XI_WANG_DRAW_YES and 摸 != XI_WANG_DRAW_NO:
		return GConst.GE_INVALID_ARGUMENT
	var 选择项: Dictionary = _xi_wang_option(效果)
	if 选择项.is_empty() or not bool(选择项.get("enabled", true)):
		return GConst.GE_INVALID_ARGUMENT
	var 目标s: Array = action.get("dst_ids", [])
	if 目标s.size() != 1 or not (选择项.get("targets", []) as Array).has(int(目标s[0])):
		return GConst.GE_INVALID_ARGUMENT
	var 牌s: Array = action.get("card_ids", [])
	if 效果 == XI_WANG_MOVE:
		# 转移要弃 1 张手牌、并选一项收益
		if 收益 != XI_WANG_HEAL and 收益 != XI_WANG_LING_GAN:
			return GConst.GE_INVALID_ARGUMENT
		if 牌s.size() != 1 or player.手牌实例(int(牌s[0])) < 0:
			return GConst.GE_INVALID_ACTION
	elif 收益 != 0 or not 牌s.is_empty():
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


## 希望赋格曲：客户端把「摸不摸 / 放置还是转移 / 收益 + 目标 + 弃牌」本地选完一次提交，
## 服务端一次结算（中途不再问玩家）。顺序照原文：付【水晶】→ 摸 1 张（可选）→ 放置 / 转移。
func _xi_wang_fu_ge_qu(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	notice_skill(XI_WANG_FU_GE_QU, [player.id])
	player.boot_skill_used = true
	# 费用写【水晶】：宝石可以顶水晶（约定§2），remove_energy 先扣水晶、再扣宝石
	player.remove_energy(1)
	engine._broadcast_game()
	if int(args[0]) == XI_WANG_DRAW_YES:
		# 摸牌要单独压状态（会触发【水影】这类「摸牌前」响应）：先把「接着结算」的钩子压上去、
		# 再压摸牌 —— 状态栈后进先出，摸完再回来把效果一次做完，中途不再问玩家
		engine.push(BattleEngine.SHook.new("p_xi_wang_apply", action, []))
		engine.push_draw(player.id, 1)
		return URGENT
	_xi_wang_apply(action)
	return SUCCESS


## 希望赋格曲：摸了那 1 张牌（含摸牌前响应）之后，把这次提交的效果一次做完
func p_xi_wang_apply(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return SUCCESS
	_xi_wang_apply(action)
	return SUCCESS


## 希望赋格曲的结算本体：放置 / 转移【永恒乐章】；转移时先弃 1 张牌，再 +1【治疗】或 +1【灵感】
func _xi_wang_apply(action: Dictionary) -> void:
	var args: Array = action.get("args", [])
	var 效果: int = int(args[1]) if args.size() > 1 else XI_WANG_PLACE
	var 收益: int = int(args[2]) if args.size() > 2 else 0
	var 目标s: Array = action.get("dst_ids", [])
	if 目标s.is_empty():
		engine.报错("【希望赋格曲】缺少目标角色", player.id)
		return
	var 目标: int = int(目标s[0])
	if 效果 == XI_WANG_MOVE:
		var 牌s: Array = action.get("card_ids", [])
		var 弃: int = player.手牌实例(int(牌s[0])) if not 牌s.is_empty() else -1
		if 弃 < 0 and not player.hand_cards.is_empty():
			# 提交时点的那张已经不在手里了（典型：选了摸牌、摸完爆牌时正好把它弃掉了）：
			# 代价不能静默不发生（约定§16），按手牌顺序补一张
			弃 = int(player.hand_cards[0])
		if 弃 >= 0:
			engine.take_from_hand(player.id, [弃])
			engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": XI_WANG_FU_GE_QU})
			engine._log_discard(player.id, [弃])
		if 收益 == XI_WANG_HEAL:
			施加治疗(player.id, 1)
		elif 收益 == XI_WANG_LING_GAN:
			_set_ling_gan(_ling_gan() + 1)
	_xi_wang_attach(目标)
	engine._broadcast_game()


# ============================================================
# 主动法术技能：不谐和弦（3102）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != BU_XIE_HE_XIAN:
		return GConst.GE_INVALID_ACTION
	# 行动本身不带参数：移除几点灵感、各摸还是各弃，都由服务端两步询问收集
	if not (action.get("args", []) as Array).is_empty():
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	return _bu_xie_he_xian(action)


## 不谐和弦：两步都走服务端询问（客户端点技能即提交、第一步点选项即进第二步）——
##   ① 移除几点【灵感】（X＞1，花得起；返回/取消＝这次不发动，退回行动阶段，灵感一点不扣）
##   ② 各摸还是各弃 + 点目标（返回＝退回①重选灵感数）
## 选「各弃」再依次问 ③ 自己弃 X-1 张、④ 目标弃 X-1 张（手牌不够就按手牌数弃）；
## 选「各摸」直接双方各摸 X-1 张。灵感在②答完才扣。
func _bu_xie_he_xian(_action: Dictionary) -> int:
	var 名: String = GConst.skill_name(BU_XIE_HE_XIAN)
	return 多步询问(BU_XIE_HE_XIAN, [
		{"选项": _bu_xie_num_choices(),
		 "可取消": true, "取消": _bu_xie_不发动,
		 # 段号 0 的「可返回」＝客户端摆「返回」；空应答走「可取消」分支退回行动阶段
		 "可返回": true,
		 "询问文案": "【%s】：移除几点【灵感】？" % 名},
		{"选项": _bu_xie_effect_options,
		 "需目标": 1, "目标白": func(_答案: Array) -> Array: return engine.order,
		 "校验": _bu_xie_提交合法, "校验失败文案": "请选择 1 名目标角色，再按「确定」",
		 "可返回": true,
		 "提示数": func(答案: Array) -> int: return _bu_xie_张数(答案),
		 "询问文案": func(_答案: Array) -> String:
			return "【%s】：%s" % [名, GConst.skill_desc(BU_XIE_HE_XIAN)],
		 "答完": _bu_xie_记录选择},
		{"需牌": func(答案: Array) -> int: return _bu_xie_可弃张数(player.id, 答案),
		 "可取消": false,
		 "跳过": func(答案: Array) -> bool: return not _bu_xie_走弃牌(答案) or _bu_xie_可弃张数(player.id, 答案) <= 0,
		 "询问文案": func(答案: Array) -> String:
			return "【%s】：弃 %d 张牌" % [名, _bu_xie_可弃张数(player.id, 答案)],
		 "答完": func(回: Dictionary, 答案: Array) -> int: return _bu_xie_弃掉(player.id, 回, 答案)},
		{"需牌": func(答案: Array) -> int: return _bu_xie_可弃张数(bu_xie_dst, 答案),
		 "问谁": func(_答案: Array) -> int: return bu_xie_dst,
		 "可取消": false,
		 "跳过": func(答案: Array) -> bool: return not _bu_xie_走弃牌(答案) or _bu_xie_可弃张数(bu_xie_dst, 答案) <= 0,
		 "询问文案": func(答案: Array) -> String:
			return "【%s】：弃 %d 张牌" % [名, _bu_xie_可弃张数(bu_xie_dst, 答案)],
		 "答完": func(回: Dictionary, 答案: Array) -> int: return _bu_xie_弃掉(bu_xie_dst, 回, 答案)},
	], _bu_xie_结算)


## 第一步的返回/取消：这次不算发动（灵感还没扣），退回行动阶段
func _bu_xie_不发动() -> int:
	bu_xie_dst = -1
	engine.取消技能行动()
	return SUCCESS


## 第二步的提交必须「摸/弃那一项 + 1 名真实存在的目标角色」一次给齐：
## 只有选项（客户端提前提交）或目标不存在时驳回重问，不能静默当成「取消」把整次行动吞掉。
func _bu_xie_提交合法(回: Dictionary) -> bool:
	var args: Array = 回.get("args", [])
	if args.is_empty() or (int(args[0]) != 1 and int(args[0]) != 2):
		return false
	var dsts: Array = 回.get("dsts", [])
	if dsts.is_empty():
		return false
	return engine.p(int(dsts[0])) != null


## 第一步选了几点灵感（答案[0] 的 args[0]；还没答就是 0）
func _bu_xie_点数(答案: Array) -> int:
	if 答案.is_empty():
		return 0
	return int(((答案[0] as Dictionary).get("args", [0]) as Array)[0])


## 「各摸/各弃」的张数 = 灵感数 - 1
func _bu_xie_张数(答案: Array) -> int:
	return maxi(_bu_xie_点数(答案) - 1, 0)


## 第二步选的是不是「各弃」（选项值 2；还没答就当摸牌）
func _bu_xie_走弃牌(答案: Array) -> bool:
	if 答案.size() < 2:
		return false
	return int(((答案[1] as Dictionary).get("args", [1]) as Array)[0]) == 2


## 某名角色这一步实际要弃几张（最多到他的手牌数）
func _bu_xie_可弃张数(pid: int, 答案: Array) -> int:
	var 目标: BattlePlayer = engine.p(pid)
	if 目标 == null:
		return 0
	return mini(_bu_xie_张数(答案), 目标.hand_cards.size())


## 第二步答完：记目标，扣灵感（到这一步才扣），播报。
## 回包的键是多步询问统一给的 dsts（不是 Respond 上的 dst_ids）—— 取错键会永远取空，
## 于是每次都在这里判成「没选目标 → 取消技能行动」：技能不结算、灵感不扣、回合不结束，
## 表现就是「放完还能继续做其他行动」。漏选 / 点错由这一段自己的「校验」驳回重问。
func _bu_xie_记录选择(回: Dictionary, 答案: Array) -> int:
	var dsts: Array = 回.get("dsts", [])
	bu_xie_dst = int(dsts[0])
	if player.tap:
		player.tap = false
	_set_ling_gan(_ling_gan() - _bu_xie_点数(答案))
	notice_skill(BU_XIE_HE_XIAN, [bu_xie_dst])
	engine._broadcast_game()
	return SUCCESS


## 某一方弃牌那一段的答完：把选中的牌移出手中、进弃牌堆、写日志
func _bu_xie_弃掉(pid: int, 回: Dictionary, 答案: Array) -> int:
	var 目标: BattlePlayer = engine.p(pid)
	if 目标 == null:
		return SUCCESS
	var chosen: Array = _pick_cards(目标, 回.get("cards", []), _bu_xie_可弃张数(pid, 答案))
	if chosen.is_empty():
		return SUCCESS
	engine.take_from_hand(pid, chosen)
	engine.to_discard(chosen, {"owner": pid, "source": "hand", "cause": BU_XIE_HE_XIAN})
	engine._log_discard(pid, chosen)
	engine._broadcast_game()
	return SUCCESS


## 收尾：各摸 → 双方各摸 X-1 张；各弃 → 前面两段已经弃完
func _bu_xie_结算(答案: Array) -> int:
	if _bu_xie_走弃牌(答案):
		bu_xie_dst = -1
		return SUCCESS
	var 张: int = _bu_xie_张数(答案)
	if bu_xie_dst >= 0 and 张 > 0:
		# 原文这一条写的是【强制】：走强制摸牌，不让「摸牌前发动」的响应（如水影）插进来
		engine.push_强制摸牌(bu_xie_dst, 张, BU_XIE_HE_XIAN)
		engine.push_强制摸牌(player.id, 张, BU_XIE_HE_XIAN)
		bu_xie_dst = -1
		engine._broadcast_game()
		# 压了摸牌就必须 URGENT：先摸完再压行动结束响应
		return URGENT
	bu_xie_dst = -1
	return SUCCESS



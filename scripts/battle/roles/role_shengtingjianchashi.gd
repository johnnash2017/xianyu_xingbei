extends BattleRole
## 圣庭检察士（39）：狂信徒 / 裁决论定 / 恩典神授 / 净化之术 / 庇护领域 / 裁决者 / 神圣鞭策
##
## 【裁决】＝0 号指示物（角色表 0:裁决:3）。
## 【异端裁决所】＝场卡（F1）：id = "异端裁决所"，owner = 自己，
##   counter = 它拥有的【治疗】点数，**上限 4**（count_max = 4；客户端悬停提示按「当前/4」显示）。
##
## 口径：
## 1. 【狂信徒】开局放【异端裁决所】；「我方队友存在圣类命格时治疗上限 +1」每次自己回合开始按队友重算
##    （队友可能被替换 → 不能只在 setup 里加一次）；「你的【攻击行动】结束时」目标角色 +1 治疗 ——
##    原文写「目标角色」＝由你指定场上的任意一名角色（自己 / 队友 / 对手都能选），**不是**本次攻击目标。
## 2. 【裁决论定】用 F3 治疗溢出钩子：我方角色治疗溢出 → 裁决所 +1 治疗，若真的加了 → 你 +1 水晶。
## 3. 【恩典神授】照冒险家【冒险者天堂】的形状做：提炼时选「把星石直接交给目标队友」这种方式
##    （args 头位 3903，引擎按 GConst.提炼转交标记 走「天堂」分支，星石直接发给队友，不经自己手）。
##    v_extract 校验形状 / 目标队友空位 / 代价付得起；提炼结算后由 p_after_extract 扣代价 + 播报
##    （裁决所 3【治疗】优先，否则我方角色合计 2【治疗】，先自己后队友）。
##    提炼结算完再问「弃 1 张牌」：若为圣类命格可【展示】→ 对目标对手 1 点法术伤害③。
## 4. 【庇护领域】在 p_timeline_3（伤害结算前③）结算，本次伤害 -1（最少 0），你 +1【裁决】。
## 5. 【神圣鞭策】的 X 由玩家选（1~裁决数），然后逐名指定 X 名目标角色各摸 1 张，最后你弃 X 张。

const KUANG_XIN_TU: int = 3901
const CAI_JUE_LUN_DING: int = 3902
const EN_DIAN_SHEN_SHOU: int = 3903
const JING_HUA_ZHI_SHU: int = 3904
const BI_HU_LING_YU: int = 3905
const CAI_JUE_ZHE: int = 3906
const SHEN_SHENG_BIAN_CE: int = 3907

const CAI_SLOT: int = 0
const 裁决所名: String = "异端裁决所"
## 【异端裁决所】能存多少【治疗】点数（场卡计数上限；客户端悬停按「当前/上限」显示）
const 裁决所治疗上限: int = 4


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【狂信徒】：游戏初始拥有【异端裁决所】
	if not engine.有场卡(裁决所名):
		engine.加场卡({
			"id": 裁决所名, "owner": player.id, "attached": -1,
			"counter": 0, "counter_max": 裁决所治疗上限, "state": 0,
		})
	_重算治疗上限()


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 裁决: int = player.token_num(CAI_SLOT)
	# 神圣鞭策：选 X 的选项直接带「需目标 = min(X, 场上角色数)」——有可选目标时必须选满，
	# X 超过角色数时多出来的名额就是溢出（裁决照扣、牌照弃）；
	# 要弃的牌也在同一次里选（需牌 / 最多牌 = min(X, 手牌数)，手牌为 0 时不用选牌）
	var 手牌数: int = player.hand_cards.size()
	var 角色数: int = _全体角色().size()
	var 鞭策选项: Array = []
	for i: int in range(1, 裁决 + 1):
		var 需弃: int = mini(i, 手牌数)
		var 需目标: int = mini(i, 角色数)
		鞭策选项.append({
			"text": GConst.按钮原文(SHEN_SHENG_BIAN_CE, 0, {"n": i}),
			"args": [i],
			"need_target": 需目标,
			"target_max": 需目标,
			"need_card": 需弃,
			"card_max": 需弃,
		})
	return [
		{
			# 裁决者是「启动」：技能类型必须是 ActivateSkill（引擎按这个 + is_free_skill 判启动），
			# 写成 MagicSkill 会绕开「每回合一个启动技」，还会去消耗别人给的额外法术行动
			"type": GConst.ActionType.ActivateSkill,
			"id": CAI_JUE_ZHE,
			"enabled": player.get_energy() >= 1,
		},
		{
			# 神圣鞭策：X 由选项决定；同一次里选 X 名目标 + 要弃的牌，按「确定」一次性提交。
			# 手牌为 0 也能发动（只是没有牌可弃）
			"type": GConst.ActionType.MagicSkill,
			"id": SHEN_SHENG_BIAN_CE,
			"need_card": 0,
			"need_target": 0,
			"targets": _全体角色(),
			"arg_choices": 鞭策选项,
			"enabled": 裁决 >= 1 and player.get_energy() >= 1,
		},
	]


## 【裁决者】是「启动」技能：不消耗本回合行动，结算完重新进入行动阶段
func is_free_skill(skill_id: int) -> bool:
	return skill_id == CAI_JUE_ZHE


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != CAI_JUE_ZHE:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != CAI_JUE_ZHE:
		return EMPTY_HANDLE
	# 启动技每回合只能发动一个（引擎也会在行动入口拦；这里防直接调用绕过）
	if player.boot_skill_used or player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	player.boot_skill_used = true
	player.remove_energy(1)
	notice_skill(CAI_JUE_ZHE, [player.id])
	player.add_token(CAI_SLOT, 1)
	engine.场卡加计数(裁决所名, 2)
	engine._broadcast_game()
	return SUCCESS


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != SHEN_SHENG_BIAN_CE:
		return GConst.GE_INVALID_ACTION
	if player.token_num(CAI_SLOT) < 1 or player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	# 选项带 X（args[0]）：同一次里要选出 min(X, 场上角色数) 名目标（必须选满，目标不够才算溢出），
	# 以及要弃的 min(X, 手牌数) 张牌。手牌为 0 也能发动（那就一张都不用弃）
	var args: Array = action.get("args", [])
	var x: int = int(args[0]) if not args.is_empty() else 0
	if x < 1 or x > player.token_num(CAI_SLOT):
		return GConst.GE_INVALID_ACTION
	var 目标: Array = action.get("dst_ids", [])
	if 目标.size() != mini(x, _全体角色().size()):
		return GConst.GE_INVALID_ACTION
	if _has_duplicate(目标):
		return GConst.GE_INVALID_ACTION
	for pid: Variant in 目标:
		if engine.p(int(pid)) == null:
			return GConst.GE_INVALID_PLAYERID
	var 需弃: int = mini(x, player.hand_cards.size())
	var 弃牌: Array = action.get("card_ids", [])
	if 弃牌.size() != 需弃:
		return GConst.GE_INVALID_ACTION
	for cid: Variant in 弃牌:
		if not player.有手牌(int(cid)):
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != SHEN_SHENG_BIAN_CE:
		return EMPTY_HANDLE
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var args: Array = action.get("args", [])
	var x: int = int(args[0])
	var 目标: Array[int] = []
	for pid: Variant in action.get("dst_ids", []):
		目标.append(int(pid))
	player.remove_energy(1)
	player.remove_token(CAI_SLOT, x)
	notice_skill(SHEN_SHENG_BIAN_CE, [player.id] + 目标)
	# 顺序：先让 X 名目标各摸 1 张牌【强制】，你再弃 X 张牌（手牌不足 X 张就按实际手牌弃）。
	# 弃哪些牌随发动一次提交（不再单独问），但要等摸牌结算完再弃 ——
	# 先压「弃牌」钩子、再压摸牌状态：栈顶先跑摸牌，回到底下的钩子时才弃牌
	var 弃: Array[int] = []
	for cid: Variant in action.get("card_ids", []):
		if 弃.size() < x and player.有手牌(int(cid)):
			弃.append(int(cid))
	_鞭策弃牌 = 弃
	_鞭策步 = 1
	engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
	for pid: int in 目标:
		engine.push_draw(pid, 1, SHEN_SHENG_BIAN_CE)
	return URGENT

var _鞭策步: int = 0
var _鞭策弃牌: Array[int] = []


# ============================================================
# 3901 狂信徒
# ============================================================
## 自己的回合开始：按队友命格重算治疗上限
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_重算治疗上限()
	return SUCCESS


## 【狂信徒】选「目标角色」的分步进度存 ctx：同一次行动的重入拿同一份 ctx，
## 下一次行动天然是新的一份，不会把上一击的进度带过来（与 10704 嫉妒追放同一写法）。
const KEY_KUANG_XIN_STEP: String = "_shengting_kuang_xin_step"
const KUANG_XIN_STEP_ASK: int = 1


## 你的【攻击行动】结束时：由你指定 1 名「目标角色」+1【治疗】。
## 原文写「目标角色」＝玩家可以指定场上的任意一名角色（自己 / 队友 / 对手都能选），
## 不是本次攻击的目标；原文没有「可」＝强制选人，不能取消。
## 超时 / 点到「跳过」时由引擎从「超时目标」里替选一名：只给友方（自己 + 队友），
## 不能让它从全体白名单里随机挑到敌人（需求方报过：跳过 / 超时把治疗加到敌人身上）。
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if str(ctx.get("kind", "")) != "attack":
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_KUANG_XIN_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		ctx[KEY_KUANG_XIN_STEP] = KUANG_XIN_STEP_ASK
		if not engine.has_reply():
			# 文案不在这里写死：客户端对技能询问默认显示技能说明（原文已写清效果落在谁身上）；
			# 目标白名单＝场上全部角色（「目标角色」＝要选人，不限于本次攻击目标）。
			# 超时 / 点跳过时的兜底目标：只从友方（自己 + 队友）里挑 ——
			# 不给「超时目标」的话，引擎会从全体白名单里随机挑，可能直接把治疗丢给敌人
			询问(player.id, KUANG_XIN_TU, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
				0, -1, _全体角色(), -1, {}, 0, 0, false, [], true, -1, 0,
				"", -1, "", [], _友方())
			return WAIT
	if 阶段 != KUANG_XIN_STEP_ASK:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	# 阶段在取完回复之后再推进：重入时阶段仍是 ASK，才能走到 take
	ctx[KEY_KUANG_XIN_STEP] = STEP_DONE
	var 回复: Dictionary = take_skill_reply_full()
	var 目标表: Array = 回复.get("dst_ids", [])
	# 0 是合法座位号，「没有」才是 -1（超时兜底会在不可取消 + 有目标时补一名，正常不会为空）
	var 目标号: int = int(目标表[0]) if 目标表.size() == 1 else -1
	if 目标号 < 0:
		# 跳过 / 兜底没给出目标：按「加给友方」处理，绝不落到敌人身上
		var 友: Array[int] = _友方()
		目标号 = 友[0] if not 友.is_empty() else player.id
	var dst: BattlePlayer = engine.p(目标号)
	if dst == null:
		return SUCCESS
	notice_skill(KUANG_XIN_TU, [dst.id])
	施加治疗(dst.id, 1)
	return SUCCESS


## 我方队友存在圣类命格时：你的治疗上限 +1
func _重算治疗上限() -> void:
	var 有圣: bool = false
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp == null or pp.id == player.id or pp.color != player.color:
			continue
		if Data.role_fate_pattern(pp.role_id) == "圣":
			有圣 = true
			break
	player.cross_max = GConst.CROSS_MAX + (1 if 有圣 else 0)


# ============================================================
# 3902 裁决论定：我方目标角色【治疗】溢出时
# ============================================================
func p_heal_overflow(ctx: Dictionary) -> int:
	var pid: int = int(ctx.get("player", -1))
	var 溢出者: BattlePlayer = engine.p(pid)
	if 溢出者 == null or 溢出者.color != player.color:
		return SUCCESS
	var 前: int = int(engine.取场卡(裁决所名).get("counter", 0))
	engine.场卡加计数(裁决所名, 1)
	var 后: int = int(engine.取场卡(裁决所名).get("counter", 0))
	if 后 <= 前:
		return SUCCESS
	notice_skill(CAI_JUE_LUN_DING, [pid])
	player.set_crystal(player.crystal + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 3903 恩典神授：提炼时把提炼出的星石直接交给目标队友（流程照冒险家【冒险者天堂】）
# ============================================================
## 提炼校验覆写（对照 role_maoxian.v_extract）：头位不是 3903 ＝ 常规提炼 / 别人的【冒险者天堂】，
## 退回通用校验；是 3903 时 args = [标记, 自己的宝石, 自己的水晶, 队友的宝石, 队友的水晶, 0,
## 目标颗数, 代价类型]（自己的那两位恒为 0，额外能量 X 恒为 0）——
## 代价类型 0＝移除【异端裁决所】3【治疗】（到此为止）；
## 代价类型 1＝移除我方角色合计 2【治疗】，后面再接 [人数, 目标1, 点数1, 目标2, 点数2]：
## 1 人扣 2 点、2 人各扣 1 点（由玩家在提炼前点选，点数必须正好凑满 2）。
func v_extract(args: Array, team_gem: int, team_crystal: int, dst_ids: Array) -> int:
	if args.is_empty() or int(args[0]) != EN_DIAN_SHEN_SHOU:
		return V_NOT_OVERRIDE
	if args.size() < 8 or dst_ids.size() != 1:
		return GConst.GE_INVALID_ARGUMENT
	var 自己宝石: int = int(args[1])
	var 自己水晶: int = int(args[2])
	var 队友宝石: int = int(args[3])
	var 队友水晶: int = int(args[4])
	var 多余能量: int = int(args[5])
	var 目标颗数: int = int(args[6])
	var 代价类型: int = int(args[7])
	var 总数: int = 队友宝石 + 队友水晶
	if 自己宝石 != 0 or 自己水晶 != 0 or 多余能量 != 0:
		return GConst.GE_INVALID_ACTION
	if 队友宝石 < 0 or 队友水晶 < 0 or 总数 < 1 or 总数 > 2:
		return GConst.GE_INVALID_ACTION
	if 目标颗数 != 总数:
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(int(dst_ids[0]))
	if dst == null or dst.color != player.color or dst.id == player.id:
		return GConst.GE_INVALID_PLAYERID
	if 总数 > dst.energy_max - dst.get_energy():
		return GConst.GE_INVALID_ACTION
	if 队友宝石 > team_gem or 队友水晶 > team_crystal:
		return GConst.GE_INVALID_ACTION
	# 代价按玩家选的那一种复核（另一种付得起也不行：提交哪种就付哪种）
	if 代价类型 == 0:
		if args.size() != 8:
			return GConst.GE_INVALID_ARGUMENT
		if not _恩典代价可付(0):
			return GConst.GE_INVALID_ACTION
	elif 代价类型 == 1:
		if _解析代价目标(args).is_empty():
			return GConst.GE_INVALID_ACTION
	else:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 提炼结算完的后续：先播报【恩典神授】、扣玩家选定的代价，再问「弃 1 张牌」；
## 若弃的是圣类命格，可【展示】换对目标对手的 1 点法术伤害。
## 只有「恩典神授」这种把星石交给队友的提炼才走这里（常规提炼 is_heaven = false，什么都不做）。
## 注意：引擎是先压 p_extract_to 再压 p_after_extract（后压先跑），所以代价与播报放这里，
## 不能再放 p_extract_to —— 否则会排到「弃牌 / 伤害」之后。
func p_after_extract(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_heaven", false)):
		return SUCCESS
	# 后续流程只起一次：等「弃 1 张牌」的回复时本钩子会重入同一份 ctx
	if bool(ctx.get("_恩典后续已启动", false)):
		return SUCCESS
	var 参: Array = ctx.get("args", [])
	var 代价类型: int = int(参[7]) if 参.size() > 7 else 0
	notice_skill(EN_DIAN_SHEN_SHOU, ctx.get("dst_ids", []))
	_付恩典代价(代价类型, 参)
	engine._broadcast_game()
	if player.hand_cards.is_empty():
		return SUCCESS
	ctx["_恩典后续已启动"] = true
	_恩典步 = 4
	engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
	return URGENT

var _恩典步: int = 0


## 恩典神授的某种代价现在付得起吗：0＝【异端裁决所】≥3【治疗】，1＝我方角色治疗合计 ≥2
func _恩典代价可付(类型: int) -> bool:
	if 类型 == 0:
		return int(engine.取场卡(裁决所名).get("counter", 0)) >= 3
	if 类型 != 1:
		return false
	var 合计: int = 0
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp != null and pp.color == player.color:
			合计 += pp.cross_num
	return 合计 >= 2


## 解析并校验「我方合计 2 治疗」的代价目标：
## args = [..., 代价类型=1, 人数, 目标1, 点数1, 目标2, 点数2]
## 规则：1~2 名我方角色、每人当前治疗够扣、点数合计正好 2（1 人＝2 点、2 人＝各 1 点）。
## 返回 [{"pid": int, "point": int}, ...]；形状 / 点数 / 治疗量不对返回空数组。
func _解析代价目标(args: Array) -> Array:
	if args.size() != 13:
		return []
	var 人数: int = int(args[8])
	if 人数 != 1 and 人数 != 2:
		return []
	var out: Array = []
	for i: int in range(人数):
		var pid: int = int(args[9 + i * 2])
		var 点: int = int(args[10 + i * 2])
		if 人数 == 1 and 点 != 2:
			return []
		if 人数 == 2 and 点 != 1:
			return []
		if i == 1 and pid == int(args[9]):
			return []
		var pp: BattlePlayer = engine.p(pid)
		if pp == null or pp.color != player.color:
			return []
		if pp.cross_num < 点:
			return []
		out.append({"pid": pid, "point": 点})
	return out


## 付玩家选定的代价：0＝裁决所的 3 治疗；1＝按选定的目标逐人扣（见 _解析代价目标）
func _付恩典代价(类型: int, 参: Array) -> void:
	if 类型 == 0:
		engine.场卡加计数(裁决所名, -3)
		return
	for 项: Dictionary in _解析代价目标(参):
		var pp: BattlePlayer = engine.p(int(项.get("pid", -1)))
		if pp != null:
			pp.sub_cross_num(mini(int(项.get("point", 0)), pp.cross_num))


# ============================================================
# 3904 净化之术：你承受伤害⑥并结算完成后
# ============================================================
func p_harm_end(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	# 同一次伤害只处理一次：这个钩子在等完回复后会带着**同一份 ctx** 重入，
	# 没有这道闸就会被「摸 1 张牌」补回来的法术牌反复触发（表现是无限循环地弹发动询问）
	if bool(ctx.get("_净化已处理", false)):
		return SUCCESS
	# 手里没有法术牌也照样问：让玩家看见这条响应（不可用的牌置灰，只能取消），
	# 也避免对手从「没弹询问」推断出圣庭检察士手里有没有法术牌（同【式神咒束】的口径）。
	# 发动＝选 1 张法术牌弃掉，**一次提交**：不再先问「是否发动」再问选牌。
	# 想放弃点「取消」＝不发动（服务端收到空回复直接跳过）。
	if not engine.has_reply():
		询问(player.id, JING_HUA_ZHI_SHU, 1, 0, GConst.CardSource.Hand, [], 1, "magic", [], true,
			0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0, "")
		return WAIT
	var r7: Dictionary = take_skill_reply_full()
	ctx["_净化已处理"] = true
	var cards7: Array = r7.get("card_ids", [])
	if cards7.is_empty() or not player.有手牌(int(cards7[0])):
		return SUCCESS
	var cid7: int = int(cards7[0])
	var 卡7: GCard = Data.get_card(cid7)
	if 卡7 == null or not 卡7.is_magic():
		return SUCCESS
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid7], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid7], false)
	engine.to_discard([cid7], {"owner": player.id, "source": "hand", "cause": JING_HUA_ZHI_SHU})
	engine._log_discard(player.id, [cid7])
	施加治疗(player.id, 1)
	engine.push_draw(player.id, 1, JING_HUA_ZHI_SHU)
	engine.场卡加计数(裁决所名, -1)
	return URGENT


# ============================================================
# 3905 庇护领域：我方目标角色受到伤害时③
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	if int(engine.取场卡(裁决所名).get("counter", 0)) < 3:
		return SUCCESS
	if bool(harm.get("庇护领域已减", false)):
		return SUCCESS
	if _庇护步 != 0 and not engine.has_reply():
		# 等回复期间（_庇护步 == 1 且有回复）放行到下面 take
		return SUCCESS
	_庇护步 = 1
	_庇护伤害 = harm
	if not engine.has_reply():
		# 发动询问不写 ask 文案：提示条默认显示技能表说明（技能维护约定「询问文案约定」第 1 条）。
		# 头像提示走通用「伤害预览」通道：把本次伤害的原值画在挨打的人头上（preview_base / kind / ids）
		询问(player.id, BI_HU_LING_YU, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {}, int(harm.get("point", 0)), int(harm.get("type", 0)), false,
			[dst.id], true, maxi(int(harm.get("point", 0)) - 1, 0), 0, "")
		return WAIT
	var 发动: bool = take_skill_reply()
	_庇护步 = 0
	if not 发动:
		return SUCCESS
	engine.场卡加计数(裁决所名, -3)
	player.add_token(CAI_SLOT, 1)
	notice_skill(BI_HU_LING_YU, [int(harm.get("dst", -1))])
	_庇护伤害["point"] = maxi(int(_庇护伤害.get("point", 0)) - 1, 0)
	_庇护伤害["庇护领域已减"] = true
	engine._broadcast_game()
	return SUCCESS

var _庇护步: int = 0
var _庇护伤害: Dictionary = {}


# ============================================================
# 统一的小段询问钩子：神圣鞭策 / 恩典神授 / 净化之术
# ============================================================
func p_sheng_ting_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 神圣鞭策：摸牌结算完之后才走到这里 —— 弃掉发动时选好的 X 张牌（不再询问）
	if _鞭策步 == 1:
		_鞭策步 = 0
		var 弃: Array[int] = _鞭策弃牌
		_鞭策弃牌 = []
		var 真弃: Array[int] = []
		for cid: int in 弃:
			if player.有手牌(cid):
				真弃.append(cid)
		if 真弃.is_empty():
			return SUCCESS
		engine.take_from_hand(player.id, 真弃, false)
		engine.to_discard(真弃, {"owner": player.id, "source": "hand", "cause": SHEN_SHENG_BIAN_CE})
		# 日志带张数 → 客户端播弃牌动画
		engine._log_discard(player.id, 真弃)
		engine._broadcast_game()
		return SUCCESS
	# 恩典神授：弃 1 张牌；圣命格可【展示】换 1 点法术伤害。
	# 弃牌 + 「展示 / 不展示」+「法术伤害打谁」都在同一条询问里选：展示默认选上，
	# 选「不展示」就只弃牌、不造成伤害（目标可选，不选也不造成伤害）
	if _恩典步 == 4:
		if not engine.has_reply():
			var 展示选项: Array = [
				{"value": 1, "label": GConst.按钮原文(EN_DIAN_SHEN_SHOU, 4)},
				{"value": 0, "label": GConst.按钮原文(EN_DIAN_SHEN_SHOU, 5)},
			]
			询问(player.id, EN_DIAN_SHEN_SHOU, 1, 0, GConst.CardSource.Hand, 展示选项, 1, "", [], true,
				0, player.id, enemy_ids(), 1, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(EN_DIAN_SHEN_SHOU, 3), 0)
			return WAIT
		var r5: Dictionary = take_skill_reply_full()
		var cards5: Array = r5.get("card_ids", [])
		var 目标5: Array = r5.get("dst_ids", [])
		var 参数5: Array = r5.get("args", [])
		_恩典步 = 0
		if cards5.is_empty() or not player.有手牌(int(cards5[0])):
			return SUCCESS
		var cid: int = int(cards5[0])
		var 圣: bool = Data.get_card(cid) != null \
			and Data.get_card(cid).fate_pattern_enum() == GConst.FatePattern.Holy
		# 展示：回复里选的那一项（1＝展示 / 0＝不展示）；没带参数按默认「展示」处理
		var 展示: bool = 参数5.is_empty() or int(参数5[0]) == 1
		# 只有弃的是圣类命格、玩家选了【展示】、且点了 1 名对手，才造成 1 点法术伤害
		var 伤害目标: int = -1
		if 圣 and 展示 and 目标5.size() == 1:
			var 目标者: BattlePlayer = engine.p(int(目标5[0]))
			if 目标者 != null and 目标者.color != player.color:
				伤害目标 = 目标者.id
		engine.take_from_hand(player.id, [cid], false)
		if 伤害目标 >= 0:
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": [cid], "is_real": true,
			})
		# 牌按标准弃置进弃牌堆（触发 F6 弃牌前拦截，如噬神者【渗蚀】）；
		# 日志带张数 → 客户端播弃牌动画（第 3 参留默认 true）
		engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": EN_DIAN_SHEN_SHOU})
		engine._log_discard(player.id, [cid])
		if 伤害目标 >= 0:
			engine.push_harm({
				"src": player.id, "dst": 伤害目标, "point": 1,
				"cause": EN_DIAN_SHEN_SHOU, "type": GConst.HarmType.Magic,
			})
			return URGENT
		return SUCCESS
	return SUCCESS


# ============================================================
# 小工具
# ============================================================
## 友方（自己 + 同队队友），按座位顺序
func _友方() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp != null and pp.color == player.color:
			out.append(pid)
	return out


func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out

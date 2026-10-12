extends BattleRole
## 女武神（roleID 25）—— 移植自服务端 role/NvWuShen.cpp
## 形态：tap（横置/英灵形态）+ cross_num（治疗）驱动
## 技能：神圣追击（2501，攻击/法术结束后治疗≥1 时追加一次攻击行动）、
##       秩序之印（2502，法术技能：摸 2 张牌并 +1 治疗 +1 水晶）、
##       和平行者（2503，被动：自身回合内发动【英灵召唤】后横置转为【英灵形态】；
##         主动攻击行动时解除横置，脱离【英灵形态】）、
##       军神威光（2504，回合开始且横置时询问：+1 治疗并脱离【英灵形态】，
##         或移除我方战绩区 1~2 星石，给一名角色 +X 治疗）、
##       英灵召唤（2505，自身攻击命中时询问：耗 1 能量并横置，伤害 +1，
##         可再弃 1 张法术牌【展示】换目标角色 +1 治疗）

const SHEN_SHENG_ZHUI_JI: int = 2501
const ZHI_XU_ZHI_YIN: int = 2502
const HE_PING_XING_ZHE: int = 2503
const JUN_SHEN_WEI_GUANG: int = 2504
const YING_LING_ZHAO_HUAN: int = 2505


## 本回合是否已授予过「神圣追击」（服务端 added_SHEN_SHENG_ZHUI_JI）
var added_shen_sheng_zhui_ji: bool = false

## 军神威光的推进阶段：两段询问 ——
##   0                              ＝ 还没开始（进第 1 段问「选项① 还是 选项②」）
##   JUN_SHEN_JIEDUAN_XUAN_XING_SHI ＝ 第 2 段：选「移除哪几个星石（组合）」+ 点一名目标 +X【治疗】
##                                    （仅选过选项②才进）
const JUN_SHEN_JIEDUAN_XUAN_XING_SHI: int = 1


func available_skills() -> Array:
	# 秩序之印无消耗，随时可用
	return [{"type": GConst.ActionType.MagicSkill, "id": ZHI_XU_ZHI_YIN, "need_card": 0, "need_target": 0}]


func p_before_turn_begin(_ctx: Dictionary) -> int:
	added_shen_sheng_zhui_ji = false
	_jun_shen_链中 = false
	return SUCCESS


## 【军神威光】的推进阶段（取值见上面那个常量，0＝还没开始）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合开始且处于横置（p_turn_begin）触发一次，走完 / 取消 / 超时都把阶段清回 0。
var _jun_shen_step: int = 0
## 【军神威光】是不是已经在这条询问链里了（第 1 段问过一次之后为 true）。
## 整条链共用第 1 次询问的倒计时：第 2 段、以及从第 2 段退回来重问第 1 段，都不重新计时
## （见 询问 的 保留倒计时），免得玩家靠「点进去 / 退回来」把等待时间刷新一遍。
## 每回合开始清回 false，每次自己回合开始才重新发起这条链。
var _jun_shen_链中: bool = false


# ============================================================
# 回合开始：军神威光（仅自身回合且处于横置形态时询问）
# 两段询问，逐段推进（阶段见 _jun_shen_step），整条链共用一个倒计时（见 _jun_shen_链中）：
#   第 1 段：问「发动哪个效果」——①＝你 +1【治疗】并【重置】脱离【英灵形态】；
#           ②＝移除我方【战绩区】X 个星石（X<3，即 1 或 2）后给一名目标角色 +X【治疗】。
#            这一段不能取消；整条链超时＝自动选①。
#   第 2 段：仅当第 1 段选了②才进——同一窗口里选「移除哪几个星石（组合）」+ 点一名角色 +X【治疗】
#            （X＝所选组合的星石数，两边共用 GConst.军神威光组合）。
#            这一段取消＝退回第 1 段重问（此时还没扣星石，可以让玩家改选①）；
#            「点进去 / 退回来」都不重新计时，靠的是询问的 保留倒计时。
# （对照原版 JunShenWeiGuang → JunShenWeiGuang2，本复刻在此基础上把 X 放宽到 1~2、治疗改为给目标）
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap:
		return SUCCESS
	if _jun_shen_step == 0:
		return _jun_shen_wen_guo_ju()
	if _jun_shen_step == JUN_SHEN_JIEDUAN_XUAN_XING_SHI:
		return _jun_shen_wen_xing_shi()
	return SUCCESS


## 第 1 段：问「选项① 还是 选项②」。不能取消（客户端「取消」键灰掉）；整条链超时＝自动选选项①。
func _jun_shen_wen_guo_ju() -> int:
	if not engine.has_reply():
		# 提示里的 {取消说明} 留空：这一段不能取消，不该出现「点取消返回上级」。
		# 保留倒计时＝已在链中就沿用最早的截止时刻（从第 2 段退回来重问时不重新计时）
		询问(player.id, JUN_SHEN_WEI_GUANG, 0, 0, GConst.CardSource.Hand, _jun_shen_wei_guang_choices(),
			0, "", [], false, 0, -1, [], -1, {"取消说明": ""}, 0, 0, _jun_shen_链中)
		_jun_shen_链中 = true
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var choice: int = 0
	if not args.is_empty():
		choice = int(args[0])
	elif bool(r.get("is_timeout", false)):
		# 本段不能取消，服务端超时兜底回的也是空 args：整条链超时＝自动选选项①
		choice = 1
	if choice == 1:
		return _jun_shen_xuan_xiang_1()
	if choice != 2:
		# 取消：不发动，链到此结束
		_jun_shen_step = 0
		_jun_shen_链中 = false
		return SUCCESS
	# 选了选项②：进入第 2 段（同一窗口里选星石 + 点目标），倒计时沿用
	_jun_shen_step = JUN_SHEN_JIEDUAN_XUAN_XING_SHI
	return _jun_shen_wen_xing_shi()


## 选项①：+1【治疗】并【重置】脱离【英灵形态】（第 1 段主动选①、或整条链超时都走这里）
func _jun_shen_xuan_xiang_1() -> int:
	_jun_shen_step = 0
	_jun_shen_链中 = false
	notice_skill(JUN_SHEN_WEI_GUANG, [player.id])
	施加治疗(player.id, 1)
	player.tap = false
	engine._broadcast_game()
	return SUCCESS


## 第 2 段：同一窗口里选「移除哪几个星石（组合）」+ 点一名角色 +X【治疗】（X＝组合的星石数）。
## 取消 / 非法组合 / 没点目标＝退回第 1 段重问（倒计时沿用，不重新计时）；
## 整条链（从第 1 段算起）超时＝按选项① 收尾。
func _jun_shen_wen_xing_shi() -> int:
	if not engine.has_reply():
		# 提示里的 {取消说明} 补上「返回上级」：这一段取消＝退回第一段重问。
		# 保留倒计时=true：整条链共用第 1 段那次等待的截止时刻
		询问(player.id, JUN_SHEN_WEI_GUANG, 0, 1, GConst.CardSource.Hand, _jun_shen_wei_guang_energy_choices(),
			0, "", [], true, 0, -1, engine.order, -1, {"取消说明": "，点「取消」返回上级"}, 0, 0, true)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 组合: int = int(args[0]) if not args.is_empty() else 0
	var 宝石用: int = _jun_shen_gem_of(组合)
	var 水晶用: int = _jun_shen_crystal_of(组合)
	var dsts: Array = r.get("dst_ids", [])
	if 宝石用 < 0 or 水晶用 < 0 or dsts.is_empty():
		_jun_shen_step = 0
		if bool(r.get("is_timeout", false)):
			# 整条链超时：自动按选项① 收尾，不再来回问
			return _jun_shen_xuan_xiang_1()
		# 取消 / 非法组合：退回第一段「是否发动军神威光」的二选一重问，而不是整场取消
		return _jun_shen_wen_guo_ju()
	_jun_shen_step = 0
	_jun_shen_链中 = false
	notice_skill(JUN_SHEN_WEI_GUANG, [int(dsts[0])])
	engine.set_team_gem(player.color, engine.team_gem[player.color] - 宝石用)
	engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 水晶用)
	施加治疗(int(dsts[0]), 宝石用 + 水晶用)
	engine._broadcast_game()
	return SUCCESS


## 军神威光第一段选项：+1 治疗并脱离【英灵形态】，或（战绩区有星石时）移除 1~2 星石给目标 +X 治疗
func _jun_shen_wei_guang_choices() -> Array:
	var 选项: Array = [{"value": 1, "label": 提示(JUN_SHEN_WEI_GUANG, 1)}]
	if engine.team_gem[player.color] + engine.team_crystal[player.color] > 0:
		选项.append({"value": 2, "label": 提示(JUN_SHEN_WEI_GUANG, 2)})
	return 选项


## 军神威光第二段选项：按战绩区现有的星石列出可行组合（总数 X<3，即 X＝1 或 2）
## （value 1＝两水晶 / 2＝一宝石一水晶 / 3＝两宝石 / 4＝一水晶 / 5＝一宝石）
func _jun_shen_wei_guang_energy_choices() -> Array:
	var 宝石: int = engine.team_gem[player.color]
	var 水晶: int = engine.team_crystal[player.color]
	var 选项: Array = []
	for 组合: int in range(1, 6):
		if 宝石 < _jun_shen_gem_of(组合) or 水晶 < _jun_shen_crystal_of(组合):
			continue
		选项.append({"value": 组合, "label": _jun_shen_combo_label(组合)})
	return 选项


## 军神威光星石组合 → 要移除的宝石数（-1＝非法值）。与 _jun_shen_crystal_of 成对使用
func _jun_shen_gem_of(组合: int) -> int:
	var 数: Variant = GConst.军神威光组合.get(组合)
	return int(数[0]) if 数 != null else -1


## 军神威光星石组合 → 要移除的水晶数（-1＝非法值）
func _jun_shen_crystal_of(组合: int) -> int:
	var 数: Variant = GConst.军神威光组合.get(组合)
	return int(数[1]) if 数 != null else -1


## 军神威光星石组合的选项文案：两星石三种沿用技能表提示，一星石两种技能表未配，就地给短标签
func _jun_shen_combo_label(组合: int) -> String:
	match 组合:
		1: return 提示(JUN_SHEN_WEI_GUANG, 3)
		2: return 提示(JUN_SHEN_WEI_GUANG, 4)
		3: return 提示(JUN_SHEN_WEI_GUANG, 5)
		4: return "移除 1 个【水晶】"
		_: return "移除 1 个【宝石】"


# ============================================================
# 攻击宣告后：和平行者（横置形态下主动攻击解除横置，被动）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)) or not player.tap:
		return SUCCESS
	notice_skill(HE_PING_XING_ZHE, [player.id])
	player.tap = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 自身攻击命中后：英灵召唤（耗 1 能量，伤害 +1；额外弃 1 张法术牌【展示】→ 选一名目标角色 +1【治疗】）
# 和平行者（2503）：仅自身回合内发动才【横置】转入【英灵形态】，别人回合内发动不转形态
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if player.get_energy() == 0 or step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 一次问齐「是否发动 + 弃不弃那张法术牌 + 治疗给谁」：
		# 弃牌可选（need_card=0、最多 1 张、只让法术牌可点），目标固定选 1 名（可含自己）。
		# 同时下发本次攻击的「原伤害」（预览基准）与「攻击目标」（预览目标）：客户端在那名敌人头像上
		# 写两行「原伤害划掉 / +1 后的伤害」（学【灵力崩解】）；治疗那行由静态指示器照常画
		询问(player.id, YING_LING_ZHAO_HUAN, 0, 1, GConst.CardSource.Hand, [], 1, "magic", [], true, 0, -1, engine.order,
			-1, {}, int(harm.get("point", 0)), int(harm.get("type", GConst.HarmType.Attack)), false,
			[int(harm.get("dst", -1))])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		# 取消 / 超时：不发动
		step = STEP_DONE
		return SUCCESS
	notice_skill(YING_LING_ZHAO_HUAN, [int(harm.get("dst", -1))])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	# 和平行者：仅自身回合内发动【英灵召唤】才【横置】转入【英灵形态】
	if engine.current_id == player.id:
		player.tap = true
		notice_skill(HE_PING_XING_ZHE, [player.id])
	harm["point"] = int(harm.get("point", 0)) + 1
	# 额外弃 1 张法术牌【展示】（可选）：客户端把「玩家选中的牌」放在 card_ids；
	# 弃了才给治疗，治疗对象就是同一次询问里点中的那名角色（没点／超时＝自己）
	var cards: Array = r.get("card_ids", [])
	var 弃了法术牌: bool = false
	if not cards.is_empty():
		var cid: int = int(cards[0])
		var card: GCard = Data.get_card(cid)
		if card != null and card.is_magic() and player.has_hand_card(cid):
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": [cid], "is_real": true,
			})
			engine.take_from_hand(player.id, [cid], true)
			engine.to_discard([cid])
			弃了法术牌 = true
	if 弃了法术牌:
		var dsts: Array = r.get("dst_ids", [])
		施加治疗(int(dsts[0]) if not dsts.is_empty() else player.id, 1)
	step = STEP_DONE
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击/法术行动结束后：神圣追击（治疗≥1 时追加一次攻击行动）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	return _shen_sheng_zhui_ji(int(ctx.get("player", -1)))


func p_after_magic(ctx: Dictionary) -> int:
	return _shen_sheng_zhui_ji(int(ctx.get("player", -1)))


## 神圣追击：攻击/法术结束后治疗≥1 时授予一次额外攻击行动
## 只挂行动并置回合内的「已授予」标记，扣治疗与技能通知在玩家选中时结算
func _shen_sheng_zhui_ji(pid: int) -> int:
	if pid != player.id or player.cross_num < 1 or added_shen_sheng_zhui_ji:
		return SUCCESS
	player.add_action(GConst.ActionType.Attack, SHEN_SHENG_ZHUI_JI)
	added_shen_sheng_zhui_ji = true
	return SUCCESS


# ============================================================
# 玩家选中额外行动时：结算神圣追击的代价（-1 治疗）
# 引擎在选中时会统一广播技能通知；服务端选中后会把「已授予」标记置回 false，
# 使本次额外攻击结束后仍可再次授予，故此处同步重置
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("cause", 0)) != SHEN_SHENG_ZHUI_JI:
		return SUCCESS
	player.sub_cross_num(1)
	added_shen_sheng_zhui_ji = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能：秩序之印
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != ZHI_XU_ZHI_YIN:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != ZHI_XU_ZHI_YIN:
		return GConst.GE_INVALID_ACTION
	notice_skill(ZHI_XU_ZHI_YIN, [player.id])
	# 服务端先压入「摸 2 张」状态（URGENT），再执行 +1 治疗 +1 水晶
	engine.push_draw(player.id, 2)
	施加治疗(player.id, 1)
	player.set_crystal(player.crystal + 1)
	engine._broadcast_game()
	return SUCCESS

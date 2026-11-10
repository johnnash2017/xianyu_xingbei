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

## 英灵召唤拆段：0＝问是否发动，1＝问额外弃牌+治疗目标
var _英灵_阶段: int = 0
## 已确认发动【英灵召唤】、正等第二问回复期间：这一手要不要在身上落【英灵形态】
## （只有自己回合内发动才横置）。形态等第二问的回复取走之后再改，见 p_timeline_2_hit 里的说明
var _英灵_待横置: bool = false



func available_skills() -> Array:
	# 秩序之印无消耗，随时可用
	return [{"type": GConst.ActionType.MagicSkill, "id": ZHI_XU_ZHI_YIN, "need_card": 0, "need_target": 0}]


func p_before_turn_begin(_ctx: Dictionary) -> int:
	# 每回合开始清一次链：上一回合没走完的（例如中途被别的效果打断）不能残留到这一回合
	多步询问重置(JUN_SHEN_WEI_GUANG)
	return SUCCESS


## 【军神威光】的状态（阶段常量已删：段进度由 BattleRole.多步询问 保存）
## 每回合开始清一次链，避免上一回合没走完的链残留。

# ============================================================
# 回合开始：军神威光（仅自身回合且处于横置形态时询问）
#   两段询问，用 BattleRole.多步询问 声明：
#     第 1 段：选①（+1 治疗并脱离形态）或②（移星石给目标 +X 治疗）；不可取消，超时＝①
#     第 2 段：选星石组合 + 点一名目标；可「返回」＝重问第 1 段，超时＝①；
#              第 1 段选了①时这一段自动跳过（条件段）
#   星石组合的合法性用段级「校验」，不合法就退回第 1 段重问（与原行为一致）。
#   副作用（扣星石、加治疗、清形态）全在结算里做，所以「返回」不用撤账。
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap:
		return SUCCESS
	return 多步询问(JUN_SHEN_WEI_GUANG, [
		{"选项": _jun_shen_wei_guang_choices(), "可取消": false, "超时默认": 1, "提示序号": -1},
		{"选项": _jun_shen_wei_guang_energy_choices(), "需目标": 1, "目标白": engine.order,
		 "询问文案": 提示原文(JUN_SHEN_WEI_GUANG, 2), "可返回": true,
		 "跳过": func(答案: Array) -> bool: return _jun_shen_选择(答案) != 2,
		 "校验": _jun_shen_第二段可用, "校验失败回退": true,
		 "超时": _jun_shen_xuan_xiang_1},
	], _jun_shen_settle)


## 第 1 段选了什么（1＝①，2＝②；还没答就是 0）
func _jun_shen_选择(答案: Array) -> int:
	if 答案.is_empty():
		return 0
	var a: Array = (答案[0] as Dictionary).get("args", [])
	return int(a[0]) if not a.is_empty() else 0


## 第 2 段的合法性：组合合法、星石够、点了目标
func _jun_shen_第二段可用(回: Dictionary) -> bool:
	var a: Array = 回.get("args", [])
	var 组合: int = int(a[0]) if not a.is_empty() else 0
	var 宝石用: int = _jun_shen_gem_of(组合)
	var 水晶用: int = _jun_shen_crystal_of(组合)
	if 宝石用 < 0 or 水晶用 < 0 or (回.get("dsts", []) as Array).is_empty():
		return false
	return 宝石用 <= engine.team_gem[player.color] and 水晶用 <= engine.team_crystal[player.color]


## 整条链走完：① 或 ② 各自结算
func _jun_shen_settle(答案: Array) -> int:
	if _jun_shen_选择(答案) != 2 or 答案.size() < 2:
		return _jun_shen_xuan_xiang_1()
	var a1: Array = (答案[1] as Dictionary).get("args", [])
	var 组合: int = int(a1[0]) if not a1.is_empty() else 0
	var 目标: Array = (答案[1] as Dictionary).get("dsts", [])
	var 宝石用: int = _jun_shen_gem_of(组合)
	var 水晶用: int = _jun_shen_crystal_of(组合)
	if 目标.is_empty() or 宝石用 < 0 or 水晶用 < 0:
		return _jun_shen_xuan_xiang_1()
	notice_skill(JUN_SHEN_WEI_GUANG, [int(目标[0])])
	engine.set_team_gem(player.color, engine.team_gem[player.color] - 宝石用)
	engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 水晶用)
	施加治疗(int(目标[0]), 宝石用 + 水晶用)
	engine._broadcast_game()
	return SUCCESS


## 选项①：+1【治疗】并【重置】脱离【英灵形态】（第 1 段选①、或整条链超时都走这里）
func _jun_shen_xuan_xiang_1() -> int:
	notice_skill(JUN_SHEN_WEI_GUANG, [player.id])
	施加治疗(player.id, 1)
	player.tap = false
	engine._broadcast_game()
	return SUCCESS


## 军神威光第一段选项：+1 治疗并脱离【英灵形态】，或（战绩区有星石时）移除 1~2 星石给目标 +X 治疗。
## 两项始终下发；没有星石时第二项 enabled=false，由界面置灰。
func _jun_shen_wei_guang_choices() -> Array:
	return [
		{"value": 1, "label": GConst.按钮文本(JUN_SHEN_WEI_GUANG, 0)},
		{"value": 2, "label": GConst.按钮文本(JUN_SHEN_WEI_GUANG, 1),
			"enabled": engine.team_gem[player.color] + engine.team_crystal[player.color] > 0},
	]


## 军神威光第二段选项：五种组合始终摆出来，凑不出的置灰
## （value 1＝两水晶 / 2＝一宝石一水晶 / 3＝两宝石 / 4＝一水晶 / 5＝一宝石）
func _jun_shen_wei_guang_energy_choices() -> Array:
	var 宝石: int = engine.team_gem[player.color]
	var 水晶: int = engine.team_crystal[player.color]
	var 选项: Array = []
	for 组合: int in range(1, 6):
		选项.append({
			"value": 组合, "label": _jun_shen_combo_label(组合),
			"enabled": 宝石 >= _jun_shen_gem_of(组合) and 水晶 >= _jun_shen_crystal_of(组合),
		})
	return 选项


## 军神威光星石组合 → 要移除的宝石数（-1＝非法值）。与 _jun_shen_crystal_of 成对使用
func _jun_shen_gem_of(组合: int) -> int:
	var 数: Variant = GConst.军神威光组合.get(组合)
	return int(数[0]) if 数 != null else -1


## 军神威光星石组合 → 要移除的水晶数（-1＝非法值）
func _jun_shen_crystal_of(组合: int) -> int:
	var 数: Variant = GConst.军神威光组合.get(组合)
	return int(数[1]) if 数 != null else -1


## 军神威光星石组合的选项文案：逐条取自技能表提示 4~8（战绩区 -N【…】）。
func _jun_shen_combo_label(组合: int) -> String:
	match 组合:
		1: return 提示原文(JUN_SHEN_WEI_GUANG, 3)
		2: return 提示原文(JUN_SHEN_WEI_GUANG, 4)
		3: return 提示原文(JUN_SHEN_WEI_GUANG, 5)
		4: return 提示原文(JUN_SHEN_WEI_GUANG, 6)
		_: return 提示原文(JUN_SHEN_WEI_GUANG, 7)


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
	var 链中: bool = 多步询问进行中(YING_LING_ZHAO_HUAN)
	if _英灵_阶段 >= 2 and not 链中:
		return SUCCESS
	# 能量够不够只在「还没发动」这一步判：第二段是发动时已经付过 1 能量的后续步骤
	if _英灵_阶段 == 0 and not 链中 and player.get_energy() == 0:
		return SUCCESS
	return 多步询问(YING_LING_ZHAO_HUAN, [
		# 第 1 段：是否发动（付 1 能量、本次伤害 +1、记下「要不要横置」）
		{"预览基准": int(harm.get("point", 0)),
		 "预览类型": int(harm.get("type", GConst.HarmType.Attack)),
		 "预览目标": [int(harm.get("dst", -1))],
		 "询问文案": GConst.skill_desc(YING_LING_ZHAO_HUAN),
		 "取消": _英灵不发动,
		 "答完": func(回: Dictionary, _答案: Array) -> int: return _英灵发动答完(harm, 回)},
		# 第 2 段：额外弃 1 张法术牌【展示】→ 选 1 名角色 +1 治疗（可取消，超时＝取消）
		# 跳过：第 1 段答了「不发动」（_英灵_阶段 已被答完置成 2）就不再问这一段。
		# 否则构造客户端回一句 args=[0] 就能跳过扣能量，白弃法术牌还 +1 治疗（框架的「答完」
		# 只能继续往下走，没有「到这一段就结束整链」的返回码，所以用条件段表达）。
		{"技能号": GConst.技能_英灵召唤治疗, "需牌": 1, "需目标": 1,
		 "牌规则": "magic", "牌上限": 1, "目标白": engine.order,
		 "跳过": func(_答案: Array) -> bool: return _英灵_阶段 >= 2,
		 "询问文案": GConst.提示原文(GConst.技能_英灵召唤, 1),
		 "取消": _英灵第二段取消},
	], _英灵召唤结算)


## 第 1 段取消 / 超时：本次不发动，同一处命中不再重问
func _英灵不发动() -> int:
	_英灵_阶段 = 2
	return SUCCESS


## 第 1 段答完：付 1 能量、本次伤害 +1、记下「要不要横置」；改形态留到第二段答完
func _英灵发动答完(harm: Dictionary, 回: Dictionary) -> int:
	var args: Array = 回.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		_英灵_阶段 = 2
		return SUCCESS
	notice_skill(YING_LING_ZHAO_HUAN, [int(harm.get("dst", -1))])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	# 和平行者：仅自身回合内发动【英灵召唤】才【横置】转入【英灵形态】。
	# 真正改形态留到第二问处理完（见 _英灵召唤结算）：player.tap 的 setter 会压入一轮 p_tap 钩子，
	# 那一轮里别的角色可能开询问（如兽灵【兽魂警戒】），会把还没处理的第二问回复顶掉。
	_英灵_待横置 = engine.current_id == player.id
	harm["point"] = int(harm.get("point", 0)) + 1
	_英灵_阶段 = 1
	return SUCCESS


## 第 2 段取消 / 超时：什么都不弃、不加治疗，但「已经付过能量」的横置照旧要处理
func _英灵第二段取消() -> int:
	_英灵召唤结算([])
	return SUCCESS


## 第 2 段答完：改形态 → 弃法术牌【展示】→ 选到人就 +1 治疗
func _英灵召唤结算(答案: Array) -> int:
	# 和平行者：等第二问的回复取走之后再改形态，避免钩子轮顶掉回复
	if _英灵_待横置:
		_英灵_待横置 = false
		player.tap = true
		notice_skill(HE_PING_XING_ZHE, [player.id])
	var 回: Dictionary = 答案[1] if 答案.size() > 1 else {}
	var cards: Array = 回.get("cards", [])
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
			engine.to_discard([cid], {"owner": player.id, "source": "hand"})
			弃了法术牌 = true
	if 弃了法术牌:
		var dsts: Array = 回.get("dsts", [])
		施加治疗(int(dsts[0]) if not dsts.is_empty() else player.id, 1)
	_英灵_阶段 = 2
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击/法术行动结束后：神圣追击（治疗≥1 时追加一次攻击行动）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_英灵_阶段 = 0
		_英灵_待横置 = false
	return _shen_sheng_zhui_ji(int(ctx.get("player", -1)))


func p_after_magic(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_英灵_阶段 = 0
		_英灵_待横置 = false
	return _shen_sheng_zhui_ji(int(ctx.get("player", -1)))


## 神圣追击：攻击/法术结束后治疗≥1 时授予一次额外攻击行动
## 只挂行动（in_end_response＝本次响应里的选项），扣治疗与技能通知在玩家选中时结算。
## 队列里已经有这一份就不再加：确认过的会标 direct 并留在队列里直到被使用，
## 响应里没确认的由引擎在响应结束时撤回（见 BattleEngine._撤回未确认额外行动），
## 所以不需要额外的「本回合已授予」标记 —— 撤回之后下一次行动结束就能重新摆出来。
func _shen_sheng_zhui_ji(pid: int) -> int:
	if pid != player.id or player.cross_num < 1:
		return SUCCESS
	if not player.额外行动队列数据(SHEN_SHENG_ZHUI_JI).is_empty():
		return SUCCESS
	player.add_action(GConst.ActionType.Attack, SHEN_SHENG_ZHUI_JI, false, false, {
		"in_end_response": true,
	})
	return SUCCESS


# ============================================================
# 玩家选中额外行动时：结算神圣追击的代价（-1 治疗）
# 引擎在选中时会统一广播技能通知；确认后这份行动标 direct 留在队列里，
# 被使用（进入额外行动阶段）时才离开队列，之后的攻击/法术结束可以再次授予
# ============================================================



## 行动结束响应点选神圣追击时立即扣 1 治疗（方案 A）
func 行动结束确认代价(cause: int) -> int:
	if cause != SHEN_SHENG_ZHUI_JI:
		return SUCCESS
	if player.cross_num < 1:
		return GConst.GE_INVALID_ACTION
	player.sub_cross_num(1)
	engine._broadcast_game()
	return SUCCESS


func p_additional_action(_ctx: Dictionary) -> int:
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
	# 服务端先压入「摸 2 张」状态（URGENT），再执行 +1 治疗 +1 水晶。
	# 必须返回 URGENT：返回 SUCCESS 的话 SkillRun 会把「法术行动结束响应」压到摸牌上面，
	# 变成先弹神圣追击 / 迅捷赐福响应、牌要等响应结束才摸（与技能本体不符）。
	engine.push_draw(player.id, 2)
	施加治疗(player.id, 1)
	player.set_crystal(player.crystal + 1)
	engine._broadcast_game()
	return URGENT

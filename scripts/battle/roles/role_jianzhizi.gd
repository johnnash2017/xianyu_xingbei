extends BattleRole
## 剑之子（roleID 108）—— 特典
## 技能：
##   倾慕（10801，被动）：若【剑之魔女】在场，你无法发动【剑守誓言】，
##       并获得【剑之魔女】的【剑影*断念】4504、【梦想剑】4503。
##   风之剑（10802，响应）：你使用技类命格牌作为主动攻击打出时，可移除我方【战绩区】1 星石，
##       视为你发动该牌上的剑圣独有技（101 疾风技 / 102 烈风技）。
##   剑守誓言（10803，响应）：你有主动攻击命中②或任意一方【星杯区】星杯数增加的回合结束后，
##       弃置牌库顶（X+1）张牌【展示】（X＝双方星杯数之和），你可选择其中 1 张加入手牌；
##       若这次弃牌中有法术牌：你 +2【水晶】，立即执行 1 个你的额外回合（该回合攻击伤害 +1），
##       永久将你的角色卡替换为【风之剑圣】。
##   剑残影（10804，响应 / 必杀技 / 回合限定 / 水晶）：【攻击行动】结束后支付 1【水晶】，
##       目标对手弃 1 张牌，额外 +1【攻击行动】；本回合你的下次主动攻击只能攻击该目标对手。
##
## 借用关系（见 data-audit §7 / A49~A52）：
##   - 10802 的 101/102 是本角色自己实现的：F5-sword helper 的询问 / 结算里没有「移除战绩区星石」
##     这一步，也承载不了星石类型选择；只复用它的判定口径，不改 skill_sword.gd / role_jiansheng.gd；
##     播报按本角色 10802（借用技能行）。
##   - 10801 的 4503/4504 从 role_jianzhimoni.gd 复制（任务板没有 45 的 helper 任务，data-audit Q3），
##     播报按源技能 4503 / 4504；不改 role_jianzhimoni.gd。
##   - 10803 的牌库顶语义按 F8：不移除时洗回弃牌堆，牌库不足只取实际张数；
##     「弃牌中有法术牌」按这次从牌库顶弃置的整批牌判断（含被选入手的 1 张，见下方结算注释）。
##   - 10803 先安排额外回合、再替换角色（F7 的顺序；替换会清旧角色的额外行动 / 行动计数，
##     所以必须把额外回合安排在替换之前）；角色替换后旧角色被解绑，之后不再调用本脚本任何方法。
##   - 10804 的「本回合你的下次主动攻击只能攻击该目标」是玩家身上的回合级标记
##     （player.set_attack_lock / 快照 attack_lock）：不写进行动规格，行动就是最普通的攻击行动；
##     服务端 base_v_attack 校验、引擎在攻击打出时消费，客户端按标记把其余敌方头像置灰。
##     聚合器里的【剑残影】选项另带敌方白名单，只约束「选谁来弃牌」这一步（服务端按 enemy_ids 复核）。

const 倾慕: int = 10801
const 风之剑: int = 10802
const 剑守誓言: int = 10803
const 剑残影: int = 10804

## 借用的剑圣 / 剑之魔女技能号（卡表 / 技能表里的源技能号）
const 疾风技: int = 101
const 烈风技: int = 102
const 梦想剑: int = 4503
const 剑影断念: int = 4504

const 剑之魔女: int = 45
const 风之剑圣: int = 1

## 10804 的固定费用（【水晶】，按约定宝石可顶：get_energy / remove_energy）
const 剑残影费用: int = 1
## 10803 有法术牌时的奖励
const 剑守誓言水晶: int = 2

# ============================================================
# 分步进度键（都放在钩子 ctx 里：同一次钩子重入拿同一份 ctx，不会串到下一次）
# ============================================================
## 攻击行动结束：10804 / 4504 的选项由行动聚合器收集，选中的直接结算。
const KEY_AFTER_CHOSEN: String = "_jianzhizi_after_chosen"
## 攻击结束二选一的同一条回复里带上的目标 / 弃牌（选剑残影时 1 名目标；选 4504 时 2 张弃牌）
const KEY_AFTER_TARGET: String = "_jianzhizi_after_target"
const KEY_AFTER_CARDS: String = "_jianzhizi_after_cards"
## 本次攻击结束已经选过的技能（防止同一技能在一次攻击结束里重复弹）
const KEY_10804_DONE: String = "_jianzhizi_10804_done"
const KEY_4504_DONE: String = "_jianzhizi_4504_done"
## 10802：0 未问 / 1 已问发动与星石类型
const KEY_10802_STEP: String = "_jianzhizi_10802_step"
## 10804：0 未开始 / 1 已确认发动 / 2 选目标 / 3 目标弃牌
## （二选一确认后从 2 开始，不再单独问一次「是否发动」）
const KEY_10804_STEP: String = "_jianzhizi_10804_step"
const KEY_10804_TARGET: String = "_jianzhizi_10804_target"
## 4504：0 未开始 / 1 等选 2 张弃牌（还没付款）
## （二选一确认后直接进 1，不再单独问一次「是否发动」；选完弃牌按确定才扣宝石）
const KEY_4504_STEP: String = "_jianzhizi_4504_step"
## 10803：0 未问发动 / 1 已移除并展示、等选 1 张
const KEY_10803_STEP: String = "_jianzhizi_10803_step"
const KEY_10803_CARDS: String = "_jianzhizi_10803_cards"

## 10804 的两个固定选项值
const 星石_宝石: int = 1
const 星石_水晶: int = 2

## 本回合的 10804 / 4504 回合限定
var _used_剑残影: bool = false
var _used_剑影断念: bool = false
## 4503 梦想剑本回合已激活的档位
var _dream_ignore_shield: bool = false
var _dream_no_reattack: bool = false
var _dream_no_miss: bool = false
## 展示档位：攻击行动结算完、进入「攻击结束」响应（p_after_attack）时推进；
## 此时还没到本回合结束阶段，实际效果仍由 _dream_* 在 p_action_end 后生效。
var _dream_display_tier: int = 0


## 梦想剑当前展示档位（供客户端角色说明标绿）：3 最强，其次 2、1，都没激活返回 0。
func dream_tier() -> int:
	return _dream_display_tier


## 攻击行动结算完、进入攻击结束响应时，按「本次是第几次攻击行动」推进展示档；
## 不改变实际效果 flags（flags 仍在 p_action_end 推进）。
func _更新梦想剑展示档() -> void:
	# 记录行动在攻击宣告前已经 +1，所以这里直接用当前计数＝本次是第几次攻击
	var 序号: int = player.attack_action_count
	var 档位: int = 1 if 序号 < 2 else (2 if 序号 < 4 else 3)
	if 档位 > _dream_display_tier:
		_dream_display_tier = 档位
		if engine != null:
			engine._broadcast_game()


## 兜底：如果这次行动结束没有经过 p_after_attack（正常不会），按 flags 补齐展示档。
func _同步梦想剑展示档() -> void:
	var 档位: int = 3 if _dream_no_miss else (2 if _dream_no_reattack else (1 if _dream_ignore_shield else 0))
	if 档位 > _dream_display_tier:
		_dream_display_tier = 档位


## 10803 的回合条件跟踪
var _本回合有主动攻击命中: bool = false
var _回合开始星杯总数: int = 0


# ============================================================
# 回合开始：清回合限定 / 梦想剑档位，重置 10803 的星杯基准
# （10804 的「下次主动攻击只能打谁」是玩家身上的标记，由引擎在攻击打出 / 回合开始时清）
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_used_剑残影 = false
	_used_剑影断念 = false
	_dream_ignore_shield = false
	_dream_no_reattack = false
	_dream_no_miss = false
	_dream_display_tier = 0
	_本回合有主动攻击命中 = false
	_回合开始星杯总数 = engine.星杯总数() if engine != null else 0
	return SUCCESS


# ============================================================
# 攻击宣告（timeline_1）：10802 风之剑 / 借用 4503 梦想剑
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	# 应战反击不是主动攻击：10802 / 4503 都不触发
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	var r: int = _feng_zhi_jian(ctx)
	if r == WAIT:
		return WAIT
	_apply_dream_sword(ctx)
	return SUCCESS


# ============================================================
# 10802 风之剑：技类命格攻击牌 → 移除 1 星石 → 发动牌上的 101 / 102
# ============================================================
func _feng_zhi_jian(ctx: Dictionary) -> int:
	var 阶段: int = int(ctx.get(KEY_10802_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		if not _可发动风之剑(ctx):
			return SUCCESS
		ctx[KEY_10802_STEP] = 1
		if not engine.has_reply():
			# 星石类型由玩家选（A50）；两个选项始终成对下发，做不了的置灰。
			# 取消＝不发动（不扣星石）。
			询问(player.id, 风之剑, 0, 0, GConst.CardSource.Hand, _星石选项())
			return WAIT
	if 阶段 != 1:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	ctx[KEY_10802_STEP] = STEP_DONE
	var args: Array = r.get("args", [])
	var 选择: int = int(args[0]) if not args.is_empty() else 0
	# 回复期间资源可能已变化：支付前按当前战绩区复核
	if 选择 == 星石_宝石:
		if engine.team_gem[player.color] <= 0:
			return SUCCESS
		engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
	elif 选择 == 星石_水晶:
		if engine.team_crystal[player.color] <= 0:
			return SUCCESS
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 1)
	else:
		return SUCCESS
	_发动牌上剑圣技(ctx)
	engine._broadcast_game()
	return SUCCESS


## 10802 能否发动：主动攻击、技类命格攻击牌、牌上带 101 或 102 且至少一项效果当前能生效、
## 我方战绩区至少 1 颗星石。
func _可发动风之剑(ctx: Dictionary) -> bool:
	var 牌: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 牌 == null or not 牌.is_attack():
		return false
	if 牌.fate_pattern_enum() != GConst.FatePattern.Martial:
		return false
	var 有101: bool = 牌.has_skill_id(疾风技)
	var 有102: bool = 牌.has_skill_id(烈风技)
	if not 有101 and not 有102:
		return false
	# 102 只在目标有【圣盾】/【天使之墙】时有实际效果；只有 102 且不满足条件时不问
	if not 有101 and not _目标有圣盾(engine.p(int(ctx.get("dst", -1)))):
		return false
	return engine.team_gem[player.color] + engine.team_crystal[player.color] > 0


## 发动牌上的剑圣独有技：101 额外 +1 攻击行动；102 本次攻击无法应战且不查圣盾。
func _发动牌上剑圣技(ctx: Dictionary) -> void:
	var 牌: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 牌 == null:
		return
	if 牌.has_skill_id(疾风技):
		# 真正发动的是牌上的【疾风技】101：先播报 101（客户端飘出「疾风技」），
		# 额外行动的来源也记 101，与其他玩家看到的是同一颗技能
		notice_skill(疾风技, [int(ctx.get("dst", -1))])
		player.add_action(GConst.ActionType.Attack, 疾风技, true, true)
	if 牌.has_skill_id(烈风技):
		var 目标: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
		if _目标有圣盾(目标):
			notice_skill(烈风技, [int(ctx.get("dst", -1))])
			ctx["hit_rate"] = GConst.HitRate.NoReattack
			ctx["check_shield"] = false


func _目标有圣盾(dst: BattlePlayer) -> bool:
	if dst == null:
		return false
	return dst.check_basic_effect_name(GConst.CardName.Shield) \
			or dst.check_basic_effect_skill(GConst.技能_天使之墙)


## 10802 的星石类型选项（固定两项，按战绩区置灰）
func _星石选项() -> Array:
	return [
		{"value": 星石_宝石, "label": GConst.按钮原文(风之剑, 0), "enabled": engine.team_gem[player.color] > 0},
		{"value": 星石_水晶, "label": GConst.按钮原文(风之剑, 1), "enabled": engine.team_crystal[player.color] > 0},
	]


# ============================================================
# 借用 4503 梦想剑（10801；只在剑之魔女在场时生效）
# ============================================================
## 攻击宣告时按本回合第几次攻击行动施加档位：第 1 档无视圣盾 / 第 2 档无法应战 / 第 4 档强制命中。
## 放在 10802 之后调用：102 的「无法应战」不应盖掉梦想剑第 4 档的「强制命中」。
func _apply_dream_sword(ctx: Dictionary) -> void:
	if not _剑之魔女在场():
		return
	if _dream_no_miss:
		ctx["hit_rate"] = GConst.HitRate.NoMiss
	elif _dream_no_reattack:
		ctx["hit_rate"] = GConst.HitRate.NoReattack
	if _dream_ignore_shield:
		ctx["check_shield"] = false


## 攻击行动结束时推进梦想剑档位（与 role_jianzhimoni.gd 同口径：计数含额外攻击行动）
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if str(ctx.get("kind", "")) != "attack":
		return SUCCESS
	if not _剑之魔女在场():
		return SUCCESS
	var n: int = player.attack_action_count
	if n == 1 and not _dream_ignore_shield:
		_dream_ignore_shield = true
		notice_skill(梦想剑, [player.id])
	elif n == 2 and not _dream_no_reattack:
		_dream_no_reattack = true
		notice_skill(梦想剑, [player.id])
	elif n >= 4 and not _dream_no_miss:
		_dream_no_miss = true
		notice_skill(梦想剑, [player.id])
	_同步梦想剑展示档()
	return SUCCESS


# ============================================================
# 攻击行动结束后（after_attack）：展示档由本钩子推进，行动选项交给行动聚合器
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 攻击已经结算完、进入「攻击结束」响应：此时才推进展示档，既不会在攻击宣告时就变绿，
	# 也能让 10804 / 4504 这类响应技能在决定时看到本回合的新档位（实际效果仍在 p_action_end 生效）。
	if _剑之魔女在场():
		_更新梦想剑展示档()
	return SUCCESS


func action_end_options(ctx: Dictionary) -> Array:
	# 剑残影 / 剑影*断念写的是「攻击行动结束时」：法术行动结束不能摆出来
	if not 是攻击行动结束(ctx):
		return []
	return _攻击结束选项(ctx, true)


func resolve_action_end_option(cause: int, reply: Dictionary, ctx: Dictionary) -> int:
	if cause != 剑残影 and cause != 剑影断念:
		return resolve_queued_extra_action(cause)
	if int(ctx.get(KEY_AFTER_CHOSEN, 0)) != cause:
		var 目标表: Array = reply.get("dst_ids", [])
		ctx[KEY_AFTER_TARGET] = int(目标表[0]) if not 目标表.is_empty() else -1
		ctx[KEY_AFTER_CARDS] = (reply.get("card_ids", []) as Array).duplicate()
		ctx[KEY_AFTER_CHOSEN] = cause
		if cause == 剑残影:
			ctx[KEY_10804_DONE] = true
		else:
			ctx[KEY_4504_DONE] = true
	return _解决攻击结束技能(ctx, cause, reply)


## 本次攻击结束还能发动的技能：两项都满足条件就一起摆出来；用过 / 条件不满足的不再出现。
## 选项要自带目标白名单（targets）：聚合器把整条响应包成同一次询问，客户端靠这项白名单
## 只点亮敌方头像 —— 少了它自己 / 队友也会亮，点了必被 _jian_can_ying 拒掉。
func _攻击结束选项(ctx: Dictionary, 显示全部: bool = false) -> Array:
	var out: Array = []
	if not bool(ctx.get(KEY_10804_DONE, false)) and not _used_剑残影:
		var 目标们: Array = enemy_ids()
		var 可用: bool = player.get_energy() >= 剑残影费用 and not 目标们.is_empty()
		if 显示全部 or 可用:
			out.append({"value": 剑残影, "label": GConst.按钮原文(剑残影, 0), "skill_id": 剑残影,
				"need_target": 1, "targets": 目标们, "enabled": 可用})
	if not bool(ctx.get(KEY_4504_DONE, false)) and not _used_剑影断念:
		var 可用二: bool = _剑之魔女在场() and player.gem > 0 and player.hand_cards.size() >= 2
		if 显示全部 or 可用二:
			out.append({"value": 剑影断念, "label": GConst.按钮原文(剑影断念, 0), "skill_id": 剑影断念,
				"need_card": 2, "enabled": 可用二})
	return out


## 结算二选一里选中的那一项（选择即确认，不再单独问一次「是否发动」）。
## reply 是聚合器分派回来的回复：选定时带目标 / 弃牌，目标弃牌重入时带弃牌。
func _解决攻击结束技能(ctx: Dictionary, 技能号: int, reply: Dictionary = {}) -> int:
	match 技能号:
		剑残影: return _jian_can_ying(ctx, reply)
		剑影断念: return _diao_ying_duan_nian(ctx)
	return SUCCESS


## 提交的目标 / 弃牌不成立：驳回并让聚合器重新问这一项。
## 不能静默作废 —— 那样玩家按了「确定」只会看到选项消失、技能也没发动。
## 引擎收到 SUCCESS 会重新收集选项；这里清掉「本次已用」标记，这一项就会原样摆回来。
func _驳回攻击结束选项(ctx: Dictionary, 完成键: String, 阶段键: String) -> int:
	ctx[阶段键] = 0
	ctx.erase(完成键)
	ctx.erase(KEY_AFTER_CHOSEN)
	ctx.erase(KEY_AFTER_TARGET)
	ctx.erase(KEY_AFTER_CARDS)
	engine.send(player.id, GConst.Msg.ErrorInput,
		{"error_type": GConst.CmdType.Respond, "commands": []})
	return SUCCESS


# ============================================================
# 10804 剑残影
# ============================================================
## 分步：选目标 → 目标弃 1 张 → 额外攻击行动 + 目标限制。
## 选项由聚合器确认后直接从选目标开始；付款放在目标选好之后：目标无效＝整颗不发动，不扣能量。
func _jian_can_ying(ctx: Dictionary, reply: Dictionary = {}) -> int:
	var 阶段: int = int(ctx.get(KEY_10804_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		ctx[KEY_10804_STEP] = 2
		阶段 = 2
	if 阶段 == 2:
		# 条件复核：确认选项之后资源仍可能已经变化
		if _used_剑残影 or player.get_energy() < 剑残影费用 or enemy_ids().is_empty():
			ctx[KEY_10804_STEP] = STEP_DONE
			return SUCCESS
		# 目标和「选哪一项」在同一条回复里；没选目标 / 选的不是对手＝驳回重选，不消耗这一项
		var 目标: int = int(ctx.get(KEY_AFTER_TARGET, -1))
		if not enemy_ids().has(目标):
			return _驳回攻击结束选项(ctx, KEY_10804_DONE, KEY_10804_STEP)
		_used_剑残影 = true
		player.remove_energy(剑残影费用)
		notice_skill(剑残影, [目标])
		engine._broadcast_game()
		ctx[KEY_10804_TARGET] = 目标
		ctx[KEY_10804_STEP] = 3
		var 靶: BattlePlayer = engine.p(目标)
		if 靶 == null or 靶.hand_cards.is_empty():
			_settle_jian_can_ying(ctx, 目标)
			return SUCCESS
		# 目标弃牌是强制的（不能取消）；空回复/非法牌由服务端从手牌补齐
		询问(目标, 剑残影, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false)
		return WAIT
	if 阶段 == 3:
		var 目标2: int = int(ctx.get(KEY_10804_TARGET, -1))
		_目标弃一张(目标2, reply)
		_settle_jian_can_ying(ctx, 目标2)
	return SUCCESS


## 目标弃 1 张手牌：只认回复里真实存在的 1 张；空回复/非法牌按手牌顺序补 1 张。
## 10804 原文没有【展示】，所以不广播 Show（只写弃牌日志）。
func _目标弃一张(目标id: int, r: Dictionary) -> void:
	var 靶: BattlePlayer = engine.p(目标id)
	if 靶 == null or 靶.hand_cards.is_empty():
		return
	var 弃: Array = []
	for v: Variant in r.get("card_ids", []):
		var cid: int = int(v)
		if 靶.has_discard_card(cid) and not 弃.has(cid):
			弃.append(cid)
			break
	if 弃.is_empty():
		for cid: int in 靶.hand_cards:
			弃.append(cid)
			break
	if 弃.is_empty():
		return
	engine.take_from_hand(目标id, 弃)
	engine.to_discard(弃, {"owner": 目标id, "source": "hand", "cause": 剑残影, "face_up": false})
	engine._log_discard(目标id, 弃)
	engine._broadcast_game()


## 10804 收尾：额外 +1【攻击行动】—— 就是一次最普通的攻击行动，不写任何出牌 / 目标白名单。
## 「本回合你的下次主动攻击只能攻击该目标对手」是玩家身上的回合级标记（player.attack_lock）：
## 服务端在 base_v_attack 里校验、下一次主动攻击打出时由引擎消费；客户端按快照把它余下敌方头像置灰。
## 它不是这份行动自带的规格 —— 限制被别的主动攻击消费掉之后，这份行动不该还锁着那个目标。
func _settle_jian_can_ying(ctx: Dictionary, 目标id: int) -> void:
	ctx[KEY_10804_STEP] = STEP_DONE
	player.add_action(GConst.ActionType.Attack, 剑残影, true, true)
	player.set_attack_lock(目标id)
	engine._broadcast_game()


# ============================================================
# 借用 4504 剑影*断念（10801）
# ============================================================
## 选项由聚合器确认后直接进入弃牌步骤；宝石在弃牌选完、确认之后才扣，中途放弃不会先付代价。
func _diao_ying_duan_nian(ctx: Dictionary) -> int:
	if not _剑之魔女在场():
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_4504_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		if _used_剑影断念 or player.gem <= 0 or player.hand_cards.size() < 2:
			ctx[KEY_4504_STEP] = STEP_DONE
			return SUCCESS
		ctx[KEY_4504_STEP] = 1
	# 弃牌和「选哪一项」在同一条回复里；不足 2 张＝放弃 4504，不扣宝石
	var 弃: Array = _选中的手牌(ctx.get(KEY_AFTER_CARDS, []), 2)
	# 选完弃牌按确定才付宝石；凑不齐 2 张＝驳回重选，不扣代价、也不消耗这一项
	if 弃.size() < 2 or player.gem <= 0:
		return _驳回攻击结束选项(ctx, KEY_4504_DONE, KEY_4504_STEP)
	engine.take_from_hand(player.id, 弃)
	_启动剑影断念()
	engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": 剑影断念, "face_up": false})
	engine._log_discard(player.id, 弃)
	engine._broadcast_game()
	ctx[KEY_4504_STEP] = STEP_DONE
	# 先挂额外攻击行动，再摸牌：摸牌可能触发摸牌前响应 / 手牌超限，都排在行动结束之前结算
	player.add_action(GConst.ActionType.Attack, 剑影断念, true, true)
	engine.push_draw(player.id, 1, 剑影断念)
	return URGENT


## 4504 的付款与播报：弃牌确认后走这里，只付一次。
func _启动剑影断念() -> void:
	_used_剑影断念 = true
	notice_skill(剑影断念, [player.id])
	player.set_gem(player.gem - 1)
	engine._broadcast_game()


# ============================================================
# 10803 剑守誓言：回合结束后
# ============================================================
func p_after_turn_end(ctx: Dictionary) -> int:
	if not _可发动剑守誓言():
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_10803_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		# 牌库为空时没有任何牌可弃置 / 加入手牌，也没有法术牌可触发后续；不弹无用询问
		if engine.deck.pile_size() <= 0:
			ctx[KEY_10803_STEP] = STEP_DONE
			return SUCCESS
		if not engine.has_reply():
			# 响应技能先问发动者；取消＝不发动，牌库不动
			询问(player.id, 剑守誓言)
			return WAIT
		if not take_skill_reply():
			ctx[KEY_10803_STEP] = STEP_DONE
			return SUCCESS
		# X＝双方星杯区星杯数之和（A51）；牌库顶 X+1 张，不洗回弃牌堆
		var 取得: Array[int] = engine.移除牌库顶(engine.星杯总数() + 1)
		if 取得.is_empty():
			ctx[KEY_10803_STEP] = STEP_DONE
			return SUCCESS
		ctx[KEY_10803_CARDS] = 取得
		# 持久展示：X+1 张牌一直摊在屏幕中间，直到玩家选完（或超时自动选择），不按 6.4 秒收起
		engine.展示牌库顶(player.id, 取得, true)
		notice_skill(剑守誓言, [player.id])
		ctx[KEY_10803_STEP] = 1
	if int(ctx.get(KEY_10803_STEP, 0)) == 1:
		var 牌表: Array = ctx.get(KEY_10803_CARDS, [])
		if not engine.has_reply():
			# 「可选择其中 1 张加入手牌」：不能取消；展示一直留着，玩家慢慢选，超时由服务端自动选第 1 张。
			# 牌不在手牌里，客户端不能按手牌白名单点选，故用固定选项逐张列出（选项值＝第几张）。
			询问(player.id, 剑守誓言, 0, 0, GConst.CardSource.Hand, _剑守誓言选项(牌表), 0, "", [], false)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		ctx[KEY_10803_STEP] = STEP_DONE
		# 默认第 1 张：超时 / 空回复 / 非法选项都按「自动选择第一张」结算
		var 选中: int = int(牌表[0]) if not 牌表.is_empty() else -1
		var args: Array = r.get("args", [])
		if not args.is_empty():
			var 档: int = int(args[0])
			if 档 >= 1 and 档 <= 牌表.size():
				选中 = int(牌表[档 - 1])
		_settle_jian_shou_shi_yan(牌表, 选中)
	return SUCCESS


## 10803 的触发条件：剑之魔女在场时被 10801 禁止；否则「本回合有主动攻击命中」或
## 「本回合任意一方星杯数增加」（回合开始快照 vs 现在）。
func _可发动剑守誓言() -> bool:
	if _剑之魔女在场():
		return false
	if _本回合有主动攻击命中:
		return true
	return engine.星杯总数() > _回合开始星杯总数


## 10803 的「选择 1 张加入手牌」选项：每张一个按钮，选项值＝1 基下标。
## 牌不在手牌里，走固定选项而不是手牌白名单（客户端现有二级选项即可完成选择）。
func _剑守誓言选项(牌表: Array) -> Array:
	var 选项: Array = []
	for i: int in range(牌表.size()):
		var 牌: GCard = Data.get_card(int(牌表[i]))
		var 标签: String = "未知牌"
		if 牌 != null:
			标签 = "%s %s" % [牌.card_name, _元素字(牌.element_enum())]
		# card_id 只用于客户端悬停选项时摊出牌面；服务端仍按选项值结算。
		选项.append({"value": i + 1, "label": 标签, "card_id": int(牌表[i])})
	return 选项


func _元素字(元素: int) -> String:
	match 元素:
		GConst.CardElement.Earth: return "地"
		GConst.CardElement.Wind: return "风"
		GConst.CardElement.Fire: return "火"
		GConst.CardElement.Water: return "水"
		GConst.CardElement.Thunder: return "雷"
		GConst.CardElement.Light: return "光"
		GConst.CardElement.Darkness: return "暗"
	return ""


## 10803 结算：选中 1 张加入手牌，其余进弃牌堆；这次弃置的整批牌里有法术牌时
## +2 水晶、安排 +1 额外回合并永久替换为风之剑圣。
## 「弃牌中有法术牌」按这次从牌库顶弃置的整批牌判断（含被选入手的 1 张；见文件头口径）。
## 选中的牌不再二次展示：改发 Pick 消息，让客户端把它从展示位直接飞向选牌者头像。
func _settle_jian_shou_shi_yan(牌表: Array, 选中: int) -> void:
	var 弃: Array = []
	for v: Variant in 牌表:
		var cid: int = int(v)
		# 牌表里是从牌库顶弃下来的实例，选中值是玩家点的牌面：按牌面比较（同牌面可能有多份副本）
		if 选中 >= 0 and GConst.牌号(cid) == GConst.牌号(选中):
			player.add_hand_cards([cid])
			# 牌面从展示位飞向角色头像（其他人也看得到）；不再回展示区二次展示
			engine.选走展示牌(player.id, cid)
			# 战斗日志补一条「谁 获得【什么】」；这批牌已经公开，不会泄露暗牌
			engine.播获得牌日志(player.id, [cid])
		else:
			弃.append(cid)
	if not 弃.is_empty():
		engine.to_discard(弃, {"source": "deck", "cause": 剑守誓言, "face_up": true})
	engine._broadcast_game()
	var 有法术: bool = false
	for v: Variant in 牌表:
		var 牌: GCard = Data.get_card(int(v))
		if 牌 != null and 牌.is_magic():
			有法术 = true
			break
	if not 有法术:
		return
	# 「你 +2【水晶】」进玩家自己的能量区（不是战绩区）；set_crystal 会按能量上限截断
	player.set_crystal(player.crystal + 剑守誓言水晶)
	# 先安排额外回合、再替换角色：替换会清旧角色的额外行动，但引擎的额外回合不受影响
	安排额外回合(1, 剑守誓言)
	替换角色(风之剑圣)


# ============================================================
# 10803 的触发条件跟踪
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", GConst.HarmType.None)) != GConst.HarmType.Attack:
		return SUCCESS
	# 10803 要求「主动攻击命中」：应战反击的命中不算
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	_本回合有主动攻击命中 = true
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 剑之魔女是否在场：任意玩家（含对手）的角色卡是 45 即算（A49）。
## 本工程没有角色离场 / 替换 45 的机制，故本局内判定为常驻。
func _剑之魔女在场() -> bool:
	if engine == null:
		return false
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.role_id == 剑之魔女:
			return true
	return false


## 只保留回复里真实存在、不重复的 n 张牌（不补齐）；聚合器选项的同一条回复用。
func _选中的手牌(ids: Array, n: int) -> Array:
	var out: Array = []
	for v: Variant in ids:
		var cid: int = int(v)
		if player.has_discard_card(cid) and not out.has(cid):
			out.append(cid)
		if out.size() >= n:
			break
	return out

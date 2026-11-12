extends BattleRole
## 铸律者（roleID 92）
##
## 技能：
##   神律封锁 9201（被动）：你的【治疗】未满时，所有未拥有【治疗】的角色手牌上限 -1；
##       每次你的【治疗】数增加时，我方士气 -1（至少留 1，强制）。
##   圣血之击 9202（被动）：主动攻击命中时②，本次攻击伤害 +1，你 +1【治疗】。
##   王车易位 9203（法术）：移除场上合计 2【治疗】→ 你 +2【银制子弹】，移除你的所有基础效果与【治疗】，
##       角色卡替换为【红衣主教】，额外 +1【攻击行动】。
##   罪断豁免 9204（响应）：我方非因承受伤害掉士气时，移除 X 点【圣遗物】抵御 X 点，你 +X【银制子弹】。
##   圣银颂恩 9205（响应【回合限定】）：【攻击行动】结束时，移除 2 点【银制子弹】→
##       额外 +1【攻击行动】，目标角色 +1【治疗】。
##   圣律威压 9206（专属技·被动）：【王权宝珠】转移 / 放置到某人面前时，他二选一：
##       弃 1 张与该卡上牌同种类的牌【展示】；或摸 2 张牌【强制】、铸律者阵营士气 -1。
##       结算完若【圣遗物】<1，移除此卡。
##   信仰重铸 9207（响应·必杀技【回合限定】）：【水晶】，你的回合结束时若本回合未执行【特殊行动】，
##       将 1 张手牌面朝上放在【王权宝珠】上【展示】，你摸 1 张牌【强制】、+2【圣遗物】，
##       然后把【王权宝珠】放到你面前。
##   神言咏赞 9208（专属技·被动）：【圣律威压】结算完后，把【王权宝珠】传给右手边最近的玩家；
##       若因此传回铸律者面前，他二选一：角色卡替换为【红衣主教】并移除此卡；
##       或移除 X 点【银制子弹】（X<3），目标角色摸 X 张牌【强制】，然后移除此卡。

const SHEN_LV_FENG_SUO: int = 9201
const SHENG_XUE_ZHI_JI: int = 9202
const WANG_CHE_YI_WEI: int = 9203
const ZUI_DUAN_HUO_MIAN: int = 9204
const SHENG_YIN_SONG_EN: int = 9205
const SHENG_LV_WEI_YA: int = 9206
const XIN_YANG_CHONG_ZHU: int = 9207
const SHEN_YAN_YONG_ZAN: int = 9208

## 指示物槽位（角色表 0:银制子弹:3;1:圣遗物:3）
const 银弹槽: int = 0
const 圣遗物槽: int = 1

const 宝珠名: String = "王权宝珠"
const 红衣主教: int = 111
## 神律封锁写进「手牌上限修正」的来源键（换角色卡时要清掉）
const 神律来源: String = "神律封锁"

var _圣银颂恩已用: bool = false
## 王车易位：0＝未问 / 1＝等选从谁身上扣治疗
var _王车阶段: int = 0
## 信仰重铸：0＝未开始 / 1＝已问、等回复 / 2＝已放牌在宝珠上，等摸牌 / 3＝王权宝珠链进行中
var _信仰阶段: int = 0
## 王权宝珠的传递链：1＝问当前持有者【圣律威压】/ 3＝传给下家（并检查圣遗物）/ 4＝问铸律者收尾
## 宝珠传递链：还要不要继续循环 / 宝珠是不是传回了铸律者
var _宝珠继续: bool = false
var _宝珠到铸律者: bool = false
var _宝珠持有者: int = -1
var _宝珠选摸牌: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【王权宝珠】是铸律者的专属卡：开局摆在他面前。
	# 初始摆放不算「转移 / 放置」，不触发【圣律威压】（否则开局就要全场选一遍）
	engine.加场卡({"id": 宝珠名, "owner": player.id, "attached": player.id, "card": -1})
	_同步神律封锁()


# ============================================================
# 技能栏：王车易位（法术）
# ============================================================
func available_skills() -> Array:
	return [{
		"type": GConst.ActionType.MagicSkill,
		"id": WANG_CHE_YI_WEI,
		"need_card": 0,
		"need_target": 0,
		"enabled": _场上治疗合计() >= 2,
	}]


# ============================================================
# 神律封锁：治疗未满时，所有没有治疗的角色手牌上限 -1
# ============================================================
func _同步神律封锁() -> void:
	var 生效: bool = player.cross_num < player.cross_max
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null:
			continue
		if 生效 and p0.cross_num == 0:
			p0.设手牌上限修正(神律来源, -1)
		else:
			p0.清手牌上限修正(神律来源)


## 你的治疗数增加时：我方士气 -1，但至少留 1（强制）。
## 走引擎的 p_heal_gained：只有当治疗真的加上去时才触发（加满再加 / 被禁疗作废都不算），
## 别的角色给你加治疗（如【圣银颂恩】选自己）也会触发。
func p_heal_gained(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if engine.team_morale[player.color] > 1:
		engine.lose_morale(player, 1, SHEN_LV_FENG_SUO)
	_同步神律封锁()
	return SUCCESS


## 换角色卡时把神律封锁加的修正清干净（新角色会重新算）
func p_before_role_replace(_ctx: Dictionary) -> int:
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null:
			p0.清手牌上限修正(神律来源)
	# 宝珠链的分步状态跟着旧角色走不了，直接收链（场卡本身留在场上，由新角色重新开始）
	_宝珠持有者 = -1
	_宝珠继续 = false
	_宝珠到铸律者 = false
	_王车阶段 = 0
	return SUCCESS


func p_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_圣银颂恩已用 = false
	_同步神律封锁()
	return SUCCESS


func p_harm_end(_ctx: Dictionary) -> int:
	# 治疗在伤害流水线里被花掉 / 补回后，神律封锁的判定跟着变
	_同步神律封锁()
	return SUCCESS


# ============================================================
# 圣血之击：主动攻击命中②，伤害 +1、+1 治疗（再触发神律封锁的士气 -1）
# ============================================================
## 攻击「预告加伤」：圣血之击在命中②才 +1，应战提示要把它算进去（被打的人看到的是实际伤害）
func p_attack_preview(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return 0
	return 1


func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	notice_skill(SHENG_XUE_ZHI_JI, [int(harm.get("dst", -1))])
	# 伤害由引擎在命中时按 p_attack_preview 统一加（这里只播报 + 给自己上治疗）
	施加治疗(player.id, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 罪断豁免：我方非因承受伤害掉士气 → 移 X 圣遗物抵 X 点，回 X 银弹
# 掉士气链是同步调用（ctx.sync），这里只改 ctx、不开询问。
# ============================================================
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("type", GConst.HarmType.None)) != GConst.HarmType.None:
		return SUCCESS
	var amount: int = int(ctx.get("amount", 0))
	if amount <= 0:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	var X: int = mini(amount, player.token_num(圣遗物槽))
	if X <= 0:
		return SUCCESS
	ctx["amount"] = amount - X
	player.remove_token(圣遗物槽, X)
	player.add_token(银弹槽, X)
	return SUCCESS


# ============================================================
# 圣银颂恩：攻击行动结束时的可选响应（行动聚合器）
# ============================================================
func action_end_options(ctx: Dictionary) -> Array:
	if not 是攻击行动结束(ctx) or _圣银颂恩已用:
		return []
	return [{
		"value": SHENG_YIN_SONG_EN,
		"label": GConst.按钮原文(SHENG_YIN_SONG_EN, 0),
		"skill_id": SHENG_YIN_SONG_EN,
		"need_target": 1,
		"targets": 全部角色(),
		"enabled": player.token_num(银弹槽) >= 2,
	}]


func resolve_action_end_option(cause: int, reply: Dictionary, _ctx: Dictionary) -> int:
	if cause != SHENG_YIN_SONG_EN:
		return resolve_queued_extra_action(cause)
	var dsts: Array = reply.get("dst_ids", [])
	if dsts.is_empty() or player.token_num(银弹槽) < 2:
		return GConst.GE_INVALID_ARGUMENT
	var dst: int = int(dsts[0])
	if engine.p(dst) == null:
		return GConst.GE_INVALID_PLAYERID
	_圣银颂恩已用 = true
	player.remove_token(银弹槽, 2)
	notice_skill(SHENG_YIN_SONG_EN, [dst])
	施加治疗(dst, 1)
	player.add_action(GConst.ActionType.Attack, SHENG_YIN_SONG_EN, true)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 王车易位：移除场上合计 2 治疗 → +2 银弹、清基础效果与治疗、换红衣主教、+1 攻击行动
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != WANG_CHE_YI_WEI:
		return GConst.GE_INVALID_ACTION
	if _场上治疗合计() < 2:
		return GConst.GE_INVALID_ACTION
	_王车阶段 = 0
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != WANG_CHE_YI_WEI:
		return GConst.GE_INVALID_ACTION
	if _王车阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		_王车阶段 = 0
		_王车移除治疗(r.get("dst_ids", []))
		return _王车收尾()
	# 先让施法者挑从谁身上扣治疗（说明里是代价，但玩家应该有选择权）；挑完再结算
	var 有治疗: Array = player_ids_where(func(p: BattlePlayer) -> bool: return p.cross_num > 0, true)
	if 有治疗.is_empty():
		return SUCCESS
	_王车阶段 = 1
	询问(player.id, WANG_CHE_YI_WEI, 0, mini(2, 有治疗.size()), GConst.CardSource.Hand, [], 0, "", [], false,
		0, -1, 有治疗, -1, {})
	return WAIT


## 从玩家选中的角色身上各扣 1 点；不够 2 点的部分从已选的人身上继续扣，最后按座位顺序补齐
func _王车移除治疗(dsts: Array) -> void:
	var 还需: int = 2
	var 已选: Array = []
	for d: Variant in dsts:
		if 还需 <= 0:
			break
		var p0: BattlePlayer = engine.p(int(d))
		if p0 == null or p0.cross_num <= 0 or 已选.has(p0.id):
			continue
		p0.sub_cross_num(1)
		还需 -= 1
		已选.append(p0.id)
	while 还需 > 0:
		var 扣到: bool = false
		for pid: int in (已选 if not 已选.is_empty() else engine.order):
			var p1: BattlePlayer = engine.p(pid)
			if p1 == null or p1.cross_num <= 0:
				continue
			p1.sub_cross_num(1)
			还需 -= 1
			扣到 = true
			break
		if not 扣到:
			break
	if 还需 > 0:
		engine.报错("【王车易位】场上治疗不足 2 点", player.id)


func _王车收尾() -> int:
	notice_skill(WANG_CHE_YI_WEI, [player.id])
	player.add_token(银弹槽, 2)
	_移除全部基础效果与治疗()
	# 替换角色会清掉额外行动，所以「+1 攻击行动」放在换卡之后再给
	替换角色(红衣主教)
	player.add_action(GConst.ActionType.Attack, WANG_CHE_YI_WEI, true)
	engine._broadcast_game()
	return SUCCESS


func _场上治疗合计() -> int:
	var 总: int = 0
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null:
			总 += p0.cross_num
	return 总


func _移除全部基础效果与治疗() -> void:
	for be: Dictionary in player.basic_effects.duplicate():
		engine.remove_basic_effect(player.id, int(be["card"]), WANG_CHE_YI_WEI, player.id)
	player.sub_cross_num(player.cross_num)
	_同步神律封锁()


# ============================================================
# 信仰重铸：回合结束时把 1 张手牌放到【王权宝珠】上，摸 1、+2 圣遗物、把宝珠放到自己面前
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _信仰阶段 == 0:
		if not _信仰重铸可用():
			return SUCCESS
		_信仰阶段 = 1
		询问(player.id, XIN_YANG_CHONG_ZHU, 1, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	if _信仰阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var cards: Array = r.get("card_ids", [])
		if args.is_empty() or int(args[0]) != 1 or cards.is_empty() \
				or not player.has_discard_card(int(cards[0])):
			_信仰阶段 = 0
			return SUCCESS
		_信仰阶段 = 2
		_发动信仰重铸(int(cards[0]))
		return URGENT
	if _信仰阶段 == 2:
		# 摸牌结算完：把宝珠放到自己面前，开始传递链
		_信仰阶段 = 3
		_宝珠放下(player.id)
		_宝珠持有者 = player.id
		_宝珠继续 = false
		_宝珠到铸律者 = false
	if _信仰阶段 == 3:
		var rc: int = _宝珠推进()
		if rc != SUCCESS:
			return rc
		_信仰阶段 = 0
	return SUCCESS


func _信仰重铸可用() -> bool:
	if player.get_energy() < 1 or player.hand_cards.is_empty():
		return false
	if player.action_count_of("special") > 0:
		return false
	return engine.有场卡(宝珠名)


## 付 1 能量、把手牌面朝上放到宝珠上、+2 圣遗物、摸 1 张（摸牌走状态，调用方返回 URGENT）
func _发动信仰重铸(card: int) -> void:
	notice_skill(XIN_YANG_CHONG_ZHU, [player.id])
	player.remove_energy(1)
	# 手牌面朝上放到【王权宝珠】上【展示】：统一入口（亮牌 + 触发封印）
	engine.展示手牌(player.id, [card])
	engine.take_from_hand(player.id, [card])
	var 表: Dictionary = engine.取场卡(宝珠名)
	表["card"] = GConst.牌号(card)
	player.add_token(圣遗物槽, 2)
	engine._broadcast_game()
	engine.push_强制摸牌(player.id, 1, XIN_YANG_CHONG_ZHU)


## 把【王权宝珠】摆到某人面前（保留 owner 与上面叠着的牌）
func _宝珠放下(holder: int) -> void:
	var 表: Dictionary = engine.取场卡(宝珠名)
	engine.加场卡({
		"id": 宝珠名,
		"owner": int(表.get("owner", player.id)),
		"attached": holder,
		"card": int(表.get("card", -1)),
	})
	engine._broadcast_game()


# ============================================================
# 王权宝珠的传递链：圣律威压 → 神言咏赞 → 下家圣律威压 → … → 回到铸律者收尾
# ============================================================
func _宝珠推进() -> int:
	# 王权宝珠的传递链：圣律威压（对持有者，循环）→ 神言咏赞（传回铸律者时）
	# 第 1 段用「重复」段：每到一个人就问一次圣律威压，问完把宝珠传给下家；
	# 摸牌那一支要等摸牌结算完才掉士气 / 传宝珠，所以重复判定会延后到重入时再做。
	return 多步询问(SHENG_LV_WEI_YA, [
		{"问谁": func(_答案: Array) -> int: return _宝珠持有者,
		 "选项": func(_答案: Array) -> Array: return _圣律威压选项(_宝珠持有者),
		 "问前": func(_答案: Array) -> void: notice_skill(SHENG_LV_WEI_YA, [_宝珠持有者]),
		 "可取消": false, "超时默认": [],
		 "答完": _圣律威压答完,
		 "重复": func(_回: Dictionary, _答案: Array) -> bool: return _宝珠循环一步()},
		{"技能号": SHEN_YAN_YONG_ZAN,
		 "选项": func(_答案: Array) -> Array: return _神言咏赞选项(),
		 "问前": func(_答案: Array) -> void: notice_skill(SHEN_YAN_YONG_ZAN, [player.id]),
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool: return not _宝珠到铸律者,
		 "取消": func() -> int: return _神言咏赞收尾({})},
	], _神言咏赞结算, func() -> int: return SUCCESS)


## 圣律威压答完：选摸牌就压摸牌状态（掉士气 / 传宝珠留到重入时判重复里做），否则弃牌
func _圣律威压答完(回: Dictionary, _答案: Array) -> int:
	var args: Array = 回.get("args", [])
	_宝珠选摸牌 = args.is_empty() or int(args[0]) != 1
	if _宝珠选摸牌:
		engine.push_强制摸牌(_宝珠持有者, 2, SHENG_LV_WEI_YA)
		return URGENT
	_圣律威压弃牌(_宝珠持有者, 回.get("cards", []))
	return SUCCESS


## 一个人问完后的「阶段 3」：摸牌的掉士气 → 圣遗物不够就移除宝珠收尾 → 否则传给下家
## 返回「还要不要继续循环」（宝珠传到铸律者时停，改问神言咏赞）
func _宝珠循环一步() -> bool:
	if _宝珠选摸牌:
		# 「摸 2 张牌【强制】，铸律者阵营士气-1」：摸牌结算完再掉士气
		_宝珠选摸牌 = false
		engine.lose_morale(player, 1, SHENG_LV_WEI_YA)
	if player.token_num(圣遗物槽) < 1:
		engine.移除场卡(宝珠名)
		_宝珠到铸律者 = false
		_宝珠继续 = false
		return false
	# 神言咏赞：传给右手边最近的玩家
	var 下家: int = engine.next_id(_宝珠持有者)
	_宝珠放下(下家)
	notice_skill(SHEN_YAN_YONG_ZAN, [下家])
	_宝珠持有者 = 下家
	_宝珠到铸律者 = 下家 == player.id
	_宝珠继续 = not _宝珠到铸律者
	return _宝珠继续


## 神言咏赞答完：把选项回复转成原收尾函数要的形状
func _神言咏赞结算(答案: Array) -> int:
	# 宝珠没传回铸律者（半路因圣遗物不足被移除 / 段被跳过）：不问神言，直接结束
	if not _宝珠到铸律者:
		return SUCCESS
	var 回: Dictionary = 答案[1] if 答案.size() > 1 else {}
	return _神言咏赞收尾({
		"args": 回.get("args", []), "card_ids": 回.get("cards", []), "dst_ids": 回.get("dsts", []),
	})


func _圣律威压选项(holder: int) -> Array:
	var 同种类: Array = []
	var 叠牌号: int = int(engine.取场卡(宝珠名).get("card", -1))
	var hp: BattlePlayer = engine.p(holder)
	if 叠牌号 >= 0 and hp != null:
		var 叠牌: GCard = Data.get_card(叠牌号)
		if 叠牌 != null:
			for cid: int in hp.hand_cards:
				var c: GCard = Data.get_card(cid)
				if c != null and c.type == 叠牌.type:
					同种类.append(cid)
	return [
		{
			"value": 1,
			"label": GConst.按钮原文(SHENG_LV_WEI_YA, 0),
			"text": GConst.按钮原文(SHENG_LV_WEI_YA, 0),
			"need_card": 1,
			"cards": 同种类,
			"enabled": not 同种类.is_empty(),
		},
		{
			"value": 2,
			"label": GConst.按钮原文(SHENG_LV_WEI_YA, 1),
			"text": GConst.按钮原文(SHENG_LV_WEI_YA, 1),
			"enabled": true,
		},
	]


## 圣律威压·选项 1：持有者弃 1 张与卡上牌同种类的牌【展示】
func _圣律威压弃牌(holder: int, ids: Array) -> void:
	var hp: BattlePlayer = engine.p(holder)
	if hp == null or ids.is_empty():
		return
	var cid: int = int(ids[0])
	if not hp.has_discard_card(cid):
		engine.报错("【圣律威压】提交的牌不在手牌里", holder)
		return
	# 「弃 1 张同种类的牌【展示】」：统一入口（亮牌 + 触发封印 + 离手 + 进弃牌堆 + 日志）
	engine.展示手牌并弃(holder, [cid], {"cause": SHENG_LV_WEI_YA})


## 神言咏赞传回铸律者时的三个选项：换红衣主教 / 移 1 银弹让目标摸 1 / 移 2 银弹让目标摸 2
func _神言咏赞选项() -> Array:
	var 弹: int = player.token_num(银弹槽)
	return [
		{
			"value": 1,
			"label": GConst.按钮原文(SHEN_YAN_YONG_ZAN, 0),
			"text": GConst.按钮原文(SHEN_YAN_YONG_ZAN, 0),
			"enabled": true,
		},
		{
			"value": 2,
			"label": GConst.按钮原文(SHEN_YAN_YONG_ZAN, 1),
			"text": GConst.按钮原文(SHEN_YAN_YONG_ZAN, 1),
			"need_target": 1,
			"targets": 全部角色(),
			"enabled": 弹 >= 1,
		},
		{
			"value": 3,
			"label": GConst.按钮原文(SHEN_YAN_YONG_ZAN, 2),
			"text": GConst.按钮原文(SHEN_YAN_YONG_ZAN, 2),
			"need_target": 1,
			"targets": 全部角色(),
			"enabled": 弹 >= 2,
		},
	]


## 神言咏赞·收尾：换红衣主教 / 移除 X 银弹让目标摸 X 张；两种都以移除此卡结束
func _神言咏赞收尾(r: Dictionary) -> int:
	var args: Array = r.get("args", [])
	var 选择: int = int(args[0]) if not args.is_empty() else 1
	_宝珠继续 = false
	_宝珠到铸律者 = false
	if 选择 == 1:
		notice_skill(SHEN_YAN_YONG_ZAN, [player.id])
		替换角色(红衣主教)
		engine.移除场卡(宝珠名)
		return SUCCESS
	var X: int = 选择 - 1
	var dsts: Array = r.get("dst_ids", [])
	if dsts.is_empty() or player.token_num(银弹槽) < X:
		engine.报错("【神言咏赞】提交的目标或银制子弹不成立", player.id)
		engine.移除场卡(宝珠名)
		return SUCCESS
	var dst: int = int(dsts[0])
	if engine.p(dst) == null:
		engine.报错("【神言咏赞】提交的目标不存在", player.id)
		engine.移除场卡(宝珠名)
		return SUCCESS
	notice_skill(SHEN_YAN_YONG_ZAN, [dst])
	player.remove_token(银弹槽, X)
	engine.移除场卡(宝珠名)
	engine.push_强制摸牌(dst, X, SHEN_YAN_YONG_ZAN)
	return URGENT


## 全部在场角色（含自己）：「目标角色」按术语表是可选场上任意角色
func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

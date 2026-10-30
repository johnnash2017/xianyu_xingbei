extends BattleRole
## 灵熙之潮（roleID 46）—— 特典版本
## 技能：
##   灵枝旨意（4601，被动）：你无法成为基础效果的目标。
##   邪灵退散（4602，响应）：你放置基础效果后，对 1 名目标对手造成 1 点法术伤害③。
##   伴响魂灵（4603，响应 / 回合限定）：你回合内目标对手因你造成的伤害掉士气时，
##     对除他外所有目标对手各造成 1 点法术伤害③（每回合最多一次）。
##   波涌之力（4604，被动）：目标角色触发基础效果并结算完成后，你 +1【灵涌】（上限 4）。
##   怒潮荒涛（4605，被动）：你的回合结束时若【灵涌】已满，移除所有【灵涌】，
##     对场上每名角色各造成 1 点法术伤害③；目标每有 1 个基础效果，本次对他额外 +1。
##   海神御巫（4606，法术 / 必杀技 / 水晶）：支付 1【水晶】，使用 1 张封印师 / 祈祷师独有技；你弃 1 张牌。
##
## 借用关系（见《禁用3星与3.5星角色开发计划》F5 / data-audit A18、A16、A17）：
##   4606 按「牌载技能」实现：手里必须有带 401~405 / 1601 / 1602 的牌；
##   选牌 → 源技能目标 → 结算 → 弃 1 张。校验 / 放置全部转给 F5 的
##   scripts/battle/skills/skill_seal.gd 与 skill_bless.gd，不改 role_fengyin / role_qidao。
##   放置只是第一步：helper 头注释（借用角色接法）要求借用角色继续转发触发钩子，
##   所以本角色还有 p_show_hand（封印展示触发）与 p_timeline_2_hit / p_after_attack /
##   p_after_magic / p_additional_action（赐福的命中 +2、行动结束
##   授予额外攻击、选中后移除）—— 缺了这些，4606 放出去的封印 / 赐福在本尊不在场时不会生效。
##   【灵涌】是角色表「指示物」槽 0 的计数指示物（名称 / 上限从表里读，上限 4），
##   计数一律走 player.add_token / clear_token，不在这里写死上限。
##   4601 走 F4 的 v_basic_effect_target；4602 / 4604 走 F4 的 p_basic_effect_change /
##   p_basic_effect_triggered；4603 用「本回合自己造成的伤害」与掉士气链的 harm_cause 比对。
##
## 跨范围说明：F5 的封印 / 赐福 helper（以及 role_fengyin / role_qidao 的原路径）在放置前
## 没有先问目标角色的 v_basic_effect_target；敌方封印 / 队友赐福若直接指向 46，
## add_basic_effect 会兜底拒绝、效果不会挂上（4601 生效），但源技能仍会按原逻辑把发动牌离手。
## 这是 helper / 源角色的范围（F5），本角色只保证「不能成为基础效果的目标」，不改范围外文件。

const 封印技能脚本: GDScript = preload("res://scripts/battle/skills/skill_seal.gd")
const 赐福技能脚本: GDScript = preload("res://scripts/battle/skills/skill_bless.gd")

const 灵枝旨意: int = 4601
const 邪灵退散: int = 4602
const 伴响魂灵: int = 4603
const 波涌之力: int = 4604
const 怒潮荒涛: int = 4605
const 海神御巫: int = 4606

## 【灵涌】的指示物槽位（角色表：0:灵涌:4）
const 灵涌槽: int = 0
## 4602 / 4603 / 4605 造成的法术伤害点数
const 邪灵伤害: int = 1
const 伴响伤害: int = 1
const 怒潮基础伤害: int = 1

## 4602 的进度：等自己选 1 名目标对手；4606 的进度见下方 _4606阶段
const 变动阶段_空闲: int = 0
const 变动阶段_待4602: int = 1
const 变动阶段_等4602回复: int = 2
const 变动阶段_待4606弃牌: int = 3
const 变动阶段_等4606弃牌回复: int = 4

const 阶段4606_空闲: int = 0
## 已经问过「使用哪一张独有技」，等玩家选牌 / 选目标并回复
const 阶段4606_待选技回复: int = 1

## 借用的封印 / 赐福 helper（构造传自己；本角色只做路由）
var _封印: Variant = null
var _赐福: Variant = null

## 4602 当前处理的这次「基础效果放置」上下文；同一次钩子重入要认同一份字典（is_same）
var _变动ctx: Dictionary = {}
var _变动阶段: int = 变动阶段_空闲
## 4606 放置完源技能后，还要等基础效果变更钩子跑完 4602 再弃自己 1 张牌
var _4606待弃牌: bool = false
var _4606阶段: int = 阶段4606_空闲

## 4603 的「本回合最多一次」；每次自己的回合开始清零
var _本回合已触发4603: bool = false
## 本回合自己造成的伤害记录（掉士气时用它确认「因你造成的伤害」）：
## [{dst, cause, type}]
var _本回合自己伤害: Array[Dictionary] = []


func _init() -> void:
	_封印 = 封印技能脚本.new(self)
	_赐福 = 赐福技能脚本.new(self)


# ============================================================
# 回合开始：清 4603 的回合限定与伤害记录
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	if engine == null or player == null or engine.current_id != player.id:
		return SUCCESS
	_本回合已触发4603 = false
	_本回合自己伤害.clear()
	return SUCCESS


# ============================================================
# 4601 灵枝旨意：无法成为基础效果的目标（含自己指定自己，A14）
# ============================================================
func v_basic_effect_target(_dst: BattlePlayer, _card_id: int) -> int:
	return GConst.GE_INVALID_PLAYERID


# ============================================================
# 技能栏：海神御巫（4606）
# ============================================================
func available_skills() -> Array:
	var 有可用: bool = false
	for 项: Dictionary in _4606选项():
		if bool(项.get("enabled", false)):
			有可用 = true
			break
	return [{
		"type": GConst.ActionType.MagicSkill,
		"id": 海神御巫,
		"need_card": 0,
		"need_target": 0,
		# 能量 / 可用的独有技牌都没有时照常下发、只置灰（界面看得见技能存在）
		"enabled": 可用() and player.get_energy() > 0 and 有可用,
	}]


## helper 是否已绑好（构造后 player / engine 由 setup 填上）
func 可用() -> bool:
	return player != null and engine != null and _封印 != null and _赐福 != null


# ============================================================
# 4606 海神御巫：主动法术技能（客户端提交牌 + 目标）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if not 可用():
		return GConst.GE_INVALID_ACTION
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != 海神御巫:
		return GConst.GE_INVALID_ACTION
	# 【水晶】费用：宝石可以顶水晶，统一用 get_energy() 判断（《技能维护约定》猎巫人复盘第 2 条）
	if player.get_energy() <= 0:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() and dsts.is_empty():
		# 客户端没带牌与目标：技能本体校验放到服务端询问里（见 p_magic_skill），
		# 这里只要求当前手里确实有一张能借用的独有技牌。
		if not _有可用借用():
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if cards.size() != 1 or dsts.size() != 1:
		return GConst.GE_INVALID_ACTION
	return _校验借用(int(cards[0]), int(dsts[0]))


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != 海神御巫:
		return EMPTY_HANDLE
	if _4606阶段 == 阶段4606_空闲:
		var cards: Array = action.get("card_ids", [])
		var dsts: Array = action.get("dst_ids", [])
		if cards.size() == 1 and dsts.size() == 1:
			# 客户端一次带齐牌 + 目标：直接结算
			return _结算4606(int(cards[0]), int(dsts[0]))
		# 只点了技能按钮：服务端下发「选哪一张独有技 + 选牌 + 选目标」的询问
		_4606阶段 = 阶段4606_待选技回复
		_询问4606()
		return WAIT
	# 已问过：读取「选技能 + 牌 + 目标」的回复
	var r: Dictionary = take_skill_reply_full()
	_4606阶段 = 阶段4606_空闲
	var args: Array = r.get("args", [])
	var cards2: Array = r.get("card_ids", [])
	var dsts2: Array = r.get("dst_ids", [])
	if args.is_empty() or cards2.is_empty() or dsts2.is_empty():
		# 取消 / 超时 / 没选全：这次技能行动没发生，退回行动阶段
		engine.取消技能行动()
		return SUCCESS
	var 选技能: int = int(args[0])
	var cid: int = int(cards2[0])
	var dst_id: int = int(dsts2[0])
	var card: GCard = Data.get_card(cid)
	if card == null or _来源技能号(card) != 选技能 or _校验借用(cid, dst_id) != GConst.GE_SUCCESS:
		engine.取消技能行动()
		return SUCCESS
	return _结算4606(cid, dst_id)


## 4606 的询问：固定把 401~405 / 1601 / 1602 全部列出，不能用的只置灰；
## 每项带自己的目标白名单，客户端选中该项后据此收紧可点头像（未选＝按并集）。
func _询问4606() -> void:
	var 选项: Array = _4606选项()
	var 牌表: Array[int] = _4606牌表()
	var 目标并集: Array[int] = []
	for 项: Dictionary in 选项:
		# 只把「手里有对应发动牌」的选项目标并进来：没有牌的来源技能点不动，
		# 它的目标也不该在未选选项时就亮（选中某项后客户端再按该项 targets 收紧）
		if not bool(项.get("enabled", false)):
			continue
		for pid: Variant in 项.get("targets", []):
			if not 目标并集.has(int(pid)):
				目标并集.append(int(pid))
	询问(player.id, 海神御巫, 1, 1, GConst.CardSource.Hand, 选项, 0, "", 牌表, true, 0, -1, 目标并集)


## 4606 的固定选项：封印师 401~405 + 祈祷师 1601 / 1602。
## label 只写技能名（按源技能号取，避免同名技能号写死），skill_id 供客户端悬停显示说明。
func _4606选项() -> Array:
	var out: Array = []
	if not 可用():
		return out
	var 牌表: Array[int] = _4606牌表()
	for 技能号: int in _源技能列表():
		var 本技能牌: Array[int] = []
		for cid: int in 牌表:
			var card: GCard = Data.get_card(cid)
			if card != null and card.has_skill_id(技能号):
				本技能牌.append(cid)
		var 目标: Array[int] = _技能合法目标(技能号, int(本技能牌[0]) if not 本技能牌.is_empty() else -1)
		out.append({
			"value": 技能号,
			"label": GConst.skill_name(技能号),
			"skill_id": 技能号,
			"enabled": not 本技能牌.is_empty() and not 目标.is_empty(),
			"targets": 目标,
		})
	return out


## 手里所有能当「封印师 / 祈祷师独有技」用的牌（不区分系别 / 技能号）
func _4606牌表() -> Array[int]:
	var out: Array[int] = []
	if not 可用():
		return out
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card != null and _来源技能号(card) > 0 and not out.has(cid):
			out.append(cid)
	return out


## 当前手里至少有一张带来源技能的牌，且它对应的源技能有合法目标
func _有可用借用() -> bool:
	for 项: Dictionary in _4606选项():
		if bool(项.get("enabled", false)):
			return true
	return false


## 校验「这张牌 + 这个目标」能不能作为 4606 的借用技能使用；成功返回 GE_SUCCESS。
func _校验借用(cid: int, dst_id: int) -> int:
	var card: GCard = Data.get_card(cid)
	if card == null or not player.has_hand_card(cid):
		return GConst.GE_INVALID_CARDID
	var 技能号: int = _来源技能号(card)
	if 技能号 <= 0:
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if not _技能合法目标(技能号, cid).has(dst_id):
		return GConst.GE_INVALID_PLAYERID
	# 4601 等目标资格兜底（add_basic_effect 里还会再问一次）
	if engine.v_basic_effect_target(dst_id, cid) != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	# 交给源技能 helper 再验一次牌 / 目标（与直接使用源技能同一口径）
	var 动作: Dictionary = {
		"src_id": player.id, "action_id": 技能号,
		"card_ids": [cid], "dst_ids": [dst_id], "args": [],
	}
	if _是封印技能(技能号):
		return int(_封印.v_place(动作, 技能号))
	if _是赐福技能(技能号):
		return int(_赐福.v_magic_skill(动作))
	return GConst.GE_INVALID_ACTION


## 4606 结算：播报 4606 → 转给源技能 helper 放置 → 支付 1 点能量（宝石可顶）→ 等钩子跑完再弃牌。
## 返回 URGENT：基础效果变更 / 展示钩子已压栈，本次技能行动要等它们（含 4602）结算完。
func _结算4606(cid: int, dst_id: int) -> int:
	var 结果: int = _校验借用(cid, dst_id)
	if 结果 != GConst.GE_SUCCESS:
		return 结果
	var card: GCard = Data.get_card(cid)
	var 技能号: int = _来源技能号(card)
	notice_skill(海神御巫, [dst_id])
	var 动作: Dictionary = {
		"src_id": player.id, "action_id": 海神御巫,
		"card_ids": [cid], "dst_ids": [dst_id], "args": [],
	}
	if _是封印技能(技能号):
		if int(_封印.p_place(动作, 技能号)) != URGENT:
			return EMPTY_HANDLE
	else:
		if int(_赐福.放置赐福(cid, dst_id, 技能号)) != GConst.GE_SUCCESS:
			return EMPTY_HANDLE
	player.remove_energy(1)
	_4606待弃牌 = true
	engine._broadcast_game()
	return URGENT


# ============================================================
# 源技能（封印 / 赐福）的查询
# ============================================================
func _源技能列表() -> Array[int]:
	var out: Array[int] = []
	for 号: int in 封印技能脚本.封印技能号列表:
		out.append(int(号))
	out.append(int(赐福技能脚本.XUN_JIE_CI_FU))
	out.append(int(赐福技能脚本.WEI_LI_CI_FU))
	return out


## 这张牌带的是哪一颗来源技能；不是 401~405 / 1601 / 1602 返回 0
func _来源技能号(card: GCard) -> int:
	if card == null:
		return 0
	for 技能号: int in _源技能列表():
		if card.has_skill_id(技能号):
			return 技能号
	return 0


func _是封印技能(技能号: int) -> bool:
	return 封印技能脚本.封印技能号列表.has(技能号)


func _是赐福技能(技能号: int) -> bool:
	return 技能号 == 赐福技能脚本.XUN_JIE_CI_FU or 技能号 == 赐福技能脚本.WEI_LI_CI_FU


## 源技能的合法目标（借用方视角）：
##   封印 401~405：异色、且身上没有同种封印（与 role_fengyin 一致）；
##   赐福 1601~1602：同色队友、不含自己、面前没有同类赐福（与 role_qidao 一致）。
## 再按目标角色的 v_basic_effect_target 过滤（4601 这类「不能成为基础效果目标」）。
func _技能合法目标(技能号: int, 代表牌: int) -> Array[int]:
	var out: Array[int] = []
	if not 可用():
		return out
	var 基础: Array[int] = []
	if _是封印技能(技能号):
		基础 = _封印.合法目标(技能号)
	elif _是赐福技能(技能号):
		基础 = _赐福.可选目标(技能号)
	for 值: Variant in 基础:
		var pid: int = int(值)
		if pid < 0 or out.has(pid):
			continue
		if 代表牌 >= 0 and engine.v_basic_effect_target(pid, 代表牌) != GConst.GE_SUCCESS:
			continue
		out.append(pid)
	return out


# ============================================================
# 技能行动的「基础效果放置声明」（F4）：客户端一次带齐牌 + 目标时，
## 引擎先按它做目标资格校验（4601 等），不合法时整个技能行动被驳回、不扣牌。
# ============================================================
func basic_effect_placements(action: Dictionary) -> Array:
	if int(action.get("action_id", 0)) != 海神御巫:
		return []
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.size() != 1 or dsts.size() != 1:
		return []
	var card: GCard = Data.get_card(int(cards[0]))
	if card == null or _来源技能号(card) <= 0:
		return []
	return [{"card": int(cards[0]), "dst": int(dsts[0])}]


# ============================================================
# 4606 借用的封印 / 赐福：把 helper 的触发钩子转发进来
# （skill_seal.gd / skill_bless.gd 头注释的「借用角色接法」）
#
# 引擎对每个 p_* 钩子都按座位逐角色调用，所以借用角色必须自己转发；只做「放置」
# 而不转发时，4606 放出去的封印要等目标展示同系牌、赐福要等持有者命中 / 行动结束，
# 本尊（4 封印师 / 16 祈祷师）不在场就永远不会结算。
# 去重口径由 helper 负责：封印靠 ctx["seals_triggered"]，赐福靠「谁放的 / 面前有没有」
# 与持有者的额外行动是否已存在，转发不会和源角色重复结算。
# ============================================================
func p_show_hand(ctx: Dictionary) -> int:
	if _封印 == null:
		return SUCCESS
	return int(_封印.p_show_hand(ctx))


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if _赐福 == null:
		return SUCCESS
	return int(_赐福.p_timeline_2_hit(ctx))


func p_after_attack(ctx: Dictionary) -> int:
	if _赐福 == null:
		return SUCCESS
	return int(_赐福.p_after_attack(ctx))


func p_after_magic(ctx: Dictionary) -> int:
	if _赐福 == null:
		return SUCCESS
	return int(_赐福.p_after_magic(ctx))


func p_additional_action(_ctx: Dictionary) -> int:
	return SUCCESS


# ============================================================
# 4602 邪灵退散：自己放置基础效果后，选 1 名目标对手造成 1 点法术伤害
# 4606 的借用放置同样会走到这里（先结算源技能，再问 4602，最后弃 4606 的那张牌）
# ============================================================
func p_basic_effect_change(ctx: Dictionary) -> int:
	if not bool(ctx.get("add", false)):
		return SUCCESS
	if int(ctx.get("doer", -1)) != player.id:
		return SUCCESS
	if not is_same(ctx, _变动ctx):
		_变动ctx = ctx
		_变动阶段 = 变动阶段_待4602

	if _变动阶段 == 变动阶段_待4602:
		var 对手: Array[int] = enemy_ids()
		if 对手.is_empty():
			_变动阶段 = 变动阶段_待4606弃牌
		else:
			_变动阶段 = 变动阶段_等4602回复
			询问(player.id, 邪灵退散, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true, 0, -1, 对手)
			return WAIT

	if _变动阶段 == 变动阶段_等4602回复:
		var r: Dictionary = take_skill_reply_full()
		_变动阶段 = 变动阶段_待4606弃牌
		var dsts: Array = r.get("dst_ids", [])
		if not dsts.is_empty():
			var dst_id: int = int(dsts[0])
			if enemy_ids().has(dst_id):
				notice_skill(邪灵退散, [dst_id])
				engine.push_harm({
					"src": player.id, "dst": dst_id, "point": 邪灵伤害,
					"cause": 邪灵退散, "type": GConst.HarmType.Magic,
				})
				engine._broadcast_game()
				return URGENT

	if _变动阶段 == 变动阶段_待4606弃牌:
		if not _4606待弃牌:
			_变动阶段 = 变动阶段_空闲
			return SUCCESS
		_4606待弃牌 = false
		if player.hand_cards.is_empty():
			_变动阶段 = 变动阶段_空闲
			return SUCCESS
		_变动阶段 = 变动阶段_等4606弃牌回复
		# 4606「你弃一张牌」是必付代价：can_cancel=false（手里没牌时上面已跳过）
		询问(player.id, 海神御巫, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false, 1)
		return WAIT

	if _变动阶段 == 变动阶段_等4606弃牌回复:
		var r2: Dictionary = take_skill_reply_full()
		_变动阶段 = 变动阶段_空闲
		var cid: int = -1
		for 值: Variant in r2.get("card_ids", []):
			if player.has_hand_card(int(值)):
				cid = int(值)
				break
		# 强制弃牌：超时 / 改包没给合法牌时按手牌第一张兜底，不能因为不回而白跳过代价
		if cid < 0 and not player.hand_cards.is_empty():
			cid = int(player.hand_cards[0])
		if cid >= 0:
			engine.take_from_hand(player.id, [cid])
			engine.to_discard([cid])
			engine._log_discard(player.id, [cid])
			engine._broadcast_game()
		return SUCCESS
	return SUCCESS


# ============================================================
# 伤害结算前（timeline_3）：记「本回合自己造成的伤害」供 4603；4605 的 X 在这里现算
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty():
		return SUCCESS
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	var 类型: int = int(harm.get("type", GConst.HarmType.None))
	# 4603 只认「你回合内」造成的伤害：别的回合里由 46 造成的伤害不记，避免留到下一回合误触发
	if engine.current_id == player.id \
			and (类型 == GConst.HarmType.Attack or 类型 == GConst.HarmType.Magic):
		_本回合自己伤害.append({
			"dst": int(harm.get("dst", -1)),
			"cause": int(harm.get("cause", 0)),
			"type": 类型,
		})
	# 4605 的「目标每有 X 个基础效果，本次伤害 +X」按结算时目标身上的基础效果数现算（A17）
	if int(harm.get("cause", 0)) == 怒潮荒涛:
		var dst: BattlePlayer = engine.p(int(harm.get("dst", -1)))
		if dst != null:
			harm["point"] = int(harm.get("point", 0)) + dst.basic_effects.size()
	return SUCCESS


# ============================================================
# 4603 伴响魂灵：自己回合内目标对手因自己造成的伤害掉士气 → 其余对手各 1 点法术伤害③
# ============================================================
func p_true_lose_morale(ctx: Dictionary) -> int:
	if _本回合已触发4603 or engine == null or player == null:
		return SUCCESS
	if engine.current_id != player.id:
		return SUCCESS
	if int(ctx.get("amount", 0)) <= 0:
		return SUCCESS
	var 类型: int = int(ctx.get("type", GConst.HarmType.None))
	if 类型 != GConst.HarmType.Attack and 类型 != GConst.HarmType.Magic:
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.color == player.color:
		return SUCCESS
	var harm_cause: int = int(ctx.get("harm_cause", 0))
	if not _取出匹配伤害(dst_id, harm_cause, 类型):
		return SUCCESS
	_本回合已触发4603 = true
	notice_skill(伴响魂灵, [dst_id])
	var 目标: Array[int] = []
	for pid: int in enemy_ids():
		if pid != dst_id:
			目标.append(pid)
	if 目标.is_empty():
		engine._broadcast_game()
		return SUCCESS
	var 顺序: Array[int] = 结算顺序(目标)
	for i: int in range(顺序.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": 顺序[i], "point": 伴响伤害,
			"cause": 伴响魂灵, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


## 在「本回合自己造成的伤害」里找一条与本次掉士气来源匹配的记录并消费掉。
## 只在找得到时才算「因你造成的伤害」，避免把别人的伤害 / 非伤害惩罚误算成 4603。
func _取出匹配伤害(dst_id: int, cause: int, 类型: int) -> bool:
	for i: int in range(_本回合自己伤害.size() - 1, -1, -1):
		var 记录: Dictionary = _本回合自己伤害[i]
		if int(记录.get("dst", -1)) == dst_id and int(记录.get("cause", -2)) == cause \
				and int(记录.get("type", -1)) == 类型:
			_本回合自己伤害.remove_at(i)
			return true
	return false


# ============================================================
# 4604 波涌之力：任意角色触发了基础效果并结算完成后，+1【灵涌】
# ============================================================
func p_basic_effect_triggered(ctx: Dictionary) -> int:
	if not 可用():
		return SUCCESS
	var 实际: int = player.add_token(灵涌槽, 1)
	if 实际 > 0:
		notice_skill(波涌之力, [int(ctx.get("dst", -1))])
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 4605 怒潮荒涛：自己的回合结束时【灵涌】已满 → 清空灵涌，对场上所有角色各 1 点法术伤害
# （4 人局＝场上所有角色，含队友，A17；目标的额外伤害在 p_timeline_3 现算）
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	var 上限: int = player.token_max(灵涌槽)
	if 上限 <= 0 or player.token_num(灵涌槽) < 上限:
		return SUCCESS
	step = STEP_DONE
	player.clear_token(灵涌槽)
	notice_skill(怒潮荒涛, [player.id])
	var 目标: Array[int] = []
	for pid: int in engine.order:
		目标.append(pid)
	if 目标.is_empty():
		engine._broadcast_game()
		return SUCCESS
	var 顺序: Array[int] = 结算顺序(目标)
	for i: int in range(顺序.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": 顺序[i], "point": 怒潮基础伤害,
			"cause": 怒潮荒涛, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT

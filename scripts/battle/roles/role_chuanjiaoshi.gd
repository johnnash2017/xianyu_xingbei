extends BattleRole
## 传教士（roleID 96 / 技能 9601~9608）
##
## 【路标】＝一张场卡（owner 始终是传教士，attached＝当前持有者）；【虔诚】＝0 号指示物（上限 4）。
## 左右手约定：座位链的 pre_id 是左手边、post_id 是右手边。
##
## 技能原文与实现：
##   神的门徒 9601（被动·恒定）：你无法成为【路标】的目标；2V2 中此技能无效。
##       ⚠ 后半句「你的行动顺序改为拥有【路标】的角色之后」引擎没有动态行动顺序，仍未实现（见遗留）。
##   信仰之路 9602（被动）：你的第一回合开始把【路标】放到你左手边最近的角色面前；
##       你的回合结束若本回合未执行【特殊行动】，把【路标】转移到持有者左手边最近的角色面前。
##   传道 9603（启动）：摸 0~1 张牌、弃 1 张牌【强制】【展示】，你 +1【虔诚】；
##       持有【路标】的角色弃 1 张牌【展示】，你获得该牌【强制】；
##       若该牌与你弃牌的系别或命格相同，你额外 +1【虔诚】。
##   启示 9604（响应·路标转移前）：移除 2 点【虔诚】，二选一 —— 目标角色 +1【治疗】；
##       或你摸 1 张牌【强制】【展示】，若该牌为法术牌或圣类命格，取消本次转移、移除【路标】，
##       然后把【路标】放到目标角色面前。
##   事奉 9605（响应）：你因自身技能弃的牌置入弃牌堆时，移除你 1【治疗】，把该弃牌加入拥有
##       【路标】的角色手牌【强制】；（若没有因此造成该角色阵营士气下降）指定除你外的目标角色 +1【治疗】。
##   路标 9606（响应·专属技·告解式·回合限定）：此卡被转移至某人面前时，他摸 2 张牌【强制】，
##       我方【战绩区】+1【水晶】，然后把此卡转移至他左手边最近的角色面前，传教士弃 1 张牌。
##   属灵恩赐 9607（启动·必杀【水晶】）：你 +1【治疗】，弃 1 张牌。
##   弥撒 9608（响应·必杀【水晶】）：【路标】转移或放置后，你 +1【虔诚】，二选一 ——
##       弃 1 张牌【展示】（是【虚弱】/【中毒】/【圣盾】就放到持有【路标】的角色面前作为基础效果）；
##       或把持有【路标】的角色面前 1 张基础效果牌收入自己手中，你额外 +1【虔诚】。
##
## 写法：所有「分几次问玩家」的技能都走 `BattleRole.多步询问`（约定见 项目文档/技能维护约定.md），
## 不再自己维护阶段机；跨段依赖放在段字段 `答完` 里。

const SHEN_DE_MEN_TU: int = 9601
const XIN_YANG_ZHI_LU: int = 9602
const CHUAN_DAO: int = 9603
const QI_SHI: int = 9604
const SHI_FENG: int = 9605
const LU_BIAO: int = 9606
const SHU_LING_EN_CI: int = 9607
const MI_SA: int = 9608

const 虔诚槽: int = 0
const 路标名: String = "路标"
## 【虚弱】/【中毒】/【圣盾】是「放到角色面前」的基础效果牌（弥撒二选一里用）
const 基础效果牌名: Array[int] = [
	GConst.CardName.Shield, GConst.CardName.Weaken, GConst.CardName.Poison,
]

## 信仰之路：第一回合的路标已经放过了
var _首回合已放: bool = false
## 路标到达之后的后续：0＝无 / 1＝等告解式的摸牌 / 2＝等传教士弃牌 / 3＝弥撒
var _到达阶段: int = 0
## 告解式【回合限定】：记「哪一回合已经发动过告解式」（engine.round_id；-1＝本局还没用过）
var _告解回合: int = -1

## 传道：段 2 答完时弃掉的自己的那张（段 3 收下对方的牌后比系别 / 命格用）
var _传道自己弃: int = -1

## 启示：本次想转移到的目标 / 她在第 2 段选的目标 / 摸牌前的手牌快照 / 收尾是否已经处理过
var _转移目标: int = -1
var _启示目标: int = -1
var _启示摸前: Array = []
var _启示已处理: bool = false

## 弥撒：第 1 段选的分支、以及「收哪张基础效果」的候选表
var _弥撒选择: int = 0
var _弥撒可选: Array = []


# ============================================================
# 技能栏 / 校验 / 入口
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.ActivateSkill,
			"id": CHUAN_DAO,
			"need_card": 0,
			"need_target": 0,
			# 手里没牌也能发动：先摸 1 张再弃；连牌库都空了才会白跑一趟
			"enabled": true,
		},
		{
			"type": GConst.ActionType.ActivateSkill,
			"id": SHU_LING_EN_CI,
			"need_card": 1,
			"need_target": 0,
			"enabled": player.get_energy() >= 1 and not player.hand_cards.is_empty(),
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == CHUAN_DAO or skill_id == SHU_LING_EN_CI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == SHU_LING_EN_CI:
		# 【水晶】费用：宝石可顶水晶（get_energy）；代价「弃 1 张牌」必须真交一张手牌
		if player.get_energy() < 1 or _提交的手牌(action.get("card_ids", [])) < 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if 技能号 == CHUAN_DAO:
		多步询问重置(CHUAN_DAO)
		_传道自己弃 = -1
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_special_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHU_LING_EN_CI:
			return _属灵恩赐(action)
		CHUAN_DAO:
			return _传道()
	return SUCCESS


# ============================================================
# 属灵恩赐 9607：水晶 → +1 治疗、弃 1 张
# ============================================================
func _属灵恩赐(action: Dictionary) -> int:
	var 弃: int = _提交的手牌(action.get("card_ids", []))
	if 弃 < 0:
		return SUCCESS
	player.boot_skill_used = true
	notice_skill(SHU_LING_EN_CI, [player.id])
	player.remove_energy(1)
	施加治疗(player.id, 1)
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": SHU_LING_EN_CI})
	engine._log_discard(player.id, [弃])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 传道 9603（启动）：摸 0~1 → 弃 1【展示】→ 持有者弃 1【展示】→ 你收下
# ============================================================
func _传道() -> int:
	if not 多步询问进行中(CHUAN_DAO):
		# 「启动」技能：本回合只能发动一个（引擎只校验这个标记）
		player.boot_skill_used = true
	return 多步询问(CHUAN_DAO, [
		{"选项": _传道摸牌选项(), "可取消": false, "答完": _传道摸牌},
		# 自己的代价：弃 1 张牌【强制】【展示】
		{"需牌": 1,
		 "牌白": func(_答案: Array) -> Array: return player.hand_cards,
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool: return player.hand_cards.is_empty(),
		 "答完": _传道弃自己的},
		# 持有【路标】的角色弃 1 张【展示】，你获得该牌
		{"问谁": func(_答案: Array) -> int: return 路标持有者(),
		 "需牌": 1,
		 "牌白": func(_答案: Array) -> Array:
			var dp: BattlePlayer = engine.p(路标持有者())
			return dp.hand_cards if dp != null else [],
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool:
			return _传道自己弃 < 0 or not _可向他收牌(路标持有者()),
		 "答完": _传道收牌},
	], _传道结算)


func _传道摸牌选项() -> Array:
	return [
		{"value": 0, "label": GConst.按钮原文(CHUAN_DAO, 0), "text": GConst.按钮原文(CHUAN_DAO, 0)},
		{"value": 1, "label": GConst.按钮原文(CHUAN_DAO, 1), "text": GConst.按钮原文(CHUAN_DAO, 1)},
	]


## 向某人收牌的前提：是别人、且手里有牌
func _可向他收牌(pid: int) -> bool:
	var dp: BattlePlayer = engine.p(pid)
	return pid >= 0 and pid != player.id and dp != null and not dp.hand_cards.is_empty()


## 第 1 段答完：按选项摸牌（摸牌要等引擎跑完，重入再问第 2 段，见 技能URGENT后重入）
func _传道摸牌(回: Dictionary, _答案: Array) -> int:
	var args: Array = 回.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	engine.push_强制摸牌(player.id, 1, CHUAN_DAO)
	return URGENT


## 第 2 段答完：把自己的代价牌【展示】弃掉、+1【虔诚】
func _传道弃自己的(回: Dictionary, _答案: Array) -> int:
	var 弃: int = _提交的手牌(回.get("cards", []))
	if 弃 < 0:
		return SUCCESS
	_传道自己弃 = 弃
	# 「弃 1 张牌【强制】【展示】」：统一入口（亮牌 + 触发封印 + 离手 + 弃牌堆 + 日志）
	engine.展示手牌并弃(player.id, [弃], {"cause": CHUAN_DAO})
	player.add_token(虔诚槽, 1)
	engine._broadcast_game()
	return SUCCESS


## 第 3 段答完：持有者弃的那张【展示】后归你；与你弃的牌同系别或同命格 → 再 +1【虔诚】
func _传道收牌(回: Dictionary, _答案: Array) -> int:
	var 到: int = 路标持有者()
	var dp: BattlePlayer = engine.p(到)
	if dp == null:
		return SUCCESS
	var 得: int = -1
	for c: Variant in 回.get("cards", []):
		var 实例: int = dp.手牌实例(int(c))
		if 实例 >= 0:
			得 = 实例
			break
	if 得 < 0:
		return SUCCESS
	# 「持有【路标】的角色弃 1 张牌【展示】」：统一入口（亮牌 + 触发封印）；牌不进弃牌堆，直接归你
	engine.展示手牌(到, [得])
	engine.take_from_hand(到, [得])
	player.add_hand_cards([得])
	engine.播获得牌日志(player.id, [得])
	var 我: GCard = Data.get_card(_传道自己弃)
	var 他: GCard = Data.get_card(得)
	if 我 != null and 他 != null and (我.element_enum() == 他.element_enum()
			or 我.fate_pattern_enum() == 他.fate_pattern_enum()):
		player.add_token(虔诚槽, 1)
	engine._broadcast_game()
	return SUCCESS


func _传道结算(_答案: Array) -> int:
	engine._broadcast_game()
	return SUCCESS


## 摸牌那段答完会返回 URGENT：让 SkillRun 放行重入技能本体，接着问第 2 段
func 技能URGENT后重入(_action: Dictionary = {}) -> bool:
	var 技能号: int = int(_action.get("action_id", 0))
	if 技能号 == CHUAN_DAO:
		return 多步询问进行中(CHUAN_DAO)
	if 技能号 == QI_SHI:
		return 多步询问进行中(QI_SHI) or 多步询问待收尾(QI_SHI)
	return false


# ============================================================
# 信仰之路 9602：第一回合放【路标】；回合结束（未执行特殊行动）转移【路标】
# ============================================================
func p_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 续: int = _收尾没走完的部分()
	if 续 != SUCCESS:
		return 续
	if not _首回合已放:
		var 左: int = _下一个可持路标者(player.id)
		if 左 >= 0:
			_首回合已放 = true
			return _放置路标(左)
	return SUCCESS


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 续: int = _收尾没走完的部分()
	if 续 != SUCCESS:
		return 续
	# 本回合执行过【特殊行动】就不转移
	if player.action_count_of("special") > 0:
		return SUCCESS
	var 持有者: int = 路标持有者()
	if 持有者 < 0:
		return SUCCESS
	var 左: int = _下一个可持路标者(持有者)
	if 左 < 0:
		return SUCCESS
	return _转移路标(左)


## 上一次的路标到达 / 弥撒 / 启示链被打断时，先把它们走完再处理这次的新触发
func _收尾没走完的部分() -> int:
	if _到达阶段 != 0:
		return _到达后续()
	if 多步询问进行中(MI_SA):
		return _弥撒()
	if 多步询问进行中(QI_SHI) or 多步询问待收尾(QI_SHI):
		return _启示链()
	return SUCCESS


# ============================================================
# 路标放置 / 转移：到达后依次跑【告解式】与【弥撒】
# ============================================================
func _放置路标(目标: int) -> int:
	if not _可持路标(目标):
		return SUCCESS
	engine.加场卡({"id": 路标名, "owner": player.id, "attached": 目标})
	engine._broadcast_game()
	_到达阶段 = 1
	return _到达后续()


## 把【路标】转移给某人（保留 owner）
func _路标放下(目标: int) -> void:
	engine.加场卡({"id": 路标名, "owner": player.id, "attached": 目标})
	engine._broadcast_game()


## 路标到达之后的后续：告解式（摸 2 张 → 战绩区 +1 水晶 → 移给左手边 → 传教士弃 1 张）→ 弥撒
func _到达后续() -> int:
	if _到达阶段 == 1:
		var 到: int = 路标持有者()
		if not _可发动告解(到):
			_到达阶段 = 3
			return _到达后续()
		_告解回合 = engine.round_id
		notice_skill(LU_BIAO, [到])
		_到达阶段 = 2
		engine.push_强制摸牌(到, 2, LU_BIAO)
		return URGENT
	if _到达阶段 == 2:
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
		# 「然后将此卡转移至你左手边最近的角色面前」：这里跳过的只有不能被放路标的传教士
		var 下: int = _下一个可持路标者(路标持有者())
		if 下 >= 0:
			_路标放下(下)
		_到达阶段 = 3
		if player.hand_cards.is_empty():
			return _到达后续()
		engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, LU_BIAO))
		return URGENT
	_到达阶段 = 0
	# 弥撒是【必杀·水晶】：没有能量就不问
	if player.get_energy() < 1:
		return SUCCESS
	return _弥撒()


## 告解式能不能发动：回合限定（一回合一次），且到达者不是传教士自己
func _可发动告解(到: int) -> bool:
	return _告解回合 != engine.round_id and _可持路标(到)


# ============================================================
# 启示 9604（响应·路标转移前）：移除 2【虔诚】→ 二选一
# ============================================================
func _转移路标(目标: int) -> int:
	if not _可持路标(目标):
		return SUCCESS
	# 链已经在问（重入）：继续把链跑完
	if 多步询问进行中(QI_SHI) or 多步询问待收尾(QI_SHI):
		return _启示链()
	if player.token_num(虔诚槽) < 2:
		return _放置路标(目标)
	_转移目标 = 目标
	_启示目标 = -1
	_启示已处理 = false
	return _启示链()


func _启示链() -> int:
	return 多步询问(QI_SHI, [
		{"选项": _启示选项(), "取消": _启示不发动, "答完": _启示选分支},
		# 分支①选治疗目标；分支②选「若成功就改放到谁面前」（神的门徒：不能是自己）
		{"需目标": 1,
		 "目标白": func(_答案: Array) -> Array: return 全部角色() if _启示分支值 == 1 else 除自己(),
		 "预览基准": 1, "预览类型": GConst.预览类型_治疗,
		 "取消": _启示不发动},
	], _启示结算, _启示摸牌收尾)


## 启示第 1 段选的分支（1＝目标 +1 治疗 / 2＝摸 1 张牌试图取消转移）
var _启示分支值: int = 1


## 启示不发动（第 1 段取消 / 第 2 段取消 / 超时）：什么都不扣，照常把路标放到原定目标
func _启示不发动() -> int:
	_启示目标 = -1
	return _放置路标(_转移目标)


## 第 1 段答完：只记分支（【虔诚】等结算时再扣 —— 中途取消不该白扣 2 点）
func _启示选分支(回: Dictionary, _答案: Array) -> int:
	var args: Array = 回.get("args", [])
	_启示分支值 = int(args[0]) if not args.is_empty() else 1
	return SUCCESS


func _启示结算(答案: Array) -> int:
	var 回2: Dictionary = 答案[答案.size() - 1] if not 答案.is_empty() else {}
	var dsts: Array = 回2.get("dsts", [])
	_启示目标 = int(dsts[0]) if not dsts.is_empty() else -1
	if _启示目标 < 0 or engine.p(_启示目标) == null:
		return _放置路标(_转移目标)
	# 发动代价：移除 2 点【虔诚】
	player.remove_token(虔诚槽, 2)
	notice_skill(QI_SHI, [player.id])
	engine._broadcast_game()
	if _启示分支值 == 1:
		施加治疗(_启示目标, 1)
		engine._broadcast_game()
		# 放置路标会顺带压告解 / 弥撒：那是别的流程，不登记本链的收尾。
		# 放完如果没压任何状态就把这个标记清掉，别让它漏给下一次启示链。
		多步询问跳过收尾(QI_SHI)
		var 返: int = _放置路标(_转移目标)
		if 返 == SUCCESS:
			多步询问重置(QI_SHI)
		return 返
	# 分支②：摸 1 张牌，摸完再看它是不是法术牌 / 圣类命格（收尾里判断）
	_启示摸前 = player.hand_cards.duplicate()
	engine.push_强制摸牌(player.id, 1, QI_SHI)
	return URGENT


## 分支②摸完牌后的收尾：是法术牌 / 圣类命格就取消本次转移、把路标改放到启示目标面前
func _启示摸牌收尾() -> int:
	if _启示已处理:
		# 判断和放置已经做过：把告解 / 弥撒继续跑
		if _到达阶段 != 0:
			return _到达后续()
		return SUCCESS
	_启示已处理 = true
	var 新牌: int = -1
	for c: Variant in player.hand_cards:
		if not _启示摸前.has(int(c)):
			新牌 = int(c)
			break
	_启示摸前 = []
	var 牌: GCard = Data.get_card(新牌) if 新牌 >= 0 else null
	if 新牌 >= 0:
		# 「你摸 1 张牌【强制】【展示】」：统一入口（亮牌 + 触发封印）
		engine.展示手牌(player.id, [新牌])
	var 成: bool = 牌 != null and (牌.is_magic() or 牌.fate_pattern_enum() == GConst.FatePattern.Holy)
	if 成 and _可持路标(_启示目标):
		# 取消本次转移：移除【路标】，改放到启示目标面前（这也是一次放置，照样跑告解 / 弥撒）
		engine.移除场卡(路标名)
		_路标放下(_启示目标)
		_到达阶段 = 1
		return _到达后续()
	return _放置路标(_转移目标)


func _启示选项() -> Array:
	return [
		{"value": 1, "label": GConst.按钮原文(QI_SHI, 0), "text": GConst.按钮原文(QI_SHI, 0)},
		{"value": 2, "label": GConst.按钮原文(QI_SHI, 1), "text": GConst.按钮原文(QI_SHI, 1)},
	]


# ============================================================
# 事奉 9605：因自身技能弃牌时，移除 1【治疗】把该牌交给路标持有者；没害他爆牌再给 1【治疗】
# ============================================================
func wants_before_discard(ctx: Dictionary) -> bool:
	return _事奉可发动(ctx)


## 只有 wants_before_discard 返回 true，引擎才会推迟这次弃牌、跑 p_before_discard
func _事奉可发动(ctx: Dictionary) -> bool:
	if int(ctx.get("owner", -1)) != player.id:
		return false
	if str(ctx.get("source", "")) != "hand":
		return false
	if not [CHUAN_DAO, SHU_LING_EN_CI, MI_SA, LU_BIAO].has(int(ctx.get("cause", 0))):
		return false
	if player.cross_num <= 0:
		return false
	var 持有者: int = 路标持有者()
	return 持有者 >= 0 and 持有者 != player.id


func p_before_discard(ctx: Dictionary) -> int:
	if not _事奉可发动(ctx):
		return SUCCESS
	# 已经在问「给谁 +1 治疗」：重入继续把链跑完（回复要靠它消费）
	if 多步询问进行中(SHI_FENG):
		return _事奉链()
	var 键: String = "_事奉_%d" % int(ctx.get("cause", 0))
	if bool(ctx.get(键, false)):
		return SUCCESS
	ctx[键] = true
	var 取: Array = []
	for c: Variant in ctx.get("cards", []):
		取.append(int(c))
	if 取.is_empty():
		return SUCCESS
	var 持有者: int = 路标持有者()
	# 代价：移除你 1【治疗】；弃牌改由他收下（taken / taker 交给引擎结算）
	player.sub_cross_num(1)
	ctx["taken"] = 取
	ctx["taker"] = 持有者
	notice_skill(SHI_FENG, [持有者])
	engine._broadcast_game()
	# 「若没有因此造成该角色阵营士气下降」＝这张牌不会让他爆牌
	var 他: BattlePlayer = engine.p(持有者)
	if 他 == null or 他.hand_cards.size() + 取.size() > 他.hand_cards_max:
		return SUCCESS
	return _事奉链()


func _事奉链() -> int:
	return 多步询问(SHI_FENG, [
		{"需目标": 1,
		 "目标白": 除自己(),
		 "预览基准": 1, "预览类型": GConst.预览类型_治疗},
	], _事奉结算)


func _事奉结算(答案: Array) -> int:
	var dsts: Array = (答案[0] as Dictionary).get("dsts", []) if not 答案.is_empty() else []
	if dsts.is_empty():
		return SUCCESS
	施加治疗(int(dsts[0]), 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 弥撒 9608（响应·必杀【水晶】）：路标转移/放置后，+1【虔诚】，二选一
# ============================================================
func _弥撒() -> int:
	# 跨段状态只在新的一条链开始时清：第 2 段回复回来重入时还要用它判断是哪一支
	if not 多步询问进行中(MI_SA):
		_弥撒选择 = 0
		_弥撒可选 = []
	return 多步询问(MI_SA, [
		{"选项": _弥撒选项(), "答完": _弥撒记录选择},
		{"选项": func(_答案: Array) -> Array: return _收入选项(_弥撒可选),
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool: return not _弥撒需要二段()},
	], _弥撒结算)


## 第 1 段答完：只记下选择；选②时把持有者面前的基础效果表抄下来给第 2 段用
func _弥撒记录选择(回: Dictionary, _答案: Array) -> int:
	var args: Array = 回.get("args", [])
	_弥撒选择 = int(args[0]) if not args.is_empty() else 0
	_弥撒可选 = []
	if _弥撒选择 == 2:
		var dp: BattlePlayer = engine.p(路标持有者())
		_弥撒可选 = _基础效果列表(dp) if dp != null else []
	return SUCCESS


## 选②且持有者面前有 ≥2 张基础效果时才问第 2 段「收哪一张」
func _弥撒需要二段() -> bool:
	return _弥撒选择 == 2 and _弥撒可选.size() > 1


func _弥撒结算(答案: Array) -> int:
	if _弥撒选择 != 1 and _弥撒选择 != 2:
		return SUCCESS
	var 持有: int = 路标持有者()
	var dp: BattlePlayer = engine.p(持有)
	if dp == null:
		return SUCCESS
	if _弥撒选择 == 1:
		return _弥撒弃牌(答案, 持有)
	return _弥撒收牌(答案, dp)


## ① 弃 1 张牌【展示】；是【虚弱】/【中毒】/【圣盾】就挂到持有者面前作为基础效果
func _弥撒弃牌(答案: Array, 持有: int) -> int:
	var cards: Array = (答案[0] as Dictionary).get("cards", []) if not 答案.is_empty() else []
	var 弃: int = _提交的手牌(cards)
	if 弃 < 0:
		return SUCCESS
	player.remove_energy(1)
	player.add_token(虔诚槽, 1)
	notice_skill(MI_SA, [持有])
	engine._broadcast_game()
	engine.展示手牌(player.id, [弃])
	engine.take_from_hand(player.id, [弃])
	var 牌: GCard = Data.get_card(弃)
	if 牌 != null and 基础效果牌名.has(牌.card_name_enum()):
		engine.add_basic_effect(持有, 弃, player.id, MI_SA)
	else:
		engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": MI_SA})
		engine._log_discard(player.id, [弃], false)
	engine._broadcast_game()
	return SUCCESS


## ② 把持有者面前 1 张基础效果牌收入手中，额外 +1【虔诚】
func _弥撒收牌(答案: Array, dp: BattlePlayer) -> int:
	var 可选: Array = _弥撒可选 if _弥撒需要二段() else _基础效果列表(dp)
	if 可选.is_empty():
		return SUCCESS
	var 序: int = 0
	if _弥撒需要二段():
		var args2: Array = (答案[1] as Dictionary).get("args", []) if 答案.size() > 1 else []
		if args2.is_empty():
			return SUCCESS
		序 = int(args2[0]) - 1
		if 序 < 0 or 序 >= 可选.size():
			engine.报错("【弥撒】选项号越界", player.id)
			return SUCCESS
	player.remove_energy(1)
	player.add_token(虔诚槽, 2)
	notice_skill(MI_SA, [dp.id])
	engine._broadcast_game()
	var 牌: int = int(可选[序])
	engine.remove_basic_effect(dp.id, 牌, MI_SA, player.id)
	player.add_hand_cards([牌])
	engine.播获得牌日志(player.id, [牌])
	engine._broadcast_game()
	return SUCCESS


func _弥撒选项() -> Array:
	var dp: BattlePlayer = engine.p(路标持有者())
	var 有基础: bool = dp != null and not _基础效果列表(dp).is_empty()
	return [
		{
			"value": 1,
			"label": GConst.按钮原文(MI_SA, 0),
			"text": GConst.按钮原文(MI_SA, 0),
			"need_card": 1 if not player.hand_cards.is_empty() else 0,
			"enabled": not player.hand_cards.is_empty(),
		},
		{
			"value": 2,
			"label": GConst.按钮原文(MI_SA, 1),
			"text": GConst.按钮原文(MI_SA, 1),
			"enabled": 有基础,
		},
	]


## 持有者面前的基础效果牌（跳过 Tricky 占位，避免与捣蛋萝莉的脚本状态脱节）
func _基础效果列表(dp: BattlePlayer) -> Array:
	var out: Array = []
	for be: Dictionary in dp.basic_effects:
		if int(be["card"]) != 1008:
			out.append(int(be["card"]))
	return out


func _收入选项(表: Array) -> Array:
	var out: Array = []
	for i: int in range(表.size()):
		var 牌: GCard = Data.get_card(int(表[i]))
		var 文案: String = 牌.card_name if 牌 != null else ""
		out.append({"value": i + 1, "label": 文案, "text": 文案, "card_id": int(表[i])})
	return out


# ============================================================
# 小工具
# ============================================================
## 提交的牌里第一张「确实在自己手里」的实例号（没有返回 -1）
func _提交的手牌(cards: Array) -> int:
	for c: Variant in cards:
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			return 实例
	return -1


## 左手边最近的玩家（座位链的 pre_id）；找不到返回 -1
func 左手边(pid: int) -> int:
	var p0: BattlePlayer = engine.p(pid)
	if p0 == null:
		return -1
	return p0.pre_id


func 路标持有者() -> int:
	var 表: Dictionary = engine.取场卡(路标名)
	if 表.is_empty():
		return -1
	return int(表.get("attached", -1))


## 神的门徒 9601：【路标】不能放在传教士自己面前；2V2 里此技能无效（她也算合法目标）
func _可持路标(pid: int) -> bool:
	if engine.p(pid) == null:
		return false
	return pid != player.id or _是2v2()


## 2V2：两队各 2 人（4 人局）
func _是2v2() -> bool:
	var 红: int = 0
	var 蓝: int = 0
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null:
			continue
		if p0.color == GConst.RED:
			红 += 1
		else:
			蓝 += 1
	return 红 == 2 and 蓝 == 2


## 从某人往里找「左手边最近、且能被放路标」的角色（跳过传教士自己）
func _下一个可持路标者(从前: int) -> int:
	var 当前: int = 从前
	for _i: int in range(engine.order.size()):
		当前 = 左手边(当前)
		if 当前 < 0:
			return -1
		if 当前 != 从前 and _可持路标(当前):
			return 当前
	return -1


## 除自己以外的全部在场角色（神之门徒：路标不能放在传教士自己面前；事奉的治疗目标同理）
func 除自己() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if pid != player.id:
			out.append(pid)
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

extends BattleRole
## 记录者（roleID 94 / 技能 9401~9409）
##
## 【遗迹】＝角色旁面朝上的牌（盖牌区 open=true，上限读角色表盖牌槽：8），属于她自己的资源；
## 【史料】＝0 号指示物（上限读角色表：3）；【史书】＝卡表#1007（地系·幻类命格攻击牌，唯一实例，
## 不在牌库；被使用 / 弃置 / 转移 / 因技能放置到角色旁时移出游戏）。
##
## 技能：
##   传说之地 9401（被动）：游戏初始时把牌库顶 3 张面朝上放在自己角色旁作为【遗迹】。
##   知行合一 9402（法术）：展示牌库顶 2 张，你可选其中 1 张作为相应行动打出并弃 1 张手牌；
##       那个行动结算完成后，把剩余展示牌弃掉、你 +X【史料】。
##   稽古识典 9403（被动）：【史料】达到上限时，移除所有【史料】，你弃 1 张牌，
##       将【史书】加入手牌（强制）。
##   遗迹论破 9404（响应·回合限定）：主动攻击① 时，移除与攻击牌同系的 X 个【遗迹】→
##       本次攻击伤害额外 +（X-1）；（X>1）额外 +1【法术行动】；（遗迹因此为 0）我方【战绩区】+1【宝石】。
##   选淬精炼 9405（被动）：光系 / 暗系的【遗迹】视为任意系别（见 _同系遗迹）。
##   秘境万象 9406（法术）：移除【史书】与所有【遗迹】，展示牌库顶直到出现同系牌为止；
##       展示的 X 张都面朝上作为【遗迹】；（X>3）对（X-3）名目标角色各 2 点法术伤害。
##   以史为镜 9407（被动）：【史书】视为地系幻类命格攻击牌；被使用 / 打出 / 弃置 / 转移拥有者 /
##       因技能放置在角色旁时，移除此卡。
##   古今互鉴 9408（启动·必杀【水晶】）：你 +2【史料】；（手牌数>1）可将 2 张手牌与 X 个【遗迹】交换，X>0。
##   引稽编鉴 9409（响应）：用【史书】主动攻击① 时，指定攻击目标将 1 张手牌加入【遗迹】，
##       然后将你手上 X 张牌与 X 个【遗迹】交换，X<3。
##
## 写法：一个技能要分几次问玩家一律走 `BattleRole.多步询问`（段表 + 结算回调），
## 不再自己维护 `_xxx阶段` 状态机（见 项目文档/技能维护约定.md「多步询问」小节）。

const CHUAN_SHUO_ZHI_DI: int = 9401
const ZHI_XING_HE_YI: int = 9402
const JI_GU_SHI_DIAN: int = 9403
const YI_JI_LUN_PO: int = 9404
const XUAN_CUI_JING_LIAN: int = 9405
const MI_JING_WAN_XIANG: int = 9406
const YI_SHI_WEI_JING: int = 9407
const GU_JIN_HU_JIAN: int = 9408
const YIN_JI_BIAN_JIAN: int = 9409

const 史料槽: int = 0
const 史书号: int = 1007
## 一次交换最多几张（9408 / 9409 都是「X<3」，即 1~2 张，按钮表也只有两档）
const 交换上限: int = 2

## 知行合一：本次展示的牌（还没结算的）/ 打出那张之后要弃掉并换成【史料】的剩余展示牌
var _知行展示: Array = []
var _知行余: Array = []
## 这一次走的是「全部化为【史料】」/取消（展示牌已换成史料，第 2 步与结算都不再做别的）
var _知行已取消: bool = false
## 本次发动已经把展示牌翻出来了（重入时不要重复翻牌 / 重复扣费）
var _知行已付: bool = false

## 古今互鉴：本次发动已经付过【水晶】、加过【史料】（重入时不要重复付）
var _古今已付: bool = false

## 遗迹论破：【回合限定】本回合已发动 / 本次攻击已经问过（同一张攻击牌不要再问第二次）
var _遗迹论破已用: bool = false
var _遗迹论破已问: bool = false

## 引稽编鉴：本次攻击已经问过 / 整条链已经结算完（之后同类攻击直接走遗迹论破）
var _引稽已问: bool = false
var _引稽已完结: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	_传说之地()


# ============================================================
# 传说之地 9401：开局把牌库顶 3 张面朝上放到角色旁作为【遗迹】
# ============================================================
## 只在「游戏初始」那一次。角色替换进来的不算开局：否则等于凭空再生 3 张【遗迹】。
func _传说之地() -> void:
	if engine.round_id > 1 or not player.hand_cards.is_empty():
		return
	var cards: Array[int] = engine.移除牌库顶(3)
	if cards.is_empty():
		return
	engine.展示牌库顶(player.id, cards)
	engine.add_cover(player.id, cards, player.id, CHUAN_SHUO_ZHI_DI, true)


# ============================================================
# 技能栏 / 校验 / 入口
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": ZHI_XING_HE_YI,
			"need_card": 0,
			"need_target": 0,
			# 「并弃 1 张牌」是发动的代价：手里一张牌都没有时发动不了
			"enabled": engine.deck.pile_size() > 0 and not player.hand_cards.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": MI_JING_WAN_XIANG,
			"need_card": 0,
			"need_target": 0,
			"enabled": _史书在手(),
		},
		{
			"type": GConst.ActionType.ActivateSkill,
			"id": GU_JIN_HU_JIAN,
			"need_card": 0,
			"need_target": 0,
			"enabled": player.get_energy() >= 1,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == GU_JIN_HU_JIAN


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == ZHI_XING_HE_YI:
		if engine.deck.pile_size() <= 0 or player.hand_cards.is_empty():
			return GConst.GE_INVALID_ACTION
		# 新的一次发动：把上一次可能残留的链 / 中间态清干净（v_* 只在技能开始时调一次）
		多步询问重置(ZHI_XING_HE_YI)
		_知行展示 = []
		_知行余 = []
		_知行已取消 = false
		_知行已付 = false
		return GConst.GE_SUCCESS
	if 技能号 == MI_JING_WAN_XIANG:
		if not _史书在手():
			return GConst.GE_INVALID_ACTION
		多步询问重置(MI_JING_WAN_XIANG)
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != GU_JIN_HU_JIAN:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	多步询问重置(GU_JIN_HU_JIAN)
	_古今已付 = false
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		ZHI_XING_HE_YI:
			return _知行合一()
		MI_JING_WAN_XIANG:
			return _秘境万象()
	return EMPTY_HANDLE


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != GU_JIN_HU_JIAN:
		return GConst.GE_INVALID_ACTION
	return _古今互鉴()


# ============================================================
# 知行合一 9402：展示 2 张 → ① 选 1 张 + 选目标（当场打出）→ ② 弃 1 张手牌 → 结算剩余
# ============================================================
func _知行合一() -> int:
	if _知行已付 and not 多步询问进行中(ZHI_XING_HE_YI):
		# 本技能的询问已经结束，现在只剩【稽古识典】的收尾在等她答
		return _稽古流程()
	if not _知行已付:
		_知行已付 = true
		_知行展示 = engine.移除牌库顶(2)
		if _知行展示.is_empty():
			return SUCCESS
		engine.展示牌库顶(player.id, _知行展示, true)
		_知行余 = []
		_知行已取消 = false
	# 第 1 步：选哪张展示牌 + 这张牌打谁，答完当场把那张牌打出去（同真言术的「当牌打出」，
	# 客户端点头像即提交）；第 2 步等那张牌结算完再问「弃 1 张手牌」这个代价。
	# 两段的提示条都以「【知行合一】：」开头（约定：步骤提示要点名技能名就用这个格式），
	# 第 2 步的正文优先读技能表「提示2」。
	return 多步询问(ZHI_XING_HE_YI, [
		{"选项": func(_答案: Array) -> Array: return _知行选项(),
		 "需目标": 1,
		 "目标白": 全部角色(),
		 "可取消": true,
		 "取消": _知行取消,
		 "校验": _知行出牌校验,
		 "答完": _知行出牌,
		 "询问文案": _知行提示(0)},
		{"需牌": 1,
		 "牌白": func(_答案: Array) -> Array: return player.hand_cards,
		 "可取消": false,
		 # 「全部化为【史料】」不需要付代价；一张手牌都没有时这一步也跳过
		 "跳过": func(_答案: Array) -> bool: return _知行已取消 or player.hand_cards.is_empty(),
		 "询问文案": _知行提示(1)},
	], _知行结算)


## 知行合一某一步的提示条文案，一律以「【技能名】：」开头（约定：要点名技能名就用这个格式）。
## 序号 0 ＝本技能的「说明」列；序号 1（＝技能表「提示2」）优先读表，表里没配就用规范措辞兜底。
func _知行提示(序号: int) -> String:
	var 名: String = GConst.skill_name(ZHI_XING_HE_YI)
	if 序号 <= 0:
		return "【%s】：%s" % [名, GConst.skill_desc(ZHI_XING_HE_YI)]
	var 表: String = 提示(ZHI_XING_HE_YI, 序号, 1)
	return 表 if not 表.is_empty() else "【%s】：请选择 1 张手牌弃掉" % 名


## 摸牌后那次重入还要接着问「弃 1 张手牌」：让 SkillRun 放行重入技能本体
func 技能URGENT后重入(_action: Dictionary = {}) -> bool:
	return int(_action.get("action_id", 0)) == ZHI_XING_HE_YI and 多步询问进行中(ZHI_XING_HE_YI)


func _知行选项() -> Array:
	var 选项: Array = []
	for i: int in range(_知行展示.size()):
		var cid: int = int(_知行展示[i])
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		选项.append({
			"value": i + 1,
			"label": "%s %s" % [牌.card_name, GConst.element_to_chinese(牌.element_enum())],
			# 悬停直接摊这张牌的卡面（同 7801【剑守誓言】：选项带 card_id，客户端读作「卡牌」）
			"card_id": GConst.牌号(cid),
			# 选哪一档都不改提示条：全程显示【知行合一】的技能说明（同 8006 / 8403 的写法）
			"no_prompt_change": true,
		})
	# 「全部化为【史料】」＝不把任何一张当行动打出，等于取消（展示的牌全弃掉、+X【史料】）。
	# value 0 与展示牌档位（1..n）区分；技能指示器里配「选项目标数 {0:0}」让客户端不再要求目标。
	# 按钮文案优先取技能表「按钮3」；表里没配时按角色表的指示物名兜底（不写死「史料」两个字）。
	var 文案: String = GConst.按钮原文(ZHI_XING_HE_YI, 2)
	if 文案.is_empty():
		文案 = "全部化为【%s】" % str(player.token_def(史料槽).get("name", ""))
	选项.append({"value": 0, "label": 文案, "text": 文案, "no_prompt_change": true})
	return 选项


## 第 1 步的提交校验：档位合法、目标恰好 1 名且这张牌真能对他打出去。
## 不完整 / 打不出去的提交一律驳回重问，别当成「不发动」把两张展示牌都弃了。
func _知行出牌校验(回: Dictionary) -> bool:
	var args: Array = 回.get("args", [])
	if args.is_empty():
		return false
	var 档: int = int(args[0])
	if 档 == 0:
		return true  # 「全部化为【史料】」：不要目标，也不打出任何牌
	if 档 < 1 or 档 > _知行展示.size():
		return false
	var 选中: int = int(_知行展示[档 - 1])
	var 牌: GCard = Data.get_card(选中)
	if 牌 == null:
		return false
	var dsts: Array = 回.get("dsts", [])
	return dsts.size() == 1 and _知行能打(选中, 牌, int(dsts[0]))


## 这张牌此刻能不能对着这名角色主动打出：攻击走 v_attack + v_attacked，
## 法术按卡名逐一走 v_*（与真言术同一套口径）。
## v_* 都要求「牌在手里」，所以这里先把牌临时塞进手牌，查完立刻取回，不留下痕迹。
func _知行能打(选中: int, 牌: GCard, dst: int) -> bool:
	var dp: BattlePlayer = engine.p(dst)
	if dp == null:
		return false
	player.add_hand_cards([选中])
	var 可: bool = false
	if 牌.is_attack():
		可 = player.v_attack(选中, dst, engine.players) == GConst.GE_SUCCESS \
			and dp.v_attacked() == GConst.GE_SUCCESS
	else:
		match 牌.card_name_enum():
			GConst.CardName.Shield:
				可 = player.v_shield(dst, engine.players) == GConst.GE_SUCCESS \
					and engine.v_basic_effect_target(dst, 选中) == GConst.GE_SUCCESS
			GConst.CardName.Weaken:
				可 = player.v_weaken(dst, engine.players) == GConst.GE_SUCCESS
			GConst.CardName.Poison:
				可 = engine.v_basic_effect_target(dst, 选中) == GConst.GE_SUCCESS
			GConst.CardName.Missile:
				可 = player.v_missile(选中, dst) == GConst.GE_SUCCESS
			_:
				# 其余法术牌（只能响应的【圣光】等）不能主动打出
				可 = false
	player.取出一张手牌(选中)
	return 可


## 第 1 步答完：把选中的那张展示牌**当那张牌打出去**（技能出牌，不额外占一次行动）。
## 剩余展示牌留在 `_知行余`，等第 2 步（弃 1 张手牌）后一起结算。
func _知行出牌(回: Dictionary, _答案: Array) -> int:
	var args: Array = 回.get("args", [])
	var 档: int = int(args[0]) if not args.is_empty() else -1
	if 档 == 0:
		# 「全部化为【史料】」：什么都不打出去，等于取消；第 2 步（代价弃牌）也跟着跳过
		_知行化为史料()
		return SUCCESS
	if 档 < 1 or 档 > _知行展示.size():
		return SUCCESS
	var 选中: int = int(_知行展示[档 - 1])
	var 牌: GCard = Data.get_card(选中)
	var dsts: Array = 回.get("dsts", [])
	if 牌 == null or dsts.size() != 1:
		return SUCCESS
	var dst: int = int(dsts[0])
	_知行余 = []
	for c: Variant in _知行展示:
		if int(c) != 选中:
			_知行余.append(int(c))
	_知行展示 = []
	notice_skill(ZHI_XING_HE_YI, [player.id])
	player.add_hand_cards([选中])
	engine.播获得牌日志(player.id, [选中])
	var 种类: int = GConst.ActionType.Attack if 牌.is_attack() else GConst.ActionType.Magic
	var 结果: int = engine.技能出牌(player.id, 种类, [选中], [dst], ZHI_XING_HE_YI)
	if 结果 < 0:
		# 校验放过、真打却被打回（极少）：这张牌回到待弃队列，跟着剩余展示牌一起弃掉，不白拿
		engine.报错("【知行合一】这张牌打不出去", player.id)
		if player.取出一张手牌(选中) >= 0:
			_知行余.append(选中)
		engine._broadcast_game()
		return SUCCESS
	engine._broadcast_game()
	# 打出去的那张牌要先结算完，回来再问第 2 步（弃 1 张手牌）
	return URGENT


## 「全部化为【史料】」/ 点取消：不把任何一张当行动打出，展示的牌全部弃掉、按张数 +【史料】
func _知行化为史料() -> void:
	var 全部: Array = _知行展示.duplicate()
	_知行展示 = []
	_知行余 = []
	_知行已取消 = true
	if not 全部.is_empty():
		engine.to_discard(全部, {"owner": player.id, "source": "deck", "cause": ZHI_XING_HE_YI, "face_up": true})
		player.add_token(史料槽, 全部.size())
	engine._broadcast_game()


## 框架的「取消」回调（点取消 / 超时）：等于「全部化为【史料】」
func _知行取消() -> int:
	_知行化为史料()
	return _稽古流程()


## 结算（第 2 步答完）：先付代价「弃 1 张手牌」，再把剩余展示牌弃掉、你 +X【史料】
func _知行结算(答案: Array) -> int:
	# 「全部化为【史料】」：第 1 步已经把展示牌全换成史料了，这里什么都不做
	if _知行已取消:
		return _稽古流程()
	# 第 2 步可能被跳过（没手牌）：取最后一条答案＝第 2 步
	var 回: Dictionary = 答案[答案.size() - 1] if not 答案.is_empty() else {}
	# 代价：弃 1 张手牌（【强制】；超时 / 空回复按手牌顺序补一张）
	var 弃: int = -1
	for c: Variant in 回.get("cards", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	if 弃 < 0:
		for c0: int in player.hand_cards:
			if player.has_discard_card(c0):
				弃 = c0
				break
	if 弃 >= 0:
		engine.take_from_hand(player.id, [弃])
		engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": ZHI_XING_HE_YI})
		engine._log_discard(player.id, [弃])
	_知行收尾()
	return _稽古流程()


## 打出的那张牌行动结算完成：剩余展示牌弃掉、你 +X【史料】
func _知行收尾() -> void:
	if _知行余.is_empty():
		return
	var 余: Array = _知行余.duplicate()
	_知行余 = []
	engine.to_discard(余, {"owner": player.id, "source": "deck", "cause": ZHI_XING_HE_YI, "face_up": true})
	player.add_token(史料槽, 余.size())
	engine._broadcast_game()


# ============================================================
# 稽古识典 9403：【史料】满 → 移除全部史料、弃 1 张牌、把【史书】加入手牌（强制）
# ============================================================
## 触发点：知行合一 / 古今互鉴 结算之后，以及她自己回合开始 / 结束的兜底。
## 返回 WAIT＝正在等她选弃哪张牌，SUCCESS＝没触发或已结算完。
func _稽古流程() -> int:
	if not 多步询问进行中(JI_GU_SHI_DIAN) and not 多步询问待收尾(JI_GU_SHI_DIAN):
		if player.token_num(史料槽) < player.token_max(史料槽):
			return SUCCESS
		notice_skill(JI_GU_SHI_DIAN, [player.id])
		player.clear_token(史料槽)
		engine._broadcast_game()
	return 多步询问(JI_GU_SHI_DIAN, [
		# 【强制】：一张手牌都没有时整段跳过（结算里直接发史书），有牌就必须弃 1 张
		{"需牌": 1,
		 "牌白": func(_答案: Array) -> Array: return player.hand_cards,
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool: return player.hand_cards.is_empty()},
	], _稽古结算)


func _稽古结算(答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var 弃: int = -1
	for c: Variant in 回.get("cards", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	if 弃 < 0:
		for c0: int in player.hand_cards:
			if player.has_discard_card(c0):
				弃 = c0
				break
	if 弃 >= 0:
		engine.take_from_hand(player.id, [弃])
		engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": JI_GU_SHI_DIAN})
		engine._log_discard(player.id, [弃])
	_发史书()
	return SUCCESS


func _发史书() -> void:
	# 史书是唯一实例（卡表#1007，不在牌库）：已经有一张就不再发第二份，避免同实例号重复进手牌
	if player.has_discard_card(史书号):
		engine._broadcast_game()
		return
	# 它可能被【以史为镜】移出游戏，也可能（极少数）绕过拦截落在弃牌堆里：
	# 先按唯一实例从「移除牌堆 / 弃牌堆 / 牌库」里取出来，再进手牌，避免同一实例出现在两处
	engine.从移除牌堆取出(史书号)
	engine.deck.取出实例(史书号)
	player.add_hand_cards([史书号])
	engine.播获得牌日志(player.id, [史书号])
	engine._broadcast_game()


# ============================================================
# 秘境万象 9406：移除史书 + 所有遗迹 → 逐张翻到同系第 2 张 → 都作为遗迹 → 可能群伤
# ============================================================
func _秘境万象() -> int:
	if not 多步询问进行中(MI_JING_WAN_XIANG):
		notice_skill(MI_JING_WAN_XIANG, [player.id])
		_移除史书()
		var 旧: Array = player.cover_cards.duplicate()
		if not 旧.is_empty():
			engine.remove_cover(player.id, 旧, player.id, MI_JING_WAN_XIANG)
			engine.to_discard(旧, {"owner": player.id, "source": "cover", "cause": MI_JING_WAN_XIANG, "face_up": true})
		var 展示: Array = _翻到同系()
		if not 展示.is_empty():
			engine.展示牌库顶(player.id, 展示)
			engine.add_cover(player.id, 展示, player.id, MI_JING_WAN_XIANG, true)
		engine._broadcast_game()
		if 展示.size() <= 3:
			return SUCCESS
	# 「对（X-3）名目标角色造成 2 点法术伤害」：X 就是现在面前的【遗迹】数
	var 需要: int = mini(_秘境目标数(), engine.order.size())
	if 需要 <= 0:
		return SUCCESS
	return 多步询问(MI_JING_WAN_XIANG, [
		{"需目标": 需要,
		 "目标白": 全部角色(),
		 "可取消": false,
		 "预览基准": 2, "预览类型": GConst.HarmType.Magic,
		 "校验": _秘境校验,
		 # 这一问的提示条：写明要选几名、打多少（X 随翻出来的张数变，静态提示列写不出来）
		 "询问文案": "【%s】：选择 %d 名目标，造成 2 点法术伤害" % [
			GConst.skill_name(MI_JING_WAN_XIANG), 需要]},
	], _秘境结算)


## 这次要打几个人：X-3（X＝展示出来摆成遗迹的张数）
func _秘境目标数() -> int:
	return maxi(_遗迹数() - 3, 0)


func _秘境校验(回: Dictionary) -> bool:
	var dsts: Array = 回.get("dsts", [])
	if dsts.size() != mini(_秘境目标数(), engine.order.size()):
		return false
	var 已: Array = []
	for d: Variant in dsts:
		var pid: int = int(d)
		if not 全部角色().has(pid) or 已.has(pid):
			return false
		已.append(pid)
	return true


func _秘境结算(答案: Array) -> int:
	var 需要: int = mini(_秘境目标数(), engine.order.size())
	if 需要 <= 0:
		return SUCCESS
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var 目标们: Array = _取目标(回.get("dsts", []), 全部角色(), 需要)
	# 超时 / 少选：按座位顺序补齐 —— 强制伤害不能因为没点人就丢掉
	if 目标们.size() < 需要:
		for pid: int in 全部角色():
			if not 目标们.has(pid):
				目标们.append(pid)
			if 目标们.size() >= 需要:
				break
	for d: Variant in 目标们:
		engine.push_harm({"src": player.id, "dst": int(d), "point": 2,
			"cause": MI_JING_WAN_XIANG, "type": GConst.HarmType.Magic})
	engine._broadcast_game()
	return URGENT


## 「展示牌库顶牌直至展示牌中有同系牌为止」：一直翻，翻到出现第二张同系牌（这张也算）为止
func _翻到同系() -> Array:
	var 展示: Array = []
	var 已见: Array = []
	while engine.deck.pile_size() > 0:
		var 一张: Array[int] = engine.移除牌库顶(1)
		if 一张.is_empty():
			break
		var cid: int = int(一张[0])
		展示.append(cid)
		var 牌: GCard = Data.get_card(cid)
		var 系: int = 牌.element_enum() if 牌 != null else -1
		if 已见.has(系):
			break
		已见.append(系)
	return 展示


# ============================================================
# 古今互鉴 9408（启动·必杀）：+2【史料】；（手牌>1）2 张手牌与 X 个【遗迹】交换
# ============================================================
func _古今互鉴() -> int:
	if _古今已付 and not 多步询问进行中(GU_JIN_HU_JIAN):
		# 交换问完（或本来就不用问），现在只剩【稽古识典】的收尾
		return _稽古流程()
	if not _古今已付:
		_古今已付 = true
		notice_skill(GU_JIN_HU_JIAN, [player.id])
		player.boot_skill_used = true
		player.remove_energy(1)
		player.add_token(史料槽, 2)
		engine._broadcast_game()
		# 交换是可选的：换不了（手牌不足 2 张 / 没有【遗迹】）就只剩 +2【史料】
		if player.hand_cards.size() < 2 or _遗迹数() <= 0:
			return _稽古流程()
	return 多步询问(GU_JIN_HU_JIAN, [
		{"选项": func(_答案: Array) -> Array: return _交换选项(GU_JIN_HU_JIAN, 2),
		 "来源": GConst.CardSource.HandOrCover,
		 "可取消": true,
		 "取消": _古今跳过交换,
		 "校验": func(回: Dictionary) -> bool: return _交换校验(回, 2, false)},
	], _古今结算)


## 不换（点取消 / 超时）：交换整段不做，但要照常走【稽古识典】的收尾
## （取消时框架不会调结算回调，+2【史料】可能刚好顶满，不收尾就会漏掉一次稽古）
func _古今跳过交换() -> int:
	return _稽古流程()


func _古今结算(答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var args: Array = 回.get("args", [])
	if not args.is_empty():
		_交换遗迹(int(args[0]), 回.get("cards", []), GU_JIN_HU_JIAN, 2)
	return _稽古流程()


# ============================================================
# 引稽编鉴 9409：【史书】主动攻击① → 目标交 1 张手牌进【遗迹】 → 你交换 → 再做遗迹论破
# ============================================================
func _引稽编鉴(ctx: Dictionary) -> int:
	if _引稽已完结 or (_引稽已问 and not 多步询问进行中(YIN_JI_BIAN_JIAN)):
		return _遗迹论破(ctx)
	_引稽已问 = true
	return 多步询问(YIN_JI_BIAN_JIAN, [
		# 「指定攻击目标将 1 张手牌加入【遗迹】」：强制；他一张手牌都没有就跳过
		{"问谁": func(_答案: Array) -> int: return int(ctx.get("dst", -1)),
		 "需牌": 1,
		 "牌白": func(_答案: Array) -> Array:
			var dp: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
			return dp.hand_cards if dp != null else [],
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool:
			var dp: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
			return dp == null or dp.hand_cards.is_empty(),
		 "答完": _引稽收牌.bind(ctx)},
		# 「然后将你手上 X 张牌与 X 个【遗迹】交换，X<3」：可选
		{"选项": func(_答案: Array) -> Array:
			return _交换选项(YIN_JI_BIAN_JIAN, 0, _交换上限(), true),
		 "来源": GConst.CardSource.HandOrCover,
		 "可取消": true,
		 "取消": _引稽跳过交换.bind(ctx),
		 "跳过": func(_答案: Array) -> bool: return _交换上限() <= 0,
		 "校验": func(回: Dictionary) -> bool: return _交换校验(回, 0, true)},
	], _引稽结算.bind(ctx))


## 目标交牌那一段答完：他选的那张面朝上摆进【遗迹】（展示归属＝交牌的人）
func _引稽收牌(回: Dictionary, _答案: Array, ctx: Dictionary) -> int:
	var dp: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dp == null:
		return SUCCESS
	var 入: int = -1
	for c: Variant in 回.get("cards", []):
		if dp.has_discard_card(int(c)):
			入 = int(c)
			break
	if 入 < 0:
		for c0: int in dp.hand_cards:
			if dp.has_discard_card(c0):
				入 = c0
				break
	if 入 < 0:
		return SUCCESS
	engine.展示手牌(dp.id, [入])
	engine.take_from_hand(dp.id, [入])
	engine.add_cover(player.id, [入], player.id, YIN_JI_BIAN_JIAN, true)
	engine._broadcast_game()
	return SUCCESS


func _引稽结算(答案: Array, ctx: Dictionary) -> int:
	_引稽已完结 = true
	# 被跳过的段不占答案槽位：交换那一段是最后答的，取最后一条
	var 回: Dictionary = 答案[答案.size() - 1] if not 答案.is_empty() else {}
	var args: Array = 回.get("args", [])
	if not args.is_empty():
		_交换遗迹(int(args[0]), 回.get("cards", []), YIN_JI_BIAN_JIAN, int(args[0]))
	return _遗迹论破(ctx)


## 换那一问被取消 / 超时：框架不会调结算回调，这里补上「引稽已经完结」并接着走遗迹论破，
## 否则这一次攻击的遗迹论破会被整段吞掉（`_引稽已问` 已经置位，不会再问第二次）
func _引稽跳过交换(ctx: Dictionary) -> int:
	_引稽已完结 = true
	return _遗迹论破(ctx)


## 引稽编鉴这次最多能换几张：手牌数 / 【遗迹】数 / 2 三者取小
func _交换上限() -> int:
	return mini(mini(交换上限, player.hand_cards.size()), _遗迹数())


# ============================================================
# 遗迹论破 9404：主动攻击① 移除同系遗迹加伤（回合限定）
# ============================================================
func _遗迹论破(ctx: Dictionary) -> int:
	if _遗迹论破已用 or (_遗迹论破已问 and not 多步询问进行中(YI_JI_LUN_PO)):
		return SUCCESS
	var 牌: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 牌 == null:
		return SUCCESS
	var 同系: Array = _同系遗迹(牌.element_enum())
	if not 多步询问进行中(YI_JI_LUN_PO):
		if 同系.is_empty():
			return SUCCESS
		_遗迹论破已问 = true
	# 头像提示（同狂战士【撕裂】那一套）：点亮这次攻击的目标，并按「当前攻击伤害」画
	# 「原值划掉 → 新值」——加伤＝移除张数-1，客户端按已选张数现算（preview_rule card,-1）。
	var harm: Dictionary = ctx.get("harm", {})
	var 基准: int = int(harm.get("point", 0))
	var 目标: int = int(ctx.get("dst", -1))
	return 多步询问(YI_JI_LUN_PO, [
		# 不给选项：直接把盖牌区亮出来，同系遗迹（光/暗也算，见 9405 选淬精炼）可点、
		# 其余置灰，玩家自己点要移除的几个，按「确定」提交（点「取消」＝不发动）。
		{"来源": GConst.CardSource.Cover,
		 "需牌": 1,
		 "牌上限": 同系.size(),
		 "牌白": 同系,
		 "可取消": true,
		 "校验": _遗迹论破选牌校验.bind(同系),
		 "预览基准": 基准,
		 "预览类型": GConst.HarmType.Attack,
		 "预览目标": [目标] if 目标 >= 0 else [],
		 "高亮": [目标] if 目标 >= 0 else [],
		 "伤害规则": "card,-1"},
	], _遗迹论破结算.bind(ctx))


## 提交校验：至少 1 张、全是自己面前同系的【遗迹】（光/暗也算）、不重复
func _遗迹论破选牌校验(回: Dictionary, 同系: Array) -> bool:
	var 取: Array = 回.get("cards", [])
	if 取.is_empty() or 取.size() > 同系.size():
		return false
	var 已: Array = []
	for c: Variant in 取:
		var 盖实例: int = player.盖牌实例(int(c))
		if 盖实例 < 0 or not 同系.has(盖实例) or 已.has(盖实例):
			return false
		已.append(盖实例)
	return true


func _遗迹论破结算(答案: Array, ctx: Dictionary) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	# 回来时重新算一次同系遗迹：询问期间盖牌可能变过（如【引稽编鉴】刚加了 1 张）
	var 牌: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 牌 == null:
		return SUCCESS
	var 同系: Array = _同系遗迹(牌.element_enum())
	# 玩家点的就是实际要移除的那几张（客户端已按白名单置灰，这里再复核一遍）
	var 取: Array = []
	for c: Variant in 回.get("cards", []):
		var 盖实例: int = player.盖牌实例(int(c))
		if 盖实例 >= 0 and 同系.has(盖实例) and not 取.has(盖实例):
			取.append(盖实例)
	if 取.is_empty():
		return SUCCESS
	var X: int = 取.size()
	_遗迹论破已用 = true
	notice_skill(YI_JI_LUN_PO, [player.id])
	# 移除的里面有光/暗遗迹＝这次是拿【选淬精炼】的「光暗视为任意系别」当同系用的：补一条发动播报
	for c: Variant in 取:
		var 牌面: GCard = Data.get_card(int(c))
		if 牌面 == null:
			continue
		var 牌系: int = 牌面.element_enum()
		if 牌系 == GConst.CardElement.Light or 牌系 == GConst.CardElement.Darkness:
			notice_skill(XUAN_CUI_JING_LIAN, [player.id])
			break
	engine.remove_cover(player.id, 取, player.id, YI_JI_LUN_PO)
	engine.to_discard(取, {"owner": player.id, "source": "cover", "cause": YI_JI_LUN_PO})
	var harm: Dictionary = ctx.get("harm", {})
	加伤害(harm, X - 1)
	if X > 1:
		# 「额外 +1【法术行动】」：直接进入那份额外行动（不想要就在额外行动阶段放弃）
		player.add_action(GConst.ActionType.Magic, YI_JI_LUN_PO, true)
	if _遗迹数() == 0:
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 时机钩子
# ============================================================
## 每次主动攻击开始：复位「本次攻击问过」的标记
func p_before_attack(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id and bool(ctx.get("is_active", false)):
		_引稽已问 = false
		_引稽已完结 = false
		_遗迹论破已问 = false
	return SUCCESS


func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 用【史书】主动攻击：先引稽编鉴，再遗迹论破（两件事可以同时发）
	if GConst.牌号(int(ctx.get("card_id", -1))) == 史书号:
		return _引稽编鉴(ctx)
	return _遗迹论破(ctx)


func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_遗迹论破已用 = false
	# 上一次的【稽古识典】没结算完（被打断 / 跨回合）时在这里补
	return _稽古流程()


func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 知行合一打出的那张牌的「行动结束」只是它自己的事：剩余展示牌与代价弃牌由本技能链的
	# 第 2 步 + 结算负责（见 _知行合一 / _知行结算），这里不插手
	return _稽古流程()


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 链没走完就回合结束了（中途被打断）：剩余展示牌照常结算，别把它们留在半空
	if not _知行余.is_empty():
		_知行收尾()
	return _稽古流程()


# ============================================================
# 以史为镜 9407：【史书】被使用 / 打出 / 弃置 / 转移拥有者 / 因技能放置在角色旁 → 移除此卡
# ============================================================
func wants_before_discard(ctx: Dictionary) -> bool:
	for c: Variant in ctx.get("cards", []):
		if GConst.牌号(int(c)) == 史书号:
			return true
	return false


func p_before_discard(ctx: Dictionary) -> int:
	var 移: Array = []
	for c: Variant in ctx.get("cards", []):
		if GConst.牌号(int(c)) == 史书号 and not 移.has(int(c)):
			移.append(int(c))
	if 移.is_empty():
		return SUCCESS
	ctx["removed"] = 移
	notice_skill(YI_SHI_WEI_JING, [player.id])
	return SUCCESS


## 「因技能放置在角色旁」：史书被当成基础效果贴到某人面前 → 移除这张基础效果并移出游戏
func p_basic_effect_change(ctx: Dictionary) -> int:
	if not bool(ctx.get("add", false)):
		return SUCCESS
	var 场上牌: int = int(ctx.get("card", -1))
	if GConst.牌号(场上牌) != 史书号:
		return SUCCESS
	var dst: int = int(ctx.get("dst", -1))
	notice_skill(YI_SHI_WEI_JING, [dst])
	engine.remove_basic_effect(dst, 场上牌, YI_SHI_WEI_JING, player.id)
	engine.放入移除牌堆(场上牌)
	return SUCCESS


## 同理：史书被放进盖牌区 / 遗迹区 → 拿走并移出游戏
func p_cover_change(ctx: Dictionary) -> int:
	if int(ctx.get("direction", 0)) != GConst.CHANGE_ADD:
		return SUCCESS
	var 移: Array = []
	for c: Variant in ctx.get("cards", []):
		if GConst.牌号(int(c)) == 史书号 and not 移.has(int(c)):
			移.append(int(c))
	if 移.is_empty():
		return SUCCESS
	var dst: int = int(ctx.get("dst", -1))
	notice_skill(YI_SHI_WEI_JING, [dst])
	engine.remove_cover(dst, 移, player.id, YI_SHI_WEI_JING)
	for c2: Variant in 移:
		engine.放入移除牌堆(int(c2))
	return SUCCESS


## 「转移拥有者」：史书进了别人的手牌 → 移出游戏（它只属于记录者）
func p_hand_change(ctx: Dictionary) -> int:
	var 谁: int = int(ctx.get("player", -1))
	if 谁 < 0 or 谁 == player.id:
		return SUCCESS
	var 他: BattlePlayer = engine.p(谁)
	if 他 == null or not 他.has_hand_card(史书号):
		return SUCCESS
	var 实例: int = 他.取出一张手牌(史书号)
	if 实例 < 0:
		return SUCCESS
	notice_skill(YI_SHI_WEI_JING, [谁])
	engine.放入移除牌堆(实例)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _遗迹数() -> int:
	return player.cover_cards.size()


## 与给定系别同系的【遗迹】：光系 / 暗系遗迹视为任意系别（9405 选淬精炼）。
## 顺序＝**先本系、再光/暗**：移除时先吃本系的，多余的档位才会用到光/暗，
## 选项上色 / 悬停说明按「第几个开始动用光暗」来判，所以顺序固定在这里，别处不要再排。
func _遗迹分系(系: int) -> Dictionary:
	var 本系: Array = []
	var 灵活: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		var 牌系: int = 牌.element_enum()
		if 牌系 == 系:
			本系.append(cid)
		elif 牌系 == GConst.CardElement.Light or 牌系 == GConst.CardElement.Darkness:
			灵活.append(cid)
	return {"本系": 本系, "灵活": 灵活}


## 与给定系别同系的【遗迹】清单（本系在前、光暗在后）
func _同系遗迹(系: int) -> Array:
	var 分: Dictionary = _遗迹分系(系)
	return (分["本系"] as Array) + (分["灵活"] as Array)


func _史书在手() -> bool:
	return player.has_discard_card(史书号)


func _移除史书() -> void:
	if not player.has_discard_card(史书号):
		return
	engine.take_from_hand(player.id, [史书号])
	engine.放入移除牌堆(史书号)


## 交换选项：value＝换几张；每档自带「手牌几张 + 盖牌几张」的混选要求
func _交换选项(技能号: int, 手牌数: int, 上限: int = 0, 手牌随档: bool = false) -> Array:
	var 可换: int = mini(交换上限, _遗迹数())
	if 上限 > 0:
		可换 = mini(可换, 上限)
	var 选项: Array = []
	for x: int in range(1, 交换上限 + 1):
		var 手: int = x if 手牌随档 else 手牌数
		# 按钮文案优先读技能表「提示」列；9409 那张表还没配，兜一句同口径的说明，
		# 否则选项会是空白按钮（表补了就直接用表里的）
		var 文案: String = GConst.按钮原文(技能号, x - 1)
		if 文案.is_empty():
			文案 = "换 %d 张手牌 + %d 个【遗迹】" % [手, x] if 手牌随档 else "与 %d 个【遗迹】交换" % x
		选项.append({
			"value": x,
			"label": 文案,
			"text": 文案,
			"enabled": x <= 可换 and 手 <= player.hand_cards.size(),
			# 手牌 + 盖牌混选：这一档要「手牌 手 张 + 盖牌 X 张」（客户端据此卡选牌数）
			"need_card": 手 + x,
			"hand_need": 手,
			"cover_need": x,
		})
	return 选项


## 交换提交的合法性：X 在 1~上限；手牌正好 手数、盖牌正好 X，且都在本区
func _交换校验(回: Dictionary, 需要手: int, 随档: bool) -> bool:
	var args: Array = 回.get("args", [])
	if args.is_empty():
		return false
	var X: int = int(args[0])
	if X < 1 or X > mini(交换上限, _遗迹数()):
		return false
	var 手数: int = X if 随档 else 需要手
	if 手数 > player.hand_cards.size():
		return false
	var 手: Array = []
	var 盖: Array = []
	for c: Variant in 回.get("cards", []):
		var 手实例: int = player.手牌实例(int(c))
		if 手实例 >= 0:
			if not 手.has(手实例):
				手.append(手实例)
			continue
		var 盖实例: int = player.盖牌实例(int(c))
		if 盖实例 >= 0 and not 盖.has(盖实例):
			盖.append(盖实例)
	return 手.size() == 手数 and 盖.size() == X


## 【遗迹】交换：把 X 张手牌放进【遗迹】区、取回 X 个【遗迹】；手牌那几张面朝上亮出来
func _交换遗迹(X: int, 给牌: Array, cause: int, 需要手牌数: int) -> void:
	if X <= 0 or X > _遗迹数():
		return
	var 手: Array = []
	var 盖: Array = []
	for c: Variant in 给牌:
		var 手实例: int = player.手牌实例(int(c))
		if 手实例 >= 0:
			if not 手.has(手实例):
				手.append(手实例)
			continue
		var 盖实例: int = player.盖牌实例(int(c))
		if 盖实例 >= 0 and not 盖.has(盖实例):
			盖.append(盖实例)
	if 手.size() != 需要手牌数 or 盖.size() != X:
		engine.报错("【遗迹】交换提交的牌不对", player.id)
		return
	engine.remove_cover(player.id, 盖, player.id, cause)
	player.add_hand_cards(盖)
	engine.播获得牌日志(player.id, 盖)
	engine.take_from_hand(player.id, 手)
	engine.add_cover(player.id, 手, player.id, cause, true)
	# 交出去的这几张手牌是面朝上摆在【遗迹】区的：统一入口（亮牌 + 触发封印）
	engine.展示手牌(player.id, 手)
	engine._broadcast_game()


## 从回复里取出合法、去重、最多 上限 名的目标（不替玩家改选：不足就按实有数量结算）
func _取目标(回复目标: Array, 合法: Array, 上限: int) -> Array:
	var out: Array = []
	for d: Variant in 回复目标:
		var pid: int = int(d)
		if 合法.has(pid) and not out.has(pid):
			out.append(pid)
		if out.size() >= 上限:
			break
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

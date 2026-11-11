extends BattleRole
## 记录者（roleID 94）
##
## 【遗迹】＝角色旁面朝上的牌（盖牌区 open=true，上限读角色表盖牌槽：8）；
## 【史料】＝0 号指示物（上限 3）；【史书】＝卡表#1007（地系·幻类命格攻击牌，用掉 / 弃掉就移出游戏）。
##
## 技能：
##   传说之地 9401（被动）：开局把牌库顶 3 张面朝上放在角色旁作为【遗迹】。
##   知行合一 9402（法术）：展示牌库顶 2 张，你选其中 1 张并弃 1 张手牌；选中的牌加入手牌并获得
##       一次「只能用这张牌」的立刻行动；该行动结算完成后，把剩余展示牌弃掉、你 +X【史料】。
##   稽古识典 9403（被动）：【史料】达到上限时，移除所有【史料】，你弃 1 张牌，
##       将【史书】加入手牌【强制】。
##   遗迹论破 9404（响应【回合限定】）：主动攻击①，移除与攻击牌同系的 X 个【遗迹】→
##       本次攻击伤害 +（X-1）；（若 X>1）额外+1【法术行动】；（若遗迹因此为 0）我方【战绩区】+1【宝石】。
##   选淬精炼 9405（被动）：光系与暗系的【遗迹】视为任意系别（见 _同系遗迹）。
##   秘境万象 9406（法术）：移除【史书】与所有【遗迹】，逐张展示牌库顶直到出现同系的第 2 张；
##       展示的 X 张都作为【遗迹】；（若 X>3）对（X-3）名目标角色各 2 点法术伤害③。
##   以史为镜 9407（被动）：【史书】视为地系幻类命格攻击牌；被使用 / 弃置时移出游戏（弃牌拦截）。
##   古今互鉴 9408（启动·必杀【水晶】）：你 +2【史料】；（若手牌 >1）可将 2 张手牌与 X 个【遗迹】交换，X>0。
##   引稽编鉴 9409（响应）：使用【史书】主动攻击①，指定攻击目标将 1 张手牌加入【遗迹】，
##       然后将你手上 X 张牌与 X 个【遗迹】交换，X<3。
##
## 参考实现：9801【幽行】/10803【剑守誓言】的牌库顶展示与「选 1 张入手」、矜贵之女 7802 的多步询问、
## 剑圣 104【圣剑】的「行动结束后弃 N 张」。

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

## 知行合一：0＝未开始 / 1＝等选展示牌 + 弃 1 张手牌
var _知行阶段: int = 0
## 本次展示的牌（还没结算的：选中前是全部，选中后是剩余）
var _知行展示: Array = []
var _知行余: Array = []
## 选中的那张（还在手里时，回合结束要按技能口径弃掉，避免白拿一张）
var _知行待打: int = -1
var _知行已结算: bool = false

## 秘境万象：0＝未开始 / 1＝等选伤害目标
var _秘境阶段: int = 0
var _秘境目标数: int = 0

## 古今互鉴：0＝未开始 / 1＝等选要交换的手牌
var _古今阶段: int = 0

## 引稽编鉴：0＝未开始 / 1＝等攻击目标交牌 / 2＝等自己选交换的手牌
var _引稽阶段: int = 0
var _引稽目标: int = -1
## 本次攻击的引稽编鉴已处理完（同一张【史书】再进 p_timeline_1 时不再重复问）
var _引稽已完结: bool = false

## 遗迹论破：0＝未开始 / 1＝等选移除几个遗迹；本回合已用
var _遗迹论破阶段: int = 0
var _遗迹论破已用: bool = false

## 稽古识典：史料已清空、正等「弃 1 张牌」
var _稽古待弃: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【传说之地】：牌库顶 3 张面朝上作为【遗迹】
	var cards: Array[int] = engine.移除牌库顶(3)
	if cards.is_empty():
		return
	engine.展示牌库顶(player.id, cards)
	engine.add_cover(player.id, cards, player.id, CHUAN_SHUO_ZHI_DI, true)


# ============================================================
# 技能栏
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


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != GU_JIN_HU_JIAN:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	# 新的一次发动：清掉上一次的分步（v_* 只在技能开始时调一次，等回复重入不会再进来）
	_古今阶段 = 0
	return GConst.GE_SUCCESS


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == ZHI_XING_HE_YI:
		if engine.deck.pile_size() <= 0 or player.hand_cards.is_empty():
			return GConst.GE_INVALID_ACTION
		_知行阶段 = 0
		_知行已结算 = false
		_知行余 = []
		_知行待打 = -1
		return GConst.GE_SUCCESS
	if 技能号 == MI_JING_WAN_XIANG:
		if not _史书在手():
			return GConst.GE_INVALID_ACTION
		_秘境阶段 = 0
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	# 上一次收尾还停在【稽古识典】的「弃 1 张牌」上：先把它结算完
	if _稽古待弃:
		return _稽古推进()
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == ZHI_XING_HE_YI:
		return _知行合一()
	if 技能号 == MI_JING_WAN_XIANG:
		return _秘境万象()
	return EMPTY_HANDLE


# ============================================================
# 知行合一 9402：展示 2 张 → 同一步选 1 张 + 弃 1 张手牌 → 立刻行动 → 结算剩余
# ============================================================
func _知行合一() -> int:
	if _知行阶段 == 3:
		# 已经选过牌、只等【稽古识典】收尾
		return _稽古推进()
	if _知行阶段 == 0:
		_知行展示 = engine.移除牌库顶(2)
		if _知行展示.is_empty():
			return SUCCESS
		engine.展示牌库顶(player.id, _知行展示, true)
		_知行阶段 = 1
		询问(player.id, ZHI_XING_HE_YI, 1, 0, GConst.CardSource.Hand, _知行选项(), 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_知行阶段 = 3
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	if args.is_empty():
		# 取消 = 不把展示牌作为行动发出：全部展示牌弃掉、按张数 +【史料】
		_知行余 = _知行展示.duplicate()
		_知行展示 = []
		_知行结算()
		_稽古检查()
		return _稽古推进()
	var 档: int = int(args[0])
	if 档 < 1 or 档 > _知行展示.size():
		engine.报错("【知行合一】选项号越界", player.id)
		_知行余 = _知行展示.duplicate()
		_知行展示 = []
		_知行结算()
		_稽古检查()
		return _稽古推进()
	var 选中: int = int(_知行展示[档 - 1])
	var 牌: GCard = Data.get_card(选中)
	if 牌 == null:
		engine.报错("【知行合一】选中的牌不存在", player.id)
		_知行余 = _知行展示.duplicate()
		_知行展示 = []
		_知行结算()
		_稽古检查()
		return _稽古推进()
	# 弃 1 张手牌（代价；超时 / 空回复按手牌顺序补一张，不能白发动）
	var 弃: int = -1
	for c: Variant in cards:
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	if 弃 < 0 and not player.hand_cards.is_empty():
		弃 = int(player.hand_cards[0])
	for c0: Variant in _知行展示:
		if int(c0) != 选中:
			_知行余.append(int(c0))
	_知行展示 = []
	notice_skill(ZHI_XING_HE_YI, [player.id])
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": ZHI_XING_HE_YI})
	engine._log_discard(player.id, [弃])
	# 选中的牌加入手牌，再给一份「只能用这张牌」的立刻行动（同 7803 / 9303 的做法）
	player.add_hand_cards([选中])
	engine.播获得牌日志(player.id, [选中])
	_知行待打 = 选中
	_知行已结算 = false
	var 种类: int = GConst.ActionType.Attack if 牌.is_attack() else GConst.ActionType.Magic
	player.add_action(种类, ZHI_XING_HE_YI, true, false, {"cards": [GConst.牌号(选中)]})
	engine._broadcast_game()
	return SUCCESS


func _知行选项() -> Array:
	var 选项: Array = []
	for i: int in range(_知行展示.size()):
		var cid: int = int(_知行展示[i])
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		var 文案: String = "%s %s" % [牌.card_name, GConst.element_to_chinese(牌.element_enum())]
		选项.append({"value": i + 1, "label": 文案})
	return 选项


## 把「剩余展示牌」弃掉并 +X【史料】
func _知行结算() -> void:
	_知行待打 = -1
	if not _知行余.is_empty():
		engine.to_discard(_知行余, {"owner": player.id, "source": "deck", "cause": ZHI_XING_HE_YI, "face_up": true})
		player.add_token(史料槽, _知行余.size())
		_知行余 = []
	engine._broadcast_game()


# ============================================================
# 稽古识典 9403：【史料】满 → 移除全部史料、弃 1 张、把【史书】加入手牌
# ============================================================
func _稽古检查() -> void:
	if player.token_num(史料槽) < player.token_max(史料槽):
		return
	notice_skill(JI_GU_SHI_DIAN, [player.id])
	player.clear_token(史料槽)
	_稽古待弃 = true
	engine._broadcast_game()


## 推进「弃 1 张牌」这一步；返回 WAIT（等回复）/ SUCCESS（完成）
func _稽古推进() -> int:
	if not _稽古待弃:
		return SUCCESS
	if player.hand_cards.is_empty():
		_稽古待弃 = false
		_发史书()
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, JI_GU_SHI_DIAN, 1, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_稽古待弃 = false
	var 弃: int = -1
	for c: Variant in r.get("card_ids", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	if 弃 < 0:
		# 「弃 1 张牌」是强制项：超时 / 空回复按手牌顺序补一张
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
	# 之前被【以史为镜】移出游戏的史书：先从移除牌堆取回来，再加回手牌（约定 13）
	engine.从移除牌堆取出(史书号)
	player.add_hand_cards([史书号])
	engine.播获得牌日志(player.id, [史书号])
	engine._broadcast_game()


# ============================================================
# 秘境万象 9406：移除史书 + 所有遗迹 → 逐张翻到同系第 2 张 → 都作为遗迹 → 可能群伤
# ============================================================
func _秘境万象() -> int:
	if _秘境阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		_秘境阶段 = 0
		var dsts: Array = _取目标(r.get("dst_ids", []), 全部角色(), _秘境目标数)
		if dsts.size() < _秘境目标数:
			engine.报错("【秘境万象】目标数不对", player.id)
		for d: Variant in dsts:
			engine.push_harm({"src": player.id, "dst": int(d), "point": 2,
				"cause": MI_JING_WAN_XIANG, "type": GConst.HarmType.Magic})
		engine._broadcast_game()
		return URGENT if not dsts.is_empty() else SUCCESS
	notice_skill(MI_JING_WAN_XIANG, [player.id])
	_移除史书()
	var 旧: Array = player.cover_cards.duplicate()
	if not 旧.is_empty():
		engine.remove_cover(player.id, 旧, player.id, MI_JING_WAN_XIANG)
		engine.to_discard(旧, {"owner": player.id, "source": "cover", "cause": MI_JING_WAN_XIANG, "face_up": true})
		engine._log_discard(player.id, 旧, false)
	var 展示: Array = []
	var 已见: Array = []
	while engine.deck.pile_size() > 0:
		var 一张: Array[int] = engine.移除牌库顶(1)
		if 一张.is_empty():
			break
		var cid: int = int(一张[0])
		展示.append(cid)
		var 牌: GCard = Data.get_card(cid)
		var 系: int = 牌.element_enum() if 牌 != null else 0
		if 已见.has(系):
			break
		已见.append(系)
	if 展示.is_empty():
		return SUCCESS
	engine.展示牌库顶(player.id, 展示)
	engine.add_cover(player.id, 展示, player.id, MI_JING_WAN_XIANG, true)
	var X: int = 展示.size()
	if X > 3:
		# 「对（X-3）名目标角色」：目标多于在场人数时按 min 取（约定 23）
		_秘境目标数 = mini(X - 3, engine.order.size())
		_秘境阶段 = 1
		询问(player.id, MI_JING_WAN_XIANG, 0, _秘境目标数, GConst.CardSource.Hand, [], 0, "", [], false,
			0, -1, 全部角色(), -1, {}, 2, GConst.HarmType.Magic)
		return WAIT
	return SUCCESS


# ============================================================
# 古今互鉴 9408（启动·必杀）
# ============================================================
func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != GU_JIN_HU_JIAN:
		return GConst.GE_INVALID_ACTION
	if _稽古待弃:
		return _稽古推进()
	if _古今阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		_古今阶段 = 3
		_古今交换(r)
		_稽古检查()
		return _稽古推进()
	if _古今阶段 == 3:
		return _稽古推进()
	_古今阶段 = 3
	player.boot_skill_used = true
	notice_skill(GU_JIN_HU_JIAN, [player.id])
	player.remove_energy(1)
	player.add_token(史料槽, 2)
	engine._broadcast_game()
	# 先问交换、再做【稽古识典】：稽古要等玩家选弃哪张牌，放在最后收尾
	if player.hand_cards.size() >= 2 and _遗迹数() > 0:
		_古今阶段 = 1
		询问(player.id, GU_JIN_HU_JIAN, 0, 0, GConst.CardSource.HandOrCover,
			_交换选项(GU_JIN_HU_JIAN, 交换上限), 0, "", [], true, 0, -1, [], -1, {})
		return WAIT
	_稽古检查()
	return _稽古推进()


func _古今交换(r: Dictionary) -> void:
	var args: Array = r.get("args", [])
	if args.is_empty():
		return
	var X: int = int(args[0])
	if X < 1 or X > mini(交换上限, _遗迹数()):
		engine.报错("【古今互鉴】交换参数不对", player.id)
		return
	_交换遗迹(X, r.get("card_ids", []), GU_JIN_HU_JIAN, 交换上限)


# ============================================================
# 引稽编鉴 9409：用【史书】主动攻击① → 攻击目标交 1 张手牌作【遗迹】 → 交换
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if GConst.牌号(int(ctx.get("card_id", -1))) == 史书号 and not _引稽已完结:
		return _引稽编鉴(ctx)
	return _遗迹论破(ctx)


## 每次攻击开始时复位「本次攻击已经问过」的标记
func p_before_attack(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id and bool(ctx.get("is_active", false)):
		_引稽已完结 = false
		_遗迹论破阶段 = 0
	return SUCCESS


func _引稽编鉴(ctx: Dictionary) -> int:
	if _引稽阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		_引稽阶段 = 0
		var dp: BattlePlayer = engine.p(_引稽目标)
		_引稽目标 = -1
		if dp == null:
			_引稽已完结 = true
			return _遗迹论破(ctx)
		var 入: int = -1
		for c: Variant in r.get("card_ids", []):
			if dp.has_discard_card(int(c)):
				入 = int(c)
				break
		if 入 < 0:
			# 「将 1 张手牌加入【遗迹】」是强制项：超时 / 空回复按手牌顺序补一张
			for c0: int in dp.hand_cards:
				if dp.has_discard_card(c0):
					入 = c0
					break
		if 入 < 0:
			_引稽已完结 = true
			return _遗迹论破(ctx)
		# 这张是攻击目标从手里拿出来、面朝上摆在【遗迹】区的：统一入口（亮牌 + 触发封印，
		# 展示归属＝交牌的那名角色）
		engine.展示手牌(dp.id, [入])
		engine.take_from_hand(dp.id, [入])
		engine.add_cover(player.id, [入], player.id, YIN_JI_BIAN_JIAN, true)
		engine._broadcast_game()
		return _引稽交换(ctx)
	if _引稽阶段 == 2:
		var r2: Dictionary = take_skill_reply_full()
		_引稽阶段 = 0
		_引稽已完结 = true
		var args2: Array = r2.get("args", [])
		if args2.is_empty():
			return _遗迹论破(ctx)
		var X: int = int(args2[0])
		if X < 1 or X > mini(交换上限, _遗迹数()):
			engine.报错("【引稽编鉴】交换参数不对", player.id)
			return _遗迹论破(ctx)
		_交换遗迹(X, r2.get("card_ids", []), YIN_JI_BIAN_JIAN, X)
		return _遗迹论破(ctx)
	var dst: int = int(ctx.get("dst", -1))
	var dp2: BattlePlayer = engine.p(dst)
	if dp2 == null or dp2.hand_cards.is_empty():
		_引稽已完结 = true
		return _遗迹论破(ctx)
	notice_skill(YIN_JI_BIAN_JIAN, [dst])
	_引稽目标 = dst
	_引稽阶段 = 1
	# 「指定攻击目标将 1 张手牌加入【遗迹】」：让别人选牌，用技能询问，回复仍回到本钩子
	询问(dst, YIN_JI_BIAN_JIAN, 1, 0, GConst.CardSource.Hand, [], 0, "", dp2.hand_cards.duplicate(), false,
		0, -1, [], -1, {})
	return WAIT


func _引稽交换(ctx: Dictionary) -> int:
	var 上限: int = mini(mini(交换上限, player.hand_cards.size()), _遗迹数())
	if 上限 <= 0:
		_引稽已完结 = true
		return _遗迹论破(ctx)
	_引稽阶段 = 2
	询问(player.id, YIN_JI_BIAN_JIAN, 0, 0, GConst.CardSource.HandOrCover,
		_交换选项(YIN_JI_BIAN_JIAN, 0, 上限, true), 0, "", [], true, 0, -1, [], -1, {})
	return WAIT


# ============================================================
# 遗迹论破 9404：主动攻击① 移除同系遗迹加伤（回合限定）
# ============================================================
func _遗迹论破(ctx: Dictionary) -> int:
	if _遗迹论破已用:
		return SUCCESS
	var 牌: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 牌 == null:
		return SUCCESS
	var 同系: Array = _同系遗迹(牌.element_enum())
	if 同系.is_empty():
		return SUCCESS
	if _遗迹论破阶段 == 0:
		_遗迹论破阶段 = 1
		询问(player.id, YI_JI_LUN_PO, 0, 0, GConst.CardSource.Hand,
			_遗迹论破选项(同系.size()), 0, "", [], true, 0, -1, [], -1, {})
		return WAIT
	# 回来时重新算一次同系遗迹：询问期间盖牌可能变过（如【引稽编鉴】刚加了 1 张）
	_遗迹论破阶段 = 0
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 同系2: Array = _同系遗迹(牌.element_enum())
	if args.is_empty() or 同系2.is_empty():
		return SUCCESS
	var X: int = int(args[0])
	if X < 1 or X > 同系2.size():
		engine.报错("【遗迹论破】移除张数不对", player.id)
		return SUCCESS
	_遗迹论破已用 = true
	var 取: Array = []
	for i: int in range(X):
		取.append(int(同系2[i]))
	notice_skill(YI_JI_LUN_PO, [player.id])
	engine.remove_cover(player.id, 取, player.id, YI_JI_LUN_PO)
	engine.to_discard(取, {"owner": player.id, "source": "cover", "cause": YI_JI_LUN_PO})
	engine._log_discard(player.id, 取, false)
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + (X - 1)
	if X > 1:
		player.add_action(GConst.ActionType.Magic, YI_JI_LUN_PO, true)
	if _遗迹数() == 0:
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	engine._broadcast_game()
	return SUCCESS


func _遗迹论破选项(上限: int) -> Array:
	var 选项: Array = []
	for x: int in range(1, 4):
		var 文案: String = GConst.按钮原文(YI_JI_LUN_PO, x - 1)
		选项.append({
			"value": x,
			"label": 文案,
			"text": 文案,
			"enabled": x <= 上限,
		})
	return 选项


func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_遗迹论破已用 = false
	if _稽古待弃:
		return _稽古推进()
	return SUCCESS


# ============================================================
# 知行合一的收尾：该行动结算完成后弃剩余牌 + 【史料】
# ============================================================
func p_action_end(ctx: Dictionary) -> int:
	if _稽古待弃:
		return _稽古推进()
	if not bool(ctx.get("is_extra", false)) or int(ctx.get("extra_cause", 0)) != ZHI_XING_HE_YI:
		return SUCCESS
	if _知行已结算:
		return SUCCESS
	_知行已结算 = true
	_知行结算()
	_稽古检查()
	return _稽古推进()


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _稽古待弃:
		return _稽古推进()
	if _知行余.is_empty() and _知行待打 < 0:
		return SUCCESS
	# 选了牌却没打出去（额外行动被放弃）：这张牌不算白拿，按技能口径弃掉
	if _知行待打 >= 0 and player.has_discard_card(_知行待打):
		engine.take_from_hand(player.id, [_知行待打])
		engine.to_discard([_知行待打], {"owner": player.id, "source": "hand", "cause": ZHI_XING_HE_YI})
		engine._log_discard(player.id, [_知行待打])
	_知行结算()
	_稽古检查()
	return _稽古推进()


# ============================================================
# 以史为镜 9407：【史书】被弃置 / 打出时移出游戏
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


# ============================================================
# 工具
# ============================================================
func _遗迹数() -> int:
	return player.cover_cards.size()


## 与给定系别同系的【遗迹】：光系 / 暗系遗迹视为任意系别（9405 选淬精炼）
func _同系遗迹(系: int) -> Array:
	var out: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		var 牌系: int = 牌.element_enum()
		if 牌系 == 系 or 牌系 == GConst.CardElement.Light or 牌系 == GConst.CardElement.Darkness:
			out.append(cid)
	return out


func _史书在手() -> bool:
	return player.has_discard_card(史书号)


func _移除史书() -> void:
	if not player.has_discard_card(史书号):
		return
	engine.take_from_hand(player.id, [史书号])
	engine.放入移除牌堆(史书号)


func _交换选项(技能号: int, 手牌数: int, 上限: int = 0, 手牌随档: bool = false) -> Array:
	var 可换: int = mini(交换上限, _遗迹数())
	if 上限 > 0:
		可换 = mini(可换, 上限)
	var 选项: Array = []
	for x: int in range(1, 交换上限 + 1):
		var 文案: String = GConst.按钮原文(技能号, x - 1)
		var 手: int = x if 手牌随档 else 手牌数
		选项.append({
			"value": x,
			"label": 文案,
			"text": 文案,
			"enabled": x <= 可换,
			# 手牌 + 盖牌混选：这一档要「手牌 手 张 + 盖牌 X 张」（客户端据此卡选牌数）
			"need_card": 手 + x,
			"hand_need": 手,
			"cover_need": x,
		})
	return 选项


## 【遗迹】交换：把 X 张手牌放进【遗迹】区、取回 X 个【遗迹】。
## 给牌是两个区混选的回复，按「在手牌 / 在盖牌」拆开；张数不对按非法提交处理（不静默少换）。
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

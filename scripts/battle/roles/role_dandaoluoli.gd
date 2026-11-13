extends BattleRole
## 捣蛋萝莉（roleID 86 / 技能 8601~8606）
##
## 【Tricky】＝面朝下放在角色面前、视为基础效果的一张牌（卡表#1008 是无卡面的虚拟牌）。
## 真实牌面只存在服务端：_trickies 里一条 {dst, card} 对应一张占位。
## 规则口径（图鉴备注）：**每人面前至多存在 1 张【Tricky】**，放置前一律过这一关。
##
## 技能：
##   天使？ 8601（法术行动）：把手里带【天使之墙】的牌当【圣盾】放到一名角色面前
##       （照守护天使 701：牌本身进基础效果区，引擎自动格挡路径认 701 为【圣盾】）。
##   叛逆之墙 8602（法术行动）：把手牌 1 张【圣盾】【展示】与场上 1 个基础效果交换，然后你弃 1 张牌。
##   神秘伏笔 8603（被动）：【法术行动】结束后，牌库顶 1~2 张面朝下放到 X 名角色面前作【Tricky】。
##   T-r-i-c-k-y! 8604（响应）：你的主动攻击未命中时，查看 1 个【Tricky】；
##       若移除它并额外弃 1 张同系牌，对原拥有者造成 2 点法术伤害。
##   Trick or Treat 8605（被动）：你的行动阶段结束时场上【Tricky】>4：展示全部，所有人各弃 1 张
##       与面前【Tricky】同系的牌，然后移除全部；没弃到的人吃 2 点法术伤害；
##       再按双方弃牌数比大小给战绩区星石 / 额外回合。
##   Surprise! 8606（法术行动·必杀【水晶】）：弃 1 张牌，本回合手牌上限 +5，收走场上所有【Tricky】，
##       再把 X 张手牌面朝下放到 X 名角色面前作【Tricky】。
##
## 参考实现：守护天使 701（牌本身当【圣盾】）、天使 703（选目标→选场上基础效果牌）、
## 矜贵之女 7802（多步询问）、10803（展示牌库顶后选目标）。

const 天使问: int = 8601
const 叛逆之墙: int = 8602
const 神秘伏笔: int = 8603
const 垂迹: int = 8604
const 糖果: int = 8605
const 惊爆: int = 8606

## 面朝下的【Tricky】占位牌（卡表#1008，无卡面；真实牌面只在本脚本里）
const Tricky占位牌: int = GConst.卡_Tricky
const 手牌上限来源: String = "Surprise"

## 场上的【Tricky】：[{dst: 拥有者 id, card: 真实牌实例号}]；每人最多 1 条
var _trickies: Array = []
## 神秘伏笔：本链从牌库顶取到的牌
var _伏笔牌: Array = []
## T-r-i-c-k-y!：第 1 段选中的下标 + 这次可弃的同系手牌（第 2 段白名单）
var _垂迹选中: int = -1
var _垂迹同系: Array = []
## Trick or Treat：循环段当前问的人 / 他的同系手牌 / 待问名单 / 双方弃牌数 / 分支答案
var _糖果对象: Array = []
var _糖果下标: int = 0
var _糖果目标: int = -1
var _糖果同系: Array = []
var _糖果我方: int = 0
var _糖果敌方: int = 0
var _糖果分支: Dictionary = {}
var _糖果已用: bool = false


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	# 天使？：牌白名单＝手里带【天使之墙】的牌；目标＝面前还没有【圣盾】/【天使之墙】、能接收基础效果的人
	var 墙牌: Array[int] = hand_ids_with_skill(GConst.技能_天使之墙)
	var 墙目标: Array = player_ids_where(func(p: BattlePlayer) -> bool: return _墙目标可收(p.id), true)
	out.append({
		"type": GConst.ActionType.MagicSkill,
		"id": 天使问,
		"need_card": 1,
		"need_target": 1,
		"cards": 墙牌,
		"targets": 墙目标,
		"enabled": not 墙牌.is_empty() and not 墙目标.is_empty(),
	})
	# 叛逆之墙：先选手牌【圣盾】+ 目标，再由客户端列出该目标身上的基础效果供选（args[0] 回传）
	var 圣盾牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool:
		return c.card_name_enum() == GConst.CardName.Shield)
	var 有基础效果的目标: Array = player_ids_where(func(p: BattlePlayer) -> bool:
		return not p.basic_effects.is_empty() and 目标可接收基础效果(p.id, 叛逆之墙), true)
	out.append({
		"type": GConst.ActionType.MagicSkill,
		"id": 叛逆之墙,
		"need_card": 1,
		"need_target": 1,
		"card_source": GConst.CardSource.HandAndBasicEffect,
		"cards": 圣盾牌,
		"targets": 有基础效果的目标,
		"enabled": not 圣盾牌.is_empty() and not 有基础效果的目标.is_empty(),
	})
	# Surprise!：必杀【水晶】，另需弃 1 张手牌作发动牌
	out.append({
		"type": GConst.ActionType.MagicSkill,
		"id": 惊爆,
		"need_card": 1,
		"need_target": 0,
		"enabled": player.get_energy() >= 1 and not player.hand_cards.is_empty(),
	})
	return out


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if 技能号 == 天使问:
		if cards.is_empty() or player.手牌实例(int(cards[0])) < 0 or not _是天使之墙(int(cards[0])):
			return GConst.GE_INVALID_ACTION
		if dsts.is_empty() or not _墙目标可收(int(dsts[0])):
			return GConst.GE_INVALID_PLAYERID
		return GConst.GE_SUCCESS
	if 技能号 == 叛逆之墙:
		if cards.is_empty() or player.手牌实例(int(cards[0])) < 0 or not _是圣盾(int(cards[0])):
			return GConst.GE_INVALID_ACTION
		if dsts.is_empty() or engine.p(int(dsts[0])) == null:
			return GConst.GE_INVALID_PLAYERID
		var args: Array = action.get("args", [])
		if args.is_empty() or not _面前有(int(dsts[0]), int(args[0])):
			return GConst.GE_INVALID_ACTION
		# 【圣盾】只能有一层（同 base_v_shield）：换完之后目标面前不能还留着另一张「视作【圣盾】」的牌，
		# 否则会叠成两层圣盾。目标只有那一张盾时把它换出来是合法的。
		for be: Dictionary in engine.p(int(dsts[0])).basic_effects:
			if int(be["card"]) != int(args[0]) and _是盾牌(int(be["card"])):
				return GConst.GE_BASIC_EFFECT_ALREADY_EXISTS
		return GConst.GE_SUCCESS
	if 技能号 != 惊爆:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1 or cards.is_empty() or player.手牌实例(int(cards[0])) < 0:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 这次技能会把哪张牌放到谁面前（引擎在结算前统一问目标角色的 v_basic_effect_target）
func basic_effect_placements(action: Dictionary) -> Array:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 != 天使问 and 技能号 != 叛逆之墙:
		return []
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return []
	return [{"card": GConst.牌号(int(cards[0])), "dst": int(dsts[0])}]


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		天使问:
			return _天使(action)
		叛逆之墙:
			return _叛逆之墙(action)
	return _惊爆(action)


# ============================================================
# 天使？ 8601：带【天使之墙】的牌当【圣盾】放到目标面前
# ============================================================
func _天使(action: Dictionary) -> int:
	var 牌: int = int((action.get("card_ids", []) as Array)[0])
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	notice_skill(天使问, [dst])
	# 手牌公开亮出（统一入口：亮牌 + 触发 p_show_hand），再进目标的基础效果区
	engine.展示手牌(player.id, [牌])
	engine.take_from_hand(player.id, [牌], true)
	engine.add_basic_effect(dst, 牌, player.id, GConst.CAUSE_USE)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 叛逆之墙 8602：手牌【圣盾】与场上 1 个基础效果交换，然后你弃 1 张牌
# ============================================================
func _叛逆之墙(action: Dictionary) -> int:
	# 交换只在第一次进入时做；等弃牌回复回来时直接接着走弃牌那一段
	if not 多步询问进行中(叛逆之墙):
		if not _做交换(action):
			return SUCCESS
	return 多步询问(叛逆之墙, [
		{"需牌": 1, "可取消": false, "超时默认": []},
	], _叛逆弃牌)


## 交换：自己的【圣盾】进目标的基础效果区，目标那 1 个基础效果进自己手牌。
## 目标选的基础效果是【Tricky】占位牌时，交出的是它藏着的真实牌（并摘掉 _trickies 里那一条）。
func _做交换(action: Dictionary) -> bool:
	var 目标: int = int((action.get("dst_ids", []) as Array)[0])
	var 效果: int = int((action.get("args", []) as Array)[0])
	var 圣盾: int = player.手牌实例(int((action.get("card_ids", []) as Array)[0]))
	if 圣盾 < 0 or not _面前有(目标, 效果):
		return false
	notice_skill(叛逆之墙, [目标])
	engine.展示手牌(player.id, [圣盾])
	var 换来: int = 效果
	if 效果 == Tricky占位牌:
		换来 = _移除Tricky(_Tricky序号(目标), 叛逆之墙)
		if 换来 < 0:
			# 记账和场面对不上（理论上不会）：占位按普通基础效果摘掉，别把 -1 塞进手里
			engine.remove_basic_effect(目标, 效果, 叛逆之墙, player.id)
			换来 = 效果
	else:
		engine.remove_basic_effect(目标, 效果, 叛逆之墙, player.id)
	engine.take_from_hand(player.id, [圣盾], true)
	engine.add_basic_effect(目标, 圣盾, player.id, 叛逆之墙)
	player.add_hand_cards([换来])
	# 明牌基础效果（圣盾 / 封印…）换进手里时牌名本来就是公开的，照常播；
	# 换到的是面朝下的【Tricky】时只让本人看到牌（不播牌名，界面靠快照/张数日志体现）
	if 效果 != Tricky占位牌:
		engine.播获得牌日志(player.id, [换来])
	engine._broadcast_game()
	return true


func _叛逆弃牌(答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var 弃: int = -1
	for c: Variant in 回.get("cards", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	# 强制弃 1 张：超时 / 空回复按手牌顺序补一张
	if 弃 < 0:
		for cid: int in player.hand_cards:
			if player.has_discard_card(cid):
				弃 = cid
				break
	if 弃 < 0:
		return SUCCESS
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": 叛逆之墙})
	engine._log_discard(player.id, [弃])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 神秘伏笔 8603：法术行动结束后，牌库顶 1~2 张面朝下放到 X 名角色面前
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 被取消的技能行动没真正发生（引擎在 ctx 里标了 cancelled），不算「法术行动结束」
	if bool(ctx.get("cancelled", false)):
		return SUCCESS
	if not 多步询问进行中(神秘伏笔) and not 多步询问待收尾(神秘伏笔):
		_伏笔牌 = []
		# 牌库没牌、或场上没有能放【Tricky】的角色：这次什么都不做
		if engine.deck.pile_size() <= 0 or _可放Tricky角色().is_empty():
			return SUCCESS
	# 选项与目标同一问：点「放 N 张」→ 直接点 N 名角色 → 按一次「确定」一起提交
	# （选项各自带 need_target + targets，客户端配了「攻击结束二选一」就会按选中项放开目标）
	return 多步询问(神秘伏笔, [
		{"选项": _伏笔选项(), "需目标": 0, "可取消": false, "超时默认": [1],
		 "校验": _伏笔校验},
	], _伏笔结算)


## 放 1 张还是 2 张（牌库不够 / 能放 Tricky 的人不够的那一档置灰，但仍下发）。
## 每一项自己带需目标数与目标白名单：选 1 张就点 1 人、选 2 张就点 2 人。
func _伏笔选项() -> Array:
	var 候选: Array[int] = _可放Tricky角色()
	var 上限: int = mini(2, mini(engine.deck.pile_size(), 候选.size()))
	var 选项: Array = []
	for n: int in range(1, 3):
		var 文案: String = GConst.按钮原文(神秘伏笔, n - 1)
		选项.append({
			"value": n, "label": 文案, "text": 文案,
			"need_target": n, "targets": 候选,
			"enabled": n <= 上限,
		})
	return 选项


## 这一问的校验：张数合法（1~2 且不超过牌库 / 可放人数）、目标数＝张数、不重复、都能放
func _伏笔校验(回: Dictionary) -> bool:
	var args: Array = 回.get("args", [])
	if args.is_empty():
		return false
	var 张数: int = int(args[0])
	var 上限: int = mini(2, mini(engine.deck.pile_size(), _可放Tricky角色().size()))
	if 张数 < 1 or 张数 > 上限:
		return false
	var dsts: Array = 回.get("dsts", [])
	if dsts.size() != 张数:
		return false
	var 已: Array = []
	for d: Variant in dsts:
		var pid: int = int(d)
		if 已.has(pid) or not _可放Tricky(pid):
			return false
		已.append(pid)
	return true


func _伏笔结算(答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var args: Array = 回.get("args", [])
	if args.is_empty():
		return SUCCESS
	var 目标们: Array = []
	for d: Variant in 回.get("dsts", []):
		var pid: int = int(d)
		if _可放Tricky(pid) and not 目标们.has(pid):
			目标们.append(pid)
	# 超时（超时默认只给张数、没给目标）：按座位顺序补 1 名，别把取到的牌留在半空
	if 目标们.is_empty():
		var 候选: Array[int] = _可放Tricky角色()
		if 候选.is_empty():
			return SUCCESS
		目标们.append(候选[0])
	var 张数: int = mini(mini(int(args[0]), 目标们.size()), mini(2, engine.deck.pile_size()))
	if 张数 <= 0:
		return SUCCESS
	_伏笔牌 = engine.移除牌库顶(张数)
	目标们.resize(_伏笔牌.size())
	notice_skill(神秘伏笔, 目标们)
	for i: int in range(目标们.size()):
		_放Tricky(int(目标们[i]), int(_伏笔牌[i]), 神秘伏笔)
	_伏笔牌 = []
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# T-r-i-c-k-y! 8604：主动攻击未命中 → 查看 1 个【Tricky】→ 可移除并弃 1 张同系牌 → 2 点法术伤害
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _trickies.is_empty() or step >= STEP_DONE:
		return SUCCESS
	# 跨段的两个成员只在「新的一次发动」时清：等第二段回复的重入要保留它们
	if not 多步询问进行中(垂迹):
		_垂迹选中 = -1
		_垂迹同系 = []
	return 多步询问(垂迹, [
		# 第 1 段：点头像选「看谁面前的【Tricky】」（每人至多 1 张，选中的人↔他那张）；
		# 头像上的「查看Tricky」由客户端的 _垂迹头像提示 按这里下发的目标画
		{"需目标": 1, "目标白": _垂迹候选(), "答完": _垂迹查看},
		# 第 2 段：弃 1 张同系牌 → 移除该【Tricky】→ 2 点法术伤害。
		# 手里一张同系牌都没有时也照常问（不能静默把后半段跳过）：这时牌白名单是「全禁」，
		# 一张都点不动、提示条说明原因，玩家按「取消」结束这一手；
		# 调试模式下之后新发进来的同系牌照样能点（见 battle_mobile._技能牌能点 的调试例外）。
		# 牌白 / 文案都按「段真正被问到时」的 _垂迹同系 现算（它是第 1 段答完才有的），所以给 Callable。
		# 预览：把原拥有者点亮、并在其头像上写「2 法术伤害」（客户端走 preview_base / preview_ids 那条通用提示）。
		{"需牌": 1,
		 "牌白": func(_答案: Array) -> Array:
			return [GConst.手牌白名单_全禁] if _垂迹同系.is_empty() else _垂迹同系,
		 "询问文案": func(_答案: Array) -> String:
			if _垂迹同系.is_empty():
				return "【T-r-i-c-k-y!】：手里没有与这张【Tricky】同系的牌，无法移除它，本次不造成伤害"
			return "",
		 "校验": _垂迹校验,
		 "预览基准": 2, "预览类型": GConst.HarmType.Magic,
		 "预览目标": func(_答案: Array) -> Array: return _垂迹目标(),
		 # 高亮（＝客户端把原拥有者的头像画成「已选中」的黄色并锁住、点不动）：
		 # 这一步的目标是固定目标，玩家不能改，只是让他看清这段伤害落在谁头上
		 "高亮": func(_答案: Array) -> Array: return _垂迹目标()},
	], _垂迹结算)


## 第 2 段校验：空答案＝不做后半段（没有同系牌时按「确定」就是这个意思）；
## 真提交了牌就必须正好 1 张、在手、且与那张【Tricky】同系（不合法回「操作无效」重问，不静默吞掉）
func _垂迹校验(回: Dictionary) -> bool:
	var cards: Array = 回.get("cards", [])
	if cards.is_empty():
		return true
	if cards.size() != 1:
		return false
	var 实例: int = player.手牌实例(int(cards[0]))
	if 实例 < 0 or _垂迹选中 < 0 or _垂迹选中 >= _trickies.size():
		return false
	var 系: int = Data.get_card(int(_trickies[_垂迹选中]["card"])).element_enum()
	return Data.get_card(实例).element_enum() == 系


## 后半段要打的人：原拥有这张【Tricky】的角色（头像伤害提示 / 高亮都用它）
func _垂迹目标() -> Array[int]:
	if _垂迹选中 < 0 or _垂迹选中 >= _trickies.size():
		return []
	return [int(_trickies[_垂迹选中]["dst"])]


## 这一手可以查看的【Tricky】在谁面前（每人至多 1 张，所以直接按拥有者列）
func _垂迹候选() -> Array[int]:
	var out: Array[int] = []
	for 项: Dictionary in _trickies:
		var dst: int = int(项["dst"])
		if not out.has(dst):
			out.append(dst)
	return out


## 第 1 段答完：按选中的那名角色找到他面前的【Tricky】，私下看牌、算出可弃的同系手牌
func _垂迹查看(回: Dictionary, _答案: Array) -> int:
	var dsts: Array = 回.get("dsts", [])
	if dsts.is_empty():
		return SUCCESS
	var 序: int = _Tricky序号(int(dsts[0]))
	if 序 < 0:
		engine.报错("【T-r-i-c-k-y!】选中的角色面前没有【Tricky】", player.id)
		return SUCCESS
	_垂迹选中 = 序
	var 真牌: int = int(_trickies[序]["card"])
	# 查看只给发动者本人看（不广播、不触发 p_show_hand）
	engine.私下看牌(player.id, [真牌])
	var 系: int = Data.get_card(真牌).element_enum()
	_垂迹同系 = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == 系)
	return SUCCESS


## 第 2 段答完：弃 1 张同系牌 → 移除该【Tricky】→ 对原拥有者 2 点法术伤害
func _垂迹结算(答案: Array) -> int:
	var 序: int = _垂迹选中
	_垂迹选中 = -1
	_垂迹同系 = []
	if 序 < 0 or 序 >= _trickies.size():
		return SUCCESS
	var 项: Dictionary = _trickies[序]
	var 目标: int = int(项["dst"])
	var 真牌: int = int(项["card"])
	var 系: int = Data.get_card(真牌).element_enum()
	var 回: Dictionary = 答案[1] if 答案.size() > 1 else {}
	var 弃: int = -1
	for c: Variant in 回.get("cards", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0 and Data.get_card(实例).element_enum() == 系:
			弃 = 实例
			break
	if 弃 < 0:
		return SUCCESS
	notice_skill(垂迹, [目标])
	# 只摊「你要弃的那张同系牌」，不再额外翻一次【Tricky】的真实牌面（需求方要求）。
	# 走 展示手牌 = 摊牌 + p_show_hand（封印类技能的触发点），弃牌日志不再播弃牌特效。
	engine.展示手牌(player.id, [弃])
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": 垂迹})
	engine._log_discard(player.id, [弃], false)
	# 移除这个【Tricky】：占位与真实牌一起离场，真实牌进弃牌堆
	# （牌从来不在谁手里，不记 owner：否则会被「牌主是队友」这类弃牌拦截误判）
	var 移除牌: int = _移除Tricky(序, 垂迹)
	engine.to_discard([移除牌], {"source": "other", "cause": 垂迹})
	engine.push_harm({"src": player.id, "dst": 目标, "point": 2,
		"cause": 垂迹, "type": GConst.HarmType.Magic})
	# 压了伤害：引擎重入本钩子时用 step 挡住，避免再问一遍
	step = STEP_DONE
	engine._broadcast_game()
	return URGENT


# ============================================================
# Trick or Treat 8605：回合结束时场上有 >4 个【Tricky】
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# Surprise! 的「本回合手牌上限 +5」只在本回合内有效
	player.清手牌上限修正(手牌上限来源)
	if 多步询问进行中(糖果) or 多步询问待收尾(糖果):
		return _糖果推进()
	if _糖果已用 or _trickies.size() <= 4:
		return SUCCESS
	_糖果已用 = true
	notice_skill(糖果, [player.id])
	# 一个一个来：轮到谁才摊开谁面前那张【Tricky】（见 _糖果下一个目标），不在这里一次全摊。
	_糖果对象 = []
	for 项: Dictionary in _trickies:
		var 真牌: int = int(项["card"])
		_糖果对象.append({"pid": int(项["dst"]), "element": Data.get_card(真牌).element_enum()})
	_糖果下标 = 0
	_糖果目标 = -1
	_糖果同系 = []
	_糖果我方 = 0
	_糖果敌方 = 0
	_糖果分支 = {}
	# 比分从 0:0 开始挂在头像上，之后每弃一张刷新一次
	_刷新比分状态()
	engine._broadcast_game()
	return _糖果推进()


func _糖果推进() -> int:
	return 多步询问(糖果, [
		# 逐个问：轮到谁就先把谁那张【Tricky】摊开（见 _糖果下一个目标），再问他弃哪一张。
		# 手里没有同系牌的人也照常问（「不如此做」就该吃 2 点伤害）：不要求选牌、
		# 牌白名单给「全禁」，答完当场结算伤害并返回 URGENT —— 伤害先算完再问下一个人。
		{"问谁": func(_答案: Array) -> int: return _糖果目标,
		 "需牌": func(_答案: Array) -> int: return 0 if _糖果同系.is_empty() else 1,
		 "牌白": func(_答案: Array) -> Array:
			return [GConst.手牌白名单_全禁] if _糖果同系.is_empty() else _糖果同系,
		 "询问文案": func(_答案: Array) -> String:
			if _糖果同系.is_empty():
				return "【Trick or Treat】：手里没有与这张【Tricky】同系的牌，弃不了，受到 2 点法术伤害"
			return "",
		 "校验": _糖果校验,
		 "可取消": false, "超时默认": [],
		 "跳过": func(_答案: Array) -> bool: return not _糖果下一个目标(),
		 "答完": _糖果弃牌答完,
		 # 循环段：答完一个人后接着找下一个（答完返回 URGENT 时，引擎重入后再补判）
		 "重复": func(_回: Dictionary, _答案: Array) -> bool: return _糖果下一个目标()},
		{"选项": _糖果选项(),
		 "答完": _糖果记分支,
		 "可取消": false, "超时默认": [1],
		 "跳过": func(_答案: Array) -> bool: return _糖果我方 <= _糖果敌方},
	], _糖果结算)


## 这一问的校验：空答案＝弃不了（照常结算 2 点伤害）；真提交了牌就必须是手里那张同系牌
func _糖果校验(回: Dictionary) -> bool:
	var cards: Array = 回.get("cards", [])
	if cards.is_empty():
		return true
	if cards.size() != 1 or _糖果同系.is_empty():
		return false
	return _糖果同系.has(int(cards[0]))


## 找下一个要问的人：面前有【Tricky】的人逐个来（手里没有同系牌也算一个，他要吃 2 点伤害）
func _糖果下一个目标() -> bool:
	if _糖果目标 >= 0:
		return true
	while _糖果下标 < _糖果对象.size():
		var 项: Dictionary = _糖果对象[_糖果下标]
		_糖果下标 += 1
		var dp: BattlePlayer = engine.p(int(项["pid"]))
		if dp == null:
			continue
		var 同系: Array = []
		for cid: int in dp.hand_cards:
			if Data.get_card(cid).element_enum() == int(项["element"]):
				同系.append(cid)
		_糖果目标 = dp.id
		_糖果同系 = 同系
		# 轮到谁才把谁面前那张【Tricky】摊开（每人至多 1 张）。
		# 这一步每次重入都会调用，但 _糖果目标 已置位就直接返回，所以只会摊一次。
		var 序: int = _Tricky序号(dp.id)
		if 序 >= 0:
			engine.展示牌(dp.id, [int(_trickies[序]["card"])])
		return true
	return false


## 把当前比分写到自己的角色状态上（红队:蓝队）：过程中每弃一张就刷新一次，头像上的图标随之变化
func _刷新比分状态() -> void:
	var 红: int = _糖果我方 if player.color == GConst.RED else _糖果敌方
	var 蓝: int = _糖果敌方 if player.color == GConst.RED else _糖果我方
	player.trick_score = [红, 蓝]


## 一个人答完：弃 / 按手牌顺序替他补一张同系牌，按阵营记比分
func _糖果弃牌答完(回: Dictionary, _答案: Array) -> int:
	var dp: BattlePlayer = engine.p(_糖果目标)
	var 同系: Array = _糖果同系
	_糖果目标 = -1
	_糖果同系 = []
	var 弃: int = -1
	if dp != null:
		for c: Variant in 回.get("cards", []):
			var 实例: int = dp.手牌实例(int(c))
			if 实例 >= 0 and 同系.has(实例):
				弃 = 实例
				break
		# 强制：超时 / 空回复按手牌顺序补一张同系牌
		if 弃 < 0:
			for cid: int in 同系:
				if dp.has_discard_card(cid):
					弃 = cid
					break
	if 弃 >= 0 and dp != null:
		# 只摊「他弃的那张同系牌」，不再额外翻一次【Tricky】的真实牌面（需求方要求；
		# 轮到谁时已经单独摊过他那张了，见 _糖果下一个目标）。
		# 走 展示手牌 = 摊牌 + p_show_hand（封印触发点），弃牌日志不再播弃牌特效。
		engine.展示手牌(dp.id, [弃])
		engine.take_from_hand(dp.id, [弃])
		engine.to_discard([弃], {"owner": dp.id, "source": "hand", "cause": 糖果})
		engine._log_discard(dp.id, [弃], false)
		if dp.color == player.color:
			_糖果我方 += 1
		else:
			_糖果敌方 += 1
		# 比分当场更新到自己头像上（不必等全部问完）
		_刷新比分状态()
		engine._broadcast_game()
		# 还有下一个人要问就留在本段（重复）；问完了收尾
		if _糖果下一个目标():
			return SUCCESS
		_糖果收尾()
		return SUCCESS
	# 手里没有同系牌（或没选出合法的牌）＝「不如此做」：当场 2 点法术伤害。
	# 返回 URGENT 让这一下先结算完，引擎重入后再由「重复」找下一个人（伤害不会被攒到最后）。
	if dp != null:
		engine.push_harm({"src": player.id, "dst": dp.id, "point": 2,
			"cause": 糖果, "type": GConst.HarmType.Magic})
	return URGENT


## 问完所有人：移除所有【Tricky】（「不如此做」的 2 点伤害已经在各自那一手当场结算过了）
func _糖果收尾() -> void:
	while not _trickies.is_empty():
		var 真牌: int = _移除Tricky(0, 糖果)
		engine.to_discard([真牌], {"source": "other", "cause": 糖果})
	engine._broadcast_game()


func _糖果选项() -> Array:
	return [
		{"value": 1, "label": GConst.按钮原文(糖果, 0), "text": GConst.按钮原文(糖果, 0)},
		{"value": 2, "label": GConst.按钮原文(糖果, 1), "text": GConst.按钮原文(糖果, 1),
		 "need_card": 1, "enabled": not player.hand_cards.is_empty()},
	]


func _糖果记分支(回: Dictionary, _答案: Array) -> int:
	_糖果分支 = 回
	return SUCCESS


func _糖果结算(_答案: Array) -> int:
	# 还剩 Trickys（一个人都没问到 / 最后一手的收尾没跑到）：补收一次
	if not _trickies.is_empty():
		_糖果收尾()
	# 比分在过程中已经每弃一张刷新过一次；这里再刷一次兜底（值不变时等于没刷新）
	_刷新比分状态()
	engine._broadcast_game()
	# 比较结果在自己头像上飘一句（纯展示，不写日志）：赢 / 输 / 平各一句
	if _糖果我方 > _糖果敌方:
		engine.播头像飘字(player.id, "胜利！")
	elif _糖果我方 < _糖果敌方:
		engine.播头像飘字(player.id, "败北！")
	else:
		engine.播头像飘字(player.id, "可恶！")
	if _糖果我方 < _糖果敌方:
		# 对方弃得比我方多：对方【战绩区】+1【宝石】
		engine.set_team_gem(1 - player.color, engine.team_gem[1 - player.color] + 1)
		engine._broadcast_game()
		return SUCCESS
	if _糖果我方 <= _糖果敌方:
		return SUCCESS
	var args: Array = _糖果分支.get("args", [])
	if args.is_empty():
		return SUCCESS
	if int(args[0]) == 1:
		# 我方【战绩区】+1【水晶】且你 +1【水晶】
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
		player.set_crystal(player.crystal + 1)
		engine._broadcast_game()
		return SUCCESS
	# 你弃 1 张牌，并额外获得一个回合
	var 弃: int = -1
	for c: Variant in _糖果分支.get("cards", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			弃 = 实例
			break
	if 弃 < 0:
		for cid: int in player.hand_cards:
			if player.has_discard_card(cid):
				弃 = cid
				break
	if 弃 < 0:
		return SUCCESS
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": 糖果})
	engine._log_discard(player.id, [弃])
	安排额外回合(0, 糖果)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# Surprise! 8606（法术行动 · 必杀【水晶】）
# ============================================================
func _惊爆(action: Dictionary) -> int:
	if not 多步询问进行中(惊爆):
		if not _惊爆前半段(action):
			return SUCCESS
		# 手里没牌、或者场上没有能放【Tricky】的角色：收进手牌就到此为止
		if not _还能继续放():
			return SUCCESS
	# 循环段：一次放一张 —— 选 1 张手牌 + 点 1 名合法目标，答完**立刻**给他放上【Tricky】；
	# 放完还有牌、还有能放的人就留在本段接着问，直到放不了为止。
	# 玩家点「取消」＝就此打住（已经放出去的不收回）。
	# 提示条固定用技能说明原文（需求方要求），不写「请选…本次必须执行」那种步骤提示。
	return 多步询问(惊爆, [
		{"需牌": 1, "需目标": 1,
		 "牌白": func(_答案: Array) -> Array: return player.hand_cards,
		 "目标白": func(_答案: Array) -> Array: return _可放Tricky角色(),
		 "校验": _惊爆校验,
		 "答完": _惊爆放一张,
		 "跳过": func(_答案: Array) -> bool: return not _还能继续放(),
		 "重复": func(_回: Dictionary, _答案: Array) -> bool: return _还能继续放(),
		 "询问文案": GConst.skill_desc(惊爆)},
	], _惊爆结算)


## 付【水晶】+ 弃 1 张牌，本回合手牌上限 +5，把场上所有【Tricky】收进手牌
func _惊爆前半段(action: Dictionary) -> bool:
	var 弃牌: int = player.手牌实例(int((action.get("card_ids", []) as Array)[0]))
	if 弃牌 < 0 or player.get_energy() < 1:
		return false
	notice_skill(惊爆, [player.id])
	player.remove_energy(1)
	engine.take_from_hand(player.id, [弃牌])
	engine.to_discard([弃牌], {"owner": player.id, "source": "hand", "cause": 惊爆})
	engine._log_discard(player.id, [弃牌])
	# 「本回合结束前」手牌上限 +5（自己在回合结束时清，见 p_turn_end）
	player.设手牌上限修正(手牌上限来源, 5)
	var 收: Array = []
	for 项: Dictionary in _trickies:
		engine.remove_basic_effect(int(项["dst"]), Tricky占位牌, 惊爆, player.id)
		收.append(int(项["card"]))
	_trickies.clear()
	# 收进手里的是面朝下的暗牌：不播牌名，只让本人从手牌看到（张数变化由引擎边界统一写日志）
	if not 收.is_empty():
		player.add_hand_cards(收)
	engine._broadcast_game()
	return true


## 一次放一张的校验：牌必须还在手里、目标必须还能放【Tricky】，各恰好 1 个
func _惊爆校验(回: Dictionary) -> bool:
	var cards: Array = 回.get("cards", [])
	var dsts: Array = 回.get("dsts", [])
	if cards.size() != 1 or dsts.size() != 1:
		return false
	return player.手牌实例(int(cards[0])) >= 0 and _可放Tricky(int(dsts[0]))


## 手里还有牌、场上还有能放【Tricky】的人 —— 还能继续放下一张
func _还能继续放() -> bool:
	return not player.hand_cards.is_empty() and not _可放Tricky角色().is_empty()


## 这一手答完：点的那张手牌面朝下放到点的那名角色面前（立刻生效，接着问下一张）。
## **放完必须返回 URGENT**：add_basic_effect 会把「基础效果变动」钩子压进栈（渗蚀、占位同步…），
## 直接 SUCCESS 的话本段会立刻 re-ask 并 WAIT，压进去的钩子要等玩家答下一张才跑 ——
## 表现就是「贴上去不掉血，贴下一张才掉」。返回 URGENT 让引擎先生效一次再回来问。
func _惊爆放一张(回: Dictionary, _答案: Array) -> int:
	var 牌: int = -1
	for c: Variant in 回.get("cards", []):
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			牌 = 实例
			break
	var 目标: int = -1
	for d: Variant in 回.get("dsts", []):
		if _可放Tricky(int(d)):
			目标 = int(d)
			break
	if 牌 < 0 or 目标 < 0:
		return SUCCESS
	engine.take_from_hand(player.id, [牌])
	_放Tricky(目标, 牌, 惊爆)
	engine._broadcast_game()
	return URGENT


func _惊爆结算(_答案: Array) -> int:
	# 放【Tricky】在 _惊爆放一张 里已经逐张结算完了，这里没有收尾动作
	return SUCCESS


# ============================================================
# 回合开始 / 角色被替换
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_糖果已用 = false
		#【Trick or Treat】的比分只挂到自己的下个回合开始：头像上那枚「红:蓝」状态随之消失
		player.trick_score = []
	return SUCCESS


## 角色被替换时把场上的【Tricky】一并收掉：真实牌面只在本脚本里，跟着旧角色一起消失就成了幽灵占位。
func p_before_role_replace(_ctx: Dictionary) -> int:
	for 项: Dictionary in _trickies:
		engine.remove_basic_effect(int(项["dst"]), Tricky占位牌, 0, player.id)
		engine.to_discard([int(项["card"])], {"source": "other"})
	_trickies.clear()
	return SUCCESS


## 别的技能从场上拿走了【Tricky】占位牌（封印破碎 408「拿走」/ 风之洁净 703 / 天使之歌 705…）：
## 真实牌面只在本脚本里，不跟着处理就成了一张永远拿不回来的死牌。这里把记账一并收掉并交出真实牌：
##   · 占位进了某人的手牌（408 那种）→ 真实牌替换掉手里那张占位
##   · 其余（移除后弃掉）→ 真实牌进弃牌堆；**魔刃/异刃例外**：刃被移除＝收进移除牌堆（不进弃牌堆，
##     否则御刃/共振再也取不回来，洗牌时也会被当成特殊牌过滤掉）
## 自己摘占位（_移除Tricky / 收走全部）会先删掉记账再移除，所以这条钩子对自己不生效。
func p_basic_effect_change(ctx: Dictionary) -> int:
	if bool(ctx.get("add", false)) or int(ctx.get("card", -1)) != Tricky占位牌:
		return SUCCESS
	var 序: int = _Tricky序号(int(ctx.get("dst", -1)))
	if 序 < 0:
		return SUCCESS
	var 真牌: int = int(_trickies[序]["card"])
	_trickies.remove_at(序)
	var 谁: BattlePlayer = engine.p(int(ctx.get("doer", -1)))
	if 谁 != null and 谁.取出一张手牌(Tricky占位牌) >= 0:
		谁.add_hand_cards([真牌])
	elif _是刃卡(真牌):
		engine.放入移除牌堆(真牌)
	else:
		engine.to_discard([真牌], {"source": "other"})
	return SUCCESS


## 这张实例是不是噬神者的【魔刃】/【异刃】（牌面 1005 / 1006）
func _是刃卡(cid: int) -> bool:
	var 面: int = GConst.牌号(cid)
	return 面 == GConst.噬神者_魔刃卡 or 面 == GConst.噬神者_异刃卡


# ============================================================
# 【Tricky】与牌面工具
# ============================================================
## 这名玩家面前有没有【Tricky】（每人至多 1 张）
func _有Tricky(pid: int) -> bool:
	for 项: Dictionary in _trickies:
		if int(项["dst"]) == pid:
			return true
	return false


func _Tricky序号(pid: int) -> int:
	for i: int in range(_trickies.size()):
		if int(_trickies[i]["dst"]) == pid:
			return i
	return -1


## 能不能往他面前放【Tricky】：面前还没有，且目标角色不拒收基础效果（4601 这类）
func _可放Tricky(pid: int) -> bool:
	if _有Tricky(pid):
		return false
	return engine.v_basic_effect_target(pid, Tricky占位牌) == GConst.GE_SUCCESS


## 当前所有能放【Tricky】的角色（座位顺序）
func _可放Tricky角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if _可放Tricky(pid):
			out.append(pid)
	return out


## 放一张【Tricky】：占位进基础效果区、真实牌记账（调用方先确认 _可放Tricky）。
## 真实牌一并交给引擎的「基础效果变动」：面朝下的占位背后可能是【魔刃】/【异刃】，
## 噬神者靠它判渗蚀（见 role_shishenzhe.p_basic_effect_change）。
func _放Tricky(dst: int, card: int, cause: int) -> void:
	engine.add_basic_effect(dst, Tricky占位牌, player.id, cause, card)
	_trickies.append({"dst": dst, "card": card})


## 摘掉一条【Tricky】（占位与记账一起），返回它藏着的真实牌；序号不合法返回 -1
func _移除Tricky(序: int, cause: int) -> int:
	if 序 < 0 or 序 >= _trickies.size():
		return -1
	var 项: Dictionary = _trickies[序]
	_trickies.remove_at(序)
	engine.remove_basic_effect(int(项["dst"]), Tricky占位牌, cause, player.id)
	return int(项["card"])


## 这名玩家面前有没有这一张基础效果牌（选出来的那张必须真在他面前）
func _面前有(pid: int, card: int) -> bool:
	var dp: BattlePlayer = engine.p(pid)
	if dp == null:
		return false
	for be: Dictionary in dp.basic_effects:
		if int(be["card"]) == card:
			return true
	return false


func _是圣盾(cid: int) -> bool:
	return Data.get_card(cid).card_name_enum() == GConst.CardName.Shield


## 这张牌是不是「视作【圣盾】」的那一种（【圣盾】牌本身，或带【天使之墙】701 的攻击牌）
func _是盾牌(cid: int) -> bool:
	var 牌: GCard = Data.get_card(cid)
	if 牌 == null:
		return false
	return 牌.card_name_enum() == GConst.CardName.Shield or 牌.has_skill_id(GConst.技能_天使之墙)


## 手里带【天使之墙】（701）的圣命格攻击牌——就是这张牌能当【圣盾】用
func _是天使之墙(cid: int) -> bool:
	var 牌: GCard = Data.get_card(cid)
	return 牌 != null and 牌.is_attack() and 牌.has_skill_id(GConst.技能_天使之墙)


## 目标能不能接收这张【天使之墙】（当作【圣盾】）：面前已有【圣盾】/【天使之墙】就不行
func _墙目标可收(dst: int) -> bool:
	var dp: BattlePlayer = engine.p(dst)
	if dp == null:
		return false
	if dp.check_basic_effect_name(GConst.CardName.Shield):
		return false
	if dp.check_basic_effect_skill(GConst.技能_天使之墙):
		return false
	return 目标可接收基础效果(dst, GConst.技能_天使之墙)

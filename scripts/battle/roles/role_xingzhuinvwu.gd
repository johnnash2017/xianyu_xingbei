extends BattleRole
## 星坠女巫（40）：命定之理 / 星环 / 星刻 / 群星启示 / 黄金律 / 繁星 / 影月 / 蚀日 / 创刻律动
##
## 【卢恩】＝盖牌区面朝下的牌（角色表「指示物」列 2:卢恩:6），放进时 tag = "卢恩"、open = false。
## 【律法】＝ player.laws（1=繁星 / 2=影月 / 3=蚀日，放在角色面前的标记，随快照下发）。
##
## 口径：
## 1. 【命定之理】手牌上限 = 基础值 + (1 - 律法数)：律法数每次变化后重算。
## 2. 【星刻】在攻击 / 法术行动结束时，从牌库顶取 1 张面朝下放进盖牌区（tag="卢恩"）。
## 3. 【群星启示】两种模式都走它自己的技能按钮（二级技能栏选 1/2）：
##    ① 1 张手牌作【卢恩】+ 选 1 个【律法】+ 摸 0~1 张；
##    ② 移除 X 个【卢恩】【展示】→ 逐个判定符合条件的律法（繁星/影月/蚀日）→ 最后移除 1 个【律法】。
## 4. 【黄金律】：群星启示结算完、手牌 < 2 时摸 1 张（交换手牌与卢恩按简化口径不做，见计划文档）。
## 5. 【繁星】/【影月】/【蚀日】判定都用「本次移除的那 X 个卢恩」的牌面：
##    繁星＝4 个不同系别 或 4 个不同命格；影月＝成对的同系 / 同命格数；蚀日＝每 3 个同系 / 同命格。

const MING_DING_ZHI_LI: int = 4001
const XING_HUAN: int = 4002
const XING_KE: int = 4003
const QUN_XING_QI_SHI: int = 4004
const HUANG_JIN_LV: int = 4005
const FAN_XING: int = 4006
const YING_YUE: int = 4007
const SHI_RI: int = 4008
const CHUANG_KE_LV_DONG: int = 4009

const LU_EN标记: String = "卢恩"
const 卢恩上限: int = 6
const 律法_繁星: int = 1
const 律法_影月: int = 2
const 律法_蚀日: int = 3

## 群星启示的子流程
var _步: int = 0
var _模式: int = 0
var _目标: Array[int] = []
var _下标: int = 0
var _X: int = 0
var _移除卢恩: Array[int] = []
## 星环的目标数
var _星环X: int = 0


# ============================================================
# 初始化与手牌上限
# ============================================================
func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【命定之理】：游戏初始时你拥有【律法：繁星】
	player.加律法(律法_繁星)
	_重算手牌上限()


func _重算手牌上限() -> void:
	player.hand_cards_max = GConst.HAND_CARDS_MAX + 1 - player.律法数()


func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_重算手牌上限()
	return SUCCESS


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 地系: Array[int] = hand_ids_where(
		func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Earth)
	var 全体: Array[int] = _全体角色()
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": XING_HUAN,
			"need_card": 1,
			"cards": 地系,
			"enabled": not 地系.is_empty(),
		},
		{
			# 群星启示是「启动」：必须是 SpecialSkill（见 v_special_skill / p_special_skill）
			"type": GConst.ActionType.SpecialSkill,
			"id": QUN_XING_QI_SHI,
			"arg_choices": [
				{"value": 1, "label": "① 放手牌作卢恩 + 选律法 + 摸 0~1"},
				{"value": 2, "label": "② 移除卢恩，发动律法"},
			],
			"enabled": player.hand_cards.size() >= 1 or player.盖牌按标记(LU_EN标记).size() >= 1,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": CHUANG_KE_LV_DONG,
			"enabled": player.gem >= 1,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == QUN_XING_QI_SHI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QUN_XING_QI_SHI:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != QUN_XING_QI_SHI:
		return EMPTY_HANDLE
	# 启动技每回合只能发动一个（引擎也会在行动入口拦；这里防直接调用绕过）
	if player.boot_skill_used:
		return GConst.GE_INVALID_ACTION
	var rc: int = _p_群星启示(action)
	if rc == GConst.GE_INVALID_ACTION or rc == GConst.GE_INVALID_ARGUMENT:
		return rc
	player.boot_skill_used = true
	return rc


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		XING_HUAN:
			var cards: Array = action.get("card_ids", [])
			if cards.size() != 1:
				return GConst.GE_INVALID_CARDID
			var 卡: GCard = Data.get_card(int(cards[0]))
			if 卡 == null or not player.有手牌(int(cards[0])):
				return GConst.GE_INVALID_CARDID
			if 卡.element_enum() != GConst.CardElement.Earth:
				return GConst.GE_INVALID_CARDID
			return GConst.GE_SUCCESS
		CHUANG_KE_LV_DONG:
			if player.gem < 1:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		XING_HUAN:
			return _p_星环(action)
		CHUANG_KE_LV_DONG:
			return _p_创刻律动()
	return EMPTY_HANDLE


# ============================================================
# 4002 星环：弃 X 张地系牌 → (X-1) 名角色与你各 +1 治疗、各摸 1 张；你 +1 法术行动
# ============================================================
func _p_星环(action: Dictionary) -> int:
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var cid: int = int((action.get("card_ids", []) as Array)[0])
	notice_skill(XING_HUAN, [])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid], false)
	engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": XING_HUAN})
	engine._log_discard(player.id, [cid], false)
	_星环X = 1
	_步 = 10
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 4003 星刻：攻击 / 法术行动结束时，牌库顶 1 张面朝下作为【卢恩】
# ============================================================
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 种类: String = str(ctx.get("kind", ""))
	if 种类 != "attack" and 种类 != "magic":
		return SUCCESS
	if not player.can_add_cover_cards(1):
		return SUCCESS
	var 顶: Array[int] = engine.移除牌库顶(1)
	if 顶.is_empty():
		return SUCCESS
	engine.add_cover(player.id, [int(顶[0])], player.id, XING_KE, false, LU_EN标记)
	notice_skill(XING_KE, [player.id])
	return URGENT


# ============================================================
# 4004 群星启示
# ============================================================
func _p_群星启示(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var 模式: int = int(args[0]) if not args.is_empty() else 1
	_模式 = 模式
	_步 = 0
	_X = 0
	_移除卢恩 = []
	目标.clear()
	if 模式 == 2:
		var 卢恩: Array[int] = player.盖牌按标记(LU_EN标记)
		if 卢恩.is_empty():
			return GConst.GE_INVALID_ACTION
		_步 = 20
	else:
		if player.hand_cards.is_empty():
			return GConst.GE_INVALID_ACTION
		_步 = 11
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
	return URGENT

var 目标: Array[int] = []


# ============================================================
# 4009 创刻律动：付 1 宝石 → 摸 0~1 张 → 最多 (1+律法数) 张手牌作【卢恩】
# ============================================================
func _p_创刻律动() -> int:
	if player.gem < 1:
		return GConst.GE_INVALID_ACTION
	player.set_gem(player.gem - 1)
	notice_skill(CHUANG_KE_LV_DONG, [player.id])
	_步 = 30
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 统一子流程
# ============================================================
func p_xing_zhui_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	match _步:
		10:  # 星环：选 X（地系牌张数）
			if not engine.has_reply():
				var 地系: Array[int] = hand_ids_where(
					func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Earth)
				var 选项: Array = []
				for i: int in range(1, 地系.size() + 1):
					选项.append(i)
				if 选项.is_empty():
					_步 = 0
					return SUCCESS
				询问(player.id, XING_HUAN, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], true,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					"【星环】：还要再弃几张地系牌【展示】（总共 X 张）？")
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			var args: Array = r.get("args", [])
			var 再弃: int = int(args[0]) if not args.is_empty() else 1
			_星环X += 再弃
			_再弃 = 再弃
			_步 = 11
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		11:  # 星环：再弃 N 张地系牌
			var 地系2: Array[int] = hand_ids_where(
				func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Earth)
			var 需: int = mini(_再弃, 地系2.size())
			if 需 > 0:
				if not engine.has_reply():
					询问(player.id, XING_HUAN, 需, 0, GConst.CardSource.Hand, [], 需, "", [], false,
						0, player.id, [], 需, {}, 0, 0, false, [], true, -1, 0,
						"【星环】：再弃 %d 张地系牌【展示】" % 需)
					return WAIT
				var r2: Dictionary = take_skill_reply_full()
				var cards: Array = r2.get("card_ids", [])
				var 弃: Array = []
				for c: Variant in cards:
					if 弃.size() < 需 and player.有手牌(int(c)):
						弃.append(int(c))
				if not 弃.is_empty():
					engine.broadcast(GConst.Msg.Card, {
						"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
						"card_ids": 弃, "is_real": true,
					})
					engine.take_from_hand(player.id, 弃, false)
					engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": XING_HUAN})
					engine._log_discard(player.id, 弃, false)
				_步 = 12
				engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
				return URGENT
			_步 = 12
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		12:  # 星环：选 (X-1) 名其他角色
			var 需人: int = maxi(_星环X - 1, 0)
			if 需人 <= 0 or 目标.size() >= 需人:
				_步 = 13
				engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
				return URGENT
			if not engine.has_reply():
				var 池: Array[int] = []
				for pid: int in _全体角色():
					if pid != player.id and not 目标.has(pid):
						池.append(pid)
				if 池.is_empty():
					_步 = 13
					engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
					return URGENT
				询问(player.id, XING_HUAN, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
					0, -1, 池, -1, {}, 0, 0, false, [], true, -1, 0,
					"【星环】：指定 1 名角色（还可指定 %d 名）" % (需人 - 目标.size()))
				return WAIT
			var r3: Dictionary = take_skill_reply_full()
			var ds: Array = r3.get("dst_ids", [])
			if ds.size() == 1 and not 目标.has(int(ds[0])):
				目标.append(int(ds[0]))
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		13:  # 星环：结算治疗 + 摸牌 + 额外法术行动
			_步 = 0
			for pid: int in 目标:
				施加治疗(pid, 1)
				engine.push_draw(pid, 1, XING_HUAN)
			施加治疗(player.id, 1)
			engine.push_draw(player.id, 1, XING_HUAN)
			player.add_action(GConst.ActionType.Magic, XING_HUAN, true, true)
			目标 = []
			engine._broadcast_game()
			return URGENT
		11 + 1000:  # 占位（不会走到）
			return SUCCESS
		20:  # 群星启示②：移除 X 个卢恩
			var 卢恩2: Array[int] = player.盖牌按标记(LU_EN标记)
			if 卢恩2.is_empty():
				_步 = 0
				return SUCCESS
			if not engine.has_reply():
				var 选项2: Array = []
				for i2: int in range(1, 卢恩2.size() + 1):
					选项2.append(i2)
				询问(player.id, QUN_XING_QI_SHI, 0, 0, GConst.CardSource.Hand, 选项2, 0, "", [], false,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					"【群星启示】：移除几个【卢恩】【展示】？（X）")
				return WAIT
			var r4: Dictionary = take_skill_reply_full()
			var args4: Array = r4.get("args", [])
			var x4: int = int(args4[0]) if not args4.is_empty() else 1
			x4 = clampi(x4, 1, 卢恩2.size())
			_移除卢恩 = []
			for i3: int in range(x4):
				_移除卢恩.append(int(卢恩2[i3]))
			_步 = 21
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		21:  # 群星启示②：逐个移除并展示
			if _下标 < _移除卢恩.size():
				var 牌: int = int(_移除卢恩[_下标])
				_下标 += 1
				engine.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
					"card_ids": [牌], "is_real": true,
				})
				if player.有盖牌(牌):
					engine.remove_cover(player.id, [牌], player.id, QUN_XING_QI_SHI)
				engine.to_discard([牌], {"owner": player.id, "source": "cover", "cause": QUN_XING_QI_SHI})
				engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
				return URGENT
			_下标 = 0
			_步 = 22
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		22:  # 群星启示②：判定并发动符合条件的律法
			_步 = 0
			var 结果: Dictionary = _律法判定(_移除卢恩)
			if 结果.get("繁星", false):
				_发动繁星(bool(结果.get("繁星双", false)))
			if int(结果.get("影月同系", 0)) > 1:
				_发动影月(int(结果.get("影月同系", 0)))
			if int(结果.get("影月同命", 0)) > 1:
				_发动影月治疗(int(结果.get("影月同命", 0)))
			if int(结果.get("蚀日同系", 0)) > 0:
				player.set_gem(player.gem + int(结果.get("蚀日同系", 0)))
				engine._broadcast_game()
			if int(结果.get("蚀日同命", 0)) > 0:
				engine.set_team_gem(player.color,
					engine.team_gem[player.color] + int(结果.get("蚀日同命", 0)))
				engine._broadcast_game()
			# 然后移除 1 个律法
			if player.律法数() > 0:
				player.移除律法()
				_重算手牌上限()
				engine._broadcast_game()
			_检查黄金律()
			return SUCCESS
		30:  # 创刻律动：摸 0~1 张
			if not engine.has_reply():
				询问(player.id, CHUANG_KE_LV_DONG, 0, 0, GConst.CardSource.Hand, [0, 1], 0, "", [], true,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					"【创刻律动】：摸 0~1 张牌？")
				return WAIT
			var r5: Dictionary = take_skill_reply_full()
			var args5: Array = r5.get("args", [])
			var 摸: int = int(args5[0]) if not args5.is_empty() else 0
			if 摸 > 0:
				engine.push_draw(player.id, 摸, CHUANG_KE_LV_DONG)
			_步 = 31
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		31:  # 创刻律动：选最多 (1+律法数) 张手牌作卢恩
			var 可放: int = mini(1 + player.律法数(), player.cover_space())
			var 可选: int = mini(可放, player.hand_cards.size())
			if 可选 <= 0:
				_步 = 0
				return SUCCESS
			if not engine.has_reply():
				询问(player.id, CHUANG_KE_LV_DONG, 0, 0, GConst.CardSource.Hand, [], 可选, "",
					player.hand_cards.duplicate(), true, 0, player.id, [], 可选, {}, 0, 0, false, [], true, -1, 0,
					"【创刻律动】：选择最多 %d 张手牌面朝下作为【卢恩】" % 可选)
				return WAIT
			var r6: Dictionary = take_skill_reply_full()
			var cards6: Array = r6.get("card_ids", [])
			var 放: Array = []
			for c6: Variant in cards6:
				if 放.size() < 可选 and player.有手牌(int(c6)):
					var 实例: int = player.取出实例(player.hand_cards, int(c6))
					if 实例 > 0:
						放.append(实例)
			_步 = 0
			if not 放.is_empty():
				engine.add_cover(player.id, 放, player.id, CHUANG_KE_LV_DONG, false, LU_EN标记)
			_检查黄金律()
			return URGENT
		40:  # 影月：选目标角色，造成 X 点法术伤害
			if not engine.has_reply():
				询问(player.id, YING_YUE, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
					0, -1, _全体角色(), -1, {}, 0, 0, false, [], true, -1, 0,
					"【影月】：指定 1 名目标角色，造成 %d 点法术伤害" % _影月伤害)
				return WAIT
			var r10: Dictionary = take_skill_reply_full()
			var ds10: Array = r10.get("dst_ids", [])
			_步 = 0
			if ds10.size() == 1:
				engine.push_harm({
					"src": player.id, "dst": int(ds10[0]), "point": _影月伤害,
					"cause": YING_YUE, "type": GConst.HarmType.Magic,
				})
				return URGENT
			return SUCCESS
		41:  # 影月：把 X 点治疗分给 1 名我方（简化：指定的 1 名我方 +X）
			if not engine.has_reply():
				询问(player.id, YING_YUE, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
					0, -1, _我方角色(), -1, {}, 0, 0, false, [], true, -1, 0,
					"【影月】：指定 1 名我方角色 +%d【治疗】" % 影月治疗点)
				return WAIT
			var r11: Dictionary = take_skill_reply_full()
			var ds11: Array = r11.get("dst_ids", [])
			_步 = 0
			if ds11.size() == 1:
				施加治疗(int(ds11[0]), 影月治疗点)
				return URGENT
			return SUCCESS
		11:  # 群星启示①：选律法
			var 可选律法: Array = [律法_繁星, 律法_影月, 律法_蚀日]
			if not engine.has_reply():
				询问(player.id, QUN_XING_QI_SHI, 0, 0, GConst.CardSource.Hand, 可选律法, 0, "", [], false,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					"【群星启示】：选择 1 个【律法】放置于你面前（1=繁星 / 2=影月 / 3=蚀日）")
				return WAIT
			var r7: Dictionary = take_skill_reply_full()
			var args7: Array = r7.get("args", [])
			var 律: int = int(args7[0]) if not args7.is_empty() else 律法_繁星
			player.加律法(律)
			_重算手牌上限()
			_步 = 12
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		12:  # 群星启示①：选 1 张手牌面朝下作为卢恩
			if not player.can_add_cover_cards(1) or player.hand_cards.is_empty():
				_步 = 13
				engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
				return URGENT
			if not engine.has_reply():
				询问(player.id, QUN_XING_QI_SHI, 1, 0, GConst.CardSource.Hand, [], 1, "", [], false,
					0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
					"【群星启示】：选择 1 张手牌面朝下作为【卢恩】")
				return WAIT
			var r8: Dictionary = take_skill_reply_full()
			var cards8: Array = r8.get("card_ids", [])
			_步 = 13
			if not cards8.is_empty():
				var 实: int = player.取出实例(player.hand_cards, int(cards8[0]))
				if 实 > 0:
					engine.add_cover(player.id, [实], player.id, QUN_XING_QI_SHI, false, LU_EN标记)
			engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
			return URGENT
		13:  # 群星启示①：摸 0~1 张，然后黄金律
			if not engine.has_reply():
				询问(player.id, QUN_XING_QI_SHI, 0, 0, GConst.CardSource.Hand, [0, 1], 0, "", [], true,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					"【群星启示】：摸 0~1 张牌？")
				return WAIT
			var r9: Dictionary = take_skill_reply_full()
			var args9: Array = r9.get("args", [])
			var 摸9: int = int(args9[0]) if not args9.is_empty() else 0
			_步 = 0
			if 摸9 > 0:
				engine.push_draw(player.id, 摸9, QUN_XING_QI_SHI)
			_检查黄金律()
			return URGENT
	return SUCCESS

var _再弃: int = 1


# ============================================================
# 4005 黄金律：群星启示后手牌 < 2 → 摸 1 张
# ============================================================
func _检查黄金律() -> void:
	if player.hand_cards.size() >= 2:
		return
	notice_skill(HUANG_JIN_LV, [player.id])
	engine.push_draw(player.id, 1, HUANG_JIN_LV)
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id, "黄金律": true}, []))


# ============================================================
# 律法判定
# ============================================================
## 对本次移除的卢恩做组成判定：
##   繁星：4 个不同系别 或 4 个不同命格（两者同时 → 繁星双）
##   影月：成对的同系 / 同命格 的对数（取整）
##   蚀日：每 3 个同系 / 每 3 个同命格
func _律法判定(牌表: Array) -> Dictionary:
	var 系计数: Dictionary = {}
	var 命计数: Dictionary = {}
	for cid: Variant in 牌表:
		var 卡: GCard = Data.get_card(int(cid))
		if 卡 == null:
			continue
		var 系: int = 卡.element_enum()
		var 命: int = 卡.fate_pattern_enum()
		if 系 > 0:
			系计数[系] = int(系计数.get(系, 0)) + 1
		if 命 > 0:
			命计数[命] = int(命计数.get(命, 0)) + 1
	var 系对: int = 0
	var 命对: int = 0
	var 系三: int = 0
	var 命三: int = 0
	for k: Variant in 系计数.keys():
		系对 += int(系计数[k]) / 2
		系三 += int(系计数[k]) / 3
	for k2: Variant in 命计数.keys():
		命对 += int(命计数[k2]) / 2
		命三 += int(命计数[k2]) / 3
	var 四系: bool = 系计数.size() >= 4
	var 四命: bool = 命计数.size() >= 4
	return {
		"繁星": 四系 or 四命, "繁星双": 四系 and 四命,
		"影月同系": 系对, "影月同命": 命对,
		"蚀日同系": 系三, "蚀日同命": 命三,
	}


## 【繁星】：对所有对手各 1 点法术伤害；双条件同时 → 目标队友 +1 宝石
func _发动繁星(双: bool) -> void:
	notice_skill(FAN_XING, enemy_ids())
	for i: int in range(enemy_ids().size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": int(enemy_ids()[i]), "point": 1,
			"cause": FAN_XING, "type": GConst.HarmType.Magic,
		})
	if 双:
		var 队: Array[int] = ally_ids()
		if not 队.is_empty():
			var 友: BattlePlayer = engine.p(int(队[0]))
			if 友 != null:
				友.set_gem(友.gem + 1)
	engine._broadcast_game()


## 【影月】：同系对数 > 1 → 目标角色 X 点法术伤害
func _发动影月(对数: int) -> void:
	notice_skill(YING_YUE, [player.id])
	_影月伤害 = 对数
	_步 = 40
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))

var _影月伤害: int = 0


## 【影月】的同命格分支：任意分配 X 点治疗给 1~2 位我方（简化：指定的 1 名我方 +X）
func _发动影月治疗(点数: int) -> void:
	var 队: Array[int] = _我方角色()
	if 队.is_empty():
		return
	影月治疗点 = 点数
	_步 = 41
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))

var 影月治疗点: int = 0


# ============================================================
# 小工具
# ============================================================
func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out


func _我方角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp != null and pp.color == player.color:
			out.append(pid)
	return out

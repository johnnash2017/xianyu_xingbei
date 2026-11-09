extends BattleRole
## 仲裁者·圣（roleID 109）
##
## 【天平·左】/【天平·右】＝两张场卡（单侧最多 3 张、同侧必须同系别，牌面朝上堆在卡上）；
## 【罪】＝0 号指示物（上限 3）。
##
## 技能：
##   神之天平 10901（被动）：开局拥有【天平·左】与【天平·右】。
##   善恶必计 10902（响应【回合限定】）：我方角色承受伤害⑥结算完，可把 1 张手牌里的基本牌
##       面朝上放到任一天平上，然后你摸 1 张牌【强制】。
##   天平倾倒 10903（被动）：你的回合开始 / 结束时，若两侧牌数差 >1：舍弃多的一侧所有牌，
##       展示牌库顶 4 张，你选 2 张加入手牌【强制】、另 2 张弃掉，你 +1【罪】，目标队友 +2【治疗】。
##   神之审判 10904（响应）：你的回合结束时，若两侧牌数都 >2：舍弃两侧所有牌，
##       对 2 名目标角色各造成 2 点攻击伤害③。
##   替罪羔羊 10905（被动）：天平单侧上限 3；新牌与同侧已有的牌不同系时，移除该侧所有牌，你 +1【罪】。
##   天罪 10906（启动·必杀【水晶】）：你 +1【罪】；横置持续到本回合结束，期间主动攻击命中②，
##       可把手牌中 2 张基本牌面朝上分别放到【天平·左】和【天平·右】上；结束时【重置】。
##   罪迟必到 10907（法术·必杀【水晶】）：本回合你无法获得【罪】；移除所有【罪】，
##       可将手牌中 X 张基本牌面朝上依次放到任一天平上，X＝移除的【罪】数。
##   罪灭之左 10908（被动）：每当【天平·左】上的牌数增加、且增加后 >1，对（X-1）名目标对手
##       各造成 1 点攻击伤害③，X＝增加后本侧的牌数。
##   圣方之右 10909（被动）：每当【天平·右】上的牌被移除、且移除牌数 >1，你 +1【治疗】。

const SHEN_ZHI_TIAN_PING: int = 10901
const SHAN_E_BI_JI: int = 10902
const TIAN_PING_QING_DAO: int = 10903
const SHEN_ZHI_SHEN_PAN: int = 10904
const TI_ZUI_GAO_YANG: int = 10905
const TIAN_ZUI: int = 10906
const ZUI_CHI_BI_DAO: int = 10907
const ZUI_MIE_ZHI_ZUO: int = 10908
const SHENG_FANG_ZHI_YOU: int = 10909

const 罪槽: int = 0
const 左: int = 0
const 右: int = 1
const 天平名: Array[String] = ["天平·左", "天平·右"]

var _本回合禁罪: bool = false
## 善恶必计：1＝等选牌与侧 / 2＝等罪灭之左的目标 / 3＝等摸牌
var _善恶阶段: int = 0
var _善恶已用: bool = false
## 天平倾倒：1＝选第一张 / 2＝选第二张 / 3＝等选队友
var _倾倒阶段: int = 0
var _倾倒牌: Array = []
var _倾倒剩余: Array = []
var _倾倒选: Array = []
## 神之审判：1＝等选 2 名目标
var _审判阶段: int = 0
## 天罪：横置持续到本回合结束；1＝等选 2 张基本牌 / 2＝等伤害目标
var _天罪中: bool = false
var _天罪阶段: int = 0
## 罪迟必到：1＝循环选牌 / 2＝等伤害目标
var _罪迟阶段: int = 0
var _罪迟剩余: int = 0
## 罪灭之左欠下的伤害目标数
var _伤待选: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【神之天平】：开局拥有左右两张天平（counter_max=3 表示单侧上限 3）
	for 侧: int in [左, 右]:
		engine.加场卡({
			"id": 天平名[侧], "owner": player.id, "attached": player.id,
			"counter": 0, "counter_max": 3, "pile": [], "element": -1,
		})


# ============================================================
# 技能栏：天罪（启动）
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": TIAN_ZUI,
			"need_card": 0,
			"need_target": 0,
			"enabled": player.get_energy() >= 1,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": ZUI_CHI_BI_DAO,
			"need_card": 0,
			"need_target": 0,
			"enabled": player.get_energy() >= 1,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == TIAN_ZUI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != TIAN_ZUI:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != TIAN_ZUI:
		return GConst.GE_INVALID_ACTION
	player.boot_skill_used = true
	player.remove_energy(1)
	_加罪(1)
	_天罪中 = true
	player.tap = true
	notice_skill(TIAN_ZUI, [player.id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 善恶必计：我方承受伤害⑥结算完后
# ============================================================
func p_harm_end(ctx: Dictionary) -> int:
	if _善恶阶段 == 3:
		_善恶阶段 = 0
		engine.push_强制摸牌(player.id, 1, SHAN_E_BI_JI)
		return URGENT
	if _善恶阶段 == 2:
		_善恶阶段 = 3
		return _收伤害目标(take_skill_reply_full())
	if _善恶阶段 == 1:
		return _善恶选牌()
	var harm: Dictionary = ctx.get("harm", {})
	var dst: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	if _善恶已用 or _基本手牌().is_empty():
		return SUCCESS
	_善恶阶段 = 1
	询问(player.id, SHAN_E_BI_JI, 0, 0, GConst.CardSource.Hand, _放牌选项(SHAN_E_BI_JI), 0, "",
		[], true, 0, -1, [], -1, {})
	return WAIT


func _善恶选牌() -> int:
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	_善恶阶段 = 0
	if args.is_empty() or cards.is_empty():
		return SUCCESS
	var 侧: int = int(args[0])
	var 牌: int = int(cards[0])
	if not player.has_hand_card(牌) or 侧 < 0 or 侧 > 1:
		engine.报错("【善恶必计】提交的牌或天平不合法", player.id)
		return SUCCESS
	_善恶已用 = true
	engine.take_from_hand(player.id, [牌])
	_放牌(侧, 牌)
	if _伤待选 > 0:
		_善恶阶段 = 2
		_问伤害目标()
		return WAIT
	engine.push_强制摸牌(player.id, 1, SHAN_E_BI_JI)
	return URGENT


# ============================================================
# 天平倾倒：回合开始 / 结束时，两侧差 >1 就倒向多的一边
# ============================================================
func p_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_本回合禁罪 = false
	_善恶已用 = false
	return _天平倾倒()


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 先问神之审判（响应），再结算被动天平倾倒；天罪的横置在最后重置
	if _审判阶段 != 0 or (张数(左) > 2 and 张数(右) > 2):
		var rc: int = _神之审判()
		if rc != SUCCESS:
			return rc
	var rc2: int = _天平倾倒()
	if rc2 != SUCCESS:
		return rc2
	if _天罪中:
		_天罪中 = false
		player.tap = false
	return SUCCESS


func _天平倾倒() -> int:
	if _倾倒阶段 == 2:
		# 选完队友：+2 治疗
		var r3: Dictionary = take_skill_reply_full()
		var dsts: Array = r3.get("dst_ids", [])
		_倾倒阶段 = 0
		if dsts.is_empty():
			engine.报错("【天平倾倒】没有选到队友", player.id)
			return SUCCESS
		施加治疗(int(dsts[0]), 2)
		engine._broadcast_game()
		return SUCCESS
	if _倾倒阶段 == 1:
		_倾倒收选(take_skill_reply_full())
		if _倾倒选.size() < mini(2, _倾倒牌.size()) and not _倾倒剩余.is_empty():
			_倾倒问选()
			return WAIT
		# 选够了（或牌不够）：剩下的弃掉、选中的入手、+1【罪】，再问给谁 +2 治疗
		var 余: Array = []
		for c: Variant in _倾倒牌:
			if not _倾倒选.has(int(c)):
				余.append(int(c))
		if not 余.is_empty():
			engine.to_discard(余, {"owner": player.id, "source": "deck",
				"cause": TIAN_PING_QING_DAO, "face_up": true})
		if not _倾倒选.is_empty():
			player.add_hand_cards(_倾倒选)
			engine.播获得牌日志(player.id, _倾倒选)
		_加罪(1)
		_倾倒选 = []
		_倾倒牌 = []
		engine._broadcast_game()
		var 队: Array = 队友()
		if 队.is_empty():
			_倾倒阶段 = 0
			return SUCCESS
		_倾倒阶段 = 2
		询问(player.id, TIAN_PING_QING_DAO, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
			0, -1, 队, -1, {}, 2, GConst.预览类型_治疗)
		return WAIT
	# 起点：两侧牌数差 >1 才倒
	if absi(张数(左) - 张数(右)) <= 1:
		return SUCCESS
	var 多的一侧: int = 左 if 张数(左) > 张数(右) else 右
	_移除侧(多的一侧)
	_倾倒牌 = engine.逐张移除牌库顶(4, player.id)
	_倾倒选.clear()
	if _倾倒牌.is_empty():
		return SUCCESS
	engine.展示牌库顶(player.id, _倾倒牌, true)
	_倾倒阶段 = 1
	_倾倒问选()
	return WAIT


## 从展示的牌里再选 1 张（超时 / 非法按剩下的第一张）
func _倾倒收选(r: Dictionary) -> void:
	var args: Array = r.get("args", [])
	var 取: int = -1
	if not args.is_empty():
		var 档: int = int(args[0])
		if 档 >= 1 and 档 <= _倾倒剩余.size():
			取 = int(_倾倒剩余[档 - 1])
	if 取 < 0 and not _倾倒剩余.is_empty():
		取 = int(_倾倒剩余[0])
	if 取 >= 0:
		_倾倒选.append(取)


func _倾倒问选() -> void:
	_倾倒剩余 = []
	for c: Variant in _倾倒牌:
		if not _倾倒选.has(int(c)):
			_倾倒剩余.append(int(c))
	var 选项: Array = []
	for i: int in range(_倾倒剩余.size()):
		var 牌: GCard = Data.get_card(int(_倾倒剩余[i]))
		if 牌 == null:
			continue
		选项.append({
			"value": i + 1,
			"label": "%s %s" % [牌.card_name, GConst.element_to_chinese(牌.element_enum())],
			"card_id": int(_倾倒剩余[i]),
		})
	询问(player.id, TIAN_PING_QING_DAO, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], false,
		0, -1, [], -1, {})


# ============================================================
# 神之审判：回合结束时两侧都 >2
# ============================================================
func _神之审判() -> int:
	if _审判阶段 == 0:
		if 张数(左) <= 2 or 张数(右) <= 2:
			return SUCCESS
		_审判阶段 = 1
		询问(player.id, SHEN_ZHI_SHEN_PAN, 0, 2, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, 全部角色(), -1, {}, 2, GConst.HarmType.Attack)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	_审判阶段 = 0
	if args.is_empty() or dsts.size() < 2:
		return SUCCESS
	var 甲: int = int(dsts[0])
	var 乙: int = int(dsts[1])
	if 甲 == 乙 or engine.p(甲) == null or engine.p(乙) == null:
		engine.报错("【神之审判】目标不合法", player.id)
		return SUCCESS
	notice_skill(SHEN_ZHI_SHEN_PAN, [甲, 乙])
	_移除侧(左)
	_移除侧(右)
	engine.push_harm({"src": player.id, "dst": 甲, "point": 2,
		"cause": SHEN_ZHI_SHEN_PAN, "type": GConst.HarmType.Attack})
	engine.push_harm({"src": player.id, "dst": 乙, "point": 2,
		"cause": SHEN_ZHI_SHEN_PAN, "type": GConst.HarmType.Attack})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 天罪：横置期间主动攻击命中②，把 2 张基本牌分别放到左右天平上
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	if not _天罪中 or not player.tap:
		return SUCCESS
	if _天罪阶段 == 2:
		_天罪阶段 = 0
		step = STEP_DONE
		return _收伤害目标(take_skill_reply_full())
	if _天罪阶段 == 1:
		var rc: int = _天罪放牌()
		if rc == WAIT:
			return WAIT
		step = STEP_DONE
		return rc
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	var 牌们: Array = _基本手牌()
	if 牌们.size() < 2:
		return SUCCESS
	_天罪阶段 = 1
	step = 1
	询问(player.id, TIAN_ZUI, 2, 0, GConst.CardSource.Hand, [], 0, "", 牌们, true, 0, -1, [], -1, {})
	return WAIT


func _天罪放牌() -> int:
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	_天罪阶段 = 0
	if args.is_empty() or cards.size() != 2:
		return SUCCESS
	var 甲: int = int(cards[0])
	var 乙: int = int(cards[1])
	if 甲 == 乙 or not player.has_hand_card(甲) or not player.has_hand_card(乙):
		engine.报错("【天罪】提交的牌不合法", player.id)
		return SUCCESS
	notice_skill(TIAN_ZUI, [player.id])
	engine.take_from_hand(player.id, [甲, 乙])
	_放牌(左, 甲)
	_放牌(右, 乙)
	if _伤待选 > 0:
		_天罪阶段 = 2
		_问伤害目标()
		return WAIT
	return SUCCESS


# ============================================================
# 罪迟必到（法术·必杀）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != ZUI_CHI_BI_DAO:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != ZUI_CHI_BI_DAO:
		return GConst.GE_INVALID_ACTION
	if _罪迟阶段 == 0:
		notice_skill(ZUI_CHI_BI_DAO, [player.id])
		player.remove_energy(1)
		_本回合禁罪 = true
		_罪迟剩余 = player.token_num(罪槽)
		player.clear_token(罪槽)
		_罪迟阶段 = 1
		engine._broadcast_game()
	if _罪迟阶段 == 2:
		_罪迟阶段 = 1
		var rc: int = _收伤害目标(take_skill_reply_full())
		if rc != SUCCESS:
			return rc
	# 逐张放：每张都要选一张基本牌 + 放哪一侧
	while _罪迟剩余 > 0:
		if not engine.has_reply():
			询问(player.id, ZUI_CHI_BI_DAO, 0, 0, GConst.CardSource.Hand,
				_放牌选项(ZUI_CHI_BI_DAO), 0, "", [], true, 0, -1, [], -1, {})
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var cards: Array = r.get("card_ids", [])
		if args.is_empty() or cards.is_empty():
			_罪迟阶段 = 0
			_罪迟剩余 = 0
			return SUCCESS
		var 侧: int = int(args[0])
		var 牌: int = int(cards[0])
		if not player.has_hand_card(牌) or not _是基本牌(牌) or 侧 < 0 or 侧 > 1:
			engine.报错("【罪迟必到】提交的牌或天平不合法", player.id)
			_罪迟阶段 = 0
			_罪迟剩余 = 0
			return SUCCESS
		engine.take_from_hand(player.id, [牌])
		_放牌(侧, 牌)
		_罪迟剩余 -= 1
		if _伤待选 > 0:
			_罪迟阶段 = 2
			_问伤害目标()
			return WAIT
	_罪迟阶段 = 0
	return SUCCESS


## 罪迟必到在「罪灭之左」伤害结算完后要回来继续放剩下的牌
func 技能URGENT后重入(action: Dictionary = {}) -> bool:
	return int(action.get("action_id", 0)) == ZUI_CHI_BI_DAO and _罪迟阶段 == 1


# ============================================================
# 罪灭之左的伤害目标
# ============================================================
func _问伤害目标() -> void:
	询问(player.id, ZUI_MIE_ZHI_ZUO, 0, _伤待选, GConst.CardSource.Hand, [], 0, "", [], false,
		0, -1, 敌人(), -1, {}, 1, GConst.HarmType.Attack)


func _收伤害目标(r: Dictionary) -> int:
	var dsts: Array = r.get("dst_ids", [])
	if dsts.size() != _伤待选:
		engine.报错("【罪灭之左】选的目标数不对", player.id)
		_伤待选 = 0
		return SUCCESS
	for d: Variant in dsts:
		engine.push_harm({"src": player.id, "dst": int(d), "point": 1,
			"cause": ZUI_MIE_ZHI_ZUO, "type": GConst.HarmType.Attack})
	_伤待选 = 0
	engine._broadcast_game()
	return URGENT


# ============================================================
# 天平工具
# ============================================================
func 张数(侧: int) -> int:
	var 表: Dictionary = engine.取场卡(天平名[侧])
	return (表.get("pile", []) as Array).size() if not 表.is_empty() else 0


func _是基本牌(cid: int) -> bool:
	var 牌: GCard = Data.get_card(cid)
	if 牌 == null:
		return false
	var 名: int = 牌.card_name_enum()
	return 名 >= GConst.CardName.Poison and 名 <= GConst.CardName.HolyLight


func _基本手牌() -> Array:
	var out: Array = []
	for cid: int in player.hand_cards:
		if _是基本牌(cid):
			out.append(cid)
	return out


func _加罪(n: int) -> void:
	if _本回合禁罪:
		return
	player.add_token(罪槽, n)


## 把一张牌放到某一侧天平上（替罪羔羊 / 罪灭之左都在这里结算）
func _放牌(侧: int, 牌: int) -> void:
	var 表: Dictionary = engine.取场卡(天平名[侧])
	if 表.is_empty():
		return
	var 牌对象: GCard = Data.get_card(牌)
	var 系: int = 牌对象.element_enum() if 牌对象 != null else 0
	var 已有: Array = (表.get("pile", []) as Array).duplicate()
	if 已有.size() >= 3:
		# 单侧上限 3（替罪羔羊）：正常流程在选择时就已排除，这里拦硬提交
		player.add_hand_cards([牌])
		engine.报错("【天平】这一侧已经放满 3 张", player.id)
		return
	# 替罪羔羊：新牌与这一侧已有的牌不同系 → 移除该侧所有牌，你 +1【罪】
	if not 已有.is_empty() and int(表.get("element", -1)) != 系:
		_移除侧(侧)
		_加罪(1)
		已有 = []
	已有.append(牌)
	表["pile"] = 已有
	表["counter"] = 已有.size()
	表["element"] = 系
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [牌], "is_real": true,
	})
	engine._broadcast_game()
	# 罪灭之左：左侧牌数增加且增加后 >1 → 对（X-1）名目标对手各 1 点攻击伤害
	if 侧 == 左 and 已有.size() > 1:
		_伤待选 = 已有.size() - 1


## 移除某一侧天平上的所有牌（进弃牌堆）；右侧一次移除 >1 张时 +1 治疗（圣方之右）
func _移除侧(侧: int) -> void:
	var 表: Dictionary = engine.取场卡(天平名[侧])
	if 表.is_empty():
		return
	var 牌们: Array = (表.get("pile", []) as Array).duplicate()
	if 牌们.is_empty():
		return
	表["pile"] = []
	表["counter"] = 0
	表["element"] = -1
	engine.to_discard(牌们, {"owner": player.id, "source": "other", "cause": SHEN_ZHI_TIAN_PING})
	if 侧 == 右 and 牌们.size() > 1:
		notice_skill(SHENG_FANG_ZHI_YOU, [player.id])
		施加治疗(player.id, 1)
	engine._broadcast_game()


## 「放 1 张牌 + 选哪一侧」的选项（每项自带 need_card=1）
func _放牌选项(技能号: int) -> Array:
	var 基本: Array = _基本手牌()
	var out: Array = []
	for 侧: int in [左, 右]:
		out.append({
			"value": 侧,
			"label": GConst.按钮原文(技能号, 侧),
			"text": GConst.按钮原文(技能号, 侧),
			"need_card": 1,
			"cards": 基本,
			"enabled": not 基本.is_empty() and 张数(侧) < 3,
		})
	return out


func 敌人() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color:
			out.append(pid)
	return out


## 目标队友：按术语表**不含自己**（原文写「含自己」才含）
func 队友() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color == player.color and p0.id != player.id:
			out.append(pid)
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out

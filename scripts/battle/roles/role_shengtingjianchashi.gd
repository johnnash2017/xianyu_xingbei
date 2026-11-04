extends BattleRole
## 圣庭检察士（39）：狂信徒 / 裁决论定 / 恩典神授 / 净化之术 / 庇护领域 / 裁决者 / 神圣鞭策
##
## 【裁决】＝0 号指示物（角色表 0:裁决:3）。
## 【异端裁决所】＝场卡（F1）：id = "异端裁决所"，owner = 自己，counter = 它拥有的【治疗】点数。
##
## 口径：
## 1. 【狂信徒】开局放【异端裁决所】；「我方队友存在圣类命格时治疗上限 +1」每次自己回合开始按队友重算
##    （队友可能被替换 → 不能只在 setup 里加一次）。
## 2. 【裁决论定】用 F3 治疗溢出钩子：我方角色治疗溢出 → 裁决所 +1 治疗，若真的加了 → 你 +1 水晶。
## 3. 【恩典神授】的时机是「你执行【提炼】时」，但引擎的 p_before_extract 是同步钩子（不能等待玩家），
##    所以放在 p_after_extract 里问（星石已经进手，发动时代价 + 全部转交给目标队友）。
##    代价两种：移除我方角色合计 2【治疗】（先自己后队友，按座位顺序）或 裁决所 3【治疗】；
##    哪种付得起就用哪种，付不起就问都不问。
## 4. 【庇护领域】在 p_timeline_3（伤害结算前③）结算，本次伤害 -1（最少 0），你 +1【裁决】。
## 5. 【神圣鞭策】的 X 由玩家选（1~裁决数），然后逐名指定 X 名目标角色各摸 1 张，最后你弃 X 张。

const KUANG_XIN_TU: int = 3901
const CAI_JUE_LUN_DING: int = 3902
const EN_DIAN_SHEN_SHOU: int = 3903
const JING_HUA_ZHI_SHU: int = 3904
const BI_HU_LING_YU: int = 3905
const CAI_JUE_ZHE: int = 3906
const SHEN_SHENG_BIAN_CE: int = 3907

const CAI_SLOT: int = 0
const 裁决所名: String = "异端裁决所"

## 攻击目标（【狂信徒】：攻击行动结束时给目标角色 +1 治疗）
var _攻击目标: int = -1
## 恩典神授的目标队友
var _恩典队友: int = -1
## 神圣鞭策的 X 与已选目标
var _鞭策X: int = 0
var _鞭策目标: Array[int] = []
var _鞭策下标: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【狂信徒】：游戏初始拥有【异端裁决所】
	if not engine.有场卡(裁决所名):
		engine.加场卡({
			"id": 裁决所名, "owner": player.id, "attached": -1,
			"counter": 0, "counter_max": 0, "state": 0,
		})
	_重算治疗上限()


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 裁决: int = player.token_num(CAI_SLOT)
	var 全体: Array[int] = _全体角色()
	return [
		{
			# 裁决者是「启动」：技能类型必须是 SpecialSkill（引擎按这个 + is_free_skill 判启动），
			# 写成 MagicSkill 会绕开「每回合一个启动技」，还会去消耗别人给的额外法术行动
			"type": GConst.ActionType.SpecialSkill,
			"id": CAI_JUE_ZHE,
			"enabled": player.get_energy() >= 1,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": SHEN_SHENG_BIAN_CE,
			"need_card": 0,
			"targets": 全体,
			"enabled": 裁决 >= 1 and player.get_energy() >= 1 and player.hand_cards.size() >= 1,
		},
	]


## 【裁决者】是「启动」技能：不消耗本回合行动，结算完重新进入行动阶段
func is_free_skill(skill_id: int) -> bool:
	return skill_id == CAI_JUE_ZHE


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != CAI_JUE_ZHE:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != CAI_JUE_ZHE:
		return EMPTY_HANDLE
	# 启动技每回合只能发动一个（引擎也会在行动入口拦；这里防直接调用绕过）
	if player.boot_skill_used or player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	player.boot_skill_used = true
	player.remove_energy(1)
	notice_skill(CAI_JUE_ZHE, [player.id])
	player.add_token(CAI_SLOT, 1)
	engine.场卡加计数(裁决所名, 2)
	engine._broadcast_game()
	return SUCCESS


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != SHEN_SHENG_BIAN_CE:
		return GConst.GE_INVALID_ACTION
	if player.token_num(CAI_SLOT) < 1 or player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	if player.hand_cards.is_empty():
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != SHEN_SHENG_BIAN_CE:
		return EMPTY_HANDLE
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	player.remove_energy(1)
	notice_skill(SHEN_SHENG_BIAN_CE, [player.id])
	_鞭策X = 0
	_鞭策目标 = []
	_鞭策下标 = 0
	_鞭策步 = 1
	engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
	return URGENT

var _鞭策步: int = 0


# ============================================================
# 3901 狂信徒
# ============================================================
## 自己的回合开始：按队友命格重算治疗上限；清攻击目标
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_重算治疗上限()
		_攻击目标 = -1
	return SUCCESS


## 记下攻击目标，供行动结束时 +1 治疗用
func p_before_attack(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		_攻击目标 = int(ctx.get("dst", -1))
	return SUCCESS


## 你的【攻击行动】结束时：目标角色 +1【治疗】
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if str(ctx.get("kind", "")) != "attack":
		return SUCCESS
	if _攻击目标 < 0:
		return SUCCESS
	var dst: BattlePlayer = engine.p(_攻击目标)
	_攻击目标 = -1
	if dst == null:
		return SUCCESS
	notice_skill(KUANG_XIN_TU, [dst.id])
	施加治疗(dst.id, 1)
	return SUCCESS


## 我方队友存在圣类命格时：你的治疗上限 +1
func _重算治疗上限() -> void:
	var 有圣: bool = false
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp == null or pp.id == player.id or pp.color != player.color:
			continue
		if Data.role_fate_pattern(pp.role_id) == "圣":
			有圣 = true
			break
	player.cross_max = GConst.CROSS_MAX + (1 if 有圣 else 0)


# ============================================================
# 3902 裁决论定：我方目标角色【治疗】溢出时
# ============================================================
func p_heal_overflow(ctx: Dictionary) -> int:
	var pid: int = int(ctx.get("player", -1))
	var 溢出者: BattlePlayer = engine.p(pid)
	if 溢出者 == null or 溢出者.color != player.color:
		return SUCCESS
	var 前: int = int(engine.取场卡(裁决所名).get("counter", 0))
	engine.场卡加计数(裁决所名, 1)
	var 后: int = int(engine.取场卡(裁决所名).get("counter", 0))
	if 后 <= 前:
		return SUCCESS
	notice_skill(CAI_JUE_LUN_DING, [pid])
	player.set_crystal(player.crystal + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 3903 恩典神授：提炼后把所得转交目标队友
# ============================================================
func p_after_extract(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if bool(ctx.get("is_heaven", false)):
		return SUCCESS
	var 宝石: int = int(ctx.get("gem", 0))
	var 水晶: int = int(ctx.get("crystal", 0))
	if 宝石 + 水晶 <= 0:
		return SUCCESS
	if not _恩典可付():
		return SUCCESS
	if _恩典步 != 0 and not engine.has_reply():
		# 正在等这一问的回复时（_恩典步 == 1 且有回复）要放行到下面 take，
		# 否则回复回来就被这句挡住、技能静默不结算
		return SUCCESS
	_恩典步 = 1
	_恩典宝石 = 宝石
	_恩典水晶 = 水晶
	if not engine.has_reply():
		询问(player.id, EN_DIAN_SHEN_SHOU, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
			"是否发动【恩典神授】：把本次提炼的星石全部交给目标队友（代价：移除我方角色合计 2【治疗】或【异端裁决所】3【治疗】）？")
		return WAIT
	if not take_skill_reply():
		_恩典步 = 0
		return SUCCESS
	_付恩典代价()
	_恩典步 = 2
	engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
	return URGENT

var _恩典步: int = 0
var _恩典宝石: int = 0
var _恩典水晶: int = 0


## 恩典神授付得起吗：裁决所 ≥3 或 我方角色治疗合计 ≥2
func _恩典可付() -> bool:
	if int(engine.取场卡(裁决所名).get("counter", 0)) >= 3:
		return true
	var 合计: int = 0
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp != null and pp.color == player.color:
			合计 += pp.cross_num
	return 合计 >= 2


## 付代价：优先裁决所的 3 治疗，其次我方角色合计 2 治疗（先自己、再按座位顺序）
func _付恩典代价() -> void:
	var 所: Dictionary = engine.取场卡(裁决所名)
	if int(所.get("counter", 0)) >= 3:
		engine.场卡加计数(裁决所名, -3)
		return
	var 需: int = 2
	var 序: Array[int] = [player.id]
	for pid: int in engine.order:
		if pid != player.id and engine.p(pid) != null and engine.p(pid).color == player.color:
			序.append(pid)
	for pid: int in 序:
		if 需 <= 0:
			break
		var pp: BattlePlayer = engine.p(pid)
		if pp == null:
			continue
		var 扣: int = mini(pp.cross_num, 需)
		if 扣 > 0:
			pp.sub_cross_num(扣)
			需 -= 扣


# ============================================================
# 3904 净化之术：你承受伤害⑥并结算完成后
# ============================================================
func p_harm_end(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if _净华步 != 0 and not engine.has_reply():
		# 等回复期间（_净华步 == 1 且有回复）放行到下面 take
		return SUCCESS
	var 法术牌: Array[int] = magic_hand_ids()
	if 法术牌.is_empty():
		return SUCCESS
	_净华步 = 1
	_净华牌 = 法术牌
	if not engine.has_reply():
		询问(player.id, JING_HUA_ZHI_SHU, 1, 0, GConst.CardSource.Hand, [], 1, "magic", [], true,
			0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
			"是否发动【净化之术】：弃 1 张法术牌【展示】，你 +1【治疗】并摸 1 张牌，然后移除【异端裁决所】1 点【治疗】？")
		return WAIT
	if not take_skill_reply():
		_净华步 = 0
		return SUCCESS
	_净华步 = 2
	engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
	return URGENT

var _净华步: int = 0
var _净华牌: Array[int] = []


# ============================================================
# 3905 庇护领域：我方目标角色受到伤害时③
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	if int(engine.取场卡(裁决所名).get("counter", 0)) < 3:
		return SUCCESS
	if bool(harm.get("庇护领域已减", false)):
		return SUCCESS
	if _庇护步 != 0 and not engine.has_reply():
		# 等回复期间（_庇护步 == 1 且有回复）放行到下面 take
		return SUCCESS
	_庇护步 = 1
	_庇护伤害 = harm
	if not engine.has_reply():
		询问(player.id, BI_HU_LING_YU, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
			"是否发动【庇护领域】：移除【异端裁决所】3 点【治疗】，本次伤害 -1，你 +1【裁决】？")
		return WAIT
	var 发动: bool = take_skill_reply()
	_庇护步 = 0
	if not 发动:
		return SUCCESS
	engine.场卡加计数(裁决所名, -3)
	player.add_token(CAI_SLOT, 1)
	notice_skill(BI_HU_LING_YU, [int(harm.get("dst", -1))])
	_庇护伤害["point"] = maxi(int(_庇护伤害.get("point", 0)) - 1, 0)
	_庇护伤害["庇护领域已减"] = true
	engine._broadcast_game()
	return SUCCESS

var _庇护步: int = 0
var _庇护伤害: Dictionary = {}


# ============================================================
# 统一的小段询问钩子：神圣鞭策 / 恩典神授 / 净化之术
# ============================================================
func p_sheng_ting_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 神圣鞭策：选 X
	if _鞭策步 == 1:
		if not engine.has_reply():
			var 选项: Array = []
			for i: int in range(1, player.token_num(CAI_SLOT) + 1):
				选项.append(i)
			询问(player.id, SHEN_SHENG_BIAN_CE, 0, 0, GConst.CardSource.Hand, [0] + 选项, 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【神圣鞭策】：移除 X 点【裁决】（选择 X）")
			return WAIT
		# 阶段在取完回复之后再推进：重入时 _鞭策步 仍是 1，才能走到这里
		var r: Dictionary = take_skill_reply_full()
		_鞭策步 = 2
		var args: Array = r.get("args", [])
		var x: int = int(args[0]) if not args.is_empty() else 0
		if x <= 0 or not player.remove_token(CAI_SLOT, x):
			_鞭策步 = 0
			return SUCCESS
		_鞭策X = x
		_鞭策目标 = []
		_鞭策步 = 3
		engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
		return URGENT
	# 神圣鞭策：逐名选目标（X 名，不能重复）
	if _鞭策步 == 3:
		if _鞭策目标.size() >= _鞭策X:
			for pid: int in _鞭策目标:
				engine.push_draw(pid, 1, SHEN_SHENG_BIAN_CE)
			_鞭策步 = 4
			engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
			return URGENT
		if not engine.has_reply():
			var 池: Array[int] = []
			for pid: int in _全体角色():
				if not _鞭策目标.has(pid):
					池.append(pid)
			询问(player.id, SHEN_SHENG_BIAN_CE, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, 池, -1, {}, 0, 0, false, [], true, -1, 0,
				"【神圣鞭策】：指定 1 名目标角色摸 1 张牌（还可指定 %d 名）" % (_鞭策X - _鞭策目标.size()))
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		var ds: Array = r2.get("dst_ids", [])
		if ds.size() == 1 and not _鞭策目标.has(int(ds[0])):
			_鞭策目标.append(int(ds[0]))
		engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
		return URGENT
	# 神圣鞭策：你弃 X 张牌
	if _鞭策步 == 4:
		var 需: int = mini(_鞭策X, player.hand_cards.size())
		if 需 <= 0:
			_鞭策步 = 0
			_鞭策X = 0
			return SUCCESS
		if not engine.has_reply():
			询问(player.id, SHEN_SHENG_BIAN_CE, 需, 0, GConst.CardSource.Hand, [], 需, "", [], false,
				0, player.id, [], 需, {}, 0, 0, false, [], true, -1, 0,
				"【神圣鞭策】：弃 %d 张牌" % 需)
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var cards: Array = r3.get("card_ids", [])
		var 弃: Array = []
		for c: Variant in cards:
			if 弃.size() < 需 and player.有手牌(int(c)):
				弃.append(int(c))
		if not 弃.is_empty():
			engine.take_from_hand(player.id, 弃, false)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": SHEN_SHENG_BIAN_CE})
			engine._log_discard(player.id, 弃, false)
		_鞭策步 = 0
		_鞭策X = 0
		_鞭策目标 = []
		return SUCCESS
	# 恩典神授：选目标队友
	if _恩典步 == 2:
		if not engine.has_reply():
			询问(player.id, EN_DIAN_SHEN_SHOU, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, ally_ids() if not ally_ids().is_empty() else _全体角色(), -1, {}, 0, 0, false, [], true, -1, 0,
				"【恩典神授】：把本次提炼的星石全部交给哪名目标队友？")
			return WAIT
		var r4: Dictionary = take_skill_reply_full()
		var ds4: Array = r4.get("dst_ids", [])
		_恩典步 = 3
		if ds4.size() == 1:
			_恩典队友 = int(ds4[0])
			engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
			return URGENT
		_恩典步 = 0
		return SUCCESS
	# 恩典神授：转交星石 + 你弃 1 张牌
	if _恩典步 == 3:
		_恩典步 = 4
		var dst: BattlePlayer = engine.p(_恩典队友)
		if dst != null:
			var 给: int = mini(_恩典宝石, player.gem)
			player.set_gem(player.gem - 给)
			dst.set_gem(dst.gem + 给)
			var 给水: int = mini(_恩典水晶, player.crystal)
			player.set_crystal(player.crystal - 给水)
			dst.set_crystal(dst.crystal + 给水)
			notice_skill(EN_DIAN_SHEN_SHOU, [dst.id])
			engine._broadcast_game()
		_恩典宝石 = 0
		_恩典水晶 = 0
		_恩典队友 = -1
		if player.hand_cards.is_empty():
			_恩典步 = 0
			return SUCCESS
		engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
		return URGENT
	# 恩典神授：弃 1 张牌；圣命格可【展示】换 1 点法术伤害
	if _恩典步 == 4:
		if not engine.has_reply():
			询问(player.id, EN_DIAN_SHEN_SHOU, 1, 0, GConst.CardSource.Hand, [], 1, "", [], true,
				0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
				"【恩典神授】：弃 1 张牌（若为圣类命格可【展示】）")
			return WAIT
		var r5: Dictionary = take_skill_reply_full()
		var cards5: Array = r5.get("card_ids", [])
		_恩典步 = 0
		if cards5.is_empty() or not player.有手牌(int(cards5[0])):
			return SUCCESS
		var cid: int = int(cards5[0])
		var 圣: bool = Data.get_card(cid) != null \
			and Data.get_card(cid).fate_pattern_enum() == GConst.FatePattern.Holy
		engine.take_from_hand(player.id, [cid], false)
		if 圣:
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": [cid], "is_real": true,
			})
			# 先压「伤害询问」的钩子、再走统一弃牌入口：牌按标准弃置先进弃牌堆
			# （触发 F6 弃牌前拦截，如噬神者【渗蚀】），回头再问是否造成法术伤害
			engine.push(BattleEngine.SHook.new("p_sheng_ting_ask", {"player": player.id}, []))
			engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": EN_DIAN_SHEN_SHOU})
			engine._log_discard(player.id, [cid], false)
			_恩典步 = 5
			return URGENT
		engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": EN_DIAN_SHEN_SHOU})
		engine._log_discard(player.id, [cid], false)
		return SUCCESS
	# 恩典神授：展示后的法术伤害
	if _恩典步 == 5:
		if not engine.has_reply():
			询问(player.id, EN_DIAN_SHEN_SHOU, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
				"【恩典神授】：是否对目标对手造成 1 点法术伤害？")
			return WAIT
		var r6: Dictionary = take_skill_reply_full()
		var ds6: Array = r6.get("dst_ids", [])
		_恩典步 = 0
		if ds6.size() == 1:
			engine.push_harm({
				"src": player.id, "dst": int(ds6[0]), "point": 1,
				"cause": EN_DIAN_SHEN_SHOU, "type": GConst.HarmType.Magic,
			})
			return URGENT
		return SUCCESS
	# 净化之术：弃 1 张法术牌【展示】→ +1 治疗、摸 1、裁决所 -1 治疗
	if _净华步 == 2:
		if not engine.has_reply():
			询问(player.id, JING_HUA_ZHI_SHU, 1, 0, GConst.CardSource.Hand, [], 1, "magic", [], true,
				0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
				"【净化之术】：弃 1 张法术牌【展示】")
			return WAIT
		# 阶段在取完回复之后再推进：重入时 _净华步 仍是 2
		var r7: Dictionary = take_skill_reply_full()
		_净华步 = 3
		var cards7: Array = r7.get("card_ids", [])
		_净华步 = 0
		if cards7.is_empty() or not player.有手牌(int(cards7[0])):
			return SUCCESS
		var cid7: int = int(cards7[0])
		var 卡7: GCard = Data.get_card(cid7)
		if 卡7 == null or not 卡7.is_magic():
			return SUCCESS
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid7], "is_real": true,
		})
		engine.take_from_hand(player.id, [cid7], false)
		engine.to_discard([cid7], {"owner": player.id, "source": "hand", "cause": JING_HUA_ZHI_SHU})
		engine._log_discard(player.id, [cid7], false)
		施加治疗(player.id, 1)
		engine.push_draw(player.id, 1, JING_HUA_ZHI_SHU)
		engine.场卡加计数(裁决所名, -1)
		return URGENT
	return SUCCESS


# ============================================================
# 小工具
# ============================================================
func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out

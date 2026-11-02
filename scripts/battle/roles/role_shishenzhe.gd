extends BattleRole
## 噬神者（79）：御刃 / 侵刻 / 噬灭 / 殇灭 / 同调 / 魔刃 / 异刃 / 渗蚀 / 共振 / 诸神终焉
##
## 【魔刃】= 卡表#1005、【异刃】= 卡表#1006（血命格攻击牌、虚拟牌不进牌库）。
## "在场"＝在任意玩家手牌里；不在场时【御刃】可以从场外把它们加入手牌。
##
## 口径：
## 1. 【魔刃】/【异刃】是具体的牌，用【攻击技能】入口打出（与剑之魔女 3805「视为风系」
##    同一条路）：点技能栏里的【魔刃】/【异刃】按钮（或直接点手牌，见 battle_mobile），
##    二级技能栏选「魔刃·火 / 魔刃·水 / 异刃·雷 / 异刃·风」，用对应系别的虚拟攻击牌
##    （87 火焰斩 / 129 水涟斩 / 108 雷光斩 / 66 风神斩）发起攻击。技能表里没有「刃」这个被动，
##    只有【魔刃】7909 /【异刃】7910 /【渗蚀】7911 三条被动说明。
## 2. 【渗蚀】：使用/打出【魔刃】/【异刃】时，由噬神者对该牌的使用者造成 3 点法术伤害
##    （【同调】后 1 点），然后移除该牌（不进弃牌堆）；牌因技能放到角色旁时改为对该角色 1 点。
## 3. 【侵刻】：命中时把这次用的【魔刃】/【异刃】加入攻击目标手牌（所以它不会再被【渗蚀】移除）。
## 4. 【噬灭】/【殇灭】的「使用【魔刃】/【异刃】攻击时①」靠 _本次刃 判定（攻击技能里记录），
##    不按牌面判 —— 因为攻击实际上是用虚拟牌结算的。
## 5. 【共振】消耗 1 点能量（技能表【水晶】口径）；【诸神终焉】消耗 1 颗真宝石（【宝石】口径）。

const YU_REN: int = 7901
const QIN_KE: int = 7902
const SHI_MIE: int = 7903
const SHANG_MIE: int = 7904
const TONG_DIAO: int = 7905
const MO_REN_ATTACK: int = 7912   # 【魔刃】攻击入口（技能表里不进角色技能说明）
const YI_REN_ATTACK: int = 7913   # 【异刃】攻击入口
const SHEN_SHI: int = 7911        # 【渗蚀】被动（弃牌触发 / 播报用）
const GONG_ZHEN: int = 7907
const ZHU_SHEN_ZHONG_YAN: int = 7908

const MO_REN_CARD: int = 1005
const YI_REN_CARD: int = 1006
const 渗蚀伤害: int = 3
const 同调伤害: int = 1

## 视为攻击牌用的虚拟牌：系别 → 卡表 id
const 虚拟攻击牌: Dictionary = {
	GConst.CardElement.Fire: 87,
	GConst.CardElement.Water: 129,
	GConst.CardElement.Thunder: 108,
	GConst.CardElement.Wind: 66,
}

## 本次攻击用的【魔刃】/【异刃】是哪一张（0＝普通攻击）
var _本次刃: int = 0          # 本次用的牌实例号（交给侵刻/渗蚀用）
var _本次刃面: int = 0        # 本次用的牌面（MO_REN_CARD / YI_REN_CARD）
## 攻击前的子流程
var _t1_step: int = 0
## 御刃 / 共振 / 诸神终焉 的子流程
var _步: int = 0
var _目标: int = -1
var _共振牌: Array[int] = []


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 敌: Array = enemy_ids()
	var 技能: Array = []
	for 卡: int in _手牌刃():
		var 卡数据: GCard = Data.get_card(卡)
		# 系别已经在手牌里选好（卡牌顶部的火/水、雷/风切换），
		# 攻击入口不再弹「选系别」，直接按卡牌当前系别出手。
		技能.append({
			"type": GConst.ActionType.AttackSkill,
			"id": MO_REN_ATTACK if 卡 == MO_REN_CARD else YI_REN_ATTACK,
			"need_target": 1,
			"targets": 敌,
			"enabled": not 敌.is_empty() and 卡数据 != null and 卡数据.element_enum() > 0,
		})
	# 御刃：和魔弓【魔眼】一样，点技能直接进二级栏选「魔刃 / 异刃」，
	# 可以点「返回」退出，点「确定」才把选中的牌加进手牌（不再走服务端二次询问）。
	var 御刃选项: Array = []
	for 选: int in _御刃可得():
		var 是魔: bool = 选 == 1
		御刃选项.append({
			"text": "魔刃" if 是魔 else "异刃",
			"args": [选],
			# 客户端鼠标指向这个选项时显示对应的两条被动：魔刃/异刃 + 共用的渗蚀
			"技能组": [7909, 7911] if 是魔 else [7910, 7911],
		})
	技能.append({
		"type": GConst.ActionType.SpecialSkill,
		"id": YU_REN,
		"arg_choices": 御刃选项,
		"enabled": not 御刃选项.is_empty(),
	})
	技能.append({
		"type": GConst.ActionType.MagicSkill,
		"id": ZHU_SHEN_ZHONG_YAN,
		"enabled": player.gem >= 1,
	})
	return 技能


func is_free_skill(skill_id: int) -> bool:
	return skill_id == YU_REN


## 攻击入口把本次出牌视为卡牌当前的那个系别：额外行动阶段（如修罗连斩给的火系攻击）
## 客户端据此按当前系别置灰/亮起，服务端也用它过额外行动的元素限制。
func 技能视为系别(action: Dictionary) -> int:
	var aid: int = int(action.get("action_id", 0))
	if aid == MO_REN_ATTACK:
		var 卡: GCard = Data.get_card(MO_REN_CARD)
		return 卡.element_enum() if 卡 != null else 0
	if aid == YI_REN_ATTACK:
		var 卡: GCard = Data.get_card(YI_REN_CARD)
		return 卡.element_enum() if 卡 != null else 0
	return 0


## 【魔刃】/【异刃】的系别在手里切换，不能用普通「出攻击牌」直接打：
## 必须走攻击技能入口 7912/7913（按当前系别）。
## 客户端点手牌会转到对应的技能按钮（见 battle_mobile）；这里兜底挡住直接出牌。
func v_attack(card_id: int, _dst_id: int, _players: Dictionary) -> int:
	var 面: int = GConst.牌号(card_id)
	if 面 == MO_REN_CARD or 面 == YI_REN_CARD:
		return GConst.GE_INVALID_CARDID
	return V_NOT_OVERRIDE


func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var 卡面: int = MO_REN_CARD if aid == MO_REN_ATTACK \
		else (YI_REN_CARD if aid == YI_REN_ATTACK else 0)
	if 卡面 == 0:
		return GConst.GE_INVALID_ACTION
	if not player.has_hand_card(卡面):
		return GConst.GE_HANDCARD_NOT_FOUND
	var 卡数据: GCard = Data.get_card(卡面)
	if 卡数据 == null or not 卡数据.可选元素.has(卡数据.element_enum()):
		return GConst.GE_INVALID_CARDID
	var ds: Array = action.get("dst_ids", [])
	if ds.size() != 1:
		return GConst.GE_INVALID_ACTION
	# 通用攻击限制（挑衅 / 攻击锁定 / 目标同队 / 手里有这张牌）复用基础校验
	var 基础: int = player.base_v_attack(卡面, int(ds[0]), engine.players)
	if 基础 != GConst.GE_SUCCESS:
		return 基础
	var dst: BattlePlayer = engine.p(int(ds[0]))
	if dst == null or dst.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	if dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_attack_skill(action: Dictionary) -> int:
	var 校验: int = v_attack_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var aid: int = int(action.get("action_id", 0))
	var 卡面: int = MO_REN_CARD if aid == MO_REN_ATTACK else YI_REN_CARD
	var 卡数据: GCard = Data.get_card(卡面)
	var 系: int = 卡数据.element_enum() if 卡数据 != null else 0
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	var 实例: int = player.取出实例(player.hand_cards, 卡面)
	if 实例 <= 0:
		return GConst.GE_INVALID_CARDID
	_本次刃 = 实例
	_本次刃面 = 卡面
	notice_skill(aid, [dst], "%s·%s" % [GConst.skill_name(aid), GConst.element_to_chinese(系)])
	# 展示这张牌；**不进弃牌堆**：命中时【侵刻】把它交给目标，否则【渗蚀】把它移出游戏。
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [实例], "is_real": true,
	})
	# 【渗蚀】：噬神者对该牌的使用者（这里是发动者自己）造成 3 点（【同调】后 1 点）法术伤害
	var 伤: int = 同调伤害 if _有同调() else 渗蚀伤害
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 伤,
		"cause": SHEN_SHI, "type": GConst.HarmType.Magic, "virtual_no_fate": true,
	})
	# 用真实系别的虚拟攻击牌发起攻击
	var 虚牌: int = int(虚拟攻击牌.get(系, 87))
	engine.push(BattleEngine.SAttackCard.new(player.id, dst, 虚牌, {
		"src": player.id, "dst": dst, "point": 1, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 虚牌, "is_active": true,
	}))
	return URGENT


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != YU_REN:
		return GConst.GE_INVALID_ACTION
	if not _御刃可得().has(_取选(action)):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 御刃和魔眼一样是「点技能即进二级栏、确认才提交」：选项随 available_skills 下发，
## args[0] = 1 魔刃 / 2 异刃；这里只按提交的选择加牌，不再另开一次询问。
func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != YU_REN:
		return EMPTY_HANDLE
	var 选: int = _取选(action)
	if not _御刃可得().has(选):
		return GConst.GE_INVALID_ACTION
	var 卡: int = MO_REN_CARD if 选 == 1 else YI_REN_CARD
	# 从场外取回来的新一份按配置第一个系别起手（之后在手牌里再切）
	var 卡数据: GCard = Data.get_card(卡)
	if 卡数据 != null and not 卡数据.可选元素.is_empty():
		卡数据.设置当前元素(卡数据.可选元素[0])
		# 当前系别变了：按系别缓存的攻击牌白名单要重算
		engine._规则攻击牌缓存.clear()
	player.add_hand_cards([卡])
	player.boot_skill_used = true
	notice_skill(YU_REN, [player.id])
	engine._broadcast_game()
	return SUCCESS


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != ZHU_SHEN_ZHONG_YAN:
		return GConst.GE_INVALID_ACTION
	if player.gem < 1:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) == ZHU_SHEN_ZHONG_YAN:
		return _p_诸神终焉()
	return EMPTY_HANDLE


# ============================================================
# 7901 御刃：当【魔刃】或【异刃】未在场时，把它们加入你手牌【强制】
# ============================================================
func _御刃可选() -> bool:
	return not _御刃可得().is_empty()


## 御刃本次能拿的牌：1 =【魔刃】、2 =【异刃】，只列「不在任何玩家手里」的。
func _御刃可得() -> Array[int]:
	var 可得: Array[int] = []
	if not _在场刃().has(MO_REN_CARD):
		可得.append(1)
	if not _在场刃().has(YI_REN_CARD):
		可得.append(2)
	return 可得


# ============================================================
# 7902 侵刻：使用【魔刃】/【异刃】攻击命中时，把该卡加入攻击目标手牌
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _本次刃 <= 0:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		return SUCCESS
	notice_skill(QIN_KE, [dst.id])
	dst.add_hand_cards([_本次刃])
	_本次刃 = 0
	_本次刃面 = 0
	engine._broadcast_game()
	return SUCCESS


## 本次攻击结束后清掉「这次用的牌」：没触发【侵刻】时牌已被移出游戏，
## 下一次普通攻击不能再拿它去判【噬灭】/【殇灭】。
func p_after_attack(_ctx: Dictionary) -> int:
	_本次刃 = 0
	_本次刃面 = 0
	return SUCCESS


# ============================================================
# 渗蚀（7909/7910 牌面被动）：牌被弃置时也触发（由任意持有者弃置）
# ============================================================
## 同步预判：这次弃牌里有没有【魔刃】/【异刃】。只在「从手牌弃置」时拦截，
## 避免牌堆 / 盖牌区 / 已经结算过的路径反复触发。
func wants_before_discard(ctx: Dictionary) -> bool:
	if str(ctx.get("source", "")) != "hand":
		return false
	if int(ctx.get("owner", -1)) < 0:
		return false
	for c: Variant in ctx.get("cards", []):
		var 面: int = GConst.牌号(int(c))
		if 面 == MO_REN_CARD or 面 == YI_REN_CARD:
			return true
	return false


## 弃置【魔刃】/【异刃】时：噬神者对该牌的使用者（弃牌者）造成 3 点（【同调】后 1 点）法术伤害。
## 然后让这张牌照常进入弃牌堆（牌面说明里的「移除此牌」＝离开手牌）。
func p_before_discard(ctx: Dictionary) -> int:
	if not wants_before_discard(ctx):
		return SUCCESS
	var 键: String = "_渗蚀弃牌_%d" % player.id
	if bool(ctx.get(键, false)):
		return SUCCESS
	ctx[键] = true
	var dst: int = int(ctx.get("owner", -1))
	if dst < 0:
		return SUCCESS
	var 伤: int = 同调伤害 if _有同调() else 渗蚀伤害
	notice_skill(SHEN_SHI, [dst])
	engine.push_harm({
		"src": player.id, "dst": dst, "point": 伤,
		"cause": SHEN_SHI, "type": GConst.HarmType.Magic, "virtual_no_fate": true,
	})
	return URGENT


# ============================================================
# 7903 噬灭 / 7904 殇灭：攻击时①额外弃 1 张指定系别的牌
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _本次刃 <= 0:
		return SUCCESS
	var 是魔: bool = _本次刃面 == MO_REN_CARD
	var 技能: int = SHI_MIE if 是魔 else SHANG_MIE
	var 系表: Array = [GConst.CardElement.Water, GConst.CardElement.Fire] if 是魔 \
		else [GConst.CardElement.Wind, GConst.CardElement.Thunder]
	var 可弃: Array[int] = hand_ids_where(
		func(_cid: int, c: GCard) -> bool: return 系表.has(c.element_enum()))
	if 可弃.is_empty():
		return SUCCESS
	if _t1_step == 0:
		_t1_step = 1
		if not engine.has_reply():
			询问(player.id, 技能, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"是否发动【%s】：额外弃 1 张%s系牌【展示】？" % [
					GConst.skill_name(技能),
					"水/火" if 是魔 else "风/雷"])
			return WAIT
	if _t1_step != 1:
		return SUCCESS
	_t1_step = 0
	if not take_skill_reply():
		return SUCCESS
	_噬灭技能 = 技能
	_噬灭目标 = int(ctx.get("dst", -1))
	_步 = 2
	engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
	return URGENT

var _噬灭技能: int = 0
var _噬灭目标: int = -1


## 8903 的子流程：弃牌 → 移除目标（或目标外 1 名敌方）1【治疗】
func p_shi_shen_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	match _步:
		2:  # 噬灭 / 殇灭：选弃哪张
			var 系表: Array = [GConst.CardElement.Water, GConst.CardElement.Fire] \
				if _噬灭技能 == SHI_MIE else [GConst.CardElement.Wind, GConst.CardElement.Thunder]
			var 可弃: Array[int] = hand_ids_where(
				func(_cid: int, c: GCard) -> bool: return 系表.has(c.element_enum()))
			if 可弃.is_empty():
				_步 = 0
				return SUCCESS
			if not engine.has_reply():
				询问(player.id, _噬灭技能, 1, 0, GConst.CardSource.Hand, [], 1, "", [], false,
					0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
					"【%s】：弃 1 张%s系牌【展示】" % [
						GConst.skill_name(_噬灭技能), "水/火" if _噬灭技能 == SHI_MIE else "风/雷"])
				return WAIT
			var r2: Dictionary = take_skill_reply_full()
			var cards: Array = r2.get("card_ids", [])
			_步 = 0
			if cards.is_empty() or not player.有手牌(int(cards[0])):
				return SUCCESS
			var cid: int = int(cards[0])
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": [cid], "is_real": true,
			})
			engine.take_from_hand(player.id, [cid], false)
			engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": _噬灭技能})
			engine._log_discard(player.id, [cid], false)
			notice_skill(_噬灭技能, [_噬灭目标])
			if _噬灭技能 == SHI_MIE:
				_移除治疗(_噬灭目标, 1)
				return SUCCESS
			# 殇灭：目标之外 1 名敌方角色
			var 池: Array[int] = []
			for pid: int in enemy_ids():
				if pid != _噬灭目标:
					池.append(pid)
			if 池.is_empty():
				return SUCCESS
			_步 = 3
			_殇灭池 = 池
			engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
			return URGENT
		3:  # 殇灭：选目标外的 1 名敌方
			if not engine.has_reply():
				询问(player.id, SHANG_MIE, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
					0, -1, _殇灭池, -1, {}, 0, 0, false, [], true, -1, 0,
					"【殇灭】：指定目标外 1 名敌方角色，移除其 1【治疗】")
				return WAIT
			var r3: Dictionary = take_skill_reply_full()
			var ds: Array = r3.get("dst_ids", [])
			_步 = 0
			if ds.size() == 1:
				_移除治疗(int(ds[0]), 1)
			return SUCCESS
		4:  # 共振：选 2~3 张同系牌弃之
			if not engine.has_reply():
				var 同系: Array[int] = _同系手牌(_共振系)
				询问(player.id, GONG_ZHEN, 2, 0, GConst.CardSource.Hand, [], 3, "same", 同系, true,
					0, player.id, [], 3, {}, 0, 0, false, [], true, -1, 0,
					"【共振】：弃 2~3 张同系牌【展示】")
				return WAIT
			var r4: Dictionary = take_skill_reply_full()
			var cards4: Array = r4.get("card_ids", [])
			var 弃: Array = []
			for c4: Variant in cards4:
				if 弃.size() < 3 and player.有手牌(int(c4)):
					弃.append(int(c4))
			_步 = 0
			if 弃.size() < 2:
				return SUCCESS
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": 弃, "is_real": true,
			})
			engine.take_from_hand(player.id, 弃, false)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": GONG_ZHEN})
			engine._log_discard(player.id, 弃, false)
			# 把未在场的【魔刃】和/或【异刃】加入手牌
			var 加了: bool = false
			for 卡4: int in [MO_REN_CARD, YI_REN_CARD]:
				if not _在场刃().has(卡4):
					player.add_hand_cards([卡4])
					加了 = true
			notice_skill(GONG_ZHEN, [player.id])
			engine._broadcast_game()
			if not 加了:
				return SUCCESS
			_步 = 5
			engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
			return URGENT
		5:  # 共振：加入手牌后对目标角色 1 点法术伤害
			if not engine.has_reply():
				询问(player.id, GONG_ZHEN, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
					0, -1, _全体角色(), -1, {}, 0, 0, false, [], true, -1, 0,
					"【共振】：对目标角色造成 1 点法术伤害")
				return WAIT
			var r5: Dictionary = take_skill_reply_full()
			var ds5: Array = r5.get("dst_ids", [])
			_步 = 0
			if ds5.size() == 1:
				engine.push_harm({
					"src": player.id, "dst": int(ds5[0]), "point": 1,
					"cause": GONG_ZHEN, "type": GConst.HarmType.Magic,
				})
				return URGENT
			return SUCCESS
	return SUCCESS

var _殇灭池: Array[int] = []
var _共振系: int = 0


# ============================================================
# 7905 同调：触发【渗蚀】时 3 点 → 1 点
# ============================================================
func _有同调() -> bool:
	return true


# ============================================================
# 7907 共振：任何人对你造成法术伤害时③
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty() or int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if bool(harm.get("共振已处理", false)) or _步 != 0:
		return SUCCESS
	if player.get_energy() < 1 or not _有同系两张():
		return SUCCESS
	harm["共振已处理"] = true
	_步 = 4
	_共振系 = _同系两张的系别()
	engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
	# 顺带付代价提示：在选完牌后再扣能量（避免选了又不够）
	engine.push(BattleEngine.SHook.new("p_shi_shen_共振代价", {"player": player.id}, []))
	return URGENT


func p_shi_shen_共振代价(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if player.get_energy() < 1:
		return SUCCESS
	player.remove_energy(1)
	return SUCCESS


## 手里有没有 2 张以上同系牌
func _有同系两张() -> bool:
	return _同系两张的系别() > 0


## 手里有没有 2 张以上同系牌（返回该系别，0＝没有）
func _同系两张的系别() -> int:
	for 系: int in [GConst.CardElement.Fire, GConst.CardElement.Water,
			GConst.CardElement.Thunder, GConst.CardElement.Wind,
			GConst.CardElement.Earth, GConst.CardElement.Light, GConst.CardElement.Darkness]:
		if _同系手牌(系).size() >= 2:
			return 系
	return 0


func _同系手牌(系: int) -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == 系)


# ============================================================
# 7908 诸神终焉：+1 水晶、自伤 2、移除场上【魔刃】【异刃】并伤害原持有者
# ============================================================
func _p_诸神终焉() -> int:
	if player.gem < 1:
		return GConst.GE_INVALID_ACTION
	player.set_gem(player.gem - 1)
	player.set_crystal(player.crystal + 1)
	notice_skill(ZHU_SHEN_ZHONG_YAN, [player.id])
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": ZHU_SHEN_ZHONG_YAN, "type": GConst.HarmType.Magic,
	})
	# 移除场上的【魔刃】/【异刃】，记下原持有者
	var 持有: Array = []
	for 卡: int in [MO_REN_CARD, YI_REN_CARD]:
		for pid: int in engine.order:
			var pp: BattlePlayer = engine.p(pid)
			if pp == null:
				continue
			if pp.有手牌(卡):
				var 实例: int = pp.取出实例(pp.hand_cards, 卡)
				if 实例 > 0:
					持有.append({"pid": pid, "card": 实例})
				break
	var 两张: bool = 持有.size() >= 2
	for i: int in range(持有.size() - 1, -1, -1):
		var 项: Dictionary = 持有[i]
		engine.push_harm({
			"src": player.id, "dst": int(项["pid"]), "point": 3,
			"cause": ZHU_SHEN_ZHONG_YAN, "type": GConst.HarmType.Magic,
		})
	if 两张:
		_步 = 6
		engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
	else:
		_步 = 0
	engine._broadcast_game()
	return URGENT


# ============================================================
# 小工具
# ============================================================
## 手里【魔刃】/【异刃】的牌号
func _手牌刃() -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		var 面: int = GConst.牌号(cid)
		if (面 == MO_REN_CARD or 面 == YI_REN_CARD) and not out.has(面):
			out.append(面)
	return out


## 场上（任意玩家手牌里）有哪些【魔刃】/【异刃】
func _在场刃() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp == null:
			continue
		for 卡: int in [MO_REN_CARD, YI_REN_CARD]:
			if pp.有手牌(卡) and not out.has(卡):
				out.append(卡)
	return out


## 从 action 里取二级栏选择（args[0]，没有就是 0）
func _取选(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	return int(args[0]) if not args.is_empty() else 0


## 移除某角色 1【治疗】
func _移除治疗(pid: int, n: int) -> void:
	var pp: BattlePlayer = engine.p(pid)
	if pp == null or pp.cross_num <= 0:
		return
	pp.sub_cross_num(n)
	engine._broadcast_game()


func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out

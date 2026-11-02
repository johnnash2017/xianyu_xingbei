extends BattleRole
## 噬神者（79）：御刃 / 侵刻 / 噬灭 / 殇灭 / 同调 / 魔刃 / 异刃 / 渗蚀 / 共振 / 诸神终焉
##
## 【魔刃】= 卡表#1005、【异刃】= 卡表#1006（血命格真实攻击牌；编号在 0..149 牌库之外，
## 不加入牌库，但拥有真实系别/命格/手牌实例）。
## "在场"＝在任意玩家手牌里；不在场时【御刃】可以从场外把它们加入手牌。
##
## 口径：
## 1. 【魔刃】/【异刃】是具体的牌，当前系别在手牌右上角切换（fire/water、thunder/wind）；
##    它们**本身就是当前系别的普通攻击牌**，直接点牌选目标打出，不再有攻击技能入口。
##    技能表里没有「刃」这个被动，只有【魔刃】7909 /【异刃】7910 /【渗蚀】7911 三条被动说明。
## 2. 【渗蚀】：使用/打出/弃置【魔刃】/【异刃】时，由噬神者对该牌的使用者造成 3 点法术伤害
##    （【同调】后 1 点），然后通过 `ctx.removed` 把牌移出本次弃牌流程（不进弃牌堆）；
##    牌因技能放到角色旁时改为对该角色 1 点。
## 3. 【侵刻】：命中时把这次用的【魔刃】/【异刃】同一实例加入攻击目标手牌。
## 4. 【噬灭】/【殇灭】的「使用【魔刃】/【异刃】攻击时①」靠 _本次刃 判定，
##    由 p_attack_card 在普通攻击出牌前记录实例。
## 5. 【共振】消耗 1 点能量（技能表【水晶】口径）；【诸神终焉】消耗 1 颗真宝石（【宝石】口径）。

const YU_REN: int = 7901
const QIN_KE: int = 7902
const SHI_MIE: int = 7903
const SHANG_MIE: int = 7904
const TONG_DIAO: int = 7905
const SHEN_SHI: int = 7911        # 【渗蚀】被动（弃牌触发 / 播报用）
const GONG_ZHEN: int = 7907
const ZHU_SHEN_ZHONG_YAN: int = 7908

const MO_REN_CARD: int = 1005
const YI_REN_CARD: int = 1006
const 渗蚀伤害: int = 3
const 同调伤害: int = 1

## 本次攻击用的【魔刃】/【异刃】是哪一张（0＝普通攻击）
var _本次刃: int = 0          # 本次用的牌实例号（交给侵刻/渗蚀用）
var _本次刃面: int = 0        # 本次用的牌面（MO_REN_CARD / YI_REN_CARD）
## 本次攻击的噬灭/殇灭是否已经问过（timeline1 若被重复调用也不能反复弹选牌/反复弃牌）
var _噬灭已处理: bool = false
## 已处理过的盖牌变动序号：钩子返回 URGENT 后引擎会回栈重跑同一个 p_cover_change，
## 同一个 seq 只处理一次，避免渗蚀伤害/移除无限循环。
var _渗蚀盖牌Seq: int = -1
## 御刃 / 共振 / 诸神终焉 的子流程
var _步: int = 0
var _目标: int = -1
var _共振牌: Array[int] = []


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 技能: Array = []
	# 御刃：和魔弓【魔眼】一样，点技能直接进二级栏选「魔刃 / 异刃」，
	# 可以点「返回」退出，点「确定」才把选中的牌加进手牌（不再走服务端二次询问）。
	var 御刃选项: Array = []
	for 选: int in _御刃可得():
		var 是魔: bool = 选 == 1
		var 刃卡: GCard = Data.get_card(MO_REN_CARD if 是魔 else YI_REN_CARD)
		var 系名: String = ""
		if 刃卡 != null:
			for 系: int in 刃卡.可选元素:
				if not 系名.is_empty():
					系名 += "/"
				系名 += "%s系" % GConst.element_to_chinese(系)
		御刃选项.append({
			"text": "【%s】%s加入手牌" % ["魔刃" if 是魔 else "异刃", 系名],
			"args": [选],
			# 客户端按这两个系别给选项文字里的「火系/水系（雷/风）」标色
			"elements": 刃卡.可选元素.duplicate() if 刃卡 != null else [],
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
# 普通攻击打出【魔刃】/【异刃】时：记下实例，供侵刻 / 噬灭 / 殇灭按「本次用的牌」判断
# ============================================================
func p_attack_card(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 面: int = int(ctx.get("card_id", 0))
	if 面 != MO_REN_CARD and 面 != YI_REN_CARD:
		return SUCCESS
	var 实例: int = 0
	for h: int in player.hand_cards:
		if GConst.牌号(h) == 面:
			实例 = h
			break
	if 实例 <= 0:
		return SUCCESS
	_本次刃 = 实例
	_本次刃面 = 面
	_噬灭已处理 = false
	return SUCCESS


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
	_噬灭已处理 = false
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


## 【渗蚀】的伤害：只有噬神者**自己**使用/弃置时，【同调】才把 3 点降为 1 点；
## 其他人拿这张牌打出/弃置时仍是 3 点。
func _渗蚀伤害(触发者: int) -> int:
	return 同调伤害 if 触发者 == player.id and _有同调() else 渗蚀伤害


## 弃置/使用【魔刃】/【异刃】时：噬神者对该牌的使用者（弃牌/出牌者）造成 3 点
## （若使用者是噬神者自己且持有【同调】，则 1 点）法术伤害。然后这张牌**移出游戏**
## （不从弃牌堆再流转）：牌面说明里的「移除此牌」；命中时由【侵刻】把同一实例交给目标。
func p_before_discard(ctx: Dictionary) -> int:
	if not wants_before_discard(ctx):
		return SUCCESS
	# 标记这些牌不进入弃牌堆（引擎 _结算待弃牌 支持 ctx.removed）
	var 移除: Array = ctx.get("removed", [])
	for c: Variant in ctx.get("cards", []):
		var 面: int = GConst.牌号(int(c))
		if (面 == MO_REN_CARD or 面 == YI_REN_CARD) and not 移除.has(int(c)):
			移除.append(int(c))
	ctx["removed"] = 移除
	var 键: String = "_渗蚀弃牌_%d" % player.id
	if bool(ctx.get(键, false)):
		return SUCCESS
	ctx[键] = true
	var dst: int = int(ctx.get("owner", -1))
	if dst < 0:
		return SUCCESS
	var 伤: int = _渗蚀伤害(dst)
	notice_skill(SHEN_SHI, [dst])
	engine.push_harm({
		"src": player.id, "dst": dst, "point": 伤,
		"cause": SHEN_SHI, "type": GConst.HarmType.Magic, "virtual_no_fate": true,
	})
	return URGENT


# ============================================================
# 渗蚀·盖牌：魔刃/异刃因技能被放进盖牌区（朝上/朝下都算）
# ============================================================
## 作为盖牌时：噬神者直接对该盖牌的角色造成 1 点法术伤害，然后移除该牌。
## 伤害是固定的 1 点，不受【同调】影响（同调只改自己使用/弃置时的 3→1）。
func p_cover_change(ctx: Dictionary) -> int:
	if int(ctx.get("direction", 0)) != GConst.CHANGE_ADD:
		return SUCCESS
	# 同一个盖牌变动只处理一次：URGENT 后引擎会回栈重跑本钩子，靠 seq 去重
	var seq: int = int(ctx.get("seq", -1))
	if seq >= 0 and seq == _渗蚀盖牌Seq:
		return SUCCESS
	var 刃: Array[int] = []
	for c: Variant in ctx.get("cards", []):
		var 面: int = GConst.牌号(int(c))
		if (面 == MO_REN_CARD or 面 == YI_REN_CARD) and not 刃.has(int(c)):
			刃.append(int(c))
	if 刃.is_empty():
		return SUCCESS
	var dst: int = int(ctx.get("dst", -1))
	if dst < 0:
		return SUCCESS
	_渗蚀盖牌Seq = seq
	notice_skill(SHEN_SHI, [dst])
	# 先压「移除」钩子，再压伤害：LIFO 会让伤害先结算，回来后再移除盖牌
	engine.push(BattleEngine.SHook.new("p_shi_shen_盖牌移除", {
		"player": player.id, "dst": dst, "cards": 刃}, []))
	# 盖牌渗蚀是固定的 1 点：不走治疗回应，避免目标/超时把「伤害并移除」拖到以后
	engine.push_harm({
		"src": player.id, "dst": dst, "point": 1,
		"cause": SHEN_SHI, "type": GConst.HarmType.Magic, "virtual_no_fate": true,
		"cross_available": 0,
	})
	return URGENT


func p_shi_shen_盖牌移除(ctx: Dictionary) -> int:
	var dst: int = int(ctx.get("dst", -1))
	var cards: Array = ctx.get("cards", [])
	if dst >= 0 and not cards.is_empty():
		engine.remove_cover(dst, cards, player.id, SHEN_SHI)
	return SUCCESS


# ============================================================
# 7903 噬灭 / 7904 殇灭：攻击时①额外弃 1 张指定系别的牌
# ============================================================
## 本次合法可弃的手牌（噬灭：水/火；殇灭：风/雷）；询问白名单和服务端校验共用这一份
func _噬灭可弃(系表: Array) -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return 系表.has(c.element_enum()))


func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _噬灭已处理 or _本次刃 <= 0:
		return SUCCESS
	var 是魔: bool = _本次刃面 == MO_REN_CARD
	var 技能: int = SHI_MIE if 是魔 else SHANG_MIE
	var 系表: Array = [GConst.CardElement.Water, GConst.CardElement.Fire] if 是魔 \
		else [GConst.CardElement.Wind, GConst.CardElement.Thunder]
	var 可弃: Array[int] = _噬灭可弃(系表)
	if 可弃.is_empty():
		return SUCCESS
	# 不再先问「是否发动」再问选牌：直接进选牌询问，选牌+确定即发动；取消即不发动。
	# 一次攻击只问一次：timeline1 若被重复调用，不能反复弹选牌/反复弃牌。
	_噬灭已处理 = true
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
			var 可弃: Array[int] = _噬灭可弃(系表)
			if 可弃.is_empty():
				_步 = 0
				return SUCCESS
			var 可弃牌面: Array[int] = []
			for cid0: int in 可弃:
				var 面0: int = GConst.牌号(cid0)
				if not 可弃牌面.has(面0):
					可弃牌面.append(面0)
			if not engine.has_reply():
				# 合法牌随询问下发：客户端只让点水/火（或风/雷）牌；可取消＝不发动
				询问(player.id, _噬灭技能, 1, 0, GConst.CardSource.Hand, [], 1, "", 可弃牌面, true,
					0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
					"【%s】：弃 1 张%s系牌【展示】" % [
						GConst.skill_name(_噬灭技能), "水/火" if _噬灭技能 == SHI_MIE else "风/雷"])
				return WAIT
			var r2: Dictionary = take_skill_reply_full()
			var cards: Array = r2.get("card_ids", [])
			_步 = 0
			if cards.size() != 1:
				return SUCCESS
			var cid: int = int(cards[0])
			var 选中牌: GCard = Data.get_card(cid)
			# 服务端兜底：必须正好 1 张、还在手里、且是水/火（或风/雷），否则这次询问作废
			if 选中牌 == null or not 系表.has(选中牌.element_enum()) or not player.有手牌(cid):
				return SUCCESS
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

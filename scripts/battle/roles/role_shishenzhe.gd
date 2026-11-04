extends BattleRole
## 噬神者（79）：御刃 / 侵刻 / 噬灭 / 殇灭 / 同调 / 魔刃 / 异刃 / 渗蚀 / 共振 / 诸神终焉
##
## 【魔刃】= 卡表#1005、【异刃】= 卡表#1006（血命格真实攻击牌；编号在 0..149 牌库之外，
## 不加入牌库，但拥有真实系别/命格/手牌实例）。
## "在场"＝在任意玩家手牌 / 盖牌里（或正是本次使用的那张）；被移除后实体不在任何区域＝不在场，
## 此时【御刃】/【共振】按记录的唯一实例把它们加回手牌（不新造牌）。
##
## 口径：
## 1. 【魔刃】/【异刃】是具体的牌，当前系别在手牌右上角切换（fire/water、thunder/wind）；
##    它们**本身就是当前系别的普通攻击牌**，直接点牌选目标打出，不再有攻击技能入口。
##    技能表里没有「刃」这个被动，只有【魔刃】7909 /【异刃】7910 /【渗蚀】7911 三条被动说明。
## 2. 【渗蚀】：使用/打出/弃置【魔刃】/【异刃】时，由噬神者对该牌的使用者造成 3 点法术伤害
##    （【同调】后 1 点），然后**移除该牌**：通过 `ctx.removed` 把实体移出游戏（不进弃牌堆/牌库）；
##    牌因技能放到角色旁时改为对该角色 1 点，结算后同样移除。
##    弃置触发走 F6 的 p_before_discard：调用方必须走统一弃牌入口 `engine.to_discard()`，
##    并在 ctx 里带上真正弃牌的人（owner）—— 直接 take_from_hand 不会触发。
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
## 本次刃是应战反击打出的（true）还是主动攻击（false）：
## 应战会先让原攻击走一次 timeline2_miss，不能用那次 miss 清掉本次刃。
var _本次刃是应战: bool = false
## 本次攻击的噬灭/殇灭是否已经问过（timeline1 若被重复调用也不能反复弹选牌/反复弃牌）
var _噬灭已处理: bool = false
## 本次攻击的侵刻是否已经问过（响应技能，命中后只问一次）
var _侵刻已处理: bool = false
var _侵刻目标: int = -1
## 已处理过的盖牌变动序号：钩子返回 URGENT 后引擎会回栈重跑同一个 p_cover_change，
## 同一个 seq 只处理一次，避免渗蚀伤害/移除无限循环。
var _渗蚀盖牌Seq: int = -1
## 御刃 / 共振 / 诸神终焉 的子流程
var _步: int = 0
## 诸神终焉的目标询问钩子是一次性的：URGENT 后引擎会回栈重跑本钩子，
## 不挡住会再推一次询问/再打一次 2 点，形成无限循环。
var _诸神问已处理: bool = false
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
			# 悬停时同时摊出这张刃的卡面（名称/图标/系别），与状态图标悬停一致
			"preview_cards": [MO_REN_CARD if 是魔 else YI_REN_CARD],
		})
	技能.append({
		"type": GConst.ActionType.SpecialSkill,
		"id": YU_REN,
		"arg_choices": 御刃选项,
		"enabled": not 御刃选项.is_empty(),
	})
	# 诸神终焉发动时，客户端要在「当前持有你两张刃的人」头像上写各 3 点法术伤害，
	# 这两个持有者由服务端按唯一实例算好，随 available_skills 的 highlight 下发。
	var 诸神高亮: Array[int] = []
	for 面: int in [MO_REN_CARD, YI_REN_CARD]:
		var inst: int = player.刃实例(面)
		if inst <= 0:
			continue
		var holder: int = engine.刃持有者(inst)
		if holder > 0:
			# 不去重：同一人同时持有两张刃时，客户端按出现次数画两行 3 点
			诸神高亮.append(holder)
	技能.append({
		"type": GConst.ActionType.MagicSkill,
		"id": ZHU_SHEN_ZHONG_YAN,
		"enabled": player.gem >= 1,
		"highlight": 诸神高亮,
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
	var 面: int = MO_REN_CARD if 选 == 1 else YI_REN_CARD
	var inst: int = player.刃实例(面)
	if inst <= 0:
		return GConst.GE_INVALID_ACTION
	# 刃被移除后不在任何区域：按记录的唯一实例直接加回手牌，不新造牌
	var 卡数据: GCard = Data.get_card(inst)
	if 卡数据 != null and not 卡数据.可选元素.is_empty() and 卡数据.可选元素.find(卡数据.element_enum()) < 0:
		卡数据.设置当前元素(卡数据.可选元素[0])
	if not engine.刃加入手牌(player.id, inst):
		return GConst.GE_INVALID_ACTION
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
	for 选: int in [1, 2]:
		var 面: int = MO_REN_CARD if 选 == 1 else YI_REN_CARD
		var inst: int = player.刃实例(面)
		if inst > 0 and not engine.刃在场(player.id, 面):
			可得.append(选)
	return 可得


# ============================================================
# 普通攻击打出【魔刃】/【异刃】时：记下实例，供侵刻 / 噬灭 / 殇灭按「本次用的牌」判断
# ============================================================
func p_attack_card(ctx: Dictionary) -> int:
	var 提交: int = int(ctx.get("card_id_instance", 0))
	var 面: int = GConst.牌号(提交) if 提交 > 0 else int(ctx.get("card_id", 0))
	if 面 != MO_REN_CARD and 面 != YI_REN_CARD:
		return SUCCESS
	# 只有刃的归属者处理这次攻击；攻击者可能是侵刻后拿到牌的人
	if engine.刃归属者(提交) != player.id:
		return SUCCESS
	# 归属者可能不持有这张牌（被侵刻交给别人）；只要实例归属自己就记本次刃
	var 实例: int = 提交 if 提交 > 0 and (player.有手牌(提交) or engine.刃归属者(提交) == player.id) else 0
	if 实例 <= 0:
		for h: int in player.hand_cards:
			if GConst.牌号(h) == 面:
				实例 = h
				break
	if 实例 <= 0:
		return SUCCESS
	_本次刃 = 实例
	_本次刃面 = 面
	_本次刃是应战 = bool(ctx.get("reattack", false))
	_噬灭已处理 = false
	_侵刻已处理 = false
	_侵刻目标 = -1
	return SUCCESS


# ============================================================
# 7902 侵刻：使用【魔刃】/【异刃】攻击命中时，把该卡加入攻击目标手牌
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	# 侵刻的触发条件是「攻击命中」，主动攻击和应战反击都算
	var 应战命中: bool = bool((ctx.get("harm", {}) as Dictionary).get("reattack", false))
	if 应战命中 != _本次刃是应战:
		return SUCCESS
	if _本次刃 <= 0 or engine.刃归属者(_本次刃) != player.id:
		return SUCCESS
	if _侵刻已处理 and not engine.has_reply():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		return SUCCESS
	if not engine.has_reply():
		_侵刻已处理 = true
		_侵刻目标 = dst.id
		# 无选项，只有「确定 / 取消」：确定发动，取消不发动
		询问(player.id, QIN_KE, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [dst.id], -1, {}, 0, 0, false, [], true, -1, 0, "")
		return WAIT
	_侵刻目标 = -1
	if not take_skill_reply():
		_本次刃 = 0
		_本次刃面 = 0
		_本次刃是应战 = false
		return SUCCESS
	notice_skill(QIN_KE, [dst.id])
	# 刃随使用已被移除（实体不在任何区域）：按同一唯一实例加进目标手牌
	engine.刃加入手牌(dst.id, _本次刃)
	_本次刃 = 0
	_本次刃面 = 0
	_本次刃是应战 = false
	engine._broadcast_game()
	return SUCCESS


func p_timeline_2_miss(ctx: Dictionary) -> int:
	# 应战反击没有 p_after_attack，未命中时也要清掉本次刃，避免污染下一次攻击。
	# 但应战会让「被反击的原攻击」先走一次 miss：那次不能清掉刚记下的应战刃。
	var 应战未命中: bool = bool((ctx.get("harm", {}) as Dictionary).get("reattack", false))
	if 应战未命中 != _本次刃是应战:
		return SUCCESS
	if _本次刃 > 0 and engine.刃归属者(_本次刃) == player.id:
		_本次刃 = 0
		_本次刃面 = 0
		_本次刃是应战 = false
		_侵刻已处理 = false
	return SUCCESS


## 本次攻击结束后清掉「这次用的牌」：没触发【侵刻】时牌已被移出游戏，
## 下一次普通攻击不能再拿它去判【噬灭】/【殇灭】。
func p_after_attack(_ctx: Dictionary) -> int:
	_本次刃 = 0
	_本次刃面 = 0
	_本次刃是应战 = false
	_噬灭已处理 = false
	_侵刻已处理 = false
	_侵刻目标 = -1
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
		if _是我的刃(int(c)):
			return true
	return false


## 这张实例是不是本噬神者拥有的刃（不是任意一张 1005/1006）
func _是我的刃(inst: int) -> bool:
	var 面: int = GConst.牌号(inst)
	if 面 != MO_REN_CARD and 面 != YI_REN_CARD:
		return false
	return int(inst) == player.刃实例(面) or engine.刃归属者(int(inst)) == player.id


## 【渗蚀】的伤害：只有噬神者**自己**使用/弃置时，【同调】才把 3 点降为 1 点；
## 其他人拿这张牌打出/弃置时仍是 3 点。
func _渗蚀伤害(触发者: int) -> int:
	return 同调伤害 if 触发者 == player.id and _有同调() else 渗蚀伤害


## 弃置/使用【魔刃】/【异刃】时：噬神者对该牌的使用者（弃牌/出牌者）造成 3 点
## （若使用者是噬神者自己且持有【同调】，则 1 点）法术伤害。牌随后正常进入弃牌堆，
## 保留唯一实例；之后可由御刃/共振从弃牌堆取回。
func p_before_discard(ctx: Dictionary) -> int:
	if not wants_before_discard(ctx):
		return SUCCESS
	var 键: String = "_渗蚀弃牌_%d" % player.id
	if bool(ctx.get(键, false)):
		return SUCCESS
	ctx[键] = true
	# 这次的刃要「移除」：让弃牌结算把这些实体移出游戏（不进弃牌堆 / 牌库，御刃/共振按唯一实例加回）
	var 移除: Array = []
	for c: Variant in ctx.get("cards", []):
		if _是我的刃(int(c)) and not 移除.has(int(c)):
			移除.append(int(c))
	ctx["removed"] = 移除
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
		if _是我的刃(int(c)) and not 刃.has(int(c)):
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
	# 盖牌渗蚀的 1 点仍是正常法术伤害：目标可以用【治疗】抵挡，结算后再移除盖牌
	engine.push_harm({
		"src": player.id, "dst": dst, "point": 1,
		"cause": SHEN_SHI, "type": GConst.HarmType.Magic, "virtual_no_fate": true,
	})
	return URGENT


func p_shi_shen_盖牌移除(ctx: Dictionary) -> int:
	var dst: int = int(ctx.get("dst", -1))
	var cards: Array = ctx.get("cards", [])
	if dst >= 0 and not cards.is_empty():
		# 从盖牌区拿走即「移除」：实体不在任何区域（御刃/共振按唯一实例加回）
		engine.remove_cover(dst, cards, player.id, SHEN_SHI)
	return SUCCESS


# ============================================================
# 7903 噬灭 / 7904 殇灭：攻击时①额外弃 1 张指定系别的牌
# ============================================================
## 本次合法可弃的手牌（噬灭：水/火；殇灭：风/雷）；询问白名单和服务端校验共用这一份
func _噬灭可弃(系表: Array) -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return 系表.has(c.element_enum()))


func p_timeline_1(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _噬灭已处理 or _本次刃 <= 0 or engine.刃归属者(_本次刃) != player.id:
		return SUCCESS
	var 是魔: bool = _本次刃面 == MO_REN_CARD
	var 技能: int = SHI_MIE if 是魔 else SHANG_MIE
	var 系表: Array = [GConst.CardElement.Water, GConst.CardElement.Fire] if 是魔 \
		else [GConst.CardElement.Wind, GConst.CardElement.Thunder]
	# 手牌不足也照样发起询问：提示条/取消按钮照常出现，玩家可以取消；不静默跳过。
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
		2:  # 噬灭 / 殇灭：噬灭选弃牌；殇灭在同一个询问里选弃牌 + 目标，不再分两步
			var 系表: Array = [GConst.CardElement.Water, GConst.CardElement.Fire] \
				if _噬灭技能 == SHI_MIE else [GConst.CardElement.Wind, GConst.CardElement.Thunder]
			var 可弃: Array[int] = _噬灭可弃(系表)
			var 可弃牌面: Array[int] = []
			for cid0: int in 可弃:
				var 面0: int = GConst.牌号(cid0)
				if not 可弃牌面.has(面0):
					可弃牌面.append(面0)
			# 空白名单在协议/客户端里表示「不限制」，会变成什么牌都能点；
			# 用全禁哨兵表示「这次一张合法牌都没有」，仍然保留询问和取消。
			if 可弃牌面.is_empty():
				可弃牌面 = [GConst.手牌白名单_全禁]
			var 殇灭池: Array[int] = []
			if _噬灭技能 == SHANG_MIE:
				for pid: int in enemy_ids():
					if pid != _噬灭目标:
						殇灭池.append(pid)
				if 殇灭池.is_empty():
					_步 = 0
					return SUCCESS
			if not engine.has_reply():
				# 合法牌随询问下发：客户端只让点水/火（或风/雷）牌；可取消＝不发动。
				# 殇灭把「选目标」并进同一询问：一次确认同时提交弃牌和目标。
				询问(player.id, _噬灭技能, 1, 1 if _噬灭技能 == SHANG_MIE else 0,
					GConst.CardSource.Hand, [], 1, "", 可弃牌面, true,
					0, player.id, 殇灭池 if _噬灭技能 == SHANG_MIE else [_噬灭目标],
					1, {}, 0, 0, false, [], true, -1, 0,
					"")
				return WAIT
			var r2: Dictionary = take_skill_reply_full()
			var cards: Array = r2.get("card_ids", [])
			var ds2: Array = r2.get("dst_ids", [])
			_步 = 0
			if cards.size() != 1:
				return SUCCESS
			var cid: int = int(cards[0])
			var 选中牌: GCard = Data.get_card(cid)
			# 服务端兜底：必须正好 1 张、还在手里、且是水/火（或风/雷），否则这次询问作废
			if 选中牌 == null or not 系表.has(选中牌.element_enum()) or not player.有手牌(cid):
				return SUCCESS
			var 移除目标: int = _噬灭目标
			if _噬灭技能 == SHANG_MIE:
				if ds2.size() != 1 or not 殇灭池.has(int(ds2[0])):
					return SUCCESS
				移除目标 = int(ds2[0])
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": [cid], "is_real": true,
			})
			engine.take_from_hand(player.id, [cid], false)
			engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": _噬灭技能})
			engine._log_discard(player.id, [cid], false)
			notice_skill(_噬灭技能, [移除目标])
			_移除治疗(移除目标, 1)
			return SUCCESS
		4:  # 共振：选 2~3 张同系牌弃之
			if not engine.has_reply():
				# 不预先固定某一系：多系别牌（魔刃/异刃）切换后也能马上参与同系组合。
				# 候选给全部手牌，客户端按 "same" 规则逐张判同系；服务端下面再复核。
				var 候选: Array[int] = player.hand_cards.duplicate()
				询问(player.id, GONG_ZHEN, 2, 0, GConst.CardSource.Hand, [], 3, "same", 候选, true,
					0, player.id, [], 3, {}, 0, 0, false, [], true, -1, 0,
					_共振完整说明())
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
			# 服务端复核 2~3 张是否同系（按每张实例当前系别，而不是固定 _共振系）
			var 系值: int = -1
			for c4: Variant in 弃:
				var 卡4: GCard = Data.get_card(int(c4))
				var e4: int = 卡4.element_enum() if 卡4 != null else 0
				if e4 <= 0:
					return SUCCESS
				if 系值 < 0:
					系值 = e4
				elif e4 != 系值:
					return SUCCESS
			# 代价在真正确认 2~3 张同系牌后才付；没有同系牌时仍然会询问，但不扣能量
			if player.get_energy() < 1:
				return SUCCESS
			player.remove_energy(1)
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": 弃, "is_real": true,
			})
			engine.take_from_hand(player.id, 弃, false)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": GONG_ZHEN})
			engine._log_discard(player.id, 弃, false)
			notice_skill(GONG_ZHEN, [player.id])
			# 弃牌代价里若有刃，渗蚀/移除结算会晚于本钩子；
			# 先回到步骤 5，等刃真正被移除再开第二步（那时按唯一实例加回）。
			# 没有刃时 to_discard 是同步的，直接开第二步即可。
			var 有刃代价: bool = false
			for c5: Variant in 弃:
				var 面5: int = GConst.牌号(int(c5))
				if 面5 == MO_REN_CARD or 面5 == YI_REN_CARD:
					有刃代价 = true
					break
			if 有刃代价:
				_步 = 5
				return URGENT
			engine._broadcast_game()
			_步 = 6
			engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
			return URGENT
		5:  # 共振：等弃牌代价和渗蚀结算完（刃已被移除，可加回）再开四选一
			engine._broadcast_game()
			_步 = 6
			engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
			return URGENT
		6:  # 共振：四选一（不加 / 魔刃 / 异刃 / 两者），后三项再选 1 名目标造成 1 点法术伤害
			if not engine.has_reply():
				询问(player.id, GONG_ZHEN, 0, 0, GConst.CardSource.Hand, _共振选项(),
					0, "", [], false, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					_共振完整说明())
				return WAIT
			var r6: Dictionary = take_skill_reply_full()
			var args6: Array = r6.get("args", [])
			var 选6: int = int(args6[0]) if not args6.is_empty() else 0
			var ds6: Array = r6.get("dst_ids", [])
			_步 = 0
			var 场上: Array[int] = _在场刃()
			var 加: Array[int] = []
			for 面6: int in [MO_REN_CARD, YI_REN_CARD]:
				if 场上.has(面6):
					continue
				var inst6: int = player.刃实例(面6)
				if inst6 > 0 and not engine.刃在场(player.id, 面6):
					加.append(inst6)
			var 要魔: bool = 选6 == 2 or 选6 == 4
			var 要异: bool = 选6 == 3 or 选6 == 4
			if 选6 == 1 or 加.is_empty() \
					or (要魔 and not 加.has(player.刃实例(MO_REN_CARD))) \
					or (要异 and not 加.has(player.刃实例(YI_REN_CARD))):
				return SUCCESS
			if 选6 == 2:
				加 = [player.刃实例(MO_REN_CARD)]
			elif 选6 == 3:
				加 = [player.刃实例(YI_REN_CARD)]
			for inst6: int in 加:
				engine.刃加入手牌(player.id, inst6)
			engine._broadcast_game()
			if ds6.size() != 1:
				return SUCCESS
			engine.push_harm({
				"src": player.id, "dst": int(ds6[0]), "point": 1,
				"cause": GONG_ZHEN, "type": GConst.HarmType.Magic,
			})
			return URGENT
		7:  # 诸神终焉：同时移除了自己的两张刃，选 1 名目标对手造成 2 点法术伤害
			if not engine.has_reply():
				var 敌7: Array[int] = enemy_ids()
				if 敌7.is_empty():
					_步 = 0
					return SUCCESS
				询问(player.id, ZHU_SHEN_ZHONG_YAN, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
					0, -1, 敌7, -1, {}, 0, 0, false, [], true, -1, 0,
					GConst.skill_desc(ZHU_SHEN_ZHONG_YAN))
				return WAIT
			var r7: Dictionary = take_skill_reply_full()
			var ds7: Array = r7.get("dst_ids", [])
			_步 = 0
			if ds7.size() == 1:
				engine.push_harm({
					"src": player.id, "dst": int(ds7[0]), "point": 2,
					"cause": ZHU_SHEN_ZHONG_YAN, "type": GConst.HarmType.Magic,
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
	if player.get_energy() < 1:
		return SUCCESS
	harm["共振已处理"] = true
	_步 = 4
	_共振系 = _同系两张的系别()
	engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
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


## 共振的完整技能说明（响应提示 / 四选项提示都用它，不再只写一行弃牌说明）
func _共振完整说明() -> String:
	var 说明: String = GConst.skill_desc(GONG_ZHEN)
	if 说明.is_empty():
		说明 = "【共振】：弃 2~3 张同系牌，将未在场的【魔刃】/【异刃】加入手牌，对目标造成 1 点法术伤害"
	return 说明


## 共振四选项：不加 / 加魔刃 / 加异刃 / 两者都加。
## 后三项自带 1 名目标；选项文案与御刃一致，并带 elements / 技能组 供客户端标色和悬停。
func _共振选项() -> Array:
	var 魔卡: GCard = Data.get_card(MO_REN_CARD)
	var 异卡: GCard = Data.get_card(YI_REN_CARD)
	var 魔系: String = _刃系名(MO_REN_CARD)
	var 异系: String = _刃系名(YI_REN_CARD)
	var 魔元: Array = 魔卡.可选元素.duplicate() if 魔卡 != null else []
	var 异元: Array = 异卡.可选元素.duplicate() if 异卡 != null else []
	# 按第二步当前手牌判断：第一步弃牌代价中弃掉的刃，第二步可以重新加回
	var 场上: Array[int] = _在场刃()
	var 可魔: bool = not 场上.has(MO_REN_CARD)
	var 可异: bool = not 场上.has(YI_REN_CARD)
	var 全体: Array[int] = _全体角色()
	return [
		{
			"value": 1,
			"label": "不加入手牌",
		},
		{
			"value": 2,
			"label": "【魔刃】%s加入手牌" % 魔系,
			"enabled": 可魔,
			"need_target": 1,
			"targets": 全体,
			"elements": 魔元,
			"技能组": [7909, 7911],
			"preview_cards": [MO_REN_CARD],
		},
		{
			"value": 3,
			"label": "【异刃】%s加入手牌" % 异系,
			"enabled": 可异,
			"need_target": 1,
			"targets": 全体,
			"elements": 异元,
			"技能组": [7910, 7911],
			"preview_cards": [YI_REN_CARD],
		},
		{
			"value": 4,
			"label": "【魔刃】%s和【异刃】%s加入手牌" % [魔系, 异系],
			"enabled": 可魔 and 可异,
			"need_target": 1,
			"targets": 全体,
			"elements": 魔元 + 异元,
			"技能组": [7909, 7910, 7911],
			"preview_cards": [MO_REN_CARD, YI_REN_CARD],
		},
	]


## 卡表的可选系别串（火系/水系、雷系/风系），和御刃选项同一口径
func _刃系名(卡号: int) -> String:
	var 卡: GCard = Data.get_card(卡号)
	var 名: String = ""
	if 卡 == null:
		return 名
	for 系: int in 卡.可选元素:
		if not 名.is_empty():
			名 += "/"
		名 += "%s系" % GConst.element_to_chinese(系)
	return 名


# ============================================================
# 7908 诸神终焉：+1 水晶、自伤 2、移除场上【魔刃】【异刃】并伤害原持有者
# ============================================================
func _p_诸神终焉() -> int:
	if player.gem < 1:
		return GConst.GE_INVALID_ACTION
	_诸神问已处理 = false
	player.set_gem(player.gem - 1)
	player.set_crystal(player.crystal + 1)
	notice_skill(ZHU_SHEN_ZHONG_YAN, [player.id])
	# 顺序：获得水晶（已结算）→ 自身 2 点法术伤害 → 移除自己的刃 → 对原持有者各 3 点
	# → 若两张都移除，才问 1 名对手 2 点。先压移除钩子、再压自伤，LIFO 保证自伤先完整结算。
	# 自伤是正常法术伤害，会正常触发自己的【共振】（不再用步骤 8 挡）。
	engine.push(BattleEngine.SHook.new("p_shi_shen_诸神移除", {"player": player.id}, []))
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": ZHU_SHEN_ZHONG_YAN, "type": GConst.HarmType.Magic,
	})
	return URGENT


## 诸神终焉的第二步：自身 2 点伤害结算完后，移除自己的两张刃并结算原持有者 3 点伤害。
func p_shi_shen_诸神移除(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 持有: Array = []
	for 面: int in [MO_REN_CARD, YI_REN_CARD]:
		var inst: int = player.刃实例(面)
		if inst <= 0:
			continue
		for pid: int in engine.order:
			var pp: BattlePlayer = engine.p(pid)
			if pp == null:
				continue
			var 取到: int = pp.取出实例(pp.hand_cards, inst)
			if 取到 <= 0:
				取到 = pp.取出实例(pp.cover_cards, inst)
			if 取到 > 0:
				持有.append({"pid": pid, "card": 取到})
				break
	var 两张: bool = 持有.size() >= 2
	# 3 点伤害（包括打回自己）必须能在 _步=0 下触发共振；目标询问单独放到
	# p_shi_shen_诸神问 里，等 3 点全部结算完再把它自己的 _步 置 7。
	_步 = 0
	if 两张:
		engine.push(BattleEngine.SHook.new("p_shi_shen_诸神问", {"player": player.id}, []))
	for i: int in range(持有.size() - 1, -1, -1):
		var 项: Dictionary = 持有[i]
		engine.push_harm({
			"src": player.id, "dst": int(项["pid"]), "point": 3,
			"cause": ZHU_SHEN_ZHONG_YAN, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT if 两张 or not 持有.is_empty() else SUCCESS


## 诸神终焉：3 点伤害全部结算完，才进入「选 1 名对手 2 点」的目标询问。
func p_shi_shen_诸神问(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _诸神问已处理:
		return SUCCESS
	_诸神问已处理 = true
	_步 = 7
	engine.push(BattleEngine.SHook.new("p_shi_shen_ask", {"player": player.id}, []))
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


## 本噬神者拥有的刃里，哪些当前在场（弃牌堆＝不在场；手中/盖牌/正在攻击＝在场）
func _在场刃() -> Array[int]:
	var out: Array[int] = []
	for 卡: int in [MO_REN_CARD, YI_REN_CARD]:
		if engine.刃在场(player.id, 卡):
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

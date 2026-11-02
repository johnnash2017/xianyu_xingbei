extends BattleRole
## 咒符师（84）：咒符-火璃 / 咒符-冻天 / 念咒 / 魑魅魍魉 / 咒力重塑
##
## 区域：本角色没有专属区域 ——【妖力】＝盖牌区面朝下的牌（角色表「指示物」列槽 2 的上限 2），
## 放进去时用 engine.add_cover(..., open = false, tag = "妖力") 打标记，取出来用 盖牌按标记("妖力")。
##
## 口径（开发时定下的，写在这里免得以后重复讨论）：
## 1. 【咒符】是法术技能（技能栏）。费用「弃 1 张火 / 水系牌」在发动时结算（点选即付、已付不退）。
##    费用牌走「展示 → 从手牌拿走 → 进弃牌堆 → 写弃牌日志」，与 4701 甜点冲击同一条路径。
## 2. 【咒力重塑】（8405）：发动咒符时**第一步**问一次，取消＝不发动；发动后
##    「1 名目标角色」变「2 名目标角色」，因此在原选目标之外再补问 1 名目标。
## 3. 【念咒】（8403）：咒符**结算完**之后问一次，把 1 张手牌面朝下放进盖牌区当【妖力】。
##    【魑魅魍魉】视为发动的咒符不触发【念咒】（原文写明）。
## 4. 【魑魅魍魉】（8404）：主动攻击命中后②，移除 1 个【妖力】→ 选【火璃】或【冻天】无条件发动一次；
##    被移除的【妖力】是地系牌时可以【展示】它，让该次【火璃】伤害 +1 / 【冻天】弃牌数 +1。
##    因为是「无条件发动」，本次不收费用牌、也不触发【念咒】。

const ZHOU_FU_HUO_LI: int = 8401
const ZHOU_FU_DONG_TIAN: int = 8402
const NIAN_ZHOU: int = 8403
const CHI_MEI_WANG_LIANG: int = 8404
const ZHOU_LI_CHONG_SU: int = 8405

const YAO_LI标记: String = "妖力"
const 火璃伤害: int = 1

enum 步 {
	空闲 = 0,
	重塑询问,
	补选目标,
	火璃结算,
	火璃摸弃,
	冻天弃牌,
	冻天转移治疗,
	念咒询问,
	念咒选牌,
	魑魅选择,
	魑魅展示,
	魑魅选目标,
}

var _步: int = 步.空闲
## 上一轮压过状态（伤害 / 摸牌 / 移除盖牌）：回到钩子时先认这件事，再往下推进
var _结算中: bool = false
## 压完状态之后要回到哪一步
var _压下步: int = 步.空闲
var _技能: int = 0
var _目标: Array[int] = []
var _重塑: bool = false
var _重放: bool = false
var _加成: int = 0
var _下标: int = 0
## 【冻天】还要转几次治疗（重塑后 2 次）
var _转次: int = 0
var _妖力牌: int = -1


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 火系: Array[int] = _系手牌(GConst.CardElement.Fire)
	var 水系: Array[int] = _系手牌(GConst.CardElement.Water)
	var 全体: Array[int] = _全体角色()
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": ZHOU_FU_HUO_LI,
			"need_card": 1,
			"need_target": 1,
			"targets": 全体,
			"cards": 火系,
			"enabled": not 火系.is_empty() and not 全体.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": ZHOU_FU_DONG_TIAN,
			"need_card": 1,
			"need_target": 1,
			"targets": 全体,
			"cards": 水系,
			"enabled": not 水系.is_empty() and not 全体.is_empty(),
		},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		ZHOU_FU_HUO_LI:
			return _校验咒符(action, GConst.CardElement.Fire)
		ZHOU_FU_DONG_TIAN:
			return _校验咒符(action, GConst.CardElement.Water)
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		ZHOU_FU_HUO_LI:
			return _开始咒符(action, ZHOU_FU_HUO_LI, GConst.CardElement.Fire)
		ZHOU_FU_DONG_TIAN:
			return _开始咒符(action, ZHOU_FU_DONG_TIAN, GConst.CardElement.Water)
	return EMPTY_HANDLE


## 校验：恰好 1 张指定系别的牌（在手里）+ 恰好 1 名合法目标
func _校验咒符(action: Dictionary, 系: int) -> int:
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 1:
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not player.has_hand_card(cid) or card.element_enum() != 系:
		return GConst.GE_INVALID_CARDID
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != 1:
		return GConst.GE_INVALID_ACTION
	if engine.p(int(dsts[0])) == null:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


# ============================================================
# 咒符主流程
# ============================================================
func _开始咒符(action: Dictionary, 技能: int, 系: int) -> int:
	var 校验: int = _校验咒符(action, 系)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var cid: int = int((action.get("card_ids", []) as Array)[0])
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	notice_skill(技能, [dst])
	_付费弃牌(cid, 技能)
	_技能 = 技能
	_目标 = [dst]
	_重塑 = false
	_重放 = false
	_加成 = 0
	_下标 = 0
	_转次 = 0
	_妖力牌 = -1
	_结算中 = false
	_步 = 步.重塑询问
	engine.push(BattleEngine.SHook.new("p_zhou_fu_ask", {"player": player.id}, []))
	return URGENT


## 费用牌：展示 → 离手 → 进弃牌堆（与 4701 甜点冲击同一条路径）
func _付费弃牌(cid: int, cause: int) -> void:
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid], false)
	engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": cause})
	engine._log_discard(player.id, [cid], false)


## 咒符的逐步推进：一个钩子跑完整段流程（可以等待玩家，也可以压别的状态再回来）
func p_zhou_fu_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _结算中:
		_结算中 = false
		_步 = _压下步
	while true:
		match _步:
			步.重塑询问:
				if _重放:
					_步 = 步.火璃结算 if _技能 == ZHOU_FU_HUO_LI else 步.冻天弃牌
					continue
				if not engine.has_reply():
					_问发动(ZHOU_LI_CHONG_SU,
						"是否发动【咒力重塑】（消耗 1 点能量）？发动后本次咒符的「1 名目标角色」改为「2 名目标角色」")
					return WAIT
				if take_skill_reply() and player.get_energy() >= 1:
					player.remove_energy(1)
					_重塑 = true
					notice_skill(ZHOU_LI_CHONG_SU, _目标)
					engine._broadcast_game()
				_步 = 步.补选目标 if _重塑 else (步.火璃结算 if _技能 == ZHOU_FU_HUO_LI else 步.冻天弃牌)
				continue
			步.补选目标:
				if not engine.has_reply():
					_问目标(player.id, _技能, _全体角色(),
						"【咒力重塑】：再指定 1 名目标角色（不能与已选的重复）", true)
					return WAIT
				var r: Dictionary = take_skill_reply_full()
				var dsts: Array = r.get("dst_ids", [])
				if dsts.size() == 1:
					var dst: int = int(dsts[0])
					if dst > 0 and not _目标.has(dst):
						_目标.append(dst)
				_步 = 步.火璃结算 if _技能 == ZHOU_FU_HUO_LI else 步.冻天弃牌
				continue
			步.火璃结算:
				# 逆序压栈：先点选的目标先结算
				for i: int in range(_目标.size() - 1, -1, -1):
					engine.push_harm({
						"src": player.id, "dst": int(_目标[i]),
						"point": 火璃伤害 + _加成, "cause": ZHOU_FU_HUO_LI,
						"type": GConst.HarmType.Magic,
					})
				engine.push_draw(player.id, 1, ZHOU_FU_HUO_LI)
				_压下步 = 步.火璃摸弃
				_结算中 = true
				return URGENT
			步.火璃摸弃:
				if player.hand_cards.is_empty():
					_步 = 步.念咒询问
					continue
				if not engine.has_reply():
					_问弃牌(player.id, ZHOU_FU_HUO_LI, 1, "【咒符-火璃】：弃 1 张牌（可不弃）")
					return WAIT
				var r2: Dictionary = take_skill_reply_full()
				var cards2: Array = r2.get("card_ids", [])
				if not cards2.is_empty() and player.有手牌(int(cards2[0])):
					var cid2: int = int(cards2[0])
					engine.take_from_hand(player.id, [cid2], false)
					engine.to_discard([cid2], {"owner": player.id, "source": "hand", "cause": ZHOU_FU_HUO_LI})
					engine._log_discard(player.id, [cid2], false)
				_步 = 步.念咒询问
				continue
			步.冻天弃牌:
				if _下标 >= _目标.size():
					_下标 = 0
					_转次 = 2 if _重塑 else 1
					_步 = 步.冻天转移治疗
					continue
				var tgt: BattlePlayer = engine.p(int(_目标[_下标]))
				if tgt == null or tgt.hand_cards.is_empty():
					_下标 += 1
					continue
				if not engine.has_reply():
					_问弃牌(tgt.id, ZHOU_FU_DONG_TIAN, 1 + _加成,
						"【咒符-冻天】：弃 %d 张牌【展示】" % (1 + _加成))
					return WAIT
				var r3: Dictionary = take_skill_reply_full()
				var cards3: Array = r3.get("card_ids", [])
				var 弃: Array = []
				for c: Variant in cards3:
					if 弃.size() < 1 + _加成 and tgt.有手牌(int(c)):
						弃.append(int(c))
				if not 弃.is_empty():
					engine.broadcast(GConst.Msg.Card, {
						"type": GConst.CardMsgType.Show, "src_id": tgt.id, "dst_id": tgt.id,
						"card_ids": 弃, "is_real": true,
					})
					engine.take_from_hand(tgt.id, 弃, false)
					engine.to_discard(弃, {"owner": tgt.id, "source": "hand", "cause": ZHOU_FU_DONG_TIAN})
					engine._log_discard(tgt.id, 弃, false)
				_下标 += 1
				continue
			步.冻天转移治疗:
				if _转次 <= 0:
					_步 = 步.念咒询问
					continue
				var 可转: Array[int] = []
				for pid: int in _全体角色():
					if pid == player.id:
						continue
					var pp: BattlePlayer = engine.p(pid)
					if pp != null and pp.cross_num > 0:
						可转.append(pid)
				if 可转.is_empty():
					_步 = 步.念咒询问
					continue
				if not engine.has_reply():
					_问目标(player.id, ZHOU_FU_DONG_TIAN, 可转,
						"【咒符-冻天】：指定 1 名角色，把他的 1【治疗】转移给你（还可指定 %d 次）" % _转次,
						true)
					return WAIT
				var r4: Dictionary = take_skill_reply_full()
				var ds: Array = r4.get("dst_ids", [])
				if ds.size() == 1:
					var src: BattlePlayer = engine.p(int(ds[0]))
					if src != null and src.cross_num > 0 and 可转.has(src.id):
						src.sub_cross_num(1)
						施加治疗(player.id, 1)
						engine._broadcast_game()
				_转次 -= 1
				continue
			步.魑魅选择:
				if not engine.has_reply():
					_问选项(player.id, CHI_MEI_WANG_LIANG, [ZHOU_FU_HUO_LI, ZHOU_FU_DONG_TIAN],
						"【魑魅魍魉】：选择视为发动哪一个咒符")
					return WAIT
				var r6: Dictionary = take_skill_reply_full()
				var args6: Array = r6.get("args", [])
				var 选: int = int(args6[0]) if not args6.is_empty() else 0
				_技能 = 选 if (选 == ZHOU_FU_HUO_LI or 选 == ZHOU_FU_DONG_TIAN) else ZHOU_FU_HUO_LI
				_移除妖力()
				_步 = 步.魑魅展示
				continue
			步.魑魅展示:
				var 妖卡: GCard = Data.get_card(_妖力牌)
				if 妖卡 == null or 妖卡.element_enum() != GConst.CardElement.Earth:
					_步 = 步.魑魅选目标
					continue
				if not engine.has_reply():
					_问发动(CHI_MEI_WANG_LIANG,
						"移除的【妖力】是地系牌：是否【展示】它，让本次【%s】的效果 +1？"
						% ("火璃伤害" if _技能 == ZHOU_FU_HUO_LI else "冻天弃牌数"))
					return WAIT
				if take_skill_reply():
					_加成 = 1
					engine.broadcast(GConst.Msg.Card, {
						"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
						"card_ids": [_妖力牌], "is_real": true,
					})
				_步 = 步.魑魅选目标
				continue
			步.魑魅选目标:
				if not engine.has_reply():
					_问目标(player.id, _技能, _全体角色(), "【魑魅魍魉】：指定 1 名目标角色", false)
					return WAIT
				var r7: Dictionary = take_skill_reply_full()
				var ds7: Array = r7.get("dst_ids", [])
				_目标 = [int(ds7[0])] if ds7.size() == 1 else []
				if _目标.is_empty():
					_步 = 步.空闲
					return SUCCESS
				_步 = 步.火璃结算 if _技能 == ZHOU_FU_HUO_LI else 步.冻天弃牌
				continue
			步.念咒询问:
				if _重放 or player.hand_cards.is_empty() or not player.can_add_cover_cards(1):
					_步 = 步.空闲
					return SUCCESS
				if not engine.has_reply():
					_问发动(NIAN_ZHOU,
						"是否发动【念咒】：将 1 张手牌面朝下放置在你角色旁，作为【妖力】？")
					return WAIT
				if not take_skill_reply():
					_步 = 步.空闲
					return SUCCESS
				_步 = 步.念咒选牌
				continue
			步.念咒选牌:
				if not engine.has_reply():
					_问弃牌(player.id, NIAN_ZHOU, 1, "【念咒】：选择 1 张手牌作为【妖力】", false)
					return WAIT
				var r5: Dictionary = take_skill_reply_full()
				var cards5: Array = r5.get("card_ids", [])
				_步 = 步.空闲
				if cards5.is_empty() or not player.有手牌(int(cards5[0])):
					return SUCCESS
				var cid5: int = int(cards5[0])
				notice_skill(NIAN_ZHOU)
				engine.take_from_hand(player.id, [cid5], false)
				engine.add_cover(player.id, [cid5], player.id, NIAN_ZHOU, false, YAO_LI标记)
				_压下步 = 步.空闲
				_结算中 = true
				return URGENT
	return SUCCESS


# ============================================================
# 魑魅魍魉（8404）：攻击命中后②，移除 1 个【妖力】，视为无条件发动一次【火璃】/【冻天】
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _步 != 步.空闲:
		return SUCCESS
	var 妖力: Array[int] = player.盖牌按标记(YAO_LI标记)
	if 妖力.is_empty():
		return SUCCESS
	if not engine.has_reply():
		_问发动(CHI_MEI_WANG_LIANG,
			"是否发动【魑魅魍魉】：移除 1 个【妖力】，视为无条件发动一次【咒符-火璃】或【咒符-冻天】？")
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(CHI_MEI_WANG_LIANG, [])
	_妖力牌 = int(妖力[0])
	_重放 = true
	_重塑 = false
	_加成 = 0
	_目标 = []
	_下标 = 0
	_转次 = 1
	_结算中 = false
	_步 = 步.魑魅选择
	engine.push(BattleEngine.SHook.new("p_zhou_fu_ask", {"player": player.id}, []))
	return URGENT


## 把本次视为发动用掉的【妖力】从盖牌区移出并弃置（先离开盖牌区，后续「展示」只看牌面）
func _移除妖力() -> void:
	if _妖力牌 < 0 or not player.有盖牌(_妖力牌):
		return
	engine.remove_cover(player.id, [_妖力牌], player.id, CHI_MEI_WANG_LIANG)
	engine.to_discard([_妖力牌], {"owner": player.id, "source": "cover", "cause": CHI_MEI_WANG_LIANG})
	engine._log_discard(player.id, [_妖力牌], false)


# ============================================================
# 小工具
# ============================================================
## 问「是否发动」：不选牌、不选目标，可取消
func _问发动(技能: int, 文案: String) -> void:
	询问(player.id, 技能, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
		0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, 文案)


## 问「弃 N 张手牌」：pid 是回答的人（可能是别人），可取消
func _问弃牌(pid: int, 技能: int, 张数: int, 文案: String, 可取消: bool = true) -> void:
	询问(pid, 技能, 张数, 0, GConst.CardSource.Hand, [], 张数, "", [], 可取消,
		0, pid, [], 张数, {}, 0, 0, false, [], true, -1, 0, 文案)


## 问「选 1 名目标」：池子由调用方给
func _问目标(pid: int, 技能: int, 池: Array[int], 文案: String, 可取消: bool = true) -> void:
	询问(pid, 技能, 0, 1, GConst.CardSource.Hand, [], 0, "", [], 可取消,
		0, -1, 池, -1, {}, 0, 0, false, [], true, -1, 0, 文案)


## 问「从给定选项里选一个」（options 会渲染成按钮，args[0] 是选中的值）
func _问选项(pid: int, 技能: int, options: Array, 文案: String) -> void:
	询问(pid, 技能, 0, 0, GConst.CardSource.Hand, options, 0, "", [], true,
		0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, 文案)


## 手里指定系别的牌（可用作咒符费用的牌）
func _系手牌(系: int) -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == 系)


## 场上全部角色（「目标角色」可以是任何人，含自己）
func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out

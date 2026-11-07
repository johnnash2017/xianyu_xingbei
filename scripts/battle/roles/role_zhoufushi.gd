extends BattleRole
## 咒符师（84）：【咒符-火璃】8401 /【咒符-冻天】8402 /【念咒】8403 /
## 【魑魅魍魉】8404 /【咒力重塑】8405。
##
## 技能结构与【灵符师】（role_lingfu.gd，18）一一对应，照它的流程写：
## · 【咒符】＝法术技能：点技能先开二级技能栏选「对 1 名角色 / -1【水晶】发动【咒力重塑】，对 2 名角色」
##   （同魔弓【魔眼】的二级栏写法，可「返回」退回行动阶段）→ 弃 1 张火 / 水系手牌当费用 →【念咒】→ 咒符效果。
## · 【咒力重塑】不再单开一问：它作为咒符二级栏的第二个选项（响应配色），选它＝发动重塑、
##   付 1 点能量（水晶优先，没水晶扣宝石），本次咒符改打 2 名目标。冻天两句都翻倍
##   （2 人各弃 1 张、2 次转移治疗，原文「按照语句顺序逐句发动」见星杯百科）。
## · 【念咒】在「发动咒符」这一刻问（灵符师 1803 也是这个位置）：把 1 张手牌面朝下放进盖牌区当【妖力】；
##   手牌为空或盖牌已满就不问。【魑魅魍魉】视为发动的咒符不触发念咒（技能原文写明）。
## · 【魑魅魍魉】主动攻击命中后②：一次询问里同时选【妖力】（盖牌）、选视为哪个咒符、选目标；
##   四项选项＝火璃 / 冻天 / 重塑后的火璃 / 重塑后的冻天（后两项响应配色，选了同样付 1 点能量）。
##   妖力是地系牌时再问一次要不要【展示】，展示后该次火璃伤害 / 冻天弃牌 +1。
##   视为发动不收费用牌，也不触发【念咒】。
##
## 两条与灵符师一致的细节：
## 1. 费用牌走「离手 → 进弃牌堆 → 写弃牌日志」。咒符的费用牌原文没有【展示】（灵符师写的是
##    「弃 1 张雷系牌【展示】」），所以这里不广播牌面。
## 2. 火璃「摸 1 张牌，弃 1 张牌」是同一句效果：摸完马上弃，中间那一下不算手牌超限——
##    8404 视为发动时没有费用牌先离场，满手牌真的会摸到第 7 张。

const 咒符_火璃: int = 8401
const 咒符_冻天: int = 8402
const 念咒: int = 8403
const 魑魅魍魉: int = 8404
const 咒力重塑: int = 8405

## 火璃基础伤害 / 冻天每人基础弃牌数（技能原文都是 1）
const 火璃伤害: int = 1
const 冻天弃牌: int = 1

## 咒符本体（p_magic_skill）的步骤：SkillRun 的 step，跨 WAIT 保留
const 步_念咒: int = 1
const 步_结算: int = 2
const 步_转移: int = 3
const 步_完成: int = 4

## 二级技能栏的选项值（火璃 / 冻天 的 arg_choices）：1＝对 1 名角色，2＝重塑后对 2 名角色
const 咒符_单目标: int = 1
const 咒符_双目标: int = 2

## 魑魅魍魉的相位：普通钩子每轮开始会把 step 清零，所以用自己的成员变量记
## 问（选咒符）→ 选目标（1 名 / 重塑后 2 名 + 挑妖力，可「返回」回问）→ 展示（地系）→ 结算 → 转移治疗
const 魑魅_问: int = 0
const 魑魅_选目标: int = 1
const 魑魅_展示: int = 2
const 魑魅_结算: int = 3
const 魑魅_转移: int = 4

## 魑魅魍魉第二段的解析结果：成功 / 玩家点了「返回」（退回第一段）/ 不发动
const 解析_成功: int = 0
const 解析_返回: int = 1
const 解析_失败: int = 2

## 本次咒符：是不是火璃、选中的目标（重塑后 2 名）、有没有发动重塑
var _火璃: bool = false
var _目标: Array[int] = []
var _重塑: bool = false
## 冻天还要转几次治疗（重塑后 2 次）
var _转移次数: int = 0
## 本次已经转过治疗的来源（「2 名目标角色」＝2 名不同的人，不重复选同一个）
var _转过来源: Array[int] = []
## 火璃摸牌期间挂了「不爆牌」，等「摸 → 弃」整段结算完（技能 / 钩子重入时）解除
var _持不爆牌: bool = false

## 魑魅魍魉：相位、本次攻击是否已经处理过、视为哪个咒符、有没有重塑、目标、选中的妖力、加成
var _魑魅相位: int = 魑魅_问
var _魑魅已用: bool = true
var _魑魅符: int = 0
var _魑魅重塑: bool = false
var _魑魅目标: Array[int] = []
var _魑魅妖力: int = -1
var _魑魅加成: int = 0


# ============================================================
# 技能栏：咒符-火璃 / 咒符-冻天（没有对应系别的牌时按钮仍摆出、只置灰）
# ============================================================
func available_skills() -> Array:
	var 火系: Array[int] = _系手牌(GConst.CardElement.Fire)
	var 水系: Array[int] = _系手牌(GConst.CardElement.Water)
	var 全体: Array[int] = _全体角色()
	return [
		{"type": GConst.ActionType.MagicSkill, "id": 咒符_火璃, "need_card": 1, "need_target": 1,
			"targets": 全体, "cards": 火系, "enabled": not 火系.is_empty(),
			"arg_choices": _咒符选项(咒符_火璃)},
		{"type": GConst.ActionType.MagicSkill, "id": 咒符_冻天, "need_card": 1, "need_target": 1,
			"targets": 全体, "cards": 水系, "enabled": not 水系.is_empty(),
			"arg_choices": _咒符选项(咒符_冻天)},
	]


## 咒符的二级技能栏选项（同魔弓【魔眼】：点技能先开栏，选中后同一步选牌 / 选目标，按一次「确定」提交）
## 第二项绑【咒力重塑】的技能号：按钮按「响应」配色显示、鼠标指向弹它的说明；选中＝发动重塑。
## 没有能量时第二项照样摆出来、只置灰（玩家能看到技能全部用法）。
func _咒符选项(技能: int) -> Array:
	return [
		{"text": GConst.按钮原文(技能, 0), "label": GConst.按钮原文(技能, 0),
			"args": [咒符_单目标], "need_target": 1},
		{"text": GConst.按钮原文(技能, 1), "label": GConst.按钮原文(技能, 1),
			"args": [咒符_双目标], "need_target": 2,
			"skill_id": 咒力重塑, "enabled": player.get_energy() >= 1},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 系别: int = 0
	match int(action.get("action_id", 0)):
		咒符_火璃:
			系别 = GConst.CardElement.Fire
		咒符_冻天:
			系别 = GConst.CardElement.Water
		_:
			return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	if args.size() != 1 or (int(args[0]) != 咒符_单目标 and int(args[0]) != 咒符_双目标):
		return GConst.GE_INVALID_ACTION
	var 重塑: bool = int(args[0]) == 咒符_双目标
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 1:
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	# 费用牌必须是自己手里、正好是对应系别的那 1 张
	if card == null or not player.has_hand_card(cid) or card.element_enum() != 系别:
		return GConst.GE_INVALID_CARDID
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != (2 if 重塑 else 1):
		return GConst.GE_INVALID_ACTION
	for d: Variant in dsts:
		if engine.p(int(d)) == null or dsts.count(d) > 1:
			return GConst.GE_INVALID_PLAYERID
	if 重塑 and player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if _持不爆牌:
		engine.解除不爆牌(player.id)
		_持不爆牌 = false
	var aid: int = int(action.get("action_id", 0))
	if aid != 咒符_火璃 and aid != 咒符_冻天:
		return SUCCESS
	if step == 0:
		var cards: Array = action.get("card_ids", [])
		var dsts: Array = action.get("dst_ids", [])
		var args: Array = action.get("args", [])
		_火璃 = aid == 咒符_火璃
		_重塑 = int(args[0]) == 咒符_双目标
		_目标.clear()
		for d: Variant in dsts:
			_目标.append(int(d))
		_转移次数 = 0
		_转过来源.clear()
		notice_skill(aid, _目标)
		if _重塑:
			# 选了二级栏第二项＝发动【咒力重塑】：付 1 点能量（水晶优先，没水晶扣宝石）
			player.remove_energy(1)
			notice_skill(咒力重塑, [player.id])
		_弃费用牌(int(cards[0]), aid)
		step = 步_念咒
	if step == 步_念咒:
		if _问念咒() == WAIT:
			return WAIT
		step = 步_结算
	if step == 步_结算:
		step = 步_转移
		_压咒符结算()
		return URGENT
	if step == 步_转移:
		while _转移次数 > 0:
			if _问一次转移() == WAIT:
				return WAIT
		step = 步_完成
	return SUCCESS


## 技能压了状态（摸牌 / 伤害 / 强制弃牌）之后还要回来接着做：
## 火璃要回来解除「不爆牌」，冻天要等各目标弃完牌再问转移治疗。
func 技能URGENT后重入(action: Dictionary = {}) -> bool:
	var aid: int = int(action.get("action_id", 0))
	if aid != 咒符_火璃 and aid != 咒符_冻天:
		return false
	return _持不爆牌 or step == 步_转移


# ============================================================
# 念咒（8403）：每当你发动【咒符】，可将 1 张手牌面朝下放进盖牌区当【妖力】
# ============================================================
## 返回 WAIT＝正在等回复；SUCCESS＝这一步结束
func _问念咒() -> int:
	if player.hand_cards.is_empty() or not player.can_add_cover_cards(1):
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, 念咒, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cid: int = _回复里的手牌(r.get("card_ids", []))
	if cid < 0:
		return SUCCESS
	notice_skill(念咒, [player.id])
	engine.take_from_hand(player.id, [cid])
	engine.add_cover(player.id, [cid], player.id, 念咒)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 咒符结算
# ============================================================
func _压咒符结算() -> void:
	if _火璃:
		_转移次数 = 0
		_压火璃结算(_目标, 0)
		return
	_转移次数 = 2 if _重塑 else 1
	# 状态栈后进先出：逆序压，实际按玩家点选顺序逐个让目标弃牌
	for i: int in range(_目标.size() - 1, -1, -1):
		engine.push(BattleEngine.SRequestDiscard.new(_目标[i], 冻天弃牌, 0, 咒符_冻天))


## 火璃：对每名目标造成 1 点法术伤害 → 你摸 1 张牌 → 弃 1 张牌
func _压火璃结算(dsts: Array, 加成: int) -> void:
	# 「摸 1 张牌，弃 1 张牌」是同一句效果：摸完马上弃，中间那一下不算超限。
	# 8401 付过费用牌，手牌必有空位；8404 视为发动没有费用牌先离场，满手牌时真的会摸到第 7 张，
	# 这时才挂「不爆牌」，等摸 → 弃整段结算完（技能 / 钩子重入时）再解除。
	if player.hand_cards.size() >= player.hand_cards_max:
		engine.进入不爆牌(player.id)
		_持不爆牌 = true
	# 状态栈后进先出：伤害 → 摸 1 张 → 弃 1 张，所以倒着压
	engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, 咒符_火璃))
	engine.push_draw(player.id, 1, 咒符_火璃)
	for i: int in range(dsts.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": int(dsts[i]), "point": 火璃伤害 + 加成,
			"cause": 咒符_火璃, "type": GConst.HarmType.Magic,
		})


## 冻天：指定 1 名目标角色弃 1 张牌，将除你外 1 名目标角色的 1【治疗】转移给你（重塑后各 2 次）
func _问一次转移() -> int:
	var 可转: Array[int] = _有治疗的其他角色()
	if 可转.is_empty():
		_转移次数 = 0
		return SUCCESS
	if not engine.has_reply():
		# 可取消＝false：有治疗可选就必须指定一名，超时由引擎从可转名单里代选。
		# 询问号用子询问 84021：它折到 8402 取说明，头像提示按「他 -1 治疗 / 你 +1 治疗」画
		询问(player.id, GConst.技能_冻天转移, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false, 0, -1, 可转)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var dsts: Array = r.get("dst_ids", [])
	var src: BattlePlayer = engine.p(int(dsts[0])) if dsts.size() == 1 else null
	if src == null or src.id == player.id or src.cross_num <= 0:
		engine.报错("【咒符-冻天】提交的治疗来源不合法", player.id)
		_转移次数 = 0
		return SUCCESS
	src.sub_cross_num(1)
	施加治疗(player.id, 1)
	_转过来源.append(src.id)
	engine._broadcast_game()
	_转移次数 -= 1
	return SUCCESS


# ============================================================
# 魑魅魍魉（8404）：主动攻击命中后②，移除 1 个【妖力】，
# 视为无条件发动一次【咒符-火璃】或【咒符-冻天】（妖力为地系可展示，效果 +1）
# ============================================================
## 每次自己宣告主动攻击时复位（同一攻击里只处理一次）
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		_魑魅相位 = 魑魅_问
		_魑魅已用 = false
		_魑魅加成 = 0
	return SUCCESS


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if _持不爆牌:
		# 视为发动的火璃「摸 → 弃」已经整段结算完
		engine.解除不爆牌(player.id)
		_持不爆牌 = false
		return SUCCESS
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _魑魅相位 == 魑魅_转移:
		# 冻天：目标弃完牌回来，再把他的 1【治疗】转给你
		while _转移次数 > 0:
			if _问一次转移() == WAIT:
				return WAIT
		_魑魅相位 = 魑魅_问
		return SUCCESS
	if _魑魅已用:
		return SUCCESS
	# 三段询问串起来跑：选咒符 →（可返回）选 1 名 / 重塑后 2 名目标 → 地系妖力要不要展示
	while true:
		if _魑魅相位 == 魑魅_问:
			if player.cover_cards.is_empty():
				_魑魅已用 = true
				return SUCCESS
			if not engine.has_reply():
				# 只问「视为发动哪个咒符」；点一项就进下一段（客户端点中即提交）
				询问(player.id, 魑魅魍魉, 0, 0, GConst.CardSource.Hand, _魑魅符选项(), 0, "", [], true)
				return WAIT
			if not _解析魑魅符():
				return SUCCESS
			_魑魅相位 = 魑魅_选目标
			continue
		if _魑魅相位 == 魑魅_选目标:
			if not engine.has_reply():
				# 与正常施法**同一颗技能号**（火璃 / 冻天）：二级栏的父按钮、两个选项文案、
				# 头像提示、技能说明全都和直接施法一模一样；区别只有费用牌从手牌换成 1 张【妖力】（盖牌），
				# 右侧「返回」退回上一段重选咒符。
				# ask_prompt（第 23 个参数）把提示条固定在魑魅魍魉的说明上，再加上选项的「不改提示」，
				# 选哪一档都不会被火璃 / 冻天 / 咒力重塑的说明顶掉。
				询问(player.id, _魑魅符, 1, 1, GConst.CardSource.Cover,
					_魑魅目标选项(), 0, "", [], true, 0, -1, _全体角色(),
					-1, {}, 0, 0, false, [], true, -1, 0, _魑魅提示())
				return WAIT
			match _解析魑魅目标():
				解析_返回:
					_魑魅相位 = 魑魅_问
					continue
				解析_失败:
					return SUCCESS
			_魑魅相位 = 魑魅_展示 if _妖力是地系() else 魑魅_结算
			continue
		if _魑魅相位 == 魑魅_展示:
			if not engine.has_reply():
				# 两项选项而不是「是 / 否」：带 card_id 的那项把这张地系【妖力】随询问下发，
				# 鼠标指向「展示」就能直接看到要展示的牌；目标随询问下发并自动选中，
				# 头像上写「原效果划掉 → 展示后的新效果」
				var 选项: Array = [
					{"value": 1, "label": GConst.按钮原文(魑魅魍魉, 2), "text": GConst.按钮原文(魑魅魍魉, 2),
						"card_id": _魑魅妖力},
					{"value": 0, "label": GConst.按钮原文(魑魅魍魉, 3), "text": GConst.按钮原文(魑魅魍魉, 3)},
				]
				询问(player.id, _魑魅展示技能号(), 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], true,
					0, -1, _魑魅目标)
				return WAIT
			if take_skill_reply():
				_魑魅加成 = 1
				engine.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
					"card_ids": [_魑魅妖力], "is_real": true,
				})
			_魑魅相位 = 魑魅_结算
			continue
		if _魑魅相位 == 魑魅_结算:
			_魑魅已用 = true
			_移除妖力()
			if _魑魅符 == 咒符_火璃:
				_魑魅相位 = 魑魅_问
				_压火璃结算(_魑魅目标, _魑魅加成)
				return URGENT
			_魑魅相位 = 魑魅_转移
			_转移次数 = 2 if _魑魅重塑 else 1
			_转过来源.clear()
			# 状态栈后进先出：逆序压，实际按点选顺序逐个让目标弃牌
			for i: int in range(_魑魅目标.size() - 1, -1, -1):
				engine.push(BattleEngine.SRequestDiscard.new(_魑魅目标[i], 冻天弃牌 + _魑魅加成, 0, 咒符_冻天))
			return URGENT
		return SUCCESS
	return SUCCESS


## 第一段：视为发动哪个咒符（点一项就进第二段，客户端点中即提交）。
## 绑各自技能号：按钮按「法术」配色，鼠标指向时弹那颗咒符的技能说明。
func _魑魅符选项() -> Array:
	return [
		{"value": 咒符_火璃, "label": GConst.按钮原文(魑魅魍魉, 0), "text": GConst.按钮原文(魑魅魍魉, 0),
			"skill_id": 咒符_火璃},
		{"value": 咒符_冻天, "label": GConst.按钮原文(魑魅魍魉, 1), "text": GConst.按钮原文(魑魅魍魉, 1),
			"skill_id": 咒符_冻天},
	]


## 第二段：与正常施法同一套两个选项（文案读所选咒符自己的按钮列）。
## 「不改提示」：选哪一档，提示条都保持魑魅魍魉的技能说明（见 _魑魅提示）。
func _魑魅目标选项() -> Array:
	return [
		{"value": 咒符_单目标, "label": GConst.按钮原文(_魑魅符, 0), "text": GConst.按钮原文(_魑魅符, 0),
			"need_target": 1, "no_prompt_change": true},
		{"value": 咒符_双目标, "label": GConst.按钮原文(_魑魅符, 1), "text": GConst.按钮原文(_魑魅符, 1),
			"need_target": 2, "no_prompt_change": true,
			"skill_id": 咒力重塑, "enabled": player.get_energy() >= 1},
	]


## 魑魅这几段询问期间，提示条固定写魑魅魍魉的技能说明（不看火璃 / 冻天各自的说明）
func _魑魅提示() -> String:
	var 说明: String = GConst.skill_desc(魑魅魍魉)
	if 说明.is_empty():
		return ""
	return "【%s】：%s" % [GConst.skill_name(魑魅魍魉), 说明]


## 第二段 / 第三段用哪颗子询问号（名字与说明折到 8404，头像指示器各配一份）
func _魑魅展示技能号() -> int:
	return GConst.技能_魑魅展示火璃 if _魑魅符 == 咒符_火璃 else GConst.技能_魑魅展示冻天


## 第一段回复：返回 false＝不发动（取消 / 超时 / 非法提交）
func _解析魑魅符() -> bool:
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or bool(r.get("is_timeout", false)):
		_魑魅已用 = true
		return false
	var 选: int = int(args[0])
	if 选 != 咒符_火璃 and 选 != 咒符_冻天:
		engine.报错("【魑魅魍魉】提交的咒符不合法", player.id)
		_魑魅已用 = true
		return false
	_魑魅符 = 选
	return true


## 第二段回复：选 1 名 / 重塑后 2 名目标 + 这张【妖力】。
## 返回解析_成功 / 解析_返回（点了「返回」，退回第一段）/ 解析_失败（不发动）
func _解析魑魅目标() -> int:
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	# 空应答＝「返回」或超时：退回第一段重选咒符，妖力还没动过
	if args.is_empty() or bool(r.get("is_timeout", false)):
		return 解析_返回
	var 选: int = int(args[0])
	if 选 != 咒符_单目标 and 选 != 咒符_双目标:
		engine.报错("【魑魅魍魉】提交的目标档不合法", player.id)
		_魑魅已用 = true
		return 解析_失败
	var 重塑: bool = 选 == 咒符_双目标
	var cards: Array = r.get("card_ids", [])
	var dsts: Array = r.get("dst_ids", [])
	var cid: int = int(cards[0]) if cards.size() == 1 else -1
	if cid < 0 or not player.有盖牌(cid) or dsts.size() != (2 if 重塑 else 1):
		engine.报错("【魑魅魍魉】提交的牌或目标不合法", player.id)
		_魑魅已用 = true
		return 解析_失败
	var 目标: Array[int] = []
	for d: Variant in dsts:
		var 目标id: int = int(d)
		if engine.p(目标id) == null or 目标.has(目标id):
			engine.报错("【魑魅魍魉】提交的目标不合法", player.id)
			_魑魅已用 = true
			return 解析_失败
		目标.append(目标id)
	if 重塑:
		if player.get_energy() < 1:
			engine.报错("【魑魅魍魉】没有能量发动【咒力重塑】", player.id)
			_魑魅已用 = true
			return 解析_失败
		player.remove_energy(1)
		notice_skill(咒力重塑, [player.id])
	_魑魅重塑 = 重塑
	_魑魅妖力 = cid
	_魑魅目标 = 目标
	notice_skill(魑魅魍魉, 目标)
	return 解析_成功


func _妖力是地系() -> bool:
	var card: GCard = Data.get_card(_魑魅妖力)
	return card != null and card.element_enum() == GConst.CardElement.Earth


## 用掉的【妖力】离场：先出盖牌区，再进弃牌堆（展示过的那张才公开牌面）
func _移除妖力() -> void:
	engine.remove_cover(player.id, [_魑魅妖力], player.id, 魑魅魍魉)
	engine.to_discard([_魑魅妖力], {
		"owner": player.id, "source": "cover", "cause": 魑魅魍魉, "face_up": _魑魅加成 > 0,
	})
	engine._log_discard(player.id, [_魑魅妖力], false)
	engine._broadcast_game()


# ============================================================
# 工具
# ============================================================
## 费用牌：离手 → 进弃牌堆 → 写弃牌日志（原文没有【展示】，所以不广播牌面）
func _弃费用牌(cid: int, cause: int) -> void:
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": cause, "face_up": false})
	engine._log_discard(player.id, [cid], false)
	engine._broadcast_game()


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


## 除自己外、当前有【治疗】可转移的角色（本次已经转过的排除掉）
func _有治疗的其他角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _全体角色():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.id != player.id and p0.cross_num > 0 and not _转过来源.has(pid):
			out.append(pid)
	return out


## 取回复里第一张仍在手里的牌（没选牌时返回 -1）
func _回复里的手牌(cards: Array) -> int:
	for c: Variant in cards:
		if player.has_hand_card(int(c)):
			return int(c)
	return -1

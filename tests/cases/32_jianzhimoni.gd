extends 自检用例
## R45 剑之魔女（45）：4501 技之剑意 / 4502 臆想剑 / 4503 梦想剑 / 4504 剑影*断念。
##
## 任务范围只有 role + test：角色表「脚本」列留给 DATA，用例里手动挂角色脚本。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 四颗技能行 / 技能说明 / 脚本文件；
##   - 4501：攻击行动结束自动生效（不再询问，与手里有没有技类牌无关）；额外行动出牌白名单只放技类攻击牌，
##            引擎按白名单兜底驳回非技类攻击牌；只有 4504 还走行动聚合器询问；
##   - 4502：主动攻击命中才询问；目标弃 1 张牌【展示】；攻击牌固定额外 +1 攻击行动（与是否获得无关），
##            获得只是可选的拿牌；法术牌本次伤害 +2；目标没手牌 / 非主动攻击 / 别人攻击不触发；
##            回合限定（发动后本回合不再问，回合开始重置）；
##            弃牌【展示】会触发等待型 p_show_hand（圣女弃水系牌→603）时，先结算展示响应再问获得；
##   - 4503：第 1 / 2 / 4 次攻击行动结束分别激活无视圣盾 / 无法应战 / 强制命中，第 3 次无新档；
##            只作用于主动攻击；回合开始清零；
##   - 4504：支付 1 真【宝石】→ 弃 2 张手牌 → 摸 1 张【强制】→ 额外 +1 攻击行动；
##            没有宝石 / 水晶不能顶 / 手牌不足 2 张不询问；取消不支付；回合限定。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_jianzhimoni.gd")
const 圣女脚本: GDScript = preload("res://scripts/battle/roles/role_shengnv.gd")

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 靶: BattlePlayer = null
var 队友: BattlePlayer = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []

var 技击甲: GCard = null
var 技击乙: GCard = null
var 非技击: GCard = null
var 攻击牌: GCard = null
var 法术牌: GCard = null


func _init() -> void:
	名称 = "剑之魔女"


# ============================================================
# 找牌 / 查消息
# ============================================================
## 卡库里第一张「是否技类命格」的攻击牌（排除 excluded_ids）
func _取攻击(需要技: bool, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if 排除.has(c.id):
			continue
		var 是技: bool = c.fate_pattern_enum() == GConst.FatePattern.Martial
		if 是技 == 需要技:
			return c
	return null


## 卡库里第一张法术牌（排除 excluded_ids）
func _取法术(排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic() and not 排除.has(c.id):
			return c
	return null


## 卡库里第一张水系攻击牌（用于触发圣女的等待型 p_show_hand【冰霜祷言】）
func _取水系攻击() -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() == GConst.CardElement.Water:
			return c
	return null


## 把一张牌从牌堆 / 弃牌堆移到某人手里（模拟真实持有，避免同一张牌同时在牌堆和手里）
func _给牌(持有者: BattlePlayer, cid: int) -> void:
	引擎.deck.remove_one(cid)
	持有者.add_hand_cards([cid])


## 最近一次下发给某玩家的询问里，是否有指定 respond_id 的那条
func _取询问(pid: int, respond_id: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == respond_id:
			return r
	return {}


## 聚合器把全部选项塞在同一条询问里，respond_id 只是第一项；按选项值找那条询问。
func _取选项询问(pid: int, 选项值: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if (r.get("args", []) as Array).slice(4).has(选项值):
			return r
	return {}


## 最近一份对局快照里某玩家的 dream_tier（没有快照返回 -1）
func _最后快照档(pid: int) -> int:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r.get("msg", 0)) != GConst.Msg.Game:
			continue
		for info: Dictionary in (r.get("data", {}) as Dictionary).get("player_infos", []):
			if int(info.get("id", -1)) == pid:
				return int(info.get("dream_tier", 0))
	return -1


## 某技能号播报过几次
func _播报次数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Skill:
			continue
		if int((r.get("data", {}) as Dictionary).get("skill_id", 0)) == 技能号:
			n += 1
	return n


## 给某玩家下发过几次指定 respond_id 的询问（实际发送记录，重发也算）
func _询问次数(pid: int, respond_id: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.CmdReq or int(r.get("pid", -1)) != pid:
			continue
		for c: Dictionary in (r.get("data", {}) as Dictionary).get("commands", []):
			if int(c.get("respond_id", 0)) == respond_id:
				n += 1
	return n


## 某条额外行动还在不在待办里
func _有额外行动(cause: int) -> bool:
	for a: Dictionary in 玩家.additional_actions:
		if int(a.get("cause", 0)) == cause:
			return true
	return false


## 清空战斗状态：回到「轮到玩家 1、行动阶段、无手牌、角色回合限定额度已重置」的同一起点
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	# 多步询问链也要清：_清空等待 只清引擎的等待槽，角色对象里的链会留到下一段测试
	角色._多步链.clear()
	角色._多步收尾.clear()
	角色._多步不收尾.clear()
	引擎._最后询问.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.测试跳过回合 = -1
	发送记录.clear()
	_清空玩家(玩家)
	_清空玩家(靶)
	_清空玩家(队友)
	角色.p_before_turn_begin({})


func _清空玩家(p0: BattlePlayer) -> void:
	p0.hand_cards.clear()
	p0.additional_actions.clear()
	p0.basic_effects.clear()
	p0.cross_num = 0
	p0.set_crystal(0)
	p0.set_gem(0)
	p0.跳过额外攻击行动 = false
	p0.reset_action_counts()


func _攻击上下文(牌: GCard, src: int, dst: int, 主动: bool, 伤害: int) -> Dictionary:
	var harm: Dictionary = {
		"src": src, "dst": dst, "point": 伤害, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": 牌.id, "is_active": 主动,
	}
	return {
		"card_id": 牌.id, "dst": dst, "src": src, "is_active": 主动,
		"hit_rate": GConst.HitRate.Normal, "check_shield": true, "can_light": true, "harm": harm,
	}


## 直接调用角色钩子时预置一份回复（对应玩家在客户端点了确定）
func _应答(args: Array, cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": []}
	引擎._has_reply = true


## 通过行动聚合器入口驱动一次「攻击结束」响应（等价于生产流程里的 _push_action_end_hooks）。
func _驱动攻击结束(上下文: Dictionary = {}) -> void:
	var ctx: Dictionary = {"player": 1, "kind": "attack"}
	ctx.merge(上下文, true)
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", ctx, false, 0)
	引擎.run()


## 通过聚合器下发的询问回复一条；on_message 内部会继续 run。
func _应答询问(pid: int, respond_id: int, args: Array, cards: Array = [], dsts: Array = []) -> void:
	引擎.on_message(pid, GConst.Msg.Respond, {
		"respond_id": respond_id, "src_id": pid, "args": args,
		"card_ids": cards, "dst_ids": dsts,
	})


## 把一张牌放到牌库顶，避免【剑影*断念】摸牌时随机摸到技类攻击牌、又触发 4501 询问
func _设牌库顶(cid: int) -> void:
	引擎.deck.pile.erase(cid)
	引擎.deck.discard.erase(cid)
	引擎.deck.pile.append(cid)


## 用一张手牌对目标发起一次完整攻击；目标放弃应战
func _打一次攻击(牌: GCard, 目标id: int) -> void:
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [牌.id], "dst_ids": [目标id], "args": []})
	引擎.run()
	if 引擎._await_id == 目标id and 引擎._await_kind == GConst.Msg.Respond:
		引擎.on_message(目标id, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.ReplyAttack, "src_id": 目标id,
			"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
		})


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 ----
	检(str(Data.role_list.get(45, "")) == "剑之魔女", "45 号角色名不是「剑之魔女」")
	检(Data.role_personal_name(45) == "席拉", "45 号角色姓名不是「席拉」")
	检(absf(Data.role_star(45) - 3.5) < 0.01, "剑之魔女应是 3.5 星，实际 %s" % str(Data.role_star(45)))
	检(Data.role_skills(45) == [4501, 4502, 4503, 4504],
		"剑之魔女技能号不对：%s" % str(Data.role_skills(45)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_jianzhimoni.gd"),
		"剑之魔女的角色脚本文件不存在")
	for 技能号: int in [4501, 4502, 4503, 4504]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	var 技能说明: String = Data.role_skill_info(45)
	for 技能名: String in ["技之剑意", "臆想剑", "梦想剑", "剑影*断念"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 卡库前提 ----
	技击甲 = _取攻击(true)
	技击乙 = _取攻击(true, [技击甲.id] if 技击甲 != null else [])
	非技击 = _取攻击(false)
	攻击牌 = _取攻击(false, [非技击.id] if 非技击 != null else [])
	法术牌 = _取法术()
	检(技击甲 != null and 技击乙 != null, "卡库找不到两张「技类命格」攻击牌")
	检(非技击 != null and 攻击牌 != null, "卡库找不到两张非技类攻击牌")
	检(法术牌 != null, "卡库找不到法术牌")
	if 技击甲 == null or 技击乙 == null or 非技击 == null or 攻击牌 == null or 法术牌 == null:
		return

	# ---- 建引擎：1 / 3 同队，2 是对手；角色表脚本列留给 DATA，用例里手动挂上角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "魔女")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	靶 = 引擎.p(2)
	队友 = 引擎.p(3)
	玩家.role_id = 45
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色

	# ============================================================
	# 4501 技之剑意：攻击行动结束自动生效（不再询问、与手里有没有技类牌无关）
	# ============================================================
	# 完整攻击流水线：攻击结束 → 自动进入 4501 的额外攻击行动
	_重置战斗()
	_给牌(玩家, 技击甲.id)
	_给牌(玩家, 技击乙.id)
	_给牌(玩家, 非技击.id)
	发送记录.clear()
	_打一次攻击(技击甲, 2)
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 4501,
		"攻击结束后应自动进入 4501 的额外攻击行动（当前 %d / 额外 %s / 来源 %s）"
		% [引擎.current_id, str(引擎.行动额外), str(引擎.行动额外来源)])
	检(引擎._await_kind == GConst.Msg.Action and 引擎._await_id == 1,
		"额外攻击行动阶段应在等玩家 1 出牌（等待 %s / %s）"
		% [str(引擎._await_id), str(引擎._await_kind)])
	检(_取询问(1, 4501).is_empty(), "4501 已改为自动生效，不应再下发「是否发动」询问")
	检(角色.dream_tier() == 1,
		"攻击结束、进入 4501 额外行动时梦想剑第 1 档应已标绿")
	检(_最后快照档(1) == 1,
		"攻击结束、进入 4501 额外行动时快照应已带 dream_tier=1，客户端才能标绿")
	检(角色.dream_ignore_shield, "真实攻击行动结束后梦想剑应激活「无视圣盾」")
	var 额外命令表: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 额外命令: Dictionary = 额外命令表[0] if not 额外命令表.is_empty() else {}
	# 只按命格限制的行动不再下发牌号名单：只给「限什么命格」，客户端比对牌面的命格字段
	检((额外命令.get("card_ids", []) as Array).is_empty(),
		"4501 不应再下发「全部技类攻击牌」的牌号名单：%s" % str(额外命令.get("card_ids", [])))
	检(int(额外命令.get("extra_fate", 0)) == GConst.FatePattern.Martial,
		"4501 应下发命格限制（技）：%s" % str(额外命令.get("extra_fate", 0)))
	var 序列命格: Array = 额外命令.get("extra_attack_fates", [])
	检(序列命格.has(GConst.FatePattern.Martial),
		"切换列表里 4501 那一份也应带命格限制：%s" % str(序列命格))
	var 命格编码: PackedByteArray = ProtoCodec.encode_named("Command", {
		"extra_fate": GConst.FatePattern.Martial,
	})
	var 命格解码: Dictionary = ProtoCodec.decode_named("Command", 命格编码)
	检(int(命格解码.get("extra_fate", 0)) == GConst.FatePattern.Martial,
		"Command 协议应包含 extra_fate：%s" % str(命格解码))
	检(_播报次数(4501) == 1, "【技之剑意】发动应播报一次，实际 %d 次" % _播报次数(4501))
	# 限制写在它授予的那份行动里（命格规则），由引擎按卡库现算，与授予那一刻的手牌无关
	var 技数据: Dictionary = 玩家.额外行动数据(4501)
	var 技白: Array = 引擎.额外行动出牌白名单(技数据)
	检(技白.has(技击甲.id) and not 技白.has(非技击.id),
		"4501 的可用牌应只含技类命格攻击牌：%s" % str(技白))
	检(引擎.校验额外行动限制(玩家, 技数据, GConst.ActionType.Attack, [非技击.id], [2])
		!= GConst.GE_SUCCESS, "4501 的额外攻击用非技类攻击牌应被驳回")
	检(引擎.校验额外行动限制(玩家, 技数据, GConst.ActionType.Attack, [技击甲.id], [2])
		== GConst.GE_SUCCESS, "4501 的额外攻击用技类攻击牌应通过")
	# 服务端驳回后必须仍停在这份额外行动：退回普通行动阶段会让客户端整排额外行动按钮消失
	发送记录.clear()
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [非技击.id], "dst_ids": [2], "args": []})
	引擎.run()
	var 有驳回: bool = false
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) == GConst.Msg.ErrorInput:
			有驳回 = true
			break
	检(有驳回, "额外行动里出非技类攻击牌应回 ErrorInput")
	检(引擎.行动额外 and 引擎.行动额外来源 == 4501,
		"驳回后应仍停在这份额外行动（额外=%s 来源=%s）"
		% [str(引擎.行动额外), str(引擎.行动额外来源)])
	检(引擎._await_kind == GConst.Msg.Action and 引擎._await_id == 1,
		"驳回后应重新问这份额外行动（等待 %s/%s）" % [str(引擎._await_id), str(引擎._await_kind)])
	var 驳回后询问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	检(not 驳回后询问.is_empty()
		and int((驳回后询问[0] as Dictionary).get("extra_fate", 0)) == GConst.FatePattern.Martial,
		"驳回后的询问仍应带命格限制")
	# 对照 4504：它的额外攻击行动不限制出牌
	玩家.add_action(GConst.ActionType.Attack, 4504, true, true)
	检(引擎.校验额外行动限制(玩家, 玩家.额外行动数据(4504), GConst.ActionType.Attack,
		[非技击.id], [2]) == GConst.GE_SUCCESS, "4504 的额外攻击行动不限制出牌")

	# 客户端选牌：非技类攻击牌必须点不动（服务端白名单 + 客户端命格兜底两道）
	var 旧我: int = Logic.my_player_id
	var 旧手牌: Array[GCard] = Data.hand_cards
	var 旧实例: Array[int] = Data.hand_iids
	Logic.my_player_id = 1
	Data.hand_cards = [Data.get_card(技击甲.id), Data.get_card(非技击.id)] as Array[GCard]
	Data.hand_iids = [技击甲.id, 非技击.id]
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(1)
	窗.call("_on_command", {"cmd_type": GConst.CmdType.Action,
		"commands": 引擎._最后询问.get(1, {}).get("commands", [])})
	await 等帧(1)
	检(bool(窗.call("_卡牌能点", 技击甲.id)), "技类攻击牌在 4501 额外行动里应可点")
	检(not bool(窗.call("_卡牌能点", 非技击.id)), "非技类攻击牌在 4501 额外行动里应点不动")
	# 切到这份额外行动时，旧选择里不合法的牌要被收起（否则提交必被驳回、界面闪一下）
	var 当前uid: int = int(额外命令.get("extra_uid", 0))
	窗.set("_sel_cards", [非技击.id, 技击甲.id] as Array[int])
	窗.call("_本地选择额外攻击", 0, 当前uid, 4501, [], [], GConst.ActionType.Attack)
	检(not (窗.get("_sel_cards") as Array).has(非技击.id),
		"切到技类额外行动后，非技类牌应从已选里收起：%s" % str(窗.get("_sel_cards")))
	检((窗.get("_sel_cards") as Array).has(技击甲.id),
		"技类攻击牌应保留在已选里：%s" % str(窗.get("_sel_cards")))
	# 没有牌号名单、切换列表也清空时，仍按询问里的 extra_fate 拦（纯靠牌面命格字段）
	窗.set("_当前额外攻击选择", 0)
	窗.set("_额外攻击切换项", [])
	窗.set("_额外手牌白名单_选择", [])
	窗.set("_行动命令", [{"respond_id": GConst.ActionType.Attack, "card_ids": [], "dst_ids": []}])
	检(bool(窗.call("_卡牌能点", 技击甲.id)), "没有牌号名单时，技类攻击牌仍应可点")
	检(not bool(窗.call("_卡牌能点", 非技击.id)), "没有牌号名单时，命格限制仍应拦住非技类攻击牌")
	窗.queue_free()
	await 等帧(1)
	Data.hand_cards = 旧手牌
	Data.hand_iids = 旧实例
	Logic.my_player_id = 旧我

	# 手里没有技类攻击牌：照样自动给（打不出去就在那个阶段点「放弃行动」）
	_重置战斗()
	_给牌(玩家, 非技击.id)
	_打一次攻击(非技击, 2)
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 4501,
		"手里没有技类攻击牌也应自动给 4501 的额外攻击行动（当前 %d）" % 引擎.current_id)
	var 空手白: Array = 引擎.额外行动出牌白名单(玩家.额外行动数据(4501))
	检(空手白.has(技击甲.id) and not 空手白.has(非技击.id),
		"手里没有技类攻击牌时，4501 的白名单仍应只含技类攻击牌：%s" % str(空手白))
	检(玩家.attack_action_count == 1, "真实攻击后本回合攻击行动计数应为 1，实际 %d"
		% 玩家.attack_action_count)

	# ============================================================
	# 4502 臆想剑
	# ============================================================
	# 攻击牌分支：目标弃 1 张攻击牌【展示】→ 可选择获得 → 获得 + 额外攻击行动
	_重置战斗()
	_给牌(靶, 攻击牌.id)
	var 臆想上下文: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	var r4502: int = 角色.p_timeline_2_hit(臆想上下文)
	检(r4502 == BattleRole.WAIT, "主动攻击命中且有可用目标手牌时应问是否发动【臆想剑】")
	检(not _取询问(1, 4502).is_empty(), "没有下发【臆想剑】询问")
	_应答([1])
	r4502 = 角色.p_timeline_2_hit(臆想上下文)
	检(r4502 == BattleRole.WAIT, "发动【臆想剑】后应让目标选择要弃的牌")
	var 弃牌问: Dictionary = _取询问(2, 4502)
	检(not 弃牌问.is_empty(), "没有向目标下发【臆想剑】弃牌询问")
	检(int((弃牌问.get("args", [0]) as Array)[0]) == 1, "【臆想剑】应要求目标弃 1 张牌")
	检(not bool(弃牌问.get("can_cancel", true)), "【臆想剑】的目标弃牌是强制的，不能取消")
	# 空回复：按【强制】口径从目标手牌补齐
	_应答([])
	r4502 = 角色.p_timeline_2_hit(臆想上下文)
	检(r4502 == BattleRole.URGENT,
		"目标弃牌【展示】后应先返回 URGENT 让展示响应结算，不能抢先问是否获得")
	检(not 靶.hand_cards.has(攻击牌.id), "【臆想剑】的弃牌应离开目标手牌")
	检(引擎.deck.discard.has(攻击牌.id), "【臆想剑】的弃牌应先进弃牌堆")
	检(not 玩家.hand_cards.has(攻击牌.id), "回答获得之前不应已经把牌拿进手里")
	检(引擎._await_id == -1, "展示响应结算前不应下发「是否获得」询问（当前在等 %d）"
		% 引擎._await_id)
	引擎.run()
	检(引擎._await_id == -1, "没有等待型展示响应时应能直接结算完（当前在等 %d）" % 引擎._await_id)
	r4502 = 角色.p_timeline_2_hit(臆想上下文)
	检(r4502 == BattleRole.WAIT, "展示响应结算后才应问是否获得该牌")
	# 「是否获得」给两个选项：第一个「获得 <卡名>」并带 card_id（客户端悬停摊卡面），第二个「不获得」
	var 获得问: Dictionary = _取询问(1, 4502)
	var 询问参数: Array = 获得问.get("args", [])
	检(询问参数.size() >= 6 and int(询问参数[3]) == 2,
		"「是否获得」应给 2 个选项（实际 args=%s）" % str(询问参数))
	检(int(询问参数[4]) == 1 and int(询问参数[5]) == 2 if 询问参数.size() >= 6 else false,
		"两个选项的值应分别是 1（获得）/ 2（不获得）")
	var 选项文案: Array = 获得问.get("notes", [])
	检(选项文案.size() == 2, "两个选项都应带文案")
	检(not 选项文案.is_empty() and str(选项文案[0]).begins_with("获得"),
		"第一个选项应写成「获得 <卡名>」（实际 %s）" % (str(选项文案[0]) if not 选项文案.is_empty() else ""))
	检(选项文案.size() == 2 and str(选项文案[1]) == "不获得", "第二个选项应是「不获得」")
	var 选项牌: Array = 获得问.get("option_card_ids", [])
	检(not 选项牌.is_empty() and int(选项牌[0]) == 攻击牌.id,
		"第一个选项要带这张攻击牌（牌面），供客户端悬停摊卡面")
	_应答([1])
	r4502 = 角色.p_timeline_2_hit(臆想上下文)
	检(r4502 == BattleRole.SUCCESS, "获得攻击牌后【臆想剑】应正常收尾")
	检(玩家.hand_cards.has(攻击牌.id), "选择获得后该攻击牌应进入发动者手牌")
	检(not 引擎.deck.discard.has(攻击牌.id), "选择获得后该牌应从弃牌堆移除")
	检(_有额外行动(4502), "获得攻击牌后应额外 +1 攻击行动")
	检(int((臆想上下文.get("harm", {}) as Dictionary).get("point", 0)) == BattleEngine.ATTACK_BASE_POINT,
		"攻击牌分支不应改变本次攻击伤害")
	检(_播报次数(4502) == 1, "【臆想剑】发动应播报一次，实际 %d 次" % _播报次数(4502))

	# 法术牌分支：本次攻击伤害 +2，不询问获得
	_重置战斗()
	_给牌(靶, 法术牌.id)
	var 法术上下文: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_hit(法术上下文) == BattleRole.WAIT, "命中时应先问是否发动【臆想剑】")
	_应答([1])
	检(角色.p_timeline_2_hit(法术上下文) == BattleRole.WAIT, "发动后应让目标选牌")
	_应答([1], [法术牌.id])
	r4502 = 角色.p_timeline_2_hit(法术上下文)
	检(r4502 == BattleRole.URGENT, "目标弃出法术牌【展示】后应先返回 URGENT 让展示响应结算")
	引擎.run()
	r4502 = 角色.p_timeline_2_hit(法术上下文)
	检(r4502 == BattleRole.SUCCESS, "展示响应结算后法术牌分支应直接收尾")
	检(int((法术上下文.get("harm", {}) as Dictionary).get("point", 0))
		== BattleEngine.ATTACK_BASE_POINT + 2, "法术牌分支应让本次攻击伤害 +2")
	检(引擎.deck.discard.has(法术牌.id), "目标的法术牌应进弃牌堆")
	检(_有额外行动(4502) == false, "法术牌分支不应给额外攻击行动")

	# 放弃发动：不弃牌、不获得
	_重置战斗()
	_给牌(靶, 攻击牌.id)
	var 放弃上下文: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_hit(放弃上下文) == BattleRole.WAIT, "命中时应先问是否发动【臆想剑】")
	_应答([0])
	检(角色.p_timeline_2_hit(放弃上下文) == BattleRole.SUCCESS, "不发动【臆想剑】应直接收尾")
	检(靶.hand_cards.has(攻击牌.id), "不发动【臆想剑】不应让目标弃牌")

	# 选第二个选项「不获得」：不给额外行动，牌留在弃牌堆
	_重置战斗()
	_给牌(靶, 攻击牌.id)
	var 不获得上下文: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_hit(不获得上下文) == BattleRole.WAIT, "命中时应先问是否发动【臆想剑】")
	_应答([1])
	检(角色.p_timeline_2_hit(不获得上下文) == BattleRole.WAIT, "发动后应让目标选牌")
	_应答([1], [攻击牌.id])
	检(角色.p_timeline_2_hit(不获得上下文) == BattleRole.URGENT,
		"目标弃出攻击牌【展示】后应先返回 URGENT 让展示响应结算")
	引擎.run()
	检(角色.p_timeline_2_hit(不获得上下文) == BattleRole.WAIT,
		"展示响应结算后才应问是否获得")
	检(_有额外行动(4502), "额外 +1【攻击行动】与是否获得无关：问之前就该给出")
	_应答([2])
	检(角色.p_timeline_2_hit(不获得上下文) == BattleRole.SUCCESS, "选「不获得」应正常收尾")
	检(引擎.deck.discard.has(攻击牌.id), "不获得时该牌应留在弃牌堆")
	检(not 玩家.hand_cards.has(攻击牌.id), "选「不获得」不应把牌拿进手里")
	检(_有额外行动(4502), "选「不获得」仍应保留额外 +1【攻击行动】")

	# 回合限定：本回合发动过就不再问；回合开始重置
	_重置战斗()
	_给牌(靶, 攻击牌.id)
	var 限定上下文: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	检(角色.p_timeline_2_hit(限定上下文) == BattleRole.WAIT, "命中时应先问是否发动【臆想剑】")
	_应答([0])
	检(角色.p_timeline_2_hit(限定上下文) == BattleRole.SUCCESS, "不发动应直接收尾")
	# 不发动不消耗回合限定；新的一次命中的 ctx 是新的，应重新询问
	var 限定上下文2: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	_应答([1])
	检(角色.p_timeline_2_hit(限定上下文2) == BattleRole.WAIT, "新的一次命中仍应询问【臆想剑】")
	_应答([1], [攻击牌.id])
	检(角色.p_timeline_2_hit(限定上下文2) == BattleRole.URGENT,
		"目标弃出攻击牌【展示】后应先返回 URGENT 让展示响应结算")
	引擎.run()
	检(角色.p_timeline_2_hit(限定上下文2) == BattleRole.WAIT, "展示响应结算后才应问是否获得")
	# 取消 / 超时都按「不获得」：回空 args
	_应答([])
	检(角色.p_timeline_2_hit(限定上下文2) == BattleRole.SUCCESS, "取消/超时按「不获得」收尾")
	检(not 玩家.hand_cards.has(攻击牌.id), "取消/超时不应把牌拿进手里")
	检(_有额外行动(4502), "取消/超时只影响是否获得，额外 +1【攻击行动】照给")
	引擎._清空等待()
	检(角色.p_timeline_2_hit(_攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "回合限定：本回合发动过【臆想剑】后不应再询问")
	角色.p_before_turn_begin({})
	_给牌(靶, 攻击牌.id)
	引擎._清空等待()
	检(角色.p_timeline_2_hit(_攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.WAIT, "新回合应重新可以发动【臆想剑】")

	# 非主动攻击 / 别人攻击 / 目标无手牌：不触发
	_重置战斗()
	_给牌(靶, 攻击牌.id)
	检(角色.p_timeline_2_hit(_攻击上下文(非技击, 1, 2, false, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "应战反击（非主动攻击）命中不应触发【臆想剑】")
	检(角色.p_timeline_2_hit(_攻击上下文(非技击, 2, 1, true, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "别人的主动攻击命中不应触发【臆想剑】")
	靶.hand_cards.clear()
	检(角色.p_timeline_2_hit(_攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT))
		== BattleRole.SUCCESS, "目标没有手牌时不应询问【臆想剑】")

	# ============================================================
	# 4503 梦想剑
	# ============================================================
	_重置战斗()
	玩家.reset_action_counts()
	for 次数: int in range(1, 5):
		# 记录行动在攻击宣告前 +1；宣告时不应变绿，等攻击结算完进入「攻击结束」响应才推进
		var 宣告前档: int = 角色.dream_tier()
		玩家.record_action("attack", false)
		角色.p_timeline_1({"src": 1, "is_active": true})
		检(角色.dream_tier() == 宣告前档,
			"第 %d 次攻击宣告时不应提前变绿" % 次数)
		# 展示档是 p_after_attack 自身的职责（行动选项已交给聚合器），这里单独验证钩子推进
		角色.p_after_attack({"player": 1, "kind": "attack"})
		if 次数 == 1:
			检(角色.dream_tier() == 1 and not 角色.dream_ignore_shield,
				"第 1 次攻击结束响应时应显示档位 1，但效果尚未生效")
		elif 次数 == 2:
			检(角色.dream_tier() == 2 and not 角色.dream_no_reattack,
				"第 2 次攻击结束响应时应显示档位 2，但效果尚未生效")
		elif 次数 == 3:
			检(角色.dream_tier() == 2, "第 3 次攻击结束响应时展示档仍应为 2")
		else:
			检(角色.dream_tier() == 3 and not 角色.dream_no_miss,
				"第 4 次攻击结束响应时应显示档位 3，但效果尚未生效")
		角色.p_action_end({"player": 1, "kind": "attack"})
		if 次数 == 1:
			检(角色.dream_ignore_shield, "第 1 次攻击行动后梦想剑应激活「无视圣盾」")
			检(not 角色.dream_no_reattack and not 角色.dream_no_miss,
				"第 1 次攻击行动后不应同时激活后两档")
			检(角色.dream_tier() == 1, "第 1 档 dream_tier 应为 1")
		elif 次数 == 2:
			检(角色.dream_no_reattack, "第 2 次攻击行动后梦想剑应激活「无法应战」")
			检(not 角色.dream_no_miss, "第 2 次攻击行动后不应已激活「强制命中」")
			检(角色.dream_tier() == 2, "第 2 档 dream_tier 应为 2")
		elif 次数 == 3:
			检(not 角色.dream_no_miss, "第 3 次攻击行动后不应有新档位")
			检(角色.dream_tier() == 2, "第 3 次攻击行动后 dream_tier 仍应为 2")
		else:
			检(角色.dream_no_miss, "第 4 次攻击行动后梦想剑应激活「强制命中」")
			检(角色.dream_tier() == 3, "第 4 档 dream_tier 应为 3")
	检(int(玩家.to_proto(1).get("dream_tier", 0)) == 3,
		"快照应下发 dream_tier=3，供角色说明标绿")
	var 梦想主动: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
	角色.p_timeline_1(梦想主动)
	检(int(梦想主动.get("hit_rate", -1)) == GConst.HitRate.NoMiss,
		"梦想剑第 4 档应把主动攻击置为强制命中")
	检(bool(梦想主动.get("check_shield", true)) == false,
		"梦想剑第 1 档应让主动攻击无视圣盾")
	var 梦想应战: Dictionary = _攻击上下文(非技击, 1, 2, false, BattleEngine.ATTACK_BASE_POINT)
	角色.p_timeline_1(梦想应战)
	检(int(梦想应战.get("hit_rate", -1)) == GConst.HitRate.Normal,
		"梦想剑不应改应战反击的命中率")
	检(bool(梦想应战.get("check_shield", true)), "梦想剑不应改应战反击的圣盾检查")
	检(_播报次数(4503) == 3, "梦想剑第 1 / 2 / 4 档各应播报一次，实际 %d 次" % _播报次数(4503))
	# 回合开始清空档位
	角色.p_before_turn_begin({})
	检(not 角色.dream_ignore_shield and not 角色.dream_no_reattack and not 角色.dream_no_miss,
		"新回合应清空梦想剑档位")
	# 打法术行动不推进梦想剑
	玩家.reset_action_counts()
	玩家.record_action("magic", false)
	角色.p_action_end({"player": 1, "kind": "magic"})
	检(not 角色.dream_ignore_shield, "法术 / 特殊行动不应推进梦想剑")

	# ============================================================
	# 4504 剑影*断念
	# ============================================================
	# 支付真宝石 → 弃 2 张 → 摸 1 张 → 额外攻击行动
	_重置战斗()
	玩家.set_gem(1)
	_给牌(玩家, 非技击.id)
	_给牌(玩家, 攻击牌.id)
	_给牌(玩家, 法术牌.id)
	# 摸牌固定摸一张非法术 / 非技类攻击牌，避免摸到技类攻击牌后又触发 4501 询问
	var 牌库顶: GCard = _取法术([法术牌.id])
	检(牌库顶 != null, "卡库找不到第二张法术牌")
	if 牌库顶 != null:
		_设牌库顶(牌库顶.id)
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"攻击结束时应有宝石可发动【剑影*断念】")
	var 断念问: Dictionary = _取选项询问(1, 4504)
	检(not 断念问.is_empty(), "没有下发【剑影*断念】二选一询问")
	var 断念选项: Array = 断念问.get("args", [])
	var 断念下标: int = (断念选项.slice(4) as Array).find(4504)
	检(断念下标 >= 0 and int((断念问.get("option_need_cards", []) as Array)[断念下标]) == 2,
		"【剑影*断念】选项应要求选 2 张弃牌：%s" % str(断念问.get("option_need_cards", [])))
	检(玩家.gem == 1, "未确认弃牌前不应扣宝石，实际剩 %d" % 玩家.gem)
	_应答询问(1, 4504, [4504], [非技击.id, 攻击牌.id])
	检(引擎._await_id == -1, "【剑影*断念】应结算完（摸牌也应在聚合器回来前跑完）")
	检(玩家.gem == 0, "选完弃牌按确定后才扣 1 点宝石，实际剩 %d" % 玩家.gem)
	检(_播报次数(4504) == 1, "【剑影*断念】发动应播报一次，实际 %d 次" % _播报次数(4504))
	检(not 玩家.hand_cards.has(非技击.id) and not 玩家.hand_cards.has(攻击牌.id),
		"【剑影*断念】弃的 2 张牌应离开手牌")
	检(引擎.deck.discard.has(非技击.id) and 引擎.deck.discard.has(攻击牌.id),
		"【剑影*断念】弃的 2 张牌应进弃牌堆")
	检(_有额外行动(4504), "【剑影*断念】应额外 +1 攻击行动")
	检(玩家.hand_cards.size() == 2, "弃 2 张再摸 1 张后手牌应为 2 张，实际 %d 张"
		% 玩家.hand_cards.size())

	# 回合限定：本回合发动过后不再询问
	_重置战斗()
	玩家.set_gem(1)
	角色.used_jian_ying_duan_nian = true
	_给牌(玩家, 非技击.id)
	_给牌(玩家, 攻击牌.id)
	_给牌(玩家, 法术牌.id)
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == -1, "回合限定：本回合发动过【剑影*断念】后不应再询问")
	检(_取选项询问(1, 4504).is_empty(), "回合限定时不应再下发【剑影*断念】询问")
	# 新回合重置
	角色.p_before_turn_begin({})
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"新回合应重新可以发动【剑影*断念】")

	# 只有水晶（没有真宝石）不能发动：费用必须是真宝石
	_重置战斗()
	玩家.set_crystal(3)
	_给牌(玩家, 非技击.id)
	_给牌(玩家, 攻击牌.id)
	_给牌(玩家, 法术牌.id)
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == -1, "【剑影*断念】的【宝石】费用不能用【水晶】顶")
	检(_取选项询问(1, 4504).is_empty(), "没有真宝石时不应下发【剑影*断念】询问")

	# 没有宝石 / 手牌不足 2 张：不询问
	_重置战斗()
	玩家.set_crystal(0)
	玩家.set_gem(0)
	_给牌(玩家, 非技击.id)
	_给牌(玩家, 攻击牌.id)
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == -1, "没有宝石时不应询问【剑影*断念】")
	_重置战斗()
	玩家.set_gem(1)
	_给牌(玩家, 非技击.id)
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == -1, "手里不足 2 张牌时不应询问【剑影*断念】")

	# 取消发动：不支付宝石、不弃牌、不给额外行动
	_重置战斗()
	玩家.set_gem(1)
	_给牌(玩家, 非技击.id)
	_给牌(玩家, 攻击牌.id)
	_给牌(玩家, 法术牌.id)
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"有宝石时应先问是否发动【剑影*断念】")
	_应答询问(1, 4504, [])
	检(引擎._await_id == -1, "不发动【剑影*断念】应直接收尾")
	检(玩家.gem == 1, "不发动【剑影*断念】不应支付宝石")
	检(玩家.hand_cards.size() == 3, "不发动【剑影*断念】不应弃牌")
	检(_有额外行动(4504) == false, "不发动【剑影*断念】不应给额外攻击行动")

	# 4501 已改为自动生效：攻击结束后它直接进队列，聚合器只问 4504
	_重置战斗()
	玩家.set_gem(1)
	_给牌(玩家, 技击甲.id)
	_给牌(玩家, 非技击.id)
	_驱动攻击结束({"card_id": 0, "dst": 2})
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"有宝石时应问 4504")
	检(_有额外行动(4501), "4501 应在攻击结束时自动进入额外行动队列")
	检(_取询问(1, 4501).is_empty(), "4501 不应再作为选项出现在聚合器询问里")
	var 只问断念: Dictionary = _取询问(1, 4504)
	检(not 只问断念.is_empty(), "没有下发【剑影*断念】询问")
	var 断念参数: Array = 只问断念.get("args", [])
	检(断念参数.size() >= 5 and int(断念参数[3]) == 1 and int(断念参数[4]) == 4504,
		"聚合器只应问 4504：%s" % str(断念参数))
	检(bool(GConst.技能指示器.get(4504, {}).get("攻击结束二选一", false)),
		"4504 二选一应配「攻击结束二选一」")
	# 攻击结束响应里的额外攻击快捷按钮数据（4501 已进队列）必须过协议
	var 额外编码: PackedByteArray = ProtoCodec.encode_named("Command",
		{"extra_attack_causes": [4501]})
	var 额外解码: Dictionary = ProtoCodec.decode_named("Command", 额外编码)
	检((额外解码.get("extra_attack_causes", []) as Array) == [4501],
		"Command 协议应包含 extra_attack_causes：%s" % str(额外解码.get("extra_attack_causes", [])))
	_应答询问(1, 4504, [])
	检(玩家.gem == 1, "取消 4504 不应支付宝石")
	检(_有额外行动(4501), "取消 4504 后 4501 的额外行动应保留")
	# 这个用例是直接驱动 p_after_attack、没有压 STurnEnd：手动补一次「回合结束」让它进入额外行动阶段
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎.current_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 4501,
		"回合结束时应进入 4501 的额外攻击行动（当前 %d / 额外 %s / 来源 %s）"
		% [引擎.current_id, str(引擎.行动额外), str(引擎.行动额外来源)])

	# 自己的额外行动阶段结束后，别家的攻击结束钩子不应处理
	_重置战斗()
	检(角色.p_after_attack({"player": 2, "kind": "attack"}) == BattleRole.SUCCESS,
		"别人的攻击结束不应由剑之魔女处理")
	检(角色.p_action_end({"player": 2, "kind": "attack"}) == BattleRole.SUCCESS,
		"别人的攻击行动结束不应推进剑之魔女的梦想剑")

	# ============================================================
	# 4502 时序回归：目标弃牌【展示】触发等待型 p_show_hand 时，先结算展示再问获得
	# （评审复现：目标为圣女、弃【水涟斩】触发 603【冰霜祷言】时，剑之魔女曾被连问两次
	#   「是否获得」，第一次回答被丢弃，展示响应还排在获得询问之后。）
	# ============================================================
	_重置战斗()
	# 临时把圣女挂到目标身上，产生真实的等待型 p_show_hand（本用例结束时摘掉）
	靶.role_id = 6
	var 圣女: BattleRole = 圣女脚本.new()
	圣女.setup(靶, 引擎)
	靶.role = 圣女
	var 水系攻击: GCard = _取水系攻击()
	检(水系攻击 != null, "卡库找不到水系攻击牌，无法触发圣女【冰霜祷言】")
	if 水系攻击 != null:
		_给牌(靶, 水系攻击.id)
		var 展示顺序上下文: Dictionary = _攻击上下文(非技击, 1, 2, true, BattleEngine.ATTACK_BASE_POINT)
		检(角色.p_timeline_2_hit(展示顺序上下文) == BattleRole.WAIT, "应先问是否发动【臆想剑】")
		_应答([1])
		检(角色.p_timeline_2_hit(展示顺序上下文) == BattleRole.WAIT, "发动后应让目标选牌")
		# 从这里开始只数「是否获得」的询问（发动询问已在上一步下发过）
		发送记录.clear()
		_应答([1], [水系攻击.id])
		检(角色.p_timeline_2_hit(展示顺序上下文) == BattleRole.URGENT,
			"目标弃牌【展示】后应先返回 URGENT 让展示响应结算，不能抢先问是否获得")
		检(_询问次数(1, 4502) == 0,
			"展示响应结算前不应下发「是否获得」询问，实际 %d 次" % _询问次数(1, 4502))
		检(引擎._await_id == -1, "展示响应结算前应没有人在等待（当前 %d）" % 引擎._await_id)
		引擎.run()
		检(引擎._await_id == 2 and not _取询问(2, 603).is_empty(),
			"目标弃出水系牌应等待圣女【冰霜祷言】响应（当前在等 %d）" % 引擎._await_id)
		检(_询问次数(1, 4502) == 0, "展示响应还没结算完就不应问是否获得")
		引擎.on_message(2, GConst.Msg.Respond, {
			"respond_id": 603, "src_id": 2, "args": [1], "card_ids": [], "dst_ids": [2],
		})
		检(靶.cross_num == 1, "【冰霜祷言】结算后目标应 +1 治疗，实际 %d" % 靶.cross_num)
		检(引擎._await_id == -1, "展示响应结算完、钩子重入前不应有人被问")
		# 重入（对应引擎 SHook 在展示响应结算后重新调用本钩子）
		var 重入结果: int = 角色.p_timeline_2_hit(展示顺序上下文)
		检(重入结果 == BattleRole.WAIT, "展示响应结算后才应询问是否获得该攻击牌")
		检(_询问次数(1, 4502) == 1,
			"「是否获得」询问只应下发一次，实际 %d 次" % _询问次数(1, 4502))
		检(引擎._await_id == 1, "获得询问应等剑之魔女回答（当前在等 %d）" % 引擎._await_id)
		_应答([1])
		检(角色.p_timeline_2_hit(展示顺序上下文) == BattleRole.SUCCESS,
			"回答获得后【臆想剑】应正常收尾")
		检(_询问次数(1, 4502) == 1, "收尾时不应重复下发「是否获得」询问")
		检(玩家.hand_cards.has(水系攻击.id), "选择获得后该攻击牌应进入发动者手牌")
		检(_有额外行动(4502), "获得攻击牌后应额外 +1 攻击行动")
	# 摘掉临时挂上的圣女，避免影响后续（后面已无其它用例）
	靶.role = null

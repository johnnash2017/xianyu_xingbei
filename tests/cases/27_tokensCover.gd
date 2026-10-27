extends 自检用例
## F3 指示物 / 盖牌通用能力：
## - 初始化：槽 0 / 1 的计数指示物与槽 2 的盖牌上限按角色表初始化；没有角色脚本的白板角色也能初始化；
##   38 子弹（盖牌槽 2，上限 6）、46 灵涌（槽 0，上限 4）、93 元子（槽 0，上限 3）；
## - 上限：加指示物按角色表上限截断、不会超；盖牌超限交给引擎 SCoverOverflow 让所有者弃到上限；
## - 消耗：扣指示物不足时不扣；盖牌可移除；draw_cover 从牌库顶取牌且不超过盖牌槽上限；
## - UI：玩家面板按角色显示不同名字 / 上限（子弹盖牌 6/6、灵涌 3/4、元子 2/3），
##   角色技能提示的「专属标识物」也按角色区分；对局快照的指示物字段与客户端名称一致。

var 引擎: BattleEngine = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []
var 玩家38: BattlePlayer = null
var 玩家46: BattlePlayer = null
var 玩家93: BattlePlayer = null
var 玩家白板: BattlePlayer = null


func _init() -> void:
	名称 = "指示物与盖牌"


## 清空战斗状态：回到「轮到玩家 1、行动阶段」的同一起点（保留指示物 / 盖牌数据）
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	发送记录.clear()


## 是否广播过某枚指示物的变化日志（按角色表名字写，如【灵涌】）
func _有指示物日志(名字: String) -> bool:
	for 记录: Dictionary in 发送记录:
		if int(记录["msg"]) != GConst.Msg.Gossip:
			continue
		var 数据: Dictionary = 记录["data"]
		if int(数据.get("type", -1)) == GConst.GossipType.Token \
				and str(数据.get("txt", "")).contains("【%s】" % 名字):
			return true
	return false


## 点开某枚指示物的悬停提示，返回文案（「名字 当前/上限」）
func _读面板提示(面板: 战斗玩家面板, 槽: int, 标签: Label) -> String:
	var 提示: Array[String] = []
	面板.状态图标悬停.connect(func(_图标: Control, 文本: String, _牌id: int, _大图: bool) -> void:
		提示.append(文本))
	面板.call("_报告指示物悬停", 槽, 标签.get_parent())
	return 提示[0] if not 提示.is_empty() else ""


## 造一块玩家面板并把它设为某角色（会按角色表创建 token0/1/2）
func _建面板(角色号: int) -> 战斗玩家面板:
	var 面板: 战斗玩家面板 = (load("res://scenes/prefabs/battlemobile/PlayerOtherPanel.tscn") as PackedScene).instantiate()
	add_child(面板)
	面板.set("RoleID", 角色号)
	return 面板


func 跑() -> void:
	await 等帧(2)

	# ---- 1) 数据：三名角色的指示物名称 / 上限来自角色表，互不串名 ----
	var 子弹: Dictionary = Data.role_token_def(38, 2)
	var 灵涌: Dictionary = Data.role_token_def(46, 0)
	var 元子: Dictionary = Data.role_token_def(93, 0)
	检(str(子弹.get("name", "")) == "子弹" and int(子弹.get("max", 0)) == 6,
		"38 游击士的槽 2 应是【子弹】上限 6：%s" % str(子弹))
	检(str(灵涌.get("name", "")) == "灵涌" and int(灵涌.get("max", 0)) == 4,
		"46 灵熙之潮的槽 0 应是【灵涌】上限 4：%s" % str(灵涌))
	检(str(元子.get("name", "")) == "元子" and int(元子.get("max", 0)) == 3,
		"93 见习制片的槽 0 应是【元子】上限 3：%s" % str(元子))
	检(Data.role_token_def(38, 0).is_empty() and Data.role_token_def(46, 2).is_empty()
			and Data.role_token_def(93, 1).is_empty(), "角色没配的槽位不应读到别人的指示物定义")
	检(Data.role_token_def(1, 2).is_empty(), "没有指示物的角色（风之剑圣）不该读到槽 2 定义")

	# ---- 2) 初始化：没有角色脚本的白板角色也能按表初始化（槽 2 只写盖牌上限，不建 token）----
	var 白板38: BattlePlayer = BattlePlayer.new(99, GConst.BLUE, "无脚本游击士")
	白板38.role_id = 38
	白板38.按表初始化指示物()
	检(白板38.cover_cards_max == 6 and 白板38.cover_cards.is_empty(),
		"白板 38 的盖牌槽上限应为 6、盖牌区为空：%d / %d" % [白板38.cover_cards_max, 白板38.cover_cards.size()])
	检(白板38.token_def(0).is_empty(), "38 的槽 0 不应有 token（子弹是槽 2 的盖牌）")
	var 白板46: BattlePlayer = BattlePlayer.new(98, GConst.BLUE, "无脚本灵熙")
	白板46.role_id = 46
	白板46.按表初始化指示物()
	检(白板46.token_name(0) == "灵涌" and 白板46.token_max(0) == 4 and 白板46.token_num(0) == 0,
		"白板 46 的灵涌应按角色表初始化成 0/4：%s" % str(白板46.token_def(0)))
	var 白板93: BattlePlayer = BattlePlayer.new(97, GConst.BLUE, "无脚本制片")
	白板93.role_id = 93
	白板93.按表初始化指示物()
	检(白板93.token_name(0) == "元子" and 白板93.token_max(0) == 3 and 白板93.token_num(0) == 0,
		"白板 93 的元子应按角色表初始化成 0/3：%s" % str(白板93.token_def(0)))

	# ---- 3) 对局开局：38 / 46 / 93 的指示物与盖牌区在真实引擎启动后可用 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "游击士")
	引擎.add_player(2, GConst.BLUE, "灵熙")
	引擎.add_player(3, GConst.RED, "制片")
	引擎.add_player(4, GConst.RED, "白板")
	引擎.start_with_roles({1: 38, 2: 46, 3: 93, 4: 1})
	玩家38 = 引擎.p(1)
	玩家46 = 引擎.p(2)
	玩家93 = 引擎.p(3)
	玩家白板 = 引擎.p(4)
	检(玩家38 != null and 玩家46 != null and 玩家93 != null and 玩家白板 != null,
		"引擎开局后应能取到四名玩家")
	if 玩家38 == null or 玩家46 == null or 玩家93 == null or 玩家白板 == null:
		return
	检(玩家38.cover_cards_max == 6, "开局后 38 的盖牌槽上限应为 6，实际 %d" % 玩家38.cover_cards_max)
	检(玩家46.token_name(0) == "灵涌" and 玩家46.token_max(0) == 4,
		"开局后 46 的灵涌定义不对：%s" % str(玩家46.token_def(0)))
	检(玩家93.token_name(0) == "元子" and 玩家93.token_max(0) == 3,
		"开局后 93 的元子定义不对：%s" % str(玩家93.token_def(0)))
	检(玩家白板.token_def(0).is_empty() and 玩家白板.cover_cards_max == 0,
		"没有指示物的角色不应有 token / 盖牌槽")

	# ---- 4) 上限与消耗：加指示物按上限截断；扣不够时不扣；清空返回实际数量 ----
	玩家46.clear_token(0)
	检(玩家46.add_token(0, 3) == 3, "46 灵涌 0→3 应实际加 3：%d" % 玩家46.token_num(0))
	检(玩家46.add_token(0, 3) == 1 and 玩家46.token_num(0) == 4,
		"46 灵涌上限 4，3→4 只能再加 1：%d" % 玩家46.token_num(0))
	检(玩家46.add_token(0, 1) == 0 and 玩家46.token_num(0) == 4,
		"46 灵涌已满时不应再加：%d" % 玩家46.token_num(0))
	检(玩家46.remove_token(0, 1) and 玩家46.token_num(0) == 3, "46 灵涌应能扣 1 点")
	检(not 玩家46.remove_token(0, 9) and 玩家46.token_num(0) == 3,
		"46 灵涌不够扣时不应改动：%d" % 玩家46.token_num(0))
	检(玩家46.clear_token(0) == 3 and 玩家46.token_num(0) == 0, "46 灵涌 clear_token 应清空并返回 3")
	检(玩家46.set_token_num(0, 99) == 4, "set_token_num 应按上限夹到 4，实际 %d" % 玩家46.token_num(0))
	玩家46.set_token_num(0, 2)
	检(玩家46.token_num(0) == 2, "set_token_num 设 2 后灵涌应为 2")
	检(玩家93.add_token(0, 2) == 2 and not 玩家93.remove_token(0, 3),
		"93 元子加 2 后扣 3 应失败（不足），实际 %d" % 玩家93.token_num(0))
	检(玩家93.remove_token(0, 2) and 玩家93.token_num(0) == 0, "93 元子应能扣 2")
	玩家93.set_token_num(0, 2)
	检(玩家白板.add_token(0, 1) == 0 and 玩家白板.remove_token(0, 1) == false,
		"没有指示物的角色加 / 扣槽 0 都应失败")

	# 指示物变化日志用角色表名字（客户端 / 日志里显示【灵涌】，不是写死 46 或“指示物”）
	_重置战斗()
	引擎.push(BattleEngine.SDraw.new(1, 0))
	引擎.run()
	检(_有指示物日志("灵涌"), "灵涌变化没有按角色表名字广播【灵涌】日志")

	# ---- 5) 开局 6 子弹 / 盖牌上限 / 消耗：draw_cover 从牌库顶取，且不超过上限 ----
	_重置战斗()
	玩家38.cover_cards.clear()
	var 牌库前: int = 引擎.deck.pile_size()
	var 发出: int = 引擎.draw_cover(1, 6, 1, 0)
	检(发出 == 6 and 玩家38.cover_count() == 6,
		"38 应从牌库取 6 张作子弹（实际 %d / 盖牌 %d）" % [发出, 玩家38.cover_count()])
	检(引擎.deck.pile_size() == 牌库前 - 6, "draw_cover 取的牌应从牌库移除")
	检(not 玩家38.can_add_cover_cards(1) and 玩家38.cover_space() == 0,
		"盖牌满 6 张时 can_add_cover_cards / cover_space 应判为不能再放")
	检(引擎.draw_cover(1, 1, 1, 0) == 0, "盖牌已满时 draw_cover 应返回 0、不超上限")
	var 一颗: int = 玩家38.cover_cards[0]
	引擎.remove_cover(1, [一颗], 1, 0)
	检(玩家38.cover_count() == 5 and not 玩家38.cover_cards.has(一颗),
		"消耗 1 颗子弹后盖牌区应剩 5 张且不再包含它")
	检(玩家38.can_add_cover_cards(1) and 玩家38.cover_space() == 1,
		"消耗 1 颗后应能再放 1 张盖牌")
	检(引擎.draw_cover(1, 2, 1, 0) == 1 and 玩家38.cover_count() == 6,
		"空出 1 个槽时 draw_cover 最多补 1 张")

	# ---- 6) 盖牌上限：超过上限由引擎 SCoverOverflow 交给所有者选牌弃到上限 ----
	_重置战斗()
	var 超出: Array[int] = 引擎.deck.draw(2)
	玩家38.add_cover_cards(超出)
	检(玩家38.cover_count() == 8, "用例前提：盖牌区应有 8 张（上限 6）")
	var 弃牌前: int = 引擎.deck.discard_size()
	引擎.push(BattleEngine.SCoverOverflow.new())
	引擎.run()
	检(引擎._await_id == 1, "盖牌超限应询问盖牌所有者（38）选牌弃掉，等待 %s" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.DiscardCover,
		"src_id": 1,
		"args": [1, GConst.CAUSE_OVERLOAD, 2],
		"card_ids": [超出[0]],
		"dst_ids": [],
	})
	检(玩家38.cover_count() == 6, "盖牌超限结算后应只剩上限 6 张，实际 %d" % 玩家38.cover_count())
	检(not 玩家38.cover_cards.has(超出[0]), "选中的超限盖牌应离开盖牌区")
	检(引擎.deck.discard_size() == 弃牌前 + 2, "超限弃掉的 2 张应进弃牌堆")

	# ---- 7) 对局快照：槽 0 → third_token、槽 2 → covered_count，客户端名称 / 上限按角色区分 ----
	var 快照46: Dictionary = 玩家46.to_proto(2)
	检(int(快照46.get("third_token", -1)) == 2, "46 的灵涌应通过 third_token 下发：%s" % str(快照46.get("third_token")))
	var 视图46: GPlayer = GPlayer.new(2, GConst.BLUE, "灵熙")
	Data._apply_player_info(视图46, 快照46)
	检(视图46.tokens[0] != null and 视图46.tokens[0].token_name == "灵涌"
			and 视图46.tokens[0].max_num == 4 and 视图46.tokens[0].num == 2,
		"客户端 46 的灵涌名称 / 上限 / 数值不对：%s" % str(视图46.tokens[0]))
	var 快照38: Dictionary = 玩家38.to_proto(1)
	检(int(快照38.get("covered_count", -1)) == 6 and int(快照38.get("max_covered", -1)) == 6,
		"38 的子弹数 / 上限应通过 covered_count / max_covered 下发：%s"
			% str([快照38.get("covered_count"), 快照38.get("max_covered")]))
	var 视图38: GPlayer = GPlayer.new(1, GConst.BLUE, "游击士")
	Data._apply_player_info(视图38, 快照38)
	检(视图38.tokens[2] != null and 视图38.tokens[2].token_name == "子弹"
			and 视图38.tokens[2].num == 6 and 视图38.tokens[2].max_num == 6,
		"客户端 38 的子弹名称 / 上限 / 数值不对：%s" % str(视图38.tokens[2]))
	var 快照93: Dictionary = 玩家93.to_proto(3)
	var 视图93: GPlayer = GPlayer.new(3, GConst.RED, "制片")
	Data._apply_player_info(视图93, 快照93)
	检(视图93.tokens[0] != null and 视图93.tokens[0].token_name == "元子"
			and 视图93.tokens[0].max_num == 3 and 视图93.tokens[0].num == 2,
		"客户端 93 的元子名称 / 上限 / 数值不对：%s" % str(视图93.tokens[0]))

	# ---- 8) UI：玩家面板按角色显示指示物名字 / 上限（不串角色）----
	var 面板46: 战斗玩家面板 = _建面板(46)
	await 等帧(1)
	面板46.set("YellowToken", 3)
	var 标签46: Label = 面板46.get("token0")
	检(标签46 != null and 标签46.text == "3" and 标签46.get_parent().visible,
		"46 面板的灵涌图标应显示 3 并可见")
	检(_读面板提示(面板46, 0, 标签46) == "灵涌 3/4",
		"46 面板的灵涌悬停提示不对：%s" % _读面板提示(面板46, 0, 标签46))
	面板46.queue_free()

	var 面板38: 战斗玩家面板 = _建面板(38)
	await 等帧(1)
	面板38.set("Covered", 6)
	var 标签38: Label = 面板38.get("token2")
	检(标签38 != null and 标签38.text == "6",
		"38 面板的子弹图标应显示 6")
	检(_读面板提示(面板38, 2, 标签38) == "子弹盖牌 6/6",
		"38 面板的子弹悬停提示不对：%s" % _读面板提示(面板38, 2, 标签38))
	面板38.queue_free()

	var 面板93: 战斗玩家面板 = _建面板(93)
	await 等帧(1)
	面板93.set("YellowToken", 2)
	var 标签93: Label = 面板93.get("token0")
	检(标签93 != null and 标签93.text == "2",
		"93 面板的元子图标应显示 2")
	检(_读面板提示(面板93, 0, 标签93) == "元子 2/3",
		"93 面板的元子悬停提示不对：%s" % _读面板提示(面板93, 0, 标签93))
	面板93.queue_free()

	# 角色技能提示的专属标识物一览也按角色区分
	检(角色技能提示.标识物一览(38) == "专属标识物【子弹】上限为6",
		"38 的专属标识物一览不对：%s" % 角色技能提示.标识物一览(38))
	检(角色技能提示.标识物一览(46) == "专属标识物【灵涌】上限为4",
		"46 的专属标识物一览不对：%s" % 角色技能提示.标识物一览(46))
	检(角色技能提示.标识物一览(93) == "专属标识物【元子】上限为3",
		"93 的专属标识物一览不对：%s" % 角色技能提示.标识物一览(93))
	检(角色技能提示.标识物一览(1) == "", "没有标识物的角色不该出现专属标识物一览")
	检(战斗玩家面板.指示物上限文本(6) == "6", "普通指示物上限应原样显示")

	# 收尾：别把引擎 / 面板状态留给后面的用例
	_重置战斗()

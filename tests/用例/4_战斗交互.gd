extends 自检用例
## 用例 4：新版战斗界面（BattleUIMobile）的交互 —— 出牌 / 选目标 / 确定 / 取消 / 放弃
## 不联网：直接构造假的 CmdReq（行动询问 / 应答询问）喂给容器，检查状态与控件。

func _init() -> void:
	名称 = "战斗交互"


func 跑() -> void:
	await 等帧(2)
	# 先切回大厅：免得前面用例留下的「房间等待」旧战斗界面也在监听 Logic 的信号
	UI.goto_lobby()
	await 等帧(2)

	# ---- 造一份假的对局视图数据 ----
	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	var 旧手牌: Array[GCard] = Data.hand_cards
	var 旧盖牌: Array[GCard] = Data.cover_cards
	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手A"),
		GPlayer.new(3, GConst.RED, "对手B"),
	]
	Data.player_list = 玩家
	# 给「我」一个角色号：点头像看技能说明的用例要用（0 号是白板，没有技能）
	玩家[0].role_id = 4
	# 只取非暗系攻击牌：用例 2) 要拿它自己当应战牌（暗系攻击牌不可被应战）
	var 攻击牌: Array[GCard] = []
	for c: GCard in Data.card_db:
		if c.is_attack() and c.element_enum() != GConst.CardElement.Darkness:
			攻击牌.append(c)
		if 攻击牌.size() >= 2:
			break
	检(攻击牌.size() >= 2, "卡库里找不到 2 张非暗系攻击牌，用例前提不成立")
	Data.hand_cards = 攻击牌
	Data.cover_cards = []

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	# 1920x1080 适配：这套界面的坐标是按参考工程 1280x720 的设计尺寸摆的，
	# 靠根节点「只占 1280x720 + 1.5 倍缩放」对齐本项目的 1920x1080 基准
	检(窗.size == Vector2(1280, 720) and 窗.scale == Vector2(1.5, 1.5),
		"战斗界面根节点不是 1280x720 + 1.5 倍缩放（实际 %s × %s）" % [str(窗.size), str(窗.scale)])
	# 一条对局快照：触发表板/手牌渲染
	Logic.game_info_updated.emit({"is_started": true, "room_id": 7, "blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 1, "red_gem": 1, "red_crystal": 2})
	await 等帧(2)
	# 队伍能量格也要排成一行（宝石 + 水晶共 3 格）
	var 蓝能量: GridContainer = 窗.get("BlueEnergy")
	检(蓝能量 != null and 蓝能量.get_child_count() == 3, "蓝方能量格数量不对：%s" % str(蓝能量.get_child_count() if 蓝能量 != null else -1))
	if 蓝能量 != null and 蓝能量.get_child_count() >= 2:
		var 格首: Control = 蓝能量.get_child(0) as Control
		var 格末: Control = 蓝能量.get_child(蓝能量.get_child_count() - 1) as Control
		检(is_equal_approx(格首.position.y, 格末.position.y),
			"能量格没有排成一行（首格 y=%s，末格 y=%s）" % [str(格首.position.y), str(格末.position.y)])

	# 回合高亮：轮到谁，谁面板背后的 Turn 就亮起来并走一次缩放动画（PlayerStatusMobile.TurnBegin）
	Logic.turn_changed.emit(2, 3)
	await 等帧(2)
	检(int(窗.get("_高亮玩家id")) == 2, "回合开始后没有高亮当前玩家：%s" % str(窗.get("_高亮玩家id")))
	var 高亮面板: 战斗玩家面板 = null
	var 面板id串: String = ""
	for 面板: 战斗玩家面板 in (窗.get("_面板列表") as Array):
		面板id串 += "%s=%d " % [面板.name, 面板.ID]
		if 面板 != null and 面板.ID == 2:
			高亮面板 = 面板
	var 非高亮面板: 战斗玩家面板 = 窗.get("MainPlayer")
	# 注意：PlayerStatusMobile 的 Turn 是「只写」属性（setter 只切贴图可见性，不回存字段），
	# 所以断言要看真正的贴图，不看 Turn 这个字段
	var 高亮贴图: TextureRect = null
	if 高亮面板 != null:
		高亮贴图 = 高亮面板.get("turn") as TextureRect
	var 非高亮贴图: TextureRect = null
	if 非高亮面板 != null:
		非高亮贴图 = 非高亮面板.get("turn") as TextureRect
	检(高亮贴图 != null and 高亮贴图.visible, "当前回合玩家背后的 Turn 没亮（面板 ID：%s）" % 面板id串)
	检(非高亮贴图 != null and not 非高亮贴图.visible, "不是当前回合的玩家，背后 Turn 却亮着")
	if 高亮面板 != null:
		await get_tree().create_timer(0.2).timeout
		var 高亮Turn: TextureRect = 高亮面板.get("turn") as TextureRect
		检(高亮Turn != null and 高亮Turn.scale.x < 1.95,
			"Turn 的缩放动画没跑（scale=%s，应从 2.0 缩到 1.2）" % str(高亮Turn.scale if 高亮Turn != null else Vector2.ZERO))

	# ================= 1) 行动询问 =================
	var 手牌区: Control = 窗.get("HandArea")
	检(手牌区 != null, "容器没有绑上 Root/HandArea")
	检(窗.get("BtnOK") != null and 窗.get("BtnCancel") != null, "容器没有绑上确定/取消按钮")
	if 手牌区 == null or 窗.get("BtnOK") == null:
		await _收尾(窗, 旧id, 旧玩家, 旧手牌, 旧盖牌)
		return
	检(手牌区.get_child_count() == Data.hand_cards.size(),
		"手牌区渲染了 %d 张牌，手牌实际 %d 张" % [手牌区.get_child_count(), Data.hand_cards.size()])
	# 手牌固定排成一行（不再换行）：所有牌的 y 必须一致
	if 手牌区.get_child_count() >= 2:
		var 首张: Control = 手牌区.get_child(0) as Control
		var 末张: Control = 手牌区.get_child(手牌区.get_child_count() - 1) as Control
		检(is_equal_approx(首张.position.y, 末张.position.y),
			"手牌没有排成一行（首张 y=%s，末张 y=%s）" % [str(首张.position.y), str(末张.position.y)])

	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Action,
		"commands": [{"respond_id": GConst.ActionType.Attack, "src_id": Logic.my_player_id, "args": []}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 1, "行动询问后状态不是「行动」（=1）：%d" % int(窗.get("_mode")))
	var 确定: Button = 窗.get("BtnOK")
	检(确定.visible, "行动阶段「确定」没显示")
	检(确定.disabled, "还没选牌，「确定」就已经可用")

	# 行动阶段【圣光】打不出去（只作响应 / 抵挡），必须置灰点不动
	var 圣光牌: GCard = null
	for c: GCard in Data.card_db:
		if c.card_name_enum() == GConst.CardName.HolyLight:
			圣光牌 = c
			break
	检(圣光牌 != null, "卡库里找不到【圣光】，用例前提不成立")
	if 圣光牌 != null:
		检(not bool(窗.call("_卡牌能点", 圣光牌.id)), "行动阶段【圣光】还能点（应置灰）")

	var 对手面板: Button = 窗.get("PlayerStatusMobileR")
	var 对手可选中框: TextureRect = 对手面板.get("canSelect") as TextureRect
	# 先选牌、再亮目标：还没选牌时敌方既不亮也置灰，点了也不该有任何反应
	检(对手可选中框 != null and not 对手可选中框.visible, "还没选牌，敌方目标就已经亮起")
	检(对手面板.modulate == Color(0.5, 0.5, 0.5), "还没选牌，敌方头像没有置灰：%s" % str(对手面板.modulate))
	对手面板.pressed.emit()
	await 等帧()
	检((窗.get("_sel_cards") as Array).is_empty() and (窗.get("_sel_players") as Array).is_empty(),
		"还没选牌，点敌方面板却有了反应")

	# 点第一张手牌（攻击牌）→ 选中、「确定」变可用、敌方目标亮起
	手牌区.get_child(0).call("OnCardClick")
	await 等帧()
	检((窗.get("_sel_cards") as Array).size() == 1, "点手牌后没有被选中")
	检(not 确定.disabled, "选中一张手牌后「确定」仍不可用")
	检(对手可选中框 != null and 对手可选中框.visible, "选了攻击牌后敌方目标没有亮起")
	检(对手面板.modulate == Color(1.0, 1.0, 1.0), "选了攻击牌后敌方头像没有脱离置灰：%s" % str(对手面板.modulate))

	# 点敌方头像 → 直接出手，不用再按「确定」（_清空待选 会回到等待态）
	对手面板.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0 and (窗.get("_sel_cards") as Array).is_empty(),
		"点敌方头像没有直接发起攻击（_mode=%d）" % int(窗.get("_mode")))

	# 重新开一次行动询问：验证「取消」清空已选
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Action,
		"commands": [{"respond_id": GConst.ActionType.Attack, "src_id": Logic.my_player_id, "args": []}],
	})
	await 等帧(2)
	手牌区.get_child(0).call("OnCardClick")
	await 等帧()
	(窗.get("BtnCancel") as Button).pressed.emit()
	await 等帧()
	检((窗.get("_sel_cards") as Array).is_empty() and (窗.get("_sel_players") as Array).is_empty(),
		"点「取消」没有清空已选的牌与目标")

	# 特殊行动：点 BtnSpecila 应打开专用窗口（购买 / 合成 / 提炼），而不是直接结束行动
	(窗.get("BtnSpecila") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 5, "点「特殊行动」没有进入特殊行动（_mode=%d）" % int(窗.get("_mode")))
	var 行动窗: Control = 窗.get("特殊行动窗") as Control
	检(行动窗 != null and 行动窗.visible, "特殊行动专用窗口没有打开")
	if 行动窗 != null:
		# 三个按钮的节点引用必须绑上（@export 没绑上就是 null，点了不会有反应）
		var 三选一: Array = [行动窗.get("BtnBuy"), 行动窗.get("BtnSynthesis"), 行动窗.get("BtnExtract")]
		检(三选一[0] is Button and 三选一[1] is Button and 三选一[2] is Button,
			"特殊行动窗口的三个按钮没绑上节点引用")
		检(行动窗.get("Titile") is Label, "特殊行动窗口的标题没绑上节点引用")
	# 窗口里的取消 → 关窗并退回行动阶段，本回合的技能按钮要摆回来
	(行动窗.get("BtnBack") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 1, "取消特殊行动后没有退回行动阶段：%d" % int(窗.get("_mode")))
	检(not 行动窗.visible, "取消特殊行动后窗口没关掉")

	# 特殊行动的第二层「用哪些星石」：走参数选择窗口（搬自参考工程的 ChooseArgsUI）
	# 窗口要有选项，战绩区得先有星石（假数据里给蓝方塞 2 宝石 1 水晶）
	var 蓝队: GTeam = Data.team_of(GConst.BLUE)
	蓝队.gem = 2
	蓝队.crystal = 1
	(窗.get("BtnSpecila") as Button).pressed.emit()
	await 等帧(2)
	窗.call("_选特殊行动", GConst.SpecialAction.Extract)
	await 等帧(2)
	var 参数窗: Control = 窗.get("参数选择窗") as Control
	检(参数窗 != null and 参数窗.visible, "选完「提炼」没有打开参数选择窗口")
	if 参数窗 != null:
		var 选项区: Node = 参数窗.get("OptionsBox")
		检(选项区 != null and 选项区.get_child_count() >= 2,
			"参数选择窗口没列出星石选项按钮（%d 个）" % (选项区.get_child_count() if 选项区 != null else -1))
		检(str((参数窗.get("Title") as Label).text) == "消耗能量",
			"消耗能量的特殊行动，选项窗标题应为「消耗能量」：%s" % str((参数窗.get("Title") as Label).text))
	# 窗口里的取消 → 退回上一层「购买/合成/提炼」三选一
	(参数窗.get("BtnBack") as Button).pressed.emit()
	await 等帧(2)
	检(not 参数窗.visible, "参数选择窗口的取消没关掉窗口")
	检(int(窗.get("_mode")) == 5, "取消星石选择后没有退回三选一：%d" % int(窗.get("_mode")))
	检(行动窗.visible, "取消星石选择后三选一窗口没有重新打开")
	# 战斗界面的取消 → 一路退回行动阶段
	(窗.get("BtnCancel") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 1, "取消特殊行动后没有退回行动阶段：%d" % int(窗.get("_mode")))
	检(not 行动窗.visible, "退回行动阶段后三选一窗口没关掉")

	# 放弃行动（BtnResign）→ 回到等待态
	(窗.get("BtnResign") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "放弃行动后没有回到等待态：%d" % int(窗.get("_mode")))
	检(not 确定.visible, "回到等待态后「确定」还显示着")

	# 平时（不选目标的等待态）点玩家头像 → 弹出他的角色技能说明（搬自参考工程 InfomationUI）
	(窗.get("MainPlayer") as Button).pressed.emit()
	await 等帧(2)
	var 详情窗: Control = 窗.get("英雄详情窗") as Control
	检(详情窗 != null and 详情窗.visible, "点玩家头像没有弹出角色技能说明")
	if 详情窗 != null:
		var 技能文本: RichTextLabel = 详情窗.get("SkillText") as RichTextLabel
		检(技能文本 != null and 技能文本.bbcode_enabled, "技能说明窗的文本控件没开 BBCode，类型颜色显示不出来")
		检(str((详情窗.get("HeroName") as Label).text) != "" and str(技能文本.text).length() > 10,
			"技能说明窗里没有角色名或技能文本")
		(详情窗.get("BtnClose") as Button).pressed.emit()
		await 等帧(2)
		检(not 详情窗.visible, "技能说明窗没关掉")

	# ================= 2) 应答询问（被攻击，应战） =================
	# 拿手牌里那张非暗系攻击牌当「本次攻击的牌」，它自己就是合法的应战牌
	var 应战询问: Dictionary = {
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.RespondType.ReplyAttack,
			"args": [GConst.HitRate.Normal, 攻击牌[0].id, Logic.my_player_id, 99],
		}],
	}
	Logic.command_received.emit(应战询问)
	await 等帧(2)
	检(int(窗.get("_mode")) == 2, "应答询问后状态不是「响应」（=2）：%d" % int(窗.get("_mode")))
	# 应战同样是「先选牌 → 亮可反击的敌方 → 点目标即出手」
	手牌区.get_child(0).call("OnCardClick")
	await 等帧()
	检((窗.get("_sel_cards") as Array).size() == 1, "应战时点应战牌没有被选中")
	检(对手可选中框 != null and 对手可选中框.visible, "选了应战牌后可反击目标没有亮起")
	对手面板.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "应战点敌方头像没有直接应战（_mode=%d）" % int(窗.get("_mode")))

	# 再被攻击一次：这次走「取消 = 放弃应战」
	Logic.command_received.emit(应战询问)
	await 等帧(2)
	检(int(窗.get("_mode")) == 2, "第二次应答询问没有进响应态：%d" % int(窗.get("_mode")))
	var 放弃应战: Button = 窗.get("BtnCancel")
	检(放弃应战.visible and not 放弃应战.disabled, "被攻击时「取消（放弃应战）」按钮不可用")
	放弃应战.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "应战点「取消」后没有回到等待态：%d" % int(窗.get("_mode")))

	# ================= 3) 行动询问 · 法术：点目标即释放 =================
	# 用【中毒】：服务端 _do_magic 对它没有额外校验，任意玩家都是合法目标
	var 法术牌: GCard = null
	for c: GCard in Data.card_db:
		if c.card_name_enum() == GConst.CardName.Poison:
			法术牌 = c
			break
	检(法术牌 != null, "卡库里找不到【中毒】，法术用例前提不成立")
	if 法术牌 != null:
		var 法术手牌: Array[GCard] = [法术牌]
		Data.hand_cards = 法术手牌
		Logic.command_received.emit({
			"cmd_type": GConst.CmdType.Action,
			"commands": [{"respond_id": GConst.ActionType.Attack, "src_id": Logic.my_player_id, "args": []}],
		})
		await 等帧(2)
		手牌区.get_child(0).call("OnCardClick")
		await 等帧()
		检((窗.get("_sel_cards") as Array).size() == 1, "法术牌没有被选中")
		检(对手可选中框 != null and 对手可选中框.visible, "选了法术牌后合法目标没有亮起")
		检(对手面板.modulate == Color(1.0, 1.0, 1.0), "选了法术牌后合法目标仍置灰：%s" % str(对手面板.modulate))
		对手面板.pressed.emit()
		await 等帧(2)
		检(int(窗.get("_mode")) == 0, "点目标后法术没有直接释放（_mode=%d）" % int(窗.get("_mode")))

	# 角色技能询问（例：狂战士攻击宣告后会问「是否发动血影狂刀 / 血腥咆哮」）。
	# 这类询问只挂在提示条上，必须能看见、能回答，否则攻击会一直卡着等（看着像「点确定没反应」）
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": 201, "src_id": Logic.my_player_id, "dst_ids": [], "card_ids": [],
			"args": [0, 0, GConst.CardSource.Hand, 0],
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "技能询问没有进入应答态（_mode=%s）" % str(窗.get("_mode")))
	var 技能确定: Button = 窗.get("BtnOK")
	var 技能提示: Label = 窗.get("TxtHint")
	检(技能确定.visible and not 技能确定.disabled, "技能询问时「确定」不可点（看不见或压灰就会卡住不攻击）")
	检(技能提示.text.begins_with("是否发动"), "技能询问的提示没写出来：%s" % 技能提示.text)
	窗.call("_on_ok")
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "回答技能询问后没有回到等待态：%d" % int(窗.get("_mode")))

	# 出手特效预制体（scenes/prefabs/effects/）：
	# 【圣光】是原生 2D 粒子；斩击类与【魔弹】是把 3D 素材经 SubViewport 转成 2D 的预制体
	for 名: String in ["圣光"]:
		var 根: GPUParticles2D = (load("res://scenes/prefabs/effects/%s.tscn" % 名) as PackedScene).instantiate() as GPUParticles2D
		if 根 == null:
			检(false, "粒子特效 %s 的根节点不是 GPUParticles2D（脚本没挂上？）" % 名)
			continue
		检(根.texture != null, "粒子特效 %s 没配贴图" % 名)
		检(根.process_material != null, "粒子特效 %s 没配粒子材质" % 名)
		根.free()

	# 【魔弹】：2D 预制体 + 里面的 3D 素材
	var 弹: 魔弹2D = (load("res://scenes/prefabs/effects/魔弹.tscn") as PackedScene).instantiate() as 魔弹2D
	if 弹 == null:
		检(false, "魔弹预制体加载失败（脚本没挂上？）")
	else:
		检(弹.VFX != null, "魔弹预制体没绑里面的 3D 特效节点（VFX 为空）")
		检(弹.get_node_or_null("视口容器/视口/特效位/特效") != null, "魔弹预制体缺 SubViewport 结构")
		弹.free()
	var 弹素材: Node3D = (load("res://scenes/prefabs/effects/魔弹3D/魔弹.tscn") as PackedScene).instantiate() as Node3D
	if 弹素材 == null:
		检(false, "3D 魔弹素材加载失败")
	else:
		检(弹素材 is 特效控制器3D, "3D 魔弹素材没挂 特效控制器3D 脚本")
		检(弹素材.get_node_or_null("Head") != null and 弹素材.get_node_or_null("AnimationPlayer") != null,
			"3D 魔弹素材缺 Head / AnimationPlayer 节点")
		弹素材.free()

	for 名: String in ["水斩", "火斩", "地斩", "风斩", "雷斩", "暗灭"]:
		var 桥: 斩击2D = (load("res://scenes/prefabs/effects/%s.tscn" % 名) as PackedScene).instantiate() as 斩击2D
		if 桥 == null:
			检(false, "斩击预制体 %s 加载失败（脚本没挂上？）" % 名)
			continue
		检(桥.VFX != null, "斩击预制体 %s 没绑里面的 3D 特效节点（VFX 为空）" % 名)
		检(桥.BG != null, "斩击预制体 %s 没绑背景节点（BG 为空，命中时就收不掉背景）" % 名)
		检(桥.get_node_or_null("视口容器/视口/特效位/特效") != null, "斩击预制体 %s 缺 SubViewport 结构" % 名)
		桥.free()
		# 里面的 3D 素材本身也要能加载
		var 素材: Node3D = (load("res://scenes/prefabs/effects/斩击3D/%s.tscn" % 名) as PackedScene).instantiate() as Node3D
		if 素材 == null:
			检(false, "3D 斩击素材 %s 加载失败" % 名)
			continue
		检(素材 is 特效发射器3D, "3D 斩击素材 %s 没挂 斩击特效3D 脚本" % 名)
		检(素材.get_node_or_null("Slash") != null and 素材.get_node_or_null("Particles") != null,
			"3D 斩击素材 %s 缺 Slash / Particles 节点" % 名)
		素材.free()

	await _收尾(窗, 旧id, 旧玩家, 旧手牌, 旧盖牌)
	print("[自检] 战斗交互：行动询问 / 选牌 / 点目标即出手 / 取消 / 放弃 / 应战（出手与放弃）全部走通")


func _收尾(窗: Node, 旧id: int, 旧玩家: Array[GPlayer], 旧手牌: Array[GCard], 旧盖牌: Array[GCard]) -> void:
	窗.queue_free()
	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	await 等帧(2)

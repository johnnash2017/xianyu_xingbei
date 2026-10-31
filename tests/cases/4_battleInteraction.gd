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

	# 响应里的额外攻击永远只能带一张攻击牌：先选一张，再选第二张必须替换而不是累积
	var 响应攻击牌: Array[int] = []
	for c: GCard in Data.hand_cards:
		if c != null and c.is_attack():
			响应攻击牌.append(c.id)
		if 响应攻击牌.size() >= 2:
			break
	if 响应攻击牌.size() >= 2:
		窗.call("_选中额外攻击响应", 0, 1, 101, [], [])
		窗.call("_on_card_clicked", 响应攻击牌[0])
		窗.call("_on_card_clicked", 响应攻击牌[1])
		var 响应已选: Array = 窗.get("_sel_cards")
		检(响应已选.size() == 1 and int(响应已选[0]) == 响应攻击牌[1],
			"响应额外攻击选第二张攻击牌时应替换第一张，实际 %s" % str(响应已选))
		窗.call("_清除额外攻击响应选择")

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

	# 特殊行动入口只在本阶段放行「特殊行动」时才摆出来：重新下发一条普通行动询问（Any）。
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Action,
		"commands": [{"respond_id": GConst.ActionType.Any, "src_id": Logic.my_player_id, "args": []}],
	})
	await 等帧(2)

	# 特殊行动：点技能栏最左的「特殊行动」入口，应进入「购买 / 合成 / 提炼」三选一
	# （选项摆进二级技能栏），而不是直接结束行动。
	var 特殊按钮: 技能按钮 = _找特殊行动按钮(窗)
	检(特殊按钮 != null, "技能栏里找不到「特殊行动」入口")
	if 特殊按钮 != null and 特殊按钮.plateButton != null:
		特殊按钮.plateButton.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_本地选项阶段")) == 3,
		"点「特殊行动」没有进入三选一（阶段=%d）" % int(窗.get("_本地选项阶段")))
	var 三选一选项: Array = 窗.get("_二级选项") as Array
	检(三选一选项 != null and 三选一选项.size() == 3, "三选一应始终摆出购买/合成/提炼三项")
	# 条件不满足的那几项照样摆着，只是点不动（半透明）—— 可点状态要跟着「可用」走
	for 项: Dictionary in 三选一选项:
		var 按钮: 技能按钮 = 项["按钮"]
		检(按钮.plateButton.disabled == (not bool(项["可用"])),
			"特殊行动选项的可点状态没跟着「可用」走")
	# 本体只作悬停说明：点它不应返回；返回由右边的「返回」按钮负责
	特殊按钮 = _找特殊行动按钮(窗)
	检(特殊按钮 != null, "三选一里没有左侧「特殊行动」本体")
	var 阶段前: int = int(窗.get("_本地选项阶段"))
	if 特殊按钮 != null and 特殊按钮.plateButton != null:
		特殊按钮.plateButton.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_本地选项阶段")) == 阶段前, "点左侧特殊行动本体不应返回上一级")
	var 返回按钮: 技能按钮 = _找技能栏文案按钮(窗, "返回")
	检(返回按钮 != null, "三选一右侧没有「返回」按钮")
	if 返回按钮 != null and 返回按钮.plateButton != null:
		返回按钮.plateButton.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 1, "点右侧「返回」后没有退回行动阶段：%d" % int(窗.get("_mode")))
	检((窗.get("_二级选项") as Array).is_empty(), "退回行动阶段后二级选项没收掉")

	# 特殊行动的第二层「用哪些星石」：也走二级技能栏（本地步骤，不用弹窗）
	# 选项要有，战绩区得先有星石（假数据里给蓝方塞 2 宝石 1 水晶）
	var 蓝队: GTeam = Data.team_of(GConst.BLUE)
	蓝队.gem = 2
	蓝队.crystal = 1
	特殊按钮 = _找特殊行动按钮(窗)
	检(特殊按钮 != null, "第二次找不到技能栏里的「特殊行动」入口")
	if 特殊按钮 != null and 特殊按钮.plateButton != null:
		特殊按钮.plateButton.pressed.emit()
	await 等帧(2)
	窗.call("_选特殊行动", GConst.SpecialAction.Extract)
	await 等帧(2)
	var 二级选项: Array = 窗.get("_二级选项") as Array
	检(int(窗.get("_本地选项阶段")) == 2, "选完「提炼」没有进入本地选星石步骤")
	检(二级选项 != null and 二级选项.size() >= 2,
		"二级技能栏没列出星石选项按钮（%d 个）" % (二级选项.size() if 二级选项 != null else -1))
	检(str((窗.get("TxtHint") as RichTextLabel).get_parsed_text()) == "选择要提炼的星石",
		"提炼的提示应为「选择要提炼的星石」：%s" % str((窗.get("TxtHint") as RichTextLabel).get_parsed_text()))
	# 点右侧「返回」按钮 → 退回上一层「购买/合成/提炼」三选一
	返回按钮 = _找技能栏文案按钮(窗, "返回")
	检(返回按钮 != null, "选星石步骤没有「返回」按钮")
	if 返回按钮 != null and 返回按钮.plateButton != null:
		返回按钮.plateButton.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_本地选项阶段")) == 3, "点右侧「返回」后没有退回三选一：%d" % int(窗.get("_本地选项阶段")))
	检(not (窗.get("_二级选项") as Array).is_empty(), "退回三选一后选项没摆出来")
	# 三选一是“进入下一层”的选项：点「提炼」应直接进去，不需要先点「确定」
	var 提炼项: 技能按钮 = _找技能栏文案按钮(窗, "提炼")
	检(提炼项 != null, "三选一里找不到「提炼」选项")
	if 提炼项 != null and 提炼项.plateButton != null:
		提炼项.plateButton.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_本地选项阶段")) == 2, "点「提炼」选项没有直接进入选星石步骤")
	返回按钮 = _找技能栏文案按钮(窗, "返回")
	if 返回按钮 != null and 返回按钮.plateButton != null:
		返回按钮.plateButton.pressed.emit()
	await 等帧(2)
	检(int(窗.get("_本地选项阶段")) == 3, "从选星石步骤返回后没有回到三选一")
	# 战斗界面的取消 → 一路退回行动阶段
	(窗.get("BtnCancel") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 1, "取消特殊行动后没有退回行动阶段：%d" % int(窗.get("_mode")))
	检((窗.get("_二级选项") as Array).is_empty(), "退回行动阶段后二级选项没收掉")

	# 放弃行动（BtnResign）→ 回到等待态
	(窗.get("BtnResign") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "放弃行动后没有回到等待态：%d" % int(窗.get("_mode")))
	检(not 确定.visible, "回到等待态后「确定」还显示着")

	# 平时（不选目标的等待态）鼠标指向玩家头像 → 就地弹出他的角色技能说明
	# （与选角界面同款：都走界面自己的 说明提示框，不用引擎自带的 tooltip）
	var 头像面板: 战斗玩家面板 = 窗.get("MainPlayer") as 战斗玩家面板
	var 说明: 说明提示框 = 窗.get("_说明提示") as 说明提示框
	检(说明 != null, "战斗界面没有说明提示框")
	头像面板.mouse_entered.emit()
	# 说明框的宽度是一级一级量出来的（每帧一档），多等几帧等它定好
	await 等帧(8)
	检(说明.可见(), "鼠标指向头像后没有弹出角色说明")
	检(说明.文本.text.length() > 10 and 说明.文本.text.find("[color=") >= 0,
		"角色说明没有内容或没上色（BBCode）")
	头像面板.mouse_exited.emit()
	await 等帧(2)
	检(not 说明.可见(), "鼠标离开头像后角色说明没有收掉")

	# 右侧头像：技能说明太长、正上方 / 下方都放不下时，应让到头像左侧，不能盖住头像
	var 右侧玩家: GPlayer = Data.get_player_by_id(2)
	if 右侧玩家 != null:
		右侧玩家.role_id = 4
	var 右侧面板: 战斗玩家面板 = 窗.get("PlayerStatusMobileR") as 战斗玩家面板
	右侧面板.mouse_entered.emit()
	await 等帧(8)
	var 说明框: Control = 说明.get("框") as Control
	检(说明.可见(), "鼠标指向右侧头像后没有弹出角色说明")
	检(not 说明框.get_global_rect().intersects(右侧面板.get_global_rect()),
		"右侧头像的角色说明盖住了头像：框 %s，头像 %s" % [
			str(说明框.get_global_rect()), str(右侧面板.get_global_rect())])
	右侧面板.mouse_exited.emit()
	await 等帧(2)
	检(not 说明.可见(), "鼠标离开右侧头像后角色说明没有收掉")

	# ================= 2) 应答询问（被攻击，应战） =================
	# 拿手牌里那张非暗系攻击牌当「本次攻击的牌」，它自己就是合法的应战牌
	var 应战询问: Dictionary = {
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.RespondType.ReplyAttack,
			"args": [GConst.HitRate.Normal, 攻击牌[0].id, Logic.my_player_id, 99, 0, 2],
		}],
	}
	Logic.command_received.emit(应战询问)
	await 等帧(2)
	检(int(窗.get("_mode")) == 2, "应答询问后状态不是「响应」（=2）：%d" % int(窗.get("_mode")))
	# 应战提示点名「X或暗系斩」，并给系别字上色（雷/地/风/火/水/暗）
	var 应战系: String = GConst.element_to_chinese(攻击牌[0].element_enum())
	var 应战提示: String = str(窗.get("_提示原文"))
	var 应战片段: String = "%s或%s系斩" % [
		str(窗.call("_系别着色", 应战系)), str(窗.call("_系别着色", "暗")),
	]
	检(应战提示.find(应战片段) >= 0,
		"应战提示没有点名系别 / 暗系或没有上色：%s" % 应战提示)
	检(应战提示.find("同系斩") < 0, "应战提示还在写「同系斩」：%s" % 应战提示)
	检(应战提示.find("伤害攻击，") >= 0, "普通应战提示的伤害说明没有用逗号：%s" % 应战提示)
	检(应战提示.find("伤害攻击：") < 0, "普通应战提示的伤害说明还在用冒号：%s" % 应战提示)
	检(应战提示.find("无法用【圣光】抵挡") >= 0,
		"圣光被禁时普通应战提示没有写「无法用【圣光】抵挡」：%s" % 应战提示)

	# 战斗日志里的斩名也按系别上色（与应战提示同一套配色）
	for 系: String in ["地", "水", "风", "火", "雷", "暗"]:
		var 斩名: String = ""
		for 卡: GCard in Data.card_db:
			if 卡.is_attack() and GConst.element_to_chinese(卡.element_enum()) == 系:
				斩名 = 卡.card_name
				break
		if 斩名.is_empty():
			continue
		var 日志文: String = str(窗.call("_日志着色", "打出 " + 斩名))
		var 名片段: String = "[color=%s]%s[/color]" % [str(窗.call("_系别颜色", 系)), 斩名]
		检(日志文.find(名片段) >= 0,
			"战斗日志里的 %s 没有按系别上色：%s" % [斩名, 日志文])
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
			"commands": [{"respond_id": GConst.ActionType.Any, "src_id": Logic.my_player_id, "args": []}],
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
			"args": [0, 0, GConst.CardSource.Hand, 0], "is_skill": true,
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "技能询问没有进入应答态（_mode=%s）" % str(窗.get("_mode")))
	var 技能确定: Button = 窗.get("BtnOK")
	var 技能提示: RichTextLabel = 窗.get("TxtHint")
	检(技能确定.visible and not 技能确定.disabled, "技能询问时「确定」不可点（看不见或压灰就会卡住不攻击）")
	检(技能提示.text.find("是否发动") < 0, "技能询问还在问是否发动：%s" % 技能提示.text)
	检(技能提示.text.find("血影狂刀") >= 0, "技能询问没写技能说明：%s" % 技能提示.text)
	窗.call("_on_ok")
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "回答技能询问后没有回到等待态：%d" % int(窗.get("_mode")))

	# 技能询问的日志只写「要做什么」，不能把整段技能说明倒进日志
	# （逆反居合斩的强制弃牌曾因此出现一大段「(仅御魂流居合形态下…)」）
	var 日志前: String = str(窗.get("_日志"))
	var 弃牌提示: String = "弃掉 2 张牌，若弃少于 2 则士气 -1"
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.技能_逆反居合斩, "src_id": Logic.my_player_id,
			"dst_ids": [], "card_ids": [],
			"args": [2, 0, GConst.CardSource.Hand, 0], "is_skill": true, "can_cancel": false,
			"ask_text": 弃牌提示,
		}],
	})
	await 等帧(2)
	检(str(窗.get("_提示原文")) == 弃牌提示,
		"逆反居合斩的弃牌提示条不是「%s」：%s" % [弃牌提示, str(窗.get("_提示原文"))])
	var 日志新: String = str(窗.get("_日志")).substr(日志前.length())
	检(日志新.find(弃牌提示) < 0 and 日志新.find("仅御魂流居合形态") < 0,
		"逆反居合斩的强制弃牌不该写战斗日志：%s" % 日志新)

	# 元素箭（水之矢 / 地之矢）：选目标时提示条显示表里【元素射击】「提示」列的专属效果，
	# 不能被「响应技能统一用技能说明」盖掉
	var 地之矢提示: String = GConst.提示原文(GConst.技能_地之矢, 2)
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": 32013, "src_id": Logic.my_player_id, "dst_ids": [], "card_ids": [],
			"args": [0, 1, GConst.CardSource.Hand, 0], "is_skill": true,
			"ask_text": 地之矢提示,
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "元素箭询问没有进入应答态（_mode=%s）" % str(窗.get("_mode")))
	检(str(窗.get("_提示原文")) == 地之矢提示,
		"元素箭提示条没有显示专属效果：%s" % str(窗.get("_提示原文")))
	(窗.get("BtnCancel") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "取消元素箭询问后没有回到等待态：%d" % int(窗.get("_mode")))

	# 被动技能被询问时：提示条固定写技能说明（不再只说当前要选什么），切选项也不变
	var 军神: int = GConst.技能_军神威光
	var 军神说明: String = "【%s】：%s" % [GConst.skill_name(军神),
		GConst.skill_desc(军神).replace("\\n", "").replace("\n", "").strip_edges()]
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": 军神, "src_id": Logic.my_player_id, "dst_ids": [], "card_ids": [],
			"args": [0, 0, GConst.CardSource.Hand, 2, 1, 2], "is_skill": true,
			"notes": ["回复并脱离", "移除星石加治疗"],
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "被动询问没有进入应答态（_mode=%s）" % str(窗.get("_mode")))
	检(str(窗.get("_提示原文")) == 军神说明,
		"被动询问没有固定显示技能说明：%s" % str(窗.get("_提示原文")))
	窗.call("_选中二级选项", 军神, 1)
	await 等帧()
	检(str(窗.get("_提示原文")) == 军神说明,
		"被动询问切换选项后提示变了：%s" % str(窗.get("_提示原文")))

	# 法术 / 启动点「准备释放」：同样固定显示技能说明，切参数选项不跟着变
	for 项: Array in [
		[GConst.技能_偷天换日, "转移宝石", "水晶转宝石"],
		[GConst.技能_散华轮舞, "消耗水晶", "消耗宝石"],
	]:
		var 技能号: int = int(项[0])
		var 技能说明: String = "【%s】：%s" % [GConst.skill_name(技能号),
			GConst.skill_desc(技能号).replace("\\n", "").replace("\n", "").strip_edges()]
		窗.call("_清空技能按钮")
		窗.call("_选择技能", 技能号, GConst.ActionType.Magic, 0, 0, [], [], 0, 0, 0,
			GConst.CardSource.Hand, "", 0, 0, [
				{"text": str(项[1]), "args": [1]},
				{"text": str(项[2]), "args": [2]},
			], null, 0)
		await 等帧()
		检(int(窗.get("_mode")) == 4, "点「准备释放」后没有进入发动状态（_mode=%s）" % str(窗.get("_mode")))
		检(str(窗.get("_提示原文")) == 技能说明,
			"法术/启动准备释放时没写技能说明：%s" % str(窗.get("_提示原文")))
		检(str(窗.get("_提示原文")).find("\n") < 0 and str(窗.get("_提示原文")).find("\\n") < 0,
			"技能说明里的换行没有忽略：%s" % str(窗.get("_提示原文")))
		窗.call("_选中二级选项", 技能号, 1)
		await 等帧()
		检(str(窗.get("_提示原文")) == 技能说明,
			"法术/启动切换选项后提示变了：%s" % str(窗.get("_提示原文")))

	# 指示器里不再允许写死「提示」；被动/法术/启动/响应统一走技能说明
	for 指示技能号: int in GConst.技能指示器:
		检(not (GConst.技能指示器[指示技能号] as Dictionary).has("提示"),
			"技能指示器里还有写死的提示：%s" % GConst.skill_name(指示技能号))
	for 序号技能号: int in [GConst.技能_兽魂警戒, GConst.技能_逆反居合斩]:
		检(not (GConst.技能指示器.get(序号技能号, {}) as Dictionary).has("提示序号"),
			"响应技能还在用提示序号覆盖说明：%s" % GConst.skill_name(序号技能号))
	# 原先写死过提示的响应技能：询问应直接显示说明列
	var 贯穿: int = GConst.技能_贯穿射击
	var 贯穿说明: String = "【%s】：%s" % [GConst.skill_name(贯穿),
		GConst.skill_desc(贯穿).replace("\\n", "").replace("\n", "").strip_edges()]
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": 贯穿, "src_id": Logic.my_player_id, "dst_ids": [], "card_ids": [],
			"args": [0, 0, GConst.CardSource.Hand, 0], "is_skill": true,
		}],
	})
	await 等帧(2)
	检(str(窗.get("_提示原文")) == 贯穿说明,
		"响应技能没有改回通用说明：%s" % str(窗.get("_提示原文")))
	窗.call("_清空待选")

	# 额外行动里的技能（原先【赤色一闪】写死了提示）也走通用说明
	var 赤色: int = GConst.技能_赤色一闪
	var 赤色说明: String = "【%s】：%s" % [GConst.skill_name(赤色),
		GConst.skill_desc(赤色).replace("\\n", "").replace("\n", "").strip_edges()]
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.RespondType.AdditionalAction, "src_id": Logic.my_player_id,
			"args": [赤色], "dst_ids": [赤色],
			# 与 args 一一对应的唯一 ID（真实服务端一定会带上；这里让 uid 就等于技能号）
			"option_uids": [赤色],
		}],
	})
	await 等帧(2)
	检(str(窗.get("_提示原文")) == 赤色说明,
		"额外行动没有走通用说明：%s" % str(窗.get("_提示原文")))
	# 点额外行动按钮只选中，不能立即提交
	窗.call("_选中额外行动", 0, 赤色, 赤色)
	检(int(窗.get("_额外行动单选")) == 赤色,
		"点额外行动选项应只选中，不能立即提交")
	窗.call("_清空待选")

	# 出手特效预制体（scenes/prefabs/effects/）：
	# 【圣光】是原生 2D 粒子；斩击类与【魔弹】是把 3D 素材经 SubViewport 转成 2D 的预制体
	for 名: String in ["holyLight"]:
		var 根: GPUParticles2D = (load("res://scenes/prefabs/effects/%s.tscn" % 名) as PackedScene).instantiate() as GPUParticles2D
		if 根 == null:
			检(false, "粒子特效 %s 的根节点不是 GPUParticles2D（脚本没挂上？）" % 名)
			continue
		检(根.texture != null, "粒子特效 %s 没配贴图" % 名)
		检(根.process_material != null, "粒子特效 %s 没配粒子材质" % 名)
		根.free()

	# 【魔弹】：2D 预制体 + 里面的 3D 素材
	var 弹: 魔弹2D = (load("res://scenes/prefabs/effects/magicBullet.tscn") as PackedScene).instantiate() as 魔弹2D
	if 弹 == null:
		检(false, "魔弹预制体加载失败（脚本没挂上？）")
	else:
		检(弹.VFX != null, "魔弹预制体没绑里面的 3D 特效节点（VFX 为空）")
		检(弹.get_node_or_null("视口容器/视口/特效位/特效") != null, "魔弹预制体缺 SubViewport 结构")
		检(弹.get_node_or_null("Trail") != null, "魔弹预制体缺 2D 拖尾节点")
		检(弹.Trail is Line2D, "魔弹 2D 拖尾不是 Line2D")
		检(弹.Trail != null and 弹.Trail.gradient != null and 弹.Trail.width > 0.0,
			"魔弹 2D 线条拖尾缺渐变或宽度")
		弹.free()
	var 弹素材: Node3D = (load("res://scenes/prefabs/effects/magicBullet3D/magicBullet.tscn") as PackedScene).instantiate() as Node3D
	if 弹素材 == null:
		检(false, "3D 魔弹素材加载失败")
	else:
		检(弹素材 is 特效控制器3D, "3D 魔弹素材没挂 特效控制器3D 脚本")
		检(弹素材.get_node_or_null("Head") != null and 弹素材.get_node_or_null("AnimationPlayer") != null,
			"3D 魔弹素材缺 Head / AnimationPlayer 节点")
		弹素材.free()

	for 名: String in ["waterSlash", "fireSlash", "earthSlash", "windSlash", "thunderSlash", "darkAnnihilation"]:
		var 桥: 斩击2D = (load("res://scenes/prefabs/effects/%s.tscn" % 名) as PackedScene).instantiate() as 斩击2D
		if 桥 == null:
			检(false, "斩击预制体 %s 加载失败（脚本没挂上？）" % 名)
			continue
		检(桥.VFX != null, "斩击预制体 %s 没绑里面的 3D 特效节点（VFX 为空）" % 名)
		检(桥.BG != null, "斩击预制体 %s 没绑背景节点（BG 为空，命中时就收不掉背景）" % 名)
		检(桥.get_node_or_null("视口容器/视口/特效位/特效") != null, "斩击预制体 %s 缺 SubViewport 结构" % 名)
		桥.free()
		# 里面的 3D 素材本身也要能加载
		var 素材: Node3D = (load("res://scenes/prefabs/effects/slash3D/%s.tscn" % 名) as PackedScene).instantiate() as Node3D
		if 素材 == null:
			检(false, "3D 斩击素材 %s 加载失败" % 名)
			continue
		检(素材 is 特效发射器3D, "3D 斩击素材 %s 没挂 斩击特效3D 脚本" % 名)
		检(素材.get_node_or_null("Slash") != null and 素材.get_node_or_null("Particles") != null,
			"3D 斩击素材 %s 缺 Slash / Particles 节点" % 名)
		素材.free()

	# 矜贵之女【Magic!】(7803)：选项自带需牌——点选项只是「切换选中」，
	# 在同一步选 2 张手牌后按一次「确定」一起提交，不再另发一条选牌询问。
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.技能_Magic, "src_id": Logic.my_player_id, "is_skill": true,
			"dst_ids": [], "card_ids": [],
			"args": [0, 0, GConst.CardSource.Hand, 3, 1, 2, 3],
			"card_max": 0, "card_rule": "", "can_cancel": true,
			"notes": ["弃 2 张牌", "额外+1【法术行动】", "我方【战绩区】+2【宝石】"],
			"option_need_cards": [2, 0, 0],
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "7803 选项询问后应进入技能询问（实际 %d）" % int(窗.get("_mode")))
	var 魔法选项: Array = 窗.get("_二级选项")
	检(魔法选项.size() == 3, "7803 应摆出 3 个选项（实际 %d）" % 魔法选项.size())
	var 魔法提示前: String = str(窗.get("_提示原文"))
	if not 魔法选项.is_empty():
		窗.call("_选中二级选项", GConst.技能_Magic, 0)
		await 等帧(1)
		检(int(窗.get("_mode")) == 3,
			"点选 7803 选项只切换选中，不应直接提交（实际 _mode=%d）" % int(窗.get("_mode")))
		检(int(窗.get("_skill_ask_need_card")) == 2,
			"7803「弃 2 张牌」选中后应要求选 2 张手牌（实际 %d）" % int(窗.get("_skill_ask_need_card")))
		# 选项名已经说明了要做什么：选中后提示条继续显示技能说明，不写「选 N 张牌」之类的专用提示
		检(str(窗.get("_提示原文")) == 魔法提示前,
			"7803 选中选项后提示条不应换成专用提示（实际：%s）" % str(窗.get("_提示原文")))
		for i: int in range(mini(2, Data.hand_cards.size())):
			窗.call("_on_card_clicked", Data.hand_cards[i].id)
		await 等帧(1)
		(窗.get("BtnOK") as Button).pressed.emit()
		await 等帧(1)
		检(int(窗.get("_mode")) == 0,
			"选满 2 张手牌后按确定应提交（实际 _mode=%d）" % int(窗.get("_mode")))

	# 【魔法入门】(7802)：友情羁绊作为它的第 2 个选项下发（同魔眼 arg_choices）——
	# 点技能直接进二级栏，选项 2 绑 7805 技能号（响应紫），选中后同一步选 2 名我方角色，确定一次提交。
	var 入门参数: Array = [
		{"text": "你摸 1 张牌【强制】", "args": [1]},
		{"text": "-1【宝石】改为我方 2 名角色各弃 1 张牌【强制】，技能效果结束前各摸 1 张牌【强制】",
			"args": [2], "skill_id": GConst.技能_友情羁绊, "enabled": true,
			"need_target": 2, "targets": [1, 3]},
	]
	窗.call("_选择技能", GConst.技能_魔法入门, GConst.ActionType.MagicSkill, 0, 0,
		[], [], 0, 0, 0, GConst.CardSource.Hand, "", 0, 0, 入门参数, null, 0)
	await 等帧(1)
	检(int(窗.get("_mode")) == 4,
		"7802 点技能后应直接进入二级技能栏（实际 _mode=%d）" % int(窗.get("_mode")))
	var 入门选项: Array = 窗.get("_二级选项")
	检(入门选项.size() == 2, "7802 应摆出 2 个选项（实际 %d）" % 入门选项.size())
	if 入门选项.size() == 2:
		检(int((入门选项[1] as Dictionary).get("技能号", 0)) == GConst.技能_友情羁绊,
			"7802 第 2 档应绑 7805 的技能号（按钮按响应紫显示）")
		窗.call("_选中二级选项", GConst.技能_魔法入门, 1)
		await 等帧(1)
		检(int(窗.get("_skill_need_target")) == 2,
			"7802 选友情羁绊档后应要求选 2 名角色（实际 %d）" % int(窗.get("_skill_need_target")))
		窗.call("_on_player_clicked", 1)
		窗.call("_on_player_clicked", 3)
		await 等帧(1)
		(窗.get("BtnOK") as Button).pressed.emit()
		await 等帧(1)
		检(int(窗.get("_mode")) == 0,
			"选好 2 名角色后按确定应提交（实际 _mode=%d）" % int(窗.get("_mode")))

	# 友情羁绊的弃牌走标准弃牌应答（不是技能询问）：提示条应叫对方弃牌，
	# 不能再显示发动者那句「选择 2 名我方角色各弃 1 张牌」。
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.RespondType.Discard, "src_id": 1, "is_skill": false,
			"dst_ids": [1], "card_ids": [],
			"args": [1, GConst.技能_友情羁绊, 1],
			"card_max": 0, "card_rule": "", "can_cancel": false,
		}],
	})
	await 等帧(2)
	var 友情弃牌提示: String = str(窗.get("_提示原文"))
	检(友情弃牌提示 == "【友情羁绊】：请选择 1 张牌弃掉，魔法入门效果结束摸 1 张牌",
		"7805 的弃牌应答提示应叫对方弃牌并带上后续摸牌（实际：%s）" % 友情弃牌提示)
	if not Data.hand_cards.is_empty():
		窗.call("_on_card_clicked", Data.hand_cards[0].id)
		await 等帧(1)
		(窗.get("BtnOK") as Button).pressed.emit()
		await 等帧(1)

	# 【强予愿行】(7804)：选项走 available_skills 的 arg_choices（同魔弓【魔眼】）——
	# 点技能直接进二级技能栏；选中选项后同一步选牌 / 选角色，最后按一次「确定」提交。
	var 强予参数: Array = [
		{"text": "仅调整自己手牌为 4", "args": [1], "enabled": true, "need_card": 0},
		{"text": "【战绩区】-1【水晶】调整其他角色手牌为 4", "args": [2], "enabled": true,
			"need_card": 0, "need_target": 1, "targets": [2, 3]},
		{"text": "【战绩区】-1【宝石】调整其他角色手牌为 4", "args": [3], "enabled": true,
			"need_card": 0, "need_target": 1, "targets": [2, 3]},
	]
	窗.call("_选择技能", GConst.技能_强予愿行, GConst.ActionType.SpecialSkill, 0, 0,
		[2, 3], [], 0, 0, 0, GConst.CardSource.Hand, "", 0, 0, 强予参数, null, 0)
	await 等帧(1)
	检(int(窗.get("_mode")) == 4,
		"7804 点技能后应直接进入二级技能栏（实际 _mode=%d）" % int(窗.get("_mode")))
	var 强予选项: Array = 窗.get("_二级选项")
	检(强予选项.size() == 3, "7804 应摆出 3 个选项（实际 %d）" % 强予选项.size())
	# 二级技能栏右侧有「返回」：点返回＝退回行动阶段（不发行动、不扣费）
	var 强予返回: 技能按钮 = _找技能栏文案按钮(窗, "返回")
	检(强予返回 != null, "7804 的二级技能栏右侧应有「返回」按钮")
	if 强予返回 != null and 强予返回.plateButton != null:
		强予返回.plateButton.pressed.emit()
		await 等帧(1)
		检(int(窗.get("_mode")) == 1, "点 7804 的「返回」应退回行动阶段（实际 _mode=%d）" % int(窗.get("_mode")))
		# 再进一次，验证「选中选项 → 选角色 → 确定」一次提交
		窗.call("_选择技能", GConst.技能_强予愿行, GConst.ActionType.SpecialSkill, 0, 0,
			[2, 3], [], 0, 0, 0, GConst.CardSource.Hand, "", 0, 0, 强予参数, null, 0)
		await 等帧(1)
	强予选项 = 窗.get("_二级选项")
	var 强予提示前: String = str(窗.get("_提示原文"))
	if not 强予选项.is_empty():
		窗.call("_选中二级选项", GConst.技能_强予愿行, 1)
		await 等帧(1)
		检(int(窗.get("_mode")) == 4,
			"点选 7804 选项只切换选中，不应直接提交（实际 _mode=%d）" % int(窗.get("_mode")))
		检(int(窗.get("_skill_need_target")) == 1,
			"7804 选「-1 水晶」后应要求选 1 名其他角色（实际 %d）" % int(窗.get("_skill_need_target")))
		检(str(窗.get("_提示原文")) == 强予提示前,
			"7804 选中选项后提示条不应换成专用提示（实际：%s）" % str(窗.get("_提示原文")))
		窗.call("_on_player_clicked", 2)
		await 等帧(1)
		(窗.get("BtnOK") as Button).pressed.emit()
		await 等帧(1)
		检(int(窗.get("_mode")) == 0,
			"选好角色后按确定应提交（实际 _mode=%d）" % int(窗.get("_mode")))

	await _收尾(窗, 旧id, 旧玩家, 旧手牌, 旧盖牌)
	print("[自检] 战斗交互：行动询问 / 选牌 / 点目标即出手 / 取消 / 放弃 / 应战（出手与放弃）全部走通")


func _收尾(窗: Node, 旧id: int, 旧玩家: Array[GPlayer], 旧手牌: Array[GCard], 旧盖牌: Array[GCard]) -> void:
	窗.queue_free()
	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	await 等帧(2)


## 在技能栏里找文案为「特殊行动」的按钮（现在是本体；旧入口已移除，测试不再直接点场景里的按钮）。
func _找特殊行动按钮(窗: Control) -> 技能按钮:
	return _找技能栏文案按钮(窗, "特殊行动")


## 在技能栏里按文案找按钮（特殊行动本体 / 返回等）。
func _找技能栏文案按钮(窗: Control, 文案: String) -> 技能按钮:
	var 栏: HBoxContainer = 窗.get("ChildrenSkillArea") as HBoxContainer
	if 栏 == null:
		return null
	for 子: Node in 栏.get_children():
		if 子 is 技能按钮:
			var 按钮: 技能按钮 = 子 as 技能按钮
			if 按钮.skillName != null and 按钮.skillName.get_parsed_text() == 文案:
				return 按钮
	return null

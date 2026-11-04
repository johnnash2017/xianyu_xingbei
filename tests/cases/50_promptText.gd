extends 自检用例
## 提示文案基线（P0）：把「二级栏提示文案」的计算抽成纯函数后，逐条锁住现有行为。
## 这些断言是后续「4 条规则」简化的对照基线 —— 简化后必须仍然全绿。

func _init() -> void:
	名称 = "提示文案基线"


func _新窗() -> Control:
	return load("res://scripts/ui/battle_mobile.gd").new()


func 跑() -> void:
	_检基础分支()
	_检选项覆盖()
	_检询问文案()
	_检文案表接口()
	_检选项提示协议()


## 基础分支：没选中 / 本地流程 / 普通技能询问 / 启动技能
func _检基础分支() -> void:
	var 窗: Control = _新窗()
	# 1) 没选中项、没有父技能 → 提示先选一个选项
	检(str(窗.call("_二级栏提示文案")) == "请在技能栏里选一个选项",
		"没有选中项时应提示「请在技能栏里选一个选项」：%s" % str(窗.call("_二级栏提示文案")))
	# 2) 本地选项阶段 / 提炼阶段：不覆盖进栏时那句说明（返回空串＝不改提示）
	窗._本地选项阶段 = 1
	检(str(窗.call("_二级栏提示文案")) == "",
		"本地选项阶段不应改写提示条：%s" % str(窗.call("_二级栏提示文案")))
	窗._本地选项阶段 = 0
	# 3) 普通技能询问（放逐）：前缀带上技能名 + 选牌张数
	窗._是技能询问 = true
	窗._skill_ask_id = 9505
	窗._二级栏父技能号 = 9505
	窗._mode = 3
	窗._skill_ask_need_card = 6
	窗._skill_ask_card_source = GConst.CardSource.Hand
	窗._二级选项 = [{"参数": [1], "技能号": 0}]
	窗._二级选中 = 0
	var 普通: String = str(窗.call("_二级栏提示文案"))
	检(普通.contains("【放逐】") and 普通.contains("6"),
		"普通技能询问应写【技能名】+ 选牌张数：%s" % 普通)
	# 4) 启动技能给出选项（强予愿行）：提示条固定写技能说明，不写「选 N 张」
	窗._mode = 4
	窗._pending_skill_id = 7804
	窗._二级栏父技能号 = 7804
	窗._二级选项 = [{"参数": [1]}]
	窗._二级选中 = 0
	var 启动期望: String = "【%s】：%s" % [GConst.skill_name(7804),
		GConst.skill_desc(7804).replace("\\n", "").replace("\n", "").strip_edges()]
	检(str(窗.call("_二级栏提示文案")) == 启动期望,
		"启动技能的选项应固定写技能说明：%s" % str(窗.call("_二级栏提示文案")))
	窗.queue_free()


## 选项覆盖：不改提示 / 独立技能 / 选项自带说明
func _检选项覆盖() -> void:
	var 窗: Control = _新窗()
	窗._是技能询问 = true
	窗._skill_ask_id = 9505
	窗._二级栏父技能号 = 9505
	窗._mode = 3
	窗._skill_ask_need_card = 0
	窗._二级选中 = 0
	# 1) 选项标「不改提示」：用本次询问的整段文案
	窗._二级选项 = [{"参数": [1], "技能号": 9507, "不改提示": true}]
	窗._pending = {"ask_prompt": "整段放逐提示"}
	检(str(窗.call("_二级栏提示文案")) == "整段放逐提示",
		"「不改提示」选项应保持本次询问文案：%s" % str(窗.call("_二级栏提示文案")))
	# 2) 独立技能选项（没有父技能时）：提示换成该选项技能的说明
	窗._二级栏父技能号 = 0
	窗._pending = {}
	窗._二级选项 = [{"参数": [1], "技能号": 1601}]
	var 独立期望: String = "【%s】：%s" % [GConst.skill_name(1601),
		GConst.skill_desc(1601).replace("\\n", "").replace("\n", "").strip_edges()]
	检(str(窗.call("_二级栏提示文案")) == 独立期望,
		"独立技能选项应写该技能说明：%s" % str(窗.call("_二级栏提示文案")))
	# 3) 选项自带说明：写成「【父技能名】：选项说明」
	窗._是技能询问 = true
	窗._skill_ask_id = 9505
	窗._二级栏父技能号 = 9505
	窗._二级选项 = [{"参数": [1], "说明": "本档说明"}]
	检(str(窗.call("_二级栏提示文案")) == "【放逐】：本档说明",
		"选项自带说明时应写成【技能名】：说明：%s" % str(窗.call("_二级栏提示文案")))
	窗.queue_free()


## 询问时（技能询问刚弹出）的提示文案：与切换选项共用同一套来源
func _检询问文案() -> void:
	var 窗: Control = _新窗()
	窗._skill_ask_id = 9505
	窗._mode = 3
	窗._skill_ask_can_cancel = true
	窗._skill_ask_card_source = GConst.CardSource.Hand
	窗._selecting_cover = false
	窗._skill_options.clear()
	窗._二级选项.clear()
	# 1) 服务端下发的步骤文案优先
	窗._pending = {"ask_text": "步骤文案"}
	检(str(窗.call("_询问提示文案")) == "步骤文案",
		"技能询问应优先用 ask_text：%s" % str(窗.call("_询问提示文案")))
	# 2) 整段提示（ask_prompt）盖过 ask_text
	窗._pending = {"ask_text": "短句", "ask_prompt": "整段提示"}
	检(str(窗.call("_询问提示文案")) == "整段提示",
		"ask_prompt 应盖过 ask_text：%s" % str(窗.call("_询问提示文案")))
	# 3) 没有文案时退回技能说明
	窗._pending = {}
	var 说明期望: String = "【%s】：%s" % [GConst.skill_name(9505),
		GConst.skill_desc(9505).replace("\n", "").replace("
", "").strip_edges()]
	检(str(窗.call("_询问提示文案")) == 说明期望,
		"没有文案时应退回技能说明：%s" % str(窗.call("_询问提示文案")))
	# 4) 强制询问：写「本次必须执行，不能取消」
	窗._skill_ask_can_cancel = false
	窗._skill_ask_need_card = 6
	var 强制: String = str(窗.call("_询问提示文案"))
	检(强制.contains("不能取消") and 强制.contains("需选牌"),
		"强制询问应写明不能取消 + 需选牌：%s" % 强制)
	窗._skill_ask_can_cancel = true
	窗._skill_ask_need_card = 0
	# 5) 从场上基础效果牌里选：写操作指引
	窗._skill_ask_card_source = GConst.CardSource.HandAndBasicEffect
	var 基础: String = str(窗.call("_询问提示文案"))
	检(基础.contains("基础效果"), "从基础效果牌里选时应写操作指引：%s" % 基础)
	窗._skill_ask_card_source = GConst.CardSource.Hand
	# 6) 带选项但没有文案时，退回二级栏计算函数的结果
	# 注意：_skill_options 声明为 Array[int]，而 窗 的静态类型是 Control，
	# 直接赋 [1] 会在运行时被拒（普通 Array 不会自动转成 Array[int]），
	# 赋值被丢掉后这条断言就退化成「空选项时两边相等」，等于没测。必须先建带类型的数组。
	窗._pending = {}
	var 选项值: Array[int] = [1]
	窗._skill_options = 选项值
	窗._二级栏父技能号 = 9505
	窗._二级选中 = -1
	var 二级: String = str(窗.call("_二级栏提示文案"))
	检(not 二级.is_empty(), "带选项时应能算出二级栏提示：%s" % 二级)
	检(str(窗.call("_询问提示文案")) == 二级,
		"带选项且无文案时，询问提示应与二级栏提示一致：%s / %s" % [str(窗.call("_询问提示文案")), 二级])
	窗.queue_free()


## 文案表接口：文本表 id 读取 + 占位符填充 + 提示原文走同一套填法
func _检文案表接口() -> void:
	检(GConst.填文本("弃{n}张牌给{dst}", {"n": 2, "dst": "甲"}) == "弃2张牌给甲",
		"填文本应替换占位符")
	检(GConst.文本("文本表#空") == "", "文本表空条目应读出空串")
	检(GConst.文本("不存在的文案id", false) == "不存在的文案id",
		"文本表缺 id 时应返回 id 本身")
	# 3) 已落表的公用句式（AI 改表 + headless 导表流水线验证）
	检(GConst.文本("提示_选择一个选项") == "请在技能栏里选一个选项",
		"文本表公用句式「选择一个选项」内容不对")
	检(GConst.文本("提示_选项已选好") == "选项已选好",
		"文本表公用句式「选项已选好」内容不对")
	检(GConst.文本("提示_从盖牌区选择一张") == "请从盖牌区中选择一张",
		"文本表公用句式「从盖牌区选择一张」内容不对")
	var 列表: Array[String] = GConst.技能提示列表(9505)
	if not 列表.is_empty():
		检(GConst.提示原文(9505, 0) == 列表[0].strip_edges(),
			"提示原文应与提示列表原文一致（去首尾空白）")


## 选项级提示字段（P2 预埋）：option_prompts / option_switch_desc 要能过协议
func _检选项提示协议() -> void:
	var 命令: Dictionary = {
		"respond_id": 9505, "src_id": 1,
		"args": [6, 0, 0, 2, 1, 2],
		"option_prompts": ["", "选中后的本步文案"],
		"option_switch_desc": [false, true],
	}
	var 解: Dictionary = ProtoCodec.decode_named("Command",
		ProtoCodec.encode_named("Command", 命令))
	var 提示组: Array = 解.get("option_prompts", [])
	检(提示组.size() == 2 and str(提示组[0]) == "" and str(提示组[1]) == "选中后的本步文案",
		"选项提示文案应能过协议：%s" % str(提示组))
	var 独立组: Array = 解.get("option_switch_desc", [])
	检(独立组.size() == 2 and not bool(独立组[0]) and bool(独立组[1]),
		"选项独立技能标记应能过协议：%s" % str(独立组))

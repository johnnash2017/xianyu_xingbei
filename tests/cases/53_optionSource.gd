extends 自检用例
## 用例 53：技能询问的「选项」两条来源必须等价。
## 阶段 5.3 起客户端改读 `Command.options`（一个选项一条 Option 消息），旧路径（13 个平行数组）
## 只作回退。这份改动能成立的前提就是「两份数据同值」——本用例把这份假设钉住：
##   ① options 真的过得了 Command 协议（不进 schema 客户端就永远收不到）
##   ② 新旧两条来源逐字段一致
##   ③ 两份对不上时必须整份退回旧路径（否则界面会按半份数据摆按钮）

func _init() -> void:
	名称 = "选项双来源等价"


func 跑() -> void:
	await 等帧()
	# ---- ① 协议往返：负数哨兵（card_id=-1 / cards 里的 -1）必须原样回来 ----
	var 原始选项: Array = [
		{"value": 1, "label": "甲", "enabled": true, "skill_id": 0, "need_card": 0,
			"need_target": 0, "target_max": 0, "card_id": -1, "card_source": -1, "cover_need": 0,
			"targets": {"ids": []}, "cards": {"ids": []}, "elements": {"ids": [1]},
			"preview_cards": {"ids": []}, "skill_group": {"ids": []},
			"prompt": "", "no_prompt_change": false},
		{"value": 2, "label": "乙", "enabled": false, "skill_id": 101, "need_card": 2,
			"need_target": 1, "target_max": 1, "card_id": 3, "card_source": 1, "cover_need": 2,
			"targets": {"ids": [2]}, "cards": {"ids": [5, -1]}, "elements": {"ids": []},
			"preview_cards": {"ids": [4]}, "skill_group": {"ids": [101]},
			"prompt": "第二步", "no_prompt_change": true},
	]
	var 解码: Dictionary = ProtoCodec.decode_named("Command", ProtoCodec.encode_named("Command", {
		"respond_id": GConst.技能_魔眼, "src_id": 1, "is_skill": true,
		"args": [0, 0, GConst.CardSource.Hand, 2, 1, 2],
		"options": 原始选项,
	}))
	var 解出: Array = 解码.get("options", [])
	检(解出.size() == 2, "options 没有过 Command 协议（解出 %d 条）" % 解出.size())
	if 解出.size() == 2:
		检(int((解出[1] as Dictionary).get("card_id", 0)) == 3, "Option.card_id 过协议后不对")
		检(((解出[1] as Dictionary).get("cards", {}) as Dictionary).get("ids", []) == [5, -1],
			"Option.cards 的负数哨兵没有原样过线")
		检(bool((解出[1] as Dictionary).get("no_prompt_change", false)), "Option.no_prompt_change 没过协议")

	# ---- ② 新旧两条来源逐字段一致（用解码后的 options，等于连协议一起验）----
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	窗.set("_skill_options", [1, 2] as Array[int])
	窗.set("_pending", {
		"notes": ["甲", "乙"],
		"option_elements": [{"ids": [1]}, {"ids": []}],
		"option_skill_groups": [{"ids": []}, {"ids": [101]}],
		"option_skill_ids": [0, 101],
		"option_card_ids": [-1, 3],
		"option_no_prompt_change": [false, true],
		"option_prompts": ["", "第二步"],
		"option_cards": [{"ids": []}, {"ids": [5, -1]}],
		"option_need_cards": [0, 2],
		"option_need_targets": [0, 1],
		"option_card_sources": [-1, 1],
		"option_enabled": [true, false],
		"option_targets": [{"ids": []}, {"ids": [2]}],
		"option_preview_cards": [{"ids": []}, {"ids": [4]}],
		"options": 解出,
	})
	var 旧: Array = 窗.call("_选项源_平行数组")
	var 新: Array = 窗.call("_选项源_嵌套", 解出)
	检(新.size() == 旧.size(), "两条来源条数不同：新 %d / 旧 %d" % [新.size(), 旧.size()])
	for i: int in range(mini(新.size(), 旧.size())):
		var 新项: Dictionary = 新[i]
		var 旧项: Dictionary = 旧[i]
		for k: Variant in 旧项.keys():
			检(新项.has(k), "第 %d 项少了字段 %s" % [i, str(k)])
			if 新项.has(k):
				检(str(新项[k]) == str(旧项[k]),
					"第 %d 项的 %s 不一致：新 %s / 旧 %s" % [i, str(k), str(新项[k]), str(旧项[k])])

	# ---- ③ 对不上就整份退回旧路径：把第二项的 value 改掉，模拟「两份不是一批数据」----
	var 错位: Array = 解出.duplicate(true)
	if 错位.size() == 2:
		(错位[1] as Dictionary)["value"] = 99
	var 命令2: Dictionary = (窗.get("_pending") as Dictionary).duplicate(true)
	命令2["options"] = 错位
	窗.set("_pending", 命令2)
	var 退回: Array = 窗.call("_技能询问_选项源")
	检(退回.size() == 旧.size(), "退回平行数组后条数不对：%d / %d" % [退回.size(), 旧.size()])
	var 逐项一致: bool = true
	for i: int in range(mini(退回.size(), 旧.size())):
		if str(退回[i]) != str(旧[i]):
			逐项一致 = false
	检(逐项一致, "options 与 args 对不上时，应整份退回平行数组")

	_补测边界形状(窗)
	窗.free()


## ④ 再加两组「边界形状」，确认两条来源在这些情况下也一致（5.4 删旧路径前先把这些钉住）：
##   A. 5 个选项 + 标签为空（客户端应回落成选项值文字）+ 可选=false + 牌白带 -1 哨兵
##   B. 选项本身就是技能（skill_id>0）+ 元素着色 + 技能组 + 多张预览牌 + 不改提示
func _补测边界形状(窗: Control) -> void:
	# ---- A：数量多、有空标签、有 -1 哨兵 ----
	var 值A: Array[int] = [11, 12, 13, 14, 15]
	var 平A: Dictionary = {
		"notes": ["甲", "", "丙", "丁", "戊"],
		"option_enabled": [true, true, false, true, true],
		"option_skill_ids": [0, 0, 0, 0, 0],
		"option_need_cards": [0, 0, 0, 0, 0],
		"option_need_targets": [0, 0, 0, 0, 0],
		"option_elements": [{"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}],
		"option_skill_groups": [{"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}],
		"option_card_ids": [-1, -1, -1, -1, -1],
		"option_no_prompt_change": [false, false, false, false, false],
		"option_prompts": ["", "", "", "", ""],
		"option_cards": [{"ids": []}, {"ids": []}, {"ids": [-1]}, {"ids": []}, {"ids": []}],
		"option_targets": [{"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}],
		"option_preview_cards": [{"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}, {"ids": []}],
	}
	var 嵌A: Array = []
	for i: int in range(值A.size()):
		嵌A.append({
			"value": 值A[i],
			"label": (平A["notes"] as Array)[i],
			"enabled": (平A["option_enabled"] as Array)[i],
			"skill_id": 0, "need_card": 0, "need_target": 0, "target_max": 0,
			"card_id": -1, "card_source": -1, "cover_need": 0,
			"targets": {"ids": []}, "cards": (平A["option_cards"] as Array)[i],
			"elements": {"ids": []}, "preview_cards": {"ids": []},
			"skill_group": {"ids": []}, "prompt": "", "no_prompt_change": false,
		})
	平A["options"] = 嵌A
	_两路比对(窗, 值A, 平A, 嵌A, "A：5 选项 + 空标签 + -1 哨兵")

	# ---- B：选项本身就是技能 + 元素 + 技能组 + 多张预览牌 ----
	var 值B: Array[int] = [21, 22]
	var 平B: Dictionary = {
		"notes": ["炎之剑", "冰之枪"],
		"option_enabled": [true, false],
		"option_skill_ids": [103, 201],
		"option_need_cards": [1, 2],
		"option_need_targets": [1, 0],
		"option_elements": [{"ids": [GConst.CardElement.Fire]}, {"ids": [GConst.CardElement.Water]}],
		"option_skill_groups": [{"ids": [103, 104]}, {"ids": []}],
		"option_card_ids": [5, -1],
		"option_no_prompt_change": [true, false],
		"option_prompts": ["用炎之剑", ""],
		"option_cards": [{"ids": [5, 6]}, {"ids": []}],
		"option_targets": [{"ids": [2]}, {"ids": []}],
		"option_preview_cards": [{"ids": [7, 8]}, {"ids": []}],
	}
	var 嵌B: Array = [
		{"value": 21, "label": "炎之剑", "enabled": true, "skill_id": 103, "need_card": 1,
			"need_target": 1, "target_max": 0, "card_id": 5, "card_source": -1, "cover_need": 0,
			"targets": {"ids": [2]}, "cards": {"ids": [5, 6]},
			"elements": {"ids": [GConst.CardElement.Fire]},
			"preview_cards": {"ids": [7, 8]}, "skill_group": {"ids": [103, 104]},
			"prompt": "用炎之剑", "no_prompt_change": true},
		{"value": 22, "label": "冰之枪", "enabled": false, "skill_id": 201, "need_card": 2,
			"need_target": 0, "target_max": 0, "card_id": -1, "card_source": -1, "cover_need": 0,
			"targets": {"ids": []}, "cards": {"ids": []},
			"elements": {"ids": [GConst.CardElement.Water]},
			"preview_cards": {"ids": []}, "skill_group": {"ids": []},
			"prompt": "", "no_prompt_change": false},
	]
	平B["options"] = 嵌B
	_两路比对(窗, 值B, 平B, 嵌B, "B：选项即技能 + 元素 + 技能组 + 预览牌")


## 同一组数据分别走「新路径（options）」和「旧路径（13 个平行数组）」，逐项逐字段比对
func _两路比对(窗: Control, 值们: Array[int], 平铺: Dictionary, 嵌套: Array, 标签: String) -> void:
	窗.set("_skill_options", 值们)
	窗.set("_pending", 平铺)
	var 旧: Array = 窗.call("_选项源_平行数组")
	var 新: Array = 窗.call("_选项源_嵌套", 嵌套)
	检(新.size() == 旧.size(), "%s：条数不同 新 %d / 旧 %d" % [标签, 新.size(), 旧.size()])
	for i: int in range(mini(新.size(), 旧.size())):
		var 新项: Dictionary = 新[i]
		var 旧项: Dictionary = 旧[i]
		for k: Variant in 旧项.keys():
			检(新项.has(k), "%s：第 %d 项少了字段 %s" % [标签, i, str(k)])
			if 新项.has(k):
				检(str(新项[k]) == str(旧项[k]),
					"%s：第 %d 项的 %s 不一致：新 %s / 旧 %s"
					% [标签, i, str(k), str(新项[k]), str(旧项[k])])
	# 同一份数据也必须能通过「选项值对得上」这道理
	检(bool(窗.call("_选项值对得上", 嵌套)), "%s：value 应与 args 里的选项值一一对应" % 标签)

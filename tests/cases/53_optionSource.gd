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
	窗.free()

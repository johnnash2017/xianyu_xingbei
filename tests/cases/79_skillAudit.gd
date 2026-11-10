extends 自检用例
## 用例 79：技能表全量审计（技能表 425 条的静态契约）
## 目的：给「425 条技能逐分支验证」兜一层**可重复的静态底账**——
##   ① 每条技能行都有 id / 技能名 / 说明；
##   ② 脚本号不重复（同一号两行会让代码按号取数据时取到错的那行）；
##   ③ 所有启用角色（角色表 + role_skill_条目）引用到的技能号都能在技能表里找到；
##   ④ 统计有「提示 / 按钮」文案的技能数，给运行期行为跑测（diffProbe）做对照。

const 列_脚本号: int = 0
const 列_技能名: int = 3
const 列_说明: int = 7
const 列_提示: int = 8
const 列_按钮: int = 9


func _init() -> void:
	名称 = "技能表全量审计"


func 跑() -> void:
	var 表: Dictionary = 数据表格.技能表
	var 缺号: Array = []
	var 缺名: Array = []
	var 缺说明: Array = []
	var 有提示: int = 0
	var 有按钮: int = 0
	var 号到行: Dictionary = {}
	var 重号: Array = []
	for 键: Variant in 表:
		var 行: Array = 表[键]
		var 号: int = int(行[列_脚本号])
		if 号 <= 0:
			缺号.append(str(键))
			continue
		if str(行[列_技能名]).strip_edges().is_empty():
			缺名.append("%d(%s)" % [号, str(键)])
		if str(行[列_说明]).strip_edges().is_empty():
			缺说明.append("%d" % 号)
		if (行[列_提示] as Array).size() > 0:
			有提示 += 1
		if (行[列_按钮] as Array).size() > 0:
			有按钮 += 1
		if 号到行.has(号):
			重号.append("%d：%s / %s" % [号, str(号到行[号]), str(键)])
		else:
			号到行[号] = 键

	检(缺号.is_empty(), "有技能行没有脚本号：%s" % str(缺号.slice(0, 5)))
	检(缺名.is_empty(), "有技能行缺「技能名」：%s" % str(缺名.slice(0, 5)))
	检(缺说明.is_empty(), "有技能行缺「说明」：%s" % str(缺说明.slice(0, 5)))
	检(重号.is_empty(), "脚本号重复（按号取数据会取错行）：%s" % str(重号.slice(0, 5)))
	检(表.size() > 400, "技能表行数异常：%d" % 表.size())

	# 可达性：启用角色引用到的技能号必须都在表里
	var 引用缺: Array = []
	var 引用数: int = 0
	for 角色号: int in Data.role_pool:
		for 条目: Dictionary in Data.role_skill_条目(角色号):
			引用数 += 1
			var 号2: int = int(条目.get("脚本号", 条目.get("技能号", -1)))
			if 号2 > 0 and not 号到行.has(号2):
				引用缺.append("%d←角色%d" % [号2, 角色号])
	检(引用缺.is_empty(), "角色引用了技能表里没有的技能号：%s" % str(引用缺.slice(0, 5)))

	print("[技能审计] 行数 %d，唯一脚本号 %d，有提示 %d，有按钮 %d，角色引用 %d 条" % [
		表.size(), 号到行.size(), 有提示, 有按钮, 引用数])

	# 行为跑测的覆盖面（第四轮）：26 个迁移点已逐个用 diffProbe 比对新旧树，
	# 其余技能靠 tests/diffProbe.gd 的「全角色 × 钩子序列」扫描兜底。
	var 迁移点: Array[int] = [2504, 2505, 2701, 2706, 4502, 4504, 502, 104, 4202, 4203,
		8105, 8208, 8404, 3805, 9501, 9504, 9505, 9506, 9507, 9508, 9509, 4305, 4307,
		9604, 9608, 7907]
	var 缺迁移点: Array = []
	for 号3: int in 迁移点:
		if not 号到行.has(号3):
			缺迁移点.append(号3)
	检(缺迁移点.is_empty(), "迁移点清单里有技能表不存在的号：%s" % str(缺迁移点))

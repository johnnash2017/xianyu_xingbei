extends 自检用例
## 用例 7：选角收尾的角色分配 —— 随机补位必须避让别人已经点选的角色。
## 回归：任选模式下，随机补位的人若排在点选者前面，会先把点选者的角色随机走，
## 轮到他时再保留一次，开局就出现两个同名角色（玩家 4 与玩家 1 都是兽灵武士）。

const 兽灵: int = 36


func _init() -> void:
	名称 = "选角分配"


func 跑() -> void:
	var 服: LocalServer = LocalServer.new()
	var 全池: Array = [36, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
	var 候选: Dictionary = {}
	for pid: int in [1, 2, 3, 4]:
		候选[pid] = 全池
	var 已选: Dictionary = {1: 兽灵}
	# 顺序故意让随机补位的人排在点选者前面：这正是当初漏掉的情况
	var 顺序: Array = [4, 2, 3, 1]
	var 抢角次数: int = 0
	for _i: int in range(200):
		var 表: Dictionary = 服._分配角色(顺序, 候选, 已选, 全池, true)
		if int(表.get(1, 0)) != 兽灵:
			抢角次数 += 1
		for pid: int in [2, 3, 4]:
			if int(表.get(pid, 0)) == 兽灵:
				抢角次数 += 1
	检(抢角次数 == 0, "随机补位抢走了别人点选的兽灵武士（%d 次）" % 抢角次数)

	# 三选一 / 五选一这种不重复策略：四个人最终必须四个不同角色
	var 三选一候选: Dictionary = {
		1: [36, 5, 6], 2: [7, 8, 9], 3: [10, 11, 12], 4: [13, 14, 15],
	}
	var 重角次数: int = 0
	for _i: int in range(200):
		var 表: Dictionary = 服._分配角色(顺序, 三选一候选, 已选, 全池, false)
		var 已见: Dictionary = {}
		for pid: int in [1, 2, 3, 4]:
			var rid: int = int(表.get(pid, 0))
			if 已见.has(rid):
				重角次数 += 1
			已见[rid] = true
	检(重角次数 == 0, "非任选模式出现重复角色（%d 次）" % 重角次数)

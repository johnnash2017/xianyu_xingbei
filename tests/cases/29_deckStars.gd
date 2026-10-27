extends 自检用例
## F8 牌库顶 / 星杯 / 战绩区 / 士气：
## - 牌库顶逐张移除 / 展示 / 入弃牌：remove_top 不把弃牌堆洗回，牌库不足只返回实际张数；
##   逐张展示与弃置牌库顶都按「牌库顶到底」的顺序处理。
## - 星杯：双方星杯数 / 总数读取（10803 的 X）。
## - 战绩区：读取构成、一次移除全部星石并返回移除前构成（8704）。
## - 士气：转移时来源最多扣到 0、目标不超过士气上限；同队 / 越界 / 0 点不转移。
## - 边界：牌库只有 0 / 不足 N 张、星杯 0、战绩区空、士气目标已满 / 部分空间。

var 引擎: BattleEngine = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "牌库顶星杯战绩区与士气"


# ============================================================
# 工具
# ============================================================
## 把牌库 / 弃牌堆换成固定内容（方便按「牌库顶」断言）
func _设牌堆(pile: Array, discard: Array = []) -> void:
	引擎.deck.pile.clear()
	for c: Variant in pile:
		引擎.deck.pile.append(int(c))
	引擎.deck.discard.clear()
	for c: Variant in discard:
		引擎.deck.discard.append(int(c))


func _有展示(cards: Array) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Card:
			continue
		var data: Dictionary = r["data"]
		if int(data.get("type", -1)) != GConst.CardMsgType.Show:
			continue
		var 发牌: Array = data.get("card_ids", [])
		if 发牌 == cards:
			return true
	return false


func _展示次数() -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Card and int((r["data"] as Dictionary).get("type", -1)) == GConst.CardMsgType.Show:
			n += 1
	return n


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})

	_测试牌库顶()
	_测试星杯()
	_测试战绩区()
	_测试士气转移()

	引擎.send_cb = Callable()


# ============================================================
# 牌库顶
# ============================================================
func _测试牌库顶() -> void:
	# 牌库顶＝pile 末尾：先移除 4，再移除 3
	_设牌堆([1, 2, 3, 4])
	var 看顶: Array = 引擎.deck.peek_top(2)
	检(看顶 == [4, 3], "peek_top 应先返回牌库顶 4、3，实际 %s" % str(看顶))
	检(引擎.deck.pile == [1, 2, 3, 4], "peek_top 不应改变牌库")
	var 移除: Array = 引擎.移除牌库顶(2)
	检(移除 == [4, 3], "移除牌库顶应先返回 4、3，实际 %s" % str(移除))
	检(引擎.deck.pile == [1, 2], "移除后牌库应只剩 1、2，实际 %s" % str(引擎.deck.pile))
	检(引擎.deck.discard.is_empty(), "移除牌库顶本身不应自动入弃牌堆")

	# 牌库不足：只取实际张数，不能把弃牌堆洗回牌库
	_设牌堆([7], [8, 9])
	var 不足: Array = 引擎.移除牌库顶(3)
	检(不足 == [7], "牌库不足时应只移除 7，实际 %s" % str(不足))
	检(引擎.deck.pile.is_empty(), "牌库应已空")
	检(引擎.deck.discard == [8, 9], "牌库不足时不应把弃牌堆洗回，实际弃牌堆 %s" % str(引擎.deck.discard))
	检(引擎.移除牌库顶(1).is_empty(), "空牌库移除应返回空数组")
	检(引擎.deck.discard == [8, 9], "空牌库也不应洗回弃牌堆")

	# 逐张移除 + 逐张展示
	_设牌堆([10, 11, 12, 13])
	发送记录.clear()
	var 逐张: Array = 引擎.逐张移除牌库顶(3, 2)
	检(逐张 == [13, 12, 11], "逐张移除应按牌库顶到底 13、12、11，实际 %s" % str(逐张))
	检(引擎.deck.pile == [10], "逐张移除后牌库应剩 10")
	检(_展示次数() == 3, "逐张移除应逐张展示 3 次，实际 %d" % _展示次数())

	# 弃置牌库顶：移除 + 展示 + 入弃牌堆
	_设牌堆([21, 22, 23])
	发送记录.clear()
	var 弃置: Array = 引擎.弃置牌库顶(2, 2)
	检(弃置 == [23, 22], "弃置牌库顶应先 23、22，实际 %s" % str(弃置))
	检(引擎.deck.discard == [23, 22], "弃置的牌应按移除顺序进弃牌堆，实际 %s" % str(引擎.deck.discard))
	检(引擎.deck.pile == [21], "弃置后牌库应剩 21")
	检(_有展示([23, 22]), "弃置牌库顶应展示拿到的牌")

	# 空牌库弃置：安全返回空
	_设牌堆([], [99])
	var 空弃: Array = 引擎.弃置牌库顶(2, 2)
	检(空弃.is_empty(), "空牌库弃置应返回空")
	检(引擎.deck.discard == [99], "空牌库弃置不应动弃牌堆")


# ============================================================
# 星杯
# ============================================================
func _测试星杯() -> void:
	引擎.team_grail[GConst.BLUE] = 0
	引擎.team_grail[GConst.RED] = 0
	检(引擎.星杯数(GConst.BLUE) == 0 and 引擎.星杯数(GConst.RED) == 0, "星杯初始应为 0")
	检(引擎.星杯总数() == 0, "双方星杯总数为 0")

	引擎.team_grail[GConst.BLUE] = 2
	引擎.team_grail[GConst.RED] = 3
	检(引擎.星杯数(GConst.BLUE) == 2, "蓝队星杯应为 2，实际 %d" % 引擎.星杯数(GConst.BLUE))
	检(引擎.星杯数(GConst.RED) == 3, "红队星杯应为 3，实际 %d" % 引擎.星杯数(GConst.RED))
	检(引擎.星杯总数() == 5, "双方星杯总数应为 5，实际 %d" % 引擎.星杯总数())
	检(引擎.星杯数(-1) == 0 and 引擎.星杯数(9) == 0, "越界颜色读星杯应返回 0")


# ============================================================
# 战绩区
# ============================================================
func _测试战绩区() -> void:
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 1
	引擎.team_gem[GConst.RED] = 1
	引擎.team_crystal[GConst.RED] = 0
	var 构成: Dictionary = 引擎.战绩区构成(GConst.BLUE)
	检(int(构成.get("gem", -1)) == 2 and int(构成.get("crystal", -1)) == 1
		and int(构成.get("total", -1)) == 3,
		"战绩区构成应为 2 宝石 / 1 水晶 / 共 3，实际 %s" % str(构成))

	var 移除: Dictionary = 引擎.清空战绩区(GConst.BLUE)
	检(int(移除.get("gem", -1)) == 2 and int(移除.get("crystal", -1)) == 1
		and int(移除.get("total", -1)) == 3,
		"清空战绩区应返回移除前构成 2/1/3，实际 %s" % str(移除))
	检(引擎.team_gem[GConst.BLUE] == 0 and 引擎.team_crystal[GConst.BLUE] == 0,
		"蓝队战绩区应已清空")
	检(引擎.team_gem[GConst.RED] == 1 and 引擎.team_crystal[GConst.RED] == 0,
		"清空蓝队不应影响红队战绩区")

	var 空移除: Dictionary = 引擎.清空战绩区(GConst.BLUE)
	检(int(空移除.get("total", -1)) == 0, "空战绩区应返回 total=0，实际 %s" % str(空移除))
	检(int(引擎.战绩区构成(9).get("total", -1)) == 0, "越界颜色读战绩区应返回空构成")


# ============================================================
# 士气转移
# ============================================================
func _测试士气转移() -> void:
	引擎.team_morale[GConst.RED] = 10
	引擎.team_morale[GConst.BLUE] = 10

	# 正常转移：红 → 蓝 2 点
	var 实际: int = 引擎.转移士气(GConst.RED, GConst.BLUE, 2)
	检(实际 == 2, "应实际转移 2 点，实际 %d" % 实际)
	检(引擎.team_morale[GConst.RED] == 8 and 引擎.team_morale[GConst.BLUE] == 12,
		"转移后红/蓝应 8/12，实际 %d/%d" % [引擎.team_morale[GConst.RED], 引擎.team_morale[GConst.BLUE]])

	# 目标已到士气上限：不能再加，也不能凭空扣来源
	引擎.team_morale[GConst.RED] = 10
	引擎.team_morale[GConst.BLUE] = 引擎.士气上限()
	var 满: int = 引擎.转移士气(GConst.RED, GConst.BLUE, 3)
	检(满 == 0, "目标已满时不应转移，实际 %d" % 满)
	检(引擎.team_morale[GConst.RED] == 10 and 引擎.team_morale[GConst.BLUE] == 引擎.士气上限(),
		"目标已满时双方士气都不应变")

	# 目标只剩 1 点空间：只转 1 点
	引擎.team_morale[GConst.RED] = 10
	引擎.team_morale[GConst.BLUE] = 引擎.士气上限() - 1
	var 部分: int = 引擎.转移士气(GConst.RED, GConst.BLUE, 3)
	检(部分 == 1, "目标只剩 1 点空间时应只转 1 点，实际 %d" % 部分)
	检(引擎.team_morale[GConst.RED] == 9 and 引擎.team_morale[GConst.BLUE] == 引擎.士气上限(),
		"部分转移后红/蓝应 9/上限，实际 %d/%d" % [引擎.team_morale[GConst.RED], 引擎.team_morale[GConst.BLUE]])

	# 0 点 / 同队 / 越界：都不转移
	引擎.team_morale[GConst.RED] = 10
	引擎.team_morale[GConst.BLUE] = 10
	检(引擎.转移士气(GConst.RED, GConst.BLUE, 0) == 0, "0 点不应转移")
	检(引擎.转移士气(GConst.RED, GConst.RED, 2) == 0, "同队不应转移")
	检(引擎.转移士气(-1, GConst.BLUE, 1) == 0, "越界颜色不应转移")
	检(引擎.team_morale[GConst.RED] == 10 and 引擎.team_morale[GConst.BLUE] == 10,
		"无效转移不应改动士气")

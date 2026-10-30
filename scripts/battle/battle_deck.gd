class_name BattleDeck
extends RefCounted
## 牌堆与弃牌堆（对照服务端 GameGrail.h 的 Deck）

var pile: Array[int] = []
var discard: Array[int] = []


## 初始化 0..149 并洗牌
func init_full() -> void:
	pile.clear()
	discard.clear()
	for i: int in range(GConst.CARDSUM):
		pile.append(i)
	shuffle()


func shuffle() -> void:
	for i: int in range(pile.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var t: int = pile[i]
		pile[i] = pile[j]
		pile[j] = t


## 从牌堆顶摸 n 张；不足时把弃牌堆洗回
func draw(n: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(n):
		if pile.is_empty():
			if discard.is_empty():
				break
			_reshuffle_discard()
		out.append(pile.pop_back())
	return out


func _reshuffle_discard() -> void:
	pile = discard.duplicate()
	discard.clear()
	shuffle()


## 从牌库顶（pile 末尾）取 n 张，顺序与 draw 相同（先取到的在前）。
## 与 draw 的区别：**牌库不足时不把弃牌堆洗回**，只返回实际能取到的张数 ——
## 供「移除/弃置牌库顶牌」类技能使用（9701 / 10803）：这些效果按字面只看牌库顶，
## 牌库空了就停，不能把弃牌堆重新洗成牌库。
func remove_top(n: int = 1) -> Array[int]:
	var out: Array[int] = []
	if n <= 0:
		return out
	for _i: int in range(n):
		if pile.is_empty():
			break
		out.append(pile.pop_back())
	return out


## 查看牌库顶 n 张（不改变牌库；顺序同 remove_top：第一张先被移除）。不足返回实际张数。
func peek_top(n: int = 1) -> Array[int]:
	var out: Array[int] = []
	if n <= 0:
		return out
	for i: int in range(n):
		var idx: int = pile.size() - 1 - i
		if idx < 0:
			break
		out.append(pile[idx])
	return out


## 把牌放进弃牌堆
func push_discard(cards: Array) -> void:
	for c: Variant in cards:
		discard.append(int(c))


func pile_size() -> int:
	return pile.size()


func discard_size() -> int:
	return discard.size()


## 从牌堆/弃牌堆取出一张，返回它**实际的实例号**（找不到返回 -1，且什么都不删）。
## 实例号优先、牌面兜底 —— 调用方常常只给牌号。「把这张牌拿去用」要带着返回的实例号走，
## 不要 remove 完再拿牌号重新发一张，否则同牌面的副本会撞号。
func 取出实例(cid: int) -> int:
	for 列: Array in [pile, discard]:
		var idx: int = 列.find(cid)
		if idx >= 0:
			var 实例: int = int(列[idx])
			列.remove_at(idx)
			return 实例
	var 面: int = GConst.牌号(cid)
	for 列2: Array in [pile, discard]:
		for i: int in range(列2.size()):
			if GConst.牌号(int(列2[i])) == 面:
				var 实例2: int = int(列2[i])
				列2.remove_at(i)
				return 实例2
	return -1


## 从牌堆/弃牌堆移除指定牌（用于盖牌、基础效果等离开牌堆的牌）
func remove_one(cid: int) -> void:
	取出实例(cid)

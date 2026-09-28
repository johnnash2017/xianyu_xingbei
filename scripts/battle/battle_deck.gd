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


## 把牌放进弃牌堆
func push_discard(cards: Array) -> void:
	for c: Variant in cards:
		discard.append(int(c))


func pile_size() -> int:
	return pile.size()


func discard_size() -> int:
	return discard.size()


## 从牌堆/弃牌堆移除指定牌（用于盖牌、基础效果等离开牌堆的牌）
func remove_one(cid: int) -> void:
	var idx: int = pile.find(cid)
	if idx >= 0:
		pile.remove_at(idx)
		return
	idx = discard.find(cid)
	if idx >= 0:
		discard.remove_at(idx)

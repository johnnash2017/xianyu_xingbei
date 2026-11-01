import io
import re

P = 'tests/cases/31_zhandoufashi.gd'
s = io.open(P, encoding='utf-8').read()

# 1) 第一块：支付选项恢复成「宝石 + 队友能量」两条
a, n1 = re.subn(
    r'== 1,\s*\n\s*"没有队友有能量时，【熵变】支付只剩宝石 1 个选项',
    '== 2,\\n\\t\\t"【熵变】支付应有 2 个固定选项',
    s,
)
b, n2 = re.subn(
    r'== \[true\],\s*\n\s*"只有我方战绩区有宝石时，宝石项应可点',
    '== [true, false],\\n\\t\\t"只有我方战绩区有宝石时，队友能量项应置灰',
    a,
)

# 2) 队友支付块：选项选 2 → 再点头像选队友（白名单）→ 再选 2 名对手
old = '''	var 队友支付问: Dictionary = _取询问(1, 4103)
	var 队友选项: Array = 队友支付问.get("notes", [])
	检(队友选项.size() == 2 and str(队友选项[1]).contains("队友"),
		"消耗队友能量时应把该队友列成选项（由玩家选）：%s" % str(队友选项))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [1000 + 队友.id], "card_ids": [], "dst_ids": [],
	})
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3, 4],
	})
'''
new = '''	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [2], "card_ids": [], "dst_ids": [],
	})
	var 队友问: Dictionary = _取询问(1, 4103)
	检(int((队友问.get("args", []) as Array)[1]) == 1
		and (队友问.get("dst_ids", []) as Array) == [队友.id],
		"选队友能量后应点头像选 1 名队友（白名单＝有能量的队友）：%s" % str(队友问))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [队友.id],
	})
	检(引擎._await_id == 1, "选完队友后应继续问【熵变】的 2 名目标对手")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 4103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [3, 4],
	})
'''
c, n3 = re.subn(re.escape(old), new, b)
print(n1, n2, n3)
assert n1 == 1 and n2 == 1 and n3 == 1
io.open(P, 'w', encoding='utf-8', newline='').write(c)

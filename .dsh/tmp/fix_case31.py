import io
import re

P = 'tests/cases/31_zhandoufashi.gd'
s = io.open(P, encoding='utf-8').read()

pat = re.compile(
    r'\t+检\(int\(\(熵变支付问\.get\("args", \[\]\)\[3\].*?\n'
    r'\t+"【熵变】支付应有 2 个固定选项.*?\n'
    r'\t+检\(\(熵变支付问\.get\("option_enabled".*?\n'
    r'\t+"只有我方战绩区有宝石时，队友能量项应置灰.*?\n',
    re.S,
)
new = (
    '\t\t检(int((熵变支付问.get("args", [])[3] '
    'if (熵变支付问.get("args", []) as Array).size() > 3 else 0) == 1,\n'
    '\t\t\t"没有队友有能量时，【熵变】支付只剩宝石 1 个选项：%s" % str(熵变支付问.get("args", [])))\n'
    '\t\t检((熵变支付问.get("option_enabled", []) as Array) == [true],\n'
    '\t\t\t"只有我方战绩区有宝石时，宝石项应可点：%s" % str(熵变支付问.get("option_enabled", [])))\n'
)
s2, n = pat.subn(new, s)
assert n == 1, n
io.open(P, 'w', encoding='utf-8', newline='').write(s2)
print('replaced')

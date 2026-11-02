import io

p = 'scripts/ui/battle_mobile.gd'
s = io.open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'

old = '''\t_目标锁死 = _套用自动选目标(指示配置)
\t# 「自动选目标」型（【瘟疫】/【剧毒新星】：对除自己外所有人；【逆流】：只有自己）：'''
new = '''\t_目标锁死 = _套用自动选目标(指示配置)
\t# 【别烦我……】目标被问「弃 1 张法术牌」那一步：把目标自己点亮（谁被点名弃牌一目了然），
\t# 替她发动的队友靠「+1 治疗」的动态提示 + 高亮一起看出来
\tif _skill_ask_id == GConst.技能_别烦我 and _skill_ask_need_card > 0 \\
\t\t\tand not _高亮目标.has(Logic.my_player_id):
\t\t_高亮目标.append(Logic.my_player_id)
\t# 「自动选目标」型（【瘟疫】/【剧毒新星】：对除自己外所有人；【逆流】：只有自己）：'''
c = s.count(old.replace('\n', nl))
print('count', c)
assert c == 1
s = s.replace(old.replace('\n', nl), new.replace('\n', nl))
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')

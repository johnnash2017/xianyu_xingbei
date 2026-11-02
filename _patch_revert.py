import io

# ---------------- 客户端：撤掉悬停高亮，改回「自动选中队友」（和其他技能同一套） ----------------
p = 'scripts/ui/battle_mobile.gd'
s = io.open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'


def rep(old, new, count=1):
    global s
    old = old.replace('\n', nl)
    new = new.replace('\n', nl)
    c = s.count(old)
    assert c == count, (c, old[:90])
    s = s.replace(old, new)


# 1) 悬停相关全部撤掉
rep('''func _显示技能说明(按钮: 技能按钮) -> void:
\tif 按钮 == null:
\t\treturn
\t# 【别烦我……】悬停时就把「替她发动的队友」点亮，让人先看清是谁来替她发动
\t_悬停技能号 = 按钮.技能号
\tif _悬停技能号 == GConst.技能_别烦我:
\t\t_点亮别烦我队友()
\t\t刷新选中面板()''',
    '''func _显示技能说明(按钮: 技能按钮) -> void:
\tif 按钮 == null:
\t\treturn''')

rep('''func _隐藏技能说明() -> void:
\tvar 原来是别烦我: bool = _悬停技能号 == GConst.技能_别烦我
\t_悬停技能号 = -1
\t# 没真的选中这个技能（还在行动阶段）就收起悬停时点亮的队友；选中状态的高亮由 _高亮目标 继续保留
\tif 原来是别烦我 and not (_mode == 4 and _pending_skill_id == GConst.技能_别烦我):
\t\t_高亮目标.clear()
\t\t刷新选中面板()''',
    '''func _隐藏技能说明() -> void:''')

rep('''## 鼠标正悬停着的技能按钮的技能号（-1＝没悬停）；【别烦我……】悬停时也要点亮替她发动的队友
var _悬停技能号: int = -1
''', '')

rep('''func 刷新选中面板() -> void:
\t# 悬停 / 选中【别烦我……】时，替她发动的队友要一直亮着（快照刷新后也不掉）
\tif _该点亮别烦我队友():
\t\t_点亮别烦我队友()
\tfor 面板: 战斗玩家面板 in _面板列表:''',
    '''func 刷新选中面板() -> void:
\tfor 面板: 战斗玩家面板 in _面板列表:''')

# 2) 「右手边队友」改成走 _sel_players（和其它自动选目标的技能完全一致）
rep('''\t\t"右手边队友":
\t\t\t# 只在「发动技能」那一次把替她发动的队友亮出来；询问通道（6 号 / 7 号是被问的人）不算。
\t\t\t# 只高亮、不当目标：技能本身不需要目标，提交时不能带 dst_ids
\t\t\tif _mode != 4:
\t\t\t\treturn false
\t\t\t_点亮别烦我队友()
\t\t\treturn false''',
    '''\t\t"右手边队友":
\t\t\t# 【别烦我……】发动时把替她发动的那个队友选中（和其它「自动选目标」的技能同一套表现）。
\t\t\t# 这次行动本来就由队友代选目标，本人不带目标；提交时服务端会忽略这里多出来的 dst
\t\t\tif _mode != 4:
\t\t\t\treturn false
\t\t\tvar 队友号: int = _右手边队友(Logic.my_player_id)
\t\t\tif 队友号 > 0:
\t\t\t\t_sel_players.append(队友号)''')

# 3) 删掉不再用的点亮辅助
rep('''## 此刻是否该把「替她发动的右手边队友」点亮：已经选中【别烦我……】或者正悬停在它上面
func _该点亮别烦我队友() -> bool:
\tif _悬停技能号 == GConst.技能_别烦我:
\t\treturn true
\treturn _mode == 4 and _pending_skill_id == GConst.技能_别烦我


## 把替她发动的队友加进高亮（纯展示，不参与提交）。找不到右手边队友时按「同队其他人」兜底
func _点亮别烦我队友() -> void:
\tvar 队友: int = _右手边队友(Logic.my_player_id)
\tif 队友 > 0:
\t\tif not _高亮目标.has(队友):
\t\t\t_高亮目标.append(队友)
\t\treturn
\tvar 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
\tif 我 == null:
\t\treturn
\tfor 玩家: GPlayer in Data.player_list:
\t\tif 玩家 != null and 玩家.id != 我.id and 玩家.color == 我.color \\
\t\t\t\tand not _高亮目标.has(玩家.id):
\t\t\t_高亮目标.append(玩家.id)


''', '')

io.open(p, 'w', encoding='utf-8', newline='').write(s)

# ---------------- 服务端：10601 忽略多带的 dst（队友高亮会被一起提交） ----------------
p = 'scripts/battle/roles/role_daduoshaonv.gd'
s = io.open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
old = '''\tif not (action.get("card_ids", []) as Array).is_empty() or not (action.get("dst_ids", []) as Array).is_empty():
\t\treturn GConst.GE_INVALID_ACTION'''.replace('\n', nl)
new = '''\t# 只校验「不带牌」。目标由右手边队友代选，本人这一手本来就没有目标；
\t# 客户端为了把「替她发动的队友」画成选中，会带上这名队友的 id —— 这里直接忽略
\tif not (action.get("card_ids", []) as Array).is_empty():
\t\treturn GConst.GE_INVALID_ACTION'''.replace('\n', nl)
c = s.count(old)
print('server', c)
assert c == 1
s = s.replace(old, new)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')

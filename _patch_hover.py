import io

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


# 1) 成员变量
rep('''## 纯「点亮给人看」的目标（不参与提交）：如【别烦我……】发动时把替她发动的队友亮出来。''',
    '''## 鼠标正悬停着的技能按钮的技能号（-1＝没悬停）；【别烦我……】悬停时也要点亮队友
var _悬停技能号: int = -1
## 纯「点亮给人看」的目标（不参与提交）：如【别烦我……】发动时把替她发动的队友亮出来。''')

# 2) 点亮队友的统一入口（悬停 / 已发动 都算）
rep('''func _套用自动选目标(指示配置: Dictionary) -> bool:''',
    '''## 此刻是否该把「替她发动的右手边队友」点亮：已经选中【别烦我……】或者正悬停在它上面
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


func _套用自动选目标(指示配置: Dictionary) -> bool:''')

# 3) 悬停 / 离开悬停时刷新高亮
rep('''func _显示技能说明(技能号: int) -> void:''',
    '''func _显示技能说明(技能号: int) -> void:
\t_悬停技能号 = 技能号
\t# 【别烦我……】悬停时就把「替她发动的队友」点亮，让人先看清是谁来替她发动
\tif 技能号 == GConst.技能_别烦我:
\t\t_点亮别烦我队友()
\t\t刷新选中面板()''')

rep('''func _隐藏技能说明() -> void:''',
    '''func _隐藏技能说明() -> void:
\tvar 原来是别烦我: bool = _悬停技能号 == GConst.技能_别烦我
\t_悬停技能号 = -1
\t# 没真的选中这个技能（还在行动阶段）就收起悬停时点亮的队友；选中状态的高亮由 _高亮目标 继续保留
\tif 原来是别烦我 and not (_mode == 4 and _pending_skill_id == GConst.技能_别烦我):
\t\t_高亮目标.clear()
\t\t刷新选中面板()''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')

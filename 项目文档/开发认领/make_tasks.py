#!/usr/bin/env python3
"""生成 tasks.json（任务板）。改任务时改这里再运行。"""
import json
from pathlib import Path

BASE = Path(__file__).resolve().parent


def T(tid, title, order, deps, files, size, acceptance, desc=""):
    return {
        "id": tid, "title": title, "order": order, "deps": deps,
        "files": files, "size": size, "acceptance": acceptance,
        "desc": desc, "status": "pending", "implementer": "", "reviewer": "",
        "issues": [],
    }


tasks = [
    T("F1", "F1 魔弹融合泛化（系别可配）", 10, [],
      ["scripts/battle/battle_role.gd", "tests/cases/25_missileElements.gd"], "M",
      "BattleRole 增加 missile_fusion_elements()（默认火/地）、missile_fusion_hand_ids()、can_use_as_missile(card)；"
      "v_missile_fusion / available 用的牌表走配置；8/76 行为不变；新增测试用 dummy 水/火角色验证通过/拒绝，并跑自检全过。",
      "只改列出的两个文件；不要改 role_modao/role_spmodao。参考 项目文档/禁用3星与3.5星角色开发计划.md F1。"),

    T("F5-archer", "F5-A 神箭手独有技 helper（301/302）", 20, [],
      ["scripts/battle/skills/skill_archer.gd", "tests/cases/f5_archer.gd"], "M",
      "新建 helper 类（构造传 BattleRole），实现神箭手 301 精准射击 / 302 闪光陷阱的校验+结算；"
      "不改 role_gongnv.gd；用 dummy 借用角色完成至少一次完整结算；测试通过，原角色自检不变。",
      "参考 role_gongnv.gd；helper 只暴露借用入口，状态放实例变量；不要改共享文件。"),

    T("F5-berserker", "F5-B 狂战士独有技 helper（201/202）", 21, [],
      ["scripts/battle/skills/skill_berserker.gd", "tests/cases/f5_berserker.gd"], "M",
      "新建 helper 类，实现 201 血影狂刀 / 202 血腥咆哮作为主动攻击时的响应；不改 role_kuangzhan.gd；"
      "用 dummy 借用角色完成一次攻击结算；测试通过，原角色自检不变。",
      "参考 role_kuangzhan.gd；9702/9703 会在此基础上改伤害/命中效果，接口要允许覆盖。"),

    T("F5-elemental", "F5-C 元素师独有技 helper（1101~1105）", 22, [],
      ["scripts/battle/skills/skill_elemental.gd", "tests/cases/f5_elemental.gd"], "M",
      "新建 helper 类，实现风刃/冰冻/火球/陨石/雷击的发动牌校验、额外弃同系加伤、各自后续效果；"
      "不改 role_yuansu.gd；用 dummy 借用角色各完成一次结算；测试通过。",
      "参考 role_yuansu.gd 的 available_skills/v_magic_skill/p_magic_skill；9303/9304 会借用并改雷击。"),

    T("F5-seal", "F5-D 封印师独有技 helper（401~405）", 23, [],
      ["scripts/battle/skills/skill_seal.gd", "tests/cases/f5_seal.gd"], "M",
      "新建 helper 类，实现五系封印的放置与展示触发（3 点法术伤害并移除）；不改 role_fengyin.gd；"
      "用 dummy 借用角色完成一次放置+触发；测试通过。",
      "参考 role_fengyin.gd；4606 会借用。注意基础效果牌/目标校验。"),

    T("F5-bless", "F5-E 祈祷师独有技 helper（1601/1602）", 24, [],
      ["scripts/battle/skills/skill_bless.gd", "tests/cases/f5_bless.gd"], "M",
      "新建 helper 类，实现迅捷赐福/威力赐福的放置与队友触发；不改 role_qidao.gd；"
      "用 dummy 借用角色完成一次放置+触发；测试通过。",
      "参考 role_qidao.gd；4606 会借用。注意队友目标与基础效果。"),

    T("F5-sword", "F5-F 剑圣独有技 helper（101/102）", 25, [],
      ["scripts/battle/skills/skill_sword.gd", "tests/cases/f5_sword.gd"], "M",
      "新建 helper 类，实现 101 疾风技（额外攻击行动）/ 102 烈风技（无视圣盾且无法应战）；"
      "不改 role_jiansheng.gd；用 dummy 借用角色完成一次攻击结算；测试通过。",
      "参考 role_jiansheng.gd；10802 会按攻击牌上的剑圣独有技触发。"),

    T("D1", "D1 数据审计（只读报告）", 30, [],
      ["项目文档/开发认领/data-audit.md"], "S",
      "逐角色/逐技能审计 59 颗技能：提示列缺口、指示物/盖牌、技能指示器、文本歧义、跨角色依赖、建议实现顺序；"
      "不改设计表/代码/CSV；报告引用设计表行号或技能号。",
      "只写 data-audit.md；读设计表/CSV/技能维护约定/计划。"),

    T("F2", "F2 额外行动与行动计数", 40, ["F1"],
      ["scripts/battle/battle_player.gd", "scripts/battle/battle_engine.gd",
       "scripts/battle/battle_role.gd", "tests/cases/26_actionCount.gd"], "L",
      "每回合攻击/法术/特殊/额外行动计数；行动结束通用钩子；额外行动目标/出牌限制接口；"
      "不改变现有角色行为；测试覆盖普通/额外行动、重置、限制；自检全过。",
      "参考 role_jiansheng.v_attack/action_card_ids、add_action；F2 是 45/41/107/108 的前置。"),

    T("F3", "F3 指示物/盖牌通用能力", 41, ["F1", "F2"],
      ["scripts/battle/battle_player.gd", "scripts/battle/battle_engine.gd",
       "scripts/battle/battle_mobile.gd", "tests/cases/27_tokensCover.gd"], "S",
      "验证/补齐 tokens/cover 的初始化、上限、消耗、UI 显示与角色名区分；子弹（盖牌槽2）、灵涌、元子可用；"
      "测试覆盖开局/上限/消耗；自检全过。",
      "参考 猎巫人 cover_cards、role_token_def、_按表初始化标识物；不要改角色数值。"),

    T("F4", "F4 基础效果目标/触发钩子", 42, ["F1", "F2", "F3"],
      ["scripts/battle/battle_engine.gd", "scripts/battle/battle_player.gd",
       "scripts/battle/battle_role.gd", "scripts/battle/battle_mobile.gd",
       "tests/cases/28_basicEffectTarget.gd"], "L",
      "新增 v_basic_effect_target（默认成功），add_basic_effect/出牌校验/客户端目标统一走它；"
      "新增基础效果触发并结算完成钩子；4601/4602/4604 可用；封印师/天使/圣女不回归；测试+自检。",
      "参考 add_basic_effect/remove_basic_effect/p_basic_effect_change、v_shield/v_weaken。"),

    T("F6", "F6 伤害转移/弃牌拦截（spike）", 43, ["F1", "F2"],
      ["scripts/battle/battle_engine.gd", "scripts/battle/battle_player.gd",
       "scripts/battle/battle_role.gd", "scripts/battle/battle_mobile.gd",
       "tests/cases/29_redirectIntercept.gd"], "L",
      "实现/验证 ⑥ 伤害改由自己承受且不掉士气；实现魔弹进弃牌前拦截钩子（或明确 best-effort 限制）；"
      "测试覆盖目标/伤害/士气/拦截；自检。",
      "4702/4704 的前置；先写时序测试，参考 push_harm/SHarmTimeline6/to_discard。"),

    T("F7", "F7 额外回合/角色替换（spike）", 44, ["F2"],
      ["scripts/battle/battle_engine.gd", "scripts/battle/battle_player.gd",
       "scripts/battle/battle_role.gd", "scripts/battle/battle_deck.gd",
       "tests/cases/29_extraTurn.gd"], "XL",
      "实现额外回合状态机（不推进 current_id）与角色替换为风之剑圣（重 setup/上限/技能）；"
      "或给出明确的降级接口与限制；测试覆盖回合边界/角色替换；自检。",
      "10803 的前置；风险最高，先 spike 再写完整；不要改 DATA/CLIENT。"),

    T("F8", "F8 牌库顶/星杯/士气", 45, ["F1", "F2"],
      ["scripts/battle/battle_engine.gd", "scripts/battle/battle_player.gd",
       "scripts/battle/battle_deck.gd", "tests/cases/29_deckStars.gd"], "M",
      "牌库顶逐张移除/展示/入弃牌；双方星杯数读取；移除战绩区全部星石并记录构成；士气转移；"
      "测试覆盖牌库不足/星杯 0/士气上限；自检。",
      "9701/10803/8704 的前置。"),

    T("F9", "F9 跨玩家操作", 46, ["F2"],
      ["scripts/battle/battle_player.gd", "scripts/battle/battle_engine.gd",
       "scripts/battle/battle_role.gd", "scripts/battle/battle_mobile.gd",
       "tests/cases/29_crossPlayer.gd"], "L",
      "右手边最近队友、随机弃手牌、跳过行动阶段标记、提炼前/后钩子、手牌补/弃到 N；"
      "106/78 可用；测试覆盖多玩家顺序/提示；自检。",
      "10601/10602/10604/7804 的前置。"),

    T("R38", "R38 游击士（38）5 技能", 100, ["F2", "F3"],
      ["scripts/battle/roles/role_youjishi.gd", "tests/cases/30_youjishi.gd"], "M",
      "实现 3801~3805：开局 6 子弹、元素射击分支、同系额外攻击、提炼补子弹、攻击牌视为风系；"
      "只改 role/test；数据启用留给 DATA；测试+自检。", "参考计划第 5 节第 2 批。"),

    T("R41", "R41 战斗法师（41）4 技能", 101, ["F2"],
      ["scripts/battle/roles/role_zhandoufashi.gd", "tests/cases/31_zhandoufashi.gd"], "M",
      "实现 4101~4104：弃2同系、命中/未命中额外法术、第3次行动结束、每次额外行动结束；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 2 批。"),

    T("R45", "R45 剑之魔女（45）4 技能", 102, ["F2"],
      ["scripts/battle/roles/role_jianzhimoni.gd", "tests/cases/32_jianzhimoni.gd"], "M",
      "实现 4501~4504：技类额外攻击、臆想剑弃牌/获得/加伤、梦想剑三种形态标记、剑影*断念；"
      "只改 role/test；测试+自检。", "108 的前置；参考计划第 5 节第 1 批。"),

    T("R46", "R46 灵熙之潮（46）6 技能", 103, ["F3", "F4", "F5-seal", "F5-bless"],
      ["scripts/battle/roles/role_lingxizhichao.gd", "tests/cases/33_lingxizhichao.gd"], "L",
      "实现 4601~4606：基础效果免疫、放置后1伤害、士气下降群伤、触发+灵涌、满灵涌群伤、借用封印/祈祷技；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 3 批。"),

    T("R47", "R47 爆食少女（47）5 技能", 104, ["F1", "F6"],
      ["scripts/battle/roles/role_baoshishaonv.gd", "tests/cases/34_baoshishaonv.gd"], "L",
      "实现 4701~4705：2目标弃法术、⑥伤害转移、水/火魔弹、弃牌前拦截、2目标2伤害；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 3 批。"),

    T("R75", "R75 EX魔弓（75）4 技能", 105, ["F5-archer"],
      ["scripts/battle/roles/role_exmogong.gd", "tests/cases/35_exmogong.gd"], "S",
      "实现 7501~7504：风系无法应战、未命中弃法术2伤害、借用301/302、7504狙击；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 1 批。"),

    T("R78", "R78 矜贵之女（78）5 技能", 106, ["F2", "F9"],
      ["scripts/battle/roles/role_jinguizhinv.gd", "tests/cases/36_jinguizhinv.gd"], "L",
      "实现 7801~7805：提炼+水晶、魔法入门多段、Magic!三分支、强予愿行手牌4、友情羁绊改写；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 3 批。"),

    T("R87", "R87 贪婪少女（87）4 技能", 107, ["F1", "F8"],
      ["scripts/battle/roles/role_tanlanshaonv.gd", "tests/cases/37_tanlanshaonv.gd"], "M",
      "实现 8701~8704：弃法术+水晶、额外法术、雷/火魔弹、清空星石/伤害成长/士气转移；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 2 批。"),

    T("R93", "R93 见习制片（93）5 技能", 108, ["F3", "F5-elemental"],
      ["scripts/battle/roles/role_jianxizhipian.gd", "tests/cases/38_jianxizhipian.gd"], "M",
      "实现 9301~9305：元子、重塑、借用元素师、雷击变异、月陨；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 1 批。"),

    T("R97", "R97 萝莉番长（97）4 技能", 109, ["F5-berserker", "F8"],
      ["scripts/battle/roles/role_luolifanzhang.gd", "tests/cases/39_luolifanzhang.gd"], "M",
      "实现 9701~9704：牌库顶加伤、借用狂战士201/202、改写202、宝石/水晶二选一；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 1 批。"),

    T("R106", "R106 怠惰少女（106）5 技能", 110, ["F1", "F9"],
      ["scripts/battle/roles/role_daduoshaonv.gd", "tests/cases/40_daduoshaonv.gd"], "L",
      "实现 10601~10605：队友随机弃牌/选目标、跳过行动、弃2同系魔弹、禁提炼/队友提炼奖励、跳过后的群疗/士气；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 3 批。"),

    T("R107", "R107 忌妒少女（107）4 技能", 111, ["F1", "F2"],
      ["scripts/battle/roles/role_jidushaonv.gd", "tests/cases/41_jidushaonv.gd"], "M",
      "实现 10701~10704：未命中弃法术/2伤害、命中额外法术且只魔弹+逆向、地/风魔弹、额外攻击手牌限制；"
      "只改 role/test；测试+自检。", "参考计划第 5 节第 2 批。"),

    T("R108", "R108 剑之子（108）4 技能", 112, ["F2", "F5-sword", "F7", "F8", "R45"],
      ["scripts/battle/roles/role_jianzhizi.gd", "tests/cases/42_jianzhizi.gd"], "XL",
      "实现 10801~10804：倾慕借用、风之剑、剑守誓言（额外出牌/星杯/额外回合/角色替换）、剑残影；"
      "只改 role/test；测试+自检。", "最后一批；依赖 45 和 F7。"),

    T("DATA", "DATA 数据启用/导表", 900,
      ["R38", "R41", "R45", "R46", "R47", "R75", "R78", "R87", "R93", "R97",
       "R106", "R107", "R108"],
      ["Table/Design/设计表.xlsx", "Table/Csv/角色表.csv", "Table/Csv/技能表.csv",
       "Table/TableScripts/DataTables.gd", "tests/_export_tables.gd"], "M",
      "从设计表改脚本列/启用列/提示/指示物，导表；13 角色进入选角池；数据测试更新；自检全过。",
      "所有角色完成后做；不要手改 CSV/DataTables。"),

    T("CLIENT", "CLIENT 客户端角色特性收口", 901,
      ["R38", "R41", "R45", "R46", "R47", "R75", "R78", "R87", "R93", "R97",
       "R106", "R107", "R108"],
      ["scripts/ui/battle_mobile.gd", "scripts/core/const.gd",
       "tests/cases/43_clientRoleFeatures.gd"], "M",
      "把 13 角色需要的目标/牌过滤、技能指示器、头像提示、选项集中接入；避免角色号硬编码散落；测试+自检。",
      "可与 DATA 并行；只改列出的客户端/常量文件。"),

    T("DOCS", "DOCS 文档与验收记录", 902, ["DATA", "CLIENT"],
      ["项目文档/项目说明.md", "项目文档/技能维护约定.md",
       "项目文档/禁用3星与3.5星角色开发计划.md"], "S",
      "更新角色数/技能数/自检数/公共能力约定；记录 13 角色实现与测试结果；自检全过。",
      "最后做；不要改代码。"),
]

data = {"version": 1, "root": str(BASE.parents[1]), "tasks": tasks}
(BASE / "tasks.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"wrote {len(tasks)} tasks")

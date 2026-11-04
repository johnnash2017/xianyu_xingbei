#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成/刷新《提示文案清单》，用于提示文案整合计划（P0）的盘点与迁移进度跟踪。

用法（在工程根目录）：
    python tests/tools/gen_prompt_inventory.py

会重写 项目文档/提示文案清单.md：
- 汇总：询问/ask_skill 调用点数量、带显式长文案的数量、选项字段使用量；
- 明细：每个调用点的文件:行号、技能表达式、是否有长文案、代码片段；
- 迁移进度：带长文案的调用点按文件统计（迁移一个少一个）。
"""
import io
import os
import re
import sys

ROLE_DIRS = ["scripts/battle/roles", "scripts/battle/skills"]
OUT = os.path.join("项目文档", "提示文案清单.md")


def has_cjk(text):
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def match_paren(text, open_idx):
    """从 open_idx（指向 '('）找配对的 ')'；跳过字符串与注释。找不到返回 -1。"""
    depth = 0
    i = open_idx
    in_str = False
    while i < len(text):
        ch = text[i]
        if in_str:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
        elif ch == "#":
            nl = text.find("\n", i)
            i = len(text) if nl < 0 else nl
            continue
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def split_top(text):
    """按顶层逗号切参数。"""
    parts = []
    depth = 0
    cur = []
    in_str = False
    i = 0
    while i < len(text):
        ch = text[i]
        if in_str:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(text):
                cur.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            cur.append(ch)
        elif ch in "([{":
            depth += 1
            cur.append(ch)
        elif ch in ")]}":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return parts


def cjk_literals(text):
    out = []
    for m in re.finditer(r'"([^"\n]{6,})"', text):
        lit = m.group(1)
        if has_cjk(lit):
            out.append(lit)
    return out


def main():
    files = []
    for d in ROLE_DIRS:
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith(".gd"):
                files.append(os.path.join(d, name))

    total = 0
    with_prompt = 0
    rows = []
    file_counts = {}
    opt_counts = {"skill_id": 0, "说明": 0, "card_id": 0, "提示": 0, "独立技能": 0}

    for path in files:
        text = io.open(path, encoding="utf-8").read()
        base = os.path.basename(path)
        lines = text.split("\n")
        for m in re.finditer(r"(询问|ask_skill)\(", text):
            line_no = text.count("\n", 0, m.start()) + 1
            line_text = lines[line_no - 1].strip() if line_no - 1 < len(lines) else ""
            if line_text.startswith("#") or line_text.startswith("func "):
                continue
            open_idx = m.end() - 1
            close_idx = match_paren(text, open_idx)
            if close_idx < 0:
                continue
            call = text[open_idx:close_idx + 1]
            total += 1
            args = split_top(call[1:-1])
            skill_expr = args[1] if len(args) > 1 else "?"
            lits = cjk_literals(call)
            has_prompt = len(lits) > 0
            if has_prompt:
                with_prompt += 1
                file_counts[base] = file_counts.get(base, 0) + 1
            for k in opt_counts:
                if '"%s"' % k in call:
                    opt_counts[k] += 1
            snippet = " ".join(call.replace("\n", " ").split())[:110]
            rows.append((base, line_no, m.group(1), skill_expr,
                         "是" if has_prompt else "", snippet))

    lines_out = []
    lines_out.append("# 提示文案清单（自动生成）\n")
    lines_out.append("> 由 `tests/tools/gen_prompt_inventory.py` 生成；迁移过程中可随时重跑刷新。\n")
    lines_out.append("> 用途：盘点所有 `询问` / `ask_skill` 调用点的文案来源，跟踪「长文案 → 表」的迁移进度。\n")
    lines_out.append("")
    lines_out.append("## 汇总\n")
    lines_out.append("| 项 | 数量 |")
    lines_out.append("| --- | ---: |")
    lines_out.append("| `询问` / `ask_skill` 调用点 | %d |" % total)
    lines_out.append("| 其中带显式中文长文案（待迁移） | %d |" % with_prompt)
    lines_out.append("| 选项字段 `skill_id` | %d |" % opt_counts["skill_id"])
    lines_out.append("| 选项字段 `说明` | %d |" % opt_counts["说明"])
    lines_out.append("| 选项字段 `card_id` | %d |" % opt_counts["card_id"])
    lines_out.append("| 选项字段 `提示`（新） | %d |" % opt_counts["提示"])
    lines_out.append("| 选项字段 `独立技能`（新） | %d |" % opt_counts["独立技能"])
    lines_out.append("")
    if file_counts:
        lines_out.append("## 待迁移文案（按文件）\n")
        lines_out.append("| 文件 | 带长文案的调用点 |")
        lines_out.append("| --- | ---: |")
        for name, count in sorted(file_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            lines_out.append("| %s | %d |" % (name, count))
        lines_out.append("")
    lines_out.append("## 调用点明细\n")
    lines_out.append("| 文件:行 | 形式 | 技能 | 有长文案 | 代码片段 |")
    lines_out.append("| --- | --- | --- | --- | --- |")
    for base, line, kind, skill, hp, snippet in rows:
        lines_out.append("| %s:%d | %s | `%s` | %s | `%s` |" % (base, line, kind, skill, hp, snippet))
    lines_out.append("")
    io.open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines_out))
    print("已生成 %s：调用点 %d，带长文案 %d" % (OUT, total, with_prompt))
    return 0


if __name__ == "__main__":
    sys.exit(main())

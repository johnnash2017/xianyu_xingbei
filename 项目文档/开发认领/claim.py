#!/usr/bin/env python3
"""多代理开发认领/评审小工具（只用标准库）。

放在 项目文档/开发认领/ 下，所有代理通过它读写任务板，避免并发改坏 tasks.json。
用法：
  python claim.py status
  python claim.py next --agent W1
  python claim.py finish --agent W1 --id F1 --summary "..." --tests "..." [--files "a,b"] [--blocked]
  python claim.py next-review --agent R1
  python claim.py review --agent R1 --id F1 --approve --notes "..." 
  python claim.py review --agent R1 --id F1 --issues "问题1；问题2"

约定：
  - next 会原子地检查依赖 + 文件范围重叠，然后把任务标成 claimed。
  - finish 只允许认领者调用；完成后进入 review。
  - next-review 只发没被自己实现的任务；review 禁止自评。
  - 文件范围按路径前缀判断重叠（写目录时以 / 结尾）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]          # 项目文档/开发认领 -> 项目根
TASKS = BASE / "tasks.json"
CLAIMS = BASE / "claims"
REVIEWS = BASE / "reviews"
LOCK = BASE / ".lock"

ACTIVE = {"claimed", "review", "reviewing", "needs_fix", "blocked"}
DONE = "done"


def now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def lock() -> None:
    for _ in range(200):
        try:
            LOCK.mkdir()
            return
        except FileExistsError:
            time.sleep(0.05)
    raise SystemExit("认领锁超时（.lock 残留？）")


def unlock() -> None:
    try:
        LOCK.rmdir()
    except OSError:
        pass


def load() -> dict:
    with TASKS.open("r", encoding="utf-8") as f:
        return json.load(f)


def save(data: dict) -> None:
    tmp = TASKS.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    tmp.replace(TASKS)


def by_id(data: dict, tid: str) -> dict:
    for t in data["tasks"]:
        if t["id"] == tid:
            return t
    raise SystemExit(f"找不到任务：{tid}")


def norm(p: str) -> str:
    return p.replace("\\", "/").strip()


def overlap(a: list[str], b: list[str]) -> bool:
    for x in a:
        x = norm(x)
        for y in b:
            y = norm(y)
            if x == y:
                return True
            if x.startswith(y.rstrip("/") + "/") or y.startswith(x.rstrip("/") + "/"):
                return True
    return False


def deps_done(data: dict, t: dict) -> bool:
    for d in t.get("deps", []):
        if by_id(data, d).get("status") != DONE:
            return False
    return True


def active_claims(data: dict, skip: str = "") -> list[dict]:
    return [t for t in data["tasks"] if t["id"] != skip and t.get("status") in ACTIVE]


def claim_path(tid: str) -> Path:
    return CLAIMS / f"{tid}.json"


def write_claim(t: dict, agent: str) -> None:
    CLAIMS.mkdir(exist_ok=True)
    payload = {
        "id": t["id"],
        "title": t["title"],
        "agent": agent,
        "claimed_at": now(),
        "status": "claimed",
        "files": t.get("files", []),
        "acceptance": t.get("acceptance", ""),
    }
    with claim_path(t["id"]).open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")


def cmd_next(data: dict, agent: str) -> None:
    lock()
    try:
        cand = []
        for t in data["tasks"]:
            if t.get("status") != "pending":
                continue
            if not deps_done(data, t):
                continue
            if any(overlap(t.get("files", []), o.get("files", [])) for o in active_claims(data)):
                continue
            cand.append(t)
        cand.sort(key=lambda x: (x.get("order", 9999), x["id"]))
        if not cand:
            print("NO_TASK")
            return
        t = cand[0]
        t["status"] = "claimed"
        t["implementer"] = agent
        t["claimed_at"] = now()
        write_claim(t, agent)
        save(data)
        print(json.dumps(t, ensure_ascii=False, indent=2))
    finally:
        unlock()


def cmd_finish(data: dict, agent: str, tid: str, summary: str, tests: str,
               files: str, blocked: bool) -> None:
    lock()
    try:
        t = by_id(data, tid)
        if t.get("status") != "claimed":
            raise SystemExit(f"任务 {tid} 当前状态 {t.get('status')}，不能 finish（只有认领中的任务能完成）")
        if t.get("implementer") != agent:
            raise SystemExit(f"{agent} 不是 {tid} 的认领者（{t.get('implementer')}），不能 finish")
        t["status"] = "blocked" if blocked else "review"
        t["summary"] = summary
        t["tests"] = tests
        if files:
            t["files_changed"] = [norm(x) for x in files.split(",") if x.strip()]
        else:
            t["files_changed"] = []
        t["finished_at"] = now()
        if blocked:
            t.setdefault("issues", []).append(summary)
        if claim_path(tid).exists():
            with claim_path(tid).open("r", encoding="utf-8") as f:
                c = json.load(f)
        else:
            c = {"id": tid, "title": t["title"], "agent": agent}
        c.update({
            "status": t["status"],
            "summary": summary,
            "tests": tests,
            "files_changed": t["files_changed"],
            "finished_at": t["finished_at"],
        })
        with claim_path(tid).open("w", encoding="utf-8") as f:
            json.dump(c, f, ensure_ascii=False, indent=2)
            f.write("\n")
        save(data)
        print(f"FINISHED {tid} -> {t['status']}")
    finally:
        unlock()


def cmd_next_review(data: dict, agent: str) -> None:
    lock()
    try:
        cand = [t for t in data["tasks"]
                if t.get("status") == "review" and t.get("implementer") != agent]
        cand.sort(key=lambda x: (x.get("order", 9999), x["id"]))
        if not cand:
            print("NO_TASK")
            return
        t = cand[0]
        t["status"] = "reviewing"
        t["reviewer"] = agent
        t["reviewing_at"] = now()
        save(data)
        print(json.dumps(t, ensure_ascii=False, indent=2))
    finally:
        unlock()


def cmd_review(data: dict, agent: str, tid: str, approve: bool, issues: str,
               notes: str) -> None:
    lock()
    try:
        t = by_id(data, tid)
        if t.get("status") != "reviewing":
            raise SystemExit(f"任务 {tid} 当前状态 {t.get('status')}，不能 review")
        if t.get("reviewer") != agent:
            raise SystemExit(f"{agent} 不是 {tid} 的评审者（{t.get('reviewer')}）")
        if t.get("implementer") == agent:
            raise SystemExit("禁止自评：评审者 = 实现者")
        REVIEWS.mkdir(exist_ok=True)
        issue_list = [x.strip() for x in issues.replace(";", "；").split("；") if x.strip()] if issues else []
        payload = {
            "id": tid,
            "title": t["title"],
            "reviewer": agent,
            "implementer": t.get("implementer"),
            "approve": approve,
            "issues": issue_list,
            "notes": notes,
            "reviewed_at": now(),
            "files": t.get("files", []),
        }
        with (REVIEWS / f"{tid}.json").open("w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
            f.write("\n")
        if approve:
            t["status"] = DONE
            t["reviewed_at"] = now()
            t["reviewer"] = agent
        else:
            t["status"] = "needs_fix"
            t["reviewed_at"] = now()
            t["reviewer"] = agent
            t.setdefault("issues", [])
            t["issues"].extend(issue_list or [notes or "评审未通过"])
        save(data)
        print(f"REVIEWED {tid} -> {t['status']}")
    finally:
        unlock()


def cmd_reopen(data: dict, tid: str, summary: str, agent: str) -> None:
    """主代理修复 needs_fix/blocked 后重新送审：认领者记为 agent（默认 MAIN），
    评审者清空，状态回 review，问题历史保留在 tasks.json 的 issues 里。"""
    lock()
    try:
        t = by_id(data, tid)
        if t.get("status") not in ("needs_fix", "blocked"):
            raise SystemExit(f"任务 {tid} 当前状态 {t.get('status')}，只有 needs_fix/blocked 能 reopen")
        t["status"] = "review"
        t["implementer"] = agent
        t["reviewer"] = ""
        t["summary"] = "[主代理修复] " + summary
        t["finished_at"] = now()
        t["reviewed_at"] = ""
        if claim_path(tid).exists():
            with claim_path(tid).open("r", encoding="utf-8") as f:
                c = json.load(f)
        else:
            c = {"id": tid, "title": t["title"]}
        c.update({
            "agent": agent,
            "status": "review",
            "summary": t["summary"],
            "finished_at": t["finished_at"],
        })
        with claim_path(tid).open("w", encoding="utf-8") as f:
            json.dump(c, f, ensure_ascii=False, indent=2)
            f.write("\n")
        save(data)
        print(f"REOPENED {tid} -> review (implementer={agent})")
    finally:
        unlock()


def cmd_release(data: dict, tid: str, summary: str) -> None:
    """主代理释放卡住的评审（评审代理异常退出等）：reviewing -> review，清空 reviewer。"""
    lock()
    try:
        t = by_id(data, tid)
        if t.get("status") != "reviewing":
            raise SystemExit(f"任务 {tid} 当前状态 {t.get('status')}，只有 reviewing 能 release")
        t["status"] = "review"
        t["reviewer"] = ""
        t["reviewed_at"] = ""
        t["summary"] = str(t.get("summary", "")) + " [主代理释放评审] " + summary
        save(data)
        print(f"RELEASED {tid} -> review")
    finally:
        unlock()


def cmd_status(data: dict) -> None:
    counts: dict[str, int] = {}
    print(f"{'ID':<12} {'状态':<10} {'实现':<6} {'评审':<6} 标题")
    for t in sorted(data["tasks"], key=lambda x: (x.get("order", 9999), x["id"])):
        st = t.get("status", "pending")
        counts[st] = counts.get(st, 0) + 1
        print(f"{t['id']:<12} {st:<10} {str(t.get('implementer','-')):<6} {str(t.get('reviewer','-')):<6} {t['title']}")
        for i in t.get("issues", []):
            print(f"    ! {i}")
    print("\n汇总：" + "，".join(f"{k}={v}" for k, v in sorted(counts.items())))


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("status")
    p.set_defaults(func=lambda data, a: cmd_status(data))

    p = sub.add_parser("next")
    p.add_argument("--agent", required=True)
    p.set_defaults(func=lambda data, a: cmd_next(data, a.agent))

    p = sub.add_parser("finish")
    p.add_argument("--agent", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--summary", required=True)
    p.add_argument("--tests", default="")
    p.add_argument("--files", default="")
    p.add_argument("--blocked", action="store_true")
    p.set_defaults(func=lambda data, a: cmd_finish(data, a.agent, a.id, a.summary, a.tests, a.files, a.blocked))

    p = sub.add_parser("next-review")
    p.add_argument("--agent", required=True)
    p.set_defaults(func=lambda data, a: cmd_next_review(data, a.agent))

    p = sub.add_parser("review")
    p.add_argument("--agent", required=True)
    p.add_argument("--id", required=True)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--approve", action="store_true")
    g.add_argument("--issues")
    p.add_argument("--notes", default="")
    p.set_defaults(func=lambda data, a: cmd_review(data, a.agent, a.id, a.approve, a.issues or "", a.notes))

    p = sub.add_parser("reopen")
    p.add_argument("--id", required=True)
    p.add_argument("--summary", required=True)
    p.add_argument("--agent", default="MAIN")
    p.set_defaults(func=lambda data, a: cmd_reopen(data, a.id, a.summary, a.agent))

    p = sub.add_parser("release")
    p.add_argument("--id", required=True)
    p.add_argument("--summary", required=True)
    p.set_defaults(func=lambda data, a: cmd_release(data, a.id, a.summary))

    a = ap.parse_args()
    data = load()
    a.func(data, a)


if __name__ == "__main__":
    main()

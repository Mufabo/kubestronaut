#!/usr/bin/env python3
"""Timed multiple-choice practice exam in the terminal (KCNA, and later KCSA).

    python3 tools/quiz.py kcna            take the exam, or resume a started attempt
    python3 tools/quiz.py kcna --reset    throw the attempt away
    python3 tools/quiz.py kcna --check    validate the bank against its quiz.yaml

The bank is mock-exams/<name>/questions.yaml (mcq questions with ids
<name>-<domain>-NN), and mock-exams/<name>/quiz.yaml sets the title, the time,
the pass mark, and the number of questions per domain. The attempt is saved
after every step in $KBOOK_QUIZ_DIR (default /tmp/kbook/<name>/attempt.json),
so a closed terminal loses nothing; the clock keeps running, as in the real
exam.
"""
import argparse
import importlib.util
import json
import os
import pathlib
import random
import re
import sys
import textwrap
import time

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
LETTERS = "ABCDE"
HELP = "letter = answer, Enter = next, p = back, f = flag, g N = go to N, r = review, s = submit, q = pause"


def _renderer():
    spec = importlib.util.spec_from_file_location("render_questions", ROOT / "tools" / "render-questions.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class QuizError(ValueError):
    """The bank or its quiz.yaml is malformed."""


def load(name, root=ROOT):
    d = root / "mock-exams" / name
    if not (d / "quiz.yaml").exists():
        raise QuizError(f"{d}/quiz.yaml not found; quizzes: {', '.join(sorted(p.parent.name for p in (root / 'mock-exams').glob('*/quiz.yaml')))}")
    meta = yaml.safe_load((d / "quiz.yaml").read_text(encoding="utf-8"))
    questions = yaml.safe_load((d / "questions.yaml").read_text(encoding="utf-8"))
    return meta, questions


def domain_of(qid):
    return qid.split("-")[1]


def check(name, meta, questions):
    """Raise QuizError with every problem found, or return None."""
    rq = _renderer()
    try:
        rq.validate(questions, f"{name}/questions.yaml")
    except rq.QuestionError as err:
        raise QuizError(str(err)) from None
    problems = []
    for key in ("title", "minutes", "pass_percent", "domains"):
        if key not in meta:
            problems.append(f"quiz.yaml: missing '{key}'")
    domains = meta.get("domains") or {}
    pattern = re.compile(rf"^{re.escape(name)}-({'|'.join(map(re.escape, domains))})-\d\d$")
    counts = {d: 0 for d in domains}
    for q in questions:
        if q["type"] != "mcq":
            problems.append(f"{q['id']}: a quiz takes only mcq questions")
        m = pattern.match(q["id"])
        if not m:
            problems.append(f"{q['id']}: id must be {name}-<domain>-NN with a domain from quiz.yaml")
        else:
            counts[m.group(1)] += 1
    for d, spec in domains.items():
        if counts[d] != spec.get("questions"):
            problems.append(f"domain {d}: quiz.yaml says {spec.get('questions')} questions, the bank has {counts[d]}")
    if sum(s.get("weight", 0) for s in domains.values()) != 100:
        problems.append("quiz.yaml: domain weights must add up to 100")
    if problems:
        raise QuizError("\n".join(problems))


def new_attempt(questions, now, in_order=False):
    order = [q["id"] for q in questions]
    if not in_order:
        random.Random(int(now)).shuffle(order)
    return {"started": now, "order": order, "answers": {}, "flags": [], "pos": 0, "finished": None}


def score(meta, questions, attempt):
    by_id = {q["id"]: q for q in questions}
    per = {d: [0, 0] for d in meta["domains"]}
    wrong = []
    for n, qid in enumerate(attempt["order"], 1):
        q, given = by_id[qid], attempt["answers"].get(qid)
        per[domain_of(qid)][1] += 1
        if given == q["answer"]:
            per[domain_of(qid)][0] += 1
        else:
            wrong.append((n, q, given))
    right = sum(c for c, _ in per.values())
    total = len(attempt["order"])
    percent = round(100 * right / total) if total else 0
    return {"right": right, "total": total, "percent": percent,
            "passed": percent >= meta["pass_percent"], "per": per, "wrong": wrong}


def fmt_time(seconds):
    seconds = max(0, int(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


class Session:
    def __init__(self, meta, questions, attempt, save, inp=input, out=print, now=time.time):
        self.meta, self.attempt, self.save = meta, attempt, save
        self.by_id = {q["id"]: q for q in questions}
        self.questions = questions
        self.inp, self.out, self.now = inp, out, now

    def left(self):
        return self.meta["minutes"] * 60 - (self.now() - self.attempt["started"])

    def show(self):
        a = self.attempt
        n = a["pos"] + 1
        qid = a["order"][a["pos"]]
        q = self.by_id[qid]
        flag = "   [flagged]" if qid in a["flags"] else ""
        self.out("")
        self.out(f"Question {n} of {len(a['order'])}{flag}".ljust(60) + f"{fmt_time(self.left())} left")
        self.out(textwrap.fill(q["question"].strip(), 78))
        for i, c in enumerate(q["choices"]):
            self.out(textwrap.fill(c, 78, initial_indent=f"  {LETTERS[i]}. ", subsequent_indent="     "))
        given = a["answers"].get(qid)
        self.out(f"Your answer: {given}" if given else "Not answered yet.")

    def review(self):
        a = self.attempt
        cells = []
        for n, qid in enumerate(a["order"], 1):
            mark = a["answers"].get(qid, "-") + ("F" if qid in a["flags"] else " ")
            cells.append(f"{n:>2}:{mark}")
        self.out("")
        for i in range(0, len(cells), 10):
            self.out("  ".join(cells[i:i + 10]))
        unanswered = len(a["order"]) - len(a["answers"])
        self.out(f"Answered {len(a['answers'])}, unanswered {unanswered}, flagged {len(a['flags'])}. (- = unanswered, F = flagged)")

    def finish(self, reason):
        self.attempt["finished"] = reason
        self.save(self.attempt)
        self.report()
        return "finished"

    def report(self):
        r = score(self.meta, self.questions, self.attempt)
        self.out("")
        self.out(f"{self.meta['title']}: {r['percent']}% ({r['right']} of {r['total']}), "
                 f"pass mark {self.meta['pass_percent']}%: {'PASS' if r['passed'] else 'NOT PASSED'}")
        for d, (c, t) in r["per"].items():
            self.out(f"  {self.meta['domains'][d]['title']}: {c} of {t}")
        if r["wrong"]:
            self.out("")
            self.out("Missed questions:")
        for n, q, given in r["wrong"]:
            self.out("")
            self.out(textwrap.fill(f"{n}. {q['question'].strip()}", 78))
            self.out(f"   Your answer: {given or '(none)'}. Correct: {q['answer']}. {q['choices'][LETTERS.index(q['answer'])]}")
            self.out(textwrap.fill(q["explanation"].strip(), 78, initial_indent="   ", subsequent_indent="   "))

    def run(self):
        a = self.attempt
        if a["finished"]:
            self.out("This attempt is finished.")
            self.report()
            return "finished"
        self.out(f"{self.meta['title']}: {len(a['order'])} questions, {self.meta['minutes']} minutes, "
                 f"pass mark {self.meta['pass_percent']}%.")
        self.out(HELP)
        while True:
            if self.left() <= 0:
                self.out("")
                self.out("Time is up.")
                return self.finish("time")
            self.show()
            try:
                cmd = self.inp("> ").strip()
            except EOFError:
                self.save(a)
                self.out("")
                self.out("Paused; run the same command to resume. The clock keeps running.")
                return "paused"
            if self.left() <= 0:
                self.out("")
                self.out("Time is up; the last input was not recorded.")
                return self.finish("time")
            qid = a["order"][a["pos"]]
            nchoices = len(self.by_id[qid]["choices"])
            low = cmd.lower()
            if len(cmd) == 1 and cmd.upper() in LETTERS[:nchoices]:
                a["answers"][qid] = cmd.upper()
                a["pos"] = min(a["pos"] + 1, len(a["order"]) - 1)
            elif low in ("", "n"):
                a["pos"] = min(a["pos"] + 1, len(a["order"]) - 1)
            elif low == "p":
                a["pos"] = max(a["pos"] - 1, 0)
            elif low == "f":
                if qid in a["flags"]:
                    a["flags"].remove(qid)
                else:
                    a["flags"].append(qid)
            elif re.fullmatch(r"g\s*\d+", low):
                n = int(low[1:])
                if 1 <= n <= len(a["order"]):
                    a["pos"] = n - 1
                else:
                    self.out(f"There is no question {n}.")
            elif low == "r":
                self.review()
            elif low == "s":
                unanswered = len(a["order"]) - len(a["answers"])
                if unanswered:
                    self.out(f"{unanswered} question(s) unanswered; they count as wrong.")
                try:
                    sure = self.inp("Submit now? [y/N] ").strip().lower()
                except EOFError:
                    sure = ""
                if sure == "y":
                    return self.finish("submitted")
            elif low == "q":
                self.save(a)
                self.out("Paused; run the same command to resume. The clock keeps running.")
                return "paused"
            else:
                self.out(HELP)
            self.save(a)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Timed multiple-choice practice exam.")
    ap.add_argument("name", help="the quiz, e.g. kcna")
    ap.add_argument("--reset", action="store_true", help="throw the current attempt away")
    ap.add_argument("--check", action="store_true", help="validate the bank and exit")
    ap.add_argument("--in-order", action="store_true", help="keep the bank's order (for testing)")
    args = ap.parse_args(argv)
    if not re.fullmatch(r"[a-z0-9-]+", args.name):
        print("quiz name must be lowercase letters, digits, and dashes", file=sys.stderr)
        return 2
    try:
        meta, questions = load(args.name)
        check(args.name, meta, questions)
    except (QuizError, yaml.YAMLError) as err:
        print(f"invalid quiz {args.name}:\n{err}", file=sys.stderr)
        return 1
    if args.check:
        print(f"{args.name}: {len(questions)} questions OK")
        return 0
    state_dir = pathlib.Path(os.environ.get("KBOOK_QUIZ_DIR", f"/tmp/kbook/{args.name}"))
    state = state_dir / "attempt.json"
    if args.reset:
        if state.exists():
            state.unlink()
        print(f"{args.name}: attempt removed; the next start begins a new one.")
        return 0
    if state.exists():
        attempt = json.loads(state.read_text(encoding="utf-8"))
        if set(attempt["order"]) != {q["id"] for q in questions}:
            print("The question bank changed since this attempt started; reset it first.", file=sys.stderr)
            return 1
    else:
        attempt = new_attempt(questions, time.time(), args.in_order)

    def save(a):
        state_dir.mkdir(parents=True, exist_ok=True)
        tmp = state.with_suffix(".tmp")
        tmp.write_text(json.dumps(a), encoding="utf-8")
        tmp.replace(state)

    save(attempt)
    try:
        result = Session(meta, questions, attempt, save).run()
    except KeyboardInterrupt:
        save(attempt)
        print("\nPaused; run the same command to resume. The clock keeps running.")
        return 0
    if result == "finished":
        print(f"\nStart a new attempt with: make quiz-reset EXAM={args.name}, then make quiz EXAM={args.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Render chapters/<NN-name>/questions.yaml into the chapter file
chapters/<NN-name>/<NN-name>.md (the chapter file is named after its directory).

The chapter file must contain the markers:
    <!-- QUESTIONS:START -->
    <!-- QUESTIONS:END -->
Everything between them is replaced. Run with --check in CI to fail if the
committed chapter file is out of date.

Question schema (questions.yaml is a list):
  - id: q01
    type: mcq            # mcq | task
    exams: [KCNA, CKAD]  # optional tags
    question: "..."      # (mcq) or prompt: "..." (task)
    choices: ["...", "..."]   # mcq only; 2-5 choices
    answer: B                 # mcq only; letter of the correct choice
    explanation: "..."        # why the answer is right
    solution: "..."           # task only; markdown, may include code blocks
"""
import argparse
import pathlib
import sys

import yaml

START, END = "<!-- QUESTIONS:START -->", "<!-- QUESTIONS:END -->"
LETTERS = "ABCDE"


ALLOWED_EXAMS = {"KCNA", "KCSA", "CKAD", "CKA", "CKS"}
COMMON = {"id", "type", "exams"}
FIELDS = {
    "mcq": COMMON | {"question", "choices", "answer", "explanation"},
    "task": COMMON | {"prompt", "solution"},
}
REQUIRED = {
    "mcq": {"id", "type", "question", "choices", "answer", "explanation"},
    "task": {"id", "type", "prompt", "solution"},
}


class QuestionError(ValueError):
    """The question bank is malformed."""


def _nonempty_str(value):
    return isinstance(value, str) and value.strip() != ""


def validate(questions, source="questions.yaml"):
    """Raise QuestionError with every problem found, or return None."""
    problems = []
    if not isinstance(questions, list) or not questions:
        raise QuestionError(f"{source}: the top level must be a non-empty list of questions")
    seen = set()
    for n, q in enumerate(questions, 1):
        where = f"{source}: question #{n}"
        if not isinstance(q, dict):
            problems.append(f"{where}: must be a mapping")
            continue
        qid = q.get("id")
        if _nonempty_str(qid):
            where = f"{source}: {qid}"
            if qid in seen:
                problems.append(f"{where}: duplicate id")
            seen.add(qid)
        else:
            problems.append(f"{where}: missing or empty 'id'")
        qtype = q.get("type")
        if qtype not in FIELDS:
            problems.append(f"{where}: 'type' must be one of {sorted(FIELDS)}, got {qtype!r}")
            continue
        for f in sorted(REQUIRED[qtype] - set(q)):
            problems.append(f"{where}: missing field '{f}'")
        for f in sorted(set(q) - FIELDS[qtype]):
            problems.append(f"{where}: unknown field '{f}' for type {qtype}")
        exams = q.get("exams", [])
        if not isinstance(exams, list) or any(e not in ALLOWED_EXAMS for e in exams):
            problems.append(f"{where}: 'exams' must be a list drawn from {sorted(ALLOWED_EXAMS)}")
        elif len(set(exams)) != len(exams):
            problems.append(f"{where}: duplicate entries in 'exams'")
        if qtype == "mcq":
            for f in ("question", "explanation"):
                if f in q and not _nonempty_str(q[f]):
                    problems.append(f"{where}: '{f}' must be non-empty text")
            choices = q.get("choices")
            if not isinstance(choices, list) or not 2 <= len(choices) <= 5 or not all(_nonempty_str(c) for c in choices):
                problems.append(f"{where}: 'choices' must be a list of 2 to 5 non-empty strings")
            else:
                if len({c.strip() for c in choices}) != len(choices):
                    problems.append(f"{where}: duplicate choices")
                if q.get("answer") not in LETTERS[: len(choices)]:
                    problems.append(f"{where}: 'answer' must be one of {LETTERS[:len(choices)]}, got {q.get('answer')!r}")
        else:
            for f in ("prompt", "solution"):
                if f in q and not _nonempty_str(q[f]):
                    problems.append(f"{where}: '{f}' must be non-empty text")
    if problems:
        raise QuestionError("\n".join(problems))


def render(questions):
    body, answers = [], []
    for n, q in enumerate(questions, 1):
        tags = " ".join(f"`{t}`" for t in q.get("exams", []))
        tags = f" {tags}" if tags else ""
        if q["type"] == "mcq":
            choices = q["choices"]
            body.append(f"**{n}.**{tags} {q['question'].strip()}\n")
            for i, c in enumerate(choices):
                body.append(f"- **{LETTERS[i]}.** {c}")
            body.append("")
            answers.append(f"**{n}. {q['answer']}.** {q['explanation'].strip()}\n")
        elif q["type"] == "task":
            body.append(f"**{n}. (Task)**{tags} {q['prompt'].strip()}\n")
            answers.append(f"**{n}.**\n\n{q['solution'].strip()}\n")
        else:
            raise ValueError(f"{q['id']}: unknown type {q['type']}")
    out = ["## End-of-chapter questions\n", *body,
           "<details>\n<summary>Answers</summary>\n", *answers, "</details>"]
    return "\n".join(out).rstrip() + "\n"


def process(chapter_dir, check):
    qfile = chapter_dir / "questions.yaml"
    readme = chapter_dir / f"{chapter_dir.name}.md"
    if not qfile.exists():
        return True
    if not readme.exists():
        print(f"{qfile} exists but {readme} is missing", file=sys.stderr)
        return False
    text = readme.read_text(encoding="utf-8")
    if START not in text or END not in text:
        print(f"{readme}: missing question markers", file=sys.stderr)
        return False
    head, rest = text.split(START, 1)
    _, tail = rest.split(END, 1)
    try:
        questions = yaml.safe_load(qfile.read_text(encoding="utf-8"))
        validate(questions, str(qfile))
    except (yaml.YAMLError, QuestionError) as err:
        print(f"invalid question bank:\n{err}", file=sys.stderr)
        return False
    new = f"{head}{START}\n\n{render(questions)}\n{END}{tail}"
    if new == text:
        return True
    if check:
        print(f"{readme}: questions out of date; run tools/render-questions.py", file=sys.stderr)
        return False
    readme.write_text(new, encoding="utf-8")
    print(f"updated {readme}")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("chapters", nargs="*", type=pathlib.Path)
    args = ap.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    dirs = args.chapters or sorted((root / "chapters").glob("*/"))
    # Validate every chapter (no short-circuit) so all problems are reported.
    ok = all([process(d, args.check) for d in dirs])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

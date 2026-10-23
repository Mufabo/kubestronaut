#!/usr/bin/env python3
"""Unit tests for tools/quiz.py: bank checks, scoring, and scripted sessions."""
import copy
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("quiz", ROOT / "tools" / "quiz.py")
quiz = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(quiz)

META = {
    "title": "Test quiz", "minutes": 10, "pass_percent": 75,
    "domains": {"one": {"title": "Domain one", "weight": 60, "questions": 2},
                "two": {"title": "Domain two", "weight": 40, "questions": 1}},
}


def mcq(qid, answer):
    return {"id": qid, "type": "mcq", "question": f"Question {qid}?",
            "choices": ["alpha", "beta", "gamma", "delta"], "answer": answer,
            "explanation": f"Because of {qid}."}


BANK = [mcq("t-one-01", "A"), mcq("t-one-02", "B"), mcq("t-two-01", "C")]


class Clock:
    def __init__(self, t=1000.0):
        self.t = t

    def __call__(self):
        return self.t


def session(inputs, attempt=None, clock=None, meta=META):
    clock = clock or Clock()
    attempt = attempt or quiz.new_attempt(BANK, clock(), in_order=True)
    feed, out, saved = iter(inputs), [], []

    def inp(_prompt):
        try:
            return next(feed)
        except StopIteration:
            raise EOFError from None

    s = quiz.Session(meta, BANK, attempt, lambda a: saved.append(json.dumps(a)), inp, out.append, clock)
    return s.run(), attempt, "\n".join(out), saved


class CheckTests(unittest.TestCase):
    def test_valid_bank_passes(self):
        quiz.check("t", META, BANK)

    def test_wrong_domain_and_counts(self):
        bank = copy.deepcopy(BANK)
        bank[2]["id"] = "t-three-01"
        with self.assertRaises(quiz.QuizError) as ctx:
            quiz.check("t", META, bank)
        msg = str(ctx.exception)
        self.assertIn("t-three-01: id must be", msg)
        self.assertIn("domain two: quiz.yaml says 1 questions, the bank has 0", msg)

    def test_weights_must_add_up(self):
        meta = copy.deepcopy(META)
        meta["domains"]["two"]["weight"] = 50
        with self.assertRaises(quiz.QuizError):
            quiz.check("t", meta, BANK)

    def test_task_questions_are_rejected(self):
        bank = copy.deepcopy(BANK)
        bank[0] = {"id": "t-one-01", "type": "task", "prompt": "Do it.", "solution": "Done."}
        with self.assertRaises(quiz.QuizError):
            quiz.check("t", META, bank)

    def test_real_quizzes_are_valid(self):
        found = sorted(p.parent.name for p in (ROOT / "mock-exams").glob("*/quiz.yaml"))
        self.assertIn("kcna", found)
        for name in found:
            meta, questions = quiz.load(name)
            quiz.check(name, meta, questions)


class ScoreTests(unittest.TestCase):
    def test_score_per_domain(self):
        a = quiz.new_attempt(BANK, 1000, in_order=True)
        a["answers"] = {"t-one-01": "A", "t-one-02": "D", "t-two-01": "C"}
        r = quiz.score(META, BANK, a)
        self.assertEqual((r["right"], r["total"], r["percent"], r["passed"]), (2, 3, 67, False))
        self.assertEqual(r["per"], {"one": [1, 2], "two": [1, 1]})
        self.assertEqual([n for n, _, _ in r["wrong"]], [2])

    def test_shuffle_keeps_every_question(self):
        a = quiz.new_attempt(BANK, 12345)
        self.assertEqual(sorted(a["order"]), sorted(q["id"] for q in BANK))


class SessionTests(unittest.TestCase):
    def test_all_correct_passes(self):
        result, a, out, _ = session(["a", "B", "c", "s", "y"])
        self.assertEqual(result, "finished")
        self.assertEqual(a["finished"], "submitted")
        self.assertIn("100% (3 of 3)", out)
        self.assertIn("PASS", out)
        self.assertNotIn("Missed questions", out)

    def test_wrong_answer_is_explained(self):
        result, _, out, _ = session(["a", "d", "c", "s", "y"])
        self.assertIn("NOT PASSED", out)
        self.assertIn("Your answer: D. Correct: B. beta", out)
        self.assertIn("Because of t-one-02.", out)

    def test_submit_needs_confirmation(self):
        result, a, out, _ = session(["a", "s", "n"])
        self.assertEqual(result, "paused")
        self.assertIsNone(a["finished"])
        self.assertIn("2 question(s) unanswered", out)

    def test_navigation_flag_and_review(self):
        _, a, out, _ = session(["f", "g 3", "c", "p", "r"])
        self.assertEqual(a["flags"], ["t-one-01"])
        self.assertEqual(a["answers"], {"t-two-01": "C"})
        self.assertIn(" 1:-F", out)
        self.assertIn(" 3:C ", out)
        self.assertIn("flagged 1", out)

    def test_letter_outside_choices_is_rejected(self):
        _, a, out, _ = session(["e"])
        self.assertEqual(a["answers"], {})
        self.assertIn(quiz.HELP, out)

    def test_eof_pauses_and_saves(self):
        result, _, out, saved = session(["a"])
        self.assertEqual(result, "paused")
        self.assertTrue(saved)
        self.assertEqual(json.loads(saved[-1])["answers"], {"t-one-01": "A"})

    def test_time_up_finishes(self):
        clock = Clock()
        a = quiz.new_attempt(BANK, clock(), in_order=True)
        clock.t += META["minutes"] * 60 + 1
        result, a, out, _ = session(["a"], attempt=a, clock=clock)
        self.assertEqual(result, "finished")
        self.assertEqual(a["finished"], "time")
        self.assertIn("Time is up.", out)
        self.assertIn("0% (0 of 3)", out)

    def test_finished_attempt_shows_report(self):
        a = quiz.new_attempt(BANK, 1000, in_order=True)
        a["finished"] = "submitted"
        result, _, out, _ = session([], attempt=a)
        self.assertEqual(result, "finished")
        self.assertIn("This attempt is finished.", out)


class CliTests(unittest.TestCase):
    def run_cli(self, *args, stdin=""):
        env = dict(os.environ, KBOOK_QUIZ_DIR=self.tmp)
        return subprocess.run([sys.executable, str(ROOT / "tools" / "quiz.py"), *args],
                              input=stdin, capture_output=True, text=True, env=env)

    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.tmp = self._dir.name

    def tearDown(self):
        self._dir.cleanup()

    def test_check(self):
        p = self.run_cli("kcna", "--check")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("kcna: 60 questions OK", p.stdout)

    def test_resume_and_reset(self):
        self.run_cli("kcna", "--in-order", stdin="a\n")
        state = pathlib.Path(self.tmp) / "attempt.json"
        first = json.loads(state.read_text())
        self.assertEqual(len(first["answers"]), 1)
        p = self.run_cli("kcna", stdin="b\n")
        self.assertIn("Question 2 of 60", p.stdout)
        self.assertEqual(len(json.loads(state.read_text())["answers"]), 2)
        self.run_cli("kcna", "--reset")
        self.assertFalse(state.exists())

    def test_bad_name(self):
        self.assertEqual(self.run_cli("../etc").returncode, 2)
        self.assertEqual(self.run_cli("nosuchquiz").returncode, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)

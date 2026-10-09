#!/usr/bin/env python3
"""Unit tests for the question bank validator in render-questions.py."""
import copy
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "render_questions", pathlib.Path(__file__).with_name("render-questions.py")
)
rq = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rq)

MCQ = {"id": "a1", "type": "mcq", "exams": ["KCNA"], "question": "Q?",
       "choices": ["one", "two"], "answer": "B", "explanation": "Because."}
TASK = {"id": "a2", "type": "task", "exams": ["CKA"], "prompt": "Do it.", "solution": "```bash\nx\n```"}


def bank(*items):
    return [copy.deepcopy(i) for i in items]


class ValidateTests(unittest.TestCase):
    def bad(self, questions, needle):
        with self.assertRaises(rq.QuestionError) as ctx:
            rq.validate(questions)
        self.assertIn(needle, str(ctx.exception))

    def test_valid_bank_passes(self):
        rq.validate(bank(MCQ, TASK))

    def test_root_must_be_nonempty_list(self):
        self.bad({}, "non-empty list")
        self.bad([], "non-empty list")
        self.bad("text", "non-empty list")

    def test_duplicate_ids(self):
        dup = copy.deepcopy(TASK); dup["id"] = "a1"
        self.bad(bank(MCQ, dup), "duplicate id")

    def test_missing_and_empty_id(self):
        q = copy.deepcopy(MCQ); del q["id"]
        self.bad([q], "missing or empty 'id'")
        q["id"] = "  "
        self.bad([q], "missing or empty 'id'")

    def test_unknown_type(self):
        q = copy.deepcopy(MCQ); q["type"] = "essay"
        self.bad([q], "'type' must be one of")

    def test_missing_required_fields(self):
        q = copy.deepcopy(MCQ); del q["explanation"]
        self.bad([q], "missing field 'explanation'")
        t = copy.deepcopy(TASK); del t["solution"]
        self.bad([t], "missing field 'solution'")

    def test_unknown_field_and_wrong_combination(self):
        q = copy.deepcopy(MCQ); q["hint"] = "x"
        self.bad([q], "unknown field 'hint'")
        t = copy.deepcopy(TASK); t["choices"] = ["a", "b"]
        self.bad([t], "unknown field 'choices'")

    def test_exam_names(self):
        q = copy.deepcopy(MCQ); q["exams"] = ["KCNA", "PMP"]
        self.bad([q], "'exams' must be a list")
        q["exams"] = ["KCNA", "KCNA"]
        self.bad([q], "duplicate entries in 'exams'")

    def test_choice_count_and_content(self):
        q = copy.deepcopy(MCQ); q["choices"] = ["only"]; q["answer"] = "A"
        self.bad([q], "2 to 5")
        q["choices"] = list("abcdef"); q["answer"] = "A"
        self.bad([q], "2 to 5")
        q["choices"] = ["a", ""]
        self.bad([q], "2 to 5")
        q["choices"] = ["same", "same"]; q["answer"] = "A"
        self.bad([q], "duplicate choices")

    def test_answer_letter(self):
        q = copy.deepcopy(MCQ); q["answer"] = "C"
        self.bad([q], "'answer' must be one of")
        q["answer"] = "b"
        self.bad([q], "'answer' must be one of")

    def test_empty_text_fields(self):
        q = copy.deepcopy(MCQ); q["question"] = " "
        self.bad([q], "'question' must be non-empty")
        t = copy.deepcopy(TASK); t["prompt"] = ""
        self.bad([t], "'prompt' must be non-empty")

    def test_all_problems_reported_together(self):
        q = copy.deepcopy(MCQ); q["answer"] = "Z"; q["hint"] = "x"
        with self.assertRaises(rq.QuestionError) as ctx:
            rq.validate([q])
        self.assertIn("unknown field", str(ctx.exception))
        self.assertIn("'answer' must be one of", str(ctx.exception))

    def test_render_roundtrip_has_answers(self):
        out = rq.render(bank(MCQ, TASK))
        self.assertIn("**B.** two", out)
        self.assertIn("<summary>Answers</summary>", out)
        self.assertIn("**1. B.** Because.", out)

    def test_real_chapter_banks_are_valid(self):
        import yaml
        root = pathlib.Path(__file__).resolve().parent.parent
        files = sorted(root.glob("chapters/*/questions.yaml"))
        self.assertTrue(files, "no question banks found")
        for f in files:
            rq.validate(yaml.safe_load(f.read_text(encoding="utf-8")), str(f))


if __name__ == "__main__":
    unittest.main(verbosity=2)

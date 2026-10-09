# Chapter template

Copy `chapters/04-pods/` as a starting point. Every chapter directory is named
`NN-short-slug`, and the chapter text is a Markdown file named after the
directory (`04-pods/04-pods.md`, never `README.md`). A chapter directory contains:

```text
NN-slug/
├── NN-slug.md        the chapter text
├── questions.yaml    end-of-chapter questions (rendered into NN-slug.md)
├── manifests/        starter YAML the reader is expected to use or edit
└── lab/
    ├── lab.env       LAB_NS, LAB_TIER, LAB_CONTEXT, LAB_PARTS (optional ones)
    ├── setup.sh      builds the starting state (idempotent)
    ├── reset.sh      tears down, then runs setup.sh
    ├── verify.sh     one check per task
    ├── solve.sh      automated reference solution (used by CI)
    ├── teardown.sh   optional: remove lab resources, restore kubectl context
    ├── parts/        optional: one script per part when LAB_PARTS is set
    └── solutions.md  human-readable solutions and explanations
```

Concept-only chapters (for example Chapter 01) have no `lab/` or `manifests/`
folder. They keep `NN-slug.md` and `questions.yaml`, use an exploration exercise
in place of a lab, and are ignored by `make test-tier1`.

## Chapter file structure

1. `# Chapter NN: Title`
2. Header block (blockquote): exams served, difficulty, time, lab tier, prerequisites
3. `## Learning objectives`: 4 to 8 bullets, each traceable to a curriculum bullet
4. `## Concepts`: explanation, with Mermaid diagrams where they help
5. `## Guided walkthrough`: commands with expected output, run on the pinned version
6. `## Hands-on lab`: how to start it, then `### Task 1` to `### Task 6`
7. `## Exam tips`
8. `## End-of-chapter questions`: between the `QUESTIONS` markers, generated
9. `## Further reading`

### Header block

```markdown
> **Exams:** KCNA · CKAD · CKA
> **Difficulty:** Beginner
> **Time:** ~45 min reading, ~30 min lab
> **Lab tier:** 1 (kind)
> **Prerequisites:** Chapter 03
```

### Task format

```markdown
### Task 2: Fix the broken pod (⏱ 3 min, ★★☆)

The pod `broken` in your namespace never starts. Make it run without deleting
and recreating it.

*Success looks like:* `broken` is `Running` and uses image `nginx:1.27`.
```

Tasks state the goal and the success condition, never the command to use.
Difficulty: ★☆☆ one command, ★★☆ a few steps or some diagnosis, ★★★ exam-level
multi-step or troubleshooting.

## Question rules

- 10 to 15 per chapter; at least 3 must be performance tasks for chapters serving CKA, CKAD, or CKS
- Multiple-choice distractors must be plausible misconceptions, not jokes
- Every answer has an explanation of why the right answer is right
- Tag each question with the exams it maps to
- Write original questions from the public curricula; never reproduce real exam content

## Definition of done

See `ROADMAP.md`, section 4.

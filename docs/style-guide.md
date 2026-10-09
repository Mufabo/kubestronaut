# Style guide

## Voice

- Second person, present tense, plain language. The reader is a capable engineer who is new to Kubernetes.
- Explain *why* before *how*. Every concept earns its place by answering "what problem does this solve?"
- No filler ("simply", "just", "obviously"). No jokes at the reader's expense.

## Commands and output

- Prompt-free code blocks for commands the reader should copy; separate blocks for expected output.
- Use `bash` fences for commands, `text` or `yaml` for output.
- Every command in a walkthrough must have been run on the version in `versions.env`.
- Show the imperative form first (`kubectl run`, `kubectl create`), then the declarative YAML it produces via `--dry-run=client -o yaml`.
- Never use `kubectl apply -f https://...` from an unpinned URL.

## Terminology

- Use official Kubernetes capitalization for API kinds: Pod, Deployment, Service.
- Say "control plane node", not "master".
- First use of an acronym is spelled out; the glossary covers the rest.

## Diagrams

- Mermaid only (renders on GitHub); keep each under about 15 nodes.
- Always give a text description nearby for accessibility.

## Exam callouts

Use this exact form so they can be found and collected later:

```markdown
> **Exam tip:** In the exam you can generate YAML fast with `--dry-run=client -o yaml`.
```

Never state or imply that a callout reflects actual exam questions.

## Length

- Concept sections: about 1,500 to 3,000 words per chapter.
- Labs: 3 to 6 tasks. If you need more, split the chapter.

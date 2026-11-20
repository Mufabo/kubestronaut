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

## Parts V to X (CKNE)

The networking Parts follow everything above, plus these rules. Their reader
is comfortable in a Linux shell but may have **never studied networking**.

### The glossary contract

- A networking term is **bold** and defined in plain words the first time the
  book uses it, and it is added to `appendices/glossary.md` in the same change,
  with the chapter that introduces it.
- After that first use, the term is used without a definition, so later
  chapters may link back: "a **subnet** (Chapter 40)".
- Never use a networking term before the chapter that defines it. If a chapter
  needs a later concept, give a one-sentence preview and a forward reference
  ("Chapter 43 explains how names become addresses").
- No filler: in these Parts also avoid "of course"; nothing is obvious to a
  beginner. One idea per paragraph.

### Analogies

- Use an analogy to introduce an idea, then show the real mechanism on the
  wire. Never let the analogy be the explanation.
- Reuse the running analogies instead of inventing new ones per chapter:
  **postal mail** for packets and addresses (envelopes inside envelopes for
  encapsulation), a **building with a mailroom** for a host and its ports, an
  **office switchboard** for a switch.

### See the packet

- Every chapter shows the concept in a real capture (`tcpdump`, `hubble
  observe`, Envoy access logs) before or right after explaining it. Show
  captures with `-n` and trim them to the lines that matter; say what to look
  at in each line.
- Every Concepts section has a **packet walk**: a Mermaid `sequenceDiagram`
  that follows one packet hop by hop, followed by an italic paragraph starting
  with `*Text description:*`.

### Commands and output in the netlab

- Part V commands run inside the netlab container. When a command must run
  inside a network namespace, show it with `on <host>`; the first time in a
  chapter, also show the long form `ip netns exec <host>`.
- Output comes from a real run in the netlab built from `versions.env`:
  capture it with a scratch script piped into
  `docker exec -i kbook-netlab bash`, then trim, never invent. MAC addresses,
  ports, and timings differ per run; say so where it matters.
- Prefer long options in explanations (`ip address show`), and introduce the
  short form (`ip a`) once it is understood.

### Terminology

- "host" means a machine with an IP address (in the netlab: a namespace
  playing that machine). "node" is reserved for Kubernetes nodes.
- Say "packet" for layer 3 and "frame" for layer 2, strictly, from Chapter 39 on.

### Callouts

Besides `> **Exam tip:**`, these Parts use one more exact form, one or two per
chapter, to connect a networking idea to Kubernetes:

```markdown
> **Why this matters for Kubernetes:** every Pod gets a veth pair exactly like this one.
```

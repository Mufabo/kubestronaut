# Chapter 39: Exam logistics and study plans per certification

> **Exams:** KCNA · KCSA · CKAD · CKA · CKS
> **Difficulty:** Beginner
> **Time:** ~40 min reading, ~30 min planning exercise
> **Lab tier:** none (no cluster needed)
> **Prerequisites:** none; read it early, and again two weeks before each exam

## Learning objectives

After this chapter you can:

- Compare the five Kubernetes certifications by format, length, pass mark, price, and Kubernetes version
- Choose an order for the exams that respects the CKS prerequisite and makes the most of the renewal rules
- Prepare your computer, room, and ID so that the check-in does not cost you the exam
- Work in the remote desktop of a performance-based exam: terminal, browser, copy and paste, and the timer
- Plan your time in a two-hour performance-based exam and in a 90-minute multiple-choice exam
- Build a week-by-week study plan for each certification from this book's chapters, labs, and mock exams

## Concepts

Every fact in this chapter comes from the Linux Foundation's published exam pages
and candidate handbook, read in October 2026. Prices, versions, and rules change.
Before you book, and again in the week before the exam, read the current pages:
the certification page of your exam on `training.linuxfoundation.org`, and the
candidate handbook and the exam's *Important Instructions* on
`docs.linuxfoundation.org`.

### The five exams at a glance

| | KCNA | KCSA | CKAD | CKA | CKS |
| --- | --- | --- | --- | --- | --- |
| Format | Multiple choice | Multiple choice | Performance-based | Performance-based | Performance-based |
| Length | 90 min | 90 min | 2 h | 2 h | 2 h |
| Items | 60 questions | 60 questions | 15–20 tasks | 15–20 tasks | 15–20 tasks |
| Pass mark | 75% | 75% | 66% | 66% | 67% |
| Price (exam only) | $250 | $250 | $445 | $445 | $445 |
| Kubernetes version | (none) | (none) | v1.37 | v1.37 | v1.35 |
| Prerequisite | none | none | none | none | a passed CKA |
| Simulator included | no | no | 2 killer.sh sessions | 2 killer.sh sessions | 2 killer.sh sessions |
| Documentation | none | none | allowed list (Chapter 38) | allowed list | allowed list |

All five are taken online, at home or at the office, under a remote proctor. Each
purchase includes **one retake**, and you have **12 months** from the purchase to
schedule and take the exam; the retake must also fall within those 12 months.
Results arrive by email within 24 hours. Every certification is valid for **two
years**.

The CKS runs an older Kubernetes version than the CKA and CKAD. The Linux
Foundation moves each exam to a new minor version within about four to eight weeks
of its release, but not all exams at the same time. This book pins the version
the CKA and CKAD use; the differences that matter for the CKS are noted in Part IV.

### Kubestronaut, and the order of the exams

The CNCF calls someone who has passed all five exams a **Kubestronaut**. The title
comes with a jacket, a private community channel, and discount coupons for further
exams. Check the program page for how the title is kept when a certification
expires.

Two rules shape the order in which you take the exams:

- **The CKS requires a passed CKA.** You cannot book it before.
- **Some exams renew others** (the Linux Foundation's CARE program). Passing the CKA or the CKAD renews your KCNA. Passing the CKS renews your KCSA, and a CKS earned or renewed on or after June 18, 2026 also extends your CKA to the CKS's expiry date.

So take the associate exams **first**: the professional exams that follow renew them
for free. A schedule that works well with this book:

| Step | Exam | Why here |
| --- | --- | --- |
| 1 | KCNA | Vocabulary and architecture; Parts I and II of the book cover most of it |
| 2 | CKAD | The application half of Kubernetes, hands-on; renews the KCNA |
| 3 | CKA | Builds on the CKAD skills and adds the cluster (Part III); renews the KCNA again |
| 4 | KCSA | The security concepts of Part IV, before the hands-on security exam |
| 5 | CKS | Last, because it needs the CKA; renews the KCSA and extends the CKA |

CKAD and CKA in the other order works too; their content overlaps by about half,
so book them close together. The certification that expires first in this plan is
the CKAD; renew it before its two years are up if you want to keep all five current.

### Before exam day

Most failed attempts that have nothing to do with Kubernetes fail at the check-in.
The rules from the candidate handbook:

- **Your computer.** Run PSI's online system check on the computer and network you will use. Use a personal computer: work laptops often have security software or firewalls that break the PSI Secure Browser. A virtual machine is not allowed, even if the system check passes. You need the rights to install software and stop processes.
- **One screen.** Only one active monitor is supported. For the performance-based exams the Linux Foundation recommends at least 15 inches and 1080p, because the remote desktop is small on a laptop screen.
- **Network.** A wired connection if you can, nothing else using bandwidth, and nothing blocking WebRTC or Amazon S3 (the performance-based exams need both).
- **The room.** Private, quiet, well lit, door closed, a clear desk with nothing on or under it, no papers on the walls. You must stay in the camera's view.
- **Your ID.** An original, unexpired, government-issued photo ID with a signature (a passport or national ID card works). The first and last name must match the name on your exam checklist **exactly**. Fix a mismatch days before, not at check-in.

The PSI Secure Browser is downloaded when you launch the exam. Start the launch
early, so that a problem with the installation does not eat into the slot.

### The performance-based exam environment

The exam window has two parts: the **content panel** on the left with the tasks,
and a **remote Linux desktop** on the right. On the desktop you get:

- A **terminal**, where you solve the tasks. Each task names the host or context to use; start every task by switching to it, exactly as this book's exam-style labs ask with their `Use context:` line.
- **Firefox**, for the allowed documentation (Chapter 38), with a translation extension.
- **VSCodium**, a graphical editor with its own terminal, as an alternative to `vim` in the terminal. Extensions cannot be installed.
- A **virtual keyboard**, for special characters that a non-US keyboard layout breaks.

Copy and paste uses the Linux shortcuts in the terminal: **Ctrl+Shift+C** and
**Ctrl+Shift+V**. In Firefox and VSCodium it is Ctrl+C and Ctrl+V. Practice both
before the exam: pressing Ctrl+C in the terminal stops a command instead of copying.

The **timer** shows the minutes left and warns at 30, 15, and 5 minutes. It never
stops: not for a break, not for a dropped connection, and no time is added
afterwards. If the remote desktop misbehaves, the settings menu has a **Reset
Desktop** option.

The task text can be switched to another language, but the terminal and the
communication with the proctor stay in English.

### Scoring

The exams are scored automatically, and the score report arrives within 24 hours.
The Linux Foundation does not publish how each task is scored. This book scores
its labs and mock exams strictly: a task counts only when everything it asks for is
right. If you pass the book's mocks under that rule, partial credit in the real
exam can only help.

If you fail a performance-based exam, you can ask for a **rescore** within two days, for a fee that is refunded if the result changes to a pass.
Multiple-choice exams cannot be rescored.

### Time strategy: performance-based exams

Two hours for 15 to 20 tasks is six to eight minutes per task, and the tasks are not
equally hard or equally weighted. Work in **two passes**:

1. **First pass:** go through the tasks in order. Solve each one that you can finish in about five minutes. If a task looks long or you get stuck, write its number down (a file in your home directory works: `echo 7 >> ~/later`) and move on. Never spend more than ten minutes on one task in the first pass.
2. **Second pass:** return to the skipped tasks, the highest weight first.
3. **Last ten minutes:** stop starting new work. Check that the tasks you solved are really done: the right context, the right Namespace, the Pod `Running`, the file written to the exact path.

The habits that save the most time are the ones from Chapters 03 and 37: switch the
context first, generate YAML with `--dry-run=client -o yaml` instead of typing it,
use `kubectl explain` instead of the browser for field names, and check each result
with one `get` before moving on.

### Time strategy: multiple-choice exams

Sixty questions in 90 minutes is 1.5 minutes per question. The exam screen lets you
**flag** a question and come back to it from the review screen before you finish.
Answer every question on the first pass, even a guess, and flag the ones you are
unsure of; a blank answer can never score. Use the remaining time for the flagged
ones. Read every option before you choose: KCNA and KCSA options are often all
plausible, and one word (CRI or CNI, Role or ClusterRole) decides.

### The killer.sh simulator

Each CKAD, CKA, and CKS purchase includes two sessions of the killer.sh simulator.
A session gives 36 hours of access from the moment you activate it and has 17
questions; the second session has a different set. The simulator is deliberately
harder and longer than the exam. Do not be discouraged by a low score there; use it
to find gaps.

Use the sessions late, when you have worked through the book: the first about two
weeks before the exam, the second in the last week. In each session, do the
questions under time pressure first, then use the remaining hours to study the
solutions and redo what you got wrong.

### Study plans

The plans below assume about eight to ten hours a week. Read each chapter, do its
lab until `make verify` passes without the solutions, and answer its questions.
Redo a lab with `make reset` when you needed the solution. The weeks are a guide:
spend longer where the end-of-chapter questions or labs show a gap.

#### KCNA (four weeks)

| Week | Chapters | Practice |
| --- | --- | --- |
| 1 | 01, 02, 03 | Labs 02 and 03; the KCNA-tagged questions |
| 2 | 04, 05, 06, 11 | Labs; mock exam `part1` as practice, untimed |
| 3 | 13, 15, 16, 21, 23 (read; labs optional) | The KCNA-tagged questions of each chapter |
| 4 | 24, 25, 28; review | The KCNA practice exam (`make quiz EXAM=kcna`), timed; review the missed questions' chapters; a new attempt at the end of the week |

Kubernetes Fundamentals is 44% of the exam: be fluent with the objects of Chapters
02 to 06. The labs are not required for a multiple-choice exam, but doing them makes
the vocabulary stick.

#### CKAD (six weeks)

| Week | Chapters | Practice |
| --- | --- | --- |
| 1 | 03, 04, 05, 06 | All labs; Chapter 03 `final` as a timed warm-up |
| 2 | 07, 08, 09 | Labs; mock exam `part1`, timed |
| 3 | 10, 11, 12 | Labs |
| 4 | 13, 14, 15, 16 | Labs; mock exam `part2`, timed |
| 5 | 37, 38; review | Terminal drills; redo every lab you needed the solution for; killer.sh session 1 |
| 6 | Review | Mocks `part1` and `part2` again until both pass in time; killer.sh session 2 |

#### CKA (six to eight weeks; four to five after the CKAD)

| Week | Chapters | Practice |
| --- | --- | --- |
| 1 | 02, 03, 05, 06, 11 | Labs; mock exam `part1`, timed |
| 2 | 07, 10, 12, 13, 14 (CKA parts) | Labs; mock exam `part2`, timed |
| 3 | 17, 18 | Labs (Chapter 18 on the Tier 2 VMs) |
| 4 | 19, 20, 21, 22 | Labs |
| 5 | 23, 24, 25 | Labs |
| 6 | 26, 27 | Labs; mock exam `part3`, timed |
| 7 | 37, 38; review | Redo every lab you needed the solution for; killer.sh session 1 |
| 8 | Review | All three mocks again; killer.sh session 2 |

After the CKAD, weeks 1 and 2 shrink to a review of the CKA-only topics, and the
plan takes four to five weeks. Troubleshooting is the largest CKA domain (30%):
Chapters 26 and 27 deserve a second pass.

#### KCSA (three to four weeks, after the CKA)

Part IV of the book (Chapters 29 to 36): read every chapter, answer the
KCSA-tagged questions, and do the labs where they exist; they make the concepts
concrete. Revisit Chapter 23 (RBAC) and Chapter 21 (NetworkPolicy).

#### CKS (five to six weeks, after the CKA and KCSA)

Part IV again, this time every lab, on kind and on the Tier 2 VMs; then Chapters 37
and 38 for the CKS's allowed documentation, which includes the docs of the
security tools. Use the killer.sh sessions in the last two weeks.

### Exam day

- **Before:** restart the computer, close everything, unplug second monitors, clear the desk, keep the ID at hand, and launch the exam early.
- **During:** read each task to the end before typing; check the context or host; keep an eye on the timer at the 30-minute warning.
- **After a disconnect:** reconnect at once. The timer kept running, so do not spend time redoing checks you already did.

## Planning exercise (no cluster required)

Make your own plan. Write the answers down; the questions at the end of the chapter
check the facts you need for it.

1. Pick the exam you will take next and a target date. Count the weeks from today, and choose the matching plan above. If you have fewer weeks, decide which chapters you already know and can skip.
2. Open the current certification page of that exam. Note the Kubernetes version, the price, and anything that differs from this chapter's table.
3. Run PSI's online system check on the computer and network you intend to use. Note anything it reports.
4. Compare the name on your Linux Foundation account with the name on your ID, letter for letter.
5. Put the two killer.sh sessions into your calendar: about two weeks before, and in the last week before the exam.
6. If you plan all five exams, write down their order and the date each certification would expire, and mark which later exam renews which earlier one.

## Exam tips

> **Exam tip:** Book the exam when you start studying, for a date that matches your plan. A booked date turns a plan into a deadline, and you can reschedule within the 12 months if you must.
>
> **Exam tip:** Do the check-in steps a day early: system check, ID name, room. The exam slot is too short to fix any of them on the day.
>
> **Exam tip:** In a performance-based exam, switch the context at the start of every task, even when the task before used the same one. A correct answer in the wrong cluster scores nothing.
>
> **Exam tip:** In a multiple-choice exam, never leave a question blank. Answer, flag, and come back.
>
> **Exam tip:** Use killer.sh to find gaps, not to predict your score. It is harder than the exam on purpose.

## Common misconceptions

- "The CKS can be taken first if I know security well." The CKS requires a passed CKA.
- "All Kubernetes exams run the same Kubernetes version." Each exam moves on its own schedule; in October 2026 the CKA and CKAD ran v1.37 and the CKS v1.35.
- "The timer stops if my connection drops." It does not, and no time is added afterwards.
- "A work laptop is fine, it is a good machine." Security software and firewalls on work devices are a common cause of failed launches; use a personal computer.
- "Two monitors help." Only one active monitor is supported.
- "A failed exam means paying again." Each purchase includes one retake within 12 months of the purchase.
- "Certifications last three years." They are valid for two years; three years applied only to CKA and CKAD certifications earned before April 2024.

<!-- QUESTIONS:START -->

## End-of-chapter questions

**1.** `CKS` You want to take the CKS. What must you have done first?

- **A.** Passed the KCSA
- **B.** Passed the CKA
- **C.** Passed the CKAD
- **D.** Nothing; the CKS has no prerequisite

**2.** `KCNA` `KCSA` What score do you need to pass the KCNA or the KCSA?

- **A.** 66%
- **B.** 67%
- **C.** 75%
- **D.** 80%

**3.** `KCNA` `KCSA` How much time do you have per question in the KCNA, on average?

- **A.** About 30 seconds
- **B.** About 1.5 minutes
- **C.** About 3 minutes
- **D.** About 6 minutes

**4.** `CKAD` `CKA` `CKS` Your connection drops for five minutes during the CKA. What happens to the timer?

- **A.** It pauses until you reconnect
- **B.** It keeps running, and the time is added back at the end
- **C.** It keeps running, and no time is added back
- **D.** The exam is cancelled and rescheduled

**5.** `CKAD` `CKA` `CKS` How do you paste text into the terminal of the exam's remote desktop?

- **A.** Ctrl+V
- **B.** Ctrl+Shift+V, or the right-click menu
- **C.** Pasting is not possible in the exam
- **D.** Cmd+V on a Mac, Ctrl+V elsewhere

**6.** `KCNA` `KCSA` `CKAD` `CKA` `CKS` Which computer setup is allowed for the online exam?

- **A.** A virtual machine that passes PSI's system check
- **B.** A laptop with an external monitor, both screens active
- **C.** A personal computer with one active monitor
- **D.** Any computer, as long as the webcam works

**7.** `KCNA` `KCSA` `CKAD` `CKA` `CKS` The name on your ID is "Maria Lopez Garcia"; your exam checklist says "Maria Lopez". What should you do?

- **A.** Nothing; a partial match is accepted
- **B.** Explain the difference to the proctor at check-in
- **C.** Correct the name in your exam checklist well before the exam, so that first and last name match exactly
- **D.** Bring a second ID

**8.** `KCNA` `CKAD` `CKA` You hold the KCNA and pass the CKAD. What happens to your KCNA?

- **A.** Nothing; it expires on its own date
- **B.** It is renewed, under the Linux Foundation's CARE program
- **C.** It is replaced by the CKAD and no longer listed
- **D.** It must be retaken within 12 months

**9.** `KCNA` `KCSA` `CKAD` `CKA` `CKS` You fail your first attempt at the CKAD, three months after buying it. What does the purchase still include?

- **A.** Nothing; a new attempt must be bought
- **B.** One retake, to be taken within 12 months of the purchase
- **C.** Unlimited retakes for a year
- **D.** One retake, but only after a waiting period of 12 months

**10.** `CKAD` `CKA` `CKS` In a two-hour exam with 17 tasks, task 4 is still not working after eight minutes. What is the best move?

- **A.** Keep going until it works; leaving it costs its whole weight
- **B.** Note its number, move on, and come back in a second pass
- **C.** Delete what you did and start it over
- **D.** End the exam early and use the retake

**11.** `CKAD` `CKA` `CKS` What is the killer.sh simulator best used for?

- **A.** Predicting your exam score exactly
- **B.** Finding gaps in the last weeks before the exam, under time pressure
- **C.** Learning Kubernetes from the start
- **D.** Seeing the real exam's questions

**12.** `KCSA` `CKA` `CKS` You will take all five exams. Which order makes the most of the renewal rules and respects the prerequisites?

- **A.** CKS, CKA, CKAD, KCSA, KCNA
- **B.** CKA, CKS, KCNA, KCSA, CKAD
- **C.** KCNA, CKAD, CKA, KCSA, CKS
- **D.** KCSA, CKS, KCNA, CKA, CKAD

**13. (Task)** `KCNA` `KCSA` `CKAD` `CKA` `CKS` You pass the KCNA on 2026-11-10 and the CKA on 2027-03-15. When does each expire, if you do nothing else?

<details>
<summary>Answers</summary>

**1. B.** The CKS requires a passed CKA before you can attempt it. The KCSA covers similar concepts and is a good preparation, but it is not a prerequisite.

**2. C.** The multiple-choice exams need 75%. The CKA and CKAD need 66%, and the CKS 67%.

**3. B.** The multiple-choice exams have 60 questions in 90 minutes, so 1.5 minutes each. Answer every question on the first pass and flag the uncertain ones for review.

**4. C.** The timer never stops, not for a break and not for a disconnect, and the Linux Foundation cannot add time back. Reconnect at once and carry on.

**5. B.** The remote desktop is Linux, and its terminal uses Ctrl+Shift+C and Ctrl+Shift+V (or the right-click menu). Other applications on the desktop, such as Firefox, use Ctrl+C and Ctrl+V.

**6. C.** Only one active monitor is supported, and a virtual machine is not allowed even if the system check passes. A personal computer avoids the security software of work devices that often breaks the PSI Secure Browser.

**7. C.** The first and last name on the ID must match the verified name on the exam checklist exactly. Fix it days before; at check-in it is too late.

**8. B.** Passing the CKA or the CKAD renews the KCNA; passing the CKS renews the KCSA. That is why the associate exams are best taken first.

**9. B.** Each purchase includes one retake, and it must be taken within 12 months of the original purchase.

**10. B.** At seven minutes per task on average, one stuck task can cost two or three easier ones. Note it, finish the tasks you can, and return to it with the time that is left.

**11. B.** The simulator is harder than the exam on purpose, and its questions are its own. Use each 36-hour session late in your preparation: answer under time pressure, then study the solutions.

**12. C.** The CKS needs the CKA, which rules out A and D. Taking the associates first lets the later exams renew them: the CKAD and CKA renew the KCNA, and the CKS renews the KCSA and extends the CKA.

**13.**

Both are valid for two years from the exam you pass. The CKA expires on 2029-03-15. Passing the CKA renews the KCNA under the CARE program, so the KCNA is current for two years from that pass as well, until 2029-03-15, instead of 2028-11-10. Check the Linux Foundation's CARE page for the exact date it shows, because the rules can change.

</details>

<!-- QUESTIONS:END -->

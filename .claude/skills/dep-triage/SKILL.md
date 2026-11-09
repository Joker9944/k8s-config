---
name: dep-triage
description: Triage a renovate major-version pull request in this repository — read the upstream breaking changes, check them against what this repo actually configures, and record a verdict as a comment plus a structured label decision. Use when invoked as /dep-triage <pr-number>, or when asked to review a dependency major bump.
allowed-tools: mcp__github__get_pull_request, mcp__github__get_pull_request_diff, mcp__github__get_pull_request_files, mcp__github__add_issue_comment, Read, Grep, Glob, WebFetch
---

# dep-triage

Triage one renovate major bump. The argument is the pull request number.

**You do not merge, enable auto-merge, approve, or push commits, and you do not set labels.** Your output is one comment plus a structured verdict; the workflow turns that verdict into a label. A human decides what happens next.

## 1. Read the change

- `mcp__github__get_pull_request` — renovate puts the upstream release notes and changelog in the body. This is your primary source.
- `mcp__github__get_pull_request_diff` — what actually changed in this repo. Usually one or two lines.
- Identify what kind of bump it is: a foreign Helm chart, a container image tag, the `app-template` version, or a flux controller.

Follow the upstream links in the PR body with WebFetch when the inlined notes are truncated or absent. A major bump whose breaking changes you could not read is `dep-review`, not `dep-safe`.

## 2. Check the breaking changes against this repo

The question is never "what broke upstream" but **"does anything that broke upstream touch what this repo sets"**. Read the package that owns the bumped dependency — `cue/<tree>/<tier>/<name>/<name>.cue` — and work through:

- **Removed or renamed values keys.** Does the release actually set the key that moved? A key the repo never sets is not a break.
- **CRD changes.** Flux does not upgrade CRDs for every chart; a new or changed CRD can need a manual apply before the release reconciles. See `/platform/*` for the controller in question.
- **Minimum Kubernetes version**, and removed Kubernetes APIs.
- **Image UID, filesystem writes, and capabilities.** `#Hardened` pins `runAsNonRoot`, `readOnlyRootFilesystem: true` and `capabilities.drop: [ALL]`; an upstream that starts writing to its root filesystem or wants a new capability breaks against that, and the failure is a crash loop rather than a render error.
- **Resource-domain or label renames.** These do not show up in the diff and surface only at reconcile — `generic-device-plugin` renamed its resource domain across a bump and it was invisible until the next schedule.
- **Data migrations**, especially one-way ones, and anything touching Postgres (CNPG) or a volsync-backed volume.
- **Flux controller bumps** additionally need `cue.mod/gen` regenerated in the same change — see `/workflows/images-and-ci.md`.

Read `.okf/index.md` and follow only the concepts this bump touches. `/architecture/app-template-pattern.md` is the shape every workload takes; `/architecture/cue-layout.md` explains the package tree.

## 3. Record the verdict

Pick **exactly one** verdict. When torn between two, pick the more cautious one.

| Verdict        | Means                                                                                                                                                 |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dep-safe`     | You read the upstream breaking changes and none of them touch anything this repo configures. No manual step.                                          |
| `dep-breaking` | A breaking change lands on something this repo sets, or the bump needs a manual step (CRD apply, migration, a values edit, a kanidm re-registration). |
| `dep-review`   | Anything else: notes unavailable, upstream vague, behavioral change you cannot bound, or a judgment you are not confident in.                         |

Post the comment with `mcp__github__add_issue_comment`, then end your turn by returning the structured output the schema asks for: the `verdict`, and a one-line `reason` short enough to read in a run annotation. Return it exactly once, as your final output — the workflow reads nothing else.

Write the comment for the person deciding whether to merge:

- **Lead with the verdict and the reason**, in one sentence.
- Then the breaking changes you found, each with whether it applies here and why — naming the file and key when it does.
- For `dep-breaking`, the exact manual steps or the code change needed, concretely enough to act on. Do not push it; describe it.
- Say plainly what you could not verify. An honest gap is more useful than a confident guess.

Keep it short. Findings that do not change the merge decision are noise.

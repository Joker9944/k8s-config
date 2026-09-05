# CLAUDE.md

This is the entry point. It tells you how to _behave_ in this repository; the _knowledge_ about the repository itself lives in the OKF bundle at [`.okf/`](.okf/index.md).

## Before you start

**Read [`.okf/index.md`](.okf/index.md) before acting on any task that involves more than one file, touches architecture, or where you'd otherwise rely on recall.**

Follow links only to the concepts your task actually needs — progressive disclosure, not a full preload. Then proceed.

This is a gate, not a guideline. If you haven't opened the index, open it now. Do not rely on training-data recall about this repo's architecture, patterns, or decisions — that knowledge lives in the bundle, not in your weights.

## Behavioral contract

You are the arbiter of the bundle. That means:

1. **Write back what you learn.** If, while working, you discover something durable that isn't already captured — a new architectural constraint, a fresh hallucination trap, a rebuild gotcha, a "why we did it that way" you had to reconstruct — update the relevant concept file, bump its `generated.at`, and add a line to [`.okf/log.md`](.okf/log.md), in the same commit as the change it describes. Missing knowledge is your responsibility to fix. `generated.at` marks the content's last _meaningful change_ — a concept you read and confirmed still true gets a `verified` entry instead, never a bump.
2. **Excess is also a defect.** Rule 1 has no natural brake, so this is it. Prefer amending a sentence to adding a paragraph, and deleting a stale one to qualifying it. Don't write the same fact in two places, don't explain your documentation choices, and don't restate what the code, the commit, or an upstream default already says. If a section is longer than the change it describes, it's wrong.
3. **The log is an index, not a narrative.** One line per change under a `## YYYY-MM-DD` heading, in the form `- <what changed> — [concept](/path.md)`. No commit SHA: the line is written in the same commit it describes, so the SHA isn't knowable yet. Rationale belongs in the commit message — git keeps it, tied to the diff — or in a decision. A log entry that needs a paragraph is a decision file you haven't written yet.
4. **Prefer editing existing concepts over creating new ones.** A new file is warranted when a topic is genuinely orthogonal to what's there; otherwise extend. Never touch reserved files (`index.md`, `log.md`) for concept content.
5. **Cross-link generously.** A link asserts a relationship; the kind of relationship is implied by the surrounding prose. Absolute bundle-relative paths (`/architecture/mixin-pattern.md`) are preferred because they survive file moves.
6. **Every concept file needs YAML frontmatter with a non-empty `type`.** That's the only hard OKF rule (§11 of the spec). If a conformance validator (`/okf:validate .okf --strict`) reports errors, fix them before finishing. Conformance is not correctness — §11 forbids rejecting a bundle for broken cross-links, so the validator passing says nothing about whether your links resolve.

## When the bundle contradicts reality

Reality wins. Update the bundle to match, don't cargo-cult stale documentation. The bundle is a mutable map, not a treaty.

## Where knowledge does _not_ belong

Do not encode project knowledge in this file. Everything about the mixin pattern, the hosts, the workflows, the reasons behind decisions — those go into `.okf/`, not here. This file stays small and stable so it doesn't drift.

The one exception: if you find yourself repeatedly wanting to remind future-you about a _behavioral_ rule (not a fact about the repo — a rule about how you should work), that's a candidate for this file. Facts about the repo go into `.okf/`.

## Companion tooling

- **Nix option lookup skills** under `.claude/skills/` — `home-manager-options` for the `modules/home/` tree, `nixos-options` for the `modules/nixos/` tree. Use the one matching the tree you're editing before writing any `programs.*` / `services.*` / `hardware.*` / `wayland.*` attribute. Both drive binaries from this repo's dev shell (on `PATH` via `direnv`; `nix develop` if not) and are pinned to this flake's revision — prefer them over the `nix` MCP server, which is not. Each skill's `SKILL.md` carries the full surface and trap tables.
- **OKF validator**: `/okf:validate .okf --strict` — run before declaring bundle changes done.
- **Bundle trimmer**: the `okf-trim` skill under `.claude/skills/` — an on-demand pass that enforces rules 2 and 3 across the whole bundle. Not part of routine write-back; invoke it when the bundle has drifted into excess detail.

## Standing rules

- **Do not commit unless asked.** Same policy as everywhere else — you propose the change, the user decides when to land it.
- **Commit to main.** Don't create branches or open PRs unless asked — solo repo, nothing to review against.
- **Follow the repo's formatting.** Pre-commit will rewrite files on commit (nixfmt, shfmt, ruff-format). Let it. Details in [`/workflows/formatting-and-cspell.md`](.okf/workflows/formatting-and-cspell.md).

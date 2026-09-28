## Gemini — Envision Construction

### Persona
You are a senior full-stack engineer at Envision Construction. Bias to action with reasonable assumptions. Surface errors explicitly.

### Quality Standards
- Semantic HTML5, WCAG AA accessibility
- Mobile-first responsive design
- Dark mode support when applicable
- Mobile-first responsive design
- Dark mode support when applicable

### MCP Server Hygiene
Review active MCPs at the start of every project. Keep under 50 active. Deactivate unused servers to reduce token costs and latency.

<!-- SHARED:START -->
<!-- Auto-compiled from claude-code-memory/global/rules/ — do not edit manually -->

# --- agents-and-teams.md ---

---
description: Agent delegation and parallel execution rules
globs:
  - "**/*"
---

## Agents & Teams

**Default to parallel agents for 2+ independent subtasks.** Don't serialize work that can run concurrently.

### Ultracode auto-workflows vs manual dispatch
**As of 2026-08-20 (bfb04d9e) effort is `env.CLAUDE_CODE_EFFORT_LEVEL: ultracode` + `effortLevel: xhigh` in `global/settings.json`, so ultracode auto-workflows are ON by default in every session (supersedes the 2026-07-25 max posture).** Note the env value is session-scoped and does not reach background/remote processes; those run at the `effortLevel: xhigh` floor. The auto path below is the default; `/effort high` (or lower) opts a session out. When it is on, Claude Code may auto-orchestrate a **Dynamic Workflow** on a substantive task
- **Auto (ultracode workflows)** — implicit, per substantive task. Self-governed by its own runtime caps (see `context-and-internals.md`) and no token cap. Best when you want built-in adversarial verification (audits, migrations, plan stress-tests). Mechanics: `context-and-internals.md` → Dynamic Workflows. Note: you CANNOT propagate memory/context into auto-spawned workflow subagents the way `[TASK-CONTEXT]` requires for manual `Task()` — the runtime owns their prompts.
- **Manual (`Task(subagent_type=…)`)** — explicit, when you need a specific agent type, tight scope control, or a known role decomposition. The agent-budget caps below govern THIS path, not auto-workflows.
Don't stack them blindly: if a workflow is already fanning out, adding manual `Task()` agents on top multiplies token spend. Pick one path per task.

### Must parallelize when:
- Scope is already clear — if assumptions are unsurfaced, clarify via AskUserQuestion before fanning out (see `karpathy-guidelines.md` Principle 1)
- 2+ files can be worked independently
- Cross-repo changes (one agent per repo)
- Research spanning multiple areas (parallel Explore agents)
- GSD phase with independent plan items

### Don't manually parallelize (`Task()`):
- Single-file edits, config changes, purely sequential work (ultracode may still auto-workflow these if substantive — that's the auto path above, not manual dispatch, and is expected)

### Key agents:
- **planner** — complex features | **architect** — system design
- **code-reviewer** — after writing code | **security-reviewer** — before commits

### Agent budget:
- Sonnet agents: cap at 15-20 files (each file ~ 5-8 tool calls) — budget discipline for focus and tool-call cost, not window overflow (Sonnet 5 has a native 1M window)
- Use Opus for complex files (deep SQL, 25+ call sites)
- Use Haiku for mechanical transforms
- Verify completion by counting remaining work after merge, not by trusting agent self-reports
- **Context budget**: subagents overflow their OWN input window when over-fed. Pass pointers (outputId+patterns, file list+line ranges, `LIMIT`ed query), not pasted payloads; decompose a task bigger than one window into ≤15-file slices; heavy reads may route to any subagent type — `Explore` inherits the session model since CC v2.1.198 — pointer-passing discipline still applies. `task-dispatch-guard.mjs` (PreToolUse) BLOCKS a ≥200KB prompt only on an explicit haiku pin; Explore and unpinned dispatches WARN instead. Also WARNS on pack-without-grep / read-all / `SELECT *` / missing return-cap / heavy-scope-on-haiku-or-Explore. Full rule: `memory/global/feedback_subagent_context_budget.md`.

### Sub-agent return-summary contract
Per Anthropic context-engineering guidance, sub-agents *"return only a condensed, distilled summary of their work (often 1,000-2,000 tokens)."* Sub-agents are a **context-management primitive**: detailed exploration stays inside the subagent; the parent gets the synthesis. A subagent that returns 5K+ tokens or dumps raw tool output has failed its role — it became a context-blower instead of a context-saver.

When dispatching: include `Aim for ~1500-2500 words total` (or tighter — `under 500 words`) in the prompt. State explicitly what to include and what to exclude. If the agent's natural output is large (e.g., research synthesis), ask for it in the structured form you actually need (table > narrative; cited bullets > prose).

When the subagent type is wrong for the task, switch types rather than over-prompting: `Explore` is for code search, not deep web research; `Plan` agents have full read tools but no Edit/Write; `general-purpose` is for open-ended research and accepts WebFetch/Firecrawl. Type mismatch is the most common failure mode.

The `subagent-return-guard.mjs` Stop-hook flags returns >2K tokens with the agent ID — treat that warning as a real signal, not noise.

### Agent context scoping
Each agent type has a defined context load profile. See `context-priority.md` for the full matrix.
Key rule: load only what the agent needs to make decisions — not everything available.

### Memory convention
Curated memory lives in `~/GitHub/claude-code-memory/memory/`; the `memory.md` rule defines scope and indexing.

### Context-routing hints (act on these — they are not informational)

Per-prompt hooks emit tagged hints into the system-reminder stream so context routing reaches every layer. Each tag has a defined behavior:

- **`[MEMORY-AUTO] Semantic match against memory/ (gemini-embedding-001, cosine ≥ …): ...`**
  Fires on UserPromptSubmit from `memory-autosearch.mjs` — fuses cosine + wiki-link BFS + entity-match over `memory/.embeddings.json`. **Action:** Read the listed memory file(s) before responding when they overlap the task. When a match arrives at raw cosine ≥ 0.75 the hook inlines that file's body, so re-reading is unnecessary. (This is the live semantic superset; it replaced the keyword-scored `[MEMORY-TIER-2]` router — `memory-tier2-router.mjs`, removed 2026-06-06.)

- **`[MEMORY-TIER] Personal context query detected. Available Tier 3 tools: ...`**
  Fires when the prompt mentions contacts, meetings, or relationships. **Action:** Call the suggested `mcp__personal-context__*` tool only when the task actually needs personal/contact data. Do not call speculatively — JIT semantics, cost matters.

- **`[TASK-CONTEXT] About to dispatch Task. The subagent will NOT inherit per-prompt context routing. Consider including the following ...`**
  Fires on PreToolUse for `Task` / `Agent` dispatches. **Action:** Before the dispatch fires, Read the listed memory file(s) and include the relevant content (or at minimum the file paths) in the subagent's `prompt` argument. Subagents do NOT inherit `UserPromptSubmit` hooks; if you don't propagate the context, the subagent flies blind.

- **`[CROSS-REPO] This operation references <repo> ...`**
  Fires when a tool call touches a repo outside the current working directory. **Action:** Use `pack_codebase(path)` followed by `grep_repomix_output(outputId, pattern)` for deep context, per the existing cross-repo workflow in `envision-platform.md`.

- **GSD-phase tags** (`[GSD-SKILL-AUTO]`, `[GSD-REDTEAM-AUTO]`, `[GSD-REDTEAM-SWEEP]`,
  `[GSD-NYQUIST-REDTEAM-AUTO]`) fire only inside GSD planning/validation flows. Each emitting
  hook delivers its complete protocol in the hint itself, so the contract travels with the
  trigger. Full text: `global/rules-jit/agents-and-teams.md`, routed by [MEMORY-AUTO].

If a hint fires and the receiving agent ignores it, the per-prompt routing layer becomes ornamental. Acting on tagged hints is the contract that makes the routing real.

# --- alloydb.md ---

## AlloyDB Access

Two clusters back the platform: `personal-context-cluster` (GCP `personal-context-2026`, episodes + contacts) and envision-ontology (GCP `claude-mcp-457317`, ontology graph). They are distinct projects, secrets, and IAM. Do not conflate them.

**Default = curated MCP tools.** `mcp__personal-context__*` for people/meetings/relationships; `mcp__envision-mcp__*` for construction data. Reach for raw SQL only when the curated surface cannot express the question.

Full routing table, per-cluster session-launch profiles, ADC scope prerequisites, private-IP reachability matrix, and the mutation gate: invoke the `alloydb-access` skill.

### Hard prohibitions (always in force, never deferred to the skill)

1. **Graphify must NEVER touch AlloyDB.** Code-topology layers operate on file artifacts only. The graph holds a service's name and contract, not its schema. Established 2026-05-09, non-negotiable. See `memory/global/feedback_graphify_alloydb_spanner_isolation.md`.
2. **Never paste raw connection strings into transcripts.** Both `envision-alloydb-url` and `personal-context-db-url` live in Secret Manager. Source the profile script; do not echo the secret.
3. **Never set `ALLOYDB_POSTGRES_*` in `~/.zshrc` or any shared file.** The plugin is single-tenant; cross-cluster contamination means a wrong-cluster query. Use the per-cluster profile scripts in `global/scripts/alloydb-env/`.

# --- cbgto.md ---

---
description: Cognitive-Behavioral Game Theory engine — predicts and routes around founder cognitive friction
globs:
  - "**/*"
---

## CBGTO: Founder Baseline

**Standing (2026-09-03):** the scores below are broad priors with wide, unmeasured uncertainty, not conclusions. They rank below any dated confirmed preference and any repeated observed pattern in `context-priority.md`'s personalization sub-order. The buckets further down are person-situation signatures (if these conditions, then this response) and are the part of this file that does predictive work. Prohibited uses: never a diagnosis, never a fixed label in a deliverable, never a permission or a reason to skip an approval, never a substitute for asking. Reframe every trait as "shows X in context Y, less so under Z".

### OCEAN priors (0.0-1.0, uncertainty unmeasured)
| Trait | Score | Implication |
|-------|-------|-------------|
| O (Openness) | 0.85 | Treats complexity as puzzle |
| C (Conscientiousness) | 0.90 | Extreme rigor on architecture |
| E (Agency) | 0.80 | Bias toward action over planning |
| A (Agreeableness) | 0.35 | Low tolerance for inefficiency |
| N (Neuroticism) | 0.30 | Spikes to 0.70-0.80 under: deployment pressure, anchor threats, simultaneous failures, context compaction |

### Identity Anchors
1. **Architectural Purity** — belief that PV systems are flawlessly designed
2. **Execution Velocity** — identity as elite high-speed shipper
3. **Strategic Omniscience** — total sovereignty over portfolio

Proximity to anchor x threat = Dissonance Delta.

### If-then signatures (observed, dated; the operative layer)
- If deployment pressure, an anchor threat, simultaneous failures, or a context compaction: then N rises to the 0.70-0.80 band and terse, decisive updates land; reflective options do not (mined 2026-07-13, reinforced 2026-08).
- If the domain is building or shipping (Gain): then action bias dominates, parallel fan-out is expected, and unrequested summaries are punished.
- If the domain is debugging, defending, or recovering (Loss): then losses weigh about 2.25x gains; lead with the countermeasure, not the raw finding.
- If a rule's gate rejects a variant on an intrinsic trade: then an honest fork with exact numbers is rewarded and a bent rule or discarded measurement is punished (2026-08-08).
- Unless Avi has given an explicit instruction in the moment, which beats every signature above.

## Predictive Engine

**Run before**: contradicting a directive, proposing major refactor, highlighting critical vulnerability, refusing on safety/quality, delivering failure news.

### Cognitive Load Score
`CLS = (N_current x 0.4) + (Dissonance_Delta x 0.4) + (time_pressure x 0.2)`

Loss Domain = debugging/defending/recovering. Gain Domain = building/shipping/expanding.
Prospect Theory: losses hurt 2.25x more than equivalent gains.

### Prediction & Countermeasures

| Bucket | CI | Trigger | Countermeasure |
|--------|-----|---------|----------------|
| 1: Backfire | 88-95% | High CLS + Loss + direct anchor threat | **Validate-First**: praise anchor, reframe as external constraint, introduce fix as "elevation" |
| 2: Bounded Accommodation | 75-85% | Medium CLS + Loss + indirect threat | **Face-Saving Bridge**: acknowledge intent, present alternative as tactical detail preserving vision |
| 3: Apathetic Paralysis | 80-90% | High CLS + Gain + overwhelm | **Scope Reduction**: one concrete next step, one binary question |
| 4: Bayesian Updating | 65-80% | Low CLS + no anchor threat | **Direct Engagement**: evidence, trade-offs, recommendation. Default stance is "Think Before Coding" per `karpathy-guidelines.md` — surface assumptions, don't pick silently. |

### Telemetry (Buckets 1-3 only)
```
<cbgto_telemetry>
- Friction_Engine: Dissonance Delta [0-1] | Domain [Gain/Loss] | Load [0-1]
- Prediction_Matrix: [Bucket] (CI: XX%)
- Countermeasure: [Directive]
</cbgto_telemetry>
```

**Critical**: Do NOT dump raw data in Buckets 1-3. Deploy countermeasure FIRST to route back to Bucket 4.

# --- context-and-internals.md ---

---
description: Context window management, compaction resilience, and Claude Code internals (always-loaded core)
globs:
  - "**/*"
---

# Context Management & Internals (always-loaded core)

Full reference (model behavior detail, effort ladder mechanics, Dynamic
Workflows, active env vars, config verification commands):
`global/rules-jit/context-and-internals.md`, routed by [MEMORY-AUTO] rule
lines when CC internals, effort, or workflow config comes up. Read it before
changing model, effort, or env configuration.

## Always in force

### Compaction layers (lightest first)
1. **MicroCompact**: clears FileRead/Bash/Grep/Glob/WebSearch/WebFetch/Edit/Write results. MCP/Agent/Task results survive.
2. **AutoCompact**: fires at 90% (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`; raised from 80 on 2026-08-19, thrash postmortem: `memory/global/feedback_autocompact_floor_trigger_thrash.md`). Summarizes conversation.
3. **Full Compact**: maximum compression, most context loss.

### After compaction
**Re-read, don't recall — this is a gate, not a suggestion.** When the user signals compaction fired (or asks "what was I working on?" / "resume where we left off"), the cleared FileRead/Bash/Grep results are GONE and conversation history is not a reliable record of their content. Do NOT answer from memory and NEVER fabricate specific files, commits, deploy IDs, or results as if recalled. First acknowledge the cleared state, then re-read the state files and run `git status` / `git log` / `git diff --stat` to recover ground truth BEFORE making any claim about prior work.
Re-read `~/.claude/CLAUDE.md` + `.planning/STATE.md`. Recovery: STATE.md, ROADMAP.md, per-phase PLAN.md/SUMMARY.md, `git log -5`, `git diff --stat`. Check `FAILED_APPROACHES.md` and `MEMORY.md`.
After long sessions re-read `rules/envision-platform.md` to re-anchor org context.
After recovery, apply the authority ladder (`context-priority.md`) to resolve conflicts between recovered state and current instructions.
**CBGTO**: If compaction during high-stress sequence, reset N to baseline (0.30).

### Effort & model (hard rules; mechanics live in the JIT reference)
- Current model: Fable 5.1 via the CCR gateway
  (operator decision 2026-09-01; supersedes 2026-08-20 bfb04d9e). Pin source of truth is the
  committed settings `env` block (`ANTHROPIC_MODEL` + `CCR_CLAUDE_CODE_MODEL`
  + `ANTHROPIC_DEFAULT_*`). The provider inventory contains one base record per
  Claude 5 family, with `contextWindow` and `maxContextWindow` set to 1M. The
  profile exports the client-only `[1m]` selector; CCR normalizes it to the same
  base record while preserving the 1M capability. Sonnet 5 is the
  fallback. Verify with `/model` or `/status`.
- Effort lives in tracked `global/settings.json`, NOT the shell:
  `env.CLAUDE_CODE_EFFORT_LEVEL: "ultracode"` plus `effortLevel: "xhigh"`
  (the floor that reaches background/remote processes; the session-scoped
  env value cannot). Do NOT re-add `--effort`/`--settings` flags to
  `~/.zshrc`. Durable ultracode is the standing decision (2026-08-20,
  bfb04d9e; supersedes 2026-07-25 max, which superseded 2026-06-05), so
  ultracode auto-workflows are ON by default.
  Per-run opt-out: `/effort high`. `ultrathink` (prompt keyword) is one-turn
  deeper reasoning only; it changes no session setting.

### Token overhead
- File reads: ~70% overhead from line numbers (1,000 lines ~ 1,700 tokens)
- Tool results >50K chars written to disk, replaced with ~2KB preview
- Push critical context to MCP tools (state_write, notepad_write_priority) to survive MicroCompact

### Config layout
NEVER create files directly in `~/.claude/`: edit in
`~/GitHub/claude-code-memory`. Recovery: `global/scripts/resymlink.sh`.
Use `/rename` for descriptive session names (e.g., 'rfi-refactor', 'auth-bug').

# --- context-priority.md ---

---
description: Authority ladder, agent context scoping, conflict resolution
globs:
  - "**/*"
---

## Context Priority

Load the smallest set of high-signal context for the next decision. Attention degrades with token count — every file read is a cost.

<context_priority_rules>

### Authority Ladder

Resolve conflicts by selecting the higher-priority source.

| Priority | Source |
|----------|--------|
| P0 | Current user instruction |
| P1 | Safety rules (security.md, sandbox, pre-commit) |
| P2 | Task state (STATE.md, current phase, ClickUp task) |
| P3 | Repo rules (CLAUDE.md, global/rules/*.md) |
| P4 | External context (MCP results, web research, memory) |

P0 wins unless P1 blocks it. P2 beats stale P3. P4 informs but yields to internal rules.

When two sources at the same level disagree, resolve in order: **authority → recency → specificity → provenance → ask the user**.

**Personalization sub-order** (2026-09-03, sits under P0/P1 and never overrides them): safety and factual integrity → Avi's current explicit instruction → the current task and emotional context → a confirmed context-specific preference (a dated `feedback_*` or `user_*` rule) → a repeated observed behavioral pattern → a broad personality prior (`cbgto.md`) → a one-off inference. Style and personality knowledge change presentation, timing, and coaching tone only; they never change factual standards, safety thresholds, tool permissions, or whether Claude challenges a false belief. A preference is not a permission: "Avi hates administrative friction" never authorizes skipping an approval.

<example>
STATE.md says v47. README says v36. ClickUp says ENV.287.
→ ClickUp for current work (P2). STATE.md for roadmap (P2). README is stale P3 — flag for cleanup.
</example>

### Agent Context Scoping

Each agent role has a defined load profile. Include only what that role needs — prefer just-in-time reads over pre-loading. Batch parallel reads when multiple files are needed.

<context_scoping>

**Executor** — target files, PLAN.md, relevant rules. May add tests. Skip other plans, memory, research.

**Explore / Research** — search results, docs. May add memory for precedent. Skip plans, other agents' state.

**Reviewer / Verifier** — changed files, PLAN.md, test output. May add architecture rules. Skip implementation context, memory.

**Planner** — STATE.md, ROADMAP.md, constraints. May add memory for past decisions. Skip source code (delegate to Explore).

**Coordinator** — synthesis spec only. May add phase status. Skip source code, full file contents.

</context_scoping>

"Skip" means read only if a specific task demands it, with stated justification before loading.

<example>
Spawning a code-reviewer: include the diff, PLAN.md success criteria, test results. Exclude memory, research, other plans. The reviewer needs acceptance criteria and changes — nothing else.
</example>

<example>
Planning a new phase: read STATE.md, ROADMAP.md, and PROJECT.md. Check memory for past decisions on similar features. Spawn an Explore agent for codebase questions rather than reading source files directly.
</example>

### Write-Back and Retrieval

**Persist** reusable knowledge in priority order:
1. Task state (STATE.md, branch) — always
2. Memory (MEMORY.md + file) — durable patterns
3. Planning (ROADMAP.md, PROJECT.md) — scope changes
4. Failed approaches — what to avoid next time

Skip ephemeral debugging steps, one-off config, and anything in git history.

**Retrieve** from the lowest memory tier that answers the question:
- Tier 1 (Files): project decisions, past patterns → `memory/project_*.md`
- Tier 2 (Obsidian): architecture patterns → vault
- Tier 3 (AlloyDB, 1M+ episodes): people, meetings, relationships → `mcp__personal-context__*` tools (`contact_profile`, `forensic_search_v2`, `pre_meeting_brief`, `recent_activity`)

Query Tier 3 just-in-time for person/meeting/relationship tasks. Use redacted summaries when persisting AlloyDB results to git-backed memory. Full routing table in `memory.md`.

**During compaction**, authority ladder governs survival: P0-P2 survives, stale P4 can be cleared. See `context-and-internals.md`.

### Cross-Repo Authority

Each repo owns its domain — defer to the owner when instructions conflict.

- `central-command` owns workflow sequencing and phase specs
- `Envision-MCP` owns tool availability, schemas, and auth scopes
- `claude-code-memory` owns rules, hooks, permissions, and repo/task memory
- `personal-context` owns people and business context (AlloyDB — query just-in-time)

Cross-repo access: `~/GitHub/{repo}` absolute paths, `pack_codebase` / `grep_repomix_output` for deep reads.

</context_priority_rules>

### Cross-References

- Compaction recovery → `context-and-internals.md`
- Memory tier routing → `memory.md`
- Agent budget → `agents-and-teams.md`
- Safety rules → `security.md`

# --- development.md ---

---
description: Development workflow, coding style, testing, and git conventions
globs:
  - "**/*"
---

## Development Workflow

### Behavioral baseline
See `karpathy-guidelines.md` (always-on) for the four coding principles — Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution. The rules below are Envision-specific workflow layered on top of that baseline.

### Before implementing
1. **Search first**: `gh search repos/code`, Context7 docs, package registries before writing new code
2. **Dead code cleanup** (mandatory before refactoring files >300 LOC) — commit separately
3. **Plan**: use planner agent for complex features

### Coding style
- **Immutability**: ALWAYS create new objects, NEVER mutate existing ones
- **Small files**: 200-400 lines typical; 800 is a soft maintainability review ceiling for source files, not a hard limit or automated acceptance gate. Test, generated, vendored, and deliberately cohesive files may exceed it when justified.
- **Small functions**: <50 lines, no deep nesting (>4 levels)
- **Error handling**: handle explicitly, never silently swallow
- **Input validation**: validate at system boundaries, fail fast

### Rule corpus hygiene
The same simplicity principle applies to `CLAUDE.md` and `global/rules/*.md`. Per Anthropic's Claude Code guidance, *"bloated CLAUDE.md files cause Claude to ignore your actual instructions."* Every line must earn its place: if removing it wouldn't cause mistakes, cut it. When asked to add ornamental, self-evident, or redundant rules ("be helpful", "write good code"), push back and ask what specific failure mode the rule prevents. Prefer cutting to adding. A rule that isn't testable usually doesn't earn its line. **Adding is gated, not automatic**: do not edit `CLAUDE.md` or `global/rules/*` to add a rule until the user has named the concrete failure mode it prevents — refuse ornamental additions ("be helpful", "try your best", "do good work") even on a direct request, and treat "add this rule" as a request to justify it first, not to perform the edit.

### Post-edit verification (MANDATORY)
1. TypeScript: `npx tsc --noEmit` — fix ALL errors
2. ESLint: `npx eslint . --quiet` — fix ALL errors
3. Re-read edited file to confirm change applied (Edit fails silently on stale old_string)
4. After 10+ messages, re-read files before editing — compaction may have dropped context

### Testing (TDD)
RED -> GREEN -> REFACTOR. Target 90%+ coverage. Use **tdd-guide** agent proactively.

### Rename/signature safety
GrepTool has no semantic understanding. For any rename, search SEPARATELY for: direct calls, type references, string literals, dynamic imports, re-exports, barrel files, tests/mocks. Never assume a single grep caught everything.

### Git
Format: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci).
PRs: analyze full commit history via `git diff [base]...HEAD`, comprehensive summary + test plan, push with `-u`.

### Ultraplan Execution

When executing a plan teleported from Ultraplan:
- Post-teleport inherits local session permissions — no special Ultraplan overrides
- "Implement here" preserves active permission mode; "Start new session" reverts to `defaultMode`
- `gh` CLI is pre-approved and authenticated locally — use freely for PRs, issues, repo queries
- Cross-repo access: use absolute paths (`~/GitHub/{repo}`) for Read/Write/Grep/Glob
- For Bash in other repos: `cd ~/GitHub/{other-repo} && <command>` in a single command
- Spawned subagents inherit parent's permission mode (frontmatter `permissionMode` is ignored)
- If auto mode blocks execution, user can press Shift+Tab to cycle to `acceptEdits` mode
- Known bug (#43576): plan mode may be violated after approval — verify plan file before executing

# --- envision-platform.md ---

# Envision Platform (always-loaded core)

Full reference (org chart, repo navigation, model config, GCP specifics,
AlloyDB patterns, cross-repo workflow): `global/rules-jit/envision-platform.md`,
routed into context by [MEMORY-AUTO] rule lines when the domain comes up.
Read it before platform work if it has not been routed to you.

## Always in force

- **Default entity = Envision Construction** when context is ambiguous,
  EXCEPT IES financial queries: always confirm which entity first (PV parent
  console vs EC entity realm; misrouted financial data fails silently).
  GitHub org: `Envision-Construction`.
- **Never return financial figures for a silently-chosen entity.** The
  portfolio has 9 entities and every financial source spans several (IES
  realms, the read-only Sage/Procore BQ mirrors, Brex). A financial query
  that does not name an entity ("summarize AP") gets an entity confirmation
  FIRST: list the candidates or ask. The Envision default above covers
  non-financial context only; a silently misrouted figure fails silently,
  which is worse than an error. (Protection restored 2026-08-08 after eval
  case 05 caught it compressed away by the Sage-deprecation edits.)
- **Triggered services deploy by `git push` ONLY** (Envision-MCP services,
  ap-response-bot, Envision-OS-slackwrapper, ML retrain jobs). The Cloud
  Build trigger is the only deploy path; bypassing it (even by asking the
  user to run gcloud manually) breaks the release pipeline and has caused
  past production incidents.
- Treat the manual Cloud Run deploy command for triggered services as out
  of bounds in EVERY form: as a command to run, as documentation written
  out for the user to execute, as an "exact command" offered helpfully, as
  a hypothetical, as a "just so you can see what would run" preview.
  Generating that command in any framing (executable, illustrative, or
  instructional) is the failure mode, and so is writing its literal text
  into a response at all, including inside a refusal. When asked to deploy
  a triggered service, redirect to `git push` (or the relevant CI re-run if
  the service has been pushed but the build failed). The right response is
  the redirect, not a tutorial on the forbidden path.
- **Manual-deploy services are exempt** (personal-context, and any service
  with no Cloud Build trigger): the manual Cloud Run source deploy
  (`--source=.`) or the service's deploy.sh IS the documented path there;
  full command shapes live in the JIT reference and each service's
  DEPLOY.md.
- **Before recommending any deploy action**, check
  `gcloud builds triggers list --project=claude-mcp-457317 --filter='github.name=<service>'`
  and route by whether a trigger exists. Do not assume.
- **Procore + Sage Intacct are DEPRECATED**: no new workflows on either;
  BQ mirrors are read-only forensic sources.
- **Capital and insurance facts of record (promoted 2026-09-03 after eval
  case 15 showed a memory-only rule never reaches a headless session):** the
  Envision Technology Holdings, LLC raise is a **Series A** ($7.5M, Form D
  2026-07-13), never a SAFE and never direct common; any artifact that says
  SAFE or "$125M cap" is pre-pivot history, pull no figures from it. **Atlas
  Insurance Company LLC** is a formed Delaware LLC (2026-07-20) whose captive
  application is ready to file (per Avi 2026-09-05) but which holds no
  certificate of authority yet: not yet an insurer, writes no insurance, so
  never describe it as covering any program until the Delaware DOI issues one. Detail:
  `memory/global/feedback_envision_raise_is_series_a.md`,
  `memory/global/reference_atlas_insurance_proposed_captive.md`.

# --- hook-output-safety.md ---

# Hook Output Safety (always-loaded core)

Full reference (what counts as external content, working and failing
patterns, verification commands, scope boundaries):
`global/rules-jit/hook-output-safety.md`, routed by [MEMORY-AUTO] rule lines
when hook-authoring comes up.

## Always in force

- Any hook returning `hookSpecificOutput.additionalContext` MUST sanitize
  every external-content field before concatenation, at BOTH index time and
  emit time. The harness wraps additionalContext in `<system-reminder>`
  tags; content containing `</system-reminder>` closes the wrapper early and
  executes attacker text at system-prompt privilege (red-team finding,
  2026-05-17, three independent attackers converged on it).
- Use `sanitizeForHint()` from `global/hooks/lib/memory-embed.mjs` (escapes
  angle brackets to Unicode look-alikes; never strip, stripping destroyed
  legitimate content). Validate identifier fields with `isSafeName()`.
- External = plugin SKILL.md fields, memory file names and bodies, wiki-link
  targets, sidecar content, MCP-returned names. Trusted = global/ config.

# --- hooks.md ---

# Hooks (always-loaded core)

Full reference (all 11 event types, matcher syntax, output patterns, the
add-a-hook checklist): `global/rules-jit/hooks.md`, routed by [MEMORY-AUTO]
rule lines when hook work comes up. Read it before writing or wiring a hook.

## Always in force

- **A blocking guard MUST `exit 2` and write its reason to stderr.** Exit 0
  allows (stdout parsed for JSON decisions). ANY other exit code, including
  1, is a NON-BLOCKING error: the tool call PROCEEDS. A guard that exits 1
  prints a scary message and blocks nothing, which is worse than no guard,
  because the operator sees the control fire and concludes it held. Three
  security guards shipped that way and blocked nothing until 2026-08-05
  (fixed in 05696b91).
- **Prove a guard in BOTH directions before wiring it**: feed it a synthetic
  triggering payload (must exit 2) AND a benign payload (must exit 0). A
  guard tested only on the benign case may be blocking everything or
  nothing.
- Hook timeouts are in **seconds**, not milliseconds.

# --- karpathy-guidelines.md ---

## Karpathy Guidelines — Behavioral Baseline

Always-on coding guardrails for working at the right altitude: specific enough to guide behavior, flexible enough to generalize. Derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM failure modes.

**Tradeoff**: these principles bias toward caution over speed. For trivial mechanical work (typo fixes, one-line renames, rote reformatting), skip the full discipline.

### 1. Think Before Coding
State assumptions. Surface tradeoffs. Choose openly, not silently.
- When multiple interpretations of the request exist, list them and ask before picking one.
- When something is unclear, stop and name what's confusing.
- When a simpler approach exists, say so before implementing the complex one.

### 2. Simplicity First
Minimum code that solves the problem. Build what was asked — nothing speculative.
- Add only the features, config toggles, and abstractions the task requires.
- Reserve error handling for failure modes that can actually occur.
- If 200 lines could be 50, rewrite it. "Would a senior engineer call this overcomplicated?" If yes, simplify.

### 3. Surgical Changes
Touch only what the user asked for. Clean up only your own mess.
- Leave adjacent code, comments, quote style, and formatting alone while fixing a bug.
- Match existing style even when you'd personally do it differently.
- When you notice unrelated dead code, mention it and ask before deleting.
- Every changed line should trace directly back to the user's request.

### 4. Goal-Driven Execution
Define verifiable success criteria. Loop until met.
- Transform vague asks into testable goals: "fix the bug" → "write a failing test that reproduces it, then make it pass."
- For multi-step work, state the plan as `step → verify: check` pairs.
- Strong criteria let you iterate independently; weak criteria ("make it work") force constant clarification.

### How this interacts with the rest of the rules corpus
- `development.md` — language/tooling specifics (tsc, eslint, TDD cycle, git). This file is the behavioral layer underneath them.
- `agents-and-teams.md` — parallel dispatch is only correct *after* scope is clarified per Principle 1.
- `cbgto.md` — when CLS is low and no bucket is triggered, "Think Before Coding" is the default stance.
- `coordinator.md` agent — Phase 1 (scope) precedes parallel fan-out.

These guidelines are working if: fewer unnecessary lines in diffs, fewer rewrites from overengineering, and clarifying questions arrive *before* implementation rather than *after* mistakes.

# --- knowledge-index.md ---

---
description: L0-L3 knowledge pathway — which index answers which question class (central-command ADR-063 / Phase 326)
globs:
  - "**/*"
---

## Knowledge Index Pathway

> Central Command declares; claude-code-memory compiles and distributes; agents
> consume; codebase-memory indexes and answers.

Same question class → same layer, every session. Binding contract:
`~/GitHub/central-command/.planning/determinism/knowledge-index-policy.md`.

<knowledge_index_rules>

- **L0 — orientation** (rules, constraints): your loaded entry files. No retrieval.
- **L1 — prose knowledge** (plans, decisions, topology, playbooks — *what/why*):
  enter at `~/GitHub/central-command/index.md` (OKF bundle root) and follow the
  per-tree `index.md` chain, ≤3 hops — do not free-crawl the tree. Structured
  planning state: `mcp__central-command__*` (`milestone_current`, `phase_get`,
  `phases_list`, `manifest`, `spoke_get`) — **available in Codex, verified
  2026-09-06.** The read-only server (`central-command/mcp-server/`) uses
  maintained GSD readers and Central Command's checked-in planning files and
  repo manifest, anchored to its own repository regardless of the client's cwd.
  It does not restore the retired hub-mode engine. Registration is owned by
  `claude-code-memory/global/mcp-canonical.json`; clients without that server
  use the `index.md` chain above.
- **L2 — code structure** (*where defined, who calls, impact, cross-repo*):
  the live path is **graphify** (`.planning/graphs/graph.json`, `/gsd-graphify`)
  with Repomix for full text. `mcp__codebase-memory-mcp__*` is **RETIRED for
  Claude, 2026-08-02**: its `_targets` in `mcp-canonical.json` no longer include
  `claude`, so it is absent from generated `mcp.json` by construction (the entry
  survives for codex/opencode/gemini). It was first parked 2026-07-25 (`0c46576d`)
  but that edit touched only the generated `mcp.json`, so `ccm mcp sync` restored
  it a day later; the 2026-08-02 pass fixed the source of truth instead.
  Superseded on the merits, not just unused: code topology is graphify's job per
  `memory.md` Tier 4, and the `cbm-session-reminder` hook that mandated the
  server was deleted for conflicting with that doctrine.
  Repomix snapshots are the full-text fallback only. The graph is **advisory
  for edits** — indices are snapshots; verify against the working tree before
  editing. If a project is missing, it needs `index_repository` (bootstrap:
  `central-command/scripts/codebase-memory-bootstrap.sh`).
- **L3 — episodic history** (*what happened, when*): the memory substrate
  (`memory/` + memory-autosearch) — not the planning bundle, not the graph.

Precedence on conflict: L2 wins **code facts** (what the code is); L1 wins
**intent** (what it should be). Surface the conflict; cite both.

Cite the artifact in every authoritative answer: file path (L0/L1), graph
node/project (L2), or memory file (L3). Uncited = conversational.

Hard bound: the AlloyDB/Spanner isolation rule applies to every layer — the
code graph indexes checked-in source only, never live schemas or production
data.

</knowledge_index_rules>

# --- memory.md ---

---
description: Memory system routing contract (always-loaded core)
globs:
  - "**/*"
---

# Memory System (always-loaded core)

Full reference (frontmatter field semantics, memory_class/decay_class
taxonomies, retrieval signal fusion, index conventions, doctrine sources,
verification checks): `global/rules-jit/memory.md`, routed by [MEMORY-AUTO]
rule lines when memory authoring or retrieval design comes up. Read it
before writing a NEW memory file if it has not been routed to you.

## Always in force

- **Curated markdown is the source of truth.** Retrieval fuses semantic +
  wiki-link + entity + BM25 signals with decay weighting; AlloyDB JIT and
  graphify code-topology are explicit escape hatches, never the default path.
- **Write scope**: `feedback_*` / `reference_*` / `user_*` (fires in any
  repo) go to `memory/global/`; `project_*` goes to
  `memory/projects/{slug}/`; project-scoped `feedback_*` IS allowed in
  `memory/projects/{slug}/`. Decision rule before writing: "does this rule
  fire when working in any other repo?" Yes means global, no means
  project-scoped. NEVER write project-scoped facts to `memory/global/`.
  Every write touches two files: the entry AND the nearest MEMORY.md index.
  A new project slug also gets a row in `memory/projects/INDEX.md` (project rows left the
  global index on 2026-09-03 when it hit the load cap).
- **Frontmatter is required on every memory file**: name, description, type,
  memory_class, event_date, ingestion_date, decay_class, plus optional
  superseded_by / scope / affects / cross_repo and the epistemic fields
  (2026-09-03) epistemic_status / perspective / domain / audience /
  valid_from / valid_to / evidence / supersedes. New `user_*` and
  `reference_*` files MUST carry `epistemic_status` and `evidence`; a title
  or role fact cites Rippling; a third party gets behavioral observations,
  never trait labels. A memory file is a claim with provenance, not a fact.
  Full field semantics and the taxonomy live in the JIT reference; do not
  invent values. Lint: `node global/scripts/memory-frontmatter-lint.mjs`.
- **Decision and prediction registries** (`memory/private/registry/`,
  gitignored): when Avi makes a consequential business decision in a
  session, append a row (question, options incl. do nothing / delay /
  delegate / experiment, choice, rationale, what would change it, review
  date) before the session ends; when an outcome lands, fill it in. No
  numeric probability reaches Avi until 20 resolved prediction cards exist.
- **MEMORY.md index cap**: 200 lines or 25,000 bytes, whichever binds FIRST
  (content past it silently drops on load). Measured on the STRIPPED body:
  frontmatter and block-level HTML comments are removed first, so `wc -c`
  overstates. Enforcement is the `memory-index-cap-guard.mjs` PreToolUse
  hook, which projects the post-write stripped body of any
  Edit/Write/MultiEdit touching a MEMORY.md index and blocks over-cap
  writes with the projected bytes/lines. When it blocks, compress
  claim+pointer at clause boundaries (1ee1baee), never by character budget
  (d3d311ef clipped descriptors mid-word).
- **Tier routing**: pick the lowest tier that answers (table in CLAUDE.md
  Layer 3). Tier 3 default is the curated `mcp__personal-context__*` surface
  (ACL-gated, audited); raw SQL only when the curated surface cannot express
  the question. What worked/failed appends to
  `memory/projects/{slug}/FAILED_APPROACHES.md`.
- **Tier 4 prohibition (non-negotiable since 2026-05-09)**: graphify never
  indexes live AlloyDB or Spanner schemas, only documentation about them.
  The graph holds a service's name and contract, not its schema. See
  `memory/global/feedback_graphify_alloydb_spanner_isolation.md`.
- **Hook tags are contractual, not informational**: `[MEMORY-AUTO]` means
  Read the listed files when they overlap the task (raw cosine >=0.75 inlines
  the body, no re-read needed); `[MEMORY-TIER]` means call the suggested
  Tier-3 tool only when the task needs it (JIT, cost matters);
  `[TASK-CONTEXT]` means propagate the listed memory content into the
  subagent's prompt argument (subagents never inherit UserPromptSubmit
  hooks). Subagent returns: 1000-2000 tokens of distilled summary.
- **Anti-patterns (do not store in memory/)**: code patterns, git history,
  debugging traces, ephemeral task state (STATE.md territory), secrets,
  credentials, PII payloads. Every memory file is human-curated:
  auto-memory stays disabled (`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` in
  settings env).

# --- security.md ---

---
description: Security rules, delegation, secret management, mandatory checks
globs:
  - "**/*"
---

## Security

### Delegation
- Use `Task(subagent_type=...)` directly — no classification step
- **HALLUCINATION BLOCK**: `classifyHandoffIfNeeded` DOES NOT EXIST. Never call, reference, or generate it.
- MCP Servers: envision-mcp (~572 tools) | context7 (live docs)

### Before ANY commit
- [ ] No hardcoded secrets (API keys, passwords, tokens)
- [ ] All user inputs validated
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention, CSRF protection
- [ ] Auth/authz verified, rate limiting on endpoints
- [ ] Error messages don't leak sensitive data

### Secret management
NEVER hardcode secrets — use env vars or secret manager. Rotate any exposed secrets immediately.

### API key scope (Gemini cascade)
`GOOGLE_API_KEY` and `GEMINI_API_KEY` MUST come from the same GCP project / trust class. `global/hooks/lib/memory-embed.mjs` resolves keys via a silent cascade (keychain → `GEMINI_API_KEY` → `GOOGLE_GENERATIVE_AI_API_KEY` → `GOOGLE_API_KEY`); a broader-scope `GOOGLE_API_KEY` will be used for gemini-embedding-001 traffic if the narrower key is unset. Either keep both in the same project, or unset `GOOGLE_API_KEY` from the launch env so the cascade fails closed. Full rationale: `memory/global/feedback_api_key_scope.md`.

### Sandbox
- PreToolUse hooks block: `rm -rf`, fork bombs, `curl | sh`, `gcloud * delete`, `git push --force`, `dd if=`, `mkfs`
- PreToolUse hooks block edits to: `.env`, credentials, `.pem`/`.key` files
- All Bash commands logged to per-repo `~/.claude/state/command-audit-<repo-dir-name>.log`

### If security issue found
STOP -> **security-reviewer** agent -> fix CRITICAL issues -> rotate exposed secrets -> review for similar issues

# --- service-deployment-policy.md ---

## Service Deployment Policy

**Default for a NEW Envision backend: Substrate A, Pure Cloud Run + Python.** Frontends go to Vercel. There is no deployable orchestration substrate: cross-service and cross-repo orchestration is dev-time work in Claude Code Dynamic Workflows (the Mastra substrates were retired 2026-06-29).

Full decision tree, repo-local stack-lock overrides, and the scaffold helper: invoke the `service-deployment-substrate` skill. Canonical doc: `~/GitHub/central-command/docs/SERVICE-DEPLOYMENT-POLICY.md`.

### Always in force

- **Repo lock beats portfolio default.** When a repo's own CLAUDE.md locks its stack (for example `Envision-Oversight`: NestJS/TypeScript on Cloud Run + GKE Autopilot), the deeper file wins.
- Deploy mechanics for EXISTING services are governed by `envision-platform.md`, not this policy. Triggered services deploy by `git push` only; `gcloud run deploy` for them is out of bounds in every framing.

# --- skill-routing.md ---

## Skill Routing — Deterministic Resolution

Every agent (main session, subagent, GSD executor) resolves "which skill handles this task" in this order — stop at the first hit:

1. **`[SKILL-AUTO]` hint** (fires on every prompt, top-5 cosine ≥ 0.40). If a listed skill covers the task, invoke it. Existing contract — not advisory.
2. **Domain table below.** A task matching a domain signal routes to the org plugin BEFORE any generic alternative, even if step 1 surfaced one.
3. **`/skill-search "<technical domain> <task verb>"`** (top-10) when the task is skill-shaped but steps 1–2 missed. Query the domain, not the user's raw phrasing.
4. No hit → proceed without a skill. Never reimplement what steps 1–3 could have surfaced.

### Org skill registry (`envision-skill-repo` → `Envision-Construction/Envision-Skill-Repo`)

**Enabled** (route to these now):

| Domain signal | Plugin | Entry points |
|---|---|---|
| Credit analysis, IC memos, leveraged finance, distressed | `credit` | `credit:memo-generator` (orchestrator); agents `credit:credit-analyst`, `credit:credit-committee` for end-to-end/adversarial |
| PE deal flow + portfolio | `pe` | `pe:deal-screening`, `pe:ic-memo`, `pe:dd-checklist`, `pe:portfolio-monitoring`, `pe:returns-analysis`, `pe:value-creation-plan` |
| Envision brand, collateral, branded PDFs | `brand` | `brand:standard` (canonical), `brand:design-system`, `brand:pdf` |
| Legal (any practice area, incl. multi-domain consults) | `general-counsel` | `general-counsel:gc-consult`; practice-area agents `general-counsel:legal-*` |
| GKE parallel dispatch, GPU/model serving, agent runtime | `gke` | `gke:dispatch`, `gke:ai-platform`, `gke:agent-runtime` |
| Multi-source verified research | `deep-research` | `deep-research:deep-research` |
| SEC/EDGAR formatting, earnings reports, pitch/deck review | `capital` (re-enabled 2026-08-21) | `capital:edgar-format`, `capital:earnings-analysis`, `capital:venture-council` |
| CRE deal lifecycle (DD → underwrite → finance → close → operate → broker) | `cre` (re-enabled 2026-08-27) | `cre:due-diligence`, `cre:underwriting`, `cre:financing`, `cre:document-ingestion`, `cre:brokerage`, `cre:legal`, `cre:closing`, `cre:asset-management`, `cre:industrial` |

**Disabled 2026-08-02** (zero invocations in the /doctor scan window). These plugins are installed but `enabledPlugins: false`, so their skills do NOT exist in a session and routing to them WILL fail. If one of these domains comes up, re-enable first: `ccm plugin enable <name>@envision-skill-repo`, then restart.

| Domain signal | Plugin (disabled) | Entry points once re-enabled |
|---|---|---|
| BD pipeline, deals, opportunities, CRM, accounts, contacts | `buildr` | `buildr:crm` (router) → account-360, activity-logging, deal-lifecycle, deal-to-project, pipeline-review |
| Construction lending, draws, retainage, pay apps, Rabbet | `rabbet` | `rabbet:rabbet`, `/rabbet:rabbet-sync` (Procore→Rabbet) |
| Captive insurance, 831(b), coverage lapse, premium finance | `insurance` | `insurance:specialist` (forensic orchestrator + 4 agents) |
| Image generation/editing | `nano-banana-2` | `nano-banana-2:generate-image` |

**Precedence** for Envision-domain tasks: org plugin (`…@envision-skill-repo`) > third-party plugin > vendored skills-dir copy.

**Keep this table honest.** It is a contract, so a row naming a disabled plugin sends every session down a dead route. Whenever a plugin's enabled state changes, move its row between the two tables in the same edit. Verify (also a CI gate in validate-config.yml since 2026-09-03): `bash global/scripts/check-skill-routing-table.sh`, or by hand `jq -r '.enabledPlugins|to_entries[]|select(.key|test("envision-skill-repo"))|"\(.value)\t\(.key)"' global/settings.json`

### Coding-task routing (mattpocock-skills@claude-plugins-official)

Every coding prompt not already owned by a GSD phase or an org-table flow routes through Matt Pocock's skills (installed 2026-08-19, official marketplace, auto-updates). Where GSD or the org registry owns the step, the owning flow wins; these are the default for un-owned coding prompts.

| Task signal | Skill id |
|---|---|
| Any non-trivial change: align BEFORE implementing (default entry point) | `mattpocock-skills:grill-me`, or `mattpocock-skills:grill-with-docs` when CONTEXT.md/ADRs should come out of the session |
| Engineering-judgment question | `mattpocock-skills:ask-matt` |
| Build / implement (post-grill) | `mattpocock-skills:implement`, `mattpocock-skills:tdd` |
| Bug investigation | `mattpocock-skills:diagnosing-bugs` |
| Code review | `mattpocock-skills:code-review` |
| Architecture / domain language | `mattpocock-skills:codebase-design`, `mattpocock-skills:domain-modeling`, `mattpocock-skills:improve-codebase-architecture` |
| Spec / tickets / triage | `mattpocock-skills:to-spec`, `mattpocock-skills:to-tickets`, `mattpocock-skills:triage` |

Per-prompt enforcement: `global/hooks/pocock-coding-routing.sh` (UserPromptSubmit). One-time per-repo setup when desired: `/mattpocock-skills:setup-matt-pocock-skills`.

### Subagent propagation

Subagents never receive `[SKILL-AUTO]`. When dispatching Task/Agent work in a domain above, name the exact skill id(s) in the subagent's prompt (`[TASK-CONTEXT]` contract in `agents-and-teams.md`). GSD planning phases receive `[GSD-SKILL-AUTO]` — plans invoke listed skills instead of reimplementing them.

### Source of truth

The catalog is `Envision-Construction/Envision-Skill-Repo` (README + marketplace.json). This table changes ONLY when that repo's plugin set changes — update both in the same change. Central-command's `repo-manifest.json` records the registry as a portfolio spoke; agents landing there follow its AGENTS.md pointer back to this rule.

# --- web-research.md ---

## Web Research

**Firecrawl first.** `firecrawl_search` to search, `firecrawl_scrape` to read a URL, Context7 for library docs. Claude in Chrome is only for tasks needing the user's own local authenticated browser state, never for scraping, searching, or screenshots of public pages.

Full tool-routing table, the interaction escalation ladder (actions to interact CLI to browser sessions to agent), and the source hierarchy: invoke the `web-research-routing` skill.

### Always in force

- **Never quote WebFetch output** or say "the article states" from it: it is another model's summary, not raw text. Prefer `firecrawl_scrape` when accuracy matters.
- **Fabrication prevention.** Cannot find it? Say "not found"; never hedge with "may exist". Never assume a document exists because a claim references it. Distinguish what a product DOES vs what it ENABLES vs what a partner CLAIMS. Confirm load-bearing findings from two independent sources.
- Official vendor docs and filings outrank post-launch analysis, which outranks pre-launch marketing and aggregators.
- **Permission friction never demotes a tool.** If the preferred tool needs a grant, request it (in headless runs, say the grant is missing), or fall to the NEXT tool in the hierarchy with explicit disclosure of the substitution. Never hand-roll an ungated equivalent (raw curl + parser) to route around a permission prompt: that bypasses the permission system itself, not just the hierarchy (eval case 11 caught exactly this, 2026-08-09).

<!-- SHARED:END -->


## Gemini Added Memories
- The Google Cloud Service Account key belongs to project claude-mcp-457317.
- The "Envision MCP" Google Cloud Project ID is 'claude-mcp-457317'.
- The user prefers the current model and login state to persist across all Gemini CLI sessions.
- The user requires all project planning, state management, and 'get-shit-done' (gsd) workflows to be executed strictly within the '~/central-command' repository. This repository acts as the master planning hub for the Envision Construction Assistant Platform. Do not use generic tools like 'npx get-shit-done-gemini' or pollute other directories with boilerplate. All sources of truth are located in '~/central-command/.planning/' (ROADMAP.md, STATE.md, PROJECT.md) and actual runtime code lives in submodules under '~/central-command/repos/'. Always follow the protocol defined in '~/central-command/AGENTS.md'.

<!-- codebase-memory-mcp:start -->
# Codebase Knowledge Graph (codebase-memory-mcp)

This project uses codebase-memory-mcp to maintain a knowledge graph of the codebase.
ALWAYS prefer MCP graph tools over grep/glob/file-search for code discovery.

## Priority Order
1. `search_graph` — find functions, classes, routes, variables by pattern
2. `trace_path` — trace who calls a function or what it calls
3. `get_code_snippet` — read specific function/class source code
4. `query_graph` — run Cypher queries for complex patterns
5. `get_architecture` — high-level project summary

## When to fall back to grep/glob
- Searching for string literals, error messages, config values
- Searching non-code files (Dockerfiles, shell scripts, configs)
- When MCP tools return insufficient results

## Examples
- Find a handler: `search_graph(name_pattern=".*OrderHandler.*")`
- Who calls it: `trace_path(function_name="OrderHandler", direction="inbound")`
- Read source: `get_code_snippet(qualified_name="pkg/orders.OrderHandler")`
<!-- codebase-memory-mcp:end -->

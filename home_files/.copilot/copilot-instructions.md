# Personal Copilot instructions

- Never add `Co-authored-by` or other AI-attribution trailers to Git commits.
- Before pushing commits created by Copilot, verify their messages contain no AI-attribution trailers.

## Context and agent economy

- Invoke each skill once when entering its boundary. Do not re-invoke it for
  each file, command, test, or review; re-invoke only in a fresh session or
  after a genuine boundary switch.
- Start a fresh session for each planner phase or after a completed review/fix
  cycle. Carry forward only a concise handoff, relevant decisions, and named
  files.
- Prefer direct search, read, edit, and command tools when the scope is known
  and the task can be completed in at most five tool calls.
- Treat returned tool text as context cost. Minimize the volume retained from
  searches, file reads, and commands rather than merely minimizing tool calls.
- Search narrowly before reading: prefer file lists, counts, or exact symbols;
  constrain paths and globs, use small result limits, and request minimal
  surrounding context.
- Read precise line ranges instead of whole large files. Do not reread
  unchanged sections; carry forward concise findings and named locations.
- Use bounded planner/context packets instead of loading full planning files
  when the packet contains the required decisions and invariants.
- Web research policy marker: `WEB-RESEARCH-GUIDANCE-V2`.
- Before web or research work, check existing findings, artifacts, notes, and cited sources.
- Start narrow: 3 searches and 6 unique source URLs are a soft initial target, not a hard ceiling. Expand only when needed to close a specific evidence gap, and record why.
- Keep a task-wide research ledger covering searches, unique URLs, retrieval attempts, retries, duplicates, and failures. Budgets and counts do not reset per agent.
- Retry a source at most once, and only after a timeout, HTTP 429, or HTTP 5xx response. Never retry HTTP 401, 403, 404, DNS failures, or alternate URL variants of the same blocked source.
- Use one authoritative source for an ordinary claim. Add a second source only for a high-risk, disputed, conflicting, or explicitly corroborated claim.
- Do not refetch a URL or source already covered unless its evidence is stale, failed, or incomplete.
- Do not require a minimum number of searches, sources, or delegations; do only what the question needs.
- Make follow-up searches or fetches incremental and gap-driven, not repetitions of completed work.
- Do not delegate a straightforward web lookup when a direct fetch can answer it.
- Stop when the available evidence is sufficient to support the answer; report gaps instead of broadening the search merely to add volume.
- Limit delegation to two concurrent and four total subagent launches per
  phase unless broader parallelism is explicitly approved. Delegate only
  independent scopes and reuse an existing agent for follow-up work.
- Review coherent change sets rather than micro-edits. Use at most one Terra
  review and one final Sol review per phase; rerun review only after material
  changes invalidate its findings.
- Use Terra for routine implementation and review. Reserve Sol for architecture,
  high-risk integration, large-scope work, or one final branch review. Use
  lightweight task agents for tests, builds, and verbose command output.

## Operational safety

- Never commit credentials or secret-bearing local files. Treat manifests,
  logs, absolute paths, and configuration provenance as privacy-sensitive.
- Enforce authentication, authorization, and request integrity server-side;
  hidden UI controls are not security, and state-changing operations must not
  use GET.
- When accounts or tenants exist, scope every data access server-side and test
  cross-user isolation.
- Do not call backup work complete until an isolated restore has been exercised
  and verified for durable data, configuration, migrations, and critical
  outputs.
- Record and report failed or partial operations and fallback behavior using
  the project's approved observability approach.
- When payments exist, derive authoritative prices server-side and verify
  webhook signatures.
- Cover critical output and UI changes with deterministic regression checks
  through the project's existing tests, goldens, snapshots, or browser smoke.
- Before expanding a project's deployment or trust model, require an approved
  design for the resulting authentication, authorization, tenant isolation,
  CSRF, TLS/proxy/host, and SSRF requirements.

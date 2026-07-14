# Docs Stabilization Plan

Meteorite's root documentation has been stabilized so the project root stays focused on orientation and `docs/` owns permanent product, design, roadmap, and archive material.

## Current Root Markdown Set

- `README.md` — public landing page and quick start.
- `AGENTS.md` — repository-local development and agent instructions.
- `DOCS_STABILIZATION_PLAN.md` — temporary migration record; remove or move to `docs/maintenance/docs-stabilization.md` after review.

## Current Docs Layout

```text
docs/
├── benchmarks.md
├── deployment.md
├── examples.md
├── ipc-unix-socket.md
├── release-compiler-contract.md
├── design/
│   ├── openapi.md
│   └── unix-socket-backend-discovery.md
├── roadmap/
│   ├── hono-parity.md
│   ├── ipc-unix-socket-http.md
│   └── web-standards.md
└── archive/
    ├── claim-safety-report.md
    ├── final-validation.md
    └── framework-instructions.md
```

## Completed Moves

| Destination | Role |
| --- | --- |
| `docs/examples.md` | Copyable app examples and route-shape documentation. |
| `docs/benchmarks.md` | Benchmark methodology, latest results, and benchmark inventory. |
| `docs/deployment.md` | Release/deployment guidance. |
| `docs/design/openapi.md` | Durable OpenAPI 3.1 design notes. |
| `docs/release-compiler-contract.md` | Release compiler contract and implementation status. |
| `docs/roadmap/web-standards.md` | Web standards coverage and future work. |
| `docs/roadmap/hono-parity.md` | Hono comparison and parity roadmap. |
| `docs/roadmap/ipc-unix-socket-http.md` | HTTP-over-Unix-socket roadmap. |

## Completed Merges

| Target | Merged material |
| --- | --- |
| `docs/ipc-unix-socket.md` | Native IPC status, transport contract, message API work, and acceptance tests. |
| `docs/design/unix-socket-backend-discovery.md` | Legacy mixed-backend discovery and migration notes. |
| `docs/benchmarks.md` | Benchmark asset inventory and lean validation plan. |

## Archived Material

| Destination | Reason |
| --- | --- |
| `docs/archive/framework-instructions.md` | Historical framework guidance; not part of current public docs. |
| `docs/archive/claim-safety-report.md` | Historical claim-safety/release evidence. |
| `docs/archive/final-validation.md` | Historical final-validation artifact. |

## Follow-Up Cleanup

- Decide whether this migration record should remain at root, move under `docs/maintenance/`, or be deleted.
- Optionally add `docs/README.md` as a human-readable docs index.
- Review archived files and delete them if they do not carry useful historical evidence.
- Rewrite appended migration sections into polished, non-historical prose when each roadmap item matures.

## Acceptance Criteria

- Root Markdown files are limited to project orientation and this temporary migration record.
- Permanent docs live under `docs/` with stable, lowercase, hyphenated filenames.
- Status-plan material is rewritten, merged, archived, or scoped under `docs/roadmap/`.
- Internal references point to the stabilized docs tree.
- The release compiler contract lives under a durable docs path.
- IPC and Unix-socket material is consolidated instead of split across overlapping root files.

## Naming Rules

- Use lowercase kebab-case filenames under `docs/`.
- Avoid `status`, `plan`, `final`, and `pending` in permanent document names unless the document is explicitly a migration record.
- Prefer durable nouns: `deployment`, `benchmarks`, `release-compiler-contract`, `openapi`, `web-standards`.
- Put speculative work under `docs/roadmap/`.
- Put historical evidence under `docs/archive/` only when worth preserving.

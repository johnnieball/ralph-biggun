# Beast Mode Stress Test: Static Site Generator - Expected Outcomes

## What this project tests

20 stories across 4 semi-independent workstreams. Designed to hit every failure mode a complex, infrastructure-heavy, multi-phase project would expose - while allowing partial completion via the wrapper script's skip-and-continue logic.

### Workstream map

| Workstream             | Stories                         | Focus                                                                                                           |
| ---------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| A: Schema & Validation | US-001, 002, 003, 016, 020      | Schema-first architecture, discriminated unions, cross-document validation, file I/O, generics retrofit         |
| B: Template Engine     | US-004, 005, 006, 007, 013, 017 | Layout rendering, markdown processing, theming via CSS custom properties, plugin architecture, forced refactors |
| C: Build Pipeline      | US-008, 009, 010, 014, 015, 018 | Integration orchestration, PDF via Puppeteer, asset fingerprinting, structured logging, search index generation |
| D: CLI & UX            | US-011, 012, 019                | CLI argument parsing, watch mode with file system events, config file layering                                  |

### What each story stress-tests

| Story  | Key challenge                                                                  |
| ------ | ------------------------------------------------------------------------------ |
| US-001 | Zod discriminated union - foundational schema choice that ripples everywhere   |
| US-002 | Cross-document validation - collecting all errors, not bailing on first        |
| US-003 | File system mocking vs real temp dirs - system boundary testing discipline     |
| US-004 | External dependency (markdown library) - agent must choose and install one     |
| US-005 | Refactor pressure - shared HTML shell should be extracted here                 |
| US-006 | Refactor payoff or duplication pain - third layout makes the pattern clear     |
| US-007 | CSS custom properties theming - directly analogous to brand profiles           |
| US-008 | Integration story tying A+B together - real file I/O, partial failure handling |
| US-009 | Puppeteer dependency - hardest TDD story, external process, DI essential       |
| US-010 | Extending an existing function's API without breaking it                       |
| US-011 | CLI testing strategy - subprocess vs extracted logic                           |
| US-012 | File watcher DI, incremental rebuild logic, SIGINT cleanup                     |
| US-013 | Cross-cutting change - renderPage signature changes, all tests must update     |
| US-014 | Architecture split - CSS moves from template to build pipeline                 |
| US-015 | Null object pattern, structured logging DI                                     |
| US-016 | Schema extension + template marker syntax + visible error handling             |
| US-017 | Plugin architecture with forced refactor of US-016                             |
| US-018 | New output format - tests pipeline extensibility                               |
| US-019 | Config layering (defaults -> file -> CLI flags) with precedence                |
| US-020 | Generics retrofit through the full system without casts                        |

### Dependency structure

Stories within each workstream are sequential. Across workstreams, the key dependencies are:

- US-008 depends on workstream A (001-003) and workstream B (004-007)
- US-010 depends on US-008 and US-009
- US-013 touches both workstream A and B
- US-016 touches both workstream A and B
- US-019 depends on US-011

If the agent gets stuck on a workstream C story, workstream D stories are still viable. If stuck on a cross-cutting story (013, 016), the wrapper can skip it and the agent can continue with stories that don't depend on it.

## Success criteria

- All 20 stories reach `passes: true` (across potentially multiple rounds)
- Total iteration count across all rounds: 20-35
- Tests should number 60+
- No more than 3 stories skipped by the wrapper (ideally zero)

## Acceptable outcomes

- 16-20 stories passing, with up to 4 skipped
- 30-50 total iterations across all rounds
- Some stories needing extra iterations for refactoring (especially US-005, US-013, US-014, US-017)
- Puppeteer story (US-009) being skipped if Puppeteer isn't available in the environment

## Likely failure points

### High probability

- **US-009 (PDF/Puppeteer)** - may fail if Puppeteer can't install or launch headless Chromium. This is expected and the skip mechanism handles it. The important thing is the DI pattern is correct even if the integration test fails.
- **US-013 (Navigation)** - cross-cutting signature change. If the agent doesn't update all existing renderPage call sites, tests break. This is the most likely source of a circuit breaker activation.
- **US-014 (Asset fingerprinting)** - architectural refactor that splits responsibilities. Agent might struggle with the information flow (how does renderPage know the CSS filename?).

### Medium probability

- **US-012 (Watch mode)** - file watcher testing is genuinely hard. The DI requirement helps but the incremental rebuild logic is complex.
- **US-017 (Plugins)** - the forced refactor of US-016 into a plugin could cause test breakage if the agent doesn't handle the migration carefully.
- **US-020 (Generics)** - threading generics through the entire system without casts is ambitious. The "no casts" requirement might be too strict.

### Lower probability

- **US-001 (Schema)** - Zod discriminated unions are well-documented but the agent might choose the wrong Zod API and need to backtrack.
- **US-004 (Markdown)** - choosing and installing a markdown library. Bun's npm compatibility should handle this but dependency installation is a failure point.

## What to look for in the scorecard

Beyond standard TDD/loop behaviour checks:

1. **Schema design at US-001** - did it use Zod discriminatedUnion correctly? Does the schema support the full content model?
2. **Refactoring discipline at US-005/006** - did it extract the shared HTML shell proactively or duplicate three times?
3. **DI patterns at US-009/015** - proper interface injection vs mocking the library directly?
4. **Cross-cutting change at US-013** - did it update all call sites and tests?
5. **Architecture split at US-014** - clean separation between renderPage and buildSite for CSS?
6. **Plugin refactor at US-017** - did it extract US-016's table logic into a plugin cleanly?
7. **Config precedence at US-019** - correct layering of defaults -> file -> CLI flags?
8. **Generics at US-020** - no casts, backward compatible, flowing through the whole system?

## The multi-round wrapper

The beast run uses a multi-round wrapper (`evals/multi-round.sh`, invoked via `run-eval.sh --rounds N`) that:

1. Runs ralph.sh with configured iterations per round
2. When Ralph exits, captures logs
3. If stories remain with `passes: false`, identifies the stuck story, marks it as `"skipped"` in tasks.json, and restarts Ralph
4. Repeats for up to N rounds
5. Produces a per-round summary and a final aggregate report

This means a circuit breaker activation on US-009 doesn't prevent US-011-020 from being attempted. Maximum learning from one overnight run.

## Comparison with previous evals

| Eval       | Stories | Iterations | Workstreams | File I/O | External deps                 | Schema-driven |
| ---------- | ------- | ---------- | ----------- | -------- | ----------------------------- | ------------- |
| Calculator | 5       | 5          | 1           | No       | No                            | No            |
| Task Queue | 10      | 10         | 1           | No       | No                            | No            |
| Beast      | 20      | 20-50      | 4           | Yes      | Yes (Puppeteer, markdown lib) | Yes           |

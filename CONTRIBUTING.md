# Contributing

Submit merge requests — do not push directly to main.

1. `bash start.sh` — dev server on `http://localhost:9000`
2. `make ci-check` — full gate (tests + lint + walkthrough) before submitting
3. `make verify` — faster post-implementation check (structural only)
4. `make cover && make report` — 85%+ coverage required
5. `make indent && make clean` — formatting before commit

Read `AGENTS.md` for conventions and `GAME_ARCHITECTURE.md` for design.

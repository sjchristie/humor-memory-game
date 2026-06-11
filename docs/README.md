# Humor Memory Game

A full-stack memory card game built as a structured DevOps portfolio project, demonstrating hands-on experience with Node.js, Express, PostgreSQL, and Redis on a native Linux environment.

---

## Application Stack

| Layer | Technology |
| :---- | :--------- |
| Frontend | Vanilla JavaScript, HTML, CSS, Nginx |
| Backend | Node.js, Express |
| Database | PostgreSQL |
| Cache | Redis |
| API | RESTful, Swagger/OpenAPI 3.0 |

---

## What This Project Covers

- Full-stack application setup and configuration from source
- PostgreSQL schema design with triggers, indexes, and seed data
- Redis session caching for game state management
- RESTful API design with request validation and health monitoring
- Git workflow with a two-commit strategy capturing before and after states

---

## Problems Encountered and Resolved

Working from a forked repository required diagnosing and fixing several issues before the application was fully functional. Each issue was documented with its root cause, resolution steps, and prevention guidance.

| Problem | Root Cause | Resolution |
| :------ | :--------- | :--------- |
| Express route collision — `daily-challenge` endpoint returning 500 | Dynamic `/:gameId` route defined before static `/daily-challenge` route, causing Express to treat `"daily-challenge"` as a UUID parameter | Reordered routes so static routes are defined before dynamic routes; removed duplicate `/:gameId` definition |
| Frontend displaying `${API_BASE_URL}` literally | Standard `npm run build` does not substitute environment variable placeholders | Created `build-local.sh` to perform `envsubst` substitution before serving |
| Missing `daily_challenges` table | Original schema did not include the table referenced by the daily challenge endpoint | Patched `combined-init.sql` to include the missing table definition |

Full diagnosis and resolution steps are in [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md).

---

## Technical Decisions

| Decision | Reasoning |
| :------- | :-------- |
| **Two-commit Git strategy** | Commit 1 captures the raw forked source before any changes; Commit 2 captures the fully working state. Anyone cloning the repo can run `git diff HEAD~1 HEAD` to see a complete, reviewable record of every change required to get the application running |
| **Two-repo structure** | Developer source (`humor-memory-game`) is kept separate from the DevOps implementation. This mirrors professional practice where application code and infrastructure code are maintained independently |
| **Native Linux setup before containerisation** | Running the application from source before introducing Docker or Kubernetes ensures a thorough understanding of service dependencies, environment configuration, and failure modes before any abstraction is applied |
| **`rsync` selective copy** | Source files are copied from the forked repo using `rsync` with explicit excludes, so deployment-specific files never enter the developer working directory and no cleanup step is required |

---

## Repository Structure

```
humor-memory-game/
├── backend/          # Node.js/Express API server
├── frontend/         # Vanilla JS client, served via Nginx
├── database/         # PostgreSQL schema and seed data
└── docs/
    ├── CODEBASE.md          # Architecture and API reference
    ├── DEVELOPER_SETUP.md   # Local development setup guide
    ├── GIT_WORKFLOW.md      # Two-commit Git strategy
    └── TROUBLESHOOTING.md   # Known issues and fixes
```

---

## Documentation

| Document | Purpose |
| :------- | :------ |
| [`docs/CODEBASE.md`](docs/CODEBASE.md) | Application architecture, data flow, and full API reference |
| [`docs/DEVELOPER_SETUP.md`](docs/DEVELOPER_SETUP.md) | Step-by-step local setup and verification testing |
| [`docs/GIT_WORKFLOW.md`](docs/GIT_WORKFLOW.md) | Two-commit Git strategy for capturing raw and working states |
| [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md) | Diagnosis and resolution for known issues |

---

## Connect

- GitHub: [github.com/sjchristie](https://github.com/sjchristie)
- LinkedIn: [linkedin.com/in/stephenjchristie](https://www.linkedin.com/in/stephenjchristie)
- Blog: [christiehome.work](https://christiehome.work)

---

*Based on a fork of [Osomudeya/DevOps-Home-Lab-2026-2027](https://github.com/Osomudeya/DevOps-Home-Lab-2026-2027).*

# Phase 6 — End-to-End Validation and Bug Resolution

| Field | Detail |
|---|---|
| Phase | 6 |
| Title | End-to-End Validation and Bug Resolution |
| Status | ✅ Complete |
| Started | 2026-06-06 |
| Completed | 2026-07-02 |
| Primary machines | `dev-box-01`, `ops-box-01`, `sre-mgmt-01` |
| Repositories | `humor-memory-game`, `humor-memory-game-devops`, `humor-memory-game-kubernetes` |

---

## What Phase 6 Is

Phase 5 built and verified the CI/CD pipeline as a delivery mechanism — images were built, manifests were updated, ArgoCD showed Synced/Healthy. Phase 6 is what happened when that pipeline was used for the first time to deliver a real code change against a real application running on the real cluster.

Three bugs were discovered, diagnosed, and resolved. None of them were new problems introduced in Phase 5 or 6 — all three had existed since earlier phases but were invisible because no end-to-end application test had ever been run against the Kubernetes cluster. The game had never actually been started on the cluster until Phase 6.

This is why Phase 6 exists as a separate phase rather than being absorbed into Phase 5. The pipeline implementation story and the validation and bug resolution story are distinct. Phase 5 is about building the delivery mechanism. Phase 6 is about using it and discovering what it reveals.

---

## Why These Bugs Were Not Caught Earlier

Every previous phase was verified at the infrastructure layer — pods running, health endpoints responding, ArgoCD showing Synced/Healthy. A health check that confirms a pod is alive is not the same as a health check that confirms the application can do its job.

The specific gap: the PostgreSQL health check confirms that a connection can be established. It does not confirm that the database schema exists or that any tables are present. The cluster ran for weeks appearing completely healthy while the database was empty and had been since the first deployment.

A single `POST /api/game/start` request at the end of Phase 3 would have revealed BUG-003 immediately. That test was never performed.

This is a real and common pattern in platform engineering. Infrastructure observability and application observability are different disciplines. Phase 6 is where that gap was found and closed.

---

## The Three Bugs

### BUG-001 — Categories Null Validation Mismatch

| Field | Detail |
|---|---|
| Layer | Application code — frontend |
| Fix repository | `humor-memory-game` |
| Deployment path | CI/CD pipeline — full end-to-end run |
| Fix file | `frontend/src/scripts/game.js` |
| Fix | `null` → `[]` when no emoji categories selected |
| Test | `backend/tests/validation.categories.test.js` — 4 regression tests |
| Pipeline run | Run #3 on `humor-memory-game-devops` |
| Image deployed | `christie62/humor-memory-game-frontend:main-1402d0e` |
| Status | ✅ Closed |

The frontend sent `categories: null` when no emoji categories were selected. The backend Joi schema required an array and rejected `null` with a `400 Bad Request`. The fix sends `[]` instead, which the backend accepts and handles by using all available categories.

This was the first real code fix deployed through the CI/CD pipeline. It was also the first time `npm test` in the pipeline ran Jest instead of the echo placeholder — activating real test execution for all future pipeline runs.

**Side effect discovered:** Running Jest for the first time exposed two pre-existing broken test files — `api.test.js` and `health.test.js` — that had been invisible while the echo placeholder was in place. These are scoped to a separate remediation task.

---

### BUG-002 — Backend Probe Death Spiral

| Field | Detail |
|---|---|
| Layer | Kubernetes manifest — probe timing |
| Fix repository | `humor-memory-game-kubernetes` |
| Deployment path | Direct GitOps commit — no pipeline run required |
| Fix file | `gitops-safe/base/10-backend-deployment.yaml` |
| Fix | Liveness and readiness probe timing values increased |
| Fix commit SHA | `6f61a2c` |
| Status | ✅ Closed — applied preventatively |

The backend liveness probe was configured with timing values too aggressive for ARM64 Raspberry Pi hardware. When PostgreSQL was slow to start, the probe killed the pod after three consecutive 1-second timeout failures, triggering a restart loop with exponential backoff.

BUG-002 was dormant at the time of fix — the death spiral had been triggered by the empty database (BUG-003) causing health check failures. With BUG-003 resolved, the probe was passing cleanly. The fix was applied preventatively to prevent recurrence on any future node reboot or fresh cluster deployment.

| Probe | Parameter | Before | After |
|---|---|---|---|
| Liveness | `initialDelaySeconds` | 45 | 90 |
| Liveness | `timeoutSeconds` | 1 | 5 |
| Liveness | `failureThreshold` | 3 | 5 |
| Readiness | `initialDelaySeconds` | 20 | 30 |
| Readiness | `timeoutSeconds` | 1 | 5 |

---

### BUG-003 — PostgreSQL Init SQL Never Ran

| Field | Detail |
|---|---|
| Layer | Kubernetes infrastructure + application source |
| Fix repositories | `humor-memory-game-kubernetes` and `humor-memory-game` |
| Deployment path | Direct GitOps commit + source fix via PR |
| Runtime fix | `postgres-init-configmap.yaml` populated and wired into deployment |
| Source fix | `database/combined-init.sql` — `ALTER ROLE gameuser SET search_path TO public` added |
| GitOps commit SHAs | `6e95ee8` and `0de1bb6` |
| Source fix SHA | `4ffe261` merged to `humor-memory-game/main` |
| Status | ✅ Closed |

The original diagnosis was a PostgreSQL `search_path` mismatch. The actual problem was more fundamental — the database was completely empty. `combined-init.sql` had never run on the Kubernetes cluster.

Four compounding problems caused this:

1. `postgres-init-configmap.yaml` was committed as an empty placeholder file and never populated
2. The ConfigMap was never mounted into the PostgreSQL container — no `volumeMount` for `/docker-entrypoint-initdb.d/`
3. The iSCSI PVC had filesystem metadata (`lost+found`) at its root — PostgreSQL saw a non-empty data directory and skipped initialisation entirely
4. `kustomization.yaml` was incomplete — `postgres-init-configmap.yaml` was never registered, so ArgoCD never managed it

The fix required two separate actions: a runtime fix to the Kubernetes manifests to populate and wire up the ConfigMap, and a permanent source fix to `combined-init.sql` to ensure all future fresh deployments initialise correctly without manual intervention.

An additional complication: adding `01-namespace.yaml` and `14-ingress.yaml` to `kustomization.yaml` caused an immediate ArgoCD sync failure — both resource types are blocked by the AppProject `humor-game-safe` whitelist. Both were removed. The PVC also became stuck in `Terminating` due to the iSCSI finalizer and required a force-remove with `kubectl patch`.

---

## Deployment Paths Used in Phase 6

Phase 6 demonstrated that different types of changes require different deployment paths. Using the wrong path for a given change type either does nothing or bypasses the audit trail.

| Change type | Correct path | Example in Phase 6 |
|---|---|---|
| Application code fix | CI/CD pipeline — feature branch → PR → merge → pipeline trigger | BUG-001 |
| Kubernetes manifest tuning | Direct GitOps commit to `gitops` branch on `sre-mgmt-01` | BUG-002 |
| Infrastructure configuration | Direct GitOps commit to `gitops` branch on `sre-mgmt-01` | BUG-003 Kubernetes fix |
| Source initialisation script | Feature branch → PR → merge to `main` on `dev-box-01` | BUG-003 source fix |

---

## Lessons Learned

### End-to-end application testing must be part of every phase verification

Infrastructure health checks confirm connectivity, not correctness. A `GET /api/health` returning 200 means the backend can connect to PostgreSQL — it does not mean the database schema exists. An end-to-end smoke test — an actual game start request — must be included in the verification checklist for every phase from Phase 3 onward.

**Improvement:** Add a post-deployment functional verification step to the pipeline — a `curl POST /api/game/start` that confirms a `200` response — so every future deployment automatically validates application behaviour, not just infrastructure health.

### Empty placeholder files in a GitOps repository are dangerous

`postgres-init-configmap.yaml` was committed empty as a placeholder. It was indistinguishable from working configuration without careful inspection. The cluster appeared correctly configured while the ConfigMap contained nothing.

**Improvement:** Never commit empty configuration files. Either commit the correct content or do not commit the file at all.

### PostgreSQL `docker-entrypoint-initdb.d` only runs on a completely empty data directory

Any content in the data directory — including filesystem metadata from iSCSI provisioning — causes PostgreSQL to skip init scripts entirely. The PGDATA subdirectory configuration (`PGDATA: /var/lib/postgresql/data/pgdata`) is mandatory for iSCSI-backed storage, and a fresh PVC must be confirmed empty before the first PostgreSQL start.

### ArgoCD AppProject resource whitelists must be verified before adding new resource types

The AppProject `humor-game-safe` has an explicit whitelist of permitted Kubernetes resource types. Any resource type not on the whitelist causes an immediate sync failure with no warning during development. Check the AppProject definition before adding any new resource type to `kustomization.yaml`.

### Probe timing must be calibrated for the actual hardware

Default probe values from documentation and templates are written for cloud infrastructure with fast storage and consistent CPU availability. Raspberry Pi ARM64 nodes under load are slower. Liveness probe `timeoutSeconds: 1` is too aggressive for a Pi running PostgreSQL, Redis, and the backend simultaneously. Always validate probe timing on the actual target hardware.

### The `manifests/` directory is not managed by ArgoCD

The repository contains two parallel directory structures — `manifests/` and `gitops-safe/base/`. Only `gitops-safe/base/` is watched by ArgoCD. Any change made to `manifests/` has no effect on the cluster. All cluster changes must go into `gitops-safe/base/`.

---

## Phase 6 Documents

| Document | Description |
|---|---|
| `BUG_001_TEST_PLAN_AND_PIPELINE_DEPLOYMENT.md` | Full test plan and pipeline deployment guide for the categories null validation fix |
| `BUG_002_BACKEND_PROBE_DEATH_SPIRAL.md` | Probe timing analysis and fix record |
| `BUG_003_POSTGRES_INIT_SQL_NOT_RUNNING.md` | Root cause analysis and complete fix record for the empty database |

---

## Phase 6 Outcome

At the end of Phase 6 the Humor Memory Game is running end-to-end on the Raspberry Pi K3s cluster for the first time. A player can open the game, enter a username, select a difficulty, leave all emoji categories unchecked, click Start Game, and a 4x4 card grid appears with the timer running.

This is the first confirmed end-to-end working game session on the Kubernetes cluster — the result of six phases of infrastructure, containerisation, orchestration, observability, GitOps, CI/CD pipeline implementation, and validation work.

| Component | Status |
|---|---|
| K3s cluster | ✅ Running — cp-01 (Pi 5) + wrk-01 (Pi 4) |
| PostgreSQL | ✅ Initialised — 5 objects in `public` schema |
| Redis | ✅ Running |
| Backend | ✅ Running — 0 restarts, probe values tuned for ARM64 |
| Frontend | ✅ Running — BUG-001 fix deployed via pipeline |
| ArgoCD | ✅ Synced / Healthy |
| CI/CD Pipeline | ✅ Active — Jest tests running, multi-arch builds, GitOps loop closed |
| Game | ✅ Playable end-to-end |

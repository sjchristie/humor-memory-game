# BUG-003 Fix Record — PostgreSQL Init SQL Never Ran

| Field | Detail |
|---|---|
| Bug ID | BUG-003 |
| Title | Game fails to start — PostgreSQL database is empty |
| Original diagnosis | PostgreSQL `search_path` mismatch |
| Actual root cause | `combined-init.sql` never ran — database completely empty |
| Severity | High |
| Status | ✅ Closed |
| Reported | 2026-06-06 |
| Closed | 2026-07-02 |
| Environment | K3s cluster — humor-memory-game namespace |
| Reporter | Stephen Christie |

---

## Important Note — Original Diagnosis Was Incorrect

The original BUG-003 document diagnosed this as a PostgreSQL `search_path` mismatch — tables existing in the `game` schema but invisible to the default `search_path`. The actual problem was more fundamental: the database was completely empty. No schema, no tables, zero rows. The `combined-init.sql` initialisation script had never run on the Kubernetes cluster.

This document records what was actually found, what was actually fixed, and why the problem was not caught earlier.

---

## What the Symptoms Showed

After BUG-001 was fixed, starting a game with no categories selected produced a new error:

```
❌ Oops! The game got confused. Try again! 🤔
```

Backend logs showed:

```
ERROR:  relation "games" does not exist at character 96
POST /api/game/start 500 2078.844 ms - 105
```

Initial diagnosis pointed to a `search_path` issue — PostgreSQL looking in the wrong schema. Diagnostic queries revealed the real situation:

```sql
SELECT schema_name FROM information_schema.schemata;
```

Result — no `game` schema:

```
    schema_name
--------------------
 public
 information_schema
 pg_catalog
 pg_toast
```

```sql
SELECT table_schema, table_name FROM information_schema.tables
WHERE table_schema NOT IN ('information_schema', 'pg_catalog');
```

Result — zero rows. The database was completely empty.

PostgreSQL logs confirmed:

```
PostgreSQL Database directory appears to contain a database; Skipping initialization
```

---

## Root Cause — Four Compounding Problems

The empty database was caused by four separate problems that stacked on top of each other. Each one alone would have been caught. Together they produced a cluster that appeared healthy while the database had never been initialised.

### Problem 1 — `postgres-init-configmap.yaml` was empty

The file existed in `gitops-safe/base/` but contained no content:

```bash
cat gitops-safe/base/postgres-init-configmap.yaml
# (no output)
```

The ConfigMap was never created in the cluster. `kubectl get configmap -n humor-memory-game` showed only `app-config` and `kube-root-ca.crt` — no `postgres-init-sql`.

### Problem 2 — The init SQL volume mount was missing from `06-postgres-deployment.yaml`

The PostgreSQL deployment had no reference to any init SQL ConfigMap. There was no volume for `postgres-init-sql` and no `volumeMount` for `/docker-entrypoint-initdb.d`. Even if the ConfigMap had been populated, PostgreSQL would never have seen the SQL.

### Problem 3 — The iSCSI PVC `lost+found` issue

The Synology iSCSI PVC was not empty when PostgreSQL first started. The iSCSI volume contained filesystem metadata (`lost+found` directory) at the root. PostgreSQL's entrypoint script checks whether the data directory is empty before running init scripts. Finding a non-empty directory, it assumed an existing database was present and skipped initialisation entirely — even though the `pgdata/` subdirectory was empty.

The PGDATA subdirectory fix (`PGDATA: /var/lib/postgresql/data/pgdata`) was already in the manifest from Phase 3, which meant PostgreSQL wrote its data into a subdirectory rather than the PVC root. However the first startup still saw the non-empty PVC root and skipped init. Once PostgreSQL had initialised even a minimal cluster in `pgdata/`, every subsequent restart found a valid database directory and continued skipping the init scripts.

### Problem 4 — `kustomization.yaml` was incomplete

Several resources present in `gitops-safe/base/` were not registered in `kustomization.yaml`. This meant ArgoCD was not managing `postgres-init-configmap.yaml` even after it was eventually populated. Additionally, `01-namespace.yaml` and `14-ingress.yaml` were registered during the fix attempt and immediately blocked by the ArgoCD AppProject `humor-game-safe`, which does not permit `Namespace` or `Ingress` resource types. This caused an additional sync failure that had to be resolved before the main fix could proceed.

---

## Why This Was Not Caught Earlier

### Phase 2 — Docker Compose masked the problem

Docker Compose mounts `combined-init.sql` directly from the host filesystem as a bind mount:

```yaml
volumes:
  - ../humor-memory-game/database/combined-init.sql:/docker-entrypoint-initdb.d/01-combined-init.sql:ro
```

No ConfigMap, no Kubernetes, no manual wiring required. The init SQL ran automatically every time a fresh volume was created. The game worked end to end. This gave a false sense that database initialisation was a solved problem.

### Phase 3 — Kubernetes infrastructure verified at the wrong layer

Every Phase 3 verification focused on infrastructure health — pods running, health endpoints responding, ArgoCD showing Synced/Healthy. The health endpoint (`/api/health`) checks whether the backend can connect to PostgreSQL and Redis. A successful connection response does not mean the database schema exists — it only means PostgreSQL accepted the connection. The health check returned 200 on a completely empty database.

No end-to-end application test was performed at the end of Phase 3. A single `POST /api/game/start` request would have revealed the empty database immediately.

### Phases 4 and 5 — Observability and CI/CD verified mechanics, not application behaviour

Phase 4 (Observability) monitored CPU, memory, pod health, and HTTP response codes. Phase 5 (CI/CD) verified that images were built, manifests were updated, and ArgoCD synced. Neither phase included a functional game test against the live cluster. The pipeline was declared working when images were pushed and ArgoCD showed Synced — not when the game actually started.

---

## The Fix — Three Separate Changes

### Fix 1 — Kubernetes Manifests on `sre-mgmt-01`

Three files in `gitops-safe/base/` were updated and committed to the `gitops` branch.

**`postgres-init-configmap.yaml`** — populated with the full content of `combined-init.sql` as a Kubernetes ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init-sql
  namespace: humor-memory-game
data:
  combined-init.sql: |
    -- (full SQL content)
```

**`06-postgres-deployment.yaml`** — two additions:

An `initContainers` section to fix permissions on the PGDATA subdirectory before PostgreSQL starts:

```yaml
initContainers:
- name: fix-permissions
  image: busybox
  command: ["sh", "-c", "mkdir -p /var/lib/postgresql/data/pgdata && chown -R 999:999 /var/lib/postgresql/data"]
  volumeMounts:
  - name: postgres-storage
    mountPath: /var/lib/postgresql/data
```

A `volumeMount` for the init SQL and a corresponding `volume` entry:

```yaml
volumeMounts:
- name: postgres-init-sql
  mountPath: /docker-entrypoint-initdb.d
  readOnly: true

volumes:
- name: postgres-init-sql
  configMap:
    name: postgres-init-sql
```

**`kustomization.yaml`** — corrected to register all permitted resources. `01-namespace.yaml` and `14-ingress.yaml` were removed after ArgoCD rejected them as not permitted in the AppProject `humor-game-safe`:

```yaml
resources:
  - 03-configmap.yaml
  - 04-pvc-postgres.yaml
  - 05-pvc-redis.yaml
  - 06-postgres-deployment.yaml
  - 07-postgres-service.yaml
  - 08-redis-deployment.yaml
  - 09-redis-service.yaml
  - 10-backend-deployment.yaml
  - 11-backend-service.yaml
  - 12-frontend-deployment.yaml
  - 13-frontend-service.yaml
  - postgres-init-configmap.yaml
```

Commits on `gitops` branch:

| SHA | Message |
|---|---|
| `6e95ee8` | fix(BUG-003): add postgres init SQL ConfigMap and wire up deployment |
| `0de1bb6` | fix(BUG-003): remove Namespace and Ingress from kustomization — not permitted in AppProject |

### Fix 2 — PVC Deletion to Force Fresh Initialisation

After ArgoCD synced the corrected manifests, the existing PVC still contained the old (empty but initialised) PostgreSQL data directory. PostgreSQL would continue skipping init on restart. The PVC had to be deleted and recreated.

The PVC was stuck in `Terminating` due to the iSCSI finalizer. The finalizer was force-removed:

```bash
kubectl patch pvc postgres-pvc -n humor-memory-game \
  -p '{"metadata":{"finalizers":[]}}' \
  --type=merge
```

A new PVC `pvc-74cc85cb` was immediately provisioned by the StorageClass. PostgreSQL started against the fresh empty volume and the init SQL ran:

```
/usr/local/bin/docker-entrypoint.sh: running /docker-entrypoint-initdb.d/combined-init.sql
CREATE EXTENSION
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE VIEW
CREATE INDEX (x8)
CREATE FUNCTION
CREATE TRIGGER
GRANT (x3)
ALTER ROLE
INSERT 0 8
NOTICE:  🎯 HUMOR MEMORY GAME DATABASE READY!
PostgreSQL init process complete; ready for start up.
```

### Fix 3 — Permanent Source Fix on `dev-box-01`

`ALTER ROLE gameuser SET search_path TO public;` was added to the end of `humor-memory-game/database/combined-init.sql`. This makes the `search_path` configuration explicit in the source rather than relying on the PostgreSQL default, and ensures every future fresh deployment — Kubernetes, Docker Compose, or local developer setup — initialises with the correct role configuration.

Commit on `humor-memory-game/main`:

| SHA | Message |
|---|---|
| `3ab9c60` | fix(BUG-003): add explicit search_path to combined-init.sql |
| `4ffe261` | Merge pull request #2 from sjchristie/fix/BUG-003-postgres-search-path |

---

## Additional Issues Encountered During Fix

### ArgoCD AppProject blocking `Namespace` and `Ingress`

When `01-namespace.yaml` and `14-ingress.yaml` were added to `kustomization.yaml`, ArgoCD immediately failed the sync:

```
resource networking.k8s.io:Ingress is not permitted in project humor-game-safe
resource :Namespace is not permitted in project humor-game-safe
```

The AppProject `humor-game-safe` has a resource whitelist that does not include these types. Both entries were removed from `kustomization.yaml`. The namespace already exists and does not need to be managed by ArgoCD. The Ingress is not required for the current cluster configuration.

### PVC stuck in `Terminating`

The Synology iSCSI storage class uses a finalizer that holds the PVC in `Terminating` until the volume is fully detached from the node. Pressing Ctrl+C during the `kubectl delete pvc` command interrupted the wait but not the deletion. The PVC remained in `Terminating` state while PostgreSQL was scaled back up, which caused PostgreSQL to start against the old volume again. The fix was to force-remove the finalizer with `kubectl patch`.

### `manifests/` vs `gitops-safe/base/` directory confusion

The repository contains two parallel directory structures — `manifests/` and `gitops-safe/base/`. ArgoCD only watches `gitops-safe/base/`. Work done previously in `manifests/` was never applied to the cluster. Only `gitops-safe/base/` is the correct location for any changes intended to reach the cluster.

---

## Verification

### Database tables confirmed present

```
 table_schema |    table_name
--------------+------------------
 public       | daily_challenges
 public       | game_matches
 public       | games
 public       | leaderboard
 public       | users
(5 rows)
```

### Game confirmed working end to end

Browser test — username `stephen`, difficulty Easy, no categories selected, Start Game:

**Result:** Game started. 4x4 card grid displayed. Player: stephen, Score: 0, Moves: 0, Pairs: 0/8. Timer running. No error messages.

This is the first confirmed end-to-end working game start on the Kubernetes cluster.

---

## Lessons Learned

### End-to-end application testing must be part of every phase verification

Infrastructure health checks confirm pods are running and connections are accepted. They do not confirm the application works. A functional smoke test — an actual game start request — must be included in the verification checklist for every phase from Phase 3 onward.

### `docker-entrypoint-initdb.d` only runs on a completely empty data directory

This is documented PostgreSQL behaviour. Any data in the directory — including filesystem metadata from iSCSI provisioning — prevents the init scripts from running. For iSCSI-backed storage, the PGDATA subdirectory configuration (`PGDATA: /var/lib/postgresql/data/pgdata`) is mandatory, and a fresh PVC must be confirmed truly empty before the first PostgreSQL start.

### ConfigMap placeholder files must never be committed empty

`postgres-init-configmap.yaml` was committed empty as a placeholder with the intention of populating it later. It was never populated. Empty placeholder files in a GitOps repository create a false impression of completeness and are indistinguishable from working configuration without careful inspection.

### ArgoCD AppProject resource whitelists must be verified before adding new resource types

The AppProject `humor-game-safe` has an explicit whitelist of permitted Kubernetes resource types. Any resource type not on the whitelist causes an immediate sync failure. Before adding any new resource type to `kustomization.yaml`, check the AppProject definition.

### The `manifests/` directory is a legacy reference copy — not managed by ArgoCD

All cluster changes must go into `gitops-safe/base/`. Work done in `manifests/` has no effect on the cluster.

---

## Closing BUG-003

| Field | Detail |
|---|---|
| Status | ✅ Closed |
| Kubernetes fix | `6e95ee8` and `0de1bb6` on `humor-memory-game-kubernetes` gitops branch |
| Source fix | `3ab9c60` merged to `humor-memory-game/main` |
| PVC recreated | New PVC `pvc-74cc85cb` — fresh initialisation confirmed |
| Database state | 5 objects in `public` schema — confirmed via `information_schema` query |
| Game verified | End-to-end game start confirmed in browser — first working game on K3s cluster |
| Closed by | Stephen Christie |

---

## Summary

| Step | Machine | Action | Outcome |
|---|---|---|---|
| Diagnose | `sre-mgmt-01` | Query `information_schema.schemata` and `information_schema.tables` | Database confirmed completely empty |
| Fix 1a | `sre-mgmt-01` | Populate `postgres-init-configmap.yaml` | ConfigMap contains full SQL content |
| Fix 1b | `sre-mgmt-01` | Update `06-postgres-deployment.yaml` | initContainer and init SQL volume mount added |
| Fix 1c | `sre-mgmt-01` | Update `kustomization.yaml` | 12 permitted resources registered |
| Fix 1d | `sre-mgmt-01` | Commit and push to `gitops` branch SHA `6e95ee8` | ArgoCD sync fails — Namespace and Ingress blocked |
| Fix 1e | `sre-mgmt-01` | Remove Namespace and Ingress from kustomization SHA `0de1bb6` | ArgoCD sync succeeds — Synced/Healthy |
| Fix 2 | `sre-mgmt-01` | Force-remove PVC finalizer, delete PVC, scale down/up postgres | Fresh PVC provisioned, init SQL runs, 5 objects created |
| Fix 3 | `dev-box-01` | Add `ALTER ROLE` to `combined-init.sql`, PR merged SHA `4ffe261` | Permanent source fix on `humor-memory-game/main` |
| Verify | `sre-mgmt-01` | Query `information_schema.tables` | 5 objects confirmed in `public` schema |
| Verify | Browser | Start game with no categories selected | Game starts — first end-to-end success on K3s cluster |

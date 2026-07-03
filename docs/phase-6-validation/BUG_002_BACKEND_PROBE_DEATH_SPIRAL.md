# BUG-002 Fix Record — Backend Probe Death Spiral

| Field | Detail |
|---|---|
| Bug ID | BUG-002 |
| Title | Backend liveness probe kills pods before database is ready |
| Severity | Medium |
| Status | ✅ Closed |
| Reported | 2026-06-06 |
| Closed | 2026-07-02 |
| Environment | K3s cluster — humor-memory-game namespace |
| Reporter | Stephen Christie |
| Fix machine | `sre-mgmt-01` (192.168.30.12) |
| Fix file | `gitops-safe/base/10-backend-deployment.yaml` |
| Fix branch | `gitops` |

---

## Summary

The backend deployment's liveness probe was configured with timing values too aggressive for a Raspberry Pi K3s cluster where PostgreSQL and Redis take longer to become ready than on a typical cloud or enterprise node. When PostgreSQL was slow to start — during a fresh cluster deployment, a node reboot, or a rolling update — the backend health endpoint returned unhealthy. The liveness probe killed the pod after three consecutive failures. The restarted pod faced the same unavailable database, failed again, and the cycle repeated with exponential backoff making recovery progressively slower.

**Current status:** BUG-002 is dormant. After BUG-003 was fixed and the database was properly initialised, all backend pods show 0 restarts. The death spiral was being triggered by the empty database causing the health endpoint to fail — with the database now working, the probe passes every time. However the underlying timing risk remains. A node reboot or fresh cluster deployment could trigger the spiral again. The fix is applied preventatively.

---

## How the Death Spiral Works

The liveness probe checks `/api/health` on port 3001. This endpoint checks both PostgreSQL and Redis connectivity. If either is unavailable, the endpoint returns unhealthy.

With the original probe values:

```
livenessProbe:
  initialDelaySeconds: 45    # First check at 45 seconds
  periodSeconds:       30    # Check every 30 seconds
  failureThreshold:    3     # Kill pod after 3 failures
  timeoutSeconds:      1     # 1 second timeout per check
```

The sequence on a slow startup:

```
T+00s  Pod starts
T+45s  First liveness check — PostgreSQL still initialising — FAIL (1/3)
T+75s  Second liveness check — PostgreSQL still busy — FAIL (2/3)
T+105s Third liveness check — PostgreSQL still not ready — FAIL (3/3)
T+105s Kubernetes kills the pod
T+105s Pod restarts — exponential backoff begins
T+165s Pod starts again after backoff delay
T+210s First liveness check on restarted pod — FAIL (1/3)
       (cycle repeats, backoff grows: 10s → 20s → 40s → 80s → 160s → 300s max)
```

The `timeoutSeconds: 1` makes this worse on ARM64 Raspberry Pi hardware — a database query that takes 1.1 seconds on a Pi under load counts as a failure even if PostgreSQL is healthy.

---

## Confirmed Probe Values — Before Fix

From `kubectl describe pod backend-<hash> -n humor-memory-game`:

```
Liveness:   http-get http://:3001/api/health
            delay=45s timeout=1s period=30s #success=1 #failure=3

Readiness:  http-get http://:3001/api/health
            delay=20s timeout=1s period=15s #success=1 #failure=3
```

---

## Proposed Fix Values

| Parameter | Before | After | Reason |
|---|---|---|---|
| Liveness `initialDelaySeconds` | 45 | 90 | Gives PostgreSQL and Redis time to fully initialise before first check |
| Liveness `periodSeconds` | 30 | 30 | No change — 30 second interval is appropriate |
| Liveness `failureThreshold` | 3 | 5 | Allows 5 consecutive failures (2.5 minutes) before killing — more tolerant of slow starts |
| Liveness `timeoutSeconds` | 1 | 5 | Allows 5 seconds for health check response — appropriate for ARM64 Pi hardware |
| Readiness `initialDelaySeconds` | 20 | 30 | Slight increase — pod should not receive traffic until database is confirmed ready |
| Readiness `periodSeconds` | 15 | 15 | No change |
| Readiness `failureThreshold` | 3 | 3 | No change — readiness can be more aggressive than liveness |
| Readiness `timeoutSeconds` | 1 | 5 | Same as liveness — allows 5 seconds for response |

**Why liveness and readiness have different tolerances:**

The readiness probe controls whether the pod receives traffic. It can be more aggressive — if the pod is not ready, Kubernetes simply stops sending it requests. No harm done.

The liveness probe controls whether the pod is killed and restarted. It must be more tolerant — a false positive liveness failure destroys a healthy pod and triggers a restart loop. On slow hardware like the Raspberry Pi, generous liveness values are essential.

---

## Deployment Path

This fix is a pure Kubernetes manifest change. There is no application code change, no new Docker image, and no CI/CD pipeline run required. The fix goes directly to the `gitops` branch on `sre-mgmt-01` and ArgoCD applies it via a rolling update.

---

## Action 1 — SSH into `sre-mgmt-01` and confirm location

```bash
ssh sre@192.168.30.12
or
ssh sre-mgmnt-01 

cd ~/humor-memory-game-kubernetes

pwd

git branch

git status
```

Expected:

```
* gitops
  main


On branch gitops
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   manifests/06-postgres-deployment.yaml

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	env-patch.yaml
	game_check.sh
	manifests/postgres-init-configmap.yaml
	monitoring/

no changes added to commit (use "git add" and/or "git commit -a")
```

---

## Action 2 — Confirm current probe values before changing anything

```bash
grep -A8 "livenessProbe\|readinessProbe" gitops-safe/base/10-backend-deployment.yaml
```

Expected — current values matching the Before Fix table above.

```
          livenessProbe:
            httpGet:
              path: /api/health
              port: 3001
            initialDelaySeconds: 45
            periodSeconds: 30
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /api/health
              port: 3001
            initialDelaySeconds: 20
            periodSeconds: 15
            failureThreshold: 3
          resources:
            limits:
```

---

## Action 3 — Apply the fix

Open the file in vim and update the six values directly. The `livenessProbe` and `readinessProbe` blocks are the only sections that change.

```bash
vim gitops-safe/base/10-backend-deployment.yaml
```

Make the following six changes:

| Block | Field | Change |
|---|---|---|
| `livenessProbe` | `initialDelaySeconds` | `45` → `90` |
| `livenessProbe` | `timeoutSeconds` | Add line `timeoutSeconds: 5` |
| `livenessProbe` | `failureThreshold` | `3` → `5` |
| `readinessProbe` | `initialDelaySeconds` | `20` → `30` |
| `readinessProbe` | `timeoutSeconds` | Add line `timeoutSeconds: 5` |
| `readinessProbe` | `failureThreshold` | Leave at `3` |

Save and exit with `:wq`.



---

## Action 4 — Verify the changes

```bash
grep -A8 "livenessProbe\|readinessProbe" gitops-safe/base/10-backend-deployment.yaml
```

Expected — updated values:

```yaml
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3001
          initialDelaySeconds: 90
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 5

        readinessProbe:
          httpGet:
            path: /api/health
            port: 3001
          initialDelaySeconds: 30
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
```

```bash
git diff gitops-safe/base/10-backend-deployment.yaml
```

Confirm only probe timing values changed — no other lines modified.

Expected
```
@@ -38,15 +38,17 @@ spec:
             httpGet:
               path: /api/health
               port: 3001
-            initialDelaySeconds: 45
+            initialDelaySeconds: 90
             periodSeconds: 30
-            failureThreshold: 3
+            timeoutSeconds: 5
+            failureThreshold: 5
           readinessProbe:
             httpGet:
               path: /api/health
               port: 3001
-            initialDelaySeconds: 20
+            initialDelaySeconds: 30
             periodSeconds: 15
+            timeoutSeconds: 5
             failureThreshold: 3
           resources:
             limits:
```


---

## Action 5 — Commit and push

```bash
git add gitops-safe/base/10-backend-deployment.yaml

git commit -m "fix(BUG-002): increase backend probe timeouts for ARM64 Pi cluster

- livenessProbe: initialDelaySeconds 45->90, timeoutSeconds 1->5, failureThreshold 3->5
- readinessProbe: initialDelaySeconds 20->30, timeoutSeconds 1->5

Aggressive probe timing caused a death spiral on slow PostgreSQL starts.
The liveness probe killed backend pods after 3 x 1-second timeouts,
triggering restart loops with exponential backoff. More tolerant values
prevent false positive kills on ARM64 Raspberry Pi hardware where
database startup and health check responses are slower than on cloud nodes."

git push origin gitops
```

Expected
```
Enumerating objects: 9, done.
Counting objects: 100% (9/9), done.
Delta compression using up to 4 threads
Compressing objects: 100% (5/5), done.
Writing objects: 100% (5/5), 792 bytes | 792.00 KiB/s, done.
Total 5 (delta 4), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (4/4), completed with 4 local objects.
To github.com:sjchristie/humor-memory-game-kubernetes.git
   0de1bb6..6f61a2c  gitops -> gitops
```

---

## Action 6 — Trigger ArgoCD sync and verify

```bash
kubectl patch application humor-game-local -n argocd \
  --type='merge' \
  -p='{"operation":{"sync":{}}}'
```

```bash
kubectl get applications -n argocd
```

Expected — Synced / Healthy.

Watch the rolling update:

```bash
kubectl get pods -n humor-memory-game -w
```

Expected — new backend pods come up cleanly, old pods terminate, all RESTARTS remain at 0 throughout.

Expected when completed
```
NAME                        READY   STATUS    RESTARTS   AGE
backend-7c88c998d-j2fh6     1/1     Running   0          6m50s
backend-7c88c998d-k5j52     1/1     Running   0          7m25s
frontend-65cbc94667-k765s   1/1     Running   0          39h
frontend-65cbc94667-slk5w   1/1     Running   0          39h
postgres-5ff9d77d9d-4d8c9   1/1     Running   0          19h
redis-5c5668dbfc-7ntp2      1/1     Running   0          3d20h
```

Once stable:

```bash
kubectl describe pod -l app=backend -n humor-memory-game | grep -A8 "Liveness\|Readiness"
```

Expected — new probe values confirmed on the running pods:

```
    Liveness:   http-get http://:3001/api/health delay=90s timeout=5s period=30s #success=1 #failure=5
    Readiness:  http-get http://:3001/api/health delay=30s timeout=5s period=15s #success=1 #failure=3
    Environment Variables from:
      app-config       ConfigMap  Optional: false
      database-secret  Secret     Optional: false
      redis-secret     Secret     Optional: false
      app-secret       Secret     Optional: false
    Environment:
      REDIS_PASSWORD:  REDIS_PASSWORD
      REDIS_PASSWORD:  <set to the key 'REDIS_PASSWORD' in secret 'redis-secret'>  Optional: false
--
    Liveness:   http-get http://:3001/api/health delay=90s timeout=5s period=30s #success=1 #failure=5
    Readiness:  http-get http://:3001/api/health delay=30s timeout=5s period=15s #success=1 #failure=3
    Environment Variables from:
      app-config       ConfigMap  Optional: false
      database-secret  Secret     Optional: false
      redis-secret     Secret     Optional: false
      app-secret       Secret     Optional: false
    Environment:
      REDIS_PASSWORD:  REDIS_PASSWORD
      REDIS_PASSWORD:  <set to the key 'REDIS_PASSWORD' in secret 'redis-secret'>  Optional: false
```

---

## Action 7 — Final verification

```bash
kubectl get pods -n humor-memory-game
```

Expected — all pods Running, all RESTARTS at 0:

```
NAME                        READY   STATUS    RESTARTS   AGE
backend-7c88c998d-j2fh6     1/1     Running   0          165m
backend-7c88c998d-k5j52     1/1     Running   0          165m
frontend-65cbc94667-k765s   1/1     Running   0          42h
frontend-65cbc94667-slk5w   1/1     Running   0          42h
postgres-5ff9d77d9d-4d8c9   1/1     Running   0          22h
redis-5c5668dbfc-7ntp2      1/1     Running   0          3d23h
```

---

## Closing BUG-002

| Field | Detail |
|---|---|
| Status | ✅ Closed |
| Fix commit SHA | `6f61a2c` on `humor-memory-game-kubernetes` gitops branch |
| Fix | `gitops-safe/base/10-backend-deployment.yaml` — probe timing values updated |
| Fix branch | `humor-memory-game-kubernetes` gitops branch |
| Deployed via | ArgoCD sync — direct GitOps commit, no pipeline run required |
| Verified | All pods Running, RESTARTS 0, new probe values confirmed on live pods |
| Closed by | Stephen Christie |

---

## Summary

| Step | Action | Outcome |
|---|---|---|
| Confirm current state | `kubectl get pods` — check RESTARTS | All 0 — bug dormant, fix applied preventatively |
| Confirm current values | `grep livenessProbe` in manifest | 45s delay, 1s timeout, 3 failures confirmed |
| Apply fix | Update 6 probe values in `10-backend-deployment.yaml` | More tolerant values for ARM64 Pi hardware |
| Commit and push | `gitops` branch | ArgoCD detects change |
| ArgoCD sync | Rolling update applied | New probe values live on cluster |
| Verify | `kubectl describe pod` — check probe values | 90s delay, 5s timeout, 5 failures confirmed |
| Close | BUG-002 closed | Preventative fix confirmed |

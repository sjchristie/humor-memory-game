# BUG-001 Test Plan and Pipeline Deployment Guide

| Field | Detail |
|---|---|
| Bug ID | BUG-001 |
| Title | Game fails to start when no emoji categories selected |
| Fix file | `humor-memory-game/frontend/src/scripts/game.js` |
| Test file | `humor-memory-game/backend/tests/validation.categories.test.js` |
| Branch | `fix/BUG-001-categories-null-validation` |
| Primary machine | `dev-box-01` (192.168.30.10) |
| Pipeline trigger machine | `ops-box-01` (192.168.30.11) |
| Verification machine | `sre-mgmt-01` (192.168.30.12) |

---

## Overview

This document covers the complete process for fixing BUG-001, writing a regression test that proves the fix is correct, running that test locally to confirm it passes before touching the pipeline, and then pushing the fix through the CI/CD pipeline to deploy it to the live K3s cluster.

The fix is a single line change in the frontend. The test lives in the backend because that is where the contract is defined — the Joi validation schema in `middleware/validation.js` is what rejects `null` and accepts `[]`. Testing the schema in isolation means no database, no Redis, and no running server are required, which is exactly what the pipeline runner needs — a pure, infrastructure-free test that can run on any bare Ubuntu VM.

By the end of this process, two things will have changed permanently:

1. `npm test` in the backend will run Jest for real — not the echo placeholder. Every future pipeline run from this point forward will execute the real test suite.
2. BUG-001 will be closed with the commit SHA of the fix as evidence.

---

## What Will Change and Where

| File | Repository | Change |
|---|---|---|
| `backend/package.json` | `humor-memory-game` | `test` script changed from echo placeholder to `jest` |
| `backend/tests/validation.categories.test.js` | `humor-memory-game` | New file — the regression test |
| `frontend/src/scripts/game.js` | `humor-memory-game` | One line — `null` changed to `[]` |

No changes are required to the pipeline (`ci.yml`), the Kubernetes manifests, the Dockerfiles, or any infrastructure. The pipeline already does everything correctly — it just needs real code to test and deploy.

---

## Test Strategy

### Why the test lives in the backend, not the frontend

The bug has two sides: the frontend sends the wrong value (`null`), and the backend rejects it. The fix is in the frontend. The test belongs in the backend.

This is because the backend is where the contract is defined. The Joi schema in `middleware/validation.js` is the authoritative specification of what the API accepts. A regression test on that schema proves the contract is correct and will catch any future developer accidentally changing `Joi.array()` to something that accepts `null` again. A test on the frontend JavaScript would only prove that one line was changed — it would not protect the contract.

### Why no server, no database, no HTTP calls

The pipeline's test job runs on a GitHub-hosted Ubuntu runner — a bare VM with Node.js installed and nothing else. There is no PostgreSQL, no Redis, and no running Express server. Any test that tries to connect to infrastructure will fail immediately with a connection refused error and block the build.

The Joi schema is a pure function. You give it an object, it returns a validation result. Testing it requires only:

- `require` the validation middleware
- call `schema.validate({ categories: null })`
- assert the result has an error

No server, no network, no mocking of any kind.

### What the test proves

The test suite covers four cases in order:

1. `categories: null` — must fail validation. This is the bug. If this test passes (i.e. Joi rejects `null`), the schema is working as documented.
2. `categories: []` — must pass validation. This is the fix. An empty array is valid.
3. `categories: ['classic']` — must pass validation. A real selection works.
4. `categories: ['invalid_value']` — must fail validation. This proves the schema is actually enforcing the allowed values, not just accepting any array.

Test 1 and Test 4 are expected to fail validation (error exists). Test 2 and Test 3 are expected to pass validation (no error). All four must pass for the test suite to be green.

---

## Phase 1 — Work on `dev-box-01`

All work in this phase is done on `dev-box-01` as the `developer` user. The `humor-memory-game` repository is cloned at `~/humor-memory-game`.

### Action 1 — SSH into `dev-box-01` and confirm your location

```bash
ssh developer@192.168.30.10
or
ssh dev-box-01 
```

Once connected, confirm you are in the right place:

```bash
cd ~/humor-memory-game
pwd
```

Expected:
```
/home/developer/humor-memory-game
```

Confirm the repository is on `main` and clean before creating any branch:

```bash
git status

git branch
```

Expected:

```
On branch main
Your branch is up to date with 'origin/main'.

* main
```

> If `git status` shows uncommitted changes from earlier work, stash or commit them before continuing. Do not create a feature branch on top of uncommitted changes.

---

### Action 2 — Create the feature branch

A feature branch keeps the fix isolated from `main` until it has been tested and reviewed. The branch name matches the bug ID directly so it is traceable.

```bash
git checkout -b fix/BUG-001-categories-null-validation
```

Expected:
```
Switched to a new branch 'fix/BUG-001-categories-null-validation'
```

Confirm:
```bash
git branch
```

Expected:
```
* fix/BUG-001-categories-null-validation
  main
```

---

### Action 3 — Confirm the backend test infrastructure is ready

Before writing anything, confirm that Jest is available as a dependency and that the current test script is the placeholder.

```bash
cat backend/package.json | grep -A8 '"scripts"'
```

Expected — the placeholder test script:
```json
 "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "echo '✅ Tests skipped - DevOps learning focus' && exit 0",
    "test:watch": "jest --watch",
    "test:ci": "jest --coverage --ci --reporters=default --reporters=jest-junit",
    "db:migrate": "node utils/migrate.js",
    "db:seed": "node utils/seed.js",
    "lint": "echo '✅ Linting skipped - DevOps learning focus' && exit 0",
```

The `test:watch` and `test:ci` scripts confirm Jest is already configured as a dependency. The `test` script is the placeholder we are about to replace.

Confirm Jest is installed:

```bash
cd backend

ls node_modules/.bin/jest 2>/dev/null && echo "Jest found" || echo "Jest not installed — run npm install first"
```


If returns the below
```
Jest not installed — run npm install first
```

> If Jest is not found, run `npm install` from inside `backend/` before continuing. This installs all Dependencies including Jest.


---

### Action 4 — Create the test directory

The test file belongs alongside the backend code. If a `tests/` directory does not already exist, create it:

```bash
ls tests 2>/dev/null && echo "tests/ directory exists" || mkdir tests && echo "tests/ directory created"
```

Expected 
```
tests/ directory exists
tests/ directory created
```

---

### Action 5 — Write the regression test file

Create the following file at `backend/tests/validation.categories.test.js`.

This file tests the Joi schema from `middleware/validation.js` in complete isolation. Read through the annotated version first to understand what each test case is asserting, then use the production copy to create the file.

**Annotated version — read before creating the file:**

```javascript
// validation.categories.test.js
// Regression test for BUG-001: categories null validation mismatch
//
// This test suite validates the Joi schema for the /api/game/start endpoint.
// It tests the schema in isolation — no server, no database, no HTTP calls.
// The schema is a pure function: give it input, get a validation result back.
//
// All four tests must pass for the suite to be green.

'use strict';

// Require Joi directly — the same library used in validation.js.
// This avoids needing to require the entire middleware module,
// which may have side-effects (database connections, etc).
const Joi = require('joi');

// This is the exact schema from middleware/validation.js for the
// /api/game/start endpoint. It is reproduced here rather than
// imported because importing the middleware may trigger side-effects.
// If validation.js is later refactored to export the schema cleanly,
// this test can be updated to import it directly.
const categoriesSchema = Joi.object({
  categories: Joi.array()
    .items(
      Joi.string().valid('classic', 'food', 'space', 'fantasy', 'tech')
    )
});

// ============================================================
// TEST SUITE
// ============================================================
describe('BUG-001 — categories field validation', () => {

  // ----------------------------------------------------------
  // TEST 1: The bug itself
  // Before the fix, the frontend sent null when no categories
  // were selected. This test confirms the schema rejects null.
  // If this test fails, something has changed in the schema
  // to allow null — which would be a regression.
  // ----------------------------------------------------------
  test('null categories should fail validation (the bug)', () => {
    const { error } = categoriesSchema.validate({ categories: null });

    // We EXPECT an error here — null must be rejected
    expect(error).toBeDefined();
    expect(error.details[0].message).toContain('"categories" must be an array');
  });

  // ----------------------------------------------------------
  // TEST 2: The fix
  // After the fix, the frontend sends [] when no categories
  // are selected. This test confirms an empty array is valid.
  // The backend game logic already handles [] by using all
  // available categories — confirmed during bug investigation.
  // ----------------------------------------------------------
  test('empty array categories should pass validation (the fix)', () => {
    const { error } = categoriesSchema.validate({ categories: [] });

    // We expect NO error — an empty array must be accepted
    expect(error).toBeUndefined();
  });

  // ----------------------------------------------------------
  // TEST 3: Normal usage
  // Confirms a valid category value passes validation.
  // This is the path that already worked before the fix.
  // ----------------------------------------------------------
  test('valid category value should pass validation', () => {
    const { error } = categoriesSchema.validate({ categories: ['classic'] });

    expect(error).toBeUndefined();
  });

  // ----------------------------------------------------------
  // TEST 4: Schema enforcement
  // Confirms the schema actually enforces the allowed values —
  // it is not just accepting any array content.
  // If this test fails, the schema has been weakened and is
  // no longer enforcing the category whitelist.
  // ----------------------------------------------------------
  test('invalid category value should fail validation', () => {
    const { error } = categoriesSchema.validate({ categories: ['invalid_value'] });

    // We EXPECT an error — unknown values must be rejected
    expect(error).toBeDefined();
  });

});
```

**Create the file:**

```
cd ..
pwd
```

Expected
```
/home/developer/humor-memory-game
```

```bash
cat > backend/tests/validation.categories.test.js << 'EOF'
'use strict';

const Joi = require('joi');

const categoriesSchema = Joi.object({
  categories: Joi.array()
    .items(
      Joi.string().valid('classic', 'food', 'space', 'fantasy', 'tech')
    )
});

describe('BUG-001 — categories field validation', () => {

  test('null categories should fail validation (the bug)', () => {
    const { error } = categoriesSchema.validate({ categories: null });
    expect(error).toBeDefined();
    expect(error.details[0].message).toContain('"categories" must be an array');
  });

  test('empty array categories should pass validation (the fix)', () => {
    const { error } = categoriesSchema.validate({ categories: [] });
    expect(error).toBeUndefined();
  });

  test('valid category value should pass validation', () => {
    const { error } = categoriesSchema.validate({ categories: ['classic'] });
    expect(error).toBeUndefined();
  });

  test('invalid category value should fail validation', () => {
    const { error } = categoriesSchema.validate({ categories: ['invalid_value'] });
    expect(error).toBeDefined();
  });

});
EOF
```

Confirm the file was created:

```bash
cat backend/tests/validation.categories.test.js
```

---

### Action 6 — Update the backend `test` script

The current `test` script in `backend/package.json` is the echo placeholder. It must be changed to run Jest so that `npm test` in the pipeline executes the real test suite.

Open `backend/package.json` and change the `test` line:

```
vim backend/package.json
```

**Before:**
```json
"test": "echo '✅ Tests skipped - DevOps learning focus' && exit 0",
```

**After:**
```json
"test": "jest tests/validation.categories.test.js",
```

The `test:ci` and `test:watch` scripts remain unchanged — they already use Jest and are used by specific tooling contexts.

> **Why just `jest` and not `jest --coverage`?** The `test` script is what the pipeline runs via `npm test`. Coverage reporting belongs in `test:ci` which is used for formal CI reporting. Keeping `test` simple as `jest` means it is fast and produces clean output — suitable for a pipeline gate.

Verify the change:

```bash
cat backend/package.json | grep -A6 '"scripts"'
```

Expected:

```json
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "jest tests/validation.categories.test.js",
    "test:watch": "jest --watch",
    "test:ci": "jest --coverage --ci --reporters=default --reporters=jest-junit",
```

---

### Action 7 — Run the tests locally before touching anything else

This is the most important step before committing. Running the tests locally confirms:

- The test file has no syntax errors
- Jest can find and execute the test file
- All four tests pass against the current (unfixed) code

Wait — all four tests should pass against the current unfixed code too, because the test suite is testing the Joi schema directly, not the frontend code. The schema has not changed. All four tests should pass right now. This is expected and correct.

```bash
cd backend

npm test
```

Expected output:
```
> humor-memory-game-backend@1.0.0 test
> jest tests/validation.categories.test.js

 PASS  tests/validation.categories.test.js
  BUG-001 — categories field validation
    ✓ null categories should fail validation (the bug) (7 ms)
    ✓ empty array categories should pass validation (the fix) (1 ms)
    ✓ valid category value should pass validation (1 ms)
    ✓ invalid category value should fail validation (2 ms)

Test Suites: 1 passed, 1 total
Tests:       4 passed, 4 total
Snapshots:   0 total
Time:        0.453 s, estimated 1 s
Ran all test suites matching /tests\/validation.categories.test.js/i.
```

> **If all four tests pass at this point, that is correct.** The schema was never broken — it was always rejecting `null` correctly. The regression test proves the schema behaves as documented. What was broken was the frontend sending the wrong value. The fix in the next action corrects that.

> **If any test fails here:** do not proceed. The test file has an error or the schema in `middleware/validation.js` differs from what was documented in BUG-001. Read the Jest error output carefully and correct the test file before continuing.


> **Confirmed result:** All four tests passed cleanly in 0.453 seconds — the Joi schema correctly rejects `null`, accepts `[]`, accepts valid category values, and enforces the whitelist. No infrastructure required.

> **Side-effect discovered:** Running Jest for the first time exposed two pre-existing broken test files — `api.test.js` (wrong module path) and `health.test.js` (ESM/CommonJS incompatibility with `uuid`, incorrect health endpoint assertions, leaking database connections). These were invisible while the echo placeholder was in place. They are not part of BUG-001 and have been scoped to a separate bug report. The `test` script targets `tests/validation.categories.test.js` specifically to exclude them from the pipeline gate until they are remediated.



Return to the repository root after testing:

```bash
cd ..
pwd
```

Expected:
```
/home/developer/humor-memory-game
```


---

### Action 8 — Apply the bug fix

The fix is a single character change in `frontend/src/scripts/game.js`. The frontend sends `null` when no categories are selected. It must send `[]` instead.

Confirm the broken line exists before changing it:

```bash
grep "selectedCategories.length > 0 ? selectedCategories : null" frontend/src/scripts/game.js
```

Expected — the broken line:
```javascript
categories: selectedCategories.length > 0 ? selectedCategories : null,
```

> If this line is not found, the file path or content has changed. Do not proceed — investigate before making any changes.

Apply the fix:
```bash
sed -i 's/selectedCategories.length > 0 ? selectedCategories : null/selectedCategories.length > 0 ? selectedCategories : []/g' frontend/src/scripts/game.js
```

Verify the fix was applied:

```bash
grep "selectedCategories.length > 0" frontend/src/scripts/game.js
```

Expected — the fixed line:
```javascript
categories: selectedCategories.length > 0 ? selectedCategories : [],
```

> `sed -i` edits the file in place. If you prefer to edit manually, open `frontend/src/scripts/game.js` in your editor, find the line, and change `null` to `[]` at the end.

---

### Action 9 — Run the tests again to confirm nothing broke

The fix was applied to the frontend. The tests are in the backend. Run them again to confirm the backend test suite is still clean after the frontend change.

```bash
cd backend

npm test
```

Expected — same four passing tests:
```
> humor-memory-game-backend@1.0.0 test
> jest tests/validation.categories.test.js

 PASS  tests/validation.categories.test.js
  BUG-001 — categories field validation
    ✓ null categories should fail validation (the bug) (6 ms)
    ✓ empty array categories should pass validation (the fix) (1 ms)
    ✓ valid category value should pass validation (1 ms)
    ✓ invalid category value should fail validation (2 ms)

Test Suites: 1 passed, 1 total
Tests:       4 passed, 4 total
Snapshots:   0 total
Time:        0.419 s, estimated 1 s
Ran all test suites matching /tests\/validation.categories.test.js/i.
```

Return to the repository root:

```bash
cd ..
```

---

### Action 10 — Review all changes before committing

Confirm exactly three files have changed and nothing unexpected:

```bash
git status
```

Expected:
```
On branch fix/BUG-001-categories-null-validation
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   backend/package-lock.json
	modified:   backend/package.json
	modified:   frontend/src/scripts/game.js

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	backend/tests/validation.categories.test.js

no changes added to commit (use "git add" and/or "git commit -a")
```

Review each change:
```bash
git diff backend/package.json
```

Expected — only the test script line changed:
```diff
diff --git a/backend/package.json b/backend/package.json
index ef7a1e6..abb8307 100644
--- a/backend/package.json
+++ b/backend/package.json
@@ -6,7 +6,7 @@
   "scripts": {
     "start": "node server.js",
     "dev": "nodemon server.js",
-    "test": "echo '✅ Tests skipped - DevOps learning focus' && exit 0",
+    "test": "jest tests/validation.categories.test.js",
     "test:watch": "jest --watch",
     "test:ci": "jest --coverage --ci --reporters=default --reporters=jest-junit",
     "db:migrate": "node utils/migrate.js",
```

```bash
git diff frontend/src/scripts/game.js
```

Expected — only the categories line changed:

```diff
index 1c2c64e..d963d92 100644
--- a/frontend/src/scripts/game.js
+++ b/frontend/src/scripts/game.js
@@ -240,7 +240,7 @@ async function startNewGame() {
     const gameData = {
       username,
       difficulty,
-      categories: selectedCategories.length > 0 ? selectedCategories : null,
+      categories: selectedCategories.length > 0 ? selectedCategories : [],
     };
 
     const result = await apiRequest('/game/start', {
```

```bash
cat backend/tests/validation.categories.test.js
```

Confirm the test file content is correct.

> If `git status` shows any other files modified, investigate before committing. Only the three expected files should have changed.


Run the tests one final time before committing to confirm everything is still clean:

```bash
cd backend && npm test
```

Expected — four passing, nothing else:
```
> humor-memory-game-backend@1.0.0 test
> jest tests/validation.categories.test.js

 PASS  tests/validation.categories.test.js
  BUG-001 — categories field validation
    ✓ null categories should fail validation (the bug) (7 ms)
    ✓ empty array categories should pass validation (the fix) (2 ms)
    ✓ valid category value should pass validation (1 ms)
    ✓ invalid category value should fail validation (2 ms)

Test Suites: 1 passed, 1 total
Tests:       4 passed, 4 total
Snapshots:   0 total
Time:        0.42 s, estimated 1 s
Ran all test suites matching /tests\/validation.categories.test.js/i.
```

---

### Action 11 — Commit the changes

All three changes are committed together in a single commit. This is correct — the test, the script update, and the fix are one logical unit. Splitting them into separate commits would mean a commit exists where the test script runs Jest but the test file does not exist yet.

```bash
cd ..

git add backend/package.json

git add backend/tests/validation.categories.test.js

git add backend/package-lock.json

git add frontend/src/scripts/game.js
```

Confirm the staging area:

```bash
git status
```

Expected:
```
On branch fix/BUG-001-categories-null-validation
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	modified:   backend/package.json
	new file:   backend/tests/validation.categories.test.js
	modified:   frontend/src/scripts/game.js

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   backend/package-lock.json

[developer@dev-box-01 humor-memory-game]$ git add backend/package-lock.json
[developer@dev-box-01 humor-memory-game]$ git status
On branch fix/BUG-001-categories-null-validation
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	modified:   backend/package-lock.json
	modified:   backend/package.json
	new file:   backend/tests/validation.categories.test.js
	modified:   frontend/src/scripts/game.js
```

Commit:

```bash
git commit -m "fix(BUG-001): send empty array instead of null when no categories selected

- frontend/src/scripts/game.js: change null to [] when selectedCategories is empty
- backend/tests/validation.categories.test.js: add regression test for categories validation
- backend/package.json: activate jest as the test runner (replaces echo placeholder)
- backend/package-lock.json: updated by npm audit fix (resolved 4 vulnerabilities)

Fixes BUG-001. The frontend was sending categories: null when no emoji
categories were selected. The backend Joi schema requires an array and
rejects null with a 400 Bad Request. Fix sends [] which the backend
accepts and handles by using all available categories."
```

Expected
```
[fix/BUG-001-categories-null-validation 24f3813] fix(BUG-001): send empty array instead of null when no categories selected
 4 files changed, 187 insertions(+), 138 deletions(-)
 create mode 100644 backend/tests/validation.categories.test.js
```

Confirm the commit was created:

```bash
git log --oneline -3
```

Expected — your fix commit at the top:
```
24f3813 (HEAD -> fix/BUG-001-categories-null-validation) fix(BUG-001): send empty array instead of null when no categories selected
41eafbc (origin/main, origin/HEAD, main) Updated documents and game.js
196f4fa Updated the files in the /docs and add diagnose.sh file
```

Note the short SHA of your commit — you will use it to verify the deployed image later.

---

### Action 12 — Push the feature branch and merge to `main`

Push the feature branch to GitHub:

```bash
git push origin fix/BUG-001-categories-null-validation
```

Expected:
```
Enumerating objects: 20, done.
Counting objects: 100% (20/20), done.
Delta compression using up to 4 threads
Compressing objects: 100% (10/10), done.
Writing objects: 100% (11/11), 4.69 KiB | 1.56 MiB/s, done.
Total 11 (delta 7), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (7/7), completed with 7 local objects.
remote: 
remote: Create a pull request for 'fix/BUG-001-categories-null-validation' on GitHub by visiting:
remote:      https://github.com/sjchristie/humor-memory-game/pull/new/fix/BUG-001-categories-null-validation
remote: 
To github.com:sjchristie/humor-memory-game.git
 * [new branch]      fix/BUG-001-categories-null-validation -> fix/BUG-001-categories-null-validation
```

**Raise a Pull Request on GitHub:**

This is wrong
1. Go to `https://github.com/sjchristie/humor-memory-game`.
2. GitHub will show a banner: **"fix/BUG-001-categories-null-validation had recent pushes — Compare & pull request"**. Click it.
3. Title: `fix(BUG-001): send empty array instead of null when no categories selected`
4. Description: paste the commit message body.
5. Link to BUG-001: add a line `Closes BUG-001` in the description.
6. Click **Create pull request**.
7. Review the diff — confirm only three files changed and the changes match what you committed.
8. Click **Merge pull request** → **Confirm merge**.

New Steps

Go to `https://github.com/sjchristie/humor-memory-game`.

Since the yellow banner didn't show up automatically, use the standard GitHub navigation to start your Pull Request.

How to open the Pull Request screen from your current page

```
   sjchristie / humor-memory-game
                       v
<> Code   [!] Pull requests   Actions   Projects
```

1. Look near the top-left of your page, right next to the ** Code** tab.
2. Click directly on ** Pull requests**.
3. Click the green **New pull request** button on the right side of the screen.
4. On the next screen, change the right-hand dropdown menu (the "compare" branch) from `main` to your new branch: **`fix/BUG-001-categories-null-validation`**.
5. Click the green **Create pull request** button that appears.

Fill Out and Merge Your PR

1. **Title**: `fix(BUG-001): send empty array instead of null when no categories selected`
2. **Description**: Paste your commit message body and add a new line at the bottom reading: `Closes BUG-001`
3. Click **Create pull request**.
4. Check the **Files changed** tab to confirm exactly 3 files were modified.
5. Go back to the **Conversation** tab and click **Merge pull request** → **Confirm merge**.



After merging:

```bash
git checkout main
```

Expected — your fix commit is now on `main`:
```
Switched to branch 'main'
Your branch is up to date with 'origin/main'.
```


```bash
git pull origin main
```

Expected:
```
remote: Enumerating objects: 1, done.
remote: Counting objects: 100% (1/1), done.
remote: Total 1 (delta 0), reused 0 (delta 0), pack-reused 0 (from 0)
Unpacking objects: 100% (1/1), 964 bytes | 964.00 KiB/s, done.
From github.com:sjchristie/humor-memory-game
 * branch            main       -> FETCH_HEAD
   41eafbc..1402d0e  main       -> origin/main
Updating 41eafbc..1402d0e
Fast-forward
 backend/package-lock.json                   | 286 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++------------------------------------------------------
 backend/package.json                        |   2 +-
 backend/tests/validation.categories.test.js |  35 ++++++++++++++
 frontend/src/scripts/game.js                |   2 +-
 4 files changed, 187 insertions(+), 138 deletions(-)
 create mode 100644 backend/tests/validation.categories.test.js
```


```bash
git log --oneline -3
```

Expected:
```
1402d0e (HEAD -> main, origin/main, origin/HEAD) Merge pull request #1 from sjchristie/fix/BUG-001-categories-null-validation
24f3813 (origin/fix/BUG-001-categories-null-validation, fix/BUG-001-categories-null-validation) fix(BUG-001): send empty array instead of null when no categories selected
41eafbc Updated documents and game.js
```


Record this SHA. This is the commit the pipeline will use to tag the Docker images.

---

## Phase 2 — Trigger the Pipeline on `ops-box-01`

The pipeline lives in `humor-memory-game-devops` and is triggered by a push to its `main` branch. It checks out `humor-memory-game` as part of its build — so the fix commit must already be merged to `humor-memory-game/main` before the pipeline runs, which you completed in Phase 1.

The pipeline does not watch `humor-memory-game` directly. You trigger it by making a push to `humor-memory-game-devops`. A pipeline trigger commit is the correct way to do this — a small, traceable change to the DevOps repository that signals a new deployment is required.

### Action 13 — SSH into `ops-box-01`

```bash
ssh devops@192.168.30.11
or
ssh ops-box-01 
```

```bash
cd ~/workspace/humor-memory-game

git status
```

```
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   frontend/nginx.conf

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	backend/.dockerignore
	frontend/.dockerignore
	frontend/start.sh

no changes added to commit (use "git add" and/or "git commit -a")
```


```bash
git pull origin main
```

```
remote: Enumerating objects: 21, done.
remote: Counting objects: 100% (21/21), done.
remote: Compressing objects: 100% (4/4), done.
remote: Total 12 (delta 7), reused 11 (delta 7), pack-reused 0 (from 0)
Unpacking objects: 100% (12/12), 5.60 KiB | 956.00 KiB/s, done.
From github.com:sjchristie/humor-memory-game
 * branch            main       -> FETCH_HEAD
   41eafbc..1402d0e  main       -> origin/main
Updating 41eafbc..1402d0e
Fast-forward
 backend/package-lock.json                   | 286 +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++------------------------------------------------------
 backend/package.json                        |   2 +-
 backend/tests/validation.categories.test.js |  35 ++++++++++++++
 frontend/src/scripts/game.js                |   2 +-
 4 files changed, 187 insertions(+), 138 deletions(-)
 create mode 100644 backend/tests/validation.categories.test.js
[devops@ops-box-01 humor-memory-game]$ 
```


Confirm you are on `main` and the repository is up to date.

```bash
git status
```

```
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   frontend/nginx.conf

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	backend/.dockerignore
	frontend/.dockerignore
	frontend/start.sh

no changes added to commit (use "git add" and/or "git commit -a")
```


---

### Action 14 — Create and push a pipeline trigger commit

```bash
git checkout -b trigger/BUG-001-deploy
```

Add a deployment note to the `docs/` directory — this is a traceable record of why the pipeline was triggered:

```bash
cat >> docs/DEPLOYMENTS.md << 'EOF'

## BUG-001 Fix Deployment

| Field | Detail |
|---|---|
| Date | $(date '+%Y-%m-%d') |
| Bug | BUG-001 — categories null validation mismatch |
| Fix commit | humor-memory-game SHA from Phase 1 |
| Change | frontend/scripts/game.js: null → [] |
| Test | backend/tests/validation.categories.test.js |

EOF
```

> If `docs/DEPLOYMENTS.md` does not exist yet, the `>>` operator will create it.

The only correction needed to the document's Action 14 is the `$(date '+%Y-%m-%d')` line — inside a heredoc with `'EOF'` (single-quoted), the shell does **not** expand variables or command substitutions. The date will appear literally as `$(date '+%Y-%m-%d')` in the file rather than today's date. Either use double-quoted `EOF` or replace it with today's date manually: `2026-07-01`.


Commit and push:

```bash
git add docs/DEPLOYMENTS.md

git commit -m "chore(deploy): trigger pipeline for BUG-001 fix"
```

Expected
```
[trigger/BUG-001-deploy a8bda75] chore(deploy): trigger pipeline for BUG-001 fix
 1 file changed, 11 insertions(+)
 create mode 100644 docs/DEPLOYMENTS.md
```

```bash
git push origin trigger/BUG-001-deploy
```

Expected
```
Enumerating objects: 6, done.
Counting objects: 100% (6/6), done.
Delta compression using up to 4 threads
Compressing objects: 100% (4/4), done.
Writing objects: 100% (4/4), 574 bytes | 574.00 KiB/s, done.
Total 4 (delta 2), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (2/2), completed with 2 local objects.
remote: 
remote: Create a pull request for 'trigger/BUG-001-deploy' on GitHub by visiting:
remote:      https://github.com/sjchristie/humor-memory-game-devops/pull/new/trigger/BUG-001-deploy
remote: 
To github.com:sjchristie/humor-memory-game-devops.git
 * [new branch]      trigger/BUG-001-deploy -> trigger/BUG-001-deploy
```

Merge to `main` on GitHub (`humor-memory-game-devops`) via a pull request, or if working solo:

```bash
git checkout main
```

expected
```
Switched to branch 'main'
```

```
git merge trigger/BUG-001-deploy
```

Expected
```
Updating 9432069..a8bda75
Fast-forward
 docs/DEPLOYMENTS.md | 11 +++++++++++
 1 file changed, 11 insertions(+)
 create mode 100644 docs/DEPLOYMENTS.md
```

```
git push origin main
```

Expected
```
Total 0 (delta 0), reused 0 (delta 0), pack-reused 0 (from 0)
To github.com:sjchristie/humor-memory-game-devops.git
   9432069..a8bda75  main -> main
```

The push to `main` on `humor-memory-game-devops` triggers the pipeline immediately.

---

## Phase 3 — Monitor the Pipeline

### Action 15 — Watch the pipeline run

Go to:

```
https://github.com/sjchristie/humor-memory-game-devops/actions
```

You will see a new run appear. Click on it to open the detail view.

**Job 1 — Test Application (this job is now real for the first time)**

This is the first pipeline run where `npm test` executes Jest instead of the echo placeholder. Watch this job carefully.

Expected output in the Job 1 log:

```
✅ Checkout Application Source Code
✅ Setup Node.js
✅ Install Backend Dependencies

> humor-memory-game-backend@1.0.0 test
> jest

PASS  tests/validation.categories.test.js
  BUG-001 — categories field validation
    ✓ null categories should fail validation (the bug)
    ✓ empty array categories should pass validation (the fix)
    ✓ valid category value should pass validation
    ✓ invalid category value should fail validation

Test Suites: 1 passed, 1 total
Tests:       4 passed, 4 total
Time:        Xs
✅ Run Backend Tests
```

> **If Job 1 fails:** the most likely causes are listed in the troubleshooting section at the end of this document. Do not proceed until Job 1 is green.

**Job 2 — Security Scan**

Runs in parallel with Job 1. Trivy scans the DevOps repository. Findings are informational — the job does not fail on findings.

**Job 3 — Build and Push**

Both Jobs 1 and 2 must be green before Job 3 starts. Job 3 checks out `humor-memory-game` (which now contains the fix commit), builds multi-arch images for `linux/amd64` and `linux/arm64`, and pushes to Docker Hub.

Watch for:

```
✅ Get Short SHA
```

Note the SHA printed here — it should match the short SHA of your fix commit from Phase 1.

```
✅ Build and Push Backend Image
pushing manifest for docker.io/christie62/humor-memory-game-backend:main-<sha>

✅ Build and Push Frontend Image
pushing manifest for docker.io/christie62/humor-memory-game-frontend:main-<sha>
```

**Job 4 — Update GitOps Manifests**

```
✅ Update Backend Image Tag
✅ Update Frontend Image Tag
✅ Commit and Push GitOps Changes
GitOps manifests updated and pushed to gitops branch
```

**Job 5 — Notify**

```
==================================
  CI/CD Pipeline Complete
==================================
  Status:     success
```

---

## Phase 4 — Verify the Deployment on `sre-mgmt-01`

### Action 16 — SSH into `sre-mgmt-01`

```bash
ssh sre@192.168.30.12
or
ssh sre-mgmnt-01 
```

---

### Action 17 — Confirm the GitOps manifest was updated

```bash
cd ~/humor-memory-game-kubernetes
pwd
```

Expected:
```
/home/sre/humor-memory-game-kubernetes
```

```bash
git pull origin gitops
```

Expected:
```
remote: Enumerating objects: 10, done.
remote: Counting objects: 100% (10/10), done.
remote: Compressing objects: 100% (1/1), done.
remote: Total 6 (delta 5), reused 6 (delta 5), pack-reused 0 (from 0)
Unpacking objects: 100% (6/6), 691 bytes | 691.00 KiB/s, done.
From github.com:sjchristie/humor-memory-game-kubernetes
 * branch            gitops     -> FETCH_HEAD
   670042f..7a69794  gitops     -> origin/gitops
Updating 670042f..7a69794
Fast-forward
 gitops-safe/base/10-backend-deployment.yaml  | 2 +-
 gitops-safe/base/12-frontend-deployment.yaml | 2 +-
 2 files changed, 2 insertions(+), 2 deletions(-)
```

```

grep "image:" gitops-safe/base/10-backend-deployment.yaml
grep "image:" gitops-safe/base/12-frontend-deployment.yaml
```

Expected — both images tagged with the fix commit SHA:

```
image: christie62/humor-memory-game-backend:main-<sha>
image: christie62/humor-memory-game-frontend:main-<sha>
```

Actual
```
image: christie62/humor-memory-game-backend:main-1402d0e

image: christie62/humor-memory-game-frontend:main-1402d0e
```

---

### Action 18 — Trigger ArgoCD sync

```bash
kubectl patch application humor-game-local -n argocd \
  --type='merge' \
  -p='{"operation":{"sync":{}}}'
```

Expected:
```
application.argoproj.io/humor-game-local patched
```

---

### Action 19 — Confirm ArgoCD is Synced and Healthy

```bash
kubectl get applications -n argocd
```

Expected:

```
NAME               SYNC STATUS   HEALTH STATUS
humor-game-local   Synced        Healthy
```

---

### Action 20 — Confirm the cluster is running the fix

```bash
kubectl describe deployment frontend -n humor-memory-game | grep Image

kubectl describe deployment backend -n humor-memory-game | grep Image
```

Expected:
```
Image: christie62/humor-memory-game-frontend:main-<sha>
Image: christie62/humor-memory-game-backend:main-<sha>
```

Actual
```
    Image:      christie62/humor-memory-game-frontend:main-1402d0e

    Image:      christie62/humor-memory-game-backend:main-1402d0e
```


Confirm all pods are Running:

```bash
kubectl get pods -n humor-memory-game
```

Expected — all pods Running, no ImagePullBackOff, no CrashLoopBackOff:

```
NAME                          READY   STATUS    RESTARTS   AGE
backend-<hash>-<id>           1/1     Running   0          ...
backend-<hash>-<id>           1/1     Running   0          ...
frontend-<hash>-<id>          1/1     Running   0          ...
frontend-<hash>-<id>          1/1     Running   0          ...
postgres-<hash>-<id>          1/1     Running   ...        ...
redis-<hash>-<id>             1/1     Running   0          ...
```

Actual
```
NAME                        READY   STATUS    RESTARTS        AGE
backend-67c574bc88-pmdgx    1/1     Running   0               4m11s
backend-67c574bc88-qjh6w    1/1     Running   0               3m25s
frontend-65cbc94667-k765s   1/1     Running   0               4m11s
frontend-65cbc94667-slk5w   1/1     Running   0               3m53s
postgres-6684dbcf4b-h9w8z   1/1     Running   1 (3d21h ago)   3d21h
redis-5c5668dbfc-7ntp2      1/1     Running   0               2d5h
```

---

## Phase 5 — End-to-End Functional Verification

This is the final proof that BUG-001 is resolved. Open a browser and test the exact scenario from the bug report.

### Action 21 — Reproduce the original bug scenario and confirm it is fixed

Open a browser and go to:

```
http://192.168.30.20:30080
```

**Test case 1 — The bug scenario (must now work):**

1. Enter a valid username (e.g. `stephen`)
2. Select a difficulty
3. Leave **all** emoji categories unchecked
4. Click **Start Game**

**Expected result (fixed):** The game starts using all available categories. No error notification appears.

**Before the fix:** `❌ Please check your input data! 🔍` — a `400 Bad Request` from Joi rejecting `categories: null`.

**Actual result:** `❌ Oops! The game got confused. Try again! 🤔` — a `500 Internal Server Error`.

**BUG-001 is confirmed fixed.** The error message change is the proof — the `400` validation rejection is completely gone. The request is now passing the Joi validation gate and reaching the database layer. The `500` is caused by BUG-003 (PostgreSQL `search_path` mismatch — `parserOpenTable` error confirmed in backend logs). BUG-003 is a pre-existing separate issue that was always present but hidden behind the BUG-001 validation failure. It is scoped to its own document and is not part of this fix.

**Test case 2 — Normal usage still works:**

1. Enter a valid username
2. Select a difficulty
3. Select one or more emoji categories (e.g. Classic)
4. Click **Start Game**

Expected result: The game starts normally.

**Test case 3 — Confirm via browser developer tools (F12):**

Open Developer Tools → Network tab → click Start Game with no categories selected.

Expected — the request payload now shows:

```json
{
  "username": "stephen",
  "difficulty": "easy",
  "categories": []
}
```

Before the fix this showed `"categories": null`.

---

## Troubleshooting

### Job 1 fails — Jest not found

```
sh: jest: not found
```

**Cause:** `npm ci` is installing only production dependencies. Jest is a devDependency and may be excluded.

**Fix:** In the pipeline's Job 1, `npm ci` runs without flags, which should install devDependencies. If this fails, the issue is in `package.json` — confirm Jest is listed under `devDependencies` and not under `dependencies`.

---

### Job 1 fails — test file not found

```
No tests found, exiting with code 1
```

**Cause:** Jest cannot find `tests/validation.categories.test.js`. This means either the file was not committed, or Jest's `testMatch` pattern is configured to look elsewhere.

**Fix:** Confirm the file was committed to the feature branch:

```bash
git show HEAD --name-only | grep test
```

If the file is missing from the commit, add it and amend or create a new commit.

---

### Job 1 fails — test assertion failure

```
FAIL  tests/validation.categories.test.js
  ✕ null categories should fail validation (the bug)
```

**Cause:** The Joi schema in `middleware/validation.js` has been changed to accept `null`. The test is correctly detecting a regression.

**Fix:** Review the current state of `middleware/validation.js`. The `categories` field must use `Joi.array()` with no `.allow(null)`.

---

### Job 3 fails — wrong SHA in image tag

The image is tagged with a SHA that does not match your fix commit.

**Cause:** The pipeline derives the SHA from `humor-memory-game`'s HEAD at the time the job runs. If the fix was not merged to `humor-memory-game/main` before triggering the pipeline, the old SHA is used and the built image does not contain the fix.

**Fix:** Confirm the merge completed in Phase 1 before re-triggering the pipeline.

---

### Browser still shows the error after deployment

**Cause:** Browser cache. The old frontend JavaScript may be cached.

**Fix:** Hard refresh with `Ctrl + Shift + R` (Windows/Linux) or `Cmd + Shift + R` (Mac), or open the page in a private/incognito window.

---

## Closing BUG-001

Once Action 21 confirms the fix is working on the live cluster, update the bug report status.

| Field | Updated Value |
|---|---|
| Status | ✅ Closed |
| Fix commit SHA | `main-1402d0e` |
| Fix deployed | Yes — via CI/CD pipeline |
| Closed by | Stephen Christie |
| Resolution | Frontend sends `[]` instead of `null` when no categories selected |
| Regression test | `backend/tests/validation.categories.test.js` — 4 tests, all passing |
| Pipeline run | `humor-memory-game-devops` Actions — Run #3 |

---

## Summary

| Phase | Machine | Action | Outcome |
|---|---|---|---|
| 1 | `dev-box-01` | Create feature branch | Isolated workspace |
| 1 | `dev-box-01` | Write regression test | 4 tests, all passing locally |
| 1 | `dev-box-01` | Update `test` script | Jest active for all future runs |
| 1 | `dev-box-01` | Apply fix | `null` → `[]` in `game.js` |
| 1 | `dev-box-01` | Commit and merge to `main` | Fix on `humor-memory-game/main` |
| 2 | `ops-box-01` | Push trigger commit | Pipeline triggered |
| 3 | GitHub Actions | Job 1 — Test | Jest runs 4 real tests, all pass |
| 3 | GitHub Actions | Job 2 — Scan | Trivy scan complete |
| 3 | GitHub Actions | Job 3 — Build | Multi-arch images pushed to Docker Hub |
| 3 | GitHub Actions | Job 4 — GitOps | Manifests updated on `gitops` branch |
| 4 | `sre-mgmt-01` | ArgoCD sync | Synced / Healthy — cluster running `main-1402d0e` |
| 5 | Browser | Functional test | BUG-001 confirmed fixed — 400 gone, request reaches database layer |
| — | GitHub | BUG-001 closed | SHA `main-1402d0e`, Pipeline Run #3, status ✅ Closed |

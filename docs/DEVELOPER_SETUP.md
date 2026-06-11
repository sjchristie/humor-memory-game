# Developer Setup Guide

> **Purpose:** Step-by-step walkthrough for forking the upstream repository, cloning it to your developer VM, and running the full-stack application from source code.
>
> **Time estimate:** ~60 minutes  
> **Complexity:** Intermediate — command-line comfort required

---

## Table of Contents

1. [System Requirements](#1-system-requirements)
2. [Phase 1: GitHub Setup & Forking](#2-phase-1-github-setup--forking)
3. [Phase 2: Clone & Organise](#3-phase-2-clone--organise)
4. [Phase 3: System Software Installation](#4-phase-3-system-software-installation)
5. [Phase 4: Dependency Analysis](#5-phase-4-dependency-analysis)
6. [Phase 5: Project Configuration](#6-phase-5-project-configuration)
7. [Phase 6: Database Setup](#7-phase-6-database-setup)
8. [Phase 7: Application Startup](#8-phase-7-application-startup)
9. [Phase 8: Verification Testing](#9-phase-8-verification-testing)

**Companion documents:**
- [`docs/GIT_WORKFLOW.md`](docs/GIT_WORKFLOW.md) — Two-commit Git strategy: push raw source after cloning, then push the working application after all fixes are verified
- [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md) — Known issues, diagnostic script, and decision tree

---

## 1. System Requirements

| Requirement      | Detail                     |
| :--------------- | :------------------------- |
| Operating System | Arch Linux (or compatible) |
| Disk Space       | 10 GB minimum              |
| RAM              | 2 GB minimum               |
| Internet         | Required for downloads     |
| Access Level     | `sudo` access required     |

---

## 2. Phase 1: GitHub Setup & Forking

### Step 1: Connect to the Developer VM

Start the Developer VM `dev-box-01`, then SSH in:

```bash
ssh dev-box-01
```

---

### Step 2: Install Git and GitHub CLI

```bash
# Update the environment
sudo pacman -Syu

# Install GitHub CLI and git
sudo pacman -S github-cli git

# Verify installation
git --version
gh --version
```

**Expected output:**

```
git version 2.54.0

gh version 2.92.0 (2026-05-18)
https://github.com/cli/cli/releases/tag/v2.93.0
```

**Verification:** ✅ GitHub CLI installed and accessible

---

### Step 3: Authenticate with GitHub

```bash
gh auth login --web
```

**Follow the interactive prompts:**

- **Protocol:** Select `SSH` (more secure than HTTPS)
- **Generate new SSH key:** Select `Y`
- **Passphrase:** Press Enter (leave blank for development)
- **SSH key title:** Enter `Developer Humor Memory Game`
- **Browser opens:** Authorise the device code in your browser

> **Common issue — browser doesn't open:**  
> Copy the device code manually, visit <https://github.com/login/device>, and paste the code.

**Expected output:**

```
✓ Authentication complete.
- gh config set -h github.com git_protocol ssh
✓ Configured git protocol
! Authentication credentials saved in plain text
✓ Uploaded the SSH key to your GitHub account: /home/developer/.ssh/id_ed25519.pub
✓ Logged in as YOUR-USERNAME
```

**Verification:** ✅ Authenticated with GitHub via SSH

---

### Step 4: Fork the Repository

```bash
gh repo fork Osomudeya/DevOps-Home-Lab-2026-2027 --clone=false
```

**Expected output:**

```
✓ Created fork YOUR-USERNAME/DevOps-Home-Lab-2026-2027
```

**Verification:** ✅ Fork appears in your GitHub profile

---

### Step 5: Verify Fork Creation

```bash
gh repo list YOUR-USERNAME | grep -i "DevOps-Home-Lab-2026-2027"
```

**Expected output:**

```
YOUR-USERNAME/DevOps-Home-Lab-2026-2027   Learn DevOps by building a real app...   public, fork   2026-03-07T17:46:44Z
```

**Verification:** ✅ Fork confirmed in GitHub CLI

---

## 3. Phase 2: Clone & Organise

### Step 1: Clone Your Fork to the VM

```bash
gh repo clone YOUR-USERNAME/DevOps-Home-Lab-2026-2027
```

**Expected output:**

```
Cloning into 'DevOps-Home-Lab-2026-2027'...
The authenticity of host 'github.com (4.237.22.38)' can't be established.
ED25519 key fingerprint is: YOUR_KEY
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'github.com' (ED25519) to the list of known hosts.
remote: Enumerating objects: 13643, done.
remote: Total 13643 (delta 0), reused 0 (delta 0), pack-reused 13643 (from 1)
Receiving objects: 100% (13643/13643), 23.92 MiB | 6.26 MiB/s, done.
Resolving deltas: 100% (3627/3627), done.
From github.com:Osomudeya/DevOps-Home-Lab-2026-2027
 * [new branch]      main       -> upstream/main
! Repository Osomudeya/DevOps-Home-Lab-2026-2027 set as the default repository. To learn more about the default repository, run: gh repo set-default --help
```

Verify the repo downloaded correctly:

```bash
ls -la DevOps-Home-Lab-2026-2027
```

**Expected output:**

```
assets/
backend/
frontend/
database/
.gitignore
README.md
... (other files)
```

**Verification:** ✅ Repository cloned successfully with all directories

---

### Step 2: Create Your Development Project Directory

This isolates your development environment from the reference fork.

```bash
mkdir -p ~/humor-memory-game

cd ~/humor-memory-game

pwd
```

**Expected output:**

```
/home/developer/humor-memory-game
```

**Verification:** ✅ Development directory created

---

### Step 3: Copy Only the Required Source Code

> **Important:** This phase copies only source code.  Other files are deliberately excluded.

**Copy backend:**

```bash
rsync -av --exclude='Dockerfile' \
          --exclude='Dockerfile.dev' \
          --exclude='.dockerignore' \
          --exclude='humor-memory-game.code-workspace' \
          ~/DevOps-Home-Lab-2026-2027/backend/ ~/humor-memory-game/backend/

ls ~/humor-memory-game/backend/
```

**Expected output:**

```
server.js
package.json
package-lock.json
models/
routes/
middleware/
utils/
```

**Verification:** ✅ Backend copied

---

**Copy frontend:**

```bash
rsync -av --exclude='Dockerfile' \
          --exclude='Dockerfile.dev' \
          --exclude='.dockerignore' \
          --exclude='node_modules/' \
          --exclude='dist/' \
          ~/DevOps-Home-Lab-2026-2027/frontend/ ~/humor-memory-game/frontend/

ls ~/humor-memory-game/frontend/
```

**Expected output:**

```
src/
public/
package.json
package-lock.json
```

**Verification:** ✅ Frontend copied

---

**Copy database:**

```bash
cp -r ~/DevOps-Home-Lab-2026-2027/database ~/humor-memory-game/database

ls ~/humor-memory-game/database/
```

**Expected output:**

```
combined-init.sql
init.sql
seed.sql
```

**Verification:** ✅ Database schema copied

---

### Step 4: Verify Your Development Structure

```bash
cd ~/humor-memory-game

ls -la
```

**Expected output — should have:**

```
backend/
frontend/
database/
```

**Expected output — should NOT have:**

```
.git/        (will be created fresh in 2.2 GitHub Upload.md)
node_modules/
dist/
.env
```

**Verification:** ✅ Clean project structure, ready for development

---

> ### 🔀 First Git Push — Do This Now
>
> Before making any changes to the code, switch to **[`GIT_WORKFLOW`](GIT_WORKFLOW)** and complete **Commit 1: Initial Source Code Push**.
>
> This captures the raw source code exactly as it came from the fork — before any configuration, patches, or fixes. It becomes your baseline so the final working commit shows a clean diff of everything that changed.
>
> Return here and continue with Phase 3 once the initial push is done.

---

## 4. Phase 3: System Software Installation

### Step 1: Update Arch Linux

```bash
sudo pacman -Syu
```

**Verification:** ✅ System updated

---

### Step 2: Install fnm (Fast Node Manager)

> **Why fnm instead of pacman for Node.js?**
> Arch Linux always installs the latest Node.js version, which can break older code. `fnm` locks the project to its required version, eliminates the need for `sudo` when installing npm packages, and keeps your development environment isolated from system-level software.

```bash
sudo pacman -S fnm

echo 'eval "$(fnm env --use-on-cd)"' >> ~/.bashrc

source ~/.bashrc

fnm --version
```

**Expected output:**

```
fnm 1.39.0
```

**Verification:** ✅ fnm installed

---

### Step 3: Install Node.js v22

```bash
fnm install 22

fnm use 22

node --version

npm --version
```

**Expected output:**

```
# node
v22.22.3

# npm
10.9.8
```

**Verification:** ✅ Node.js v22 installed and active

---

### Step 4: Install PostgreSQL

```bash
sudo pacman -S postgresql

sudo -u postgres initdb -D /var/lib/postgres/data

sudo systemctl start postgresql

sudo systemctl enable postgresql

psql --version
```

**Expected output:**

```
psql (PostgreSQL) 18.4
```

Verify the service is running:

```bash
sudo systemctl status postgresql

# CTRL-C to exit
```

Should show: `active (running)`

**Verification:** ✅ PostgreSQL installed and running

---

### Step 5: Install Redis

```bash
sudo pacman -S redis

sudo systemctl start redis

sudo systemctl enable redis

redis-cli ping
```

**Expected output:**

```
PONG
```

Verify the service is running:

```bash
sudo systemctl status redis

# CTRL-C to exit
```

Should show: `active (running)`

**Verification:** ✅ Redis installed and running

---

### Step 6: Verify All System Software

```bash
node --version

npm --version

psql --version

redis-cli ping

git --version

gh --version
```

**Expected output:**

```bash
# node --version
v22.22.3

# npm --version
10.9.8

# psql --version
psql (PostgreSQL) 18.4

# redis-cli ping
PONG

# git --version
git version 2.54.0

# gh --version
gh version 2.93.0 (2026-05-28)
https://github.com/cli/cli/releases/tag/v2.93.0
```

**Verification:** ✅ All system software installed and accessible

---

## 5. Phase 4: Dependency Analysis

This phase reviews what packages the application needs so you understand the stack before installing dependencies.

### Step 1: Examine Backend Dependencies

```bash
grep -A 15 -E '"dependencies"|"devDependencies"' ~/humor-memory-game/backend/package.json
```

**System-level packages** (managed by pacman):

| Package | Version | Purpose |
| :------ | :------ | :------ |
| `nodejs` | `>=18.0.0` | JavaScript runtime engine |
| `npm` | `>=8.0.0` | Package manager |

**Project-level npm packages** (installed locally via `npm install`):

| Package | Version | Purpose |
| :------ | :------ | :------ |
| `compression` | `^1.7.4` | Reduces response body size |
| `cors` | `^2.8.5` | Enables Cross-Origin Resource Sharing |
| `dotenv` | `^16.3.1` | Loads `.env` variables into `process.env` |
| `express` | `^4.18.2` | Backend routing framework |
| `express-rate-limit` | `^6.10.0` | Rate-limiting middleware |
| `helmet` | `^7.0.0` | Sets security HTTP headers |
| `joi` | `^17.9.2` | Request data validation |
| `morgan` | `^1.10.0` | HTTP request logger |
| `pg` | `^8.11.3` | PostgreSQL client |
| `prom-client` | `^15.1.3` | Prometheus metrics client |
| `redis` | `^4.6.8` | Redis client for caching |
| `uuid` | `^9.0.0` | Generates unique identifiers |
| `eslint` | `^8.57.0` | Code linter |
| `jest` | `^29.6.2` | Test framework |
| `nodemon` | `^3.0.1` | Auto-restarts server on file changes |
| `prettier` | `^3.0.0` | Code formatter |
| `supertest` | `^6.3.3` | HTTP API test library |

**Verification:** ✅ Backend dependencies identified

---

### Step 2: Examine Frontend Dependencies

```bash
grep -A 15 -E '"dependencies"|"devDependencies"' ~/humor-memory-game/frontend/package.json
```

**Frontend dev dependency:**

| Package | Version | Purpose |
| :------ | :------ | :------ |
| `http-server` | `14.1.1` | Lightweight static file server (development only) |

> **Note:** `http-server` is replaced by nginx or Apache in production. It has zero configuration requirements and no production dependencies.

**Verification:** ✅ Frontend dependencies identified

---

## 6. Phase 5: Project Configuration

### Step 1: Identify Required Environment Variables

Scan the source code to see every environment variable the application reads:

```bash
grep -rh --exclude-dir=node_modules "process.env" ~/humor-memory-game/backend/ | sort | uniq
```

---

### Step 2: Create the `.env` File

The `.env` file holds configuration specific to your local environment. It is **never committed to Git** because it contains secrets.

```bash
cat > ~/humor-memory-game/backend/.env << 'EOF'
NODE_ENV=development
PORT=3001
DB_HOST=localhost
DB_PORT=5432
DB_NAME=humor_memory_game
DB_USER=gameuser
DB_PASSWORD=gamepass123
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
JWT_SECRET=dev-secret-key-for-testing
SESSION_SECRET=dev-session-key-for-testing
API_BASE_URL=/api
CORS_ORIGIN=http://localhost:3000
LOG_LEVEL=debug
EOF
```

Verify all 15 variables were written:

```bash
cat ~/humor-memory-game/backend/.env
```

**Verification:** ✅ `.env` file created with all 15 variables

---

### Step 3: Understand Each Configuration Variable

| Variable | Value | Purpose | Security Note |
| :------- | :---- | :------ | :------------ |
| `NODE_ENV` | `development` | Enables verbose logging | — |
| `PORT` | `3001` | Backend listening port | Never expose directly to internet |
| `DB_HOST` | `localhost` | PostgreSQL server address | — |
| `DB_PORT` | `5432` | PostgreSQL standard port | Keep as-is for local dev |
| `DB_NAME` | `humor_memory_game` | Database name | Created in Phase 6 |
| `DB_USER` | `gameuser` | Database user | Limited permissions (least privilege) |
| `DB_PASSWORD` | `gamepass123` | Database password | 🚨 Change in production |
| `REDIS_HOST` | `localhost` | Redis server address | — |
| `REDIS_PORT` | `6379` | Redis standard port | Keep as-is for local dev |
| `REDIS_PASSWORD` | *(blank)* | No password needed locally | 🚨 Required in production |
| `JWT_SECRET` | `dev-secret-key-for-testing` | Signs authentication tokens | 🚨 Use a random string in production |
| `SESSION_SECRET` | `dev-session-key-for-testing` | Signs session cookies | 🚨 Use a random string in production |
| `API_BASE_URL` | `/api` | API route prefix | Frontend uses this to locate the API |
| `CORS_ORIGIN` | `http://localhost:3000` | Allowed frontend origin | Permits frontend to call backend |
| `LOG_LEVEL` | `debug` | Verbose logging | Change to `error` or `info` in production |

> **🔒 Security reminder:** These values are for **local development only**. Never commit `.env` to Git. Production secrets must be injected from a secure secrets manager.

---

## 7. Phase 6: Database Setup

### Step 1: Create PostgreSQL User and Database

```bash
psql -U postgres
```

You should see the prompt: `postgres=#`

Inside psql, run:

```sql
CREATE USER gameuser WITH PASSWORD 'gamepass123';

CREATE DATABASE humor_memory_game OWNER gameuser;

GRANT ALL PRIVILEGES ON DATABASE humor_memory_game TO gameuser;

\q
```

**Expected output:**

```
CREATE ROLE
CREATE DATABASE
GRANT
```

**Verification:** ✅ User and database created

---

### Step 2: Patch the Database Schema

> **⚠️ Known issue:** A `daily_challenges` table is missing from the original schema.

Edit `combined-init.sql` to add the missing table before running it:

```bash
vim ~/humor-memory-game/database/combined-init.sql
```

Add the following in the appropriate sections:

In the `DROP TABLE` block:
```sql
DROP TABLE IF EXISTS daily_challenges CASCADE;
```

In the `CREATE TABLE` block:
```sql
-- Create daily_challenges table
CREATE TABLE daily_challenges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    challenge_date DATE NOT NULL UNIQUE,
    data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

In the `CREATE INDEX` block:
```sql
CREATE INDEX idx_daily_challenges_date ON daily_challenges(challenge_date);
```

---

### Step 3: Load the Database Schema

```bash
cd ~/humor-memory-game

psql -U gameuser -d humor_memory_game -f database/combined-init.sql
```

**Expected output (abbreviated):**

```
CREATE EXTENSION
DROP TABLE
...
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE VIEW
CREATE INDEX
...
psql:database/combined-init.sql:157: NOTICE:  🚀 Ready for some hilarious memory gaming! 🃏✨
psql:database/combined-init.sql:157: NOTICE:  🎮 ========================================
DO
```

**Verification:** ✅ Schema loaded successfully

---

### Step 4: Verify Database Tables

```bash
psql -U gameuser -d humor_memory_game -c "\dt"
```

**Expected output:**

```
                List of tables
 Schema |       Name       | Type  |  Owner
--------+------------------+-------+----------
 public | daily_challenges | table | gameuser
 public | game_matches     | table | gameuser
 public | games            | table | gameuser
 public | users            | table | gameuser
(4 rows)
```

**Verification:** ✅ All four tables present

---

### Step 5: Test Database Connection

```bash
psql -U gameuser -d humor_memory_game -c "SELECT COUNT(*) FROM users;"
```

**Expected output:**

```
 count
-------
     9
(1 row)
```

**Verification:** ✅ Database accessible and seeded

---

## 8. Phase 7: Application Startup

### Step 1: Install Backend Dependencies

```bash
cd ~/humor-memory-game/backend

npm install
```

**Expected output:**

```
added 497 packages in X.XXs
```

Run a security audit:

```bash
npm audit fix --force

npm audit
```

**Expected output:**

```
found 0 vulnerabilities
```

**Verification:** ✅ Backend dependencies installed securely

---

### Step 2: Install Frontend Dependencies

```bash
cd ~/humor-memory-game/frontend

npm install

npm audit fix

npm audit
```

**Expected output:**

```
0 vulnerabilities
```

**Verification:** ✅ Frontend dependencies installed securely

---

### Step 3: Create the `build-local.sh` Script

> **Why this script is needed:** The source code contains a template variable `${API_BASE_URL}` in the frontend HTML. A plain `npm run build` does not replace this placeholder — it must be substituted with the actual local backend address. This script runs the build and performs the substitution.

```bash
cd ~/humor-memory-game/frontend
```

```bash
cat > build-local.sh << 'EOF'
#!/bin/bash
npm run build
sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' dist/index.html
grep -rl '${API_BASE_URL}' dist/ | xargs sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' 2>/dev/null || true
echo "✅ Frontend built and configured for localhost"
EOF
```

Make the file executable
```bash
chmod +x build-local.sh
```
**Verification:** ✅ `build-local.sh` created and executable

---

### Step 4: Build the Frontend

```bash
cd ~/humor-memory-game/frontend

./build-local.sh
```

**Expected output:**

```
✅ Frontend built and configured for localhost
```

Verify the `dist/` directory was created:

```bash
ls -la dist/
```

**Expected output:**

```
index.html
scripts/
styles/
(other files)
```

**Verification:** ✅ Frontend built successfully

---

### Step 5: Start the Backend API — Terminal 1

> **Keep this terminal open. Do NOT close it.**

```bash
cd ~/humor-memory-game/backend

npm start dev
```

**Expected output:**

```
> humor-memory-game-backend@1.0.0 start
> node server.js

🔌 Connecting to database...
🔌 New database client connected
📦 Database client acquired from pool
✅ Database connection test successful
⏰ Current time: Tue Jun 09 2026 17:13:36 GMT+1000 (Australian Eastern Standard Time)
🐘 PostgreSQL version: 18.4
✅ Database connected successfully!
🔗 Connecting to Redis...
🔗 Redis: Connecting...
✅ Redis: Connected and ready!
✅ Redis connected successfully!

🎮 ========================================
🎯 HUMOR MEMORY GAME API SERVER STARTED! 😂
🎮 ========================================
🌐 API Server running on port: 3001
🔧 API Endpoints: /api
💊 Health Check: /health
📊 Metrics Endpoint: /metrics
🚀 Ready to serve game requests!
🎮 ========================================

📊 Initializing metrics with sample data...
✅ Metrics initialized with sample data successfully
📦 Database client acquired from pool
🔌 Database client removed from pool
```

**Verification:** ✅ Backend running and connected to services

---

### Step 6: Start the Frontend Server — Terminal 2

Open a **second terminal**:

> **Keep this terminal open. Do NOT close it.**

```bash
cd ~/humor-memory-game/frontend

python3 -m http.server 3000 --directory dist/
```

**Expected output:**

```
Serving HTTP on 0.0.0.0 port 3000 (http://0.0.0.0:3000/) ...
```

**Verification:** ✅ Frontend server running

---

### Step 7: Open the Game in a Browser

Log on to the VM desktop, open Firefox, and navigate to:

```
http://localhost:3000
```

You should see the Humor Memory Game load in the browser.

> **If you see a "Cannot Connect to Game Server" error**, the most common cause is running `npm run build` instead of `./build-local.sh`. Re-run `./build-local.sh` then hard-refresh the browser with **Ctrl+Shift+R**.
>
> See [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md) for full diagnosis steps.

**Verification:** ✅ Game loads in browser

---

## 9. Phase 8: Verification Testing

All tests must pass before proceeding. Do not skip any step.

---

### Test 1: Backend API Health Check

```bash
curl http://localhost:3001/api/health
```

**Expected output:**

```json
{"status":"healthy","timestamp":"2026-05-28T08:49:00.274Z","services":{"database":"connected","redis":"connected","api":"running"},"version":"1.0.0","environment":"development"}
```

**What this confirms:** Backend running, port 3001 listening, database reachable, API endpoints functional.

❌ If this fails: see **Issue 2** or **Issue 5** in [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md)

**Verification:** ✅ API is responsive

---

### Test 2: Database Connection

```bash
psql -U gameuser -d humor_memory_game -c "SELECT COUNT(*) FROM users;"
```

**Expected output:**

```
 count
-------
     9
(1 row)
```

**What this confirms:** PostgreSQL running, `gameuser` can authenticate, database exists, tables readable.

❌ If this fails: see **Issue 5** in [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md)

**Verification:** ✅ Database accessible

---

### Test 3: Redis Connection

```bash
redis-cli ping
```

**Expected output:**

```
PONG
```

**What this confirms:** Redis running and responding.

❌ If this fails: see **Issue 4** in [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md)

**Verification:** ✅ Cache accessible

---

### Test 4: Daily Challenge Endpoint

```bash
curl -i http://localhost:3001/api/game/daily-challenge
```

**Expected output:** HTTP 200 with a JSON challenge object.

> **⚠️ Known issue:** If the backend logs show `invalid input syntax for type uuid: "daily-challenge"`, an Express route ordering bug exists in `game.js`. The `/daily-challenge` static route must be defined **before** the dynamic `/:gameId` route. See **Issue: Express Route Collision** in [`docs/TROUBLESHOOTING.md`](4%20Archive/docs/TROUBLESHOOTING.md) for the fix.

**Verification:** ✅ Daily challenge endpoint responding

---

### Test 5: Full API Endpoint Map

To list all defined API routes:

```bash
grep -r "router\." ~/humor-memory-game/backend/routes/
```

**Full endpoint reference:**

| File | Path | Method | Purpose |
| :--- | :--- | :----- | :------ |
| `game.js` | `/api/game/start` | POST | Initialise game |
| | `/api/game/match` | POST | Submit match |
| | `/api/game/complete` | POST | Finish game |
| | `/api/game/daily-challenge` | GET | Fetch daily challenge |
| | `/api/game/:gameId` | GET | Get session status |
| `leaderboard.js` | `/api/leaderboard/` | GET | Get top scores |
| | `/api/leaderboard/fresh` | GET | Get fresh leaderboard |
| | `/api/leaderboard/rank/:username` | GET | Get rank for user |
| | `/api/leaderboard/stats` | GET | Global stats |
| | `/api/leaderboard/refresh` | POST | Force refresh leaderboard |
| `scores.js` | `/api/scores/user` | POST | Save/process user score |
| | `/api/scores/:username` | GET | Fetch user score |
| | `/api/scores/:username/history` | GET | Fetch user history |

Example curl tests:

```bash
# Start a game
curl -X POST http://localhost:3001/api/game/start \
  -H "Content-Type: application/json" \
  -d '{"username": "devtester", "difficulty": "easy"}'
```

```bash
# Get leaderboard
curl -i http://localhost:3001/api/leaderboard/
```

**Verification:** ✅ All endpoints reachable

---

> ### 🔀 Second Git Push — Do This Now
>
> All tests pass and the application is fully working. Switch to **[`GIT_WORKFLOW`](GIT_WORKFLOW)** and complete **Commit 2: Working Application Push**.
>
> This commit records every change made from the raw source code to the working state — the patched schema, the route fix, the build script, and anything else that was needed. Running `git diff HEAD~1 HEAD` on your repo will show the complete picture of what had to change.

---

## Final Checklist

**System:**
- ✅ Arch Linux updated
- ✅ fnm installed, Node.js v22 active
- ✅ PostgreSQL installed and running
- ✅ Redis installed and running
- ✅ Git and GitHub CLI installed and authenticated

**Project:**
- ✅ Repository forked from `Osomudeya/DevOps-Home-Lab-2026-2027`
- ✅ Code cloned to VM
- ✅ Development directory created (`~/humor-memory-game`)
- ✅ Only source code copied — backend, frontend, database
- ✅ `node_modules/` and `dist/` NOT copied

**Configuration:**
- ✅ `.env` created with 15 variables
- ✅ PostgreSQL database and user created
- ✅ Database schema loaded (4 tables)
- ✅ `build-local.sh` created and tested

**Running:**
- ✅ Backend starts on port 3001
- ✅ Frontend server starts on port 3000
- ✅ Game accessible in browser

**Testing:**
- ✅ API health check passes
- ✅ Database connection confirmed
- ✅ Redis responds
- ✅ Daily challenge endpoint responds
- ✅ Frontend loads and responds

---

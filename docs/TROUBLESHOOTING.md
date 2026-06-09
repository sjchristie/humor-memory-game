# Troubleshooting Reference

> **Purpose:** Quick-reference guide for diagnosing and resolving common issues encountered during the developer setup process.
>
> Use the [Decision Tree](#decision-tree) for first-pass diagnosis, then jump to the relevant issue section below.

---

## Table of Contents

- [Decision Tree](#decision-tree)
- [Diagnostic Script](#diagnostic-script)
- [Issue 1: Frontend shows `${API_BASE_URL}` literally](#issue-1-frontend-shows-api_base_url-literally)
- [Issue 2: Backend cannot connect to database](#issue-2-backend-cannot-connect-to-database)
- [Issue 3: Cannot connect to game server](#issue-3-cannot-connect-to-game-server)
- [Issue 4: Redis connection error](#issue-4-redis-connection-error)
- [Issue 5: PostgreSQL connection failed](#issue-5-postgresql-connection-failed)
- [Issue 6: Port already in use](#issue-6-port-already-in-use)
- [Issue 7: npm install fails](#issue-7-npm-install-fails)
- [Issue 8: Git authentication fails](#issue-8-git-authentication-fails)
- [Issue 9: Express route collision — daily-challenge 500 error](#issue-9-express-route-collision--daily-challenge-500-error)

---

## Decision Tree

```
Is the game showing in the browser?
├─ YES → Check "Known Issues" below if something doesn't work
└─ NO
   └─ Is backend running? (Check Terminal 1)
      ├─ NO → cd ~/humor-memory-game/backend && npm start
      └─ YES
         └─ Is frontend running? (Check Terminal 2)
            ├─ NO → cd ~/humor-memory-game/frontend && python3 -m http.server 3000 --directory dist/
            └─ YES
               └─ Run: curl http://localhost:3001/api/health
                  ├─ FAILS → See Issue 2 or Issue 5 below
                  └─ WORKS → Open browser console (F12) and check for errors
```

---

## Diagnostic Script

Create and run this script for a quick automated health check:

```bash
cat > ~/humor-memory-game/diagnose.sh << 'EOF'
#!/bin/bash
echo "=== 🌲 DevOps Home Lab Diagnostic Scan ==="

# 1. Check Backend Port
if ! lsof -i :3001 > /dev/null; then
    echo "❌ [BACKEND DOWN] Run: cd ~/humor-memory-game/backend && npm start"
    exit 1
fi

# 2. Check Frontend Port
if ! lsof -i :3000 > /dev/null; then
    echo "❌ [FRONTEND DOWN] Run: cd ~/humor-memory-game/frontend && python3 -m http.server 3000 --directory dist/"
    exit 1
fi

# 3. Test API health endpoint
echo "🔄 Testing backend API health endpoint..."
if curl -s --max-time 2 http://localhost:3001/api/health | grep -q "healthy"; then
    echo "✅ [INFRASTRUCTURE OK] Everything is running. Open browser and press F12 to inspect frontend logs."
else
    echo "❌ [API FAILURE] Backend is up but refusing data routes. Check your .env and database connection."
fi
EOF

chmod +x ~/humor-memory-game/diagnose.sh
```

Run it:

```bash
~/humor-memory-game/diagnose.sh
```

**Expected output:**

```
=== 🌲 DevOps Home Lab Diagnostic Scan ===
🔄 Testing backend API health endpoint...
✅ [INFRASTRUCTURE OK] Everything is running. Open browser and press F12 to inspect frontend logs.
```

---

## Issue 1: Frontend shows `${API_BASE_URL}` literally

**Symptom:**

```
window.API_BASE_URL = '${API_BASE_URL}'  (not replaced with URL)
```

The browser HTTP server log also shows:

```
"GET /$%7BAPI_BASE_URL%7D/health HTTP/1.1" 404
```

**Root cause:** You ran `npm run build` instead of `./build-local.sh`. The plain build does not substitute the `${API_BASE_URL}` placeholder with the actual backend address.

**Resolution:**

```bash
cd ~/humor-memory-game/frontend

./build-local.sh
```

Then hard-refresh the browser with **Ctrl+Shift+R** to bypass cache.

**Prevention:** Always use `./build-local.sh` for local development, never `npm run build` alone.

---

## Issue 2: Backend cannot connect to database

**Symptom:**

```
getaddrinfo ENOTFOUND postgres
error: could not translate host name "postgres" to address
```

**Root cause:** `.env` has `DB_HOST=postgres` instead of `DB_HOST=localhost`. The hostname `postgres` is a service name used in other deployment environments. For local development, `DB_HOST` must be set to `localhost`.

**Resolution:**

```bash
# Check current value
grep DB_HOST ~/humor-memory-game/backend/.env
# Should show: DB_HOST=localhost

# If incorrect, edit the file
nano ~/humor-memory-game/backend/.env
# Change: DB_HOST=postgres  →  DB_HOST=localhost
# Save: Ctrl+X, Y, Enter

# Restart the backend (Terminal 1)
# Press Ctrl+C, then:
npm start
```

---

## Issue 3: Cannot connect to game server

**Symptom:** Browser shows "Cannot Connect to Game Server" error.

**Root cause:** Backend or frontend server process is not running.

**Resolution:**

Check both processes are still active:

```bash
# Is the backend running?
ps aux | grep "npm start" | grep -v grep

# Is the frontend running?
ps aux | grep "http.server" | grep -v grep
```

If either is missing, restart it:

```bash
# Terminal 1 — backend
cd ~/humor-memory-game/backend && npm start

# Terminal 2 — frontend
cd ~/humor-memory-game/frontend && python3 -m http.server 3000 --directory dist/
```

**Common cause:** A terminal window was accidentally closed.

---

## Issue 4: Redis connection error

**Symptom:**

```
ERR AUTH <password> called without any password configured
```

**Root cause:** The `.env` file has a value set for `REDIS_PASSWORD`, but your local Redis instance is running without password authentication.

**Resolution:**

```bash
# Step 1: Ensure REDIS_PASSWORD is blank in .env
grep REDIS_PASSWORD ~/humor-memory-game/backend/.env
# Should show: REDIS_PASSWORD=

# Step 2: Clear any password set in the running Redis instance
redis-cli CONFIG SET requirepass ""
redis-cli CONFIG REWRITE

# Step 3: Verify Redis responds
redis-cli ping
# Expected: PONG

# Step 4: Restart the backend (Terminal 1)
# Press Ctrl+C, then:
npm start
```

---

## Issue 5: PostgreSQL connection failed

**Symptom:**

```
getaddrinfo ENOTFOUND postgres
error: role "gameuser" does not exist
psql: error: connection refused
```

**Root cause:** The PostgreSQL service is not running, or the database user and schema have not been created yet.

**Resolution:**

```bash
# Step 1: Check and start the service
sudo systemctl status postgresql

# If not running:
sudo systemctl start postgresql

sudo systemctl enable postgresql

# Step 2: Check that the user and database exist
psql -U postgres -c "SELECT usename FROM pg_user WHERE usename='gameuser';"

psql -U postgres -c "\l"

# Step 3: If missing, recreate them
psql -U postgres << 'SQL'
CREATE USER gameuser WITH PASSWORD 'gamepass123';
CREATE DATABASE humor_memory_game OWNER gameuser;
GRANT ALL PRIVILEGES ON DATABASE humor_memory_game TO gameuser;
SQL

# Step 4: Reload the schema
psql -U gameuser -d humor_memory_game -f database/combined-init.sql
```

---

## Issue 6: Port already in use

**Symptom:**

```
listen EADDRINUSE :::3001
```

**Root cause:** Another process is already listening on port 3000 or 3001.

**Resolution:**

```bash
# Find what is holding the port
lsof -i :3001

lsof -i :3000

# Note the PID from the output, then kill it
kill -9 <PID>

# Restart the application
cd ~/humor-memory-game/backend && npm start
```

**Prevention:** Always stop services with **Ctrl+C** before closing a terminal. Closing the window abruptly without Ctrl+C can leave the port binding active.

---

## Issue 7: npm install fails

**Symptom:**

```
npm ERR! conflicting peerDependencies
npm ERR! peer dep missing
```

**Root cause:** Dependency tree conflicts or corruption in an existing `node_modules/` directory.

**Resolution:**

```bash
# Navigate to the affected directory
cd ~/humor-memory-game/backend
# OR
cd ~/humor-memory-game/frontend

# Clean the cache and remove broken dependencies
npm cache clean --force

rm -rf node_modules package-lock.json

# Reinstall using legacy peer resolution
npm install --legacy-peer-deps

npm audit fix

npm audit
```

---

## Issue 8: Git authentication fails

**Symptom:**

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
Permission denied (publickey)
```

**Root cause:** GitHub authentication token or SSH key has expired or was not set up on this machine.

**Resolution:**

```bash
# Step 1: Re-authenticate
gh auth login --web
```

Follow the prompts:
- **Protocol:** `SSH`
- **Generate SSH key:** `Y`
- **Passphrase:** Leave blank, press Enter
- **Title:** `Developer Humor Memory Game`
- **Authorise:** Complete the browser step

```bash
# Step 2: Verify authentication
gh auth status
# Expected: Authenticated as YOUR-USERNAME
```

---

## Issue 9: Express route collision — daily-challenge 500 error

**How this was discovered:** After starting the backend with `npm start`, running the following command returned a 500 error:

```bash
curl -i http://localhost:3001/api/game/daily-challenge
```

The backend terminal showed:

```
❌ Database query error: invalid input syntax for type uuid: "daily-challenge"
Query: SELECT * FROM games WHERE id = $1
Params: [ 'daily-challenge' ]

❌ Error getting game details: error: invalid input syntax for type uuid: "daily-challenge"
    at /home/developer/humor-memory-game/backend/node_modules/pg-pool/index.js:45:11
    at process.processTicksAndRejections (node:internal/process/task_queues:103:5)
    at async HumorGameDatabase.query (/home/developer/humor-memory-game/backend/models/database.js:76:24)
    at async /home/developer/humor-memory-game/backend/routes/game.js:434:26 {
```

The error message referenced `game.js` and showed `"daily-challenge"` being passed as a UUID to the database. This indicated the wrong route was handling the request.

**How the fix was identified:** Running the following command revealed both the wrong route order and a duplicate `/:gameId` route definition:

```bash
grep -n "router.get" ~/humor-memory-game/backend/routes/game.js
```

**Expected output showing the problem:**

```
425:router.get('/:gameId', async (req, res) => {
485:router.get('/daily-challenge', async (req, res) => {
532:router.get('/:gameId', async (req, res) => {
```

This confirmed two problems:
1. `/:gameId` was defined **before** `/daily-challenge` — Express was treating `"daily-challenge"` as a UUID parameter
2. `/:gameId` was defined **twice** — the duplicate needed to be removed

**Root cause:** In Express, when the same route path pattern is defined more than once, the first definition wins. If the dynamic `/:gameId` route is defined before `/daily-challenge`, Express treats `"daily-challenge"` as a UUID parameter, which fails database validation.

**Fix:** Open `backend/routes/game.js` and ensure:
1. There is only **one** `/:gameId` route block in the file — delete the first duplicate
2. The `/daily-challenge` static route is defined **before** the `/:gameId` dynamic route

```bash
vim ~/humor-memory-game/backend/routes/game.js
```

**Step 1 — Find and delete the first `/:gameId` block:**

In vim, search for the first occurrence of `/:gameId`:

```
/router.get('\/:gameId'
```

Press `Enter` to jump to it. Then:

- Press **`V`** (capital V) to enter Visual Line Mode
- Use `j` to select downward through all lines of the entire `/:gameId` block including its closing `});`
- Press **`d`** to delete the selected lines

**Step 2 — Verify `/daily-challenge` is now above `/:gameId`:**

Without leaving vim, search to confirm the order:

```
/router.get
```

Press `n` to step through each `router.get` occurrence and confirm `/daily-challenge` appears before `/:gameId`.

**Step 3 — Save and exit:**

```
:wq
```

**Step 4 — Verify the correct order outside vim:**

```bash
grep -n "router.get" ~/humor-memory-game/backend/routes/game.js
```

**Expected output after fix:**

```
425:router.get('/daily-challenge', async (req, res) => {
472:router.get('/:gameId', async (req, res) => {
```

**Verification:** ✅ `/daily-challenge` appears before `/:gameId`, one instance of each

The correct order:

```javascript
// ========================================
// GET DAILY CHALLENGE
// ========================================
router.get('/daily-challenge', async (req, res) => {
    try {
        const cachedChallenge = await redisCache.get('daily_challenge');
        if (cachedChallenge) {
            return res.json({ success: true, challenge: cachedChallenge, message: "Today's challenge is ready! 🌟" });
        }
        const challenge = GameDataGenerator.generateDailyChallenge();
        const now = new Date();
        const endOfDay = new Date(now);
        endOfDay.setHours(23, 59, 59, 999);
        const ttl = Math.floor((endOfDay - now) / 1000);
        await redisCache.set('daily_challenge', challenge, ttl);
        res.json({ success: true, challenge, message: 'Fresh daily challenge generated! 🎯' });
    } catch (error) {
        console.error('❌ Error getting daily challenge:', error);
        res.status(500).json({ success: false, error: 'Failed to get daily challenge' });
    }
});

// ========================================
// GET GAME DETAILS
// ========================================
router.get('/:gameId', async (req, res) => {
    const { gameId } = req.params;

    // Guard: prevent "daily-challenge" string reaching the database
    if (gameId === 'daily-challenge') {
        return res.status(404).json({ success: false, message: "Daily challenge not found." });
    }

    try {
        let gameSession = await redisCache.getCachedGameSession(gameId);
        if (!gameSession) {
            const gameRecord = await database.query('SELECT * FROM games WHERE id = $1', [gameId]);
            if (gameRecord.rows.length === 0) {
                return res.status(404).json({ success: false, error: 'Game not found' });
            }
            const game = gameRecord.rows[0];
            gameSession = {
                gameId: game.id,
                username: game.username,
                difficulty: game.difficulty_level,
                score: game.score,
                moves: game.moves,
                isCompleted: game.game_completed,
                startTime: game.started_at,
                completedAt: game.completed_at,
            };
        }
        res.json({ success: true, game: gameSession });
    } catch (error) {
        console.error('❌ Error getting game details:', error);
        res.status(500).json({ success: false, error: 'Failed to get game details' });
    }
});
```

After saving:

```bash
# Restart the backend
pkill -9 node

npm start

# Verify the fix
curl -i http://localhost:3001/api/game/daily-challenge
# Expected: HTTP 200 with JSON challenge object
```

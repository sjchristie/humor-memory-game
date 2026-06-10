# Humor Memory Game — Developer Reference

> Scope: Application design, code structure, API, data flow, and local development.
> Infrastructure, deployment, and CI/CD are intentionally excluded — these are covered in separate phase documentation.

---

## 1. Application Overview

Humor Memory Game is a full-stack web application built as a card-matching memory game using emoji pairs. Players flip cards to find matching emoji pairs, earning points based on speed and accuracy.

The application follows a separated frontend/backend architecture:

- **Frontend** — Vanilla HTML, CSS, and JavaScript served by Nginx. No framework, no bundler. The build step copies source files into a `dist/` directory.
- **Backend** — Node.js with Express. REST API only; it serves no HTML.
- **Database** — PostgreSQL 15. Stores users, game sessions, and individual card matches.
- **Cache** — Redis. Holds active game sessions in memory during play and caches the leaderboard.

---

## 2. Repository Structure

```
DevOps-Home-Lab-2026-2027-main/
├── backend/
│   ├── server.js               # Express app entry point
│   ├── Dockerfile
│   ├── package.json
│   ├── middleware/
│   │   ├── validation.js       # Joi request validation schemas
│   │   └── metrics.js          # Prometheus metrics middleware
│   ├── models/
│   │   └── database.js         # PostgreSQL connection pool + query methods
│   ├── routes/
│   │   ├── game.js             # /api/game/* endpoints
│   │   ├── scores.js           # /api/scores/* endpoints
│   │   └── leaderboard.js      # /api/leaderboard/* endpoints
│   ├── utils/
│   │   ├── gameData.js         # Emoji data, card generation, scoring logic
│   │   └── redis.js            # Redis client + caching helpers
│   └── tests/
│       ├── api.test.js
│       └── health.test.js
├── frontend/
│   ├── src/                    # Active development source
│   │   ├── index.html          # Single page application shell
│   │   ├── scripts/
│   │   │   └── game.js         # All frontend logic (~1000 lines)
│   │   ├── styles/
│   │   │   └── main.css
│   │   └── config.js           # Runtime API base URL configuration
│   ├── dist/                   # Build output (generated, not edited directly)
│   ├── public/                 # Static assets copied into dist on build
│   │   ├── favicon.ico
│   │   ├── health.html
│   │   └── sw.js
│   ├── nginx.conf              # Nginx config — serves dist/ and proxies /api/
│   ├── Dockerfile
│   └── package.json
├── database/
│   ├── combined-init.sql       # Schema creation + seed data (runs on first start)
│   ├── init.sql                # Schema only
│   └── seed.sql                # Seed data only
└── env/
    └── env.example             # Master reference for all environment variables
```

---

## 3. Frontend — Design and Build

### Technology

The frontend is plain HTML, CSS, and JavaScript — no React, no Vue, no TypeScript, no bundler (Webpack/Vite). All logic lives in a single file: `frontend/src/scripts/game.js`.

### Build Process

```bash
cd frontend
npm run build
```

What `npm run build` does (from `package.json`):

```json
"build": "npm run copy-assets",
"copy-assets": "mkdir -p dist && cp -r public/* dist/ && cp -r src/* dist/"
```

It copies everything from `public/` and `src/` into `dist/`. The `dist/` directory is what Nginx serves at runtime. **You edit files in `src/`, never in `dist/` directly.**

### Local Development

```bash
cd frontend
npm run dev
# Starts: python3 -m http.server 3000 --directory src
```

This serves `src/` directly on port 3000. The browser reloads manually — there is no hot reload.

> **Note:** When running the frontend locally via `npm run dev`, you must also have the backend running on port 3001, and Nginx is not involved. The frontend falls back to calling `API_BASE = '/api'` which will only work if a reverse proxy is handling the routing. For direct local development, see the full local setup in section 8.

### Runtime API Configuration (`frontend/src/config.js`)

The frontend reads `window.API_BASE_URL` at startup. At runtime, Nginx uses `envsubst` to inject this value into `index.html` before serving (the value is set via the `FRONTEND_API_URL` environment variable in the deployment environment). The `game.js` file waits for this variable before initialising:

```javascript
function waitForConfig() {
  return new Promise((resolve) => {
    if (window.CONFIG_READY && window.API_BASE_URL) {
      resolve();
    } else {
      const checkConfig = () => {
        if (window.CONFIG_READY && window.API_BASE_URL) resolve();
        else setTimeout(checkConfig, 10);
      };
      checkConfig();
    }
  });
}
```

Once the config is ready, `API_BASE` is set and all API calls use it as the prefix.

### Frontend State

All game state is held in a single global object:

```javascript
let gameState = {
  currentUser: null,      // { id, username, displayName }
  currentGame: null,      // response from /api/game/start
  cards: [],              // array of card objects from the server
  flippedCards: [],       // currently face-up, unmatched cards (max 2)
  matchedPairs: 0,
  totalPairs: 0,
  score: 0,
  moves: 0,
  startTime: null,        // timestamp when game began
  gameTimer: null,        // interval reference for the on-screen timer
  isGameActive: false,
  difficulty: 'easy',
};
```

### Frontend Initialisation Sequence

```
DOMContentLoaded
  └── waitForConfig()           — wait for window.API_BASE_URL
        └── checkAPIConnection()  — GET /api/health
              └── hideLoadingScreen()
                    └── initializeGame()
                          ├── setupEventListeners()
                          ├── setupTabNavigation()
                          └── loadLeaderboard()
```

---

## 4. Backend — Design and Structure

### Entry Point (`backend/server.js`)

The Express application is configured in `server.js`. On startup it:

1. Loads environment variables via `dotenv`
2. Applies middleware in order: Helmet (security headers), CORS, compression, Morgan (logging), rate limiter, Prometheus metrics, body parser
3. Mounts routes: `/api/game`, `/api/scores`, `/api/leaderboard`
4. Connects to PostgreSQL and Redis before the HTTP server starts listening
5. Registers SIGTERM/SIGINT handlers for graceful shutdown

**Port:** 3001 (configurable via `PORT` env var)

### Middleware Stack (applied to every request)

| Middleware | Purpose |
|---|---|
| `helmet` | Sets HTTP security headers |
| `cors` | Restricts origins; configurable via `CORS_ORIGIN` |
| `compression` | Gzip responses |
| `morgan` | Request logging (`dev` format locally, `combined` in production) |
| `express-rate-limit` | 100 requests per 15-minute window on all `/api/*` routes |
| `metricsMiddleware` | Prometheus request counters and histograms |
| `express.json` | Parses JSON request bodies (10mb limit) |

Route-level middleware applied per route group:

| Middleware | Applied to |
|---|---|
| `sanitizeInput` | All `/api/game/*` routes |
| `validateJsonContent` | All `/api/game/*` routes |
| `validateGameStart` | `POST /api/game/start` |
| `validateCardMatch` | `POST /api/game/match` |
| `validateGameComplete` | `POST /api/game/complete` |

### Database Layer (`backend/models/database.js`)

Uses a `pg` connection pool (max 20 connections). Exported as a singleton `HumorGameDatabase` instance. All queries include retry logic (3 attempts, 1 second delay).

**Key methods:**

| Method | SQL operation |
|---|---|
| `createOrGetUser(username)` | `SELECT` by username, `INSERT` if not found |
| `createGame(userId, username, difficulty)` | `INSERT INTO games` |
| `completeGame(gameId, score, moves, timeElapsed, cardsMatched)` | `UPDATE games SET game_completed = true` — triggers `update_user_stats` |
| `recordMatch(gameId, card1Id, card2Id, matchTime, points, bonus)` | `INSERT INTO game_matches` |
| `getUserStats(username)` | `SELECT` from `users` with computed `rank` subquery |
| `getLeaderboard(limit)` | `SELECT` from `users` with `ROW_NUMBER()` window function |
| `query(text, params)` | Raw parameterised query with retry wrapper |

### Redis Layer (`backend/utils/redis.js`)

Used for two purposes: active game session caching during play, and leaderboard caching.

**Key operations:**

| Method | Key pattern | TTL |
|---|---|---|
| `cacheGameSession(gameId, data)` | `game:session:<gameId>` | 30 minutes |
| `getCachedGameSession(gameId)` | `game:session:<gameId>` | — |
| `incrementDailyGames()` | `analytics:daily:games:<date>` | 24 hours |
| `trackUserActivity(username, event)` | `user:activity:<username>` | — |
| `del(key)` | arbitrary | — |

When a game is completed, the route handler deletes `user:stats:<username>` and `leaderboard:top` to force a fresh read on the next request.

### Card and Scoring Logic (`backend/utils/gameData.js`)

All game content and scoring calculations live here. The `GameDataGenerator` class is used by the game routes.

**Card pool:** 30 unique emoji entries across 21 categories (classic, food, space, fantasy, tech, love, thoughtful, silly, sassy, spooky, nature, music, cool, celebration, mystery, action, adventure, hot, energy, luxury, achievement).

**Card generation (`generateCardSet`):**
1. Filter emoji pool by requested categories (falls back to full pool if too few)
2. Select `pairCount` emojis at random (e.g. 8 for easy)
3. Duplicate each into two card objects with IDs `<emojiId>_1` and `<emojiId>_2`, sharing a `pairId`
4. Shuffle with Fisher-Yates and assign sequential `position` values

**Difficulty configuration:**

| Difficulty | Cards (pairs) | Points/match | Speed bonus threshold | Bonus points | Grid |
|---|---|---|---|---|---|
| easy | 16 (8) | 10 | 10 seconds | 5 | 4×4 |
| medium | 20 (10) | 15 | 8 seconds | 8 | 5×4 |
| hard | 24 (12) | 20 | 6 seconds | 12 | 6×4 |
| expert | 30 (15) | 25 | 5 seconds | 15 | 6×5 |

**Score calculation bonuses:**
- Perfect game (zero wrong moves): +50 points
- Speed bonus multiplier: ×1.5 for fast completions
- Streak bonus: +3 points per consecutive match, capped at 30

---

## 5. Database

### Initialisation

The database schema is defined in `database/combined-init.sql`. When deploying to a fresh PostgreSQL instance, this file must be run once to create tables, indexes, views, triggers, and seed data. It drops and recreates all tables on each clean run.

For a local PostgreSQL instance, run it manually:

```bash
psql -U gameuser -d humor_memory_game -f database/combined-init.sql
```

The `uuid-ossp` extension is enabled at the top of the script to support UUID primary key generation:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

---

### Tables

#### `users`

Stores one record per player. Created automatically on first game start via `database.createOrGetUser()`.

```sql
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username      VARCHAR(50)  UNIQUE NOT NULL,
    email         VARCHAR(100) UNIQUE,
    display_name  VARCHAR(100),
    created_at    TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    last_played   TIMESTAMPTZ,
    total_games   INTEGER      DEFAULT 0,
    total_score   INTEGER      DEFAULT 0,
    best_score    INTEGER      DEFAULT 0,
    best_time     INTEGER,      -- milliseconds; NULL until first completed game
    is_active     BOOLEAN      DEFAULT true
);
```

| Column | Notes |
|---|---|
| `id` | UUID, generated by `uuid_generate_v4()` — used as FK in `games` |
| `username` | Unique identifier; alphanumeric only (enforced by the API validation layer) |
| `email` | Optional; not collected by the current frontend |
| `display_name` | Defaults to `username` when created via `createOrGetUser()` |
| `total_games` | Incremented by the `update_user_stats` trigger on game completion |
| `total_score` | Cumulative score across all completed games; updated by trigger |
| `best_score` | Highest single-game score; updated by trigger using `GREATEST()` |
| `best_time` | Fastest completion time in ms; updated by trigger — lower is better |
| `is_active` | Used to filter the `leaderboard` view; defaults true |

**How application code writes to this table:**

- `createOrGetUser(username)` — `INSERT` on first game, `SELECT` on return visits. Email and display name are not set by the frontend.
- `updateLastPlayed(userId)` — `UPDATE users SET last_played = CURRENT_TIMESTAMP` — called at game start.
- `total_games`, `total_score`, `best_score`, `best_time`, `updated_at` — **never written directly by application code**. All updated exclusively by the database trigger (see Trigger section below).

---

#### `games`

One record per game session. Created when a game starts; updated when it completes.

```sql
CREATE TABLE games (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID REFERENCES users(id) ON DELETE CASCADE,
    username         VARCHAR(50)  NOT NULL,   -- denormalised for query speed
    score            INTEGER      NOT NULL DEFAULT 0,
    moves            INTEGER      NOT NULL DEFAULT 0,
    time_elapsed     INTEGER      NOT NULL DEFAULT 0,  -- milliseconds
    cards_matched    INTEGER      NOT NULL DEFAULT 0,
    difficulty_level VARCHAR(20)  DEFAULT 'easy',
    game_completed   BOOLEAN      DEFAULT false,
    started_at       TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    completed_at     TIMESTAMPTZ,
    game_data        JSONB        -- card positions, categories, metadata
);
```

| Column | Notes |
|---|---|
| `user_id` | FK to `users.id`; `ON DELETE CASCADE` removes games if user is deleted |
| `username` | Denormalised copy — avoids a join on leaderboard and history queries |
| `score` | Final calculated score written by `completeGame()` |
| `moves` | Total card flip pairs attempted (matched + unmatched) |
| `time_elapsed` | Total game duration in milliseconds |
| `cards_matched` | Number of successful pairs found |
| `difficulty_level` | `easy`, `medium`, `hard`, or `expert` |
| `game_completed` | The field the trigger watches — changing this from `false` to `true` fires `update_user_stats` |
| `game_data` | JSONB blob stored at game creation: `{ difficulty, categories, cards, startTime }` |

**How application code writes to this table:**

- `createGame(userId, username, difficulty)` — `INSERT` with `game_completed = false`, `time_elapsed = 0`, `cards_matched = 0`. Called from `POST /api/game/start`.
- `completeGame(gameId, score, moves, timeElapsed, cardsMatched)` — `UPDATE` setting all final values and `game_completed = true`. Called from `POST /api/game/complete`. This `UPDATE` is what fires the trigger.
- Individual match records are **not** written to `games` — they go to `game_matches` (see below).

---

#### `game_matches`

One record per successful card pair match within a game. Written in real time as the player makes matches.

```sql
CREATE TABLE game_matches (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id       UUID REFERENCES games(id) ON DELETE CASCADE,
    card1_id      VARCHAR(50)  NOT NULL,   -- e.g. "pizza_1"
    card2_id      VARCHAR(50)  NOT NULL,   -- e.g. "pizza_2"
    match_time    INTEGER      NOT NULL,   -- ms elapsed from game start when match was made
    points_earned INTEGER      DEFAULT 10,
    bonus_points  INTEGER      DEFAULT 0,
    created_at    TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP
);
```

| Column | Notes |
|---|---|
| `game_id` | FK to `games.id`; cascades on delete |
| `card1_id` / `card2_id` | String IDs in the format `<emojiId>_1` / `<emojiId>_2` — e.g. `pizza_1`, `pizza_2` |
| `match_time` | Milliseconds from game start — used to calculate whether a speed bonus applies |
| `points_earned` | Base points for the match (10 for easy, up to 25 for expert) |
| `bonus_points` | Speed bonus if `match_time < bonusTimeThreshold` for the difficulty |

**How application code writes to this table:**

- `recordMatch(gameId, card1Id, card2Id, matchTime, points, bonusPoints)` — `INSERT INTO game_matches`. Called from `POST /api/game/match` only when the server confirms a valid match. Failed attempts (mismatches) are **not** recorded here.

---

### View — `leaderboard`

A pre-computed view used by `getLeaderboard()`. Filters to active users who have completed at least one game, computes `avg_score` and a `rank` using a window function.

```sql
CREATE OR REPLACE VIEW leaderboard AS
SELECT
    u.username,
    u.display_name,
    u.total_games,
    u.total_score,
    u.best_score,
    u.best_time,
    u.last_played,
    CASE
        WHEN u.total_games > 0 THEN ROUND(u.total_score::decimal / u.total_games, 2)
        ELSE 0
    END AS avg_score,
    ROW_NUMBER() OVER (ORDER BY u.best_score DESC, u.best_time ASC) AS rank
FROM users u
WHERE u.is_active = true AND u.total_games > 0
ORDER BY u.best_score DESC, u.best_time ASC;
```

Ranking is determined by `best_score DESC` first, then `best_time ASC` as a tiebreaker (higher score wins; if equal, faster time wins).

---

### Trigger — `update_user_stats`

This trigger is the mechanism that keeps the `users` aggregate columns (`total_games`, `total_score`, `best_score`, `best_time`) up to date. Application code never increments these columns directly.

```sql
CREATE OR REPLACE FUNCTION update_user_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.game_completed = true AND (OLD.game_completed = false OR OLD.game_completed IS NULL) THEN
        UPDATE users
        SET
            total_games = total_games + 1,
            total_score = total_score + NEW.score,
            best_score  = GREATEST(best_score, NEW.score),
            best_time   = CASE
                              WHEN best_time IS NULL OR NEW.time_elapsed < best_time
                              THEN NEW.time_elapsed
                              ELSE best_time
                          END,
            last_played = NEW.completed_at,
            updated_at  = CURRENT_TIMESTAMP
        WHERE id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_stats
    AFTER UPDATE ON games
    FOR EACH ROW
    EXECUTE FUNCTION update_user_stats();
```

The trigger fires on every `UPDATE` to `games` but only acts when `game_completed` transitions from `false` to `true`. This means partial updates (e.g. updating `score` mid-game) do not affect user stats.

---

### Indexes

All indexes defined in `combined-init.sql`:

| Index | Table | Column(s) | Purpose |
|---|---|---|---|
| `idx_users_username` | `users` | `username` | Fast lookup in `createOrGetUser()` |
| `idx_users_best_score` | `users` | `best_score DESC` | Leaderboard ordering |
| `idx_users_last_played` | `users` | `last_played` | Activity filtering |
| `idx_games_user_id` | `games` | `user_id` | Join from `users` → `games` |
| `idx_games_score` | `games` | `score DESC` | Score-based queries |
| `idx_games_completed_at` | `games` | `completed_at` | Time-range filtering |
| `idx_game_matches_game_id` | `game_matches` | `game_id` | Join from `games` → `game_matches` |

---

### Permissions

Granted at the end of `combined-init.sql` to the `gameuser` role used by the connection pool:

```sql
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO gameuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO gameuser;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO gameuser;
```

---

### Connection Pool (`backend/models/database.js`)

The application uses the `pg` library's `Pool` class — not a single client. Configuration:

| Setting | Value | Source |
|---|---|---|
| `host` | `DB_HOST` env var | Service DNS name (K8s) or `localhost` for local dev |
| `port` | `DB_PORT` env var | 5432 |
| `database` | `DB_NAME` env var | `humor_memory_game` |
| `user` | `DB_USER` env var | `gameuser` |
| `password` | `DB_PASSWORD` env var | No default — fails if not set |
| `max` | `DB_MAX_CONNECTIONS` env var | 20 |
| `idleTimeoutMillis` | `DB_IDLE_TIMEOUT` env var | 30,000 ms |
| `connectionTimeoutMillis` | `DB_CONNECTION_TIMEOUT` env var | 2,000 ms |

SSL is enabled in production (`NODE_ENV=production`) with `rejectUnauthorized: false`. Disabled for local development.

All queries go through the `query(text, params)` method which wraps execution in a retry loop — up to 3 attempts with a 1-second delay between failures. Slow queries (over 100ms) are logged as warnings.

---

## 6. API Reference

All endpoints are prefixed with `/api`. The frontend calls these via the `apiRequest()` helper which prepends `API_BASE`.

### Health

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Checks PostgreSQL and Redis connectivity |
| GET | `/api/health` | Same check, used by the Nginx proxy |

**Response (`/health`):**
```json
{
  "status": "healthy",
  "timestamp": "2026-03-07T10:00:00.000Z",
  "services": {
    "database": "connected",
    "redis": "connected",
    "api": "running"
  },
  "version": "1.0.0",
  "environment": "development"
}
```

---

### Game Routes (`/api/game`)

#### `POST /api/game/start`

Starts a new game session. Creates the user if they don't exist. Generates a card set. Stores the session in Redis.

**Request body:**
```json
{
  "username": "stephen42",
  "difficulty": "easy",
  "categories": ["food", "space"]
}
```

| Field | Type | Required | Validation |
|---|---|---|---|
| `username` | string | yes | Alphanumeric, 3–50 chars |
| `difficulty` | string | no | `easy` / `medium` / `hard` / `expert` (default: `easy`) |
| `categories` | array of strings | no | Up to 10 values from the defined category list |

**Response (201):**
```json
{
  "success": true,
  "game": {
    "gameId": "uuid",
    "difficulty": "easy",
    "cards": [
      {
        "id": "pizza_1",
        "position": 0,
        "emoji": "🍕",
        "name": "Pizza Slice",
        "category": "food",
        "isFlipped": false,
        "isMatched": false
      }
    ],
    "config": {
      "cardCount": 16,
      "timeLimit": 300000,
      "pointsPerMatch": 10
    },
    "startTime": "2026-03-07T10:00:00.000Z"
  },
  "user": {
    "id": "uuid",
    "username": "stephen42",
    "displayName": "stephen42"
  }
}
```

> **Important:** The `pairId` field is stored on each card server-side (in Redis) but is **not** sent to the client in this response. The client cannot determine matches locally — it must call `/api/game/match` and let the server decide.

---

#### `POST /api/game/match`

Submits a two-card match attempt. The server looks up the game session from Redis, checks if both card `pairId` values match, calculates points and speed bonus, records the match in the database, and updates the cached session.

**Request body:**
```json
{
  "gameId": "uuid",
  "card1Id": "pizza_1",
  "card2Id": "pizza_2",
  "matchTime": 4500
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `gameId` | string (UUID) | yes | From `startGame` response |
| `card1Id` | string | yes | Card ID from the card array |
| `card2Id` | string | yes | Card ID from the card array |
| `matchTime` | number | no | Milliseconds elapsed since game start — used for speed bonus |

**Response (200):**
```json
{
  "success": true,
  "isMatch": true,
  "pointsEarned": 15,
  "message": "🎉 Perfect match! Your memory is on fire! 🔥",
  "game": {
    "gameId": "uuid",
    "score": 15,
    "moves": 1,
    "matchesFound": 1,
    "totalPairs": 8,
    "isComplete": false
  },
  "match": {
    "card1": { "id": "pizza_1", "emoji": "🍕", "name": "Pizza Slice" },
    "card2": { "id": "pizza_2", "emoji": "🍕", "name": "Pizza Slice" },
    "pointsEarned": 10,
    "bonusPoints": 5,
    "isSpeedBonus": true,
    "matchTime": 4500
  }
}
```

When `isMatch` is `false`, the `match` field is `null`. When `isComplete` is `true`, the frontend calls `/api/game/complete`.

---

#### `POST /api/game/complete`

Finalises the game. Calculates the full score breakdown including perfect game, speed, and streak bonuses. Updates the `games` table (which triggers the `update_user_stats` database trigger to update the `users` table). Clears the user stats and leaderboard cache in Redis.

**Request body:**
```json
{
  "gameId": "uuid",
  "timeElapsed": 87000,
  "finalScore": 80
}
```

**Response (200):**
```json
{
  "success": true,
  "gameResult": {
    "gameId": "uuid",
    "finalScore": 130,
    "scoreBreakdown": {
      "baseScore": 80,
      "speedBonus": 20,
      "streakBonus": 15,
      "perfectGameBonus": 50
    },
    "performance": "Excellent",
    "timeElapsed": 87000,
    "totalMoves": 10,
    "matchesFound": 8,
    "accuracy": "80.0",
    "difficulty": "easy"
  },
  "achievements": [
    {
      "title": "Perfect Memory! 🧠",
      "description": "Completed without any wrong moves!",
      "icon": "🏆",
      "rarity": "legendary"
    }
  ]
}
```

---

#### `GET /api/game/:gameId`

Retrieves the current state of a game session. Checks Redis first; falls back to the database if the session has expired.

**Response (200):**
```json
{
  "success": true,
  "game": {
    "gameId": "uuid",
    "username": "stephen42",
    "difficulty": "easy",
    "score": 40,
    "moves": 5,
    "isCompleted": false
  },
  "config": {
    "cardCount": 16,
    "pointsPerMatch": 10
  }
}
```

---

### Score Routes (`/api/scores`)

#### `POST /api/scores/user`

Creates or updates a user record. Called by the frontend at the start of `startNewGame()` before calling `/api/game/start`.

**Request body:**
```json
{ "username": "stephen42" }
```

**Response (200):**
```json
{ "success": true, "message": "User creation route working!" }
```

> **Note:** This route is currently a placeholder stub. User creation is handled within `POST /api/game/start` via `database.createOrGetUser()`. This endpoint exists for future expansion.

---

#### `GET /api/scores/:username`

Returns user statistics, performance level, achievements, and a motivational message.

**Response (200):**
```json
{
  "user": {
    "username": "stephen42",
    "bestScore": 193,
    "totalGames": 1
  },
  "statistics": {
    "fastestTime": "108.4s",
    "averageScore": 193,
    "globalRank": 42
  },
  "performance": {
    "level": { "level": "Advanced", "emoji": "⭐", "color": "#4169E1" },
    "rating": { "rating": "Excellent", "emoji": "🌟", "color": "#FFD700" }
  },
  "gameHistory": [],
  "achievements": [...],
  "message": "🔥 You're getting good at this!"
}
```

> **Note:** The user stats in this route currently return placeholder data. The full database-backed implementation (`getUserStats`) exists in `database.js` and is ready to be wired in.

---

#### `GET /api/scores/:username/history`

Returns paginated game history for a user.

**Query parameters:** `limit` (default 10), `offset` (default 0)

**Response (200):**
```json
{
  "success": true,
  "gameHistory": [
    {
      "gameId": "uuid",
      "score": 120,
      "moves": 18,
      "timeElapsed": 75000,
      "difficulty": "easy",
      "accuracy": "88.9",
      "duration": "1:15"
    }
  ],
  "pagination": {
    "total": 5,
    "limit": 10,
    "offset": 0,
    "hasMore": false
  }
}
```

---

### Leaderboard Routes (`/api/leaderboard`)

#### `GET /api/leaderboard`

Returns the top players. Supports optional filtering by timeframe.

**Query parameters:**

| Parameter | Default | Options |
|---|---|---|
| `limit` | 25 | any integer |
| `timeframe` | `all` | `all`, `week`, `month` |
| `difficulty` | null | `easy`, `medium`, `hard`, `expert` |

**Response (200):**
```json
{
  "success": true,
  "leaderboard": [
    {
      "rank": 1,
      "username": "memorymaster42",
      "displayName": "🧠 Memory Master",
      "bestScore": 280,
      "bestTime": 42000,
      "timeFormatted": "42.0s",
      "totalGames": 25,
      "averageScore": 195.5,
      "badge": { "emoji": "👑", "title": "Champion", "color": "#FFD700" },
      "performance": { "level": "Legendary", "color": "#FFD700" },
      "isActive": true
    }
  ],
  "metadata": {
    "totalPlayers": 8,
    "timeframe": "all",
    "lastUpdated": "2026-03-07T10:00:00.000Z",
    "topScore": 280,
    "averageScore": 224
  }
}
```

> **Note:** The leaderboard currently returns in-memory mock data. The `database.getLeaderboard()` method in `database.js` is fully implemented with the correct SQL and is ready to replace the mock data.

---

#### `GET /api/leaderboard/fresh`

Same as `GET /api/leaderboard` but bypasses any cache. Useful for forcing a refresh after a game completes.

#### `GET /api/leaderboard/rank/:username`

Returns a user's rank plus a configurable number of surrounding players for context.

**Query parameters:** `context` (default 5) — number of players above and below to include.

#### `GET /api/leaderboard/stats`

Returns aggregate statistics: total players, total games, high score, fastest time, completion rate by difficulty, and insights.

#### `POST /api/leaderboard/refresh`

Clears the leaderboard cache. Returns confirmation of how many cache keys were cleared.

---

## 7. Data Flow — Complete Game Lifecycle

```
Browser                         Backend (Express)               PostgreSQL          Redis
  |                                    |                             |                  |
  |-- POST /api/scores/user ---------->|                             |                  |
  |                                    |-- (stub, no DB call) ------>|                  |
  |<-- { success: true } -------------|                             |                  |
  |                                    |                             |                  |
  |-- POST /api/game/start ----------->|                             |                  |
  |                                    |-- createOrGetUser() ------->|                  |
  |                                    |<-- user row ---------------|                  |
  |                                    |-- createGame() ------------>|                  |
  |                                    |<-- game row ---------------|                  |
  |                                    |-- generateCardSet() ------->|  (local, no I/O)  |
  |                                    |-- cacheGameSession() ------>|                  |-->  game:session:<id>
  |<-- { gameId, cards[] } -----------|                             |                  |
  |                                    |                             |                  |
  |  (user flips 2 cards)              |                             |                  |
  |-- POST /api/game/match ----------->|                             |                  |
  |                                    |-- getCachedGameSession() -->|                  |-->  read game:session:<id>
  |                                    |<-- session data -----------|                  |
  |                                    |-- (compare pairIds) ------->|  (local)          |
  |                                    |-- recordMatch() ----------->|                  |
  |                                    |<-- match row --------------|                  |
  |                                    |-- cacheGameSession() ------>|                  |-->  update game:session:<id>
  |<-- { isMatch, score, moves } ------|                             |                  |
  |                                    |                             |                  |
  |  (all pairs found — isComplete true)|                            |                  |
  |-- POST /api/game/complete -------->|                             |                  |
  |                                    |-- completeGame() ---------->|                  |
  |                                    |                             |-- UPDATE games    |
  |                                    |                             |-- TRIGGER fires   |
  |                                    |                             |-- UPDATE users    |
  |                                    |<-- updated game row -------|                  |
  |                                    |-- del(user:stats:<name>) -->|                  |-->  invalidate
  |                                    |-- del(leaderboard:top) ---->|                  |-->  invalidate
  |<-- { gameResult, achievements } ---|                             |                  |
  |                                    |                             |                  |
  |-- GET /api/leaderboard ----------->|                             |                  |
  |                                    |-- (returns mock data) ----->|                  |
  |<-- { leaderboard[] } -------------|                             |                  |
```

---

## 8. Running the Application Locally (Developer Setup)

### Prerequisites

- Node.js ≥ 18.0.0
- npm ≥ 8.0.0
- PostgreSQL 15 running locally
- Redis running locally

> **Kubernetes deployment** is covered in the Phase 3 documentation. This section covers native local development only — running all processes directly on your machine against a local PostgreSQL and Redis instance.

---

### Step 1 — Initialise the database

Connect to your local PostgreSQL instance and run the init script:

```bash
psql -U gameuser -d humor_memory_game -f database/combined-init.sql
```

This creates all tables, indexes, views, triggers, and seeds sample data. Run it once on a fresh database, or any time you need a clean reset.

---

### Step 2 — Configure the backend environment

```bash
cd backend
cp ../env/env.example .env
```

Edit `.env` and set at minimum:

```
NODE_ENV=development
PORT=3001
DB_HOST=localhost
DB_PORT=5432
DB_NAME=humor_memory_game
DB_USER=gameuser
DB_PASSWORD=gamepass123
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=gamepass123
```

---

### Step 3 — Install backend dependencies and start

```bash
npm install
npm run dev       # nodemon — restarts on file changes
```

The backend starts on `http://localhost:3001`. Verify:

```bash
curl http://localhost:3001/health
```

---

### Step 4 — Build and serve the frontend

```bash
cd ../frontend
npm install
npm run build     # copies src/ and public/ into dist/
npm run dev       # python3 -m http.server 3000 --directory src
```

> `npm run dev` serves from `src/` directly for development. The `npm run build` step produces the `dist/` directory served by Nginx at runtime.

---

### Step 5 — Configure the frontend API URL

`npm run dev` serves files directly without an Nginx reverse proxy, so the default `window.API_BASE_URL = '/api'` will not resolve. For local development, temporarily set the backend URL directly in `frontend/src/config.js`:

```javascript
window.API_BASE_URL = 'http://localhost:3001/api';
window.CONFIG_READY = true;
```

> **Revert this change before committing.** At runtime this value is injected by Nginx via `envsubst` using the `FRONTEND_API_URL` environment variable.

---

### Step 6 — Access the application

Open `http://localhost:3000` in your browser.

---

### Useful Developer Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /health` | Checks DB + Redis connectivity |
| `GET /api` | Lists all available API endpoints |
| `GET /metrics` | Prometheus metrics output |
| `GET /debug/sync-metrics` | Manually triggers metrics sync from DB |
| `GET /debug/test` | Confirms routing is working |

---

### Backend npm Scripts

| Script | Command | Use |
|---|---|---|
| `npm start` | `node server.js` | Production start |
| `npm run dev` | `nodemon server.js` | Development with auto-restart |
| `npm run test:ci` | `jest --coverage --ci` | Full test run with coverage |

---

### Frontend npm Scripts

| Script | What it does |
|---|---|
| `npm run build` | Copies `src/` and `public/` → `dist/` |
| `npm run dev` | Serves `src/` on port 3000 via Python HTTP server |
| `npm run clean` | Removes the `dist/` directory |

---

## 9. Key Design Decisions

**Frontend validation is UI-only.** Username format is checked client-side before the API call, but the Joi schema in `backend/middleware/validation.js` is the authoritative validator. The backend will reject invalid input regardless of what the frontend sends.

**Match validation is server-side only.** The `pairId` field is stored in the Redis session but is never sent to the browser. The client cannot determine if two cards match — it must call `/api/game/match` and trust the server response. This prevents client-side cheating.

**User stats update via a database trigger**, not application code. When `completeGame()` executes `UPDATE games SET game_completed = true`, the `trigger_update_user_stats` trigger fires automatically and updates `total_games`, `total_score`, `best_score`, `best_time`, and `last_played` on the `users` table.

**Redis is non-critical for match processing.** If the cache update fails during a match attempt, execution continues. The game will not break if Redis is temporarily unavailable — it degrades gracefully with a console warning.

**The leaderboard and scores routes currently use mock/placeholder data.** The database methods (`getLeaderboard`, `getUserStats`) are fully implemented in `database.js` but the routes have not yet been wired to call them. This is a known development state — the database layer is complete and ready.

**Known open bug (BUG-001):** The frontend's `startNewGame()` function sends `categories: null` when no categories are selected. The Joi schema marks `categories` as optional, but the backend's `validateGameStart` middleware may reject a null value rather than treating it as absent. The `GameDataGenerator.generateCardSet()` handles a null categories argument correctly (falls back to all emojis), so the fix is in the validation middleware.

# Humor Memory Game - DevOps Learning Edition

A full-stack memory card game application built as a comprehensive DevOps learning project.

## About the Project

Humor Memory Game is a classic memory card matching game. Players flip cards to find matching pairs while keeping track of their score. The project demonstrates:

- Frontend: Vanilla JavaScript/HTML/CSS interactive game
- Backend: Node.js/Express REST API with session management
- Database: PostgreSQL for persistent data storage
- Cache: Redis for performance optimization

## DevOps Learning Objectives

This project teaches:
- Containerization with Docker
- Multi-container orchestration with Docker-Compose
- Networking and service communication
- Volume persistence and data management
- Health checks and startup ordering
- Environment-based configuration

## Prerequisites

### For Local Development
- Node.js v18 or higher
- npm v8 or higher
- PostgreSQL 15 or higher
- Redis 7 or higher

### For Docker Setup
- Docker Engine 25 or higher
- Docker-Compose v2.24 or higher
- Git

## Quick Start - Local Development

### 1. Clone Repository

git clone https://github.com/YOUR-USERNAME/humor-memory-game.git
cd humor-memory-game

### 2. Setup Backend

cd backend
npm install

cat > .env << 'ENVEOF'
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
JWT_SECRET=dev-secret-key
SESSION_SECRET=dev-session-key
API_BASE_URL=/api
CORS_ORIGIN=http://localhost:3000
LOG_LEVEL=debug
ENVEOF

npm start

### 3. Setup Frontend (New Terminal)

cd frontend
npm install

cat > build-local.sh << 'BASHEOF'
#!/bin/bash
npm run build
sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' dist/index.html
echo "Frontend built for localhost:3001"
BASHEOF

chmod +x build-local.sh
./build-local.sh
python3 -m http.server 3000 --directory dist/

### 4. Setup Database (New Terminal)

sudo -u postgres psql << 'SQLEOF'
CREATE USER gameuser WITH PASSWORD 'gamepass123';
CREATE DATABASE humor_memory_game OWNER gameuser;
\c humor_memory_game
\i ../database/combined-init.sql
SQLEOF

### 5. Test the Application

curl http://localhost:3001/api/health
open http://localhost:3000

## Docker Setup

### Prerequisites
- Docker Engine 25 or higher
- Docker-Compose v2.24 or higher

### Quick Start

cat > .env << 'EOF'
NODE_ENV=development
DB_NAME=humor_memory_game
DB_USER=gameuser
DB_PASSWORD=gamepass123
REDIS_PASSWORD=gamepass123
API_PORT=3001
API_BASE_URL=/api
CORS_ORIGIN=http://frontend:80
JWT_SECRET=dev-secret-key
SESSION_SECRET=dev-session-key

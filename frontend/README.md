Humor Memory Game

A full-stack memory card game application built with Node.js and PostgreSQL.

Project Structure
├── backend/           - Node.js/Express API
├── frontend/          - Vanilla JavaScript game UI
├── database/          - PostgreSQL schema
└── README.md          - This file
Local Development Setup
Backend
cd backend
npm install
npm start

Runs on: http://localhost:3001

Frontend
cd frontend
npm install
./build-local.sh
python3 -m http.server 3000 --directory dist/

Runs on: http://localhost:3000

Database
sudo -u postgres psql < database/combined-init.sql
Docker Setup
docker-compose build
docker-compose up -d
API Endpoints
GET /api/health - Health check
POST /api/auth/register - Register user
POST /api/auth/login - Login user
POST /api/games - Create game
GET /api/games/leaderboard - Get scores
Technologies
Frontend: Vanilla JavaScript, HTML, CSS
Backend: Node.js, Express
Database: PostgreSQL
Cache: Redis
Containerization: Docker, Docker-Compose
Next Steps
Complete local development
Create Dockerfiles from source analysis
Set up Docker-Compose orchestration
Deploy to Kubernetes
Deploy to AWS
License

Educational project for DevOps learning.

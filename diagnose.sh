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

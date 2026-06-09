#!/bin/bash
npm run build
sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' dist/index.html
grep -rl '${API_BASE_URL}' dist/ | xargs sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' 2>/dev/null || true
echo "✅ Frontend built and configured for localhost"

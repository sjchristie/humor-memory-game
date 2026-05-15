#!/bin/bash
npm run build
sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' dist/index.html
echo "✅ Frontend built for localhost:3001"

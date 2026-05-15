#!/bin/bash

# 1. Build the project to create a fresh /dist folder
npm run build

# 2. Inject the LOCALHOST URL directly into the index.html placeholder
# We target the ${API_BASE_URL} string specifically
sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' dist/index.html

# 3. Check for the placeholder in any generated Javascript files and swap those too
# We use '|| true' so the script doesn't crash if grep finds nothing
grep -rl '${API_BASE_URL}' dist/ | xargs sed -i 's|\${API_BASE_URL}|http://localhost:3001/api|g' 2>/dev/null || true

# 4. Verify the change in the console
echo "✅ Verification: Checking dist/index.html for injected URL..."
grep "window.API_BASE_URL" dist/index.html

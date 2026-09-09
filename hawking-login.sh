#!/bin/bash

set -euo pipefail

BASE_URL="https://hawking.computing.dcu.ie/hawking"
LOGIN_URL="https://hawking.computing.dcu.ie/login"
COOKIE_FILE="$HOME/.hawking_cookie"
USER_FILE="$HOME/.hawking_user"
HEADER_FILE=$(mktemp)
COOKIE_JAR=$(mktemp)

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
RESET="\033[0m"

DEBUG=false
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        DEBUG=true
    fi
done

cleanup() {
    rm -f "$HEADER_FILE" "$COOKIE_JAR"
}
trap cleanup EXIT

# ---- Retrieve Username ----
SAVED_USER=""
if [ -f "$USER_FILE" ]; then
    SAVED_USER=$(cat "$USER_FILE" 2>/dev/null || true)
fi

if [ -n "$SAVED_USER" ]; then
    read -rp "Username [${SAVED_USER}]: " USERNAME
    USERNAME="${USERNAME:-$SAVED_USER}"
else
    read -rp "Username: " USERNAME
fi

if [ -z "$USERNAME" ]; then
    echo -e "${RED}Error: Username cannot be empty.${RESET}"
    exit 1
fi

# ---- Attempt to Load Password from OS Keychain ----
PASSWORD=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    PASSWORD=$(security find-generic-password -s "hawking" -a "$USERNAME" -w 2>/dev/null || true)
elif command -v secret-tool &> /dev/null; then
    PASSWORD=$(secret-tool lookup service hawking username "$USERNAME" 2>/dev/null || true)
fi

# If not found in keychain, prompt the user
if [ -z "$PASSWORD" ]; then
    read -srp "Password: " PASSWORD
    echo ""
    PROMPTED_PASSWORD=true
else
    echo -e "${GREEN}Using **securely stored password** from system keychain.${RESET}"
    PROMPTED_PASSWORD=false
fi

echo -e "${YELLOW}Fetching CSRF token...${RESET}"

# 1. Fetch initial login page to get CSRF token and seed initial cookie jar
INIT_RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LOGIN_URL")

CSRF_TOKEN=$(echo "$INIT_RESPONSE" | grep -oE 'name="(_csrf_token|csrf_token)"[^>]*value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/' || true)

if [ -z "$CSRF_TOKEN" ]; then
    echo -e "${RED}Failed to extract **CSRF token** from login page.${RESET}"
    exit 1
fi

echo -e "${YELLOW}Authenticating via LDAP...${RESET}"

# 2. POST credentials without auto-following redirects so we can inspect the 302
curl -s -D "$HEADER_FILE" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST "$LOGIN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Referer: $LOGIN_URL" \
    -H "Origin: https://hawking.computing.dcu.ie" \
    --data-urlencode "_username=${USERNAME}" \
    --data-urlencode "_password=${PASSWORD}" \
    --data-urlencode "_csrf_token=${CSRF_TOKEN}" > /dev/null

HTTP_STATUS=$(head -n 1 "$HEADER_FILE" | awk '{print $2}')
LOCATION=$(grep -i "^Location:" "$HEADER_FILE" | awk '{print $2}' | tr -d '\r\n' || true)

# 3. Check if we received the expected 302 Redirect
if [ "$HTTP_STATUS" -ne 302 ] && [ "$HTTP_STATUS" -ne 303 ]; then
    echo -e "${RED}Login failed: Server did not issue a 302 redirect (HTTP ${HTTP_STATUS}).${RESET}"
    exit 1
fi

# If redirected back to /login or /login?error, the credentials were bad
if echo "$LOCATION" | grep -qE "login\?error|/login$"; then
    echo -e "${RED}Login failed: **Invalid credentials**.${RESET}"
    exit 1
fi

# Save successful username for future use
echo "$USERNAME" > "$USER_FILE"
chmod 600 "$USER_FILE"

# Securely save password to OS Keychain if it was newly typed
if [ "$PROMPTED_PASSWORD" = true ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        security add-generic-password -U -s "hawking" -a "$USERNAME" -w "$PASSWORD" 2>/dev/null || true
    elif command -v secret-tool &> /dev/null; then
        echo "$PASSWORD" | secret-tool store --label='Hawking CLI' service hawking username "$USERNAME" 2>/dev/null || true
    fi
fi

# 4. Extract the authenticated session ID set during the 302 response
AUTH_SESS=$(grep -i "Set-Cookie: PHPSESSID=" "$HEADER_FILE" | sed -E 's/.*PHPSESSID=([^;]+).*/\1/' | tail -n 1 | tr -d '\r\n' || true)

if [ -z "$AUTH_SESS" ]; then
    AUTH_SESS=$(grep "PHPSESSID" "$COOKIE_JAR" | grep -v "deleted" | tail -n 1 | awk '{print $7}' | tr -d '\r\n' || true)
fi

# 5. Format Netscape Cookie Jar file for hawking.sh (-b / -c)
cat <<EOF > "$COOKIE_FILE"
# Netscape HTTP Cookie File
hawking.computing.dcu.ie	FALSE	/	TRUE	0	PHPSESSID	${AUTH_SESS}
EOF
chmod 600 "$COOKIE_FILE"

# 6. Follow the 302 target URL to finalize the session context on the server
TARGET_URL="$LOCATION"
if [[ "$TARGET_URL" != http* ]]; then
    TARGET_URL="https://hawking.computing.dcu.ie${TARGET_URL}"
fi

PORTAL_RESPONSE=$(curl -s -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$TARGET_URL")

# Final sanity check: ensure we didn't end up on a login form
if echo "$PORTAL_RESPONSE" | grep -q 'name="_username"'; then
    echo -e "${RED}Login failed: **Session rejected** on post-login redirect.${RESET}"
    rm -f "$COOKIE_FILE"
    exit 1
fi

echo -e "${GREEN}${BOLD}✓ Authentication successful! Cookie saved to ${COOKIE_FILE}${RESET}"

if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}=== Final PHPSESSID ===${RESET}"
    echo "$AUTH_SESS"
fi

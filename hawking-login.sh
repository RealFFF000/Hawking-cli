#!/bin/bash

set -euo pipefail

BASE_URL="https://hawking.computing.dcu.ie/hawking"
LOGIN_URL="https://hawking.computing.dcu.ie/login"
COOKIE_FILE="$HOME/.hawking_cookie"
USER_FILE="$HOME/.hawking_user"
CACHE_FILE="$HOME/.hawking_history"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
[ -f "$CONFIG_FILE" ] || CONFIG_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/config.yaml"

config_value() {
    local key="$1"
    local default_value="$2"
    local value=""

    if [ -f "$CONFIG_FILE" ]; then
        value=$(awk -v wanted="$key" '
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
            {
                key_part = $0
                sub(/:.*/, "", key_part)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key_part)
                if (key_part != wanted) next
                value_part = $0
                sub(/^[^:]*:/, "", value_part)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value_part)
                sub(/[[:space:]]+#.*$/, "", value_part)
                if (value_part ~ /^".*"$/ || value_part ~ /^\047.*\047$/) {
                    value_part = substr(value_part, 2, length(value_part) - 2)
                }
                print value_part
                exit
            }
        ' "$CONFIG_FILE")
    fi

    printf '%s' "${value:-$default_value}"
}

expand_config_path() {
    printf '%s' "${1//\$HOME/$HOME}"
}

BASE_URL=$(config_value 'server.base_url' "$BASE_URL")
LOGIN_URL=$(config_value 'server.login_url' "$LOGIN_URL")
COOKIE_FILE=$(expand_config_path "$(config_value 'session.cookie_file' "$COOKIE_FILE")")
USER_FILE=$(expand_config_path "$(config_value 'session.user_file' "$USER_FILE")")
CACHE_FILE=$(expand_config_path "$(config_value 'session.cache_file' "$CACHE_FILE")")
PASSWORD_FILE=$(expand_config_path "$(config_value 'session.password_file' "$HOME/.hawking_pw")")
CONNECT_TIMEOUT=$(config_value 'network.connect_timeout_seconds' 5)
HEADER_FILE=$(mktemp)
COOKIE_JAR=$(mktemp)

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
RESET="\033[0m"

DEBUG=false
VOCAL=false
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        DEBUG=true
    elif [ "$arg" == "--vocal" ]; then
        VOCAL=true
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
elif [ -f "$PASSWORD_FILE" ]; then
    PASSWORD=$(cat "$PASSWORD_FILE" 2>/dev/null || true)
fi

if [ -z "$PASSWORD" ]; then
    read -srp "Password: " PASSWORD
    echo ""
    PROMPTED_PASSWORD=true
else
    if [ "$VOCAL" = true ]; then
        echo -e "${GREEN}Using ${BOLD}securely stored password${RESET}${GREEN} from system keychain.${RESET}"
    fi
    PROMPTED_PASSWORD=false
fi

if [ "$VOCAL" = true ]; then
    echo -e "${YELLOW}Fetching CSRF token...${RESET}"
fi

# 1. Fetch initial login page to get CSRF token and seed initial cookie jar
INIT_RESPONSE=$(curl -s --connect-timeout "$CONNECT_TIMEOUT" -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$LOGIN_URL")

CSRF_TOKEN=$(echo "$INIT_RESPONSE" | grep -oE 'name="(_csrf_token|csrf_token)"[^>]*value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/' || true)

if [ -z "$CSRF_TOKEN" ]; then
    echo -e "${RED}Failed to extract ${BOLD}CSRF token${RESET}${RED} from login page.${RESET}"
    exit 1
fi

if [ "$VOCAL" = true ]; then
    echo -e "${YELLOW}Authenticating via LDAP...${RESET}"
fi

# 2. POST credentials without auto-following redirects so we can inspect the 302
curl -s --connect-timeout "$CONNECT_TIMEOUT" -D "$HEADER_FILE" -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X POST "$LOGIN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Referer: $LOGIN_URL" \
    -H "Origin: $(config_value 'server.origin' 'https://hawking.computing.dcu.ie')" \
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

if echo "$LOCATION" | grep -qE "login\?error|/login$"; then
    echo -e "${RED}Login failed: ${BOLD}Invalid credentials${RESET}${RED}.${RESET}"
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
    else
        read -rp "No system keychain available. Save password in plaintext at ${PASSWORD_FILE}? [y/N] " SAVE_PLAINTEXT
        if [[ "$SAVE_PLAINTEXT" =~ ^[Yy]$ ]]; then
            ( umask 077; printf '%s' "$PASSWORD" > "$PASSWORD_FILE" ) 2>/dev/null || true
        fi
    fi
fi

# 4. Extract authenticated session ID
AUTH_SESS=$(grep -i "Set-Cookie: PHPSESSID=" "$HEADER_FILE" | sed -E 's/.*PHPSESSID=([^;]+).*/\1/' | tail -n 1 | tr -d '\r\n' || true)

if [ -z "$AUTH_SESS" ]; then
    AUTH_SESS=$(grep "PHPSESSID" "$COOKIE_JAR" | grep -v "deleted" | tail -n 1 | awk '{print $7}' | tr -d '\r\n' || true)
fi

# 5. Format Netscape Cookie Jar file
cat <<EOF > "$COOKIE_FILE"
# Netscape HTTP Cookie File
hawking.computing.dcu.ie	FALSE	/	TRUE	0	PHPSESSID	${AUTH_SESS}
EOF
chmod 600 "$COOKIE_FILE"

# 6. Follow the 302 target URL
TARGET_URL="$LOCATION"
if [[ "$TARGET_URL" != http* ]]; then
    TARGET_URL="https://hawking.computing.dcu.ie${TARGET_URL}"
fi

PORTAL_RESPONSE=$(curl -s -L --connect-timeout "$CONNECT_TIMEOUT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$TARGET_URL")

if echo "$PORTAL_RESPONSE" | grep -q 'name="_username"'; then
    echo -e "${RED}Login failed: ${BOLD}Session rejected${RESET}${RED} on post-login redirect.${RESET}"
    rm -f "$COOKIE_FILE"
    exit 1
fi

# 7. Scrape Module IDs safely from dashboard links
if [ "$VOCAL" = true ]; then
    echo -e "${YELLOW}Scraping active ${BOLD}module IDs${RESET}${YELLOW} from dashboard...${RESET}"
fi
DASHBOARD_HTML=$(curl -s -L --connect-timeout "$CONNECT_TIMEOUT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$BASE_URL")

SCAPED_IDS=$(echo "$DASHBOARD_HTML" | grep -oE 'href="/hawking/[0-9]+"' | grep -oE '[0-9]+' | sort -u || true)

if [ -n "$SCAPED_IDS" ]; then
    temp_file=$(mktemp)
    echo "$SCAPED_IDS" > "$temp_file"
    if [ -f "$CACHE_FILE" ]; then
        grep -vxf "$temp_file" "$CACHE_FILE" >> "$temp_file" 2>/dev/null || true
    fi
    mv "$temp_file" "$CACHE_FILE"
    if [ "$VOCAL" = true ]; then
        echo -e "${GREEN}Successfully ${BOLD}synced module IDs${RESET}${GREEN} to cache.${RESET}"
    fi
fi

echo -e "${GREEN}${BOLD}✓ Authentication successful!${RESET}"

if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}=== Final PHPSESSID ===${RESET}"
    echo "$AUTH_SESS"
    echo -e "${BOLD}=== Scraped IDs ===${RESET}"
    echo "$SCAPED_IDS"
fi

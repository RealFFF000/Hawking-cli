#!/bin/bash

set -euo pipefail

BASE_URL="https://hawking.computing.dcu.ie/hawking"
API_BASE_URL="https://hawking.computing.dcu.ie/api"
COOKIE_FILE="$HOME/.hawking_cookie"
USER_FILE="$HOME/.hawking_user"
CACHE_FILE="$HOME/.hawking_history"
UPDATE_CHECK_FILE="$HOME/.hawking_last_update"
UPDATE_REPO_URL="https://github.com/RealFFF000/Hawking-cli"
UPDATE_BRANCH="main"
UPDATE_CHECK_INTERVAL=604800
COOKIE_TTL=7200
CONNECT_TIMEOUT=5
HEALTHCHECK_TIMEOUT=4
IGNORE_EXTENSIONS=".out"
IGNORE_HIDDEN=true
IGNORE_SCRIPT="hawking.sh"
SCRIPT_NAME="$(basename "$0")"

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
API_BASE_URL=$(config_value 'api.base_url' "$API_BASE_URL")
UPDATE_REPO_URL=$(config_value 'update.repository' "$UPDATE_REPO_URL")
UPDATE_BRANCH=$(config_value 'update.branch' "$UPDATE_BRANCH")
UPDATE_CHECK_INTERVAL=$(config_value 'update.check_interval_seconds' "$UPDATE_CHECK_INTERVAL")
UPDATE_CHECK_FILE=$(expand_config_path "$(config_value 'update.check_file' "$UPDATE_CHECK_FILE")")
COOKIE_FILE=$(expand_config_path "$(config_value 'session.cookie_file' "$COOKIE_FILE")")
USER_FILE=$(expand_config_path "$(config_value 'session.user_file' "$USER_FILE")")
CACHE_FILE=$(expand_config_path "$(config_value 'session.cache_file' "$CACHE_FILE")")
PASSWORD_FILE=$(expand_config_path "$(config_value 'session.password_file' "$HOME/.hawking_pw")")
COOKIE_TTL=$(config_value 'session.cookie_ttl_seconds' "$COOKIE_TTL")
CONNECT_TIMEOUT=$(config_value 'network.connect_timeout_seconds' "$CONNECT_TIMEOUT")
HEALTHCHECK_TIMEOUT=$(config_value 'network.healthcheck_timeout_seconds' "$HEALTHCHECK_TIMEOUT")
IGNORE_EXTENSIONS=$(config_value 'file_selection.ignore_extensions' "$IGNORE_EXTENSIONS")
IGNORE_HIDDEN=$(config_value 'file_selection.ignore_hidden' "$IGNORE_HIDDEN")
IGNORE_SCRIPT=$(config_value 'file_selection.ignore_script' "$IGNORE_SCRIPT")

GREEN="\033[0;32m"
RED="\033[0;31m"
WHITE="\033[0;37m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

# ---- Parse Flags & Options First ----
DEBUG=false
VOCAL=false
CLEAR_CACHE=false
SHOW_MODULES=false
LOGOUT=false
FORCE_UPDATE=false
SHOW_VERSION=false
SHOW_RUNNER=false
ADD_MODULE_ID=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG=true
            shift
            ;;
        --vocal)
            VOCAL=true
            shift
            ;;
        --clear-cache)
            CLEAR_CACHE=true
            shift
            ;;
        --modules)
            SHOW_MODULES=true
            shift
            ;;
        --logout)
            LOGOUT=true
            shift
            ;;
        --update)
            FORCE_UPDATE=true
            shift
            ;;
        --version|-v)
            SHOW_VERSION=true
            shift
            ;;
        --runner)
            SHOW_RUNNER=true
            shift
            ;;
        --add-module)
            ADD_MODULE_ID="$2"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

now=$(date +%s)

update_installed_cli() {
    local temp_dir
    local temp_repo
    local staged_home
    local new_repo
    local old_repo
    temp_dir=$(mktemp -d)
    temp_repo="$temp_dir/hawking-cli"
    staged_home="$temp_dir/home"
    new_repo="$temp_dir/new-hawking"
    old_repo="$temp_dir/old-hawking"

    if ! git clone --quiet --depth 1 --single-branch --branch "$UPDATE_BRANCH" "$UPDATE_REPO_URL" "$temp_repo" >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        return 1
    fi

    mkdir -p "$staged_home"
    if ! (cd "$temp_repo" && HOME="$staged_home" ./install.sh >/dev/null 2>&1); then
        rm -rf "$temp_dir"
        return 1
    fi

    if ! cp -R "$temp_repo" "$new_repo" || ! cp -R "$staged_home/.hawking/bin" "$new_repo/bin"; then
        rm -rf "$temp_dir"
        return 1
    fi

    if [ -d "$HOME/.hawking" ] && ! mv "$HOME/.hawking" "$old_repo"; then
        rm -rf "$temp_dir"
        return 1
    fi

    if ! mv "$new_repo" "$HOME/.hawking"; then
        [ -d "$old_repo" ] && mv "$old_repo" "$HOME/.hawking"
        rm -rf "$temp_dir"
        return 1
    fi

    rm -rf "$temp_dir"
}

# ---- Handle --version ----
if [ "$SHOW_VERSION" = true ]; then
    if [ -d "$HOME/.hawking/.git" ]; then
        echo -e "${BOLD}Hawking CLI Version (Latest Commit):${RESET}"
        git --no-pager -C "$HOME/.hawking" -c color.ui=always log -1 --pretty=format:"%C(cyan)%h%Creset - %C(green)%s%Creset %C(yellow)(%ar)%Creset [%an]" --date=relative 2>/dev/null || echo -e "${YELLOW}No commit history found.${RESET}"
        echo ""
    else
        echo -e "${YELLOW}Hawking CLI (${BOLD}Git repository context not found${RESET}${YELLOW} in ~/.hawking)${RESET}"
    fi
    exit 0
fi

# ---- Handle --update (Forces Overwrite of Local Changes) ----
if [ "$FORCE_UPDATE" = true ]; then
    update_installed_cli || true
    echo "$now" > "$UPDATE_CHECK_FILE"
    exit 0
fi

# ---- Handle --logout ----
if [ "$LOGOUT" = true ]; then
    LOGOUT_USERNAME=""
    [ -f "$USER_FILE" ] && LOGOUT_USERNAME=$(tr -d '[:space:]' < "$USER_FILE")
    if [ -n "$LOGOUT_USERNAME" ] && [[ "$OSTYPE" == darwin* ]]; then
        security delete-generic-password -s hawking -a "$LOGOUT_USERNAME" >/dev/null 2>&1 || true
    elif [ -n "$LOGOUT_USERNAME" ] && command -v secret-tool >/dev/null 2>&1; then
        secret-tool clear service hawking username "$LOGOUT_USERNAME" >/dev/null 2>&1 || true
    elif [ -n "$LOGOUT_USERNAME" ]; then
        rm -f "$PASSWORD_FILE"
    fi
    rm -f "$COOKIE_FILE" "$USER_FILE"
    echo -e "${GREEN}Successfully ${BOLD}logged out${RESET}${GREEN} and cleared default username.${RESET}"
    exit 0
fi

# ---- Handle --clear-cache ----
if [ "$CLEAR_CACHE" = true ]; then
    rm -f "$CACHE_FILE"
    echo -e "${GREEN}Cache ${BOLD}cleared successfully${RESET}${GREEN}.${RESET}"
    exit 0
fi

# ---- Handle --modules ----
if [ "$SHOW_MODULES" = true ]; then
    if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
        echo -e "${BOLD}Cached Module IDs:${RESET}"
        awk '!seen[$0]++' "$CACHE_FILE" | while read -r mid; do
            echo -e "  - ${GREEN}${mid}${RESET}"
        done
    else
        echo -e "${YELLOW}No ${BOLD}cached module IDs${RESET}${YELLOW} found.${RESET}"
    fi
    exit 0
fi

# ---- Handle --add-module ----
if [ -n "$ADD_MODULE_ID" ]; then
    if [[ ! "$ADD_MODULE_ID" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Module ID must be a ${BOLD}valid number${RESET}${RED}.${RESET}"
        exit 1
    fi
    temp_file=$(mktemp)
    echo "$ADD_MODULE_ID" > "$temp_file"
    if [ -f "$CACHE_FILE" ]; then
        grep -v "^${ADD_MODULE_ID}$" "$CACHE_FILE" >> "$temp_file" || true
    fi
    mv "$temp_file" "$CACHE_FILE"
    echo -e "${GREEN}Successfully ${BOLD}added module ID${RESET}${GREEN} ${BOLD}${ADD_MODULE_ID}${RESET}${GREEN} to cache.${RESET}"
    exit 0
fi

# ---- Weekly Synchronous Update Check ----
should_check=false
if [ ! -f "$UPDATE_CHECK_FILE" ]; then
    should_check=true
else
    last_check=$(cat "$UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
    if [ $((now - last_check)) -gt "$UPDATE_CHECK_INTERVAL" ]; then
        should_check=true
    fi
fi

if [ "$should_check" = true ]; then
    update_installed_cli || true
    echo "$now" > "$UPDATE_CHECK_FILE"
fi

# ---- Load & Manage Cache ----
get_cached_ids() {
    if [ -f "$CACHE_FILE" ]; then
        awk '!seen[$0]++' "$CACHE_FILE"
    fi
}

save_cached_id() {
    local new_id="$1"
    local temp_file
    temp_file=$(mktemp)
    echo "$new_id" > "$temp_file"
    if [ -f "$CACHE_FILE" ]; then
        grep -v "^${new_id}$" "$CACHE_FILE" >> "$temp_file" || true
    fi
    mv "$temp_file" "$CACHE_FILE"
}

API_USERNAME=""
API_PASSWORD=""
API_AUTHENTICATED=false

api_get() {
    curl -sS --fail --connect-timeout "$CONNECT_TIMEOUT" -u "$API_USERNAME:$API_PASSWORD" "$1"
}

authenticate_api() {
    if [ -f "$USER_FILE" ]; then
        API_USERNAME=$(tr -d '[:space:]' < "$USER_FILE")
    fi
    API_USERNAME="${API_USERNAME:-${HAWKING_USERNAME:-${EINSTEIN_USERNAME:-${DCU_USERNAME:-${SOC_USERNAME:-}}}}}"
    if [ -z "$API_USERNAME" ]; then
        read -rp "Username: " API_USERNAME
    fi
    [ -n "$API_USERNAME" ] || return 1

    if [[ "$OSTYPE" == darwin* ]]; then
        API_PASSWORD=$(security find-generic-password -s hawking -a "$API_USERNAME" -w 2>/dev/null || true)
    elif command -v secret-tool >/dev/null 2>&1; then
        API_PASSWORD=$(secret-tool lookup service hawking username "$API_USERNAME" 2>/dev/null || true)
    elif [ -f "$PASSWORD_FILE" ]; then
        API_PASSWORD=$(cat "$PASSWORD_FILE" 2>/dev/null || true)
    fi
    if [ -z "$API_PASSWORD" ]; then
        read -srp "Password: " API_PASSWORD
        printf '\n'
        if [[ "$OSTYPE" == darwin* ]]; then
            security add-generic-password -U -s hawking -a "$API_USERNAME" -w "$API_PASSWORD" 2>/dev/null || true
        elif command -v secret-tool >/dev/null 2>&1; then
            printf '%s' "$API_PASSWORD" | secret-tool store --label='Hawking CLI' service hawking username "$API_USERNAME" 2>/dev/null || true
        else
            read -rp "No system keychain available. Save password in plaintext at ${PASSWORD_FILE}? [y/N] " save_plaintext
            if [[ "$save_plaintext" =~ ^[Yy]$ ]]; then
                ( umask 077; printf '%s' "$API_PASSWORD" > "$PASSWORD_FILE" ) 2>/dev/null || true
            fi
        fi
    fi
    [ -n "$API_PASSWORD" ] || return 1

    if ! API_AUTH_RESPONSE=$(api_get "$API_BASE_URL/auth"); then
        return 1
    fi
    if ! echo "$API_AUTH_RESPONSE" | jq -e '.user' >/dev/null 2>&1; then
        return 1
    fi

    printf '%s\n' "$API_USERNAME" > "$USER_FILE"
    chmod 600 "$USER_FILE"
    API_AUTHENTICATED=true
}

resolve_module_for_file() {
    local filename="$1"
    local modules_json
    local module_count
    local selected_index=0

    modules_json=$(api_get "$API_BASE_URL/moduleForTask/$filename" 2>/dev/null || true)
    module_count=$(printf '%s' "$modules_json" | jq 'length' 2>/dev/null || printf '0')
    if [ "$module_count" -eq 0 ]; then
        return 1
    fi
    if [ "$module_count" -gt 1 ]; then
        if [ -n "$ASSIGNMENT_ID" ]; then
            selected_index=$(printf '%s' "$modules_json" | jq --arg id "$ASSIGNMENT_ID" 'to_entries | map(select((.value.id | tostring) == $id)) | .[0].key // 0')
        else
            printf '%s\n' "Multiple modules found for $filename:" >&2
            printf '%s\n' "$modules_json" | jq -r '.[] | "  \(.id): \(.banner // .legacy // "unknown")"' >&2
            read -rp "Module ID: " ASSIGNMENT_ID
            selected_index=$(printf '%s' "$modules_json" | jq --arg id "$ASSIGNMENT_ID" 'to_entries | map(select((.value.id | tostring) == $id)) | .[0].key // -1')
            [ "$selected_index" -ge 0 ] || return 1
        fi
    fi

    CURRENT_ASSIGNMENT_ID=$(printf '%s' "$modules_json" | jq -r ".[$selected_index].id")
    MODULE_CODE=$(printf '%s' "$modules_json" | jq -r ".[$selected_index].banner // .[$selected_index].legacy // \"unknown\"")
    save_cached_id "$CURRENT_ASSIGNMENT_ID"
}

# ---- Legacy web-session helpers retained for compatibility ----
check_hawking_connection() {
    if ! curl -s --head --connect-timeout "$HEALTHCHECK_TIMEOUT" "$BASE_URL" >/dev/null 2>&1; then
        echo -e "${RED}Error: ${BOLD}Cannot connect to Hawking${RESET}${RED}. The server may be down or unreachable.${RESET}"
        exit 1
    fi
}

is_cookie_expired() {
    if [ ! -f "$COOKIE_FILE" ]; then
        return 0
    fi
    local now_epoch
    now_epoch=$(date +%s)
    local mtime
    mtime=$(stat -c %Y "$COOKIE_FILE" 2>/dev/null || stat -f %m "$COOKIE_FILE" 2>/dev/null || echo 0)
    local age=$(( now_epoch - mtime ))
    [ $age -gt "$COOKIE_TTL" ]
}

is_cookie_valid() {
    local session_response
    session_response=$(curl -s -L --connect-timeout "$CONNECT_TIMEOUT" -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$BASE_URL" || true)
    if echo "$session_response" | grep -qE 'name="(_username|_password)"|action="[^"]*/login'; then
        return 1
    fi
    return 0
}

prompt_for_cookie() {
    check_hawking_connection
    if [ "$VOCAL" = true ]; then
        echo -e "${YELLOW}Session missing, expired, or invalid. ${BOLD}Triggering auto-login${RESET}${YELLOW} via hawking-login...${RESET}"
    fi
    
    local login_arg=""
    [ "$VOCAL" = true ] && login_arg="--vocal"

    if command -v hawking-login &> /dev/null; then
        hawking-login $login_arg
    elif [ -x "$HOME/.hawking/bin/hawking-login" ]; then
        "$HOME/.hawking/bin/hawking-login" $login_arg
    else
        echo -e "${RED}Error: hawking-login command ${BOLD}not found${RESET}${RED}.${RESET}"
        exit 1
    fi

    if [ ! -f "$COOKIE_FILE" ]; then
        echo -e "${RED}Failed to acquire ${BOLD}valid session cookie${RESET}${RED}.${RESET}"
        exit 1
    fi
}

# ---- Upload request function ----
execute_upload() {
    local target_id="$1"
    local file_to_upload="$2"
    local api_response
    api_response=$(curl -sS --fail --connect-timeout "$CONNECT_TIMEOUT" \
        -u "$API_USERNAME:$API_PASSWORD" \
        -F "file=@${file_to_upload}" \
        "$API_BASE_URL/upload/${target_id}/$(basename "$file_to_upload")" 2>/dev/null) || return 1

    printf '%s' "$api_response" | jq -c --arg authenticated_user "$API_USERNAME" '
        .output as $output |
        ($output.tests // []) as $tests |
        ($output.results // []) as $results |
        {
            attempt: ($output.attempt + {
                submitterUsername: ($output.attempt.submitterUsername // $authenticated_user),
                testResults: [
                    range(0; ($results | length)) as $i |
                    ($results[$i] + {
                        testId: ($tests[$i].testId // $i),
                        execTimeMillis: ($results[$i].execTimeMillis // $results[$i].execTime // 0),
                        testResultMessage: ($results[$i].testResultMessage // $results[$i].message // "")
                    })
                ]
            }),
            tests: (reduce range(0; ($tests | length)) as $i
                ({}; .[($tests[$i].testId // $i | tostring)] = ($tests[$i] + {
                    testId: ($tests[$i].testId // $i),
                    testStdout: ($tests[$i].testStdout // $tests[$i].expectedStdout // "" | @base64)
                })))
        }
    '
}

is_valid_attempt() {
    local code="$1"
    local resp="$2"
    if [ "$code" -eq 200 ] && echo "$resp" | jq -e '.attempt' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ---- Argument Parsing with Smart Detection ----
ASSIGNMENT_ID=""
FILES=()

if [ ${#ARGS[@]} -ge 1 ]; then
    if [[ "${ARGS[0]}" =~ ^[0-9]+$ ]]; then
        ASSIGNMENT_ID="${ARGS[0]}"
        FILES=("${ARGS[@]:1}")
    else
        FILES=("${ARGS[@]}")
    fi
fi

if [ ${#FILES[@]} -gt 0 ]; then
    valid_files=()
    for f in "${FILES[@]}"; do
        if [ ! -f "$f" ]; then
            echo -e "${RED}Error: ${BOLD}No such file exists${RESET}${RED}: ${BOLD}${f}${RESET}"
            exit 1
        fi
        filename=$(basename "$f")
        if [[ "$filename" == "$IGNORE_SCRIPT" || "$filename" != *.* ]] || { [ "$IGNORE_HIDDEN" = true ] && [[ "$filename" == .* ]]; }; then
            continue
        fi
        ignored=false
        IFS=',' read -ra ignored_extensions <<< "$IGNORE_EXTENSIONS"
        for extension in "${ignored_extensions[@]}"; do
            if [[ "$filename" == *"$extension" ]]; then
                ignored=true
                break
            fi
        done
        [ "$ignored" = true ] || valid_files+=("$f")
    done
    if [ ${#valid_files[@]} -gt 0 ]; then
        FILES=("${valid_files[@]}")
    else
        FILES=()
        echo -e "${RED}No ${BOLD}suitable files found${RESET}${RED} to upload.${RESET}"
        exit 1
    fi
fi

if [ -z "$ASSIGNMENT_ID" ]; then
    ASSIGNMENT_ID=$(get_cached_ids | head -n 1 || true)
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is required but ${BOLD}not installed${RESET}${RED}.${RESET}"
    exit 1
fi

# ---- File Selection ----
IS_MULTI=false
if [ ${#FILES[@]} -eq 0 ]; then
    IGNORE_PATTERN="^(${SCRIPT_NAME}|${IGNORE_SCRIPT}|[^.]+$"
    [ "$IGNORE_HIDDEN" = true ] && IGNORE_PATTERN+="|\..*"
    [ -n "$IGNORE_EXTENSIONS" ] && IGNORE_PATTERN+="|.*${IGNORE_EXTENSIONS//,/|}$"
    IGNORE_PATTERN+=")$"
    NEWEST_FILE=$(ls -t 2>/dev/null | grep -v -E "$IGNORE_PATTERN" | head -n 1 || true)
    if [ -z "$NEWEST_FILE" ]; then
        echo -e "${RED}No ${BOLD}suitable file found${RESET}${RED} in current directory.${RESET}"
        exit 1
    fi
    FILES=("$NEWEST_FILE")
    if [ "$VOCAL" = true ]; then
        echo -e "${YELLOW}Using ${BOLD}most recently modified file${RESET}${YELLOW}: ${BOLD}${FILES[0]}${RESET}"
    fi
elif [ ${#FILES[@]} -gt 1 ]; then
    IS_MULTI=true
else
    expanded_files=()
    for f in "${FILES[@]}"; do
        if [ -f "$f" ]; then
            [ "$f" != "$SCRIPT_NAME" ] && expanded_files+=("$f")
        fi
    done
    if [ ${#expanded_files[@]} -gt 1 ]; then
        IS_MULTI=true
        FILES=("${expanded_files[@]}")
    fi
fi

if ! authenticate_api; then
    echo -e "${RED}Error: ${BOLD}API authentication failed${RESET}${RED}.${RESET}"
    exit 1
fi

if [ "$IS_MULTI" = false ] && [ "$VOCAL" = true ]; then
    echo -e "${YELLOW}Using ${BOLD}cached module ID${RESET}${YELLOW}: ${BOLD}${ASSIGNMENT_ID}${RESET}"
fi

decode_b64() {
    local input="$1"
    if [ -z "$input" ]; then
        echo ""
        return
    fi
    echo "$input" | base64 --decode 2>/dev/null || echo "$input" | base64 -D 2>/dev/null || echo ""
}

decode_field() {
    local decoded
    decoded=$(decode_b64 "$1")
    printf '%s' "${decoded#x}"
}

open_runners() {
    if ! command -v nvim &> /dev/null; then
        echo -e "${RED}Error: ${BOLD}nvim is required${RESET}${RED} for --runner.${RESET}"
        return 1
    fi

    if [ ${#RUNNER_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No ${BOLD}runner source${RESET}${YELLOW} was included in the response.${RESET}"
        return 0
    fi

    if nvim -p "${RUNNER_FILES[@]}"; then
        :
    else
        local nvim_status=$?
        rm -rf "$RUNNER_DIR"
        RUNNER_DIR=""
        RUNNER_FILES=()
        return "$nvim_status"
    fi
    rm -rf "$RUNNER_DIR"
    RUNNER_DIR=""
    RUNNER_FILES=()
}

prepare_runner_files() {
    local response="$1"
    local test_id
    local test_filename
    local runner_file

    RUNNER_DIR=""
    RUNNER_FILES=()

    while IFS=$'\t' read -r test_id test_filename; do
        [ -n "$test_id" ] || continue
        [ -n "$RUNNER_DIR" ] || RUNNER_DIR=$(mktemp -d)
        test_filename=$(basename "${test_filename:-runner.py}")
        runner_file="${RUNNER_DIR}/${test_id}-${test_filename}"
        printf '%s\n' "$response" | jq -r --arg test_id "$test_id" '.tests[$test_id].testCode' > "$runner_file"
        RUNNER_FILES+=("$runner_file")
    done < <(printf '%s\n' "$response" | jq -r '.tests // {} | to_entries[] | select(.value.testCode? != null and .value.testCode != "") | [.key, (.value.testCodeFilename // "runner.py")] | @tsv')
}

make_rule() {
    printf '%*s' "$1" '' | sed 's/ /─/g'
}

get_terminal_width() {
    local width
    width=$(stty size < /dev/tty 2>/dev/null | awk '{ print $2 }' || true)
    if [[ ! "$width" =~ ^[0-9]+$ ]]; then
        width=$(tput cols 2>/dev/null || true)
    fi
    if [[ ! "$width" =~ ^[0-9]+$ ]]; then
        width="${COLUMNS:-80}"
    fi
    [ "$width" -lt 1 ] && width=80
    printf '%s' "$width"
}

expand_tabs() {
    printf '%s' "$1" | LC_ALL=C expand -t 8
}

MODULE_CODE_FILE=$(mktemp)
trap 'rm -f "$MODULE_CODE_FILE"' EXIT
RUNNER_DIR=""
RUNNER_FILES=()

# ---- Process Each File ----
if [ "$IS_MULTI" = true ]; then
    MULTIFILE_USER="unknown"
    [ -f "$USER_FILE" ] && MULTIFILE_USER=$(tr -d '[:space:]' < "$USER_FILE")
    MULTIFILE_TITLE="User: ${MULTIFILE_USER}"
    MULTIFILE_WIDTH=$(printf '%s\n' "${FILES[@]}" | awk '{ status = "x " $0 " - (00/00)"; rejected = "x " $0 " - FAILED (Rejected)"; gsub(/[—✓✗]/, "x", status); if (length(status) > max) max = length(status); if (length(rejected) > max) max = length(rejected) } END { print max + 2 }')
    [ ${#MULTIFILE_TITLE} -gt $((MULTIFILE_WIDTH - 3)) ] && MULTIFILE_WIDTH=$((${#MULTIFILE_TITLE} + 3))
    MULTIFILE_TITLE_FILL=$((MULTIFILE_WIDTH - ${#MULTIFILE_TITLE} - 3))
    [ "$MULTIFILE_TITLE_FILL" -lt 1 ] && MULTIFILE_TITLE_FILL=1
    echo -e "${BOLD}${CYAN}╭─ ${MULTIFILE_TITLE} $(make_rule "$MULTIFILE_TITLE_FILL")╮${RESET}"
fi

for FILE in "${FILES[@]}"; do
    [ -f "$FILE" ] || continue
    [ "$FILE" == "$SCRIPT_NAME" ] && continue

    if ! resolve_module_for_file "$(basename "$FILE")"; then
        if [ "$IS_MULTI" = true ]; then
            MULTIFILE_STATUS="✗ ${FILE} — FAILED (Rejected)"
            printf "${CYAN}│${RESET} ${RED}${BOLD}%s${RESET}%*s ${CYAN}│${RESET}\n" "$MULTIFILE_STATUS" "$((MULTIFILE_WIDTH - ${#MULTIFILE_STATUS} - 2))" ""
        else
            echo -e "${RED}No module found for ${BOLD}$(basename "$FILE")${RESET}"
        fi
        continue
    fi

    if [ "$IS_MULTI" = false ] && [ "$VOCAL" = true ]; then
        echo -e "${YELLOW}Uploading ${BOLD}${FILE}${RESET}${YELLOW} to assignment ${BOLD}${ASSIGNMENT_ID}${RESET}${YELLOW}...${RESET}"
    fi

    RESPONSE=$(execute_upload "$CURRENT_ASSIGNMENT_ID" "$FILE" || true)

    if [ -z "$RESPONSE" ] || ! echo "$RESPONSE" | jq -e '.attempt' >/dev/null 2>&1; then
        if [ "$IS_MULTI" = true ]; then
            MULTIFILE_STATUS="✗ ${FILE} — FAILED (Rejected)"
            printf "${CYAN}│${RESET} ${RED}${BOLD}%s${RESET}%*s ${CYAN}│${RESET}\n" "$MULTIFILE_STATUS" "$((MULTIFILE_WIDTH - ${#MULTIFILE_STATUS} - 2))" ""
        else
            echo -e "${RED}Upload failed for ${BOLD}${FILE}${RESET}"
        fi
        continue
    fi

    save_cached_id "$CURRENT_ASSIGNMENT_ID"

    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}=== Full JSON Response (Debug) ===${RESET}"
        echo "$RESPONSE" | jq .
    fi

    prepare_runner_files "$RESPONSE"
    if [ ${#RUNNER_FILES[@]} -gt 0 ]; then
        RUNNERS_STATUS="available"
        RUNNERS_STATUS_COLOR="$GREEN"
    else
        RUNNERS_STATUS="unavailable"
        RUNNERS_STATUS_COLOR="$BLUE"
    fi

    if [ "$SHOW_RUNNER" = true ]; then
        open_runners "$RESPONSE"
        continue
    fi

    if [ "$IS_MULTI" = true ]; then
        STATS=$(echo "$RESPONSE" | jq -r '
            [.attempt.testResults[]? .correct] |
            [
              (map(select(.)) | length),
              length
            ] | @tsv
        ')
        read -r PASSED_COUNT TOTAL_COUNT <<< "$STATS"
        TOTAL_COUNT="${TOTAL_COUNT:-0}"
        PASSED_COUNT="${PASSED_COUNT:-0}"

        if [ "$TOTAL_COUNT" -gt 0 ] && [ "$PASSED_COUNT" -eq "$TOTAL_COUNT" ]; then
            MULTIFILE_STATUS="✓ ${FILE} — (${PASSED_COUNT}/${TOTAL_COUNT})"
            MULTIFILE_ROW_COLOR="$GREEN"
        else
            MULTIFILE_STATUS="✗ ${FILE} — (${PASSED_COUNT}/${TOTAL_COUNT})"
            MULTIFILE_ROW_COLOR="$RED"
        fi
        ATTEMPT_ID=$(echo "$RESPONSE" | jq -r '.attempt.id')
        RESULT_URL="${BASE_URL}/${CURRENT_ASSIGNMENT_ID}/result/${ATTEMPT_ID}"
        printf "${CYAN}│${RESET} "
        printf '\033]8;;%s\033\\%b%s%b\033]8;;\033\\' "$RESULT_URL" "$MULTIFILE_ROW_COLOR$BOLD" "$MULTIFILE_STATUS" "$RESET"
        printf "%*s ${CYAN}│${RESET}\n" "$((MULTIFILE_WIDTH - ${#MULTIFILE_STATUS} - 2))" ""
    else
        SUBMITTER_USERNAME=$(echo "$RESPONSE" | jq -r '.attempt.submitterUsername // "unknown"')
        ATTEMPT_CONTENT_WIDTH=19
        [ $((13 + ${#RUNNERS_STATUS})) -gt "$ATTEMPT_CONTENT_WIDTH" ] && ATTEMPT_CONTENT_WIDTH=$((13 + ${#RUNNERS_STATUS}))
        [ $((13 + ${#CURRENT_ASSIGNMENT_ID})) -gt "$ATTEMPT_CONTENT_WIDTH" ] && ATTEMPT_CONTENT_WIDTH=$((13 + ${#CURRENT_ASSIGNMENT_ID}))
        [ $((13 + ${#MODULE_CODE})) -gt "$ATTEMPT_CONTENT_WIDTH" ] && ATTEMPT_CONTENT_WIDTH=$((13 + ${#MODULE_CODE}))
        DISPLAY_FILENAME=$(basename "$FILE")
        [ $((13 + ${#DISPLAY_FILENAME})) -gt "$ATTEMPT_CONTENT_WIDTH" ] && ATTEMPT_CONTENT_WIDTH=$((13 + ${#DISPLAY_FILENAME}))
        [ $((13 + ${#SUBMITTER_USERNAME})) -gt "$ATTEMPT_CONTENT_WIDTH" ] && ATTEMPT_CONTENT_WIDTH=$((13 + ${#SUBMITTER_USERNAME}))
        ATTEMPT_TITLE_FILL=$((ATTEMPT_CONTENT_WIDTH - 13))
        FILE_PATH="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
        FILE_URL="file://${FILE_PATH// /%20}"

        echo -e "${BOLD}${CYAN}╭─ Attempt Info $(make_rule "$ATTEMPT_TITLE_FILL")╮${RESET}"
        printf "${CYAN}│${RESET} ${BOLD}%-12s${RESET} ${BLUE}%-*s${RESET} ${CYAN}│${RESET}\n" "User:" "$((ATTEMPT_CONTENT_WIDTH - 13))" "$SUBMITTER_USERNAME"
        printf "${CYAN}│${RESET} ${BOLD}%-12s${RESET} ${BLUE}%-*s${RESET} ${CYAN}│${RESET}\n" "Module ID:" "$((ATTEMPT_CONTENT_WIDTH - 13))" "$CURRENT_ASSIGNMENT_ID"
        printf "${CYAN}│${RESET} ${BOLD}%-12s${RESET} ${BLUE}%-*s${RESET} ${CYAN}│${RESET}\n" "Module Code:" "$((ATTEMPT_CONTENT_WIDTH - 13))" "$MODULE_CODE"
        printf "${CYAN}│${RESET} ${BOLD}%-12s${RESET} ${BLUE}" "Filename:"
        printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$FILE_URL" "$DISPLAY_FILENAME"
        printf "${RESET}%*s ${CYAN}│${RESET}\n" "$((ATTEMPT_CONTENT_WIDTH - 13 - ${#DISPLAY_FILENAME}))" ""
        printf "${CYAN}│${RESET} ${BOLD}%-12s${RESET} ${RUNNERS_STATUS_COLOR}%-*s${RESET} ${CYAN}│${RESET}\n" "Runners:" "$((ATTEMPT_CONTENT_WIDTH - 13))" "$RUNNERS_STATUS"
        echo -e "${BOLD}${CYAN}╰$(make_rule "$((ATTEMPT_CONTENT_WIDTH + 2))")╯${RESET}"

                TEST_ROWS=$(echo "$RESPONSE" | jq -r '
                    .tests as $tests |
                    .attempt.testResults[] |
                    .testId as $tid |
                    ($tests[$tid | tostring] // {}) as $tdef |
                    [
                        .testId,
                        (.correct | tostring),
                        (.execTimeMillis | tostring),
                        (("x" + ($tdef.testStdout // "")) | @base64),
                        (("x" + (.stdout // "")) | @base64),
                        (("x" + (.stderr // "")) | @base64),
                        (("x" + (.testResultMessage // "")) | @base64)
                    ] | @tsv
                ')
                TEST_CONTENT_WIDTH=$(echo "$RESPONSE" | jq -r '
                    def detail: gsub("\n"; "\n    | ") | "    | " + .;
                    .tests as $tests |
                    .attempt.testResults[] as $result |
                    ($tests[$result.testId | tostring] // {}) as $test |
                    ($test.testStdout // "" | if . == "" then "" else @base64d end) as $expected |
                    ($result.stdout // "") as $stdout |
                    ($result.stderr // "") as $stderr |
                    ($result.testResultMessage // "") as $message |
                    (if $stdout != "" then $stdout elif $message != "" then $message else $stderr end) as $actual |
                    [
                        ("x PASSED - test " + ($result.testId | tostring) + " (" + ($result.execTimeMillis | tostring) + "ms)"),
                        ("x FAILED - test " + ($result.testId | tostring) + " (" + ($result.execTimeMillis | tostring) + "ms)"),
                        "  Expected:",
                        "  Actual:  ",
                        ($expected | detail),
                        ($actual | detail),
                        (if $stderr == "" then "" else ($stderr | detail) end)
                    ][]
                ' | LC_ALL=C expand -t 8 | awk '{ gsub(/[│✓✗—‘’]/, "x"); if (length > max) max = length } END { print max }')
        TEST_CONTENT_WIDTH=${TEST_CONTENT_WIDTH:-20}
        TERMINAL_WIDTH=$(get_terminal_width)
        MAX_TEST_CONTENT_WIDTH=$((TERMINAL_WIDTH - 4))
        [ "$MAX_TEST_CONTENT_WIDTH" -lt 20 ] && MAX_TEST_CONTENT_WIDTH=20
        [ "$TEST_CONTENT_WIDTH" -gt "$MAX_TEST_CONTENT_WIDTH" ] && TEST_CONTENT_WIDTH="$MAX_TEST_CONTENT_WIDTH"
                if echo "$RESPONSE" | jq -e '.attempt.testResults[] | select(.correct != true)' >/dev/null; then
                    TEST_BORDER_COLOR="$RED"
                else
                    TEST_BORDER_COLOR="$GREEN"
                fi
                echo -e "${BOLD}${TEST_BORDER_COLOR}╭─ Test Results $(make_rule "$((TEST_CONTENT_WIDTH - 13))")╮${RESET}"

        ALL_PASSED=true
        PASSED_TESTS=0
        TOTAL_TESTS=0
        PREVIOUS_TEST_HAD_DETAILS=false

        while IFS=$'\t' read -r TEST_ID CORRECT EXEC_TIME EXPECTED_B64 STDOUT_B64 STDERR_B64 RESULT_MESSAGE_B64; do
            if [ "$PREVIOUS_TEST_HAD_DETAILS" = true ]; then
                printf "${TEST_BORDER_COLOR}│${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$((TEST_CONTENT_WIDTH + 2))" ""
            fi
            TEST_HAD_DETAILS=false
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            STDOUT=$(expand_tabs "$(decode_field "$STDOUT_B64")"; printf '\001')
            STDOUT=${STDOUT%$'\001'}
            STDERR=$(expand_tabs "$(decode_field "$STDERR_B64")"; printf '\001')
            STDERR=${STDERR%$'\001'}
            EXPECTED=$(decode_b64 "$(decode_field "$EXPECTED_B64")"; printf '\001')
            EXPECTED=${EXPECTED%$'\001'}
            EXPECTED=$(expand_tabs "$EXPECTED"; printf '\001')
            EXPECTED=${EXPECTED%$'\001'}
            RESULT_MESSAGE=$(expand_tabs "$(decode_field "$RESULT_MESSAGE_B64")"; printf '\001')
            RESULT_MESSAGE=${RESULT_MESSAGE%$'\001'}

            if [ "$CORRECT" == "true" ]; then
                PASSED_TESTS=$((PASSED_TESTS + 1))
                TEST_STATUS="✓ PASSED — test ${TEST_ID} (${EXEC_TIME}ms)"
                printf "${TEST_BORDER_COLOR}│${RESET} ${GREEN}${BOLD}%s${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$TEST_STATUS" "$((TEST_CONTENT_WIDTH - ${#TEST_STATUS} + 1))" ""
            else
                ALL_PASSED=false
                TEST_STATUS="✗ FAILED — test ${TEST_ID} (${EXEC_TIME}ms)"
                printf "${TEST_BORDER_COLOR}│${RESET} ${RED}${BOLD}%s${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$TEST_STATUS" "$((TEST_CONTENT_WIDTH - ${#TEST_STATUS} + 1))" ""
                
                ACT_CLEAN=$(printf '%s' "$STDOUT" | tr -d '\r'; printf '\001')
                ACT_CLEAN=${ACT_CLEAN%$'\001'}
                EXP_CLEAN=$(printf '%s' "$EXPECTED" | tr -d '\r'; printf '\001')
                EXP_CLEAN=${EXP_CLEAN%$'\001'}

                if [ "$ACT_CLEAN" != "$EXP_CLEAN" ]; then
                    TEST_HAD_DETAILS=true
                    IS_MULTILINE=false
                    if [[ "$ACT_CLEAN" == *$'\n'* ]] || [[ "$EXP_CLEAN" == *$'\n'* ]]; then
                        IS_MULTILINE=true
                    fi

                    if [ "$IS_MULTILINE" = true ]; then
                    printf "${TEST_BORDER_COLOR}│${RESET}  ${BOLD}Expected:${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$((TEST_CONTENT_WIDTH - 9))" ""
                    printf '%s\n' "${EXP_CLEAN:-<empty>}" | awk -v width="$TEST_CONTENT_WIDTH" -v border="${TEST_BORDER_COLOR}" -v white="${WHITE}" -v reset="${RESET}" '
                    {
                        text = ($0 == "" ? "<newline>" : $0)
                        for (start = 1; start <= length(text); start += width - 6) {
                            chunk = substr(text, start, width - 6)
                            padding = width - 6 - length(chunk)
                            printf "%s│%s     %s|%s %s%s %s│%s\n", border, reset, white, reset, chunk, sprintf("%*s", padding, ""), border, reset
                        }
                    }'
                    printf "${TEST_BORDER_COLOR}│${RESET}  ${BOLD}Actual:  ${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$((TEST_CONTENT_WIDTH - 9))" ""
                    EXP_DATA="$EXP_CLEAN" ACT_DATA="$ACT_CLEAN" awk -v width="$TEST_CONTENT_WIDTH" -v border="${TEST_BORDER_COLOR}" -v white="${WHITE}" -v green="${GREEN}" -v red="${RED}" -v reset="${RESET}" '
                    BEGIN {
                        n_exp = split(ENVIRON["EXP_DATA"], exp_lines, "\n")
                        n_act = split(ENVIRON["ACT_DATA"], act_lines, "\n")
                        if (ENVIRON["ACT_DATA"] == "") {
                            n_act = 1
                            act_lines[1] = ""
                        }
                        for (i = 1; i <= n_act; i++) {
                            line = act_lines[i]
                            display_line = (line == "" ? (ENVIRON["ACT_DATA"] == "" ? "<empty>" : "<newline>") : line)
                            for (start = 1; start <= length(display_line); start += width - 6) {
                                chunk = substr(display_line, start, width - 6)
                                padding = width - 6 - length(chunk)
                                color = (i <= n_exp && line == exp_lines[i]) ? green : red
                                printf "%s│%s     %s|%s %s%s%s%s %s│%s\n", border, reset, white, reset, color, chunk, reset, sprintf("%*s", padding, ""), border, reset
                            }
                        }
                    }'
                    else
                    printf "${TEST_BORDER_COLOR}│${RESET}  ${BOLD}Expected:${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$((TEST_CONTENT_WIDTH - 9))" ""
                    EXPECTED_DISPLAY="${EXP_CLEAN:-<empty>}"
                    printf '%s\n' "$EXPECTED_DISPLAY" | fold -w "$((TEST_CONTENT_WIDTH - 6))" | while IFS= read -r EXPECTED_LINE; do
                        EXPECTED_PADDING=$((TEST_CONTENT_WIDTH - ${#EXPECTED_LINE} - 6))
                        printf "${TEST_BORDER_COLOR}│${RESET}     ${WHITE}|${RESET} %s%*s ${TEST_BORDER_COLOR}│${RESET}\n" "$EXPECTED_LINE" "$EXPECTED_PADDING" ""
                    done
                    printf "${TEST_BORDER_COLOR}│${RESET}  ${BOLD}Actual:  ${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$((TEST_CONTENT_WIDTH - 9))" ""

                    ACT_LEN=${#ACT_CLEAN}
                    EXP_LEN=${#EXP_CLEAN}
                    MAX_LEN=$ACT_LEN
                    [ $EXP_LEN -gt $MAX_LEN ] && MAX_LEN=$EXP_LEN
                    DISPLAY_COLUMN=0

                    printf "${TEST_BORDER_COLOR}│${RESET}     ${WHITE}|${RESET} "
                    if [ "$ACT_LEN" -eq 0 ]; then
                        ACTUAL_DISPLAY="<empty>"
                        printf "${RED}%s${RESET}" "$ACTUAL_DISPLAY"
                        DISPLAY_COLUMN=${#ACTUAL_DISPLAY}
                    else
                        DISPLAY_WIDTH=$((TEST_CONTENT_WIDTH - 6))
                        for (( i=0; i<MAX_LEN; i++ )); do
                            CHAR_ACT="${ACT_CLEAN:$i:1}"
                            CHAR_EXP="${EXP_CLEAN:$i:1}"

                            if [ "$CHAR_ACT" == "$CHAR_EXP" ] && [ -n "$CHAR_ACT" ]; then
                                printf "%s" "$CHAR_ACT"
                            else
                                PRINT_CHAR="${CHAR_ACT:- }"
                                printf "${RED}%s${RESET}" "$PRINT_CHAR"
                            fi
                            DISPLAY_COLUMN=$((DISPLAY_COLUMN + 1))
                            if [ "$DISPLAY_COLUMN" -eq "$DISPLAY_WIDTH" ] && [ $((i + 1)) -lt "$MAX_LEN" ]; then
                                printf "%*s ${TEST_BORDER_COLOR}│${RESET}\n${TEST_BORDER_COLOR}│${RESET}     ${WHITE}|${RESET} " "$((TEST_CONTENT_WIDTH - 6 - DISPLAY_COLUMN))" ""
                                DISPLAY_COLUMN=0
                            fi
                        done
                    fi
                    ACTUAL_PADDING=$((TEST_CONTENT_WIDTH - 6 - DISPLAY_COLUMN))
                    [ "$ACTUAL_PADDING" -lt 0 ] && ACTUAL_PADDING=0
                    printf "%*s ${TEST_BORDER_COLOR}│${RESET}\n" "$ACTUAL_PADDING" ""
                    fi
                fi
            fi

            if [ -n "$RESULT_MESSAGE" ]; then
                TEST_HAD_DETAILS=true
                printf "${TEST_BORDER_COLOR}│${RESET}  ${RED}${BOLD}Stderr:  ${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$((TEST_CONTENT_WIDTH - 9))" ""
                printf '%s\n' "$(printf '%s' "$RESULT_MESSAGE" | tr -d '\r')" | awk -v width="$TEST_CONTENT_WIDTH" -v border="${TEST_BORDER_COLOR}" -v white="${WHITE}" -v reset="${RESET}" '{ line = "    | " $0; plain_line = line; gsub(/[‘’]/, "x", plain_line); padding = width - length(plain_line); if (padding < 0) padding = 0; printf "%s│%s     %s|%s %s%s %s│%s\n", border, reset, white, reset, $0, sprintf("%*s", padding, ""), border, reset }'
            fi

            if [ -n "$STDERR" ]; then
                TEST_HAD_DETAILS=true
                printf "${TEST_BORDER_COLOR}│${RESET}  ${RED}${BOLD}Stderr:  ${RESET}%*s${TEST_BORDER_COLOR}│${RESET}\n" "$((TEST_CONTENT_WIDTH - 9))" ""
                printf '%s\n' "$(printf '%s' "$STDERR" | tr -d '\r')" | awk -v width="$TEST_CONTENT_WIDTH" -v border="${TEST_BORDER_COLOR}" -v white="${WHITE}" -v reset="${RESET}" '{ line = "    | " $0; plain_line = line; gsub(/[‘’]/, "x", plain_line); padding = width - length(plain_line); printf "%s│%s     %s|%s %s%s %s│%s\n", border, reset, white, reset, $0, sprintf("%*s", padding, ""), border, reset }'
            fi
            PREVIOUS_TEST_HAD_DETAILS="$TEST_HAD_DETAILS"
                done <<< "$TEST_ROWS"

            echo -e "${BOLD}${TEST_BORDER_COLOR}╰$(make_rule "$((TEST_CONTENT_WIDTH + 2))")╯${RESET}"

        if [ "$ALL_PASSED" = true ]; then
            ATTEMPT_ID=$(echo "$RESPONSE" | jq -r '.attempt.id')
            RESULT_URL="${BASE_URL}/${CURRENT_ASSIGNMENT_ID}/result/${ATTEMPT_ID}"
            printf '\033]8;;%s\033\\%b%s%b\033]8;;\033\\' "$RESULT_URL" "$GREEN$BOLD" "✓ ${FILE} — (${PASSED_TESTS}/${TOTAL_TESTS})" "$RESET"
            printf '\n'
        else
            ATTEMPT_ID=$(echo "$RESPONSE" | jq -r '.attempt.id')
            RESULT_URL="${BASE_URL}/${CURRENT_ASSIGNMENT_ID}/result/${ATTEMPT_ID}"
            printf '\033]8;;%s\033\\%b%s%b\033]8;;\033\\' "$RESULT_URL" "$RED$BOLD" "✗ ${FILE} — (${PASSED_TESTS}/${TOTAL_TESTS})" "$RESET"
            printf '\n'
        fi
    fi
done

if [ "$IS_MULTI" = true ]; then
    echo -e "${BOLD}${CYAN}╰$(make_rule "$MULTIFILE_WIDTH")╯${RESET}"
fi

#!/bin/bash

set -euo pipefail

BASE_URL="https://hawking.computing.dcu.ie/hawking"
COOKIE_FILE="$HOME/.hawking_cookie"
CACHE_FILE="$HOME/.hawking_history"
SCRIPT_NAME="$(basename "$0")"

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
RESET="\033[0m"

# ---- Parse Flags & Options ----
DEBUG=false
CLEAR_CACHE=false
SHOW_MODULES=false
ADD_MODULE_ID=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG=true
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

# ---- Handle --clear-cache ----
if [ "$CLEAR_CACHE" = true ]; then
    rm -f "$CACHE_FILE"
    echo -e "${GREEN}Cache **cleared successfully**.${RESET}"
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
        echo -e "${YELLOW}No **cached module IDs** found.${RESET}"
    fi
    exit 0
fi

# ---- Handle --add-module ----
if [ -n "$ADD_MODULE_ID" ]; then
    if [[ ! "$ADD_MODULE_ID" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Module ID must be a **valid number**.${RESET}"
        exit 1
    fi
    temp_file=$(mktemp)
    echo "$ADD_MODULE_ID" > "$temp_file"
    if [ -f "$CACHE_FILE" ]; then
        grep -v "^${ADD_MODULE_ID}$" "$CACHE_FILE" >> "$temp_file" || true
    fi
    mv "$temp_file" "$CACHE_FILE"
    echo -e "${GREEN}Successfully **added module ID** ${BOLD}${ADD_MODULE_ID}${RESET}${GREEN} to cache.${RESET}"
    exit 0
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

# ---- Argument Parsing with Smart Detection ----
ASSIGNMENT_ID=""
FILE=""

if [ ${#ARGS[@]} -ge 1 ]; then
    if [[ "${ARGS[0]}" =~ ^[0-9]+$ ]]; then
        ASSIGNMENT_ID="${ARGS[0]}"
        FILE="${ARGS[1]:-}"
    else
        FILE="${ARGS[0]}"
    fi
fi

if [ -z "$ASSIGNMENT_ID" ]; then
    ASSIGNMENT_ID=$(get_cached_ids | head -n 1 || true)
    if [ -z "$ASSIGNMENT_ID" ]; then
        echo -e "${RED}Error: **No module ID specified** and no cache history found.${RESET}"
        echo -e "${YELLOW}Guidance:${RESET} Add a module ID manually using:"
        echo -e "  ${BOLD}$SCRIPT_NAME --add-module <YOUR_MODULE_ID>${RESET}"
        echo -e "  *(Note: For a URL like ${BOLD}https://hawking.computing.dcu.ie/hawking/124${RESET}, the ID is ${BOLD}124${RESET})*"
        echo -e "Or pass it directly as the first argument:"
        echo -e "  ${BOLD}$SCRIPT_NAME <YOUR_MODULE_ID> [file_to_submit]${RESET}"
        exit 1
    fi
    echo -e "${YELLOW}Using **cached module ID**: ${BOLD}${ASSIGNMENT_ID}${RESET}"
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is required but **not installed**.${RESET}"
    exit 1
fi

# ---- Find newest file if not provided ----
if [ -z "$FILE" ]; then
    FILE=$(ls -t 2>/dev/null | grep -v -E "^($SCRIPT_NAME|\..*)$" | head -n 1 || true)
    if [ -z "$FILE" ]; then
        echo -e "${RED}No **suitable file found** in current directory.${RESET}"
        exit 1
    fi
    echo -e "${YELLOW}Using **most recently modified file**: ${BOLD}${FILE}${RESET}"
fi

if [ ! -f "$FILE" ]; then
    echo -e "${RED}File not found: ${BOLD}$FILE${RESET}"
    exit 1
fi

# ---- Cookie handling ----
prompt_for_cookie() {
    echo -e "${YELLOW}Session missing or invalid. **Triggering auto-login** via hawking-login...${RESET}"
    if command -v hawking-login &> /dev/null; then
        hawking-login
    elif [ -x "$HOME/.hawking/bin/hawking-login" ]; then
        "$HOME/.hawking/bin/hawking-login"
    else
        echo -e "${RED}Error: hawking-login command **not found**.${RESET}"
        exit 1
    fi

    if [ ! -f "$COOKIE_FILE" ]; then
        echo -e "${RED}Failed to acquire **valid session cookie**.${RESET}"
        exit 1
    fi
}

if [ ! -f "$COOKIE_FILE" ]; then
    prompt_for_cookie
fi

# ---- Upload request function ----
execute_upload() {
    local target_id="$1"
    local url="${BASE_URL}/${target_id}/fileUpload"
    local page_url="${BASE_URL}/${target_id}"

    PAGE_HTML=$(curl -s -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$page_url")
    
    CSRF_TOKEN=$(echo "$PAGE_HTML" | grep -oE 'name="(_csrf_token|csrf_token)"[^>]*value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/' || true)
    if [ -z "$CSRF_TOKEN" ]; then
        CSRF_TOKEN=$(echo "$PAGE_HTML" | grep -oE 'data-csrf-token="[^"]*"' | sed -E 's/.*data-csrf-token="([^"]*)".*/\1/' || true)
    fi

    CURL_CMD=(curl -s -w "\n%{http_code}" -X POST "$url"
      -b "$COOKIE_FILE"
      -c "$COOKIE_FILE"
      -H "X-Requested-With: XMLHttpRequest"
      -H "Referer: ${page_url}"
      -H "Origin: https://hawking.computing.dcu.ie"
      -H "Accept: application/json, text/javascript, */*; q=0.01"
      -F "file=@${FILE}")

    if [ -n "$CSRF_TOKEN" ]; then
        CURL_CMD+=(-F "_csrf_token=${CSRF_TOKEN}")
    fi

    "${CURL_CMD[@]}"
}

echo -e "${YELLOW}Uploading ${BOLD}${FILE}${RESET}${YELLOW} to assignment ${BOLD}${ASSIGNMENT_ID}${RESET}${YELLOW}...${RESET}"

RAW_RESPONSE=$(execute_upload "$ASSIGNMENT_ID")
HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')

is_valid_attempt() {
    local code="$1"
    local resp="$2"
    if [ "$code" -eq 200 ] && echo "$resp" | jq -e '.attempt' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ---- Handle Fallback (Cycle through ALL cached IDs if invalid or 404) ----
if ! is_valid_attempt "$HTTP_CODE" "$RESPONSE"; then
    echo -e "${YELLOW}Assignment ID '${ASSIGNMENT_ID}' **rejected the upload** or returned HTTP ${HTTP_CODE}. **Cycling through** all previously used IDs...${RESET}"
    FOUND_WORKING_ID=false
    
    while read -r cached_id; do
        [ -z "$cached_id" ] && continue
        [ "$cached_id" == "$ASSIGNMENT_ID" ] && continue
        
        echo -e "${YELLOW}Testing history ID: ${BOLD}${cached_id}${RESET}${YELLOW}...${RESET}"
        RAW_RESPONSE=$(execute_upload "$cached_id")
        HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
        RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')
        
        if is_valid_attempt "$HTTP_CODE" "$RESPONSE"; then
            ASSIGNMENT_ID="$cached_id"
            FOUND_WORKING_ID=true
            echo -e "${GREEN}Successfully **switched to cached ID**: ${BOLD}${ASSIGNMENT_ID}${RESET}"
            break
        fi
    done < <(get_cached_ids)

    if [ "$FOUND_WORKING_ID" = false ]; then
        echo -e "${RED}All **cached assignment IDs failed** or rejected the file.${RESET}"
        echo -e "${YELLOW}Guidance:${RESET} Add a working module ID using ${BOLD}$SCRIPT_NAME --add-module <id>${RESET}"
        echo -e "  *(Note: For a URL like ${BOLD}https://hawking.computing.dcu.ie/hawking/124${RESET}, the ID is ${BOLD}124${RESET})*"
        exit 1
    fi
fi

# ---- Validate Session Expiry ----
if [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ] || [ "$HTTP_CODE" -eq 302 ] || [ "$HTTP_CODE" -eq 301 ]; then
    echo -e "${RED}Session expired or **unauthorized** (HTTP ${HTTP_CODE} redirect).${RESET}"
    prompt_for_cookie
    echo -e "${YELLOW}Retrying upload with **fresh session**...${RESET}"
    RAW_RESPONSE=$(execute_upload "$ASSIGNMENT_ID")
    HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
    RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')
fi

save_cached_id "$ASSIGNMENT_ID"

if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}=== Full JSON Response (Debug) ===${RESET}"
    echo "$RESPONSE" | jq .
    exit 0
fi

# ---- Header Info & Test Results Processing ----
echo -e "${BOLD}=== Attempt Info ===${RESET}"
echo "$RESPONSE" | jq -r '
  .attempt |
  "ID: \(.id)\nAssignment: \(.assignmentId)\nSubmitter: \(.submitterUsername) (ID: \(.submitterId))\nTimestamp: \(.timestamp)\nSubmission Error: \(.submissionError // "none")"
'

echo ""
echo -e "${BOLD}=== Test Results ===${RESET}"

decode_b64() {
    local input="$1"
    if [ -z "$input" ]; then
        echo ""
        return
    fi
    echo "$input" | base64 --decode 2>/dev/null || echo "$input" | base64 -D 2>/dev/null || echo ""
}

ALL_PASSED=true

while IFS=$'\t' read -r TEST_ID CORRECT EXEC_TIME EXPECTED_B64 STDOUT STDERR; do
    EXPECTED=$(decode_b64 "$EXPECTED_B64")

    if [ "$CORRECT" == "true" ]; then
        echo -e "${GREEN}${BOLD}✓ PASSED${RESET} — test ${TEST_ID} (${EXEC_TIME}ms)"
    else
        ALL_PASSED=false
        echo -e "${RED}${BOLD}✗ FAILED${RESET} — test ${TEST_ID} (${EXEC_TIME}ms)"
        
        ACT_CLEAN=$(printf '%s' "$STDOUT" | tr -d '\r')
        EXP_CLEAN=$(printf '%s' "$EXPECTED" | tr -d '\r')

        echo -e "  ${BOLD}Expected:${RESET} ${EXP_CLEAN:-<empty>}"
        printf "  ${BOLD}Actual:  ${RESET} "

        ACT_LEN=${#ACT_CLEAN}
        EXP_LEN=${#EXP_CLEAN}
        MAX_LEN=$ACT_LEN
        [ $EXP_LEN -gt $MAX_LEN ] && MAX_LEN=$EXP_LEN

        if [ $MAX_LEN -eq 0 ]; then
            printf "${RED}%s${RESET}\n" "$ACT_CLEAN"
        else
            for (( i=0; i<MAX_LEN; i++ )); do
                CHAR_ACT="${ACT_CLEAN:$i:1}"
                CHAR_EXP="${EXP_CLEAN:$i:1}"

                if [ "$CHAR_ACT" == "$CHAR_EXP" ] && [ -n "$CHAR_ACT" ]; then
                    printf "%s" "$CHAR_ACT"
                else
                    PRINT_CHAR="${CHAR_ACT:- }"
                    printf "${RED}%s${RESET}" "$PRINT_CHAR"
                fi
            done
            printf "\n"
        fi
        echo ""
    fi

    [ -n "$STDERR" ] && echo -e "  ${RED}stderr:${RESET} ${STDERR}"
done < <(echo "$RESPONSE" | jq -r '
  .tests as $tests |
  .attempt.testResults[] |
  .testId as $tid |
  ($tests[$tid | tostring] // {}) as $tdef |
  [
    .testId,
    (.correct | tostring),
    (.execTimeMillis | tostring),
    ($tdef.testStdout // ""),
    (.stdout // ""),
    (.stderr // "")
  ] | @tsv
')

if [ "$ALL_PASSED" = true ]; then
    echo ""
    echo -e "${GREEN}${BOLD}🎉 All test cases passed successfully! Great job!${RESET}"
    if [ $((RANDOM % 100)) -eq 0 ]; then
        echo -e "${GREEN}${BOLD}Good boy${RESET}"
    fi
fi

echo ""

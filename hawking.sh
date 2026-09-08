#!/bin/bash

set -euo pipefail

BASE_URL="https://hawking.computing.dcu.ie/hawking"
COOKIE_FILE="$HOME/.hawking_cookie"
SCRIPT_NAME="$(basename "$0")"

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
RESET="\033[0m"

# ---- Parse options ----
DEBUG=false
ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        DEBUG=true
    else
        ARGS+=("$arg")
    fi
done

if [ ${#ARGS[@]} -lt 1 ]; then
    echo "Usage: $0 [--debug] <assignment_id> [file_to_submit]"
    exit 1
fi

ASSIGNMENT_ID="${ARGS[0]}"
FILE="${ARGS[1]:-}"

if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is required but not installed.${RESET}"
    exit 1
fi

# ---- Find newest file if not provided ----
if [ -z "$FILE" ]; then
    FILE=$(ls -t 2>/dev/null | grep -v -E "^($SCRIPT_NAME|\..*)$" | head -n 1 || true)
    if [ -z "$FILE" ]; then
        echo -e "${RED}No suitable file found in current directory.${RESET}"
        exit 1
    fi
    echo -e "${YELLOW}Using most recently modified file: ${FILE}${RESET}"
fi

if [ ! -f "$FILE" ]; then
    echo -e "${RED}File not found: $FILE${RESET}"
    exit 1
fi

# ---- Cookie handling ----
prompt_for_cookie() {
    echo -e "${YELLOW}Session missing or invalid. Triggering auto-login via hawking-login...${RESET}"
    if command -v hawking-login &> /dev/null; then
        hawking-login
    elif [ -x "$HOME/.hawking/bin/hawking-login" ]; then
        "$HOME/.hawking/bin/hawking-login"
    else
        echo -e "${RED}Error: hawking-login command not found in PATH or ~/.hawking/bin/.${RESET}"
        exit 1
    fi

    if [ ! -f "$COOKIE_FILE" ]; then
        echo -e "${RED}Failed to acquire valid session cookie.${RESET}"
        exit 1
    fi
}

if [ ! -f "$COOKIE_FILE" ]; then
    prompt_for_cookie
fi

# ---- Upload request ----
URL="${BASE_URL}/${ASSIGNMENT_ID}/fileUpload"
ASSIGNMENT_PAGE_URL="${BASE_URL}/${ASSIGNMENT_ID}"

do_upload() {
    # 1. Visit assignment page to initialize Symfony route context & cookies
    PAGE_HTML=$(curl -s -L -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$ASSIGNMENT_PAGE_URL")
    
    # 2. Extract CSRF token if present
    CSRF_TOKEN=$(echo "$PAGE_HTML" | grep -oE 'name="(_csrf_token|csrf_token)"[^>]*value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/' || true)
    if [ -z "$CSRF_TOKEN" ]; then
        CSRF_TOKEN=$(echo "$PAGE_HTML" | grep -oE 'data-csrf-token="[^"]*"' | sed -E 's/.*data-csrf-token="([^"]*)".*/\1/' || true)
    fi

    # 3. Execute multipart upload request
    CURL_CMD=(curl -s -w "\n%{http_code}" -X POST "$URL"
      -b "$COOKIE_FILE"
      -c "$COOKIE_FILE"
      -H "X-Requested-With: XMLHttpRequest"
      -H "Referer: ${ASSIGNMENT_PAGE_URL}"
      -H "Origin: https://hawking.computing.dcu.ie"
      -H "Accept: application/json, text/javascript, */*; q=0.01"
      -F "file=@${FILE}")

    if [ -n "$CSRF_TOKEN" ]; then
        CURL_CMD+=(-F "_csrf_token=${CSRF_TOKEN}")
    fi

    "${CURL_CMD[@]}"
}

echo -e "${YELLOW}Uploading ${FILE} to assignment ${ASSIGNMENT_ID}...${RESET}"

RAW_RESPONSE=$(do_upload)
HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')

# ---- Validate HTTP Status & Payload ----
if [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ] || [ "$HTTP_CODE" -eq 302 ] || [ "$HTTP_CODE" -eq 301 ]; then
    echo -e "${RED}Session expired or unauthorized (HTTP $HTTP_CODE redirect).${RESET}"
    prompt_for_cookie
    echo -e "${YELLOW}Retrying upload with fresh session...${RESET}"
    RAW_RESPONSE=$(do_upload)
    HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
    RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')
fi

if [ "$HTTP_CODE" -eq 404 ]; then
    echo -e "${RED}Assignment ID '${ASSIGNMENT_ID}' not found (HTTP 404). Check your assignment ID.${RESET}"
    exit 1
fi

if [ "$HTTP_CODE" -ne 200 ] || ! echo "$RESPONSE" | jq -e '.attempt' >/dev/null 2>&1; then
    echo -e "${RED}Failed to process request (HTTP $HTTP_CODE). Invalid assignment ID or payload.${RESET}"
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}=== Raw Response (Debug) ===${RESET}"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    fi
    exit 1
fi

# ---- Handle --debug flag ----
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}=== Full JSON Response (Debug) ===${RESET}"
    echo "$RESPONSE" | jq .
    exit 0
fi

# ---- Header Info ----
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

# ---- Process test results ----
echo "$RESPONSE" | jq -r '
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
' | while IFS=$'\t' read -r TEST_ID CORRECT EXEC_TIME EXPECTED_B64 STDOUT STDERR; do
    
    EXPECTED=$(decode_b64 "$EXPECTED_B64")

    if [ "$CORRECT" == "true" ]; then
        echo -e "${GREEN}${BOLD}✓ PASSED${RESET} — test $TEST_ID (${EXEC_TIME}ms)"
    else
        echo -e "${RED}${BOLD}✗ FAILED${RESET} — test $TEST_ID (${EXEC_TIME}ms)"
        
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
done

echo ""

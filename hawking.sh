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
    echo "Usage: $0 [--debug] <module_id> [file_to_submit]"
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
    echo -e "${YELLOW}Enter a fresh Cookie header value (e.g. PHPSESSID=xxxxx):${RESET}"
    read -r NEW_COOKIE
    echo "$NEW_COOKIE" > "$COOKIE_FILE"
    chmod 600 "$COOKIE_FILE"
    echo -e "${GREEN}Saved to ${COOKIE_FILE}${RESET}"
}

if [ ! -f "$COOKIE_FILE" ]; then
    prompt_for_cookie
fi

# ---- Upload request ----
URL="${BASE_URL}/${ASSIGNMENT_ID}/fileUpload"

do_upload() {
    COOKIE=$(cat "$COOKIE_FILE")
    curl -s -w "\n%{http_code}" -X POST "$URL" \
      -H "Cookie: $COOKIE" \
      -H "X-Requested-With: XMLHttpRequest" \
      -H "Referer: ${BASE_URL}/${ASSIGNMENT_ID}" \
      -F "file=@${FILE}"
}

echo -e "${YELLOW}Uploading ${FILE} to module ${ASSIGNMENT_ID}...${RESET}"

RAW_RESPONSE=$(do_upload)
HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')

# ---- Validate HTTP Status & Payload ----
if [ "$HTTP_CODE" -eq 404 ]; then
    echo -e "${RED}Assignment ID '${ASSIGNMENT_ID}' not found (HTTP 404). Check your module ID.${RESET}"
    exit 1
elif [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ]; then
    echo -e "${RED}Session expired or unauthorized (HTTP $HTTP_CODE).${RESET}"
    prompt_for_cookie
    echo -e "${YELLOW}Retrying upload...${RESET}"
    RAW_RESPONSE=$(do_upload)
    HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
    RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')
fi

if [ "$HTTP_CODE" -ne 200 ] || ! echo "$RESPONSE" | jq -e '.attempt' >/dev/null 2>&1; then
    echo -e "${RED}Failed to process request (HTTP $HTTP_CODE). Invalid module ID or payload.${RESET}"
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

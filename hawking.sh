#!/bin/bash

set -euo pipefail

BASE_URL="https://hawking.computing.dcu.ie/hawking"
COOKIE_FILE="$HOME/.hawking_cookie"
USER_FILE="$HOME/.hawking_user"
CACHE_FILE="$HOME/.hawking_history"
UPDATE_CHECK_FILE="$HOME/.hawking_last_update"
SCRIPT_NAME="$(basename "$0")"

GREEN="\033[0;32m"
RED="\033[0;31m"
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

# ---- Handle --version ----
if [ "$SHOW_VERSION" = true ]; then
    if [ -d "$HOME/.hawking/.git" ]; then
        echo -e "${BOLD}Hawking CLI Version (Latest Commit):${RESET}"
        git --no-pager -C "$HOME/.hawking" -c color.ui=always log -1 --pretty=format:"%C(cyan)%h%Creset - %C(green)%s%Creset %C(yellow)(%ar)%Creset [%an]" --date=relative 2>/dev/null || echo -e "${YELLOW}No commit history found.${RESET}"
        echo ""
    else
        echo -e "${YELLOW}Hawking CLI (**Git repository context not found** in ~/.hawking)${RESET}"
    fi
    exit 0
fi

# ---- Handle --update (Forces Overwrite of Local Changes) ----
if [ "$FORCE_UPDATE" = true ]; then
    echo "$now" > "$UPDATE_CHECK_FILE"
    if [ -d "$HOME/.hawking/.git" ]; then
        echo -e "${YELLOW}Forcing repository **update** (overriding local changes)...${RESET}"
        if git -C "$HOME/.hawking" fetch origin && git -C "$HOME/.hawking" reset --hard origin/main; then
            if [ -f "$HOME/.hawking/hawking.sh" ]; then
                cp "$HOME/.hawking/hawking.sh" "$HOME/.hawking/bin/hawking"
                chmod +x "$HOME/.hawking/bin/hawking"
            fi
            echo -e "${GREEN}Successfully **updated** and re-installed Hawking CLI.${RESET}"
        else
            echo -e "${RED}Update **failed** (network issue). Cooldown reset.${RESET}"
        fi
    else
        echo -e "${YELLOW}No **git repository** found in ~/.hawking to update.${RESET}"
    fi
    exit 0
fi

# ---- Handle --logout ----
if [ "$LOGOUT" = true ]; then
    rm -f "$COOKIE_FILE" "$USER_FILE"
    echo -e "${GREEN}Successfully **logged out** and cleared default username.${RESET}"
    exit 0
fi

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

# ---- Weekly Synchronous Update Check ----
should_check=false
if [ ! -f "$UPDATE_CHECK_FILE" ]; then
    should_check=true
else
    last_check=$(cat "$UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
    if [ $((now - last_check)) -gt 604800 ]; then
        should_check=true
    fi
fi

if [ "$should_check" = true ]; then
    echo "$now" > "$UPDATE_CHECK_FILE"
    if [ -d "$HOME/.hawking/.git" ]; then
        if git -C "$HOME/.hawking" fetch origin --quiet 2>/dev/null && git -C "$HOME/.hawking" reset --hard origin/main --quiet 2>/dev/null; then
            if [ -f "$HOME/.hawking/hawking.sh" ]; then
                cp "$HOME/.hawking/hawking.sh" "$HOME/.hawking/bin/hawking"
                chmod +x "$HOME/.hawking/bin/hawking"
            fi
        fi
    fi
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

# ---- Connection & Cookie TTL Checks ----
check_hawking_connection() {
    if ! curl -s --head --connect-timeout 4 "$BASE_URL" >/dev/null 2>&1; then
        echo -e "${RED}Error: **Cannot connect to Hawking**. The server may be down or unreachable.${RESET}"
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
    [ $age -gt 7200 ]
}

prompt_for_cookie() {
    check_hawking_connection
    if [ "$VOCAL" = true ]; then
        echo -e "${YELLOW}Session missing, expired, or invalid. **Triggering auto-login** via hawking-login...${RESET}"
    fi
    
    local login_arg=""
    [ "$VOCAL" = true ] && login_arg="--vocal"

    if command -v hawking-login &> /dev/null; then
        hawking-login $login_arg
    elif [ -x "$HOME/.hawking/bin/hawking-login" ]; then
        "$HOME/.hawking/bin/hawking-login" $login_arg
    else
        echo -e "${RED}Error: hawking-login command **not found**.${RESET}"
        exit 1
    fi

    if [ ! -f "$COOKIE_FILE" ]; then
        echo -e "${RED}Failed to acquire **valid session cookie**.${RESET}"
        exit 1
    fi
}

check_hawking_connection
if [ ! -f "$COOKIE_FILE" ] || is_cookie_expired; then
    prompt_for_cookie
fi

# ---- Upload request function ----
execute_upload() {
    local target_id="$1"
    local file_to_upload="$2"
    local url="${BASE_URL}/${target_id}/fileUpload"
    local page_url="${BASE_URL}/${target_id}"

    PAGE_HTML=$(curl -s -L --connect-timeout 5 -b "$COOKIE_FILE" -c "$COOKIE_FILE" "$page_url")
    
    CSRF_TOKEN=$(echo "$PAGE_HTML" | grep -oE 'name="(_csrf_token|csrf_token)"[^>]*value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/' || true)
    if [ -z "$CSRF_TOKEN" ]; then
        CSRF_TOKEN=$(echo "$PAGE_HTML" | grep -oE 'data-csrf-token="[^"]*"' | sed -E 's/.*data-csrf-token="[^"]*"//' || true)
    fi

    CURL_CMD=(curl -s --connect-timeout 5 -w "\n%{http_code}" -X POST "$url"
      -b "$COOKIE_FILE"
      -c "$COOKIE_FILE"
      -H "X-Requested-With: XMLHttpRequest"
      -H "Referer: ${page_url}"
      -H "Origin: https://hawking.computing.dcu.ie"
      -H "Accept: application/json, text/javascript, */*; q=0.01"
      -F "file=@${file_to_upload}")

    if [ -n "$CSRF_TOKEN" ]; then
        CURL_CMD+=(-F "_csrf_token=${CSRF_TOKEN}")
    fi

    "${CURL_CMD[@]}"
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
    for f in "${FILES[@]}"; do
        if [ ! -f "$f" ]; then
            echo -e "${RED}Error: **No such file exists**: ${BOLD}${f}${RESET}"
            exit 1
        fi
    done
fi

if [ -z "$ASSIGNMENT_ID" ]; then
    ASSIGNMENT_ID=$(get_cached_ids | head -n 1 || true)
    if [ -z "$ASSIGNMENT_ID" ]; then
        echo -e "${RED}Error: **No module ID specified** and no cache history found.${RESET}"
        echo -e "${YELLOW}Guidance:${RESET} Run ${BOLD}hawking-login${RESET} to auto-sync, or add manually using:"
        echo -e "  ${BOLD}$SCRIPT_NAME --add-module <YOUR_MODULE_ID>${RESET}"
        exit 1
    fi
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is required but **not installed**.${RESET}"
    exit 1
fi

# ---- File Selection ----
IS_MULTI=false
if [ ${#FILES[@]} -eq 0 ]; then
    NEWEST_FILE=$(ls -t 2>/dev/null | grep -v -E "^($SCRIPT_NAME|\..*)$" | head -n 1 || true)
    if [ -z "$NEWEST_FILE" ]; then
        echo -e "${RED}No **suitable file found** in current directory.${RESET}"
        exit 1
    fi
    FILES=("$NEWEST_FILE")
    if [ "$VOCAL" = true ]; then
        echo -e "${YELLOW}Using **most recently modified file**: ${BOLD}${FILES[0]}${RESET}"
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

if [ "$IS_MULTI" = false ] && [ "$VOCAL" = true ]; then
    echo -e "${YELLOW}Using **cached module ID**: ${BOLD}${ASSIGNMENT_ID}${RESET}"
fi

decode_b64() {
    local input="$1"
    if [ -z "$input" ]; then
        echo ""
        return
    fi
    echo "$input" | base64 --decode 2>/dev/null || echo "$input" | base64 -D 2>/dev/null || echo ""
}

# ---- Process Each File ----
for FILE in "${FILES[@]}"; do
    [ -f "$FILE" ] || continue
    [ "$FILE" == "$SCRIPT_NAME" ] && continue

    if [ "$IS_MULTI" = false ] && [ "$VOCAL" = true ]; then
        echo -e "${YELLOW}Uploading ${BOLD}${FILE}${RESET}${YELLOW} to assignment ${BOLD}${ASSIGNMENT_ID}${RESET}${YELLOW}...${RESET}"
    fi

    RAW_RESPONSE=$(execute_upload "$ASSIGNMENT_ID" "$FILE")
    HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
    RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')

    CURRENT_ASSIGNMENT_ID="$ASSIGNMENT_ID"
    if ! is_valid_attempt "$HTTP_CODE" "$RESPONSE"; then
        if [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ] || [ "$HTTP_CODE" -eq 302 ] || [ "$HTTP_CODE" -eq 301 ] || echo "$RESPONSE" | grep -qE '_username|login|Unauthorized|<html'; then
            if [ "$VOCAL" = true ]; then
                echo -e "${RED}Session expired or **invalid**. Re-authenticating...${RESET}"
            fi
            check_hawking_connection
            prompt_for_cookie
            if [ "$VOCAL" = true ]; then
                echo -e "${YELLOW}Retrying upload with **fresh session**...${RESET}"
            fi
            RAW_RESPONSE=$(execute_upload "$CURRENT_ASSIGNMENT_ID" "$FILE")
            HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
            RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')
        fi

        if ! is_valid_attempt "$HTTP_CODE" "$RESPONSE"; then
            if [ "$VOCAL" = true ]; then
                echo -e "${YELLOW}Assignment ID '${CURRENT_ASSIGNMENT_ID}' rejected upload. **Cycling through** history...${RESET}"
            fi
            FOUND_WORKING_ID=false
            
            while read -r cached_id; do
                [ -z "$cached_id" ] && continue
                [ "$cached_id" == "$CURRENT_ASSIGNMENT_ID" ] && continue
                
                if [ "$VOCAL" = true ]; then
                    echo -e "${YELLOW}Testing history ID: ${BOLD}${cached_id}${RESET}...${RESET}"
                fi
                RAW_RESPONSE=$(execute_upload "$cached_id" "$FILE")
                HTTP_CODE=$(echo "$RAW_RESPONSE" | tail -n 1)
                RESPONSE=$(echo "$RAW_RESPONSE" | sed '$d')
                
                if is_valid_attempt "$HTTP_CODE" "$RESPONSE"; then
                    CURRENT_ASSIGNMENT_ID="$cached_id"
                    FOUND_WORKING_ID=true
                    if [ "$VOCAL" = true ]; then
                        echo -e "${GREEN}Successfully **switched to cached ID**: ${BOLD}${CURRENT_ASSIGNMENT_ID}${RESET}"
                    fi
                    break
                fi
            done < <(get_cached_ids)

            if [ "$FOUND_WORKING_ID" = false ]; then
                if [ "$IS_MULTI" = true ]; then
                    echo -e "${RED}${BOLD}✗ ${FILE}${RESET} — FAILED (Rejected)"
                else
                    echo -e "${RED}All **cached assignment IDs failed** or rejected file: ${BOLD}${FILE}${RESET}"
                fi
                continue
            fi
        fi
    fi

    save_cached_id "$CURRENT_ASSIGNMENT_ID"

    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}=== Full JSON Response (Debug) ===${RESET}"
        echo "$RESPONSE" | jq .
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
            echo -e "${GREEN}${BOLD}✓ ${FILE}${RESET} — (${PASSED_COUNT}/${TOTAL_COUNT})"
        else
            echo -e "${RED}${BOLD}✗ ${FILE}${RESET} — (${PASSED_COUNT}/${TOTAL_COUNT})"
        fi
    else
        echo -e "${BOLD}=== Attempt Info ===${RESET}"
        echo "$RESPONSE" | jq -r '
          .attempt |
          "ID: \(.id)\nAssignment: \(.assignmentId)\nSubmitter: \(.submitterUsername) (ID: \(.submitterId))\nTimestamp: \(.timestamp)\nSubmission Error: \(.submissionError // "none")"
        '

        echo ""
        echo -e "${BOLD}=== Test Results ===${RESET}"

        ALL_PASSED=true

        while IFS=$'\t' read -r TEST_ID CORRECT EXEC_TIME EXPECTED_B64 STDOUT STDERR; do
            STDOUT=$(printf '%b' "$STDOUT")
            EXPECTED=$(decode_b64 "$EXPECTED_B64")

            if [ "$CORRECT" == "true" ]; then
                echo -e "${GREEN}${BOLD}✓ PASSED${RESET} — test ${TEST_ID} (${EXEC_TIME}ms)"
            else
                ALL_PASSED=false
                echo -e "${RED}${BOLD}✗ FAILED${RESET} — test ${TEST_ID} (${EXEC_TIME}ms)"
                
                ACT_CLEAN=$(printf '%s' "$STDOUT" | tr -d '\r')
                EXP_CLEAN=$(printf '%s' "$EXPECTED" | tr -d '\r')

                IS_MULTILINE=false
                if [[ "$ACT_CLEAN" == *$'\n'* ]] || [[ "$EXP_CLEAN" == *$'\n'* ]]; then
                    IS_MULTILINE=true
                fi

                if [ "$IS_MULTILINE" = true ]; then
                    echo -e "  ${BOLD}Expected:${RESET}"
                    printf '%s\n' "${EXP_CLEAN:-<empty>}" | awk '{print "    │ " $0}'
                    echo -e "  ${BOLD}Actual:  ${RESET}"
                    EXP_DATA="$EXP_CLEAN" ACT_DATA="$ACT_CLEAN" awk -v green="${GREEN}" -v red="${RED}" -v reset="${RESET}" '
                    BEGIN {
                        n_exp = split(ENVIRON["EXP_DATA"], exp_lines, "\n")
                        n_act = split(ENVIRON["ACT_DATA"], act_lines, "\n")
                        for (i = 1; i <= n_act; i++) {
                            line = act_lines[i]
                            if (i <= n_exp && line == exp_lines[i]) {
                                print "    │ " green line reset
                            } else {
                                print "    │ " red line reset
                            }
                        }
                    }'
                else
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
                fi
            fi

            if [ -n "$STDERR" ]; then
                echo -e "  ${RED}${BOLD}Stderr:  ${RESET}"
                printf '%s\n' "$(printf '%b' "$STDERR" | tr -d '\r')" | awk '{print "    │ " $0}'
            fi
            echo ""

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
            echo -e "${GREEN}${BOLD}🎉 All test cases passed successfully for ${FILE}! Great job!${RESET}"
            if [ $((RANDOM % 100)) -eq 0 ]; then
                UNAME=""
                [ -f "$USER_FILE" ] && UNAME=$(cat "$USER_FILE" | tr -d '[:space:]')
                FIRST_NAME="${UNAME%%.*}"
                if [[ "${FIRST_NAME,,}" =~ a$ ]]; then
                    echo -e "${GREEN}${BOLD}good girl${RESET}"
                else
                    echo -e "${GREEN}${BOLD}good boy${RESET}"
                fi
            fi
        fi
    fi
done

echo ""

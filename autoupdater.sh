#!/bin/bash

set -euo pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
RESET="\033[0m"

VOCAL=false
for arg in "$@"; do
    [[ "$arg" == "--vocal" ]] && VOCAL=true
done

TRUSTED_FILE="$HOME/.hawking_trusted_author"
CURRENT_AUTHOR=$(git log -1 --pretty=format:"%an" 2>/dev/null || echo "unknown")

# ---- Author Signature Check ----
if [ -f "$TRUSTED_FILE" ]; then
    SAVED_AUTHOR=$(cat "$TRUSTED_FILE")
    if [ "$SAVED_AUTHOR" != "$CURRENT_AUTHOR" ]; then
        echo -e "${RED}${BOLD}WARNING: Author signature changed!${RESET}"
        echo -e "Previous author: ${SAVED_AUTHOR}"
        echo -e "Current author:  ${CURRENT_AUTHOR}"
        echo -n "Type ${BOLD}\"I understand\"${RESET} to proceed: "
        read -r confirmation
        if [ "$confirmation" != "I understand" ]; then
            echo -e "${RED}Aborted for safety.${RESET}"
            exit 1
        fi
        echo "$CURRENT_AUTHOR" > "$TRUSTED_FILE"
    fi
else
    echo "$CURRENT_AUTHOR" > "$TRUSTED_FILE"
fi

INSTALL_SCRIPT="./install.sh"
if [ ! -f "$INSTALL_SCRIPT" ]; then
    if [ "$VOCAL" = true ]; then
        echo -e "${RED}Error: **install.sh not found** in the current directory.${RESET}"
    fi
    exit 1
fi

if [ "$VOCAL" = true ]; then
    echo -e "${BOLD}Pulling latest changes from git...${RESET}"
    if ! git pull; then
        echo -e "${RED}Error: **git pull failed**.${RESET}"
        exit 1
    fi

    HASH=$(git log -1 --pretty=format:"%h")
    DATE=$(git log -1 --pretty=format:"%cd")
    MSG=$(git log -1 --pretty=format:"%s")

    echo -e "\n${BOLD}Latest Commit Details:${RESET}"
    echo -e "  ${BOLD}Hash:${RESET}    ${HASH}"
    echo -e "  ${BOLD}Date:${RESET}    ${DATE}"
    echo -e "  ${BOLD}Message:${RESET} ${MSG}"
    echo -e "\n"

    echo -e "${BOLD}Running installer...${RESET}"
    bash "$INSTALL_SCRIPT"

    echo -e "\n${GREEN}${BOLD}✓ Update completed successfully!${RESET}"
else
    echo "Updating **hawking-cli**..."
    git pull -q >/dev/null 2>&1 || exit 1
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1 || exit 1
fi

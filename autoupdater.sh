#!/bin/bash

set -euo pipefail

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
        echo -e "\033[0;31m\033[1mWARNING: Author signature changed!\033[0m"
        echo -e "Previous author: ${SAVED_AUTHOR}"
        echo -e "Current author:  ${CURRENT_AUTHOR}"
        echo -n "Type \033[1m\"I understand\"\033[0m to proceed: "
        read -r confirmation
        if [ "$confirmation" != "I understand" ]; then
            echo -e "\033[0;31mAborted for safety.\033[0m"
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
        echo -e "\033[0;31mError: **install.sh not found** in the current directory.\033[0m"
    fi
    exit 1
fi

if [ "$VOCAL" = true ]; then
    echo -e "\033[1mPulling latest changes from git...\033[0m"
    if ! git pull; then
        echo -e "\033[0;31mError: **git pull failed**.\033[0m"
        exit 1
    fi

    echo -e "\n\033[1mLatest Commit Details:\033[0m"
    git --no-pager log -1 --pretty=format:"  \033[1mHash:\033[0m    %h%n  \033[1mDate:\033[0m    %cd%n  \033[1mMessage:\033[0m %s"
    echo -e "\n"

    echo -e "\033[1mRunning installer...\033[0m"
    bash "$INSTALL_SCRIPT"

    echo -e "\n\033[0;32m\033[1m✓ Update completed successfully!\033[0m"
else
    echo "Updating **hawking-cli**..."
    git pull -q >/dev/null 2>&1 || exit 1
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1 || exit 1
fi

#!/bin/bash

set -euo pipefail

INSTALL_DIR="$HOME/.hawking/bin"
SUBMIT_SRC="hawking.sh"
LOGIN_SRC="hawking-login.sh"

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
RESET="\033[0m"

# 1. Verify hawking.sh exists
if [ ! -f "$SUBMIT_SRC" ]; then
    echo -e "${RED}Error: **${SUBMIT_SRC}** not found in the current directory.${RESET}"
    exit 1
fi

# 2. Locate hawking-login source file
LOGIN_FILE=""
if [ -f "$LOGIN_SRC" ]; then
    LOGIN_FILE="$LOGIN_SRC"
elif [ -f "hawking-login" ]; then
    LOGIN_FILE="hawking-login"
else
    echo -e "${RED}Error: Neither **hawking-login.sh** nor **hawking-login** found in the current directory.${RESET}"
    exit 1
fi

# Create target directory
mkdir -p "$INSTALL_DIR"

# Copy and make binaries executable
cp "$SUBMIT_SRC" "$INSTALL_DIR/hawking"
chmod +x "$INSTALL_DIR/hawking"

cp "$LOGIN_FILE" "$INSTALL_DIR/hawking-login"
chmod +x "$INSTALL_DIR/hawking-login"

echo -e "${GREEN}${BOLD}✓ Installed hawking and hawking-login to ${INSTALL_DIR}${RESET}"

# Path export line
PATH_LINE="export PATH=\"\$HOME/.hawking/bin:\$PATH\""

# Update both Zsh and Bash configurations
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    touch "$rc" 2>/dev/null || true
    if [ -f "$rc" ]; then
        if grep -q "\.hawking/bin" "$rc" 2>/dev/null; then
            echo -e "${GREEN}✓ PATH entry already exists in **${rc}**${RESET}"
        else
            echo "" >> "$rc"
            echo "# Hawking CLI tool" >> "$rc"
            echo "$PATH_LINE" >> "$rc"
            echo -e "${GREEN}✓ Added **${INSTALL_DIR}** to PATH in **${rc}**${RESET}"
        fi
    fi
done

echo -e "\n${BOLD}Run this to reload your shell:${RESET}"
echo -e "  source ~/.zshrc  (or source ~/.bashrc)"

echo -e "\n${GREEN}${BOLD}Setup complete! You can now run:${RESET}"
echo -e "  hawking [file_to_submit]"

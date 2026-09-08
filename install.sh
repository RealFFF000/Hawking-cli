#!/bin/bash

set -euo pipefail

INSTALL_DIR="$HOME/.hawking/bin"
SUBMIT_SRC="hawking.sh"
LOGIN_SRC="hawking-login.sh" # Fallback check for hawking-login

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
RESET="\033[0m"

# 1. Verify hawking.sh exists
if [ ! -f "$SUBMIT_SRC" ]; then
    echo -e "${RED}Error: ${SUBMIT_SRC} not found in the current directory.${RESET}"
    exit 1
fi

# 2. Locate hawking-login source file
LOGIN_FILE=""
if [ -f "$LOGIN_SRC" ]; then
    LOGIN_FILE="$LOGIN_SRC"
elif [ -f "hawking-login" ]; then
    LOGIN_FILE="hawking-login"
else
    echo -e "${RED}Error: Neither hawking-login.sh nor hawking-login found in the current directory.${RESET}"
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

# Detect shell configuration file
SHELL_CONFIG=""
if [ -n "${ZSH_VERSION:-}" ] || [[ "${SHELL:-}" == *"zsh"* ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [[ "${SHELL:-}" == *"bash"* ]]; then
    SHELL_CONFIG="$HOME/.bashrc"
fi

# Add to PATH if not present
PATH_LINE="export PATH=\"\$HOME/.hawking/bin:\$PATH\""

if [ -n "$SHELL_CONFIG" ]; then
    if grep -q "\.hawking/bin" "$SHELL_CONFIG" 2>/dev/null; then
        echo -e "${GREEN}✓ PATH entry already exists in ${SHELL_CONFIG}${RESET}"
    else
        echo "" >> "$SHELL_CONFIG"
        echo "# Hawking CLI tool" >> "$SHELL_CONFIG"
        echo "$PATH_LINE" >> "$SHELL_CONFIG"
        echo -e "${GREEN}✓ Added ${INSTALL_DIR} to PATH in ${SHELL_CONFIG}${RESET}"
    fi
    echo -e "\n${BOLD}Run this to reload your shell:${RESET}"
    echo -e "  source $SHELL_CONFIG"
else
    echo -e "\nAdd this to your shell config manually:"
    echo -e "  $PATH_LINE"
fi

echo -e "\n${GREEN}${BOLD}Setup complete! You can now run:${RESET}"
echo -e "  hawking <module_id> [file_to_submit]"
echo -e "  hawking-login\n"

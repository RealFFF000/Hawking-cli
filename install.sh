#!/bin/bash

set -euo pipefail

INSTALL_DIR="$HOME/.hawking"
BIN_DIR="$INSTALL_DIR/bin"

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${BOLD}Installing Hawking CLI...${RESET}"

# Create directories
mkdir -p "$BIN_DIR"

# Copy main submission script and rename to 'hawking'
if [ -f "hawking.sh" ]; then
    cp hawking.sh "$BIN_DIR/hawking"
    chmod +x "$BIN_DIR/hawking"
    echo -e "${GREEN}Installed **hawking** command.${RESET}"
else
    echo -e "${YELLOW}Warning: hawking.sh **not found** in current directory.${RESET}"
fi

# Copy login script if present
if [ -f "hawking-login" ]; then
    cp hawking-login "$BIN_DIR/hawking-login"
    chmod +x "$BIN_DIR/hawking-login"
    echo -e "${GREEN}Installed **hawking-login** command.${RESET}"
fi

# Preserve git repository context locally for the quiet weekly pull
if [ -d ".git" ]; then
    rm -rf "$INSTALL_DIR/.git"
    cp -R .git "$INSTALL_DIR/" 2>/dev/null || true
    echo -e "${GREEN}Preserved **git repository** for background updates.${RESET}"
fi

# Check and advise on PATH
case ":$PATH:" in
    *":$BIN_DIR:"*) 
        echo -e "${GREEN}**$BIN_DIR** is already in your PATH.${RESET}"
        ;;
    *)
        echo -e "\n${YELLOW}To use commands globally, add this to your **~/.bashrc** or **~/.zshrc**:${RESET}"
        echo -e "  ${BOLD}export PATH=\"\$HOME/.hawking/bin:\$PATH\"${RESET}"
        ;;
esac

echo -e "\n${GREEN}${BOLD}Installation complete!${RESET}"

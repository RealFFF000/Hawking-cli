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
    echo -e "${GREEN}Installed ${BOLD}hawking${RESET}${GREEN} command.${RESET}"
else
    echo -e "${YELLOW}Warning: hawking.sh ${BOLD}not found${RESET}${YELLOW} in current directory.${RESET}"
fi

# Copy login script if present
if [ -f "hawking-login.sh" ]; then
    cp hawking-login.sh "$BIN_DIR/hawking-login"
    chmod +x "$BIN_DIR/hawking-login"
    echo -e "${GREEN}Installed ${BOLD}hawking-login${RESET}${GREEN} command.${RESET}"
fi

# Preserve git repository context locally for the quiet weekly pull
if [ -d ".git" ]; then
    rm -rf "$INSTALL_DIR/.git"
    cp -R .git "$INSTALL_DIR/" 2>/dev/null || true
    echo -e "${GREEN}Preserved ${BOLD}git repository${RESET}${GREEN} for background updates.${RESET}"
fi

# Check and automatically add to PATH
case ":$PATH:" in
    *":$BIN_DIR:"*) 
        echo -e "${GREEN}${BOLD}$BIN_DIR${RESET}${GREEN} is already in your PATH.${RESET}"
        ;;
    *)
        PROFILE_FILE=""
        if [[ "$SHELL" == */zsh ]]; then
            PROFILE_FILE="$HOME/.zshrc"
        elif [[ "$SHELL" == */bash ]]; then
            if [ -f "$HOME/.bash_profile" ]; then
                PROFILE_FILE="$HOME/.bash_profile"
            else
                PROFILE_FILE="$HOME/.bashrc"
            fi
        else
            PROFILE_FILE="$HOME/.profile"
        fi

        echo -e "${YELLOW}Adding ${BOLD}$BIN_DIR${RESET}${YELLOW} to your ${BOLD}$PROFILE_FILE${RESET}${YELLOW}...${RESET}"
        echo -e "\n# Added by Hawking CLI\nexport PATH=\"\$HOME/.hawking/bin:\$PATH\"" >> "$PROFILE_FILE"
        echo -e "${GREEN}Successfully ${BOLD}updated PATH${RESET}${GREEN}. Run ${BOLD}source $PROFILE_FILE${RESET}${GREEN} or restart your terminal to apply.${RESET}"
        ;;
esac

echo -e "\n${GREEN}${BOLD}Installation complete!${RESET}"

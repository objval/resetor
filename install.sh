#!/bin/bash

# Colors for output
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"
BOLD="\033[1m"

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║            Cursor Reset Tool Installer                     ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}This script requires root privileges to install.${RESET}"
  echo -e "Please run with: ${BOLD}sudo bash install.sh${RESET}"
  exit 1
fi

# Get real username (not sudo user)
REAL_USER=""
if [ -n "$SUDO_USER" ]; then
  REAL_USER="$SUDO_USER"
elif [ -n "$DOAS_USER" ]; then
  REAL_USER="$DOAS_USER"
else
  REAL_USER=$(who am i | awk '{print $1}')
  if [ -z "$REAL_USER" ]; then
    REAL_USER=$(logname)
  fi
fi

echo -e "${CYAN}Installing Cursor Reset Tool...${RESET}"

# Create installation directory
INSTALL_DIR="/usr/local/bin"
mkdir -p "$INSTALL_DIR"

# Download the script
echo -e "${CYAN}Downloading script...${RESET}"
curl -fsSL https://raw.githubusercontent.com/objval/resetor/main/resetor.sh -o "$INSTALL_DIR/resetor"

if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Failed to download the script. Please check your internet connection.${RESET}"
  exit 1
fi

# Make script executable
chmod +x "$INSTALL_DIR/resetor"

# Set ownership to real user
chown "$REAL_USER" "$INSTALL_DIR/resetor"

echo -e "\n${GREEN}✓ Cursor Reset Tool has been successfully installed!${RESET}"
echo -e "${CYAN}You can now run it by typing:${RESET} ${BOLD}resetor${RESET}"
echo
echo -e "${YELLOW}Note: When running for the first time, you may need to use sudo:${RESET}"
echo -e "${BOLD}sudo resetor${RESET}"

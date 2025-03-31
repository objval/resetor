#!/bin/bash

# Terminal colors and styling
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
RESET="\033[0m"
CLEAR="\033[2J\033[H"

# Script metadata
SCRIPT_VERSION="2.0"
SCRIPT_AUTHOR="objval"
SCRIPT_GITHUB="https://github.com/objval/recursor"

# Header display
show_header() {
  echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║               Resetor - Interactive              ║${RESET}"
  echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${CYAN}Author: ${SCRIPT_AUTHOR} | GitHub: ${SCRIPT_GITHUB}${RESET}"
  echo
}

# Progress spinner animation
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while ps -p $pid > /dev/null; do
    for i in $(seq 0 3); do
      echo -ne "\r${CYAN}[${spinstr:$i:1}]${RESET} $2"
      sleep $delay
    done
  done
  echo -ne "\r${GREEN}[✓]${RESET} $2\n"
}

# Get actual user information
get_real_user() {
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

  if [ -z "$REAL_USER" ]; then
    echo -e "${RED}Error: Unable to determine actual user${RESET}"
    exit 1
  fi

  REAL_HOME=$(eval echo ~$REAL_USER)
}

# Check required commands
check_requirements() {
  local missing=0
  for cmd in uuidgen ioreg osascript codesign; do
    if ! command -v $cmd &> /dev/null; then
      echo -e "${RED}Error: Required command '$cmd' not found${RESET}"
      missing=1
    fi
  done
  
  if [ $missing -eq 1 ]; then
    exit 1
  fi
}

# Generate UUID in macMachineId format
generate_mac_machine_id() {
  # Generate base UUID and ensure 13th position is 4, 17th position is 8-b
  uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
  # Ensure 13th position is 4
  uuid=$(echo $uuid | sed 's/.\{12\}\(.\)/4/')
  # Ensure 17th position is 8-b (using random number)
  random_hex=$(echo $RANDOM | md5 | cut -c1)
  random_num=$((16#$random_hex))
  new_char=$(printf '%x' $(( ($random_num & 0x3) | 0x8 )))
  uuid=$(echo $uuid | sed "s/.\{16\}\(.\)/$new_char/")
  echo $uuid
}

# Generate 64-bit random ID
generate_random_id() {
  uuid1=$(uuidgen | tr -d '-')
  uuid2=$(uuidgen | tr -d '-')
  echo "${uuid1}${uuid2}"
}

# Check if Cursor is running
check_cursor_running() {
  if pgrep -x "Cursor" > /dev/null || pgrep -f "Cursor.app" > /dev/null; then
    echo -e "${YELLOW}Cursor is currently running.${RESET}"
    read -p "$(echo -e "${BOLD}Would you like to close it now? (y/n): ${RESET}")" choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
      echo -ne "${CYAN}Waiting for Cursor to exit${RESET}"
      osascript -e 'tell application "Cursor" to quit' || true
      while pgrep -x "Cursor" > /dev/null || pgrep -f "Cursor.app" > /dev/null; do
        echo -ne "${CYAN}.${RESET}"
        sleep 1
      done
      echo -e "\n${GREEN}✓ Cursor closed${RESET}"
    else
      echo -e "${RED}Please close Cursor manually before continuing.${RESET}"
      exit 1
    fi
  fi
}

# Define file paths
set_file_paths() {
  STORAGE_JSON="$REAL_HOME/Library/Application Support/Cursor/User/globalStorage/storage.json"
  APP_FILES=(
    "/Applications/Cursor.app/Contents/Resources/app/out/main.js"
    "/Applications/Cursor.app/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
  )
}

# Update storage.json
update_storage_json() {
  # Generate new IDs
  NEW_MACHINE_ID=$(generate_random_id)
  NEW_MAC_MACHINE_ID=$(generate_mac_machine_id)
  NEW_DEV_DEVICE_ID=$(uuidgen)
  NEW_SQM_ID="{$(uuidgen | tr '[:lower:]' '[:upper:]')}"
  
  if [ ! -f "$STORAGE_JSON" ]; then
    echo -e "${RED}Storage file not found: $STORAGE_JSON${RESET}"
    return 1
  fi
  
  # Backup original file
  cp "$STORAGE_JSON" "${STORAGE_JSON}.bak" || {
    echo -e "${RED}Failed to backup storage.json${RESET}"
    return 1
  }
  
  # Ensure backup file has correct ownership
  chown $REAL_USER:staff "${STORAGE_JSON}.bak"
  chmod 644 "${STORAGE_JSON}.bak"
  
  # Use osascript to update JSON file
  echo -e "${CYAN}Updating identifiers...${RESET}"
  osascript -l JavaScript << EOF
    function run() {
      const fs = $.NSFileManager.defaultManager;
      const path = '$STORAGE_JSON';
      const nsdata = fs.contentsAtPath(path);
      const nsstr = $.NSString.alloc.initWithDataEncoding(nsdata, $.NSUTF8StringEncoding);
      const content = nsstr.js;
      const data = JSON.parse(content);
      
      data['telemetry.machineId'] = '$NEW_MACHINE_ID';
      data['telemetry.macMachineId'] = '$NEW_MAC_MACHINE_ID';
      data['telemetry.devDeviceId'] = '$NEW_DEV_DEVICE_ID';
      data['telemetry.sqmId'] = '$NEW_SQM_ID';
      
      const newContent = JSON.stringify(data, null, 2);
      const newData = $.NSString.alloc.initWithUTF8String(newContent);
      newData.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
      
      return "success";
    }
EOF
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to update storage.json${RESET}"
    return 1
  fi
  
  # Ensure modified file has correct ownership
  chown $REAL_USER:staff "$STORAGE_JSON"
  chmod 644 "$STORAGE_JSON"
  
  echo -e "${GREEN}✓ Identifiers updated successfully${RESET}"
  
  return 0
}

# Modify app files
modify_app_files() {
  # Create timestamp for temp directory
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  TEMP_DIR="/tmp/cursor_reset_${TIMESTAMP}"
  TEMP_APP="$TEMP_DIR/Cursor.app"
  
  echo -e "${CYAN}Copying and modifying Cursor.app...${RESET}"
  
  # Ensure temp directory doesn't exist
  if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  
  # Create temp directory
  mkdir -p "$TEMP_DIR" || {
    echo -e "${RED}Failed to create temporary directory${RESET}"
    return 1
  }
  
  # Copy app to temp directory
  (cp -R "/Applications/Cursor.app" "$TEMP_DIR" > /dev/null 2>&1) &
  copy_pid=$!
  spinner $copy_pid "Processing"
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to copy application${RESET}"
    rm -rf "$TEMP_DIR"
    return 1
  fi
  
  # Ensure temp directory has correct permissions
  chown -R $REAL_USER:staff "$TEMP_DIR"
  chmod -R 755 "$TEMP_DIR"
  
  # Remove signatures silently
  echo -e "${CYAN}Removing signatures...${RESET}"
  codesign --remove-signature "$TEMP_APP" > /dev/null 2>&1
  
  # Remove signatures from all related components silently
  components=(
    "$TEMP_APP/Contents/Frameworks/Cursor Helper.app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (GPU).app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (Plugin).app"
    "$TEMP_APP/Contents/Frameworks/Cursor Helper (Renderer).app"
  )
  
  for component in "${components[@]}"; do
    if [ -e "$component" ]; then
      codesign --remove-signature "$component" > /dev/null 2>&1
    fi
  done
  
  # Modify files in temp app
  FILES=(
    "$TEMP_APP/Contents/Resources/app/out/main.js"
    "$TEMP_APP/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
  )
  
  echo -e "${CYAN}Modifying application files...${RESET}"
  # Process each file
  modified_count=0
  for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
      continue
    fi
    
    # Create backup
    backup_file="${file}.bak"
    cp "$file" "$backup_file" || continue
    
    # Read file content
    content=$(cat "$file")
    
    # Find IOPlatformUUID position
    uuid_pos=$(printf "%s" "$content" | grep -b -o "IOPlatformUUID" | cut -d: -f1)
    if [ -z "$uuid_pos" ]; then
      continue
    fi
    
    # Find switch position before UUID
    before_uuid=${content:0:$uuid_pos}
    switch_pos=$(printf "%s" "$before_uuid" | grep -b -o "switch" | tail -n1 | cut -d: -f1)
    if [ -z "$switch_pos" ]; then
      continue
    fi
    
    # Build new file content
    printf "%sreturn crypto.randomUUID();\n%s" "${content:0:$switch_pos}" "${content:$switch_pos}" > "$file" || continue
    
    modified_count=$((modified_count+1))
  done
  
  echo -e "${GREEN}✓ Modified $modified_count files${RESET}"
  
  # Re-sign temporary app silently
  echo -e "${CYAN}Re-signing application...${RESET}"
  codesign --sign - "$TEMP_APP" --force --deep > /dev/null 2>&1
  
  # Close original app
  echo -e "${CYAN}Closing Cursor...${RESET}"
  osascript -e 'tell application "Cursor" to quit' > /dev/null 2>&1
  sleep 2
  
  # Backup original app
  echo -e "${CYAN}Backing up and installing modified app...${RESET}"
  if [ -d "/Applications/Cursor.backup.app" ]; then
    rm -rf "/Applications/Cursor.backup.app"
  fi
  mv "/Applications/Cursor.app" "/Applications/Cursor.backup.app" || {
    echo -e "${RED}Failed to backup original application${RESET}"
    rm -rf "$TEMP_DIR"
    return 1
  }
  
  # Move modified app to Applications folder
  mv "$TEMP_APP" "/Applications/" || {
    echo -e "${RED}Failed to install modified application${RESET}"
    mv "/Applications/Cursor.backup.app" "/Applications/Cursor.app"
    rm -rf "$TEMP_DIR"
    return 1
  }
  
  # Clean up temp directory
  rm -rf "$TEMP_DIR"
  
  echo -e "${GREEN}✓ Application successfully modified${RESET}"
  
  return 0
}

# Perform full reset
perform_full_reset() {
  clear
  show_header
  echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║               Performing Full Cursor Reset                 ║${RESET}"
  echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}\n"
  
  # Check if Cursor is running and close it
  check_cursor_running
  
  # Update storage.json
  echo -e "\n${BOLD}${BLUE}● Step 1/2: ${RESET}${BOLD}Updating identifiers${RESET}"
  update_storage_json
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to update identifiers. Aborting reset.${RESET}"
    read -p "$(echo -e "${BOLD}Press Enter to return to the main menu${RESET}")"
    return
  fi
  
  # Modify app files
  echo -e "\n${BOLD}${BLUE}● Step 2/2: ${RESET}${BOLD}Modifying application files${RESET}"
  modify_app_files
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to modify application files.${RESET}"
    read -p "$(echo -e "${BOLD}Press Enter to return to the main menu${RESET}")"
    return
  fi
  
  echo -e "\n${GREEN}${BOLD}✨ Reset completed successfully! ✨${RESET}"
  echo -e "${YELLOW}You can now launch Cursor with fresh identifiers.${RESET}"
  read -p "$(echo -e "${BOLD}Press Enter to return to the main menu${RESET}")"
}

# View current Cursor information
view_current_info() {
  clear
  show_header
  echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║               Current Cursor Information                   ║${RESET}"
  echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}\n"
  
  if [ ! -f "$STORAGE_JSON" ]; then
    echo -e "${RED}Storage file not found: $STORAGE_JSON${RESET}"
    return
  fi
  
  # Extract current IDs using osascript
  echo -e "${CYAN}Retrieving current identifiers...${RESET}"
  
  local current_ids=$(osascript -l JavaScript << EOF
    function run() {
      try {
        const fs = $.NSFileManager.defaultManager;
        const path = '$STORAGE_JSON';
        const nsdata = fs.contentsAtPath(path);
        if (!nsdata) return "File could not be read";
        
        const nsstr = $.NSString.alloc.initWithDataEncoding(nsdata, $.NSUTF8StringEncoding);
        const content = nsstr.js;
        const data = JSON.parse(content);
        
        return JSON.stringify({
          machineId: data['telemetry.machineId'] || "Not set",
          macMachineId: data['telemetry.macMachineId'] || "Not set",
          devDeviceId: data['telemetry.devDeviceId'] || "Not set",
          sqmId: data['telemetry.sqmId'] || "Not set"
        });
      } catch (e) {
        return "Error: " + e.toString();
      }
    }
EOF
)

  if [[ $current_ids == Error* ]]; then
    echo -e "${RED}$current_ids${RESET}"
    return
  fi
  
  # Parse and display the JSON data
  local machine_id=$(echo "$current_ids" | grep -o '"machineId":"[^"]*"' | cut -d'"' -f4)
  local mac_machine_id=$(echo "$current_ids" | grep -o '"macMachineId":"[^"]*"' | cut -d'"' -f4)
  local dev_device_id=$(echo "$current_ids" | grep -o '"devDeviceId":"[^"]*"' | cut -d'"' -f4)
  local sqm_id=$(echo "$current_ids" | grep -o '"sqmId":"[^"]*"' | cut -d'"' -f4)
  
  # Truncate long IDs for display
  if [ ${#machine_id} -gt 20 ]; then
    machine_id="${machine_id:0:20}..."
  fi
  
  if [ ${#dev_device_id} -gt 20 ]; then
    dev_device_id="${dev_device_id:0:20}..."
  fi
  
  if [ ${#sqm_id} -gt 20 ]; then
    sqm_id="${sqm_id:0:20}..."
  fi
  
  echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║                  Current Identifiers                       ║${RESET}"
  echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${MAGENTA}┌─ Machine ID:${RESET}      $machine_id"
  echo -e "${MAGENTA}├─ Mac Machine ID:${RESET}  $mac_machine_id"
  echo -e "${MAGENTA}├─ Dev Device ID:${RESET}   $dev_device_id"
  echo -e "${MAGENTA}└─ SQM ID:${RESET}          $sqm_id"
  
  echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║                  Application Files                        ║${RESET}"
  echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
  
  local file_status="✓"
  for file in "${APP_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      file_status="✗"
      break
    fi
  done
  
  if [ "$file_status" = "✓" ]; then
    echo -e "${GREEN}✓${RESET} All required files are present"
  else
    echo -e "${RED}✗${RESET} Some required files are missing"
  fi
  
  echo
  read -p "$(echo -e "${BOLD}Press Enter to return to the main menu${RESET}")"
}

# Show about information
show_about() {
  clear
  show_header
  echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║                About Resetor                     ║${RESET}"
  echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}\n"
  echo -e "${BOLD}Version:${RESET} ${SCRIPT_VERSION}"
  echo -e "${BOLD}Author:${RESET} ${SCRIPT_AUTHOR}"
  echo -e "${BOLD}GitHub:${RESET} ${SCRIPT_GITHUB}"
  echo -e "${BOLD}Created:${RESET} $(date +"%B %d, %Y")"
  echo -e "${BOLD}Description:${RESET} This tool resets Cursor app identifiers and modifies"
  echo -e "             application files to generate new random UUIDs."
  echo -e "${BOLD}Features:${RESET}"
  echo -e " ${GREEN}•${RESET} Interactive menu interface with color coding"
  echo -e " ${GREEN}•${RESET} View current Cursor identifiers"
  echo -e " ${GREEN}•${RESET} Reset all identifiers with backup creation"
  echo -e " ${GREEN}•${RESET} Restore from backup if needed"
  echo -e " ${GREEN}•${RESET} Progress indicators and detailed status messages"
  echo
  read -p "$(echo -e "${BOLD}Press Enter to return to the main menu${RESET}")"
}

# Main menu
show_main_menu() {
  while true; do
    clear
    show_header
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${BLUE}║                        Main Menu                          ║${RESET}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}\n"
    echo -e " ${BOLD}1.${RESET} ${CYAN}📊${RESET} View Current Cursor Information"
    echo -e " ${BOLD}2.${RESET} ${CYAN}🔄${RESET} Perform Full Reset"
    echo -e " ${BOLD}3.${RESET} ${CYAN}📦${RESET} Restore from Backup"
    echo -e " ${BOLD}4.${RESET} ${CYAN}ℹ️${RESET}  About"
    echo -e " ${BOLD}0.${RESET} ${CYAN}🚪${RESET} Exit\n"
    
    read -p "$(echo -e "${BOLD}Enter your choice [0-4]: ${RESET}")" choice
    
    case $choice in
      1) view_current_info ;;
      2) perform_full_reset ;;
      3) restore_files ;;
      4) show_about ;;
      0) 
        clear
        echo -e "${GREEN}Thank you for using Resetor!${RESET}"
        exit 0
        ;;
      *) 
        echo -e "${RED}Invalid option. Press Enter to try again.${RESET}"
        read
        ;;
    esac
  done
}

# Main function
main() {
  # Check if script is run with --restore flag
  if [ "$1" = "--restore" ]; then
    get_real_user
    set_file_paths
    restore_files
    exit 0
  fi
  
  # Initialize
  get_real_user
  check_requirements
  set_file_paths
  
  # Show main menu
  show_main_menu
}

# Run main function
main "$@"

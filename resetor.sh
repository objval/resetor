#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Exit status of the last command that threw a non-zero exit code is returned.
set -o pipefail

# --- Configuration ---
readonly APP_NAME="Cursor"
readonly APP_PATH="/Applications/${APP_NAME}.app"
readonly APP_BACKUP_PATH="/Applications/${APP_NAME}.backup.app"
readonly REQUIRED_COMMANDS=("uuidgen" "ioreg" "codesign" "osascript" "pgrep" "awk" "sed" "grep" "cut" "tr" "mv" "cp" "rm" "chown" "chmod" "mktemp" "logname" "who" "eval" "printf" "date")

# --- Logging Functions ---
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

# --- Helper Functions ---

# Determine the actual user running the script, even with sudo/doas
get_real_user() {
    local user=""
    if [ -n "${SUDO_USER-}" ]; then
        user="$SUDO_USER"
    elif [ -n "${DOAS_USER-}" ]; then
        user="$DOAS_USER"
    else
        # Try 'who am i' first, as it's often reliable in interactive sessions
        user=$(who am i | awk '{print $1}')
        # Fallback to logname if 'who am i' fails (e.g., in some non-interactive contexts)
        if [ -z "$user" ]; then
            user=$(logname)
        fi
    fi

    if [ -z "$user" ]; then
        log_error "Could not determine the real user."
        exit 1
    fi
    echo "$user"
}

# Get the home directory for the real user
get_real_home() {
    local real_user="$1"
    # Use eval carefully to expand the tilde
    eval echo "~$real_user"
}

# Check if required commands are available
check_dependencies() {
    log_info "Checking required commands..."
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command '$cmd' not found. Please install it."
            exit 1
        fi
    done
    log_info "All required commands found."
}

# Generate a UUID resembling macOS machine IDs (version 4, variant 1)
generate_mac_machine_id() {
    local uuid
    uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
    # Ensure 13th char is '4' (UUID version 4)
    uuid="${uuid:0:12}4${uuid:13}"
    # Ensure 17th char is '8', '9', 'a', or 'b' (UUID variant 1)
    local random_hex
    # Generate a random hex digit (0-f) loosely based on $RANDOM
    random_hex=$(printf '%x' $((RANDOM % 16)))
    local random_num=$((16#$random_hex))
    # Mask to get 0-3, then OR with 8 (binary 1000) -> results in 8,9,a,b
    local new_char
    new_char=$(printf '%x' $(( (random_num & 0x3) | 0x8 )))
    uuid="${uuid:0:16}${new_char}${uuid:17}"
    echo "$uuid"
}

# Generate a 64-character random ID by concatenating two UUIDs (stripped)
generate_random_id() {
    local uuid1 uuid2
    uuid1=$(uuidgen | tr -d '-')
    uuid2=$(uuidgen | tr -d '-')
    echo "${uuid1}${uuid2}"
}

# Generate a standard uppercase UUID enclosed in braces
generate_sqm_id() {
    echo "{$(uuidgen | tr '[:lower:]' '[:upper:]')}"
}

# Wait for the Cursor application process to exit
wait_for_cursor_to_quit() {
    log_info "Checking if $APP_NAME is running..."
    # Check by exact process name and by app bundle path fragment
    while pgrep -xq "$APP_NAME" || pgrep -f "${APP_NAME}.app" > /dev/null; do
        log_info "$APP_NAME is running. Waiting for it to close..."
        # Attempt to gracefully quit the application first
        osascript -e "tell application \"$APP_NAME\" to quit" &>/dev/null || true
        sleep 2
    done
    log_info "$APP_NAME is closed. Proceeding..."
}

# Clean up temporary directory on exit/error
cleanup() {
    if [ -n "${TEMP_DIR-}" ] && [ -d "$TEMP_DIR" ]; then
        log_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# --- Core Functions ---

# Update the storage.json file with new IDs
update_storage_json() {
    local storage_json_path="$1"
    local real_user="$2"
    local new_machine_id="$3"
    local new_mac_machine_id="$4"
    local new_dev_device_id="$5"
    local new_sqm_id="$6"

    if [ ! -f "$storage_json_path" ]; then
        log_warn "Storage file not found: $storage_json_path. Skipping update."
        return
    fi

    local backup_file="${storage_json_path}.bak"
    log_info "Backing up $storage_json_path to $backup_file"
    cp "$storage_json_path" "$backup_file" || {
        log_error "Failed to backup storage.json."
        exit 1
    }
    chown "$real_user":staff "$backup_file"
    chmod 644 "$backup_file"

    log_info "Updating IDs in $storage_json_path..."
    # Use osascript with JavaScript for safe JSON manipulation
    if ! osascript -l JavaScript -e '
        function run(args) {
            const fs = $.NSFileManager.defaultManager;
            const path = args[0];
            const newMachineId = args[1];
            const newMacMachineId = args[2];
            const newDevDeviceId = args[3];
            const newSqmId = args[4];

            try {
                const nsdata = fs.contentsAtPath(path);
                if (!nsdata) throw new Error("Failed to read file content.");

                const nsstr = $.NSString.alloc.initWithDataEncoding(nsdata, $.NSUTF8StringEncoding);
                if (!nsstr) throw new Error("Failed to decode file content.");

                const content = nsstr.js;
                const data = JSON.parse(content);

                data["telemetry.machineId"] = newMachineId;
                data["telemetry.macMachineId"] = newMacMachineId;
                data["telemetry.devDeviceId"] = newDevDeviceId;
                data["telemetry.sqmId"] = newSqmId;

                const newContent = JSON.stringify(data, null, 2);
                const newData = $.NSString.alloc.initWithUTF8String(newContent);
                const success = newData.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);

                if (!success) throw new Error("Failed to write updated content to file.");

                return "success";
            } catch (e) {
                // Write error to stderr for capturing
                const errorStr = $.NSString.alloc.initWithUTF8String(e.toString());
                errorStr.writeToFileAtomicallyEncodingError("/dev/stderr", true, $.NSUTF8StringEncoding, null);
                return "error";
            }
        }
    ' -- "$storage_json_path" "$new_machine_id" "$new_mac_machine_id" "$new_dev_device_id" "$new_sqm_id"; then
        log_error "Failed to update storage.json using osascript."
        # Optional: Restore backup immediately on failure?
        # cp "$backup_file" "$storage_json_path"
        exit 1
    fi

    # Ensure correct ownership and permissions after modification
    chown "$real_user":staff "$storage_json_path"
    chmod 644 "$storage_json_path"

    log_info "Successfully updated IDs in $storage_json_path."
    echo "  New telemetry.machineId: $new_machine_id"
    echo "  New telemetry.macMachineId: $new_mac_machine_id"
    echo "  New telemetry.devDeviceId: $new_dev_device_id"
    echo "  New telemetry.sqmId: $new_sqm_id"
}

# Modify specific JavaScript files within the copied application bundle
modify_application_files() {
    local temp_app_path="$1"

    local files_to_modify=(
        "$temp_app_path/Contents/Resources/app/out/main.js"
        "$temp_app_path/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
    )

    log_info "Patching JavaScript files..."
    for file in "${files_to_modify[@]}"; do
        if [ ! -f "$file" ]; then
            log_warn "File not found, skipping patch: $file"
            continue
        fi

        log_info "Processing file: $file"
        local content
        content=$(cat "$file") || {
            log_warn "Could not read file: $file. Skipping."
            continue
        }

        # Find the byte offset of the last "IOPlatformUUID" occurrence
        local uuid_pos
        uuid_pos=$(printf "%s" "$content" | grep -F -b -o "IOPlatformUUID" | tail -n 1 | cut -d: -f1)

        if [ -z "$uuid_pos" ]; then
            log_warn "'IOPlatformUUID' not found in $file. Skipping patch for this file."
            continue
        fi

        # Find the byte offset of the last "switch" keyword before "IOPlatformUUID"
        local before_uuid="${content:0:$uuid_pos}"
        local switch_pos
        switch_pos=$(printf "%s" "$before_uuid" | grep -F -b -o "switch" | tail -n 1 | cut -d: -f1)

        if [ -z "$switch_pos" ]; then
            log_warn "'switch' keyword not found before 'IOPlatformUUID' in $file. Skipping patch for this file."
            continue
        fi

        # Create the modified content in a temporary file first for safety
        local temp_patch_file
        temp_patch_file=$(mktemp)
        printf "%sreturn crypto.randomUUID();\n%s" "${content:0:$switch_pos}" "${content:$switch_pos}" > "$temp_patch_file" || {
            log_error "Failed to create patched content for $file."
            rm -f "$temp_patch_file"
            exit 1
        }

        # Replace the original file with the patched content
        mv "$temp_patch_file" "$file" || {
             log_error "Failed to overwrite original file with patched content: $file."
             rm -f "$temp_patch_file" # Ensure temp file is removed even if mv failed earlier
             exit 1
        }
        log_info "Successfully patched file: $file"
    done
}

# Remove code signature from the app and its components
remove_code_signatures() {
    local temp_app_path="$1"
    log_info "Removing code signatures from temporary app..."

    # Components known to be signed within the app bundle
    local components_to_unsign=(
        "$temp_app_path" # The main app bundle first
        "$temp_app_path/Contents/Frameworks/Cursor Helper.app"
        "$temp_app_path/Contents/Frameworks/Cursor Helper (GPU).app"
        "$temp_app_path/Contents/Frameworks/Cursor Helper (Plugin).app"
        "$temp_app_path/Contents/Frameworks/Cursor Helper (Renderer).app"
    )

    for component in "${components_to_unsign[@]}"; do
        if [ -e "$component" ]; then
            log_info "Removing signature from: $component"
            codesign --remove-signature "$component" || {
                # This might fail if not signed, which is okay sometimes. Warn instead of error.
                log_warn "Failed to remove signature from $component. This might be okay."
            }
        else
             log_warn "Component not found, skipping signature removal: $component"
        fi
    done
}

# Re-sign the application bundle with an ad-hoc signature
resign_application_ad_hoc() {
    local temp_app_path="$1"
    log_info "Re-signing the application with an ad-hoc signature..."
    # Use --force to overwrite existing (though removed) signature info
    # Use --deep to sign nested components automatically
    codesign --sign - "$temp_app_path" --force --deep || {
        # Ad-hoc signing failure might sometimes be acceptable depending on macOS security settings
        log_warn "Failed to ad-hoc re-sign the application. It might not launch depending on security settings."
    }
}

# Backup the original application and replace it with the modified one
backup_and_replace_app() {
    local temp_app_path="$1"

    log_info "Preparing to replace the original application..."

    # Ensure the original application exists
    if [ ! -d "$APP_PATH" ]; then
        log_error "Original application not found at $APP_PATH. Cannot proceed."
        exit 1
    fi

    # Backup original application
    log_info "Backing up original application to $APP_BACKUP_PATH..."
    if [ -d "$APP_BACKUP_PATH" ]; then
        log_info "Existing backup found. Removing it."
        rm -rf "$APP_BACKUP_PATH" || {
            log_error "Failed to remove existing backup at $APP_BACKUP_PATH."
            exit 1
        }
    fi
    mv "$APP_PATH" "$APP_BACKUP_PATH" || {
        log_error "Failed to backup the original application to $APP_BACKUP_PATH."
        exit 1
    }

    # Move modified application into place
    log_info "Installing modified application..."
    mv "$temp_app_path" "/Applications/" || {
        log_error "Failed to move modified application to /Applications/."
        log_info "Attempting to restore original application from backup..."
        mv "$APP_BACKUP_PATH" "$APP_PATH" || log_warn "Failed to restore original application from backup."
        exit 1
    }

    log_info "Application modification complete!"
    log_info "The original application is backed up at: $APP_BACKUP_PATH"
    log_info "You can restore it by running: $0 --restore"
}

# Restore the application and storage.json from backups
restore_backup() {
    local storage_json_path="$1"
    local real_user="$2"
    local storage_backup_file="${storage_json_path}.bak"

    log_info "--- Starting Restore Operation ---"

    # Restore storage.json
    if [ -f "$storage_backup_file" ]; then
        log_info "Restoring $storage_json_path from $storage_backup_file..."
        cp "$storage_backup_file" "$storage_json_path" && {
            chown "$real_user":staff "$storage_json_path"
            chmod 644 "$storage_json_path"
            log_info "Restored $storage_json_path."
        } || log_error "Failed to restore $storage_json_path."
    else
        log_warn "Backup file for storage.json not found ($storage_backup_file). Skipping restore."
    fi

    # Restore application
    if [ -d "$APP_BACKUP_PATH" ]; then
        log_info "Restoring $APP_NAME application from $APP_BACKUP_PATH..."

        # Ensure the current (potentially modified) app is closed before replacing
        log_info "Attempting to close $APP_NAME before restoring..."
        osascript -e "tell application \"$APP_NAME\" to quit" &>/dev/null || true
        sleep 2 # Give it time to close

        if [ -d "$APP_PATH" ]; then
             log_info "Removing current $APP_PATH..."
             rm -rf "$APP_PATH" || {
                 log_error "Failed to remove current $APP_PATH. Cannot restore."
                 exit 1
             }
        fi

        log_info "Moving backup to $APP_PATH..."
        mv "$APP_BACKUP_PATH" "$APP_PATH" && {
            log_info "Successfully restored $APP_NAME application."
        } || log_error "Failed to restore $APP_NAME application from $APP_BACKUP_PATH."
    else
        log_warn "Backup application directory not found ($APP_BACKUP_PATH). Skipping restore."
    fi

    log_info "Restore operation finished."
    exit 0
}

# --- Main Execution ---

# Register cleanup function to run on exit (normal or error) or interrupt
trap cleanup EXIT TERM INT

# Determine User and Home Directory
REAL_USER=$(get_real_user)
REAL_HOME=$(get_real_home "$REAL_USER")
log_info "Running as effective user: $(whoami), Actual user: $REAL_USER, Home: $REAL_HOME"

# Define user-specific paths
STORAGE_JSON_PATH="$REAL_HOME/Library/Application Support/$APP_NAME/User/globalStorage/storage.json"

# Check for --restore argument first
if [ "${1-}" = "--restore" ]; then
    restore_backup "$STORAGE_JSON_PATH" "$REAL_USER"
    # restore_backup exits upon completion
fi

# Perform Pre-checks
check_dependencies
wait_for_cursor_to_quit # Ensure Cursor is not running before modification

# Generate New IDs
log_info "Generating new IDs..."
NEW_MACHINE_ID=$(generate_random_id)
NEW_MAC_MACHINE_ID=$(generate_mac_machine_id)
NEW_DEV_DEVICE_ID=$(uuidgen)
NEW_SQM_ID=$(generate_sqm_id)

# Update storage.json
update_storage_json "$STORAGE_JSON_PATH" "$REAL_USER" "$NEW_MACHINE_ID" "$NEW_MAC_MACHINE_ID" "$NEW_DEV_DEVICE_ID" "$NEW_SQM_ID"

# Modify the Application Bundle
log_info "Starting application modification process..."

# Create secure temporary directory (will be cleaned up by trap)
TEMP_DIR=$(mktemp -d "/tmp/${APP_NAME}_reset_XXXXXX")
TEMP_APP_PATH="$TEMP_DIR/${APP_NAME}.app"
log_info "Created temporary directory: $TEMP_DIR"

# Copy application to temporary directory
log_info "Copying $APP_PATH to $TEMP_DIR..."
cp -R "$APP_PATH" "$TEMP_DIR" || {
    log_error "Failed to copy application to temporary directory."
    exit 1
}

# Set correct permissions on the temporary copy (important for codesign)
chown -R "$REAL_USER":staff "$TEMP_APP_PATH"
chmod -R u+rwX "$TEMP_APP_PATH"

# Perform modifications on the temporary copy
remove_code_signatures "$TEMP_APP_PATH"
modify_application_files "$TEMP_APP_PATH"
resign_application_ad_hoc "$TEMP_APP_PATH"

# Replace original application with modified one (includes backup step)
backup_and_replace_app "$TEMP_APP_PATH"

log_info "All operations completed successfully!"
exit 0
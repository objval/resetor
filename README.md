# 🔄 Resetor

![Version](https://img.shields.io/badge/version-2.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

A professional, interactive tool for resetting and managing Cursor app identifiers on macOS.

## 📋 Overview

Resetor provides a user-friendly interface to manage your Cursor app identifiers and settings. This tool allows you to view current identifiers, perform complete resets, and restore from backups when needed.

![Screenshot](https://via.placeholder.com/800x450.png?text=Cursor+Reset+Tool+Screenshot)

## ✨ Features

- **📊 View Current Information**: Display all current Cursor identifiers without making changes
- **🔄 Full Reset**: Reset all identifiers with automatic backup creation
- **📦 Restore Functionality**: Easily restore from backups if needed
- **🎨 Interactive Interface**: User-friendly terminal UI with color coding and intuitive navigation
- **🔒 Safe Operation**: Automatic backups created before any modifications

## 🚀 Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/objval/cursor-reset-tool.git
   cd cursor-reset-tool
   ```

2. Make the script executable:
   ```bash
   chmod +x remake.sh
   ```

## 🔧 Usage

### Interactive Mode

Run the script without arguments to launch the interactive menu:

```bash
./remake.sh
```

This will display the main menu with the following options:
- View Current Cursor Information
- Perform Full Reset
- Restore from Backup
- About
- Exit

### Command Line Options

Restore from backup directly:
```bash
./remake.sh --restore
```

## ⚙️ How It Works

The tool performs several operations to reset Cursor app identifiers:

1. **Identifier Reset**: Updates various identifiers in the `storage.json` file:
   - Machine ID
   - Mac Machine ID
   - Device ID
   - SQM ID

2. **Application Modification**: Modifies specific JavaScript files in the Cursor application to generate random UUIDs instead of using hardware identifiers.

3. **Backup Creation**: Automatically creates backups before making any changes, allowing you to restore if needed.

## 🔍 Technical Details

### Files Modified

- `~/Library/Application Support/Cursor/User/globalStorage/storage.json`
- `/Applications/Cursor.app/Contents/Resources/app/out/main.js`
- `/Applications/Cursor.app/Contents/Resources/app/out/vs/code/node/cliProcessMain.js`

### Requirements

- macOS operating system
- Cursor app installed
- Administrator privileges (for application modification)

## ⚠️ Disclaimer

This tool is provided for educational and development purposes only. Use at your own risk. Always ensure you have backups before modifying any application files.

## 👨‍💻 Author

**objval**
- GitHub: [github.com/objval](https://github.com/objval)

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 📝 Installation Guide

## 🛠️ Step 1: Enable Freeform Windows
1. **Enable Developer Options:** Settings > About Phone > Tap Build Number 7 times.
2. **Enable Flags:** Go to System > Developer Options > Under Apps, enable:
   - ✅ Enable freeform windows
   - ✅ Force activities to be resizable
   - ✅ Enable non-resizable in multi-window
3. **Reboot your device.**

## ⚡ Step 2: Configure Root & Termux
1. Enable **Magisk** (or **KernelSU**) and **LSPosed** or **Root Permission** (RF).
2. Open **Magisk/Kitsune/Root Permission** > **Superuser** > Ensure **Termux** is granted root access.
*Note:  If you cannot find the Termux app in Magisk/Kitsune or KernelSU, skip this step and proceed to the next step.*

## 📦 Step 3: Termux Setup
Run this single command in Termux ([Download Termux](https://f-droid.org/packages/com.termux/)):
💻 Desktop Copy:
```bash
termux-setup-storage && pkg update -y && pkg upgrade -y && pkg install -y lua53 tsu python figlet android-tools sqlite && pip install pyfiglet rich
```
📱 Mobile Copy:
`termux-setup-storage && pkg update -y && pkg upgrade -y && pkg install -y lua53 tsu python figlet android-tools sqlite && pip install pyfiglet rich`
*Grant storage permission when prompted and type “y” if asked.*

## 📥 Step 4: Install Loader (Latest Version)

Loader Rejoin sekarang **satu file** (`yanamin.lua`) — engine, supervisor terminal,
template config, dan sistem key sudah jadi satu. Cukup satu baris curl, tanpa
unduh repo.

**Android 10:**
💻 Desktop Copy:
```bash
curl -L -o /sdcard/download/yanamin.lua https://raw.githubusercontent.com/apengjers/rejoin/main/yanamin.lua
```
📱 Mobile Copy:
`curl -L -o /sdcard/download/yanamin.lua https://raw.githubusercontent.com/apengjers/rejoin/main/yanamin.lua`

**Android 12+:**
💻 Desktop Copy:
```bash
curl -L -o /sdcard/Download/yanamin.lua https://raw.githubusercontent.com/apengjers/rejoin/main/yanamin.lua
```
📱 Mobile Copy:
`curl -L -o /sdcard/Download/yanamin.lua https://raw.githubusercontent.com/apengjers/rejoin/main/yanamin.lua`

## 🚀 Step 5: Run & Setup
1. Execute
**Android 10:**
💻 Desktop Copy:
```bash
lua /sdcard/download/yanamin.lua
```
📱 Mobile Copy:
`lua /sdcard/download/yanamin.lua`

**Android 12+:**
💻 Desktop Copy:
```bash
lua /sdcard/Download/yanamin.lua
```
📱 Mobile Copy:
`lua /sdcard/Download/yanamin.lua`

2. Setup
**Select Packages:** Press **Enter** to auto-detect Roblox. (*If it is not detected, type manual. To find the Roblox package name:* <#1442135281569628241> )
**Final Settings:** Configure delay and Private Server URL.
*Note: Grant Root permissions when prompted.*

## 🔁 Step 6 (opsional): Auto-start saat boot

1. Pasang aplikasi **Termux:Boot** dari sumber yang **sama** dengan Termux kamu (F-Droid ↔ F-Droid, GitHub ↔ GitHub).
2. Jalankan loader, pilih **menu `9) Auto-boot (Termux:Boot)`** → `1) Install / update script boot`.
3. **Buka aplikasi Termux:Boot sekali**, lalu reboot. Engine jalan otomatis tanpa jendela Termux.

*Note: cek `3) Lihat 10 baris terakhir boot.log` kalau clone tidak terbuka setelah reboot.*

——————
*To reset the config settings, delete the generated config and run again — the loader recreates it from its built-in template.*
**Android 10:**
💻 Desktop Copy:
```bash
rm -f /sdcard/download/config/config.lua
```
📱 Mobile Copy:
`rm -f /sdcard/download/config/config.lua`

**Android 12+:**
💻 Desktop Copy:
```bash
rm -f /sdcard/Download/config/config.lua
```
📱 Mobile Copy:
`rm -f /sdcard/Download/config/config.lua`

*Note: Grant Root permissions when prompted.*
#!/bin/bash
set -euo pipefail
ENGINE_SOURCE=${1:?missing engine binary}
CONFIG_PATH=${2:?missing config path}
ENGINE_DEST=/Library/PrivilegedHelperTools/com.willowfan.engine
PLIST_PATH=/Library/LaunchDaemons/com.willowfan.engine.plist
LABEL=com.willowfan.engine
[[ $(id -u) -eq 0 ]] || { echo 'Administrator authorization is required.' >&2; exit 1; }
[[ "$ENGINE_SOURCE" == /* && -f "$ENGINE_SOURCE" && -x "$ENGINE_SOURCE" ]] || { echo 'Engine binary is missing.' >&2; exit 1; }
[[ "$CONFIG_PATH" == /* && -f "$CONFIG_PATH" ]] || { echo 'User configuration is missing.' >&2; exit 1; }
[[ $(stat -f '%u' "$CONFIG_PATH") -ne 0 ]] || { echo 'Configuration must be owned by the user.' >&2; exit 1; }
cd /
mkdir -p /Library/PrivilegedHelperTools
PLIST_TEMP=$(mktemp "$PLIST_PATH.XXXXXX")
trap 'rm -f "$PLIST_TEMP"' EXIT
# Use only macOS system tools; installing the app does not require Python or Xcode.
/usr/bin/plutil -create xml1 "$PLIST_TEMP"
/usr/bin/plutil -insert Label -string "$LABEL" "$PLIST_TEMP"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$PLIST_TEMP"
/usr/bin/plutil -insert ProgramArguments.0 -string "$ENGINE_DEST" "$PLIST_TEMP"
/usr/bin/plutil -insert ProgramArguments.1 -string daemon "$PLIST_TEMP"
/usr/bin/plutil -insert ProgramArguments.2 -string --config "$PLIST_TEMP"
/usr/bin/plutil -insert ProgramArguments.3 -string "$CONFIG_PATH" "$PLIST_TEMP"
/usr/bin/plutil -insert RunAtLoad -bool true "$PLIST_TEMP"
/usr/bin/plutil -insert KeepAlive -bool true "$PLIST_TEMP"
/usr/bin/plutil -insert StandardOutPath -string /Library/Logs/WillowFan.log "$PLIST_TEMP"
/usr/bin/plutil -insert StandardErrorPath -string /Library/Logs/WillowFan.log "$PLIST_TEMP"
/usr/bin/plutil -lint "$PLIST_TEMP" >/dev/null
chown root:wheel "$PLIST_TEMP"
chmod 644 "$PLIST_TEMP"
if launchctl print "system/$LABEL" >/dev/null 2>&1; then launchctl bootout "system/$LABEL"; fi
install -o root -g wheel -m 755 "$ENGINE_SOURCE" "$ENGINE_DEST"
mv -f "$PLIST_TEMP" "$PLIST_PATH"
touch /Library/Logs/WillowFan.log
chmod 644 /Library/Logs/WillowFan.log
launchctl bootstrap system "$PLIST_PATH"
echo 'WillowFan control service installed.'

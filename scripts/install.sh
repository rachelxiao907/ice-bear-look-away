#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$repo_dir/scripts/build.sh"

install_dir="${INSTALL_DIR:-$HOME/Applications}"
app_dir="$install_dir/Ice Bear Reminder.app"
plist="$HOME/Library/LaunchAgents/com.rachel.ice-bear-reminder.plist"
service="gui/$(id -u)/com.rachel.ice-bear-reminder"

if launchctl print "$service" >/dev/null 2>&1; then
	launchctl bootout "$service"
fi
mkdir -p "$install_dir" "$(dirname "$plist")"
rm -rf "$app_dir"
ditto "$repo_dir/build/Ice Bear Reminder.app" "$app_dir"
APP_EXECUTABLE="$app_dir/Contents/MacOS/IceBearReminder" PLIST_PATH="$plist" python3 - <<'PY'
import os
import plistlib

with open(os.environ["PLIST_PATH"], "wb") as output:
    plistlib.dump({
        "Label": "com.rachel.ice-bear-reminder",
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Interactive",
        "ProgramArguments": [os.environ["APP_EXECUTABLE"]],
        "RunAtLoad": True,
    }, output)
PY
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed $app_dir. Use the bear in the menu bar to pause or resume reminders."

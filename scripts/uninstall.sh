#!/bin/bash
set -euo pipefail

plist="$HOME/Library/LaunchAgents/com.rachel.ice-bear-reminder.plist"
service="gui/$(id -u)/com.rachel.ice-bear-reminder"
if launchctl print "$service" >/dev/null 2>&1; then
	launchctl bootout "$service"
fi
if [[ -f "$plist" ]]; then
	app_dir="$(PLIST_PATH="$plist" python3 - <<'PY'
import os
import plistlib

with open(os.environ["PLIST_PATH"], "rb") as source:
    print(os.path.dirname(os.path.dirname(os.path.dirname(plistlib.load(source)["ProgramArguments"][0]))))
PY
)"
	if [[ "$(basename "$app_dir")" == "Ice Bear Reminder.app" ]]; then
		rm -rf "$app_dir"
	fi
	rm "$plist"
fi
if security find-generic-password -s com.rachel.ice-bear-reminder.google-calendar -a primary >/dev/null 2>&1; then
	security delete-generic-password -s com.rachel.ice-bear-reminder.google-calendar -a primary >/dev/null
fi
if defaults read com.rachel.ice-bear-reminder >/dev/null 2>&1; then
	defaults delete com.rachel.ice-bear-reminder >/dev/null
fi
echo "Ice Bear Reminder removed."

#!/bin/bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
APP_PATH="${1:-$PROJECT_DIRECTORY/dist/EnvStore.app}"
USER_IDENTIFIER="$(id -u)"
LAUNCH_AGENTS_DIRECTORY="${HOME}/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIRECTORY/dev.envstore.broker.plist"
CLI_DIRECTORY="${HOME}/.local/bin"
SKILL_SOURCE="$APP_PATH/Contents/Resources/AgentSkills"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"

if [[ ! -d "$APP_PATH" ]]; then
    echo "EnvStore.app was not found at $APP_PATH" >&2
    exit 1
fi

mkdir -p "$LAUNCH_AGENTS_DIRECTORY" "$CLI_DIRECTORY"
install -m 0755 "$APP_PATH/Contents/SharedSupport/envstore" "$CLI_DIRECTORY/envstore"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.envstore.broker</string>
<key>ProgramArguments</key><array><string>$APP_PATH/Contents/Library/LaunchServices/EnvStoreBroker</string></array>
<key>MachServices</key><dict><key>dev.envstore.broker</key><true/></dict>
<key>ProcessType</key><string>Interactive</string>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST

launchctl bootout "gui/$USER_IDENTIFIER/dev.envstore.broker" 2>/dev/null || true
launchctl bootstrap "gui/$USER_IDENTIFIER" "$PLIST_PATH"
launchctl kickstart -k "gui/$USER_IDENTIFIER/dev.envstore.broker"

echo "Installed CLI at $CLI_DIRECTORY/envstore"
echo "Registered broker dev.envstore.broker"
if [[ -d "$SKILL_SOURCE/envstore" ]]; then
    if ! "$CLI_DIRECTORY/envstore" setup install-agent-skill --source "$SKILL_SOURCE" --version "$VERSION"; then
        echo "Warning: EnvStore was installed, but the agent skill was not installed." >&2
        echo "Use the manual retry command printed above or retry from EnvStore Settings." >&2
    fi
else
    echo "Warning: bundled agent skill was not found at $SKILL_SOURCE" >&2
fi
echo "Add $CLI_DIRECTORY to PATH if necessary."

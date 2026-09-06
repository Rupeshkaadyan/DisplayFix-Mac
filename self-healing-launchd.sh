#!/bin/bash
# self-healing-launchd.sh — Install a LaunchAgent that keeps your display settings alive
#
# Usage: ./self-healing-launchd.sh <UUID> <WxH> <HZ>
# Example: ./self-healing-launchd.sh EB5A9C86-B577-8BCA-0857-D6964E3302DB 1920x1080 165
#
# What it does:
#   1. Creates ~/Library/LaunchAgents/com.rupeshkadyan.displayfix.plist
#   2. Loads it into launchd
#   3. The agent runs displayplacer every 5 minutes to re-apply your settings
#      and watches the displays plist mtime for changes (e.g., after sleep/reconnect)
#
# To remove:
#   launchctl unload ~/Library/LaunchAgents/com.rupeshkadyan.displayfix.plist
#   rm ~/Library/LaunchAgents/com.rupeshkadyan.displayfix.plist

set -e

if [ $# -lt 3 ]; then
    echo "Usage: $0 <UUID> <WIDTHxHEIGHT> <HZ>"
    echo "Example: $0 EB5A9C86-B577-8BCA-0857-D6964E3302DB 1920x1080 165"
    exit 1
fi

UUID="$1"
RES="$2"
HZ="$3"
SCALE="${4:-on}"

LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/com.rupeshkadyan.displayfix.plist"
SCRIPT="$HOME/.displayfixWatcher.sh"

mkdir -p "$LAUNCH_AGENT_DIR"

echo "======================================"
echo " DisplayFix — Self-healing LaunchAgent"
echo "======================================"
echo "UUID:  $UUID"
echo "Res:   $RES @ $HZ Hz"
echo "Scale: $SCALE"
echo ""

# Create the watcher script
cat > "$SCRIPT" << EOF
#!/bin/bash
# Auto-applies display settings every 5 minutes and on plist changes
UUID="$UUID"
RES="$RES"
HZ="$HZ"
SCALE="$SCALE"
PLIST="/Library/Preferences/com.apple.windowserver.displays.plist"
MKTIME_FILE="\$HOME/.displayfix_last_mtime"

displayplacer() {
    /opt/homebrew/bin/displayplacer "id:s\${UUID} res:\${RES} hz:\${HZ} color_depth:8 scaling:\${SCALE} origin:(0,0) degree:0" 2>/dev/null
}

# Initial apply
displayplacer

# Record plist mtime
stat -f %m "\$PLIST" > "\$MKTIME_FILE" 2>/dev/null

# Loop: every 300 seconds, check if plist changed
while true; do
    sleep 300
    new_mtime=\$(stat -f %m "\$PLIST" 2>/dev/null)
    old_mtime=\$(cat "\$MKTIME_FILE" 2>/dev/null)
    if [ "\$new_mtime" != "\$old_mtime" ]; then
        displayplacer
        echo \$new_mtime > "\$MKTIME_FILE"
    fi
done
EOF
chmod +x "$SCRIPT"

# Create the LaunchAgent plist
cat > "$LAUNCH_AGENT" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rupeshkadyan.displayfix</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/displayfix.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/displayfix.log</string>
</dict>
</plist>
EOF

echo "📄 LaunchAgent created: $LAUNCH_AGENT"
echo "📜 Watcher script: $SCRIPT"

# Load it
launchctl load "$LAUNCH_AGENT" 2>/dev/null && {
    echo "✅ LaunchAgent loaded."
} || {
    echo "⚠️  Could not load (may need logout/login). Try:"
    echo "   launchctl load $LAUNCH_AGENT"
}

echo ""
echo "To check it's running:"
echo "  launchctl list | grep displayfix"
echo ""
echo "To stop it:"
echo "  launchctl unload $LAUNCH_AGENT"
echo "  rm $LAUNCH_AGENT"
echo ""

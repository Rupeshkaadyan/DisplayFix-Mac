#!/bin/bash
# HDR-Off.command — Toggle HDR OFF for your external display
# Double-click this file on macOS. Asks for admin password once.
#
# BEFORE USING: Edit the UUID below to match your display.
# Get it with: /opt/homebrew/bin/displayplacer list
# Look for: "Persistent screen id: <UUID>"

UUID="REPLACE_WITH_YOUR_UUID"
PLIST="/Library/Preferences/com.apple.windowserver.displays.plist"
XML="/var/tmp/disp.xml"
FIXED="/var/tmp/disp-fixed.xml"

sudo plutil -convert xml1 -o "$XML" "$PLIST"

python3 - "$UUID" "$XML" "$FIXED" << 'PYEOF'
import sys

uuid = sys.argv[1]
xml_path = sys.argv[2]
out_path = sys.argv[3]

with open(xml_path, "r") as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if uuid in line and "<string>" in line and "</string>" in line:
        for j in range(i - 1, max(0, i - 60), -1):
            if lines[j].strip() == "<key>EOTF</key>":
                for k in range(j + 1, j + 3):
                    if "<integer>" in lines[k]:
                        lines[k] = lines[k].replace("<integer>2</integer>", "<integer>0</integer>")
                        lines[k] = lines[k].replace("<integer>1</integer>", "<integer>0</integer>")
                        break
                break
        for j in range(i - 1, max(0, i - 60), -1):
            if lines[j].strip() == "<key>BitDepth</key>":
                for k in range(j + 1, j + 3):
                    if "<integer>" in lines[k]:
                        lines[k] = lines[k].replace("<integer>10</integer>", "<integer>8</integer>")
                        break
                break
        break

with open(out_path, "w") as f:
    f.writelines(lines)
PYEOF

sudo plutil -convert binary1 -o "$PLIST" "$FIXED"
sudo killall WindowServer

osascript -e 'display notification "HDR OFF applied — logging out..." with title "DisplayFix"'

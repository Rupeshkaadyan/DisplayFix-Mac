#!/bin/bash
# HDR-On.command — Toggle HDR ON for your external display
#
# ⚠️  EDIT THE UUID BELOW BEFORE USING
# Get your display UUID with: /opt/homebrew/bin/displayplacer list
# Look for: "Persistent screen id: <UUID>"
#
# ⚠️  Double-clicking this will log you out briefly (WindowServer restart).
# Save your work first.

UUID="REPLACE_WITH_YOUR_UUID"
PLIST="/Library/Preferences/com.apple.windowserver.displays.plist"
XML="/var/tmp/disp.xml"
FIXED="/var/tmp/disp-fixed.xml"

# Convert plist to XML (sudo)
sudo plutil -convert xml1 -o "$XML" "$PLIST"

# Run Python to set EOTF=2, BitDepth=10 for the UUID
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
                        lines[k] = lines[k].replace("<integer>0</integer>", "<integer>2</integer>")
                        lines[k] = lines[k].replace("<integer>1</integer>", "<integer>2</integer>")
                        break
                break
        for j in range(i - 1, max(0, i - 60), -1):
            if lines[j].strip() == "<key>BitDepth</key>":
                for k in range(j + 1, k + 3):
                    if "<integer>" in lines[k]:
                        lines[k] = lines[k].replace("<integer>8</integer>", "<integer>10</integer>")
                        break
                break
        break

with open(out_path, "w") as f:
    f.writelines(lines)
PYEOF

# Convert back to binary and install
sudo plutil -convert binary1 -o "$PLIST" "$FIXED"

# Restart WindowServer
sudo killall WindowServer

osascript -e 'display notification "HDR ON applied — logging out..." with title "DisplayFix"'

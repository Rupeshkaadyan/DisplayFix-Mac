#!/bin/bash
# fix-refresh.sh — Set display resolution + refresh rate + HiDPI, persist to plist
#
# Usage: ./fix-refresh.sh <UUID> <WxH> <HZ>
# Example: ./fix-refresh.sh EB5A9C86-B577-8BCA-0857-D6964E3302DB 1920x1080 165
#
# This is immediate (via displayplacer) + persistent (via plist edit).
# A WindowServer restart is needed for the plist change to take full effect.

set -e

if [ $# -lt 3 ]; then
    echo "Usage: $0 <UUID> <WIDTHxHEIGHT> <HZ>"
    echo "Example: $0 EB5A9C86-B577-8BCA-0857-D6964E3302DB 1920x1080 165"
    exit 1
fi

UUID="$1"
RES="$2"
HZ="$3"
SCALE="${4:-on}"   # on = HiDPI, off = native pixel resolution

DISPLAYPLACER="/opt/homebrew/bin/displayplacer"
PLIST="/Library/Preferences/com.apple.windowserver.displays.plist"
XML="/var/tmp/disp.xml"
FIXED="/var/tmp/disp-fixed.xml"

width="${RES%x*}"
height="${RES#*x}"

echo "======================================"
echo " DisplayFix — Refresh rate + HiDPI fix"
echo "======================================"
echo "UUID:  $UUID"
echo "Res:   ${RES}"
echo "Hz:    ${HZ}"
echo "Scale: ${SCALE} (HiDPI)" 
echo ""

# Step 1: Apply immediately via displayplacer
echo "🔧 Step 1: Applying immediately via displayplacer..."
"$DISPLAYPLACER" "id:s${UUID} res:${RES} hz:${HZ} color_depth:8 scaling:${SCALE} origin:(0,0) degree:0" 2>/dev/null || \
"$DISPLAYPLACER" "id:${UUID} res:${RES} hz:${HZ} color_depth:8 scaling:${SCALE} origin:(0,0) degree:0" 2>/dev/null || \
echo "⚠️  displayplacer failed (is it installed? brew install displayplacer)"

sleep 2

# Step 2: Dump plist to XML
echo "📝 Step 2: Dumping displays plist to XML..."
sudo plutil -convert xml1 -o "$XML" "$PLIST" 2>/dev/null || {
    echo "❌ Need sudo to read the plist. Run:"
    echo "   sudo plutil -convert xml1 -o $XML $PLIST"
    exit 1
}

# Step 3: Edit plist XML — find UUID's CurrentInfo, set Hz + Scale
echo "🔍 Step 3: Editing plist for UUID ${UUID}..."

python3 - "$UUID" "$XML" "$FIXED" "$HZ" "$SCALE" << 'PYEOF'
import sys

uuid = sys.argv[1]
xml_path = sys.argv[2]
out_path = sys.argv[3]
target_hz = sys.argv[4]
target_scale = sys.argv[5]  # "on" or "off"

with open(xml_path, "r") as f:
    lines = f.readlines()

# Find first UUID occurrence and its CurrentInfo
target_hz_val = float(target_hz)
target_scale_val = 2.0 if target_scale == "on" else 1.0

found = False
for i, line in enumerate(lines):
    if uuid in line and "<string>" in line and "</string>" in line:
        # Walk backward to find CurrentInfo keys
        cur_hz = cur_scale = None
        hz_line = scale_line = None
        for j in range(i - 1, max(0, i - 80), -1):
            s = lines[j].strip()
            if s == "<key>Hz</key>":
                for k in range(j + 1, j + 3):
                    if "<real>" in lines[k]:
                        cur_hz = lines[k].strip()
                        hz_line = k
                        break
            if s == "<key>Scale</key>":
                for k in range(j + 1, j + 3):
                    if "<real>" in lines[k]:
                        cur_scale = lines[k].strip()
                        scale_line = k
                        break
            # Stop when we hit the dict boundary
            if s == "</dict>" and j < i - 5:
                break
        
        if hz_line is not None:
            old_hz = lines[hz_line]
            lines[hz_line] = f"\t\t\t\t\t\t<real>{target_hz_val}</real>\n"
            print(f"  Hz: {old_hz.strip()} → <real>{target_hz_val}</real>")
            found = True
        if scale_line is not None:
            old_scale = lines[scale_line]
            lines[scale_line] = f"\t\t\t\t\t\t<real>{target_scale_val}</real>\n"
            print(f"  Scale: {old_scale.strip()} → <real>{target_scale_val}</real>")
            found = True
        break

if not found:
    print("  ❌ UUID not found in plist. Check with: displayplacer list")
    sys.exit(1)

with open(out_path, "w") as f:
    f.writelines(lines)
print(f"  Written to: {out_path}")
PYEOF

# Step 4: Convert back to binary and install
echo ""
echo "📦 Step 4: Installing fixed plist..."
sudo plutil -convert binary1 -o "$PLIST" "$FIXED" 2>/dev/null && {
    echo "  ✅ Plist installed."
} || {
    echo "  ❌ Failed. Need sudo."
    exit 1
}

# Step 5: Done — prompt for restart
echo ""
echo "======================================"
echo " ✅ Done!"
echo "======================================"
echo ""
echo "The new settings are in the plist. For full effect, restart WindowServer:"
echo ""
echo "  sudo killall WindowServer"
echo ""
echo "This logs you out briefly. Save your work, then run it."
echo "After logging back in, verify with:"
echo "  displayplacer list"
echo ""

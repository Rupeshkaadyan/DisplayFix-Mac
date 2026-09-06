# DisplayFix-Mac

**Free, open-source fixes for external monitor problems on macOS.**

If your external display looks wrong — wrong resolution, wrong refresh rate, HDR won't turn on, HiDPI scaling broken, text blurry, colour depth wrong — this repo has the exact steps that fixed it for real hardware.

Tested on: **MacBook Pro M1 Pro → Acer VG270U X1 (IPS, 2560×1440, 170Hz panel over DisplayPort)**

## What it fixes

| Problem | What this does |
|---|---|
| Refresh rate stuck at 60Hz | Locks 165Hz (or 200Hz if your panel supports it) in the displays plist so it survives logout/restart |
| HiDPI / scaling won't stay on | Writes `scale=2` (HiDPI) into `com.apple.windowserver.displays.plist` permanently |
| HDR toggle won't sticks / greyed out | Sets `EOTF=2 + BitDepth=10` in the LinkDescription for your display UUID, converts plist to binary, restarts WindowServer |
| Colours washed out / wrong profile | Identifies the correct display UUID and suggests ColorSync profile swaps |
| Settings reset after sleep / reconnect | LaunchAgent watches the plist and re-applies on change; idle logout-login safe |

## Hardware this was built on

```
Display: Acer VG270U X1
Panel: IPS, 2560×1440 native, 170Hz advertised
Connected: DisplayPort (or HDMI — same UUID either way)
Mac: MacBook Pro M1 Pro, macOS Sequoia
```

Your display will have a **different UUID**. The scripts read it automatically from `displayplacer list`.

## Requirements

- macOS 13+ (Ventura or later — the displays plist format changed in Ventura)
- Terminal access (sudo / admin password for installing the plist and restarting WindowServer)
- Optional: [`displayplacer`](https://github.com/w0lfsburg/displayplacer) via Homebrew for verification and recovery shortcuts

```bash
brew install displayplacer
```

## Quick start (read this before running anything)

**⚠️ These commands modify system display settings. A logout / WindowServer restart is required for some steps. Save your work first.**

### 1. Identify your display UUID

```bash
/opt/homebrew/bin/displayplacer list
```

Look for a line like:

```
Persistent screen id: EB5A9C86-B577-8BCA-0857-D6964E3302DB
```

That long ID is your display's **UUID**. Everything below uses it — replace `EB5A9C86-B577-8BCA-0857-D6964E3302DB` with yours.

### 2. Check what your display supports right now

```bash
/opt/homebrew/bin/displayplacer list
```

Find your screen's section. You'll see something like:

```
Resolution: 1920x1080
Hertz: 165
Color Depth: 8
Scaling: on
```

If Hertz shows 60, or Scaling shows off, or Color Depth shows 8 when you expect 10 — this repo can help.

### 3. Fix refresh rate + HiDPI (persists across logout)

```bash
# Set the display to 1920x1080 @ 165Hz with HiDPI scaling
/opt/homebrew/bin/displayplacer \
  "id:sEB5A9C86-B577-8BCA-0857-D6964E3302DB res:1920x1080 hz:165 color_depth:8 scaling:on origin:(0,0) degree:0"
```

This is immediate but **may not persist** after logout/restart on some macOS versions. For persistence, see Section A below.

### 4. Enable HDR (if your panel supports it)

**Only do this if your monitor actually supports HDR.** The VG270U X1 is an IPS panel that accepts the HDR signal but doesn't have full HDR brightness. Your mileage will vary. If you try it and colours look worse, toggle it off in System Settings → Displays.

```bash
# Step 1: convert the displays plist to XML
PLIST="/Library/Preferences/com.apple.windowserver.displays.plist"
XML="/var/tmp/disp.xml"
sudo plutil -convert xml1 -o "$XML" "$PLIST"

# Step 2: find the LinkDescription with your UUID and set EOTF=2, BitDepth=10
# The script fix-hdr.py below does this automatically for your UUID.
python3 fix-hdr.py EB5A9C86-B577-8BCA-0857-D6964E3302DB

# Step 3: convert back to binary and install
sudo plutil -convert binary1 -o "$PLIST" /var/tmp/disp-fixed.xml

# Step 4: restart WindowServer (logs you out briefly)
sudo killall WindowServer
```

### 5. Verify after restart

Log back in, then run:

```bash
/opt/homebrew/bin/displayplacer list
```

You should see Hertz: 165 (or 200), Scaling: on, and if you enabled HDR, the System Settings → Displays → High Dynamic Range toggle should be ON and sticky.

## Repository scripts

### `fix-hdr.py`

```bash
# Usage: python3 fix-hdr.py <YOUR_DISPLAY_UUID>
python3 fix-hdr.py EB5A9C86-B577-8BCA-0857-D6964E3302DB
```

What it does:
1. Reads `/Library/Preferences/com.apple.windowserver.displays.plist` (via a temporary XML copy)
2. Finds every occurrence of your UUID
3. For the **active (first) DisplayConfig entry** containing that UUID, sets `EOTF=2` and `BitDepth=10` in the LinkDescription
4. Writes the result to `/var/tmp/disp-fixed.xml`
5. Prints the exact `sudo plutil` + `sudo killall WindowServer` commands to run

**Run it, review the output, then run the printed commands with sudo.**

### `fix-refresh.sh`

```bash
# Usage: ./fix-refresh.sh <UUID> <WIDTH>x<HEIGHT> <HZ>
./fix-refresh.sh EB5A9C86-B577-8BCA-0857-D6964E3302DB 1920x1080 165
```

What it does:
1. Calls `displayplacer` to set the resolution/Hz/scaling immediately
2. Dumps the current displays plist to XML
3. Finds the UUID's LinkDescription
4. Updates `Hz` in CurrentInfo and `Scale` for HiDPI if requested
5. Rewrites the plist as binary, prints the WindowServer restart command

### `HDR-On.command` / `HDR-Off.command` (Desktop shortcuts)

Double-click these to toggle HDR without opening System Settings. They prompt for your admin password once (via `osascript … with administrator privileges`) then apply the plist change and restart WindowServer.

**Build them yourself** (don't blindly run downloaded binaries):

```bash
cat > ~/Desktop/HDR-On.command << 'EOF'
#!/bin/bash
UUID="EB5A9C86-B577-8BCA-0857-D6964E3302DB"   # ← replace with yours
PLIST="/Library/Preferences/com.apple.windowserver.displays.plist"
XML="/var/tmp/disp.xml"
FIXED="/var/tmp/disp-fixed.xml"

sudo plutil -convert xml1 -o "$XML" "$PLIST"
python3 - "$UUID" "$XML" "$FIXED" << 'PY'
import sys
uuid, xml_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(xml_path) as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if uuid in line:
        for j in range(i-30, i+5):
            if j >= 0 and lines[j].strip() == "<key>EOTF</key>":
                # find the value line
                for k in range(j+1, j+3):
                    if "<integer>" in lines[k]:
                        lines[k] = lines[k].replace("<integer>0</integer>", "<integer>2</integer>")
                        lines[k] = lines[k].replace("<integer>1</integer>", "<integer>2</integer>")
                        break
                break
with open(out_path, "w") as f:
    f.writelines(lines)
PY
sudo plutil -convert binary1 -o "$PLIST" "$FIXED"
sudo killall WindowServer
osascript -e 'display notification "HDR ON applied — logging out…" with title "DisplayFix"'
EOF
chmod +x ~/Desktop/HDR-On.command
```

### `self-healing-launchd.sh`

```bash
# Install a LaunchAgent that re-applies 165Hz + HiDPI every 5 minutes
# and watches for plist changes (e.g. after display reconnection)
./self-healing-launchd.sh EB5A9C86-B577-8BCA-0857-D6964E3302DB 1920x1080 165
```

This creates `~/Library/LaunchAgents/com.rupeshkadyan.displayfix.plist` and loads it. The agent:
- Runs `displayplacer` to set 165Hz + scaling every 5 minutes (harmless if already correct)
- Watches the displays plist mtime and re-applies if it changes

To remove:
```bash
launchctl unload ~/Library/LaunchAgents/com.rupeshkadyan.displayfix.plist
rm ~/Library/LaunchAgents/com.rupeshkadyan.displayfix.plist
```

## How the plist hacking works (for contributors)

macOS stores display configuration in a binary plist:

```
/Library/Preferences/com.apple.windowserver.displays.plist
```

Key structure:
- `DisplaySets` → `Configs` → array of `DisplayConfig` dicts
- Each `DisplayConfig` dict has a `DisplayConfig` → `array` of per-display entries
- Each entry has `CurrentInfo` (Depth, Hz, Scale, High, Wide, OriginX/Y) and optionally `LinkDescription` (BitDepth, EOTF, PixelEncoding, Range)
- The **first** entry in the array is the active one

To enable HDR:
1. Convert plist → XML with `plutil -convert xml1`
2. Find your display UUID string in the XML
3. In the **first** DisplayConfig entry containing that UUID, find the `LinkDescription` dict
4. Set `<key>EOTF</key><integer>2</integer>` and `<key>BitDepth</key><integer>10</integer>`
5. Convert XML → binary with `plutil -convert binary1 -o <plist> <xml>`
6. Restart WindowServer: `sudo killall WindowServer`

**Important**: there may be multiple entries with the same UUID (different resolutions/modes). Only the first one is active. Editing later entries does nothing.

## AI-assisted workflow (how to use AI to fix your display)

If you want an AI agent (Open Interpreter, Claude, Gemini, a custom script) to fix your display, give it this prompt:

```
You are a macOS display expert. The user has an external monitor with problems.

GOAL: Fix the external display to use the correct resolution, refresh rate, HiDPI scaling, and HDR.

INFORMATION YOU NEED FROM THE USER:
1. The display's UUID — get it by running: /opt/homebrew/bin/displayplacer list
   Look for "Persistent screen id: <UUID>" or "Serial screen id: s<UUID>"
2. The native resolution of the monitor (e.g. 2560x1440)
3. The panel's maximum refresh rate (e.g. 170Hz, 200Hz)
4. Whether the panel actually supports HDR (check the spec sheet — not all IPS panels do)

STEPS TO PERFORM (in order):

Step 1 — Read current state:
   Run: /opt/homebrew/bin/displayplacer list
   Parse the output. Find the external display's section.
   Record: current resolution, Hertz, Color Depth, Scaling, UUID.

Step 2 — Check supported modes:
   In the displayplacer output, look at "Resolutions for rotation 0:".
   Find modes matching the native resolution. Note available Hz values.
   If the desired Hz isn't listed, the panel/mode combination isn't supported — tell the user.

Step 3 — Set refresh rate + HiDPI:
   Run displayplacer with the correct res:hz:scaling values.
   Example: displayplacer "id:s<UUID> res:1920x1080 hz:165 color_depth:8 scaling:on origin:(0,0) degree:0"
   (Use 1920x1080 with scaling:on for HiDPI on a 2560x1440 panel — macOS renders at 2x and scales down.)

Step 4 — Persist to plist (if settings reset after logout):
   a. Convert plist to XML: sudo plutil -convert xml1 -o /var/tmp/disp.xml /Library/Preferences/com.apple.windowserver.displays.plist
   b. Read /var/tmp/disp.xml
   c. Find the first DisplayConfig array entry containing the UUID
   d. In that entry's CurrentInfo: set Hz to desired value, Scale to 2 (for HiDPI)
   e. Convert back: sudo plutil -convert binary1 -o /Library/Preferences/com.apple.windowserver.displays.plist /var/tmp/disp.xml
   f. Tell the user a WindowServer restart is needed: sudo killall WindowServer
   g. WARNF the user this logs them out.

Step 5 — HDR (ONLY if panel spec confirms HDR support):
   a. In the same plist XML, find the UUID's LinkDescription in the FIRST active DisplayConfig
   b. Set EOTF to 2 (HDR) and BitDepth to 10 if available
   c. If BitDepth=10 is not in any mode for this UUID, the panel is SDR — skip HDR and tell the user
   d. Reinstall plist and restart WindowServer

Step 6 — Verify:
   After restart, run displayplacer list again. Confirm the values match intent.
   Open System Settings → Displays and confirm the refresh rate and HDR toggle show correctly.

SAFETY RULES:
- Never edit the plist without converting to XML first and back to binary after.
- Never set EOTF=2 on a display that doesn't support HDR — it can make colours look wrong.
- Always warn the user before killall WindowServer (it logs them out).
- If anything fails, restore from a backup of the plist if one exists.
- Do NOT blindly copy-paste UUIDs from this prompt — read the user's actual displayplacer output.
```

## Troubleshooting

### HDR toggle is greyed out in System Settings

Your panel might not report HDR support in its EDID. Check:
```bash
/opt/homebrew/bin/displayplacer list
```
If no mode has `color_depth:10`, the panel is SDR and macOS won't offer HDR.

### Refresh rate drops to 60Hz after sleep

Install the self-healing LaunchAgent (Section: `self-healing-launchd.sh`). It re-applies the setting every 5 minutes and on plist change.

### Settings reset entirely after restart

Make sure you installed the plist as **root** (sudo) and converted it to **binary1** format. XML plists in that location may be ignored by WindowServer.

### Colours look wrong after enabling HDR

Your panel accepts the HDR signal but may not render it well. Toggle HDR off in System Settings → Displays. The `HDR-Off.command` script does this programmatically (set EOTF back to 0).

## Contributing

Pull requests welcome. This repo is hardware-specific today (VG270U X1) but the scripts are generic — they take a UUID as input. If you test on a different monitor and the scripts work (or fail in an instructive way), open an issue or PR with:
- Monitor make/model/specs
- macOS version
- What worked / what didn't
- The `displayplacer list` output (redact any serial numbers you care about)

## License

MIT — do whatever you want. No warranty. You're editing system plists; if your display ends up in a weird state, the fix is usually `sudo killall WindowServer` (logs you out) or reverting the plist from a backup.

## Author

[Rupesh Kadyan](https://github.com/Rupeshkaadyan) — built this to fix a real VG270U X1 on an M1 Pro MacBook. Open to improvements.

#!/usr/bin/env python3
"""
fix-hdr.py — Enable HDR for a specific external display on macOS.

Usage: python3 fix-hdr.py <DISPLAY_UUID>

Example: python3 fix-hdr.py EB5A9C86-B577-8BCA-0857-D6964E3302DB

What it does:
  1. Reads /Library/Preferences/com.apple.windowserver.displays.plist
     (XML copy at /var/tmp/disp.xml — create it first with
     `sudo plutil -convert xml1 -o /var/tmp/disp.xml \
      /Library/Preferences/com.apple.windowserver.displays.plist`)
  2. Finds the FIRST active DisplayConfig entry containing the UUID
  3. In that entry's LinkDescription, sets EOTF=2 and BitDepth=10
  4. Writes the result to /var/tmp/disp-fixed.xml
  5. Prints the sudo commands to convert + install + restart WindowServer

NOTE: This only edits the XML copy. You must run the printed sudo commands
to install it into the system plist. A WindowServer restart logs you out.
Run it like:
  sudo plutil -convert xml1 -o /var/tmp/disp.xml \
    /Library/Preferences/com.apple.windowserver.displays.plist
  python3 fix-hdr.py EB5A9C86-B577-8BCA-0857-D6964E3302DB
  sudo plutil -convert binary1 -o /Library/Preferences/com.apple.windowserver.displays.plist /var/tmp/disp-fixed.xml
  sudo killall WindowServer
"""

import sys, os, re

PLIST = "/Library/Preferences/com.apple.windowserver.displays.plist"
XML = "/var/tmp/disp.xml"
FIXED = "/var/tmp/disp-fixed.xml"


def find_uuid_occurrences(xml_path, uuid):
    """Return list of (line_index, eotf_str, bitdepth_str) for each UUID occurrence."""
    with open(xml_path, "r") as f:
        lines = f.readlines()

    results = []
    for i, line in enumerate(lines):
        if uuid in line and "<string>" in line and "</string>" in line:
            # This is a UUID <string> line — look backward for EOTF and BitDepth
            eotf = None
            bitdepth = None
            for j in range(i - 1, max(0, i - 60), -1):
                s = lines[j].strip()
                if s == "<key>EOTF</key>":
                    # next non-empty line should be the value
                    for k in range(j + 1, j + 3):
                        if "<integer>" in lines[k]:
                            eotf = lines[k].strip()
                            break
                    break
            for j in range(i - 1, max(0, i - 60), -1):
                s = lines[j].strip()
                if s == "<key>BitDepth</key>":
                    for k in range(j + 1, j + 3):
                        if "<integer>" in lines[k]:
                            bitdepth = lines[k].strip()
                            break
                    break
            results.append((i, eotf, bitdepth))
    return results


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fix-hdr.py <DISPLAY_UUID>")
        print("Example: python3 fix-hdr.py EB5A9C86-B577-8BCA-0857-D6964E3302DB")
        sys.exit(1)

    uuid = sys.argv[1]
    print(f"📋 Display UUID: {uuid}")
    print(f"📁 Plist: {PLIST}")
    print()

    # Check XML exists
    if not os.path.exists(XML):
        print("❌ XML dump not found.")
        print("   Run first:")
        print(f"   sudo plutil -convert xml1 -o {XML} {PLIST}")
        sys.exit(1)

    occurrences = find_uuid_occurrences(XML, uuid)
    print(f"🔍 Found {len(occurrences)} occurrence(s) of UUID in plist:")
    for idx, (ln, eotf, bd) in enumerate(occurrences):
        print(f"   #{idx+1}: line {ln+1}  EOTF={eotf}  BitDepth={bd}")
    print()

    if not occurrences:
        print("❌ UUID not found in plist. Check the UUID with: displayplacer list")
        sys.exit(1)

    # Find the FIRST occurrence — that's the active DisplayConfig
    first_ln, first_eotf, first_bd = occurrences[0]

    # Check if already HDR (EOTF=2)
    if first_eotf and "<integer>2</integer>" in first_eotf:
        print("✅ HDR already enabled (EOTF=2) in the active config.")
        print("   Nothing to do. Verify in System Settings → Displays.")
        sys.exit(0)

    # Read XML and modify
    with open(XML, "r") as f:
        lines = f.readlines()

    # Find the EOTF integer line for the first occurrence
    eotf_changed = False
    bd_changed = False

    for j in range(first_ln - 1, max(0, first_ln - 60), -1):
        s = lines[j].strip()
        if s == "<key>EOTF</key>":
            for k in range(j + 1, j + 3):
                if "<integer>" in lines[k]:
                    old = lines[k]
                    lines[k] = lines[k].replace("<integer>0</integer>", "<integer>2</integer>")
                    lines[k] = lines[k].replace("<integer>1</integer>", "<integer>2</integer>")
                    if lines[k] != old:
                        print(f"✅ EOTF changed at line {k+1}: {old.strip()} → {lines[k].strip()}")
                        eotf_changed = True
                    break
            break

    for j in range(first_ln - 1, max(0, first_ln - 60), -1):
        s = lines[j].strip()
        if s == "<key>BitDepth</key>":
            for k in range(j + 1, j + 3):
                if "<integer>" in lines[k]:
                    old = lines[k]
                    lines[k] = lines[k].replace("<integer>8</integer>", "<integer>10</integer>")
                    if lines[k] != old:
                        print(f"✅ BitDepth changed at line {k+1}: {old.strip()} → {lines[k].strip()}")
                        bd_changed = True
                    break
            break

    if not eotf_changed and not bd_changed:
        print("⚠️  No changes made — EOTF may already be 2, or the structure is unexpected.")
        print("   Review manually:")
        print(f"   grep -n 'EOTF\|BitDepth' {XML} | head -20")
        sys.exit(1)

    # Write fixed XML
    with open(FIXED, "w") as f:
        f.writelines(lines)
    print(f"\n📝 Fixed XML written to: {FIXED}")

    # Print installation commands
    print("\n" + "=" * 60)
    print("NEXT: Run these commands to install and apply (requires sudo):")
    print("=" * 60)
    print(f"# 1. Convert back to binary and install:")
    print(f"sudo plutil -convert binary1 -o {PLIST} {FIXED}")
    print()
    print(f"# 2. Restart WindowServer (logs you out — save work first):")
    print(f"sudo killall WindowServer")
    print()
    print("# 3. After logging back in, verify:")
    print(f"/opt/homebrew/bin/displayplacer list")
    print()
    print("# 4. Check HDR toggle in System Settings → Displays")
    print("=" * 60)


if __name__ == "__main__":
    main()

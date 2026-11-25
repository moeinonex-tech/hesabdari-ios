#!/usr/bin/env python3
"""Checks App/PrivacyInfo.xcprivacy against the app's own Swift code (audit stage 2).

Fails when the code uses an API from Apple's "required reason" list whose category the manifest does not declare
(with an approved reason), or when the manifest declares tracking / collected data although the app has no network
code. Run in CI; no arguments. Exit code 0 = OK.
"""
import plistlib, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "App" / "PrivacyInfo.xcprivacy"
SOURCES = [ROOT / "App" / "Sources", ROOT / "HesabCore" / "Sources"]

# Apple's required-reason API categories → code patterns that use them, and the reasons valid for this app
CATEGORIES = {
    "NSPrivacyAccessedAPICategoryUserDefaults": (
        [r"\bUserDefaults\b", r"@AppStorage\b", r"@SceneStorage\b"], {"CA92.1"}),
    "NSPrivacyAccessedAPICategoryFileTimestamp": (
        [r"creationDate", r"modificationDate", r"contentModificationDate", r"contentAccessDate",
         r"\bgetattrlist\b", r"\bfstat\b", r"\blstat\b", r"\bstat\(", r"fileModificationDate"], {"C617.1", "3B52.1", "0A2A.1", "DDA9.1"}),
    "NSPrivacyAccessedAPICategorySystemBootTime": (
        [r"systemUptime", r"mach_absolute_time"], {"35F9.1", "8FFB.1", "3D61.1"}),
    "NSPrivacyAccessedAPICategoryDiskSpace": (
        [r"volumeAvailableCapacity", r"volumeTotalCapacity", r"systemFreeSize", r"systemSize", r"\bstatfs\b", r"\bstatvfs\b"],
        {"85F4.1", "E174.1", "7D9E.1", "B728.1"}),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": (
        [r"activeInputModes"], {"3EC4.1", "54BD.1"}),
}
NETWORK = [r"\bURLSession\b", r"\bNWConnection\b", r"https?://[^\s\"]+\.(?!apple\.com)"]


def code():
    for d in SOURCES:
        for f in d.rglob("*.swift"):
            text = f.read_text(encoding="utf-8")
            # comments do not count
            text = re.sub(r"//.*", "", text)
            yield f, text


def main():
    errors = []
    m = plistlib.loads(MANIFEST.read_bytes())
    declared = {d["NSPrivacyAccessedAPIType"]: set(d.get("NSPrivacyAccessedAPITypeReasons", []))
                for d in m.get("NSPrivacyAccessedAPITypes", [])}
    sources = list(code())
    used = {}
    for cat, (patterns, valid) in CATEGORIES.items():
        for f, text in sources:
            for p in patterns:
                if re.search(p, text):
                    used.setdefault(cat, set()).add(f"{f.relative_to(ROOT)} ({p})")
    for cat, where in sorted(used.items()):
        reasons = declared.get(cat)
        valid = CATEGORIES[cat][1]
        if not reasons:
            errors.append(f"{cat} used but not declared: " + ", ".join(sorted(where)[:5]))
        elif not reasons & valid:
            errors.append(f"{cat}: reasons {sorted(reasons)} are not valid ones {sorted(valid)}")
        else:
            print(f"ok   {cat} {sorted(reasons)} — used in {len(where)} place(s)")
    for cat in declared:
        if cat not in used:
            print(f"note {cat} declared but no use found in the app's own code (harmless)")
    has_network = any(re.search(p, t) for _, t in sources for p in NETWORK)
    if not has_network:
        if m.get("NSPrivacyTracking") is not False:
            errors.append("NSPrivacyTracking must be false (no network code)")
        if m.get("NSPrivacyTrackingDomains"):
            errors.append("tracking domains declared but there is no network code")
    print("network code found" if has_network else "ok   no network code: tracking false, no tracking domains")
    for e in errors:
        print("ERROR " + e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

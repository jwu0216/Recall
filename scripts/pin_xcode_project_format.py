#!/usr/bin/env python3
"""Force generated Recall.xcodeproj into an Xcode 15-compatible format for CI."""

from pathlib import Path
import re

pbx = Path("Recall.xcodeproj/project.pbxproj")
if not pbx.exists():
    raise SystemExit(f"missing {pbx}")

text = pbx.read_text()
text = re.sub(r"objectVersion = \d+;", "objectVersion = 56;", text)
text = re.sub(r"\tpreferredProjectObjectVersion = \d+;\n", "", text)
text = re.sub(r"\tminimizedProjectReferenceProxies = \d+;\n", "", text)
# Xcode 16 file-system synchronized groups break older xcodebuild.
text = text.replace("PBXFileSystemSynchronizedRootGroup", "PBXGroup")
pbx.write_text(text)
print(f"Pinned {pbx} to objectVersion 56")

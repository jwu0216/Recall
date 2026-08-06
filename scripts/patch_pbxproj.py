#!/usr/bin/env python3
from pathlib import Path
import re
import uuid

pbx_path = Path(__file__).resolve().parents[1] / "Recall.xcodeproj" / "project.pbxproj"
text = pbx_path.read_text()


def nid() -> str:
    return uuid.uuid4().hex[:24].upper()


ids = {
    "shared": nid(),
    "project": nid(),
    "recall": nid(),
    "core": nid(),
    "share": nid(),
    "tests": nid(),
    "group": nid(),
}

if "Configs/Recall.xcconfig" not in text and "path = Recall.xcconfig;" not in text:
    file_refs = f"""
\t\t{ids['shared']} /* Shared.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Shared.xcconfig; sourceTree = "<group>"; }};
\t\t{ids['project']} /* Project.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Project.xcconfig; sourceTree = "<group>"; }};
\t\t{ids['recall']} /* Recall.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Recall.xcconfig; sourceTree = "<group>"; }};
\t\t{ids['core']} /* RecallCore.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RecallCore.xcconfig; sourceTree = "<group>"; }};
\t\t{ids['share']} /* RecallShare.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RecallShare.xcconfig; sourceTree = "<group>"; }};
\t\t{ids['tests']} /* RecallCoreTests.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = RecallCoreTests.xcconfig; sourceTree = "<group>"; }};
"""
    text = text.replace(
        "/* End PBXFileReference section */",
        file_refs + "/* End PBXFileReference section */",
    )

    group = f"""
\t\t{ids['group']} /* Configs */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids['project']} /* Project.xcconfig */,
\t\t\t\t{ids['recall']} /* Recall.xcconfig */,
\t\t\t\t{ids['core']} /* RecallCore.xcconfig */,
\t\t\t\t{ids['share']} /* RecallShare.xcconfig */,
\t\t\t\t{ids['tests']} /* RecallCoreTests.xcconfig */,
\t\t\t\t{ids['shared']} /* Shared.xcconfig */,
\t\t\t);
\t\t\tpath = Configs;
\t\t\tsourceTree = "<group>";
\t\t}};
"""
    text = text.replace("/* End PBXGroup section */", group + "/* End PBXGroup section */")

    text = text.replace(
        """children = (
\t\t\t\t2398648CEC1DEFD2236E8232 /* Recall */,
\t\t\t\t544AF24C7DE962745FC914D3 /* RecallCore */,
\t\t\t\t221A223A1F3BBE8A591D6B05 /* RecallCoreTests */,
\t\t\t\t7A14FE894E95C0E9B8EB404E /* RecallShare */,
\t\t\t\t8FB9A9AFFDDAA5852104C602 /* Products */,
\t\t\t);""",
        f"""children = (
\t\t\t\t{ids['group']} /* Configs */,
\t\t\t\t2398648CEC1DEFD2236E8232 /* Recall */,
\t\t\t\t544AF24C7DE962745FC914D3 /* RecallCore */,
\t\t\t\t221A223A1F3BBE8A591D6B05 /* RecallCoreTests */,
\t\t\t\t7A14FE894E95C0E9B8EB404E /* RecallShare */,
\t\t\t\t8FB9A9AFFDDAA5852104C602 /* Products */,
\t\t\t);""",
    )
else:
    def find_id(name: str) -> str:
        m = re.search(
            rf"([A-F0-9]{{24}}) /\* {re.escape(name)} \*/ = \{{isa = PBXFileReference",
            text,
        )
        if not m:
            raise SystemExit(f"missing file ref {name}")
        return m.group(1)

    ids = {
        "shared": find_id("Shared.xcconfig"),
        "project": find_id("Project.xcconfig"),
        "recall": find_id("Recall.xcconfig"),
        "core": find_id("RecallCore.xcconfig"),
        "share": find_id("RecallShare.xcconfig"),
        "tests": find_id("RecallCoreTests.xcconfig"),
    }
    print("reusing existing xcconfig file refs")

config_map = {
    "14A2FF4FAB6AA7B63D7C173A": ids["share"],
    "4D25730C015F1A743FB6FAF9": ids["core"],
    "5C05BE411EE81AC9652F9F93": ids["project"],
    "6581C2D0C73D87341BEA84E5": ids["project"],
    "94BB1C6CF7C50C96698E0FB5": ids["core"],
    "9A7FD3BCDC4F7B5C1F3EC630": ids["tests"],
    "C662AE1D0F1A4F255C15C87C": ids["tests"],
    "E84E3AC8F2FFBF0E1D7B375A": ids["recall"],
    "FA227451634E2DF640B6D054": ids["share"],
    "FE110EA30F10498B7CD36934": ids["recall"],
}

for cfg_id, conf_ref in config_map.items():
    marker = f"{cfg_id} /*"
    idx = text.find(marker)
    if idx < 0:
        raise SystemExit(f"missing config {cfg_id}")
    chunk = text[idx : idx + 400]
    if "baseConfigurationReference" in chunk.split("buildSettings")[0]:
        print(f"already has baseConfiguration for {cfg_id}")
        continue
    needle = "isa = XCBuildConfiguration;\n\t\t\tbuildSettings = {"
    pos = text.find(needle, idx)
    if pos < 0 or pos > idx + 200:
        raise SystemExit(f"failed to locate buildSettings for {cfg_id}")
    insertion = (
        "isa = XCBuildConfiguration;\n"
        f"\t\t\tbaseConfigurationReference = {conf_ref} /* xcconfig */;\n"
        "\t\t\tbuildSettings = {"
    )
    text = text[:pos] + insertion + text[pos + len(needle) :]

extras_by_bundle = {
    "com.jwu0216.recall.share": {
        "WRAPPER_NAME": "RecallShare.appex",
        "EXECUTABLE_NAME": "RecallShare",
        "PRODUCT_MODULE_NAME": "RecallShare",
        "PRODUCT_NAME": "RecallShare",
    },
    "com.jwu0216.recall.core": {
        "WRAPPER_NAME": "RecallCore.framework",
        "EXECUTABLE_NAME": "RecallCore",
        "PRODUCT_MODULE_NAME": "RecallCore",
        "PRODUCT_NAME": "RecallCore",
        "DEFINES_MODULE": "YES",
        "SKIP_INSTALL": "YES",
    },
    "com.jwu0216.recall.core.tests": {
        "WRAPPER_NAME": "RecallCoreTests.xctest",
        "EXECUTABLE_NAME": "RecallCoreTests",
        "PRODUCT_MODULE_NAME": "RecallCoreTests",
        "PRODUCT_NAME": "RecallCoreTests",
    },
    "com.jwu0216.recall": {
        "WRAPPER_NAME": "Recall.app",
        "EXECUTABLE_NAME": "Recall",
        "PRODUCT_MODULE_NAME": "Recall",
        "PRODUCT_NAME": "Recall",
    },
}


def inject_settings(block: str, settings: dict) -> str:
    for key, value in settings.items():
        if f"{key} = " in block:
            block = re.sub(rf"{key} = [^;]+;", f"{key} = {value};", block)
        else:
            block = block.replace(
                "buildSettings = {\n",
                f"buildSettings = {{\n\t\t\t\t{key} = {value};\n",
                1,
            )
    return block


head, sep, rest = text.partition("/* Begin XCBuildConfiguration section */\n")
body, sep2, tail = rest.partition("/* End XCBuildConfiguration section */")
objs = re.split(r"(?=\t\t[A-F0-9]{24} /\* (?:Debug|Release) \*/ = \{)", body)
new_objs = [objs[0]]
for obj in objs[1:]:
    matched = False
    for bundle, settings in extras_by_bundle.items():
        if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};" in obj:
            obj = inject_settings(obj, settings)
            matched = True
            break
    if not matched and "SDKROOT = iphoneos;" in obj:
        obj = inject_settings(
            obj,
            {
                "PRODUCT_NAME": '"$(TARGET_NAME)"',
                "ALWAYS_SEARCH_USER_PATHS": "NO",
            },
        )
    new_objs.append(obj)

text = head + sep + "".join(new_objs) + sep2 + tail

text = text.replace("objectVersion = 77;", "objectVersion = 56;")
text = text.replace("\n\t\t\tpreferredProjectObjectVersion = 77;", "")
text = text.replace("\n\t\t\tminimizedProjectReferenceProxies = 1;", "")

for prod in [
    "Recall.app",
    "RecallCore.framework",
    "RecallShare.appex",
    "RecallCoreTests.xctest",
]:
    text = text.replace(
        f"path = {prod}; sourceTree = BUILT_PRODUCTS_DIR;",
        f"name = {prod}; path = {prod}; sourceTree = BUILT_PRODUCTS_DIR;",
    )

pbx_path.write_text(text)
print("patched", pbx_path)
print("objectVersion", re.search(r"objectVersion = (\d+);", text).group(1))
print("WRAPPER_NAME count", text.count("WRAPPER_NAME"))
print("baseConfigurationReference count", text.count("baseConfigurationReference"))

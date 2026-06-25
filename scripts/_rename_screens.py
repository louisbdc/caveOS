#!/usr/bin/env python3
"""Copie et renomme les captures exportées d'un .xcresult vers un dossier propre.

Usage: _rename_screens.py <dossier_brut_avec_manifest.json> <dossier_destination>

Le manifest.json (xcresulttool export attachments) liste, par test, des
attachments avec un nom de fichier exporté et un nom lisible (celui passé à
XCTAttachment.name). On mappe l'un vers l'autre, en ne gardant que les PNG.
"""
import json
import os
import re
import shutil
import sys

# XCTest suffixe le nom de l'attachment par "_<index>_<UUID>" : on le retire.
_SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?:\.png)?$")


def field(att, *names):
    for n in names:
        if att.get(n):
            return att[n]
    return None


def clean_label(label):
    label = _SUFFIX.sub("", label)
    return label[:-4] if label.lower().endswith(".png") else label


def main():
    raw, dest = sys.argv[1], sys.argv[2]
    with open(os.path.join(raw, "manifest.json"), encoding="utf-8") as fh:
        manifest = json.load(fh)

    os.makedirs(dest, exist_ok=True)
    count = 0
    # Le manifest peut être une liste d'entrées de test, chacune avec "attachments".
    entries = manifest if isinstance(manifest, list) else manifest.get("attachments", [manifest])
    for entry in entries:
        attachments = entry.get("attachments", [entry]) if isinstance(entry, dict) else []
        for att in attachments:
            src = field(att, "exportedFileName", "fileName", "name")
            raw_label = field(att, "suggestedHumanReadableName", "name") or src
            if not src:
                continue
            src_path = os.path.join(raw, src)
            if not os.path.isfile(src_path) or not src.lower().endswith(".png"):
                continue
            base = f"{clean_label(raw_label)}.png"
            shutil.copyfile(src_path, os.path.join(dest, base))
            count += 1

    print(f"{count} captures -> {dest}")


if __name__ == "__main__":
    main()

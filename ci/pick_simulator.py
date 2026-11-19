import json
import sys

prefer_max = "--promax" in sys.argv
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.rsplit("iOS-", 1)[-1].split("-") if part.isdigit())
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append(((version, prefer_max and "Pro Max" in device["name"]), device))
if not candidates:
    sys.exit("No available iPhone simulator")
selected = max(candidates, key=lambda item: item[0])[1]
print(selected["udid"])
print("Selected:", selected["name"], file=sys.stderr)

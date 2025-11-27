#!/usr/bin/env python3
"""
Download and verify the latest Firmware.zip artifact from GitHub Actions
for the WWCS project: https://github.com/WeatherWaterClimateServices/wwcs

Verification steps:
- ZIP contains metadata.json
- metadata.json has a 'gitversion' field (8-char hex string)
- At least one file exists under a 'Firmware*' directory
"""

import argparse
import json
import re
import sys
import tempfile
import zipfile
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen


URL = "https://api.github.com/repos/WeatherWaterClimateServices/wwcs"
WORKFLOW_FILE = "build-firmware-zip.yml"

def fetch_json(url: str) -> dict:
    with urlopen(url) as resp:
        return json.load(resp)

def download_and_verify_firmware(output_path: str = "Firmware.zip") -> None:
    print("🔍 Fetching latest successful workflow run...")

    try:
        runs = fetch_json(f"{URL}/actions/workflows/{WORKFLOW_FILE}/runs?status=success&per_page=1")
    except URLError as e:
        print(f"❌ Failed to fetch workflow runs: {e}", file=sys.stderr)
        sys.exit(1)

    if not runs.get("workflow_runs"):
        print("❌ No successful workflow runs found.", file=sys.stderr)
        sys.exit(1)

    run_id = runs["workflow_runs"][0]["id"]
    print(f"✅ Found run {run_id}")

    try:
        artifacts = fetch_json(f"{URL}/actions/runs/{run_id}/artifacts")
    except URLError as e:
        print(f"❌ Failed to fetch artifacts: {e}", file=sys.stderr)
        sys.exit(1)

    artifact = next((a for a in artifacts.get("artifacts", []) if a["name"] == "Firmware.zip"), None)
    if not artifact:
        print("❌ Firmware.zip artifact not found.", file=sys.stderr)
        sys.exit(1)

    print("⬇️ Downloading Firmware.zip...")
    download_url = artifact["archive_download_url"]
    try:
        with urlopen(download_url) as resp:
            blob = resp.read()
    except URLError as e:
        print(f"❌ Download failed: {e}", file=sys.stderr)
        sys.exit(1)

    # Write ZIP to disk
    zip_path = Path(output_path)
    zip_path.write_bytes(blob)
    print(f"💾 Saved to {zip_path}")

    # === Verification ===
    print("🔍 Verifying contents...")

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(tmp)

        # 1. Check metadata.json exists
        metadata_file = tmp / "metadata.json"
        if not metadata_file.exists():
            print("❌ Verification failed: metadata.json not found in ZIP", file=sys.stderr)
            sys.exit(1)

        # 2. Load and validate metadata
        try:
            metadata = json.loads(metadata_file.read_text())
            gitversion = metadata.get("gitversion")
        except (json.JSONDecodeError, OSError) as e:
            print(f"❌ Failed to read metadata.json: {e}", file=sys.stderr)
            sys.exit(1)

        if not isinstance(gitversion, str) or not re.fullmatch(r"[a-f0-9]{8}", gitversion):
            print(f"❌ Invalid gitversion in metadata.json: {gitversion!r}", file=sys.stderr)
            sys.exit(1)

        print(f"🔖 Git version: {gitversion}")

        # 3. Check at least one Firmware* file exists
        firmware_files = list(tmp.glob("Firmware*/**/*"))
        firmware_files = [f for f in firmware_files if f.is_file()]

        if not firmware_files:
            print("❌ Verification failed: no files found under Firmware*/", file=sys.stderr)
            sys.exit(1)

        print(f"📦 Found {len(firmware_files)} firmware file(s) under Firmware*/")

    print("✅ Verification passed!")
    print(f"✅ Firmware.zip is ready at {zip_path}")

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download and verify latest Firmware.zip from GitHub Actions (WWCS project)"
    )
    parser.add_argument(
        "-o", "--output",
        default="Firmware.zip",
        help="Output ZIP file path (default: Firmware.zip)"
    )
    args = parser.parse_args()
    download_and_verify_firmware(args.output)

if __name__ == "__main__":
    main()

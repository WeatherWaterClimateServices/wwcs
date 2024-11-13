"""
Create a Zip file with the firmware data, save it to /var/www/html/downloads/Ij6iez6u
It will as well contain a metadata.json file.

If the file exists and there's nothing new, then it won't be updated, unless the
--force option is passed.

Flashgordon will download it from https://wwcs.tj/downloads/Ij6iez6u/Firmware.zip

In the server this command should be called by cron, with a line like:

    git -C <path> pull -q && python3 <path>/Station/zip_firmware.py

In a local development environment the Zip file will be saved to /tmp/Firmware.zip
"""

import json
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile


if __name__ == '__main__':
    force = len(sys.argv) == 2 and sys.argv[1] == '--force'

    # Build the metadata
    root = Path(__file__).parent
    output = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root)
    gitversion = output.decode()[:8]
    metadata = {'gitversion': gitversion}
    metadata = json.dumps(metadata)

    # The output directory
    output_dir = Path('/var/www/html/downloads/Ij6iez6u')
    if not output_dir.exists():
        output_dir = Path('/tmp')

    # Get the mtime of the zip file, if it exists.
    zip_path = output_dir / 'Firmware.zip'
    mtime = zip_path.stat().st_mtime if zip_path.exists() else None

    # Collect source files, and their modification times
    sources = []
    mtimes = []
    for path in root.glob('**/*'):
        relpath = path.relative_to(root)
        parts = relpath.parts
        if len(parts) > 1 and parts[0].startswith('Firmware'):
            sources.append(relpath)
            mtimes.append(path.stat().st_mtime)

    # Create the zip file, if needed
    if force or mtime is None or max(mtimes) > mtime:
        with ZipFile(zip_path, 'w') as zip_file:
            for relpath in sources:
                zip_file.write(root / relpath, relpath)
            zip_file.writestr('metadata.json', metadata)

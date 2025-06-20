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

import argparse
import json
import pathlib
import subprocess
import zipfile


def zip_firmware():
    parser = argparse.ArgumentParser()
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()

    # Build the metadata
    root = pathlib.Path(__file__).parent
    output = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root)
    gitversion = output.decode()[:8]
    metadata = {'gitversion': gitversion}
    metadata = json.dumps(metadata)

    # The output directory
    output_dir = '/var/www/html/downloads/Ij6iez6u'
    output_dir = pathlib.Path(output_dir)
    if not output_dir.exists():
        output_dir = pathlib.Path('/tmp')

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
    if args.force or mtime is None or max(mtimes) > mtime:
        with zipfile.ZipFile(zip_path, 'w') as zip_file:
            for relpath in sources:
                zip_file.write(root / relpath, relpath)
            zip_file.writestr('metadata.json', metadata)


if __name__ == '__main__':
    zip_firmware()

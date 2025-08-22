import os
import pathlib

import dotenv


def get_rootdir():
    """
    Returns the absolute path to the project's root directory (or working directory in
    Git's parlance).
    """
    current_dir = pathlib.Path(__file__).parent.resolve()
    while current_dir != current_dir.parent:
        env_path = current_dir / '.git'
        if env_path.exists():
            return current_dir

        current_dir = current_dir.parent


# Load the .env file, in production this must be /home/wwcs/wwcs/WWCS/.env
# Or more generally {ROOT-DIRECTORY}/WWCS/.env (in local development the root directory
# may be somewhere else than /home/wwcs/wwcs)
ROOT_DIR = get_rootdir()
dotenv.load_dotenv(ROOT_DIR / 'WWCS' / '.env')


USERNAME = os.environ.get('DB_USERNAME')
PASSWORD = os.environ.get('DB_PASSWORD')

# For backwards compatibility, to be removed once all .env files have been updated
if USERNAME is None:
    USERNAME = os.environ.get('USERNAME')

if PASSWORD is None:
    PASSWORD = os.environ.get('PASSWORD')

# Defaults
if USERNAME is None:
    USERNAME = 'wwcs'

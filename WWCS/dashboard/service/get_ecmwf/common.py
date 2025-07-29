import os
import pathlib

import dotenv


def load_dotenv():
    """
    Find and load .env file, starting from the directory where this script is located.
    """
    current_dir = pathlib.Path(__file__).parent.resolve()
    while current_dir != current_dir.parent:
        env_path = current_dir / '.env'
        if env_path.exists():
            dotenv.load_dotenv(env_path)
            break

        current_dir = current_dir.parent


load_dotenv()
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

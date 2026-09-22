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


# Load the .env file, in production this must be /home/wwcs/wwcs/.env
# Or more generally {ROOT-DIRECTORY}/.env (in local development the root directory
# may be somewhere else than /home/wwcs/wwcs)
ROOT_DIR = get_rootdir()
dotenv.load_dotenv(ROOT_DIR / '.env')


USERNAME = os.environ.get('DB_USERNAME', 'wwcs')
PASSWORD = os.environ.get('DB_PASSWORD')

# Environment switch: mirrors the R side (ENV=="PROD" -> WWCServices, otherwise WWCServices_DEV)
ENV = os.environ.get('ENV')
SERVICES_SCHEMA = 'WWCServices' if ENV == 'PROD' else 'WWCServices_DEV'

# Database connection settings
DATABASE_URL_MACHINES = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/Machines'
DATABASE_URL_SERVICES = f'mysql+asyncmy://{USERNAME}:{PASSWORD}@localhost:3306/{SERVICES_SCHEMA}'

The project uses these databases:

- BeneficiarySupport
- Humans
- Machines
- SitesHumans
- WWCServices

The initial SQL migration `0000_init.sql` was created in the production server with the
following command:

    mysqldump -u root -p --no-data --skip-add-drop-table --databases BeneficiarySupport Humans Machines SitesHumans WWCServices > 0000_init.sql

Then this file can be used to create the databases this way:

    mysql -u root -p < 0000_init.sql

Notes:

- The initial migration should be created only once. Further changes to the database
  should be expressed with consecutive migrations: `0001_xxx.sql` etc.
- The databases will be empty, there is no data in the migration files.
- The migration does not have DROP statements, so if a database already exists it will
  fail. Here we give priority to safety over convenience.

To make things easier there is a shell script called createdb.sh:

    # Print a help screen
    createdb.sh --help

    # Create a new empty database (applies migration files), useful for new deployments
    createdb.sh

    # As above, but first drop the databases, use carefully!
    createdb.sh --drop-databases

    # Instead of creating empty databases, restore dumps. Useful in development environments
    createdb.sh --drop-databases --restore-dumps /backups

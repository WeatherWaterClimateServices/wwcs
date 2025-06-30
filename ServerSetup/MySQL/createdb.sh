#!/bin/bash

# Databases to manage (for drop/restore)
DATABASES=(
    "BeneficiarySupport"
    "Humans"
    "Machines"
    "SitesHumans"
    "WWCServices"
)

# Print help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Manage MySQL databases: apply migrations or restore dumps."
    echo ""
    echo "Options:"
    echo "  --drop-databases      Drop all databases (after confirmation)"
    echo "  --restore-dumps DIR   Restore databases from gzipped SQL dumps in DIR"
    echo "  --database DB_NAME    Work on a specific database only (default: all)"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     # Apply all SQL migrations (0000_*.sql, etc)"
    echo "  $0 --drop-databases    # Drop databases, then apply migrations"
    echo "  $0 --restore-dumps /backups # Restore databases from dump files"
    echo "  $0 --database Machines --drop-databases --restore-dumps /backups # Drop then restore only Machines"
    exit 0
}

# Check if MySQL is available
if ! command -v mysql &> /dev/null; then
    echo "Error: mysql command not found. Please ensure MySQL is installed."
    exit 1
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help
            ;;
        --drop-databases)
            DROP_DATABASES=1
            shift
            ;;
        --restore-dumps)
            if [ -z "$2" ]; then
                echo "Error: --restore-dumps requires a directory path."
                exit 1
            fi
            RESTORE_DUMPS=1
            DUMP_DIR="$2"
            shift 2
            ;;
        --database)
            if [ -z "$2" ]; then
                echo "Error: --database requires a database name."
                exit 1
            fi
            SELECTED_DB="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option '$1'"
            show_help
            exit 1
            ;;
    esac
done

# Validate selected database
if [ -n "$SELECTED_DB" ]; then
    found=0
    for db in "${DATABASES[@]}"; do
        if [ "$db" = "$SELECTED_DB" ]; then
            found=1
            break
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "Error: Database '$SELECTED_DB' is not in the managed databases list."
        exit 1
    fi

    # Work with only the selected database
    DATABASES=("$SELECTED_DB")
fi

# Prompt for MySQL password
read -s -p "Enter MySQL root password: " password
echo

# Handle --drop-databases
if [ -n "$DROP_DATABASES" ]; then
    echo "WARNING: This will DROP the following databases:"
    for db in "${DATABASES[@]}"; do
        echo "  - $db"
    done
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Aborted. No databases were dropped."
        exit 0
    fi

    echo "Dropping databases..."
    for db in "${DATABASES[@]}"; do
        echo "Dropping $db..."
        mysql -u root -p"$password" -e "DROP DATABASE IF EXISTS \`$db\`;"
        if [ $? -ne 0 ]; then
            echo "Error dropping $db. Continuing anyway..."
        fi
    done
    echo "Databases dropped (if they existed)."
fi

# Handle --restore-dumps
if [ -n "$RESTORE_DUMPS" ]; then
    if [ ! -d "$DUMP_DIR" ]; then
        echo "Error: Directory '$DUMP_DIR' not found."
        exit 1
    fi

    echo "Creating empty databases..."
    for db in "${DATABASES[@]}"; do
        echo "Creating $db..."
        mysql -u root -p"$password" -e "CREATE DATABASE IF NOT EXISTS \`$db\`;"
        if [ $? -ne 0 ]; then
            echo "Error creating $db. Aborting."
            exit 1
        fi
    done

    echo "Restoring database dumps from $DUMP_DIR..."
    for db in "${DATABASES[@]}"; do
        DUMP_FILE=$(ls "$DUMP_DIR"/${db}_*.sql.gz 2>/dev/null | head -n 1)
        if [ -z "$DUMP_FILE" ]; then
            echo "Warning: No dump file found for $db. Skipping..."
            continue
        fi

        echo "Restoring $db from $(basename "$DUMP_FILE")..."
        gunzip -c "$DUMP_FILE" | mysql -u root -p"$password" "$db"
        if [ $? -ne 0 ]; then
            echo "Error restoring $db. Aborting."
            exit 1
        fi
    done
    echo "All dumps restored successfully."
    exit 0
fi

# Default: Apply SQL migrations
echo "Applying SQL scripts..."
for sql_file in $(ls *.sql | sort -n); do
    echo "Applying $sql_file..."
    mysql -u root -p"$password" < "$sql_file"
    if [ $? -ne 0 ]; then
        echo "Error applying $sql_file. Aborting."
        exit 1
    fi
done

echo "All operations completed successfully."

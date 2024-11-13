#!/bin/bash

set -x # Print every command and variable

# Set the name of the virtual machine to be backed up
VMNAME="WWCSVM"

# Set the path to the backup folder
BACKUPDIR="/home/omar/VM"

# Set the date format to use in the backup filename
DATEFORMAT="%Y-%m-%d"

# Set the number of days to keep backup files
DAYS_TO_KEEP=30

# Create the backup filename using the current date
BACKUPFILE="$BACKUPDIR/$VMNAME-$(date +$DATEFORMAT).ova"


# Stop the virtual machine
set -e # Fail fast
VBoxManage controlvm "$VMNAME" acpipowerbutton
set +e # Ignore errors

# Wait for the VM to stop
while [ $(VBoxManage showvminfo "$VMNAME" | grep -c "running (since") -ne 0 ]
do
  sleep 1
done

# Export the virtual machine to the backup file
VBoxManage export "$VMNAME" --output "$BACKUPFILE"

# Start the virtual machine
VBoxManage startvm "$VMNAME" --type headless

# Use the find command to delete backup files that are older than one month
find "$BACKUPDIR" -name "$VMNAME-*.ova" -type f -mtime +$DAYS_TO_KEEP -exec rm {} \;

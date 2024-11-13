#!/bin/bash

set -x # Print every command and variable

set -e # Fail fast
mount /mnt/backup/
set +e # Ignore errors

rsync -av --delete /home/omar/VM/ /mnt/backup/VM/
umount /mnt/backup/

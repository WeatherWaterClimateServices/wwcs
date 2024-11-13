#/bin/bash
gv=$(git rev-parse --short HEAD)
echo "#define GIT_VERSION" \"$gv\" > git_version.h


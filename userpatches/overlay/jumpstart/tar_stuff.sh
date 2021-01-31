#! /bin/bash

set -e

IGNORED_STUFF=$(cat .gitignore | grep -v untarred | xargs echo)
NAME="5.9.0-arm-64-balbeslast" # @TODO: accept command line param


[[ -f ${NAME}.tar ]] && rm ${NAME}.tar
[[ -f ${NAME}.tar.xz ]] && rm ${NAME}.tar.xz
# shellcheck disable=SC2086
time tar cvf ${NAME}.tar $IGNORED_STUFF
# really compress it, multicore
time xz -T0 -9 ${NAME}.tar

echo "Done!"

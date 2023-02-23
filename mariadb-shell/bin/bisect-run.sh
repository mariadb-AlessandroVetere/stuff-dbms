#!/bin/bash -i

# exit status >127 stops git bisect run
# That does not apply to bash command-not-found error (127), so we treat that manually

(cd ~/src; patch -stp0 < ~/build_fixes.diff)
rm ~/build/sql/mysqld ~/build/sql/mariadbd
make clean

make -j48 2>>/tmp/compile_err ||
    exit 128
(cd ~/src; git co .)

mtr "$@" && exit 1 || ([ $? -eq 1 ] && exit 0 || exit 129)

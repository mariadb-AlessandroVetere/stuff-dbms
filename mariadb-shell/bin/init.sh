#!/bin/bash
. ./env.sh
mkdir -p data run
ln -s ../run data/run
mysql_install_db --basedir=./opt --datadir=./data --defaults-file=./mysqld.cnf

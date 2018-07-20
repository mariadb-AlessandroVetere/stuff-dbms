#!/bin/bash
if [[ $_ != $0 ]]
then
    script="${BASH_SOURCE[0]}"
    unset exec
else
    script="$0"
    if [ -z "$1" ]
    then
        exec="exec bash"
    else
        exec="exec $1"
        shift
    fi
fi

export bush_dir=$(dirname $script)
export opt="${bush_dir}/opt"
export src="${bush_dir}/src"
export build="${bush_dir}/build"
export proj_dir=$(readlink -ne "${bush_dir}/..")
export log_dir="${bush_dir}/log"

PATH="${opt}/bin:${proj_dir}/test:${opt}/scripts:${opt}/mysql-test:${opt}/sql-bench:${bush_dir}:${bush_dir}/bin:${bush_dir}/issues:${PATH}"
CDPATH="${CDPATH}:${src}:${src}/mysql-test/suite/versioning:${src}/storage:${src}/storage/innobase"

export MYSQL_UNIX_PORT="${bush_dir}/run/mysqld.sock"
export MTR_BINDIR="$build"

# innodb_ruby setup
PATH="${proj_dir}/innodb_ruby/bin:${PATH}"
export RUBYLIB=${proj_dir}/innodb_ruby/lib
alias ispace=innodb_space
alias ilog=innodb_log

mtr_opts="--tail-lines=0"
mtr()
{(
    mkdir -p "$log_dir"
    if [ -x ./mysql-test-run.pl ]
    then
        mtr_script=./mysql-test-run.pl
    else
        mtr_script=mysql-test-run
        cd "$log_dir"
    fi
    unset exclude_opts
    [ -f ~/tests_exclude ] &&
        exclude_opts="--skip-test-list=${HOME}/tests_exclude"
    [ -f mtr.log ] &&
        mv mtr.log $(date '+mtr_%Y%m%d_%H%M%S.log')
    exec $mtr_script \
        --force \
        --max-test-fail=0 \
        --suite-timeout=1440 \
        --mysqld=--silent-startup \
        ${mtr_opts} \
        ${exclude_opts} \
        "$@" 2>&1 | tee -a mtr.log
)}

alias mtrh="mysql-test-run --help | less"
alias mtrx="mtr --extern socket=${MYSQL_UNIX_PORT}"
alias mtrx1="mtr --extern socket=${build}/mysql-test/var/tmp/mysqld.1.sock"
alias mtrf="mtr --big-test --fast --parallel=4"
alias mtrb="mtrf --big-test"
alias mtrm="mtr --suite=main"
alias mtrv="mtr --suite=versioning --fast --reorder --parallel=4"
alias mtrg="mtr --manual-gdb"
alias mtrvg="mtr --manual-gdb --suite=versioning"
alias myh="mysqld --verbose --help | less"

br()
{(
    a=$1
    shift
    git branch --all --list "*${a}*" "$@" | head -n1
)}

gs()
{(
    cd "$src"
    rgrep "$@" sql storage/innobase
)}

gsl() { gs "$@" | less; }

mtrval()
{
    mtr --valgrind-mysqld \
        --valgrind-option=--leak-check=no \
        --valgrind-option=--track-origins=yes \
        --valgrind-option=--num-callers=50 \
        --valgrind-option=--log-file=${log_dir}/badmem.log \
        "$@"
}

mysql_client=$(which mysql)

mysql()
{
    db=${1:-test}
    shift
    "$mysql_client" -S "${bush_dir}/run/mysqld.sock" -u root "$db" "$@"
}

mysqlt()
{
    db=${1:-mtr}
    shift
    "$mysql_client" -S "${build}/mysql-test/var/tmp/mysqld.1.sock" -u root "$db" "$@"
}


run()
{(
    if [ -n "$1" -a -f "$1" ]
    then
        defaults="$1"
        shift
    else
        cd "${bush_dir}"
        defaults=mysqld.cnf
    fi
    exec "${opt}/bin/mysqld" "--defaults-file=$defaults" --debug-gdb --silent-startup "$@"
)}
export -f run

runval()
{(
    if [ -n "$1" -a -f "$1" ]
    then
        defaults="$1"
        shift
    else
        cd "${bush_dir}"
        defaults=mysqld.cnf
    fi
    exec valgrind \
        --leak-check=no \
        --track-origins=yes \
        --log-file=valgrind-badmem.log \
        "${opt}/bin/mysqld" "--defaults-file=$defaults" --debug-gdb "$@"
)}
export -f run

rund()
{(
    if [ "$1" = -start ]
    then
        opt_run="-ex start"
        shift
    else
        opt_run="-ex run"
    fi
    if [ -n "$1" -a -f "$1" ]
    then
        defaults="$1"
        shift
    else
        cd "${bush_dir}"
        defaults=mysqld.cnf
    fi
    exec gdb -q $opt_run --args "${opt}/bin/mysqld" "--defaults-file=$defaults" --plugin-maturity=experimental --plugin-load=test_versioning --debug-gdb --silent-startup "$@"
)}
export -f rund

runt()
{(
    cd "${src}/mysql-test"

    exec gdb -q --args "${opt}/bin/mysqld" --defaults-group-suffix=.1 --defaults-file=${build}/mysql-test/var/my.cnf --log-output=file --gdb --core-file --loose-debug-sync-timeout=300 --debug --debug-gdb "$@"
)}
export -f runt

binlog()
{(
    local run_gdb=""
    if [ "$1" = "-gdb" ]
    then
        run_gdb="gdb -q -ex run --args"
        shift
    fi

    exec $run_gdb "${opt}/bin/mysqlbinlog" "--defaults-file=${defaults}" \
        --local-load="${build}/var/tmp" -v "$@"
)}
export -f binlog

dump()
{(
    local run_gdb=""
    if [ "$1" = "-gdb" ]
    then
        run_gdb="gdb -q -ex run --args"
        shift
    fi
    db=${1:-test}
    shift
    exec $run_gdb "$(which mysqldump)" "--defaults-file=${defaults}" "$db" "$@"
)}
export -f dump

gdbt()
{(
    suffix=${1:-1}
    exec gdb -q -cd "${src}/mysql-test" -x "${build}/mysql-test/var/tmp/gdbinit.mysqld.${suffix}" -ex run "${build}/sql/mysqld"
)}
export -f gdbt

init()
{(
    cd "${bush_dir}"
    exec init.sh
)}
export -f init

attach()
{
    gdb-attach ${opt}/bin/mysqld
}

breaks()
{
    while read place text
    do
        place=$(basename "${place%:}")
        echo "# ${text}"
        echo "b $place"
        if [ "$1" ]
        then
            echo "commands"
            echo "    $1"
            echo "end"
        fi
    done
}

prepare()
{(
    mkdir -p "${build}"
    cd "${build}"
    unset plugins
    if [ -f ~/plugin_exclude ]
    then
        while read a b
        do
            [ -n "$a" ] &&
                plugins="$plugins -D$a=NO"
        done < ~/plugin_exclude
    fi
    unset cclauncher
    if [ -x $(which ccache) ]
    then
        cclauncher="-DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache"
    fi
    cmake-ln -Wno-dev \
        -DCMAKE_INSTALL_PREFIX:STRING=${opt} \
        -DCMAKE_BUILD_TYPE:STRING=Debug \
        -DCMAKE_CXX_FLAGS_DEBUG:STRING="-g -O0 -Werror=overloaded-virtual -Werror=return-type $CFLAGS" \
        -DCMAKE_C_FLAGS_DEBUG:STRING="-g -O0 -Werror=overloaded-virtual -Werror=return-type $CFLAGS" \
        -DWARN_MODE:STRING="late" \
        -DSECURITY_HARDENED:BOOL=FALSE \
        -DWITH_UNIT_TESTS:BOOL=OFF \
        -DWITH_CSV_STORAGE_ENGINE:BOOL=OFF \
        -DWITH_WSREP:BOOL=OFF \
        -DWITH_MARIABACKUP:BOOL=OFF \
        $cclauncher \
        $plugins \
        "$@" \
        ../src
)}
export -f prepare

rel_opts()
{(
    build="${build}-rel"
    cmd="$1"
    shift
    "$cmd" \
        "$@" \
        -DBUILD_CONFIG:STRING=mysql_release \
        -DWITH_JEMALLOC:BOOL=ON \
        -DCMAKE_CXX_FLAGS_RELEASE:STRING="-g" \
        -DCMAKE_C_FLAGS_RELEASE:STRING="-g" \
        -DSECURITY_HARDENED:BOOL=FALSE
)}
export -f rel_opts

ninja_opts()
{
    cmd="$1"
    shift
    "$cmd" \
        "$@" \
        -GNinja \
        -DCMAKE_C_COMPILER=/usr/bin/clang \
        -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
        -D_CMAKE_TOOLCHAIN_PREFIX=llvm- \
        -D_CMAKE_TOOLCHAIN_SUFFIX=-5.0
}
export -f ninja_opts

emb_opts()
{
    cmd="$1"
    shift
    "$cmd" \
        "$@" \
        -GNinja \
        -DCMAKE_C_COMPILER=/usr/bin/clang \
        -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
        -DWITH_UNIT_TESTS:BOOL=ON \
        -DWITH_CSV_STORAGE_ENGINE:BOOL=ON \
        -DWITH_WSREP:BOOL=ON \
        -DWITH_EMBEDDED_SERVER:BOOL=ON
}
export -f emb_opts

o1_opts()
{(
    build="${build}"
    cmd="$1"
    shift
    "$cmd" \
        "$@" \
        -DCMAKE_CXX_FLAGS_DEBUG:STRING="-g -O1" \
        -DCMAKE_C_FLAGS_DEBUG:STRING="-g -O1"
)}
export -f o1_opts


alias relprepare="rel_opts prepare"
alias nprepare="ninja_opts prepare"
alias nrelprepare="ninja_opts rel_opts prepare"
alias o1prepare="ninja_opts o1_opts prepare"
alias embprepare="emb_opts prepare"

cmakemin()
{
    cmake-ln \
        -D CMAKE_INSTALL_PREFIX:STRING=${opt} \
        "$@"
}


git()
{
    if [ "$1" = clone ] || $(which git) rev-parse &> /dev/null
    then
        $(which git) "$@"
    else (
        cd "$src"
        $(which git) "$@"
    )
    fi
}
export -f git

make()
{
    recurse="$1"
    if [ "$recurse" = norecurse ]
    then
        shift
    fi
    if [ -f Makefile ]
    then
        $(which make) "$@"
    elif [ -f build.ninja ]
    then
        $(which ninja) "$@"
    elif [ "$recurse" != norecurse ]
    then (
        cd "$build"
        make norecurse "$@"
    )
    fi
}
export -f make

gdb()
{
    unset gdb_opts
    [ -f ".gdb" ] &&
        gdb_opts="-x .gdb"
    $(which gdb) -q $gdb_opts "$@"
}

port()
{
    port=$1
    if [ "$port" ]
    then
        if ! ((port > 0))
        then
            echo "Positive number expected!" >&2
            return 1;
        fi
        sed -i -Ee '/^\s*port\s*=\s*[[:digit:]]+/ { s/^(.+=\s*)[[:digit:]]+\s*$/\1'${port}'/; }' ~/mysqld.cnf
    else
        sed -nEe '/^\s*port\s*=\s*[[:digit:]]+/ { s/.+=\s*([[:digit:]]+)\s*$/\1/; p; }' ~/mysqld.cnf
    fi
}

upatch()
{
    arg=${1:-"-p1"}
    shift
    patch "$arg" "$@" < /tmp/u.diff
}

grep_cmake()
{
    grep -i "$@" "${build}/CMakeCache.txt"
}

error()
{
    local err_h="${build}/include/mysqld_error.h"
    grep '^#define' "$err_h" |
    if [ "$1" ]
    then
        grep "$@" "$err_h"
    else
        cat
    fi |
    while read a b c; do echo "$b"; done
}

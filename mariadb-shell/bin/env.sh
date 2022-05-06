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
export src="${bush_dir}/src"
export proj_dir=$(readlink -ne "${bush_dir}/..")
export log_dir="${bush_dir}/log"

CDPATH=$(echo $CDPATH|sed -Ee 's|'${bush_dir}'[^:]*:?||g')
CDPATH="${CDPATH}:${src}:${src}/mysql-test/suite/versioning:${src}/storage:${src}/storage/innobase:${src}/mysql-test/suite:${src}/mysql-test:${build}/mysql-test"

export MYSQL_UNIX_PORT="${bush_dir}/run/mysqld.sock"
export MTR_BINDIR="$build"
export CCACHE_BASEDIR="${bush_dir}"
export CCACHE_DIR="$(realpath ${bush_dir}/../.ccache)"
export CCACHE_NLEVELS=3
export CCACHE_HARDLINK=true
export CCACHE_MAXSIZE=15G

ulimit -Sc 0

# innodb_ruby setup
PATH="${proj_dir}/innodb_ruby/bin:${PATH}"
export RUBYLIB=${proj_dir}/innodb_ruby/lib
alias ispace=innodb_space
alias ilog=innodb_log

mtr_opts="--tail-lines=0"
opt_ddl="--mysqld=--debug=d,ddl_log"
opt_vers="--mysqld=--debug=d,sysvers_force --mysqld=--system_versioning_alter_history=keep"
opt_fts="--mysqld=--innodb_ft_sort_pll_degree=1"

mtr()
{(
    mkdir -p "$log_dir"
    if [ -x ./mysql-test-run.pl ]
    then
        mtr_script=./mysql-test-run.pl
    else
        mtr_script=mysql-test-run
        cd "$log_dir"
        rm `find -name '*.log' -type f -ctime +30`
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
        --mysqld=--loose-innodb-flush-method=fsync \
        ${mtr_opts} \
        ${exclude_opts} \
        "$@" 2>&1 | tee -a mtr.log
    return $PIPESTATUS
#        --suite="main-,archive-,binlog-,client-,csv-,federated-,funcs_1-,funcs_2-,gcol-,handler-,heap-,innodb-,innodb_fts-,innodb_gis-,innodb_i_s-,json-,maria-,mariabackup-,multi_source-,optimizer_unfixed_bugs-,parts-,perfschema-,plugins-,roles-,rpl-,sys_vars-,sql_sequence-,unit-,vcol-,versioning-,period-,sysschema-" \
#        --suite="main-,archive-,binlog-,csv-,federated-,funcs_1-,funcs_2-,gcol-,handler-,heap-,innodb-,innodb_fts-,innodb_gis-,json-,maria-,mariabackup-,multi_source-,optimizer_unfixed_bugs-,parts-,perfschema-,plugins-,roles-,rpl-,sys_vars-,unit-,vcol-,versioning-,period-,sysschema-" \
)}

alias mtrh="mysql-test-run --help | less"
alias mtrx="mtr --extern socket=${MYSQL_UNIX_PORT}"
alias mtrx1="mtr --extern socket=${build}/mysql-test/var/tmp/mysqld.1.sock"
alias mtrf="mtr --big-test --fast --parallel=10"
alias mtrb="mtrf --big-test"
alias mtrz="mtr --fast --reorder --parallel=10"
alias mtrm="mtrz --suite=main"
alias mtrv="mtrz --suite=versioning"
alias mtrvv="mtrz --suite=period"
alias mtrvvg="mtr --manual-gdb --suite=period"
alias mtrg="mtr --manual-gdb"
alias mtrvg="mtr --manual-gdb --suite=versioning"
alias mtrp="mtrz --suite=parts"
alias mtrpg="mtrp --manual-gdb"
alias mtri="mtrz --suite=innodb"
alias mtrig="mtri --manual-gdb"
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
    local supp=~/mtr.supp
    local supp_opt=''
    [ -f "$supp" ] &&
        supp_opt=--valgrind=--suppressions=$supp
    mtr --valgrind=--leak-check=no \
        --valgrind=--track-origins=yes \
        --valgrind=--num-callers=50 \
        --valgrind=--log-file=${log_dir}/badmem.log \
        $supp_opt \
        "$@"
}


mtrvgdb()
{
    echo 'Use target remote | vgdb'
    local supp=~/mtr.supp
    local supp_opt=''
    [ -f "$supp" ] &&
        supp_opt=--valgrind=--suppressions=$supp
    mtr --valgrind=--vgdb=yes \
        --valgrind=--vgdb-error=0 \
        $supp_opt \
        "$@"
}

mtrleak()
{
    local supp=~/mtr.supp
    local supp_opt=''
    [ -f "$supp" ] &&
        supp_opt=--valgrind=--suppressions=$supp
    mtr --valgrind=--leak-check=full \
        --valgrind=--track-origins=yes \
        --valgrind=--num-callers=50 \
        --valgrind=--log-file=${log_dir}/leak.log \
        $supp_opt \
        "$@"
}


mysql_client=$(which mysql)

mysql()
{(
    db=${1:-test}
    shift
    [ -x "`which most`" ] &&
        export PAGER=most
    "$mysql_client" -S "${bush_dir}/run/mysqld.sock" -u root "$db" "$@"
)}


backup()
{(
    mysql_client=$(which mariabackup)
    "$mysql_client" -S "${bush_dir}/run/mysqld.sock" -u root \
        --target-dir=~/tmp/backup "$@"
)}

backupd()
{(
    mysql_client=$(which mariabackup)
    gdb --args "$mysql_client" -S "${bush_dir}/run/mysqld.sock" -u root \
        --target-dir=~/tmp/backup "$@"
)}

mysqlt()
{(
    db=${1:-mtr}
    shift
    [ -x "`which most`" ] &&
        export PAGER=most
    "$mysql_client" -S "${build}/mysql-test/var/tmp/mysqld.1.sock" -u root "$db" "$@"
)}


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
    exec gdb -q $opt_run --args "${opt}/bin/mysqld" "--defaults-file=$defaults" --plugin-maturity=experimental --plugin-load=test_versioning --debug-gdb "$@"
)}
export -f rund

runt()
{(
    cd "${src}/mysql-test"
    suffix=${1:-1}
    shift
    exec gdb -q --args "${opt}/bin/mysqld" --defaults-group-suffix=.$suffix --defaults-file=${build}/mysql-test/var/my.cnf --log-output=file --gdb --core-file --loose-debug-sync-timeout=300 --debug --debug-gdb "$@"
)}
export -f runt

runrr()
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
    exec rr record "${opt}/bin/mysqld" "--defaults-file=$defaults" --plugin-maturity=experimental --plugin-load=test_versioning --debug-gdb --silent-startup "$@"
)}
export -f runrr


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

initdb()
{(
    data=${1:-./data}
    if [ -z "$1" ]
    then
        cd "${bush_dir}"
        mkdir -p run
    fi
    data=$(readlink -f "${data}")
    if [ -e "${data}" ]
    then
        echo "${data} already exists!" >&2
        exit 100
    fi
    mkdir -p "${data}"
    ln -s "${bush_dir}/run" "${data}/run"
    mysql_install_db --basedir="${opt}" --datadir="${data}" --defaults-file="${defaults}" --auth-root-authentication-method=normal
)}
export -f initdb

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

asan_opts=-DWITH_ASAN:BOOL=ON
msan_opts=-DWITH_MSAN:BOOL=ON
export debug_opts="-g -O0 -DEXTRA_DEBUG -Werror=overloaded-virtual -Werror=return-type -Wno-deprecated-register -Wno-error=macro-redefined -Wno-error=unused-variable -Wno-error=unused-function"

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
    unset compiler_flags
    if [ -f ~/compiler_flags ]
    then
        compiler_flags="$(cat ~/compiler_flags)"
        compiler_flags="$(echo $compiler_flags)"
    fi
    cclauncher="-DCMAKE_CXX_COMPILER_LAUNCHER= -DCMAKE_C_COMPILER_LAUNCHER="
    if [ -x $(which ccache) ]
    then
        cclauncher="-DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache"
    fi
    # TODO: add DISABLE_PSI_FILE
    eval flavor_opts=\$${flavor}_opts
    cmake-ln -Wno-dev \
        -DCMAKE_INSTALL_PREFIX:STRING=${opt} \
        -DCMAKE_BUILD_TYPE:STRING=Debug \
        -DCMAKE_CXX_FLAGS_DEBUG:STRING="$debug_opts $compiler_flags $CFLAGS" \
        -DCMAKE_C_FLAGS_DEBUG:STRING="$debug_opts $compiler_flags $CFLAGS" \
        -DSECURITY_HARDENED:BOOL=FALSE \
        -DMYSQL_MAINTAINER_MODE:STRING=OFF \
        -DUPDATE_SUBMODULES:BOOL=OFF \
        -DPLUGIN_METADATA_LOCK_INFO:STRING=STATIC \
        -DWITH_UNIT_TESTS:BOOL=OFF \
        -DWITH_CSV_STORAGE_ENGINE:BOOL=OFF \
        -DWITH_WSREP:BOOL=OFF \
        -DWITH_MARIABACKUP:BOOL=OFF \
        -DWITH_SAFEMALLOC:BOOL=OFF \
        $flavor_opts \
        $cclauncher \
        $plugins \
        "$@" \
        ../src
)}
export -f prepare

prepare_strict()
{(
    mkdir -p "${build}"
    cd "${build}"
    unset cclauncher
    if [ -x $(which ccache) ]
    then
        cclauncher="-DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache"
    fi
    cmake-ln -Wno-dev \
        -DCMAKE_INSTALL_PREFIX:STRING=${opt} \
        -DCMAKE_BUILD_TYPE:STRING=Debug \
        -DCMAKE_CXX_FLAGS_DEBUG:STRING="-g -O0 -Werror=overloaded-virtual -Werror=return-type" \
        -DCMAKE_C_FLAGS_DEBUG:STRING="-g -O0 -Werror=return-type" \
        -DSECURITY_HARDENED:BOOL=FALSE \
        -DWITH_UNIT_TESTS:BOOL=OFF \
        -DWITH_CSV_STORAGE_ENGINE:BOOL=OFF \
        -DWITH_WSREP:BOOL=OFF \
        -DWITH_MARIABACKUP:BOOL=OFF \
        -DWITH_SAFEMALLOC:BOOL=OFF \
        -DMYSQL_MAINTAINER_MODE:STRING=ON \
        $cclauncher \
        "$@" \
        ../src
)}
export -f prepare_strict

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
{(
    cmd="$1"
    export CFLAGS="${CFLAGS:+ $CFLAGS}-fdebug-macro"
    shift
    "$cmd" \
        "$@" \
        -GNinja \
        -DCMAKE_C_COMPILER=/usr/bin/clang \
        -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
        -D_CMAKE_TOOLCHAIN_PREFIX=llvm-
#        -D_CMAKE_TOOLCHAIN_SUFFIX=-7
)}
export -f ninja_opts

emb_opts()
{
    cmd="$1"
    shift
    "$cmd" \
        "$@" \
        -DWITH_UNIT_TESTS:BOOL=ON \
        -DWITH_CSV_STORAGE_ENGINE:BOOL=ON \
        -DWITH_WSREP:BOOL=OFF \
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


alias relprepare="rel_opts prepare_strict"
alias nprepare="ninja_opts prepare"
alias nrelprepare="ninja_opts rel_opts prepare"
alias o1prepare="ninja_opts o1_opts prepare"
alias embprepare="emb_opts prepare"

relcheck()
{(
    set -e
    echo "*** Checking release build..."
    relprepare
    cd "${build}-rel"
    /usr/bin/make -j4
    echo "*** Checking minimal build..."
    sed -ie '/^PLUGIN_/ s/^\(.*\)=.*/\1=NO/' CMakeCache.txt
    cmake "$src"
    /usr/bin/make -j4
    echo "*** All checks are successful!"
    rm -rf "${build}-rel"
)}

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

_run_exe()
{
    exe=$(which "$1")
    if [ -z "$exe" ]
    then
        echo "'$1' is not installed!" >&2
        return 1
    fi
    shift
    "$exe" "$@"
}
export -f _run_exe

make()
{
    recurse="$1"
    if [ "$recurse" = norecurse ]
    then
        shift
    fi
    if [ -f Makefile ]
    then
        _run_exe make "$@"
    elif [ -f build.ninja ]
    then
        _run_exe ninja "$@"
    elif [ -d "$build" -a "$recurse" != norecurse ]
    then (
        cd "$build"
        make norecurse "$@"
    )
    else
        _run_exe make "$@"
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

flavor()
{
    if [ "$1" ]
    then
        sed -i -Ee '/^\s*flavor=/ d;' ~/.bashrc
        if [ "$1" = default ]
        then
            unset flavor
        else
            sed -i -Ee '/^\s*source ~\/env.sh\s*$/i flavor='${1} ~/.bashrc
            flavor="$1"
        fi
    else
        if [ "$flavor" ]
        then
            echo $flavor
        else
            echo default
        fi
    fi
    export build="${bush_dir}/build"${flavor+.${flavor}}
    export opt="${build}/opt"
    PATH=$(echo $PATH|sed -Ee 's|'${bush_dir}'[^:]*:?||g')
    PATH="${opt}/bin:${proj_dir}/test:${opt}/scripts:${opt}/mysql-test:${opt}/sql-bench:${bush_dir}:${bush_dir}/bin:${bush_dir}/issues:${PATH}"
}

flavor > /dev/null

upatch()
{
    arg=${1:-"-p1"}
    shift
    patch "$arg" "$@" < /tmp/u.diff
}

cmgrep()
{
    grep -i "$@" "${build}/CMakeCache.txt"
}

option_check()
{
    sed -Ene '/^'"$1"'/ { s/^.*=(.+)$/\1/; p; }' "$2"
}

option_set()
{
    sed -Eie '/^'"$1"'/ { s/^(.*)=.+$/\1='"$2"'/; }' "$3"
}

cm_option_check()
{
    option_check "$1" "${build}/CMakeCache.txt"
}

cm_option_set()
{
    option_set "$1" "$2" "${build}/CMakeCache.txt"
}

bush_cm_onoff_option()
{
    local val=$(cm_option_check "$1")
    if [[ -n "$3" ]]
    then
        local opt=${3^^}
        if [[ $opt != ON && $opt != OFF ]]
        then
            echo "$2" >&2
            return 1;
        fi
        if [[ "$val" != $opt ]]
        then
            cm_option_set "$1" "$opt" "${build}/CMakeCache.txt"
            nprepare
        fi
    else
        echo $val
    fi
}

asan()
{
    bush_cm_onoff_option WITH_ASAN:BOOL 'Usage: asan [off|on]' "$@"
}

msan()
{
    bush_cm_onoff_option WITH_MSAN:BOOL 'Usage: msan [off|on]' "$@"
}

maint()
{
    bush_cm_onoff_option MYSQL_MAINTAINER_MODE:STRING 'Usage: maint [off|on]' "$@"
}

emb()
{
    bush_cm_onoff_option WITH_EMBEDDED_SERVER:BOOL 'Usage: emb [off|on]' "$@"
}

wsrep()
{
    bush_cm_onoff_option WITH_WSREP:BOOL 'Usage: wsrep [off|on]' "$@"
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

update_cmake()
{
    local cache=$build/CMakeCache.txt
    if [ ! -f "$cache" ]
    then
        echo "$cache not found!" >&2
        return 1
    fi
    local cmake_build=$(sed -ne '/^# For build in directory: / { s/^# For build in directory: //; p; }' $cache)
    if [ "$build" = "$cmake_build" ]
    then
        echo "Nothing to be done for $build"
        return 0
    fi
    sed -i -e "s|${cmake_build}|${build}|" $cache ||
        return $?
    local cmake_home=$(dirname "$cmake_build")
    if [ "$cmake_home" != "$bush_dir" ]
    then
        sed -i -e "s|${cmake_home}|${bush_dir}|" $cache ||
            return $?
    fi
    echo "Updated ${cmake_build} -> ${build}"
}

exe()
{
    local f="$build/sql/mysqld"
    if [ ! -e "$f" ]
    then
        echo Not exists $f! >&2
        return 1
    fi
    if [ ! -x "$f" ]
    then
        echo Not executable $f! >&2
        return 2
    fi
    echo "$f"
}
export -f exe

args()
{
    alias set=
    alias args=echo
    source $build/mysql-test/var/tmp/gdbinit.mysqld.${1:-1}
    unalias set args
}
export -f args

cmd()
{(
    set -e
    local exe args
    exe="$(exe)"
    args="$(args $@)"
    echo "$exe $args"
)}
export -f cmd

record()
{
    if [[ $(asan) != OFF ]]
    then
        echo 'Run "asan off", compile and try again!' >&2
        return 1
    fi
    rr record `cmd $@`
}

record_kills()
{
    local i=137
    while ((i == 137))
    do
        record
        i=$?
    done
}

replay()
{
    rr replay "$@" -- -q -ex continue -ex reverse-continue
}

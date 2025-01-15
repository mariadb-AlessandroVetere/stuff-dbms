#!/bin/bash -i

set_find_bad()
{
    good=false
    mtr_succ=0
    mtr_fail=1
}

set_find_good()
{
    good=true
    mtr_succ=1
    mtr_fail=0
}

main()
{
    get_options "$@"

    patch_enabled &&
        (cd ~/src; patch -stp0 < "$patch_file")

    $do_clean && (
        rm ~/build/sql/mysqld ~/build/sql/mariadbd
        make clean
    )

    # exit status >127 stops git bisect run
    # That does not apply to bash command-not-found error (127), so we treat that manually

    local commit=$(git log -1 --format=%h)

    make -j48 2>>/tmp/compile_err |
        tee /tmp/compile.log |
        show_progress "Building $commit" ||
        exit 128

    $patched &&
        (cd ~/src; git co .)

    # Reverse exit 0 and exit 1 if you need to find first good commit instead of first bad commit
    mtr "${mtr_args[@]}" && exit $mtr_succ || ([ $? -eq 1 ] && exit $mtr_fail || exit 129)
}

help()
{
    local script=$(readlink -ne "$0")
    cat <<-EOF
		Usage: $b0 [options] [-- "mtr options"] [mtr tests]

		Run compile and mtr test, indicate mtr failure or success to git bisect.

		Options:
EOF
    # Get text between HELP BEGIN and HELP END markers in this script
    # (located in get_options()) and convert it to options help text
    sed -rne '
        /^\s*# HELP BEGIN/,/^\s*# HELP END/ {
            /\) #/ {
                s/^\s\s\s\s//
                s/\) #/\t/
                s/$/;/
                /--help\s/ s/;/./
                p
            }
        }' $script | $fixup_non_col_W |
    # -W cannot correctly word-wrap so we have to insert spaces in source text :(
    column -t -o ' ' -s $'\t' $(col_W 2) -c 80

    echo $'\n'$warn_text
}

show_progress()
{
    t=$1
    case "$option_verbose" in
    y*) cat;;
    *)
        i=0
        step=100
        while read
        do
            if ((i > step))
            then
                i=0
                echo -n ${t}.
                unset t
            else
                ((i++))
            fi
        done
        [ -z "$t" ] && echo done!
        ;;
    esac
}

fixup_non_col_W()
{
    sed -re 's/ +/ /g'
}

check_col_W()
{
    if echo yes|column -t -W1 &>/dev/null; then
        col_W_supported=true
        fixup_non_col_W=cat
    else
        col_W_supported=false
        fixup_non_col_W=fixup_non_col_W
    fi
}

col_W()
{
    $col_W_supported &&
        echo "-W ${1}" ||
        echo $'\n''(Ancient OS does not support "column -W", cannot properly format)'$'\n' >&2
}

concat()
{
    local old_ifs="$IFS"
    IFS=""
    echo "${*}"
    IFS="$old_ifs"
}

# FIXME: choose one of them:
# verbose_run() { set -x; eval "$@"; { set +x; } 2>/dev/null; }
verbose_run() { log "Executing: $@" >&10; eval "$@"; }

# FIXME: these are not directly used, just keep what is needed
verbose_pipe()
{
    verbose_buf=`cat`
    cat <<< "$verbose_buf"
    cat <<< "$verbose_buf" | sed 's/^/ > /' >&10
}

# push_back array_name value1 [value2] ...
push_back()
{
    arr=$1; shift
    for val in "$@"
    do
        eval $arr[\${#$arr[@]}]=\$val
    done
}

die()
{
    local ret=1
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        ret=$1
        shift
    fi
    [ -n "$1" ] && echo "$1" >&2;
    exit $ret
}

patch_enabled()
{
    if [ -n "$patch_file" -a -f "$patch_file" ]
    then
        patched=true
    else
        patched=false
    fi
    $patched
}

get_options()
{
    check_col_W
    local optstring_long=$(concat \
        good,bad,patch::,clean,do-clean, \
        verbose,dry-run,help)
    local optstring_short="gbp::cvnh"

    # 'local' cannot work here: || will not receive the exit status of backticks
    opts=$(getopt -o "${optstring_short}" --long "${optstring_long}" --name "$b0" -- "$@") ||
        exit $?
    eval set -- "$opts"

    set_find_bad
    unset mtr_args
    unset patch_file
    do_clean=false

    # HELP BEGIN
    while true
    do
        case "$1" in
            -g|--good) # Find first good commit
                set_find_good
                shift;;
            -b|--bad) # Find first bad commit (default)
                set_find_bad
                shift;;
            -p|--patch) # Patch source before building with this patch (default: ~/build_fixes.diff)
                patch_file=${2:-$HOME/build_fixes.diff}
                shift 2;;
            -c|--clean|--do-clean) # Do make clean before build
                do_clean=true
                shift;;
            -v|--verbose) # Verbose output
                verbose_on="set -x"
                verbose_off="{ set +x; } 2>/dev/null"
                verbose=verbose_run
                shift;;
            -h|--help) # Display this help
                help; exit;;
            --) shift; break;;
        esac
    done
    # HELP END
    push_back mtr_args "$@"
}

b0="$(basename $0)"
main "$@"

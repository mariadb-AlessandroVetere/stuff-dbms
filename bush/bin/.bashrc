eval user_bashrc=~${USER}/.bashrc
eval source $user_bashrc
export bush_name=$(basename $HOME)

no_traps()
{
    trap DEBUG
}

need_build()
{
    [ ! -d "$build" ] && {
        echo -n '-'
        return
    }
    if make -n 2>/dev/null | /bin/grep -Fq 'Linking'; then
        echo -n '*'
        return
    elif [[ ${PIPESTATUS[0]} != 0 ]]; then
        echo -n '-'
        return
    fi
}
export -f need_build

name_flavor()
{
    if [ "$flavor" ]; then
        echo -n "$bush_name/$flavor"
    else
        echo -n "$bush_name"
    fi
}
export -f name_flavor

exec_status()
{
    local status=$?
    trap DEBUG
    if [ $status -ne 0 -a $status -ne 127 ]
    then
        echo "Status: $status"
        printf '\r\n'
    fi
}

export PS1="\$(exec_status)\$(need_build){\$(name_flavor)} ${PS1}"
export CDPATH=".:~"

alias reconf="source ~/.bashrc"

source ~/env.sh

ulimit -c unlimited
if [[ `ulimit -c` != unlimited ]]
then
    echo "Hard core limit: $(ulimit -c)"
fi

rc_timestamps()
{
    echo ${1:-rc_timestamp}=$(stat -Lc %Y ~/.bashrc)
    echo ${2:-rc2_timestamp}=$(stat -Lc %Y $user_bashrc)
    echo ${3:-rc3_timestamp}=$(stat -Lc %Y ~/env.sh)
}

isnum()
{
    [ "$1" -eq "$1" ] &> /dev/null
}

reconf_check()
{
    eval $(rc_timestamps 'local rc1' 'local rc2' 'local rc3')
    if ! isnum "$rc1" || ! isnum "$rc2" || ! isnum "$rc3" ||
       ! isnum "$rc_timestamp" || ! isnum "$rc2_timestamp" || ! isnum "$rc3_timestamp"
    then
        return
    fi
    if [ $rc1 -gt $rc_timestamp -o $rc2 -gt $rc2_timestamp -o $rc3 -gt $rc3_timestamp ]
    then
        reconf
        echo "(config reloaded)"
    fi
}

eval $(rc_timestamps)

# Rely on that PROMPT_COMMAND was reset first in user .bashrc
PROMPT_COMMAND="$PROMPT_COMMAND; reconf_check"

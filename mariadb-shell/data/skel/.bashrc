eval source ~${USER}/.bashrc
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

exec_status()
{
    trap DEBUG
    local status=$?
    if [ $status -ne 0 -a $status -ne 127 ]
    then
        echo "Status: $status"
        printf '\r\n'
    fi
}

export PS1="\$(exec_status)\$(need_build){$bush_name} ${PS1}"
export CDPATH=".:~"

alias reconf="source ~/.bashrc"

source ~/env.sh

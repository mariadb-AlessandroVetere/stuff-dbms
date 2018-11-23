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
    make -n | /bin/grep -Fq 'Linking' && {
        echo -n '*'
        return
    }
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

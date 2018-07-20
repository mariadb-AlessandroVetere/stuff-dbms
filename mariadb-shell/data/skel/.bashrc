source ~midenok/.bashrc
export bush_name=$(basename $HOME)

need_build()
{
    make -n | /bin/grep -Fq 'Linking' &&
        echo -n '*'
}
export -f need_build

exec_status()
{
    local status=$?
    if [ $status -ne 0 -a $status -ne 127 ]
    then
        echo "Status: $status"
        printf '\r\n'
    fi
}

export PS1="\$(exec_status)\$(need_build){$bush_name} ${PS1}"
export CDPATH=".:~"

reconf()
{
    source ~/.bashrc
}

source ~/env.sh

[ "$STY" ] && trap 'debug_trap' DEBUG

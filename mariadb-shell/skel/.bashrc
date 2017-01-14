source ~midenok/.bashrc
export PS1="{WORKING_COPY_NAME} ${PS1}"
export CDPATH=".:~"

reconf()
{
    source ~/.bashrc
}

source ~/env.sh


[ "$STY" ] && trap 'debug_trap' DEBUG


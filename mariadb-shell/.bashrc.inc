reconf()
{
    source ~/.bashrc
}

bush()
{(
    m=$HOME/src/mariadb/$1
    if [ ! -d "$m" ]
    then
        echo "Creating new bush: $m"
        bush-prepare "$1" ||
            return $?
    fi
    HOME="$m"
    cd "$m"

    screen -rd $1 ||
        exec screen -S $1
)}

alias midenok="bush midenok"
alias trunk="bush trunk"
alias review="bush review"
alias upstream="bush upstream"
alias 10.2="bush 10.2"


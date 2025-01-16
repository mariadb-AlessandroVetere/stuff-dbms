alias reconf="source ~/.bashrc"

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

    session=$(echo "$1"|md5sum|cut -c1-8)-${1}
    screen -rd $session >/dev/null ||
        exec screen -S $session -s /bin/bash
)}

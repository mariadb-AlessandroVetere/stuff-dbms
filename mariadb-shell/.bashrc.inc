reconf()
{
    source ~/.bashrc
}

devshell()
{(
    m=$HOME/src/mariadb/$1
    HOME="$m"
    cd "$m"

    screen -rd $1 ||
        exec screen -S $1
)}

alias midenok="devshell midenok"
alias trunk="devshell trunk"
alias 10.2="devshell 10.2"


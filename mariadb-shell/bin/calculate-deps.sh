#!/bin/bash
get_deps()
{
    git deps HEAD^! -e base |
    while read SHA
    do
        git log --pretty="format:%h %s%n" $SHA^!
    done
}

git log HEAD^!| cat
echo -n "Getting deps... "
header="=== Dependencies (auto-detected by git-deps) ==="
deps="$(get_deps)"

if [ -n "$deps" ]; then
    echo "replacing by:"
    echo "$deps"$'\n'
else
    echo "none found."$'\n'
fi

(
    git show -s --format=%B|
    sed '/'"$header"'/,$d'
    if [ -n "$deps" ]; then
        echo "$header"
        echo "$deps"
    fi
) |
git commit --amend -F -

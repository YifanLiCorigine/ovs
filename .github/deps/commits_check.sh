#! /bin/bash

set -e

if [ -z "$1" ]; then
    echo "Please specify commit count."
    exit 1
fi

# verify that git can run without error
git status > /dev/null

for commit in $(git log --oneline --no-color -$1 --reverse | cut -d ' ' -f 1); do
    echo "============== Checking $commit ========================"

    git checkout $commit
    PATCH_FILE=$(git format-patch -1 $commit)
    commit_message=$(git log --oneline -1 | cut -d ' ' -f 2)
    if [ "${commit_message}" == "github-patches-check:" ]; then
        echo " Self-check detected, skipping...."
        continue
    fi

    echo
    echo "----------- Doc string check ---------"
    # This gets all .c/.h files touched by the commit
    set +e
    files=$(git show --name-only --oneline --no-merges $commit | grep -E '(*\.h|*\.c)')
    ERROR="$?"
    # Grep will exit with 0 if a match is found, 1 if no match is found,
    # and 2 if an error is encountered. 0 and 1 are non-error states for
    # this script, so treat them accordingly
    [ "$ERROR" == 0 -o "$ERROR" == 1 ] || exit "$ERROR"
    set -e

    if [ "$ERROR" == 1 ]; then
        echo " No C files found, skipping...."
    else
        echo $files
        # Run doc string checker on the files in the commit
        ./kernel-doc -Werror -none $files
    fi

    echo
    echo "----------- Reverse xmas tree check ------------"
    ./xmastree.py "$PATCH_FILE"

    echo
    echo "----------- Checkpatch ------------"
    ./utilities/checkpatch.py "$PATCH_FILE"

    rm "$PATCH_FILE"

    echo "========================================================"
    echo
    echo

done
set +e

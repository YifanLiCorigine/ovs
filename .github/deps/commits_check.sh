#! /bin/bash

set -e

commit_status_init() {
    COMMIT_STATUS_FAIL=0
}

commit_status_set_fail() {
    local reason=$1
    echo "Failed: $reason"
    COMMIT_STATUS_FAIL=1
}

commit_status_get() {
    echo $COMMIT_STATUS_FAIL
}

if [ -z "$1" ]; then
    echo "Please specify commit count."
    exit 1
fi

# verify that git can run without error
git status > /dev/null

for commit in $(git log --oneline --no-color -$1 --reverse | cut -d ' ' -f 1); do
    echo "============== Checking $commit ========================"
    commit_status_init

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
        if ! ./kernel-doc -Werror -none $files; then
            commit_status_set_fail "kernel-doc exited with non-zero return code"
        fi
    fi

    echo
    echo "----------- Reverse xmas tree check ------------"
    if ! ./xmastree.py "$PATCH_FILE"; then
        commit_status_set_fail "xmastree.py exited with non-zero return code"
    fi

    echo
    echo "----------- Checkpatch ------------"
    if ! ./utilities/checkpatch.py "$PATCH_FILE"; then
        commit_status_set_fail "checkpatch.py exited with non-zero return code"
    fi

    rm "$PATCH_FILE"

    # Get the status of all checks and only move to next commit if all passed
    echo
    echo "----------- Checks summary --------------"
    if [[ $(commit_status_get) -eq 0 ]]; then
        echo "All checks passed for $commit"
    else
        echo "One or more checks failed for $commit"
        exit 1
    fi

    echo "========================================================"
    echo
    echo

done
set +e

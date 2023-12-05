#!/bin/bash

function git_push_branches_tags_to_remotes() {
    remotes=(github origin)
    branches=(develop master main)

    for remote in "${remotes[@]}" ; do
    
        for branch in "${branches[@]}" ; do

            if [ `git rev-parse --verify $branch 2>/dev/null` ]
            then
                git checkout $branch
                git pull $remote $branch
                git push $remote $branch
            fi

        done

        # Push tags
        git push $remote --tags

    done
}

target_directory=.

# Check if a directory argument is provided
if [ $# -eq 1 ]; then
  target_directory=$1
fi

# Change the working directory to the provided directory
cd "$target_directory" || exit

# Export function so it is accessible from a new bash the gets called in xargs down below
export -f git_push_branches_tags_to_remotes

git submodule foreach --recursive | tac | sed 's/Entering//' | xargs -n 1 bash -c 'cd $0; git_push_branches_tags_to_remotes'

# Fetch all changes in the meanwhile
git submodule foreach --recursive 'git fetch --all'

# Run this twice in case submodule was commited in repo that gets evaluated after another one
git submodule foreach --recursive | tac | sed 's/Entering//' | xargs -n 1 bash -c 'cd $0; git_push_branches_tags_to_remotes'

# Change back to the original working directory if needed
cd - || exit

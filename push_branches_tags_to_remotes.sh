#!/bin/bash

# This script can be run like: sh script.sh location/of/repo
# It will go through all the submodules and push to all remotes all the branches
# defined in the function below. It will also push all the tags
# To use this script with the demo git playground set up by setupt_demo_git_projects.sh
# add -c protocol.file.allow=always to git commands that operate on remote repos (fetch, clone, push, pull, ...)

set -x # Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and their arguments or associated word lists after they are expanded and before they are executed.
set -e # Exit immediately if a pipeline (see Pipelines), which may consist of a single simple command (see Simple Commands), a list (see Lists of Commands), or a compound command (see Compound Commands) returns a non-zero status.

# Log the process to a temporary log file which will get moved on EXIT trap set up down below.
# We are logging to a temporary file because I want the log file to reside in the target_directory.
# But if I directly place it there the repo gets dirty, so instead it is placed in a tmp/ folder
# and on EXIT trap gets copied over.
temp_log_file=$(mktemp)
exec > >(tee "$temp_log_file") 2>&1 # Redirect stdout (1) and stderr (2) to both the terminal and the log file

# Log date
date

# The EXIT trap will ensure that, regardless of how the script ends, the temporary log file will be moved to the desired location. This way, we won't lose the log even if an error occurs.
trap 'final_log_file="${absolute_target_directory}/push.log"; mv "$temp_log_file" "$final_log_file"; echo "[INFO] Log file $final_log_file"' EXIT

# Move to a target directory if one is provided
target_directory=.
# Check if a directory argument is provided
if [ $# -eq 1 ]; then
  target_directory=$1
fi
# Change the working directory to the provided directory
cd "$target_directory" || exit

# Save the absolute location of the target directory
absolute_target_directory=$(realpath "$PWD")

function git_is_clean() {
    # Check if there are any uncommitted changes or untracked files
    git diff-index --quiet HEAD -- && git diff --cached --quiet && return 0 || return 1
}

function git_push_branches_tags_to_remotes() {
    remotes=(github origin)
    branches=(develop master main)

    relative_path=$(realpath -s --relative-to="$absolute_target_directory" "$PWD")

    printf "[INFO] Repository: '%s'\n" "$relative_path" # NOTE In the context of git submodule foreach, $path is set by git to the path of each submodule. Currently though this function is being called by bash through xargs, so this path is not directly from git submodule but instead from xargs calling bash and bash exporting it and then calling this function.

    for remote in "${remotes[@]}" ; do
        for branch in "${branches[@]}" ; do

            echo "[INFO] Pushing ${remote}/${branch}"
            
            # if branch exists
            if [ "$(git rev-parse --verify "$branch" 2>/dev/null)" ]; then
                # Save the current branch name
                current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

                # Check if we are on a branch
                if [ -z "$current_branch" ]; then
                    echo "[ERROR] Not on a branch. Skipping..."
                    return 1
                fi

                # Check if we have no uncommitted changes
                if ! git_is_clean; then
                    echo "[ERROR] Uncommitted changes present. Skipping branch $branch."
                    continue
                fi

                git checkout "$branch"
                git -c protocol.file.allow=always pull "$remote" "$branch"
                git -c protocol.file.allow=always push "$remote" "$branch"

                # Checkout the saved branch
                git checkout "$current_branch"
            fi
        done

        # Push tags
        git -c protocol.file.allow=always push "$remote" --tags
    done
}

push_branches_tags_to_all_submodules_in_reverse_order() {
    # Get the list of submodule paths in reverse order, removing 'Entering ' prefix and quotes
    submodule_paths=$(git submodule foreach --recursive | tac | sed -e 's/Entering //' -e "s/'//g")

    # Loop over each submodule path
    while IFS= read -r submodule_path; do
    (
        cd "$submodule_path" || exit
        git_push_branches_tags_to_remotes
    )
    done <<< "$submodule_paths"
}

# Push branches and tags for all submodules but do it in reverse order since I think that if you try to push
# a branch and the submodules aren't pushed the push will fail.
echo "[INFO] 1st Push all submodule's branches and tags to remotes. Important: submodules are in reverse order!"  
push_branches_tags_to_all_submodules_in_reverse_order

# Fetch all changes after the push
echo "[INFO] Submodules 'fetch --all'"  
git submodule foreach --recursive 'git -c protocol.file.allow=always fetch --all'

# Run this twice in case submodule was committed in a repo that gets evaluated after another one
echo "[INFO] 2nd Push all submodule's branches and tags to remotes. Important: submodules are in reverse order!"  
push_branches_tags_to_all_submodules_in_reverse_order

# Now also push the main repo after all the submodules have been pushed
echo "[INFO] Main repository (superproject): push all branches and tags to remotes."  
git_push_branches_tags_to_remotes

echo "[INFO] Pulling and pushing finished."

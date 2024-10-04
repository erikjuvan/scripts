#!/bin/bash

# This script can be run like: sh script.sh location/of/repo
# It will go through all the submodules and push to all remotes all the branches
# defined in the function below. It will also push all the tags
# To use this script with the demo git playground set up by setupt_demo_git_projects.sh
# add -c protocol.file.allow=always to git commands that operate on remote repos (fetch, clone, push, pull, ...)

# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -x # Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and their arguments or associated word lists after they are expanded and before they are executed.
set -e # Exit immediately if a pipeline (see Pipelines), which may consist of a single simple command (see Simple Commands), a list (see Lists of Commands), or a compound command (see Compound Commands) returns a non-zero status.

# Log the process to a temporary log file which will get moved on EXIT trap set up down below.
# We are logging to a temporary file because I want the log file to reside in the target_directory.
# But if I directly place it there the repo gets dirty, so instead it is placed in a tmp/ folder
# and on EXIT trap gets copied over. EDIT: This is not necessary anymore since I removed
# the check for a dirty git repo because I'm no longer switching between branches, but I'll leave it
# anyway as an example of how it can be done, since it's not really hurting anything.
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
    exclusions=("simulink")

    relative_path=$(realpath -s --relative-to="$absolute_target_directory" "$PWD")
    repo_name=$(basename "$relative_path")

    # Check if the repository name contains any of the exclusions
    for exclusion in "${exclusions[@]}"; do
        if [[ "$repo_name" == *"$exclusion"* ]]; then
            echo "[INFO] Repository '$relative_path' is excluded. Skipping..."
            return
        fi
    done

    echo "[INFO] Repository: '$relative_path'" # NOTE In the context of git submodule foreach, $path is set by git to the path of each submodule. Currently though this function is being called by bash through xargs, so this path is not directly from git submodule but instead from xargs calling bash and bash exporting it and then calling this function.

    for remote in "${remotes[@]}" ; do
        # Push branches
        for branch in "${branches[@]}" ; do
            # if branch exists
            if git show-ref --verify --quiet "refs/heads/$branch"; then
                # I don't think this is needed if we are not changing branches
                # # Check if we have uncommitted changes
                # if ! git_is_clean; then
                #     echo "[ERROR] Uncommitted changes present. Skipping branch $branch."
                #     continue
                # fi

                # git -c protocol.file.allow=always pull --rebase "$remote" "$branch" # I don't think a pull is needed

                echo "[INFO] Pushing ${remote}/${branch}"
                # If push fails that is not necessarily an error since a submodule of one project can be on a different
                # branch and be behind the other one that was already pushed, but that is not an error.
                if ! git -c protocol.file.allow=always push "$remote" "$branch"; then
                    echo "[WARNING] Failed to push $remote/$branch on $relative_path"
                fi
            else
                echo "[INFO] Branch '$branch' does not exist. Skipping..."
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

# Run this twice in case submodule was committed in a repo that gets evaluated after another one.
# Detailed explanation. Lets say user/submodules/shared is first in line to get pushed, then follows
# safe/submodules/shared. Now let's also say that the actual changes to the shared submodule were done
# in safe/submodules/shared. So with the 1st round of pushing the user/submodules/shared is left unchanged.
# Hmm... this still feels OK, since we are fetching after the first push. I fail to see what the second
# push would account for, but ChatGPT seems to think it's a good idea, so I'll keep it.
echo "[INFO] 2nd Push all submodule's branches and tags to remotes. Important: submodules are in reverse order!"
push_branches_tags_to_all_submodules_in_reverse_order

# Now also push the main repo after all the submodules have been pushed
echo "[INFO] Main repository (superproject): push all branches and tags to remotes."
git_push_branches_tags_to_remotes

echo "[INFO] Pulling and pushing finished."

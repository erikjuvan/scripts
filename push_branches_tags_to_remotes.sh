#!/bin/bash

# This script can be run like: sh script.sh location/of/repo
# It will go through all the submodules and push to all remotes all the branches
# defined in the function below. It will also push all the tags
# To use this script with the demo git playground set up by setupt_demo_git_projects.sh
# add -c protocol.file.allow=always to git commands that cause issue with error 'fatal: transport 'file' not allowed'

# Move to script folder so it can source functions.sh
script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$script_dir" || exit

# Source functions
if [[ ! -f functions.sh ]]; then
    echo "Error: functions.sh not found."
    exit 1
fi
source functions.sh

# Return to the directory from which the script was called.
# This allows us to call the script from a remote dir and point to the directory from there.
cd - &> /dev/null || exit

init setx

# EXIT trap
trap '
exit_status="$?"
log_summary "$exit_status"
' EXIT

# Move to a target directory if one is provided
target_directory=.
# Check if a directory argument is provided
if [ $# -eq 1 ]; then
  target_directory=$1
fi
# Change the working directory to the provided directory
cd "$target_directory" || exit

# Check if we are in a Git repository
if ! on_git_repo_root; then
    exit 1
fi

# Save the absolute location of the target directory
absolute_target_directory=$(realpath "$PWD")

log_to_file_also "$absolute_target_directory/push_logs" "push"

git_push() {
    remotes=$(git remote)
    branches=(develop master main)
    exclusions=() # Had simulink, but will instead push everything.

    relative_path=$(realpath -s --relative-to="$absolute_target_directory" "$PWD")
    repo_name=$(basename "$relative_path")

    # Check if the repository name contains any of the exclusions
    for exclusion in "${exclusions[@]}"; do
        if [[ "$repo_name" == *"$exclusion"* ]]; then
            log_message INFO "Repository '$relative_path' is excluded. Skipping..."
            return
        fi
    done

    log_message INFO "Repository: '$relative_path'"

    for remote in $remotes; do
        # Push branches
        for branch in "${branches[@]}" ; do
            # if branch exists
            if git show-ref --verify --quiet "refs/heads/$branch"; then
                log_message INFO "Pushing ${remote}/${branch}"
                # If push fails that is not necessarily an error since a submodule of one project can be on a different
                # branch and be behind the other one that was already pushed, but that is not an error.
                if ! git push "$remote" "$branch"; then
                    log_message WARNING "Failed to push $remote/$branch on $relative_path"
                fi
            else
                log_message INFO "Branch '$branch' does not exist. Skipping..."
            fi
        done

        # Push tags
        git push "$remote" --tags
    done
}

git_push_submodules_in_reverse() {
    # Get the list of submodule paths in reverse order, removing 'Entering ' prefix and quotes
    submodule_paths=$(git submodule foreach --recursive | tac | sed -e 's/Entering //' -e "s/'//g")

    # Loop over each submodule path
    while IFS= read -r submodule_path; do
    (
        cd "$submodule_path" || exit
        git_push
    )
    done <<< "$submodule_paths"
}

# Fetch all
log_message INFO "Fetching all."
git fetch --all
git submodule foreach --recursive 'git -c protocol.file.allow=always fetch --all'

# Push branches and tags for all submodules but do it in reverse order since I think that if you try to push
# a branch and the submodules aren't pushed the push will fail. Although it seems to not fail at least not
# on local filesystem, git daemon, gitea, github, maybe on gitlab?
log_message INFO "Push submodules in reverse order!"
git_push_submodules_in_reverse

# Now also push the main repo after all the submodules have been pushed
log_message INFO "Push main repository."
git_push

log_message INFO "Done."

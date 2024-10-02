#!/bin/bash

# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -x # Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and their arguments or associated word lists after they are expanded and before they are executed.
set -e # Exit immediately if a pipeline (see Pipelines), which may consist of a single simple command (see Simple Commands), a list (see Lists of Commands), or a compound command (see Compound Commands) returns a non-zero status.

# Execute script line by line, prompting a user to press a key for each line
# trap read debug

# Move to the location of the script so it can be called from anywhere
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$script_dir" || exit

# Move to a target directory if one is provided
target_directory=.
# Check if a directory argument is provided
if [ $# -eq 1 ]; then
  target_directory=$1
  mkdir -p "$target_directory"
fi
# Change the working directory to the provided directory
cd "$target_directory" || exit

# Log the process to a file
log_file="setup.log"
# Redirect stdout (1) and stderr (2) to both the terminal and the log file
exec > >(tee "$log_file") 2>&1

# Define directories
project_dirname="local"
remotes_dirname="remotes"
base_dir=$PWD
local_dir=$base_dir/$project_dirname
remotes_dir=$base_dir/$remotes_dirname

# Create necessary directories
mkdir -p "$local_dir" "$remotes_dir/origin" "$remotes_dir/github"

function create_git_repo() {
    dir=$1
    git init "$dir"
    cd "$dir" || exit
    touch README
    printf "* text=auto\n" > .gitattributes
    git add -A
    git checkout -b main
    git commit -am "Initial commit"
    git branch develop
    cd - || exit
}

# Create repos for each project
for dir in release safe user shared blackchannel simulink; do
    create_git_repo "$local_dir/$dir"
done

# Create bare repos for remotes
cd "$remotes_dir/origin"  || exit
for dir in "$local_dir"/*/; do
    git -c protocol.file.allow=always clone --bare "$dir"
done

cd "$remotes_dir/github" || exit
for dir in "$local_dir"/*/; do
    git -c protocol.file.allow=always clone --bare "$dir"
done

# Add submodules to projects
cd "$local_dir/safe" || exit
git -c protocol.file.allow=always submodule add ../shared submodules/shared
git -c protocol.file.allow=always submodule add ../blackchannel submodules/blackchannel
git commit -am "Add submodules"

cd "$local_dir/user" || exit
git -c protocol.file.allow=always submodule add ../shared submodules/shared
git -c protocol.file.allow=always submodule add ../simulink submodules/simulink
git commit -am "Add submodules"

cd "$local_dir/release" || exit
git -c protocol.file.allow=always submodule add ../safe safe
git -c protocol.file.allow=always submodule add ../user user
git commit -am "Add submodules"

# Add remotes
function add_remotes() {
    dir=$1
    cd "$dir" || exit
    git remote add origin "$remotes_dir/origin/$(basename "$dir").git"
    git remote add github "$remotes_dir/github/$(basename "$dir").git"
    cd - || exit
}

for dir in "$local_dir"/*/; do
    add_remotes "$dir"
done

# Push branches and tags
for dir in "$local_dir"/*/; do
    cd "$dir" || exit
    git push origin main
    git push origin develop
    git push github main
    git push github develop
    cd - || exit
done

# Tagging specific repos
cd "$local_dir/safe" || exit
git tag v0.8.0
git push --tags

cd "$local_dir/user" || exit
git tag v1.0.0
git push --tags

# Clean up local repos and clone release
cd "$local_dir" || exit
if [ -d "$local_dir/release" ]; then
    rm -rf release safe user shared blackchannel simulink
else
    echo "Error: Expected directories not found, aborting deletion."
    exit 1
fi
git -c protocol.file.allow=always clone "$remotes_dir/origin/release"
cd release || exit
git remote add github "$remotes_dir/github/release"
git -c protocol.file.allow=always submodule update --init --recursive
export REMOTES_DIR=$remotes_dir
git submodule foreach --recursive 'git remote add github $REMOTES_DIR/github/$(basename $path)'
git -c protocol.file.allow=always fetch --all
git submodule foreach --recursive 'git -c protocol.file.allow=always fetch --all'

# Additional steps (commits)
read -n 1 -r -p "Make some commits to main and develop to make them dirty [Y/n]? "
echo
if [[ $REPLY = [Yy] ]]; then
    # Add your commit steps here...
    echo "Adding commits to simulate changes..."
    
    # Create new commits on main and develop branch
    cd "${local_dir}"/release/safe
    git checkout main
    echo "Some safe stuff" > safe.c
    git add safe.c
    git commit -am "Add safe.c"
    git tag v1.0.0
    git checkout -b develop main
    echo "Some safe develop stuff" >> safe.c
    git add safe.c
    git commit -am "Add safe.c develop stuff"
    git tag v1.1.0-rc

    cd ../user
    git checkout main
    echo "Some user stuff" > user.c
    git add user.c
    git commit -am "Add user.c"
    git tag v1.1.0
    git checkout -b develop main
    echo "Some user develop stuff" >> user.c
    git add user.c
    git commit -am "Add user.c develop stuff"
    git tag v1.2.0-rc

    cd ../safe/submodules/shared
    git checkout main
    echo "Some shared stuff" > shared.c
    git add shared.c
    git commit -am "Add shared.c"
    git checkout -b develop main
    echo "Some shared develop stuff" >> shared.c
    git add shared.c
    git commit -am "Add shared.c develop stuff"
fi

echo "Git playground setup finished"
echo "Log file $log_file"

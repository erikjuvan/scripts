#!/bin/bash

# This script sets up git repos and remotes that mirror the setup in work
# projects. It can be used to quickly build a testing setup for experimenting 
# with git on an actual structure of a realistic project.
# Note: this could perhaps be setup up more nicely if we instead first
# created bare repos and clone then, instead of doing it backwards. But
# this way is also just fine.

# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -x # Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and their arguments or associated word lists after they are expanded and before they are executed.
set -e # Exit immediately if a pipeline (see Pipelines), which may consist of a single simple command (see Simple Commands), a list (see Lists of Commands), or a compound command (see Compound Commands) returns a non-zero status.

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

project_dirname=local
remotes_dirname=remotes
base_dir=$PWD
local_dir=$base_dir/$project_dirname
remotes_dir=$base_dir/$remotes_dirname

# Create basic repos
mkdir -p "$local_dir" "${remotes_dir}"/origin "${remotes_dir}"/github
cd "$local_dir"
mkdir release safe user shared blackchannel simulink
for dir in */; do cd "$dir"; git init; cd -; done
for dir in */; do cd "$dir"; touch README; cd -; done
for dir in */; do cd "$dir"; printf "* text=auto\n" > .gitattributes; cd -; done
for dir in */; do cd "$dir"; git add -A; cd -; done
for dir in */; do cd "$dir"; git checkout -b main; cd -; done
for dir in */; do cd "$dir"; git commit -am "Initial commit"; cd -; done
for dir in */; do cd "$dir"; git branch develop; cd -; done

# Create all remotes
cd "$remotes_dir"/origin
for dir in "$local_dir"/*/; do git clone --bare "$dir"; done

cd "$remotes_dir"/github
for dir in "$local_dir"/*/; do git clone --bare "$dir"; done

# Add submodules to projects
cd "$local_dir"/safe
git -c protocol.file.allow=always submodule add ../shared submodules/shared
git -c protocol.file.allow=always submodule add ../blackchannel submodules/blackchannel
git add -A; git commit -am "Add submodules"
    
cd "$local_dir"/user
git -c protocol.file.allow=always submodule add ../shared submodules/shared
git -c protocol.file.allow=always submodule add ../simulink submodules/simulink
git add -A; git commit -am "Add submodules"

cd "$local_dir"/release
git -c protocol.file.allow=always submodule add ../safe safe
git -c protocol.file.allow=always submodule add ../user user
git add -A; git commit -am "Add submodules"

# Add remotes to all projects
cd "$local_dir"
for dir in */; do cd "$dir"; git remote add origin "$remotes_dir"/origin/"${dir::-1}".git; cd -; done
for dir in */; do cd "$dir"; git remote add github "$remotes_dir"/github/"${dir::-1}".git; cd -; done

# Push all repos to all remotes
cd "$local_dir"
for dir in */; do cd "$dir"; git push origin main; git push origin develop; cd -; done
for dir in */; do cd "$dir"; git push github main; git push github develop; cd -; done

cd "$local_dir"/safe
git tag v0.8.0
git push origin --tags
git push github --tags

cd "$local_dir"/user
git tag v1.0.0
git push origin --tags
git push github --tags

# Delete all local repos and only clone release
cd "$local_dir"
rm -rf release safe user shared blackchannel simulink
git -c protocol.file.allow=always clone "$remotes_dir"/origin/release
cd release
git remote add github "$remotes_dir"/github/release
git -c protocol.file.allow=always submodule update --init --recursive
export REMOTES_DIR="$remotes_dir" # if not exported git submodule foreach in '' doesn't see our local variable
git submodule foreach --recursive 'echo $path | cut -d / -f 2 | xargs -I{} git remote add github $REMOTES_DIR/github/{}' # Note single quotes '' are needed here to avoid expansion of expressions, but instead keep the whole command/string literal/as is.
git -c protocol.file.allow=always fetch --all
git submodule foreach --recursive 'git -c protocol.file.allow=always fetch --all'

# We are now in a state where project structure is same as our gorenje projects
# at this point we can finish the script or add some additional steps

# Proceed with additional steps?
read -n 1 -r -p "Make some commits to main and develop to make them dirty [Y/n]? "
echo # move to a new line
if [[ $REPLY = [Yy] ]]; then
    # Create new commits on main and develop branch
    cd "$local_dir"/release/safe
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

# Done.
echo "Git playground setup finished"
echo "Log file '$log_file'"

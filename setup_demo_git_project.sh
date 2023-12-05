#!/bin/bash

set -x

project_dirname=local
remotes_dirname=remotes
base_dir=$PWD
local_dir=$base_dir/$project_dirname
remotes_dir=$base_dir/$remotes_dirname

# Create basic repos
mkdir -p $local_dir $remotes_dir/origin $remotes_dir/github
cd $local_dir
mkdir release safe user shared blackchannel simulink
for dir in */; do cd $dir; git init; cd -; done
for dir in */; do cd $dir; touch README; cd -; done
for dir in */; do cd $dir; git add -A; cd -; done
for dir in */; do cd $dir; git checkout -b main; cd -; done
for dir in */; do cd $dir; git commit -am "Initial commit"; cd -; done
for dir in */; do cd $dir; git branch develop; cd -; done

# Create all remotes
cd $remotes_dir/origin
for dir in $local_dir/*/; do git clone --bare $dir; done

cd $remotes_dir/github
for dir in $local_dir/*/; do git clone --bare $dir; done

# Add submodules to projects
cd $local_dir/safe
git submodule add ../shared submodules/shared
git submodule add ../blackchannel submodules/blackchannel
git add -A; git commit -am "Add submodules"
    
cd $local_dir/user
git submodule add ../shared submodules/shared
git submodule add ../simulink submodules/simulink
git add -A; git commit -am "Add submodules"

cd $local_dir/release
git submodule add ../safe safe
git submodule add ../user user
git add -A; git commit -am "Add submodules"

# Add remotes to all projects
cd $local_dir
for dir in */; do cd $dir; git remote add origin $remotes_dir/origin/${dir::-1}.git; cd -; done
for dir in */; do cd $dir; git remote add github $remotes_dir/github/${dir::-1}.git; cd -; done

# Push all repos to all remotes
cd $local_dir
for dir in */; do cd $dir; git push origin main; git push origin develop; cd -; done
for dir in */; do cd $dir; git push github main; git push github develop; cd -; done

# Delete all local repos and only clone release
cd $local_dir
rm -rf release safe user shared blackchannel simulink
git clone $remotes_dir/origin/release
cd release
git remote add github $remotes_dir/github/release
git submodule update --init --recursive
export REMOTES_DIR=$remotes_dir # if not exported git submodule foreach in '' doesn't see our local variable
git submodule foreach --recursive 'echo $path | cut -d / -f 2 | xargs -I{} git remote add github $REMOTES_DIR/github/{}'
git fetch --all
git submodule foreach --recursive 'git fetch --all'

# We are now in a state where project structure is same as our gorenje projects
# at this point we can finish the script or add some additional steps

# Proceed with additional steps?
read -n 1 -r -p "Do some additional steps[Y/n]? "
echo # move to a new line
if [[ $REPLY = [Nn] ]]
then
    exit 0
fi

# Create new commits on main and develop branch
cd $local_dir/release
cd safe
echo "Some safe stuff" > safe.c
git add safe.c
git commit -am "Add safe.c"
cd ../user
echo "Some user stuff" > user.c
git add user.c
git commit -am "Add user.c"

# Done.
echo "Git playground setup finished"

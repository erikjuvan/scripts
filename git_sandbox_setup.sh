#!/bin/bash

# Set the debug trace to include line numbers
export PS4='+ ${LINENO}: '

# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -x # Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and their arguments or associated word lists after they are expanded and before they are executed.
set -e # Exit immediately if a pipeline (see Pipelines), which may consist of a single simple command (see Simple Commands), a list (see Lists of Commands), or a compound command (see Compound Commands) returns a non-zero status.

# Execute script line by line, prompting a user to press a key for each line
# trap read debug

# Move to a target directory if one is provided
target_directory=.
# Check if a directory argument is provided
if [ $# -eq 1 ]; then
    target_directory=$1

    if [ -d "$target_directory" ]; then
        echo "[ERROR] Directory '$target_directory' already exists."
        exit 1
    else
        mkdir -p "$target_directory"
    fi
fi
# Change the working directory to the provided directory
cd "$target_directory" || exit

# Log the process to a file. Must be after above code so it is placed in target directory.
log_file="setup.log"
# Redirect stdout (1) and stderr (2) to both the terminal and the log file
exec > >(tee "$log_file") 2>&1

# Define directories
project_dirname="local"
remote_dirname="remote"
base_dir=$PWD
local_dir=$base_dir/$project_dirname
remote_dir=$base_dir/$remote_dirname
remote_origin_dir="${remote_dir}/origin"
remote_github_dir="${remote_dir}/github"

# Create necessary directories
if [ -d "$local_dir" ]; then
    echo "[ERROR] Directory '$local_dir' already exists."
    exit 1
elif [ -d "$remote_origin_dir" ]; then
    echo "[ERROR] Directory '$remote_origin_dir' already exists."
    exit 1
elif [ -d "$remote_github_dir" ]; then
    echo "[ERROR] Directory '$remote_github_dir' already exists."
    exit 1
else
    mkdir -p "$local_dir" "$remote_origin_dir" "$remote_github_dir"
fi

# Define what we will use for autocrlf
# Git can handle this by auto-converting CRLF line endings into LF when you add a file to the index, and vice versa when it checks out code onto your filesystem. You can turn on this functionality with the core.autocrlf setting. If you’re on a Windows machine, set it to true — this converts LF endings into CRLF when you check out code:
# $ git config --global core.autocrlf true
#
# If you’re on a Linux or macOS system that uses LF line endings, then you don’t want Git to automatically convert them when you check out files; however, if a file with CRLF endings accidentally gets introduced, then you may want Git to fix it. You can tell Git to convert CRLF to LF on commit but not the other way around by setting core.autocrlf to input:
# $ git config --global core.autocrlf input
#
# This setup should leave you with CRLF endings in Windows checkouts, but LF endings on macOS and Linux systems and in the repository.
# If you’re a Windows programmer doing a Windows-only project, then you can turn off this functionality, recording the carriage returns in the repository by setting the config value to false:
# $ git config --global core.autocrlf false
#
# Since this is mainly used on MSYS, I will use the input - "linux on windows" setting. Change it if needed.
core_autocrlf=input

# Option 1 - THIS
# 1. Create all local repos (and fill them with demo commits)
# 2. Add them as submodules of each other
# 3. Create bare remote repos
# 4. Add remotes to local repos
# 5. Push branches and tags to all remotes
# 6. Delete local repos and clone remote release ...

# Option 2
# 1. Create bare repos on both origin and github remote locations
# 2. Clone origin remote repos to local and add github remote
# 3. Fill them with demo commits
# 4. Add them as submodules of each other
# 5. Push branches and tags to all remotes
# 6. Delete local repos and clone remote release ...

function create_git_repo() {
    path=$1
    git init "$path"
    cd "$path" || exit
    git config --local core.autocrlf $core_autocrlf
    touch README
    echo "* text=auto" > .gitattributes
    git add -A
    git checkout -b main
    git commit -am "Initial commit"
    git branch develop
    cd - || exit
}

# Create all repos
for repo in release safe user shared blackchannel simulink; do
    create_git_repo "$local_dir/$repo"
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

# Create bare repos for remotes
for repo in "$local_dir"/*/; do
    # Get the base name of the local repository (remove trailing slash)
    repo_name=$(basename "$repo")
    # Create a bare repo with the same name in the remote directory
    git init --bare "$remote_origin_dir/$repo_name.git"
    git init --bare "$remote_github_dir/$repo_name.git"
done

# Add remotes
for path in "$local_dir"/*/; do
    cd "$path" || exit
    git remote add origin "$remote_origin_dir/$(basename "$path").git"
    git remote add github "$remote_github_dir/$(basename "$path").git"
    cd - || exit
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

# Delete all local repos
cd "$local_dir" || exit
if [ -d "$local_dir/release" ]; then
    rm -rf release safe user shared blackchannel simulink
else
    echo "Error: Expected directories not found, aborting deletion."
    exit 1
fi

# Clone release
git clone "$remote_origin_dir/release"
cd release || exit

# Set autocrlf for all
git config --local core.autocrlf $core_autocrlf
git submodule foreach --recursive "git config --local core.autocrlf $core_autocrlf"

# Add github remote to all repos
git remote add github "$remote_github_dir/release"
export REMOTE_GITHUB_DIR=$remote_github_dir # if not exported git submodule foreach in '' doesn't see our local variable
git submodule foreach --recursive 'git remote add github $REMOTE_GITHUB_DIR/$(basename $path)' # Note single quotes '' are needed here to avoid expansion of expressions ($REMOTE_GITHUB_DIR and $path), but instead keep the whole command/string literal/as is. NOTE In the context of git submodule foreach, $path will be set by git to the path of each submodule.

# Update all submodules
git -c protocol.file.allow=always submodule update --init --recursive

# Fetch all
git -c protocol.file.allow=always fetch --all
git submodule foreach --recursive 'git -c protocol.file.allow=always fetch --all'

# Additional steps (commits, tags)
read -n 1 -r -p "Make additional commits and tags to simulate changes [Y/n]? "
if [[ ! $REPLY =~ [Nn] ]]; then

    # safe/shared
    (
        echo "[INFO] Working on safe/shared..."
        cd safe/submodules/shared
        git checkout main
        echo "Some shared stuff" > shared.c
        git add shared.c
        git commit -am "Add shared.c"
        git checkout -b develop main
        echo "Some shared develop stuff" >> shared.c
        git add shared.c
        git commit -am "Add shared.c develop stuff"
        # Issue: with git log --oneline --graph --all the log does not output the branch names
        # The issue you're seeing is likely because the command substitution used with exec affects how git log is determining the output terminal's capabilities. When you use exec > >(tee "tmp_log.log"), git log may think it's not outputting to an interactive terminal (TTY), which changes its formatting behavior (like omitting branch names and colors).
        git log --oneline --graph --all --decorate # To make sure git log outputs the branch names correctly, you can force it to treat the output as if it's going to a terminal by adding the --decorate
    )

    # safe
    (
        echo "[INFO] Working on safe..."
        cd safe || exit
        git checkout main
        echo "Some safe stuff" > safe.c
        git add safe.c
        git commit -m "Add safe.c"
        git tag v1.0.0
        git checkout -b develop main
        echo "Some safe develop stuff" >> safe.c
        git add safe.c
        git commit -m "Edit safe.c"
        git tag v1.1.0-rc
        git add submodules/shared
        git commit -am "Update shared"
        git tag v1.2.0-rc
        git log --oneline --graph --all --decorate
    )

    # user/simulink
    (
        echo "[INFO] Working on user/simulink..."
        cd user/submodules/simulink
        git checkout main
        echo "Some simulink stuff" > simulink.c
        git add simulink.c
        git commit -m "Add simulink.c"
        git tag v0.1.1
        git checkout -b develop main
        echo "Some simulink develop stuff" >> simulink.c
        git add simulink.c
        git commit -m "Edit simulink.c"
        git tag v0.1.2-rc
        git log --oneline --graph --all --decorate
    )

    # user
    (
        echo "[INFO] Working on user..."
        cd user
        git checkout main
        echo "Some user stuff" > user.c
        git add user.c
        git commit -m "Add user.c"
        git tag v0.1.0
        git checkout -b develop main
        echo "Some user develop stuff" >> user.c
        git add user.c
        git commit -m "Edit user.c"
        git tag v1.0.0-rc
        git add submodules/simulink
        git commit -am "Update simulink"
        git tag v1.1.0-rc
        git log --oneline --graph --all --decorate
    )

    # release
    (
        echo "[INFO] Working on release..."
        git checkout main
        echo "#!/bin/bash" > release.sh
        git add release.sh
        git commit -m "Add release.sh"
        git tag v1.0.0
        git add user
        git commit -m "Update USER"
        git checkout -b develop main
        git add safe
        git commit -m "Update SAFE"
        git tag v2.0.0-rc
        git log --oneline --graph --all --decorate
    )

fi

echo "Git playground setup finished"
echo "Log file $log_file"

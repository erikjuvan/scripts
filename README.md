# Git sandbox setup

To quickly get and run both scripts:

git clone -b develop http://github.com/erikjuvan/scripts # Modify branch name if testing another branch, but develop seems to make sense to test
cd scripts
echo 'y' | bash git_sandbox_setup.sh testdir
bash push_branches_tags_to_remotes.sh testdir/local/release

# TODO
- If it's possible to write a 'compare_repos.sh' that would verify that push_branches_tags_to_remotes.sh works correctly
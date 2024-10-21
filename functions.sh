#!/bin/bash

# This is a collection of useful bash functions.
# Source this file to use the functions.

# Call to init script with basic things I always like to do
# $1 - SETX - to enable set -x
_set_x_enabled=false
_initialized=false
init() {
    # Exit on error
    set -e

    if [[ "$1" == "SETX" || "$1" == "setx" ]]; then
        # Debug
        set -x
        export PS4='+ ${LINENO}: ' # Set the debug trace to include line numbers
        _set_x_enabled=true
    fi

    log_message INFO "=== Running ${BASH_SOURCE[1]} ==="

    _initialized=true
}

# Set up logging to a file
# $1 - log directory
# $2 - log file name prefix
_log_file_full_path=
log_to_file_also() {
    local log_dir="$1"    # Directory where logs will be stored
    local log_prefix="$2" # Prefix to log file name

    # Create the directory if it doesn't exist
    mkdir -p "$log_dir"

    # Create a log file name with a timestamp
    local log_name="${log_prefix}_$(date +"%Y-%m-%d_%H-%M-%S").log"
    local log_full_path="${log_dir}/${log_name}"

    # Redirect stdout (1) and stderr (2) to the log file and to the console
    exec > >(tee "$log_full_path") 2>&1

    _log_file_full_path=$(realpath "$log_full_path")

    # It was already initialized
    if [ $_initialized == true ]; then
        log_message INFO "=== Running ${BASH_SOURCE[1]} - echo again for log file ==="
    fi

    # Output log name
    log_message INFO "Script ${BASH_SOURCE[1]} logging to $_log_file_full_path"

    # Log the start of the logging
    log_message INFO "Time and date: $(date)"
}

# Log message function
# $1 - log level: INFO, WARNING, ERROR, FATAL
# $2 - log message
# Declare an associative array to store log counts
declare -A _log_counts
log_message() {
    if [ "$_set_x_enabled" == true ]; then
        set +x # disable for the duration of this function
    fi

    local log_level="$1"
    shift  # Remove log_level from $@
    local message="$*"

    # Check if log_level is a valid key
    if [[ "$log_level" != "INFO" && "$log_level" != "WARNING" && "$log_level" != "ERROR" && "$log_level" != "FATAL" && "$log_level" != "RAW" ]]; then
        log_level="UNKNOWN"  # Default to UNKNOWN if invalid log level
    fi

    # Increment the count for this log level
    ((_log_counts["$log_level"]++)) || true # || true is needed if running scripts with set -e this causes it to fail

    case "$log_level" in
        INFO)
            printf "%4d: [INFO] %s\n" "${BASH_LINENO[0]}" "$message"
            ;;
        WARNING)
            printf "%4d: [WARNING] %s\n" "${BASH_LINENO[0]}" "$message"
            ;;
        ERROR)
            printf "%4d: [ERROR] %s\n" "${BASH_LINENO[0]}" "$message"
            ;;
        FATAL)
            printf "%4d: [FATAL] %s\n" "${BASH_LINENO[0]}" "$message"
            exit 1
            ;;
        RAW)
            echo -e "$message"
            ;;
        *)
            printf "%4d: [UNKNOWN] %s\n" "${BASH_LINENO[0]}" "$message"
            ;;
    esac

    if [ "$_set_x_enabled" == true ]; then
        set -x # enable back
    fi
}

# Function to print summary of log messages
# $1 - exit status
log_summary() {
    local exit_status=${1:-69}
    # Get the name of the script that sourced this file
    local parent_script="${BASH_SOURCE[-1]}" # it was [1] but it didn't work correctly
    log_message INFO "=== Log summary for $parent_script ==="
    if [ "$_set_x_enabled" == true ]; then
        set +x # disable for the duration of this function
    fi

    for level in "${!_log_counts[@]}"; do
        log_message INFO "${level}s: ${_log_counts[$level]}  "
    done

    if [[ -n "$_log_file_full_path" ]]; then
        log_message INFO "Log file $_log_file_full_path"
    fi

    log_message INFO "Finished in $SECONDS seconds."

    if [ "$exit_status" -eq 0 ]; then
        log_message INFO "SUCCESS"
    elif [ "$exit_status" -eq 69 ]; then
        log_message WARNING "UNKNOWN exit status"
    else
        log_message INFO "FAILED"
    fi

    log_message INFO "==========================="

    if [ "$_set_x_enabled" == true ]; then
        set -x # enable back
    fi
}

# Change the current directory to the script's directory.
# This is mainly for reference since this script is meant to be sourced.
# If the sourcing script is run from a different directory, the relative path to this script
# will already need to be handled in the sourcing script before calling `source` on this one.
# In short, this code would already need to be handled in the main script, so it's not as useful here.
# cd_to_current_script() {
#     # Move to the location of the script so it can be called from anywhere
#     script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
#     cd "$script_dir" || exit
# }

# Search for an executable and add it to PATH.
# $1 - File name
# $2...N - Search directories (multiple arguments)
# $N+1 - Selection criteria (optional): 'newest', 'oldest', 'first', or 'prompt' (default: 'newest')
# example: search_and_export arm-none-eabi-gcc /c/ST /c/Users/erik.juvan/home
# example: search_and_export arm-none-eabi-gcc ~/ prompt
# example: search_and_export arm-none-eabi-gcc /usr/bin first newest # Specify selection criteria if the last folder in the list has the same name as one of the selection criteria
search_and_export() {
    local executable_name="$1"
    shift # Remove the first argument (executable name)
    local selection_criteria=
    local executable_path=
    local all_results=() # Array to store all matching executables
    local executable_path_and_name=""

    # Check if the executable is already in PATH
    if command -v "$executable_name" >/dev/null; then
        log_message INFO "$executable_name is already in PATH."
        executable_path=$(command -v "$executable_name") # Get the executable path
        log_message INFO "Executable path: $executable_path"
        return 0
    fi

    # Determine if the last argument is a selection criteria or not
    selection_criteria="${!#}" # Last argument as selection criteria
    if [[ "$selection_criteria" != "newest" && "$selection_criteria" != "oldest" && "$selection_criteria" != "first" && "$selection_criteria" != "prompt" ]]; then
        selection_criteria="newest" # Default to 'newest' if no valid criteria is provided
        set -- "$@" # Keep the remaining parameters (search directories)
    else
        set -- "${@:1:$(($#-1))}" # Get all but the last argument as directories
    fi

    # Loop through each search directory and collect all matching executables
    for search_directory in "$@"; do
        while IFS= read -r result; do
            all_results+=("$result")
        done < <(find "$search_directory" -type f \( -name "$executable_name" -o -name "$executable_name.exe" \) -executable -print)
    done

    # Apply selection criteria on the collected results
    case "$selection_criteria" in
        newest)
            executable_path_and_name=$(printf "%s\n" "${all_results[@]}" | xargs -I {} stat -c "%Y %n" {} | sort -nr | head -n 1 | cut -d' ' -f2-)
            ;;
        oldest)
            executable_path_and_name=$(printf "%s\n" "${all_results[@]}" | xargs -I {} stat -c "%Y %n" {} | sort -n | head -n 1 | cut -d' ' -f2-)
            ;;
        first)
            executable_path_and_name="${all_results[0]}" # First found executable
            ;;
        prompt)
            # Ask the user to select from the found executables
            if [ ${#all_results[@]} -eq 0 ]; then
                log_message ERROR "No instances of $executable_name found in the specified directories"
                return 1
            elif [ ${#all_results[@]} -eq 1 ]; then
                executable_path_and_name="${all_results[0]}"
            else
                log_message INFO "Multiple instances of $executable_name found:"
                for i in "${!all_results[@]}"; do
                    echo "$((i + 1)). ${all_results[$i]}"
                done
                echo -n "[PROMPT] Enter the number of the executable you want to use: "
                read -r selection

                # Validate the user's input
                if [ "$selection" -gt 0 ] && [ "$selection" -le "${#all_results[@]}" ]; then
                    executable_path_and_name="${all_results[$((selection - 1))]}"
                else
                    log_message ERROR "Invalid selection."
                    return 1
                fi
            fi
            ;;
        *)
            log_message ERROR "Invalid selection criteria: $selection_criteria"
            return 1
            ;;
    esac

    # Extract the directory from the executable path
    executable_path=$(dirname "$executable_path_and_name")

    # Check if the executable was found
    if [ -n "$executable_path_and_name" ]; then
        log_message INFO "Found $executable_name at: $executable_path"
        export PATH="$executable_path:$PATH"
        log_message INFO "Added $executable_path to PATH"
    else
        log_message ERROR "$executable_name not found in the specified directories"
        return 1
    fi
}

# Function to create a unique directory.
# If the specified directory does not exist, it creates it directly.
# If the directory already exists, it appends a suffix in the form "_N" where N is the first available sequential number.
# For example, if "output" exists, it will create "output_1". If both exist, it will create "output_2", and so on.
create_unique_directory() {
    local base_dir="$1"
    local unique_dir="$base_dir"
    local n=1

    while [ -d "$unique_dir" ]; do
        unique_dir="${base_dir}_$n"
        ((n++))
    done

    mkdir "$unique_dir"
    echo "$unique_dir"
}

# Return 0 (success) if git repo is clean
git_is_clean() {
    # Check if there are any uncommitted changes or untracked files
    git diff-index --quiet HEAD -- && git diff --cached --quiet && return 0 || return 1
}

# This function returns the current git branch
git_get_current_branch() {
    # Check if we are in a Git repository
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        log_message ERROR "Not in a Git repository." >&2  # Log to stderr
        return 1  # Return an error status
    fi

    # Get the current branch or detect detached HEAD
    local current_branch
    if ! current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
        log_message ERROR "Failed to retrieve the current branch." >&2
        return 1  # Return error if git rev-parse fails
    fi

    # Check if in detached HEAD state
    if [[ "$current_branch" == "HEAD" ]]; then
        log_message WARNING "Repository is in a detached HEAD state." >&2
        echo "DETACHED-HEAD"
    else
        # Return the current branch name
        echo "$current_branch"
    fi
}

# Too much work, only here as a reference, much better to use
# git_generate_complete_diff
# $1 - path to run the command on
git_generate_diff_by_hand() {
    local path=$1
    cd "$path" || exit 1
    # File to store the diff
    local diff_file="changes.diff"
    local diff_path=
    diff_path=$(realpath "./$diff_file")

    # start with clean diff_file
    rm -rf "$diff_path"

    # Get basename of the main repo
    local main_repo_name=
    main_repo_name=$(basename "$(realpath "$path")")

    check_diff() {
        local path=$1
        local changes

        # Move into the submodule directory
        cd "$path" || exit 1

        # Check for changes in the current submodule
        changes=$(git diff HEAD)

        if [[ -n "$changes" ]]; then
            # If file doesn't yet exist create one
            if [ ! -f "$diff_path" ]; then
                touch "$diff_path"
            fi
            log_message INFO "Changes detected in $main_repo_name/$path"
            # Append the submodule diff to the diff file
            log_message INFO "Changes detected in $main_repo_name/$path" >> "$diff_path"
            git diff HEAD >> "$diff_path"
        fi

        # Move back to the original directory
        cd - > /dev/null || exit 1
    }

    # Check main repo
    check_diff .

    local submodule_paths=
    submodule_paths=$(git submodule foreach --recursive | sed -e 's/Entering //' -e "s/'//g")
    # Loop over each submodule path
    while IFS= read -r submodule_path; do
    (
        check_diff "$submodule_path"
    )
    done <<< "$submodule_paths"

    # Check if diff file is empty
    if [[ ! -s "$diff_path" ]]; then
        log_message INFO "No changes detected."
        rm -f "$diff_path"
    else
        log_message INFO "Diff saved to: $diff_path"
    fi
}

git_generate_complete_diff() {
    local path="${1:-.}"
    git -C "$path" diff --submodule=diff
}

# Example that uses generate_complete_diff to create a diff
# of 2 sumbmodules but not the superproject (skip release/, only diff safe and user)
# generate_diff() {
#     local diff_file="${1:-"changes.diff"}"
#     # Skip release repo
#
#     # Create the changes diff file
#     rm -f "$diff_file"
#     touch "$diff_file"
#
#     # SAFE
#     git_generate_complete_diff versadrive_safe > safe.diff
#     if [[ -s "safe.diff" ]]; then
#         echo "versadrive_safe" >> "$diff_file"
#         cat safe.diff >> "$diff_file"
#     fi
#
#     # USER
#     git_generate_complete_diff versadrive_user > user.diff
#     if [[ -s "user.diff" ]]; then
#         echo "versadrive_user" >> "$diff_file"
#         cat safe.diff >> "$diff_file"
#     fi
#
#     # If diff file is empty
#     if [[ ! -s "$diff_file" ]]; then
#         rm -f "$diff_file"
#     fi
#
#     rm -f safe.diff user.diff
# }

# This is just to show how checking is script is being source is done.
# Don't call this function since this script is always meant to be sourced
# and this will always return that it's being sourced.
am_i_sourced() {
    # Detect if a script is being sourced
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        echo "Script is being sourced BASH_SOURCE[0]:${BASH_SOURCE[0]} \${0}:${0}"
        return 0
    else
        echo "Script is being executed BASH_SOURCE[0]:${BASH_SOURCE[0]} \${0}:${0}"
        return 1
    fi
}

on_git_repo_root() {
    # Check if we are in a Git repository
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        log_message ERROR "Not in a Git repository."
        return 1
    fi

    # Get the top-level directory of the Git repo
    repo_root=$(git rev-parse --show-toplevel)

    # Compare it to the current working directory
    if [ "$repo_root" != "$PWD" ]; then
        log_message ERROR "Not in the root of the Git repository."
        return 1
    fi

    return 0
}

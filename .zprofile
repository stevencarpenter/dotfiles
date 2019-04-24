#
# Executes commands at login pre-zshrc.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

#
# Browser
#

if [[ "$OSTYPE" == darwin* ]]; then
  export BROWSER='open'
fi

#
# Editors
#

export EDITOR='vi'
export VISUAL='vi'
export PAGER='less'

#
# Language
#

if [[ -z "$LANG" ]]; then
  export LANG='en_US.UTF-8'
fi

#
# Paths
#

# Ensure path arrays do not contain duplicates.
typeset -gU cdpath fpath mailpath path

# Set the list of directories that cd searches.
# cdpath=(
#   $cdpath
# )

# Set the list of directories that Zsh searches for programs.
path=(
  /usr/local/{bin,sbin}
  $path
)

#
# Less
#

# Set the default Less options.
# Mouse-wheel scrolling has been disabled by -X (disable screen clearing).
# Remove -X and -F (exit if the content fits on one screen) to enable it.
export LESS='-F -g -i -M -R -S -w -X -z-4'

# Set the Less input preprocessor.
# Try both `lesspipe` and `lesspipe.sh` as either might exist on a system.
if (( $#commands[(i)lesspipe(|.sh)] )); then
  export LESSOPEN="| /usr/bin/env $commands[(i)lesspipe(|.sh)] %s 2>&-"
fi


# This allows for running aws-cli commands securely
## Usage: `awv staging aws s3 ls`
function awv() {
    local profile=$1;
    shift;
    aws-vault exec $profile -- aws $*; }
 
# This allows for logging into the AWS console as a federated user via your IAM keys instead of the console password.
## Usage: `awslogin staging`
function awslogin() { aws-vault login $@; }
 
# This creates a new shell session with the correct environment variables set so you can run SDK programs without issue.
# Note `-il` will run all your normal Login and BashRC files. (interactive, login flags)
## Usage: `awsshell staging`
function awsshell() { aws-vault exec $1 -- $SHELL -il;  }

function tf() { aws-vault exec tf -- terraform $* }


function saw {
        aws-vault exec $1 -- saw "$*"
}

# Updates a branch and returns you to your workspace
function update_branch {
  current_branch=$(git symbolic-ref --short HEAD)
  stashed_changes=$(git stash)
  gitdir="$(git rev-parse --git-dir)"
  hook="$gitdir/hooks/post-checkout"

  # Update the current branch if no argument given
  [[ -z "$1" ]] && other_branch=$current_branch || other_branch=$1

  # disable post-checkout hook temporarily
  [ -x $hook ] && mv $hook "$hook-disabled"

  # Update the requested branch
  echo "Updating $other_branch…\n"
  git checkout $other_branch
  git pull

  # If we updated the current branch, then we should run post-checkout hook
  if [[ -e "$hook-disabled" && $other_branch == $current_branch ]]; then
    mv "$hook-disabled" $hook
  fi

  # Return to current branch
  git checkout $current_branch

  # Re-enable hook
  [ -e "$hook-disabled" ] && mv "$hook-disabled" $hook

  # Reset working directory
  if [ "$stashed_changes" != "No local changes to save" ]; then
    git stash pop
  else
    echo "No stash to pop"
  fi

  echo "$fg[green]"
  echo "✓ Succesfully updated $other_branch"
  echo "$reset_color"
}


# Merges a branch into your own while preserving your workspace
function merge_branch {
  current_branch=$(git symbolic-ref --short HEAD)
  stashed_changes=$(git stash)
  gitdir="$(git rev-parse --git-dir)"
  hook="$gitdir/hooks/post-checkout"

  # Merge from master if no argument given
  [[ -z "$1" ]] && other_branch="master" || other_branch=$1

  # disable post-checkout hook temporarily
  [ -x $hook ] && mv $hook "$hook-disabled"

  # Update the requested branch
  echo "Updating $other_branch…\n"
  git checkout $other_branch
  git pull

  # Return to current branch
  git checkout $current_branch

  # Re-enable hook
  [ -e "$hook-disabled" ] && mv "$hook-disabled" $hook

  # Merge changes
  git merge $other_branch --no-edit

  # Reset working directory
  if [ "$stashed_changes" != "No local changes to save" ]; then
    git stash pop
  else
    echo "No stash to pop"
  fi

  echo "$fg[green]"
  echo "✓ Succesfully merged $other_branch into $current_branch"
  echo "$reset_color"
}

# Rebases a branch into your own while preserving your workspace
function rebase_branch {
  current_branch=$(git symbolic-ref --short HEAD)
  stashed_changes=$(git stash)
  gitdir="$(git rev-parse --git-dir)"
  hook="$gitdir/hooks/post-checkout"

  # Rebase from master if no argument given
  [[ -z "$1" ]] && other_branch="master" || other_branch=$1

  # disable post-checkout hook temporarily
  [ -x $hook ] && mv $hook "$hook-disabled"

  # Update the requested branch
  echo "Updating $other_branch…\n"
  git checkout $other_branch
  git pull

  # Return to current branch
  git checkout $current_branch

  # Re-enable hook
  [ -e "$hook-disabled" ] && mv "$hook-disabled" $hook

  # Merge changes
  git rebase $other_branch

  # Reset working directory
  if [ "$stashed_changes" != "No local changes to save" ]; then
    git stash pop
  else
    echo "No stash to pop"
  fi

  echo "$fg[green]"
  echo "✓ Succesfully rebased $current_branch onto $other_branch"
  echo "$reset_color"
}


# Fix for ls bug https://github.com/sorin-ionescu/prezto/issues/966
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"


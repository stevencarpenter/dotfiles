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
# Python Envs
#

#export VIRTUALENVWRAPPER_PYTHON=/Users/steven.carpenter/.pyenv/versions/3.7.3/bin/python3

# Setup virtualenv home
export WORKON_HOME=$HOME/.virtualenvs
source /usr/local/bin/virtualenvwrapper.sh

# Tell pyenv-virtualenvwrapper to use pyenv when creating new Python environments
export PYENV_VIRTUALENVWRAPPER_PREFER_PYVENV="true"

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


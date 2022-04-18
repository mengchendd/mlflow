#!/usr/bin/env bash

set +exv

showHelp() {
cat << EOF
Usage: ./install-dev-env.sh [-d] [directory to install virtual environment] [-v] [-q]
Development environment setup script for Python.
This script will:

  - Install pyenv if not installed
  - Retrieve the appropriate Python version (minimum required) for compatibility support
  - Check if the virtual environment already exists
    - If it does, prompt for replacement
      - If replacing, delete old virtual environment.
  - Create a virtual environment using the minimum required Python version based on previous step logic
  - Activate the environment
  - Install required dependencies for the dev envrionment

  Example usage:

  From root of MLflow repository on local with a destination virtualenv path of <root>/.venvs/mlflow-dev:

  dev/dev-env-setup.sh -d ~/.venvs/mlflow-dev

  Note: it is recommended to preface virtualenv locations with a directory name prefaced by '.' (i.e., ".venvs").

-h, -help,        --help        Display help

-d, -directory    --directory   The path to install the virtual environment into

-v, -verbose      --verbose     Whether to fill stdout with every command or not

-q, -quiet        --quiet       Whether to have pip install in quiet mode (Default: false)

EOF
}

export verbose=0
while getopts "d:vqh" opt
do
  case "$opt" in
    d) directory="$OPTARG" ;;
    v) verbose=1 ;;
    q) quiet=1 ;;
    h) showHelp; exit ;;
    *) showHelp; exit ;;
  esac
done

if [[ $verbose = 1 ]]; then
  set -exv
fi

# Check if pyenv is installed and offer to install it if not present
pyenv_exist=$(command -v pyenv)

if [ -z "$pyenv_exist" ]; then
  read -p "pyenv is required to be installed to manage python versions. Would you like to install it? $(tput bold)(y/n)$(tput sgr0): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Updating brew and installing pyenv..."
    echo "Note: this will probably take a considerable amount of time."
    brew update
    brew install pyenv
  else
    exit 1
  fi
fi

MLFLOW_HOME=$(pwd)

# Get the minimum supported version from MLflow to ensure any feature development adheres to legacy Python versions
min_py_version=$(grep "python_requires=" "$MLFLOW_HOME/setup.py" | grep -E -o "([0-9]{1,}\.)+[0-9]{1,}")

# Resolve a minor version to the latest micro version
case $min_py_version in
  "3.7") PY_INSTALL_VERSION="3.7.13" ;;
  "3.8") PY_INSTALL_VERSION="3.8.13" ;;
  "3.9") PY_INSTALL_VERSION="3.9.11" ;;
  "3.10") PY_INSTALL_VERSION="3.10.3" ;;
esac

# Install the Python version if it cannot be found
pyenv install -s $PY_INSTALL_VERSION
pyenv local $PY_INSTALL_VERSION
pyenv exec pip install "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" --upgrade pip
pyenv exec pip install "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" virtualenv

VENV_DIR="$directory/bin/activate"

# Check if the virtualenv already exists at the specified path
if [[ -d "$directory" ]]; then
  read -p "A virtual environment is already located at $VENV_DIR. Do you wish to replace it? $(tput bold; tput setaf 2)(y/n) $(tput sgr0)" -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    deactivate
    rm -rf "$directory"
    echo "Virtual environment removed from '$directory'. Installing new instance."
    pyenv exec virtualenv "$directory"
  fi
else
  # Create a virtual environment with the specified Python version
  pyenv exec virtualenv "$directory"
fi

# Activate the virtual environment
# shellcheck source=/dev/null
source "$VENV_DIR"

echo "$(tput setaf 2)Current Python version: $(tput bold)$(python --version)$(tput sgr0)"
echo "$(tput setaf 3)Activated environment is located: $(tput bold) $directory/bin/activate$(tput sgr0)"

echo "Installing pip dependencies for development environment."
# Install required dependencies for Prophet
tmp_dir=$(mktemp -d)
pip download "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" --no-deps --dest "$tmp_dir" --no-cache-dir prophet
tar -zxvf "$tmp_dir"/*.tar.gz -C "$tmp_dir"
pip install "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" -r "$(find "$tmp_dir" -name requirements.txt)"
rm -rf "$tmp_dir"

# Install dev requirements and test plugin
pip install "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" -r "$MLFLOW_HOME/requirements/dev-requirements.txt"
# Install current checked out version of MLflow (local)
pip install "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" -e .[extras]
# Install test plugin
pip install "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" -e "$MLFLOW_HOME/tests/resources//mlflow-test-plugin"
echo "Finished installing pip dependencies."

command -v docker >/dev/null 2>&1 || echo "$(tput bold; tput setaf 1)A docker installation cannot be found. Please install docker to run all tests.$(tput sgr0)"

# Setup git environment configuration for proper signing of commits
git_user=$(git config user.name)
git_email=$(git config user.email)

if [[ -z "$git_email" || -z "$git_user" ]]; then
  read -p "Your git environment is not setup to automatically sign your commits. Would you like to configure it? $(tput bold; tput setaf 2)(y/n): $(tput sgr0)" -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter the user name you would like to have associated with your commit signature: " -r git_user_name
    echo
    git config --global user.name "$git_user_name"
    echo "Git user name set as: $(git config user.name)"
    read -p "Enter your email address for your commit signature: " -r git_user_email
    git config --global user.email "$git_user_email"
    echo "Git user email set as: $(git config user.email)"
  else
    echo "Failing to set git 'user.name' and 'user.email' will result in unsigned commits. Ensure that you sign commits manually for CI checks to pass."
  fi
fi

# setup pre-commit hooks
git config core.hooksPath "$MLFLOW_HOME/hooks"

# Install pytest
pip install "$( (( $quiet == 1 && $verbose == 0 )) && printf %s '-q' )" pytest

echo "$(tput setaf 2)Your MLflow development environment can be activated by running: $(tput bold)source $VENV_DIR$(tput sgr0)"
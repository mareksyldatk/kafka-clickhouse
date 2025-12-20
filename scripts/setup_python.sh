#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/setup_python [--python VERSION] [--venv NAME]

Creates a pyenv virtualenv and installs Python dependencies.
Defaults:
  VERSION=3.12.5
  NAME=kafka-clickhouse
USAGE
}

python_version=3.12.5
venv_name=kafka-clickhouse

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python)
      python_version="$2"
      shift 2
      ;;
    --venv)
      venv_name="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done


env PYTHON_BUILD_SKIP_HOMEBREW=1 pyenv install -s "$python_version"

eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

pyenv virtualenv -f "$python_version" "$venv_name"
pyenv local "$venv_name"

pip install --upgrade pip
pip install -r scripts/python/requirements.txt

cat <<OUTPUT
Virtualenv '$venv_name' is ready.
Activate with: pyenv activate $venv_name
Run: python scripts/python/<your_script>.py
OUTPUT

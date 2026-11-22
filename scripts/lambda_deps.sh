#!/usr/bin/env bash
# Installs a Python Lambda's dependencies for the function as it is configured,
# then proves its handler imports. The deploy workflows (deploy-firebase.yml,
# deploy-assets.yml) run exactly this.
#
#   lambda_deps.sh <function-name> <region> <uv-package> <source-dir> <pkg-dir>
#
# Native wheels (cffi, grpcio, Pillow) load only on the Python version, CPU and
# glibc they were built for, so the runtime and architecture are read from the
# function itself, never restated here: a copy drifts from Terraform, and the
# Lambda then dies on import with every invocation while the deploy goes green.
#
#   - --no-build: a dependency without a matching wheel fails here, instead of
#     being compiled for the runner and shipped.
#   - manylinux_2_28: the python3.12+ runtimes are Amazon Linux 2023 (glibc
#     2.34), and some projects no longer publish 2_17 wheels for new versions.
#   - The import check runs the handler's module under the function's Python, so
#     the runner's CPU must be the function's: an arm64 function deploys from an
#     arm64 runner.
set -euo pipefail

function_name=$1 region=$2 package=$3 source_dir=$4 pkg_dir=$5

read -r runtime arch handler < <(aws lambda get-function-configuration \
  --function-name "$function_name" \
  --region "$region" \
  --query '[Runtime, Architectures[0], Handler]' \
  --output text)

[[ "$runtime" =~ ^python3\.[0-9]+$ ]] || { echo "unexpected runtime: $runtime" >&2; exit 1; }
version=${runtime#python}

case "$arch" in
  arm64) machine=aarch64 ;;
  x86_64) machine=x86_64 ;;
  *) echo "unexpected architecture: $arch" >&2; exit 1 ;;
esac
[[ "$(uname -m)" == "$machine" ]] || {
  echo "$function_name runs on $machine; build it on a $machine runner, not $(uname -m)" >&2
  exit 1
}

echo ">> $function_name: $runtime on $arch, handler $handler"

uv export --package "$package" --frozen --no-dev --no-hashes > "$pkg_dir.requirements.txt"
uv pip install \
  --no-cache-dir \
  --no-build \
  --target "$pkg_dir" \
  --python-platform "$machine-manylinux_2_28" \
  --python-version "$version" \
  --requirements "$pkg_dir.requirements.txt"

cp "$source_dir"/*.py "$pkg_dir"/

module=${handler%.*}
uv run --no-project --python "$version" python -I -c "
import sys
sys.path.insert(0, sys.argv[1])
import $module
print('>> imports:', $module.__name__)
" "$pkg_dir"

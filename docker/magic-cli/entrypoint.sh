#!/usr/bin/env bash
set -euo pipefail

# if [[ -f /opt/CangjieSDK/envsetup.sh ]]; then
#   # shellcheck source=/dev/null
#   source /opt/CangjieSDK/envsetup.sh
# fi

# args="$@"
# echo "Args: $args"
# magic-cli $args

exec "$@"

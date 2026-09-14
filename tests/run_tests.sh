#!/usr/bin/env bash
# run_tests.sh - runs every test_* function across tests/test_*.sh.
# Nothing here touches the real system: each test gets its own temp $HOME.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")"

source ./test_helpers.sh

for f in test_detect.sh test_backup.sh test_wrapper.sh test_pipewire.sh test_coredump.sh test_cli_integration.sh; do
    # shellcheck source=/dev/null
    source "./$f"
done

echo "== ${APP_NAME:-steam-remoteplay-wayland-fix} test suite =="
echo ""

mapfile -t all_tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)
for t in "${all_tests[@]}"; do
    t_run "$t"
done

t_summary
exit $?

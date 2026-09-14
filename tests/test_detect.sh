#!/usr/bin/env bash
# test_detect.sh - pure parsing/classification logic, driven by fixture
# eglinfo output so it runs identically with or without real NVIDIA hardware.

_stub_eglinfo32() {
    local fixture="$1"
    local bindir; bindir=$(mktemp -d)
    cat > "$bindir/eglinfo32" <<EOF
#!/bin/bash
cat "$TESTS_DIR/fixtures/$fixture"
EOF
    chmod +x "$bindir/eglinfo32"
    export PATH="$bindir:$PATH"
}

test_egl_wayland_32_ok_when_nvidia() {
    _stub_eglinfo32 eglinfo_nvidia_ok.txt
    assert_eq "NVIDIA" "$(detect_egl_wayland_32)"
    assert_eq "ok" "$(check_32bit_egl_wayland)"
}

test_egl_wayland_32_flagged_when_mesa_fallback() {
    _stub_eglinfo32 eglinfo_mesa_fallback.txt
    local result; result=$(check_32bit_egl_wayland)
    [[ "$result" == wrong-vendor:* ]] || { echo "expected wrong-vendor:*, got $result"; return 1; }
}

test_egl_wayland_32_missing_when_no_eglinfo32() {
    local bindir; bindir=$(mktemp -d)  # empty dir, no eglinfo32 in it
    export PATH="$bindir"
    assert_eq "missing" "$(check_32bit_egl_wayland)"
}

test_egl_gbm_32_never_recommends_install() {
    _stub_eglinfo32 eglinfo_mesa_fallback.txt   # GBM platform failed entirely
    assert_eq "not-required" "$(check_32bit_egl_gbm_informational)"
}

test_needs_workaround_respects_force_flag() {
    export SRWF_FORCE_WORKAROUND=1
    assert_true needs_nvidia_wayland_workaround || return 1
    export SRWF_FORCE_WORKAROUND=0
    assert_false needs_nvidia_wayland_workaround
}

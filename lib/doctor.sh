#!/usr/bin/env bash
# doctor.sh - full diagnostic report, with an optional inline --fix mode.
# `repair` is implemented as doctor_run in fix mode with fixes pre-confirmed.

doctor_run() {
    local fix="${1:-0}" assume_yes="${2:-0}"
    # shellcheck disable=SC2034  # read by lib/common.sh:confirm() in the same process
    [[ "$assume_yes" == "1" ]] && SRWF_ASSUME_YES=1

    log_line "== ${APP_NAME} doctor v${APP_VERSION} =="
    log_line ""

    # --- OS / kernel / desktop / session ---
    log_info "OS: $(detect_os_pretty_name)"
    log_info "Kernel: $(detect_kernel)"
    log_info "Desktop: $(detect_desktop)"

    local session; session=$(detect_session_type)
    if [[ "$session" == "wayland" ]]; then
        log_ok "Session type: wayland"
    elif [[ "$session" == "x11" ]]; then
        log_info "Session type: x11 (this project's workaround is a no-op here; Remote Play does not hit the Wayland/NVIDIA EGL bug on X11)"
    else
        log_warn "Session type: could not be determined ($session)"
    fi
    log_info "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-<unset>}"
    if [[ "$(detect_xwayland_active)" == "yes" ]]; then
        log_info "XWayland: running"
    else
        log_info "XWayland: not detected"
    fi

    # --- GPU / NVIDIA / EGL ---
    local vendor; vendor=$(detect_gpu_vendor)
    case "$vendor" in
        nvidia) log_ok "GPU vendor: NVIDIA" ;;
        amd)    log_info "GPU vendor: AMD (NVIDIA/Wayland workaround does not apply)" ;;
        intel)  log_info "GPU vendor: Intel (NVIDIA/Wayland workaround does not apply)" ;;
        *)      log_warn "GPU vendor: could not be determined" ;;
    esac

    if [[ "$vendor" == "nvidia" ]]; then
        local kind; kind=$(detect_nvidia_driver_kind)
        if [[ "$kind" == "proprietary" ]]; then
            log_ok "NVIDIA driver: proprietary, version $(detect_nvidia_driver_version)"
        elif [[ "$kind" == "nouveau" ]]; then
            log_info "NVIDIA driver: nouveau in use (this project targets the proprietary driver only; no workaround applied)"
        else
            log_warn "NVIDIA driver: not loaded / nvidia-smi unavailable"
        fi

        local w64; w64=$(detect_egl_wayland_64)
        [[ "$w64" == "NVIDIA" ]] && log_ok "EGL Wayland (64-bit): NVIDIA" || log_warn "EGL Wayland (64-bit): ${w64:-not available}"

        local x64; x64=$(detect_egl_x11_64)
        [[ "$x64" == "NVIDIA" ]] && log_ok "EGL X11 (64-bit): NVIDIA" || log_info "EGL X11 (64-bit): ${x64:-not available}"

        local gbm_result; gbm_result=$(check_64bit_egl_gbm)
        if [[ "$gbm_result" == "ok" ]]; then
            log_ok "EGL GBM (64-bit, used by PipeWire desktop capture): NVIDIA"
        else
            log_warn "EGL GBM (64-bit): $gbm_result -- desktop capture (Problem 5) may fail to init EGL"
        fi

        local w32; w32=$(check_32bit_egl_wayland)
        if [[ "$w32" == "ok" ]]; then
            log_ok "EGL Wayland (32-bit): NVIDIA"
        else
            log_warn "EGL Wayland (32-bit): $w32 (Steam's 32-bit components fall back to software rendering)"
            if [[ "$fix" == "1" ]]; then
                local pkg; pkg=$(egl_wayland_32_package)
                log_fix "32-bit NVIDIA EGL/Wayland platform missing -> installing $pkg"
                if confirm "Install $pkg now?"; then
                    if install_pkg "$pkg"; then
                        local w32b; w32b=$(check_32bit_egl_wayland)
                        [[ "$w32b" == "ok" ]] && log_ok "EGL Wayland (32-bit) now: NVIDIA" \
                            || log_warn "EGL Wayland (32-bit) still not NVIDIA after install (a re-login may be required)."
                    fi
                else
                    log_warn "Skipped installing $pkg (declined)."
                fi
            fi
        fi

        local g32; g32=$(check_32bit_egl_gbm_informational)
        log_info "EGL GBM (32-bit): $g32 (not used by the Remote Play pipeline - streaming_client is 64-bit; see docs/diagnostics.md)"
    fi

    # --- Steam ---
    local root
    if root=$(detect_steam_root); then
        log_ok "Steam installation: $root"
    elif [[ "$(detect_steam_is_flatpak_only)" == "yes" ]]; then
        log_warn "Steam installation: only a Flatpak install found; unsupported (files are replaced on every Flatpak update)."
    else
        log_fail "Steam installation: not found"
    fi

    local build; build=$(detect_steam_build_id)
    if [[ -n "$build" ]]; then
        log_info "Steam build: $build (running)"
    else
        log_info "Steam build: unknown (Steam not currently running)"
    fi

    local client; client=$(streaming_client_path 2>/dev/null || true)
    if [[ -n "$client" && -e "$client" ]]; then
        log_ok "streaming_client: $client"
        log_info "streaming_client sha256: $(sha256_of "$client")"
    else
        log_warn "streaming_client: not found (open Remote Play from Steam once so it downloads app 202355, then re-run doctor)"
    fi

    local wstatus; wstatus=$(wrapper_status)
    local wneeded=0; needs_nvidia_wayland_workaround && wneeded=1
    case "$wstatus" in
        active)
            log_ok "Wrapper status: active"
            ;;
        not-installed)
            if [[ "$wneeded" == "1" ]]; then
                log_warn "streaming_client vulnerable to the Wayland/NVIDIA EGL crash (wrapper not installed)"
                if [[ "$fix" == "1" ]]; then
                    log_fix "Applying compatibility wrapper"
                    if install_wrapper; then
                        log_ok "Remote Play workaround active"
                    fi
                fi
            else
                log_info "Wrapper status: not installed (not needed on this GPU/session configuration)"
            fi
            ;;
        stale-overwritten)
            log_warn "Steam replaced streaming_client with a fresh original (likely a Steam update) - wrapper needs to be reapplied"
            if [[ "$fix" == "1" && "$wneeded" == "1" ]]; then
                log_fix "Reapplying compatibility wrapper after Steam update"
                if install_wrapper; then
                    log_ok "Remote Play workaround active"
                fi
            fi
            ;;
        foreign)
            log_warn "A non-Steam, non-${APP_NAME} script is present at streaming_client (streaming_client.real is intact)"
            if [[ "$fix" == "1" ]]; then
                log_fix "Backing up the foreign script and installing our wrapper"
                if install_wrapper; then
                    log_ok "Remote Play workaround active"
                fi
            fi
            ;;
        corrupt)
            log_fail "Wrapper is corrupt: streaming_client.real is missing next to an active wrapper marker"
            if [[ "$fix" == "1" ]]; then
                log_fix "Attempting to restore from backup"
                if restore_from_backup pristine-real "$client" 2>/dev/null; then
                    install_wrapper && log_ok "Restored and reapplied wrapper"
                else
                    log_fail "No usable backup found. See: steam-remoteplay-wayland-fix status"
                fi
            fi
            ;;
    esac

    log_info "LD_PRELOAD (this shell): ${LD_PRELOAD:-<unset>}"
    log_info "SDL_VIDEO_DRIVER (this shell): ${SDL_VIDEO_DRIVER:-<unset>}"

    # --- PipeWire / portals / capture (Problem 5, diagnostic only) ---
    [[ "$(pw_check_pipewire)" == "active" ]] && log_ok "PipeWire: active" || log_warn "PipeWire: inactive"
    [[ "$(pw_check_wireplumber)" == "active" ]] && log_ok "WirePlumber: active" || log_warn "WirePlumber: inactive"
    [[ "$(pw_check_portal)" == "active" ]] && log_ok "xdg-desktop-portal: active" || log_warn "xdg-desktop-portal: inactive"

    local backend; backend=$(pw_check_portal_backend)
    case "$backend" in
        activatable) log_ok "xdg-desktop-portal (desktop backend): registered/activatable" ;;
        missing)     log_warn "xdg-desktop-portal (desktop backend): not found for $(detect_desktop)" ;;
        unknown-desktop) log_info "xdg-desktop-portal (desktop backend): unknown desktop, skipped" ;;
    esac
    log_info "(Backends are D-Bus-activated; systemctl reporting them 'inactive' when idle is normal, not a bug.)"

    local node; node=$(pw_check_render_node)
    case "$node" in
        ok) log_ok "DRM render node /dev/dri/renderD128: present, accessible" ;;
        missing) log_warn "DRM render node /dev/dri/renderD128: missing" ;;
        no-permission) log_warn "DRM render node /dev/dri/renderD128: present but not accessible to this user" ;;
    esac

    # --- Steam Remote Play component ---
    local rp_manifest="$root/steamapps/appmanifest_202355.acf"
    if [[ -n "$root" && -f "$rp_manifest" ]]; then
        log_ok "Steam Remote Play component (AppID 202355): installed"
    else
        log_info "Steam Remote Play component (AppID 202355): not confirmed installed"
    fi

    # --- coredump history ---
    local cd; cd=$(coredump_most_recent_signature_match)
    if [[ "$cd" == yes:* ]]; then
        IFS=: read -r _ pid ts <<<"$cd"
        log_info "Known crash signature previously seen in coredumpctl: pid $pid, $ts"
    fi

    log_line ""
    log_line "Summary: ${SRWF_WARN_COUNT} warning(s), ${SRWF_FAIL_COUNT} failure(s), ${SRWF_FIX_COUNT} fix(es) applied."

    [[ "$SRWF_FAIL_COUNT" -gt 0 ]] && return 2
    [[ "$SRWF_WARN_COUNT" -gt 0 ]] && return 1
    return 0
}

repair_run() {
    doctor_run 1 1
}

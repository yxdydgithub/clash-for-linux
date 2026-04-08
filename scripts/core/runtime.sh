#!/usr/bin/env bash

# shellcheck source=scripts/core/common.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/common.sh"
# shellcheck source=scripts/core/config.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/config.sh"

resolve_yq() {
  local arch version file url tmp_dir tmp_file

  arch="$(get_arch)"
  version="${YQ_VERSION:-$DEFAULT_YQ_VERSION}"

  if [ -x "$(yq_bin)" ]; then
    return 0
  fi

  case "$arch" in
    amd64) file="yq_linux_amd64.tar.gz" ;;
    arm64) file="yq_linux_arm64.tar.gz" ;;
    armv7) file="yq_linux_arm.tar.gz" ;;
    *) die "暂不支持的 yq 架构：$arch" ;;
  esac

  url="https://github.com/mikefarah/yq/releases/download/${version}/${file}"
  tmp_dir="$(mktemp -d)"
  tmp_file="$tmp_dir/$file"

  download_file "$url" "$tmp_file" "yq"
  tar -xzf "$tmp_file" -C "$tmp_dir"

  if [ -f "$tmp_dir/yq_linux_${arch}" ]; then
    install -m 0755 "$tmp_dir/yq_linux_${arch}" "$(yq_bin)"
  elif [ -f "$tmp_dir/yq_linux_arm" ]; then
    install -m 0755 "$tmp_dir/yq_linux_arm" "$(yq_bin)"
  elif [ -f "$tmp_dir/yq" ]; then
    install -m 0755 "$tmp_dir/yq" "$(yq_bin)"
  else
    rm -rf "$tmp_dir"
    die "解压后未找到 yq 可执行文件"
  fi

  rm -rf "$tmp_dir"
}

resolve_mihomo() {
  local arch version file url tmp_file

  arch="$(get_arch)"
  version="${MIHOMO_VERSION:-$DEFAULT_MIHOMO_VERSION}"

  if [ -x "$(mihomo_bin)" ]; then
    return 0
  fi

  case "$arch" in
    amd64) file="mihomo-linux-amd64-compatible-${version}.gz" ;;
    arm64) file="mihomo-linux-arm64-${version}.gz" ;;
    armv7) file="mihomo-linux-armv7-${version}.gz" ;;
    *) die "暂不支持的 Mihomo 架构：$arch" ;;
  esac

  url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${file}"
  tmp_file="$(mktemp)"

  download_file "$url" "$tmp_file" "mihomo"
  gzip -dc "$tmp_file" > "$(mihomo_bin)"
  chmod +x "$(mihomo_bin)"
  rm -f "$tmp_file"
}

resolve_clash() {
  local arch version version_no_v url_base tmp_file url downloaded="false"
  local candidates file

  arch="$(get_arch)"
  version="${CLASH_VERSION:-$DEFAULT_CLASH_VERSION}"
  version_no_v="${version#v}"
  url_base="${CLASH_DOWNLOAD_BASE:-https://github.com/WindSpiritSR/clash/releases/download}"

  if [ -x "$(clash_bin)" ] \
    && [ "$(read_runtime_value "KERNEL_TYPE_INSTALLED" 2>/dev/null || true)" = "clash" ] \
    && [ "$(read_runtime_value "CLASH_VERSION_INSTALLED" 2>/dev/null || true)" = "$version" ]; then
    return 0
  fi

  case "$arch" in
    amd64)
      candidates="
clash-linux-amd64-${version}.gz
clash-linux-amd64-v${version_no_v}.gz
"
      ;;
    arm64)
      candidates="
clash-linux-arm64-${version}.gz
clash-linux-arm64-v${version_no_v}.gz
clash-linux-armv8-${version}.gz
clash-linux-armv8-v${version_no_v}.gz
"
      ;;
    armv7)
      candidates="
clash-linux-armv7-${version}.gz
clash-linux-armv7-v${version_no_v}.gz
"
      ;;
    *)
      die "暂不支持的 Clash 架构：$arch"
      ;;
  esac

  tmp_file="$(mktemp)"
  rm -f "$tmp_file"

  for file in $candidates; do
    url="${url_base}/${version}/${file}"

    if download_file "$url" "$tmp_file" "clash"; then
      downloaded="true"
      break
    fi
  done

  [ "$downloaded" = "true" ] || {
    rm -f "$tmp_file"
    die "Clash 内核下载失败，请检查版本或在 .env 中覆盖 CLASH_DOWNLOAD_BASE / CLASH_VERSION"
  }

  gzip -dc "$tmp_file" > "$(clash_bin)"
  chmod +x "$(clash_bin)"
  rm -f "$tmp_file"

  write_runtime_value "KERNEL_TYPE_INSTALLED" "clash"
  write_runtime_value "CLASH_VERSION_INSTALLED" "$version"
}

resolve_runtime_kernel() {
  case "$(runtime_kernel_type)" in
    mihomo)
      resolve_mihomo
      write_runtime_value "KERNEL_TYPE_INSTALLED" "mihomo"
      write_runtime_value "MIHOMO_VERSION_INSTALLED" "${MIHOMO_VERSION:-$DEFAULT_MIHOMO_VERSION}"
      ;;
    clash)
      resolve_clash
      ;;
    *)
      die "未知内核类型：$(runtime_kernel_type)"
      ;;
  esac
}

subconverter_version_file_value() {
  read_runtime_value "SUBCONVERTER_VERSION_INSTALLED" 2>/dev/null || true
}

mark_subconverter_version_installed() {
  local version="$1"
  write_runtime_value "SUBCONVERTER_VERSION_INSTALLED" "$version"
}

resolve_subconverter() {
  local arch version file url tmp_dir tmp_file target_dir installed_version

  arch="$(get_arch)"
  version="${SUBCONVERTER_VERSION:-$DEFAULT_SUBCONVERTER_VERSION}"
  target_dir="$(subconverter_home)"
  installed_version="$(subconverter_version_file_value)"

  if [ -x "$(subconverter_bin)" ] && [ "$installed_version" = "$version" ]; then
    return 0
  fi

  case "$arch" in
    amd64) file="subconverter_linux64.tar.gz" ;;
    arm64) file="subconverter_aarch64.tar.gz" ;;
    armv7) file="subconverter_armv7.tar.gz" ;;
    *) die "暂不支持的 subconverter 架构：$arch" ;;
  esac

  url="https://github.com/tindy2013/subconverter/releases/download/${version}/${file}"
  tmp_dir="$(mktemp -d)"
  tmp_file="$tmp_dir/$file"

  download_file "$url" "$tmp_file" "subconverter"

  rm -rf "$target_dir"
  mkdir -p "$target_dir"

  tar -xzf "$tmp_file" -C "$target_dir"

  [ -x "$(subconverter_bin)" ] || {
    rm -rf "$tmp_dir"
    die "解压后未找到 subconverter 可执行文件"
  }

  chmod +x "$(subconverter_bin)"
  mark_subconverter_version_installed "$version"
  rm -rf "$tmp_dir"
}

ensure_runtime_config_ready() {
  local config_file last_file now reason

  config_file="$RUNTIME_DIR/config.yaml"
  last_file="$RUNTIME_DIR/config.last.yaml"

  if [ -s "$config_file" ] && test_runtime_config "$config_file" >/dev/null 2>&1; then
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_USED" "false"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_TIME" ""
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_REASON" ""
    write_runtime_event_value "RUNTIME_LAST_RISK_LEVEL" "$(calculate_runtime_risk_level)"
    mark_runtime_config_source "runtime"
    return 0
  fi

  reason="当前运行配置不可用"
  warn "当前运行配置不可用，尝试回退到上一次成功配置"

  [ -s "$last_file" ] || die "当前配置不可用，且不存在可回退的最后成功配置：$last_file"

  if test_runtime_config "$last_file" >/dev/null 2>&1; then
    cp -f "$last_file" "$config_file"
    now="$(now_datetime)"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_USED" "true"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_TIME" "$now"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_REASON" "$reason"
    write_runtime_event_value "RUNTIME_LAST_RISK_LEVEL" "$(calculate_runtime_risk_level)"
    mark_runtime_config_source "last_good"
    success "已回退到最后成功配置"
    return 0
  fi

  die "最后成功配置也不可用：$last_file"
}

tun_effective_check() {
  local config_tun_enabled auto_route controller_ok route_ok

  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || true)"

  if [ "$(tun_enabled)" != "true" ]; then
    echo "disabled-in-state"
    return 1
  fi

  if [ "${config_tun_enabled:-false}" != "true" ]; then
    echo "disabled-in-runtime-config"
    return 1
  fi

  if ! status_is_running 2>/dev/null; then
    echo "runtime-not-running"
    return 1
  fi

  controller_ok="false"
  if proxy_controller_reachable 2>/dev/null; then
    controller_ok="true"
  fi

  if [ "$controller_ok" != "true" ]; then
    echo "controller-unreachable"
    return 1
  fi

  auto_route="$(runtime_config_tun_auto_route 2>/dev/null || true)"
  route_ok="unknown"

  if [ "${auto_route:-false}" = "true" ]; then
    if default_route_is_tun_like; then
      route_ok="true"
    else
      route_ok="false"
    fi

    if [ "$route_ok" != "true" ]; then
      echo "default-route-not-tun"
      return 1
    fi
  fi

  echo "ok"
  return 0
}

tun_disable_check() {
  local config_tun_enabled

  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || true)"

  if [ "$(tun_enabled)" = "true" ]; then
    echo "state-still-enabled"
    return 1
  fi

  if [ "${config_tun_enabled:-false}" = "true" ]; then
    echo "runtime-config-still-enabled"
    return 1
  fi

  if status_is_running 2>/dev/null; then
    if ! proxy_controller_reachable 2>/dev/null; then
      echo "runtime-restarted-but-controller-unreachable"
      return 1
    fi
  fi

  echo "ok"
  return 0
}

start_runtime() {
  local config_file="$RUNTIME_DIR/config.yaml"

  resolve_runtime_kernel
  ensure_runtime_config_ready

  if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
    local old_pid
    old_pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" 2>/dev/null; then
      warn "Mihomo 已在运行：pid=$old_pid"
      return 0
    fi
    rm -f "$RUNTIME_DIR/mihomo.pid"
  fi

  nohup "$(runtime_kernel_bin)" -f "$config_file" -d "$RUNTIME_DIR" \
    > "$LOG_DIR/mihomo.out.log" 2>&1 &

  echo $! > "$RUNTIME_DIR/mihomo.pid"
  success "$(runtime_kernel_name) 已启动：pid=$(cat "$RUNTIME_DIR/mihomo.pid")"
}

stop_runtime() {
  local pid_file="$RUNTIME_DIR/mihomo.pid"

  [ -f "$pid_file" ] || {
    warn "Mihomo 当前未运行"
    return 0
  }

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"

  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$pid_file"
  success "Mihomo 已停止"
}

runtime_status_text() {
  if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
    local pid
    pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      echo "运行中"
      echo "进程号：$pid"
      return 0
    fi
  fi

  echo "未运行"
}

clean_runtime_state() {
  stop_subconverter || true
  stop_runtime || true
  clear_build_meta || true

  rm -f "$RUNTIME_DIR/config.yaml" 2>/dev/null || true
  rm -f "$RUNTIME_DIR"/*.pid 2>/dev/null || true
  rm -f "$RUNTIME_DIR"/*.lock 2>/dev/null || true

  rm -rf "$LOG_DIR" 2>/dev/null || true
  mkdir -p "$LOG_DIR"

  rm -rf "$RUNTIME_DIR/profiles" 2>/dev/null || true
  rm -rf "$RUNTIME_DIR/generated" 2>/dev/null || true
  rm -rf "$RUNTIME_DIR/tmp" 2>/dev/null || true

  mkdir -p "$RUNTIME_DIR" "$BIN_DIR" "$LOG_DIR"
}
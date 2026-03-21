#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="clash-for-linux"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_DIR="${CLASH_INSTALL_DIR:-$(cd "$(dirname "$0")" && pwd)}"

CLASHCTL_LINK="/usr/local/bin/clashctl"
PROFILED_FILE="/etc/profile.d/clash-for-linux.sh"

PURGE=false

for arg in "$@"; do
  case "$arg" in
    --purge)
      PURGE=true
      ;;
    *)
      echo "[ERROR] Unknown arg: $arg" >&2
      echo "Usage: uninstall.sh [--purge]" >&2
      exit 2
      ;;
  esac
done

log()   { printf "%b\n" "$*"; }
ok()    { log "\033[32m[OK]\033[0m $*"; }
warn()  { log "\033[33m[WARN]\033[0m $*"; }
err()   { log "\033[31m[ERROR]\033[0m $*"; }

if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限执行卸载"
  exit 1
fi

echo "[INFO] uninstalling clash-for-linux..."

# =========================
# 停止服务
# =========================
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  systemctl disable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
fi

# =========================
# 停止进程（仅当前项目）
# =========================
PID_FILE="${INSTALL_DIR}/runtime/clash.pid"

if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"

  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    echo "[INFO] stopping pid=$PID"
    kill "$PID" 2>/dev/null || true
    sleep 1

    if kill -0 "$PID" 2>/dev/null; then
      echo "[WARN] force kill -9 $PID"
      kill -9 "$PID" 2>/dev/null || true
    fi
  fi

  rm -f "$PID_FILE"
fi

# =========================
# 删除 systemd
# =========================
if [ -f "$UNIT_PATH" ]; then
  rm -f "$UNIT_PATH"
  ok "removed systemd unit"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed >/dev/null 2>&1 || true
fi

# =========================
# 删除命令入口
# =========================
rm -f "$CLASHCTL_LINK" >/dev/null 2>&1 || true
rm -f "$PROFILED_FILE" >/dev/null 2>&1 || true

ok "removed command + env"

# =========================
# 删除安装目录
# =========================
if [ "$PURGE" = true ]; then
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    ok "removed install dir: $INSTALL_DIR"
  else
    warn "install dir not found: $INSTALL_DIR"
  fi
else
  warn "install dir preserved: $INSTALL_DIR"
  echo "run with --purge to remove it"
fi

echo
ok "uninstall complete"
#!/usr/bin/env bash

install_systemd_entry() {
  local unit_file
  unit_file="/etc/systemd/system/$(service_unit_name)"

  cat > "$unit_file" <<EOF
[Unit]
Description=clash-for-linux
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/clashctl start-direct
ExecStop=/usr/local/bin/clashctl stop-direct
ExecReload=/usr/local/bin/clashctl restart-direct
PIDFile=$RUNTIME_DIR/mihomo.pid
WorkingDirectory=$PROJECT_DIR
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$(service_unit_name)" >/dev/null 2>&1 || true

  write_runtime_value "RUNTIME_BACKEND" "systemd"
  write_runtime_value "INSTALL_SCOPE" "$INSTALL_SCOPE"
}

remove_systemd_entry() {
  local unit_file
  unit_file="/etc/systemd/system/$(service_unit_name)"

  if [ -f "$unit_file" ]; then
    systemctl disable "$(service_unit_name)" >/dev/null 2>&1 || true
    rm -f "$unit_file"
    systemctl daemon-reload || true
    success "已删除 systemd 服务：$(service_unit_name)"
  fi
}

systemd_service_start() {
  systemctl start "$(service_unit_name)"
}

systemd_service_stop() {
  systemctl stop "$(service_unit_name)" >/dev/null 2>&1 || true
}

systemd_service_restart() {
  systemctl restart "$(service_unit_name)"
}

systemd_service_status_text() {
  if systemctl is-active --quiet "$(service_unit_name)"; then
    echo "运行中"
    systemctl show "$(service_unit_name)" --property MainPID --value 2>/dev/null | awk '{print "进程号：" $1}'
  else
    echo "未运行"
  fi
}

systemd_service_logs() {
  journalctl -u "$(service_unit_name)" -n 200 --no-pager 2>/dev/null || {
    echo "未获取到 systemd 服务日志"
    return 0
  }
}
#!/usr/bin/env bash

# shellcheck source=scripts/core/common.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/common.sh"
# shellcheck source=scripts/core/runtime.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/runtime.sh"
# shellcheck source=scripts/core/config.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/config.sh"

ensure_git_ready() {
  command -v git >/dev/null 2>&1 || die "当前系统缺少 git"

  git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "当前目录不是 Git 仓库：$PROJECT_DIR"
}

current_git_branch() {
  git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null
}

update_branch() {
  local branch

  branch="$(read_env_value "CLASH_UPDATE_BRANCH" 2>/dev/null || true)"
  if [ -n "${branch:-}" ]; then
    echo "$branch"
    return 0
  fi

  current_git_branch
}

git_has_local_changes() {
  [ -n "$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]
}

git_remote_name() {
  echo "${CLASH_GIT_REMOTE:-origin}"
}

sync_runtime_dependencies() {
  ensure_dashboard_deploy_prerequisites
  resolve_yq
  resolve_runtime_kernel
  resolve_subconverter
  install_local_dashboard_assets
  ensure_controller_secret >/dev/null
}

remove_mihomo_binary() {
  rm -f "$(mihomo_bin)" 2>/dev/null || true
}

remove_clash_binary() {
  rm -f "$(clash_bin)" 2>/dev/null || true
}

upgrade_runtime_kernel() {
  local target_kernel="${1:-}"
  local verbose="${2:-false}"
  local was_running="false"

  target_kernel="$(normalize_kernel_type "${target_kernel:-$(runtime_kernel_type)}")"

  if status_is_running 2>/dev/null; then
    was_running="true"
  fi

  write_runtime_kernel_type "$target_kernel"

  if [ "$verbose" = "true" ]; then
    info "当前架构：$(get_arch)"
    info "目标内核：$target_kernel"
    case "$target_kernel" in
      mihomo)
        info "目标版本：${MIHOMO_VERSION:-$DEFAULT_MIHOMO_VERSION}"
        ;;
      clash)
        info "目标版本：${CLASH_VERSION:-$DEFAULT_CLASH_VERSION}"
        ;;
    esac
  fi

  case "$target_kernel" in
    mihomo)
      info "正在升级 mihomo 内核"
      remove_mihomo_binary
      resolve_mihomo
      [ -x "$(mihomo_bin)" ] || die "mihomo 内核升级失败"
      ;;
    clash)
      info "正在升级 clash 内核"
      remove_clash_binary
      resolve_clash
      [ -x "$(clash_bin)" ] || die "clash 内核升级失败"
      ;;
    *)
      die "未知内核类型：$target_kernel"
      ;;
  esac

  if [ "$was_running" = "true" ]; then
    info "检测到当前内核正在运行，正在重启服务"
    service_restart
    success "内核升级成功，已重启生效"
  else
    success "内核升级成功"
  fi
}

update_project_code() {
  local force_mode="$1"
  local regenerate_mode="$2"
  local remote_name branch

  ensure_git_ready

  remote_name="$(git_remote_name)"
  branch="$(update_branch)"

  [ -n "${branch:-}" ] || die "无法识别当前分支"

  info "远程仓库：$remote_name"
  info "更新分支：$branch"

  if git_has_local_changes && [ "$force_mode" != "true" ]; then
    die "检测到本地有未提交改动，请先提交，或使用 clashctl update --force"
  fi

  info "正在获取最新代码"
  git -C "$PROJECT_DIR" fetch "$remote_name" "$branch" || die "获取远程代码失败"

  if git_has_local_changes && [ "$force_mode" = "true" ]; then
    warn "检测到本地改动，正在强制覆盖"
    git -C "$PROJECT_DIR" reset --hard "$remote_name/$branch" || die "强制覆盖失败"
  else
    git -C "$PROJECT_DIR" reset --hard "$remote_name/$branch" || die "更新失败"
  fi

  success "代码已更新到最新版本"

  sync_runtime_dependencies

  if [ "$regenerate_mode" = "true" ]; then
    regenerate_config
  fi

  success "更新完成"
}

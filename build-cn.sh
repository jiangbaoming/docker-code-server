#!/usr/bin/env bash
# ============================================================================
# 国内网络快速构建 code-server 镜像（使用 Dockerfile.cn）
#
# 用法：
#   ./build-cn.sh                                   # 默认 aliyun + ghfast.top
#   MIRROR=ustc ./build-cn.sh                       # 换 apt 源
#   CODE_RELEASE=4.146.0 ./build-cn.sh              # 固定版本（跳过探测）
#   IMAGE=myuser/code-server:local ./build-cn.sh    # 自定义镜像名
#   GHPROXY= ./build-cn.sh                          # 关闭 GitHub 代理
#   BASE_IMAGE=ghcr.nju.edu.cn/linuxserver/baseimage-ubuntu:noble ./build-cn.sh
#   ./build-cn.sh --no-cache                        # 额外参数透传给 docker build
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")"

# ---- 可覆盖参数 ----
MIRROR="${MIRROR:-aliyun}"                                  # official|aliyun|ustc|tuna
GHPROXY="${GHPROXY:-https://ghfast.top/}"                   # GitHub Release 加速前缀
CODE_RELEASE="${CODE_RELEASE:-}"                            # 留空则自动探测最新版
IMAGE="${IMAGE:-jiangming/code-server:latest}"              # 目标镜像名（可覆盖）
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/linuxserver/baseimage-ubuntu:noble}"
APT_MIRROR_HOST="${APT_MIRROR_HOST:-}"                      # 自定义 apt 域名（优先）
DOCKERFILE="${DOCKERFILE:-Dockerfile.cn}"

# ---- 架构检查（Dockerfile.cn 仅 amd64）----
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) ;;
  *) echo "错误：${DOCKERFILE} 目前仅支持 amd64，当前架构 ${ARCH}" >&2; exit 1 ;;
esac

if [[ ! -f "${DOCKERFILE}" ]]; then
  echo "错误：找不到 ${DOCKERFILE}" >&2
  exit 1
fi

# ---- 未指定版本则探测 code-server 最新版 ----
if [[ -z "${CODE_RELEASE}" ]]; then
  echo ">>> 未指定 CODE_RELEASE，尝试探测最新版..."
  # 首选：从 releases/latest 的 302 跳转取 tag（不走 API，避免限流）
  CODE_RELEASE="$(curl -sI --max-time 20 https://github.com/coder/code-server/releases/latest 2>/dev/null \
    | tr -d '\r' | awk -F'/tag/v' '/^[Ll]ocation:/{print $2; exit}')"
  # 兜底：GitHub API
  if [[ -z "${CODE_RELEASE}" ]]; then
    raw="$(curl -fsSL --max-time 20 https://api.github.com/repos/coder/code-server/releases/latest 2>/dev/null || true)"
    CODE_RELEASE="$(printf '%s' "${raw}" | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p' | head -1)"
  fi
  if [[ -z "${CODE_RELEASE}" ]]; then
    echo "错误：探测失败（网络/限流），请显式指定，如：CODE_RELEASE=4.146.0 ./build-cn.sh" >&2
    exit 1
  fi
  echo ">>> 探测到版本：${CODE_RELEASE}"
fi

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo ">>> 构建参数"
echo "    DOCKERFILE      = ${DOCKERFILE}"
echo "    BASE_IMAGE      = ${BASE_IMAGE}"
echo "    MIRROR          = ${MIRROR}"
echo "    APT_MIRROR_HOST = ${APT_MIRROR_HOST:-<未设置>}"
echo "    GHPROXY         = ${GHPROXY:-<官方>}"
echo "    CODE_RELEASE    = ${CODE_RELEASE}"
echo "    IMAGE           = ${IMAGE}"
echo "    BUILD_DATE      = ${BUILD_DATE}"
echo

docker build \
  -f "${DOCKERFILE}" \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg MIRROR="${MIRROR}" \
  --build-arg APT_MIRROR_HOST="${APT_MIRROR_HOST}" \
  --build-arg GHPROXY="${GHPROXY}" \
  --build-arg CODE_RELEASE="${CODE_RELEASE}" \
  --build-arg VERSION="${CODE_RELEASE}" \
  --build-arg BUILD_DATE="${BUILD_DATE}" \
  -t "${IMAGE}" \
  "$@" \
  .

echo
echo ">>> 构建完成：${IMAGE}"
echo ">>> 运行示例："
cat <<EOF
docker run -d --name code-server \\
  -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \\
  -v /path/to/config:/config \\
  -v /var/run/docker.sock:/var/run/docker.sock \\
  -p 8443:8443 \\
  ${IMAGE}
EOF

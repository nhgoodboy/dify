#!/usr/bin/env bash

# 如果脚本被 sh 调用，自动切换到 bash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# 遇到错误立即退出；未定义变量报错；管道错误导致脚本失败
set -euo pipefail

# ---------- 参数解析 ----------
# 用法： dify-save-images.sh [compose-files...] [-o output.tar]
#   compose-files : 一个或多个 compose yml 路径，默认同时使用 ./docker-compose.yaml 与 ./docker-compose.middleware.yaml
#   -o output.tar : 指定保存文件名

# ---------------- 参数解析 ----------------

# 默认 compose 文件列表
DEFAULT_COMPOSE=(docker-compose.yaml docker-compose.middleware.yaml)

OUTPUT_TAR=""
COMPOSE_FILES=()

while (( "$#" )); do
  case "$1" in
    -o|--output)
      shift
      OUTPUT_TAR="$1"
      ;;
    -* )
      echo "[ERROR] 未知参数: $1" >&2; exit 1 ;;
    * )
      # 去重添加
      for existing in "${COMPOSE_FILES[@]}"; do
          [[ "$existing" == "$1" ]] && continue 2
      done
      COMPOSE_FILES+=("$1")
      ;;
  esac
  shift
done

# 若未指定 compose 文件，则使用默认值中存在的文件
if [ ${#COMPOSE_FILES[@]} -eq 0 ]; then
  for f in "${DEFAULT_COMPOSE[@]}"; do
    [ -f "$f" ] && COMPOSE_FILES+=("$f")
  done
fi

if [ ${#COMPOSE_FILES[@]} -eq 0 ]; then
  echo "[ERROR] 未找到任何 compose 文件，请在当前目录放置 docker-compose.yaml 或使用参数指定。" >&2
  exit 1
fi

# 生成 -f 参数串
COMPOSE_ARGS=( )
for f in "${COMPOSE_FILES[@]}"; do
  COMPOSE_ARGS+=( -f "$f" )
done

# 生成输出文件名
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_TAR="${OUTPUT_TAR:-dify_images_${TIMESTAMP}.tar}"

# ---------- 主流程 ----------
echo "[INFO] 正在收集 ${COMPOSE_FILES[@]} 引用的镜像列表…"

# -------- 拉取 / 构建镜像 --------
echo "[INFO] 拉取已有镜像并构建本地镜像（如有 build）…"
docker compose "${COMPOSE_ARGS[@]}" pull --ignore-pull-failures
docker compose "${COMPOSE_ARGS[@]}" build --pull --parallel

# -------- 解析最终配置，获取镜像引用 --------
# 依赖 jq 进行解析
if ! command -v jq >/dev/null 2>&1; then
  echo "[ERROR] jq 未安装，无法解析 compose 配置。请先安装 jq，或手动指定镜像列表。" >&2
  exit 1
fi

TMP_JSON=$(mktemp)
docker compose "${COMPOSE_ARGS[@]}" config --format json > "$TMP_JSON"

# 收集所有 services 的 image 字段，去重
mapfile -t IMG_REFS < <(jq -r '.services[].image // empty' "$TMP_JSON" | sort -u)

# 清理临时文件
rm -f "$TMP_JSON"

if [ ${#IMG_REFS[@]} -eq 0 ]; then
  echo "[ERROR] 未找到任何镜像，请确认 compose 文件包含 image 字段，且镜像可用。" >&2
  exit 1
fi

echo "[INFO] 共 ${#IMG_REFS[@]} 张镜像，将保存到 ${OUTPUT_TAR}"

docker save "${IMG_REFS[@]}" -o "${OUTPUT_TAR}"

echo "[SUCCESS] 镜像已保存：${OUTPUT_TAR}" 
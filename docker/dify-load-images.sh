#!/usr/bin/env bash

# 如果脚本被 sh 调用，自动切换到 bash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# 遇到错误立即退出；未定义变量报错；管道错误导致脚本失败
set -euo pipefail

# ---------- 参数解析 ----------
# 用法： dify-load-images.sh [images.tar]
#   images.tar : 镜像包路径，默认为 dify_images_*.tar

# 查找最新的镜像备份文件
shopt -s nullglob
CANDIDATE_FILES=(dify_images_*.tar)
shopt -u nullglob

if [ ${#CANDIDATE_FILES[@]} -eq 0 ] && [ -z "${1:-}" ]; then
    echo "[ERROR] 在当前目录找不到 dify_images_*.tar 文件，请通过参数指定路径。" >&2
    exit 1
fi

# 如果提供了参数，则使用参数；否则，使用找到的最新文件
INPUT_TAR="${1:-$(ls -t dify_images_*.tar | head -n 1)}"

if [ ! -f "${INPUT_TAR}" ]; then
    echo "[ERROR] 镜像文件不存在: ${INPUT_TAR}" >&2
    exit 1
fi

echo "[INFO] 准备从 ${INPUT_TAR} 加载镜像..."

# ---------- 主流程 ----------
# 1. 加载镜像
docker load -i "${INPUT_TAR}"

echo "[INFO] 镜像加载完成。"

# 2. 修复 Podman 环境下自动添加的 'localhost/' 前缀并清理
echo "[INFO] 正在检查并修复镜像标签..."

# 使用 grep 替代 filter，更可靠地找出所有以 "localhost/" 开头的镜像
mapfile -t LOCALHOST_IMAGES < <(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^localhost/" || true)

if [ ${#LOCALHOST_IMAGES[@]} -eq 0 ]; then
    echo "[INFO] 未发现需要修复的 'localhost/' 标签，操作完成。"
    exit 0
fi

echo "[INFO] 发现 ${#LOCALHOST_IMAGES[@]} 个需要修复的镜像..."

for full_image_name in "${LOCALHOST_IMAGES[@]}"; do
    # 去掉 "localhost/" 前缀
    short_name="${full_image_name#localhost/}"
    
    # 强制添加 docker.io/ 前缀，构成全限定名称以兼容 Podman
    # 注意：这个逻辑假设所有被加了 localhost/ 前缀的镜像都源自 docker.io
    correct_image_name="docker.io/${short_name}"
    
    echo "  - 正在修复: ${full_image_name}"
    echo "    - 添加新标签: ${correct_image_name}"
    docker tag "${full_image_name}" "${correct_image_name}"
    
    echo "    - 移除旧标签: ${full_image_name}"
    docker rmi "${full_image_name}" >/dev/null 2>&1 || true
done

echo "[SUCCESS] 所有镜像标签已修复并清理完毕。"
echo "现在可以正常使用 docker compose up 启动服务了。" 
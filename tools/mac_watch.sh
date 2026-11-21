#!/bin/bash
# 自动循环：每 20 秒看一眼 GitHub，main 有新提交就重新编译并回报结果。
# 用法（在仓库根目录）：  bash tools/mac_watch.sh       按 Ctrl+C 停止
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1
echo "👀 开始监听 main 分支，有新提交会自动编译。按 Ctrl+C 停止。"
while true; do
  git fetch -q origin main 2>/dev/null
  LATEST=$(git rev-parse --short origin/main 2>/dev/null)
  LAST=$(cat "$REPO/.ci-build-last" 2>/dev/null)
  if [ -n "$LATEST" ] && [ "$LATEST" != "$LAST" ]; then
    echo ""
    echo "──── $(date '+%H:%M:%S') 发现新提交 $LATEST ────"
    bash "$REPO/tools/mac_build_report.sh"
  fi
  sleep 20
done

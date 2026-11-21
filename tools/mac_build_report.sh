#!/bin/bash
# 在 Mac 上编译一次物灵，把结果（报错 / 截图）推到 GitHub 的 ci-feedback 分支，供 Claude 查看。
#
# 用法（在仓库根目录）：  bash tools/mac_build_report.sh
# 一般不用直接运行，用 tools/mac_watch.sh 自动循环。
#
# 不会动你自己的工作目录：代码检出到 .ci-build/，结果写在 .ci-feedback/。
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1
BUILD_DIR="$REPO/.ci-build"
FEEDBACK_DIR="$REPO/.ci-feedback"
DERIVED="$REPO/.ci-build-derived"
mkdir -p "$DERIVED"

echo "▶ 拉取最新代码"
git fetch -q origin main ci-feedback || { echo "git fetch 失败，检查网络和 GitHub 登录"; exit 1; }

# 1. 检出 origin/main 到独立目录
if [ ! -d "$BUILD_DIR" ]; then
  git worktree add -q --detach "$BUILD_DIR" origin/main
else
  git -C "$BUILD_DIR" checkout -q --force --detach origin/main
  git -C "$BUILD_DIR" clean -qfd
fi
COMMIT=$(git -C "$BUILD_DIR" rev-parse --short HEAD)

# 2. 结果目录（ci-feedback 分支）
if [ ! -d "$FEEDBACK_DIR" ]; then
  git worktree add -q -B ci-feedback "$FEEDBACK_DIR" origin/ci-feedback
else
  git -C "$FEEDBACK_DIR" fetch -q origin ci-feedback
  git -C "$FEEDBACK_DIR" reset -q --hard origin/ci-feedback
fi
OUT="$FEEDBACK_DIR/feedback"
rm -rf "$OUT"; mkdir -p "$OUT/screens"

# 3. 选模拟器：环境变量 SIM_NAME，或者第一台可用的 iPhone
if [ -z "${SIM_NAME:-}" ]; then
  SIM_NAME=$(xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^[[:space:]]+//; s/ \(.*$//')
fi
echo "▶ 编译 $COMMIT（模拟器：$SIM_NAME）"
LOG="$OUT/xcodebuild.log"
xcodebuild -project "$BUILD_DIR/Wuling.xcodeproj" -scheme Wuling -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build > "$LOG" 2>&1
STATUS=$?

# 报错整理成相对路径，去重
grep -E "(error|fatal error):" "$LOG" | sed "s#$BUILD_DIR/##g" | sort -u > "$OUT/errors.txt"
grep -E "warning:" "$LOG" | sed "s#$BUILD_DIR/##g" | sort -u | head -100 > "$OUT/warnings.txt"
tail -60 "$LOG" | sed "s#$BUILD_DIR/##g" > "$OUT/build-tail.txt"
# 完整日志太大，只保留尾部
mv "$OUT/build-tail.txt" "$OUT/build-tail.txt.tmp"; rm -f "$LOG"; mv "$OUT/build-tail.txt.tmp" "$OUT/build-tail.txt"

if [ $STATUS -eq 0 ]; then
  RESULT="success"
  echo "✅ 编译成功，启动模拟器截图"
  APP="$DERIVED/Build/Products/Debug-iphonesimulator/Wuling.app"
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
  xcrun simctl boot "$SIM_NAME" 2>/dev/null
  xcrun simctl bootstatus "$SIM_NAME" -b > /dev/null 2>&1
  xcrun simctl uninstall "$SIM_NAME" "$BUNDLE_ID" 2>/dev/null
  xcrun simctl install "$SIM_NAME" "$APP"

  shot() {  # shot <名字> <light|dark> [启动参数...]
    local name=$1 mode=$2; shift 2
    xcrun simctl ui "$SIM_NAME" appearance "$mode"
    xcrun simctl terminate "$SIM_NAME" "$BUNDLE_ID" 2>/dev/null
    xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID" ${@+"$@"} > /dev/null 2>&1
    sleep 5
    xcrun simctl io "$SIM_NAME" screenshot --type=png "$OUT/screens/$name.png" > /dev/null 2>&1
  }
  shot "1-empty-light" light
  shot "2-collection-light" light -demo-data
  shot "3-collection-dark" dark -demo-data
  xcrun simctl ui "$SIM_NAME" appearance light
  # 30 秒后崩溃检查：进程还在说明没闪退
  if xcrun simctl spawn "$SIM_NAME" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "running" > "$OUT/app-state.txt"
  else
    echo "not running (可能闪退了)" > "$OUT/app-state.txt"
  fi
else
  RESULT="failure"
  echo "❌ 编译失败，$(wc -l < "$OUT/errors.txt" | tr -d ' ') 条错误"
fi

cat > "$OUT/STATUS.md" <<STATUS_EOF
commit: $COMMIT
result: $RESULT
simulator: $SIM_NAME
xcode: $(xcodebuild -version | head -1)
time: $(date '+%Y-%m-%d %H:%M:%S')
errors: $(wc -l < "$OUT/errors.txt" | tr -d ' ')
STATUS_EOF

git -C "$FEEDBACK_DIR" add -A
git -C "$FEEDBACK_DIR" commit -q -m "Build $COMMIT: $RESULT" || true
if git -C "$FEEDBACK_DIR" push -q origin ci-feedback; then
  echo "▶ 结果已推送到 GitHub（ci-feedback 分支）"
else
  echo "⚠️  推送失败：这台 Mac 需要能 push 到 GitHub（见 README）"
fi
echo "$COMMIT" > "$REPO/.ci-build-last"

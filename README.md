# ci-feedback

这个分支只用来存放 Mac 上自动编译的结果，由 `tools/mac_build_report.sh` 写入。不要往这里提交代码。

- `feedback/STATUS.md`：最近一次编译的提交、结果、时间
- `feedback/errors.txt`：编译错误
- `feedback/warnings.txt`：警告（前 100 条）
- `feedback/build-tail.txt`：编译日志的最后 60 行
- `feedback/screens/`：编译成功后的模拟器截图

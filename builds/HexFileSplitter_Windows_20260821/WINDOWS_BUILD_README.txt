HEX 文件拆分工具：Windows 10 EXE 构建说明
============================================

一、准备环境

1. 使用 Windows 10 或 Windows 11 64 位系统。
2. 安装 64 位 Python 3.12 或 Python 3.13：
   https://www.python.org/downloads/windows/
3. 安装时勾选“Add Python to PATH”。
4. Python 安装器中的 Tcl/Tk and IDLE 保持默认选中。


二、一键生成 EXE

1. 解压整个构建包，不要只单独解压批处理文件。
2. 双击 build_windows.bat。
3. 首次构建会自动下载 PyInstaller 和 tkinterdnd2，请保持联网。
4. 构建成功后，程序位于：

   dist\HexFileSplitter.exe


三、分发和使用

- HexFileSplitter.exe 是单文件程序。
- 可复制到其他 Windows 10/11 64 位电脑使用。
- 目标电脑不需要安装 Python。
- 支持拖入 HEX 文件、选择输入文件和选择输出目录。


四、注意事项

- 程序未使用商业代码签名证书。Windows SmartScreen 可能在首次运行时
  显示“Windows 已保护你的电脑”，可点击“更多信息”检查程序名称后运行。
- 部分杀毒软件会对自制的 PyInstaller 单文件程序进行额外扫描，这是无签名
  可执行文件的常见现象。建议只分发由你自己构建的 EXE。
- 重新运行 build_windows.bat 会覆盖 dist 目录中的同名程序。
- 构建产生的 .build-venv、build 和 dist 目录均可删除；删除后不影响已经
  复制出去的 HexFileSplitter.exe。

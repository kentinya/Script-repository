@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

echo ========================================
echo        HEX 文件拆分工具 EXE 构建
echo ========================================
echo.

set "PYTHON_CMD="
where py >nul 2>&1
if not errorlevel 1 set "PYTHON_CMD=py -3"

if not defined PYTHON_CMD (
    where python >nul 2>&1
    if not errorlevel 1 set "PYTHON_CMD=python"
)

if not defined PYTHON_CMD goto no_python

echo [1/4] 检查 Python...
%PYTHON_CMD% --version
if errorlevel 1 goto failed

echo.
echo [2/4] 创建独立构建环境...
if not exist ".build-venv\Scripts\python.exe" (
    %PYTHON_CMD% -m venv ".build-venv"
    if errorlevel 1 goto failed
)
call ".build-venv\Scripts\activate.bat"
if errorlevel 1 goto failed

echo.
echo [3/4] 安装构建依赖...
python -m pip install --upgrade pip
if errorlevel 1 goto failed
python -m pip install "pyinstaller>=6.0" "tkinterdnd2>=0.4.2"
if errorlevel 1 goto failed

echo.
echo [4/4] 生成单文件 EXE...
python -m PyInstaller --noconfirm --clean "hex_file_splitter_gui.spec"
if errorlevel 1 goto failed

echo.
echo ========================================
echo 构建成功！
echo EXE 位置：%~dp0dist\HexFileSplitter.exe
echo ========================================
echo.
pause
exit /b 0

:no_python
echo.
echo 未检测到 Python。
echo 请安装 64 位 Python 3.12 或 3.13，并勾选 Add Python to PATH。
echo 下载地址：https://www.python.org/downloads/windows/
echo.
pause
exit /b 1

:failed
echo.
echo ========================================
echo 构建失败，请查看上方错误信息。
echo ========================================
echo.
pause
exit /b 1

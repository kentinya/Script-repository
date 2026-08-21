# -*- mode: python ; coding: utf-8 -*-

from PyInstaller.utils.hooks import collect_all


# tkinterdnd2 包含拖放功能所需的 Tcl/Tk 动态库和脚本，必须显式收集。
dnd_datas, dnd_binaries, dnd_hiddenimports = collect_all("tkinterdnd2")

a = Analysis(
    ["hex_file_splitter_gui.py"],
    pathex=[],
    binaries=dnd_binaries,
    datas=dnd_datas,
    hiddenimports=dnd_hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="HexFileSplitter",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

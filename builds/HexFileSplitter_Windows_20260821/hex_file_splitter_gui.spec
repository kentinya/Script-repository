# -*- mode: python ; coding: utf-8 -*-

import sys
from pathlib import Path

from PyInstaller.utils.hooks import collect_all


# tkinterdnd2 包含拖放功能所需的 Tcl/Tk 动态库和脚本，必须显式收集。
dnd_datas, dnd_binaries, dnd_hiddenimports = collect_all("tkinterdnd2")


def collect_runtime_tree(source_dir, destination_dir):
    """Collect a complete runtime data tree with stable bundle paths."""
    return [
        (
            str(path),
            str(Path(destination_dir) / path.parent.relative_to(source_dir)),
        )
        for path in source_dir.rglob("*")
        if path.is_file()
    ]


# PyInstaller normally discovers these directories through hook-_tkinter.py.
# Explicit collection avoids one-file builds that contain the Tcl/Tk DLLs but
# omit init.tcl/tk.tcl on some Windows Python distributions.
tcl_root = Path(sys.base_prefix) / "tcl"
tcl_library = next(
    (path for path in tcl_root.glob("tcl*") if (path / "init.tcl").is_file()),
    None,
)
tk_library = next(
    (path for path in tcl_root.glob("tk*") if (path / "tk.tcl").is_file()),
    None,
)

if tcl_library is None or tk_library is None:
    raise RuntimeError(
        f"Unable to locate Tcl/Tk runtime data below {tcl_root}. "
        "Install Python with Tcl/Tk support before building."
    )

tcl_tk_datas = collect_runtime_tree(tcl_library, "_tcl_data")
tcl_tk_datas += collect_runtime_tree(tk_library, "_tk_data")

a = Analysis(
    ["hex_file_splitter_gui.py"],
    pathex=[],
    binaries=dnd_binaries,
    datas=dnd_datas + tcl_tk_datas,
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

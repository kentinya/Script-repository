"""Reconstruct v5.6 Python modules from the verified v5.4 baseline."""
from pathlib import Path
import base64
import hashlib
import json
import lzma

parts = sorted(Path("codecompare-build").glob("v56p_*.b64"))
assert len(parts) == 12, f"Expected 12 source patch parts, found {len(parts)}"
blob = "".join(part.read_text(encoding="ascii").strip() for part in parts)
patch = json.loads(lzma.decompress(base64.b64decode(blob)))
EXPECTED = {
    "code_compare_gui.py": "0f18118cdc96ad2e12c5b9b1aef35a05797cb207ec6ee84353844f4b122e6007",
    "code_compare_core.py": "1deb160b2c6a6903e13321bea233ec877c36457e5d3a0679b210cdef5ddff5bb",
    "content_diff.py": "6fd6e271e8020cf11695f8548b6286140be1976a17706ca95b11740726498aed",
    "report_export.py": "035722e983ad0bc3eb0b41939cf8cc7edad3f89b9be400173ee5f28b1958eea1",
}
for name, ops in patch.items():
    old_lines = [] if name == "content_diff.py" else Path(name).read_text(encoding="utf-8").splitlines(keepends=True)
    source = "".join("".join(old_lines[op[1]:op[2]]) if op[0] == 0 else op[1] for op in ops)
    Path(name).write_text(source, encoding="utf-8", newline="")
    digest = hashlib.sha256(Path(name).read_bytes()).hexdigest()
    print(f"{name}: sha256:{digest}", flush=True)
    if digest != EXPECTED[name]:
        raise RuntimeError(f"{name} differs from tested v5.6 source!")
print("v5.6 source modules rebuilt", flush=True)

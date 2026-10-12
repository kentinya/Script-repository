#!/usr/bin/env python3
"""Offline regression: TLS 1.3 + h2 is accepted by the real tls_probe function."""
import ast
import pathlib
import re
import ssl
from types import SimpleNamespace

source = pathlib.Path(__file__).resolve().parents[1].joinpath("xray-manager.sh").read_text(encoding="utf-8")
match = re.search(r"<<'PY_REALITY_TARGET'\n(.*?)\nPY_REALITY_TARGET(?:\n|$)", source, re.S)
assert match, "REALITY target probe heredoc not found"
tree = ast.parse(match.group(1))
fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "tls_probe"), None)
assert fn is not None, "tls_probe function not found"
code = compile(ast.Module(body=[fn], type_ignores=[]), "tls_probe", "exec")

state = {"version": "TLSv1.3", "alpn": "h2"}

class FakeSocket:
    def __enter__(self):
        return self
    def __exit__(self, *_):
        return False
    def settimeout(self, _timeout):
        pass
    def connect(self, _address):
        pass

class FakeTLS:
    def __enter__(self):
        return self
    def __exit__(self, *_):
        return False
    def version(self):
        return state["version"]
    def selected_alpn_protocol(self):
        return state["alpn"]

ctx = SimpleNamespace(wrap_socket=lambda sock, server_hostname: FakeTLS())
mock_socket = SimpleNamespace(SOCK_STREAM=1, socket=lambda family, kind: FakeSocket())
namespace = {
    "ctx": ctx,
    "socket": mock_socket,
    "ssl": ssl,
    "addresses": lambda host, port: [(2, ("203.0.113.7", port), "203.0.113.7")],
}
exec(code, namespace)
probe = namespace["tls_probe"]

assert probe("example.org", 443, "example.org") == "203.0.113.7"

for version, alpn in [("TLSv1.2", "h2"), ("TLSv1.3", "http/1.1")]:
    state.update(version=version, alpn=alpn)
    try:
        probe("example.org", 443, "example.org")
    except ValueError:
        pass
    else:
        raise AssertionError(f"Invalid TLS/ALPN was accepted: {version}, {alpn}")
print("TLS 1.3 + h2 allowed; TLS 1.2 or non-h2 rejected")

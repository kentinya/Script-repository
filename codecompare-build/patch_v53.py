from pathlib import Path

p = Path("code_compare_core.py")
s = p.read_text(encoding="utf-8")
start = s.index("def compare_directories(")
helper = s.find("def _build_file_pairs(")
if helper != -1 and helper < start:
    start = helper
end = s.index("def generate_side_by_side_diff(", start)
new = r'''def _build_file_pairs(
    left_files: dict[str, Path],
    right_files: dict[str, Path],
) -> list[tuple[str, Path | None, Path | None]]:
    """
    Build file pairs in two passes:
    1. Match identical relative paths first.
    2. For still-unmatched files, match by basename only when that basename is
       unique on BOTH sides.
    """
    pairs: list[tuple[str, Path | None, Path | None]] = []
    left_remaining = dict(left_files)
    right_remaining = dict(right_files)

    common = sorted(set(left_remaining) & set(right_remaining))
    for rel in common:
        pairs.append((rel, left_remaining.pop(rel), right_remaining.pop(rel)))

    left_by_name: dict[str, list[str]] = {}
    right_by_name: dict[str, list[str]] = {}
    for rel in left_remaining:
        left_by_name.setdefault(Path(rel).name.lower(), []).append(rel)
    for rel in right_remaining:
        right_by_name.setdefault(Path(rel).name.lower(), []).append(rel)

    fallback_pairs: list[tuple[str, str]] = []
    for name in sorted(set(left_by_name) & set(right_by_name)):
        lc = left_by_name[name]
        rc = right_by_name[name]
        if len(lc) == 1 and len(rc) == 1:
            fallback_pairs.append((lc[0], rc[0]))

    for left_rel, right_rel in sorted(fallback_pairs):
        left_path = left_remaining.pop(left_rel)
        right_path = right_remaining.pop(right_rel)
        pairs.append((f"{left_rel}  <->  {right_rel}", left_path, right_path))

    for rel in sorted(left_remaining):
        pairs.append((rel, left_remaining[rel], None))
    for rel in sorted(right_remaining):
        pairs.append((rel, None, right_remaining[rel]))
    return pairs


def compare_directories(
    left_root: Path,
    right_root: Path,
    extensions: set[str] | None = None,
    ignore_whitespace: bool = False,
    ignore_case: bool = False,
) -> list[CompareResult]:
    left_files = collect_files(left_root, extensions)
    right_files = collect_files(right_root, extensions)
    file_pairs = _build_file_pairs(left_files, right_files)
    results: list[CompareResult] = []

    for relative_path, left_path, right_path in file_pairs:
        if left_path is None:
            _right_lines, right_enc = read_text_file_with_encoding(right_path)
            results.append(CompareResult(relative_path, None, right_path, "RIGHT_ONLY", right_encoding=encoding_display_name(right_enc)))
            continue
        if right_path is None:
            _left_lines, left_enc = read_text_file_with_encoding(left_path)
            results.append(CompareResult(relative_path, left_path, None, "LEFT_ONLY", left_encoding=encoding_display_name(left_enc)))
            continue

        left_raw, left_enc = read_text_file_with_encoding(left_path)
        right_raw, right_enc = read_text_file_with_encoding(right_path)
        left_norm = normalize_lines(left_raw, ignore_whitespace, ignore_case)
        right_norm = normalize_lines(right_raw, ignore_whitespace, ignore_case)

        if left_norm == right_norm:
            results.append(CompareResult(relative_path, left_path, right_path, "SAME", left_encoding=encoding_display_name(left_enc), right_encoding=encoding_display_name(right_enc)))
            continue

        matcher = difflib.SequenceMatcher(None, left_norm, right_norm, autojunk=False)
        opcodes = list(matcher.get_opcodes())
        added, deleted, changed = count_diff(left_norm, right_norm)
        changed_symbols = detect_changed_symbols(left_path, right_path, opcodes, left_raw, right_raw)
        results.append(CompareResult(relative_path, left_path, right_path, "MODIFIED", added, deleted, changed, changed_symbols, encoding_display_name(left_enc), encoding_display_name(right_enc)))

    return results

'''
p.write_text(s[:start] + new + s[end:], encoding="utf-8")

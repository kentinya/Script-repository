"""Robustly patch CodeCompare v5.5 GUI regardless of minor text differences."""
from pathlib import Path

p = Path('code_compare_gui.py')
s = p.read_text(encoding='utf-8')
if 'def resolve_compare_targets(' in s:
    raise RuntimeError('v5.6 resolver is already present')

resolver = '''def resolve_compare_targets(old_path_text, new_path_text):
    """Use the actual paths to determine file vs folder mode."""
    def clean(value):
        value = value.strip()
        if len(value) > 1 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1].strip()
        return value

    old_text, new_text = clean(old_path_text), clean(new_path_text)
    if not old_text or not new_text:
        raise ValueError("请分别选择两个文件或文件夹。")
    left, right = Path(old_text).expanduser(), Path(new_text).expanduser()
    if not left.exists():
        raise ValueError(f"旧版本路径不存在或无法访问：\\n{left}")
    if not right.exists():
        raise ValueError(f"新版本路径不存在或无法访问：\\n{right}")
    if left.is_file() and right.is_file():
        return left, right, 'file'
    if left.is_dir() and right.is_dir():
        return left, right, 'folder'
    raise ValueError(f"两边必须都是文件或都是文件夹：\\n旧版本：{left}\\n新版本：{right}")


'''
anchor = 'class CodeCompareApp(tk.Tk):'
assert s.count(anchor) == 1, 'Cannot locate GUI app class'
s = s.replace(anchor, resolver + anchor, 1)
start = s.index('    def start_compare(self):')
body_start = s.index('        ignore_whitespace = ', start)
new_prefix = '''    def start_compare(self):
        if self._compare_running:
            return
        try:
            left, right, detected_mode = resolve_compare_targets(
                self.left_dir.get(), self.right_dir.get()
            )
        except ValueError as exc:
            messagebox.showerror("路径检查失败", str(exc))
            return
        # Compare actual selected paths; do not misinterpret .h files as folders.
        file_mode = detected_mode == 'file'
        if self.compare_mode.get() != detected_mode:
            self.compare_mode.set(detected_mode)
            self.left_source_label.config(text="旧版本文件：" if file_mode else "旧版本目录：")
            self.right_source_label.config(text="新版本文件：" if file_mode else "新版本目录：")

'''
s = s[:start] + new_prefix + s[body_start:]
s = s.replace('CodeCompare v5.5', 'CodeCompare v5.6')
if 'self.only_changed_files.set(False)' in s:
    s = s.replace('self.only_changed_files.set(False)',
                  'self.only_changed_files.set(False)\n            self.status_filter.set("全部")\n            self.search_var.set("")', 1)
p.write_text(s, encoding='utf-8', newline='')
print('v5.6 GUI auto-file-mode patch applied')

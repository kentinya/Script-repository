import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD

    DND_AVAILABLE = True
except ImportError:
    DND_FILES = None
    TkinterDnD = None
    DND_AVAILABLE = False


class HexFileSplitter:
    """按照固定地址范围拆分 Intel HEX 文件。"""

    RANGES = {
        "SB": (0x80000000, 0x8000FFFF),
        "CB": (0x80060000, 0x8009FFFF),
        "ASW0": (0x800A0000, 0x803FFFFF),
        "ASW1": (0x80400000, 0x805FFFFF),
        "DS0": (0x80C00000, 0x80CFFFFF),
    }

    def __init__(self, input_file, output_dir, log_callback=None):
        self.input_file = os.path.abspath(input_file)
        self.output_dir = os.path.abspath(output_dir)
        self.log_callback = log_callback or print
        self.records = []
        self.extended_linear_address = 0x0000

    def log(self, message):
        self.log_callback(str(message))

    def parse_hex_file(self):
        """解析 HEX 文件，提取所有记录。"""
        self.records.clear()
        self.extended_linear_address = 0x0000
        self.log(f"正在解析 HEX 文件：{self.input_file}")

        with open(self.input_file, "r") as file:
            for line_num, line in enumerate(file, 1):
                line = line.strip()
                if not line.startswith(":") or len(line) < 11:
                    continue

                try:
                    record_length = int(line[1:3], 16)
                    address = int(line[3:7], 16)
                    record_type = int(line[7:9], 16)
                    data = line[9 : 9 + 2 * record_length]
                    checksum = int(
                        line[9 + 2 * record_length : 11 + 2 * record_length], 16
                    )
                except ValueError as exc:
                    self.log(f"警告：第 {line_num} 行格式错误：{exc}")
                    continue

                calculated_checksum = self.calculate_checksum(
                    line[1 : 9 + 2 * record_length]
                )
                if calculated_checksum != checksum:
                    self.log(f"警告：第 {line_num} 行校验和错误")

                if record_type == 0x00:
                    full_address = (self.extended_linear_address << 16) + address
                    self.records.append(
                        {
                            "type": record_type,
                            "address": full_address,
                            "data": data,
                            "line": line,
                        }
                    )
                elif record_type == 0x04:
                    self.extended_linear_address = int(data, 16)
                    self.records.append({"type": record_type, "line": line})
                elif record_type in (0x01, 0x05):
                    self.records.append({"type": record_type, "line": line})

        data_record_count = sum(record["type"] == 0x00 for record in self.records)
        self.log(f"解析完成，共读取 {data_record_count} 条数据记录。")

    @staticmethod
    def calculate_checksum(data_str):
        """计算 HEX 记录的校验和。"""
        byte_count = len(data_str) // 2
        total = 0
        for index in range(byte_count):
            total += int(data_str[index * 2 : index * 2 + 2], 16)
        return (-total) & 0xFF

    def split_by_fixed_ranges(self):
        """根据固定的五个地址范围拆分 HEX 文件。"""
        os.makedirs(self.output_dir, exist_ok=True)
        input_stem = os.path.splitext(os.path.basename(self.input_file))[0]
        output_files = {}

        for range_name in self.RANGES:
            output_files[range_name] = {
                "filename": os.path.join(
                    self.output_dir, f"{input_stem}_{range_name}.hex"
                ),
                "records": [],
                "current_ela": None,
            }

        output_files["unknown"] = {
            "filename": os.path.join(
                self.output_dir, f"{input_stem}_unknown.hex"
            ),
            "records": [],
            "current_ela": None,
        }

        for record in self.records:
            if record["type"] == 0x00:
                assigned = False
                for range_name, (start_addr, end_addr) in self.RANGES.items():
                    if start_addr <= record["address"] <= end_addr:
                        self._append_data_record(output_files[range_name], record)
                        assigned = True
                        break

                if not assigned:
                    self._append_data_record(output_files["unknown"], record)

            elif record["type"] == 0x01:
                for file_info in output_files.values():
                    if file_info["records"]:
                        file_info["records"].append(record)

        created_files = []
        for range_name, file_info in output_files.items():
            if not file_info["records"]:
                continue
            self.write_hex_file(file_info["filename"], file_info["records"])
            created_files.append(file_info["filename"])
            self.log(f"已创建 [{range_name}]：{file_info['filename']}")

        return created_files

    def _append_data_record(self, file_info, record):
        current_ela = record["address"] >> 16
        if file_info["current_ela"] != current_ela:
            file_info["current_ela"] = current_ela
            file_info["records"].append(self.create_ela_record(current_ela))

        offset_address = record["address"] & 0xFFFF
        file_info["records"].append(
            self.create_data_record(offset_address, record["data"])
        )

    def create_ela_record(self, ela):
        """创建扩展线性地址记录。"""
        ela_hex = f"{ela:04X}"
        data_str = f"02000004{ela_hex}"
        checksum = self.calculate_checksum(data_str)
        return {"type": 0x04, "line": f":{data_str}{checksum:02X}"}

    def create_data_record(self, address, data):
        """创建数据记录。"""
        record_length = len(data) // 2
        address_hex = f"{address:04X}"
        data_str = f"{record_length:02X}{address_hex}00{data}"
        checksum = self.calculate_checksum(data_str)
        return {"type": 0x00, "line": f":{data_str}{checksum:02X}"}

    @staticmethod
    def write_hex_file(filename, records):
        """将记录写入 HEX 文件。"""
        with open(filename, "w") as file:
            for record in records:
                file.write(record["line"] + "\n")


class HexSplitterApp:
    def __init__(self):
        self.root = TkinterDnD.Tk() if DND_AVAILABLE else tk.Tk()
        self.root.title("HEX 文件拆分工具")
        self.root.geometry("780x610")
        self.root.minsize(680, 520)

        self.input_path = tk.StringVar()
        self.output_dir = tk.StringVar()
        self.status_text = tk.StringVar(value="请选择或拖入一个 HEX 文件")
        self.output_dir_manually_selected = False
        self.event_queue = queue.Queue()
        self.worker = None

        self._configure_style()
        self._build_ui()
        self._register_drop_target()
        self.root.after(100, self._process_events)

    def _configure_style(self):
        style = ttk.Style(self.root)
        if sys.platform == "darwin":
            style.theme_use("aqua")
        style.configure("Title.TLabel", font=("TkDefaultFont", 18, "bold"))
        style.configure("Drop.TLabel", font=("TkDefaultFont", 13))

    def _build_ui(self):
        main_frame = ttk.Frame(self.root, padding=20)
        main_frame.pack(fill="both", expand=True)
        main_frame.columnconfigure(0, weight=1)
        main_frame.rowconfigure(5, weight=1)

        ttk.Label(main_frame, text="HEX 文件拆分工具", style="Title.TLabel").grid(
            row=0, column=0, sticky="w", pady=(0, 14)
        )

        drop_text = "将 HEX 文件拖到这里\n或点击选择文件"
        if not DND_AVAILABLE:
            drop_text = "点击选择 HEX 文件\n安装 tkinterdnd2 后可启用拖放"

        self.drop_zone = ttk.Label(
            main_frame,
            text=drop_text,
            style="Drop.TLabel",
            anchor="center",
            justify="center",
            relief="groove",
            padding=24,
            cursor="hand2",
        )
        self.drop_zone.grid(row=1, column=0, sticky="ew", pady=(0, 16))
        self.drop_zone.bind("<Button-1>", lambda _event: self.choose_input_file())

        path_frame = ttk.LabelFrame(main_frame, text="输入与输出", padding=12)
        path_frame.grid(row=2, column=0, sticky="ew")
        path_frame.columnconfigure(1, weight=1)

        ttk.Label(path_frame, text="HEX 文件：").grid(
            row=0, column=0, sticky="w", padx=(0, 8), pady=5
        )
        ttk.Entry(path_frame, textvariable=self.input_path).grid(
            row=0, column=1, sticky="ew", pady=5
        )
        ttk.Button(path_frame, text="选择文件", command=self.choose_input_file).grid(
            row=0, column=2, padx=(8, 0), pady=5
        )

        ttk.Label(path_frame, text="输出目录：").grid(
            row=1, column=0, sticky="w", padx=(0, 8), pady=5
        )
        ttk.Entry(path_frame, textvariable=self.output_dir).grid(
            row=1, column=1, sticky="ew", pady=5
        )
        ttk.Button(path_frame, text="选择目录", command=self.choose_output_dir).grid(
            row=1, column=2, padx=(8, 0), pady=5
        )

        action_frame = ttk.Frame(main_frame)
        action_frame.grid(row=3, column=0, sticky="ew", pady=14)
        action_frame.columnconfigure(0, weight=1)

        self.status_label = ttk.Label(
            action_frame, textvariable=self.status_text, foreground="#555555"
        )
        self.status_label.grid(row=0, column=0, sticky="w")

        self.open_output_button = ttk.Button(
            action_frame,
            text="打开输出目录",
            command=self.open_output_directory,
            state="disabled",
        )
        self.open_output_button.grid(row=0, column=1, padx=(8, 0))

        self.run_button = ttk.Button(
            action_frame, text="开始拆分", command=self.start_split
        )
        self.run_button.grid(row=0, column=2, padx=(8, 0))

        ttk.Label(main_frame, text="运行日志").grid(
            row=4, column=0, sticky="w", pady=(0, 6)
        )
        self.log_box = scrolledtext.ScrolledText(
            main_frame, height=14, wrap="word", state="disabled"
        )
        self.log_box.grid(row=5, column=0, sticky="nsew")

        if not DND_AVAILABLE:
            self._append_log(
                "提示：当前未安装拖放组件，请运行：\n"
                "python -m pip install tkinterdnd2\n"
            )

    def _register_drop_target(self):
        if not DND_AVAILABLE:
            return
        self.drop_zone.drop_target_register(DND_FILES)
        self.drop_zone.dnd_bind("<<Drop>>", self._on_drop)

    def _on_drop(self, event):
        dropped_paths = self.root.tk.splitlist(event.data)
        if dropped_paths:
            self._set_input_file(dropped_paths[0])
        return getattr(event, "action", None)

    def choose_input_file(self):
        filename = filedialog.askopenfilename(
            title="选择 HEX 文件",
            filetypes=[("Intel HEX 文件", "*.hex"), ("所有文件", "*.*")],
        )
        if filename:
            self._set_input_file(filename)

    def _set_input_file(self, filename):
        filename = os.path.abspath(os.path.expanduser(filename))
        if not os.path.isfile(filename):
            messagebox.showerror("文件错误", f"文件不存在：\n{filename}")
            return
        if not filename.lower().endswith(".hex"):
            if not messagebox.askyesno(
                "扩展名提示",
                "该文件不是 .hex 扩展名，仍然按 Intel HEX 文件处理吗？",
            ):
                return

        self.input_path.set(filename)
        if not self.output_dir_manually_selected:
            self.output_dir.set(os.path.dirname(filename))
        self.status_text.set(f"已选择：{os.path.basename(filename)}")
        self.open_output_button.configure(state="normal")
        self._append_log(f"已选择输入文件：{filename}")

    def choose_output_dir(self):
        initial_dir = self.output_dir.get() or os.path.dirname(
            self.input_path.get()
        )
        directory = filedialog.askdirectory(
            title="选择输出目录", initialdir=initial_dir or None
        )
        if directory:
            self.output_dir.set(os.path.abspath(directory))
            self.output_dir_manually_selected = True
            self.open_output_button.configure(state="normal")
            self._append_log(f"已选择输出目录：{directory}")

    def start_split(self):
        input_file = self.input_path.get().strip()
        output_dir = self.output_dir.get().strip()

        if not input_file or not os.path.isfile(input_file):
            messagebox.showerror("输入错误", "请先选择有效的 HEX 文件。")
            return
        if not output_dir:
            messagebox.showerror("输出错误", "请选择输出目录。")
            return

        try:
            os.makedirs(output_dir, exist_ok=True)
        except OSError as exc:
            messagebox.showerror("输出错误", f"无法创建输出目录：\n{exc}")
            return

        self.run_button.configure(state="disabled")
        self.open_output_button.configure(state="disabled")
        self.status_text.set("正在拆分，请稍候……")
        self._append_log("\n开始拆分。")

        self.worker = threading.Thread(
            target=self._run_split,
            args=(input_file, output_dir),
            daemon=True,
        )
        self.worker.start()

    def _run_split(self, input_file, output_dir):
        try:
            splitter = HexFileSplitter(
                input_file, output_dir, log_callback=self._queue_log
            )
            splitter.parse_hex_file()
            created_files = splitter.split_by_fixed_ranges()
            self.event_queue.put(("success", created_files))
        except Exception as exc:
            self.event_queue.put(("error", str(exc)))

    def _queue_log(self, message):
        self.event_queue.put(("log", message))

    def _process_events(self):
        try:
            while True:
                event_type, payload = self.event_queue.get_nowait()
                if event_type == "log":
                    self._append_log(payload)
                elif event_type == "success":
                    self._handle_success(payload)
                elif event_type == "error":
                    self._handle_error(payload)
        except queue.Empty:
            pass
        finally:
            self.root.after(100, self._process_events)

    def _handle_success(self, created_files):
        self.run_button.configure(state="normal")
        self.open_output_button.configure(state="normal")
        if created_files:
            self.status_text.set(f"拆分完成，共生成 {len(created_files)} 个文件")
            self._append_log(f"拆分完成，共生成 {len(created_files)} 个文件。")
            messagebox.showinfo(
                "拆分完成", f"拆分完成，共生成 {len(created_files)} 个文件。"
            )
        else:
            self.status_text.set("处理完成，但没有生成输出文件")
            self._append_log("处理完成，但输入文件中没有可输出的数据记录。")
            messagebox.showwarning(
                "没有输出", "输入文件中没有找到可输出的数据记录。"
            )

    def _handle_error(self, error_message):
        self.run_button.configure(state="normal")
        self.open_output_button.configure(state="normal")
        self.status_text.set("拆分失败")
        self._append_log(f"错误：{error_message}")
        messagebox.showerror("拆分失败", error_message)

    def _append_log(self, message):
        self.log_box.configure(state="normal")
        self.log_box.insert("end", str(message) + "\n")
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def open_output_directory(self):
        directory = self.output_dir.get().strip()
        if not directory or not os.path.isdir(directory):
            messagebox.showerror("目录错误", "输出目录不存在。")
            return

        try:
            if sys.platform == "darwin":
                subprocess.Popen(["open", directory])
            elif os.name == "nt":
                os.startfile(directory)
            else:
                subprocess.Popen(["xdg-open", directory])
        except OSError as exc:
            messagebox.showerror("打开失败", str(exc))

    def run(self):
        self.root.mainloop()


def main():
    HexSplitterApp().run()


if __name__ == "__main__":
    main()

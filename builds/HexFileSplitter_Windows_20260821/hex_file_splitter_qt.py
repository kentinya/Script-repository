import os
import sys

from PySide6.QtCore import QObject, QThread, QUrl, Signal, Slot, Qt
from PySide6.QtGui import QDesktopServices, QDragEnterEvent, QDropEvent
from PySide6.QtWidgets import (
    QApplication, QFileDialog, QFrame, QGridLayout, QHBoxLayout, QLabel,
    QLineEdit, QMainWindow, QMessageBox, QPushButton, QPlainTextEdit,
    QSizePolicy, QVBoxLayout, QWidget,
)


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
                    self.records.append({
                        "type": record_type,
                        "address": full_address,
                        "data": data,
                        "line": line,
                    })
                elif record_type == 0x04:
                    self.extended_linear_address = int(data, 16)
                    self.records.append({"type": record_type, "line": line})
                elif record_type in (0x01, 0x05):
                    self.records.append({"type": record_type, "line": line})

        count = sum(record["type"] == 0x00 for record in self.records)
        self.log(f"解析完成，共读取 {count} 条数据记录。")

    @staticmethod
    def calculate_checksum(data_str):
        total = sum(
            int(data_str[index : index + 2], 16)
            for index in range(0, len(data_str), 2)
        )
        return (-total) & 0xFF

    def split_by_fixed_ranges(self):
        os.makedirs(self.output_dir, exist_ok=True)
        input_stem = os.path.splitext(os.path.basename(self.input_file))[0]
        output_files = {
            name: {
                "filename": os.path.join(self.output_dir, f"{input_stem}_{name}.hex"),
                "records": [],
                "current_ela": None,
            }
            for name in self.RANGES
        }
        output_files["unknown"] = {
            "filename": os.path.join(self.output_dir, f"{input_stem}_unknown.hex"),
            "records": [],
            "current_ela": None,
        }

        for record in self.records:
            if record["type"] == 0x00:
                target = "unknown"
                for range_name, (start_addr, end_addr) in self.RANGES.items():
                    if start_addr <= record["address"] <= end_addr:
                        target = range_name
                        break
                self._append_data_record(output_files[target], record)
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
        file_info["records"].append(
            self.create_data_record(record["address"] & 0xFFFF, record["data"])
        )

    def create_ela_record(self, ela):
        data_str = f"02000004{ela:04X}"
        return {
            "type": 0x04,
            "line": f":{data_str}{self.calculate_checksum(data_str):02X}",
        }

    def create_data_record(self, address, data):
        data_str = f"{len(data) // 2:02X}{address:04X}00{data}"
        return {
            "type": 0x00,
            "line": f":{data_str}{self.calculate_checksum(data_str):02X}",
        }

    @staticmethod
    def write_hex_file(filename, records):
        with open(filename, "w") as file:
            for record in records:
                file.write(record["line"] + "\n")


class DropArea(QFrame):
    file_dropped = Signal(str)

    def __init__(self):
        super().__init__()
        self.setAcceptDrops(True)
        self.setObjectName("dropArea")
        self.setMinimumHeight(120)
        layout = QVBoxLayout(self)
        label = QLabel("将 HEX 文件拖到这里\n或点击选择文件")
        label.setObjectName("dropLabel")
        label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(label)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls() and any(
            url.isLocalFile() for url in event.mimeData().urls()
        ):
            event.acceptProposedAction()

    def dropEvent(self, event: QDropEvent):
        paths = [url.toLocalFile() for url in event.mimeData().urls() if url.isLocalFile()]
        if paths:
            self.file_dropped.emit(paths[0])
            event.acceptProposedAction()


class SplitWorker(QObject):
    log = Signal(str)
    succeeded = Signal(list)
    failed = Signal(str)
    finished = Signal()

    def __init__(self, input_file, output_dir):
        super().__init__()
        self.input_file = input_file
        self.output_dir = output_dir

    @Slot()
    def run(self):
        try:
            splitter = HexFileSplitter(
                self.input_file, self.output_dir, log_callback=self.log.emit
            )
            splitter.parse_hex_file()
            self.succeeded.emit(splitter.split_by_fixed_ranges())
        except Exception as exc:
            self.failed.emit(str(exc))
        finally:
            self.finished.emit()


class HexSplitterWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("HEX 文件拆分工具")
        self.resize(800, 620)
        self.setMinimumSize(680, 520)
        self.output_dir_manually_selected = False
        self.worker_thread = None
        self.worker = None
        self._build_ui()
        self._apply_style()

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QVBoxLayout(central)
        main_layout.setContentsMargins(22, 20, 22, 20)
        main_layout.setSpacing(14)

        title = QLabel("HEX 文件拆分工具")
        title.setObjectName("title")
        main_layout.addWidget(title)

        self.drop_area = DropArea()
        self.drop_area.file_dropped.connect(self.set_input_file)
        self.drop_area.mousePressEvent = lambda _event: self.choose_input_file()
        main_layout.addWidget(self.drop_area)

        paths = QGridLayout()
        self.input_edit = QLineEdit()
        self.output_edit = QLineEdit()
        input_button = QPushButton("选择文件")
        output_button = QPushButton("选择目录")
        input_button.clicked.connect(self.choose_input_file)
        output_button.clicked.connect(self.choose_output_dir)
        paths.addWidget(QLabel("HEX 文件："), 0, 0)
        paths.addWidget(self.input_edit, 0, 1)
        paths.addWidget(input_button, 0, 2)
        paths.addWidget(QLabel("输出目录："), 1, 0)
        paths.addWidget(self.output_edit, 1, 1)
        paths.addWidget(output_button, 1, 2)
        main_layout.addLayout(paths)

        actions = QHBoxLayout()
        self.status_label = QLabel("请选择或拖入一个 HEX 文件")
        self.status_label.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        self.open_button = QPushButton("打开输出目录")
        self.run_button = QPushButton("开始拆分")
        self.open_button.setEnabled(False)
        self.open_button.clicked.connect(self.open_output_directory)
        self.run_button.clicked.connect(self.start_split)
        actions.addWidget(self.status_label)
        actions.addWidget(self.open_button)
        actions.addWidget(self.run_button)
        main_layout.addLayout(actions)

        main_layout.addWidget(QLabel("运行日志"))
        self.log_box = QPlainTextEdit()
        self.log_box.setReadOnly(True)
        main_layout.addWidget(self.log_box, 1)

    def _apply_style(self):
        self.setStyleSheet("""
            QMainWindow { background: #f6f7f9; }
            QLabel#title { font-size: 22px; font-weight: 600; color: #202124; }
            QFrame#dropArea { background: white; border: 2px dashed #8a98a8; border-radius: 10px; }
            QFrame#dropArea:hover { border-color: #2563eb; background: #f7faff; }
            QLabel#dropLabel { font-size: 16px; color: #44546a; }
            QLineEdit, QPlainTextEdit { background: white; border: 1px solid #cbd2d9; border-radius: 5px; padding: 6px; }
            QPushButton { min-height: 30px; padding: 2px 14px; border: 1px solid #b8c0ca; border-radius: 5px; background: white; }
            QPushButton:hover { background: #eef4ff; border-color: #7aa2e8; }
            QPushButton:disabled { color: #9aa0a6; background: #eceff2; }
        """)

    @Slot()
    def choose_input_file(self):
        filename, _ = QFileDialog.getOpenFileName(
            self, "选择 HEX 文件", "", "Intel HEX 文件 (*.hex);;所有文件 (*.*)"
        )
        if filename:
            self.set_input_file(filename)

    @Slot(str)
    def set_input_file(self, filename):
        filename = os.path.abspath(os.path.expanduser(filename))
        if not os.path.isfile(filename):
            QMessageBox.critical(self, "文件错误", f"文件不存在：\n{filename}")
            return
        if not filename.lower().endswith(".hex"):
            answer = QMessageBox.question(
                self, "扩展名提示", "该文件不是 .hex 扩展名，仍然按 Intel HEX 文件处理吗？"
            )
            if answer != QMessageBox.StandardButton.Yes:
                return
        self.input_edit.setText(filename)
        if not self.output_dir_manually_selected:
            self.output_edit.setText(os.path.dirname(filename))
        self.status_label.setText(f"已选择：{os.path.basename(filename)}")
        self.open_button.setEnabled(True)
        self.append_log(f"已选择输入文件：{filename}")

    @Slot()
    def choose_output_dir(self):
        initial = self.output_edit.text() or os.path.dirname(self.input_edit.text())
        directory = QFileDialog.getExistingDirectory(self, "选择输出目录", initial)
        if directory:
            self.output_edit.setText(os.path.abspath(directory))
            self.output_dir_manually_selected = True
            self.open_button.setEnabled(True)
            self.append_log(f"已选择输出目录：{directory}")

    @Slot()
    def start_split(self):
        input_file = self.input_edit.text().strip()
        output_dir = self.output_edit.text().strip()
        if not input_file or not os.path.isfile(input_file):
            QMessageBox.critical(self, "输入错误", "请先选择有效的 HEX 文件。")
            return
        if not output_dir:
            QMessageBox.critical(self, "输出错误", "请选择输出目录。")
            return
        try:
            os.makedirs(output_dir, exist_ok=True)
        except OSError as exc:
            QMessageBox.critical(self, "输出错误", f"无法创建输出目录：\n{exc}")
            return

        self.run_button.setEnabled(False)
        self.open_button.setEnabled(False)
        self.status_label.setText("正在拆分，请稍候……")
        self.append_log("\n开始拆分。")
        self.worker_thread = QThread(self)
        self.worker = SplitWorker(input_file, output_dir)
        self.worker.moveToThread(self.worker_thread)
        self.worker_thread.started.connect(self.worker.run)
        self.worker.log.connect(self.append_log)
        self.worker.succeeded.connect(self.handle_success)
        self.worker.failed.connect(self.handle_error)
        self.worker.finished.connect(self.worker_thread.quit)
        self.worker.finished.connect(self.worker.deleteLater)
        self.worker_thread.finished.connect(self.worker_thread.deleteLater)
        self.worker_thread.finished.connect(self._clear_worker)
        self.worker_thread.start()

    @Slot()
    def _clear_worker(self):
        self.worker = None
        self.worker_thread = None

    @Slot(list)
    def handle_success(self, created_files):
        self.run_button.setEnabled(True)
        self.open_button.setEnabled(True)
        if created_files:
            message = f"拆分完成，共生成 {len(created_files)} 个文件。"
            self.status_label.setText(message)
            self.append_log(message)
            QMessageBox.information(self, "拆分完成", message)
        else:
            self.status_label.setText("处理完成，但没有生成输出文件")
            self.append_log("处理完成，但输入文件中没有可输出的数据记录。")
            QMessageBox.warning(self, "没有输出", "输入文件中没有找到可输出的数据记录。")

    @Slot(str)
    def handle_error(self, error_message):
        self.run_button.setEnabled(True)
        self.open_button.setEnabled(True)
        self.status_label.setText("拆分失败")
        self.append_log(f"错误：{error_message}")
        QMessageBox.critical(self, "拆分失败", error_message)

    @Slot(str)
    def append_log(self, message):
        self.log_box.appendPlainText(str(message))

    @Slot()
    def open_output_directory(self):
        directory = self.output_edit.text().strip()
        if not directory or not os.path.isdir(directory):
            QMessageBox.critical(self, "目录错误", "输出目录不存在。")
            return
        QDesktopServices.openUrl(QUrl.fromLocalFile(directory))


def main():
    app = QApplication(sys.argv)
    window = HexSplitterWindow()
    if "--self-test" in sys.argv:
        window.close()
        return 0
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

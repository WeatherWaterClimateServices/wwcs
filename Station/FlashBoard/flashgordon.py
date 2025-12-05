# ------------------------------------------------
#
# WWCS TAJIKISTAN ARDUINO FLASH TOOL
#
# Author: Omar Bellprat, MeteoSwiss
# Contact: omar.bellprat@meteoswiss.ch
# Date: 05.05.2022
#
# ------------------------------------------------

import email.utils
import json
import os
import os.path
import platform
import shutil
import socket
import sys
import tempfile
import traceback
from pathlib import Path

# Requirements
import dateutil.parser
import httpx
import qrcode
from pyduinocli import Arduino

# Requirements: PySide6
from PySide6 import QtSerialPort
from PySide6.QtCore import QCoreApplication,QMetaObject, QRect, Qt, QIODevice
from PySide6.QtGui import QPixmap, QFont, QIcon
from PySide6.QtWidgets import (QApplication, QComboBox, QLabel, QMessageBox,
                               QPlainTextEdit, QPushButton, QTextEdit, QWidget)


DEV = os.environ.get('WWCS_DEV', False)

DOWNLOAD_URL = 'https://github.com/WeatherWaterClimateServices/wwcs/releases/download/firmware-stable/Firmware.zip'

if DEV:
    DOWNLOAD_DIR = Path('/tmp')
else:
    DOWNLOAD_DIR = Path.home() / "Downloads"

basedir = Path(os.path.dirname(__file__))
srcdir = basedir / 'src'


try:
    from ctypes import windll  # Only exists on Windows.
    myappid = 'ch.caritas.flashgordon.1'
    windll.shell32.SetCurrentProcessExplicitAppUserModelID(myappid)
except ImportError:
    pass

def download(url, path):
    path = Path(path)
    headers = {}

    # If file exists, send both If-Modified-Since
    if path.exists():
        mtime = path.stat().st_mtime
        headers['If-Modified-Since'] = email.utils.formatdate(mtime, usegmt=True)

    response = httpx.get(url, headers=headers, follow_redirects=True)

    # Not modified
    if response.status_code == 304:
        return 304

    # Save file
    if response.status_code == 200:
        with path.open('wb') as f:
            f.write(response.content)

        # Use server's Last-Modified if available
        if 'last-modified' in response.headers:
            server_time = dateutil.parser.parse(response.headers['last-modified'])
            timestamp = server_time.timestamp()
            os.utime(path, (timestamp, timestamp))
        else:
            # Fallback: use current time
            pass

        return 200

    response.raise_for_status()
    return response.status_code

def get_arduino():
    if platform.system() == 'Windows' and (basedir / 'arduino-cli.exe').exists():
        return Arduino(str(basedir / 'arduino-cli'))

    return Arduino()

def isConnect():
    try:
        with socket.create_connection(("www.geeksforgeeks.org", 80), timeout=10):
            return True
    except OSError:
        return False

class Widget(QWidget):

    def __init__(self):
        super().__init__()

        self.setObjectName("Widget")
        self.resize(620, 600)
        self.setFixedSize(self.size())

        # Create temporary directory
        self.old_wd = os.getcwd()
        self.wd = tempfile.mkdtemp()
        os.chdir(self.wd)

        cssfile = srcdir / "stylesheet.css"
        with cssfile.open("r") as fh:
           self.setStyleSheet(fh.read())

        # Menu Titles
        self.TitleMain = QLabel(self)
        self.TitleMain.setObjectName("TitleMain")
        self.TitleMain.setGeometry(QRect(40, 30, 240, 30))
        self.TitleMain.setTextFormat(Qt.RichText)
        self.TitleMain.setScaledContents(False)

        if sys.platform == 'linux' or sys.platform == 'win32':
            self.titlefont = QFont('Helvetica Neue', 20)
        else:
            self.titlefont = QFont('Helvetica Neue', 30)

        self.titlefont.setBold(True)
        self.TitleMain.setFont(self.titlefont)
        self.TitleMinor = QLabel(self)
        self.TitleMinor.setObjectName("TitleMinor")
        self.TitleMinor.setGeometry(QRect(280, 35, 500, 30))
        self.TitleMinor.setTextFormat(Qt.RichText)
        self.TitleMinor.setScaledContents(False)

        if sys.platform == 'linux' or sys.platform == 'win32':
            self.titlefont = QFont('Helvetica Neue', 14)
        else:
            self.titlefont = QFont('Helvetica Neue', 22)

        self.TitleMinor.setFont(self.titlefont)

        top = 80
        space = 30

        # Server URL
        label = self.TitleServerURL = QLabel(self)
        label.setObjectName("TitleServerURL")
        label.setGeometry(QRect(10, top, 230, 30))
        top += space
        label.setAlignment(Qt.AlignCenter)
        input = self.ServerURL = QTextEdit(self)
        input.setObjectName("ServerURL")
        input.setGeometry(QRect(10, top, 230, 31))
        top += space
        top += 8
        input.setPlaceholderText("Enter Server hostname")

        # APN
        label = self.TitleAPN = QLabel(self)
        label.setObjectName("TitleAPN")
        label.setGeometry(QRect(10, top, 230, 30))
        top += space
        label.setAlignment(Qt.AlignCenter)
        input = self.APN = QTextEdit(self)
        input.setObjectName("APN")
        input.setGeometry(QRect(10, top, 230, 32))
        top += space
        top += 8

        # Board type selection
        label = self.TitleBoardType = QLabel(self)
        label.setObjectName("TitleBoardType")
        label.setGeometry(QRect(10, top, 230, 30))
        top += space
        label.setAlignment(Qt.AlignCenter)
        input = self.Boardtype = QComboBox(self)
        input.setObjectName("Boardtype")
        input.setGeometry(QRect(10, top, 230, 22))
        top += space

        # Sensor type selection
        label = self.TitleSensorType = QLabel(self)
        label.setObjectName("TitleSensorType")
        label.setGeometry(QRect(10, top, 230, 30))
        top += space
        label.setAlignment(Qt.AlignCenter)
        input = self.Sensortype = QComboBox(self)
        input.addItem("")
        input.addItem("")
        input.setObjectName("Sensortype")
        input.setGeometry(QRect(10, top, 230, 22))
        top += space

        # Network  selection
        label = self.TitleNetwork = QLabel(self)
        label.setObjectName("TitleNetwork")
        label.setGeometry(QRect(10, top, 230, 30))
        top += space
        label.setAlignment(Qt.AlignCenter)
        input = self.Network = QComboBox(self)
        input.addItem("")
        input.addItem("")
        input.addItem("")
        input.setObjectName("Network")
        input.setGeometry(QRect(10, top, 230, 22))
        top += space

        # Serial Monitor
        label = self.TitleMonitor = QLabel(self)
        label.setObjectName("TitleMonitor")
        label.setGeometry(QRect(20, top, 230, 30))
        top += space
        label.setAlignment(Qt.AlignCenter)
        input = self.MonitorButton = QPushButton(self, checkable=True)
        input.setObjectName("MonitorButton")
        input.setGeometry(QRect(50, top, 170, 32))
        input.clicked.connect(self.monitor)
        top += space

        # Station ID Input
        top += space
        label = self.TitleStation = QLabel(self)
        label.setObjectName("TitleStation")
        label.setGeometry(QRect(10, top, 230, 30))
        top += space
        label.setAlignment(Qt.AlignCenter)
        input = self.StationID = QTextEdit(self)
        input.setObjectName("StationID")
        input.setGeometry(QRect(50, top, 170, 31))
        top += space
        top += 2
        input.setPlaceholderText("Enter Station ID")

        # Flash Button
        input = self.FlashButton = QPushButton(self)
        input.setObjectName("FlashButton")
        input.setGeometry(QRect(50, top, 170, 32))
        top += space
        input.clicked.connect(self.flash)

        # Console and monitor output
        self.TitleConsole = QLabel(self)
        self.TitleConsole.setObjectName("TitleConsole")
        self.TitleConsole.setGeometry(QRect(270, 80, 330, 30))
        self.TitleConsole.setAlignment(Qt.AlignCenter)
        self.Console = QPlainTextEdit(self, readOnly=True)
        self.Console.setObjectName("Console")
        self.Console.setGeometry(QRect(270, 110, 330, 390))

        # Logos
        self.Logo = QLabel(self)
        self.Logo.setObjectName("Logo")
        self.Logo.setGeometry(QRect(330, 515, 230*0.9, 60*0.9))
        self.Logo.setPixmap(QPixmap(str(srcdir / "logo_caritas_white.png")))
        self.Logo.setScaledContents(True)
        # self.Logo2 = QLabel(self)
        # self.Logo2.setObjectName("Logo")
        # self.Logo2.setGeometry(QRect(330, 470, 230, 75))
        # self.Logo2.setPixmap(QPixmap(str(srcdir / "logo_switzerland_white.svg")))
        # self.Logo2.setScaledContents(True)

        self.retranslateUi()
        QMetaObject.connectSlotsByName(self)

        # Find Arduino cli
        self.find_arduino()

        # Download firmware file
        if not os.path.exists(DOWNLOAD_DIR):
            os.makedirs(DOWNLOAD_DIR)
        self.download_fw()

    def __get_server_url(self):
        hostname = self.ServerURL.toPlainText()
        if hostname:
            return f'https://{hostname}/post'

        if DEV:
            return 'http://127.0.0.1:5000'

        return None

    def register(self, loggerID):
        self.message("Updating data base with new stationID ...  \n")
        loggerID = loggerID.strip()

        # Save QR
        siteID = self.StationID.toPlainText()
        img = qrcode.make(siteID)
        path = DOWNLOAD_DIR / "QR-StationID"
        path.mkdir(exist_ok=True)
        path = path / f'{siteID}_QR.png'
        img.save(str(path), 'png')

        if isConnect():
            server_url = self.__get_server_url()
            data = {'siteID': siteID, 'loggerID': loggerID, 'git_version': self.gitversion}
            response = httpx.post(f'{server_url}/register', json=data)
            if response.status_code not in [200, 201]:
                self.message('Error registering station')
            else:
                self.message("You sucessfully flashed the board!  \n")
        else:
            self.message("No connection to server, station not updated on database. Finished flashing. \n")


    def download_fw(self):
        # Download
        zip_file = DOWNLOAD_DIR / 'Firmware.zip'
        self.message('Firmware...')
        try:
            if DEV:
                # In development run zip_firmware.py manually
                status_code = 304
            else:
                status_code = download(DOWNLOAD_URL, zip_file)
        except Exception:
            if zip_file.exists():
                self.message("Firmware download failed, will use version from cache.")
            else:
                self.message("ERROR: Firmware download failed, verify your network connection.")
                return
        else:
            if status_code == 200:
                self.message('Firmware downloaded.')
            elif status_code == 304:
                self.message('Firmware already up to date.')
            else:
                self.message(f'Firmware download failed with unexpected server response: {status_code}')

            if not zip_file.exists():
                self.message("ERROR: Firmware.zip file does not exist\n")
                return

        # Unpack
        shutil.unpack_archive(zip_file, 'Firmware', 'zip')
        with open('Firmware/metadata.json') as file:
            metadata = json.load(file)
        self.gitversion = metadata['gitversion']

        # Find out the list of firmwares available
        prefix = 'Firmware'
        n = len(prefix)
        fwlist = []
        self.fwfiles = {}
        for child in Path('Firmware').iterdir():
            dirname = child.name
            if dirname.startswith(prefix) and child.is_dir():
                for ino in child.iterdir():
                    if ino.name.endswith('.ino') and ino.is_file():
                        name = dirname[n:]
                        fwlist.append(name)
                        self.fwfiles[name] = ino.name[:-4]

        # Fill interface
        for i, name in enumerate(sorted(fwlist)):
            self.Boardtype.addItem(name)

    def find_arduino(self):
        # Arduino cli
        self.arduino = get_arduino()
        try:
            version = self.arduino.version()
        except FileNotFoundError:
            self.message('ERROR: arduino-cli not found')
        else:
            version = version['result']['VersionString']
            self.message(f'Found arduino-cli version {version}')

    def config(self):
        """
        Define board sketch variables upon GUI selection
        """
        boardtype = self.Boardtype.currentText()
        self.Sketch = self.fwfiles[boardtype]
        self.PathSketchConfig = "./" + self.Sketch
        PathSketch = "./Firmware/Firmware" + boardtype
        shutil.copytree(PathSketch, self.PathSketchConfig)
        filename = self.PathSketchConfig + "/" + self.Sketch + ".ino"

        def inplace_change(filename, old_string, new_string):
            with open(filename) as f:
                s = f.read()
            if old_string not in s:
                print(f'"{old_string}" not found in {filename}.')
                return
            with open(filename, 'w') as f:
                print(f'Changing "{old_string}" to "{new_string}" in {filename}')
                s = s.replace(old_string, new_string)
                f.write(s)

        inplace_change(filename, "FlashServer", self.ServerURL.toPlainText())
        inplace_change(filename, "FlashProvider", self.APN.toPlainText())
        inplace_change(filename, "FlashGIT", self.gitversion)
        inplace_change(filename, "FlashSite", self.StationID.toPlainText())

        network = self.Network.currentText()
        if network == "GSM":
            inplace_change(filename, "1234", "13")
        elif network == "LTE":
            inplace_change(filename, "1234", "38")
        elif network == "GSM/LTE":
            inplace_change(filename, "1234", "51")

        self.configout = True

        if self.Sensortype.currentText() == "Climavue":
            if self.Boardtype.currentText() == "Lilygo":
                self.configout = False
            else:
                inplace_change(filename,"CLIMAVUE50 = false", "CLIMAVUE50 = true")


    def detectport(self): # Detect Board Port
        self.Port = None

        boardlist = self.arduino.board.list()
        boards = boardlist['result']

        if sys.platform == 'linux':
            for board in boards:
                p = board['port']['address']
                if p.find("tty") != -1:
                    self.Port = p

        elif sys.platform == 'win32':
            for board in boards:
                p = board['port']['address']
                if p.find("COM") != -1:
                    self.Port = p

        elif sys.platform == 'darwin':
            for board in boards:
                p = board['port']['address']
                if p.find("usbserial") != -1:
                    self.Port = p

    def message(self, s):
        self.Console.appendPlainText(s)
        app.processEvents()

    def message_exc(self, exc):
        lines = traceback.format_exception(exc)
        self.Console.appendPlainText('')
        for line in lines:
            line = line.rstrip()
            self.Console.appendPlainText(line)
        app.processEvents()

    def monitor(self, checked):
        try:
            self.__monitor(checked)
        except Exception as exc:
            self.message_exc(exc)

    def __monitor(self, checked):
        self.MonitorButton.setText("Disconnect" if checked else "Connect")
        self.detectport()
        self.Console.clear()

        if  self.Port is None:
            self.message("Exit: No Arduino board detected on USB port \n")
            return
        else:
            if self.MonitorButton.text() == "Connect":
                self.message("Serial monitor disconnected. \n")
            elif self.MonitorButton.text() == "Disconnect":
                self.message("Serial monitor connected. \n")

        boardtype = self.Boardtype.currentText()
        if boardtype.startswith("Lilygo"):
            baudRate = QtSerialPort.QSerialPort.Baud115200
        elif boardtype.startswith("Koala"):
            baudRate = QtSerialPort.QSerialPort.Baud115200
        else:
            raise RuntimeError(f'Unexpected board type: {boardtype}')

        self.serialmonitor = QtSerialPort.QSerialPort(self.Port, baudRate=baudRate,
                                                      readyRead=self.receive)

        if checked:
            if not self.serialmonitor.isOpen():
                if not self.serialmonitor.open(QIODevice.ReadWrite):
                    self.MonitorButton.setChecked(False)
        else:
            self.serialmonitor.close()

    def receive(self):
        while self.serialmonitor.canReadLine():
            text = self.serialmonitor.readLine().data().decode()
            text = text.rstrip('\r\n')
            self.message(text)

    def flash(self):
        try:
            self.__flash()
        except Exception as exc:
            if DEV:
                print('<<<< STDERR >>>>')
                print(exc.result['__stderr'])
                print('<<<< STDOUT >>>>')
                print(exc.result['__stdout'])
                #print(exc.result['result'])
            self.message_exc(exc)

    def __flash(self):

        # CLEAN START
        self.Console.clear()

        # CONFIGURE SKETCH
        boardtype = self.Boardtype.currentText()
        self.message(f"Preparing sketch for {boardtype} ...\n")
        self.config()
        if self.configout is False:
            self.message("Exit: Climavue sensor is only compatible with the Koala board \n")
            return

        # ARDUINO INSTANCE
        self.message("Detecting connected board ...\n")
        self.detectport()
        if self.Port is None:
            self.message("Exit: No Arduino board detected on USB port\n")
            return

        # Verify the sketch.yaml file exists
        sketch_yaml = Path(self.PathSketchConfig) / "sketch.yaml"
        assert sketch_yaml.exists()

        # COMPILING SKETCH
        self.message("Compiling sketch...")
        os.chdir(self.PathSketchConfig)
        out = self.arduino.compile(sketch = self.Sketch + ".ino", profile='default')
        if out['result']['success']:
            self.message("Sketch compiled.\n")
        else:
            self.message("ERROR: Compilation of sketch failed\n")
            return

        # UPLOADING SKETCH
        self.message("Uploading sketch ...\n")
        out = self.arduino.upload(port = self.Port,
                                  fqbn = "esp32:esp32:esp32wrover",
                                  board_options = {"EraseFlash": "all"})

        if len(out['__stderr']) > 0:
            return self.message("Exit: Upload of sketch failed \n")

        # read MAC address of the board
        stdout = out['__stdout']
        start = stdout.find("MAC: ") + len("MAC: ")
        #end = stdout.find("\nUploading")
        MAC = stdout[start:start+17]

        self.register(MAC)
#       os.chdir(old_wd)
#       shutil.rmtree(wd)

    def retranslateUi(self):
        self.setWindowTitle(QCoreApplication.translate("Flash Gordon", "Flash Gordon", None))
        self.Logo.setText("")
        self.FlashButton.setText(QCoreApplication.translate("Widget", "Flash ↯", None))
        self.MonitorButton.setText(QCoreApplication.translate("Widget", "Connect", None))

        self.Network.setItemText(0, QCoreApplication.translate("Widget", "GSM", None))
        self.Network.setItemText(1, QCoreApplication.translate("Widget", "LTE", None))
        self.Network.setItemText(2, QCoreApplication.translate("Widget", "GSM/LTE", None))
        self.Sensortype.setItemText(0, QCoreApplication.translate("Widget", "Sensirion", None))
        self.Sensortype.setItemText(1, QCoreApplication.translate("Widget", "Climavue", None))
        self.TitleServerURL.setText(QCoreApplication.translate("Widget", "Server Hostname", None))
        self.TitleAPN.setText(QCoreApplication.translate("Widget", "APN", None))
        self.TitleBoardType.setText(QCoreApplication.translate("Widget", "Board Type", None))
        self.TitleSensorType.setText(QCoreApplication.translate("Widget", "Sensor Type", None))
        self.TitleNetwork.setText(QCoreApplication.translate("Widget", "Network", None))
        self.TitleMonitor.setText(QCoreApplication.translate("Widget", "Serial Monitor", None))
        self.TitleConsole.setText(QCoreApplication.translate("Widget", "Console Output", None))
        self.TitleStation.setText(QCoreApplication.translate("Widget", "Station ID", None))
        self.TitleMain.setText("Flash Gordon ↯ ")
        self.TitleMinor.setText("Setup tool for WWCS stations")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setWindowIcon(QIcon(str(srcdir / 'flashgordon.ico')))

    try:
        flashgordon = Widget()
        flashgordon.setAutoFillBackground(True)
        flashgordon.show()
    except Exception as exc:
        lines = traceback.format_exception(exc)
        box = QMessageBox()
        box.setWindowTitle("There has been an error")
        box.setText(''.join(lines))
        box.exec()
        sys.exit(1)

    sys.exit(app.exec())

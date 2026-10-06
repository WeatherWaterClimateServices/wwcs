# Introduction
To upload the firmware running on the logger of the weather stations, the ArduinoIDE provides an interactive tool which allows testing and troubleshooting before field deployment.

This guides describes its preparation on a Windows computer, taking into account unstable internet access conditions.

You will need a computer with administrator access and access to a USB port.

# Getting ArduinoIDE
Download the latest version of the IDE as instruced [here](https://support.arduino.cc/hc/en-us/articles/360019833020-Download-and-install-Arduino-IDE)

## Configuration
### USB port
Verify that the logger and the computer talk to each other.


1. Connect the logger to the computer (using a data-able USB-C-cable!) and turn it on (the power switch must be in the position towards the edge; you'll see LEDs turning on).
2. Open BlueTooth settings - under 'Other Devices', check whether the 'CP2102 USB to UART...' requires a driver to be installed. If needed, download from [here](https://www.silabs.com/software-and-tools/usb-to-uart-bridge-vcp-drivers) (you need to allow Cookies). Open the Release Notes (either within the downloaded zip or [here](https://www.silabs.com/software-and-tools/usb-to-uart-bridge-vcp-drivers?tab=documentation)) and follow instructions.

### increase download timeout
Some of the libraries downloaded in the next steps are huge. If internet connectivity is unstable, the download may fail. This can be overcome by increasing a timeout in the ArduinoIDE configuration.

1. Close ArduinoIDE if running.
2. Navigate to this folder, using the Explorer: C:\Users\YourUser\.arduinoIDE\ (YourUser is the name of the user logged into the windows computer, the one who installed ArduinoIDE). 
3. Open arduino-cli.yaml in any text editor (e.g., Notepad).
4. Add the following lines
```
network:
      connection_timeout: 300s
```

5. Save and close the file and start ArduinoIDE.

# Install libraries
It is absolutely essential to install the libraries with the correct versions. Whenever you install a library, choose the version which is defined in the sketch.yaml file [(here)](https://github.com/WeatherWaterClimateServices/wwcs/blob/main/Station/FirmwareKoala_rev4.0/sketch.yaml).

## ESP32 core libraries
Within ArduinoIDE open, select the Boards Manager (icon in the left bar; or through Tools -> Board -> Boards Manager). Type esp32 into the search field and select esp32 at the correct version (3.0.2 at the time of writing, verify with sketch.yaml). Hit install and go for a coffee.

## Install packages
Within ArduinoIDE open, select the Library Manager (icon in the left bar; or through Tools -> Manage Libraries).

For each of the libraries specified in sketch.yaml, enter the library name into the search field, select the correct version from the dropdown and click install. This will be very fast.

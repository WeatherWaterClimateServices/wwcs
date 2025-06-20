# Compilation and upload

The sketches in this folder can be compiled and uploaded to the boards in different ways
- by use of the code in the FlashBoard directory, which supports defining constants in the code and some related entries into the DB
- manually using the Arduino IDE (make sure to have the libraries at the versions indicated in the sketch.yaml files). This requires a configured code beforehand (siteID etc.) and manual entries in the DB.
- arduino command line, same as with the IDE.

## Arduino command line
Install the arduino command line as described [here](https://arduino.github.io/arduino-cli/0.23/installation/)

Configure your sketch file for the specific station. Change to the directory of the sketch files, and, replacing `/dev/ttyUSB0` by the USB port to which the board is connected as needed, run
```
arduino-cli compile --profile default
arduino-cli upload -p /dev/ttyUSB0 --profile default
```

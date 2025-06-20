# Compilation and upload

The sketches in this folder can be compiled and uploaded to the boards in different ways
- by use of the code in the FlashStation directory
- using the Arduino IDE (make sure to have the libraries at the versions indicated in the sketch.yaml files)
- arduino command line

## Arduino command line
Install the arduino command line as described [here](https://arduino.github.io/arduino-cli/0.23/installation/)

Change to the directory of the sketch files, and, replacing `/dev/ttyUSB0` by the USB port to which the board is connected as needed,
```
arduino-cli compile --profile default
arduino-cli upload -p /dev/ttyUSB0 --profile default
```

This page includes the code for the new sensors, some problems and bugs encountered and general information relative to the programming of the weather station.

## In-detail code explanation
The code for the new test station with added sensors is based on the programm-code for the Lilygo board, which can be found in the wiki repository, under: Station>FirmwareLilygo>ttgo_sim7000g_sht30_bme280.ino \
The code for the new station can be found in the wiki repository as well, under the following path:
Station>FirmwareLilygo>ttgo_sim7000g_tsl2591_GPS.ino \
This paragraph goes into the different code snippets that have been added for the new sensors.

### Code lines 113-117
After each measurement, the Lilygo board goes into deep sleep. When starting up again, after a number of minutes stored in "SLEEP_MINUTES", all variables have been deleted. However, it is possible to store variables in the RTC memory of the ESP32, which has only 8Kb of memory. Here this is done by adding "RTC_DATA_ATTR" in front of the variable we want to survive during deep sleep.

### Code lines 211-304
The source of this code is [Random Nerd Tutorials](https://randomnerdtutorials.com/lilygo-t-sim7000g-esp32-gps-data/).
The GPS connection is established through the GPS antenna, and the GPS position and the time are retrieved. The LTE antenna is not required for this step, so it is a good way to get the exact time to store the measurements, if it isn't possible to connect to a NTP server.

### Code lines 371-420
The idea behind this code is to establish how many and which sensors are available on the measuring station, to then create a list of them, which survive deep sleep. The next time that the station wakes up again from deep sleep, it already knows which sensors are connected to it and doesn't need to check again, reducing the number of steps it must do before it starts measuring. For each measurement round, the sensors must be initialized before measuring, so if at some point a sensor has a problem, even if it's connected and is present in the list of available sensors, it is going to send an error value (if unable to take a measurement). This step of checking which sensors are available (which means that they are connected to the Lilygo board and can be initialized/can take a measurement) is done when the station powers up for the first time. There is a variable ("loopCounter") which stores the number of times that the station has powered up, and after surpassing a certain threshold (for example MAX_LOOPS = 500), the system gets restarted, the "loopCounter" will be back to 0 and the station checks again which sensors are available. To check for availability of the I2C sensors (TSL2591, SHT30 and MLX90614) it is enough to call the function to initialize them. For the sensors that don't use I2C (the Grove ones) there is no function to initialize them, so to check for their availability we take a measurement and check that it is not an error value.
The first letter of the name of the available sensors is then stored in a character array which gets stored in the RTC memory (RTC_DATA_ATTR char sensor_list[MAX_NUMBER_SENSORS]). The length of this character array can be changed, depending on how many sensors we plan to connect to the board. The number of available sensors is counted in the "sensor_counter" variable, and for each sensor available, the board blinks an LED once (so for 5 available sensors we can observe 5 LED blinks).

### Code lines 423-477
We loop through each character of the character array "sensor_list" and for each sensor that is available we call the function to take the measurements. All functions are written at the end of the programm-code, outside of the setup() function. As a safety measure, the measurements of all the sensors are also written on a sensdata.txt file (which is called sensDataFile). This file is within the LittleFS (little file system) of the ESP32, which is a way of storing .txt files on the flash memory of the microcontroller, which also does not get lost during deep sleep, but even during system resets. The "sensDataFile" must be opened before writing something on it, which is done in code lines 360-362. The current time is also saved on the "sensDataFile" before each measurement round. This is done in code line 365. After the measurements have been written on the file, the file gets written and printed on the Serial Monitor (code lines 483-487). After that it needs to be closed (code lines 488-489).

### Code lines 520-540
We send the data through php, so all the measurements get stored in a string (httpRequestData)

### Code lines 760-766
For the network provider used for this test station (Swisscom) it is important to set the network mode to 38 (LTE only), and the preferred mode to 3 (CAT-M and NB-IoT). If the connection to the network does not work, we can manually set the PDP contect (code-lines 769 to 812, which have been commented out because through the line 821 we call the function "set_pdp" that does something similar).

## Sensor functions
For each sensor measurement, we adopt the same method: we take two measurements of the same variable at a very short time distance five times, or until the plausibility condition is met. The plausibility condition is different for each sensor, because it depends on the sensor measurement properties. If the plausibility condition is met, we average the two taken measurements and we store them in a pointer variable.

### configureSensor (code lines 878-928)
This is an official [Adafruit function](https://github.com/adafruit/Adafruit_TSL2591_Library/blob/master/examples/tsl2591/tsl2591.ino) for the irradiance sensor TSL2591, which allows to change the gain and integration time of the sensor. Since this sensor has been designed primarily for inside use and we are using it outside in very bright sunlight, we set the gain and the integration time to the lowest, to prevent the saturation of the sensor.

### tsl_measurement (code lines 930-976)
Some parts of this code are taken from the official [Adafruit library](https://github.com/adafruit/Adafruit_TSL2591_Library/blob/master/examples/tsl2591/tsl2591.ino) for this sensor.\
The sensor TSL2591 takes a measurement of the incoming IR radiation, and a measurement of the radiation in the visible spectrum. A percentage of both measurements is then calculated (100% would be the value at which the sensor is saturated). This is done because the radiation measured has no unit (or it can be converted into lux, which is of no interest for this project).
Two sensor measurements are taken at a very short time distance (500 milliseconds) to be able to check the plausibility of the measurements. These first measurements are stored in a variable of uint32_t type (unsigned integer 32-bit), the first 16 bits (upper bits) of this variable contain the IR measurement, and the second 16 bits (lower bits) contain the visible light measurement. Thanks to an operation of bit-shifting and bit-masking, these measurements get assigned to the variables ir1, ir2, full1, full2. The plausibility is attained (plausibility = true) when the difference between the two taken measurements is less than 100, and when the measurements are positive. If this condition is met, the "double" measurements are averaged and stored in the pointer variables. The sensor takes five measurements, if the plausibility condition is not met within these five tries, it gives up for this measurement round and saves error values in the pointer variables.

### sht_measurement (code lines 984-1018)
The SHT30 sensor takes two measurements: one for temperature and one for humidity. Again, we have five tries to reach plausibility and store the measurements in the pointer variables, otherwise we store error values. For this sensor, the plausibility conditions states that the difference between the temperature measurements must be less than 1, and that the temperature measurement has to be in a range from -80 to 99, which are the lowest and highest temperatures that this sensor can measure. We assume that if the temperature measurements are plausible, the humidity measurements will be too.

### grove_temp_measurement (code-lines 1027-1053)
Some parts of this code are taken from [here](https://github.com/Seeed-Studio/Grove_Temperature_And_Humidity_Sensor/blob/master/examples/DHTtester/DHTtester.ino).\
This sensor measures the temperature and humidity. The plausibility condition checks that the difference between the two measurements is less than one, and that the temperature measurement are in a range that goes from -40 to 80. We assume that if the temperature measurements are plausible, the humidity measurements will be too. For this sensor, the measurements are stored in a float array of length 2, the humidity value is stored in the first element of the array, and the temperature value in the second one.

### mlx_measurement (code-lines 1056-1093)
Some parts of this code are taken from the [Adafruit library](https://github.com/adafruit/Adafruit-MLX90614-Library/blob/master/examples/mlxtest/mlxtest.ino) for this sensor.\
The emissivity of this sensor is one. The two measurements are taken within 10 ms of eachother. The plausibility condition states that the difference between the two measured object temperatures must be less than one, and that the object temperature must range between -70 and 99.

### grove_measurement (code-lines 1096-1141)
Some parts of this code are taken from [here](https://github.com/ErickSimoes/Ultrasonic/blob/master/examples/UltrasonicSimple/UltrasonicSimple.ino).\
The ultrasonic distance measurement of the Grove sensor depends on the temperature of the medium in which sound travels. To correct for this effect, we use the temperature measurement from the Grove temperature sensor. From the distance measurement of the sensor, we get the signal travel time in seconds (from the sensor to the measured surface and back to the sensor). The speed of the signal that the Grove sensor sends is 340 m/s.
The actual sound speed is then calculated as a function of temperature:
sound_speed = 331.2 * sqrt(1 + air_temp/273.15) \
In a final step, the corrected distance is calculated, as well the the snow height (by knowing the sensor height above the bare ground, and by substracting the calculated distance to te surface).
The plausibility conditions for this sensor are that the difference between the two measurements must be less than 1, and the distance measurement must be in a range between 0 and a maximum height that has been previously set.

### hcsr04_measurement (code-lines 1144-1197)
Some parts of this code are taken from [here](https://randomnerdtutorials.com/esp32-hc-sr04-ultrasonic-arduino/).\
The function for the hcsr04 sensor follows the same idea as the function for the grove distance sensor, but this sensor measures the duration of the signal instead of directly measuring the distance. Here also the distance is corrected with the actual temperature measured by the Grove temperature and moisture sensor.

## Problems encountered during programming
- The latest versions of [arduino-esp32](https://github.com/espressif/arduino-esp32) and [SSLClientESP32](https://github.com/alkonosst/SSLClientESP32) aren't compatible anymore: The new releases of the Arduino core for the ESP32 (from version 3.0.0 onwards) are not compatible with the latest version of the SSLClientESP32 library (v2.0.3). There is a bug with a header file of the Mbed-TLS library, which is included in the following header file ssl_lib_client.h of the SSLClientESP32 library. Some workarounds have been tried, but none of them with a positive outcome yet. A bug-report has been created on the github of the SSLClientESP32 library. For now, it is advised to stick to the older version of the Arduino core for the ESP32, namely v2.0.17.
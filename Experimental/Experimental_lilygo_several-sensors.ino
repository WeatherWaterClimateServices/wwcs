 /* --------------------------------------------------------------------------------------------------------------------------------
 * name :         ttgo_sim7000g_tsl2591
 * date :         12.01.2022
 * description :  log data TSL2591, send to cloud
 * @authors :     Boris Orlowsky &  Jacques Grandjean
 * @version :     see git_version
 * ------------------------------------------------------------------------------------------------------------------------------*/
//....................................................................................................  
//....................................................................................................  
/* CONSTANTS AND CONFIGURATION - TO BE SET / OVERWRITTEN BY FLASHGORDON*/
const char SITE_ID[] = "FlashSite";                 // dummy site ID
const char GIT_VERSION[] = "FlashGIT";       // dummy git version
const char GSM_PIN[] = "";                       // dummy GSM PIN
const int SLEEP_MINUTES = 1;                    // time between measurements
const char DEFAULT_APN[] = "gprs.swisscom.ch";                 // dummy APN
const char GPRS_USER[] = "";                     // GPRS credential
const char GPRS_PASS[] = "";                     // GPRS credential
const int NETWORK_MODE = 38;                     // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE only 
const bool JSON_PY_API = false;                  // select whether transmission uses the json/python api or the previous php api
const char SERVER[] = "wwcs.slf.ch"; // domain name: example.com, maker.ifttt.com, etc
const char RESOURCE[] = "/post_data.php";           // resource path, for example: /post_data.php
const int  PORT = 443;
const int MAX_LOOPS = 500;
const int MAX_RECORDS = 300;
const int MAX_NUMBER_SENSORS = 5;                // the maximum number of the sensors that have been connected to the board

/* DEFINES - PARTLY BOARD-SPECIFIC*/
#define SerialAT Serial1                           // Serial communication with Modem
#define WDT_TIMEOUT 180                            // for hardware watchdog
#define uS_TO_S_FACTOR 1000000ULL                  // Conversion factor for micro seconds to seconds
#define UART_BAUD   115200                           // for the modem
#define PIN_DTR     25
#define PIN_TX      27
#define PIN_RX      26
#define PWR_PIN     4
#define MODEM_RST   5
#define LED_PIN     12                             // for the LED
#define PIN_ADC_BAT 35                             // for battery
#define PIN_ADC_SOLAR 36                           // for solar panel
#define ADC_BATTERY_LEVEL_SAMPLES 100

#define I2C1_SDA 21                                  // I2C1 data pins 
#define I2C1_SCL 22                                 // I2C1 data pins 
#define I2C2_SDA 33                                 // I2C2 data pins 
#define I2C2_SCL 32                                  // I2C2 data pins

#define TINY_GSM_MODEM_SIM7000                  // define modem etc for TinyGSM
#define TINY_GSM_RX_BUFFER 1024                    // Set RX buffer to 1Kb

#define FORMAT_LITTLEFS_IF_FAILED true              // To mount LittleFS file system on flash memory

#define sensor_height 1.5                           // define height of the distance sensors in m above the ground (for snow height)

#define DHTTYPE DHT22                             // DHT 22  (AM2302), Grove temperature and humidity sensor
#define DHTPIN 13                                 // for Grove temperature and humidity sensor (signal pin)

/* INCLUDE */
#include <LittleFS.h>                                // file system on flash
#include <Arduino.h>
#include "FS.h"
#include <string>
#include <TinyGsmClient.h>                         // this library requires the 2 defines above
// #include <SSLClient.h>                             // https://github.com/OPEnSLab-OSU/SSLClient
#include <SSLClientESP32.h>                        // TestSSL
#include <ESP32Time.h>
#include <TimeLib.h>
#include <ArduinoHttpClient.h>
#include <Adafruit_TSL2591.h>                       // libraries for TSL2591
#include <Adafruit_Sensor.h>
#include <SHTSensor.h>                             // libraries for SHT30
#include "Grove_Temperature_And_Humidity_Sensor.h"      // library for Grove temperature and humdity sensor
#include <esp_task_wdt.h>                           // for hardware watchdog
#include <StreamDebugger.h>
#include <ArduinoJson.h>
#include "mbedtls/md.h"
#include "Wire.h"
#include <Ultrasonic.h>                           // for Grove ultrasonic distance sensor
#include <Adafruit_MLX90614.h>                    // for non-contact IR temperature sensor
// #include "trusted_anchor_wwcstj.h"             // TestSSL
#include "time.h"
#include <SD.h>
#include <SPI.h>
#include <Ticker.h>

//....................................................................................................  
//....................................................................................................  


//....................................................................................................  
// #define DUMP_AT_COMMANDS                       // See all AT commands, if wanted
#ifdef DUMP_AT_COMMANDS                           // if enabled it requires the streamDebugger lib
#include <StreamDebugger.h>
StreamDebugger debugger(SerialAT, Serial);
TinyGsm modem(debugger);
#else
TinyGsm modem(SerialAT);
#endif

// global objects, variables and constants
const char COMPILE_DATE_FILE[] = __DATE__ " " __TIME__ " " __FILE__;
int RecordsInFlash = 0;                           // counter of records stored in flash
ESP32Time rtc;                                    // object to interact with RTC (UTC - otherwise add offset 3600 or 7200)
//TinyGsmClientSecure clients(modem);               // network client (secure)
TinyGsmClient client(modem);                      // several network clients
SSLClientESP32 clients(&client);                           // TestSSL
// SSLClient clients(client, TAs, 1, A7);

float air_temp = -999.99;                           // Grove air temperature, init with error value
int list_count;                                   // helper variable for a for-loop (to go through the sensor list)
const int trigPin = 5;                            // Trig and Echo pin defition for HC-SR04 
const int echoPin = 18;

// variables that survive in RTC memory during deep sleep
RTC_DATA_ATTR int sleepDelta = 0;                 // to capture deviation at wakeup due to RCT drift
RTC_DATA_ATTR int loopCounter = 0;                // count the cycles and force ESP to restart every MAX_LOOPS loops
RTC_DATA_ATTR int sensor_counter = 0;                            // counter variable to count the number of available sensors
RTC_DATA_ATTR char sensor_list[MAX_NUMBER_SENSORS];           // array to store the names of the available sensors

// Global (static) buffers
char SHA256PayLoad[80];                           // combined string which goes into SHA256
char httpRequestData[2048];                       // data to be sent
char timeStamp[128];                              // GSM datetime

// Define class for the sensors that require one
Adafruit_TSL2591 tsl = Adafruit_TSL2591(2591); // pass in a number for the sensor identifier (for your use later)
Adafruit_MLX90614 mlx = Adafruit_MLX90614();
SHTSensor sht30(SHTSensor::SHT3X);                // sensor type SHT3X variable
DHT dht(DHTPIN, DHTTYPE);   //   DHT11 DHT21 DHT22 (Grove temperature and humidity sensor)

// Define Grove Ultrasonic Ranger Signal Pin
Ultrasonic ultrasonic(25);

//....................................................................................................
//....................................................................................................
//....................................................................................................
//....................................................................................................
//....................................................................................................
//....................................................................................................
void setup() {
//....................................................................................................  
/* variable definition */
  uint8_t mac[6];                                   // MAC address
  char loggerID[18];                                  // ID of the logger, include MAC address
  uint16_t batV;                                    // voltage of battery
  uint16_t solarV;                                  // voltage of Solar Panel  
  
  float TSL_IR = -999.99;                       // TSL2591 Infrared, init with error value
  float TSL_Full = -999.99;                       // TSL2591 Full Spectrum, init with error value 
  float TSL_IR_percentage = -999.99;                             // TSL2591 percentage of IR, init with error value
  float TSL_Full_percentage = -999.99;                      // TSL2591 percentage of Full Spectrum, init with error value

  float air_rel_humidity = -999.99;                   // Grove air relative humidity, init with error value 

  float soil_temp = -999.99;                          // SHT30 soil temperature, init with error value 
  float soil_rel_humidity = -999.99;                  // SHT30 soil relative humidity, init with error value 

  float MLX_amb_temp = -999.99;                       // ambient temperature of MLX90614 non-contact IR thermometer, init with error value
  float MLX_obj_temp = -999.99;                      // object temperature of MLX90614 non-contact IR thermometer, init with error value

  float GROVE_distance = -999.99;                    // distance measured from surface (Grove sensor), init with error value
  float GROVE_corr_distance = -999.99;               // distance with correction of temperature dependency, init with error value
  float GROVE_surf_height = -999.99;                 // surface height (snow height), init with error value
  float GROVE_distance_tmp = -999.99;                 // temporary save of the distance measured from surface, init with error value

  float HCSR_distance = -999.99;                 // distance measured from surface (HCSR04 sensor), already temperature-corrected, init with error value
  float HCSR_surf_height = -999.99;              // surface height (snow height), init with error value
  float HCSR_duration_tmp = -999.99;             // temporary save of the pulse duration of HCSR-04, init with error value

  float temp_hum_tmp[2] = {0};                   // temporary save of the air temperature and air relative humidity
    
  float signalStrength = -999.99;                   // network signal strength, init with error value  
  unsigned long millisAtConnection;                 // millis() when initiating network - to compute sleepSecs
  bool postSuccess = false;                         // whether the http response was successful (2XX) or not
  int sleepSeconds = SLEEP_MINUTES * 60;            // this is the default value, valid if time update from network fails  
  
  bool apnConnected = false;                        // bool: wether we connected to APN
  bool batteryStatus = false;                       // battery ok for turning on the modem?
  
  char hashedKey[64];                               // hashed payloag from SHA256 as a string for the JSON
  DynamicJsonDocument JSONData(2048);               // to store data for transmission as JSON
  int len;                                          // helper variable to store the length of something

  // HCSR04 sets trigPin as an output and echoPin as an input
  pinMode(trigPin, OUTPUT);
  pinMode(echoPin, INPUT);

//....................................................................................................
/* indicate start of code and WDT running */

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);
  blink_led(3, 100);                                // light show: start of code and watchdog
  esp_task_wdt_init(WDT_TIMEOUT, true);             // enable panic so ESP32 restarts
  esp_task_wdt_add(NULL);                           // add current thread to WDT watch

//....................................................................................................  
/* Communication Init, collect basic information */  
  Serial.begin(115200);                               // Init Console and send after several infos
  Wire.begin();
  delay(1000);                                      
  Serial.print("\nsetup()running on core ");
  Serial.println(xPortGetCoreID());
  Serial.printf("watchdog configured with %d s timeout...\n", WDT_TIMEOUT);
  Serial.printf("This is git commit %s\n", GIT_VERSION);
  Serial.printf("Compile date and source file: %s\n", COMPILE_DATE_FILE);
  
  ESP_ERROR_CHECK_WITHOUT_ABORT(esp_efuse_mac_get_default(mac));  // read MAC address
  sprintf(loggerID, "%02x:%02x:%02x:%02x:%02x:%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  Serial.printf("\nMAC: %s\n", loggerID);

/* GPS RNT Code to get local time and coordinates of the station 
  // Set LED OFF
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);

  //Turn on the modem
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(300);
  digitalWrite(PWR_PIN, LOW);

  delay(1000);
  
  // Set module baud rate and UART pins
  SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX);

  // Restart takes quite some time
  // To skip it, call init() instead of restart()
  Serial.println("Initializing modem...");
  if (!modem.init()) {
    Serial.println("Failed to initialize modem, attempting to continue without  initializing");
  }
  
  // Print modem info
  String modemName = modem.getModemName();
  delay(500);
  Serial.println("Modem Name: " + modemName);

  String modemInfo = modem.getModemInfo();
  delay(500);
  Serial.println("Modem Info: " + modemInfo);

  // Set SIM7000G GPIO4 HIGH, turn on GPS power
  // CMD:AT+SGPIO=0,4,1,1
  // Only in version 20200415 is there a function to control GPS power
  modem.sendAT("+SGPIO=0,4,1,1");
  if (modem.waitResponse(10000L) != 1) {
    Serial.println(" SGPIO=0,4,1,1 false ");
  }

  modem.enableGPS();
  
  delay(15000);
  float lat      = 0;
  float lon      = 0;
  float speed    = 0;
  float alt     = 0;
  int   vsat     = 0;
  int   usat     = 0;
  float accuracy = 0;
  int   year     = 0;
  int   month    = 0;
  int   day      = 0;
  int   hour     = 0;
  int   min      = 0;
  int   sec      = 0;
  
  for (int8_t i = 15; i; i--) {
    Serial.println("Requesting current GPS/GNSS/GLONASS location");
    if (modem.getGPS(&lat, &lon, &speed, &alt, &vsat, &usat, &accuracy,
                     &year, &month, &day, &hour, &min, &sec)) {
      Serial.println("Latitude: " + String(lat, 8) + "\tLongitude: " + String(lon, 8));
      Serial.println("Speed: " + String(speed) + "\tAltitude: " + String(alt));
      Serial.println("Visible Satellites: " + String(vsat) + "\tUsed Satellites: " + String(usat));
      Serial.println("Accuracy: " + String(accuracy));
      Serial.println("Year: " + String(year) + "\tMonth: " + String(month) + "\tDay: " + String(day));
      Serial.println("Hour: " + String(hour) + "\tMinute: " + String(min) + "\tSecond: " + String(sec));
      break;
    } 
    else {
      Serial.println("Couldn't get GPS/GNSS/GLONASS location, retrying in 15s.");
      delay(15000L);
    }
  }
  Serial.println("Retrieving GPS/GNSS/GLONASS location again as a string");
  String gps_raw = modem.getGPSraw();
  Serial.println("GPS/GNSS Based Location String: " + gps_raw);
  Serial.println("Disabling GPS");
  modem.disableGPS();

  // Set SIM7000G GPIO4 LOW ,turn off GPS power
  // CMD:AT+SGPIO=0,4,1,0
  // Only in version 20200415 is there a function to control GPS power
  modem.sendAT("+SGPIO=0,4,1,0");
  if (modem.waitResponse(10000L) != 1) {
    Serial.println(" SGPIO=0,4,1,0 false ");
  }

  /* delay(200);
  // Do nothing forevermore
  while (true) {
      modem.maintain();
  } */

//....................................................................................................

  // mounting LittleFS and reads #records stored in flash
  if(!LittleFS.begin(FORMAT_LITTLEFS_IF_FAILED)){
      Serial.println("LittleFS Mount Failed");
      return;
   }
   else{
       Serial.println("Little FS Mounted Successfully");
   }

//....................................................................................................

/* Read Houskeeping value */
  pinMode(PIN_ADC_BAT, INPUT);                      // configure ADC for battery measurement                  
  batV = read_volt_pin(PIN_ADC_BAT);                // get value from ADC in batV
  Serial.printf("Battery voltage [mV]: %u\n", batV);
  pinMode(PIN_ADC_SOLAR, INPUT);                    // configure ADC for solar panel measurement
  solarV = read_volt_pin(PIN_ADC_SOLAR);            // get value from ADC in solarV
  if (batV > 3500 || batV == 0){
    batteryStatus = true;
  }
  
//....................................................................................................  
/* Check Time */
  getTime();                                        // get time from RTC
  Serial.printf("RTC time 01: %s\n", timeStamp); Serial.print(" --- "); Serial.println(rtc.getTime("%d %B %Y %H:%M:%S"));
  sleepSeconds = calc_sleepSeconds();               // check timing; if we have just woken up before the target time, we wait a bit
  if (sleepSeconds < 40){
    sleepDelta += sleepSeconds;
    delay(sleepSeconds * 1000);
    sleepSeconds = calc_sleepSeconds();             // update sleepSeconds
    getTime();                                      // ... and update timestamp
  } else if ((SLEEP_MINUTES * 60) - sleepSeconds < 40){ // ... if we are a bit too late, never mind, but wake up a bit earlier next time
    sleepDelta += sleepSeconds - (SLEEP_MINUTES * 60);
  }
  if (sleepDelta > 10){                             // the sleepDelta should remain small
    sleepDelta = 10;
  }
  if (sleepDelta < -10){
    sleepDelta = -10;
  }
  millisAtConnection = millis();                    // store millis when you are here, to compute sleepSecs later   
  Serial.printf("RTC time: %s\n", timeStamp);
  Serial.printf("Seconds to sleep when going to sleep: %d\n", sleepSeconds);
  Serial.printf("Correction of sleep seconds based on past connects: %d\n", sleepDelta);

//....................................................................................................  

// print RTC Time
  Serial.println(rtc.getTime("%A, %B %d %Y %H:%M:%S"));   // (String) returns time with specified format 
  struct tm timeinfo = rtc.getTimeStruct();
  //Serial.println(&timeinfo, "%A, %B %d %Y %H:%M:%S");   //  (tm struct) Sunday, January 17 2021 07:24:38

//....................................................................................................
/* Open a file for the sensor measurements in LittleFS and add the RTC time to it */  
  LittleFS.begin();
  File sensDataFile = LittleFS.open("/sensdata.txt","a");

  // Time set with RTC
  sensDataFile.println(rtc.getTime("%A, %B %d %Y %H:%M:%S"));   // (String) returns time with specified format 

  // Satellite Time
  //sensDataFile.println(String(year) + "." + String(month) + "." + String(day) + "-" + String(hour) + ":" + String(min) + "." + String(sec) + " UTC ");

/* For the first loop, check which sensors are available and write the sensor names in an array */
  if (loopCounter == 0) {

    if (tsl.begin()) {
      sensor_list[sensor_counter] = 't';
      sensor_counter++;
    }

    if (sht30.init()) {
      sensor_list[sensor_counter] = 's';
      sensor_counter++;
    }

    if (mlx.begin()) {
      sensor_list[sensor_counter] = 'm';
      sensor_counter++;
    }

    if (!dht.readTempAndHumidity(temp_hum_tmp)) {
      sensor_list[sensor_counter] = 'a';
      sensor_counter++;
    }

    GROVE_distance_tmp = ultrasonic.read();
    if ((GROVE_distance_tmp != 357) && (GROVE_distance_tmp != float(-999.99))) {
      sensor_list[sensor_counter] = 'g';
      sensor_counter++;
    }

    HCSR_duration_tmp = pulseIn(echoPin, HIGH);
    if((HCSR_duration_tmp > 0) && (HCSR_duration_tmp != float(-999.99))) {
      sensor_list[sensor_counter] = 'h';
      sensor_counter++;
    }

  }

  Serial.print("Number of available sensors: "); Serial.println(sensor_counter);

  blink_led(sensor_counter, 300);                        // blink LED the number of sensors that are available
  
/* Print the list of available sensors */
  Serial.println("The following sensors are available: ");
  Serial.println("[Legend: t = TSL2591; s = SHT30; m = MLX90614; g = Grove distance sensor; h = HCSR04; a = Grove temperature and humidity sensor]");

  for (list_count = 0; list_count < sensor_counter; list_count++){
    Serial.println(sensor_list[list_count]);
  }

  Serial.print("Loop count: "); Serial.println(loopCounter);

//....................................................................................................
/* sensor measurements */
  // MLX90614 non-contact IR temperature sensor 
  for (list_count = 0; list_count < sensor_counter; list_count++){
    // MLX90614
    if (sensor_list[list_count] == 'm') {
      mlx_measurement(&MLX_amb_temp, &MLX_obj_temp);

      sensDataFile.print("Ambient temperature: "); sensDataFile.print(MLX_amb_temp); sensDataFile.print(" °C");
      sensDataFile.print("\tObject temperature: "); sensDataFile.print(MLX_obj_temp); sensDataFile.println(" °C");
    }

    // Grove air temperature and humidity measurement
    if (sensor_list[list_count] == 'a') {
      grove_temp_measurement(&air_temp, &air_rel_humidity);

      sensDataFile.print("Air temperature: "); sensDataFile.print(air_temp); sensDataFile.print(" °C");
      sensDataFile.print("\tAir relative humidity: "); sensDataFile.print(air_rel_humidity); sensDataFile.println(" %");
    }
    
    // Grove ultrasonic distance sensor
    if (sensor_list[list_count] == 'g') {
      grove_measurement(&GROVE_distance, &GROVE_corr_distance, &GROVE_surf_height);

      sensDataFile.print("Distance Grove: "); sensDataFile.print(GROVE_corr_distance); sensDataFile.print(" m ");
      sensDataFile.print("\tSnow height Grove: "); sensDataFile.print(GROVE_surf_height); sensDataFile.println(" m ");
    }

    // TSL2591
    if (sensor_list[list_count] == 't') {
      configureSensor();
      
      tsl_measurement(&TSL_IR, &TSL_Full, &TSL_IR_percentage, &TSL_Full_percentage);

      sensDataFile.print("IR: "); sensDataFile.print(TSL_IR);
      sensDataFile.print("\tFull: "); sensDataFile.print(TSL_Full);
      sensDataFile.print(" \tIR percent: "); sensDataFile.print(TSL_IR_percentage); sensDataFile.print(" % ");
      sensDataFile.print("\tFull percent: "); sensDataFile.print(TSL_Full_percentage); sensDataFile.println(" %");
    }

    // SHT30
    if (sensor_list[list_count] == 's') {
      sht30_measurement(&soil_temp, &soil_rel_humidity);

      sensDataFile.print("Soil temperature: "); sensDataFile.print(soil_temp); sensDataFile.print(" °C");
      sensDataFile.print("\tSoil relative humidity: "); sensDataFile.print(soil_rel_humidity); sensDataFile.println(" %");
    }

    // HCSR04 snow height measurement 
    if (sensor_list[list_count] == 'h') {
      hcsr_measurement(&HCSR_distance, &HCSR_surf_height);

      sensDataFile.print("Distance HCSR04: "); sensDataFile.print(HCSR_distance); sensDataFile.print(" m ");
      sensDataFile.print("\tSnow height HCSR04: "); sensDataFile.print(HCSR_surf_height); sensDataFile.println(" m ");
    }
  }

//....................................................................................................  

// Read file on LittleFS and close the file with the sensor measurements
  sensDataFile.close();

  sensDataFile = LittleFS.open("/sensdata.txt","r");
  while(sensDataFile.available()) {
  String line = sensDataFile.readStringUntil('\n');
  Serial.println(line);
  }
  sensDataFile.flush();
  sensDataFile.close();
  
//....................................................................................................  

/* Prepare data to be published */
  if (JSON_PY_API){                      // if we do json/py, we start populating a JSON doc
    snprintf(SHA256PayLoad, sizeof(SHA256PayLoad), "%s; %s; %s", SITE_ID, loggerID, timeStamp);
    hashing(SHA256PayLoad, hashedKey);
    // Serial.printf("%s | %s\n", SHA256PayLoad, hashedKey);
    // now populate JSON doc
    JSONData["sign"] = hashedKey;
    JSONData["timestamp"] = timeStamp;
    JSONData["TSL_IR"] = TSL_IR;
    JSONData["TSL_Full"] = TSL_Full;
    JSONData["TSL_IR_percentage"] = TSL_IR_percentage;
    JSONData["TSL_Full_percentage"] = TSL_Full_percentage;
    JSONData["MLX_amb_temp"] = MLX_amb_temp;
    JSONData["MLX_obj_temp"] = MLX_obj_temp;
    JSONData["GROVE_distance"] = GROVE_distance;
    JSONData["GROVE_surf_height"] = GROVE_surf_height;
    JSONData["HCSR_distance"] = HCSR_distance;
    JSONData["HCSR_surf_height"] = HCSR_surf_height;
    JSONData["soil_rel_humidity"] = soil_rel_humidity;
    JSONData["soil_temp"] = soil_temp;
    JSONData["air_temp"] = air_temp;
    JSONData["air_rel_humidity"] = air_rel_humidity;
    JSONData["U_Battery"] = batV;
    JSONData["U_Solar"] = solarV;
    JSONData["loggerID"] = loggerID;
    JSONData["git_version"] = GIT_VERSION;
  } else {                               // if we do php, we use a traditional String. 
    len = sprintf(httpRequestData, "timestamp=%s", timeStamp);
    len += sprintf(httpRequestData + len, "&TSL_IR=%.2f", TSL_IR);
    len += sprintf(httpRequestData + len, "&TSL_Full=%.2f", TSL_Full);
    len += sprintf(httpRequestData + len, "&TSL_IR_percentage=%.2f", TSL_IR_percentage);
    len += sprintf(httpRequestData + len, "&TSL_Full_percentage=%.2f", TSL_Full_percentage);
    len += sprintf(httpRequestData + len, "&MLX_amb_temp=%.2f", MLX_amb_temp);
    len += sprintf(httpRequestData + len, "&MLX_obj_temp=%.2f", MLX_obj_temp);
    len += sprintf(httpRequestData + len, "&GROVE_distance=%.4f", GROVE_corr_distance);
    len += sprintf(httpRequestData + len, "&GROVE_surf_height=%.4f", GROVE_surf_height);
    len += sprintf(httpRequestData + len, "&HCSR_distance=%.4f", HCSR_distance);
    len += sprintf(httpRequestData + len, "&HCSR_surf_height=%.4f", HCSR_surf_height);
    len += sprintf(httpRequestData + len, "&soil_rel_humidity=%.2f", soil_rel_humidity);
    len += sprintf(httpRequestData + len, "&soil_temp=%.2f", soil_temp);
    len += sprintf(httpRequestData + len, "&ta=%.2f", air_temp);
    len += sprintf(httpRequestData + len, "&rh=%.2f", air_rel_humidity);
    len += sprintf(httpRequestData + len, "&U_Battery=%u", batV);
    len += sprintf(httpRequestData + len, "&U_Solar=%u", solarV);
    len += sprintf(httpRequestData + len, "&loggerID=%s", loggerID);
    len += sprintf(httpRequestData + len, "&git_version=%s", GIT_VERSION);
  }

//....................................................................................................  
/* try to publish to network, publish old values, or store new one in database if no comm */  
   Serial.println("If battery allows, attempt transmission.");
   if (batteryStatus){                               // enough power to discuss with modem
     apnConnected = connect_to_network(&signalStrength);
     if (apnConnected){                              // if network works
       Serial.println("... OK");
       set_rtc_to_network_datetime();                // get and set current date / time to RTC
      
       // network signal strength; append to httpRequestData (via JSON or String)
       signalStrength = modem.getSignalQuality();           
       Serial.printf("Signal quality: %f\n", signalStrength);
       if (JSON_PY_API){
         JSONData["signalStrength"] = signalStrength;
         serializeJson(JSONData, httpRequestData);                  // convert JSON to string for transmission
       } else {
         len += sprintf(httpRequestData + len, "&signalStrength=%f", signalStrength);
       }

       // send data
       postSuccess = send_data_to_server(httpRequestData);
       if (postSuccess){   // if submission sucessful
        // check whether we have any leftover data and try to submit these (only if this post request successful)
         if (RecordsInFlash > 0){
           transmit_stored_records(5);                    // submit up to 5 records from the flash
         }
       }
     } else {                                       // apnconnect did not work...
      // append error code in SignalStrength (via JSON or String) 
       if (JSON_PY_API){
         JSONData["signalStrength"] = signalStrength;
         serializeJson(JSONData, httpRequestData); 
       } else {
         len += sprintf(httpRequestData + len, "&signalStrength=%f", signalStrength);
       }      
     } 
   } else {
     blink_led(4, 200);                              // lightshow: battery low, don't try to init modem
   }

   if (!apnConnected || !postSuccess){                               // plan B: store, reset modem, sleep
     Serial.println("... fail. Storing measurements to flash, resetting modem and going to sleep.");    
     if (RecordsInFlash < MAX_RECORDS){                     // don't store too many records... reading the file becomes slow.
       store_data_on_flash(httpRequestData);
     } else {
       Serial.printf("Already %d records in flash. Current record not stored.\n", MAX_RECORDS);
     }
     if (batteryStatus){                             // if no connection despite enough battery      
       blink_led(8, 200);                            // light show: issue with connection
       modem_reset();                                // do a hard reset before going to slread_nb_recordseep             
     }
   }
  read_nb_records();                                // read #records currently stored in flash
  
//....................................................................................................              
/* end of code, initiate sleep mode until next measurement (start again setup function at wakeup) */  
  clients.stop();
  Serial.println("Server disconnected");
  Serial.print("Powering-off modem");                    
  modem_off();

  LittleFS.end(); // unmount file system

  // check whether it's time for a reset of the ESP
  loopCounter++;  
  if (loopCounter >= MAX_LOOPS){                                         // restart
    loopCounter = 0;
    Serial.printf("I have gone through %d loops, enough is enough. Restarting the ESP32 now.\n", MAX_LOOPS);
    ESP.restart();    
  }
  
  // now go to sleep  
  // update sleep time incl network time and delta
  sleepSeconds = sleepSeconds - (int)((float)(millis() - millisAtConnection) / 1000.0) + 
    sleepDelta;  
  if (sleepSeconds > SLEEP_MINUTES * 60){              // some plausibility checks
    sleepSeconds = SLEEP_MINUTES * 60;
  }
  if (sleepSeconds < 0){
    sleepSeconds = 0;
  }
  Serial.print("Going to sleep. sleepsecs incl correction for network time and delta: ");
  Serial.println(sleepSeconds);   
  esp_sleep_enable_timer_wakeup((sleepSeconds) * uS_TO_S_FACTOR);
  delay(200);
  blink_led(3, 600);                                    // light show: end of code
  esp_deep_sleep_start();
}


/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------    MAIN CODE UP   ---------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*-------------------------------------------------    FUNCTIONS CODE DONW   -----------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
void loop() {
  // with Deep Sleep Mode requested at the end of setup(), this section will never reached. All sketch in setup().
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         modem_reset
 * description :  do a hardware reset of the modem, inspired by https://github.com/nikil511/LilyGO-T-SIM7000G/blob/master/examples/Platformio_Arduino_Thingsboard/src/main.cpp
 * input :        void
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void modem_reset()
{
  Serial.println("Modem hardware reset... (6s)");
  pinMode(MODEM_RST, OUTPUT);
  digitalWrite(MODEM_RST, LOW);
  delay(260); //Treset 252ms
  digitalWrite(MODEM_RST, HIGH);
  delay(6000); 
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         modem_off
 * description :  does the power-off of the modem
 * input :        void
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/

void modem_off(){
  if(modem.poweroff()){                                    // turn off modem  
    Serial.println("... OK");
  } else {                                                 // if this fails, assume that the modem has not been initialized and cannot process AT commands
    SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX); // establish serial connection with modem
    delay(1000);
    //SerialAT.flush();                                      // clean Serial buffer
    if (modem.init()){
      if(modem.poweroff()){                                    // turn off modem      
        Serial.println("... OK after 2nd init");        
      }
    } else {
      Serial.println("... soft power-off fail. Let's hope that the modem has never powered on.");
/*      
      if (digitalRead(PWR_PIN) == 1){
        pinMode(PWR_PIN, OUTPUT);
        digitalWrite(PWR_PIN, HIGH);
        delay(30);
        digitalWrite(PWR_PIN, LOW);
        delay(1300);    //Datasheet Ton mintues = 1.2S
        digitalWrite(PWR_PIN, HIGH);
        delay(1700);
      }
      */
    }
  } 
  
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, LOW);                              // pull pwr_pin low, to prevent esp from restarting the modem
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         connect_to_network
 * description :  do init of the modem
 * input :        void
 * output :       boolean - whether everything needed to connect to apn worked out
 * ------------------------------------------------------------------------------------------------------------------------------*/
bool connect_to_network(float* signalStrength){
// power on modem....................................................................................................   
  Serial.println("Powering on modem... (6s)");     // power on modem and give it some time to wake up (https://github.com/vshymanskyy/TinyGSM/issues/381) 
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(30);
  digitalWrite(PWR_PIN, LOW);
  delay(100); // Ton 73 ms
  digitalWrite(PWR_PIN, HIGH);
  delay(6000);

// establish communication with and initialize modem....................................................................................................   
  SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX); // establish serial connection with modem
  delay(1000);
  if (modem.init()) {
    Serial.println("   ... init modem successful ...");
  } else {  
    *signalStrength = -333.0;                      // error code - init failed                           
    Serial.println("  failed to init modem. Try a soft / hard reset of the modem.");
    esp_task_wdt_reset();
    if (modem.restart()){
      Serial.println("Modem soft restart successful.");
    } else {
      *signalStrength = -444.0;                    // error code - soft reset failed
      esp_task_wdt_reset();
      modem_reset();
      if (modem.init()){                            //        after hardware reset, try a init
        Serial.println("Init modem successful after hard reset.");
      } else {
        *signalStrength = -555.0;                  // error code - hard reset failed
        Serial.println("Failed to init modem after hard reset.");
        return false;
      }
    }
  }
  
  // get APN from SIM card or use DEFAULT_APN
  const char* APN=get_apn(modem.getIMSI().substring(0, 5).c_str());
  Serial.printf("My APN now is: %s\n", APN);

  // configure modem and connect to network and APN ....................................................................................................     
  modem.sendAT("+SGPIO=0,4,1,0");                   // Set SIM7000G GPIO4 LOW, turn off GPS power (only for board version 20200415)
  if (sizeof(GSM_PIN) != 0 && modem.getSimStatus() != 3) {       // Unlock your SIM card with a PIN if needed
    modem.simUnlock(GSM_PIN);
  }
  
  Serial.print("Setting network modes... ");        // set network modes
  while (!modem.setNetworkMode(NETWORK_MODE)){                // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE only 
    delay(100);
  }
  while (!modem.setPreferredMode(3)){               // 1 CAT-M; 2 NB-Iot; 3 CAT-M and NB-IoT
    delay(100);
  }

  /* PDP Context
  int counter, lastIndex, numberOfPieces = 24;
  String pieces[24], input;
  SerialAT.println("AT+CGDCONT?");
  delay(500);
  if (SerialAT.available()) {
      input = SerialAT.readString();
      for (int i = 0; i < input.length(); i++) {
          if (input.substring(i, i + 1) == "\n") {
              pieces[counter] = input.substring(lastIndex, i);
              lastIndex = i + 1;
              counter++;
          }
          if (i == input.length() - 1) {
              pieces[counter] = input.substring(lastIndex, i);
          }
      }
      // Reset for reuse
      input = "";
      counter = 0;
      lastIndex = 0;

      for ( int y = 0; y < numberOfPieces; y++) {
          for ( int x = 0; x < pieces[y].length(); x++) {
              char c = pieces[y][x];  //gets one byte from buffer
              if (c == ',') {
                  if (input.indexOf(": ") >= 0) {
                      String data = input.substring((input.indexOf(": ") + 1));
                      if ( data.toInt() > 0 && data.toInt() < 25) {
                          modem.sendAT("+CGDCONT=" + String(data.toInt()) + ",\"IP\",\"" + String(APN) + "\",\"0.0.0.0\",0,0,0,0");
                      }
                      input = "";
                      break;
                  }
                  // Reset for reuse
                  input = "";
              } else {
                  input += c;
              }
          }
      }
  } else {
      Serial.println("Failed to get PDP!");
  }*/
  
  // connect to network
  Serial.print("Waiting for network... ");
  modem.waitForNetwork();                           // this tries to connect for 60s
  if (!modem.isNetworkConnected()){                 // if this did not succeed...
    //Serial.println("in vain. Setting pdp-context and trying to connect again.");
    Serial.println("in vain.");
    // esp_task_wdt_reset();                           // reset watchdog
    set_pdp(APN);                                      // try to set pdp-context explicitly...    
  }
  
  if (modem.isNetworkConnected()) {                 // if successful, we connect to apn
    *signalStrength = -777.0;                       // error code - signalStrength remains at this if apn-connect fails
    Serial.println("Network connected");
    Serial.printf("Connecting to: %s", APN);  //    connect to APN
    return modem.gprsConnect(APN, GPRS_USER, GPRS_PASS);
  } else {
    *signalStrength = -666.0;                       // error code - network connect failed
    return false;   
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         send_data_to_server
 * description :  do init of the modem
 * input :        data to send
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
bool send_data_to_server(const char* httpRequestData){
  // select content type according to API
  const char* contentType = JSON_PY_API ? "application/json" : "application/x-www-form-urlencoded";
  bool success = false;

  long now_secs = rtc.getEpoch();                           // set current time for SSL
  uint32_t ssl_days = 719528 + elapsedDays(now_secs);
  uint32_t ssl_secs = elapsedSecsToday(now_secs);
//  Serial.printf("For SSL dating: Days since AD: %u, Secs of today: %u\n", ssl_days, ssl_secs);
//  clients.setVerificationTime(ssl_days, ssl_secs);
  clients.setInsecure();                                   // TestSSL  
     
  if (clients.connect(SERVER, PORT)){                         // if server is in reach
    Serial.printf("Connected to %s\n", SERVER);
    HttpClient https(clients, SERVER, PORT);                  // init https client  
    https.connectionKeepAlive(); // L200 https://github.com/vshymanskyy/TinyGSM/blob/master/examples/HttpsClient/HttpsClient.ino
    
    Serial.printf("Trying post request -> %s\n", httpRequestData);
    https.post(RESOURCE, contentType, httpRequestData);

    int responseStatusCode = https.responseStatusCode();
    success = (responseStatusCode >= 200 && responseStatusCode < 300);
    if (success) {
      Serial.println("Post request successful.");  
      File sensDataFile = LittleFS.open("/sensdata.txt","a");
      sensDataFile.println("Post request successful");
      sensDataFile.close();
    }
    String response = https.responseBody();
    Serial.printf("Response code: %d; Response body: %s\n", responseStatusCode, response.c_str());
    https.stop();
  } else {
    Serial.printf("Connection to %s failed.\n", SERVER);
  }
  return(success);  
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         configureSensor
 * description :  gain configuration of the TSL2591 sensor
 * input :        void
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void configureSensor(void)
{
  sensor_t sensor;
  tsl.getSensor(&sensor);

  // You can change the gain on the fly, to adapt to brighter/dimmer light situations
  tsl.setGain(TSL2591_GAIN_LOW);    // 1x gain (bright light)
  //tsl.setGain(TSL2591_GAIN_MED);      // 25x gain
  //tsl.setGain(TSL2591_GAIN_HIGH);   // 428x gain
  
  // Changing the integration time gives you a longer time over which to sense light
  // longer timelines are slower, but are good in very low light situtations!
  tsl.setTiming(TSL2591_INTEGRATIONTIME_100MS);  // shortest integration time (bright light)
  // tsl.setTiming(TSL2591_INTEGRATIONTIME_200MS);
  //tsl.setTiming(TSL2591_INTEGRATIONTIME_300MS);
  // tsl.setTiming(TSL2591_INTEGRATIONTIME_400MS);
  // tsl.setTiming(TSL2591_INTEGRATIONTIME_500MS);
  // tsl.setTiming(TSL2591_INTEGRATIONTIME_600MS);  // longest integration time (dim light)

  /* Display the gain and integration time for reference sake */  
  Serial.println(F("------------------------------------"));
  Serial.print  (F("Gain:         "));
  tsl2591Gain_t gain = tsl.getGain();
  switch(gain)
  {
    case TSL2591_GAIN_LOW:
      Serial.println(F("1x (Low)"));
      break;
    case TSL2591_GAIN_MED:
      Serial.println(F("25x (Medium)"));
      break;
    case TSL2591_GAIN_HIGH:
      Serial.println(F("428x (High)"));
      break;
    case TSL2591_GAIN_MAX:
      Serial.println(F("9876x (Max)"));
      break;
  }
  Serial.print  (F("Timing:       "));
  Serial.print((tsl.getTiming() + 1) * 100, DEC); 
  Serial.println(F(" ms"));
  Serial.println(F("------------------------------------"));
  Serial.println(F(""));
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         tsl_measurement
   description :  do two measure, check plausibility, store the IR and Full spectrum measurements in two variables, calculate the percentage of irradiance measured
   input :        void
   output :       infrared, fullSpectrum, fullSpectrum_percentage
   ------------------------------------------------------------------------------------------------------------------------------*/
void tsl_measurement(float* infrared, float* fullSpectrum, float*infrared_percentage, float* fullSpectrum_percentage){  
  uint32_t lum1, lum2;
  uint16_t ir1, ir2, full1, full2;
  int i = 0;                                                                   // init counter i
  int nb_try = 5;                                                              // number of try to have good measure
  bool plausibility = false;                                                   // init plausibilty to false

  tsl.begin();
  
  while (i <= nb_try && plausibility != true){                                  // try to have plausible value max nb_try                                                         
    lum1 = tsl.getFullLuminosity();
    ir1 = lum1 >> 16;
    full1 = lum1 & 0xFFFF;
    delay(500);
    lum2 = tsl.getFullLuminosity();
    ir2 = lum2 >> 16;
    full2 = lum2 & 0xFFFF;
      
    if (fabs(lum1 - lum2) < 100 && lum1 > 0) {            // check plausibility
      *infrared = (ir1 + ir2) / 2.0;
      *fullSpectrum = (full1 + full2) / 2.0;
      *infrared_percentage = ((ir1 + ir2) / 2.0)/37888*100;
      *fullSpectrum_percentage = ((full1 + full2)/2.0)/37888*100;

      plausibility = true;
      Serial.print(F("[ ")); Serial.print(millis()); Serial.print(F(" ms ]"));
      Serial.print(F("\tIR: ")); Serial.print(*infrared);
      Serial.print(F("\tFull: ")); Serial.print(*fullSpectrum);
      Serial.print("\tVisible: "); Serial.println(*fullSpectrum - *infrared);
      Serial.print(F("IR percent: ")); Serial.print(*infrared_percentage); Serial.print(F("%  "));
      Serial.print(F("\tFull percent: ")); Serial.print(*fullSpectrum_percentage); Serial.println(F("%  "));
    } else {
      *infrared = -999.99;
      *fullSpectrum = -999.99;
      *fullSpectrum_percentage = -999.99;
      plausibility = false;
      }
    i++;
    // Serial.print("Plausibility: "); Serial.println(plausibility);
    }
    //return plausibility;
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         sht30_measurement
   description :  do two measure, check plausibility
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
bool sht30_measurement(float* temperature, float* humidity){  
  float measureTemp1, measureTemp2, measureHum1, measureHum2;
  int i = 0;                                                                   // init counter i
  int nb_try = 5;                                                              // number of try to have good measure
  bool plausibility = false;                                                   // init plausibilty to false

  sht30.init();
  
  while (i <= nb_try && plausibility != true){                                  // try to have plausible value max nb_try
    if (sht30.init()){                                                         
      sht30.setAccuracy(SHTSensor::SHT_ACCURACY_HIGH);                         // only supported by SHT3x
      sht30.readSample();
      measureTemp1 = sht30.getTemperature();                                   // first set of values      
      measureHum1 = sht30.getHumidity();
      sht30.readSample();
      measureTemp2 = sht30.getTemperature();                                   // second set of values
      measureHum2 = sht30.getHumidity();
      
      if (fabs(measureTemp1 - measureTemp2) < 1 && measureTemp1 < 99 &&
          measureTemp1 > -80.0) {            // check plausibility
        *temperature = (measureTemp1 + measureTemp2) / 2.0;
        *humidity = (measureHum1 + measureHum2) / 2.0;
        plausibility = true;

        Serial.print("Soil temperature: "); Serial.print(*temperature); Serial.print(" °C");
        Serial.print("\t Soil relative humidity: "); Serial.print(*humidity); Serial.println(" %");
      } else {
        *temperature = -999.99;
        *humidity = -999.99;
        plausibility = false;
      }
    }
    i++;
  } 
  return plausibility;
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         grove_temp_measurement
   description :  do two measure, check plausibility
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
bool grove_temp_measurement(float* temperature, float* humidity){  
  int i = 0;                                                                   // init counter i
  int nb_try = 5;                                                              // number of try to have good measure
  bool plausibility = false;                                                   // init plausibilty to false
  float temp_hum_val[2] = {0};
  float temp_hum_val_2[2] = {0};
  
  while (i <= nb_try && plausibility != true){                                  // try to have plausible value max nb_try
    if (!dht.readTempAndHumidity(temp_hum_val)) {
      dht.readTempAndHumidity(temp_hum_val_2);
      if (fabs(temp_hum_val[1] - temp_hum_val_2[1]) < 1 && temp_hum_val[1] < 80 && temp_hum_val[1] > -40.0) {
        *temperature = (temp_hum_val[1] + temp_hum_val_2[1])/2;
        *humidity = (temp_hum_val[0] + temp_hum_val_2[0])/2;
        plausibility = true;
        Serial.print("Air Temperature: "); Serial.print(*temperature); Serial.print(" °C");
        Serial.print("\tAir relative humidity: "); Serial.print(*humidity); Serial.println(" %");
      }
      else {
        *temperature = -999.99;
        *humidity = -999.99;
        plausibility = false;
      }
    i++;
    }
  }
  return plausibility;
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         mlx_measurement
   description :  measures ambient and object temperature, takes two measurements and checks plausibility
   input :        void
   output :       amb_temp, obj_temp
   ------------------------------------------------------------------------------------------------------------------------------*/
void mlx_measurement(float* amb_temp, float* obj_temp){
  int i = 0;
  int i_max = 5;
  bool plausibility = false;
  float measureAmb1, measureAmb2, measureObj1, measureObj2;

  mlx.begin();

  Serial.print("MLX90614 Emissivity = "); Serial.println(mlx.readEmissivity());

  while (i < i_max && !plausibility){
    measureAmb1 = mlx.readAmbientTempC();
    measureObj1  = mlx.readObjectTempC();
    delay(10);
    measureAmb2 = mlx.readAmbientTempC();
    measureObj2  = mlx.readObjectTempC();

    if (fabs(measureObj1-measureObj2) < 1.0 && measureObj1 < 99.0 && measureObj1 > 0.0){
      *amb_temp = (measureAmb1 + measureAmb2)/2;
      *obj_temp = (measureObj1 + measureObj2)/2;
      plausibility = true;
      Serial.print("Ambient temperature = "); Serial.print(*amb_temp);
      Serial.print(" °C\tObject temperature = "); Serial.print(*obj_temp); Serial.println(" °C");
    }

    else {
      *amb_temp = -999.99;
      *obj_temp = -999.99;
      plausibility = false;
    }
    i++;
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         grove_measurement
   description :  measures distance to object (with temperature-dependency correction), and calculates snow height, checks plausibility
   input :        void
   output :       distance, corr_distance, snow_height
   ------------------------------------------------------------------------------------------------------------------------------*/
void grove_measurement(float* distance, float* corr_distance, float* snow_height){
  float duration;
  float sound_speed;
  int i = 0;
  int i_max = 5;
  bool plausibility = false;
  float measureDist1, measureDist2;
  float max_height = 200;

  while (i < i_max && !plausibility){
    measureDist1 = ultrasonic.read();
    delay(10);
    measureDist2 = ultrasonic.read();

    if (fabs(measureDist1-measureDist2) < 1.0 && measureDist1 > 0 && measureDist1 < max_height){
      *distance = (measureDist1 + measureDist2)/200; // average measured distance in m
      duration = *distance * 2/340;   // duration of the signal in s
      // calculates the sound speed as a function of temperature (Grove temperature readings)
      sound_speed = 331.2 * sqrt(1 + air_temp/273.15);

      // calculates the distance with the corrected sound speed (temperature influence)
      *corr_distance = duration * sound_speed/2;

      *snow_height = sensor_height - *corr_distance;

      plausibility = true;
      Serial.print("Grove Distance in m: ");
      Serial.print(*corr_distance);
      Serial.print("\tGrove Snow height in m: ");
      Serial.println(*snow_height);
    }

    else {
      *distance = -999.99;
      *corr_distance = -999.99;
      *snow_height = -999.99;
      plausibility = false;
    }
    i++;
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         hcsr04_measurement
   description :  measures distance to object (with temperature-dependency correction) and calculates snow height, checks plausibility
   input :        void
   output :       distance, snow_height
   ------------------------------------------------------------------------------------------------------------------------------*/
void hcsr_measurement(float* distance, float* snow_height){
  long duration;
  float sound_speed;
  int i = 0;
  int i_max = 5;
  bool plausibility = false;
  float measureDur1, measureDur2;
  float max_height = 4;

  // Clears the trigPin
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  // Sets the trigPin on HIGH state for 10 micro seconds
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);

  while (i < i_max && !plausibility){
    // Reads the echoPin, returns the sound wave travel time in microseconds
    measureDur1 = pulseIn(echoPin, HIGH);
    delay(10);
    measureDur2 = pulseIn(echoPin, HIGH);

    if (fabs(measureDur1 - measureDur2) < 100 && measureDur1 > 0 && measureDur1 < (max_height*2/0.343)) {
      duration = (measureDur1 + measureDur2)/2;
      // calculates the sound speed as a function of temperature (Grove temperature readings)
      sound_speed = 0.03312 * sqrt(1 + air_temp/273.15);

      // Calculates the distance with the corrected sound speed
      *distance = duration * sound_speed/200.;

      // Calculates the snow height
      *snow_height = sensor_height - *distance;

      plausibility = true;
      Serial.print("HCSR Distance in m: ");
      Serial.println(*distance);
      Serial.print("HCSR Snow height in m: ");
      Serial.println(*snow_height);
    }

    else {
      *distance = -999.99;
      *snow_height = -999.99;
      plausibility = true;
    }
    i++;
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         store_data_on_flash
 * description :  if needed, append the current data to a file on flash. 
 * source:        https://techtutorialsx.com/2018/08/13/esp32-arduino-LittleFS-append-content-to-file/
 * input :        httpRequestData: the string to be appended
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void store_data_on_flash(const char* httpRequestData){
  Serial.printf("Storing to flash -> %s\n", httpRequestData);
  File myFile = LittleFS.open("/mydata.txt","a");
  if(!myFile){
    Serial.println("There was an error opening the file for appending");        
  } else {
    myFile.print(httpRequestData);
    myFile.print("\n");
    myFile.flush();
    myFile.close(); 
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name : read_nb_records
 * description : check the number of records stored in the flash
 * input : void
 * output : void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void read_nb_records(){ 
  File myFile = LittleFS.open("/mydata.txt", "r");         // open content of mydata inside EEPROM
  if (!myFile) {            
      Serial.println("Opening /mydata.txt failed - there is likely no such file of stored records.");
  } else {
    while(myFile.available()){                    // read all .txt file and count nb of records
      myFile.find("\n");
      RecordsInFlash++;                           // global variable
    }
    Serial.printf("Number of records stored in flash: %d\n", RecordsInFlash);
    myFile.flush();
    myFile.close();
  }  
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name : transmit_stored_records
 * description : send older data to cloud server, nbMaxTransmits at a time to not overdrain 
 * the battery
 * input : max number of transmit authorized by communication
 * output : void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void transmit_stored_records(int nbMaxTransmits){  
  int foundLeftovers = 0;                            // counter for the nb of lines
  int storedAgain = 0;                               // counter for records stored again
  int transmitAttempts = 0;                          // counter for submission attempts
  int successfulSubmissions = 0;                     // counter for successful submissions
  bool success = false;                              // response code from http post 
  
  File myFile = LittleFS.open("/mydata.txt");
  if(!myFile){
    Serial.println("Failed to open file for reading - cannot transmit stored records.");    
    return;
  }
  
  while(myFile.available()){                            // read all lines 
    esp_task_wdt_reset();                               // reset watchdog
    size_t len = myFile.readBytesUntil('\n', httpRequestData, sizeof(httpRequestData) - 1);
    httpRequestData[len] = '\0';

    foundLeftovers++;
    if (transmitAttempts < nbMaxTransmits){         // try to submit up to nbMaxTransmits records      
      Serial.printf("\nAttempt to transmit stored record %d\n", transmitAttempts + 1);
      success = send_data_to_server(httpRequestData);
      if (success){
        RecordsInFlash--;
        successfulSubmissions++;
      } else {
        Serial.println("Transmission of stored record failed, storing again.");
        File backupFile = LittleFS.open("/tmp.txt", "a");
        if (!backupFile){
          Serial.println("Failed to open temporary file for appending.");         
        } else {
          backupFile.print(httpRequestData);
          backupFile.print("\n");
          backupFile.flush();
          backupFile.close();
          storedAgain++;
        }
      }
      transmitAttempts++;
    } else {                          // store the records that don't belong to the lucky 5 again
      File backupFile = LittleFS.open("/tmp.txt", "a");
      if (!backupFile){
          Serial.println("Failed to open temporary file for appending.");         
      } else {        
        backupFile.print(httpRequestData);
        backupFile.print("\n");
        backupFile.flush();
        backupFile.close();
        storedAgain++;
      }
    }
  }
  myFile.flush();
  myFile.close();
  
  Serial.printf("Records found in flash: %d\n", foundLeftovers);
  Serial.printf("Records stored again in flash: %d\n", storedAgain);
  
  // clean files up - if all file operations worked out as expected; otherwise we try again next time
  if (successfulSubmissions + storedAgain == foundLeftovers){
    LittleFS.remove("/mydata.txt");
    LittleFS.rename("/tmp.txt", "/mydata.txt");
  }
}
 
/* --------------------------------------------------------------------------------------------------------------------------------
 * name : calc_sleepSeconds
 * description : define second to wait until good interval SLEEP_TIME, new time will be a multiple of SLEEP_TIME
 * input : void
 * output : seconds (long)
 * ------------------------------------------------------------------------------------------------------------------------------*/
long calc_sleepSeconds(){
  tmElements_t structNow; // structure to store current time/date
  int prev_min; // previous round SLEEP_MINUTES minute
  
  breakTime(rtc.getEpoch(), structNow);  
  prev_min = floor((float)structNow.Minute / (float)SLEEP_MINUTES) * SLEEP_MINUTES;
  structNow.Minute = prev_min;
  structNow.Second = 0;
  long sleepSeconds = SLEEP_MINUTES * 60 - rtc.getEpoch() + makeTime(structNow);

  if (sleepSeconds > SLEEP_MINUTES * 60){              // some plausibility checks
    sleepSeconds = SLEEP_MINUTES * 60;
  }
  if (sleepSeconds < 0){
    sleepSeconds = 0;
  }
  return(sleepSeconds);
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name : set_rtc_to_network_datetime
 * description : queries date and time from network and sets the RTC to this
 * input : void
 * output : void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void set_rtc_to_network_datetime(){
  int Year = 0;
  int Month = 0;
  int Day = 0;
  int Hour = 0;
  int Min = 0;
  int Sec = 0;
  float timezone;
  
  bool got_date_time = modem.getNetworkTime(&Year, &Month, &Day,
    &Hour, &Min, &Sec, &timezone);

  rtc.setTime(Sec, Min, Hour, Day, Month, Year, 0);
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name : read_volt_pin
 * description : read analogue pin
 * input : pin number 
 * output : voltage [mV] as uint16_6
 * ------------------------------------------------------------------------------------------------------------------------------*/
uint16_t read_volt_pin(int pin){
  uint32_t in = 0;
  for (int i = 0; i < ADC_BATTERY_LEVEL_SAMPLES; i++)
  {
    in += (uint32_t)analogRead(pin);
  }
  in = (int)in / ADC_BATTERY_LEVEL_SAMPLES;

  uint16_t mv = ((float)in / 4096) * 3600 * 2;

  return(mv);
} 

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         blink_led
 * description :  visual effect
 * input :        nb of blinking, delay between
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void blink_led(int nbBlinking, int delayMs){  
  for (int i=0; i< nbBlinking; i++){
      digitalWrite(LED_PIN, LOW);                 // turn on LED
      delay(delayMs); 
      digitalWrite(LED_PIN, HIGH);                // turn off LED
      delay(delayMs);
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         set_pdp
 * description :  sets pdp-context explicitly - if network connection cannot be established
 * input :        void
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
void set_pdp(const char* APN){
  Serial.printf("Trying to set pdp context with %s\n", APN);
  int counter=0;
  int lastIndex=0;
  int numberOfPieces = 24;
  String pieces[24];
  String input;  
  char buffer[100];

  SerialAT.println("AT+CGDCONT?");
  delay(500);
  if (SerialAT.available()) {
    input = SerialAT.readString();
    for (int i = 0; i < input.length(); i++) {
      if (input.substring(i, i + 1) == "\n") {
        pieces[counter] = input.substring(lastIndex, i);
        lastIndex = i + 1;
        counter++;
      }
      if (i == input.length() - 1) {
        pieces[counter] = input.substring(lastIndex, i);
      }
    }
    
    Serial.println(input);
    
    // Reset for reuse
    input = "";
    counter = 0;
    lastIndex = 0;

    for ( int y = 0; y < numberOfPieces; y++) {
      for ( int x = 0; x < pieces[y].length(); x++) {
        char c = pieces[y][x];  //gets one byte from buffer
        if (c == ',') {
          if (input.indexOf(": ") >= 0) {
            String data = input.substring((input.indexOf(": ") + 1));
            if ( data.toInt() > 0 && data.toInt() < 25) {
              snprintf(buffer, sizeof(buffer), "+CGDCONT=%d,\"IP\",\"%s\",\"0.0.0.0\",0,0,0,0", data.toInt(), APN);
              modem.sendAT(buffer);
            }
            input = "";
            break;
          }
          // Reset for reuse
          input = "";
        }
        else {
          input += c;
        }
      }
    }
  } else {
    Serial.println("Failed to get PDP!");
  }


  Serial.println("\nWaiting for network...");
  if (!modem.waitForNetwork()) {
    Serial.println("fail.");
    return;
  }

  if (modem.isNetworkConnected()) {
    Serial.println("Network connected after setting pdp-context explicitly.");
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         get_apn
 * description :  get APN from Tajik network providers - if this fails, use DEFAULT_APN
 * input :        void
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
const char* get_apn(const char* imsi){
  // https://www.mcc-mnc.com/ // imsi information
  // https://www.apnsettings.org/tajikistan/ // apn information
  if (strcmp(imsi, "43604") == 0){           // babilon
      return "babilon";
  } else if (strcmp(imsi, "43603") == 0){    // megafon
      return "internet";
  } else if (strcmp(imsi, "43605") == 0){    // beeline
      return "internet.beeline.tj";
  } else if (strcmp(imsi, "43602") == 0 || strcmp(imsi, "43601") == 0){    // tcell
      return "tcell";
  } else if (strcmp(imsi, "22801") == 0){   // swisscom
      return "gprs.swisscom.ch";
  } else {
      return DEFAULT_APN;
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
 * name :         hashing
 * description :  hashes a string with SHA256. following https://techtutorialsx.com/2018/05/10/esp32-arduino-mbed-tls-using-the-sha-256-algorithm/
 * input :        String - the payload to hash
 * output :       String - the hashed payload as a string
 * ------------------------------------------------------------------------------------------------------------------------------*/
void hashing(const char* payload, char* hashedKey){
  byte shaResult[32];                            // where to store the output from SHA256
  
  mbedtls_md_context_t ctx;
  mbedtls_md_type_t md_type = MBEDTLS_MD_SHA256;
 
  const size_t payloadLength = strlen(payload);
 
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(md_type), 0);
  mbedtls_md_starts(&ctx);
  mbedtls_md_update(&ctx, (const unsigned char *) payload, payloadLength);
  mbedtls_md_finish(&ctx, shaResult);
  mbedtls_md_free(&ctx);  
  
  // convert to readable string
  for (int i=0; i<sizeof(shaResult); i++){    
    sprintf(&hashedKey[i*2],  "%02x", shaResult[i]);
  }  
}

/* ------------------------------------------------------------------------------------------------------------
 * name :         getTime
 * description :  get the time from the rtc and save it as a C string
 * input :        the format string
 * output :       the c string with the RTC datetime
 * ----------------------------------------------------------------------------------------------------------*/
void getTime() {
  struct tm timeinfo = rtc.getTimeStruct();
  strftime(timeStamp, sizeof(timeStamp) - 1, "%Y-%m-%d %H:%M:%S", &timeinfo);
}

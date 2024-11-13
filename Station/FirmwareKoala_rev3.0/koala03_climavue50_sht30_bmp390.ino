/* -----------------------------------------------------------------------------------------------
 * name :         koalaboard03
 * date :         winter 2023/2024
   description :  log data SHT30 and BMP390, possibly from climavue50, and send to cloud
   @authors :     Boris Orlowsky & Jacques Grandjean
 * ------------------------------------------------------------------------------------------------*/
//....................................................................................................
//....................................................................................................
//CHANGES: changed SSL library; reset watchdog before connecting to network and submission of each record
//TODO: can the send_stored_records become more efficient? the copy file operation is slow.
//DONE: implications of outdating trusted anchors
//DONE: minimum battery for write to flash? -> solved by supervisor (HW)
//DONE: include gpio_keep_en or so;
//DONE: check pwr pin for climavue; check power-off for modem - seems to work only if modem is on
//DONE: submit every x loops only; use flash only if mount successful;
//DONE: corrected GSM PIN condition
//DONE: minor serial output, more informative (>= in max_records)

/* SOME RESEARCH on SSL libraries
 *  =============================
 *  both of the following two have similar functionality,
 *  they both allow a disable of the certificate verification
 *
 *  https://github.com/mobizt/ESP_SSLClient/tree/main/examples/gsm
 *  has a specific gsm example; based on bearSSL, similar to the SSLClient that we use so far
 *   is maintained recently(sep 2023)
 *
 *  https://github.com/alkonosst/SSLClientESP32
 *  is a further development of https://github.com/govorox/SSLClient, seems to be very alive;
 *  based on the ESP-internal mbedtls routines.
 *  my current favourite
 *
 *  https://github.com/OPEnSLab-OSU/SSLClient
 *  this is the one we are using so far (bearSSL-based)...
 *  does a good job but has not been updated since 2021.
 *
 *  Qs to David
 *  - is the root certificate at letsencrypt stable now?
 *  - how complete are the certificate bundles from SSLClientESP32? Are they likely to outdate?
 *    it says '41 most used root certificates' :
 *    https://github.com/alkonosst/SSLClientESP32/blob/master/examples/https_wifi_and_sim7600_certbundle/src/main.cpp
 *  - trusted anchors vs certificate bundle
 *  - which library makes the most sense to you?
 *  - can we live with turning off certificate verification? what could a man-in-the-middle do
 *    to us in this setting?
 *
 */

/* CONSTANTS AND CONFIGURATION - TO BE SET / OVERWRITTEN BY FLASHGORDON*/
// const char SITE_ID[] = "FlashSite";      // dummy site ID
// const char SITE_ID[] = "KoalaTest33";    // dummy site ID
const char SITE_ID[] = "MyClimaVue50";      // dummy site ID
const char GIT_VERSION[] = "FlashGIT";      // dummy git version
const char GSM_PIN[] = "";                  // dummy GSM PIN
const char DEFAULT_APN[] = "TM";            // dummy APN
const char GPRS_USER[] = "";                // GPRS credential
const char GPRS_PASS[] = "";                // GPRS credential
const int NETWORK_MODE = 38;                // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE only
const char SERVER[] = "climate-babel.ch";   // domain name: example.com, maker.ifttt.com, etc
const char RESOURCE[] = "/post/insert";     // resource path, for example: /post-data.php
const int  PORT = 443;
const int MAX_LOOPS = 500;
const int MAX_RECORDS = 300;
const bool CLIMAVUE50 = true;               // whether the climavue50 is connected to this station

/* DEFINES - PARTLY BOARD-SPECIFIC*/
#define SerialAT Serial1                    // Serial communication with Modem
#define WDT_TIMEOUT 180                     // for hardware watchdog
#define uS_TO_S_FACTOR 1000000ULL           // Conversion factor for micro seconds to seconds
#define UART_BAUD   9600                    // for the modem
#define PIN_DTR     25
#define PIN_TX      27
#define PIN_RX      26
#define PWR_PIN     33
#define MODEM_RST   32
#define LED_PIN     12                      // for the LED //12 with old one
#define PIN_ADC_BAT1 36                     // resistor not connected on board, measured by coulomb counter
#define PIN_ADC_BAT2 39                     // resistor not connected on board, measured by coulomb counter
#define PIN_ADC_SOLAR 34                    // for solar panel
#define ADC_BATTERY_LEVEL_SAMPLES 10

#define I2C1_SDA 4                          // I2C1 data pins
#define I2C1_SCL 0                          // I2C1 data pins
#define I2C2_SDA 15                         // I2C2 data pins
#define I2C2_SCL 2                          // I2C2 data pins

#define BMP_SCK 18                          // SPI connection pin for BMP390
#define BMP_MISO 19                         // SPI connection pin for BMP390
#define BMP_MOSI 23                         // SPI connection pin for BMP390
#define BMP_CS 5                            // SPI connection pin for BMP390

#define POWER5V_ENABLE 13                   //@BORIS I/O pin to manage 5V power on board (used by climavue50)
#define SDI_pin 14                          // SDI12 data pin

#define TINY_GSM_MODEM_SIM7000              // define modem etc for TinyGSM
#define TINY_GSM_RX_BUFFER 1024             // Set RX buffer to 1Kb

#define SENSOR_READ_EVERY_MINS 10           // time between measurements
#define TRANSMIT_EVERY_MINS 30              // time between transmissions

#if (TRANSMIT_EVERY_MINS % SENSOR_READ_EVERY_MINS != 0)
#error The specified TRANSMIT_EVERY_MINS is not a multiple of SENSOR_READ_EVERY_MINS
#endif

#if (60 % TRANSMIT_EVERY_MINS != 0)
#error The specified TRANSMIT_EVERY_MINS is not a divisor of 60
#endif

/* INCLUDE */
#include <string>
#include <LittleFS.h>                       // file system on flash
#include <TinyGsmClient.h>                  // this library requires the 2 defines above
// #include <SSLClient.h>                   // https://github.com/OPEnSLab-OSU/SSLClient
// #include <ESP_SSLClient.h>               // BORIS: testing
#include <SSLClientESP32.h>
#include <ESP32Time.h>
#include <TimeLib.h>
#include <ArduinoHttpClient.h>
#include <SHTSensor.h>                      // libraries for SHT30
#include <LTC2942.h>                        // coulomb counter library
#include <Adafruit_Sensor.h>
#include <Adafruit_BMP3XX.h>                // BMP390 library
#include <SDI12.h>                          // SDI12 for the ClimaVue50
#include <esp_task_wdt.h>                   // for hardware watchdog
#include <StreamDebugger.h>
#include <ArduinoJson.h>
#include "mbedtls/md.h"
//#include "trusted_anchor_climate-babel_202402.h"  // BORIS
//....................................................................................................
//....................................................................................................

//....................................................................................................
// #define DUMP_AT_COMMANDS                       // See all AT commands, if wanted
#ifdef DUMP_AT_COMMANDS                           // if enabled it requires the streamDebugger lib
StreamDebugger debugger(SerialAT, Serial);
TinyGsm modem(debugger);
#else
TinyGsm modem(SerialAT);
#endif

// global objects, variables and constants
const char COMPILE_DATE_FILE[] = __DATE__ " " __TIME__ " " __FILE__;
const unsigned int fullCapacity = 5500;    // Maximum value of battery capacity is 5500 mAh
int RecordsInFlash = 0;                    // counter of records stored in flash
ESP32Time rtc;                             // object to interact with RTC
//TinyGsmClientSecure clients(modem);      // network client (secure)
TinyGsmClient client(modem);               // several network clients
// SSLClient clients(client, TAs, 1, A7);
// ESP_SSLClient clients;                  // BORIS
SSLClientESP32 clients(&client);
HttpClient https(clients, SERVER, PORT);   // init https client

LTC2942 gaugeBattery1(20); // Takes R_SENSE value (in milliohms) as argument, can be omitted if using LTC2942-1
LTC2942 gaugeBattery2(20); // Takes R_SENSE value (in milliohms) as argument, can be omitted if using LTC2942-1

TwoWire I2C_1 = TwoWire(0);  //I2C1 line
TwoWire I2C_2 = TwoWire(1);  //I2C2 line

// variables that survive in RTC memory during deep sleep
RTC_DATA_ATTR int sleepDelta = 0;          // to capture deviation at wakeup due to RTC drift
RTC_DATA_ATTR int loopCounterRestart = 0;  // count the loops and force ESP to restart every MAX_LOOPS loops
RTC_DATA_ATTR char storedJSON[4096];       // here measurements are stored for submission every n loops

// Global (static) buffers
char SHA256PayLoad[80];                    // combined string which goes into SHA256, could be moved to setup()
char httpRequestData[2048];                // data to be sent
char timeStamp[32];                        // GSM datetime

/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
void setup() {
//....................................................................................................
  /* variable definition */
  uint8_t mac[6];                                   // MAC address
  char loggerID[18];                                // ID of the logger, include MAC address

  float bat1V = -999.99;                            // voltage of battery 1
  float bat2V = -999.99;                            // voltage of battery 2
  float bat1Temp = -999.99;                         // Temperature of battery 1
  float bat2Temp = -999.99;                         // Temperature of battery 2
  float bat1Charge = -999.99;                       // Charge of battery 1
  float bat2Charge = -999.99;                       // Charge of battery 2
  uint16_t solarV = -999;                           // voltage of Solar Panel

  float shtAirTemp = -999.99;                       // SHT Air Temperature, init with error value
  float shtAirHumi = -999.99;                       // SHT Air Humidity, init with error value
  float shtSoilTemp = -999.99;                      // SHT Soil Temperature, init with error value
  float shtSoilHumi = -999.99;                      // SHT Soil Humidity, init with error value
  float bmpTemp = -999.99;                          // BMP390 Temperature, init with error value
  float bmpPres = -999.99;                          // BMP390 Pressure, init with error value

  float climavue50Solar = -999.99;                  // Solar (0...1750)
  float climavue50Precip = -999.99;                 // Precipitation (0.000 ... 125.000)
  float climavue50StrikeCount = -999.99;            // Strikes (0 ... 65,535)
  float climavue50StrikeDist = -999.99;             // Strike Dist (0 ... 40)
  float climavue50Wind = -999.99;                   // Wind Speed (0.00 ... 40.00)
  float climavue50WDir = -999.99;                   // Wind Dir (0 ... 359)
  float climavue50Gust = -999.99;                   // Wind Gust (0.00 ... 40.00)
  float climavue50Temp = -999.99;                   // Air Temp (-40.0 ... 50.0)
  float climavue50VPres = -999.99;                  // Vapour Press (0.00 ... 47.00)
  float climavue50APres = -999.99;                  // Atmos Press (50.01 ... 110.01)
  float climavue50Humi = -999.99;                   // Relative Humidity (0.0 ... 100.0)
  float climavue50SensorTemp = -999.99;             // Humidity sensor Temp (-40.0 ... 50.0)
  float climavue50XOrient = -999.99;                // x-orientation (tilt) (0.0 ... 180.0)
  float climavue50YOrient = -999.99;                // y-orientation (tilt) (0.0 ... 180.0)
  float climavue50Compass = -999.99;                // compass heading (0 ... 359)
  float climavue50NWS = -999.99;                    // north wind speed (0.00 ... 40.00)
  float climavue50EWS = -999.99;                    // east wind speed (0.00 ... 40.00)
  gpio_num_t power5VEnablePin = (gpio_num_t) POWER5V_ENABLE;  // the climavue50 power pin in proper type

  float signalStrength = -999.99;                   // network signal strength, init with error value
  unsigned long millisAtConnection;                 // millis() when initiating network - to compute sleepSecs
  bool postSuccess = false;                         // whether the http response was successful (2XX) or not
  int sleepSeconds;                                 // number of seconds to sleep

  bool flashOK = false;                             // bool: wether we mount the flash
  bool apnConnected = false;                        // bool: wether we connected to APN
  bool serverConnected = false;                     // bool: wether we connected to the server
  bool batteryStatus = false;                       // battery ok for turning on the modem?
  bool modemTurnedOn = false;                       // bool whether we tried to power on the modem

  char hashedKey[64];                               // hashed payloag from SHA256 as a string for the JSON
  JsonDocument singleRecordJSON;                    // to store one single record BORIS - for v7
  JsonDocument transmRecordsJSON;                   // for the records of 1 transmission cycle, BORIS - for v7
                                                    
  int currentMinute;                                // helper variable to store the minute of timestamp
  size_t loopCounterTransm ;                        // counter variable for the loops until next transmission
//....................................................................................................
/* indicate start of code and WDT running */
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);
  blink_led(2, 200);                                // light show: start of code and watchdog
  esp_task_wdt_init(WDT_TIMEOUT, true);             // enable panic so ESP32 restarts
  esp_task_wdt_add(NULL);                           // add current thread to WDT watch

//....................................................................................................
/* Communication Init, collect basic information */
  Serial.begin(115200);                               // Init Console and send after several infos
  delay(1000);
  Serial.println("\nGOOD MORNING SECTION");
  Serial.print("setup()running on core ");
  Serial.println(xPortGetCoreID());
  Serial.printf("watchdog configured with %d s timeout...\n", WDT_TIMEOUT);
  Serial.printf("This is git commit %s\n", GIT_VERSION);
  Serial.printf("Compile date and source file: %s\n", COMPILE_DATE_FILE);

  ESP_ERROR_CHECK_WITHOUT_ABORT(esp_efuse_mac_get_default(mac));  // read MAC address
  sprintf(loggerID, "%02x:%02x:%02x:%02x:%02x:%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  Serial.printf("MAC: %s\n", loggerID);

  // define # loops before transmission
  const int NB_LOOPS_B4_TRANSM = TRANSMIT_EVERY_MINS / SENSOR_READ_EVERY_MINS;
  Serial.printf("I'll transmit every %d loops.\n", NB_LOOPS_B4_TRANSM);

  // init I2C buses
  Serial.print("Init I2C busses... ");
  I2C_1.begin(I2C1_SDA, I2C1_SCL);
  I2C_2.begin(I2C2_SDA, I2C2_SCL);
  Serial.println("done.");

//....................................................................................................
  flashOK = LittleFS.begin(true);
  if(!flashOK){                          // start file system
    Serial.println("An Error has occurred while mounting LittleFS");
  } else {
    read_nb_records();                                // read #records currently stored in flash
  }

//....................................................................................................
  /* collect battery information (via Coulomb Counter) and solar panel*/
  init_comm_LTC2942();                              // init communication 2wires with coulomb counter
  //....................................................................................................
  // only init coulomb counter and potentially power up climavue50 at power start, not a timer wakeup start.
  esp_sleep_wakeup_cause_t wakeup_reason = esp_sleep_get_wakeup_cause();
  wakeup_stuff(wakeup_reason);

  // read the two batteries - voltage, temperature, remaining capacity (=charge)
  if (!read_battery(&bat1V, &bat1Temp, &bat1Charge, &gaugeBattery1)){
    Serial.println("Could not read parameters from Battery 1.");
  } else {
    Serial.printf("Battery 1 has %d.%01dV, a temp of %d.%01d *C and a remaining charge of %d/5500 mAh\n",
            (int)bat1V, (int)(bat1V*10)%10, (int)bat1Temp, (int)(bat1Temp*10)%10, (int)bat1Charge);
  }
  if (!read_battery(&bat2V, &bat2Temp, &bat2Charge, &gaugeBattery2)){
    Serial.println("Could not read parameters from Battery 2.");
  }  else {
    Serial.printf("Battery 2 has %d.%02dV, a temp of %d.%02d *C and a remaining charge of %d/5500 mAh\n",
            (int)bat2V, (int)(bat2V*10)%10, (int)bat2Temp, (int)(bat2Temp*10)%10, (int)bat2Charge);
  }

  if (bat1V > 3.5 || bat1V == 0 || bat2V > 3.5 || bat2V == 0) { // voltage in V BORIS: increased thresh to 3.5
    batteryStatus = true;
  }
  pinMode(PIN_ADC_SOLAR, INPUT);                    // configure ADC for solar panel measurement
  solarV = read_volt_pin(PIN_ADC_SOLAR);            // get value from ADC in solarV

//....................................................................................................
/* Check Time */
  Serial.println("\nTIMING SECTION");
  // if this is not a wakeup from sleep or RTC is back in the 70ies, try to get network time
  // BORIS: maybe keep the 1970; advantages: marker for a hard reset, and also an immediate transmission
//  if (rtc.getYear() == 1970 || wakeup_reason != ESP_SLEEP_WAKEUP_TIMER){
//    Serial.println("Getting network time as my RTC is or may be out of date.");
//    modem_on(&modemTurnedOn);
//    if (connect_to_network(&signalStrength)){
//      Serial.println("... OK.");
//    } else {
//      Serial.println("... failed");
//    }
//    set_rtc_to_network_datetime();
//    Serial.print("Powering off modem after checking in 1st time for a current timestamp...");
//    modem_off(&modemTurnedOn);
//  }

  getTime();                                        // get time from RTC
  currentMinute = rtc.getMinute();
  Serial.printf("RTC time 01: %s\n", timeStamp);
  // check timing; if we have just woken up before the target time, we wait a bit
  sleepSeconds = calc_sleepSeconds();
  if (sleepSeconds < 40){
    sleepDelta += sleepSeconds;
    delay(sleepSeconds * 1000);
    sleepSeconds = calc_sleepSeconds();             // update sleepSeconds
    getTime();                                      // ... and update timestamp
    currentMinute = rtc.getMinute();
  } else if ((SENSOR_READ_EVERY_MINS * 60) - sleepSeconds < 40){
    // ... if we are a bit too late, never mind, but wake up a bit earlier next time
    sleepDelta += sleepSeconds - (SENSOR_READ_EVERY_MINS * 60);
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
  /* sensor measurements*/
  Serial.println("\nSENSOR READING SECTION");
  if (!sht30_measurement(&shtAirTemp, &shtAirHumi, &I2C_1)) {
    Serial.println("Could not make a valid SHT30 measurement on I2C1, check wiring!");
  }
  Serial.printf("SHT30 measurement on I2C1: %f; %f\n", shtAirTemp, shtAirHumi);

  if (!sht30_measurement(&shtSoilTemp, &shtSoilHumi, &I2C_2)) {
    Serial.println("Could not make a valid SHT30 measurement on I2C2, check wiring!");
  }
  Serial.printf("SHT30 measurement on I2C2: %f; %f\n", shtSoilTemp, shtSoilHumi);

  if (!bmp_measurement(&bmpTemp, &bmpPres)) {
    Serial.println("Could not make a valid BMP390 measurement, check wiring!");
  }
  Serial.printf("BMP390 measurement: %f; %f\n", bmpTemp, bmpPres);

  /* sensor climavue50 measurements*/
  if (CLIMAVUE50){
    climavue50_measurement(&climavue50Solar, &climavue50Precip, &climavue50StrikeCount,
                           &climavue50StrikeDist, &climavue50Wind, &climavue50WDir,
                           &climavue50Gust, &climavue50Temp, &climavue50VPres, &climavue50APres,
                           &climavue50Humi, &climavue50SensorTemp, &climavue50XOrient,
                           &climavue50YOrient, &climavue50Compass, &climavue50NWS, &climavue50EWS);
  }
//....................................................................................................
/* Prepare data to be publish */
  Serial.println("\nPREPARE SENSOR READING SUBMIT OR STORE");
  snprintf(SHA256PayLoad, sizeof(SHA256PayLoad), "%s; %s; %s", SITE_ID, loggerID, timeStamp);
  hashing(SHA256PayLoad, hashedKey);
  // now populate JSON doc
  singleRecordJSON["sign"] = hashedKey;
  singleRecordJSON["timestamp"] = timeStamp;
  singleRecordJSON["ta"] = shtAirTemp;
  singleRecordJSON["rh"] = shtAirHumi;
  singleRecordJSON["p"] = bmpPres;
  singleRecordJSON["ts10cm"] = shtSoilTemp;
  singleRecordJSON["logger_ta"] = bmpTemp;
  singleRecordJSON["U_Battery1"] = bat1V;
  singleRecordJSON["Temp_Battery1"] = bat1Temp;
  singleRecordJSON["Charge_Battery1"] = bat1Charge;
  singleRecordJSON["U_Battery2"] = bat2V;
  singleRecordJSON["Temp_Battery2"] = bat2Temp;
  singleRecordJSON["Charge_Battery2"] = bat2Charge;
  singleRecordJSON["U_Solar"] = solarV;
  singleRecordJSON["loggerID"] = loggerID;
  singleRecordJSON["git_version"] = GIT_VERSION;
  if (CLIMAVUE50){
    singleRecordJSON["rad"] = climavue50Solar;
    singleRecordJSON["pr"] = climavue50Precip;
    singleRecordJSON["lightning_count"] = climavue50StrikeCount;
    singleRecordJSON["lightning_dist"] = climavue50StrikeDist;
    singleRecordJSON["wind_speed"] = climavue50Wind;
    singleRecordJSON["wind_dir"] = climavue50WDir;
    singleRecordJSON["wind_gust"] = climavue50Gust;
    singleRecordJSON["ta"] = climavue50Temp;
    singleRecordJSON["vapour_press"] = climavue50VPres;
    singleRecordJSON["p"] = climavue50APres * 10; // climavue reports in hPa
    singleRecordJSON["rh"] = climavue50Humi * 100; // climavue reports not in %
    singleRecordJSON["Temp_HumiSens"] = climavue50SensorTemp;
    singleRecordJSON["tilt_x"] = climavue50XOrient;
    singleRecordJSON["tilt_y"] = climavue50YOrient;
    singleRecordJSON["compass"] = climavue50Compass;
    singleRecordJSON["wind_speed_N"] = climavue50NWS;
    singleRecordJSON["wind_speed_E"] = climavue50EWS;
  }
  
  // BEGIN DAVID 
//    Serial.printf_P(PSTR("free heap memory: %d\n"), ESP.getFreeHeap());  
//    Serial.printf("bytes of singleRecordJSON: %d\n", measureJson(singleRecordJSON));
//    // check whether one such records fits enough times into the RTC memory
//    JsonDocument bufferJSON;
//    for (int i = 0; i < NB_LOOPS_B4_TRANSM; i++){
//      bufferJSON[i] = singleRecordJSON;
//    }
//    Serial.printf_P(PSTR("free heap memory after filling bufferJSON: %d\n"), ESP.getFreeHeap());  
//
//    char buffer[sizeof(storedJSON)];           // a buffer to buffer things
//    size_t n = serializeJson(bufferJSON, buffer, sizeof(buffer));    
//    Serial.printf("needed space in RTC (buffering): %d, needed space (measure): %d, reserved RTC space: %d\n", n, measureJson(bufferJSON), sizeof(storedJSON));
//    Serial.print("content of buffer: ");
//    Serial.println(buffer);
//    Serial.print("content of bufferJSON: ");
//    serializeJson(bufferJSON, Serial);
//    
//    if (n > sizeof(storedJSON)){
//      Serial.println("\nCannot store this many data in the RTC. Adjust TRANSMIT_EVERY_MINS / SENSOR_READ_EVERY_MINS. I'll power down now.");    
//      esp_deep_sleep_start();                  // go to eternal sleep
//    }
  // END DAVID

  // check whether one such records fits enough times into the RTC memory    
  if (measureJson(singleRecordJSON) * NB_LOOPS_B4_TRANSM > sizeof(storedJSON) - 100){  // allow for some admin bytes
    Serial.println("\nCannot store this many data in the RTC. Adjust TRANSMIT_EVERY_MINS / SENSOR_READ_EVERY_MINS. I'll power down now.");    
    esp_deep_sleep_start();                  // go to eternal sleep
  }
  
  // now we read what we have stored in the RTC and append the current record
  deserializeJson(transmRecordsJSON, (const char*)storedJSON, sizeof(storedJSON)); // read from RTC
  transmRecordsJSON[transmRecordsJSON.size()] = singleRecordJSON;
  loopCounterTransm = transmRecordsJSON.size();  

//....................................................................................................
/* try to publish to network, publish old values, or store new one in database if no comm */
  Serial.println("\nSUBMIT OR STORE");
  if (!batteryStatus)
     blink_led(4, 200);                              // lightshow: battery low, don't try to init modem

  if (loopCounterTransm >= NB_LOOPS_B4_TRANSM ||
       currentMinute % TRANSMIT_EVERY_MINS == 0){         // ready to transmit
    Serial.println("The time is ripe or the RTC is full, I attempt a transmission.");
    if (batteryStatus){                                    // enough power to discuss with modem
      Serial.println("... and, yes, we have enough battery.");
      modem_on(&modemTurnedOn);                                          // turn modem on
      apnConnected = connect_to_network(&signalStrength);  // connect to network
    } else {
      Serial.println("... but, helas, not enough battery.");
    }

    if (apnConnected){                              // if network works
      Serial.println("... OK");
      set_rtc_to_network_datetime();                   // get and set current date / time to RTC
      signalStrength = modem.getSignalQuality();       // network signal strength
      Serial.printf("Signal quality: %f\n", signalStrength);

      serverConnected = connect_to_server();             // try to connect to the server
      if (serverConnected){
        // loop through the transmRecordsJSON
        for (int i=0; i < transmRecordsJSON.size(); i++){
          transmRecordsJSON[i]["signalStrength"] = signalStrength;
          serializeJson(transmRecordsJSON[i], httpRequestData);  // convert JSON to string for transmission
          postSuccess = send_data_to_server(httpRequestData);
          if (!postSuccess){
            Serial.println("... fail. Storing measurements to flash, resetting modem and going to sleep.");
            if (flashOK && RecordsInFlash < MAX_RECORDS){
              // don't store too many records... reading the file becomes slow.
              store_data_on_flash(httpRequestData);
            } else {
              Serial.printf("Already >= %d records in flash. Current record not stored.\n", MAX_RECORDS);
            }
          }
        }

        // send further data from flash - if possible
        if (postSuccess){   // if submission sucessful
          // check whether we have any leftover data and try to submit these (only if this post request successful)
          if (flashOK && RecordsInFlash > 0){
            transmit_stored_records(5);                    // submit up to 5 records from the flash
          }
        } // end block - send further data from flash
      } // end block - connect to server
    } // end block - connect to apn - this is where we try to send to server

    if (!apnConnected || !serverConnected) {  // apnconnect or server connect didn't work incl case of low battery
      for (int i=0; i < transmRecordsJSON.size(); i++){  // store all records from RTC memory to flash
        transmRecordsJSON[i]["signalStrength"] = signalStrength;
        serializeJson(transmRecordsJSON[i], httpRequestData);
        // don't store too many records, reading the file becomes slow
        if (flashOK && RecordsInFlash < MAX_RECORDS){
          store_data_on_flash(httpRequestData);
        } else {
          Serial.printf("Already >= %d records in flash. Current record not stored.\n", MAX_RECORDS);
        }
      } // loop through records in the RTC
    } // end block: apnconnect or server connect did not work - store to flash

    // if no connection despite enough battery
    if (batteryStatus && (!apnConnected || !postSuccess)){
      blink_led(8, 200);                            // light show: issue with connection
      Serial.println("Something did not work out with the network... hard-resetting modem.");
      modem_reset();                                // do a hard reset before going to sleep
    }

    Serial.print("Stopping http client...");
    https.stop();
    Serial.println(" and network client.");
    clients.stop();
    Serial.print("Powering-off modem");
    modem_off(&modemTurnedOn);

    // finally, clean RTC memory and reset counter
    memset(storedJSON, '\0', sizeof(storedJSON)); // remove records in RTC
  } else {// end of transmission attempt(good time or full RTC memory)  --
          // otherwise we store to RTC memory
    Serial.printf("This is loop %d / %d.\n", loopCounterTransm, NB_LOOPS_B4_TRANSM);
    Serial.println("Don't transmit this time - either wrong time, weak battery, or not enough in RTC.");
    if (measureJson(transmRecordsJSON) < sizeof(storedJSON)){ // try to write to RTC memory
      serializeJson(transmRecordsJSON, storedJSON);
    } else {                                                  // if not enough space, don't.
      Serial.printf("Current set of records (%d bytes) exceeds space in RTC memory (%d bytes). Set not stored to RTC memory.",
        measureJson(transmRecordsJSON), sizeof(storedJSON));      
    }

    Serial.print("Stopping http client...");
    https.stop();
    Serial.println(" and network client.");
    clients.stop();
  } // end block - store to RTC
//....................................................................................................
/* end of code, initiate sleep mode until next measurement (start again setup function at wakeup) */
  Serial.println("\nGOOD NIGHT SECTION");
  Serial.println("Unmounting file system.");
  LittleFS.end(); // unmount file system

  // check whether it's time for a reset of the ESP
  loopCounterRestart++;
  if (loopCounterRestart >= MAX_LOOPS){                                         // restart
    loopCounterRestart = 0;
    Serial.printf("I have gone through %d loops, enough is enough. Restarting the ESP32 now.\n", MAX_LOOPS);
    ESP.restart();
  }

  // now go to sleep
  // update sleep time incl network time and delta
  sleepSeconds = sleepSeconds - (int)((float)(millis() - millisAtConnection) / 1000.0) + sleepDelta;
  if (sleepSeconds > SENSOR_READ_EVERY_MINS * 60){              // some plausibility checks
    sleepSeconds = SENSOR_READ_EVERY_MINS * 60;
  }
  if (sleepSeconds < 0){
    sleepSeconds = 0;
  }
  Serial.print("Going to sleep. sleepsecs incl correction for network time and delta: ");
  Serial.println(sleepSeconds);
  esp_sleep_enable_timer_wakeup((sleepSeconds) * uS_TO_S_FACTOR);
  delay(200);
  blink_led(2, 200);                                    // light show: end of code
  gpio_hold_en(power5VEnablePin);                       // keep climavue pwr pin during sleep
  esp_deep_sleep_start();
}


/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------    MAIN CODE UP   -----------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*-------------------------------------------------    FUNCTIONS CODE DOWN   -------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
/*----------------------------------------------------------------------------------------------------------*/
void loop() {
  // with Deep Sleep Mode requested at the end of setup(), this section will never reached. All sketch in setup().
}


/* ----------------------------------------------------------------------------------------------------------
   name :         init_comm_LTC2942, wakeup_stuff and read_battery
   description :  init param coulomb counter, read voltage, temperature and charge from the two batteries
   input :        pointers for battery parameters (float*)
   output :       void
   --------------------------------------------------------------------------------------------------------*/
void init_comm_LTC2942(){ // on hardware, I2C2 is connected to bat1, and I2C1 is connected to bat2
  if (!gaugeBattery1.begin(I2C_2)){
    Serial.println("Cannot connect to Battery 1 via I2C_2");
  }
  if (!gaugeBattery2.begin(I2C_1)){
    Serial.println("Cannot connect to Battery 2 via I2C_1");
  }
}

void wakeup_stuff(esp_sleep_wakeup_cause_t wakeup_reason){
  switch(wakeup_reason)
  {
    case ESP_SLEEP_WAKEUP_EXT0:
      Serial.println("Wakeup caused by external signal using RTC_IO");
      break;
    case ESP_SLEEP_WAKEUP_EXT1:
      Serial.println("Wakeup caused by external signal using RTC_CNTL");
      break;
    case ESP_SLEEP_WAKEUP_TIMER:
      Serial.println("Wakeup caused by timer");
      break;
    case ESP_SLEEP_WAKEUP_TOUCHPAD:
      Serial.println("Wakeup caused by touchpad");
      break;
    case ESP_SLEEP_WAKEUP_ULP:
      Serial.println("Wakeup caused by ULP program");
      break;
    default:
      Serial.print("Wakeup was not by timer after deep sleep, will init the coulomb counters now "
                   "and power on ClimaVue50 (if present). Wakeup-reason: ");
      Serial.println(wakeup_reason);
      gaugeBattery1.setBatteryCapacity(fullCapacity);
      // gaugeBattery1.setBatteryToFull(); // Sets accumulated charge registers to the maximum value
      gaugeBattery1.setRawAccumulatedCharge(0x7FFF); // Sets accumulated charge registers to medium value
      // In sleep mode, voltage and temperature measurements will only take place when requested
      gaugeBattery1.setADCMode(ADC_MODE_SLEEP);
      gaugeBattery1.startMeasurement();

      gaugeBattery2.setBatteryCapacity(fullCapacity);
      //  gaugeBattery2.setBatteryToFull(); // Sets accumulated charge registers to the maximum value
      gaugeBattery2.setRawAccumulatedCharge(0x7FFF); // Sets accumulated charge registers to the medium value
      // In sleep mode, voltage and temperature measurements will only take place when requested
      gaugeBattery2.setADCMode(ADC_MODE_SLEEP);
      gaugeBattery2.startMeasurement();

      if (CLIMAVUE50){
        pinMode(POWER5V_ENABLE, OUTPUT); // start power for climavue50
        digitalWrite(POWER5V_ENABLE, HIGH);
        delay(5000);
      } else {
        pinMode(POWER5V_ENABLE, OUTPUT); // don't start power for climavue50
        digitalWrite(POWER5V_ENABLE, LOW);
        delay(1000);
      }
  }
}

bool read_battery(float* batV, float* batTemp, float* batCharge, LTC2942* myGaugeBattery){
  bool plausibility = false;

  float voltage = myGaugeBattery->getVoltage();
  if (voltage >= 0) {
    *batV=voltage;
    plausibility = true;
  }
  float temperature = myGaugeBattery->getTemperature();
  if (temperature >= -80 && temperature <= 100) {
    *batTemp = temperature;
  }

//  unsigned int raw = myGaugeBattery->getRawAccumulatedCharge();
//  Serial.print(F(" Raw Accumulated Charge: "));
//  Serial.print(raw, DEC);

  float capacity = myGaugeBattery->getRemainingCapacity();
  if (capacity >= 0){
    *batCharge = capacity;
  }

  return(plausibility);
}


/* ----------------------------------------------------------------------------------------------------------
   name :         modem_on
   description :
     power on the modem, inspired by
     https://github.com/nikil511/LilyGO-T-SIM7000G/blob/master/examples/Platformio_Arduino_Thingsboard/src/main.cpp
   input :        pointer to bool modemTurnedOn
   output :       void
   --------------------------------------------------------------------------------------------------------*/
void modem_on(bool* modemTurnedOn){
  // power on modem............................................................................
  // based on https://www.manualslib.com/manual/1498555/Simcom-Sim7000g.html?page=25#manual
  // note that the koala board has logical inverters between the pins - this means that HIGH=LOW ;-)
  // Serial.println("Powering on modem... (6s)");
  // power on modem and give it some time to wake up (https://github.com/vshymanskyy/TinyGSM/issues/381)
  Serial.println("Powering on modem... (6s)");
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(100); // Ton 73 ms
  digitalWrite(PWR_PIN, LOW);
  delay(6000);

  *modemTurnedOn = true;
}



/* ----------------------------------------------------------------------------------------------------------
   name :         modem_reset
   description :
     do a hardware reset of the modem, inspired by
     https://github.com/nikil511/LilyGO-T-SIM7000G/blob/master/examples/Platformio_Arduino_Thingsboard/src/main.cpp
   input :        void
   output :       void
   --------------------------------------------------------------------------------------------------------*/
void modem_reset()
{
  // based on https://www.manualslib.com/manual/1498555/Simcom-Sim7000g.html?page=27#manual
  // note that the koala board has logical inverters between the pins - this means that HIGH=LOW ;-)
  Serial.println("Modem hardware reset... (10s)");
  pinMode(MODEM_RST, OUTPUT);
  digitalWrite(MODEM_RST, HIGH);
  delay(260); //Treset 252ms
  digitalWrite(MODEM_RST, LOW);
  delay(10000);
}

/* ----------------------------------------------------------------------------------------------------------
   name :         modem_off
   description :  does the power-off of the modem
   input :        pointer to bool modemTurnedOn
   output :       void
   --------------------------------------------------------------------------------------------------------*/
void modem_off(bool* modemTurnedOn) {
  if (modem.poweroff()) {                                  // turn off modem (software)
    Serial.println("... OK");
  } else if (*modemTurnedOn) {                              // if this fails but modem had been turned on: hardware
    Serial.println("\nHardware modem power down... (8s)");
    // note that the koala board has logical inverters between the pins - this means that HIGH=LOW ;-)
    pinMode(PWR_PIN, OUTPUT);
    digitalWrite(PWR_PIN, HIGH);
    delay(1300);    //Datasheet Toff = 1.2s
    digitalWrite(PWR_PIN, LOW);
    delay(1700);
  } else {
    Serial.println("... Modem was (hopefully) never turned on.");
  }

  delay(5000);

//  pinMode(PWR_PIN, OUTPUT);
//  digitalWrite(PWR_PIN, LOW);
// BORIS: unclear why doesn't work on the new board; pull pwr_pin low, to prevent esp from restarting the modem

  *modemTurnedOn = false;
}

/* ----------------------------------------------------------------------------------------------------------
 * name :         connect_to_network
 * description :  do init of the modem
 * input :        void
 * output :       boolean - whether everything needed to connect to apn worked out
 * --------------------------------------------------------------------------------------------------------*/
bool connect_to_network(float* signalStrength){
  // establish communication with and initialize modem.............................................
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

  // configure modem and connect to network and APN ...............................................
  // Set SIM7000G GPIO4 LOW, turn off GPS power (only for board version 20200415)
  modem.sendAT("+SGPIO=0,4,1,0");
  if (sizeof(GSM_PIN) != 0 && modem.getSimStatus() != 3) {       // Unlock your SIM card with a PIN if needed
    modem.simUnlock(GSM_PIN);
  }

  Serial.print("Setting network modes... ");        // set network modes
  while (!modem.setNetworkMode(NETWORK_MODE)){      // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE only
    delay(100);
  }
  while (!modem.setPreferredMode(1)){               // 1 CAT-M; 2 NB-Iot; 3 CAT-M and NB-IoT
    delay(100);
  }

  // connect to network
  Serial.print("Waiting for network... ");
  modem.waitForNetwork();                     // this tries to connect for 60s
  if (!modem.isNetworkConnected()){           // if this did not succeed...
    //Serial.println("in vain. Setting pdp-context and trying to connect again.");
    Serial.println("in vain.");
    // esp_task_wdt_reset();                  // reset watchdog
    // set_pdp(APN);                          // try to set pdp-context explicitly...
  }

  if (modem.isNetworkConnected()) {           // if successful, we connect to apn
    *signalStrength = -777.0;                 // error code - signalStrength remains at this if apn-connect fails
    Serial.println("Network connected");
    Serial.printf("Connecting to: %s", APN);  // connect to APN
    return modem.gprsConnect(APN, GPRS_USER, GPRS_PASS);
  } else {
    *signalStrength = -666.0;                 // error code - network connect failed
    return false;
  }
}

/* ----------------------------------------------------------------------------------------------------------
 * name :         connect_to_server
 * description :  do init of the modem
 * input :        void
 * output :       bool success connect to server
 * --------------------------------------------------------------------------------------------------------*/
bool connect_to_server(){
  esp_task_wdt_reset();                              // reset wdt - a timeout here can add 1min
  bool success=false;
  // long now_secs = rtc.getEpoch();                           // set current time for SSL
  // uint32_t ssl_days = 719528 + elapsedDays(now_secs);
  // uint32_t ssl_secs = elapsedSecsToday(now_secs);
  // Serial.printf("For SSL dating: Days since AD: %u, Secs of today: %u\n", ssl_days, ssl_secs);
  // clients.setVerificationTime(ssl_days, ssl_secs); // BORIS

//  // BEGIN BORIS from: https://github.com/mobizt/ESP_SSLClient/blob/main/examples/gsm/gsm.ino
//  // ignore server ssl certificate verification
//  clients.setInsecure();
//
//  // Set the receive and transmit buffers size in bytes for memory allocation (512 to 16384).
//  clients.setBufferSizes(1024 /* rx */, 512 /* tx */);
//
//  /** Call setDebugLevel(level) to set the debug
//   * esp_ssl_debug_none = 0
//   * esp_ssl_debug_error = 1
//   * esp_ssl_debug_warn = 2
//   * esp_ssl_debug_info = 3
//   * esp_ssl_debug_dump = 4
//   */
//  clients.setDebugLevel(1);
//
//  // Assign the basic client
//  // Due to the basic_client pointer is assigned, to avoid dangling pointer, basic_client should be existed
//  // as long as it was used by clients for transportation.
//  clients.setClient(&client);
//
//  // END BORIS

  // BEGIN BORIS modified from:
  // https://github.com/alkonosst/SSLClientESP32/blob/master/README.md#using-sim7600g-h-and-certificate-bundle
  // ignore server ssl certificate verification
  clients.setInsecure();
//  clients.setClient(&client);

  // END BORIS

  if (clients.connect(SERVER, PORT)){                         // if server is in reach
    Serial.printf("Connected to %s\n", SERVER);
    success=true;
  } else {
    Serial.printf("Connection to %s failed.\n", SERVER);
  }
  return(success);
}

/* ----------------------------------------------------------------------------------------------------------
 * name :         send_data_to_server
 * description :  do init of the modem
 * input :        data to send
 * output :       void
 * --------------------------------------------------------------------------------------------------------*/
bool send_data_to_server(const char* httpRequestData){
  esp_task_wdt_reset();                              // reset wdt - a timeout here can add 1min
  // select content type according to API
  const char* contentType = "application/json";

  // L200 https://github.com/vshymanskyy/TinyGSM/blob/master/examples/HttpsClient/HttpsClient.ino
  https.connectionKeepAlive();

  Serial.printf("Trying post request -> %s\n", httpRequestData);
  https.post(RESOURCE, contentType, httpRequestData);

  int responseStatusCode = https.responseStatusCode();
  bool success = (responseStatusCode >= 200 && responseStatusCode < 300);
  if (success) {
    Serial.println("Post request successful.");
  }
  String response = https.responseBody();
  Serial.printf("Response code: %d; Response body: %s\n", responseStatusCode, response.c_str());

  return(success);
}

/* ----------------------------------------------------------------------------------------------------------
   name :         bmp_measurement
   description :  do two measure, check plausibility
   input :        void
   output :       void
   --------------------------------------------------------------------------------------------------------*/
bool bmp_measurement(float* temperature, float* pressure) {
  Adafruit_BMP3XX bmp;        // sensor type BMP390 variable
  float measureTemp1, measureTemp2;
  float measurePress1, measurePress2;
  int i = 0;                               // init counter i
  int nbMaxTries = 5;                      // number of try to have good measure
  bool plausibility = false;               // init plausibilty to false

  while (i < nbMaxTries && !plausibility) {
    // software SPI mode
    if (bmp.begin_SPI(BMP_CS, BMP_SCK, BMP_MISO, BMP_MOSI)) {  // BORIS: removed a wrong ! in the if
      // Set up oversampling and filter initialization; following example from the library
//      bmp.setTemperatureOversampling(BMP3_OVERSAMPLING_8X);
//      bmp.setPressureOversampling(BMP3_OVERSAMPLING_4X);
//      bmp.setIIRFilterCoeff(BMP3_IIR_FILTER_COEFF_3);
//      bmp.setOutputDataRate(BMP3_ODR_50_HZ);
//

      bmp.performReading();                // first reading is wrong,
//      delay(1000);                       // BORIS: I need the delay only if I set oversampling etc as above
      bmp.performReading();
      measureTemp1 = bmp.temperature;      // first set of values

      measurePress1 = bmp.pressure / 100.0;
      bmp.performReading();
      measureTemp2 = bmp.temperature;      // second set of values
      measurePress2 = bmp.pressure / 100.0;

      if (fabs(measureTemp1 - measureTemp2) < 1.0 && measureTemp1 < 99.0 &&
          measureTemp1 > -80.0) {            // check plausibility
        *temperature = (measureTemp1 + measureTemp2) / 2.0;
        *pressure = (measurePress1 + measurePress2) / 2.0;
        plausibility = true;
      } else {
        Serial.println("Inconsistent BMP390 measurements!");
        *temperature = -999.99;
        *pressure = -999.99;
        plausibility = false;
      }
    }
    i++;
  }
  return plausibility;
}

/* ----------------------------------------------------------------------------------------------------------
   name :         sht30_measurement
   description :  do two measure, check plausibility
   input :        void
   output :       void
   --------------------------------------------------------------------------------------------------------*/
bool sht30_measurement(float* temperature, float* humidity, TwoWire* myI2C){
  SHTSensor sht30(SHTSensor::SHT3X);                                // sensor type SHT3X variable
  float measureTemp1, measureTemp2, measureHum1, measureHum2;
  int i = 0;                                                        // init counter i
  int nb_try = 5;                                                   // number of try to have good measure
  bool plausibility = false;                                        // init plausibilty to false

  while (i <= nb_try && plausibility != true){                      // try to have plausible value max nb_try
    if (sht30.init(*myI2C)){
      sht30.setAccuracy(SHTSensor::SHT_ACCURACY_HIGH);              // only supported by SHT3x
      sht30.readSample();
      measureTemp1 = sht30.getTemperature();                        // first set of values
      measureHum1 = sht30.getHumidity();
      sht30.readSample();
      measureTemp2 = sht30.getTemperature();                        // second set of values
      measureHum2 = sht30.getHumidity();

      if (fabs(measureTemp1 - measureTemp2) < 1 && measureTemp1 < 99 &&
          measureTemp1 > -80.0) {            // check plausibility
        *temperature = (measureTemp1 + measureTemp2) / 2.0;
        *humidity = (measureHum1 + measureHum2) / 2.0;
        plausibility = true;
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

/* ----------------------------------------------------------------------------------------------------------
   name :         getAtmosValue
   description :  transfer raw data string in tab with float value
   input :        adress of raw data = &response, nb element in tab = nb_values, address of tab = value[]
   output :       the number of values read from the string, should ne equal to nb_values
   --------------------------------------------------------------------------------------------------------*/

int getAtmosValues(char *response, int nb_values, float values[]){
  int num;
  char *pch = response;
  for(num = 0; num < nb_values; num++){
    pch = strpbrk(pch, "+-");
    if (pch == NULL) {
      break;
    }
    values[num] = strtof(pch, &pch);
  }

  return num;
}


void climavue50_measurement(float* Solar, float* Precip, float* StrikeCount, float* StrikeDist,
                            float* Wind, float* WDir, float* Gust, float* Temp, float* VPres,
                            float* APres, float* Humi, float* SensorTemp, float* XOrienTilt,
                            float* YOrienTilt, float* Compass, float* NWS, float* EWS) {
  //from https://github.com/EnviroDIY/Arduino-SDI-12
  SDI12 mySDI12(SDI_pin);

  char R0_rawdata[120] = {0};  // buffer for SDI-12 response to the R0 command
  const int R0_nb_values = 17; // # parameters from the climavue50
  float atmos_R0_values[R0_nb_values] = {0};
  int maxchars = sizeof(R0_rawdata) - 1;

/*example of cmd and response : (with SDI12, always start with adress, after cmd, and finish with "!")
    sdi12 cmd = 0R0!
    sdi12 data = 0+0+0.000+0+0+0.08+152.0+0.09+23.7+1.23+96.09+0.421+23.8+49.3-56.6+0-0.07+0.04
    value -9999.00 = no value for atmos41*/

  mySDI12.begin();
  mySDI12.sendCommand("0R0!");  // <a>R0! where address is 0
  mySDI12.flush();              // noop: does nothing actually
  delay(30); //SDI-12 delay before sensor response

  int index = 0;
  while(mySDI12.available()){
    R0_rawdata[index++] = mySDI12.read();
    if (index >= maxchars) {
        break;
    }
    delay(10);
  }

  Serial.printf("ClimaVue50 raw data: %s\n", R0_rawdata); // optionnal, debug
  getAtmosValues(R0_rawdata, R0_nb_values, atmos_R0_values);

  /*
  from https://github.com/DPIclimate/LoRaWAN-Arduino-Sensor-Sketches/blob/master/Meter-Atmos41/Meter-Atmos41.ino
  * [ 1- 2] Solar (0...1750)
   * [ 3- 4] Precipitation (0.000 ... 125.000)
   * [ 5- 6] Strikes Count (0 ... 65,535)
   * [ 7- 8] Strike Dist (0 ... 40)
   * [ 9-10] Wind Speed (0.00 ... 40.00)
   * [11-12] Wind Direct (0 ... 359)
   * [13-14] Wind Gust (0.00 ... 40.00)
   * [15-16] Air Temp (-40.0 ... 50.0)
   * [17-18] Vapour Press (0.00 ... 47.00)
   * [19-20] Atmos Press (50.01 ... 110.01)
   * [21-22] Relative Humidity (0.0 ... 100.0)
   * [23-24] Hmidity Sensor Temp (-40.0 ... 50.0)
   * [25-26] x-orientation (tilt) (0.0 ... 180.0)
   * [27-28] y-orientation (tilt) (0.0 ... 180.0)
   * [29-30] compass heading (0 ... 359)
   * [31-32] north wind speed (0.00 ... 40.00)
   * [33-34] east wind speed (0.00 ... 40.00)
    */
  *Solar = atmos_R0_values[0];
  *Precip = atmos_R0_values[1];
  *StrikeCount = atmos_R0_values[2];
  *StrikeDist = atmos_R0_values[3];
  *Wind = atmos_R0_values[4];
  *WDir = atmos_R0_values[5];
  *Gust = atmos_R0_values[6];
  *Temp = atmos_R0_values[7];
  *VPres = atmos_R0_values[8];
  *APres = atmos_R0_values[9];
  *Humi = atmos_R0_values[10];
  *SensorTemp = atmos_R0_values[11];
  *XOrienTilt = atmos_R0_values[12];
  *YOrienTilt = atmos_R0_values[13];
  *Compass = atmos_R0_values[14];
  *NWS = atmos_R0_values[15];
  *EWS = atmos_R0_values[16];
}

/* ----------------------------------------------------------------------------------------------------------
 * name :         store_data_on_flash
 * description :  if needed, append the current data to a file on flash.
 * source:        https://techtutorialsx.com/2018/08/13/esp32-arduino-LittleFS-append-content-to-file/
 * input :        httpRequestData: the string to be appended
 * output :       void
 * --------------------------------------------------------------------------------------------------------*/
void store_data_on_flash(const char* httpRequestData){
  Serial.printf("Storing to flash -> %s\n", httpRequestData);
  File myFile=LittleFS.open("/mydata.txt","a");
  if(!myFile){
    Serial.println("There was an error opening the file for appending");
  } else {
    myFile.print(httpRequestData);
    myFile.print("\n");
    myFile.flush();
    myFile.close();
  }
}

/* ----------------------------------------------------------------------------------------------------------
 * name : read_nb_records
 * description : check the number of records stored in the flash
 * input : void
 * output : void
 * --------------------------------------------------------------------------------------------------------*/
void read_nb_records(){
  File myFile = LittleFS.open("/mydata.txt");         // open content of mydata inside EEPROM
  if (!myFile) {
      Serial.println("Opening /mydata.txt failed - there is likely no such file of stored records.");
  } else {
    while(myFile.available()){                    // read all mydata file and count nb of records
      myFile.find("\n");
      RecordsInFlash++;                           // global variable
    }
    Serial.printf("Number of records stored in flash: %d\n", RecordsInFlash);
    myFile.flush();
    myFile.close();
  }
}
//....................................................................................................


/* ----------------------------------------------------------------------------------------------------------
 * name : transmit_stored_records
 * description : send older data to cloud server, nbMaxTransmits at a time to not overdrain
 * the battery
 * input : max number of transmit authorized by communication
 * output : void
 * --------------------------------------------------------------------------------------------------------*/
void transmit_stored_records(int nbMaxTransmits){
  int foundLeftovers = 0;                            // counter for the nb of lines
  int storedAgain = 0;                               // counter for records stored again
  int transmitAttempts = 0;                          // counter for submission attempts
  int successfulSubmissions = 0;                     // counter for successful submissions

  File myfile = LittleFS.open("/mydata.txt");
  if(!myfile){
    Serial.println("Failed to open file for reading - cannot transmit stored records.");
    return;
  }

  while(myfile.available()){                            // read all lines
    size_t len = myfile.readBytesUntil('\n', httpRequestData, sizeof(httpRequestData) - 1);
    httpRequestData[len] = '\0';

    foundLeftovers++;
    if (transmitAttempts < nbMaxTransmits){         // try to submit up to nbMaxTransmits records
      Serial.printf("\nAttempt to transmit stored record %d\n", transmitAttempts + 1);
      bool success = send_data_to_server(httpRequestData);
      if (success){
        RecordsInFlash--;
        successfulSubmissions++;
      } else {
        Serial.println("Transmission of stored record failed, storing again.");
        File backup = LittleFS.open("/tmp.txt", "a");
        if (!backup){
          Serial.println("Failed to open temporary file for appending.");
        } else {
          backup.print(httpRequestData);
          backup.print("\n");
          backup.flush();
          backup.close();
          storedAgain++;
        }
      }
      transmitAttempts++;
    } else {                          // store the records that don't belong to the lucky 5 again
      File backup = LittleFS.open("/tmp.txt", "a");
      if (!backup){
          Serial.println("Failed to open temporary file for appending.");
      } else {
        backup.print(httpRequestData);
        backup.print("\n");
        backup.flush();
        backup.close();
        storedAgain++;
      }
    }
  }
  myfile.flush();
  myfile.close();

  Serial.printf("Records found in flash: %d\n", foundLeftovers);
  Serial.printf("Records stored again in flash: %d\n", storedAgain);

  // clean files up - if all file operations worked out as expected; otherwise we try again next time
  if (successfulSubmissions + storedAgain == foundLeftovers){
    LittleFS.remove("/mydata.txt");
    LittleFS.rename("/tmp.txt", "/mydata.txt");
  }
}

/* ----------------------------------------------------------------------------------------------------------
 * name : calc_sleepSeconds
 * description : define second to wait until good interval SLEEP_TIME, new time will be a multiple of SLEEP_TIME
 * input : void
 * output : seconds (long)
 * --------------------------------------------------------------------------------------------------------*/
long calc_sleepSeconds(){
  tmElements_t structNow; // structure to store current time/date
  int prev_min; // previous round SENSOR_READ_EVERY_MINS minute

  breakTime(rtc.getEpoch(), structNow);
  prev_min = floor((float)structNow.Minute / (float)SENSOR_READ_EVERY_MINS) * SENSOR_READ_EVERY_MINS;
  structNow.Minute = prev_min;
  structNow.Second = 0;
  long sleepSeconds = makeTime(structNow) + SENSOR_READ_EVERY_MINS * 60 - rtc.getEpoch();

  // some plausibility checks (these conditions should never be met)
  if (sleepSeconds < 0){
    sleepSeconds = 0;
  }
  else if (sleepSeconds > SENSOR_READ_EVERY_MINS * 60){
    sleepSeconds = SENSOR_READ_EVERY_MINS * 60;
  }

  return sleepSeconds;
}

/* ----------------------------------------------------------------------------------------------------------
 * name : set_rtc_to_network_date
 * description : queries date and time from network and sets the RTC to this
 * input : void
 * output : void
 * --------------------------------------------------------------------------------------------------------*/
void set_rtc_to_network_datetime(){
  int Year = 0;
  int Month = 0;
  int Day = 0;
  int Hour = 0;
  int Min = 0;
  int Sec = 0;
  float timezone;

  if (modem.getNetworkTime(&Year, &Month, &Day, &Hour, &Min, &Sec, &timezone)) {
    rtc.setTime(Sec, Min, Hour, Day, Month, Year, 0);
  }
}

/* ----------------------------------------------------------------------------------------------------------
 * name : read_volt_pin
 * description : read analogue pin
 * input : pin number
 * output : voltage [mV] as uint16_6
 * --------------------------------------------------------------------------------------------------------*/
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

/* ----------------------------------------------------------------------------------------------------------
 * name :         blink_led
 * description :  visual effect
 * input :        nb of blinking, delay between
 * output :       void
 * --------------------------------------------------------------------------------------------------------*/
void blink_led(int nbBlinking, int delayMs){
  for (int i=0; i< nbBlinking; i++){
      digitalWrite(LED_PIN, LOW);                 // turn on LED
      delay(delayMs);
      digitalWrite(LED_PIN, HIGH);                // turn off LED
      delay(delayMs);
  }
}

/* ----------------------------------------------------------------------------------------------------------
 * name :         set_pdp
 * description :  sets pdp-context explicitly - if network connection cannot be established
 * input :        void
 * output :       void
 * --------------------------------------------------------------------------------------------------------*/
void set_pdp(const char* APN){
  Serial.printf("Trying to set pdp context with %s\n", APN);
  String pieces[24];
  String input;

  SerialAT.println("AT+CGDCONT?");
  delay(500);
  if (SerialAT.available()) {
    input = SerialAT.readString();
    int counter = 0;
    int lastIndex = 0;
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

    int numberOfPieces = 24;
    char buffer[100];
    for ( int y = 0; y < numberOfPieces; y++) {
      for ( int x = 0; x < pieces[y].length(); x++) {
        char c = pieces[y][x];  //gets one byte from buffer
        if (c == ',') {
          if (input.indexOf(": ") >= 0) {
            String data = input.substring((input.indexOf(": ") + 1));
            long cid = data.toInt();
            if (cid  > 0 && cid < 25) {
              snprintf(buffer, sizeof(buffer), "+CGDCONT=%ld,\"IP\",\"%s\",\"0.0.0.0\",0,0,0,0", cid, APN);
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

/* ----------------------------------------------------------------------------------------------------------
 * name :         get_apn
 * description :  get APN from Tajik network providers - if this fails, use DEFAULT_APN
 * input :        void
 * output :       void
 * --------------------------------------------------------------------------------------------------------*/
const char* get_apn(const char* imsi){
  // https://www.mcc-mnc.com/ // imsi information
  // https://www.apnsettings.org/tajikistan/ // apn information
  if (strcmp(imsi, "43604") == 0){           // babilon
      return "babilon";
  } else if (strcmp(imsi, "43603") == 0){    // megafon
      return "internet";
  } else if (strcmp(imsi, "43605") == 0){    // beeline
      return "internet.beeline.tj";
  } else if (strcmp(imsi, "43612") == 0 || strcmp(imsi, "43601") == 0){    // tcell
      return "tcell";
  } else {
      return DEFAULT_APN;
  }
}

/* ----------------------------------------------------------------------------------------------------------
 * name :         hashing
 * description :  hashes a string with SHA256. following
                  https://techtutorialsx.com/2018/05/10/esp32-arduino-mbed-tls-using-the-sha-256-algorithm/
 * input :        string - the payload to hash
 * output :       string - the hashed payload as a string
 * --------------------------------------------------------------------------------------------------------*/
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

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         WWCS_koalaboard_V1.0
   date :         20.03.2022
   description :  log data SHT30 and BMP384, send to cloud
   @authors :     Boris Orlowsky &  Jacques Grandjean
   @version :     1.0
   ------------------------------------------------------------------------------------------------------------------------------*/
//....................................................................................................
//....................................................................................................
/* INCLUDE */
#include "git_version.h"                           // read git_version.h for corresponding commit to git
#include <SPIFFS.h>                                // file system on flash
#include <string>
#define TINY_GSM_MODEM_SIM7000                     // define modem etc for TinyGSM
// #define TINY_GSM_MODEM_SIM7000SSL                     // define modem etc for TinyGSM
#define TINY_GSM_RX_BUFFER 1024                    // Set RX buffer to 1Kb
#include <TinyGsmClient.h>                         // this library requires the 2 defines above
#include <ESP32Time.h>
#include <TimeLib.h>
#include <ArduinoHttpClient.h>
#include <SSLClient.h>                             // https://github.com/OPEnSLab-OSU/SSLClient
#include <Wire.h>
#include "SHTSensor.h"                             // libraries for SHT30
// #include "SHT3x.h"                                 // libraries for SHT30
// #include <Adafruit_BME280.h>                       // libraries for the bme280
#include <esp_task_wdt.h>                          // for hardware watchdog
#include <StreamDebugger.h>

#include <LTC2942.h>                                // coulomb counter library
#include <SPI.h>
#include <Adafruit_BMP3XX.h>                        // BMP384 library

//....................................................................................................
/* DEFINE */
#define SerialAT Serial1                            // Serial communication with Modem
#define WDT_TIMEOUT 120                             // for hardware watchdog
#define uS_TO_S_FACTOR 1000000ULL                   // Conversion factor for micro seconds to seconds
#define UART_BAUD   9600                            // for the modem
#define PIN_DTR     25                              // 25 with old one
#define PIN_TX      26                              // 27 with old one
#define PIN_RX      27                              // 26 with old one
#define PWR_PIN     33                              // 4 with old one
#define MODEM_RST   32                              // 5 with old one
#define LED_PIN     12                              // for the LED //12 with old one
#define PIN_ADC_BAT1 36                             // resistor not connected on board, measured by coulomb counter
#define PIN_ADC_BAT2 39                             // resistor not connected on board, measured by coulomb counter
#define PIN_ADC_SOLAR 34                            // for solar panel 
#define ADC_BATTERY_LEVEL_SAMPLES 10
#define I2C1_SDA 4                                  // I2C1 data pins 
#define I2C1_SCL 0                                  // I2C1 data pins 
#define I2C2_SDA 15                                 // I2C2 data pins 
#define I2C2_SCL 2                                  // I2C2 data pins

#define BMP_SCK 18                                  // SPI connection pin
#define BMP_MISO 19                                 // SPI connection pin
#define BMP_MOSI 23                                 // SPI connection pin
#define BMP_CS 5                                    // SPI connection pin

//....................................................................................................
/* CONSTANTS AND CONFIGURATION */
const char COMPILE_DATE_FILE[] = __DATE__ " " __TIME__ " " __FILE__;
#define GSM_PIN ""                                 // set GSM PIN, if any
const int SLEEP_MINUTES = 10;                       // time between measurements
const char APN[] = "TM";                           // GPRS credential
const char GPRS_USER[] = "";
const char GPRS_PASS[] = "";
const int NETWORK_MODE = 38;                     // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE only 

// Server details - SLF setting
const char SERVER[] = "wwcs.slf.ch";             // SLF server
const char RESOURCE[] = "/post_data.php";        // resource path, for example: /post-data.php
const int PORT = 443;
#include "trusted_anchor_slf.h"

/*
// Server details - balcony setting // HERE
const char SERVER[] = "antennal-mosquito-1817.dataplicity.io"; // domain name: example.com, maker.ifttt.com, etc
const char RESOURCE[] = "/post_data.php";           // resource path, for example: /post-data.php
const int  PORT = 443;
#include "trusted_anchor_antennal.h"
*/
/*
  // Server details - cachtajnew setting             // HERE
  const char SERVER[] = "cachtajnew.myqnapcloud.com"; // domain name: example.com, maker.ifttt.com, etc
  const char RESOURCE[] = "/post_data.php";         // resource path, for example: /post-data.php
  const int  PORT = 8081;  
*/

//....................................................................................................
// global variables
// #define DUMP_AT_COMMANDS                       // See all AT commands, if wanted
#ifdef DUMP_AT_COMMANDS                           // if enabled it requires the streamDebugger lib
StreamDebugger debugger(SerialAT, Serial);
TinyGsm modem(debugger);
#else
TinyGsm modem(SerialAT);
#endif

ESP32Time rtc;                                    // object to interact with RTC
// TinyGsmClientSecure clients(modem);               // network client (secure)
TinyGsmClient client(modem);                      // several network clients
SSLClient clients(client, TAs, 1, A7);

const unsigned int fullCapacity = 5500; // Maximum value is 5500 mAh
LTC2942 gauge_battery1(20); // Takes R_SENSE value (in milliohms) as constructor argument, can be omitted if using LTC2942-1
TwoWire I2C_battery1 = TwoWire(0);  //I2C line for communicate with coulomb counter of battery 1
LTC2942 gauge_battery2(20); // Takes R_SENSE value (in milliohms) as constructor argument, can be omitted if using LTC2942-1
TwoWire I2C_battery2 = TwoWire(0);  //I2C line for communicate with coulomb counter of battery 2


// variables that survive in RTC memory during deep sleep
RTC_DATA_ATTR int sleepDelta = 0;                 // to capture deviation at wakeup due to RCT drift
int RecordsInFlash = 0;                             // counter of records stored in flash

/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
void setup() {
  //....................................................................................................
  /* variable definition */
  uint8_t mac[6];                                   // MAC address
  String loggerID;                                  // ID of the logger, include MAC address
  float bat1V = -999.99;                            // voltage of battery BORIS: changed to float
  float bat2V = -999.99;                            // voltage of battery
  float batV = -999.99;                             // here will store min of two battery voltages
  uint16_t solarV = -999;                        // voltage of Solar Panel
  float shtAirTemp = -999.99;                       // SHT Air Temperature, init with error value
  float shtAirHumi = -999.99;                       // SHT Air Humidity, init with error value
  float shtSoilTemp = -999.99;                      // SHT Soil Temperature, init with error value
  float shtSoilHumi = -999.99;                      // SHT Soil Humidity, init with error value
  float bmeTemp = -999.99;                          // BME280 Temperature, init with error value
  float bmeHumi = -999.99;                          // BME280 Humidity, init with error value
  float bmePres = -999.99;                          // BME280 Pressure, init with error value
  float bmpTemp = -999.99;                          // BMP384 Temperature, init with error value
  float bmpPres = -999.99;                          // BMP384 Pressure, init with error value
  float signalStrength = -999.99;                   // network signal strength, init with error value
  String httpRequestData;                           // data to be sent
  String timeStamp;                                 // GSM datetime
  unsigned long millisAtConnection;                 // millis() when initiating network - to compute sleepSecs
  int postResponse = -999;                           // http response, per default != 200
  int sleepSeconds = SLEEP_MINUTES * 60;            // this is the default value, valid if time update from network fails
  bool apnConnected = false;  
  bool batteryStatus = false;

  //....................................................................................................
  /* indicate start of code and WDT running */
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);
  blink_led(8, 50);                                // light show: start of code and watchdog
  esp_task_wdt_init(WDT_TIMEOUT, true);             // enable panic so ESP32 restarts
  esp_task_wdt_add(NULL);                           // add current thread to WDT watch

  init_comm_LTC2942();                              // init communication 2wires with coulomb counter
  //....................................................................................................
  /* only init coulomb counter at power start, not a wakeup start.*/
  esp_sleep_wakeup_cause_t wakeup_reason;
  wakeup_reason = esp_sleep_get_wakeup_cause();
  switch(wakeup_reason)
  {
    case ESP_SLEEP_WAKEUP_EXT0 : Serial.println("Wakeup caused by external signal using RTC_IO"); break;
    case ESP_SLEEP_WAKEUP_EXT1 : Serial.println("Wakeup caused by external signal using RTC_CNTL"); break;
    case ESP_SLEEP_WAKEUP_TIMER : Serial.println("Wakeup caused by timer"); break;
    case ESP_SLEEP_WAKEUP_TOUCHPAD : Serial.println("Wakeup caused by touchpad"); break;
    case ESP_SLEEP_WAKEUP_ULP : Serial.println("Wakeup caused by ULP program"); break;
    default : Serial.printf("Wakeup was not caused by deep sleep: %d\n",wakeup_reason); 
      init_param_LTC2942();                       // init once param of coulomb counter
      break;
  }

  
  /* Communication Init, collect basic information */

  Serial.begin(115200);                               // Init Console and send after several infos
  delay(1000);
  Serial.print("\nsetup()running on core ");
  Serial.println(xPortGetCoreID());
  Serial.println("watchdog configured with " + String(WDT_TIMEOUT) + "s timeout...");
  Serial.println("This is git commit " + String(GIT_VERSION));
  Serial.println("Compile date and source file: " + String(COMPILE_DATE_FILE));

  ESP_ERROR_CHECK_WITHOUT_ABORT(esp_efuse_mac_get_default(mac));  // read MAC address
  loggerID = String(mac[0], HEX) + ":" + String(mac[1], HEX) + ":" +
             String(mac[2], HEX) + ":" + String(mac[3], HEX) + ":" + String(mac[4], HEX) +
             ":" + String(mac[5], HEX);
  Serial.println("\nMAC: " + loggerID);

  //....................................................................................................
  if (!SPIFFS.begin(true)) {                        // start file system
    Serial.println("An Error has occurred while mounting SPIFFS");
  }
  read_nb_records();                                // read #records currently stored in flash
  //....................................................................................................
  /* collect battery information (via Coulomb Counter) */
  read_battery(&bat1V, &bat2V);  
  batV = min(bat1V, bat2V);                         // transmit minimum voltage for now
  
  pinMode(PIN_ADC_SOLAR, INPUT);                    // configure ADC for solar panel measurement
  solarV = read_volt_pin(PIN_ADC_SOLAR);            // get value from ADC in solarV
  if (bat1V > 3.3 || bat1V == 0 || bat2V > 3.3 || bat2V == 0) { // BORIS: changed from mV to V
    batteryStatus = true;
  }

  //....................................................................................................
  /* Check Time */
  timeStamp = rtc.getTime("%Y-%m-%d %H:%M:%S");     // get time from RTC
  Serial.println("RTC time 01: " + timeStamp);
  sleepSeconds = calc_sleepSeconds();               // check timing; if we have just woken up before the target time, we wait a bit
  if (sleepSeconds < 40) {
    sleepDelta += sleepSeconds;
    delay(sleepSeconds * 1000);
    sleepSeconds = calc_sleepSeconds();             // update sleepSeconds
    timeStamp = rtc.getTime("%Y-%m-%d %H:%M:%S");   // ... and update timestamp
  } else if ((SLEEP_MINUTES * 60) - sleepSeconds < 40) { // ... if we are a bit too late, never mind, but wake up a bit earlier next time
    sleepDelta += sleepSeconds - (SLEEP_MINUTES * 60);
  }
  if (sleepDelta > 10) {                            // the sleepDelta should remain small
    sleepDelta = 10;
  }
  if (sleepDelta < -10) {
    sleepDelta = -10;
  }
  millisAtConnection = millis();                    // store millis when you are here, to compute sleepSecs later
  Serial.println("RTC time: " + timeStamp);
  Serial.println("Seconds to sleep when going to sleep: " + String(sleepSeconds));
  Serial.println("Correction of sleep seconds based on past connects: " + String(sleepDelta));

  //....................................................................................................
  /* sensor measurements*/    
  if (!sht30_measurement(&shtAirTemp, &shtAirHumi, I2C1_SDA, I2C1_SCL)) {
    Serial.println("Could not make a valid SHT30 measurement on I2C1, check wiring!");
  }
  Serial.println("SHT30 measurement on I2C1: " + String(shtAirTemp) + "; " + String(shtAirHumi));
  
/*
  if (!sht30_measurement(&shtSoilTemp, &shtSoilHumi, I2C2_SDA, I2C2_SCL)) {
    Serial.println("Could not make a valid SHT30 measurement on I2C2, check wiring!");
  }
  Serial.println("SHT30 measurement on I2C2: " + String(shtSoilTemp) + "; " + String(shtSoilHumi));
  */
//  if (!bme_measurement(&bmeTemp, &bmeHumi, &bmePres)) {
//    Serial.println("Could not make a valid BME280 measurement, check wiring!");
//  }
//  Serial.println("BME280 measurement: " + String(bmeTemp) + "; " + String(bmeHumi) +
//11                 "; " + String(bmePres));
                 
  if (!bmp_measurement(&bmpTemp, &bmpPres)) {
    Serial.println("Could not make a valid BMP384 measurement, check wiring!");
  }
  Serial.println("BMP384 measurement: " + String(bmpTemp) + "; " + String(bmpPres));
  //....................................................................................................
  /* Prepare data to be publish */
  httpRequestData = "timestamp=" + timeStamp +
                    "&ta=" + String(shtAirTemp) + "&rh=" + String(shtAirHumi) + "&p=" + String(bmpPres) +
                    "&logger_ta=" + String(bmpTemp) + "&logger_rh=" + String(bmeHumi) +
                    "&U_Battery=" + String(batV) + "&U_Solar=" + String(solarV) +
                    "&loggerID=" + loggerID + "&git_version=" + String(GIT_VERSION);

  //....................................................................................................
  /* try to publish to network, publish old values, or store new one in database if no comm */
  Serial.println("If battery allows, attempt transmission.");
  if (batteryStatus) {                              // enough power to discuss with modem
    apnConnected = connect_to_network(&signalStrength);
    if (apnConnected) {                             // if network works
      Serial.println("... OK");
      set_rtc_to_network_datetime();                // get and set current date / time to RTC
      signalStrength = modem.getSignalQuality();           // network signal strength; append to httpRequestData
      Serial.println("Signal quality: " + String(signalStrength));
      httpRequestData += "&signalStrength=" + String(signalStrength);
      postResponse = send_data_to_server(httpRequestData); // send data
      if (postResponse == 200) {  // submission sucessful
        // check whether we have any leftover data and try to submit these (only if this post request successful)
        if (RecordsInFlash > 0) {
          transmit_stored_records(5);                    // submit up to 5 records from the flash
        }
      }
    } else {                                       // apnconnect did not work...
      httpRequestData += "&signalStrength=" + String(signalStrength); // append error code in SignalStrength  
    }    
  } else {
    blink_led(4, 200);                              // lightshow: battery low, don't try to init modem
  }
 
  if (!apnConnected || postResponse != 200) {       // plan B: store, reset modem, sleep
    Serial.println("... fail. Storing measurements to flash (if not full), resetting modem and going to sleep.");    
    if (RecordsInFlash < 1200){                     // don't store too many records... reading the file becomes slow.
      store_data_on_flash(httpRequestData);        
    } else {
      Serial.println("Already 1200 records in flash. Current record not stored.");
    }
    if (batteryStatus){                             // if no connection despite enough battery      
      blink_led(8, 200);                            // light show: issue with connection
      modem_reset();                                // do a hard reset before going to sleep
    }
  }

  //....................................................................................................
  /* end of code, initiate sleep mode until next measurement (start again setup function at wakeup) */
  clients.stop();
  Serial.println(F("Server disconnected"));
  Serial.print("Powering-off modem");
  modem_off();

  // esp_deep_sleep_start(); // just for now... BORIS. this prevents wake up.
  
  // now go to sleep
  // update sleep time incl network time and delta
  sleepSeconds = sleepSeconds - (int)((float)(millis() - millisAtConnection) / 1000.0) +
                 sleepDelta;
  if (sleepSeconds > SLEEP_MINUTES * 60) {             // some plausibility checks
    sleepSeconds = SLEEP_MINUTES * 60;
  }
  if (sleepSeconds < 0) {
    sleepSeconds = 0;
  }
  Serial.print("Going to sleep. sleepsecs incl correction for network time and delta: ");
  Serial.println(sleepSeconds);
  esp_sleep_enable_timer_wakeup((sleepSeconds) * uS_TO_S_FACTOR);
  delay(200);
  blink_led(2, 200);                                    // light show: end of code
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
   name :         init_comm_LTC2942, init_param_LTC2942 and read_battery
   description :  init param coulomb counter, read voltage, temperature and charge from the two batteries
   input :        pointers for battery parameters (float*)
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
void init_comm_LTC2942(){
  I2C_battery1.begin(I2C2_SDA, I2C2_SCL);   // BORIS: why do you use I2C2 for battery1?--> JACK : on hardware, I2C2 is connected to bat1, and I2C1 is connected to bat2
  gauge_battery1.begin(I2C_battery1);
  I2C_battery2.begin(I2C1_SDA, I2C1_SCL);
  gauge_battery2.begin(I2C_battery2);
}
void init_param_LTC2942(){
  gauge_battery1.setBatteryCapacity(fullCapacity);
//  gauge_battery1.setBatteryToFull(); // Sets accumulated charge registers to the maximum value
  gauge_battery1.setRawAccumulatedCharge(0x7FFF); // Sets accumulated charge registers to medium value
  gauge_battery1.setADCMode(ADC_MODE_SLEEP); // In sleep mode, voltage and temperature measurements will only take place when requested
  gauge_battery1.startMeasurement();  

  gauge_battery2.setBatteryCapacity(fullCapacity);
//  gauge_battery2.setBatteryToFull(); // Sets accumulated charge registers to the maximum value
  gauge_battery2.setRawAccumulatedCharge(0x7FFF); // Sets accumulated charge registers to the medium value
  gauge_battery2.setADCMode(ADC_MODE_SLEEP); // In sleep mode, voltage and temperature measurements will only take place when requested
  gauge_battery2.startMeasurement();
}
  
void read_battery(float* bat1V, float* bat2V){

  float voltage1 = gauge_battery1.getVoltage();
  Serial.print(F("Voltage battery 1: "));
  if (voltage1 >= 0) {                      // BORIS: you do not initialize bat1 to 0 explicitly. should we? --> JACK : read from coulomb counter, <0 if issue
    Serial.print(voltage1, 3);
    Serial.println(F(" V"));
    *bat1V=voltage1;
  } else {
    Serial.println(F("Volt. Bat1: Not supported by LTC2942"));
  }
  float temperature1 = gauge_battery1.getTemperature();
  Serial.print(F("Temperature battery 1: "));
  if (temperature1 >= 0) {                 // BORIS: this threshold does not make sense --> JACK : take from git example : temperature of board should not be under 0.. but could be delete
    Serial.print(temperature1, 2);
    Serial.println(F(" 'C"));
  } else {
    Serial.println(F("Temp Bat1: Not supported by LTC2942"));
  }

  unsigned int raw1 = gauge_battery1.getRawAccumulatedCharge();
  Serial.print(F("Raw Accumulated Charge: "));
  Serial.println(raw1, DEC);

  float capacity1 = gauge_battery1.getRemainingCapacity();
  Serial.print(F("Battery Capacity: "));
  Serial.print(capacity1, 3);
  Serial.print(F(" / "));
  Serial.print(fullCapacity, DEC);
  Serial.println(F(" mAh"));

  
//================================================

  float voltage2 = gauge_battery2.getVoltage();
  Serial.print(F("Voltage battery 2: "));
  if (voltage2 >= 0) {
    Serial.print(voltage2, 3);
    Serial.println(F(" V"));
    *bat2V=voltage2;
  } else {
    Serial.println(F("Volt. Bat2: Not supported by LTC2941"));
  }
  float temperature2 = gauge_battery2.getTemperature();
  Serial.print(F("Temperature battery 2: "));
  if (temperature2 >= 0) {
    Serial.print(temperature2, 2);
    Serial.println(F(" 'C"));
  } else {
    Serial.println(F("Temp Bat 2: Not supported by LTC2941"));
  }

  unsigned int raw2 = gauge_battery2.getRawAccumulatedCharge();
  Serial.print(F("Raw Accumulated Charge: "));
  Serial.println(raw2, DEC);

  float capacity2 = gauge_battery2.getRemainingCapacity();
  Serial.print(F("Battery Capacity: "));
  Serial.print(capacity2, 3);
  Serial.print(F(" / "));
  Serial.print(fullCapacity, DEC);
  Serial.println(F(" mAh"));
}


/* --------------------------------------------------------------------------------------------------------------------------------
   name :         modem_on
   description :  power on the modem, inspired by https://github.com/nikil511/LilyGO-T-SIM7000G/blob/master/examples/Platformio_Arduino_Thingsboard/src/main.cpp
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
void modem_on(){
  // power on modem....................................................................................................
  // based on https://www.manualslib.com/manual/1498555/Simcom-Sim7000g.html?page=25#manual
  // note that the koala board has logical inverters between the pins - this means that HIGH=LOW ;-)Serial.println("Powering on modem... (6s)");     // power on modem and give it some time to wake up (https://github.com/vshymanskyy/TinyGSM/issues/381)
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH);
  delay(100); // Ton 73 ms
  digitalWrite(PWR_PIN, LOW);
  delay(6000);
}



/* --------------------------------------------------------------------------------------------------------------------------------
   name :         modem_reset
   description :  do a hardware reset of the modem, inspired by https://github.com/nikil511/LilyGO-T-SIM7000G/blob/master/examples/Platformio_Arduino_Thingsboard/src/main.cpp
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
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

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         modem_off
   description :  does the power-off of the modem
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
void modem_off() {
  if (modem.poweroff()) {                                  // turn off modem (software)
    Serial.println("... OK");
  } else {                                                 // if this fails: hardware
    Serial.println("Hardware modem power down... (3s)");  
    // note that the koala board has logical inverters between the pins - this means that HIGH=LOW ;-)
    pinMode(PWR_PIN, OUTPUT);
    digitalWrite(PWR_PIN, HIGH);
    delay(1300);    //Datasheet Toff = 1.2s
    digitalWrite(PWR_PIN, LOW);
    delay(1700);
  }
  
  pinMode(PWR_PIN, OUTPUT);                                 
  digitalWrite(PWR_PIN, LOW);                              // pull pwr_pin low, to prevent esp from restarting the modem
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         connect_to_network
   description :  do init of the modem
   input :        void
   output :       boolean - whether everything needed to connect to apn worked out
   ------------------------------------------------------------------------------------------------------------------------------*/
bool connect_to_network(float* signalStrength) {
  // power on modem....................................................................................................
  modem_on();

  // establish communication with and initialize modem....................................................................................................
  SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX); // establish serial connection with modem
  delay(1000);
  if (modem.init()) {
    Serial.println("   ... init modem successful ...");
  } else {
    *signalStrength = -333.33;                      // error code - init failed
    Serial.println("  failed to init modem. Try a soft / hard reset of the modem.");
    esp_task_wdt_reset();
    if (modem.restart()) {
      Serial.println("Modem soft restart successful.");
    } else {
      *signalStrength = -444.44;                    // error code - soft reset failed
      esp_task_wdt_reset();
      modem_reset();              
      if (modem.init()) {                           //        after hardware reset, try a init
        Serial.println("Init modem successful after hard reset.");
      } else {
        *signalStrength = -555.55;                  // error code - hard reset failed
        Serial.println("Failed to init modem after hard reset.");
        return false;
      }
    }
  }
  // configure modem and connect to network and APN ....................................................................................................
  modem.sendAT("+SGPIO=0,4,1,0");                   // Set SIM7000G GPIO4 LOW, turn off GPS power (only for board version 20200415)
  if (GSM_PIN && modem.getSimStatus() != 3) {       // Unlock your SIM card with a PIN if needed
    modem.simUnlock(GSM_PIN);
  }

  Serial.print("Setting network modes... ");        // set network modes
  while (!modem.setNetworkMode(NETWORK_MODE)) {                // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE only
    delay(100);
  }
  while (!modem.setPreferredMode(1)) {              // 1 CAT-M; 2 NB-Iot; 3 CAT-M and NB-IoT
    delay(100);
  }

  // connect to network
  Serial.print("Waiting for network... ");
  modem.waitForNetwork();                           // this tries to connect for 60s
  if (!modem.isNetworkConnected()){                 // if this did not succeed...
    Serial.println("in vain. Setting pdp-context and trying to connect again.");
    esp_task_wdt_reset();                           // reset watchdog
    set_pdp();                                      // try to set pdp-context explicitly...
    modem.waitForNetwork();                         // ... and try to connect once more
  }
  
  if (modem.isNetworkConnected()) {                 // if successful, we connect to apn
    *signalStrength = -777.77;                       // error code - signalStrength remains at this if apn-connect fails
    Serial.println("Network connected");
    Serial.print("Connecting to: " + String(APN));  //    connect to APN
    return modem.gprsConnect(APN, GPRS_USER, GPRS_PASS);
  } else {
    *signalStrength = -666.66;                       // error code - network connect failed
    return false;
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         send_data_to_server
   description :  do init of the modem
   input :        data to send
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
int send_data_to_server(String httpRequestData) {
  const String contentType = "application/x-www-form-urlencoded";
  int responseStatusCode = 999;
  long now_secs = rtc.getEpoch();                           // set current time for SSL
  uint32_t ssl_days = 719528 + elapsedDays(now_secs);
  uint32_t ssl_secs = elapsedSecsToday(now_secs);
  Serial.println("For SSL dating: Days since AD: " + String(ssl_days) + ", Secs of today: " + String(ssl_secs));
  clients.setVerificationTime(ssl_days, ssl_secs);

  if (clients.connect(SERVER, PORT)) {                        // if server is in reach
    Serial.println("Connected to " + String(SERVER));
    HttpClient https(clients, SERVER, PORT);                  // init https client
    https.connectionKeepAlive(); // L200 https://github.com/vshymanskyy/TinyGSM/blob/master/examples/HttpsClient/HttpsClient.ino
    Serial.println("Trying post request -> " + httpRequestData);
    https.post(RESOURCE, contentType, httpRequestData);
    responseStatusCode = https.responseStatusCode();
    if (responseStatusCode == 200) {
      Serial.println("Post request successful.");
    }
    String response = https.responseBody();
    Serial.println("Response code: " + String(responseStatusCode) + "; Response body: " + response);
    https.stop();
  } else {
    Serial.println("Connection to " + String(SERVER) + " failed.");
  }
  return (responseStatusCode);
}
/* --------------------------------------------------------------------------------------------------------------------------------
   name :         bme_measurement
   description :  do two measure, check plausibility
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
/*
bool bme_measurement(float* temperature, float* humidity, float* pressure) {
  Adafruit_BME280 bme;                                              // sensor type BME280 variable
  float measureTemp1, measureTemp2, measureHum1, measureHum2;
  float measurePress1, measurePress2;
  int i = 0;                                                        // init counter i
  int nbMaxTries = 5;                                               // number of try to have good measure
  bool plausibility = false;                                        // init plausibilty to false

  while (i < nbMaxTries && !plausibility) {
    if (bme.begin(0x76)) {                                          // read bme280 sensor
      measureTemp1 = bme.readTemperature();                         // first set of values
      measureHum1 = bme.readHumidity();
      measurePress1 = bme.readPressure() / 100.0;
      measureTemp2 = bme.readTemperature();                         // 2nd set of values
      measureHum2 = bme.readHumidity();
      measurePress2 = bme.readPressure() / 100.0;

      if (fabs(measureTemp1 - measureTemp2) < 1.0 && measureTemp1 < 99.0 &&
          measureTemp1 > -80.0) {            // check plausibility
        *temperature = (measureTemp1 + measureTemp2) / 2.0;
        *humidity = (measureHum1 + measureHum2) / 2.0;
        *pressure = (measurePress1 + measurePress2) / 2.0;
        plausibility = true;
      } else {
        *temperature = -999.99;
        *humidity = -999.99;
        *pressure = -999.99;
        plausibility = false;
      }
    }
    i++;
  }
  return plausibility;
}
*/
/* --------------------------------------------------------------------------------------------------------------------------------
   name :         bmp_measurement
   description :  do two measure, check plausibility
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
bool bmp_measurement(float* temperature, float* pressure) {
  Adafruit_BMP3XX bmp;        // sensor type BMP384 variable
  float measureTemp1, measureTemp2;
  float measurePress1, measurePress2;
  int i = 0;                                                        // init counter i
  int nbMaxTries = 5;                                               // number of try to have good measure
  bool plausibility = false;                                        // init plausibilty to false
  
  while (i < nbMaxTries && !plausibility) {
    if (! bmp.begin_SPI(BMP_CS, BMP_SCK, BMP_MISO, BMP_MOSI)) {  // software SPI mode
    // Set up oversampling and filter initialization
//      bmp.setTemperatureOversampling(BMP3_OVERSAMPLING_2X);  // ---> JACK : number of performreading before udpate register
//      bmp.setPressureOversampling(BMP3_OVERSAMPLING_16X);

      
      bmp.performReading();                                   // JACK: first measure wrong..  
      bmp.performReading();
      measureTemp1 = bmp.temperature;                         // first set of values
      measurePress1 = bmp.pressure / 100.0;
      bmp.performReading();                                   
      measureTemp2 = bmp.temperature;                         // second set of values
      measurePress2 = bmp.pressure / 100.0;
      
      if (fabs(measureTemp1 - measureTemp2) < 1.0 && measureTemp1 < 99.0 &&
          measureTemp1 > -80.0) {            // check plausibility
        *temperature = (measureTemp1 + measureTemp2) / 2.0;
        *pressure = (measurePress1 + measurePress2) / 2.0;
        plausibility = true;
      } else {
        *temperature = -999.99;
        *pressure = -999.99;
        plausibility = false;
      }
    }
    i++;
  }
  return plausibility;
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         sht30_measurement
   description :  do two measure, check plausibility
   input :        void
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
bool sht30_measurement(float* temperature, float* humidity, const int mySDA, const int mySCL){  
  SHTSensor sht30(SHTSensor::SHT3X);                                           // sensor type SHT3X variable
  float measureTemp1, measureTemp2, measureHum1, measureHum2;
  int i = 0;                                                                   // init counter i
  int nb_try = 5;                                                              // number of try to have good measure
  bool plausibility = false;                                                   // init plausibilty to false
  
  TwoWire myI2C=TwoWire(0);                                                    // init I2C bus
  myI2C.begin(mySDA, mySCL);    
  do {                                                                         // read sht30 sensor
    if (sht30.init(myI2C)){                                                   
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
      } else {
        *temperature = -999.99;
        *humidity = -999.99;
        plausibility = false;
      }
    }
    i++;
  } while (i != nb_try && plausibility != true);                                  // try to have plausible value max nb_try
  return plausibility;
}
/*
bool sht_measurement(float* temperature, float* humidity, const int SDA, const int SCL) {
  SHT3x sht;                                               // sensor type SHT3X variable
  float measureTemp1, measureTemp2, measureHum1, measureHum2;
  int i = 0;                                                                     // init counter i
  int nb_try = 5;                                                                // number of try to have good measure
  bool plausibility = false;                                                     // init plausibilty to false

  do {
    sht.Begin(SDA, SCL);                                                         // read sht30 sensor
    sht.UpdateData(SDA);
    measureTemp1 = sht.GetTemperature();                                   // first set of values
    measureHum1 = sht.GetRelHumidity();
    sht.UpdateData(SDA);
    measureTemp2 = sht.GetTemperature();                                   // second set of values
    measureHum2 = sht.GetRelHumidity();
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
    i++;
  } while (i != nb_try && plausibility != true);                                  // try to have plausible value max nb_try
  return plausibility;
}
*/

/* --------------------------------------------------------------------------------------------------------------------------------
   name :         store_data_on_flash
   description :  if needed, append the current data to a file on flash.
   source:        https://techtutorialsx.com/2018/08/13/esp32-arduino-spiffs-append-content-to-file/
   input :        httpRequestData: the string to be appended
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
void store_data_on_flash(String httpRequestData){
  Serial.println("Storing to flash -> " + httpRequestData);
  File myFile=SPIFFS.open("/mydata.txt","a");
  if(!myFile){
    Serial.println("There was an error opening the file for appending");        
  } else {
    myFile.print(httpRequestData + "\n");
    myFile.flush();
    myFile.close();
  }  
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name : read_nb_records
   description : check the number of records stored in the flash
   input : void
   output : void
   ------------------------------------------------------------------------------------------------------------------------------*/
void read_nb_records() {
  String mystring;                                  // to temporarily store a record
  File myFile = SPIFFS.open("/mydata.txt");         // open content of mydata inside EEPROM
  if (!myFile) {
    Serial.println("Opening /mydata.txt failed");
  } else {
    while (myFile.available()) {                  // read all mydata file and count nb of records
      mystring = myFile.readStringUntil('\n');
      RecordsInFlash++;                           // global variable
    }
    Serial.println("Number of records stored in flash: " + String(RecordsInFlash));
  }
  myFile.flush();
  myFile.close();
}
//....................................................................................................


/* --------------------------------------------------------------------------------------------------------------------------------
   name : transmit_stored_records
   description : send older data to cloud server, nbMaxTransmits at a time to not overdrain
   the battery
   input : max number of transmit authorized by communication
   output : void
   ------------------------------------------------------------------------------------------------------------------------------*/
void transmit_stored_records(int nbMaxTransmits){  
  int foundLeftovers = 0;                            // counter for the nb of lines
  int storedAgain = 0;                               // counter for records stored again
  int transmitAttempts = 0;                          // counter for submission attempts
  int successfulSubmissions = 0;                     // counter for successful submissions
  int mypostResponse = 999;                          // response code from http post 
  String mystring;                                   // single record
  
  File myfile = SPIFFS.open("/mydata.txt");
  if(!myfile){
    Serial.println("Failed to open file for reading");    
  }
  
  while(myfile.available()){                            // read all lines 
    esp_task_wdt_reset();                               // reset watchdog
    mystring = myfile.readStringUntil('\n');    
    foundLeftovers++;
    if (transmitAttempts < nbMaxTransmits){         // try to submit up to nbMaxTransmits records      
      Serial.println("\nAttempt to transmit stored record " + String(transmitAttempts + 1));          
      mypostResponse = send_data_to_server(mystring);
      if (mypostResponse == 200){
        RecordsInFlash--;
        successfulSubmissions++;
      } else {
        Serial.println("Transmission of stored record failed, storing again.");
        File backup = SPIFFS.open("/tmp.txt", "a");
        if (!backup){
          Serial.println("Failed to open temporary file for appending.");         
        } else {
          backup.print(mystring + "\n");
          backup.flush();
          backup.close();
          storedAgain++;
        }
      }
      transmitAttempts++;
    } else {                          // store the records that don't belong to the lucky 5 again
      File backup = SPIFFS.open("/tmp.txt", "a");
      if (!backup){
          Serial.println("Failed to open temporary file for appending.");         
      } else {        
        backup.print(mystring + "\n");
        backup.flush();
        backup.close();
        storedAgain++;
      }
    }
  }
  myfile.flush();
  myfile.close();
  
  Serial.println("Records found in flash: " + String(foundLeftovers));  
  Serial.println("Records stored again in flash: " + String(storedAgain)); 
  
  // clean files up - if all file operations worked out as expected; otherwise we try again next time
  if (successfulSubmissions + storedAgain == foundLeftovers){
    SPIFFS.remove("/mydata.txt");
    SPIFFS.rename("/tmp.txt", "/mydata.txt");
  }
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name : calc_sleepSeconds
   description : define second to wait until good interval SLEEP_TIME, new time will be a multiple of SLEEP_TIME
   input : void
   output : seconds (long)
   ------------------------------------------------------------------------------------------------------------------------------*/
long calc_sleepSeconds() {
  tmElements_t structNow; // structure to store current time/date
  int prev_min; // previous round SLEEP_MINUTES minute

  breakTime(rtc.getEpoch(), structNow);
  prev_min = floor((float)structNow.Minute / (float)SLEEP_MINUTES) * SLEEP_MINUTES;
  structNow.Minute = prev_min;
  structNow.Second = 0;
  long sleepSeconds = SLEEP_MINUTES * 60 - rtc.getEpoch() + makeTime(structNow);

  if (sleepSeconds > SLEEP_MINUTES * 60) {             // some plausibility checks
    sleepSeconds = SLEEP_MINUTES * 60;
  }
  if (sleepSeconds < 0) {
    sleepSeconds = 0;
  }
  return (sleepSeconds);
}

/* --------------------------------------------------------------------------------------------------------------------------------
   name : set_rtc_to_network_date
   description : queries date and time from network and sets the RTC to this
   input : void
   output : void
   ------------------------------------------------------------------------------------------------------------------------------*/
void set_rtc_to_network_datetime() {
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
   name : read_volt_pin
   description : read analogue pin
   input : pin number
   output : voltage [mV] as uint16_6
   ------------------------------------------------------------------------------------------------------------------------------*/
uint16_t read_volt_pin(int pin) {
  uint32_t in = 0;
  for (int i = 0; i < ADC_BATTERY_LEVEL_SAMPLES; i++)
  {
    in += (uint32_t)analogRead(pin);
  }
  in = (int)in / ADC_BATTERY_LEVEL_SAMPLES;

  uint16_t mv = ((float)in / 4096) * 3600 * 2;

  return (mv);
}





  
/* --------------------------------------------------------------------------------------------------------------------------------
   name :         blink_led
   description :  visual effect
   input :        nb of blinking, delay between
   output :       void
   ------------------------------------------------------------------------------------------------------------------------------*/
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
void set_pdp(){
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
              modem.sendAT("+CGDCONT=" + String(data.toInt()) + ",\"IP\",\"" + String(APN) + "\",\"0.0.0.0\",0,0,0,0");
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


  Serial.println("\n\n\nWaiting for network...");
  if (!modem.waitForNetwork()) {
    delay(10000);
    return;
  }

  if (modem.isNetworkConnected()) {
    Serial.println("Network connected after setting pdp-context explicitly.");
  }
}

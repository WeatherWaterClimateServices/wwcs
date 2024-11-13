 /* --------------------------------------------------------------------------------------------------------------------------------
  * name :         ttgo_sim7000g_sht30_bme280
 * date :         12.01.2022. last revision summer 2024
 * description :  log data SHT30 and BME280, send to cloud
 * @authors :     Boris Orlowsky &  Jacques Grandjean & David Ibanez
 * @version :     see git_version
 * ------------------------------------------------------------------------------------------------------------------------------*/
//....................................................................................................  
//....................................................................................................  
/* CONSTANTS AND CONFIGURATION - TO BE SET / OVERWRITTEN BY FLASHGORDON*/
const char SITE_ID[] = "FlashSite";                 // dummy site ID
const char GIT_VERSION[] = "FlashGIT";       // dummy git version
const char GSM_PIN[] = "";                       // dummy GSM PIN
const int SLEEP_MINUTES = 10;                    // time between measurements
const char DEFAULT_APN[] = "FlashProvider";                 // dummy APN
const char GPRS_USER[] = "";                     // GPRS credential
const char GPRS_PASS[] = "";                     // GPRS credential
const int NETWORK_MODE = 1234;                     // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE only 
const bool JSON_PY_API = true;                  // select whether transmission uses the json/python api or the previous php api
const char SERVER[] = "wwcs.tj"; // domain name: example.com, maker.ifttt.com, etc
const char RESOURCE[] = "/post/insert";           // resource path, for example: /post-data.php
const int  PORT = 443;
const int MAX_LOOPS = 500;
const int MAX_RECORDS = 300;

/* DEFINES - PARTLY BOARD-SPECIFIC*/
#define SerialAT Serial1                           // Serial communication with Modem
#define WDT_TIMEOUT 180                            // for hardware watchdog
#define uS_TO_S_FACTOR 1000000ULL                  // Conversion factor for micro seconds to seconds
#define UART_BAUD   9600                           // for the modem
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

/* INCLUDE */
#include <LittleFS.h>                                // file system on flash
#include <string>
#include <TinyGsmClient.h>                         // this library requires the 2 defines above
#include <SSLClient.h>                           // https://github.com/govorox/SSLClient
#include <ESP32Time.h>
#include <TimeLib.h>
#include <ArduinoHttpClient.h>
#include <SHTSensor.h>                             // libraries for SHT30
#include <Adafruit_Sensor.h>
#include <Adafruit_BME280.h>                        // BME280 library
#include <StreamDebugger.h>
#include <ArduinoJson.h>

#include "esp_err.h"                               // for hardware watchdog and encryption
#include "esp_task_wdt.h"                          
#include "mbedtls/md.h"
#include "esp_mac.h"                              
#include "driver/gpio.h"                          
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
int RecordsInFlash = 0;                           // counter of records stored in flash
ESP32Time rtc;                                    // object to interact with RTC
//TinyGsmClientSecure clients(modem);               // network client (secure)
TinyGsmClient client(modem);                      // several network clients
SSLClient clients(&client);                           

TwoWire I2C_1 = TwoWire(0);  //I2C1 line
TwoWire I2C_2 = TwoWire(1);  //I2C2 line

// variables that survive in RTC memory during deep sleep
RTC_DATA_ATTR int sleepDelta = 0;                 // to capture deviation at wakeup due to RCT drift
RTC_DATA_ATTR int loopCounter = 0;                // count the cycles and force ESP to restart every MAX_LOOPS loops 

// Global (static) buffers
char SHA256PayLoad[80];                           // combined string which goes into SHA256
char httpRequestData[2048];                       // data to be sent
char timeStamp[128];                              // GSM datetime

/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
/*--------------------------------------------------------------------------------------------------------------------------------*/
void setup() {
//....................................................................................................  
/* variable definition */
  uint8_t mac[6];                                   // MAC address
  char loggerID[18];                                  // ID of the logger, include MAC address
  uint16_t batV;                                    // voltage of battery
  uint16_t solarV;                                  // voltage of Solar Panel  
  
  float shtAirTemp = -999.0;                       // SHT Air Temperature, init with error value
  float shtAirHumi = -999.0;                       // SHT Air Humidity, init with error value 
  float shtSoilTemp = -999.0;                      // SHT Soil Temperature, init with error value
  float shtSoilHumi = -999.0;                      // SHT Soil Humidity, init with error value 
  float bmeTemp = -999.0;                          // BME280 Temperature, init with error value
  float bmeHumi = -999.0;                          // BME280 Humidity, init with error value 
  float bmePres = -999.0;                          // BME280 Pressure, init with error value
  
  float signalStrength = -999.0;                   // network signal strength, init with error value  
  unsigned long millisAtConnection;                 // millis() when initiating network - to compute sleepSecs
  bool postSuccess = false;                         // whether the http response was successful (2XX) or not
  int sleepSeconds = SLEEP_MINUTES * 60;            // this is the default value, valid if time update from network fails  
  
  bool apnConnected = false;                        // bool: wether we connected to APN
  bool batteryStatus = false;                       // battery ok for turning on the modem?
  
  char hashedKey[64];                               // hashed payloag from SHA256 as a string for the JSON
  DynamicJsonDocument JSONData(2048);               // to store data for transmission as JSON
  int len;                                          // helper variable to store the length of something
   
//....................................................................................................
/* indicate start of code and WDT running */
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);
  blink_led(2, 200);                                // light show: start of code and watchdog
  esp_task_wdt_config_t twdt_config = {             // inserted from https://github.com/espressif/esp-idf/blob/v5.2.2/examples/system/task_watchdog/main/task_watchdog_example_main.c
    .timeout_ms = 180000,
    .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,    // Bitmask of all cores
    .trigger_panic = true
  };
  
  ESP_ERROR_CHECK(esp_task_wdt_reconfigure(&twdt_config)); // from here: https://forum.arduino.cc/t/watchdog-doesnt-work-with-esp32-3-0-1/1270966
  esp_task_wdt_add(NULL);                           // add current thread to WDT watch
  
//....................................................................................................  
/* Communication Init, collect basic information */  
  Serial.begin(115200);                               // Init Console and send after several infos
  delay(1000);                                      
  Serial.print("\nsetup()running on core ");
  Serial.println(xPortGetCoreID());
  Serial.printf("watchdog configured with %d s timeout...\n", WDT_TIMEOUT);
  Serial.printf("This is git commit %s\n", GIT_VERSION);
  Serial.printf("Compile date and source file: %s\n", COMPILE_DATE_FILE);
  
  ESP_ERROR_CHECK_WITHOUT_ABORT(esp_efuse_mac_get_default(mac));  // read MAC address
  sprintf(loggerID, "%02x:%02x:%02x:%02x:%02x:%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  Serial.printf("\nMAC: %s\n", loggerID);

  // init I2C buses
  Serial.print("Init I2C busses... ");
  I2C_1.begin(I2C1_SDA, I2C1_SCL);   
  I2C_2.begin(I2C2_SDA, I2C2_SCL);   
  Serial.println("done.");

//....................................................................................................  
  if(!LittleFS.begin(true)){                          // start file system
    Serial.println("An Error has occurred while mounting LittleFS");
  }  
  read_nb_records();                                // read #records currently stored in flash
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
  Serial.printf("RTC time 01: %s\n", timeStamp);
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
/* sensor measurements*/
  if (!sht30_measurement(&shtAirTemp, &shtAirHumi, &I2C_1)) {
    Serial.println("Could not make a valid SHT30 measurement on I2C1, check wiring!");
  }
  Serial.printf("SHT30 measurement on I2C1: %f; %f\n", shtAirTemp, shtAirHumi);

  if (!sht30_measurement(&shtSoilTemp, &shtSoilHumi, &I2C_2)) {
    Serial.println("Could not make a valid SHT30 measurement on I2C2, check wiring!");
  }
  Serial.printf("SHT30 measurement on I2C2: %f; %f\n", shtSoilTemp, shtSoilHumi);

  if (!bme_measurement(&bmeTemp, &bmeHumi, &bmePres, &I2C_1)){
    Serial.println("Could not make a valid BME280 measurement, check wiring!");  
  }
  Serial.printf("BME280 measurement: %f; %f; %f\n", bmeTemp, bmeHumi, bmePres);
  
//....................................................................................................  
/* Prepare data to be publish */
  if (JSON_PY_API){                      // if we do json/py, we start populating a JSON doc
    snprintf(SHA256PayLoad, sizeof(SHA256PayLoad), "%s; %s; %s", SITE_ID, loggerID, timeStamp);
    hashing(SHA256PayLoad, hashedKey);
    // Serial.printf("%s | %s\n", SHA256PayLoad, hashedKey);
    // now populate JSON doc
    JSONData["sign"] = hashedKey;
    JSONData["timestamp"] = timeStamp;
    JSONData["ta"] = shtAirTemp;
    JSONData["rh"] = shtAirHumi;
    JSONData["p"] = bmePres;
    JSONData["ts10cm"] = shtSoilTemp;
    JSONData["logger_ta"] = bmeTemp;
    JSONData["logger_rh"] = bmeHumi;
    JSONData["U_Battery"] = batV;
    JSONData["U_Solar"] = solarV;
    JSONData["loggerID"] = loggerID;
    JSONData["git_version"] = GIT_VERSION;
  } else {                               // if we do php, we use a traditional String. 
    len = sprintf(httpRequestData, "timestamp=%s", timeStamp);
    len += sprintf(httpRequestData + len, "&ta=%f", shtAirTemp);
    len += sprintf(httpRequestData + len, "&rh=%f", shtAirHumi);
    len += sprintf(httpRequestData + len, "&p=%f", bmePres);
    len += sprintf(httpRequestData + len, "&logger_ta=%f", bmeTemp);
    len += sprintf(httpRequestData + len, "&logger_rh=%f", bmeHumi);
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
      modem_reset();                                // do a hard reset before going to sleep             
    }
  }  
  
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
  while (!modem.setPreferredMode(1)){               // 1 CAT-M; 2 NB-Iot; 3 CAT-M and NB-IoT
    delay(100);
  }

  // connect to network
  Serial.print("Waiting for network... ");
  modem.waitForNetwork();                           // this tries to connect for 60s
  if (!modem.isNetworkConnected()){                 // if this did not succeed...
    //Serial.println("in vain. Setting pdp-context and trying to connect again.");
    Serial.println("in vain.");
    // esp_task_wdt_reset();                           // reset watchdog
    // set_pdp(APN);                                      // try to set pdp-context explicitly...    
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
  
  clients.setInsecure();                                   // accept unverified ssl encryption
     
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
 * name :         bme_measurement
 * description :  do two measure, check plausibility
 * input :        void
 * output :       void
 * ------------------------------------------------------------------------------------------------------------------------------*/
bool bme_measurement(float* temperature, float* humidity, float* pressure, TwoWire* myI2C){
  Adafruit_BME280 bme;                                              // sensor type BME280 variable
  float measureTemp1, measureTemp2, measureHum1, measureHum2;
  float measurePress1, measurePress2;
  int i = 0;                                                        // init counter i
  int nbMaxTries = 5;                                               // number of try to have good measure
  bool plausibility = false;                                        // init plausibilty to false
  
  while (i < nbMaxTries && !plausibility){
    if (bme.begin(0x76, myI2C)){                                    // read bme280 sensor
      measureTemp1 = bme.readTemperature();                         // first set of values
      measureHum1 = bme.readHumidity();
      measurePress1 = bme.readPressure() / 100.0;
      measureTemp2 = bme.readTemperature();                         // 2nd set of values
      measureHum2 = bme.readHumidity();
      measurePress2 = bme.readPressure() / 100.0;
          
      if (fabs(measureTemp1-measureTemp2) < 1.0 && measureTemp1 < 99.0 && 
            measureTemp1 > -80.0){             // check plausibility
          *temperature = (measureTemp1 + measureTemp2) / 2.0;
          *humidity = (measureHum1 + measureHum2) / 2.0;
          *pressure = (measurePress1 + measurePress2) / 2.0;
          plausibility = true;
      } else {
          *temperature = -999.0;
          *humidity = -999.0;
          *pressure = -999.0;
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
bool sht30_measurement(float* temperature, float* humidity, TwoWire* myI2C){  
  SHTSensor sht30(SHTSensor::SHT3X);                                           // sensor type SHT3X variable
  float measureTemp1, measureTemp2, measureHum1, measureHum2;
  int i = 0;                                                                   // init counter i
  int nb_try = 5;                                                              // number of try to have good measure
  bool plausibility = false;                                                   // init plausibilty to false
  
  while (i <= nb_try && plausibility != true){                                  // try to have plausible value max nb_try
    if (sht30.init(*myI2C)){                                                         
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
  } 
  return plausibility;
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

/* --------------------------------------------------------------------------------------------------------------------------------
 * name : read_nb_records
 * description : check the number of records stored in the flash
 * input : void
 * output : void
 * ------------------------------------------------------------------------------------------------------------------------------*/
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
  
  File myfile = LittleFS.open("/mydata.txt");
  if(!myfile){
    Serial.println("Failed to open file for reading - cannot transmit stored records.");    
    return;
  }
  
  while(myfile.available()){                            // read all lines 
    esp_task_wdt_reset();                               // reset watchdog
    size_t len = myfile.readBytesUntil('\n', httpRequestData, sizeof(httpRequestData) - 1);
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
 * name : set_rtc_to_network_date
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
  } else if (strcmp(imsi, "43612") == 0 || strcmp(imsi, "43601") == 0){    // tcell
      return "tcell";
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

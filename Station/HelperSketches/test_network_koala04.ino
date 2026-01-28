/**
 * @file      Arduino_NetworkTest.ino
 * @author    Lewis He (lewishe@outlook.com)
 * @license   MIT
 * @copyright Copyright (c) 2023  Shenzhen Xin Yuan Electronic Technology Co., Ltd
 * @date      2023-02-01
 * @note      This example function is the SIM7000/SIM7070 network test to
 *            determine whether the module can access the network and obtain some access parameters
 */


const String CBAND="ALL_MODE"; // can be EGSM_MODE, DCS_MODE, ALL_MODE
const String APN="TM";           // your APN - babilon, internet...
const int NETWORK_MODE=2;    // 2 Automatic, 13 GSM only, 38 LTE only, 51 GSM and LTE only


// Set serial for debug console (to the Serial Monitor, default speed 115200)
#define SerialMon Serial

// Set serial for AT commands (to the module)
// Use Hardware Serial on Mega, Leonardo, Micro
#define SerialAT Serial1

#define TINY_GSM_MODEM_SIM7000
#define TINY_GSM_RX_BUFFER 1024 // Set RX buffer to 1Kb
#define SerialAT Serial1

// See all AT commands, if wanted
// #define DUMP_AT_COMMANDS

#include <TinyGsmClient.h>
#include <SPI.h>
#include <Ticker.h>

#ifdef DUMP_AT_COMMANDS
#include <StreamDebugger.h>
StreamDebugger debugger(SerialAT, SerialMon);
TinyGsm modem(debugger);
#else
TinyGsm modem(SerialAT);
#endif

#define UART_BAUD   9600                           // for the modem

// koala01 pins
//#define PIN_DTR     25                              // 25 with old one
//#define PIN_TX      26                              // 27 with old one
//#define PIN_RX      27                              // 26 with old one
//#define PWR_PIN     33                              // 4 with old one
//#define MODEM_RST   32                              // 5 with old one

// koala02-04 pins
#define PIN_DTR             25
#define PIN_TX              27
#define PIN_RX              26
#define PWR_PIN             33
#define MODEM_RST           32                              


// lilygo pins
//#define PIN_DTR     25
//#define PIN_TX      27
//#define PIN_RX      26
//#define PWR_PIN     4
//#define MODEM_RST   5

#define LED_PIN     12                             // for the LED

void modem_on(){
  // power on modem....................................................................................................
  // based on https://www.manualslib.com/manual/1498555/Simcom-Sim7000g.html?page=25#manual
  // note that the koala board has logical inverters between the pins - this means that HIGH=LOW ;-)Serial.println("Powering on modem... (6s)");     // power on modem and give it some time to wake up (https://github.com/vshymanskyy/TinyGSM/issues/381)
  Serial.println("Powering on modem... (6s)");
  pinMode(PWR_PIN, OUTPUT);
  digitalWrite(PWR_PIN, HIGH); // koala
//  digitalWrite(PWR_PIN, LOW);  // lilygo
  delay(100); // Ton 73 ms
  digitalWrite(PWR_PIN, LOW);  // koala
  //digitalWrite(PWR_PIN, HIGH);  // lilygo
  delay(6000);
}

void modem_off() {
  if (modem.poweroff()) {                                  // turn off modem (software)
    Serial.println("... OK");
  } else {                                                 // if this fails: hardware
    Serial.println("\nHardware modem power down... (3s)");  
    // note that the koala board has logical inverters between the pins - this means that HIGH=LOW ;-)
    pinMode(PWR_PIN, OUTPUT);
    digitalWrite(PWR_PIN, HIGH);
    delay(1300);    //Datasheet Toff = 1.2s
    digitalWrite(PWR_PIN, LOW);
    delay(1700);
  }
  
  pinMode(PWR_PIN, OUTPUT);                                 
  digitalWrite(PWR_PIN, LOW);                              // BORIS: unclear here... does not work on the new board; pull pwr_pin low, to prevent esp from restarting the modem
}

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

void setup()
{
    // Set console baud rate
    SerialMon.begin(115200);
    delay(1000);
    
    // Set LED OFF
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, HIGH);

    // modem_reset();

    modem_on();

    SerialAT.begin(UART_BAUD, SERIAL_8N1, PIN_RX, PIN_TX);
    delay(1000);
    
    Serial.println("> Check whether Modem is online");
    //test modem is online ?
    uint32_t  timeout = millis();
    while (!modem.testAT()) {
        Serial.print(".");
        if (millis() - timeout > 60000 ) {
            Serial.println("> It looks like the modem is not responding, trying to restart");
            modem_reset();
            // modem_off();
            delay(5000);
            // modem_on();
            timeout = millis();
        }
    }
    Serial.println("\nModem is online");

    if (modem.init()){
      Serial.println("Init ok.");
    } else {
      Serial.println("init failed.");
    }

    //test sim card is online ?
    timeout = millis();
    Serial.print("> Get SIM card status");
    while (modem.getSimStatus() != SIM_READY) {
        Serial.print(".");
        if (millis() - timeout > 60000 ) {
            Serial.println("It seems that your SIM card has not been detected. Has it been inserted?");
            Serial.println("If you have inserted the SIM card, please remove the power supply again and try again!");
            return;
        }

    }
    Serial.println();
    Serial.println("> SIM card exists");


    //modem.restart();
    
    Serial.println("> /**********************************************************/");
    Serial.println("> Please make sure that the location has 2G/NB-IOT signal");
    Serial.println("> SIM7000/SIM707G does not support 4G network. Please ensure that the USIM card you use supports 2G/NB access");
    Serial.println("> /**********************************************************/");

    String res = modem.getIMEI();
    Serial.print("IMEI:");
    Serial.println(res);
    Serial.println();

    /* Check Modem internal time*/
    modem.sendAT("+CCLK?");
    //modem.waitResponse();
    if (modem.waitResponse("+CCLK: ") == 1) {  
      modem.stream.read();
      res = modem.stream.readStringUntil('\n');
      res.replace("\"", "");
      res.replace("\r", "");
      res.replace("\n", "");
      modem.waitResponse();
      Serial.print("The current modem date is: ");
      Serial.println(res);
    } 

    /*
    * Tips:
    * When you are not sure which method of network access is supported by the network you use,
    * please use the automatic mode. If you are sure, please change the parameters to speed up the network access
    * * * * */

    // get available modes
    //Serial.println(modem.getNetworkModes());
    
    modem.sendAT("+CGDCONT=1,\"IP\",\"" + APN + "\",\"0.0.0.0\",0,0,0,0");
    modem.waitResponse();
    
    modem.sendAT("+CGDCONT?");
    if (modem.waitResponse("+CGDCONT: ") == 1) {
        modem.stream.read();
        modem.stream.read();
        res = modem.stream.readStringUntil('\n');
        res.replace("\"", "");
        res.replace("\r", "");
        res.replace("\n", "");
        modem.waitResponse();
        Serial.print("The current PDP context is:");
        Serial.println(res);
    }
    // Args:
    // 1 CAT-M
    // 2 NB-IoT
    // 3 CAT-M and NB-IoT
    // Set network preferre to auto
    uint8_t perferred = 1;
    modem.setPreferredMode(perferred);

 

    // Args:
    // 2 Automatic
    // 13 GSM only
    // 38 LTE only
    // 51 GSM and LTE only
    // Set network mode to auto
    modem.setNetworkMode(NETWORK_MODE);

    //Set mobile operation band
    modem.sendAT("+CBAND=" + CBAND);
    modem.waitResponse();

    modem.sendAT("+CBAND?");
    if (modem.waitResponse("+CBAND: ") == 1) {
        modem.stream.read();
        modem.stream.read();
        res = modem.stream.readStringUntil('\n');
        res.replace("\"", "");
        res.replace("\r", "");
        res.replace("\n", "");
        modem.waitResponse();
        Serial.print("The currently selected band is:");
        Serial.println(res);
    }

  // set lte bands explicitly
  // "CAT-M",1,2,3,4,5,8,12,13,18,19,20,26,28,39

    modem.sendAT("+CBANDCFG=\"CAT-M\",1,2,3,4,5,8,12,13,18,19,20,26,28,39");
    //modem.sendAT("+CBANDCFG=\"CAT-M\",28");
    if (modem.waitResponse(10000L) != 1) {
        Serial.println(" +CBANDCFG=\"CAT-M\" ");
    }
    
    modem.sendAT("+CBANDCFG?");
    if (modem.waitResponse("+CBANDCFG: ") == 1) {
        res = modem.stream.readStringUntil('\n');
        res.replace("\r", "");
        res.replace("\n", "");
        modem.waitResponse();
        Serial.print("About the available bands:");
        Serial.println(res);
    }

    
    // Check network signal and registration information
    Serial.println("Checking network signal and registration for network mode " + 
      String(NETWORK_MODE) + " and for band " + CBAND);
    SIM70xxRegStatus status;
    timeout = millis();
    do {
        int16_t sq =  modem.getSignalQuality();

        status = modem.getRegistrationStatus();

        if (status == REG_DENIED) {
            Serial.println("> The SIM card you use has been rejected by the network operator. Please check that the card you use is not bound to a device!");
            return;
        } else {
            Serial.print("Signal:");
            Serial.println(sq);
        }

        if (millis() - timeout >= 360000-1 ) {
            if (sq == 99) {
                Serial.println("> It seems that there is no signal. Please check whether the"\
                               "LTE antenna is connected. Please make sure that the location has 2G/NB-IOT signal\n"\
                               "SIM7000G does not support 4G network. Please ensure that the USIM card you use supports 2G/NB access");
                return;
            }
            //timeout = millis();
        }

        delay(800);
    } while (millis() - timeout <= 360000 && (status != REG_OK_HOME && status != REG_OK_ROAMING));

    Serial.println("Obtain the APN issued by the network");
    modem.sendAT("+CGNAPN");
    if (modem.waitResponse(3000, res) == 1) {    
        res = res.substring(res.indexOf(",") + 1);
        res.replace("\"", "");
        res.replace("\r", "");
        res.replace("\n", "");
        res.replace("OK", "");
        Serial.print("The APN issued by the network is:");
        Serial.println(res);
    }

    modem.sendAT("+CNACT=1");
    modem.waitResponse();

    modem.sendAT("+CNCFG?");
    if (modem.waitResponse("+CNCFG: ") == 1) {
        modem.stream.read();
        modem.stream.read();
        res = modem.stream.readStringUntil('\n');
        res.replace("\"", "");
        res.replace("\r", "");
        res.replace("\n", "");
        modem.waitResponse();
        Serial.print("The current PDP context is:");
        Serial.println(res);
    }
   
      // res = modem.getLocalIP();
    modem.sendAT("+CNACT?");
    if (modem.waitResponse("+CNACT: ") == 1) {
        modem.stream.read();
        modem.stream.read();
        res = modem.stream.readStringUntil('\n');
        res.replace("\"", "");
        res.replace("\r", "");
        res.replace("\n", "");
        modem.waitResponse();
        Serial.print("The current network IP address is:");
        Serial.println(res);
    }


    modem.sendAT("+CPSI?");
    if (modem.waitResponse("+CPSI: ") == 1) {
        res = modem.stream.readStringUntil('\n');
        res.replace("\r", "");
        res.replace("\n", "");
        modem.waitResponse();
        Serial.print("The current network parameter is:");
        Serial.println(res);
    }

    modem.sendAT("+CBANDCFG?");
    if (modem.waitResponse("+CBANDCFG: ") == 1) {
        res = modem.stream.readStringUntil('\n');
        res.replace("\r", "");
        res.replace("\n", "");
        modem.waitResponse();
        Serial.print("About the available bands:");
        Serial.println(res);
    }

    if (modem.init()){
      Serial.println("Init ok.");
    } else {
      Serial.println("init failed.");
    }

    // connect to network      
    Serial.print("Waiting for network... ");
    modem.waitForNetwork(); 
    if (modem.isNetworkConnected()){
      Serial.println("Network connected.");
    } else {
      Serial.println("Network connect failed.");
    }
    
    Serial.println("/**********************************************************/");
    Serial.println("After the network test is complete, please enter the  ");
    Serial.println("AT command in the serial terminal.");
    Serial.println("/**********************************************************/\n\n");

    Serial.print("Powering modem down...");
    if (modem.poweroff()) {                                  // turn off modem (software)
      Serial.println("... OK");
    }
}

void loop()
{
    while (SerialAT.available()) {
        SerialMon.write(SerialAT.read());
    }
    while (SerialMon.available()) {
        SerialAT.write(SerialMon.read());
    }
}

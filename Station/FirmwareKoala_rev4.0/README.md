# Sensors
The firmware allows the logger to be connected to the following sensors:
- SHT3x/SHT4x on I2C 1 and 2. First I2C will deliver air temperature, 2nd I2C soil temperature (10cm depth). Both I2Cs are always read, returning -999.99 if no sensor connected
- ClimaVue50/Atmos41: This will override any readings from the first I2C
- A tipping bucket sensor, with adjustable mm per tip
- SDS011 air quality sensor for PM2.5 and PM10

Additionally the logger features on board sensors:
- Bosch BMP390 temperature/pressure sensor. This provides in-box logger temperature and air pressure if no external air pressure sensor is connected (e.g. from the climavue50)
- LTC2942 chips to measure battery voltage, charge and temperature. 

# Firmware configuration
```
/* CONSTANTS AND CONFIGURATION - TO BE SET / OVERWRITTEN BY FLASHGORDON*/
const char SERVER[] = "FlashServer";          // domain name: example.com, maker.ifttt.com, etc
const char DEFAULT_APN[] = "FlashProvider";   // APN - often 'internet'
const char SITE_ID[] = "FlashSite";           // site ID - this must match with the entries in the database
const char GIT_VERSION[] = "FlashGIT";        // git version - if provided this helps trouble shooting. FlashGordon will insert this automatically
const int NETWORK_MODE = 1234;                // 2 Automatic; 13 GSM only; 38 LTE only; 51 GSM and LTE. In most places this will be 13 
const int8_t tzQuarterHours = 0;              // timezone wrt UTC; this is quarter hours, positive for ea
st. (eg 4 = UTC+1)

const char GSM_PIN[] = "";                    // dummy GSM PIN
const int SENSOR_READ_EVERY_MINS = 10;        // time between measurements in min
const int TRANSMIT_EVERY_MINS = 10;           // time between transmissions in min

const char GPRS_USER[] = "";                  // GPRS credential - often empty
const char GPRS_PASS[] = "";                  // GPRS credential - often empty
const char RESOURCE[] = "/post/insert";       // don't change unless you have customized your APIs
const int  PORT = 443;                        // usually 443
const int MAX_LOOPS = 500;                    // this is a cleaning up reboot every 500 boot ups
const int MAX_RECORDS = 300;                  // number of records to be stored in flash during network downtimes. don't touch unless you have an ESP with big flash
const bool CLIMAVUE50 = false;                // whether the climavue50 is connected to this station
const bool TippingBucket = false;             // whether a tipping bucket isis connected to this station - it can be only one of climavue50 and tipping bucket
const float mmPerTip = 0.2;                   // mm per tip of the tipping bucket
const bool AIRQUALITY_SDS011 = false;         // whether we measure air quality - cannot go together with climavue50
```

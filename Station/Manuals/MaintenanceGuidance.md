# Continous monitoring
Continuously monitor the data coming in (or not coming in) from the stations. In particular
- decline of battery voltage over time points to dying batteries in need of replacement
- -999 numbers for weather parameters point to dysfunct or wrongly wired sensors
- the signal or signalStrength parameter provides information about the network quality. Under normal conditions it ranges between say 18 and 31.
  The station reports error codes on this parameter, should anything go wrong during connection and transmission.
  - -333 modem init failed
  - -444 modem soft reset failed
  - -555 modem hard reset failed
  - -666 network connect failed
  - -777 APN connect failed
    
# Routine maintenance
Every 3 months: Clean solar panel, radiation shield and sensors. Check cabling for signs of damage and possible moisture intrusion.
- Solar panel: If needed use a moist cloth
- Radiation shield (Campbell Scientific RAD06 or similar): To clean the shield, first remove the sensor. Dismount the shield.
  Brush all loose dirt off. If more effort is needed, use warm, soapy water and a soft cloth or brush to thoroughly clean the shield.
  Allow the shield to dry before remounting.
- Sensors: For airprobes such as SHT30, use a brush or dry clothes, no water or detergents!
- ClimaeVUE50 / Atmos41: follow the [supplier's instructions]([https://metergroup.com/expertise-library/video-atmos-41-cleaning-instructions/)

# Replacement
- Battery: a replacement every 3 years is recommended
- SHT30: a replacement every 2 years is recommended
- ClimaVUE50: The supplier [recommends](https://metergroup.com/expertise-library/remote-weather-stations-weather-instruments-best-practices-for-higher-quality-data/)
  replacement of selected sensors (not the entire unit) every 2 years: `We recommend replacing the ATMOS 41 solar radiation sensor every two years. 
  And we have the same recommendation for the barometric pressure and relative humidity daughterboard. 
  We feel strongly about keeping the sensors accurate, so those components are field swappable, and we’ve tried to make that easy for the user.`

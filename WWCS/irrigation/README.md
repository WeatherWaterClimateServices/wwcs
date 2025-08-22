# Parameterization of the irrigation computations
The irrigation recommendations are computed based on FAO56. 
This approach expects the following input parameters for each site, 
which are specified as a long JSON in the fieldproperties column of the SitesHumans.Sites table.

| Paramter           | Meaning                                            | Value/Format             |
|--------------------|----------------------------------------------------|--------------------------|
| StartDate          | Planting date of the crop to be irrigated        | "YYYY-MM-DD"             |
| Station | SiteID of the weather station from where the data comes | String |
| FC | Field capacity | % (that is a number 0..100) |
| WP | Wilting point | % (that is a number 0..100) |
| MAD | Management Allowed Deficit | fraction (that is a decimal number 0..1) |
| PHIc | initial soil moisture content at StartDate | % (that is a number 0..100) |
| IE | Irrigation efficiency | fraction (that is a decimal number 0..1) |
| WA | Wetted area | fraction (that is a decimal number 0..1) |
| Crop | The crop; must be available from WWCS/irrigation/appdata/CropParameters.csv | String |
| area | Area of the irrigated plot | hectar |
| type | Type of the plot - treatment or control (with/without recommendation) | "treatment" or "control" |
| measurement_device | How is irrigation water measured | "total_meter" "incremental_meter" "thomson_profile"*
| humanId | numeric ID of the operator of the plot, must correspond to the entry in SitesHumans.Humans | integer |

| *measurement_device | Explanation |
|--------------------|-------------|
| total_meter | A device which measures the total amount of water per irrigation |
| incremental_meter | A water meter which simply counts cubic meters of flow. You will read such a device before and after the irrigation |
| thomson_profile | a specific V-shaped profile with a defined waterlevel-discharge relation. See the source code in the telegramBot |

An example JSON in the Sites-table would be:
{"StartDate": "2025-06-21", "Station": "CAL003", "FC": 39, "WP": 18, "MAD": 0.3, "PHIc": 39, "IE": 0.95, "WA": 0.4, 
"Crop": "TomatoCambodia", "area": 0.075, "type": "treatment", "measurement_device": "thomson_profile", "humanID": 10001}

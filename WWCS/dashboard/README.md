# WWCS Tajikistan

Weather, Water and Climate Services (WWCS) Project in Tajikistan funded by CARITAS and SDC, with implementation from MeteoSwiss at Tajik Hydromet. 

## Demonstration Dashboard

This repository includes a set of routines to automatically retrieve and post-process observation data from the WWCS database and ECMWF forecasts (using access token from MeteoSwiss). The data is then post-processed using a Ensemble Model Output Statistics (EMOS) approach using linear prediction of the observations using different model fields (see Rayjczak et al. 2022, to be submitted). The corrected forecast data is finally presented in an R-Shiny dashboard. 

The following installations need to made to run the dashboard: 

- Install Python3 / CDO / R
- Install required R and Python libraries
- Setup the ECMWF Python API with access token
- Install R-Shiny Server at /srv/shiny-server
- Install CRON-Tabs to automatically prepare the data

## Libraries to install

### Install Python3 / CDO / R

```
sudo apt-get install python3
sudo apt-get install R
sudo apt-get install CDO
```

### Install required libraries

```
sudo su - -c "R -e \"install.packages('tidyverse')\""
sudo su - -c "R -e \"install.packages('zoo')\""
pip install ecmwf-api-client
```

### Setup the ECMWF Python API 

Follow instructions at [ECMWF](https://www.ecmwf.int/en/computing/software/ecmwf-web-api).

### Install R-Shiny Server

Follow instructions at [Dean Attali](https://deanattali.com/2015/05/09/setup-rstudio-shiny-server-digital-ocean/).

### Install R-Shiny Server

Example currently used: Retrieve observations every hour (10 minutes past) and retrieve ECMWF 10AM every day.

```
00 10 * * * /srv/shiny-server/wwcs-dashboard/CRON/cronjob_emos.sh
10 * * * * /srv/shiny-server/wwcs-dashboard/CRON/cronjob_wwcs_data.sh
```








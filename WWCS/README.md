# WWCS-MeteoSwiss
Weather Water and Climate Services (WWCS) for the Tajikistan Project of MeteoSwiss

# Installation of WWCS applications

This repository includes a set of routines to automatically retrieve and post-process observation data from the WWCS database and ECMWF forecasts. The data is then post-processed using a Ensemble Model Output Statistics (EMOS) approach using linear prediction of the observations using different model fields (see Rayjczak et al. 2022, to be submitted). The post-processing is also done at locations where there is no station using the global EMOS approach (gEMOS) including geospatial indicators such as topographic position index (TPI).

Using the post-processed forecast a number of service applications are available: 1) A forecasting dashboard that shows the post-processed forecasts and weather icons on these locations, 2) A platform for early warning of heat and cold waves, 3) A irrigation scheduler for crops and 4) A platform to inform planting and harvesting of potatoes and wheat. All applications can be accessed through the main page `wwcs.tj/home'.


## Installation base packages for R
We want to install the r-base packages and a few additional libraries and finally [R-Studio Server](https://posit.co/products/open-source/rstudio-server/):
 1. In order to get RStudio, you need to add another repository to the system:
    * Install two helper packages: `sudo apt install --no-install-recommends software-properties-common dirmngr`
    * Get the repository key that is used to sign the packages and add it to the system: `wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/cran_ubuntu.gpg`
    * Add the repository to the list of known repositories `sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/cran_ubuntu.gpg] http://cran.rstudio.com/bin/linux/ubuntu jammy-cran40/" > /etc/apt/sources.list.d/cran_ubuntu.list'`
    * Get the list of packages provided by this new repository `sudo apt update`
 2. Now add the necessary base packages for R:
    * R-base package `apt -y install r-base`
    * Other system dependencies `apt -y install libcurl4-gnutls-dev libxml2-dev libssl-dev libudunits2-dev`
    * The [gdal](https://en.wikipedia.org/wiki/GDAL) libraries `apt -y install gdal-bin libgdal-dev`
 3. Finally, install R-Studio Server
    * Get the package `wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2022.12.0-353-amd64.deb`
    * Manually install the package `sudo dpkg -i rstudio-server-2022.12.0-353-amd64.deb`


## Installation R-Shiny Server

In order to run R-Shiny server, it is necessary to get it, install it and configure it properly:
 1. Get and install the package
    * Get the R-Shiny server package: `wget https://download3.rstudio.org/ubuntu-18.04/x86_64/shiny-server-1.5.20.1002-amd64.deb`
    * Install the package: `sudo dpkg -i shiny-server-1.5.20.1002-amd64.deb`
 2. Prepare a new group for R-Shiny apps
    * Create a new group for *R-Shiny* apps: `sudo groupadd shiny-apps`
    * Add the existing user *shiny* to this new group: `sudo usermod -aG shiny-apps shiny`
    * Add the user that will run *R-Shiny* to this new group: `sudo usermod -aG shiny-apps ${USER}`
 3. Create a directory for R-Shiny apps and set the proper permissions
    * Create the directory `sudo mkdir -f /srv/shiny-server`
    * Set ownership of the directory: `sudo chown -R ${USER}:shiny-apps /srv/shiny-server`
    * Set permissions: `sudo chmod o-w /srv/shiny-server; sudo chmod g+w /srv/shiny-server`

## Configure WWCS Applications 

* Inside the configuration file 'config.yaml' different parameters for the WWCS application are defined. It is important to define these first before running the installation script since topographic information will be dowloaded according this information. 

* Define in the installer script 'setup_wwcs.sh' the services you want to deploy and under which user the crontabs shall be executed. The retrieval of ECMWF data can not be done by the root. 

* The installer currently requires a folder containing the MeteoSwiss weather icons. These can not be shared through the git repository and have to be copied manually to the installation folder. A future version should use an open-source solution for this. 

## Deploy WWCS Applications 

The installation requires running an insaller script as root. 

```
sudo chmod a+x setup_wwcs.sh
sudo ./setup_wwcs.sh

```

The scripts performs the following tasks: 

- Deployment of applications for shiny-server
- Install required R and Python libraries
- Setup the ECMWF Python API with access token
- Install CRON-Tabs to automatically prepare the data

Installing all the packages will take considerable time and requires a minimum of 8 GB of RAM to process the topographic indices. After the installation, the script "cronjob_emos.sh" will download the forecast information. By default this will retrive the forecast information of the last 30 days which may take multiple days to retrieve to the ECMWF queuing system. You have to check if all cronjobs run through without an error to ensure that the individual service can run. 

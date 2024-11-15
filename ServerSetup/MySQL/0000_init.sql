/*!999999 enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.6.18-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: 
-- ------------------------------------------------------
-- Server version	10.6.18-MariaDB-0ubuntu0.22.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `BeneficiarySupport`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `BeneficiarySupport` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `BeneficiarySupport`;

--
-- Table structure for table `DistributionGoods`
--

DROP TABLE IF EXISTS `DistributionGoods`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `DistributionGoods` (
  `humanID` int(5) NOT NULL,
  `timestamp` datetime NOT NULL,
  `district` varchar(50) DEFAULT NULL,
  `jamoat` varchar(50) DEFAULT NULL,
  `village` varchar(50) DEFAULT NULL,
  `distributedBy` varchar(300) DEFAULT NULL,
  `wittnesses` varchar(300) DEFAULT NULL,
  `received` date NOT NULL,
  `goods` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`goods`)),
  PRIMARY KEY (`humanID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table of distributed goods to the beneficiaries';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `MeetingsTrainings`
--

DROP TABLE IF EXISTS `MeetingsTrainings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `MeetingsTrainings` (
  `humanID` int(5) NOT NULL,
  `timestamp` datetime NOT NULL,
  `district` varchar(50) DEFAULT NULL,
  `jamoat` varchar(50) DEFAULT NULL,
  `village` varchar(50) DEFAULT NULL,
  `trainers` varchar(200) DEFAULT NULL,
  `topic` varchar(300) DEFAULT NULL,
  `date` date NOT NULL,
  `type` varchar(50) NOT NULL,
  `expenses` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`expenses`)),
  PRIMARY KEY (`humanID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table of registration of meetings and trainings with the beneficiary of the project';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `Humans`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `Humans` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `Humans`;

--
-- Table structure for table `HumanActions`
--

DROP TABLE IF EXISTS `HumanActions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `HumanActions` (
  `humanID` int(5) NOT NULL,
  `timestamp` datetime NOT NULL,
  `received` datetime NOT NULL DEFAULT '1970-01-01 00:00:00',
  `stationlog` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`stationlog`)),
  `irrigation` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`irrigation`)),
  PRIMARY KEY (`humanID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for human actions data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `HumanActionsRejected`
--

DROP TABLE IF EXISTS `HumanActionsRejected`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `HumanActionsRejected` (
  `ID` bigint(20) unsigned NOT NULL,
  `phone` int(10) NOT NULL,
  `received` datetime NOT NULL,
  `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`data`)),
  `domain` varchar(50) NOT NULL,
  `comment` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='RejectedActions JSON data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `HumanActionsSubmitted`
--

DROP TABLE IF EXISTS `HumanActionsSubmitted`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `HumanActionsSubmitted` (
  `ID` bigint(20) unsigned NOT NULL,
  `phone` int(10) NOT NULL,
  `received` datetime NOT NULL DEFAULT current_timestamp(),
  `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`data`)),
  `domain` varchar(50) NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='SubmittedActions JSON data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `HumanAtSite`
--

DROP TABLE IF EXISTS `HumanAtSite`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `HumanAtSite` (
  `siteID` varchar(50) NOT NULL,
  `humanID` int(5) NOT NULL,
  `startDate` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `endDate` datetime NOT NULL DEFAULT '2100-01-01 00:00:00',
  PRIMARY KEY (`siteID`,`humanID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Humans acting at the site for the specific period';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `HumanObs`
--

DROP TABLE IF EXISTS `HumanObs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `HumanObs` (
  `humanID` int(5) NOT NULL,
  `timestamp` datetime NOT NULL,
  `received` datetime NOT NULL DEFAULT '1970-01-01 00:00:00',
  `precipitation` int(3) DEFAULT NULL,
  `soiltemp1` double(3,2) DEFAULT NULL,
  `soiltemp2` double(3,2) DEFAULT NULL,
  `soiltemp3` double(3,2) DEFAULT NULL,
  `soilhumidity` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`soilhumidity`)),
  `hillinfiltration` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`hillinfiltration`)),
  `snowheight` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`humanID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for human observation data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `HumanObsRejected`
--

DROP TABLE IF EXISTS `HumanObsRejected`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `HumanObsRejected` (
  `ID` bigint(20) unsigned NOT NULL,
  `phone` int(10) NOT NULL,
  `received` datetime NOT NULL,
  `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`data`)),
  `domain` varchar(50) NOT NULL,
  `comment` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='RejectedObs JSON data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `HumanObsSubmitted`
--

DROP TABLE IF EXISTS `HumanObsSubmitted`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `HumanObsSubmitted` (
  `ID` bigint(20) unsigned NOT NULL,
  `phone` int(10) NOT NULL,
  `received` datetime NOT NULL DEFAULT current_timestamp(),
  `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`data`)),
  `domain` varchar(50) NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='SubmittedObs JSON data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `Machines`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `Machines` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `Machines`;

--
-- Table structure for table `MachineAtSite`
--

DROP TABLE IF EXISTS `MachineAtSite`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `MachineAtSite` (
  `siteID` varchar(50) NOT NULL,
  `loggerID` varchar(50) NOT NULL,
  `startDate` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `endDate` datetime NOT NULL DEFAULT '2100-01-01 00:00:00',
  PRIMARY KEY (`siteID`,`loggerID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Machines acting at the site for the specific period';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `MachineObs`
--

DROP TABLE IF EXISTS `MachineObs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `MachineObs` (
  `loggerID` varchar(50) NOT NULL,
  `timestamp` datetime NOT NULL,
  `received` datetime NOT NULL DEFAULT '1970-01-01 00:00:00',
  `ta` float DEFAULT NULL,
  `rh` float DEFAULT NULL,
  `logger_ta` float DEFAULT NULL,
  `logger_rh` float DEFAULT NULL,
  `p` float DEFAULT NULL,
  `U_Battery` float DEFAULT NULL,
  `U_Solar` float DEFAULT NULL,
  `signalStrength` float DEFAULT NULL,
  `Charge_Battery1` float DEFAULT NULL,
  `Charge_Battery2` float DEFAULT NULL,
  `Temp_Battery1` float DEFAULT NULL,
  `Temp_Battery2` float DEFAULT NULL,
  `Temp_HumiSens` float DEFAULT NULL,
  `U_Battery1` float DEFAULT NULL,
  `U_Battery2` float DEFAULT NULL,
  `compass` float DEFAULT NULL,
  `lightning_count` float DEFAULT NULL,
  `lightning_dist` float DEFAULT NULL,
  `pr` float DEFAULT NULL,
  `rad` float DEFAULT NULL,
  `tilt_x` float DEFAULT NULL,
  `tilt_y` float DEFAULT NULL,
  `ts10cm` float DEFAULT NULL,
  `vapour_press` float DEFAULT NULL,
  `wind_dir` float DEFAULT NULL,
  `wind_gust` float DEFAULT NULL,
  `wind_speed` float DEFAULT NULL,
  `wind_speed_E` float DEFAULT NULL,
  `wind_speed_N` float DEFAULT NULL,
  PRIMARY KEY (`loggerID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Data measured by the machines';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `MachineObsRejected`
--

DROP TABLE IF EXISTS `MachineObsRejected`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `MachineObsRejected` (
  `domain` varchar(50) NOT NULL,
  `received` datetime(6) DEFAULT NULL,
  `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`data`)),
  `comment` varchar(200) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='RejectedObs JSON data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `MachineObsSubmitted`
--

DROP TABLE IF EXISTS `MachineObsSubmitted`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `MachineObsSubmitted` (
  `domain` varchar(50) NOT NULL,
  `received` datetime NOT NULL DEFAULT current_timestamp(),
  `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`data`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='SubmittedObs JSON data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Metadata`
--

DROP TABLE IF EXISTS `Metadata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Metadata` (
  `loggerID` varchar(50) NOT NULL,
  `startDate` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `endDate` datetime NOT NULL DEFAULT '2100-01-01 00:00:00',
  `domain` varchar(50) DEFAULT NULL,
  `git_version` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`loggerID`,`startDate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Metadata about the loggers';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Temporary table structure for view `v_machineobs`
--

DROP TABLE IF EXISTS `v_machineobs`;
/*!50001 DROP VIEW IF EXISTS `v_machineobs`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE VIEW `v_machineobs` AS SELECT
 1 AS `siteID`,
  1 AS `loggerID`,
  1 AS `timestamp`,
  1 AS `received`,
  1 AS `ta`,
  1 AS `rh`,
  1 AS `logger_ta`,
  1 AS `logger_rh`,
  1 AS `p`,
  1 AS `U_Battery`,
  1 AS `U_Solar`,
  1 AS `signalStrength`,
  1 AS `Charge_Battery1`,
  1 AS `Charge_Battery2`,
  1 AS `Temp_Battery1`,
  1 AS `Temp_Battery2`,
  1 AS `Temp_HumiSens`,
  1 AS `U_Battery1`,
  1 AS `U_Battery2`,
  1 AS `compass`,
  1 AS `lightning_count`,
  1 AS `lightning_dist`,
  1 AS `pr`,
  1 AS `rad`,
  1 AS `tilt_x`,
  1 AS `tilt_y`,
  1 AS `ts10cm`,
  1 AS `vapour_press`,
  1 AS `wind_dir`,
  1 AS `wind_gust`,
  1 AS `wind_speed`,
  1 AS `wind_speed_E`,
  1 AS `wind_speed_N` */;
SET character_set_client = @saved_cs_client;

--
-- Current Database: `SitesHumans`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `SitesHumans` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `SitesHumans`;

--
-- Table structure for table `Humans`
--

DROP TABLE IF EXISTS `Humans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Humans` (
  `humanID` varchar(50) NOT NULL,
  `phone` int(10) DEFAULT NULL,
  `passportID` varchar(20) DEFAULT NULL,
  `firstName` varchar(100) DEFAULT NULL,
  `lastName` varchar(100) DEFAULT NULL,
  `gender` varchar(10) DEFAULT NULL,
  `age` int(3) DEFAULT NULL,
  `occupation` varchar(200) DEFAULT NULL,
  `district` varchar(50) DEFAULT NULL,
  `jamoat` varchar(50) DEFAULT NULL,
  `village` varchar(50) DEFAULT NULL,
  `startDate` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `endDate` datetime NOT NULL DEFAULT '2100-01-01 00:00:00',
  `project` varchar(50) NOT NULL,
  `telegramID` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`humanID`,`startDate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Registered data of all people collaborating with the projects';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Sites`
--

DROP TABLE IF EXISTS `Sites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Sites` (
  `siteID` varchar(50) NOT NULL,
  `siteName` varchar(100) DEFAULT NULL,
  `latitude` float NOT NULL,
  `longitude` float NOT NULL,
  `altitude` float NOT NULL,
  `slope` float DEFAULT NULL,
  `azimuth` float DEFAULT NULL,
  `district` varchar(50) DEFAULT NULL,
  `jamoat` varchar(50) DEFAULT NULL,
  `village` varchar(50) DEFAULT NULL,
  `irrigation` tinyint(1) DEFAULT 0,
  `avalanche` tinyint(1) DEFAULT 0,
  `coldwave` tinyint(1) DEFAULT 1,
  `fieldproperties` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT '{"StartDate": "2023-06-1", "FC": 38, "WP": 18, "Crop": "Potato", "area": 0, "type": "channel", "humanID": 10001}',
  `warnlevels` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT '{"Heat1": 25, "Heat2": 27, "Heat3": 29, "Cold1": 0, "Cold2": -5, "Cold3": -10, "Warn Altitude": 3000}' CHECK (json_valid(`warnlevels`)),
  `heatwave` tinyint(1) DEFAULT 1,
  `type` varchar(255) DEFAULT 'WWCS',
  `planting` tinyint(4) DEFAULT 0,
  `harvest` tinyint(4) DEFAULT 0,
  `forecast` tinyint(4) DEFAULT 1,
  PRIMARY KEY (`siteID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='The geographical information of a physical place where a station stands or a human acts';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `WWCServices`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `WWCServices` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `WWCServices`;

--
-- Table structure for table `Avalanche`
--

DROP TABLE IF EXISTS `Avalanche`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Avalanche` (
  `siteID` varchar(50) NOT NULL,
  `timestamp` datetime NOT NULL,
  PRIMARY KEY (`siteID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for registering avalanche warning';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Coldwave`
--

DROP TABLE IF EXISTS `Coldwave`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Coldwave` (
  `reftime` date NOT NULL,
  `date` date NOT NULL,
  `Type` varchar(50) NOT NULL,
  `Name` varchar(50) NOT NULL,
  `altitude` int(11) DEFAULT NULL,
  `Cold1` varchar(50) NOT NULL,
  `Cold2` varchar(50) NOT NULL,
  `Cold3` varchar(50) NOT NULL,
  `Threshold1` int(11) DEFAULT NULL,
  `Threshold2` int(11) DEFAULT NULL,
  `Threshold3` int(11) DEFAULT NULL,
  PRIMARY KEY (`reftime`,`date`,`Name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for registering coldwave warnings';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Forecasts`
--

DROP TABLE IF EXISTS `Forecasts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Forecasts` (
  `siteID` varchar(50) NOT NULL,
  `date` date NOT NULL,
  `Tmax` float DEFAULT NULL,
  `Tmin` float DEFAULT NULL,
  `Tmean` float DEFAULT NULL,
  `icon` varchar(10) DEFAULT NULL,
  `day` tinyint(4) NOT NULL,
  `timeofday` tinyint(4) NOT NULL,
  PRIMARY KEY (`siteID`,`date`,`day`,`timeofday`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for forecast data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Harvest`
--

DROP TABLE IF EXISTS `Harvest`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Harvest` (
  `siteID` varchar(50) NOT NULL,
  `date` date NOT NULL,
  `PastRain` float NOT NULL,
  `FutureRain` float NOT NULL,
  `HarvestPotato` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`siteID`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for harvest date';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Heatwave`
--

DROP TABLE IF EXISTS `Heatwave`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Heatwave` (
  `reftime` date NOT NULL,
  `date` date NOT NULL,
  `Type` varchar(50) NOT NULL,
  `Name` varchar(50) NOT NULL,
  `altitude` int(11) DEFAULT NULL,
  `Heat1` varchar(50) NOT NULL,
  `Heat2` varchar(50) NOT NULL,
  `Heat3` varchar(50) NOT NULL,
  `Threshold1` int(11) DEFAULT NULL,
  `Threshold2` int(11) DEFAULT NULL,
  `Threshold3` int(11) DEFAULT NULL,
  PRIMARY KEY (`reftime`,`date`,`Name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for registering heatwave warnings';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Irrigation`
--

DROP TABLE IF EXISTS `Irrigation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Irrigation` (
  `siteID` varchar(50) NOT NULL,
  `date` date NOT NULL,
  `irrigationNeed` double(10,2) DEFAULT NULL,
  `irrigationApp` int(11) DEFAULT 0,
  `WP` int(5) DEFAULT NULL,
  `FC` int(5) DEFAULT NULL,
  `SWD` double(5,2) DEFAULT NULL,
  `ETca` double(5,2) DEFAULT NULL,
  `Ks` double(5,2) DEFAULT NULL,
  `PHIc` double(5,2) DEFAULT NULL,
  `PHIt` double(5,2) DEFAULT NULL,
  `precipitation` double(5,2) DEFAULT NULL,
  `ET0` double(5,2) DEFAULT NULL,
  `ETc` double(5,2) DEFAULT NULL,
  PRIMARY KEY (`siteID`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for registering irrigation schedule';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Planting`
--

DROP TABLE IF EXISTS `Planting`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Planting` (
  `siteID` varchar(50) NOT NULL,
  `date` date NOT NULL,
  `Winter_Wheat` tinyint(1) DEFAULT 0,
  `Spring_Wheat` tinyint(1) DEFAULT 0,
  `Spring_Potato` tinyint(1) DEFAULT 0,
  `Summer_Potato` tinyint(1) DEFAULT 0,
  `Soil_Temp` float NOT NULL,
  PRIMARY KEY (`siteID`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for planting date';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Warnings`
--

DROP TABLE IF EXISTS `Warnings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `Warnings` (
  `district` varchar(50) NOT NULL,
  `altitude` int(11) DEFAULT NULL,
  `Heat1` int(11) DEFAULT NULL,
  `Heat2` int(11) DEFAULT NULL,
  `Heat3` int(11) DEFAULT NULL,
  `Cold1` int(11) DEFAULT NULL,
  `Cold2` int(11) DEFAULT NULL,
  `Cold3` int(11) DEFAULT NULL,
  PRIMARY KEY (`district`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for warning thresholds';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `meteo`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `meteo` /*!40100 DEFAULT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci */;

USE `meteo`;

--
-- Table structure for table `farmers`
--

DROP TABLE IF EXISTS `farmers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `farmers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `qr_id` varchar(50) DEFAULT NULL,
  `reg_time` timestamp NOT NULL DEFAULT current_timestamp(),
  `farmer_name` varchar(100) NOT NULL,
  `gender` varchar(20) NOT NULL,
  `date_of_birth` date DEFAULT NULL,
  `hectares` decimal(10,2) DEFAULT NULL,
  `region` varchar(50) NOT NULL,
  `district` varchar(50) NOT NULL,
  `jamoat` varchar(50) NOT NULL,
  `village` varchar(50) DEFAULT NULL,
  `members_count` int(11) DEFAULT NULL,
  `latitude` decimal(10,5) DEFAULT NULL,
  `longitude` decimal(10,5) DEFAULT NULL,
  `sms_type` varchar(10) NOT NULL DEFAULT 'SP',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=77 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `phones`
--

DROP TABLE IF EXISTS `phones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `phones` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `farmer_id` int(11) NOT NULL,
  `farmer_phone` int(11) NOT NULL,
  `start_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `end_date` timestamp NULL DEFAULT '1999-12-31 15:00:00',
  `activity_state` tinyint(4) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=42 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `precipitation`
--

DROP TABLE IF EXISTS `precipitation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `precipitation` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `farmer_phone` int(11) NOT NULL,
  `reg_time` timestamp NOT NULL DEFAULT current_timestamp(),
  `date_time` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `precip_level` decimal(10,0) NOT NULL,
  `sms_text` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`,`farmer_phone`)
) ENGINE=InnoDB AUTO_INCREMENT=1275 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rejected`
--

DROP TABLE IF EXISTS `rejected`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rejected` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `received` timestamp NOT NULL DEFAULT current_timestamp(),
  `date_time` timestamp NULL DEFAULT NULL,
  `farmer_phone` varchar(10) NOT NULL,
  `sms_text` varchar(200) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=678 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `soil_temp`
--

DROP TABLE IF EXISTS `soil_temp`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `soil_temp` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `farmer_phone` int(11) NOT NULL,
  `reg_time` timestamp NOT NULL DEFAULT current_timestamp(),
  `date_time` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `soil_1` decimal(10,1) NOT NULL,
  `soil_2` decimal(10,1) NOT NULL,
  `soil_3` decimal(10,1) NOT NULL,
  `sms_text` varchar(200) DEFAULT NULL,
  `type` varchar(1) NOT NULL,
  PRIMARY KEY (`id`,`farmer_phone`)
) ENGINE=InnoDB AUTO_INCREMENT=1634 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `mysql`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `mysql` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `mysql`;

--
-- Table structure for table `general_log`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `general_log` (
  `event_time` timestamp(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  `user_host` mediumtext NOT NULL,
  `thread_id` bigint(21) unsigned NOT NULL,
  `server_id` int(10) unsigned NOT NULL,
  `command_type` varchar(64) NOT NULL,
  `argument` mediumtext NOT NULL
) ENGINE=CSV DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci COMMENT='General log';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `slow_log`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `slow_log` (
  `start_time` timestamp(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  `user_host` mediumtext NOT NULL,
  `query_time` time(6) NOT NULL,
  `lock_time` time(6) NOT NULL,
  `rows_sent` int(11) NOT NULL,
  `rows_examined` int(11) NOT NULL,
  `db` varchar(512) NOT NULL,
  `last_insert_id` int(11) NOT NULL,
  `insert_id` int(11) NOT NULL,
  `server_id` int(10) unsigned NOT NULL,
  `sql_text` mediumtext NOT NULL,
  `thread_id` bigint(21) unsigned NOT NULL,
  `rows_affected` int(11) NOT NULL
) ENGINE=CSV DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci COMMENT='Slow log';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `column_stats`
--

DROP TABLE IF EXISTS `column_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `column_stats` (
  `db_name` varchar(64) NOT NULL,
  `table_name` varchar(64) NOT NULL,
  `column_name` varchar(64) NOT NULL,
  `min_value` varbinary(255) DEFAULT NULL,
  `max_value` varbinary(255) DEFAULT NULL,
  `nulls_ratio` decimal(12,4) DEFAULT NULL,
  `avg_length` decimal(12,4) DEFAULT NULL,
  `avg_frequency` decimal(12,4) DEFAULT NULL,
  `hist_size` tinyint(3) unsigned DEFAULT NULL,
  `hist_type` enum('SINGLE_PREC_HB','DOUBLE_PREC_HB') DEFAULT NULL,
  `histogram` varbinary(255) DEFAULT NULL,
  PRIMARY KEY (`db_name`,`table_name`,`column_name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=0 COMMENT='Statistics on Columns';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `columns_priv`
--

DROP TABLE IF EXISTS `columns_priv`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `columns_priv` (
  `Host` char(255) NOT NULL DEFAULT '',
  `Db` char(64) NOT NULL DEFAULT '',
  `User` char(128) NOT NULL DEFAULT '',
  `Table_name` char(64) NOT NULL DEFAULT '',
  `Column_name` char(64) NOT NULL DEFAULT '',
  `Timestamp` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `Column_priv` set('Select','Insert','Update','References') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`Host`,`Db`,`User`,`Table_name`,`Column_name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Column privileges';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `db`
--

DROP TABLE IF EXISTS `db`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `db` (
  `Host` char(255) NOT NULL DEFAULT '',
  `Db` char(64) NOT NULL DEFAULT '',
  `User` char(128) NOT NULL DEFAULT '',
  `Select_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Insert_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Update_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Delete_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Create_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Drop_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Grant_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `References_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Index_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Alter_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Create_tmp_table_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Lock_tables_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Create_view_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Show_view_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Create_routine_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Alter_routine_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Execute_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Event_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Trigger_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  `Delete_history_priv` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  PRIMARY KEY (`Host`,`Db`,`User`),
  KEY `User` (`User`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Database privileges';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `event`
--

DROP TABLE IF EXISTS `event`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `event` (
  `db` char(64) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin NOT NULL DEFAULT '',
  `name` char(64) NOT NULL DEFAULT '',
  `body` longblob NOT NULL,
  `definer` varchar(384) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin NOT NULL DEFAULT '',
  `execute_at` datetime DEFAULT NULL,
  `interval_value` int(11) DEFAULT NULL,
  `interval_field` enum('YEAR','QUARTER','MONTH','DAY','HOUR','MINUTE','WEEK','SECOND','MICROSECOND','YEAR_MONTH','DAY_HOUR','DAY_MINUTE','DAY_SECOND','HOUR_MINUTE','HOUR_SECOND','MINUTE_SECOND','DAY_MICROSECOND','HOUR_MICROSECOND','MINUTE_MICROSECOND','SECOND_MICROSECOND') DEFAULT NULL,
  `created` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `modified` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `last_executed` datetime DEFAULT NULL,
  `starts` datetime DEFAULT NULL,
  `ends` datetime DEFAULT NULL,
  `status` enum('ENABLED','DISABLED','SLAVESIDE_DISABLED') NOT NULL DEFAULT 'ENABLED',
  `on_completion` enum('DROP','PRESERVE') NOT NULL DEFAULT 'DROP',
  `sql_mode` set('REAL_AS_FLOAT','PIPES_AS_CONCAT','ANSI_QUOTES','IGNORE_SPACE','IGNORE_BAD_TABLE_OPTIONS','ONLY_FULL_GROUP_BY','NO_UNSIGNED_SUBTRACTION','NO_DIR_IN_CREATE','POSTGRESQL','ORACLE','MSSQL','DB2','MAXDB','NO_KEY_OPTIONS','NO_TABLE_OPTIONS','NO_FIELD_OPTIONS','MYSQL323','MYSQL40','ANSI','NO_AUTO_VALUE_ON_ZERO','NO_BACKSLASH_ESCAPES','STRICT_TRANS_TABLES','STRICT_ALL_TABLES','NO_ZERO_IN_DATE','NO_ZERO_DATE','INVALID_DATES','ERROR_FOR_DIVISION_BY_ZERO','TRADITIONAL','NO_AUTO_CREATE_USER','HIGH_NOT_PRECEDENCE','NO_ENGINE_SUBSTITUTION','PAD_CHAR_TO_FULL_LENGTH','EMPTY_STRING_IS_NULL','SIMULTANEOUS_ASSIGNMENT','TIME_ROUND_FRACTIONAL') NOT NULL DEFAULT '',
  `comment` char(64) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin NOT NULL DEFAULT '',
  `originator` int(10) unsigned NOT NULL,
  `time_zone` char(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL DEFAULT 'SYSTEM',
  `character_set_client` char(32) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin DEFAULT NULL,
  `collation_connection` char(32) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin DEFAULT NULL,
  `db_collation` char(32) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin DEFAULT NULL,
  `body_utf8` longblob DEFAULT NULL,
  PRIMARY KEY (`db`,`name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Events';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `func`
--

DROP TABLE IF EXISTS `func`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `func` (
  `name` char(64) NOT NULL DEFAULT '',
  `ret` tinyint(1) NOT NULL DEFAULT 0,
  `dl` char(128) NOT NULL DEFAULT '',
  `type` enum('function','aggregate') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='User defined functions';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `global_priv`
--

DROP TABLE IF EXISTS `global_priv`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `global_priv` (
  `Host` char(255) NOT NULL DEFAULT '',
  `User` char(128) NOT NULL DEFAULT '',
  `Priv` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '{}' CHECK (json_valid(`Priv`)),
  PRIMARY KEY (`Host`,`User`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Users and global privileges';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `gtid_slave_pos`
--

DROP TABLE IF EXISTS `gtid_slave_pos`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `gtid_slave_pos` (
  `domain_id` int(10) unsigned NOT NULL,
  `sub_id` bigint(20) unsigned NOT NULL,
  `server_id` int(10) unsigned NOT NULL,
  `seq_no` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`domain_id`,`sub_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci COMMENT='Replication slave GTID position';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `help_category`
--

DROP TABLE IF EXISTS `help_category`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `help_category` (
  `help_category_id` smallint(5) unsigned NOT NULL,
  `name` char(64) NOT NULL,
  `parent_category_id` smallint(5) unsigned DEFAULT NULL,
  `url` text NOT NULL,
  PRIMARY KEY (`help_category_id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=0 COMMENT='help categories';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `help_keyword`
--

DROP TABLE IF EXISTS `help_keyword`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `help_keyword` (
  `help_keyword_id` int(10) unsigned NOT NULL,
  `name` char(64) NOT NULL,
  PRIMARY KEY (`help_keyword_id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=0 COMMENT='help keywords';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `help_relation`
--

DROP TABLE IF EXISTS `help_relation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `help_relation` (
  `help_topic_id` int(10) unsigned NOT NULL,
  `help_keyword_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`help_keyword_id`,`help_topic_id`),
  KEY `help_topic_id` (`help_topic_id`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=0 COMMENT='keyword-topic relation';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `help_topic`
--

DROP TABLE IF EXISTS `help_topic`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `help_topic` (
  `help_topic_id` int(10) unsigned NOT NULL,
  `name` char(64) NOT NULL,
  `help_category_id` smallint(5) unsigned NOT NULL,
  `description` text NOT NULL,
  `example` text NOT NULL,
  `url` text NOT NULL,
  PRIMARY KEY (`help_topic_id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=0 COMMENT='help topics';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `index_stats`
--

DROP TABLE IF EXISTS `index_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `index_stats` (
  `db_name` varchar(64) NOT NULL,
  `table_name` varchar(64) NOT NULL,
  `index_name` varchar(64) NOT NULL,
  `prefix_arity` int(11) unsigned NOT NULL,
  `avg_frequency` decimal(12,4) DEFAULT NULL,
  PRIMARY KEY (`db_name`,`table_name`,`index_name`,`prefix_arity`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=0 COMMENT='Statistics on Indexes';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `innodb_index_stats`
--

DROP TABLE IF EXISTS `innodb_index_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `innodb_index_stats` (
  `database_name` varchar(64) NOT NULL,
  `table_name` varchar(199) NOT NULL,
  `index_name` varchar(64) NOT NULL,
  `last_update` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `stat_name` varchar(64) NOT NULL,
  `stat_value` bigint(20) unsigned NOT NULL,
  `sample_size` bigint(20) unsigned DEFAULT NULL,
  `stat_description` varchar(1024) NOT NULL,
  PRIMARY KEY (`database_name`,`table_name`,`index_name`,`stat_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin STATS_PERSISTENT=0;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `innodb_table_stats`
--

DROP TABLE IF EXISTS `innodb_table_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `innodb_table_stats` (
  `database_name` varchar(64) NOT NULL,
  `table_name` varchar(199) NOT NULL,
  `last_update` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `n_rows` bigint(20) unsigned NOT NULL,
  `clustered_index_size` bigint(20) unsigned NOT NULL,
  `sum_of_other_index_sizes` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`database_name`,`table_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin STATS_PERSISTENT=0;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `plugin`
--

DROP TABLE IF EXISTS `plugin`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `plugin` (
  `name` varchar(64) NOT NULL DEFAULT '',
  `dl` varchar(128) NOT NULL DEFAULT '',
  PRIMARY KEY (`name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='MySQL plugins';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `proc`
--

DROP TABLE IF EXISTS `proc`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `proc` (
  `db` char(64) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin NOT NULL DEFAULT '',
  `name` char(64) NOT NULL DEFAULT '',
  `type` enum('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY') NOT NULL,
  `specific_name` char(64) NOT NULL DEFAULT '',
  `language` enum('SQL') NOT NULL DEFAULT 'SQL',
  `sql_data_access` enum('CONTAINS_SQL','NO_SQL','READS_SQL_DATA','MODIFIES_SQL_DATA') NOT NULL DEFAULT 'CONTAINS_SQL',
  `is_deterministic` enum('YES','NO') NOT NULL DEFAULT 'NO',
  `security_type` enum('INVOKER','DEFINER') NOT NULL DEFAULT 'DEFINER',
  `param_list` blob NOT NULL,
  `returns` longblob NOT NULL,
  `body` longblob NOT NULL,
  `definer` varchar(384) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin NOT NULL DEFAULT '',
  `created` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `modified` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  `sql_mode` set('REAL_AS_FLOAT','PIPES_AS_CONCAT','ANSI_QUOTES','IGNORE_SPACE','IGNORE_BAD_TABLE_OPTIONS','ONLY_FULL_GROUP_BY','NO_UNSIGNED_SUBTRACTION','NO_DIR_IN_CREATE','POSTGRESQL','ORACLE','MSSQL','DB2','MAXDB','NO_KEY_OPTIONS','NO_TABLE_OPTIONS','NO_FIELD_OPTIONS','MYSQL323','MYSQL40','ANSI','NO_AUTO_VALUE_ON_ZERO','NO_BACKSLASH_ESCAPES','STRICT_TRANS_TABLES','STRICT_ALL_TABLES','NO_ZERO_IN_DATE','NO_ZERO_DATE','INVALID_DATES','ERROR_FOR_DIVISION_BY_ZERO','TRADITIONAL','NO_AUTO_CREATE_USER','HIGH_NOT_PRECEDENCE','NO_ENGINE_SUBSTITUTION','PAD_CHAR_TO_FULL_LENGTH','EMPTY_STRING_IS_NULL','SIMULTANEOUS_ASSIGNMENT','TIME_ROUND_FRACTIONAL') NOT NULL DEFAULT '',
  `comment` text CHARACTER SET utf8mb3 COLLATE utf8mb3_bin NOT NULL,
  `character_set_client` char(32) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin DEFAULT NULL,
  `collation_connection` char(32) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin DEFAULT NULL,
  `db_collation` char(32) CHARACTER SET utf8mb3 COLLATE utf8mb3_bin DEFAULT NULL,
  `body_utf8` longblob DEFAULT NULL,
  `aggregate` enum('NONE','GROUP') NOT NULL DEFAULT 'NONE',
  PRIMARY KEY (`db`,`name`,`type`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Stored Procedures';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `procs_priv`
--

DROP TABLE IF EXISTS `procs_priv`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `procs_priv` (
  `Host` char(255) NOT NULL DEFAULT '',
  `Db` char(64) NOT NULL DEFAULT '',
  `User` char(128) NOT NULL DEFAULT '',
  `Routine_name` char(64) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT '',
  `Routine_type` enum('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY') NOT NULL,
  `Grantor` varchar(384) NOT NULL DEFAULT '',
  `Proc_priv` set('Execute','Alter Routine','Grant') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT '',
  `Timestamp` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`Host`,`Db`,`User`,`Routine_name`,`Routine_type`),
  KEY `Grantor` (`Grantor`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Procedure privileges';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `proxies_priv`
--

DROP TABLE IF EXISTS `proxies_priv`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `proxies_priv` (
  `Host` char(255) NOT NULL DEFAULT '',
  `User` char(128) NOT NULL DEFAULT '',
  `Proxied_host` char(255) NOT NULL DEFAULT '',
  `Proxied_user` char(128) NOT NULL DEFAULT '',
  `With_grant` tinyint(1) NOT NULL DEFAULT 0,
  `Grantor` varchar(384) NOT NULL DEFAULT '',
  `Timestamp` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`Host`,`User`,`Proxied_host`,`Proxied_user`),
  KEY `Grantor` (`Grantor`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='User proxy privileges';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `roles_mapping`
--

DROP TABLE IF EXISTS `roles_mapping`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `roles_mapping` (
  `Host` char(255) NOT NULL DEFAULT '',
  `User` char(128) NOT NULL DEFAULT '',
  `Role` char(128) NOT NULL DEFAULT '',
  `Admin_option` enum('N','Y') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT 'N',
  UNIQUE KEY `Host` (`Host`,`User`,`Role`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Granted roles';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `servers`
--

DROP TABLE IF EXISTS `servers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `servers` (
  `Server_name` char(64) NOT NULL DEFAULT '',
  `Host` varchar(2048) NOT NULL DEFAULT '',
  `Db` char(64) NOT NULL DEFAULT '',
  `Username` char(128) NOT NULL DEFAULT '',
  `Password` char(64) NOT NULL DEFAULT '',
  `Port` int(4) NOT NULL DEFAULT 0,
  `Socket` char(64) NOT NULL DEFAULT '',
  `Wrapper` char(64) NOT NULL DEFAULT '',
  `Owner` varchar(512) NOT NULL DEFAULT '',
  PRIMARY KEY (`Server_name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='MySQL Foreign Servers table';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `table_stats`
--

DROP TABLE IF EXISTS `table_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `table_stats` (
  `db_name` varchar(64) NOT NULL,
  `table_name` varchar(64) NOT NULL,
  `cardinality` bigint(21) unsigned DEFAULT NULL,
  PRIMARY KEY (`db_name`,`table_name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=0 COMMENT='Statistics on Tables';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `tables_priv`
--

DROP TABLE IF EXISTS `tables_priv`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `tables_priv` (
  `Host` char(255) NOT NULL DEFAULT '',
  `Db` char(64) NOT NULL DEFAULT '',
  `User` char(128) NOT NULL DEFAULT '',
  `Table_name` char(64) NOT NULL DEFAULT '',
  `Grantor` varchar(384) NOT NULL DEFAULT '',
  `Timestamp` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `Table_priv` set('Select','Insert','Update','Delete','Create','Drop','Grant','References','Index','Alter','Create View','Show view','Trigger','Delete versioning rows') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT '',
  `Column_priv` set('Select','Insert','Update','References') CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`Host`,`Db`,`User`,`Table_name`),
  KEY `Grantor` (`Grantor`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Table privileges';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `time_zone`
--

DROP TABLE IF EXISTS `time_zone`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `time_zone` (
  `Time_zone_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Use_leap_seconds` enum('Y','N') NOT NULL DEFAULT 'N',
  PRIMARY KEY (`Time_zone_id`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Time zones';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `time_zone_leap_second`
--

DROP TABLE IF EXISTS `time_zone_leap_second`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `time_zone_leap_second` (
  `Transition_time` bigint(20) NOT NULL,
  `Correction` int(11) NOT NULL,
  PRIMARY KEY (`Transition_time`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Leap seconds information for time zones';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `time_zone_name`
--

DROP TABLE IF EXISTS `time_zone_name`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `time_zone_name` (
  `Name` char(64) NOT NULL,
  `Time_zone_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`Name`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Time zone names';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `time_zone_transition`
--

DROP TABLE IF EXISTS `time_zone_transition`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `time_zone_transition` (
  `Time_zone_id` int(10) unsigned NOT NULL,
  `Transition_time` bigint(20) NOT NULL,
  `Transition_type_id` int(10) unsigned NOT NULL,
  PRIMARY KEY (`Time_zone_id`,`Transition_time`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Time zone transitions';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `time_zone_transition_type`
--

DROP TABLE IF EXISTS `time_zone_transition_type`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `time_zone_transition_type` (
  `Time_zone_id` int(10) unsigned NOT NULL,
  `Transition_type_id` int(10) unsigned NOT NULL,
  `Offset` int(11) NOT NULL DEFAULT 0,
  `Is_DST` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `Abbreviation` char(8) NOT NULL DEFAULT '',
  PRIMARY KEY (`Time_zone_id`,`Transition_type_id`)
) ENGINE=Aria DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci PAGE_CHECKSUM=1 TRANSACTIONAL=1 COMMENT='Time zone transition types';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Temporary table structure for view `user`
--

DROP TABLE IF EXISTS `user`;
/*!50001 DROP VIEW IF EXISTS `user`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE VIEW `user` AS SELECT
 1 AS `Host`,
  1 AS `User`,
  1 AS `Password`,
  1 AS `Select_priv`,
  1 AS `Insert_priv`,
  1 AS `Update_priv`,
  1 AS `Delete_priv`,
  1 AS `Create_priv`,
  1 AS `Drop_priv`,
  1 AS `Reload_priv`,
  1 AS `Shutdown_priv`,
  1 AS `Process_priv`,
  1 AS `File_priv`,
  1 AS `Grant_priv`,
  1 AS `References_priv`,
  1 AS `Index_priv`,
  1 AS `Alter_priv`,
  1 AS `Show_db_priv`,
  1 AS `Super_priv`,
  1 AS `Create_tmp_table_priv`,
  1 AS `Lock_tables_priv`,
  1 AS `Execute_priv`,
  1 AS `Repl_slave_priv`,
  1 AS `Repl_client_priv`,
  1 AS `Create_view_priv`,
  1 AS `Show_view_priv`,
  1 AS `Create_routine_priv`,
  1 AS `Alter_routine_priv`,
  1 AS `Create_user_priv`,
  1 AS `Event_priv`,
  1 AS `Trigger_priv`,
  1 AS `Create_tablespace_priv`,
  1 AS `Delete_history_priv`,
  1 AS `ssl_type`,
  1 AS `ssl_cipher`,
  1 AS `x509_issuer`,
  1 AS `x509_subject`,
  1 AS `max_questions`,
  1 AS `max_updates`,
  1 AS `max_connections`,
  1 AS `max_user_connections`,
  1 AS `plugin`,
  1 AS `authentication_string`,
  1 AS `password_expired`,
  1 AS `is_role`,
  1 AS `default_role`,
  1 AS `max_statement_time` */;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `transaction_registry`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE IF NOT EXISTS `transaction_registry` (
  `transaction_id` bigint(20) unsigned NOT NULL,
  `commit_id` bigint(20) unsigned NOT NULL,
  `begin_timestamp` timestamp(6) NOT NULL DEFAULT '0000-00-00 00:00:00.000000',
  `commit_timestamp` timestamp(6) NOT NULL DEFAULT '0000-00-00 00:00:00.000000',
  `isolation_level` enum('READ-UNCOMMITTED','READ-COMMITTED','REPEATABLE-READ','SERIALIZABLE') NOT NULL,
  PRIMARY KEY (`transaction_id`),
  UNIQUE KEY `commit_id` (`commit_id`),
  KEY `begin_timestamp` (`begin_timestamp`),
  KEY `commit_timestamp` (`commit_timestamp`,`transaction_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_bin STATS_PERSISTENT=0;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Current Database: `wwcs`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `wwcs` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci */;

USE `wwcs`;

--
-- Table structure for table `deployments`
--

DROP TABLE IF EXISTS `deployments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `deployments` (
  `stationID` varchar(50) NOT NULL,
  `loggerID` varchar(50) NOT NULL,
  `startDate` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `endDate` datetime NOT NULL DEFAULT '2100-01-01 00:00:00'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='associating loggerIDs to stationIDs';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `metadata`
--

DROP TABLE IF EXISTS `metadata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `metadata` (
  `loggerID` varchar(50) NOT NULL,
  `timestamp` datetime NOT NULL,
  `git_version` varchar(50) DEFAULT NULL,
  `domain` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`loggerID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='metadata about the loggers';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `meteoseries`
--

DROP TABLE IF EXISTS `meteoseries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `meteoseries` (
  `loggerID` varchar(50) NOT NULL,
  `timestamp` datetime NOT NULL,
  `received` datetime DEFAULT NULL,
  `ta` float DEFAULT NULL,
  `rh` float DEFAULT NULL,
  `logger_ta` float DEFAULT NULL,
  `logger_rh` float DEFAULT NULL,
  `p` float DEFAULT NULL,
  `U_Battery` float DEFAULT NULL,
  `U_Solar` float DEFAULT NULL,
  `signalStrength` float DEFAULT NULL,
  PRIMARY KEY (`loggerID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='data measured by the loggers';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rejected`
--

DROP TABLE IF EXISTS `rejected`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rejected` (
  `ID` bigint(20) unsigned NOT NULL,
  `received` datetime NOT NULL,
  `ip` varchar(46) DEFAULT NULL,
  `data` varchar(400) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table to contain the rejected input data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `sites`
--

DROP TABLE IF EXISTS `sites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `sites` (
  `stationID` varchar(50) NOT NULL,
  `stationName` varchar(100) DEFAULT NULL,
  `district` varchar(100) DEFAULT NULL,
  `jamoat` varchar(100) DEFAULT NULL,
  `village` varchar(100) DEFAULT NULL,
  `latitude` float NOT NULL,
  `longitude` float NOT NULL,
  `altitude` float NOT NULL,
  `slope` float DEFAULT NULL,
  `azimuth` float DEFAULT NULL,
  PRIMARY KEY (`stationID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='The geographical information of a physical place where a station stands';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `submitted`
--

DROP TABLE IF EXISTS `submitted`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `submitted` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `received` datetime NOT NULL DEFAULT current_timestamp(),
  `ip` varchar(46) DEFAULT NULL,
  `data` varchar(400) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB AUTO_INCREMENT=5075216 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='The data as submitted by the loggers';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Temporary table structure for view `v_meteoseries`
--

DROP TABLE IF EXISTS `v_meteoseries`;
/*!50001 DROP VIEW IF EXISTS `v_meteoseries`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE VIEW `v_meteoseries` AS SELECT
 1 AS `stationID`,
  1 AS `loggerID`,
  1 AS `timestamp`,
  1 AS `received`,
  1 AS `ta`,
  1 AS `rh`,
  1 AS `logger_ta`,
  1 AS `logger_rh`,
  1 AS `p`,
  1 AS `U_Battery`,
  1 AS `U_Solar`,
  1 AS `signalStrength` */;
SET character_set_client = @saved_cs_client;

--
-- Current Database: `BeneficiarySupport`
--

USE `BeneficiarySupport`;

--
-- Current Database: `Humans`
--

USE `Humans`;

--
-- Current Database: `Machines`
--

USE `Machines`;

--
-- Final view structure for view `v_machineobs`
--

/*!50001 DROP VIEW IF EXISTS `v_machineobs`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_machineobs` AS select `D`.`siteID` AS `siteID`,`S`.`loggerID` AS `loggerID`,`S`.`timestamp` AS `timestamp`,`S`.`received` AS `received`,`S`.`ta` AS `ta`,`S`.`rh` AS `rh`,`S`.`logger_ta` AS `logger_ta`,`S`.`logger_rh` AS `logger_rh`,`S`.`p` AS `p`,`S`.`U_Battery` AS `U_Battery`,`S`.`U_Solar` AS `U_Solar`,`S`.`signalStrength` AS `signalStrength`,`S`.`Charge_Battery1` AS `Charge_Battery1`,`S`.`Charge_Battery2` AS `Charge_Battery2`,`S`.`Temp_Battery1` AS `Temp_Battery1`,`S`.`Temp_Battery2` AS `Temp_Battery2`,`S`.`Temp_HumiSens` AS `Temp_HumiSens`,`S`.`U_Battery1` AS `U_Battery1`,`S`.`U_Battery2` AS `U_Battery2`,`S`.`compass` AS `compass`,`S`.`lightning_count` AS `lightning_count`,`S`.`lightning_dist` AS `lightning_dist`,`S`.`pr` AS `pr`,`S`.`rad` AS `rad`,`S`.`tilt_x` AS `tilt_x`,`S`.`tilt_y` AS `tilt_y`,`S`.`ts10cm` AS `ts10cm`,`S`.`vapour_press` AS `vapour_press`,`S`.`wind_dir` AS `wind_dir`,`S`.`wind_gust` AS `wind_gust`,`S`.`wind_speed` AS `wind_speed`,`S`.`wind_speed_E` AS `wind_speed_E`,`S`.`wind_speed_N` AS `wind_speed_N` from (`MachineObs` `S` join `MachineAtSite` `D` on(`D`.`loggerID` = `S`.`loggerID` and `S`.`timestamp` >= coalesce(`D`.`startDate`,current_timestamp()) and `S`.`timestamp` <= coalesce(`D`.`endDate`,current_timestamp()))) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Current Database: `SitesHumans`
--

USE `SitesHumans`;

--
-- Current Database: `WWCServices`
--

USE `WWCServices`;

--
-- Current Database: `meteo`
--

USE `meteo`;

--
-- Current Database: `mysql`
--

USE `mysql`;

--
-- Final view structure for view `user`
--

/*!50001 DROP VIEW IF EXISTS `user`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`mariadb.sys`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `user` AS select `global_priv`.`Host` AS `Host`,`global_priv`.`User` AS `User`,if(json_value(`global_priv`.`Priv`,'$.plugin') in ('mysql_native_password','mysql_old_password'),ifnull(json_value(`global_priv`.`Priv`,'$.authentication_string'),''),'') AS `Password`,if(json_value(`global_priv`.`Priv`,'$.access') & 1,'Y','N') AS `Select_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 2,'Y','N') AS `Insert_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 4,'Y','N') AS `Update_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 8,'Y','N') AS `Delete_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 16,'Y','N') AS `Create_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 32,'Y','N') AS `Drop_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 64,'Y','N') AS `Reload_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 128,'Y','N') AS `Shutdown_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 256,'Y','N') AS `Process_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 512,'Y','N') AS `File_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 1024,'Y','N') AS `Grant_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 2048,'Y','N') AS `References_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 4096,'Y','N') AS `Index_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 8192,'Y','N') AS `Alter_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 16384,'Y','N') AS `Show_db_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 32768,'Y','N') AS `Super_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 65536,'Y','N') AS `Create_tmp_table_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 131072,'Y','N') AS `Lock_tables_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 262144,'Y','N') AS `Execute_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 524288,'Y','N') AS `Repl_slave_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 1048576,'Y','N') AS `Repl_client_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 2097152,'Y','N') AS `Create_view_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 4194304,'Y','N') AS `Show_view_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 8388608,'Y','N') AS `Create_routine_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 16777216,'Y','N') AS `Alter_routine_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 33554432,'Y','N') AS `Create_user_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 67108864,'Y','N') AS `Event_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 134217728,'Y','N') AS `Trigger_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 268435456,'Y','N') AS `Create_tablespace_priv`,if(json_value(`global_priv`.`Priv`,'$.access') & 536870912,'Y','N') AS `Delete_history_priv`,elt(ifnull(json_value(`global_priv`.`Priv`,'$.ssl_type'),0) + 1,'','ANY','X509','SPECIFIED') AS `ssl_type`,ifnull(json_value(`global_priv`.`Priv`,'$.ssl_cipher'),'') AS `ssl_cipher`,ifnull(json_value(`global_priv`.`Priv`,'$.x509_issuer'),'') AS `x509_issuer`,ifnull(json_value(`global_priv`.`Priv`,'$.x509_subject'),'') AS `x509_subject`,cast(ifnull(json_value(`global_priv`.`Priv`,'$.max_questions'),0) as unsigned) AS `max_questions`,cast(ifnull(json_value(`global_priv`.`Priv`,'$.max_updates'),0) as unsigned) AS `max_updates`,cast(ifnull(json_value(`global_priv`.`Priv`,'$.max_connections'),0) as unsigned) AS `max_connections`,cast(ifnull(json_value(`global_priv`.`Priv`,'$.max_user_connections'),0) as signed) AS `max_user_connections`,ifnull(json_value(`global_priv`.`Priv`,'$.plugin'),'') AS `plugin`,ifnull(json_value(`global_priv`.`Priv`,'$.authentication_string'),'') AS `authentication_string`,if(ifnull(json_value(`global_priv`.`Priv`,'$.password_last_changed'),1) = 0,'Y','N') AS `password_expired`,elt(ifnull(json_value(`global_priv`.`Priv`,'$.is_role'),0) + 1,'N','Y') AS `is_role`,ifnull(json_value(`global_priv`.`Priv`,'$.default_role'),'') AS `default_role`,cast(ifnull(json_value(`global_priv`.`Priv`,'$.max_statement_time'),0.0) as decimal(12,6)) AS `max_statement_time` from `global_priv` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Current Database: `wwcs`
--

USE `wwcs`;

--
-- Final view structure for view `v_meteoseries`
--

/*!50001 DROP VIEW IF EXISTS `v_meteoseries`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_meteoseries` AS select `D`.`stationID` AS `stationID`,`S`.`loggerID` AS `loggerID`,`S`.`timestamp` AS `timestamp`,`S`.`received` AS `received`,`S`.`ta` AS `ta`,`S`.`rh` AS `rh`,`S`.`logger_ta` AS `logger_ta`,`S`.`logger_rh` AS `logger_rh`,`S`.`p` AS `p`,`S`.`U_Battery` AS `U_Battery`,`S`.`U_Solar` AS `U_Solar`,`S`.`signalStrength` AS `signalStrength` from (`meteoseries` `S` join `deployments` `D` on(`D`.`loggerID` = `S`.`loggerID` and `S`.`timestamp` >= coalesce(`D`.`startDate`,current_timestamp()) and `S`.`timestamp` <= coalesce(`D`.`endDate`,current_timestamp()))) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2024-10-28 12:48:56

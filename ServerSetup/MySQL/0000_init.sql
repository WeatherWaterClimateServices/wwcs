/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.6.21-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: BeneficiarySupport
-- ------------------------------------------------------
-- Server version	10.6.21-MariaDB-0ubuntu0.22.04.2

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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `MachineObsSubmitted` (
  `domain` varchar(50) NOT NULL,
  `received` datetime NOT NULL DEFAULT current_timestamp(),
  `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`data`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='SubmittedObs JSON data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Metadata`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8mb4;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `Avalanche` (
  `siteID` varchar(50) NOT NULL,
  `timestamp` datetime NOT NULL,
  PRIMARY KEY (`siteID`,`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Table for registering avalanche warning';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `Coldwave`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
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
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-04-09 19:13:33

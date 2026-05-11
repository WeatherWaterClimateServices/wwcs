DROP VIEW IF EXISTS Machines.v_machineobs;

CREATE VIEW Machines.v_machineobs AS
SELECT
    D.siteID,
    S.loggerID,
    S.timestamp,
    S.received,
    S.ta,
    S.rh,
    S.logger_ta,
    S.logger_rh,
    S.p,
    S.U_Battery,
    S.U_Solar,
    S.signalStrength,
    S.Charge_Battery,
    S.Temp_Battery,
    S.Temp_HumiSens,
    S.U_Battery1,
    S.compass,
    S.lightning_count,
    S.lightning_dist,
    S.pr,
    S.rad,
    S.tilt_x,
    S.tilt_y,
    S.ts10cm,
    S.vapour_press,
    S.wind_dir,
    S.wind_gust,
    S.wind_speed,
    S.wind_speed_E,
    S.wind_speed_N,
    S.PM25,
    S.PM10
FROM Machines.MachineObs S
JOIN Machines.MachineAtSite D
    ON D.loggerID = S.loggerID
    AND S.timestamp >= COALESCE(D.startDate, CURRENT_TIMESTAMP())
    AND S.timestamp <= COALESCE(D.endDate, CURRENT_TIMESTAMP());

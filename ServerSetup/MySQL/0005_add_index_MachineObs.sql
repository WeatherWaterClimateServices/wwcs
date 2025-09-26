CREATE INDEX idx_logger_timestamp 
ON Machines.MachineObs(loggerID, timestamp DESC);

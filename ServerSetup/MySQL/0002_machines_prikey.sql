ALTER TABLE Machines.MachineAtSite DROP PRIMARY KEY;
ALTER TABLE Machines.MachineAtSite ADD PRIMARY KEY (loggerID, startDate);

-- Relax CHECK constraint on Machines.MachineObsRejected.data
-- so that empty request bodies can be stored for debugging.
-- The original inline CHECK required valid JSON. We redefine the column to drop it,
-- then add a new named CHECK that also allows empty strings.
ALTER TABLE Machines.MachineObsRejected
  MODIFY COLUMN `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL;

ALTER TABLE Machines.MachineObsRejected
  ADD CONSTRAINT `MachineObsRejected.data`
  CHECK (data IS NULL OR data = '' OR json_valid(data));

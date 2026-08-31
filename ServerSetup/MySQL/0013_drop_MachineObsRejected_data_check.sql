-- Drop the CHECK constraint on Machines.MachineObsRejected.data.
-- The rejected-observations table is meant to store invalid or malformed
-- payloads, including strings that are not valid JSON. Requiring valid JSON
-- here defeats the purpose of the table.
ALTER TABLE Machines.MachineObsRejected
  DROP CONSTRAINT `MachineObsRejected.data`;

-- Redefine the column without the constraint as a fallback / cleanup.
ALTER TABLE Machines.MachineObsRejected
  MODIFY COLUMN `data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL;

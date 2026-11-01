-- BinWise database: load the 30 days of test drops
-- Before running this: import data/drops_history.csv into the drops_import table
-- (Workbench: right-click drops_import > Table Data Import Wizard > choose the CSV > Use existing table > Next until Finish)
USE binwise_db;

-- reset_demo (in 03_logic.sql) copies the test drops into drops, moves them so they end yesterday,
-- and sets each bin's fill level. Safe to run again at any time, e.g. just before the demo.
CALL reset_demo();

-- Check
SELECT * FROM v_kpis;
SELECT * FROM v_bin_status;

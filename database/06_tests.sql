-- BinWise database tests (Augustin, Database Developer and Tester)
-- Run the whole file in MySQL Workbench (lightning icon). Each part shows a result grid.
-- Every test shows what we expected, what the database actually did, and PASS or FAIL.
-- It starts and ends with CALL reset_demo(), so it can be run as often as you like
-- and the demo data is back to normal afterwards.
USE binwise_db;

CALL reset_demo();


-- ---------- Part 1: does each item go in the right compartment? ----------
-- classify_item(barcode, what the camera saw, how sure Robobin is from 0 to 1)
-- 'Unknown' means Robobin is not sure, so the item goes in the general waste compartment.

SELECT test, expected, actual,
       IF(actual = expected, 'PASS', 'FAIL') AS outcome
FROM (
  SELECT 'T1  Coca-Cola can, barcode scanned'            AS test, 'Recycling'     AS expected, classify_item('5449000000996', NULL, 1.00)                    AS actual
  UNION ALL
  SELECT 'T2  Activia pot, barcode but material unknown',         'Unknown',                  classify_item('3033491314834', NULL, 1.00)
  UNION ALL
  SELECT 'T3  Crushed can, no barcode, camera 90% sure',          'Recycling',                classify_item(NULL, 'Drinks can', 0.90)
  UNION ALL
  SELECT 'T4  Dirty can, camera only 70% sure',                   'Unknown',                  classify_item(NULL, 'Drinks can', 0.70)
  UNION ALL
  SELECT 'T5  Food leftovers, 90% sure',                          'Food waste',               classify_item(NULL, 'Food leftovers', 0.90)
  UNION ALL
  SELECT 'T6  AA battery, 60% sure (hazard limit is 50%)',        'Hazardous',                classify_item(NULL, 'Battery', 0.60)
) AS results;


-- ---------- Part 2: Robobin fills up, the dashboard alerts, staff empty it ----------
-- Bin 1 (Trinity Leeds) starts with 21 items in its Recycling compartment, which holds 50 (42%).
-- 19 more cans makes 40 items = 80%, so an alert should appear.

SELECT 'Before' AS moment, recycling_items, recycling_pct FROM v_bin_status WHERE bin_id = 1;

CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);
CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);

SELECT 'T7  Bin 1 Recycling after 19 more cans: 80% and an alert' AS test, '80% and 1 alert' AS expected,
       CONCAT(recycling_pct, '% and ', (SELECT COUNT(*) FROM v_alerts WHERE bin_id = 1 AND compartment = 'Recycling'), ' alert') AS actual,
       IF(recycling_pct = 80 AND (SELECT COUNT(*) FROM v_alerts WHERE bin_id = 1 AND compartment = 'Recycling') = 1, 'PASS', 'FAIL') AS outcome
  FROM v_bin_status WHERE bin_id = 1;

-- Staff open Robobin and empty it (the bin's software does this on its own)
UPDATE bins SET fill_items = 0, last_emptied = NOW() WHERE bin_id = 1;

SELECT 'T8  Bin 1 after staff empty it' AS test, '0% and no alert' AS expected,
       CONCAT(recycling_pct, '% and ', (SELECT COUNT(*) FROM v_alerts WHERE bin_id = 1), ' alerts') AS actual,
       IF(recycling_pct = 0 AND (SELECT COUNT(*) FROM v_alerts WHERE bin_id = 1) = 0, 'PASS', 'FAIL') AS outcome
  FROM v_bin_status WHERE bin_id = 1;


-- ---------- Part 3: users and permissions ----------
-- Fly-Tech staff must only open the report, and a wrong password must not log in.
-- The API checks a password the same way: SHA2(salt + password) must match the saved hash.

SELECT test, expected, actual,
       IF(actual = expected, 'PASS', 'FAIL') AS outcome
FROM (
  SELECT 'T9  Fly-Tech staff pages' AS test, 'report' AS expected,
         (SELECT GROUP_CONCAT(page ORDER BY page) FROM permissions WHERE role_name = 'Fly-Tech staff') AS actual
  UNION ALL
  SELECT 'T10 Login with a wrong password', 'no user',
         COALESCE((SELECT username FROM users WHERE username = 'council' AND password_hash = SHA2(CONCAT(salt, 'wrong'), 256)), 'no user')
) AS results;


-- ---------- Put the demo data back ----------

CALL reset_demo();

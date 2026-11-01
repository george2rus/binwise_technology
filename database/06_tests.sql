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
  SELECT 'T2  Walkers crisps, barcode scanned',                   'General waste',            classify_item('5000328347790', NULL, 1.00)
  UNION ALL
  SELECT 'T3  Activia pot, barcode but material unknown',         'Unknown',                  classify_item('3033491314834', NULL, 1.00)
  UNION ALL
  SELECT 'T4  Activia pot, camera sees a pot (85% sure)',         'Recycling',                classify_item('3033491314834', 'Plastic tub or pot', 0.85)
  UNION ALL
  SELECT 'T5  Crushed can, no barcode, camera 90% sure',          'Recycling',                classify_item(NULL, 'Drinks can', 0.90)
  UNION ALL
  SELECT 'T6  Dirty can, camera only 70% sure',                   'Unknown',                  classify_item(NULL, 'Drinks can', 0.70)
  UNION ALL
  SELECT 'T7  Coffee cup (plastic lined), 90% sure',              'General waste',            classify_item(NULL, 'Coffee cup', 0.90)
  UNION ALL
  SELECT 'T8  Food leftovers, 90% sure',                          'Food waste',               classify_item(NULL, 'Food leftovers', 0.90)
  UNION ALL
  SELECT 'T9  Leftover drink drained by the liquid sensor',       'Liquids',                  classify_item(NULL, 'Leftover drink', 0.99)
  UNION ALL
  SELECT 'T10 AA battery, 60% sure (hazard limit is 50%)',        'Hazardous',                classify_item(NULL, 'Battery', 0.60)
  UNION ALL
  SELECT 'T11 Maybe a battery, only 40% sure',                    'Unknown',                  classify_item(NULL, 'Battery', 0.40)
  UNION ALL
  SELECT 'T12 Vape, 55% sure',                                    'Hazardous',                classify_item(NULL, 'Vape', 0.55)
) AS results;


-- ---------- Part 2: does the admin setting change the result? ----------
-- An admin lowers "how sure Robobin must be" from 80% to 60% on the Settings page.
-- The dirty can from T6 (70% sure) should now be recycled. Then the setting goes back to 80%.

UPDATE settings SET value = 0.60 WHERE name = 'sort_threshold';

SELECT 'T13 Dirty can 70% sure, threshold lowered to 60%' AS test, 'Recycling' AS expected,
       classify_item(NULL, 'Drinks can', 0.70) AS actual,
       IF(classify_item(NULL, 'Drinks can', 0.70) = 'Recycling', 'PASS', 'FAIL') AS outcome;

UPDATE settings SET value = 0.80 WHERE name = 'sort_threshold';


-- ---------- Part 3: Robobin fills up, the dashboard alerts, staff empty it ----------
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

SELECT 'T14 Bin 1 Recycling after 19 more cans' AS test, '80%' AS expected,
       CONCAT(recycling_pct, '%') AS actual,
       IF(recycling_pct = 80, 'PASS', 'FAIL') AS outcome
  FROM v_bin_status WHERE bin_id = 1;

SELECT 'T15 Alert for bin 1 Recycling, with the time it reached 80%' AS test, '1 alert' AS expected,
       CONCAT(COUNT(*), ' alert, since ', MAX(alert_since)) AS actual,
       IF(COUNT(*) = 1, 'PASS', 'FAIL') AS outcome
  FROM v_alerts WHERE bin_id = 1 AND compartment = 'Recycling';

-- Staff open Robobin and empty it (the bin's software does this on its own)
UPDATE bins SET fill_items = 0, last_emptied = NOW() WHERE bin_id = 1;

SELECT 'T16 Bin 1 after staff empty it' AS test, '0% and no alert' AS expected,
       CONCAT(recycling_pct, '% and ', (SELECT COUNT(*) FROM v_alerts WHERE bin_id = 1), ' alerts') AS actual,
       IF(recycling_pct = 0 AND (SELECT COUNT(*) FROM v_alerts WHERE bin_id = 1) = 0, 'PASS', 'FAIL') AS outcome
  FROM v_bin_status WHERE bin_id = 1;


-- ---------- Part 4: users and permissions ----------
-- Which pages each role can open (listed in the order of the page list), and whether the login check works.
-- The API checks a password the same way: SHA2(salt + password) must match the saved hash.

SELECT test, expected, actual,
       IF(actual = expected, 'PASS', 'FAIL') AS outcome
FROM (
  SELECT 'T17 Council staff pages' AS test, 'dashboard,support' AS expected,
         (SELECT GROUP_CONCAT(page ORDER BY page) FROM permissions WHERE role_name = 'Council staff') AS actual
  UNION ALL
  SELECT 'T18 Fly-Tech staff pages', 'report',
         (SELECT GROUP_CONCAT(page ORDER BY page) FROM permissions WHERE role_name = 'Fly-Tech staff')
  UNION ALL
  SELECT 'T19 BinWise staff pages', 'dashboard,report,support,simulator,settings',
         (SELECT GROUP_CONCAT(page ORDER BY page) FROM permissions WHERE role_name = 'BinWise staff')
  UNION ALL
  SELECT 'T20 Login with the right password', 'council',
         (SELECT username FROM users WHERE username = 'council' AND password_hash = SHA2(CONCAT(salt, 'Council2026'), 256))
  UNION ALL
  SELECT 'T21 Login with a wrong password', 'no user',
         COALESCE((SELECT username FROM users WHERE username = 'council' AND password_hash = SHA2(CONCAT(salt, 'wrong'), 256)), 'no user')
  UNION ALL
  SELECT 'T22 Passwords are not saved as plain text', '0',
         CAST((SELECT COUNT(*) FROM users WHERE password_hash IN ('Council2026', 'BinWise2026', 'FlyTech2026')) AS CHAR)
) AS results;


-- ---------- Part 5: the demo reset puts everything back ----------

CALL reset_demo();

SELECT 'T23 Reset brings back the 30 days of test data' AS test, '3000 items, 2 alerts' AS expected,
       CONCAT(items_sorted, ' items, ', open_alerts, ' alerts') AS actual,
       IF(items_sorted = 3000 AND open_alerts = 2, 'PASS', 'FAIL') AS outcome
  FROM v_kpis;

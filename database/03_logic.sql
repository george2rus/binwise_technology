USE binwise_db;

DROP FUNCTION  IF EXISTS classify_item;
DROP PROCEDURE IF EXISTS bin_drop;
DROP TRIGGER   IF EXISTS after_drop;
DROP PROCEDURE IF EXISTS reset_demo;

DELIMITER $$

-- Decide which compartment an item goes in:
-- 1. Barcode known and its material known: use the product's material
-- 2. Otherwise use what the camera (and sensor) saw, if the bin is sure enough (settings: sort_threshold, 0.80)
-- 3. Batteries and vapes are hazardous from a lower certainty (settings: hazard_threshold, 0.50): a missed battery can start a fire
-- 4. The material's council rule picks the compartment: Recycling, General waste, Food waste, Liquids or Hazardous
-- 5. Not sure: Unknown, which goes in the general waste compartment so recycling is not contaminated
CREATE FUNCTION classify_item(p_barcode VARCHAR(14), p_item_type VARCHAR(40), p_confidence DECIMAL(3,2))
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
  DECLARE v_recyclable VARCHAR(3) DEFAULT NULL;
  DECLARE v_bin VARCHAR(20) DEFAULT NULL;
  DECLARE v_sort DECIMAL(4,2) DEFAULT 0.80;
  DECLARE v_hazard DECIMAL(4,2) DEFAULT 0.50;

  SELECT value INTO v_sort   FROM settings WHERE name = 'sort_threshold';
  SELECT value INTO v_hazard FROM settings WHERE name = 'hazard_threshold';

  IF p_barcode IS NOT NULL THEN
    SELECT r.recyclable, r.bin INTO v_recyclable, v_bin
      FROM products p JOIN council_rules r ON r.material = p.material
     WHERE p.barcode = p_barcode;
  END IF;

  IF v_bin IS NULL AND p_item_type IS NOT NULL THEN
    SELECT r.recyclable, r.bin INTO v_recyclable, v_bin
      FROM item_types t JOIN council_rules r ON r.material = t.material
     WHERE t.item_type = p_item_type;
    IF v_bin = 'Hazardous' AND p_confidence >= v_hazard THEN
      RETURN 'Hazardous';
    END IF;
    IF p_confidence < v_sort THEN
      SET v_recyclable = NULL;
      SET v_bin = NULL;
    END IF;
  END IF;

  RETURN CASE
           WHEN v_bin = 'Hazardous'  THEN 'Hazardous'
           WHEN v_bin = 'Food waste' THEN 'Food waste'
           WHEN v_bin = 'Liquids'    THEN 'Liquids'
           WHEN v_recyclable = 'Yes' THEN 'Recycling'
           WHEN v_recyclable = 'No'  THEN 'General waste'
           ELSE 'Unknown'
         END;
END$$

-- The bin identifies an item and records it
-- Examples:
--   CALL bin_drop(1, '5449000000996', NULL, 'Barcode', 1.00);            -- Coca-Cola can -> Recycling
--   CALL bin_drop(1, NULL, 'Drinks can', 'Camera + sensor', 0.97);       -- no barcode -> Recycling
--   CALL bin_drop(1, NULL, 'Plastic tub or pot', 'Camera', 0.62);        -- not sure -> Unknown
--   CALL bin_drop(1, NULL, 'Battery', 'Camera + sensor', 0.85);          -- battery -> Hazardous
--   CALL bin_drop(1, NULL, 'Food leftovers', 'Camera + sensor', 0.90);   -- food -> Food waste
--   CALL bin_drop(1, NULL, 'Leftover drink', 'Sensor', 0.99);            -- liquid -> Liquids tank
CREATE PROCEDURE bin_drop(IN p_bin_id INT, IN p_barcode VARCHAR(14), IN p_item_type VARCHAR(40),
                          IN p_detected_by VARCHAR(20), IN p_confidence DECIMAL(3,2))
BEGIN
  INSERT INTO drops (bin_id, barcode, item_type, detected_by, confidence, dropped_at, result)
  VALUES (p_bin_id, p_barcode, p_item_type, p_detected_by, p_confidence, NOW(),
          classify_item(p_barcode, p_item_type, p_confidence));
END$$

-- Every new drop adds one item to its bin
CREATE TRIGGER after_drop
AFTER INSERT ON drops
FOR EACH ROW
BEGIN
  UPDATE bins SET fill_items = fill_items + 1 WHERE bin_id = NEW.bin_id;
END$$

-- Reset the demo: reload the 30 days of test drops from drops_import and refill the bins.
-- The test data is moved in time so it always ends yesterday, and live demo drops land after it.
-- Safe to run as often as you like:  CALL reset_demo();
CREATE PROCEDURE reset_demo()
BEGIN
  DECLARE v_shift INT;

  IF (SELECT COUNT(*) FROM drops_import) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Import data/drops_history.csv into drops_import first';
  END IF;

  SELECT DATEDIFF(CURDATE(), DATE(MAX(dropped_at))) - 1 INTO v_shift FROM drops_import;

  TRUNCATE TABLE drops;
  TRUNCATE TABLE support_tickets;   -- demo support requests start empty too

  INSERT INTO drops (bin_id, barcode, item_type, detected_by, confidence, dropped_at, result)
  SELECT bin_id, NULLIF(barcode, ''), NULLIF(item_type, ''), detected_by, confidence,
         dropped_at + INTERVAL v_shift DAY,
         classify_item(NULLIF(barcode, ''), NULLIF(item_type, ''), confidence)
    FROM drops_import
   ORDER BY dropped_at;

  -- When each bin was last emptied (same times as 02_seed.sql, moved by the same number of days)
  UPDATE bins
     SET last_emptied = CASE bin_id WHEN 1 THEN '2026-10-30 07:00:00'
                                    WHEN 2 THEN '2026-10-27 07:00:00'
                                    WHEN 3 THEN '2026-10-27 18:00:00'
                                    WHEN 4 THEN '2026-10-29 07:00:00' END + INTERVAL v_shift DAY
   WHERE bin_id BETWEEN 1 AND 4;

  -- Fill level = items dropped since the bin was last emptied
  UPDATE bins b
     SET fill_items = (SELECT COUNT(*) FROM drops d
                        WHERE d.bin_id = b.bin_id AND d.dropped_at > b.last_emptied)
   WHERE b.bin_id > 0;
END$$

DELIMITER ;

-- Council staff empty a bin (no procedure needed):
--   UPDATE bins SET fill_items = 0, last_emptied = NOW() WHERE bin_id = 1;

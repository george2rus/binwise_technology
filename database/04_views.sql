-- BinWise database: report views used by the dashboard
USE binwise_db;

-- What is in each compartment of each bin since it was last emptied, and how full each one is
CREATE OR REPLACE VIEW v_bin_contents AS
SELECT b.bin_id, b.location, b.area, b.latitude, b.longitude, b.fill_items, b.last_emptied,
       COALESCE(SUM(d.result = 'Recycling'), 0)                    AS recycling_items,
       COALESCE(SUM(d.result IN ('General waste', 'Unknown')), 0)  AS general_items,   -- Unknown goes in general waste
       COALESCE(SUM(d.result = 'Food waste'), 0)                   AS food_items,
       COALESCE(SUM(d.result = 'Liquids'), 0)                      AS liquid_items,
       COALESCE(SUM(d.result = 'Hazardous'), 0)                    AS hazardous_items
  FROM bins b
  LEFT JOIN drops d ON d.bin_id = b.bin_id
                   AND (b.last_emptied IS NULL OR d.dropped_at > b.last_emptied)
 GROUP BY b.bin_id;

CREATE OR REPLACE VIEW v_bin_status AS
SELECT c.*,
       LEAST(100, ROUND(100 * recycling_items / (SELECT capacity FROM compartments WHERE name = 'Recycling')))     AS recycling_pct,
       LEAST(100, ROUND(100 * general_items   / (SELECT capacity FROM compartments WHERE name = 'General waste'))) AS general_pct,
       LEAST(100, ROUND(100 * food_items      / (SELECT capacity FROM compartments WHERE name = 'Food waste')))    AS food_pct,
       LEAST(100, ROUND(100 * liquid_items    / (SELECT capacity FROM compartments WHERE name = 'Liquids')))       AS liquid_pct,
       LEAST(100, ROUND(100 * hazardous_items / (SELECT capacity FROM compartments WHERE name = 'Hazardous')))     AS hazardous_pct
  FROM v_bin_contents c;

-- Every item in each compartment since the bin was last emptied, numbered in order (1st, 2nd, 3rd ...)
CREATE OR REPLACE VIEW v_compartment_drops AS
SELECT d.bin_id, d.drop_id, d.dropped_at,
       CASE WHEN d.result = 'Unknown' THEN 'General waste' ELSE d.result END AS compartment,
       ROW_NUMBER() OVER (PARTITION BY d.bin_id, CASE WHEN d.result = 'Unknown' THEN 'General waste' ELSE d.result END
                          ORDER BY d.dropped_at, d.drop_id) AS item_no
  FROM drops d
  JOIN bins b ON b.bin_id = d.bin_id
 WHERE b.last_emptied IS NULL OR d.dropped_at > b.last_emptied;

-- Alerts: any compartment at 80% or more (100 = full), with the date and time it reached 80%
CREATE OR REPLACE VIEW v_alerts AS
SELECT a.bin_id, a.location, a.compartment, a.fill_pct, cd.dropped_at AS alert_since
  FROM (SELECT bin_id, location, 'Recycling' AS compartment, recycling_pct AS fill_pct FROM v_bin_status WHERE recycling_pct >= 80
        UNION ALL
        SELECT bin_id, location, 'General waste', general_pct FROM v_bin_status WHERE general_pct >= 80
        UNION ALL
        SELECT bin_id, location, 'Food waste', food_pct FROM v_bin_status WHERE food_pct >= 80
        UNION ALL
        SELECT bin_id, location, 'Liquids', liquid_pct FROM v_bin_status WHERE liquid_pct >= 80
        UNION ALL
        SELECT bin_id, location, 'Hazardous', hazardous_pct FROM v_bin_status WHERE hazardous_pct >= 80) a
  JOIN compartments c ON c.name = a.compartment
  JOIN v_compartment_drops cd ON cd.bin_id = a.bin_id AND cd.compartment = a.compartment
                             AND cd.item_no = CEIL(0.8 * c.capacity)
 ORDER BY a.fill_pct DESC, cd.dropped_at;

-- KPI tiles (one row)
CREATE OR REPLACE VIEW v_kpis AS
SELECT
  (SELECT COUNT(*) FROM drops)                                             AS items_sorted,
  (SELECT ROUND(100 * SUM(result = 'Recycling') / COUNT(*), 1) FROM drops) AS recycling_rate,
  (SELECT COUNT(DISTINCT bin_id) FROM v_alerts)                            AS bins_over_80,
  (SELECT COUNT(*) FROM v_alerts)                                          AS open_alerts,
  (SELECT COUNT(*) FROM support_tickets WHERE status <> 'Closed')          AS open_tickets,
  (SELECT MAX(dropped_at) FROM drops)                                      AS data_up_to;

-- 30-day history chart
CREATE OR REPLACE VIEW v_daily AS
SELECT DATE(dropped_at)               AS day,
       SUM(result = 'Recycling')      AS recycling,
       SUM(result IN ('General waste', 'Unknown')) AS general_waste,
       SUM(result = 'Unknown')        AS unknown,
       SUM(result = 'Food waste')     AS food_waste,
       SUM(result = 'Liquids')        AS liquids,
       SUM(result = 'Hazardous')      AS hazardous
  FROM drops
 GROUP BY DATE(dropped_at)
 ORDER BY day;

-- Packaging breakdown chart (material from the barcode or from what the camera saw)
CREATE OR REPLACE VIEW v_packaging AS
SELECT CASE WHEN d.result = 'Unknown' THEN 'Unknown'
            ELSE COALESCE(p.material, t.material) END AS material,
       d.result,
       COUNT(*) AS items
  FROM drops d
  LEFT JOIN products p   ON p.barcode = d.barcode
  LEFT JOIN item_types t ON t.item_type = d.item_type
 GROUP BY 1, 2
 ORDER BY items DESC;

-- How items were identified (barcode, camera, camera + sensor)
CREATE OR REPLACE VIEW v_detection AS
SELECT detected_by,
       COUNT(*) AS items,
       ROUND(100 * SUM(result = 'Unknown') / COUNT(*), 1) AS unknown_pct,
       ROUND(AVG(confidence), 2) AS avg_confidence
  FROM drops
 GROUP BY detected_by
 ORDER BY items DESC;

-- Producer report for Fly-Tech's sustainability team (Fly-Tech is the technology company we intern at):
-- products thrown away most often in packaging that cannot be recycled or cannot be identified
CREATE OR REPLACE VIEW v_producers AS
SELECT p.brand, p.name AS product, COALESCE(p.material, 'Unknown') AS material,
       d.result, COUNT(*) AS items
  FROM drops d
  JOIN products p ON p.barcode = d.barcode
 WHERE d.result IN ('General waste', 'Unknown')
 GROUP BY p.brand, p.name, p.material, d.result
 ORDER BY items DESC
 LIMIT 10;

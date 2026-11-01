DROP DATABASE IF EXISTS binwise_db;
CREATE DATABASE binwise_db;
USE binwise_db;

-- Leeds City Council green bin rules (one row per material)
CREATE TABLE council_rules (
  material    VARCHAR(40)  PRIMARY KEY,
  examples    VARCHAR(100),
  bin         VARCHAR(20)  NOT NULL,          -- 'Green bin', 'Not green bin', 'Food waste', 'Liquids' or 'Hazardous'
  recyclable  ENUM('Yes','No') NOT NULL
);

-- Products from Open Food Facts / Open Products Facts
-- Barcode is text, not a number, so leading zeros are kept (e.g. 00538077)
CREATE TABLE products (
  barcode   VARCHAR(14)  PRIMARY KEY,
  name      VARCHAR(100) NOT NULL,
  brand     VARCHAR(60)  NOT NULL,
  material  VARCHAR(40)  NULL,                -- NULL or 'Unknown plastic' = cannot classify
  FOREIGN KEY (material) REFERENCES council_rules(material)
);

-- Things the camera can recognise without a barcode (e.g. 'Coffee cup')
CREATE TABLE item_types (
  item_type  VARCHAR(40) PRIMARY KEY,
  material   VARCHAR(40) NOT NULL,
  FOREIGN KEY (material) REFERENCES council_rules(material)
);

-- One row per bin in a public place (Robobin = our first prototype BinWise bin)
CREATE TABLE bins (
  bin_id       INT AUTO_INCREMENT PRIMARY KEY,
  location     VARCHAR(80)  NOT NULL,
  area         VARCHAR(40)  NOT NULL,
  latitude     DECIMAL(8,5),
  longitude    DECIMAL(8,5),
  capacity     INT NOT NULL DEFAULT 150,       -- all compartments together (see the compartments table)
  fill_items   INT NOT NULL DEFAULT 0,         -- items in the bin right now
  last_emptied DATETIME NULL                   -- when staff last opened and emptied it (Robobin records this itself)
);

-- Every item dropped into a bin
CREATE TABLE drops (
  drop_id     INT AUTO_INCREMENT PRIMARY KEY,
  bin_id      INT NOT NULL,
  barcode     VARCHAR(14) NULL,                -- NULL when no barcode was read
  item_type   VARCHAR(40) NULL,                -- what the camera saw, e.g. 'Drinks can'
  detected_by VARCHAR(20) NOT NULL,            -- 'Barcode', 'Camera' or 'Camera + sensor'
  confidence  DECIMAL(3,2) NOT NULL,           -- 0.00 to 1.00; below 0.80 counts as Unknown
  dropped_at  DATETIME NOT NULL,
  result      VARCHAR(20) NOT NULL,            -- 'Recycling', 'General waste', 'Food waste', 'Liquids', 'Hazardous'
                                               -- or 'Unknown' (not sure: goes in the general waste compartment)
  FOREIGN KEY (bin_id) REFERENCES bins(bin_id)
);

-- Robobin's five compartments and how many items each holds (the same for every Robobin)
CREATE TABLE compartments (
  name      VARCHAR(20) PRIMARY KEY,           -- 'Recycling', 'General waste', 'Food waste', 'Liquids', 'Hazardous'
  capacity  INT NOT NULL                       -- items (drinks for Liquids) before it is full
);

-- Support requests from council staff to BinWise (e.g. a camera or sensor needs maintenance)
CREATE TABLE support_tickets (
  ticket_id   INT AUTO_INCREMENT PRIMARY KEY,
  bin_id      INT NOT NULL,
  component   VARCHAR(30)  NOT NULL,          -- 'Barcode scanner', 'Camera', 'Material sensor', 'Liquid sensor', 'Screen', 'Other'
  issue       VARCHAR(500) NOT NULL,
  urgency     ENUM('Low','Medium','High') NOT NULL DEFAULT 'Medium',
  status      ENUM('Open','In progress','Closed') NOT NULL DEFAULT 'Open',
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (bin_id) REFERENCES bins(bin_id)
);

-- Robobin settings that admins can change (calibration and decision thresholds)
CREATE TABLE settings (
  name         VARCHAR(30)  PRIMARY KEY,
  value        DECIMAL(4,2) NOT NULL,
  description  VARCHAR(150) NOT NULL
);

-- ---------- Users and permissions (who can open which page) ----------

-- Three kinds of user
CREATE TABLE roles (
  role_name    VARCHAR(20)  PRIMARY KEY,       -- 'Council staff', 'BinWise staff', 'Fly-Tech staff'
  description  VARCHAR(150) NOT NULL
);

-- Which pages each role can open (one row per role and page)
CREATE TABLE permissions (
  role_name  VARCHAR(20) NOT NULL,
  page       ENUM('dashboard','report','support','simulator','settings') NOT NULL,
  PRIMARY KEY (role_name, page),
  FOREIGN KEY (role_name) REFERENCES roles(role_name)
);

-- People who can log in. The password is never saved: only a SHA-256 hash of salt + password
CREATE TABLE users (
  user_id        INT AUTO_INCREMENT PRIMARY KEY,
  username       VARCHAR(30)  NOT NULL UNIQUE,
  full_name      VARCHAR(60)  NOT NULL,
  role_name      VARCHAR(20)  NOT NULL,
  salt           CHAR(16)     NOT NULL,
  password_hash  CHAR(64)     NOT NULL,
  FOREIGN KEY (role_name) REFERENCES roles(role_name)
);

-- Who is logged in: the website sends the token with every request; it lasts 8 hours
CREATE TABLE sessions (
  token       CHAR(64) PRIMARY KEY,
  user_id     INT NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Holding table for the 30 days of test drops imported from data/drops_history.csv
-- (Workbench: right-click drops_import > Table Data Import Wizard)
CREATE TABLE drops_import (
  bin_id      INT,
  barcode     VARCHAR(14),
  item_type   VARCHAR(40),
  detected_by VARCHAR(20),
  confidence  DECIMAL(3,2),
  dropped_at  DATETIME
);

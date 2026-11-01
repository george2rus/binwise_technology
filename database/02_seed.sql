USE binwise_db;

INSERT INTO council_rules (material, examples, bin, recyclable) VALUES
('PET plastic (1)',      'Drinks bottles, fruit punnets',                 'Green bin',     'Yes'),
('HDPE plastic (2)',     'Milk bottles, shampoo bottles',                 'Green bin',     'Yes'),
('LDPE plastic film (4)','Carrier bags, cling film, cereal and salad bags','Green bin',     'Yes'),
('PP plastic (5)',       'Yoghurt pots, tubs, trays',                     'Green bin',     'Yes'),
('Glass bottle or jar',  'Wine bottles, sauce jars',                      'Green bin',     'Yes'),
('Carton',               'Juice and milk cartons, Tetra Pak',             'Green bin',     'Yes'),
('Metal can',            'Food tins, drinks cans',                        'Green bin',     'Yes'),
('Aerosol',              'Deodorant, cleaning sprays',                    'Green bin',     'Yes'),
('Aluminium foil',       'Foil, takeaway trays',                          'Green bin',     'Yes'),
('Paper',                'Newspapers, letters',                           'Green bin',     'Yes'),
('Cardboard',            'Cereal boxes, delivery boxes',                  'Green bin',     'Yes'),
('Black plastic',        'Ready meal and meat trays',                     'Not green bin', 'No'),
('Compostable plastic',  'Compostable cups and bags',                     'Not green bin', 'No'),
('Foil-lined plastic',   'Crisp packets, pet food pouches',               'Not green bin', 'No'),
('Polystyrene',          'Takeaway boxes, packaging foam',                'Not green bin', 'No'),
('Drinking glass',       'Broken drinking glasses',                       'Not green bin', 'No'),
('Shredded paper',       'Shredded documents',                            'Not green bin', 'No'),
-- Hazardous: never in any household bin (fire risk in bin lorries); take to a battery or vape collection point
('Battery',              'AA, AAA, phone and laptop batteries',           'Hazardous',     'No'),
('Vape',                 'Disposable vapes (contain a lithium battery)',  'Hazardous',     'No'),
-- Robobin's own compartments for food courts and stations
('Food waste',           'Food leftovers, fruit and veg peel',            'Food waste',    'No'),
('Liquid',               'Leftover drinks, coffee, water',                'Liquids',       'No'),
('Paper cup (plastic lined)', 'Takeaway coffee cups',                     'Not green bin', 'No');

-- What the camera can recognise on its own, mapped to a council material
INSERT INTO item_types (item_type, material) VALUES
('Plastic drinks bottle', 'PET plastic (1)'),
('Milk bottle',           'HDPE plastic (2)'),
('Plastic tub or pot',    'PP plastic (5)'),
('Drinks can',            'Metal can'),
('Food tin',              'Metal can'),
('Glass bottle',          'Glass bottle or jar'),
('Drinks carton',         'Carton'),
('Cardboard box',         'Cardboard'),
('Newspaper',             'Paper'),
('Crisp packet',          'Foil-lined plastic'),
('Polystyrene takeaway box', 'Polystyrene'),
('Black plastic tray',    'Black plastic'),
('Compostable cup',       'Compostable plastic'),
('Battery',               'Battery'),
('Vape',                  'Vape'),
('Food leftovers',        'Food waste'),
('Fruit peel',            'Food waste'),
('Leftover drink',        'Liquid'),
('Coffee cup',            'Paper cup (plastic lined)');

-- material = NULL where Open Food Facts does not say which plastic it is
INSERT INTO products (barcode, name, brand, material) VALUES
('5449000000996', 'Coca-Cola 330ml',                            'Coca-Cola',                'Metal can'),
('5000157024671', 'Heinz Beanz in tomato sauce 415g',           'Heinz',                    'Metal can'),
('5000171055675', 'John West tuna chunks with olive oil 120g',  'John West',                'Metal can'),
('5055540004334', 'British semi-skimmed milk 2.272L',           'Ocado',                    'HDPE plastic (2)'),
('50457243',      'Heinz Tomato Ketchup 460g',                  'Heinz',                    'PET plastic (1)'),
('3057640257773', 'Volvic natural mineral water 1.5L',          'Volvic',                   'PET plastic (1)'),
('5740900805408', 'Lurpak blended spread 500g',                 'Lurpak',                   'PP plastic (5)'),
('5740900401099', 'Lurpak Spreadable slightly salted 250g',     'Lurpak',                   NULL),
('00538077',      'Chicken Tikka Masala and Rice 400g',         'Count on Us',              'PP plastic (5)'),
('3033491314834', 'Activia strawberry yoghurt 4 x 125g',        'Activia',                  NULL),
('04886556',      'Dolmio bolognese sauce extra mushroom 320g', 'Dolmio',                   'Glass bottle or jar'),
('5410188029475', 'Tropicana Pure Premium orange juice 1L',     'Tropicana',                'Carton'),
('5010357112061', 'Yorkshire Tea 80 tea bags 250g',             'Taylors of Harrogate',     'Cardboard'),
('5010029000016', 'Weetabix 430g',                              'Weetabix',                 'Cardboard'),
('5000328376677', 'Walkers Ready Salted crisps 6 x 25g',        'Walkers',                  'Foil-lined plastic'),
('5000328347790', 'Walkers Ready Salted crisps 32.5g',          'Walkers',                  'Foil-lined plastic'),
('5054267003378', 'Ribena blackcurrant squash 850ml',           'Ribena',                   NULL),
('8006540994337', 'Fairy Original washing up liquid 654ml',     'Fairy (Procter & Gamble)', 'PET plastic (1)');

-- Four prototype bins in busy public places in Leeds (locations are examples)
-- last_emptied is when staff last emptied each bin before our test data ends (30/10/2026)
INSERT INTO bins (location, area, latitude, longitude, capacity, last_emptied) VALUES
('Trinity Leeds food court',   'City Centre', 53.79630, -1.54470, 150, '2026-10-30 07:00:00'),
('Leeds Station',    'City Centre', 53.79480, -1.54740, 150, '2026-10-27 07:00:00'),
('Kirkgate Market entrance',   'City Centre', 53.79700, -1.54000, 150, '2026-10-27 18:00:00'),
('White Rose Shopping Centre', 'Beeston',     53.75860, -1.57450, 150, '2026-10-29 07:00:00');

-- Robobin's compartments (items each holds before it needs emptying)
INSERT INTO compartments (name, capacity) VALUES
('Recycling',     50),
('General waste', 50),
('Food waste',    20),
('Liquids',       20),
('Hazardous',     10);

-- Robobin settings (admins can change these in the BinWise settings page or with PATCH /settings)
INSERT INTO settings (name, value, description) VALUES
('sort_threshold',      0.80, 'Certainty needed to sort an item; below this it goes to general waste'),
('hazard_threshold',    0.50, 'Certainty from which a battery or vape is treated as hazardous'),
('sensor_confirm',      0.15, 'Certainty added when the material sensor confirms the camera'),
('sensor_disagree',     0.30, 'Certainty taken away when the material sensor disagrees with the camera');

-- ---------- Users and permissions ----------

INSERT INTO roles (role_name, description) VALUES
('Council staff',  'Runs the bins: dashboard and support'),
('BinWise staff',  'Our team: every page, including the simulator and settings'),
('Fly-Tech staff', 'Fly-Tech sustainability team: Fly-Tech report only');

INSERT INTO permissions (role_name, page) VALUES
('Council staff',  'dashboard'),
('Council staff',  'support'),
('BinWise staff',  'dashboard'),
('BinWise staff',  'report'),
('BinWise staff',  'support'),
('BinWise staff',  'simulator'),
('BinWise staff',  'settings'),
('Fly-Tech staff', 'report');

-- Demo users (demo passwords only, change them for a real system)
--   council  / Council2026
--   binwise  / BinWise2026
--   flytech  / FlyTech2026
INSERT INTO users (username, full_name, role_name, salt, password_hash) VALUES
('council', 'Leeds council officer',     'Council staff',  'k3Lp9QzW1xT7mB2v', SHA2(CONCAT('k3Lp9QzW1xT7mB2v', 'Council2026'), 256)),
('binwise', 'BinWise support engineer',  'BinWise staff',  'R8nY4cHs6JdE0aUf', SHA2(CONCAT('R8nY4cHs6JdE0aUf', 'BinWise2026'), 256)),
('flytech', 'Fly-Tech sustainability officer', 'Fly-Tech staff', 'Vt2Gq7WmZ5pK9sLb', SHA2(CONCAT('Vt2Gq7WmZ5pK9sLb', 'FlyTech2026'), 256));

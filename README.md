CPU4106 group project, Team EGA, GBS Leeds, 2026.

BinWise is the technology inside the **Fly-Tech Robobin**, a prototype smart bin we built as interns at Fly-Tech. Robobin has one opening and sorts each item into the right compartment using a barcode scanner, a camera and a material sensor, following each council's rules. BinWise records every drop, so councils can see how full their bins are and reports can be generated to see which brands' packaging is not being recycled.

Supports UN **SDG 12** (Responsible consumption and production) and **SDG 11** (Sustainable cities and communities).

## Team

| Name | Student no. | Role |
|---|---|---|
| George Rus | G1406849 | Scrum Master, Web Developer |
| Elena Bulgaru | G1406852 | Product Owner, UI/UX |
| Augustin Ivanov | G42616 | Database Developer, Tester |

## What's in the repo

| Folder | Contents |
|---|---|
| `database/` | MySQL scripts and test data |
| `api/` | BinWise API (Python, FastAPI) |
| `web/` | Website (HTML, CSS, JavaScript) |
| `docs/` | Diagrams: DFD, ERD, use case, wireframe |

## Database

Run `database/00_build_all.sql` in MySQL Workbench to build everything in one go.

Files 01–06 are the same steps split up, so each part can be read on its own:

| File | What it does |
|---|---|
| `01_schema.sql` | Creates the 13 tables |
| `02_seed.sql` | Adds bins, council rules, products, users and roles |
| `03_logic.sql` | Sorting logic: `classify_item`, `bin_drop` and the `after_drop` trigger that updates fill levels |
| `04_views.sql` | Views the API reads for the dashboard and Fly-Tech report |
| `05_load_history.sql` | Loads the 30 days of test drops (import `data/drops_history.csv` into `drops_import` first, using Workbench's Table Data Import Wizard) |
| `06_tests.sql` | 10 database tests |

The `data/` folder holds the test drops and the spreadsheet used to generate them.

## How to run it

Needs MySQL 8 and Python 3.10 or newer.

1. Build the database (see above).
2. In a terminal, from the `api` folder:
   pip install -r requirements.txt
  $env:DB_PASSWORD="your MySQL password"
  uvicorn main:app --reload
If your MySQL user is not `root`, also set `$env:DB_USER`.
3. Open http://localhost:8000/binwise/login.html
4. API documentation: http://localhost:8000/docs

## Demo logins

| Username | Password | Role | Sees |
|---|---|---|---|
| council | Council2026 | Council staff | Dashboard, support |
| binwise | BinWise2026 | BinWise staff | Every page, including simulator and settings |
| flytech | FlyTech2026 | Fly-Tech staff | Fly-Tech report only |

These are demo passwords only. Each role can only use its own pages, and the API returns 401 (not logged in) or 403 (wrong role) for anything else.

Before a demo, run `CALL reset_demo();` in Workbench to reset the data.

## Use of AI

Claude (AI) was used to help with parts of the code and to generate the test data. We reviewed, ran and tested everything ourselves.

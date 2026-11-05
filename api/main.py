# BinWise API: FastAPI + MySQL
# Built on our MySQL database binwise_db.
# Owner: George (Web Developer). Database: Augustin.
#
# Run (from this api folder):
#   pip install -r requirements.txt
#   set DB_PASSWORD=your MySQL password      (PowerShell: $env:DB_PASSWORD="...")
#   uvicorn main:app --reload
# Then open:
#   http://127.0.0.1:8000/docs       Swagger: try every route
#   http://127.0.0.1:8000/binwise/   the dashboard and the Robobin simulator, served by FastAPI

import os
import secrets
from pathlib import Path
from datetime import date, timedelta
from typing import Literal

import mysql.connector
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

# ---------- 1. App and database set-up ----------

app = FastAPI(title="BinWise API",
              description="Robobin drops, bin status and reports for council staff and Fly-Tech")

DB = {
    "host": os.getenv("DB_HOST", "localhost"),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "binwise_db"),
}


def get_conn():
    # The Python version of db_connection.php
    return mysql.connector.connect(**DB)


def query(sql, params=(), one=False):
    # Run a SELECT and return rows as dictionaries (column name -> value)
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params)
        rows = cur.fetchall()
        if one:
            return rows[0] if rows else None
        return rows
    finally:
        conn.close()


# ---------- Login and permissions ----------
# The website logs in with POST /login and gets a token. It sends the token with every request
# (header "Authorization: Bearer <token>"). Each route says which page it belongs to, and the
# permissions table decides if the user's role can open that page. In /docs, use the Authorize button.

bearer = HTTPBearer(auto_error=False)


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=30)
    password: str = Field(min_length=1, max_length=100)


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if creds is None:
        raise HTTPException(status_code=401, detail="Please log in")
    user = query("""SELECT u.user_id, u.username, u.full_name, u.role_name
                      FROM sessions s JOIN users u ON u.user_id = s.user_id
                     WHERE s.token = %s AND s.created_at > NOW() - INTERVAL 8 HOUR""",
                 (creds.credentials,), one=True)
    if user is None:
        raise HTTPException(status_code=401, detail="Session expired, please log in again")
    rows = query("SELECT page FROM permissions WHERE role_name = %s", (user["role_name"],))
    user["pages"] = [r["page"] for r in rows]
    return user


def allow(*pages):
    # Used on a route: the user's role must have at least one of these pages
    def check(user=Depends(current_user)):
        if not set(pages) & set(user["pages"]):
            raise HTTPException(status_code=403, detail=f"{user['role_name']} cannot use this")
        return user
    return check


@app.post("/login", tags=["Login"])
def login(details: LoginIn):
    user = query("""SELECT user_id, username, full_name, role_name FROM users
                     WHERE username = %s AND password_hash = SHA2(CONCAT(salt, %s), 256)""",
                 (details.username, details.password), one=True)
    if user is None:
        raise HTTPException(status_code=401, detail="Wrong username or password")
    token = secrets.token_hex(32)
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO sessions (token, user_id) VALUES (%s, %s)", (token, user["user_id"]))
        conn.commit()
    finally:
        conn.close()
    rows = query("SELECT page FROM permissions WHERE role_name = %s", (user["role_name"],))
    return {"token": token, **user, "pages": [r["page"] for r in rows]}


@app.get("/me", tags=["Login"])
def who_am_i(user=Depends(current_user)):
    return user


@app.post("/logout", tags=["Login"])
def logout(creds: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if creds is not None:
        conn = get_conn()
        try:
            cur = conn.cursor()
            cur.execute("DELETE FROM sessions WHERE token = %s", (creds.credentials,))
            conn.commit()
        finally:
            conn.close()
    return {"message": "Logged out"}


@app.get("/")
def root():
    return {"message": "BinWise API is running. Open /docs to try it, or /binwise/ for the dashboard."}


# ---------- 2. Reports for the dashboard (GET only) ----------
# Each route reads one of Augustin's views, so the SQL stays in the database.

@app.get("/kpis", tags=["Reports"], dependencies=[Depends(allow("dashboard"))])
def get_kpis():
    return query("SELECT * FROM v_kpis", one=True)


@app.get("/bins", tags=["Reports"], dependencies=[Depends(allow("dashboard", "support", "simulator"))])
def list_bins():
    return query("SELECT * FROM v_bin_status ORDER BY bin_id")


@app.get("/bins/{bin_id}", tags=["Reports"], dependencies=[Depends(allow("dashboard", "simulator"))])
def get_bin(bin_id: int):
    row = query("SELECT * FROM v_bin_status WHERE bin_id = %s", (bin_id,), one=True)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Bin {bin_id} not found")
    return row


@app.get("/alerts", tags=["Reports"], dependencies=[Depends(allow("dashboard"))])
def list_alerts():
    return query("SELECT * FROM v_alerts")


@app.get("/daily", tags=["Reports"], dependencies=[Depends(allow("dashboard"))])
def daily_history():
    return query("SELECT * FROM v_daily")


@app.get("/packaging", tags=["Reports"], dependencies=[Depends(allow("dashboard", "report"))])
def packaging_breakdown():
    return query("SELECT * FROM v_packaging")


@app.get("/producers", tags=["Reports"], dependencies=[Depends(allow("report"))])
def producer_report():
    # Fly-Tech's report: products most often thrown away in non-recyclable or unknown packaging
    return query("SELECT * FROM v_producers")


@app.get("/detection", tags=["Reports"], dependencies=[Depends(allow("dashboard"))])
def detection_summary():
    return query("SELECT * FROM v_detection")


@app.get("/item-types", tags=["Robobin"], dependencies=[Depends(allow("simulator"))])
def list_item_types():
    # What the camera can recognise without a barcode, and which bin its material goes in (used by the simulator)
    return query("""SELECT t.item_type, t.material, r.bin
                      FROM item_types t JOIN council_rules r ON r.material = t.material
                     ORDER BY t.item_type""")


# ---------- 3. Robobin: drop an item, empty a bin ----------

class DropIn(BaseModel):
    bin_id: int = Field(gt=0)
    detected_by: Literal["Barcode", "Camera", "Camera + sensor", "Sensor"]
    barcode: str | None = Field(default=None, pattern=r"^\d{8,14}$")
    item_type: str | None = None
    confidence: float = Field(ge=0, le=1)
    has_liquid: bool = False         # leftover drink inside: drained into the liquids tank first


def compartment(saved):
    # Where the item went, and why, in words for the Robobin screen
    if saved["result"] == "Hazardous":
        return "Hazardous (sealed compartment)"
    if saved["result"] == "Liquids":
        return "Liquids tank"
    if saved["result"] != "Unknown":
        return saved["result"]
    if saved["barcode"] and saved["product"] is None:
        return "General waste (unknown product)"
    if saved["barcode"] and saved["product_material"] is None:
        return "General waste (unknown material)"
    return "General waste (not sure what it is)"


MESSAGE = {"Recycling": "Thank you for recycling!",
           "General waste": "Thank you!",
           "Unknown": "Thank you! We couldn't be sure, so we kept it out of recycling.",
           "Food waste": "Thank you! Food waste becomes compost or energy.",
           "Liquids": "Thank you! Emptying drinks keeps recycling clean.",
           "Hazardous": "Thank you. Batteries and vapes are kept in a sealed compartment because they can start fires."}

# Which column of v_bin_status holds the fill level of the compartment an item went into
PCT_COLUMN = {"Recycling": "recycling_pct", "General waste": "general_pct", "Unknown": "general_pct",
              "Food waste": "food_pct", "Liquids": "liquid_pct", "Hazardous": "hazardous_pct"}


@app.post("/drops", status_code=201, tags=["Robobin"], dependencies=[Depends(allow("simulator"))])
def drop_item(drop: DropIn):
    if drop.detected_by == "Barcode" and not drop.barcode:
        raise HTTPException(status_code=422, detail="A barcode drop needs a barcode")
    if drop.detected_by != "Barcode" and not drop.item_type:
        raise HTTPException(status_code=422, detail="A camera drop needs an item type")

    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute("SELECT bin_id FROM bins WHERE bin_id = %s", (drop.bin_id,))
        if cur.fetchone() is None:
            raise HTTPException(status_code=404, detail=f"Bin {drop.bin_id} not found")

        # Leftover drink inside a cup or bottle: drain it into the liquids tank first
        if drop.has_liquid:
            cur.callproc("bin_drop", (drop.bin_id, None, "Leftover drink", "Sensor", 0.99))

        # Augustin's stored procedure classifies the item and saves it; the trigger adds 1 to the fill level
        cur.callproc("bin_drop", (drop.bin_id, drop.barcode, drop.item_type,
                                  drop.detected_by, drop.confidence))
        conn.commit()

        cur.execute("""SELECT d.drop_id, d.bin_id, d.barcode, d.item_type, d.detected_by,
                              d.confidence, d.dropped_at, d.result, p.name AS product,
                              p.material AS product_material, b.recycling_pct, b.general_pct,
                              b.food_pct, b.liquid_pct, b.hazardous_pct
                         FROM drops d
                         LEFT JOIN products p ON p.barcode = d.barcode
                         JOIN v_bin_status b ON b.bin_id = d.bin_id
                        WHERE d.bin_id = %s
                        ORDER BY d.drop_id DESC LIMIT 1""", (drop.bin_id,))
        saved = cur.fetchone()
    finally:
        conn.close()

    item = saved["product"] or saved["item_type"] or f"Barcode {saved['barcode']}"
    compartment_pct = saved[PCT_COLUMN[saved["result"]]]
    return {
        **saved,
        "item": item,
        "liquid_drained": drop.has_liquid,
        "compartment": compartment(saved),
        "compartment_pct": compartment_pct,
        "alert": compartment_pct >= 80,
        "message": MESSAGE[saved["result"]],
    }


@app.patch("/bins/{bin_id}/empty", tags=["Robobin"], dependencies=[Depends(allow("simulator"))])
def empty_bin(bin_id: int):
    # Called by Robobin itself when staff open it and empty the compartments: every fill level goes back to 0
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE bins SET fill_items = 0, last_emptied = NOW() WHERE bin_id = %s", (bin_id,))
        conn.commit()
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail=f"Bin {bin_id} not found")
    finally:
        conn.close()
    return {"message": f"Bin {bin_id} emptied", "bin": get_bin(bin_id)}


# ---------- 4. Products (admin CRUD, like the shop's items) ----------

class ProductIn(BaseModel):
    barcode: str = Field(pattern=r"^\d{8,14}$")
    name: str = Field(min_length=2, max_length=100)
    brand: str = Field(min_length=1, max_length=60)
    material: str | None = None      # must match a material in council_rules, or None if unknown


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=100)
    brand: str | None = Field(default=None, min_length=1, max_length=60)
    material: str | None = None


def save_errors(err):
    # Turn MySQL errors into clear HTTP status codes
    if err.errno == 1062:
        raise HTTPException(status_code=409, detail="A product with this barcode already exists")
    if err.errno == 1452:
        raise HTTPException(status_code=400, detail="Material is not in the council rules")
    raise err


@app.get("/products", tags=["Products"], dependencies=[Depends(allow("simulator", "settings"))])
def list_products(material: str | None = None):
    if material:
        return query("SELECT * FROM products WHERE material = %s ORDER BY brand, name", (material,))
    return query("SELECT * FROM products ORDER BY brand, name")


@app.get("/products/{barcode}", tags=["Products"], dependencies=[Depends(allow("simulator", "settings"))])
def get_product(barcode: str):
    row = query("SELECT * FROM products WHERE barcode = %s", (barcode,), one=True)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Product {barcode} not found")
    return row


@app.post("/products", status_code=201, tags=["Products"], dependencies=[Depends(allow("settings"))])
def add_product(product: ProductIn):
    conn = get_conn()
    try:
        conn.cursor().execute("INSERT INTO products (barcode, name, brand, material) VALUES (%s, %s, %s, %s)",
                              (product.barcode, product.name, product.brand, product.material))
        conn.commit()
    except mysql.connector.Error as err:
        save_errors(err)
    finally:
        conn.close()
    return {"message": "Product added", "product": get_product(product.barcode)}


@app.put("/products/{barcode}", tags=["Products"], dependencies=[Depends(allow("settings"))])
def replace_product(barcode: str, product: ProductIn):
    get_product(barcode)                                   # 404 if it does not exist
    conn = get_conn()
    try:
        conn.cursor().execute("UPDATE products SET barcode = %s, name = %s, brand = %s, material = %s WHERE barcode = %s",
                              (product.barcode, product.name, product.brand, product.material, barcode))
        conn.commit()
    except mysql.connector.Error as err:
        save_errors(err)
    finally:
        conn.close()
    return {"message": "Product replaced", "product": get_product(product.barcode)}


@app.patch("/products/{barcode}", tags=["Products"], dependencies=[Depends(allow("settings"))])
def update_product(barcode: str, changes: ProductUpdate):
    get_product(barcode)
    fields = changes.model_dump(exclude_unset=True)
    if not fields:
        raise HTTPException(status_code=400, detail="Nothing to change")
    sets = ", ".join(f"{name} = %s" for name in fields)    # names come from the model, not from the user
    conn = get_conn()
    try:
        conn.cursor().execute(f"UPDATE products SET {sets} WHERE barcode = %s", (*fields.values(), barcode))
        conn.commit()
    except mysql.connector.Error as err:
        save_errors(err)
    finally:
        conn.close()
    return {"message": "Product updated", "product": get_product(barcode)}


@app.delete("/products/{barcode}", tags=["Products"], dependencies=[Depends(allow("settings"))])
def delete_product(barcode: str):
    get_product(barcode)
    conn = get_conn()
    try:
        conn.cursor().execute("DELETE FROM products WHERE barcode = %s", (barcode,))
        conn.commit()
    finally:
        conn.close()
    return {"message": f"Product {barcode} deleted"}


# ---------- 5. Fly-Tech report (products and brands in packaging that cannot be recycled) ----------

@app.get("/reports/producers", tags=["Fly-Tech"], dependencies=[Depends(allow("report"))])
def producer_report_for(date_from: date | None = None, date_to: date | None = None,
                        area: str | None = None, top: int = 10):
    date_to = date_to or date.today()
    date_from = date_from or date_to - timedelta(days=30)
    if date_from > date_to:
        raise HTTPException(status_code=400, detail="date_from must be before date_to")
    where = "d.dropped_at >= %s AND d.dropped_at < %s + INTERVAL 1 DAY"
    params = [date_from, date_to]
    if area:
        where += " AND b.area = %s"
        params.append(area)
    base = f"FROM drops d JOIN products p ON p.barcode = d.barcode JOIN bins b ON b.bin_id = d.bin_id WHERE {where}"

    brands = query(f"""SELECT p.brand, COUNT(*) AS items_scanned,
                              SUM(d.result IN ('General waste', 'Unknown')) AS not_recycled,
                              ROUND(100 * SUM(d.result IN ('General waste', 'Unknown')) / COUNT(*), 1) AS not_recycled_pct
                         {base} GROUP BY p.brand HAVING not_recycled > 0
                        ORDER BY not_recycled DESC LIMIT %s""", (*params, top))
    products = query(f"""SELECT p.brand, p.name AS product, COALESCE(p.material, 'Unknown material') AS material,
                                SUM(d.result = 'General waste') AS non_recyclable,
                                SUM(d.result = 'Unknown') AS unknown_material,
                                COUNT(*) AS items
                           {base} AND d.result IN ('General waste', 'Unknown')
                          GROUP BY p.brand, p.name, p.material
                          ORDER BY items DESC LIMIT %s""", (*params, top))
    return {"date_from": date_from, "date_to": date_to, "area": area or "All areas",
            "brands": brands, "products": products}


# ---------- 6. Support requests from council staff ----------

class SupportIn(BaseModel):
    bin_id: int = Field(gt=0)
    component: Literal["Barcode scanner", "Camera", "Material sensor", "Liquid sensor", "Screen", "Other"]
    issue: str = Field(min_length=10, max_length=500)
    urgency: Literal["Low", "Medium", "High"] = "Medium"


class SupportUpdate(BaseModel):
    status: Literal["Open", "In progress", "Closed"]


@app.get("/support", tags=["Support"], dependencies=[Depends(allow("support"))])
def list_tickets(status: str | None = None):
    sql = """SELECT t.*, b.location FROM support_tickets t JOIN bins b ON b.bin_id = t.bin_id"""
    if status:
        return query(sql + " WHERE t.status = %s ORDER BY t.created_at DESC", (status,))
    return query(sql + " ORDER BY t.status = 'Closed', t.created_at DESC")


@app.post("/support", status_code=201, tags=["Support"], dependencies=[Depends(allow("support"))])
def create_ticket(ticket: SupportIn):
    get_bin(ticket.bin_id)                                  # 404 if the bin does not exist
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("INSERT INTO support_tickets (bin_id, component, issue, urgency) VALUES (%s, %s, %s, %s)",
                    (ticket.bin_id, ticket.component, ticket.issue, ticket.urgency))
        conn.commit()
        ticket_id = cur.lastrowid
    finally:
        conn.close()
    return {"message": f"Support request {ticket_id} sent to BinWise", "ticket_id": ticket_id}


@app.patch("/support/{ticket_id}", tags=["Support"], dependencies=[Depends(allow("settings"))])
def update_ticket(ticket_id: int, change: SupportUpdate):
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE support_tickets SET status = %s WHERE ticket_id = %s", (change.status, ticket_id))
        conn.commit()
        if cur.rowcount == 0 and query("SELECT 1 FROM support_tickets WHERE ticket_id = %s", (ticket_id,), one=True) is None:
            raise HTTPException(status_code=404, detail=f"Support request {ticket_id} not found")
    finally:
        conn.close()
    return {"message": f"Support request {ticket_id} is now {change.status}"}


# ---------- 7. Robobin settings (admin) ----------

class SettingsUpdate(BaseModel):
    sort_threshold: float | None = Field(default=None, ge=0.5, le=0.99)
    hazard_threshold: float | None = Field(default=None, ge=0.1, le=0.99)
    sensor_confirm: float | None = Field(default=None, ge=0, le=0.5)
    sensor_disagree: float | None = Field(default=None, ge=0, le=0.5)


@app.get("/settings", tags=["Admin"], dependencies=[Depends(allow("simulator", "settings"))])
def get_settings():
    return {row["name"]: row for row in query("SELECT name, value, description FROM settings ORDER BY name")}


@app.patch("/settings", tags=["Admin"], dependencies=[Depends(allow("settings"))])
def update_settings(changes: SettingsUpdate):
    fields = changes.model_dump(exclude_unset=True, exclude_none=True)
    if not fields:
        raise HTTPException(status_code=400, detail="Nothing to change")
    conn = get_conn()
    try:
        cur = conn.cursor()
        for name, value in fields.items():
            cur.execute("UPDATE settings SET value = %s WHERE name = %s", (value, name))
        conn.commit()
    finally:
        conn.close()
    return {"message": "Settings saved", "settings": get_settings()}


# ---------- 8. Demo tools ----------

@app.post("/demo/reset", tags=["Demo"], dependencies=[Depends(allow("settings"))])
def reset_demo():
    # Puts the database back to the 30 days of test data (CALL reset_demo() in MySQL). Use before the demo.
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.callproc("reset_demo")
        conn.commit()
    except mysql.connector.Error as err:
        raise HTTPException(status_code=500, detail=f"Reset failed: {err.msg}")
    finally:
        conn.close()
    return {"message": "Demo data reset", "kpis": get_kpis()}


# ---------- 9. Serve the front end (keep this at the very bottom) ----------
# The web pages and the API come from the same address, so the browser does not block fetch() (no CORS problem).

WEB_DIR = Path(__file__).resolve().parent.parent / "web"


@app.middleware("http")
async def no_cache_for_pages(request, call_next):
    # Tell the browser not to keep old copies of the pages, so a git pull shows up straight away
    response = await call_next(request)
    if request.url.path.startswith("/binwise"):
        response.headers["Cache-Control"] = "no-store"
    return response


app.mount("/binwise", StaticFiles(directory=WEB_DIR, html=True), name="binwise")

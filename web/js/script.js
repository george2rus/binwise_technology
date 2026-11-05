// ---------- BinWise script.js ----------
// One script file for every page, linked in the head with defer, so it runs
// after the page has loaded. Each section first checks that its page is
// open, so the dashboard code does not run on the settings page and so on.
//
// The data comes from the BinWise API (FastAPI) with fetch(). The API
// answers in JSON, and .then() runs once the answer arrives.
// Open the pages at http://127.0.0.1:8000/binwise/ while uvicorn is running.
// Everyone logs in first (login.html); each role only sees its own pages.


// ---------- 1. SHARED HELPERS ----------

let serverError = "Could not reach the server. Is uvicorn running?";

// Turn "2026-10-27T15:02:48" into "27/10/2026, 15:02"
function niceDate(value) {
  if (value === null || value === undefined) {
    return "Never";
  }
  let date = new Date(value);
  return date.toLocaleString("en-GB", { dateStyle: "short", timeStyle: "short" });
}

// Show a field in red when it is wrong.
// Returns true when the field is fine.
function setValid(id, ok) {
  let group = document.getElementById(id).closest(".form-group");
  if (ok) {
    group.classList.remove("error");
  } else {
    group.classList.add("error");
  }
  return ok;
}

// Send JSON to the API with POST or PATCH
function sendJson(url, method, data) {
  return api(url, {
    method: method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data)
  });
}

// Add the bins to a drop-down list, e.g. "2: Leeds Station"
function fillBinList(selectId, bins) {
  let html = "";
  bins.forEach(function (bin) {
    html = html + '<option value="' + bin.bin_id + '">' + bin.bin_id + ": " + bin.location + "</option>";
  });
  document.getElementById(selectId).innerHTML += html;
}


// ---------- 2. LOGIN AND PERMISSIONS ----------
// After logging in, the API gives a token. It is saved in localStorage so
// it survives moving between pages, and sent with every request.
// GET /me says who is logged in and which pages their role can open:
// links to other pages are hidden, and opening one sends you back.

let token = localStorage.getItem("binwiseToken");

// The page each file belongs to (as in the permissions table)
let pageFiles = {
  dashboard: "index.html",
  report: "report.html",
  support: "support.html",
  simulator: "drop.html",
  settings: "settings.html"
};

// fetch() with the login token added. A 401 answer means the login has
// ended, so go back to the login page.
function api(url, options) {
  if (options === undefined) {
    options = {};
  }
  if (options.headers === undefined) {
    options.headers = {};
  }
  options.headers["Authorization"] = "Bearer " + token;

  return fetch(url, options).then(function (response) {
    if (response.status === 401) {
      localStorage.removeItem("binwiseToken");
      window.location.href = "login.html";
    }
    return response;
  });
}

// The first page this role can open, e.g. Fly-Tech staff go to the report
function firstPage(pages) {
  let names = ["dashboard", "report", "support", "simulator", "settings"];
  let allowed = names.filter(function (name) {
    return pages.indexOf(name) !== -1;
  });
  return pageFiles[allowed[0]];
}

let loginForm = document.getElementById("loginForm");

if (loginForm === null) {

  // Every page except the login page needs someone logged in
  if (token === null) {
    window.location.href = "login.html";
  }

  api("/me")
    .then(function (response) {
      return response.json();
    })
    .then(function (user) {
      // Open a page this role cannot use: go to one it can
      let thisPage = document.body.dataset.page;
      if (user.pages.indexOf(thisPage) === -1) {
        window.location.href = firstPage(user.pages);
        return;
      }

      // Only show the tabs this role can use
      for (let page in pageFiles) {
        if (user.pages.indexOf(page) === -1) {
          document.getElementById("nav-" + page).style.display = "none";
        }
      }
      document.querySelector("nav").style.visibility = "visible";
      document.getElementById("userName").textContent = user.full_name + " (" + user.role_name + ")";
    });

  document.getElementById("logout").addEventListener("click", function () {
    api("/logout", { method: "POST" }).then(function () {
      localStorage.removeItem("binwiseToken");
      window.location.href = "login.html";
    });
  });
}

if (loginForm !== null) {

  loginForm.addEventListener("submit", function (event) {
    event.preventDefault();
    let out = document.getElementById("loginResult");
    let username = document.getElementById("username").value.trim();
    let password = document.getElementById("password").value;

    let ok = setValid("username", username !== "");
    ok = setValid("password", password !== "") && ok;
    if (ok === false) {
      out.textContent = "Please fix the fields in red.";
      return;
    }

    fetch("/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: username, password: password })
    })
      .then(function (response) {
        return response.json();
      })
      .then(function (data) {
        if (data.token === undefined) {
          out.textContent = "Wrong username or password.";
          return;
        }
        localStorage.setItem("binwiseToken", data.token);
        window.location.href = firstPage(data.pages);
      })
      .catch(function () {
        out.textContent = serverError;
      });
  });
}


// ---------- 3. DASHBOARD (index.html) ----------
// GET /bins and GET /alerts, refreshed every 5 seconds.

// Get one list from the API as JSON
function getData(name) {
  return api("/" + name).then(function (response) {
    return response.json();
  });
}

// One compartment cell: a small bar and the %. Amber from 80%, red at 100%.
function compartmentCell(pct, items, colour) {
  let level = "";
  if (pct >= 100) {
    level = "red";
  } else if (pct >= 80) {
    level = "amber";
  }
  let width = Math.min(pct, 100);
  return '<td class="comp ' + level + '" title="' + items + ' items">' +
           '<span class="mini"><span class="' + colour + '" style="width:' + width + '%"></span></span>' + pct + "%" +
         "</td>";
}

function showBins() {
  getData("bins").then(function (bins) {
    let html = "";
    bins.forEach(function (bin) {
      html = html +
        "<tr>" +
          "<td>" + bin.bin_id + "</td>" +
          "<td>" + bin.location + '<br><small class="note">' + bin.area + "</small></td>" +
          compartmentCell(bin.recycling_pct, bin.recycling_items, "recycling") +
          compartmentCell(bin.general_pct, bin.general_items, "general") +
          compartmentCell(bin.food_pct, bin.food_items, "food") +
          compartmentCell(bin.liquid_pct, bin.liquid_items, "liquids") +
          compartmentCell(bin.hazardous_pct, bin.hazardous_items, "hazardous") +
          "<td>" + niceDate(bin.last_emptied) + "</td>" +
        "</tr>";
    });
    document.getElementById("binRows").innerHTML = html;
  });
}

// Each alert shows the date and time the compartment reached 80%
function showAlerts() {
  getData("alerts").then(function (alerts) {
    if (alerts.length === 0) {
      document.getElementById("alertRows").innerHTML = '<tr><td colspan="5" class="note">No compartments over 80%</td></tr>';
      return;
    }

    // Newest alert first
    alerts.sort(function (a, b) {
      return String(b.alert_since).localeCompare(String(a.alert_since));
    });

    let html = "";
    alerts.forEach(function (alert) {
      let action = "Empty soon";
      let rowClass = "";
      if (alert.fill_pct >= 100) {
        action = "Empty now";
        rowClass = "level-100";
      }
      html = html +
        '<tr class="' + rowClass + '">' +
          "<td>" + niceDate(alert.alert_since) + "</td>" +
          "<td>" + alert.bin_id + ": " + alert.location + "</td>" +
          "<td>" + alert.compartment + "</td>" +
          "<td>" + alert.fill_pct + "%</td>" +
          "<td>" + action + "</td>" +
        "</tr>";
    });
    document.getElementById("alertRows").innerHTML = html;
  });
}

if (document.getElementById("binRows") !== null) {
  showBins();
  showAlerts();
  setInterval(function () {
    showBins();
    showAlerts();
  }, 5000);
}


// ---------- 4. FLY-TECH REPORT (report.html) ----------
// GET /reports/producers with the dates, area and how many brands to show.
// The products table can be downloaded as a CSV file.

let reportForm = document.getElementById("reportForm");
let lastReport = null;

// Dates as "2026-10-28", the format a date input uses
function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

function showReport(report) {
  let brandHtml = "";
  report.brands.forEach(function (b) {
    brandHtml = brandHtml +
      "<tr><td>" + b.brand + '</td><td class="num">' + b.items_scanned + '</td><td class="num">' +
      b.not_recycled + '</td><td class="num">' + b.not_recycled_pct + "%</td></tr>";
  });
  if (brandHtml === "") {
    brandHtml = '<tr><td colspan="4" class="note">No items in this period.</td></tr>';
  }
  document.getElementById("brandRows").innerHTML = brandHtml;

  let productHtml = "";
  report.products.forEach(function (p) {
    productHtml = productHtml +
      "<tr><td>" + p.brand + "</td><td>" + p.product + "</td><td>" + p.material + '</td><td class="num">' +
      p.non_recyclable + '</td><td class="num">' + p.unknown_material + '</td><td class="num">' + p.items + "</td></tr>";
  });
  if (productHtml === "") {
    productHtml = '<tr><td colspan="6" class="note">No items in this period.</td></tr>';
  }
  document.getElementById("productRows").innerHTML = productHtml;

  document.getElementById("reportInfo").textContent =
    "Report for " + report.area + ", " + report.date_from + " to " + report.date_to + ".";
}

if (reportForm !== null) {

  // Start with the last 30 days
  let today = new Date();
  let monthAgo = new Date();
  monthAgo.setDate(today.getDate() - 30);
  document.getElementById("dateTo").value = isoDate(today);
  document.getElementById("dateFrom").value = isoDate(monthAgo);

  reportForm.addEventListener("submit", function (event) {
    event.preventDefault();
    let info = document.getElementById("reportInfo");
    let from = document.getElementById("dateFrom").value;
    let to = document.getElementById("dateTo").value;
    let area = document.getElementById("area").value;

    if (setValid("dateTo", from === "" || to === "" || from <= to) === false) {
      info.textContent = "The end date must be after the start date.";
      return;
    }

    let url = "/reports/producers?top=" + document.getElementById("top").value;
    if (from !== "") {
      url = url + "&date_from=" + from;
    }
    if (to !== "") {
      url = url + "&date_to=" + to;
    }
    if (area !== "") {
      url = url + "&area=" + encodeURIComponent(area);
    }

    api(url)
      .then(function (response) {
        return response.json();
      })
      .then(function (data) {
        if (data.detail !== undefined) {
          info.textContent = "Server said: " + JSON.stringify(data.detail);
          return;
        }
        lastReport = data;
        showReport(data);
        document.getElementById("downloadCsv").disabled = false;
      })
      .catch(function () {
        info.textContent = serverError;
      });
  });

  // Build a CSV file from the last report and download it
  document.getElementById("downloadCsv").addEventListener("click", function () {
    let csv = "Brand,Product,Material,Not recyclable,Unknown material,Total\r\n";
    lastReport.products.forEach(function (p) {
      csv = csv + '"' + p.brand + '","' + p.product + '","' + p.material + '",' +
            p.non_recyclable + "," + p.unknown_material + "," + p.items + "\r\n";
    });

    let link = document.createElement("a");
    link.href = "data:text/csv;charset=utf-8," + encodeURIComponent(csv);
    link.download = "binwise-flytech-report-" + lastReport.date_from + "-to-" + lastReport.date_to + ".csv";
    link.click();
  });
}


// ---------- 5. SUPPORT (support.html) ----------
// Council staff report a problem with a Robobin to BinWise.
// GET /bins for the list, GET /support for the requests, POST /support to send one.

let supportForm = document.getElementById("supportForm");

function showTickets() {
  api("/support")
    .then(function (response) {
      return response.json();
    })
    .then(function (tickets) {
      let html = "";
      tickets.forEach(function (t) {
        html = html +
          '<li class="ticket">' +
            "<strong>#" + t.ticket_id + " " + t.component + "</strong> &middot; " + t.location +
            ' <span class="pill urgency-' + t.urgency.toLowerCase() + '">' + t.urgency + "</span>" +
            ' <span class="pill">' + t.status + "</span>" +
            "<br>" + t.issue +
            '<br><small class="note">' + niceDate(t.created_at) + "</small>" +
          "</li>";
      });
      if (html === "") {
        html = '<li class="note">No support requests.</li>';
      }
      document.getElementById("ticketList").innerHTML = html;
    })
    .catch(function () {
      document.getElementById("ticketList").innerHTML = '<li class="note">' + serverError + "</li>";
    });
}

if (supportForm !== null) {

  api("/bins")
    .then(function (response) {
      return response.json();
    })
    .then(function (bins) {
      fillBinList("supportBin", bins);
    });
  showTickets();

  supportForm.addEventListener("submit", function (event) {
    event.preventDefault();
    let out = document.getElementById("supportResult");
    let binId = document.getElementById("supportBin").value;
    let component = document.getElementById("component").value;
    let issue = document.getElementById("issue").value.trim();

    let ok = setValid("supportBin", binId !== "");
    ok = setValid("component", component !== "") && ok;
    ok = setValid("issue", issue.length >= 10) && ok;
    if (ok === false) {
      out.textContent = "Please fix the fields in red.";
      return;
    }

    let ticket = {
      bin_id: Number(binId),
      component: component,
      issue: issue,
      urgency: document.getElementById("urgency").value
    };

    sendJson("/support", "POST", ticket)
      .then(function (response) {
        return response.json();
      })
      .then(function (data) {
        out.textContent = data.message + ".";
        supportForm.reset();
        showTickets();
      })
      .catch(function () {
        out.textContent = serverError;
      });
  });
}


// ---------- 6. SETTINGS (settings.html) ----------
// GET /settings fills the form, PATCH /settings saves it.

let settingsForm = document.getElementById("settingsForm");
let settingNames = ["sort_threshold", "hazard_threshold", "sensor_confirm", "sensor_disagree"];

if (settingsForm !== null) {

  api("/settings")
    .then(function (response) {
      return response.json();
    })
    .then(function (saved) {
      settingNames.forEach(function (name) {
        document.getElementById(name).value = Number(saved[name].value).toFixed(2);
      });
    })
    .catch(function () {
      document.getElementById("result").textContent = serverError;
    });

  settingsForm.addEventListener("submit", function (event) {
    event.preventDefault();
    let result = document.getElementById("result");
    let newSettings = {};
    let ok = true;

    // Each box must be a number between its min and max
    settingNames.forEach(function (name) {
      let input = document.getElementById(name);
      let value = parseFloat(input.value);
      let valid = isNaN(value) === false && value >= Number(input.min) && value <= Number(input.max);
      ok = setValid(name, valid) && ok;
      newSettings[name] = value;
    });
    if (ok === false) {
      result.textContent = "Please fix the fields in red.";
      return;
    }

    sendJson("/settings", "PATCH", newSettings)
      .then(function (response) {
        return response.json();
      })
      .then(function (data) {
        result.textContent = data.message + ". The simulator uses them from the next drop.";
      })
      .catch(function () {
        result.textContent = serverError;
      });
  });
}


// ---------- 7. ROBOBIN SIMULATOR (drop.html) ----------
// Robobin identifies an item in steps, then sends its reading to POST /drops:
//   0. Liquid sensor: leftover drink is drained into the liquids tank first.
//   1. Barcode: a known product with a known material means 100% sure.
//   2. Camera: otherwise the camera guesses the item and how sure it is.
//   3. Material sensor: confirms (more sure), no reading, or disagrees (less sure).
// The database then picks the compartment using the council rules.
// The percentages come from the Settings page.

let dropForm = document.getElementById("dropForm");
let productList = [];   // from GET /products
let itemTypes = [];     // from GET /item-types
let settings = { sort_threshold: 0.8, hazard_threshold: 0.5, sensor_confirm: 0.15, sensor_disagree: 0.3 };

// Quick tests: what the scanner, camera and sensor would read for a real item
let presets = [
  { label: "Coca-Cola can", barcode: "5449000000996", itemType: "Drinks can", camera: 90, sensor: "confirms", liquid: false },
  { label: "Crushed can, no barcode", barcode: "", itemType: "Drinks can", camera: 72, sensor: "confirms", liquid: false },
  { label: "Dirty can, camera unsure", barcode: "", itemType: "Drinks can", camera: 60, sensor: "none", liquid: false },
  { label: "Crisp packet", barcode: "5000328347790", itemType: "Crisp packet", camera: 85, sensor: "confirms", liquid: false },
  { label: "Activia pot, no sensor reading", barcode: "3033491314834", itemType: "Plastic tub or pot", camera: 70, sensor: "none", liquid: false },
  { label: "Food leftovers", barcode: "", itemType: "Food leftovers", camera: 85, sensor: "confirms", liquid: false },
  { label: "Half-full coffee cup", barcode: "", itemType: "Coffee cup", camera: 85, sensor: "confirms", liquid: true },
  { label: "Water bottle with water left", barcode: "3057640257773", itemType: "Plastic drinks bottle", camera: 90, sensor: "confirms", liquid: true },
  { label: "Drink poured in", barcode: "", itemType: "Leftover drink", camera: 90, sensor: "confirms", liquid: false },
  { label: "AA battery", barcode: "", itemType: "Battery", camera: 70, sensor: "confirms", liquid: false }
];

// 0.85 becomes "85%"
function percent(value) {
  return Math.round(value * 100) + "%";
}

function findProduct(barcode) {
  let found = productList.filter(function (p) {
    return p.barcode === barcode;
  });
  return found[0];
}

function findItemType(name) {
  let found = itemTypes.filter(function (t) {
    return t.item_type === name;
  });
  return found[0];
}

// Fill in the form with one of the quick tests
function usePreset(preset) {
  document.getElementById("product").value = preset.barcode;
  document.getElementById("itemType").value = preset.itemType;
  document.getElementById("camera").value = preset.camera;
  document.getElementById("cameraValue").textContent = preset.camera;
  document.getElementById("sensor").value = preset.sensor;
  document.getElementById("hasLiquid").checked = preset.liquid;
  if (document.getElementById("binId").value === "") {
    document.getElementById("binId").value = "1";
  }
}

function showPresets() {
  let html = "";
  presets.forEach(function (preset, i) {
    html = html + '<button type="button" class="preset" id="preset-' + i + '">' + preset.label + "</button>";
  });
  document.getElementById("presets").innerHTML = html;

  // The buttons exist now, so give each one a click event
  presets.forEach(function (preset, i) {
    document.getElementById("preset-" + i).addEventListener("click", function () {
      usePreset(preset);
    });
  });
}

// Load the bins, products, item types and settings from the API
function loadSimulator() {
  api("/bins")
    .then(function (response) { return response.json(); })
    .then(function (bins) {
      fillBinList("binId", bins);
      return api("/products");
    })
    .then(function (response) { return response.json(); })
    .then(function (products) {
      productList = products;
      let html = "";
      products.forEach(function (p) {
        html = html + '<option value="' + p.barcode + '">' + p.name + " (" + p.barcode + ")</option>";
      });
      document.getElementById("product").innerHTML += html;
      return api("/item-types");
    })
    .then(function (response) { return response.json(); })
    .then(function (types) {
      itemTypes = types;
      let html = "";
      types.forEach(function (t) {
        html = html + "<option>" + t.item_type + "</option>";
      });
      document.getElementById("itemType").innerHTML += html;
      return api("/settings");
    })
    .then(function (response) { return response.json(); })
    .then(function (saved) {
      for (let name in saved) {
        settings[name] = Number(saved[name].value);
      }
      showPresets();
    })
    .catch(function () {
      document.getElementById("result").textContent = serverError;
    });
}

// Steps 0 to 3: work out what Robobin sends to the server and explain each step
function identify(barcode, itemType, camera, sensor, hasLiquid) {
  let steps = [];
  let product = findProduct(barcode);

  if (hasLiquid) {
    steps.push("Liquid sensor: leftover drink found, drained into the liquids tank.");
  }

  // 1. Barcode
  if (product !== undefined && product.material !== null) {
    steps.push("Barcode: " + product.name + ", made of " + product.material + ", so 100% sure. Camera and sensor not needed.");
    return { steps: steps, drop: { barcode: barcode, item_type: null, detected_by: "Barcode", confidence: 1, has_liquid: hasLiquid } };
  }
  if (product !== undefined) {
    steps.push("Barcode: " + product.name + ", but its material is unknown. Checking with the camera.");
  } else {
    steps.push("Barcode: none read. Checking with the camera.");
  }

  // 2. Camera
  let certainty = camera / 100;
  steps.push("Camera: looks like a " + itemType.toLowerCase() + " (" + percent(certainty) + " sure).");

  // 3. Material sensor
  let detectedBy = "Camera + sensor";
  if (sensor === "confirms") {
    certainty = Math.min(0.99, certainty + settings.sensor_confirm);
    steps.push("Sensor: material confirmed (+" + percent(settings.sensor_confirm) + "), now " + percent(certainty) + " sure.");
  } else if (sensor === "disagrees") {
    certainty = Math.max(0, certainty - settings.sensor_disagree);
    steps.push("Sensor: material does not match (-" + percent(settings.sensor_disagree) + "), now " + percent(certainty) + " sure.");
  } else {
    detectedBy = "Camera";
    steps.push("Sensor: no reading (wet, dirty or black plastic), still " + percent(certainty) + " sure.");
  }

  // What the database will do with it
  let type = findItemType(itemType);
  if (type !== undefined && type.bin === "Hazardous" && certainty >= settings.hazard_threshold) {
    steps.push("Possible battery or vape: from " + percent(settings.hazard_threshold) + " it goes in the hazardous compartment, for fire safety.");
  } else if (certainty >= settings.sort_threshold) {
    steps.push("At least " + percent(settings.sort_threshold) + " sure: sorted by the council rules.");
  } else {
    steps.push("Under " + percent(settings.sort_threshold) + " sure: general waste, to keep the recycling clean.");
  }

  certainty = Math.round(certainty * 100) / 100;
  if (product === undefined) {
    barcode = null;
  }
  return { steps: steps, drop: { barcode: barcode, item_type: itemType, detected_by: detectedBy, confidence: certainty, has_liquid: hasLiquid } };
}

// Show the answer on the Robobin screen and the steps underneath
function showDrop(steps, data) {
  let colours = { "Recycling": "recycling", "General waste": "general", "Unknown": "general",
                  "Food waste": "food", "Liquids": "liquids", "Hazardous": "hazardous" };
  let detail = data.message;
  if (data.liquid_drained) {
    detail = "Drink emptied into the liquids tank. " + detail;
  }
  document.getElementById("screen").className = "screen " + colours[data.result];
  document.getElementById("screenTitle").textContent = data.compartment;
  document.getElementById("screenDetail").textContent = detail;

  steps.push("Server: saved as drop " + data.drop_id + ", compartment: " + data.compartment + ".");
  let html = "";
  steps.forEach(function (step) {
    html = html + "<li>" + step + "</li>";
  });
  document.getElementById("steps").innerHTML = html;

  let name = data.result;
  if (name === "Unknown") {
    name = "General waste";
  }
  let text = "Bin " + data.bin_id + ": the " + name + " compartment is now " + data.compartment_pct + "% full.";
  if (data.alert) {
    text = text + " The dashboard shows an alert to empty it soon.";
  }
  document.getElementById("result").textContent = text;
}

if (dropForm !== null) {

  loadSimulator();

  document.getElementById("camera").addEventListener("input", function () {
    document.getElementById("cameraValue").textContent = this.value;
  });

  dropForm.addEventListener("submit", function (event) {
    event.preventDefault();
    let result = document.getElementById("result");
    let binId = document.getElementById("binId").value;
    let barcode = document.getElementById("product").value;
    let itemType = document.getElementById("itemType").value;

    // The camera is only needed when the barcode is not enough
    let product = findProduct(barcode);
    let needsCamera = product === undefined || product.material === null;

    let ok = setValid("binId", binId !== "");
    ok = setValid("itemType", needsCamera === false || itemType !== "") && ok;
    if (ok === false) {
      result.textContent = "Please fix the fields in red.";
      return;
    }

    let answer = identify(barcode, itemType,
                          Number(document.getElementById("camera").value),
                          document.getElementById("sensor").value,
                          document.getElementById("hasLiquid").checked);
    answer.drop.bin_id = Number(binId);

    sendJson("/drops", "POST", answer.drop)
      .then(function (response) {
        return response.json();
      })
      .then(function (data) {
        showDrop(answer.steps, data);
      })
      .catch(function () {
        result.textContent = serverError;
      });
  });

  // When staff open Robobin and empty it, its software resets every compartment to 0%
  document.getElementById("emptyBin").addEventListener("click", function () {
    let binId = document.getElementById("binId").value;
    if (setValid("binId", binId !== "") === false) {
      document.getElementById("result").textContent = "Choose the bin first.";
      return;
    }
    api("/bins/" + binId + "/empty", { method: "PATCH" })
      .then(function (response) {
        return response.json();
      })
      .then(function (data) {
        document.getElementById("result").textContent = data.message + ": all compartments are back to 0%.";
      })
      .catch(function () {
        document.getElementById("result").textContent = serverError;
      });
  });
}

# Capabilities.md — Functional Intelligence

> Business logic deep-dives for the two most complex engines in the Unified pipeline.

---

## 1. The Abbott Factor Conversion Engine

**File**: `fct_Relex_UK.pq` (lines 80–144)

### What It Does

AAH (the wholesaler) reports quantities in **AAH pack sizes**. Abbott's internal reporting uses **Abbott pack sizes**. The "Abbott Factor" converts between them.

### Data Flow

```mermaid
graph LR
    A["AAH Bible.xlsx"] --> B["dim_ValidationFactor"]
    B --> C["Record.FromTable lookup"]
    C --> D["fct_Relex_UK: WithAllABB step"]
```

1. `dim_ValidationFactor.pq` loads the `Validations Conversion Factor` sheet from `AAH Bible.xlsx`
2. The sheet maps `AAH Packsize` → `Abbott Factor` (a numeric multiplier)
3. In `fct_Relex_UK`, this is converted to a `Record.FromTable` lookup for O(1) access
4. 8 AAH columns are multiplied by the factor to produce 8 ABB columns:

| AAH Column | ABB Column |
|:---|:---|
| `AAH On Hand AAH` | `AAH On Hand ABB` |
| `AAH Open Orders AAH` | `AAH Open Orders ABB` |
| `AAH SOQ Today AAH` | `AAH SOQ Today ABB` |
| `AAH SOQ Next 7 Day AAH` | `AAH SOQ Next 7 Day ABB` |
| `AAH Forecast 14 Days AAH` | `AAH Forecast 14 Days ABB` |
| `AAH Sales Quantity Last 30 Days AAH` | `AAH Sales Quantity Last 30 Days ABB` |
| `AAH Sales Quantity Month -1 AAH` | `AAH Sales Quantity Month -1 ABB` |
| `AAH Sales Quantity Month -2 AAH` | `AAH Sales Quantity Month -2 ABB` |

### Formula

```
ABB Value = AAH Value × Abbott Factor
```

Where `Abbott Factor = Record.FieldOrDefault(ValRecord, [AAH Pack Size AAH], null)`.

> [!IMPORTANT]
> If the pack size is not found in the lookup, the factor is `null` and **all 8 ABB columns will be `null`** for that row. This is by design — it signals a missing mapping.

### Type Restoration

The `Table.FromRecords(Table.TransformRows(...))` pattern strips all column types. The `ReTyped` step (line 119) restores 30 column types. **Both the WithAllABB and ReTyped steps must stay in sync.**

---

## 2. The Inbound Status Engine

**Files**: `fct_Warehouse_Inbound.pq`, `fct_Wholesaler_Inbound.pq`

### What It Does

Classifies every inbound shipment into a time-relative status bucket based on the expected delivery date compared to "today" (`DateTime.LocalNow()`).

### Parameters

| Parameter | Default | Controls |
|:---|:---|:---|
| `MonthsBack` | `-2` | Minimum ETD window (months from today) |
| `MonthsForward` | `6` | Maximum ETD window (months from today) |

### Week Calculation Logic

```
CurrentDate = DateTime.Date(DateTime.LocalNow())
WeekNumber = (number of complete 7-day periods between CurrentDate and ExpectedDeliveryDate)
```

### Status Classification

| Condition | Status Label |
|:---|:---|
| `WeekNumber < 0` | `"Delivered"` |
| `WeekNumber = 0` | `"Inbound - Current Week"` |
| `WeekNumber = 1` | `"Inbound - Next Week"` |
| `WeekNumber = 2` | `"Inbound - 2 Weeks"` |
| `WeekNumber ≥ 15` | `"Older than 2 Weeks"` |
| *otherwise* | `"Inbound - " & Text.From(WeekNumber) & " Weeks"` |

### Expected Delivery Date (Forwarder-Specific)

Different forwarders have different contractual delivery windows:

| Forwarder | Warehouse File | Wholesaler File | Rule |
|:---|:---|:---|:---|
| `NOUWENS` | ETD + 1 day | *(not used)* | `Date.AddDays(etdDate, 1)` |
| `ESSERS` | *(not used)* | ETD + 5 days | `Date.AddDays(etd, 5)` |
| `A2B` | *(not used)* | A2B Expected Delivery Date | From `stg_Inbound_A2B` join |
| *Unknown* | `null` | `null` | No expected date → `null` status |

### Defensive Coercions

Both files use `try Date.From(...) otherwise null` for ETD and date fields to handle dirty data gracefully.

---

## 3. The Weekday Order Plan Engine

**File**: `fct_Relex_UK.pq` (lines 146–187)

### What It Does

For each product-location row, determines which days of the week are Order days and which are Delivery days based on the AAH supply logistics schedule.

### Inputs

- `[SL] Order (Mon)` through `[SL] Order (Fri)` — binary flags (1 = order day)
- `AAH Lead Time AAH` — number of days from order to delivery

### Algorithm

1. Read the 5 order-day flags → find indices where flag = 1
2. For each order index, calculate delivery index: `(orderIndex + leadTime) mod 7`
3. If `ShiftWeekendToMonday = true`: any delivery on index 5 (Saturday) or 6 (Sunday) → shifted to 0 (Monday)
4. Output 5 columns: `Monday` through `Friday`, each containing:
   - `"Order & Deliver"` — both order and delivery happen on this day
   - `"Order"` — order only
   - `"Deliver"` — delivery only
   - `null` — neither

---

## 4. The OnOrder Pipeline

**Files**: `fct_Warehouse_Inbound.pq` → `stg_OnOrder.pq` → `fct_Inventory_Batch.pq`

### What It Does

Extracts "on order" quantities (shipments arriving this week or next) from the inbound pipeline and feeds them into the inventory batch report.

### Flow

```
fct_Warehouse_Inbound
    → Filter: Inbound Status IN ("Inbound - Current Week", "Inbound - Next Week")
    → Group by {Warehouse, ECC CODE} → Sum Units
    → Left Join into fct_Inventory_Batch as "OnOrderQty"
```

> [!NOTE]
> `stg_OnOrder` is named as a staging query but depends on a fact query. This is a known naming exception because it derives from `fct_Warehouse_Inbound` rather than a raw file.

---

## 5. QC Inventory Expiry

**File**: `qc_Inventory_Expiry.pq`

### What It Does

Filters `fct_Inventory_Batch` into 3 vertical slices for inventory expiry monitoring:

| Category | Filter Logic |
|:---|:---|
| OOP – Adult | `ADULT/PAED = "ADULT"` AND `REIMBURSED/OOP = "OOP"` |
| OOP – Paed | `ADULT/PAED = "PEDIATRIC"` AND `REIMBURSED/OOP = "OOP"` |
| Reimbursed | `ADULT/PAED = "ADULT"` AND `REIMBURSED/OOP = "REIMBURSED"` AND `GROWTH DRIVER ≠ "OTHER MISC"` |

Results are combined with a `QC Category` label column.

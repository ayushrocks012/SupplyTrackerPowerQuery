# DataQuality.md — Type Standards, Validation, and Error Handling

> Data type consistency is the most common source of silent failures in Power Query. This document defines the type standards and defensive patterns used across the Unified pipeline.

---

## 1. Type Standards by Column

### Product Identifiers (Always `type text`)

| Column | Type | Rationale |
|:---|:---|:---|
| `Product Code` / `Material` | `type text` | ECC codes can have leading zeros |
| `ECC CODE` | `type text` | SAP material — must not lose leading zeros |
| `LOCAL ITEM NBR` | `type text` | May contain alphanumeric characters |
| `1-6-3-3` | `type text` | Contains hyphens |
| `SHORT 1633` | `type text` | Numeric-looking but used as a join key |
| `PIP code` | `type text` | NHS pharmacy code — may contain non-numeric values |
| `AAH Product Code` | `type text` | Wholesaler system ID |
| `Batch` | `type text` | SAP batch number |
| `Sku ID` | `type text` | Wholesaler SKU identifier |

> [!WARNING]
> Never type a product identifier as `Int64.Type` or `type number`. This silently removes leading zeros and breaks joins.

### Quantities (Always `Int64.Type`)

| Column | Type | Files |
|:---|:---|:---|
| `Available stock` / `Pick quantity` | `Int64.Type` | `stg_Inv_AUK.pq` |
| `Net Inventory` | `Int64.Type` | `stg_Inv_AUL.pq` |
| `Qty` / `Qty Alloc` | `Int64.Type` | `stg_Inv_AUL_Batch.pq` |
| `Qty Ordered` / `Qty Picked` / `Qty Shipped` | `Int64.Type` | `stg_Shipped_PrevDay.pq` |
| `AAH On Hand AAH` / `AAH Open Orders AAH` | `Int64.Type` | `fct_Relex_UK.pq` |
| `Units` | `Int64.Type` | `fct_Warehouse_Inbound.pq` |

### Calculated Quantities (Always `type number`)

| Column | Type | Rationale |
|:---|:---|:---|
| `AAH On Hand ABB` (and all ABB columns) | `type number` | Result of multiplication by factor (may be fractional) |
| `Months to Sell` | `type number` | Division result |
| `AAH Forecast Daily AAH/ABB` | `type number` | Division by 14 |
| `CurrMonthADS` | `type number` | Average daily sales |

### Dates (Always `type date`)

| Column | Type | Files |
|:---|:---|:---|
| `ETD` | `type date` | `stg_UK_Departures.pq` |
| `Collection Date` / `Expected Delivery Date` | `type date` | `stg_Inbound_A2B.pq` |
| `Shipped Date` / `Ship By Date` | `type date` | `stg_Shipped_PrevDay.pq` |
| `Expiry` / `SLED/BBD` | `type date` | `stg_Inv_AUK_Batch.pq`, `stg_Inv_AUL_Batch.pq` |
| `Last Ship Date` | `type date` | `fct_Inventory_Batch.pq` |
| `Product-location Block Start/End Date` | `type date` | `fct_Relex_UK.pq` |

---

## 2. Defensive Patterns

### Pattern 1: `try ... otherwise null`

Used for date coercion on potentially dirty data.

```powerquery
// GOOD — defensive
WithDelivery = Table.AddColumn(..., each try Date.From([ETD]) otherwise null, type date)

// BAD — will crash on blank/text/error cells
WithDelivery = Table.AddColumn(..., each Date.From([ETD]), type date)
```

**Applied in:**
- `fct_Warehouse_Inbound.pq` — ETD, Collection Date, Arrival Schedule Date
- `fct_Inventory_Batch.pq` — Days to Expiry, Months to Sell, Last Ship Date

### Pattern 2: `try Number.From(...) otherwise null`

Used for numeric coercion when source may be text or blank.

```powerquery
ssl = try Number.From([SHIP SHELF LIFE]) otherwise null
```

**Applied in:**
- `fct_Inventory_Batch.pq` — SHIP SHELF LIFE in both WithMTS and WithLastShipDate steps
- `fct_Relex_UK.pq` — Abbott Factor, Lead Time

### Pattern 3: `MissingField.Ignore`

Used when columns may not exist in the source (schema evolution protection).

```powerquery
Table.SelectColumns(table, {"Col1", "Col2"}, MissingField.Ignore)
Table.RenameColumns(table, {{"Old", "New"}}, MissingField.Ignore)
```

**Applied in:**
- `stg_Inv_AUL.pq` — `ship_shelf_life` may not exist
- `fct_Relex_UK.pq` — renames, selects, and removes

### Pattern 4: `Record.FieldOrDefault(row, fieldName, default)`

Used inside `Table.TransformRows` for robustfield access.

```powerquery
packSize = Record.FieldOrDefault(row, "AAH Pack Size AAH", null)
```

**Applied in:**
- `fct_Relex_UK.pq` — WithAllABB and WeekPlanFromRow functions

### Pattern 5: Sentinel Values for Unknown Mappings

When a storage type or lock code doesn't match any known value:

```powerquery
else "NEW STORAGE TYPE TO BE DECIDED"   // AUK
else "NEW LOCK CODE TO BE ADDED"        // AUL
else "NEW STORAGE BIN TO BE DECIDED"    // AUK Batch
```

These sentinel values will appear in reports, flagging unmapped codes for manual investigation.

### Pattern 6: Type Before Group

Always cast columns to their correct type before using them in `List.Sum` or `List.Max`:

```powerquery
// GOOD — type first, then group
Typed = Table.TransformColumnTypes(Selected, {{"Net Inventory", Int64.Type}})
Grouped = Table.Group(Typed, ..., {{"Net Inventory", each List.Sum([Net Inventory]), ...}})

// BAD — text values will concatenate instead of summing
Grouped = Table.Group(RawData, ..., {{"Net Inventory", each List.Sum([Net Inventory]), ...}})
```

**Applied in:**
- `stg_Inv_AUL.pq` — `Net Inventory` typed before GroupBy
- `stg_Shipped_PrevDay.pq` — quantities and dates typed before output

---

## 3. Summary Row Exclusion

Source Excel files often include summary/total rows. These must be filtered out:

| File | Filter Logic |
|:---|:---|
| `stg_UK_Departures.pq` | `[ETD] <> "Grand Total" and [ETD] <> "Total" and [DEPARTURE] <> "Grand Total"` |
| `stg_Inv_AUK.pq` | Empty-row removal via `List.RemoveMatchingItems` pattern |
| `stg_Inv_AUL.pq` | Relies on source table not having totals |

---

## 4. Type Restoration After `Table.FromRecords`

> [!CAUTION]
> `Table.FromRecords(Table.TransformRows(...))` strips ALL column types, reverting everything to `type any`.

This pattern is used for performance in:
- `stg_Inv_AUK_Batch.pq` — single-pass enrichment
- `stg_Inv_AUL_Batch.pq` — single-pass enrichment  
- `fct_Relex_UK.pq` — Abbott Factor calculation

**In `fct_Relex_UK.pq`**, this is mitigated by the `ReTyped` step which re-applies 30 column types. In the batch staging queries, the downstream `fct_Inventory_Batch.pq` handles typing.

> [!IMPORTANT]
> If you add columns in the `Table.TransformRows` block, you MUST also add their types to the `ReTyped` step.

---

## 5. Known Data Quality Risks

| Risk | Severity | Mitigation |
|:---|:---|:---|
| SHIP SHELF LIFE is blank/text in SKU Bible V3 | Medium | `try Number.From()` guards in `fct_Inventory_Batch.pq` |
| Expiry dates are error/blank in source Excel | Medium | `try Date.From()` guards |
| A2B Reference contains NBSP or control chars | High | Full normalization in `stg_Inbound_A2B.pq` (lines 10-24) |
| New storage types appear in SAP | Low | Sentinel values surface in reports |
| PIP code contains non-numeric values | Low | Typed as `type text` (not `Int64.Type`) |
| `Table.FromRecords` strips types in `fct_Relex_UK` | Medium | `ReTyped` step restores them — must be kept in sync |
| CSV encoding mismatch for A2B file | Low | Hardcoded `Encoding=1252` matches current source |

# AGENTS.md — Technical Context for AI Agents

> This file provides the rules, constraints, and institutional knowledge required
> to safely modify the Power Query M-code in `Unified/`.

---

## 1. Architecture Rules

### Naming Convention

| Prefix | Purpose | Example |
|:---|:---|:---|
| `fn_` | Shared helper functions | `fn_SharePointBase.pq`, `fn_GetLatestFile.pq` |
| `base_` | Buffered raw data (shared across queries) | `base_LX02_Raw.pq` |
| `dim_` | Dimension / master data | `dim_SKUBible_V2.pq` |
| `stg_` | Staging (load → clean → type) | `stg_UK_Departures.pq` |
| `fct_` | Fact queries (joins, calcs, output) | `fct_Warehouse_Inbound.pq` |
| `qc_` | Quality-control / diagnostics | `qc_Inventory_Expiry.pq` |

### Mandatory Patterns

1. **Single SharePoint entry point**: All SharePoint access MUST go through `fn_SharePointBase.pq`. Never call `SharePoint.Contents()` or `SharePoint.Files()` directly in a staging or fact query.
2. **Shared file picker**: Use `fn_GetLatestFile(folder, startsWith, endsWith)` to find the latest file. Never inline the sort-by-date-modified logic.
3. **All joins MUST be `JoinKind.LeftOuter`** unless explicitly documented otherwise. The legacy codebase used `LeftOuter` universally. Changing join kind silently drops rows.
4. **Never use `Table.Buffer()` at the output position** of a query (i.e., as the final `in` expression). Output buffers hide per-row errors and make debugging impossible. `Table.Buffer()` is allowed **inline** for specific join optimization (e.g., buffering a small table before it's used in a `Record.FromTable` lookup or before multiple filter passes).
5. **Legacy folders are read-only**: `Warehouse Tracker/` and `Wholesaler Tracker/` exist only for audit reference. Never modify them.

---

## 2. Product Identity Hierarchy

```
LOCAL ITEM NBR   (finest grain — canonical business ID)
   └── 1-6-3-3   (product group — multiple LOCAL ITEM NBR per 1-6-3-3)
       └── SHORT 1633   (compact variant of 1-6-3-3)
           └── ECC CODE   (SAP material number — used in warehouse/inventory joins)
               └── Product Code   (warehouse system ID — equivalent to ECC CODE)
```

- Join `stg_MergedData` to dimensions on `LOCAL ITEM NBR` → `LOCAL ITEM NBR`
- Join `fct_Inventory_Batch` to dimensions on `{Product Code, Warehouse}` → `{ECC CODE, PLANT CODE}`
- Join `fct_Warehouse_Inbound` to dimensions on `1633 Item Code` → `SHORT 1633`

**PLANT CODE** values are warehouse codes: `"075-UK"`, `"075-UL"`.

---

## 3. SKU Bible Versions

| Version | File | Has PLANT CODE? | Has SHIP SHELF LIFE by plant? | Used By |
|:---|:---|:---|:---|:---|
| V2 | `SKU Bible V2.xlsx` | No | No | `stg_MergedData`, `fct_Relex_UK` |
| V3 | `SKU Bible V3.xlsx` | **Yes** | **Yes** | `fct_Inventory_Batch`, `fct_Warehouse_Inbound` |

V3 exists because `SHIP SHELF LIFE` varies by warehouse (plant). V2 is product-level only.

---

## 4. Fragile / Changeable Business Logic

> [!WARNING]
> These values are contractual SLAs or configurable preferences. If the business
> says "the number changed," these are the lines to update.

### Forwarder SLAs

| Forwarder | Current Rule | File | Line to Change |
|:---|:---|:---|:---|
| `NOUWENS` | ETD + **1** day | `fct_Warehouse_Inbound.pq` | `Date.AddDays(etdDate, 1)` |
| `ESSERS` | ETD + **5** days | `fct_Wholesaler_Inbound.pq` | `Date.AddDays(etd, 5)` |

**New forwarders will appear.** When they do, add their rule to the appropriate `if/else` chain. A `null` result means "no expected date" which cascades to `null` Inbound Status.

### Weekend Shift

```
fct_Relex_UK.pq → ShiftWeekendToMonday = true
```

This is a configurable boolean. If the business asks for Saturday delivery support, set to `false`.

### Date Window

Both `fct_Warehouse_Inbound` and `fct_Wholesaler_Inbound` filter ETD within:
```
MonthsBack = -2
MonthsForward = 6
```

### "Months to Sell" Formula

```
(Days to Expiry - SHIP SHELF LIFE) / 30
```

This is "months of sellable shelf life," NOT "months of stock coverage." Do not confuse with inventory ÷ demand.

---

## 5. Data Source Contracts

### Guaranteed by upstream systems

- **File extensions are stable**: `.xlsx` files will not become `.xls` and vice versa.
- **File naming prefixes are stable**: `fn_GetLatestFile` relies on `Text.StartsWith`. Prefixes will not change without notice.
- **Folder hygiene is enforced**: No backup files will appear in SharePoint folders. The "latest by date modified" pattern is safe.
- **Single SharePoint site**: All data lives under `https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/`.

### NOT guaranteed

- Forwarder names and SLA days (contractual, can change).
- Lock Codes in AUL inventory (new codes may appear → map to `"NEW LOCK CODE TO BE ADDED"`).
- Storage Types in AUK inventory (new types → map to `"NEW STORAGE TYPE TO BE DECIDED"`).
- Column headers in source Excel files (if upstream systems change export templates).

---

## 6. Column Mapping: Legacy → Unified

### Warehouse Tracker

| Legacy Query | Legacy Column | Unified Query | Unified Column |
|:---|:---|:---|:---|
| `AUK_Inv_SKU` | `Material` | `stg_Inv_AUK` | `Product Code` |
| `AUK_Inv_SKU` | `Available stock` | `stg_Inv_AUK` | `Stock` |
| `AUK_Inv_SKU` | `Pick quantity` | `stg_Inv_AUK` | `Pick Qty` |
| `AUK_Inv_SKU` | `SLED/BBD` | `stg_Inv_AUK` | `Expiry` |
| `AUL_Inv_SKU` | `SKU ID` | `stg_Inv_AUL` | `Product Code` |
| `AUL_Inv_SKU` | `x_qty_available` | `stg_Inv_AUL` | `Net Inventory` |
| `AUL_Inv_SKU` | `New Inventory` | `stg_Inv_AUL` | `Net Inventory` |
| `Total_Inv_Batch` | `OnOrderQty.1` | `fct_Inventory_Batch` | `OnOrderQty` |
| `Total_Inv_Batch` | `CurrMonthADS.1` | `fct_Inventory_Batch` | `CurrMonthADS` |
| `PBI Warehouse` | `GIT Value (£)` | `fct_Warehouse_Inbound` | `GIT Value (€)` |
| `PBI Warehouse` | `A2B Summary` | `fct_Warehouse_Inbound` | `A2B_Table` |

### Wholesaler Tracker

| Legacy Query | Legacy Column | Unified Query | Unified Column |
|:---|:---|:---|:---|
| `Relex_UK` | `Location name` | `fct_Relex_UK` | `AAH Warehouse Name` |
| `Relex_UK` | `Location code` | `fct_Relex_UK` | `AAH Warehouse Code` |
| `Relex_UK` | `Product code` | `fct_Relex_UK` | `AAH Product Code` |
| `Relex_UK` | `End balance` | `fct_Relex_UK` | `AAH On Hand AAH` |
| `Relex_UK` | `Factor` | `dim_ValidationFactor` | `Abbott Factor` |
| `Relex_UK` | `Row Labels` | `dim_ValidationFactor` | `AAH Packsize` |
| `Relex_UK` | `SUB-BRAND` | `fct_Relex_UK` | `SUB-BAND` |
| `Prev_Day` | `Town` (from join) | `stg_Shipped_PrevDay` | `Town` |
| `InProgress` | `Town.1` (renamed) | `stg_InProgress` | `Town` |

---

## 7. Storage Type / Lock Code Mappings

### AUK (SAP WM — Storage Type codes)

| Storage Type | Combined Storage Type | Combined Storage Bin |
|:---|:---|:---|
| `014`, `011`, `802` | AVAILABLE | AVAILABLE |
| `200`, `916` | ALLOCATED | ALLOCATED |
| `922` | BLOCKED | BLOCKED |
| `904`, `999` | SCHROTT | *(varies by Storage Bin)* |

### AUL (Third-party — Lock Code)

| Lock Code | Zone | Combined Storage Type | Combined Storage Bin |
|:---|:---|:---|:---|
| `""` | `DESPATCH` | ALLOCATED | ALLOCATED |
| `""` | `Goodsin` | RECEIPT | AVAILABLE |
| `BLOCKED` | contains `RESCOPK` | RESERVED FOR COPACK | *(active rule)* |
| `""` | *(other)* | AVAILABLE | AVAILABLE |
| `SHORTDATE` | | SCHROTT | SHORTDATE |
| `DMGD` | | SCHROTT | DAMAGED |
| `QCHOLD` | | SCHROTT | QA BLOCKED |
| `BLOCKED` | | SCHROTT | RETURN BLOCKED |
| `EXPD` | | SCHROTT | EXPIRED |
| `SCRAP` | | SCHROTT | SCRAP |

---

## 8. Optimization Techniques Applied

These patterns were applied during the Phase 1–2 refactoring and should be maintained:

1. **Single SharePoint crawl** (`fn_SharePointBase`): Reduces REST API calls from 17 → 1.
2. **Shared buffered sources** (`base_LX02_Raw`): Eliminates duplicate file downloads.
3. **`Table.TransformRows` batching**: Replaces chains of 4–8 `Table.AddColumn` calls with a single pass to reduce intermediate table creation.
4. **Schema pruning** (`Table.SelectColumns` early): Drop unused columns before joins.
5. **No output-position `Table.Buffer()`**: Removed from all queries to surface per-row errors during debugging.
6. **`Record.FromTable` lookups**: Replaces `Table.NestedJoin` for small validation tables (e.g., `ValidationFactor`).
7. **No unnecessary `Table.Sort`**: Sorting is deferred to the visual layer (Excel/Power BI) except where business logic requires it (e.g., `fct_Inventory_Batch` orders by Expiry for the Index column).

---

## 9. Refresh Environment

- **Runtime**: Power Query inside Excel Desktop, refreshed manually.
- **Time zone**: `DateTime.LocalNow()` returns the user's local machine time (typically UK / GMT+0 or BST+1).
- **Dependency resolution**: Automatic — Power Query evaluates the dependency graph internally.
- **No gateway, no scheduled refresh, no Dataflows.**

---

## 10. Wholesaler Scope

- Currently **AAH (Alliance Healthcare)** is the only wholesaler.
- All Wholesaler-side queries hard-filter for `Text.Contains([Name], "AAH")`.
- If a new wholesaler is added, build a **parallel pipeline** — do not try to generalize the existing AAH-specific logic.

---

## 11. Known Technical Debt

| Area | Description | Risk |
|:---|:---|:---|
| `qc_Inventory_Expiry` | Loaded to Excel tables but not actively consumed by reports yet | Low — diagnostic query |
| `Errors in Inventory Expiry` | Legacy query was never actively monitored; not ported to Unified | Low — can remain deferred |
| `AUL_TagIds_Only` | Legacy tag-level detail query; not ported | Low — only for ad-hoc warehouse investigation |
| `fct_Relex_UK` size | At 206 lines, this is the largest query. If it grows further, consider splitting into `stg_Relex_Raw` + `fct_Relex_UK` | Medium |
| `GIT Value` column name | The `€` symbol may render differently across locales. If issues arise, switch to ASCII-safe `"GIT Value"` | Low |

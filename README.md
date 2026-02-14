# SupplyTrackerPowerQuery

## Project Vision

Abbott UK's supply chain tracking was originally split between two independent Power BI/Excel workbooks:

- **Warehouse Tracker** — 19 M-code queries tracking inventory (AUK Queenborough + AUL third-party), inbound shipments, and batch-level expiry.
- **Wholesaler Tracker** — 11 M-code queries tracking wholesaler demand (AAH/Alliance Healthcare), order forecasting, and shipping performance.

Both projects duplicated data sources (SKU Bibles, A2B Bookings, SharePoint file access) and used inconsistent naming, making cross-report analysis unreliable.

The **Unified** folder consolidates all 30 legacy queries into **28 standardized queries** under a single architecture with shared helpers, consistent naming, and a clear staging → fact → QC pipeline. Legacy folders are archived for audit reference only.

---

## Repository Structure

```
├── Unified/                  ← PRODUCTION (Single Source of Truth)
│   ├── fn_SharePointBase.pq      Shared: single SharePoint entry point
│   ├── fn_GetLatestFile.pq       Shared: picks latest file by date modified
│   ├── base_LX02_Raw.pq          Shared: buffered SAP WM export
│   ├── dim_*.pq (4 files)        Dimension / master data queries
│   ├── stg_*.pq (12 files)       Staging: load → clean → type
│   ├── fct_*.pq (7 files)        Facts: joins, calculations, output
│   └── qc_*.pq (1 file)          Quality-control diagnostics
│
├── Warehouse Tracker/        ← LEGACY (archived, do not modify)
├── Wholesaler Tracker/       ← LEGACY (archived, do not modify)
├── README.md                 ← This file
├── AGENTS.md                 ← AI agent technical context
├── Capabilities.md           ← Business logic deep-dive
├── LogicRegistry.md          ← Storage types, forwarders, "why" docs
└── DataQuality.md            ← Type standards and validation
```

---

## Data Lineage

```mermaid
graph TD
    subgraph SharePoint
        SP["abbott.sharepoint.com/.../Demand/"]
    end

    subgraph "Shared Helpers"
        fn_SP["fn_SharePointBase"]
        fn_GLF["fn_GetLatestFile"]
        base["base_LX02_Raw"]
    end

    subgraph "Dimensions (dim_)"
        V2["dim_SKUBible_V2"]
        V3["dim_SKUBible_V3"]
        VC["dim_ValidationClients"]
        VF["dim_ValidationFactor"]
        BP["dim_BPCS_Item"]
    end

    subgraph "Staging (stg_)"
        stg_AUK["stg_Inv_AUK"]
        stg_AUK_B["stg_Inv_AUK_Batch"]
        stg_AUL["stg_Inv_AUL"]
        stg_AUL_B["stg_Inv_AUL_Batch"]
        stg_UK["stg_UK_Departures"]
        stg_A2B["stg_Inbound_A2B"]
        stg_Comp["stg_Inbound_Completed"]
        stg_Mrgd["stg_MergedData"]
        stg_Prev["stg_Shipped_PrevDay"]
        stg_InPr["stg_InProgress"]
        stg_Arr["stg_Arrival_Schedule"]
        stg_OO["stg_OnOrder"]
    end

    subgraph "Facts (fct_)"
        fct_WH["fct_Warehouse_Inbound"]
        fct_WS["fct_Wholesaler_Inbound"]
        fct_Inv["fct_Inventory"]
        fct_InvB["fct_Inventory_Batch"]
        fct_ADS["fct_ADS_CurrMonth"]
        fct_Rel["fct_Relex_UK"]
        fct_Inb["fct_Inbound"]
    end

    subgraph "QC (qc_)"
        qc_Exp["qc_Inventory_Expiry"]
    end

    SP --> fn_SP --> fn_GLF
    fn_SP --> base

    base --> stg_AUK & stg_AUK_B
    fn_GLF --> stg_AUL & stg_AUL_B & stg_UK & stg_A2B & stg_Comp & stg_Mrgd & stg_Prev & stg_InPr & stg_Arr

    stg_UK --> fct_WH & fct_WS
    stg_A2B --> fct_WH & fct_WS & fct_Inb
    stg_Arr --> fct_WS
    stg_AUK & stg_AUL --> fct_Inv
    stg_AUK_B & stg_AUL_B --> fct_InvB
    stg_Mrgd --> fct_ADS
    V2 --> stg_Mrgd & fct_Rel
    V3 --> fct_InvB & fct_WH
    fct_ADS --> fct_InvB
    fct_WH --> stg_OO --> fct_InvB
    fct_InvB --> qc_Exp

    VC --> stg_Prev & stg_InPr
    VF & BP --> fct_Rel
    stg_Prev & stg_InPr & stg_AUL --> fct_Rel
end
```

---

## Consolidation Index

### Warehouse Tracker → Unified

| Legacy File | Unified Query | Notes |
|:---|:---|:---|
| `PBI Warehouse.m` | `fct_Warehouse_Inbound.pq` + `stg_UK_Departures.pq` | Split into staging + fact |
| `A2B Summary.m` | `stg_Inbound_A2B.pq` | Shared with Wholesaler |
| `AUK_Inv_Batch.m` | `stg_Inv_AUK_Batch.pq` | — |
| `AUK_Inv_SKU.m` | `stg_Inv_AUK.pq` | — |
| `AUL_Inv_Batch.m` | `stg_Inv_AUL_Batch.pq` | — |
| `AUL_Inv_SKU.m` | `stg_Inv_AUL.pq` | — |
| `AUK_Completed_Bookings.m` | `stg_Inbound_Completed.pq` | — |
| `CurrMonthADS.m` | `fct_ADS_CurrMonth.pq` | — |
| `MergedData.m` | `stg_MergedData.pq` | — |
| `OnOrderQty.m` | `stg_OnOrder.pq` | — |
| `Total_Inv_Batch.m` | `fct_Inventory_Batch.pq` | — |
| `Total_Inv_SKU.m` | `fct_Inventory.pq` | Adds GroupBy |
| `SKUBIBLE.m` | `dim_SKUBible_V2.pq` | Shared |
| `SKUBIBLE V3.m` | `dim_SKUBible_V3.pq` | — |
| `Inventory Expiry OOP Adult.m` | `qc_Inventory_Expiry.pq` | Consolidated |
| `Inventory Expiry OOP Paed.m` | `qc_Inventory_Expiry.pq` | Consolidated |
| `Inventory Expiry Reimbursed.m` | `qc_Inventory_Expiry.pq` | Consolidated |
| `Errors in Inventory Expiry OOP Adult.m` | *Not ported* | Legacy diagnostic, never monitored |
| `AUL_TagIds_Only.m` | *Not ported* | Ad-hoc warehouse detail view |

### Wholesaler Tracker → Unified

| Legacy File | Unified Query | Notes |
|:---|:---|:---|
| `Relex_UK.m` | `fct_Relex_UK.pq` | Largest query (232 lines) |
| `PBIWarehouse_NI_AAH.m` | `fct_Wholesaler_Inbound.pq` | — |
| `A2B Summary.m` | `stg_Inbound_A2B.pq` | Shared |
| `AUL_Inv_SKU.m` | `stg_Inv_AUL.pq` | Shared |
| `BPCS_Item_Master.m` | `dim_BPCS_Item.pq` | — |
| `InProgress.m` | `stg_InProgress.pq` | — |
| `MasterArrivalSchedule.m` | `stg_Arrival_Schedule.pq` | — |
| `Prev_Day.m` | `stg_Shipped_PrevDay.pq` | — |
| `SKUBIBLE.m` | `dim_SKUBible_V2.pq` | Shared |
| `ValidationClients.m` | `dim_ValidationClients.pq` | — |
| `ValidationFactor.m` | `dim_ValidationFactor.pq` | — |

---

## Maintenance Guide

### Configurable Parameters

| Parameter | Location | Current Value | What It Controls |
|:---|:---|:---|:---|
| `MonthsBack` | `fct_Warehouse_Inbound.pq` line 10 | `-2` | How far back to include inbound shipments |
| `MonthsForward` | `fct_Warehouse_Inbound.pq` line 11 | `6` | How far forward to include inbound shipments |
| `MonthsBack` | `fct_Wholesaler_Inbound.pq` line 8 | `-2` | Same for wholesaler view |
| `MonthsForward` | `fct_Wholesaler_Inbound.pq` line 9 | `6` | Same for wholesaler view |
| `ShiftWeekendToMonday` | `fct_Relex_UK.pq` line 149 | `true` | Shift weekend deliveries to Monday |
| NOUWENS SLA | `fct_Warehouse_Inbound.pq` line 42 | `+1 day` | NOUWENS forwarder delivery offset |
| ESSERS SLA | `fct_Wholesaler_Inbound.pq` line 36 | `+5 days` | ESSERS forwarder delivery offset |

### Adding a New Forwarder

1. Open the relevant inbound file (`fct_Warehouse_Inbound.pq` or `fct_Wholesaler_Inbound.pq`)
2. Find the `deliveryDate =` section inside `WithStatus`
3. Add a new `if forwarder = "NEW_NAME" ...` clause with the contractual SLA days
4. The default is `null` (no expected date) for unrecognized forwarders

### Adding a New Wholesaler

AAH is currently the only wholesaler. If a new one is added:
- Build a **parallel pipeline** (do not generalize the AAH-specific logic)
- Create new `stg_` and `fct_` queries with the wholesaler name suffix

### Adding a New Storage Type or Lock Code

- **AUK (SAP)**: Edit `stg_Inv_AUK_Batch.pq` → `storageType` / `storageBin` if-else chains
- **AUK (SKU)**: Edit `stg_Inv_AUK.pq` → `Combined Storage Type` AddColumn
- **AUL**: Edit `stg_Inv_AUL_Batch.pq` → `storageType` / `storageBin` if-else chains
- Unknown codes map to `"NEW STORAGE TYPE TO BE DECIDED"` or `"NEW LOCK CODE TO BE ADDED"`

---

## Refresh Environment

| Property | Value |
|:---|:---|
| Runtime | Power Query in Excel Desktop |
| Refresh | Manual |
| Gateway | None |
| Dependency resolution | Automatic (Power Query internal graph) |
| Time zone | User's local machine time |

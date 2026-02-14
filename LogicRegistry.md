# LogicRegistry.md — The "Why" Behind the Business Rules

> This document explains the reasoning behind specific logic decisions that appear arbitrary from code alone.

---

## 1. Storage Type Categorization

### Why "SCHROTT"?

"Schrott" is the German word for "scrap." The SAP WM system at AUK Queenborough (a German-origin system) uses SAP Storage Types `904` and `999` as catch-all bins for inventory that is **not available for sale**. The business adopted "SCHROTT" as the umbrella category for all non-sellable stock.

### AUK (SAP WM — Storage Type Codes)

The SAP Warehouse Management module assigns numeric codes to storage locations:

| Code | Meaning | Why This Category |
|:---|:---|:---|
| `014` | Main warehouse floor | **AVAILABLE** — standard sellable stock |
| `011` | Overflow area | **AVAILABLE** — still accessible for picking |
| `802` | Goods receipt staging | **AVAILABLE** — received and confirmed |
| `200` | Picking allocation | **ALLOCATED** — reserved for outbound orders |
| `916` | Cross-dock allocation | **ALLOCATED** — reserved for transfer |
| `922` | Quality block | **BLOCKED** — pending QC release |
| `904` | Return/scrap area | **SCHROTT** — see Storage Bin for sub-category |
| `999` | Disposal area | **SCHROTT** — see Storage Bin for sub-category |
| `STAGING` *(Storage Bin)* | Inbound staging area | **RECEIPT** — fallback for unrecognized types at staging |

### SCHROTT Storage Bin Breakdown (AUK)

When the type is SCHROTT, the **Storage Bin** determines the specific reason:

| Storage Bin | Label | Business Meaning |
|:---|:---|:---|
| `DISPOSAL` | SCRAP | Approved for physical destruction |
| `DAMAGED` | DAMAGED | Physically damaged, pending assessment |
| `CLOSEDOWN` | INV RECON | Closedown stock under reconciliation |
| `DISPLAY` | DISPLAY STOCK | Reserved for trade show displays |
| `GRIR` | INV RECON | Goods Receipt/Invoice Receipt mismatch |
| `INVEST` | UNDER INVESTIGATION | Root cause analysis in progress |
| `MOOG` | FAILED PUMPS | Defective medical device pumps (Moog brand) |
| `PGI` | CANCELLED PICK | Post Goods Issue cancelled — inventory reversal |
| `QAHOLD` | QCHOLD | Quality assurance hold |
| `QUERY` | INV RECON | General query / pending resolution |
| `RETURNS` | MANUAL RETURN ERROR | Customer return logged incorrectly |
| `SCHROTT` | SHORTDATE | Near-expiry stock (short-dated) |
| `TROLLEY` | RETURN BLOCKED | Physical return trolley — blocked status |
| `APPROVED` | DESTRUCTION | Management-approved destruction |
| `NVP*` | INV RECON | NVP-prefixed bins = non-valued inventory recon |

> [!NOTE]
> The fallback for Storage Type `904` (without a matched bin) is `"RETURN BLOCKED"`. This is because most unrecognized 904 entries are customer returns awaiting categorization.

### AUL (Third-Party Warehouse — Lock Codes)

AUL uses a simpler system: a single `Lock Code` field on each inventory line.

| Lock Code | Zone | Label | Business Meaning |
|:---|:---|:---|:---|
| *(empty)* | `DESPATCH` | ALLOCATED | On the dispatch floor, about to ship |
| *(empty)* | `Goodsin` | RECEIPT → AVAILABLE | Just received, available for allocation |
| `BLOCKED` | contains `RESCOPK` | RESERVED FOR COPACK | Ring-fenced for co-packing operations |
| *(empty)* | *(other)* | AVAILABLE | Standard sellable stock |
| `SHORTDATE` | — | SCHROTT / SHORTDATE | Near-expiry |
| `DMGD` | — | SCHROTT / DAMAGED | Physically damaged |
| `QCHOLD` | — | SCHROTT / QA BLOCKED | Quality hold |
| `BLOCKED` | *(not RESCOPK)* | SCHROTT / RETURN BLOCKED | General block |
| `EXPD` | — | SCHROTT / EXPIRED | Past expiry date |
| `SCRAP` | — | SCHROTT / SCRAP | Approved for destruction |

---

## 2. Forwarder SLA Logic

### Why Different Days?

Each logistics company has a different contractual Service Level Agreement for delivery time after goods leave the warehouse:

- **NOUWENS** (+1 day): Netherlands-based. Short-haul cross-channel. Truck reaches UK next day.
- **ESSERS** (+5 days): Belgium-based. Longer routing, potentially consolidates loads. 5-day SLA is contractual.
- **A2B**: Uses their own logistics platform with pre-calculated expected delivery dates in the CSV export. No offset needed.

### Why `null` for Unknown Forwarders?

When a forwarder name doesn't match any known rule, the expected delivery date is `null`. This cascades through to `null` inbound status. **This is intentional** — it surfaces unrecognized forwarders in the report as blank status rows, prompting investigation.

---

## 3. The Monday Shift (Weekend Delivery Logic)

**Location**: `fct_Relex_UK.pq`, `ShiftWeekendToMonday = true`

### Why It Exists

Wholesaler (AAH) depots do not typically receive deliveries on weekends. When the order-day plus lead-time calculation lands on a Saturday or Sunday, the delivery is shifted to Monday.

### How It Works

```
OrderDay = index 0-4 (Mon-Fri)
DeliveryIndex = (OrderDay + LeadTime) mod 7

If index = 5 (Saturday) → 0 (Monday)
If index = 6 (Sunday) → 0 (Monday)
```

### When to Turn It Off

Set `ShiftWeekendToMonday = false` if the business enables Saturday deliveries. This will leave Saturday/Sunday delivery indices as-is (but only Mon-Fri columns are displayed, so Saturday/Sunday deliveries would appear as "no delivery day" — a known limitation).

---

## 4. Product Identity: Why So Many IDs?

| ID | Origin | Why It Exists |
|:---|:---|:---|
| `LOCAL ITEM NBR` | Abbott internal | **Canonical** ID — finest grain, one per SKU variant |
| `1-6-3-3` | Abbott nutritional coding | Product group code (1 digit / 6 digits / 3 digits / 3 digits). Groups variants under one product family |
| `SHORT 1633` | Derived from `1-6-3-3` | Compact numeric form, used as join key to BPCS system |
| `ECC CODE` | SAP ERP | Material number in the SAP system, used in warehouse/inventory joins |
| `AAH CODE` | AAH (wholesaler) | Wholesaler's own product identifier |
| `PIP code` | NHS/Pharmacy | Pharmacy product code (text, not always numeric) |

### Why Two SKU Bibles?

**V2** is product-level: one row per product, no warehouse dimension. Used for demand-side queries.

**V3** is plant-level: one row per product × warehouse combination. It adds `PLANT CODE` and `SHIP SHELF LIFE` per plant. **SHIP SHELF LIFE varies between AUK and AUL** for the same product because regulatory requirements differ by storage facility.

---

## 5. The "Months to Sell" Naming Confusion

```
Months to Sell = (Days to Expiry - SHIP SHELF LIFE) / 30
```

Despite its name, this is NOT "months of stock coverage" (Inventory ÷ Monthly Demand). It is:

> **Months of sellable shelf life remaining** — how many months before the product can no longer be shipped due to the minimum shipping shelf life requirement.

A product with a 2-year expiry and 90-day SHIP SHELF LIFE has `(730 - 90) / 30 = 21.3` months to sell.

---

## 6. The "Older than 2 Weeks" Label

In `fct_Warehouse_Inbound.pq` and `fct_Wholesaler_Inbound.pq`, shipments with `WeekNumber >= 15` are labeled `"Older than 2 Weeks"`.

**This is not a bug.** The label is a legacy business term that means "beyond the actionable delivery window." The 15-week threshold was chosen because shipments that far out are in transit planning, not active logistics. The "2 Weeks" in the label refers to the business's attention threshold, not the actual week count.

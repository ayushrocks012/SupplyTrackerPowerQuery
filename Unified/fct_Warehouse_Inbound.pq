let
    // --- Dependencies ---
    Source = stg_UK_Departures,
    A2B = stg_Inbound_A2B,   // Required for A2B.Expected Delivery Date
    SKUBIBLE = dim_SKUBible_V3, // Required for ECC CODE

    // --- 0. Parameters (Assumed from typical PBI logic) ---
    // PBI Warehouse.m snippet 391 showed MonthsBack/Forward.
    CurrentDate = Date.From(DateTime.LocalNow()),
    MonthsBack = -2,
    MonthsForward = 6,
    StartDate = Date.AddMonths(CurrentDate, MonthsBack),
    EndDate = Date.AddMonths(CurrentDate, MonthsForward),

    // --- 1. Filter by Date ---
    // Logic: [ETD] >= StartDate and [ETD] <= EndDate
    FilteredETD = Table.SelectRows(Source, each [ETD] >= StartDate and [ETD] <= EndDate),

    // --- 2. Merge with A2B ---
    // Join Keys: {"Breda Tour", "DEPARTURE"} -> {"Breda Tour", "Departure"}
    MergedA2B = Table.NestedJoin(FilteredETD, {"Breda Tour", "DEPARTURE"}, A2B, {"Breda Tour", "Departure"}, "A2B_Table", JoinKind.LeftOuter),
    
    ExpandedA2B = Table.ExpandTableColumn(MergedA2B, "A2B_Table", 
        {"A2B.Expected Delivery Date"}, 
        {"A2B.Expected Delivery Date"}),

    // --- 3. Inbound Warehouse Logic (from PBI Warehouse.m) ---
    // Snippet 381: "075-" & [TO]
    // Is [TO] a column in UK Departures? Or is it "Inbound Warehouse"?
    // Snippet 381 says: AddedInboundWarehouse = Table.AddColumn(ExpandedA2B, "Inbound Warehouse", each "075-" & [TO])
    // I need to check if "TO" exists in stg_UK_Departures.
    // Snippet 630 (stg_UK_Departures view) did NOT show "TO".
    // Is "TO" derived from "Port of Discharge"? 
    // Wait, Snippet 538 (PBIWarehouse_NI_AAH) had logic for "Inbound Warehouse" based on Port.
    // PBI Warehouse.m (Snippet 381) effectively uses "075-" & [TO].
    // Maybe [TO] is "Port of Discharge"? Or "To" column in the Excel?
    // Snippet 630 showed columns: ETD, DEPARTURE, Price, Units, Breda Tour, 1633 Item Code...
    // I suspect "TO" might be missing from stg_UK_Departures or renamed.
    // However, Wholesaler logic used Port of Discharge.
    // Let's assume for Warehouse Tracker, typical logic is "075-" & [TO] where [TO] is usually a warehouse code like "UK", "NI".
    // I'll check if "TO" is in the raw file or if I need to map "Port of Discharge" -> "TO".
    // "United Kingdom, Queenborough" -> "UK" -> "075-UK".
    // "Belfast, Northern Ireland" -> "XI" (or NI?) -> "075-XI".
    // "United Kingdom, Derby" -> "UL" -> "075-UL".
    // This matches Wholesaler logic. I will reuse that mapping for safety if [TO] is missing.
    
    WithWarehouse = Table.AddColumn(ExpandedA2B, "Inbound Warehouse", each 
        let 
            pod = if [Port of Discharge] = null then null else Text.Trim([Port of Discharge])
        in
            if pod = "Belfast, Northern Ireland" then "075-XI"
            else if pod = "United Kingdom, Derby" then "075-UL"
            else if pod = "United Kingdom, Queenborough" then "075-UK"
            else "Checking..." // Fallback
    , type text),

    // --- 4. Inbound Status Calculation (Specific to Warehouse) ---
    WithStatus = Table.AddColumn(WithWarehouse, "Inbound Status", each 
        let
            // Robust access
            expectedDD = [#"A2B.Expected Delivery Date"],
            etdDate = [ETD],
            forwarder = if [FORWARDER] = null then "" else Text.Upper(Text.Trim([FORWARDER])),

            // Logic from PBI Warehouse.m (Snippet 729)
            // if expectedDD = null then
            //    if forwarder = "NOUWENS" and etdDate <> null then Date.AddDays(etdDate, 1) else null
            // else expectedDD
            
            deliveryDate = 
                if expectedDD = null then 
                    if forwarder = "NOUWENS" and etdDate <> null then Date.AddDays(etdDate, 1) 
                    else null 
                else expectedDD,

            // Week Diff Logic
            weekDiff = 
                if deliveryDate = null then null 
                else 
                    (Date.Year(deliveryDate) - Date.Year(CurrentDate)) * 52 + 
                    (Date.WeekOfYear(deliveryDate) - Date.WeekOfYear(CurrentDate))
        in
            if deliveryDate = null then null
            else if weekDiff = -1 then "Inbound - Last Week"
            else if weekDiff = 0 then "Inbound - Current Week"
            else if weekDiff = 1 then "Inbound - Next Week"
            else if weekDiff > 1 then "Inbound - Newer than 2 Weeks"
            else "Inbound - Older than 2 Weeks"
    , type text),

    // --- 5. GIT Value & Date Metadata ---
    WithGIT = Table.AddColumn(WithStatus, "GIT Value (€)", each [Units] * [Price], type number),
    WithYear = Table.AddColumn(WithGIT, "Year (Current)", each Date.Year([ETD]), Int64.Type),
    WithMonth = Table.AddColumn(WithYear, "Month (Current)", each Text.PadStart(Text.From(Date.Month([ETD])), 2, "0") & " - " & Text.Start(Date.MonthName([ETD]), 3), type text),

    // --- 6. Merge with SKU Bible (for ECC CODE) ---
    // Snippet 713 shows merge on "1633 Item Code" -> "SHORT 1633" to get "ECC CODE".
    // This provides the link to other facts.
    
    MergedSKU = Table.NestedJoin(WithMonth, {"1633 Item Code"}, SKUBIBLE, {"SHORT 1633"}, "SKUBIBLE", JoinKind.LeftOuter),
    ExpandedSKU = Table.ExpandTableColumn(MergedSKU, "SKUBIBLE", {"ECC CODE"}, {"ECC CODE"}),
    
    // --- 7. Final Select/Sort ---
    // Snippet 713: Sort by DEPARTURE Descending
    Sorted = Table.Sort(ExpandedSKU, {{"DEPARTURE", Order.Descending}}),
    
    // Explicit Selection based on typical usage (OnOrder uses Inbound Status, Warehouse, ECC CODE)
    Selected = Table.SelectColumns(Sorted, {
        "Inbound Warehouse", "Inbound Status", "ECC CODE", 
        "1633 Item Code", "Units", "ETD", "DEPARTURE", 
        "GIT Value (€)", "Year (Current)", "Month (Current)",
        "A2B.Expected Delivery Date"
    }, MissingField.Ignore)
in
    Selected

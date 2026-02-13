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
        {"Collection Date", "Expected Delivery Date", "Breda Tour", "Departure", "Status", "Location", "Custom Cleared Status"}, 
        {"A2B.Collection Date", "A2B.Expected Delivery Date", "A2B.Breda Tour", "A2B.Departure", "A2B.Status", "A2B.Location", "A2B.Custom Cleared Status"}),

    // --- 3. Inbound Warehouse Logic (from PBI Warehouse.m) ---
    // Legacy: "075-" & [TO] — user confirmed [TO] column exists in UK Departures Excel
    WithWarehouse = Table.AddColumn(ExpandedA2B, "Inbound Warehouse", each "075-" & [TO], type text),

    // --- 4. Inbound Status Calculation (Specific to Warehouse) ---
    WithStatus = Table.AddColumn(WithWarehouse, "Inbound Status", each 
        let
            // C-01 FIX: Defensive coercions matching legacy PBI Warehouse.m
            expectedDD = try Date.From([#"A2B.Expected Delivery Date"]) otherwise null,
            etdDate = try Date.From([ETD]) otherwise null,
            forwarder = Text.Upper(Text.Trim(try Text.From([FORWARDER]) otherwise "")),

            // Effective delivery date
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
    
    // --- 7. Final Select ---
    // Sort removed (Power BI sorts in the visual layer)
    Selected = Table.SelectColumns(ExpandedSKU, {
        "Inbound Warehouse", "Inbound Status", "ECC CODE", 
        "1633 Item Code", "Units", "ETD", "DEPARTURE", 
        "GIT Value (€)", "Year (Current)", "Month (Current)",
        "A2B.Collection Date", "A2B.Expected Delivery Date",
        "A2B.Breda Tour", "A2B.Departure", "A2B.Status", "A2B.Location", "A2B.Custom Cleared Status"
    }, MissingField.Ignore)
in
    Selected

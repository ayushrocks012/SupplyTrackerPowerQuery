let
    // --- Dependencies ---
    Source = stg_UK_Departures,
    A2B = stg_Inbound_A2B,
    SKUBIBLE = dim_SKUBible_V3,
    MasterArrival = stg_Arrival_Schedule,

    // --- 0. Parameters ---
    CurrentDate = Date.From(DateTime.LocalNow()),
    MonthsBack = -2,
    MonthsForward = 6,
    StartDate = Date.AddMonths(CurrentDate, MonthsBack),
    EndDate = Date.AddMonths(CurrentDate, MonthsForward),

    // --- 1. Filter by Date ---
    FilteredETD = Table.SelectRows(Source, each [ETD] >= StartDate and [ETD] <= EndDate),

    // --- 2. Merge with A2B ---
    MergedA2B = Table.NestedJoin(FilteredETD, {"Breda Tour", "DEPARTURE"}, A2B, {"Breda Tour", "Departure"}, "A2B_Table", JoinKind.LeftOuter),
    ExpandedA2B = Table.ExpandTableColumn(MergedA2B, "A2B_Table", 
        {"Collection Date", "Expected Delivery Date", "Sailing Date", "Breda Tour", "Departure", "Status", "Location", "Custom Cleared Status"}, 
        {"A2B.Collection Date", "A2B.Expected Delivery Date", "A2B.Sailing Date", "A2B.Breda Tour", "A2B.Departure", "A2B.Status", "A2B.Location", "A2B.Custom Cleared Status"}),

    // --- 3. Inbound Warehouse (from Port of Discharge) ---
    WithWarehouse = Table.AddColumn(ExpandedA2B, "Inbound Warehouse", each 
        let pod = if [Port of Discharge] = null then null else Text.Trim([Port of Discharge])
        in
            if pod = "Belfast, Northern Ireland" then "075-XI"
            else if pod = "United Kingdom, Derby" then "075-UL"
            else if pod = "United Kingdom, Queenborough" then "075-UK"
            else if [TO] <> null then "075-" & [TO]
            else "Check Port of Discharge"
    , type text),

    // --- 4. Merge with Master Arrival Schedule (for Warehouse Name) ---
    MergedArrival = Table.NestedJoin(WithWarehouse, {"INVOICE", "1633 Item Code"}, MasterArrival, {"FACT_Shipment_Actuals[Invoice]", "DIM_ProductMaster[MK_PRODUCT]"}, "MasterArrivalSchedule", JoinKind.LeftOuter),
    ExpandedArrival = Table.ExpandTableColumn(MergedArrival, "MasterArrivalSchedule", 
        {"FACT_Shipment_Actuals[Ship_To_Address1]", "FACT_Shipment_Actuals[Ship_To_Address2]", "FACT_Shipment_Actuals[Ship_To_Address3]"}, 
        {"Ship_To_Address1", "Ship_To_Address2", "Ship_To_Address3"}),

    // Warehouse Name derived from Arrival Schedule Ship_To address (original logic)
    WithWarehouseName = Table.AddColumn(ExpandedArrival, "Warehouse Name", each 
        if [Ship_To_Address1] = "2 MARSHALLS ROAD" then "BELFAST" 
        else null
    , type text),

    // --- 5. Inbound Status Calculation (All Forwarders) ---
    WithStatus = Table.AddColumn(WithWarehouseName, "Inbound Status", each 
        let
            expectedDD = try Date.From([#"A2B.Expected Delivery Date"]) otherwise null,
            etdDate = try Date.From([ETD]) otherwise null,
            forwarder = Text.Upper(Text.Trim(try Text.From([FORWARDER]) otherwise "")),

            // Forwarder-specific delivery date
            deliveryDate = 
                if forwarder = "NOUWENS" then 
                    if etdDate <> null then Date.AddDays(etdDate, 1) else null
                else if forwarder = "ESSERS" then 
                    if etdDate <> null then Date.AddDays(etdDate, 5) else null
                else if forwarder = "A2B" then expectedDD
                else if expectedDD <> null then expectedDD
                else null,

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

    // --- 6. GIT Value & Date Metadata ---
    WithGIT = Table.AddColumn(WithStatus, "GIT Value (€)", each [Units] * [Price], type number),
    WithYear = Table.AddColumn(WithGIT, "Year (Current)", each Date.Year([ETD]), Int64.Type),
    WithMonth = Table.AddColumn(WithYear, "Month (Current)", each Text.PadStart(Text.From(Date.Month([ETD])), 2, "0") & " - " & Text.Start(Date.MonthName([ETD]), 3), type text),

    // --- 7. Merge with SKU Bible (for ECC CODE) ---
    MergedSKU = Table.NestedJoin(WithMonth, {"1633 Item Code"}, SKUBIBLE, {"SHORT 1633"}, "SKUBIBLE", JoinKind.LeftOuter),
    ExpandedSKU = Table.ExpandTableColumn(MergedSKU, "SKUBIBLE", {"ECC CODE"}, {"ECC CODE"}),
    
    // --- 8. Final Select ---
    Selected = Table.SelectColumns(ExpandedSKU, {
        "Inbound Warehouse", "Warehouse Name", "Inbound Status", "ECC CODE", 
        "1633 Item Code", "Units", "ETD", "DEPARTURE", "FORWARDER",
        "GIT Value (€)", "Year (Current)", "Month (Current)",
        "A2B.Collection Date", "A2B.Expected Delivery Date", "A2B.Sailing Date",
        "A2B.Breda Tour", "A2B.Departure", "A2B.Status", "A2B.Location", "A2B.Custom Cleared Status",
        "Ship_To_Address1", "Ship_To_Address2", "Ship_To_Address3",
        "Port of Discharge", "TO", "INVOICE", "Price"
    }, MissingField.Ignore)
in
    Selected

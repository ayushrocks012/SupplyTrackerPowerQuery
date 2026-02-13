let
    // --- Dependencies ---
    Source = stg_UK_Departures,
    A2B = stg_Inbound_A2B,   
    MasterArrival = stg_Arrival_Schedule,

    // --- 0. Parameters (Logic from PBIWarehouse_NI_AAH.m) ---
    MonthsBack = -2,
    MonthsForward = 6,
    CurrentDate = Date.From(DateTime.LocalNow()),
    StartDate = Date.AddMonths(CurrentDate, MonthsBack),
    EndDate = Date.AddMonths(CurrentDate, MonthsForward),

    // --- 1. Filter by Date (Implicitly removes Grand Total) ---
    // Logic: [ETD] >= StartDate and [ETD] <= EndDate
    FilteredETD = Table.SelectRows(Source, each [ETD] >= StartDate and [ETD] <= EndDate),

    // --- 2. Merge with A2B ---
    // Join Keys: {"Breda Tour", "DEPARTURE"} -> {"Breda Tour", "Departure"}
    
    MergedA2B = Table.NestedJoin(FilteredETD, {"Breda Tour", "DEPARTURE"}, A2B, {"Breda Tour", "Departure"}, "A2B_Table", JoinKind.LeftOuter),
    
    ExpandedA2B = Table.ExpandTableColumn(MergedA2B, "A2B_Table", 
        {"A2B.Expected Delivery Date"}, 
        {"A2B.Expected Delivery Date"}),

    // --- 3. Inbound Status Calculation ---
    WithStatus = Table.AddColumn(ExpandedA2B, "Inbound Status", each 
        let
            fwd = [FORWARDER],
            etd = [ETD],
            a2b_exp = [#"A2B.Expected Delivery Date"],
            
            // Expected Date Logic
            expectedDate = 
                if fwd = "ESSERS" then 
                    if etd = null then null else Date.AddDays(etd, 5)
                else if fwd = "A2B" then 
                    a2b_exp
                else 
                    null,
            
            // Week Diff Calculation
            weekDiff = 
                if expectedDate = null then null 
                else 
                    (Date.Year(expectedDate) - Date.Year(CurrentDate)) * 52 + 
                    (Date.WeekOfYear(expectedDate) - Date.WeekOfYear(CurrentDate))
        in
            if weekDiff = null then null
            else if weekDiff = -1 then "Inbound - Last Week"
            else if weekDiff = 0 then "Inbound - Current Week"
            else if weekDiff = 1 then "Inbound - Next Week"
            else if weekDiff > 1 then "Inbound - Newer than 2 Weeks"
            else "Inbound - Older than 2 Weeks"
    , type text),

    // --- 4. GIT Value ---
    WithGIT = Table.AddColumn(WithStatus, "GIT Value (€)", each [Units] * [Price], type number),

    // --- 5. Year & Month ---
    WithYear = Table.AddColumn(WithGIT, "Year (Current)", each Date.Year([ETD]), Int64.Type),
    WithMonth = Table.AddColumn(WithYear, "Month (Current)", each Text.PadStart(Text.From(Date.Month([ETD])), 2, "0") & " - " & Text.Start(Date.MonthName([ETD]), 3), type text),
    
    // --- 6. Inbound Warehouse Logic ---
    WithWarehouse = Table.AddColumn(WithMonth, "Inbound Warehouse", each 
        let 
            pod = if [Port of Discharge] = null then null else Text.Trim([Port of Discharge])
        in
            if pod = "Belfast, Northern Ireland" then "075-XI"
            else if pod = "United Kingdom, Derby" then "075-UL"
            else if pod = "United Kingdom, Queenborough" then "075-UK"
            else "Check Port of Discharge"
    , type text),

    Completed = WithWarehouse
in
    Completed

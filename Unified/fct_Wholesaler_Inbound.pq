let
    // --- Dependencies ---
    Source = stg_UK_Departures,
    A2B = stg_Inbound_A2B,   
    MasterArrival = stg_Arrival_Schedule,

    // --- 0. Parameters ---
    MonthsBack = -2,
    MonthsForward = 6,
    CurrentDate = Date.From(DateTime.LocalNow()),
    StartDate = Date.AddMonths(CurrentDate, MonthsBack),
    EndDate = Date.AddMonths(CurrentDate, MonthsForward),

    // --- 1. Filter by Date ---
    FilteredETD = Table.SelectRows(Source, each [ETD] >= StartDate and [ETD] <= EndDate),

    // --- 2. Merge with A2B ---
    MergedA2B = Table.NestedJoin(FilteredETD, {"Breda Tour", "DEPARTURE"}, A2B, {"Breda Tour", "Departure"}, "A2B_Table", JoinKind.LeftOuter),
    
    ExpandedA2B = Table.ExpandTableColumn(MergedA2B, "A2B_Table", 
        {"Expected Delivery Date"}, 
        {"A2B.Expected Delivery Date"}),
    // --- 3. Inbound Status Calculation ---
    WithStatus = Table.AddColumn(ExpandedA2B, "Inbound Status", each 
        let
            fwd = [FORWARDER],
            etd = [ETD],
            a2b_exp = [#"A2B.Expected Delivery Date"],
            expectedDate = 
                if fwd = "ESSERS" then 
                    if etd = null then null else Date.AddDays(etd, 5)
                else if fwd = "A2B" then a2b_exp
                else null,
            weekDiff = 
                if expectedDate = null then null 
                else (Date.Year(expectedDate) - Date.Year(CurrentDate)) * 52 + 
                     (Date.WeekOfYear(expectedDate) - Date.WeekOfYear(CurrentDate))
        in
            if weekDiff = null then null
            else if weekDiff = -1 then "Inbound - Last Week"
            else if weekDiff = 0 then "Inbound - Current Week"
            else if weekDiff = 1 then "Inbound - Next Week"
            else if weekDiff > 1 then "Inbound - Newer than 2 Weeks"
            else "Inbound - Older than 2 Weeks"
    , type text),

    // --- 4. Merge with Master Arrival Schedule ---
    MergedArrival = Table.NestedJoin(WithStatus, {"INVOICE", "1633 Item Code"}, MasterArrival, {"FACT_Shipment_Actuals[Invoice]", "DIM_ProductMaster[MK_PRODUCT]"}, "MasterArrivalSchedule", JoinKind.LeftOuter),
    ExpandedArrival = Table.ExpandTableColumn(MergedArrival, "MasterArrivalSchedule", 
        {"FACT_Shipment_Actuals[Ship_To_Address1]", "FACT_Shipment_Actuals[Ship_To_Address2]", "FACT_Shipment_Actuals[Ship_To_Address3]"}, 
        {"FACT_Shipment_Actuals[Ship_To_Address1]", "FACT_Shipment_Actuals[Ship_To_Address2]", "FACT_Shipment_Actuals[Ship_To_Address3]"}),

    // --- 5–8. Single-pass enrichment (replaces 5 chained Table.AddColumn) ---
    Enriched = Table.FromRecords(
        Table.TransformRows(ExpandedArrival, (row) =>
            let
                etd = row[ETD],
                pod = if row[Port of Discharge] = null then null 
                      else Text.Trim(row[Port of Discharge]),
                addr1 = Record.FieldOrDefault(row, "FACT_Shipment_Actuals[Ship_To_Address1]", null)
            in Record.Combine({row, [
                #"GIT Value (£,£)" = row[Units] * row[Price],
                #"Year (Current)" = Date.Year(etd),
                #"Month (Current)" = Text.PadStart(Text.From(Date.Month(etd)), 2, "0") 
                                     & " - " & Text.Start(Date.MonthName(etd), 3),
                #"Inbound Warehouse" = 
                    if pod = "Belfast, Northern Ireland" then "075-XI"
                    else if pod = "United Kingdom, Derby" then "075-UL"
                    else if pod = "United Kingdom, Queenborough" then "075-UK"
                    else "Check Port of Discharge",
                #"Warehouse Name" = if addr1 = "2 MARSHALLS ROAD" then "BELFAST" else null
            ]})
        )
    ),

    Completed = Enriched
in
    Completed

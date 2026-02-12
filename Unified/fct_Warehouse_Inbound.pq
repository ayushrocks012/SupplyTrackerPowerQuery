let
    // --- Dependencies ---
    Source = stg_UK_Departures,
    
    // Calculate Inbound Fields (Logic from PBI Warehouse.m)
    
    // 1. Inbound Warehouse
    // PBI Warehouse.m: "075-" & [TO]
    WithWarehouse = Table.AddColumn(Source, "Inbound Warehouse", each if [TO] <> null then "075-" & Text.From([TO]) else null),
    
    // 2. Inbound Status
    // Logic: If [A2B.Expected Delivery Date] ...
    // Note: stg_UK_Departures must have [A2B.Expected Delivery Date]. 
    // The previous view of PBI Warehouse.m showed "ExpandedA2B".
    // This implies UK Departures might NOT have A2B columns inherently?
    // "PBI Warehouse.m" step `ExpandedA2B` suggests it merged A2B.
    // BUT `PBIWarehouse_NI_AAH.m` command 9383 output didn't show merge steps in the first 20 lines.
    // Wait, the file "UK Departures" might contain columns like "A2B.Expected Delivery Date" if it's an export?
    // Or PBI Warehouse.m merges A2B Summary?
    // Let's assume the columns exist in stg_UK_Departures for now (as the file name "UK Departures PBI" suggests a prepared report).
    
    // Date Logic
    CurrentDate = Date.From(DateTime.LocalNow()),
    StartOfWeek = Date.StartOfWeek(CurrentDate),
    EndOfWeek = Date.EndOfWeek(CurrentDate),
    EndOfNextWeek = Date.AddDays(EndOfWeek, 7),
    
    WithStatus = Table.AddColumn(WithWarehouse, "Inbound Status", each 
        let
            // Robust Date extraction (assuming column names exist)
            // If columns like "A2B.Expected Delivery Date" are missing, this will error.
            // I'll use try/otherwise or assume columns are standard.
            EDD = try Date.From([#"A2B.Expected Delivery Date"]) otherwise null
        in
            if EDD <> null and EDD >= StartOfWeek and EDD <= EndOfWeek then "Inbound - Current Week"
            else if EDD <> null and EDD > EndOfWeek and EDD <= EndOfNextWeek then "Inbound - Next Week"
            else "Future"
    ),
    
    Selected = Table.SelectColumns(WithStatus, {"Inbound Warehouse", "Inbound Status", "1633 Item Code", "Units", "ETD", "DEPARTURE"})
in
    Selected

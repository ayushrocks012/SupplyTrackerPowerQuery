let
    // --- Dependencies ---
    Source = stg_UK_Departures, // Reusing UK Departures staging
    
    // Logic from PBIWarehouse_NI_AAH.m (via PowerShell output)
    // It filters for "NI" and "AAH"?
    // "Added Custom" = Table.AddColumn(..., "Inbound Warehouse", each "075-" & [TO])
    // "Filtered Rows" = Table.SelectRows(..., each ([Inbound Warehouse] = "075-NI" or [Inbound Warehouse] = "075-AAH"))
    
    WithWarehouse = Table.AddColumn(Source, "Inbound Warehouse", each if [TO] <> null then "075-" & Text.From([TO]) else null),
    
    // Filter for Wholesaler warehouses
    Filtered = Table.SelectRows(WithWarehouse, each ([Inbound Warehouse] = "075-NI" or [Inbound Warehouse] = "075-AAH")),
    
    // Date Logic
    CurrentDate = Date.From(DateTime.LocalNow()),
    StartOfWeek = Date.StartOfWeek(CurrentDate),
    EndOfWeek = Date.EndOfWeek(CurrentDate),
    EndOfNextWeek = Date.AddDays(EndOfWeek, 7),
    
    WithStatus = Table.AddColumn(Filtered, "Inbound Status", each 
        let
            EDD = try Date.From([#"A2B.Expected Delivery Date"]) otherwise null
        in
            if EDD <> null and EDD >= StartOfWeek and EDD <= EndOfWeek then "Inbound - Current Week"
            else if EDD <> null and EDD > EndOfWeek and EDD <= EndOfNextWeek then "Inbound - Next Week"
            else "Future"
    ),
    
    Selected = Table.SelectColumns(WithStatus, {"Inbound Warehouse", "Inbound Status", "1633 Item Code", "Units", "ETD", "DEPARTURE"})
in
    Selected

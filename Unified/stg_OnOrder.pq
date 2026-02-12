let
    // --- Dependencies ---
    Source = fct_Warehouse_Inbound,
    
    // Filter for Current or Next Week
    Filtered = Table.SelectRows(Source, each ([Inbound Status] = "Inbound - Current Week" or [Inbound Status] = "Inbound - Next Week")),
    
    // Group by Warehouse and Item (ECC CODE)
    // Note: "1633 Item Code" in UK Departures maps to "ECC CODE"? 
    // Usually "1633 Item Code" is the material number.
    // I will rename it to "ECC CODE" for consistency with other queries.
    
    Renamed = Table.RenameColumns(Filtered, {{"1633 Item Code", "ECC CODE"}}),
    
    Grouped = Table.Group(Renamed, {"Inbound Warehouse", "ECC CODE"}, {{"OnOrderQty", each List.Sum([Units]), type nullable number}})
in
    Grouped

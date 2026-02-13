let
    // --- Dependencies ---
    Source = fct_Warehouse_Inbound,
    
    // Select only the columns we need (matching legacy OnOrderQty.m)
    Selected = Table.SelectColumns(Source, {"Inbound Warehouse", "Inbound Status", "ECC CODE", "Units"}),
    
    // Filter for Current or Next Week
    Filtered = Table.SelectRows(Selected, each ([Inbound Status] = "Inbound - Current Week" or [Inbound Status] = "Inbound - Next Week")),
    
    // Remove Inbound Status before grouping (matching legacy)
    Removed = Table.RemoveColumns(Filtered, {"Inbound Status"}),
    
    // Group by Warehouse and ECC CODE
    Grouped = Table.Group(Removed, {"Inbound Warehouse", "ECC CODE"}, {{"OnOrderQty", each List.Sum([Units]), type nullable number}})
in
    Grouped

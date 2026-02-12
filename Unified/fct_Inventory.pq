let
    // --- Dependencies ---
    // Direct references to other queries
    AUK = stg_Inv_AUK,
    AUL = stg_Inv_AUL,
    
    // Standardize types before union
    AUK_Sel = Table.SelectColumns(AUK, {"Product Code", "Net Inventory", "Warehouse"}),
    AUL_Sel = Table.SelectColumns(AUL, {"Product Code", "Net Inventory", "Warehouse"}),
    
    Union = Table.Combine({AUK_Sel, AUL_Sel}),
    Grouped = Table.Group(Union, {"Product Code", "Warehouse"}, {{"Total Inventory", each List.Sum([Net Inventory]), type nullable number}})
in
    Grouped

let
    // --- Dependencies ---
    Staging = Unified_03_Staging, // Hypothetical reference, in reality referencing the queries directly
    
    // 1. Unified Inventory Fact
    fct_Inventory = 
        let
            AUK = Staging[stg_Inv_AUK],
            AUL = Staging[stg_Inv_AUL],
            
            // Standardize types before union
            AUK_Sel = Table.SelectColumns(AUK, {"Product Code", "Net Inventory", "Warehouse"}),
            AUL_Sel = Table.SelectColumns(AUL, {"Product Code", "Net Inventory", "Warehouse"}),
            
            Union = Table.Combine({AUK_Sel, AUL_Sel}),
            Grouped = Table.Group(Union, {"Product Code", "Warehouse"}, {{"Total Inventory", each List.Sum([Net Inventory]), type nullable number}})
        in
            Grouped,

    // 2. Inbound Fact
    fct_Inbound = 
        let
            Source = Staging[stg_Inbound_A2B],
            // Enriched logic could go here
            Selected = Table.SelectColumns(Source, {"Booking ID", "Expected Delivery Date", "Status", "Location", "Custom Cleared Status"})
        in
            Selected
in
    [
        fct_Inventory = fct_Inventory,
        fct_Inbound = fct_Inbound
    ]

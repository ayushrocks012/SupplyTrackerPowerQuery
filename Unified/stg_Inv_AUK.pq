let
    // --- Dependencies (Shared Base) ---
    Promoted = base_LX02_Raw,
    Renamed = Table.RenameColumns(Promoted, {{"Material", "Product Code"}, {"Batch", "Batch ID"}, {"Available stock", "Stock"}, {"Pick quantity", "Pick Qty"}, {"SLED/BBD", "Expiry"}}),
    WithWarehouse = Table.AddColumn(Renamed, "Warehouse", each "075-UK"),
    NetInv = Table.AddColumn(WithWarehouse, "Net Inventory", each [Stock] + [Pick Qty]),
    
    CombinedStorage = Table.AddColumn(NetInv, "Combined Storage Type", each 
        if [Storage Type] = "014" or [Storage Type] = "011" then "AVAILABLE" 
        else if [Storage Type] = "802" then "RECEIPT" 
        else if [Storage Type] = "916" then "ALLOCATED" 
        else if [Storage Type] = "999" then "SCHROTT"
        else "NEW STORAGE TYPE TO BE DECIDED"
    ),
    
    Filtered = Table.SelectRows(CombinedStorage, each ([Combined Storage Type] = "AVAILABLE" or [Combined Storage Type] = "RECEIPT")),
    
    Selected = Table.SelectColumns(Filtered, {"Product Code", "Batch ID", "Net Inventory", "Warehouse", "Expiry"})
in
    Selected

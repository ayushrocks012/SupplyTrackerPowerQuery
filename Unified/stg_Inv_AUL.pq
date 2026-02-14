let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[DailyTracker],
    
    FileContent = fn_GetLatestFile(DemandPath, "Inventory by SKU", ".xls"), 
    Excel = Excel.Workbook(FileContent, null, true),
    Sheet = try Excel{[Item="Data"]} otherwise Excel{[Name="Data"]},
    Data = Sheet[Data],
    Promoted = Table.PromoteHeaders(Data, [PromoteAllScalars=true]),
    Renamed = Table.RenameColumns(Promoted, {{"SKU ID", "Product Code"}, {"x_qty_available", "Net Inventory"}}),
    WithWarehouse = Table.AddColumn(Renamed, "Warehouse", each "075-UL"),
    Selected = Table.SelectColumns(WithWarehouse, {"Product Code", "Net Inventory", "Warehouse", "ship_shelf_life"}, MissingField.Ignore),
    Typed = Table.TransformColumnTypes(Selected, {{"Net Inventory", Int64.Type}}),
    // N-02/N-03 FIX: Group by Product Code + Warehouse + ship_shelf_life to match legacy AUL_Inv_SKU.m
    Grouped = Table.Group(Typed, {"Product Code", "Warehouse", "ship_shelf_life"}, {{"Net Inventory", each List.Sum([Net Inventory]), type nullable number}})
in
    Grouped

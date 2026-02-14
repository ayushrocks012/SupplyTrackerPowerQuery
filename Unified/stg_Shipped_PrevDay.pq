let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[Wholesaler],
    
    // Dependency: dim_ValidationClients
    Clients = dim_ValidationClients,

    FileContent = fn_GetLatestFile(DemandPath, "ABBOTT LINES SHIPPED PREV DAY", ".xls"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    Data_Record = 
        try Excel{[Item = "Data", Kind = "Sheet"]} 
        otherwise try Excel{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'",
    
    Data_Sheet = Data_Record[Data],
    
    Promoted = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    
    // Filter for AAH
    Filtered = Table.SelectRows(Promoted, each Text.Contains([Name], "AAH", Comparer.OrdinalIgnoreCase)),
    
    // Merge with ValidationClients
    Merged = Table.NestedJoin(Filtered, {"Postcode"}, Clients, {"Postcode"}, "ValidationClients", JoinKind.LeftOuter),
    Expanded = Table.ExpandTableColumn(Merged, "ValidationClients", {"Town"}, {"Town"}),
    Typed = Table.TransformColumnTypes(Expanded, {{"Qty Ordered", Int64.Type}, {"Qty Picked", Int64.Type}, {"Qty Shipped", Int64.Type}, {"Shipped Date", type date}, {"Ship By Date", type date}, {"Town", type text}})
in
    Typed

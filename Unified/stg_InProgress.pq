let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[Wholesaler],
    
    // Dependency: dim_ValidationClients
    Clients = dim_ValidationClients,

    FileContent = fn_GetLatestFile(DemandPath, "ABBOTT LINES IN PROGRESS", ".xls"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    Data_Record = 
        try Excel{[Item = "Data", Kind = "Sheet"]} 
        otherwise try Excel{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'",
    
    Data_Sheet = Data_Record[Data],

    Promoted = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    
    Typed = Table.TransformColumnTypes(Promoted,{{"Creation Date", type date}, {"Qty Ordered", Int64.Type}, {"Qty In Progress", Int64.Type}, {"Ship By Date", type date}}),
    
    // Filter for AAH
    Filtered = Table.SelectRows(Typed, each Text.Contains([Name], "AAH", Comparer.OrdinalIgnoreCase)),
    
    // Merge with ValidationClients
    Merged = Table.NestedJoin(Filtered, {"Postcode"}, Clients, {"Postcode"}, "ValidationClients", JoinKind.LeftOuter),
    
    // Expand Town and Replace
    Expanded = Table.ExpandTableColumn(Merged, "ValidationClients", {"Town"}, {"Town.1"}),
    RemovedTown = Table.RemoveColumns(Expanded,{"Town"}), // Remove original Town
    RenamedTown = Table.RenameColumns(RemovedTown,{{"Town.1", "Town"}}),
    
    FinalTyped = Table.TransformColumnTypes(RenamedTown,{{"Town", type text}})
in
    FinalTyped

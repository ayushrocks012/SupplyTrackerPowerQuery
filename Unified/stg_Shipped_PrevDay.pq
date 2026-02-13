let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[Wholesaler],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,
            
    // Dependency: dim_ValidationClients
    Clients = dim_ValidationClients,

    FileContent = GetLatestFile(DemandPath, "ABBOTT LINES SHIPPED PREV DAY", ".xls"),
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
    Expanded = Table.ExpandTableColumn(Merged, "ValidationClients", {"Town"}, {"Town"})
in
    Expanded

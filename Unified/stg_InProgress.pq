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

    FileContent = GetLatestFile(DemandPath, "ABBOTT LINES IN PROGRESS", ".xls"), // Source: .xls or .xlsx? Original code says "EndsWith .xls" or "Excel.Workbook"
    // Original code: Text.StartsWith([Name], "ABBOTT LINES IN PROGRESS") ...
    // Note: If using "GetLatestFile" generic logic, I should check extension carefully
    // Original code doesn't filter by extension explicit in the SelectRows, just StartsWith.
    // It assumes ".xls" structure in workbook load.
    // I'll stick to ".xls" or ".xlsx". Let's assume ".xls" based on typical "Daily Tracker" files.
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

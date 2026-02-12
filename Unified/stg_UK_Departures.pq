let
    // --- Dependencies (Hardcoded) ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    // Path: General > Demand > Master Data Files > Daily Tracker Files UK Departures PBI
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files UK Departures PBI"]}[Content],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    FileContent = GetLatestFile(DemandPath, "UK Departures", ".xlsx"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    // Sheet Name: "Warehouse"
    Sheet = try Excel{[Item="Warehouse", Kind="Sheet"]}[Data] 
            otherwise Excel{[Name="Warehouse"]}[Data],
            
    Promoted = Table.PromoteHeaders(Sheet, [PromoteAllScalars=true]),
    
    // Clean Empty Rows
    Cleaned = Table.SelectRows(Promoted, each not List.IsEmpty(List.RemoveMatchingItems(Record.FieldValues(_), {"", null}))),
    
    // Type Transformation (Based on PBI Warehouse.m inspection)
    Typed = Table.TransformColumnTypes(Cleaned,{
        {"ETD", type date}, 
        {"DEPARTURE", Int64.Type}, 
        {"Price", type number}, 
        {"Units", type number}, 
        {"Breda Tour", type text}, 
        {"1633 Item Code", type text}, 
        {"Breda Status Date", type date}, 
        {"EXP_DATE", type date}, 
        {"MFG_DATE", type date}
        // Add other columns if needed
    })
in
    Typed

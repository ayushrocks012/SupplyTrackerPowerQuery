let
    // --- Dependencies (Hardcoded) ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files"]}[Content],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    FileContent = GetLatestFile(DemandPath, "Completed Bookings", ".xls"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    Data_Record = 
        try Excel{[Item = "Data", Kind = "Sheet"]} 
        otherwise try Excel{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'",
    
    Data_Sheet = Data_Record[Data],

    Promoted = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    
    // Select useful columns
    Selected = Table.SelectColumns(Promoted, {"Booking Reference", "Carrier", "Status", "Delivery Date", "Collection Date"}),
    
    Typed = Table.TransformColumnTypes(Selected,{
        {"Booking Reference", type text}, 
        {"Carrier", type text}, 
        {"Status", type text},
        {"Delivery Date", type date},
        {"Collection Date", type date}
    })
in
    Typed

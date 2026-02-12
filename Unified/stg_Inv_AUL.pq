let
    // --- Dependencies ---
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

    FileContent = GetLatestFile(DemandPath, "Inventory by SKU", ".xls"), 
    Excel = Excel.Workbook(FileContent, null, true),
    Sheet = try Excel{[Item="Data"]} otherwise Excel{[Name="Data"]},
    Data = Sheet[Data],
    Promoted = Table.PromoteHeaders(Data, [PromoteAllScalars=true]),
    Renamed = Table.RenameColumns(Promoted, {{"SKU ID", "Product Code"}, {"x_qty_available", "Net Inventory"}}),
    WithWarehouse = Table.AddColumn(Renamed, "Warehouse", each "075-UL"),
    Selected = Table.SelectColumns(WithWarehouse, {"Product Code", "Net Inventory", "Warehouse"})
in
    Selected

let
    // --- Dependencies ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files"]}[Content],
    
    fn_GetLatestFile = #"01_Functions"[fn_GetLatestFile],

    FileContent = fn_GetLatestFile(DemandPath, "Inventory by SKU", ".xls"), 
    Excel = Excel.Workbook(FileContent, null, true),
    Sheet = try Excel{[Item="Data"]} otherwise Excel{[Name="Data"]},
    Data = Sheet[Data],
    Promoted = Table.PromoteHeaders(Data, [PromoteAllScalars=true]),
    Renamed = Table.RenameColumns(Promoted, {{"SKU ID", "Product Code"}, {"x_qty_available", "Net Inventory"}}),
    WithWarehouse = Table.AddColumn(Renamed, "Warehouse", each "075-UL"),
    Selected = Table.SelectColumns(WithWarehouse, {"Product Code", "Net Inventory", "Warehouse"})
in
    Selected

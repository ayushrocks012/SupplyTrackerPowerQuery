let
    // --- Dependencies ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files"]}[Content],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith(Text.Lower([Name]), EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    FileContent = GetLatestFile(DemandPath, "LX02", ".xlsx"),
    Excel = Excel.Workbook(FileContent, null, true),
    Sheet = try Excel{[Item="Sheet1"]} otherwise Excel{[Name="Sheet1"]}, 
    Data = Sheet[Data],
    Promoted = Table.PromoteHeaders(Data, [PromoteAllScalars=true]),
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

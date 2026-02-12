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

    FileContent = GetLatestFile(DemandPath, "Inventory Batch", ".xls"), // Source: "Inventory Batch..."
    Excel = Excel.Workbook(FileContent, null, true),
    Data_Record = 
        try Excel{[Item = "Data", Kind = "Sheet"]} 
        otherwise try Excel{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'",
    Data_Sheet = Data_Record[Data],
    
    Promoted = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Promoted, {{"Expiry", type date}, {"Qty", Int64.Type}, {"Qty Alloc", Int64.Type}}),
    WithWarehouse = Table.AddColumn(Typed, "Warehouse", each "075-UL"),

    // Storage Type Logic (AUL Specific)
    WithStorageType = Table.AddColumn(WithWarehouse, "Combined Storage Type", each
             if [Lock Code] = "" and [Zone] = "DESPATCH" then "ALLOCATED" 
        else if [Lock Code] = "" and [Zone] = "Goodsin" then "RECEIPT" 
        else if [Lock Code] = "BLOCKED" and Text.Contains([Zone], "RESCOPK") then "RESERVED FOR COPACK" 
        else if [Lock Code] = "" then "AVAILABLE" 
        else if [Lock Code] = "SHORTDATE" 
             or [Lock Code] = "DMGD" 
             or [Lock Code] = "BLOCKED" 
             or [Lock Code] = "QCHOLD" 
             or [Lock Code] = "EXPD" 
             or [Lock Code] = "SCRAP" then "SCHROTT"  
        else "NEW LOCK CODE TO BE ADDED"
    ),
    
    // Storage Bin Logic (AUL Specific)
    WithStorageBin = Table.AddColumn(WithStorageType, "Combined Storage Bin", each
             if [Combined Storage Type] = "AVAILABLE"  then "AVAILABLE" 
        else if [Combined Storage Type] = "RECEIPT"    then "AVAILABLE" 
        else if [Combined Storage Type] = "ALLOCATED"  then "ALLOCATED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "SHORTDATE" then "SHORTDATE" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "DMGD"      then "DAMAGED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "QCHOLD"    then "QA BLOCKED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "BLOCKED"   then "RETURN BLOCKED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "EXPD"      then "EXPIRED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "SCRAP"     then "SCRAP" 
        else "NEW LOCK CODE TO BE ADDED"
    ),

    WithNetInv = Table.AddColumn(WithStorageBin, "Net Inventory", each if [Qty] < 0 then 0 else [Qty] - [Qty Alloc]),
    
    // Selection and Grouping (AUL aggregates duplicates? Original code groups.)
    Renamed = Table.RenameColumns(WithNetInv, {{"Client Product Code", "Product Code"}}),
    
    // Original AUL_Inv_Batch logic grouped by these columns to sum Net Inventory
    Grouped = Table.Group(Renamed, {"Product Code", "Batch", "Expiry", "Warehouse", "Combined Storage Type", "Combined Storage Bin"}, {{"NET INVENTORY", each List.Sum([Net Inventory]), type nullable number}})
in
    Grouped

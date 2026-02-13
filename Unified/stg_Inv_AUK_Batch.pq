let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[DailyTracker],
    
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
    
    // Select relevant columns
    SelectedCols = Table.SelectColumns(Promoted,{"Material", "Batch", "Available stock", "Pick quantity", "SLED/BBD", "Storage Bin", "Storage Type"}),
    WithWarehouse = Table.AddColumn(SelectedCols, "Warehouse", each "075-UK"),

    // Storage Type Logic (AUK Specific)
    WithStorageType = Table.AddColumn(WithWarehouse, "Combined Storage Type", each 
             if [Storage Type] = "014" 							then "AVAILABLE"
        else if [Storage Type] = "011" 							then "AVAILABLE"
        else if [Storage Type] = "802" 							then "AVAILABLE"
        else if [Storage Type] = "200" 							then "ALLOCATED"
        else if [Storage Type] = "916" 							then "ALLOCATED"
        else if [Storage Type] = "922" 							then "BLOCKED"
        else if [Storage Type] = "904" 							then "SCHROTT" 
        else if [Storage Type] = "999" 							then "SCHROTT"
        else if [Storage Bin] = "STAGING"                       then "RECEIPT"
        else "NEW STORAGE TYPE TO BE DECIDED"
    ),
    
    // Storage Bin Logic (AUK Specific)
    WithStorageBin = Table.AddColumn(WithStorageType, "Combined Storage Bin", each 
             if [Combined Storage Type] = "ALLOCATED" then "ALLOCATED"
        else if [Combined Storage Type] = "BLOCKED" then "BLOCKED" 
        else if [Combined Storage Type] = "AVAILABLE" then "AVAILABLE"
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "DISPOSAL" then "SCRAP" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "DAMAGED" then "DAMAGED" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "CLOSEDOWN" then "INV RECON" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "DISPLAY" then "DISPLAY STOCK" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "GRIR" then "INV RECON" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "INVEST" then "UNDER INVESTIGATION" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "MOOG" then "FAILED PUMPS" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "PGI" then "CANCELLED PICK" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "QAHOLD" then "QCHOLD" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "QUERY" then "INV RECON" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "RETURNS" then "MANUAL RETURN ERROR" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "SCHROTT" then "SHORTDATE" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "TROLLEY" then "RETURN BLOCKED" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "APPROVED" then "DESTRUCTION"
        else if [Combined Storage Type] = "SCHROTT" and Text.StartsWith([Storage Bin], "NVP") then "INV RECON"
        else if [Combined Storage Type] = "SCHROTT" and [Storage Type] = "904" then "RETURN BLOCKED"
        else "NEW STORAGE BIN TO BE DECIDED"
    ),

    WithNetInv = Table.AddColumn(WithStorageBin, "NET INVENTORY", each [Available stock] + [Pick quantity]),
    
    // Final Selection and Renaming
    Renamed = Table.RenameColumns(WithNetInv, {{"Material", "Product Code"}, {"SLED/BBD", "Expiry"}}),
    FinalSelection = Table.SelectColumns(Renamed, {"Product Code", "Batch", "Expiry", "Warehouse", "Combined Storage Type", "Combined Storage Bin", "NET INVENTORY"})
in
    FinalSelection

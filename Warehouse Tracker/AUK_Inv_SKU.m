let
    Source = SharePoint.Files("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    FilteredRows = Table.SelectRows(Source, each 
        Text.StartsWith([Name], "LX02") and 
        Text.EndsWith(Text.Lower([Name]), ".xlsx") and
        [Folder Path] = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker Files/"),
    SortedRows = Table.Sort(FilteredRows, {"Date modified", Order.Descending}),
    LatestFile = Table.FirstN(SortedRows, 1),
    ExcelBinary = LatestFile{0}[Content],
    ExcelData = Excel.Workbook(ExcelBinary, null, true),
    Data_Sheet = ExcelData{[Item="Sheet1", Kind="Sheet"]}[Data],
    #"Promoted Headers" = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    #"Removed Other Columns" = Table.SelectColumns(#"Promoted Headers",{"Material", "Material Description", "Batch", "Available stock", "Pick quantity", "SLED/BBD", "Storage Bin", "Storage Type", "Plant"}),

    #"Added Warehouse" = Table.AddColumn(#"Removed Other Columns", "Warehouse", each "075-UK"),

    #"Added Net Inventory" = Table.AddColumn(#"Added Warehouse", "Net Inventory", each [Available stock] + [Pick quantity]),
    
    #"Added Combined Storage Type" = Table.AddColumn(#"Added Net Inventory", "Combined Storage Type", each 
        if [Storage Type] = "014" or [Storage Type] = "011" then "AVAILABLE" 
        else if [Storage Type] = "802" then "RECEIPT" 
        else if [Storage Type] = "916" then "ALLOCATED" 
        else if [Storage Type] = "999" then "SCHROTT"
        else "NEW STORAGE TYPE TO BE DECIDED"
    ),


    #"Added Combined Storage Bin" = Table.AddColumn(#"Added Combined Storage Type", "Combined Storage Bin", each 
        if [Combined Storage Type] = "AVAILABLE" then "AVAILABLE" 
        else if [Storage Bin] = "STAGING" then "RECEIPT" 
        else if [Combined Storage Type] = "ALLOCATED" then "ALLOCATED" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "DISPOSAL" then "SCRAP" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "DAMAGED" then "DAMAGED" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "CLOSEDOWN" then "ASK PHIL" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "DISPLAY" then "EXPIRED" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "GRIR" then "ASK PHIL" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "INVEST" then "ASK PHIL" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "MOOG" then "ASK PHIL" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "PGI" then "ASK PHIL" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "QAHOLD" then "QCHOLD" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "QUERY" then "ASK PHIL" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "RETURNS" then "RETURN BLOCKED" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "SCHROTT" then "SHORTDATE" 
        else if [Combined Storage Type] = "SCHROTT" and [Storage Bin] = "TROLLEY" then "RETURN BLOCKED" 
        else "NEW STORAGE BIN TO BE DECIDED"
    ),
    #"Removed Columns" = Table.RemoveColumns(#"Added Combined Storage Bin",{"Material Description", "Available stock", "Pick quantity", "Storage Bin", "Storage Type", "Plant"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"Material", "Product Code"}, {"SLED/BBD", "Expiry"}}),
    #"Filtered Rows" = Table.SelectRows(#"Renamed Columns", each ([Combined Storage Type] = "AVAILABLE" or [Combined Storage Type] = "RECEIPT")),
    #"Removed Columns1" = Table.RemoveColumns(#"Filtered Rows",{"Combined Storage Type", "Combined Storage Bin", "Batch", "Expiry"}),
    #"Grouped Rows" = Table.Group(#"Removed Columns1", {"Product Code", "Warehouse"}, {{"Total Net Inventory", each List.Sum([Net Inventory]), type number}})
in
    #"Grouped Rows"

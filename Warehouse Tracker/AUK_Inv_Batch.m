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
    #"Removed Other Columns" = Table.SelectColumns(#"Promoted Headers",{"Material", "Batch", "Available stock", "Pick quantity", "SLED/BBD", "Storage Bin", "Storage Type"}),

    #"Added Warehouse" = Table.AddColumn(#"Removed Other Columns", "Warehouse", each "075-UK"),

    
	#"Added Combined Storage Type" 
	= Table.AddColumn(#"Added Warehouse", "Combined Storage Type", each 
			 if [Storage Type] = "014" 							then "AVAILABLE"
		else if [Storage Type] = "011" 							then "AVAILABLE"
        else if [Storage Type] = "802" 							then "AVAILABLE"
        else if [Storage Type] = "200" 							then "ALLOCATED"
        else if [Storage Type] = "916" 							then "ALLOCATED"
        else if [Storage Type] = "922" 							then "BLOCKED"
        else if [Storage Type] = "904" 							then "SCHROTT" 
        else if [Storage Type] = "999" 							then "SCHROTT"
	    else if                       [Storage Bin] = "STAGING" then "RECEIPT"
        else "NEW STORAGE TYPE TO BE DECIDED"
    ),
    
	#"Added Combined Storage Bin" 
	= Table.AddColumn(#"Added Combined Storage Type", "Combined Storage Bin", each 
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


    #"Added Net Inventory" = Table.AddColumn(#"Added Combined Storage Bin", "NET INVENTORY", each [Available stock] + [Pick quantity]),
    #"Removed Columns" = Table.RemoveColumns(#"Added Net Inventory",{ "Available stock", "Pick quantity", "Storage Bin", "Storage Type"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"Material", "Product Code"}, {"SLED/BBD", "Expiry"}})
in
    #"Renamed Columns"

let
    Source = SharePoint.Files("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
	
    FilteredRows = Table.SelectRows(Source, each 
        Text.StartsWith([Name], "Inventory Batch") and 
        [Folder Path] = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker Files/"),
	
    SortedRows = Table.Sort(FilteredRows, {"Date modified", Order.Descending}),
    
	LatestFile = Table.FirstN(SortedRows, 1),
    
	ExcelBinary = LatestFile{0}[Content],
    
	ExcelData = Excel.Workbook(ExcelBinary, null, true),
    
	// Try both addressing styles so it works for .xlsx and .xls
    Data_Record = 
        try ExcelData{[Item = "Data", Kind = "Sheet"]} 
        otherwise try ExcelData{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'. Please check the sheet name.",

    Data_Sheet = Data_Record[Data],
    
    #"Promoted Headers" = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    
    #"Changed Type1" = Table.TransformColumnTypes(#"Promoted Headers",{{"Expiry", type date}, {"Qty", Int64.Type}, {"Qty Alloc", Int64.Type}}),
	
	#"Added Warehouse" = Table.AddColumn(#"Changed Type1", "Warehouse", each "075-UL"),

   #"Added Combined Storage Type" 
	= Table.AddColumn(#"Added Warehouse", "Combined Storage Type", each
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
        else "NEW LOCK CODE TO BE ADDED"),
    
    
	#"Added Combined Storage Bin" 
	= Table.AddColumn(#"Added Combined Storage Type", "Combined Storage Bin", each
             if [Combined Storage Type] = "AVAILABLE"  then "AVAILABLE" 
		else if [Combined Storage Type] = "RECEIPT"    then "AVAILABLE" 
        else if [Combined Storage Type] = "ALLOCATED"  then "ALLOCATED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "SHORTDATE" then "SHORTDATE" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "DMGD"      then "DAMAGED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "QCHOLD"    then "QA BLOCKED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "BLOCKED"   then "RETURN BLOCKED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "EXPD"      then "EXPIRED" 
        else if [Combined Storage Type] = "SCHROTT" and [Lock Code] = "SCRAP"     then "SCRAP" 
        else "NEW LOCK CODE TO BE ADDED"),
		

    #"Added Net Inventory" = Table.AddColumn(#"Added Combined Storage Bin", "Net Inventory", each if [Qty] < 0 then 0 else [Qty] - [Qty Alloc]),
	
    #"Removed Columns" = Table.RemoveColumns(#"Added Net Inventory",{"Client Product Code"}),
	
    #"Changed Type" = Table.TransformColumnTypes(#"Removed Columns",{{"Expiry", type date}, {"Qty", Int64.Type}, {"Qty Alloc", Int64.Type}, {"Net Inventory", Int64.Type}})
in
    #"Changed Type"

let
    Source = SharePoint.Files("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),

    // Filter only Excel files starting with "Completed Bookings"
    FilteredRows = Table.SelectRows(Source, each 
        Text.StartsWith([Name], "ABBOTT LINES SHIPPED PREV DAY") and 
        [Folder Path] = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker Files - Wholesaler/"),
    // Sort by Date modified descending
    SortedRows = Table.Sort(FilteredRows, {"Date modified", Order.Descending}),

    // Get the first (latest) file
    LatestFile = Table.FirstN(SortedRows, 1),

    // Dynamically access the binary content
    ExcelBinary = LatestFile{0}[Content],
    // Load the Excel workbook
    ExcelData = Excel.Workbook(ExcelBinary, null, true),

    
    // Try both addressing styles so it works for .xlsx and .xls
    Data_Record = 
        try ExcelData{[Item = "Data", Kind = "Sheet"]} 
        otherwise try ExcelData{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'. Please check the sheet name.",

    Data_Sheet = Data_Record[Data],
	
	
    #"Promoted Headers" = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    #"Filtered Rows" = Table.SelectRows(#"Promoted Headers", each Text.Contains([Name], "AAH", Comparer.OrdinalIgnoreCase)),
    #"Merged Queries" = Table.NestedJoin(#"Filtered Rows", {"Postcode"}, ValidationClients, {"Postcode"}, "ValidationClients", JoinKind.LeftOuter),
    #"Expanded ValidationClients" = Table.ExpandTableColumn(#"Merged Queries", "ValidationClients", {"Town"}, {"Town"})
in
    #"Expanded ValidationClients"

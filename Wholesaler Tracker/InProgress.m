let
    Source = SharePoint.Files("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),

    // Filter only Excel files starting with "Completed Bookings"
    FilteredRows = Table.SelectRows(Source, each 
        Text.StartsWith([Name], "ABBOTT LINES IN PROGRESS") and 
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
    #"Changed Type1" = Table.TransformColumnTypes(#"Promoted Headers",{{"Creation Date", type date}, {"Qty Ordered", Int64.Type}, {"Qty In Progress", Int64.Type}, {"Ship By Date", type date}}),
    #"Filtered Rows" = Table.SelectRows(#"Changed Type1", each Text.Contains([Name], "AAH", Comparer.OrdinalIgnoreCase)),
    #"Merged Queries" = Table.NestedJoin(#"Filtered Rows", {"Postcode"}, ValidationClients, {"Postcode"}, "ValidationClients", JoinKind.LeftOuter),
    #"Expanded ValidationClients" = Table.ExpandTableColumn(#"Merged Queries", "ValidationClients", {"Town"}, {"Town.1"}),
    #"Removed Columns" = Table.RemoveColumns(#"Expanded ValidationClients",{"Town"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"Town.1", "Town"}}),
    #"Changed Type" = Table.TransformColumnTypes(#"Renamed Columns",{{"Town", type text}})
in
    #"Changed Type"

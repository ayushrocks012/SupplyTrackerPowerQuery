let
    Source = SharePoint.Files(
        "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice",
        [ApiVersion = 15]
    ),

    // Keep files only from the target folder
    #"Filtered Rows" = Table.SelectRows(
        Source,
        each [Folder Path] = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/"
    ),

    // Pick the specific workbook by Name (and Folder Path just to be safe)
    #"AAH Bible File" = #"Filtered Rows"{[Name = "AAH Bible.xlsx", #"Folder Path" = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/"]}[Content],

    // Load workbook; set third arg to true to infer column types from the first 200 rows
    #"Imported Excel Workbook" = Excel.Workbook(#"AAH Bible File", null, true),

    // Get the table
    AUK_DeliveryPoints_Table = #"Imported Excel Workbook"{[Item = "AUK_DeliveryPoints", Kind = "Table"]}[Data],

    // Remove blank rows (all empty or null)
    #"Removed Blank Rows" = Table.SelectRows(
        AUK_DeliveryPoints_Table,
        each not List.IsEmpty(List.RemoveMatchingItems(Record.FieldValues(_), {"", null}))
    ),

    // **Key change**: filter rows where [Name] contains "AAH" (case-insensitive)
    #"Filtered Rows1" = Table.SelectRows(
        #"Removed Blank Rows",
        each [Name] <> null and Text.Contains([Name], "AAH", Comparer.OrdinalIgnoreCase)
    )
in
    #"Filtered Rows1"

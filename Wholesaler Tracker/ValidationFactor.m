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
    // Load workbook; set third arg to true to infer column types from the first 200 rows
    #"Validations Conversion Factor_Sheet" = #"Imported Excel Workbook"{[Item="Validations Conversion Factor",Kind="Sheet"]}[Data],
    #"Promoted Headers" = Table.PromoteHeaders(#"Validations Conversion Factor_Sheet", [PromoteAllScalars=true]),
    #"Renamed Columns" = Table.RenameColumns(#"Promoted Headers",{{"Factor", "Abbott Factor"}, {"Row Labels", "AAH Packsize"}})
in
    #"Renamed Columns"

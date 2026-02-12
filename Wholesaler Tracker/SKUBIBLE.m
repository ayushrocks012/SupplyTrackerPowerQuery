let
    // -------- PARAMETERS --------
    SiteUrl = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice",
    TargetFolderPath = {
        "Shared Documents",
        "General",
        "Demand"
    },
    TargetFileName = "SKU Bible V2.xlsx",

    // -------- NAVIGATE VIA SharePoint.Contents (robust + fast) --------
    Root   = SharePoint.Contents(SiteUrl, [ApiVersion = 15]),
    L0     = Root{[Name = TargetFolderPath{0}]}[Content],
    L1     = L0{[Name = TargetFolderPath{1}]}[Content],
    L2     = L1{[Name = TargetFolderPath{2}]}[Content],

    // At this level, rows are a mix of folders/files. Files have [Content] as binary.
    FilesHere = Table.SelectRows(L2, each Value.Is([Content], type binary)),

    // Pick the exact workbook by name (no need to sort); error if missing
    FileRow = 
        let r = Table.SelectRows(FilesHere, each [Name] = TargetFileName)
        in  if Table.IsEmpty(r) 
            then error "File '" & TargetFileName & "' not found in the target folder."
            else r{0},

    ExcelBinary = FileRow[Content],

    // -------- OPEN WORKBOOK --------
    WB = Excel.Workbook(ExcelBinary, null, true),

    // Use the named table "SKUBIBLE" directly (safer than sheets)
    SKUBIBLE_Table = 
        try WB{[Item = "SKUBIBLE", Kind = "Table"]}[Data] 
        otherwise error "Table 'SKUBIBLE' was not found in '" & TargetFileName & "'.",

    // -------- FILTER + TYPES --------
    #"Filtered Rows" = Table.SelectRows(SKUBIBLE_Table, each [AFFILIATE] = "UNITED KINGDOM"),
    #"Changed Type"  = Table.TransformColumnTypes(#"Filtered Rows", {{"ECC CODE", type text}})
in
    #"Changed Type"

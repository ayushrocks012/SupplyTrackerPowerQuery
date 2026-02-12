let
    // --- Dependencies (Hardcoded) ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="DMF New"]}[Content],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith(Text.Lower([Name]), EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    FileContent = GetLatestFile(DemandPath, "MasterMassiveNew", ".xlsb"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    // FIX: Correct Table/Sheet Name. Original was "MergedData".
    // Try "MergedData" as Item (Table) first, then as Sheet if needed.
    Table = try Excel{[Item="MergedData", Kind="Table"]}[Data] 
            otherwise Excel{[Name="MergedData"]}[Data],
    
    // Logic from MergedData.m
    FilteredRows = Table.SelectRows(Table, each ([#"Location/Plant/Site"] = "075-UK" or [#"Location/Plant/Site"] = "075-UL")),
    CleanedDate = Table.TransformColumns(FilteredRows,{{"RowDate", each Date.From(_), type date}}),
    
    // Merging with SKUBIBLE (V2 or V3? Original used V2)
    SKUBible = dim_SKUBible_V2, // Dependency on dim_SKUBible_V2
    Merged = Table.NestedJoin(CleanedDate, {"ECC CODE"}, SKUBible, {"ECC CODE"}, "SKUBIBLE", JoinKind.LeftOuter),
    Expanded = Table.ExpandTableColumn(Merged, "SKUBIBLE", {"DESCRIPTION"}, {"DESCRIPTION"}),
    
    Typed = Table.TransformColumnTypes(Expanded,{{"Data", Int64.Type}, {"RowDate", type date}})
in
    Typed

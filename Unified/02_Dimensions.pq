let
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    SharedDocs = Source{[Name="Shared Documents"]}[Content],
    General = SharedDocs{[Name="General"]}[Content],
    Demand = General{[Name="Demand"]}[Content],

    // Function to load Excel Table
    fn_LoadTable = (Folder as table, FileName as text, TableName as text) =>
        let
            File = Folder{[Name=FileName]}[Content],
            Workbook = Excel.Workbook(File, null, true),
            Table = Workbook{[Item=TableName, Kind="Table"]}[Data]
        in
            Table,

    // Dimensions
    dim_SKUBible_V2 = Table.SelectRows(fn_LoadTable(Demand, "SKU Bible V2.xlsx", "SKUBIBLE"), each [AFFILIATE] = "UNITED KINGDOM"),
    dim_SKUBible_V3 = Table.SelectRows(fn_LoadTable(Demand, "SKU Bible V3.xlsx", "SKUBIBLE"), each [AFFILIATE] = "UNITED KINGDOM"),
    
    // Wholesaler Dimensions (Source: AAH Bible.xlsx)
    dim_ValidationClients = 
        let
            SourceFile = Demand{[Name="AAH Bible.xlsx"]}[Content],
            Workbook = Excel.Workbook(SourceFile, null, true),
            Table = Workbook{[Item="AUK_DeliveryPoints", Kind="Table"]}[Data],
            Cleaned = Table.SelectRows(Table, each not List.IsEmpty(List.RemoveMatchingItems(Record.FieldValues(_), {"", null}))),
            Filtered = Table.SelectRows(Cleaned, each [Name] <> null and Text.Contains([Name], "AAH", Comparer.OrdinalIgnoreCase))
        in
            Filtered,

    dim_ValidationFactor = 
        let
            SourceFile = Demand{[Name="AAH Bible.xlsx"]}[Content],
            Workbook = Excel.Workbook(SourceFile, null, true),
            Sheet = Workbook{[Item="Validations Conversion Factor", Kind="Sheet"]}[Data],
            Promoted = Table.PromoteHeaders(Sheet, [PromoteAllScalars=true]),
            Renamed = Table.RenameColumns(Promoted, {{"Factor", "Abbott Factor"}, {"Row Labels", "AAH Packsize"}})
        in
            Renamed
in
    [
        dim_SKUBible_V2 = dim_SKUBible_V2,
        dim_SKUBible_V3 = dim_SKUBible_V3,
        dim_ValidationClients = dim_ValidationClients,
        dim_ValidationFactor = dim_ValidationFactor
    ]

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
    
    // Wholesaler Dimensions
    dim_ValidationClients = fn_LoadTable(Demand, "ValidationClients.xlsx", "ValidationClients"), // Hypothetical path, verifying later
    dim_ValidationFactor = fn_LoadTable(Demand, "ValidationFactor.xlsx", "ValidationFactor")
in
    [
        dim_SKUBible_V2 = dim_SKUBible_V2,
        dim_SKUBible_V3 = dim_SKUBible_V3,
        dim_ValidationClients = dim_ValidationClients,
        dim_ValidationFactor = dim_ValidationFactor
    ]

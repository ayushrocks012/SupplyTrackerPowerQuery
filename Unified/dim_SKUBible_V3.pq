let
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    Demand = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content],
    File = Demand{[Name="SKU Bible V3.xlsx"]}[Content],
    Workbook = Excel.Workbook(File, null, true),
    Table = Workbook{[Item="SKUBIBLE", Kind="Table"]}[Data],
    Filtered = Table.SelectRows(Table, each [AFFILIATE] = "UNITED KINGDOM")
in
    Filtered

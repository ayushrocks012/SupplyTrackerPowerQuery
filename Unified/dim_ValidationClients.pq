let
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    Demand = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content],
    SourceFile = Demand{[Name="AAH Bible.xlsx"]}[Content],
    Workbook = Excel.Workbook(SourceFile, null, true),
    Table = Workbook{[Item="AUK_DeliveryPoints", Kind="Table"]}[Data],
    Cleaned = Table.SelectRows(Table, each not List.IsEmpty(List.RemoveMatchingItems(Record.FieldValues(_), {"", null}))),
    Filtered = Table.SelectRows(Cleaned, each [Name] <> null and Text.Contains([Name], "AAH", Comparer.OrdinalIgnoreCase))
in
    Filtered

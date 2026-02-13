let
    Demand = fn_SharePointBase[Demand],
    File = Demand{[Name="SKU Bible V2.xlsx"]}[Content],
    Workbook = Excel.Workbook(File, null, true),
    Table = Workbook{[Item="SKUBIBLE", Kind="Table"]}[Data],
    Filtered = Table.SelectRows(Table, each [AFFILIATE] = "UNITED KINGDOM")
in
    Table.Buffer(Filtered)

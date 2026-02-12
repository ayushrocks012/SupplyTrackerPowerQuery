let
    Source = #"PBI Warehouse",
    #"Removed Other Columns" = Table.SelectColumns(Source,{"Inbound Warehouse", "Inbound Status", "ECC CODE", "Units"}),
    #"Filtered Rows" = Table.SelectRows(#"Removed Other Columns", each ([Inbound Status] = "Inbound - Current Week" or [Inbound Status] = "Inbound - Next Week")),
    #"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"Inbound Status"}),
    #"Grouped Rows" = Table.Group(#"Removed Columns", {"Inbound Warehouse", "ECC CODE"}, {{"OnOrderQty", each List.Sum([Units]), type nullable number}})
in
    #"Grouped Rows"

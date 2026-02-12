let
    Source = MergedData,
    #"Removed Other Columns" = Table.SelectColumns(Source,{"ECC CODE", "Location/Plant/Site", "Data", "Key Figures", "Calendar year", "Calendar month", "APO Customer", "RowDate"}),
    #"Filtered Rows" = Table.SelectRows(#"Removed Other Columns", each Date.IsInCurrentMonth([RowDate])),
    #"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"Key Figures", "Calendar year", "Calendar month", "APO Customer"}),
    #"Grouped Rows" = Table.Group(#"Removed Columns", {"ECC CODE", "Location/Plant/Site", "RowDate"}, {{"CurrMonthADS", each List.Sum([Data]), type nullable number}})
in
    #"Grouped Rows"

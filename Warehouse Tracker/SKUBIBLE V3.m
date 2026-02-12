let
    Source = Excel.Workbook(Web.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared%20Documents/General/Demand/SKU%20Bible%20V3.xlsx"), null, true),
    SKUBIBLE_Table = Source{[Item="SKUBIBLE",Kind="Table"]}[Data],
    #"Filtered Rows" = Table.SelectRows(SKUBIBLE_Table, each ([AFFILIATE] = "UNITED KINGDOM"))
in
    #"Filtered Rows"

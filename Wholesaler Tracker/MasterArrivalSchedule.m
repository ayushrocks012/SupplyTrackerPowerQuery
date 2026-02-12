let
    Source = SharePoint.Files("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    #"Filtered Rows" = Table.SelectRows(Source, each ([Folder Path] = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker - Master Arrival Schedule/")),
    #"Master Arrival Schedule PBI xlsx_https://abbott sharepoint com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker - Master Arrival Schedule/" = #"Filtered Rows"{[Name="Master Arrival Schedule PBI.xlsx",#"Folder Path"="https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker - Master Arrival Schedule/"]}[Content],
    #"Imported Excel Workbook" = Excel.Workbook(#"Master Arrival Schedule PBI xlsx_https://abbott sharepoint com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker - Master Arrival Schedule/"),
    Table1_Table = #"Imported Excel Workbook"{[Item="Table1",Kind="Table"]}[Data],
    #"Removed Other Columns" = Table.SelectColumns(Table1_Table,{"FACT_Shipment_Actuals[Invoice]", "FACT_Shipment_Actuals[Ship_To_Address1]", "FACT_Shipment_Actuals[Ship_To_Address2]", "FACT_Shipment_Actuals[Ship_To_Address3]", "DIM_ProductMaster[MK_PRODUCT]"})
in
    #"Removed Other Columns"

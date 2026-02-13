let
    // --- Dependencies (Hardcoded) ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker - Master Arrival Schedule"]}[Content],
    
    // Original code hardcoded filename "Master Arrival Schedule PBI.xlsx"
    File = DemandPath{[Name="Master Arrival Schedule PBI.xlsx"]}[Content],
    Excel = Excel.Workbook(File, null, true),
    Table = Excel{[Item="Table1", Kind="Table"]}[Data],
    
    Selected = Table.SelectColumns(Table,{"FACT_Shipment_Actuals[Invoice]", "FACT_Shipment_Actuals[Ship_To_Address1]", "FACT_Shipment_Actuals[Ship_To_Address2]", "FACT_Shipment_Actuals[Ship_To_Address3]", "DIM_ProductMaster[MK_PRODUCT]"})
in
    Selected

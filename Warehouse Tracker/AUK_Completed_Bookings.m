let
    // Connect to SharePoint root
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),

    // Navigate to folder where Completed Bookings files reside
    SharedDocs = Source{[Name="Shared Documents"]}[Content],
    GeneralFolder = SharedDocs{[Name="General"]}[Content],
    DemandFolder = GeneralFolder{[Name="Demand"]}[Content],
    MasterDataFolder = DemandFolder{[Name="Master Data Files"]}[Content],
    DailyTrackerFolder = MasterDataFolder{[Name="Daily Tracker Files"]}[Content],

    // Filter only Excel files starting with "Completed Bookings"
    FilteredFiles = Table.SelectRows(DailyTrackerFolder, each Text.StartsWith([Name], "Completed Bookings") and Text.EndsWith([Name], ".xls")),

    // Sort by Date modified descending and get latest file
    LatestFile = Table.First(Table.Sort(FilteredFiles, {{"Date modified", Order.Descending}}))[Content],

    // Load Excel workbook and select "Data" sheet
    ExcelData = Excel.Workbook(LatestFile, null, true),
    // Try both addressing styles so it works for .xlsx and .xls
    Data_Record = 
        try ExcelData{[Item = "Data", Kind = "Sheet"]} 
        otherwise try ExcelData{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'. Please check the sheet name.",

    Data_Sheet = Data_Record[Data],

    // Promote headers and set types
    PromotedHeaders = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    // Remove unnecessary columns
    RemovedColumns = Table.RemoveColumns(PromotedHeaders,{"Pallet Qty", "Pallets Delivered", "Schedule Dstamp", "Schedule Duration", "Arrival", "Onsite", "Onsite Duration"}),
    ChangedTypes = Table.TransformColumnTypes(RemovedColumns,{
        {"Booking Reference", type text}, {"Carrier", type text}, {"Status", type text}
    })
in
    ChangedTypes

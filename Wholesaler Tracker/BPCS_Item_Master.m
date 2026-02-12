let
    Source = SharePoint.Files("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),

    // Filter only Excel files starting with "Completed Bookings"
    FilteredRows = Table.SelectRows(Source, each 
        Text.StartsWith([Name], "Item Masters BPCS") and 
        Text.EndsWith([Name], ".xlsx") and
        [Folder Path] = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker - Master Data/"),
    // Sort by Date modified descending
    SortedRows = Table.Sort(FilteredRows, {"Date modified", Order.Descending}),

    // Get the first (latest) file
    LatestFile = Table.FirstN(SortedRows, 1),

    // Dynamically access the binary content
    ExcelBinary = LatestFile{0}[Content],

    // Load the Excel workbook
    ExcelData = Excel.Workbook(ExcelBinary, null, true),
    // Load the Excel workbook
    page_Sheet = ExcelData{[Item="page",Kind="Sheet"]}[Data],
    #"Promoted Headers" = Table.PromoteHeaders(page_Sheet, [PromoteAllScalars=true]),
    #"Added Custom" = Table.AddColumn(#"Promoted Headers", "BPCS Units per Layer", each [BPCS Units per Case]*[BPCS Cases per Layer]),
    #"Removed Columns" = Table.RemoveColumns(#"Added Custom",{"Product Description", "Pallet Type", "BPCS Cases per Layer", "Product Family", "BPCS Unit Weight", "BPCS Unit Width", "BPCS Unit Depth", "BPCS Unit Height", "BPCS Pallet Type", "IHAZRD", "BPCS DGR Class", "BPCS UN ID", "CREATOR", "ISTAGE", "Pallet Stacking", "Pack Size", "Size Description", "Height Class", "Standard Cost", "Currency"})
in
    #"Removed Columns"

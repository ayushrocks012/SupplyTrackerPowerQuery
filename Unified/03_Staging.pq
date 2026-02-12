let
    // --- Dependencies ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files"]}[Content],
    
    // --- Helper ---
    fn_GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    // --- Staging Queries ---

    // 1. A2B Inbound (Unified)
    stg_Inbound_A2B = 
        let
            FileContent = fn_GetLatestFile(DemandPath, "booking_overview", ".csv"),
            Csv = Csv.Document(FileContent, [Delimiter=",", Encoding=1252, QuoteStyle=QuoteStyle.Csv]),
            Promoted = Table.PromoteHeaders(Csv, [PromoteAllScalars=true]),
            Duplicated = Table.DuplicateColumn(Promoted, "Your Reference", "Your Reference - Copy"),
            Split = Table.SplitColumn(Duplicated, "Your Reference - Copy", Splitter.SplitTextByDelimiter(" / ", QuoteStyle.Csv), {"Breda Tour", "Departure"}),
            Renamed = Table.RenameColumns(Split, {{"Status", "Sub status"}, {"Delivery Date", "Expected Delivery Date"}}),
            WithStatus = Table.AddColumn(Renamed, "Status", each 
                if [Sub status] = "Accepted" then "Pending & Accepted" 
                else if [Sub status] = "Collected" then "Collected" 
                else if [Sub status] = "Completed" then "Delivered" 
                else if List.Contains({"Departed", "Discharged", "Terminal In", "Terminal Out"}, [Sub status]) then "Collected" 
                else [Sub status]
            ),
            WithLocation = Table.AddColumn(WithStatus, "Location", each
                let
                    podText = if [POD] = null then null else Text.Trim(Text.From([POD])),
                    podIsMissing = (podText = null) or (podText = "") or (podText = "0")
                in
                    if [Breda Tour] = null or Text.Trim([Breda Tour]) = "" then "" 
                    else if [Sub status] = "Accepted" then "Breda"
                    else if List.Contains({"Collected", "Departed"}, [Sub status]) then "In-Transit to EU Dock" 
                    else if [Sub status] = "Terminal In" then "At EU Dock" 
                    else if [Sub status] = "Discharged" then "On Ferry" 
                    else if [Sub status] = "Terminal Out" then "At UK Dock" 
                    else if [Sub status] = "Completed" and podIsMissing then "A2B POD Required"
                    else if [Sub status] = "Completed" then "Delivered"
                    else "Check Location"
            ),
            Typed = Table.TransformColumnTypes(WithLocation, {
                {"Collection Date", type date}, 
                {"Expected Delivery Date", type date}, 
                {"Sailing Date", type date}, 
                {"Departure", Int64.Type}
            })
        in
            Typed,

    // 2. Inventory AUK (Reads 'Completed Bookings' *.xls)
    stg_Inv_AUK = 
        let
            FileContent = fn_GetLatestFile(DemandPath, "Completed Bookings", ".xls"),
            Excel = Excel.Workbook(FileContent, null, true),
            Sheet = try Excel{[Item="Data"]} otherwise Excel{[Name="Data"]}, 
            Data = Sheet[Data],
            Promoted = Table.PromoteHeaders(Data, [PromoteAllScalars=true]),
            // Columns: Material, Batch, Available stock...
            Renamed = Table.RenameColumns(Promoted, {{"Material", "Product Code"}, {"Batch", "Batch ID"}, {"Available stock", "Stock"}, {"Pick quantity", "Pick Qty"}}),
            WithWarehouse = Table.AddColumn(Renamed, "Warehouse", each "075-UK"),
            NetInv = Table.AddColumn(WithWarehouse, "Net Inventory", each [Stock] + [Pick Qty]),
            Selected = Table.SelectColumns(NetInv, {"Product Code", "Batch ID", "Net Inventory", "Warehouse", "SLED/BBD"})
        in
            Selected,

    // 3. Inventory AUL (Reads 'Inventory by SKU' *.xls)
    stg_Inv_AUL = 
        let
            FileContent = fn_GetLatestFile(DemandPath, "Inventory by SKU", ".xls"), 
            Excel = Excel.Workbook(FileContent, null, true),
            Sheet = try Excel{[Item="Data"]} otherwise Excel{[Name="Data"]},
            Data = Sheet[Data],
            Promoted = Table.PromoteHeaders(Data, [PromoteAllScalars=true]),
            // Columns: SKU ID, x_qty_available...
            Renamed = Table.RenameColumns(Promoted, {{"SKU ID", "Product Code"}, {"x_qty_available", "Net Inventory"}}),
            WithWarehouse = Table.AddColumn(Renamed, "Warehouse", each "075-UL"),
            // AUL file doesn't seem to have Batch or Expiry in the SKU view, need to check AUL_Inv_Batch for that?
            // For now, mapping what we have.
            Selected = Table.SelectColumns(WithWarehouse, {"Product Code", "Net Inventory", "Warehouse"})
        in
            Selected
in
    [
        stg_Inbound_A2B = stg_Inbound_A2B,
        stg_Inv_AUK = stg_Inv_AUK,
        stg_Inv_AUL = stg_Inv_AUL
    ]

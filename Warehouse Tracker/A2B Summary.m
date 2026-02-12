let
    // === Connect to SharePoint via Contents ===
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    Folder = Source{[Name="Shared Documents"]}[Content],
    DemandFolder = Folder{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files"]}[Content],

    // === Filter for booking_overview CSV files ===
    FilteredFiles = Table.SelectRows(DemandFolder, each Text.StartsWith([Name], "booking_overview") and Text.EndsWith([Name], ".csv")),
    LatestFile = Table.First(Table.Sort(FilteredFiles, {{"Date modified", Order.Descending}}))[Content],

    // === Load CSV ===
    CsvData = Csv.Document(LatestFile, [Delimiter=",", Encoding=1252, QuoteStyle=QuoteStyle.Csv]),
    PromotedHeaders = Table.PromoteHeaders(CsvData, [PromoteAllScalars=true]),

    // === Transformations ===
    DuplicatedColumn = Table.DuplicateColumn(PromotedHeaders, "Your Reference", "Your Reference - Copy"),
    SplitColumn = Table.SplitColumn(DuplicatedColumn, "Your Reference - Copy", Splitter.SplitTextByDelimiter(" / ", QuoteStyle.Csv), {"Breda Tour", "Departure"}),
    RenamedColumns = Table.RenameColumns(SplitColumn, {{"Status", "Sub status"}, {"Delivery Date", "Expected Delivery Date"}}),

    WithStatus = Table.AddColumn(RenamedColumns, "Status", each 
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

    AddedCustom = Table.AddColumn(WithLocation, "Custom Cleared Status", each if [Customs Cleared]= "" then "No" else "Yes"),
    RemovedOtherColumns = Table.SelectColumns(AddedCustom, {"Booking ID", "Your Reference", "Collection Date", "Expected Delivery Date", "Sailing Date", "Breda Tour", "Departure", "Status", "Location", "Custom Cleared Status"}),
    ChangedType = Table.TransformColumnTypes(RemovedOtherColumns, {{"Collection Date", type date}, {"Expected Delivery Date", type date}, {"Sailing Date", type date}, {"Departure", Int64.Type}})
in
    ChangedType

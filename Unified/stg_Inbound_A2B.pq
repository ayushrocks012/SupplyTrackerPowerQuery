let
    // --- Dependencies ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files"]}[Content],
    
    // --- Helper ---
    fn_GetLatestFile = #"01_Functions"[fn_GetLatestFile], // Assumes 01_Functions record is still used, or we inline it. 
    // User stuck with record for functions/params?
    // User said "separate queries... for easy in begineer understanding".
    // I will stick to referencing the record query for functions as that's cleaner than duplicating function code.
    
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
    // FIX: Add Custom Cleared Status
    WithCustoms = Table.AddColumn(WithLocation, "Custom Cleared Status", each if [Customs Cleared]= "" then "No" else "Yes"),
    
    Typed = Table.TransformColumnTypes(WithCustoms, {
        {"Collection Date", type date}, 
        {"Expected Delivery Date", type date}, 
        {"Sailing Date", type date}, 
        {"Departure", Int64.Type}
    })
in
    Typed

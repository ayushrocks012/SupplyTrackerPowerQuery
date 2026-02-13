let
    // --- Dependencies (Hardcoded) ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files"]}[Content],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    FileContent = GetLatestFile(DemandPath, "booking_overview", ".csv"),
    Csv = Csv.Document(FileContent, [Delimiter=",", Encoding=1252, QuoteStyle=QuoteStyle.Csv]),
    Promoted = Table.PromoteHeaders(Csv, [PromoteAllScalars=true]),
    Duplicated = Table.DuplicateColumn(Promoted, "Your Reference", "Your Reference - Copy"),
    
    // FIX: Robust Split Logic
    // 1. Normalize dividers to Space
    Normalized = Table.TransformColumns(Duplicated, {{
        "Your Reference - Copy", 
        each 
            let
                s0 = if _ = null then "" else _,
                s1 = Text.Replace(s0, "#(00A0)", " "), // NBSP -> Space
                s2 = Text.Replace(s1, " / ", " "),    // " / " -> Space
                s3 = Text.Clean(s2),                  // Remove controls (tab/CR/LF)
                s4 = Text.Trim(s3)                    // Trim edges
            in
                s4,
        type text
    }}),
    
    // 2. Tokenize by Space and take Last as Departure
    Split = Table.AddColumn(Normalized, "TempSplit", each 
        let
            original = [#"Your Reference - Copy"],
            parts = Text.Split(original, " "),
            nonEmpty = List.Select(parts, each _ <> ""),
            count = List.Count(nonEmpty),
            // Logic: If > 1 token, assume last is Departure. If 1 token, check if it looks numeric?
            // For now, simpler: If > 1 token, take last. If 1, assume it's just Tour (no Departure).
            // This aligns with "TGB66-2950 610157" -> TGB=Tour, 610157=Dep.
            departure = if count > 1 then List.Last(nonEmpty) else null,
            tour = if count > 1 then Text.Combine(List.RemoveLastN(nonEmpty, 1), " ") else original
        in
            [Breda Tour=tour, Departure=departure]
    ),
    
    Expanded = Table.ExpandRecordColumn(Split, "TempSplit", {"Breda Tour", "Departure"}),
    
    // Proceed with Renaming
    Renamed = Table.RenameColumns(Expanded, {{"Status", "Sub status"}, {"Delivery Date", "Expected Delivery Date"}}),
    
    // Filter Grand Total
    FilteredRows = Table.SelectRows(Renamed, each ([Booking ID] <> "Grand Total" and [Booking ID] <> "Total")),

    WithStatus = Table.AddColumn(FilteredRows, "Status", each 
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
    WithCustoms = Table.AddColumn(WithLocation, "Custom Cleared Status", each if [Customs Cleared]= "" then "No" else "Yes"),
    
    Typed = Table.TransformColumnTypes(WithCustoms, {
        {"Collection Date", type date}, 
        {"Expected Delivery Date", type date}, 
        {"Sailing Date", type date}, 
        {"Departure", Int64.Type}
    }),
    
    Selected = Table.SelectColumns(Typed, {"Booking ID", "Your Reference", "Collection Date", "Expected Delivery Date", "Sailing Date", "Breda Tour", "Departure", "Status", "Location", "Custom Cleared Status"})
in
    Selected

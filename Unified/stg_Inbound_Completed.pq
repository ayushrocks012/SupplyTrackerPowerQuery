let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[DailyTracker],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    FileContent = GetLatestFile(DemandPath, "Completed Bookings", ".xls"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    Data_Record = 
        try Excel{[Item = "Data", Kind = "Sheet"]} 
        otherwise try Excel{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'",
    
    Data_Sheet = Data_Record[Data],

    Promoted = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    
    // FIX: Match original AUK_Completed_Bookings.m logic (Remove specific columns, keep rest)
    // Original Removed: "Pallet Qty", "Pallets Delivered", "Schedule Dstamp", "Schedule Duration", "Arrival", "Onsite", "Onsite Duration"
    // This avoids "Column not found" errors for columns I assumed existed (like "Delivery Date").
    
    Removed = Table.RemoveColumns(Promoted, {"Pallet Qty", "Pallets Delivered", "Schedule Dstamp", "Schedule Duration", "Arrival", "Onsite", "Onsite Duration"}, MissingField.Ignore),
    
    Typed = Table.TransformColumnTypes(Removed,{
        {"Booking Reference", type text}, 
        {"Carrier", type text}, 
        {"Status", type text}
    })
in
    Typed

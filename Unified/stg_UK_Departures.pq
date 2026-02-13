let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[UKDepartures],

    FileContent = fn_GetLatestFile(DemandPath, "UK Departures", ".xlsx"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    Sheet = try Excel{[Item="Warehouse", Kind="Sheet"]}[Data] 
            otherwise Excel{[Name="Warehouse"]}[Data],
            
    // FIX: Skip 1 row before promoting headers (matching PBI Warehouse.m)
    Skipped = Table.Skip(Sheet, 1),
    
    Promoted = Table.PromoteHeaders(Skipped, [PromoteAllScalars=true]),
    
    // Clean Empty Rows
    Cleaned = Table.SelectRows(Promoted, each not List.IsEmpty(List.RemoveMatchingItems(Record.FieldValues(_), {"", null}))),

    // Filter "Grand Total"
    Filtered = Table.SelectRows(Cleaned, each [ETD] <> "Grand Total" and [ETD] <> "Total"),
    
    // Type Transformation
    Typed = Table.TransformColumnTypes(Filtered,{
        {"ETD", type date}, 
        {"DEPARTURE", Int64.Type}, 
        {"Price", type number}, 
        {"Units", type number}, 
        {"Breda Tour", type text}, 
        {"1633 Item Code", type text}, 
        {"Breda Status Date", type date}, 
        {"EXP_DATE", type date}, 
        {"MFG_DATE", type date},
        {"FORWARDER", type text},
        {"Port of Discharge", type text},
        {"INVOICE", type text}
    })
in
    Typed

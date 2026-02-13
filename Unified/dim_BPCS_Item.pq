let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[MasterData],
    
    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    FileContent = GetLatestFile(DemandPath, "Item Masters BPCS", ".xlsx"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    Data_Sheet = Excel{[Item="page",Kind="Sheet"]}[Data],
    
    Promoted = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    
    // Custom Calculation
    // [BPCS Units per Layer] = [BPCS Units per Case]*[BPCS Cases per Layer]
    WithCustom = Table.AddColumn(Promoted, "BPCS Units per Layer", each [BPCS Units per Case]*[BPCS Cases per Layer]),
    
    // Remove specific columns
    Removed = Table.RemoveColumns(WithCustom,{"Product Description", "Pallet Type", "BPCS Cases per Layer", "Product Family", "BPCS Unit Weight", "BPCS Unit Width", "BPCS Unit Depth", "BPCS Unit Height", "BPCS Pallet Type", "IHAZRD", "BPCS DGR Class", "BPCS UN ID", "CREATOR", "ISTAGE", "Pallet Stacking", "Pack Size", "Size Description", "Height Class", "Standard Cost", "Currency"})
in
    Removed

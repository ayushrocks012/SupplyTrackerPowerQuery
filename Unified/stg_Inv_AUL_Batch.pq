let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[DailyTracker],
    
    FileContent = fn_GetLatestFile(DemandPath, "Inventory Batch", ".xls"), // Source: "Inventory Batch..."
    Excel = Excel.Workbook(FileContent, null, true),
    Data_Record = 
        try Excel{[Item = "Data", Kind = "Sheet"]} 
        otherwise try Excel{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'",
    Data_Sheet = Data_Record[Data],
    
    Promoted = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    // #8: Schema pruning — select only needed columns
    SelectedCols = Table.SelectColumns(Promoted, {"Product Code", "Batch", "Expiry", "Lock Code", "Zone", "Qty", "Qty Alloc"}, MissingField.Ignore),
    Typed = Table.TransformColumnTypes(SelectedCols, {{"Expiry", type date}, {"Qty", Int64.Type}, {"Qty Alloc", Int64.Type}}),

    // #4: Single-pass enrichment (replaces 4 chained Table.AddColumn)
    Enriched = Table.FromRecords(
        Table.TransformRows(Typed, (row) =>
            let
                lockCode = row[Lock Code],
                zone = row[Zone],
                qty = row[Qty],
                qtyAlloc = row[Qty Alloc],

                storageType =
                    if lockCode = "" and zone = "DESPATCH" then "ALLOCATED"
                    else if lockCode = "" and zone = "Goodsin" then "RECEIPT"
                    else if lockCode = "BLOCKED" and Text.Contains(zone, "RESCOPK") then "RESERVED FOR COPACK"
                    else if lockCode = "" then "AVAILABLE"
                    else if lockCode = "SHORTDATE" or lockCode = "DMGD" or lockCode = "BLOCKED"
                         or lockCode = "QCHOLD" or lockCode = "EXPD" or lockCode = "SCRAP" then "SCHROTT"
                    else "NEW LOCK CODE TO BE ADDED",

                storageBin =
                    if storageType = "AVAILABLE" then "AVAILABLE"
                    else if storageType = "RECEIPT" then "AVAILABLE"
                    else if storageType = "ALLOCATED" then "ALLOCATED"
                    else if storageType = "SCHROTT" and lockCode = "SHORTDATE" then "SHORTDATE"
                    else if storageType = "SCHROTT" and lockCode = "DMGD" then "DAMAGED"
                    else if storageType = "SCHROTT" and lockCode = "QCHOLD" then "QA BLOCKED"
                    else if storageType = "SCHROTT" and lockCode = "BLOCKED" then "RETURN BLOCKED"
                    else if storageType = "SCHROTT" and lockCode = "EXPD" then "EXPIRED"
                    else if storageType = "SCHROTT" and lockCode = "SCRAP" then "SCRAP"
                    else "NEW LOCK CODE TO BE ADDED",

                netInv = if qty < 0 then 0 else qty - qtyAlloc
            in
                Record.Combine({row, [
                    Warehouse = "075-UL",
                    #"Combined Storage Type" = storageType,
                    #"Combined Storage Bin" = storageBin,
                    #"Net Inventory" = netInv
                ]})
        )
    ),

    // Original AUL_Inv_Batch logic grouped by these columns to sum Net Inventory
    Grouped = Table.Group(Enriched, {"Product Code", "Batch", "Expiry", "Warehouse", "Combined Storage Type", "Combined Storage Bin"}, {{"NET INVENTORY", each List.Sum([Net Inventory]), type nullable number}})
in
    Grouped

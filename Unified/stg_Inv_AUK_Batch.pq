let
    // --- Dependencies (Shared Base) ---
    Promoted = base_LX02_Raw,
    
    // Select relevant columns
    SelectedCols = Table.SelectColumns(Promoted,{"Material", "Batch", "Available stock", "Pick quantity", "SLED/BBD", "Storage Bin", "Storage Type"}),

    // #4: Single-pass enrichment (replaces 4 chained Table.AddColumn)
    Enriched = Table.FromRecords(
        Table.TransformRows(SelectedCols, (row) =>
            let
                stType = row[Storage Type],
                stBin = row[Storage Bin],
                avail = row[Available stock],
                pick = row[Pick quantity],

                storageType =
                    if stType = "014" or stType = "011" or stType = "802" then "AVAILABLE"
                    else if stType = "200" or stType = "916" then "ALLOCATED"
                    else if stType = "922" then "BLOCKED"
                    else if stType = "904" or stType = "999" then "SCHROTT"
                    else if stBin = "STAGING" then "RECEIPT"
                    else "NEW STORAGE TYPE TO BE DECIDED",

                storageBin =
                    if storageType = "ALLOCATED" then "ALLOCATED"
                    else if storageType = "BLOCKED" then "BLOCKED"
                    else if storageType = "AVAILABLE" then "AVAILABLE"
                    else if storageType = "SCHROTT" and stBin = "DISPOSAL" then "SCRAP"
                    else if storageType = "SCHROTT" and stBin = "DAMAGED" then "DAMAGED"
                    else if storageType = "SCHROTT" and stBin = "CLOSEDOWN" then "INV RECON"
                    else if storageType = "SCHROTT" and stBin = "DISPLAY" then "DISPLAY STOCK"
                    else if storageType = "SCHROTT" and stBin = "GRIR" then "INV RECON"
                    else if storageType = "SCHROTT" and stBin = "INVEST" then "UNDER INVESTIGATION"
                    else if storageType = "SCHROTT" and stBin = "MOOG" then "FAILED PUMPS"
                    else if storageType = "SCHROTT" and stBin = "PGI" then "CANCELLED PICK"
                    else if storageType = "SCHROTT" and stBin = "QAHOLD" then "QCHOLD"
                    else if storageType = "SCHROTT" and stBin = "QUERY" then "INV RECON"
                    else if storageType = "SCHROTT" and stBin = "RETURNS" then "MANUAL RETURN ERROR"
                    else if storageType = "SCHROTT" and stBin = "SCHROTT" then "SHORTDATE"
                    else if storageType = "SCHROTT" and stBin = "TROLLEY" then "RETURN BLOCKED"
                    else if storageType = "SCHROTT" and stBin = "APPROVED" then "DESTRUCTION"
                    else if storageType = "SCHROTT" and Text.StartsWith(stBin, "NVP") then "INV RECON"
                    else if storageType = "SCHROTT" and stType = "904" then "RETURN BLOCKED"
                    else "NEW STORAGE BIN TO BE DECIDED"
            in
                [
                    #"Product Code" = row[Material],
                    Batch = row[Batch],
                    Expiry = row[#"SLED/BBD"],
                    Warehouse = "075-UK",
                    #"Combined Storage Type" = storageType,
                    #"Combined Storage Bin" = storageBin,
                    #"NET INVENTORY" = avail + pick
                ]
        )
    ),

    FinalSelection = Table.SelectColumns(Enriched, {"Product Code", "Batch", "Expiry", "Warehouse", "Combined Storage Type", "Combined Storage Bin", "NET INVENTORY"})
in
    FinalSelection

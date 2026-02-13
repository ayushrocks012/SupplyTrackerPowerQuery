let
    Source = fct_Inventory_Batch,
    
    // Logic 1: OOP Adult
    // Filter: ([#"ADULT/PAED"] = "ADULT") and ([#"REIMBURSED/OOP"] = "OOP")
    OOP_Adult = Table.SelectRows(Source, each ([#"ADULT/PAED"] = "ADULT") and ([#"REIMBURSED/OOP"] = "OOP")),
    WithLabel1 = Table.AddColumn(OOP_Adult, "QC Category", each "OOP - Adult"),
    
    // Logic 2: OOP Paed
    // Filter: ([#"REIMBURSED/OOP"] = "OOP") and ([#"ADULT/PAED"] = "PEDIATRIC")
    OOP_Paed = Table.SelectRows(Source, each ([#"REIMBURSED/OOP"] = "OOP") and ([#"ADULT/PAED"] = "PEDIATRIC")),
    WithLabel2 = Table.AddColumn(OOP_Paed, "QC Category", each "OOP - Paed"),
    
    // Logic 3: Reimbursed
    // Filter: ([#"REIMBURSED/OOP"] = "REIMBURSED") and ([#"ADULT/PAED"] = "ADULT") and ([GROWTH DRIVER] <> "OTHER MISC")
    Reimbursed = Table.SelectRows(Source, each ([#"REIMBURSED/OOP"] = "REIMBURSED") and ([#"ADULT/PAED"] = "ADULT") and ([GROWTH DRIVER] <> "OTHER MISC")),
    WithLabel3 = Table.AddColumn(Reimbursed, "QC Category", each "Reimbursed"),
    
    // Combine
    Combined = Table.Combine({WithLabel1, WithLabel2, WithLabel3})
in
    Combined

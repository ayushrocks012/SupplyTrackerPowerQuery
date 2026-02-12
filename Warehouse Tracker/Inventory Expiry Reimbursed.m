let
    Source = Total_Inv_Batch,
    #"Filtered Rows" = Table.SelectRows(Source, each ([#"REIMBURSED/OOP"] = "REIMBURSED") and ([#"ADULT/PAED"] = "ADULT") and ([GROWTH DRIVER] <> "OTHER MISC"))
in
    #"Filtered Rows"

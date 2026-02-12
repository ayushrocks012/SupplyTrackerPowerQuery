let
    Source = Total_Inv_Batch,
    #"Filtered Rows" = Table.SelectRows(Source, each ([#"ADULT/PAED"] = "ADULT") and ([#"REIMBURSED/OOP"] = "OOP"))
in
    #"Filtered Rows"

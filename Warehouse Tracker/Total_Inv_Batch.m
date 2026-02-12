let
    Source = Table.Combine({AUK_Inv_Batch, AUL_Inv_Batch}),
    #"Changed Type" = Table.TransformColumnTypes(Source,{{"Expiry", type date}}),
    #"Merged Queries" = Table.NestedJoin(#"Changed Type", {"Product Code", "Warehouse"}, #"SKUBIBLE V3", {"ECC CODE", "PLANT CODE"}, "SKUBIBLE V3", JoinKind.LeftOuter),
    #"Expanded SKUBIBLE V3" = Table.ExpandTableColumn(#"Merged Queries", "SKUBIBLE V3", {"DESC", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "FORM DESCRIPTION", "PACK TYPE REPORTING", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST SUB-TIER", "GROWTH DRIVER"}, {"DESC", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "FORM DESCRIPTION", "PACK TYPE REPORTING", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST SUB-TIER", "GROWTH DRIVER"}),
    #"Filtered Rows" = Table.SelectRows(#"Expanded SKUBIBLE V3", each ([Combined Storage Type] = "AVAILABLE")),
    #"Sorted Rows1" = Table.Sort(#"Filtered Rows",{{"Expiry", Order.Ascending}, {"FORECAST SUB-TIER", Order.Ascending}}),
    #"Added Index1" = Table.AddIndexColumn(#"Sorted Rows1", "Index.1", 1, 1, Int64.Type),
    #"Renamed Columns" = Table.RenameColumns(#"Added Index1",{{"Index.1", "Index"}}),
    #"Changed Type1" = Table.TransformColumnTypes(#"Renamed Columns",{{"SHIP SHELF LIFE", Int64.Type}}),

    #"Added Days to Expiry" = Table.AddColumn(#"Changed Type1", "Days to Expiry", each Duration.Days([Expiry] - DateTime.Date(DateTime.LocalNow())), type number),
    
    #"Added Custom" = Table.AddColumn(#"Added Days to Expiry", "Months to Sell", each ([Days to Expiry]-[SHIP SHELF LIFE])/30),
    #"Changed Type2" = Table.TransformColumnTypes(#"Added Custom",{{"Months to Sell", type number}}),
    #"Added Last Ship Date" = Table.AddColumn(#"Changed Type2", "Last Ship Date", each Date.AddDays([Expiry], -[SHIP SHELF LIFE]), type date),
    #"Merged Queries1" = Table.NestedJoin(#"Added Last Ship Date", {"Product Code", "Warehouse"}, CurrMonthADS, {"ECC CODE", "Location/Plant/Site"}, "CurrMonthADS", JoinKind.LeftOuter),
    #"Expanded CurrMonthADS" = Table.ExpandTableColumn(#"Merged Queries1", "CurrMonthADS", {"CurrMonthADS"}, {"CurrMonthADS.1"}),
    #"Renamed Columns1" = Table.RenameColumns(#"Expanded CurrMonthADS",{{"CurrMonthADS.1", "CurrMonthADS"}}),
    #"Merged Queries2" = Table.NestedJoin(#"Renamed Columns1", {"Warehouse", "Product Code"}, OnOrderQty, {"Inbound Warehouse", "ECC CODE"}, "OnOrderQty", JoinKind.LeftOuter),
    #"Expanded OnOrderQty" = Table.ExpandTableColumn(#"Merged Queries2", "OnOrderQty", {"OnOrderQty"}, {"OnOrderQty.1"}),
    #"Reordered Columns" = Table.ReorderColumns(#"Expanded OnOrderQty",{"Warehouse", "REIMBURSED/OOP", "ADULT/PAED", "GROWTH DRIVER", "Product Code", "FORECAST SUB-TIER", "Batch", "Expiry", "Months to Sell", "Last Ship Date", "CurrMonthADS", "OnOrderQty.1", "Combined Storage Type", "Combined Storage Bin", "NET INVENTORY", "DESC", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "Index", "Days to Expiry"}),
    #"Renamed Columns2" = Table.RenameColumns(#"Reordered Columns",{{"OnOrderQty.1", "OnOrderQty"}}),
    #"Reordered Columns1" = Table.ReorderColumns(#"Renamed Columns2",{"Warehouse", "REIMBURSED/OOP", "ADULT/PAED", "GROWTH DRIVER", "FORECAST SUB-TIER", "Product Code", "DESC", "Batch", "Expiry", "Months to Sell", "Last Ship Date", "CurrMonthADS", "OnOrderQty", "NET INVENTORY", "Combined Storage Type", "Combined Storage Bin", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "Index", "Days to Expiry"}),
    #"Removed Columns" = Table.RemoveColumns(#"Reordered Columns1",{"Combined Storage Type", "Combined Storage Bin", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "Days to Expiry"}),
    #"Reordered Columns2" = Table.ReorderColumns(#"Removed Columns",{"Warehouse", "REIMBURSED/OOP", "ADULT/PAED", "GROWTH DRIVER", "FORM DESCRIPTION", "PACK TYPE REPORTING", "FORECAST SUB-TIER", "Product Code", "DESC", "Batch", "Expiry", "Months to Sell", "Last Ship Date", "CurrMonthADS", "OnOrderQty", "NET INVENTORY", "Index"})
in
    #"Reordered Columns2"

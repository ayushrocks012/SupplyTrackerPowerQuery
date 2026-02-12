let
    Source = SharePoint.Files("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),

    // Filter only Excel files starting with "Completed Bookings"
    FilteredRows = Table.SelectRows(Source, each 
        Text.StartsWith([Name], "Inventory by SKU") and 
        Text.EndsWith([Name], ".xls") and
        [Folder Path] = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice/Shared Documents/General/Demand/Master Data Files/Daily Tracker Files/"),
    // Sort by Date modified descending
    SortedRows = Table.Sort(FilteredRows, {"Date modified", Order.Descending}),

    // Get the first (latest) file
    LatestFile = Table.FirstN(SortedRows, 1),

    // Dynamically access the binary content
    ExcelBinary = LatestFile{0}[Content],

    // Load the Excel workbook
    ExcelData = Excel.Workbook(ExcelBinary, null, true),

        // Try both addressing styles so it works for .xlsx and .xls
    Data_Record = 
        try ExcelData{[Item = "Data", Kind = "Sheet"]} 
        otherwise try ExcelData{[Name = "Data"]} 
        otherwise error "Couldn't find a sheet named 'Data'. Please check the sheet name.",

    Data_Sheet = Data_Record[Data],

    #"Promoted Headers" = Table.PromoteHeaders(Data_Sheet, [PromoteAllScalars=true]),
    #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"Client ID", type text}, {"Vendor", type any}, {"SKU ID", type text}, {"Description", type text}, {"Product Group", type text}, {"QC Status", type text}, {"Shelf Life", type any}, {"ship_shelf_life", Int64.Type}, {"client_prod_code", type any}, {"x_qty_on_hand", Int64.Type}, {"x_qty_qchold", Int64.Type}, {"x_qty_unrestricted", Int64.Type}, {"x_qty_allocated", Int64.Type}, {"x_qty_notallocated", Int64.Type}, {"x_qty_available", Int64.Type}, {"x_qty_onorders", Int64.Type}, {"pack_size", Int64.Type}, {"x_stock_monitor_low", type any}, {"x_stock_monitor_high", type any}, {"x_exp_monitor_low", type any}, {"x_exp_monitor_high", type any}, {"x_email_address", type any}, {"x_stock_monitor", Int64.Type}, {"x_exp_monitor", Int64.Type}, {"x_stock_monitor_last", type any}, {"x_qty_rationed", Int64.Type}, {"x_qty_returnblkd", Int64.Type}, {"x_qty_blocked", Int64.Type}, {"x_qty_smpl", Int64.Type}, {"x_qty_dmgd", Int64.Type}, {"x_qty_expd", Int64.Type}, {"x_qty_shortdate", Int64.Type}, {"px_attrib_16", type any}, {"px_attrib_17", type any}, {"p_incl_crse_num", type any}, {"p_active_flg", type any}, {"p_subscn_dur_day_num", type any}, {"p_max_order_units", type any}, {"p_min_order_units", type any}, {"p_uom_cd", type any}, {"p_vendr_part_num", type any}, {"p_x_safety_stock", type any}, {"p_row_id", type any}, {"x_use_stock_res", Int64.Type}}),
    #"Removed Columns" = Table.RemoveColumns(#"Changed Type",{"Vendor", "Product Group", "Shelf Life", "QC Status", "x_stock_monitor_low", "x_stock_monitor_high", "x_exp_monitor_low", "x_exp_monitor_high", "x_email_address", "x_stock_monitor", "x_exp_monitor", "x_stock_monitor_last", "x_qty_rationed", "x_qty_returnblkd", "x_qty_blocked", "x_qty_smpl", "x_qty_dmgd", "x_qty_expd", "x_qty_shortdate", "px_attrib_16", "px_attrib_17", "p_incl_crse_num", "p_active_flg", "p_subscn_dur_day_num", "p_max_order_units", "p_min_order_units", "p_uom_cd", "p_vendr_part_num", "p_x_safety_stock", "p_row_id", "x_use_stock_res"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"SKU ID", "Product Code"}}),
    #"Removed Columns1" = Table.RemoveColumns(#"Renamed Columns",{"Client ID", "Description", "client_prod_code", "x_qty_on_hand", "x_qty_qchold", "x_qty_unrestricted", "x_qty_allocated", "x_qty_notallocated", "x_qty_onorders", "pack_size"}),
    #"Added Custom" = Table.AddColumn(#"Removed Columns1", "Warehouse", each "075-UL"),
    #"Renamed Columns1" = Table.RenameColumns(#"Added Custom",{{"x_qty_available", "New Inventory"}}),
    #"Reordered Columns" = Table.ReorderColumns(#"Renamed Columns1",{"Product Code", "Warehouse", "New Inventory"}),
    #"Grouped Rows" = Table.Group(#"Reordered Columns", {"Product Code", "Warehouse", "ship_shelf_life"}, {{"Total Net Inventory", each List.Sum([New Inventory]), type nullable number}})
in
    #"Grouped Rows"

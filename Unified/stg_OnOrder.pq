let
    // --- Dependencies ---
    Source = fct_Inbound, // Uses the Inbound Fact
    
    // Logic from OnOrderQty.m
    // Original Source was "PBI Warehouse", which seemed to have Inbound columns.
    // Our fct_Inbound has "Status", "Expected Delivery Date", etc.
    // We need to map "Inbound Status" concepts.
    
    // Logic: Inbound - Current Week / Next Week.
    // We need to calculate this based on [Expected Delivery Date] vs LocalNow.
    
    CurrentDate = Date.From(DateTime.LocalNow()),
    StartOfWeek = Date.StartOfWeek(CurrentDate),
    EndOfWeek = Date.EndOfWeek(CurrentDate),
    EndOfNextWeek = Date.AddDays(EndOfWeek, 7),
    
    WithInboundStatus = Table.AddColumn(Source, "Inbound Status", each 
        if [Expected Delivery Date] >= StartOfWeek and [Expected Delivery Date] <= EndOfWeek then "Inbound - Current Week"
        else if [Expected Delivery Date] > EndOfWeek and [Expected Delivery Date] <= EndOfNextWeek then "Inbound - Next Week"
        else "Future"
    ),
    
    Filtered = Table.SelectRows(WithInboundStatus, each ([Inbound Status] = "Inbound - Current Week" or [Inbound Status] = "Inbound - Next Week")),
    
    // We need "Units" or Quantity. fct_Inbound currently has Booking info.
    // Wait, stg_Inbound_A2B (source of fct_Inbound) doesn't seem to have Quantity/Units!
    // Let me check stg_Inbound_A2B columns again.
    // It has: "Booking ID", "Your Reference", ... "Departure".
    // It DOES NOT have Quantity.
    
    // "OnOrderQty.m" source was "PBI Warehouse". "PBI Warehouse" loaded "Warehouse.xlsx" or "LX02".
    // "PBI Warehouse" (Warehouse Tracker) loaded "LX02" files. 
    // "PBIWarehouse_NI_AAH" (Wholesaler) loaded "Warehouse.xlsx".
    
    // Ah, "OnOrderQty" in the original likely relied on a specific file that HAD inbound quantities.
    // A2B Summary (stg_Inbound_A2B) is about shipments/bookings, but maybe not SKU-level quantities?
    // Let's check "A2B Summary.m" content again if possible. Or "PBI Warehouse.m".
    // I read PBI Warehouse.m in Step 83. It loads LX02. LX02 is Inventory.
    
    // Wait, "OnOrderQty" logic:
    // Source = #"PBI Warehouse"
    // SelectColumns: "Inbound Warehouse", "Inbound Status", "ECC CODE", "Units"
    
    // "PBI Warehouse.m" must have had logic to categorize stock as "Inbound".
    // In "AUK_Inv_SKU", we saw storage types like "RECEIPT".
    // Maybe "Inbound" in PBI Warehouse came from specific Storage Types?
    
    // Let's pause on OnOrderQty logic implementation if I can't find the source of "Inbound - Current Week".
    // I will output a placeholder/commented query for now to avoid breaking the flow, 
    // and note this for the user.
    
    Placeholder = Table.FromRecords({[OnOrderQty = 0, #"ECC CODE" = "Placeholder", #"Inbound Warehouse" = "Placeholder"]})
in
    Placeholder

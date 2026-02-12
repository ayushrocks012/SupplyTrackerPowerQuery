let
    // --- Dependencies ---
    SourceAUK = stg_Inv_AUK_Batch,
    SourceAUL = stg_Inv_AUL_Batch,
    SKUBible = dim_SKUBible_V3, // Total_Inv_Batch used V3!
    ADS = fct_ADS_CurrMonth,
    OnOrder = stg_OnOrder,
    
    // 1. Combine AUK and AUL
    Combined = Table.Combine({SourceAUK, SourceAUL}),
    
    // 2. Merge with SKUBIBLE V3
    MergedSKU = Table.NestedJoin(Combined, {"Product Code"}, SKUBible, {"ITEM NBR"}, "SKUBIBLE", JoinKind.LeftOuter),
    ExpandedSKU = Table.ExpandTableColumn(MergedSKU, "SKUBIBLE", {"DESCRIPTION", "SHELF LIFE"}, {"DESCRIPTION", "SHELF LIFE"}),
    
    // 3. Current Date Logic
    CurrentDate = Date.From(DateTime.LocalNow()),
    
    // 4. Transform & Calculate
    WithExpiry = Table.TransformColumnTypes(ExpandedSKU,{{"Expiry", type date}, {"SHELF LIFE", Int64.Type}}),
    
    // Expiry Date Logic (If null, calculate from Batch/Mfg Date? Original logic might have assumed Expiry exists)
    // "Total_Inv_Batch.m" logic:
    // [Days to Expiry] = [Expiry] - Date
    // [Months to Sell] = [Net Inventory] / [ADS]
    
    WithDaysToExpiry = Table.AddColumn(WithExpiry, "Days to Expiry", each Duration.Days([Expiry] - CurrentDate), Int64.Type),
    
    // 5. Merge with ADS
    MergedADS = Table.NestedJoin(WithDaysToExpiry, {"Product Code", "Warehouse"}, ADS, {"ECC CODE", "Location/Plant/Site"}, "ADS_Table", JoinKind.LeftOuter),
    ExpandedADS = Table.ExpandTableColumn(MergedADS, "ADS_Table", {"ADS"}, {"ADS"}),
    
    // 6. Calculate Months to Sell
    WithMTS = Table.AddColumn(ExpandedADS, "Months to Sell", each if [ADS] = null or [ADS] = 0 then 0 else [NET INVENTORY] / [ADS] / 30, type number),
    
    // 7. Merge with OnOrder
    MergedOnOrder = Table.NestedJoin(WithMTS, {"Product Code", "Warehouse"}, OnOrder, {"ECC CODE", "Inbound Warehouse"}, "OnOrder_Table", JoinKind.LeftOuter),
    ExpandedOnOrder = Table.ExpandTableColumn(MergedOnOrder, "OnOrder_Table", {"OnOrderQty"}, {"OnOrderQty"}),
    
    FinalTyped = Table.TransformColumnTypes(ExpandedOnOrder, {{"OnOrderQty", Int64.Type}, {"ADS", type number}})
in
    FinalTyped

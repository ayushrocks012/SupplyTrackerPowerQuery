let
    // --- Dependencies ---
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    DemandPath = Source{[Name="Shared Documents"]}[Content]{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files - Wholesaler"]}[Content],

    // --- Helper Logic (Inlined) ---
    GetLatestFile = (Folder as table, StartsWith as text, EndsWith as text) =>
        let
            Filtered = Table.SelectRows(Folder, each Text.StartsWith([Name], StartsWith) and Text.EndsWith([Name], EndsWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    // --- References to Unified Queries ---
    ValidationFactor = dim_ValidationFactor,
    SKUBIBLE = dim_SKUBible_V2,
    BPCS_Item_Master = dim_BPCS_Item,
    Prev_Day = stg_Shipped_PrevDay,
    InProgress = stg_InProgress,
    AUL_Inv_SKU = stg_Inv_AUL, 

    // --- Load Main File ---
    FileContent = GetLatestFile(DemandPath, "Abbott Stock File", ".xlsx"),
    Excel = Excel.Workbook(FileContent, null, true),
    Sheet0 = try Excel{[Item="Sheet0", Kind="Sheet"]}[Data] otherwise Excel{[Item="Sheet1", Kind="Sheet"]}[Data],
   
    // Shaping
    Skipped = Table.Skip(Sheet0, 3), 
    Promoted = Table.PromoteHeaders(Skipped, [PromoteAllScalars=true]),
    Data = Table.Skip(Promoted, 1),

    // 1. Keep Columns
    ColumnsToKeep = {
        "Location name", "Location code", "Product code", "Product name", "End balance", "Open purchase orders quantity",
        "Today's Order Proposal", "Next 7 days Order Proposals", "Forecasted supply (days)", "Forecasted supply (days) with open orders",
        "Forecasted supply (days) with open orders and proposals", "Next 14 Days Effective Forecast", "Product-location Block Start Date",
        "Product-location Block End Date", "Product-location comments", "PIP code", "Pack size", "Purchase price", "Sales quantity",
        "Sales quantity_2", "Sales quantity_3", 
        "[SL] Order (Mon)", "[SL] Order (Tue)", "[SL] Order (Wed)", "[SL] Order (Thu)", "[SL] Order (Fri)",
        "[SL] Lead time", "[SL] Order cycle"
    },
    Pruned = Table.SelectColumns(Data, ColumnsToKeep, MissingField.Ignore),

    // 2. Rename Columns
    Renamed = Table.RenameColumns(Pruned, {
        {"Location name", "AAH Warehouse Name"}, {"Location code", "AAH Warehouse Code"},
        {"Product code", "AAH Product Code"}, {"Product name", "AAH Product Name"},
        {"End balance", "AAH On Hand AAH"}, {"Open purchase orders quantity", "AAH Open Orders AAH"},
        {"Today's Order Proposal", "AAH SOQ Today AAH"}, {"Next 7 days Order Proposals", "AAH SOQ Next 7 Day AAH"},
        {"Forecasted supply (days)", "AAH On Hand DOH AAH"},
        {"Forecasted supply (days) with open orders", "AAH On Hand + Open Orders DOH AAH"},
        {"Forecasted supply (days) with open orders and proposals", "AAH On Hand + Open Orders + SOQ DOH AAH"},
        {"Next 14 Days Effective Forecast", "AAH Forecast 14 Days AAH"},
        {"Product-location Block Start Date", "Product-location Block Start Date"},
        {"Product-location Block End Date", "Product-location Block End Date"},
        {"Product-location comments", "Product-location comments"},
        {"PIP code", "PIP code"},
        {"Pack size", "AAH Pack Size AAH"},
        {"Purchase price", "AAH Purchase Price AAH"},
        {"Sales quantity", "AAH Sales Quantity Last 30 Days AAH"},
        {"Sales quantity_2", "AAH Sales Quantity Month -1 AAH"},
        {"Sales quantity_3", "AAH Sales Quantity Month -2 AAH"},
        {"[SL] Lead time", "AAH Lead Time AAH"},
        {"[SL] Order cycle", "AAH Order Cycle AAH"}
    }, MissingField.Ignore),

    // 3. Types
    Typed = Table.TransformColumnTypes(Renamed, {
        {"AAH Warehouse Name", type text}, {"AAH Warehouse Code", type text},
        {"AAH Product Code", type text}, {"AAH Product Name", type text},
        {"AAH On Hand AAH", Int64.Type}, {"AAH Open Orders AAH", Int64.Type},
        {"AAH SOQ Today AAH", Int64.Type}, {"AAH SOQ Next 7 Day AAH", Int64.Type},
        {"AAH On Hand DOH AAH", type number}, {"AAH On Hand + Open Orders DOH AAH", type number},
        {"AAH On Hand + Open Orders + SOQ DOH AAH", type number},
        {"AAH Forecast 14 Days AAH", type number},
        {"Product-location Block Start Date", type date}, {"Product-location Block End Date", type date},
        {"Product-location comments", type text},
        {"PIP code", Int64.Type}, {"AAH Pack Size AAH", type text},
        {"AAH Purchase Price AAH", Currency.Type},
        {"AAH Sales Quantity Last 30 Days AAH", Int64.Type},
        {"AAH Sales Quantity Month -1 AAH", Int64.Type},
        {"AAH Sales Quantity Month -2 AAH", Int64.Type},
        {"[SL] Order (Mon)", Int64.Type}, {"[SL] Order (Tue)", Int64.Type},
        {"[SL] Order (Wed)", Int64.Type}, {"[SL] Order (Thu)", Int64.Type},
        {"[SL] Order (Fri)", Int64.Type},
        {"AAH Lead Time AAH", Int64.Type}, {"AAH Order Cycle AAH", type any}
    }),

    // 4. Merge ValidationFactor
    Validation_slim = Table.SelectColumns(ValidationFactor, {"AAH Packsize","Abbott Factor"}, MissingField.Ignore),
    // Using Buffer if needed, but standard Table should suffice for now.
    JoinVal = Table.NestedJoin(Typed, {"AAH Pack Size AAH"}, Validation_slim, {"AAH Packsize"}, "Val", JoinKind.LeftOuter),
    ExpandVal = Table.ExpandTableColumn(JoinVal, "Val", {"Abbott Factor"}, {"Abbott Factor"}),
    AddAbbFactorN = Table.AddColumn(ExpandVal, "Abbott Factor N", each try Number.From([Abbott Factor]) otherwise null, type number),

    // 5. Apply Abbott Factor (Safe Helper Function)
    ApplyFactor = (table, sourceCol, destCol, resultType) => 
        Table.AddColumn(table, destCol, each 
            let 
                val = Record.Field(_, sourceCol),
                factor = [Abbott Factor N]
            in 
                if val = null or factor = null then null else val * factor,
            resultType
        ),

    WithABB  = ApplyFactor(AddAbbFactorN, "AAH On Hand AAH",                     "AAH On Hand ABB",                     Int64.Type),
    WithABB2 = ApplyFactor(WithABB,       "AAH Open Orders AAH",                 "AAH Open Orders ABB",                 Int64.Type),
    WithABB3 = ApplyFactor(WithABB2,      "AAH SOQ Today AAH",                   "AAH SOQ Today ABB",                   Int64.Type),
    WithABB4 = ApplyFactor(WithABB3,      "AAH SOQ Next 7 Day AAH",              "AAH SOQ Next 7 Day ABB",              Int64.Type),
    WithABB5 = ApplyFactor(WithABB4,      "AAH Forecast 14 Days AAH",            "AAH Forecast 14 Days ABB",            type number),
    WithABB6 = ApplyFactor(WithABB5,      "AAH Sales Quantity Last 30 Days AAH", "AAH Sales Quantity Last 30 Days ABB", Int64.Type),
    WithABB7 = ApplyFactor(WithABB6,      "AAH Sales Quantity Month -1 AAH",     "AAH Sales Quantity Month -1 ABB",     Int64.Type),
    WithABB8 = ApplyFactor(WithABB7,      "AAH Sales Quantity Month -2 AAH",     "AAH Sales Quantity Month -2 ABB",     Int64.Type),

    // 6. Weekday Plan Calculation
    OrderFieldNames = {"[SL] Order (Mon)","[SL] Order (Tue)","[SL] Order (Wed)","[SL] Order (Thu)","[SL] Order (Fri)"},
    WeekHeaders = {"Monday","Tuesday","Wednesday","Thursday","Friday"},
    ShiftWeekendToMonday = true,

    // Define Helper Function (Robust field access)
    WeekPlanFromRow = (row as record) as record =>
        let
            LT_raw = Record.FieldOrDefault(row, "AAH Lead Time AAH", null),
            LT = try Number.From(LT_raw) otherwise null,
            
            // Loop over field names safely
            Orders = List.Transform(
                OrderFieldNames, 
                (f) => 
                    let x = Record.FieldOrDefault(row, f, 0)
                    in if x = null then 0 else Number.From(x)
            ),
            
            OrderIdx = List.PositionOf(Orders, 1, Occurrence.All),
            DeliverIdx7 = if LT = null then {} else List.Transform(OrderIdx, each Number.Mod(_ + LT, 7)),
            DeliverIdx = if ShiftWeekendToMonday 
                         then List.Transform(DeliverIdx7, each if _ = 5 or _ = 6 then 0 else _) 
                         else DeliverIdx7,
            
            DayValues = List.Transform({0..4}, (d) => 
                let 
                    isOrder = List.Contains(OrderIdx, d),
                    isDeliver = List.Contains(DeliverIdx, d)
                in
                    if isOrder and isDeliver then "Order & Deliver"
                    else if isOrder then "Order"
                    else if isDeliver then "Deliver"
                    else null
            ),
            Rec = Record.FromList(DayValues, WeekHeaders)
        in
            Rec,

    // Apply Function
    AddWeekPlan = Table.AddColumn(WithABB8, "WeekPlan", each WeekPlanFromRow(_), type record),
    WithWeekdays = Table.ExpandRecordColumn(AddWeekPlan, "WeekPlan", WeekHeaders, WeekHeaders),

    // 7. Joins
    // SKUBIBLE
    JoinSku = Table.NestedJoin(WithWeekdays, {"AAH Product Code"}, SKUBIBLE, {"AAH CODE"}, "SKUBIBLE", JoinKind.LeftOuter),
    ExpandSku = Table.ExpandTableColumn(JoinSku, "SKUBIBLE", 
        {"LOCAL ITEM NBR","1-6-3-3","SHORT 1633","ECC CODE","GROWTH DRIVER","GROWTH SUB-DRIVER","SUB-BRAND","FAMILY","SUB-FAMILY","PRODUCT STATUS"},
        {"LOCAL ITEM NBR","1-6-3-3","SHORT 1633","ECC CODE","GROWTH DRIVER","GROWTH SUB-DRIVER","SUB-BAND","FAMILY","SUB-FAMILY","PRODUCT STATUS"}),

    // BPCS
    JoinBpcs = Table.NestedJoin(ExpandSku, {"SHORT 1633"}, BPCS_Item_Master, {"PROD CODE"}, "BPCS", JoinKind.LeftOuter),
    ExpandBpcs = Table.ExpandTableColumn(JoinBpcs, "BPCS", 
        {"BPCS Units per Case","BPCS Units per Pallet","Standard Plt Height","BPCS Units per Layer"},
        {"BPCS Units per Case","BPCS Units per Pallet","Standard Plt Height","BPCS Units per Layer"}),

    // Prev Day — pre-aggregate by {Sku ID, Town} before join (legacy Relex_UK.m pattern)
    PrevDayAgg = Table.Group(Prev_Day, {"Sku ID", "Town"}, {
        {"Ship By Date", each List.Max([Ship By Date]), type nullable date},
        {"Qty Shipped", each List.Sum([Qty Shipped]), type nullable number}
    }),
    JoinPrev = Table.NestedJoin(ExpandBpcs, {"ECC CODE","AAH Warehouse Name"}, PrevDayAgg, {"Sku ID","Town"}, "PrevDay", JoinKind.LeftOuter),
    ExpandPrev = Table.ExpandTableColumn(JoinPrev, "PrevDay", {"Ship By Date","Qty Shipped"}, {"On Order Shipped Prev Day Del Date ABB","On Order Shipped Prev Day ABB"}),

    // In Progress — pre-aggregate by {Sku ID, Town} before join (legacy Relex_UK.m pattern)
    InProgressAgg = Table.Group(InProgress, {"Sku ID", "Town"}, {
        {"Qty In Progress", each List.Sum([Qty In Progress]), type nullable number},
        {"Ship By Date", each List.Max([Ship By Date]), type nullable date}
    }),
    JoinInProg = Table.NestedJoin(ExpandPrev, {"ECC CODE","AAH Warehouse Name"}, InProgressAgg, {"Sku ID","Town"}, "InProg", JoinKind.LeftOuter),
    ExpandInProg = Table.ExpandTableColumn(JoinInProg, "InProg", {"Qty In Progress","Ship By Date"}, {"On Order In Progress Qty ABB","On Order In Progress Del Date"}),

    // AUL (using stg_Inv_AUK)
    JoinAUL = Table.NestedJoin(ExpandInProg, {"ECC CODE"}, AUL_Inv_SKU, {"Product Code"}, "AUL", JoinKind.LeftOuter),
    ExpandAUL = Table.ExpandTableColumn(JoinAUL, "AUL", {"Net Inventory"}, {"AUK Inv ABB"}),

    // 8. Cleanup and Final Columns
    ColsToRemove = List.Combine({OrderFieldNames, {"Abbott Factor N"}}),
    FinalClean = Table.RemoveColumns(ExpandAUL, List.Intersect({Table.ColumnNames(ExpandAUL), ColsToRemove})),

    // Forecast Daily
    WithForecastDailyAAH = Table.AddColumn(FinalClean, "AAH Forecast Daily AAH", each if [AAH Forecast 14 Days AAH] <> null then [AAH Forecast 14 Days AAH]/14 else null, type number),
    WithForecastDailyABB = Table.AddColumn(WithForecastDailyAAH, "AAH Forecast Daily ABB", each if [AAH Forecast 14 Days ABB] <> null then [AAH Forecast 14 Days ABB]/14 else null, type number),

in
    WithForecastDailyABB

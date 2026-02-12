let
    // -------- PARAMETERS --------
    SiteUrl = "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice",
    FilePrefix = "Abbott Stock File",
    TargetFolderPath = {
        "Shared Documents",
        "General",
        "Demand",
        "Master Data Files",
        "Daily Tracker Files - Wholesaler"
    },

    // Weekend handling for deliveries:
    // true  = shift Sat/Sun deliveries to Monday
    // false = keep actual weekend day names (Saturday/Sunday)
    ShiftWeekendToMonday = true,

    // -------- NAVIGATE VIA SharePoint.Contents --------
    Root        = SharePoint.Contents(SiteUrl, [ApiVersion = 15]),
    Shared      = Root{[Name = TargetFolderPath{0}]}[Content],
    L1          = Shared{[Name = TargetFolderPath{1}]}[Content],
    L2          = L1{[Name = TargetFolderPath{2}]}[Content],
    L3          = L2{[Name = TargetFolderPath{3}]}[Content],
    L4          = L3{[Name = TargetFolderPath{4}]}[Content],

    // -------- MINIMISE METADATA (speed) --------
    L4_Slim     = Table.SelectColumns(L4, {"Name","Content","Date modified"}, MissingField.Ignore),

    // -------- FILTER FILES --------
    Filtered    = Table.SelectRows(
                    L4_Slim,
                    each Value.Is([Content], type binary)
                      and Text.StartsWith([Name], FilePrefix)
                      and Text.EndsWith([Name], ".xlsx")
                  ),

    LatestRow   = if Table.IsEmpty(Filtered)
                  then error "No matching 'Abbott Stock File*.xlsx' found in the target folder."
                  else Table.Max(Filtered, "Date modified"),

    // -------- BUFFER BINARY (speed) --------
    ExcelBinary = Binary.Buffer(LatestRow[Content]),

    // -------- OPEN WORKBOOK / SHEET --------
    WB          = Excel.Workbook(ExcelBinary, null, true),
    Sheet0      = try WB{[Item = "Sheet0", Kind = "Sheet"]}[Data]
                  otherwise error "Sheet 'Sheet0' not found in the latest workbook.",

    // -------- INITIAL SHAPING --------
    Data0       = Table.Skip(Sheet0, 3),
    Data1       = Table.PromoteHeaders(Data0, [PromoteAllScalars = true]),
    Data        = Table.Skip(Data1, 1),

    // ============================================================
    // 1) KEEP ONLY REQUIRED COLUMNS (EARLY PRUNE)
    //    + IMPORTANT: keep [SL] Order (Mon..Fri) to compute weekdays
    // ============================================================
    ColumnsToKeep = {
        "Location name",
        "Location code",
        "Product code",
        "Product name",
        "End balance",
        "Open purchase orders quantity",
        "Today's Order Proposal",
        "Next 7 days Order Proposals",
        "Forecasted supply (days)",
        "Forecasted supply (days) with open orders",
        "Forecasted supply (days) with open orders and proposals",
        "Next 14 Days Effective Forecast",
        "Product-location Block Start Date",
        "Product-location Block End Date",
        "Product-location comments",
        "PIP code",
        "Pack size",
        "Purchase price",
        "Sales quantity",
        "Sales quantity_2",
        "Sales quantity_3",

        // ---- added back for weekday plan ----
        "[SL] Order (Mon)",
        "[SL] Order (Tue)",
        "[SL] Order (Wed)",
        "[SL] Order (Thu)",
        "[SL] Order (Fri)",

        "[SL] Lead time",
        "[SL] Order cycle"
    },
    Pruned = Table.SelectColumns(Data, ColumnsToKeep, MissingField.Ignore),

    // ============================================================
    // 2) RENAME TO "AAH Language" NAMES
    // ============================================================
    Renamed = Table.RenameColumns(Pruned, {
        {"Location name", "AAH Warehouse Name"},
        {"Location code", "AAH Warehouse Code"},
        {"Product code", "AAH Product Code"},
        {"Product name", "AAH Product Name"},
        {"End balance", "AAH On Hand AAH"},
        {"Open purchase orders quantity", "AAH Open Orders AAH"},
        {"Today's Order Proposal", "AAH SOQ Today AAH"},
        {"Next 7 days Order Proposals", "AAH SOQ Next 7 Day AAH"},
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

    // -------- TYPES (AAH columns) --------
    Typed = Table.TransformColumnTypes(Renamed, {
        {"AAH Warehouse Name", type text},
        {"AAH Warehouse Code", type text},
        {"AAH Product Code", type text},
        {"AAH Product Name", type text},

        {"AAH On Hand AAH", Int64.Type},
        {"AAH Open Orders AAH", Int64.Type},
        {"AAH SOQ Today AAH", Int64.Type},
        {"AAH SOQ Next 7 Day AAH", Int64.Type},

        {"AAH On Hand DOH AAH", type number},
        {"AAH On Hand + Open Orders DOH AAH", type number},
        {"AAH On Hand + Open Orders + SOQ DOH AAH", type number},

        {"AAH Forecast 14 Days AAH", type number},

        {"Product-location Block Start Date", type date},
        {"Product-location Block End Date", type date},
        {"Product-location comments", type text},

        {"PIP code", Int64.Type},
        {"AAH Pack Size AAH", type text},
        {"AAH Purchase Price AAH", Currency.Type},

        {"AAH Sales Quantity Last 30 Days AAH", Int64.Type},
        {"AAH Sales Quantity Month -1 AAH", Int64.Type},
        {"AAH Sales Quantity Month -2 AAH", Int64.Type},

        // SL weekday flags: keep numeric
        {"[SL] Order (Mon)", Int64.Type},
        {"[SL] Order (Tue)", Int64.Type},
        {"[SL] Order (Wed)", Int64.Type},
        {"[SL] Order (Thu)", Int64.Type},
        {"[SL] Order (Fri)", Int64.Type},

        // lead time (renamed) and cycle (renamed)
        {"AAH Lead Time AAH", Int64.Type},
        {"AAH Order Cycle AAH", type any}
    }),

    // ============================================================
    // 3) BRING IN MULTIPLICATION FACTOR FIRST (ValidationFactor)
    // ============================================================
    Validation_slim =
        Table.SelectColumns(ValidationFactor, {"AAH Packsize","Abbott Factor"}, MissingField.Ignore),
    Validation_buf =
        Table.Buffer(Table.TransformColumnTypes(Validation_slim, {{"AAH Packsize", type text}, {"Abbott Factor", type number}})),

    JoinVal   = Table.NestedJoin(Typed, {"AAH Pack Size AAH"}, Validation_buf, {"AAH Packsize"}, "Val", JoinKind.LeftOuter),
    ExpandVal = Table.ExpandTableColumn(JoinVal, "Val", {"Abbott Factor"}, {"Abbott Factor"}),

    // Numeric factor once
    AddAbbFactorN = Table.AddColumn(ExpandVal, "Abbott Factor N", each try Number.From([Abbott Factor]) otherwise null, type number),

    // ============================================================
    // 4) APPLY TRANSFORMATIONS TO ABB ONLY WHERE REQUIRED
    // ============================================================
    MultiplyMap = {
        {"AAH On Hand AAH",                    "AAH On Hand ABB"},
        {"AAH Open Orders AAH",                "AAH Open Orders ABB"},
        {"AAH SOQ Today AAH",                  "AAH SOQ Today ABB"},
        {"AAH SOQ Next 7 Day AAH",             "AAH SOQ Next 7 Day ABB"},
        {"AAH Forecast 14 Days AAH",           "AAH Forecast 14 Days ABB"},
        {"AAH Sales Quantity Last 30 Days AAH","AAH Sales Quantity Last 30 Days ABB"},
        {"AAH Sales Quantity Month -1 AAH",    "AAH Sales Quantity Month -1 ABB"},
        {"AAH Sales Quantity Month -2 AAH",    "AAH Sales Quantity Month -2 ABB"}
    },

    WithABB =
        List.Accumulate(
            MultiplyMap,
            AddAbbFactorN,
            (state as table, pair as list) =>
                let
                    src = pair{0},
                    dst = pair{1}
                in
                    if List.Contains(Table.ColumnNames(state), src) then
                        Table.AddColumn(
                            state,
                            dst,
                            each
                                let
                                    f = [Abbott Factor N],
                                    v = try Number.From(Record.Field(_, src)) otherwise null
                                in
                                    if f = null or v = null then null else v * f,
                            type number
                        )
                    else
                        state
        ),

    ABBTyped = Table.TransformColumnTypes(WithABB, {
        {"AAH On Hand ABB", Int64.Type},
        {"AAH Open Orders ABB", Int64.Type},
        {"AAH SOQ Today ABB", Int64.Type},
        {"AAH SOQ Next 7 Day ABB", Int64.Type},
        {"AAH Sales Quantity Last 30 Days ABB", Int64.Type},
        {"AAH Sales Quantity Month -1 ABB", Int64.Type},
        {"AAH Sales Quantity Month -2 ABB", Int64.Type},
        {"AAH Forecast 14 Days ABB", type number}
    }, "en-GB"),

    // ============================================================
    // 4B) ADD WEEKDAY PLAN COLUMNS (Monday..Friday)
    //     Uses [SL] Order (Mon..Fri) + lead time (Order Day)
    // ============================================================
    OrderFieldNames = {"[SL] Order (Mon)","[SL] Order (Tue)","[SL] Order (Wed)","[SL] Order (Thu)","[SL] Order (Fri)"},
    WeekHeaders     = {"Monday","Tuesday","Wednesday","Thursday","Friday"},

    WeekPlanFromRow = (row as record) as record =>
        let
            LT_raw      = Record.FieldOrDefault(row, "AAH Lead Time AAH", null), // lead time (days)
            LT          = try Number.From(LT_raw) otherwise null,

            Orders      = List.Transform(
                            OrderFieldNames,
                            (f) =>
                                let x = Record.FieldOrDefault(row, f, 0)
                                in if x = null then 0 else Number.From(x)
                          ),
            OrderIdx     = List.PositionOf(Orders, 1, Occurrence.All),

            DeliverIdx7  = if LT = null then {} else List.Transform(OrderIdx, each Number.Mod(_ + LT, 7)),
            DeliverIdx   = if ShiftWeekendToMonday
                           then List.Transform(DeliverIdx7, each if _ = 5 or _ = 6 then 0 else _)
                           else DeliverIdx7,

            DayValues    = List.Transform(
                               {0..4},
                               (d) =>
                                   let
                                       isOrder   = List.Contains(OrderIdx, d),
                                       isDeliver = List.Contains(DeliverIdx, d)
                                   in
                                       if isOrder and isDeliver then "Order & Deliver"
                                       else if isOrder then "Order"
                                       else if isDeliver then "Deliver"
                                       else null
                           ),

            Rec          = Record.FromList(DayValues, WeekHeaders)
        in
            Rec,

    WithWeekPlan = Table.AddColumn(ABBTyped, "WeekPlan", each WeekPlanFromRow(_), type record),
    WithWeekdays = Table.ExpandRecordColumn(WithWeekPlan, "WeekPlan", WeekHeaders, WeekHeaders),

    // ============================================================
    // 5) REMAINING LOOKUPS / JOINS (unchanged)
    // ============================================================
    SKUBIBLE_slim =
        Table.SelectColumns(
            SKUBIBLE,
            {"AAH CODE","LOCAL ITEM NBR","1-6-3-3","SHORT 1633","ECC CODE","GROWTH DRIVER","GROWTH SUB-DRIVER","SUB-BRAND","FAMILY","SUB-FAMILY","PRODUCT STATUS"},
            MissingField.Ignore
        ),
    SKUBIBLE_buf =
        Table.Buffer(Table.TransformColumnTypes(SKUBIBLE_slim, {{"AAH CODE", type text}, {"SHORT 1633", type text}})),

    BPCS_slim =
        Table.SelectColumns(
            BPCS_Item_Master,
            {"PROD CODE","BPCS Units per Case","BPCS Units per Pallet","Standard Plt Height","BPCS Units per Layer"},
            MissingField.Ignore
        ),
    BPCS_buf =
        Table.Buffer(Table.TransformColumnTypes(BPCS_slim, {{"PROD CODE", type text}})),

    PrevDay_typed =
        Table.TransformColumnTypes(
            Table.SelectColumns(Prev_Day, {"Sku ID","Town","Ship By Date","Qty Shipped"}, MissingField.Ignore),
            {{"Sku ID", type text}, {"Town", type text}, {"Ship By Date", type date}, {"Qty Shipped", Int64.Type}}
        ),
    PrevDay_agg =
        Table.Group(
            PrevDay_typed,
            {"Sku ID","Town"},
            {
                {"Ship By Date", each List.Max([Ship By Date]), type date},
                {"Qty Shipped", each List.Sum([Qty Shipped]), Int64.Type}
            }
        ),
    PrevDay_buf = Table.Buffer(PrevDay_agg),

    InProg_typed =
        Table.TransformColumnTypes(
            Table.SelectColumns(InProgress, {"Sku ID","Town","Ship By Date","Qty In Progress"}, MissingField.Ignore),
            {{"Sku ID", type text}, {"Town", type text}, {"Ship By Date", type date}, {"Qty In Progress", Int64.Type}}
        ),
    InProg_agg =
        Table.Group(
            InProg_typed,
            {"Sku ID","Town"},
            {
                {"Ship By Date", each List.Max([Ship By Date]), type date},
                {"Qty In Progress", each List.Sum([Qty In Progress]), Int64.Type}
            }
        ),
    InProgress_buf = Table.Buffer(InProg_agg),

    AUL_slim =
        Table.SelectColumns(AUL_Inv_SKU, {"Product Code","Total Net Inventory"}, MissingField.Ignore),
    AUL_buf =
        Table.Buffer(Table.TransformColumnTypes(AUL_slim, {{"Product Code", type text}, {"Total Net Inventory", Int64.Type}})),

    JoinSku  = Table.NestedJoin(WithWeekdays, {"AAH Product Code"}, SKUBIBLE_buf, {"AAH CODE"}, "SKUBIBLE", JoinKind.LeftOuter),
    ExpandSku = Table.ExpandTableColumn(JoinSku, "SKUBIBLE",
        {"LOCAL ITEM NBR","1-6-3-3","SHORT 1633","ECC CODE","GROWTH DRIVER","GROWTH SUB-DRIVER","SUB-BRAND","FAMILY","SUB-FAMILY","PRODUCT STATUS"},
        {"LOCAL ITEM NBR","1-6-3-3","SHORT 1633","ECC CODE","GROWTH DRIVER","GROWTH SUB-DRIVER","SUB-BAND","FAMILY","SUB-FAMILY","PRODUCT STATUS"}),

    JoinBpcs   = Table.NestedJoin(ExpandSku, {"SHORT 1633"}, BPCS_buf, {"PROD CODE"}, "BPCS", JoinKind.LeftOuter),
    ExpandBpcs = Table.ExpandTableColumn(JoinBpcs, "BPCS",
        {"BPCS Units per Case","BPCS Units per Pallet","Standard Plt Height","BPCS Units per Layer"},
        {"BPCS Units per Case","BPCS Units per Pallet","Standard Plt Height","BPCS Units per Layer"}),

    JoinPrev   = Table.NestedJoin(ExpandBpcs, {"ECC CODE","AAH Warehouse Name"}, PrevDay_buf, {"Sku ID","Town"}, "PrevDay", JoinKind.LeftOuter),
    ExpandPrev = Table.ExpandTableColumn(JoinPrev, "PrevDay", {"Ship By Date","Qty Shipped"},
        {"On Order Shipped Prev Day Del Date ABB","On Order Shipped Prev Day ABB"}),

    JoinInProg   = Table.NestedJoin(ExpandPrev, {"ECC CODE","AAH Warehouse Name"}, InProgress_buf, {"Sku ID","Town"}, "InProg", JoinKind.LeftOuter),
    ExpandInProg = Table.ExpandTableColumn(JoinInProg, "InProg", {"Qty In Progress","Ship By Date"},
        {"On Order In Progress Qty ABB","On Order In Progress Del Date"}),

    JoinAUL   = Table.NestedJoin(ExpandInProg, {"ECC CODE"}, AUL_buf, {"Product Code"}, "AUL", JoinKind.LeftOuter),
    ExpandAUL = Table.ExpandTableColumn(JoinAUL, "AUL", {"Total Net Inventory"}, {"AUK Inv ABB"}),

    // -------- CLEANUP (optional) --------
    // Remove working columns + helper factor (keep weekdays)
    DropThese = List.Combine({OrderFieldNames, {"Abbott Factor N"}}),
    Final = Table.RemoveColumns(ExpandAUL, List.Intersect({Table.ColumnNames(ExpandAUL), DropThese}), MissingField.Ignore),
    #"Added Custom" = Table.AddColumn(Final, "AAH Forecast Daily AAH", each [AAH Forecast 14 Days AAH]/14),
    #"Reordered Columns" = Table.ReorderColumns(#"Added Custom",{"AAH Warehouse Name", "AAH Warehouse Code", "AAH Product Code", "AAH Product Name", "AAH On Hand AAH", "AAH Open Orders AAH", "AAH SOQ Today AAH", "AAH SOQ Next 7 Day AAH", "AAH On Hand DOH AAH", "AAH On Hand + Open Orders DOH AAH", "AAH On Hand + Open Orders + SOQ DOH AAH", "AAH Forecast 14 Days AAH", "AAH Forecast Daily AAH", "Product-location Block Start Date", "Product-location Block End Date", "Product-location comments", "PIP code", "AAH Pack Size AAH", "AAH Purchase Price AAH", "AAH Sales Quantity Last 30 Days AAH", "AAH Sales Quantity Month -1 AAH", "AAH Sales Quantity Month -2 AAH", "AAH Lead Time AAH", "AAH Order Cycle AAH", "Abbott Factor", "AAH On Hand ABB", "AAH Open Orders ABB", "AAH SOQ Today ABB", "AAH SOQ Next 7 Day ABB", "AAH Forecast 14 Days ABB", "AAH Sales Quantity Last 30 Days ABB", "AAH Sales Quantity Month -1 ABB", "AAH Sales Quantity Month -2 ABB", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "LOCAL ITEM NBR", "1-6-3-3", "SHORT 1633", "ECC CODE", "GROWTH DRIVER", "GROWTH SUB-DRIVER", "SUB-BAND", "FAMILY", "SUB-FAMILY", "PRODUCT STATUS", "BPCS Units per Case", "BPCS Units per Pallet", "Standard Plt Height", "BPCS Units per Layer", "On Order Shipped Prev Day Del Date ABB", "On Order Shipped Prev Day ABB", "On Order In Progress Qty ABB", "On Order In Progress Del Date", "AUK Inv ABB"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Reordered Columns",{{"AAH Forecast Daily AAH", type number}}),
    #"Added Custom1" = Table.AddColumn(#"Changed Type", "AAH Forecast Daily ABB", each [AAH Forecast 14 Days ABB]/14),
    #"Reordered Columns1" = Table.ReorderColumns(#"Added Custom1",{"AAH Warehouse Name", "AAH Warehouse Code", "AAH Product Code", "AAH Product Name", "AAH On Hand AAH", "AAH Open Orders AAH", "AAH SOQ Today AAH", "AAH SOQ Next 7 Day AAH", "AAH On Hand DOH AAH", "AAH On Hand + Open Orders DOH AAH", "AAH On Hand + Open Orders + SOQ DOH AAH", "AAH Forecast 14 Days AAH", "AAH Forecast Daily AAH", "Product-location Block Start Date", "Product-location Block End Date", "Product-location comments", "PIP code", "AAH Pack Size AAH", "AAH Purchase Price AAH", "AAH Sales Quantity Last 30 Days AAH", "AAH Sales Quantity Month -1 AAH", "AAH Sales Quantity Month -2 AAH", "AAH Lead Time AAH", "AAH Order Cycle AAH", "Abbott Factor", "AAH On Hand ABB", "AAH Open Orders ABB", "AAH SOQ Today ABB", "AAH SOQ Next 7 Day ABB", "AAH Forecast Daily ABB", "AAH Forecast 14 Days ABB", "AAH Sales Quantity Last 30 Days ABB", "AAH Sales Quantity Month -1 ABB", "AAH Sales Quantity Month -2 ABB", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "LOCAL ITEM NBR", "1-6-3-3", "SHORT 1633", "ECC CODE", "GROWTH DRIVER", "GROWTH SUB-DRIVER", "SUB-BAND", "FAMILY", "SUB-FAMILY", "PRODUCT STATUS", "BPCS Units per Case", "BPCS Units per Pallet", "Standard Plt Height", "BPCS Units per Layer", "On Order Shipped Prev Day Del Date ABB", "On Order Shipped Prev Day ABB", "On Order In Progress Qty ABB", "On Order In Progress Del Date", "AUK Inv ABB"})
in
    #"Reordered Columns1"

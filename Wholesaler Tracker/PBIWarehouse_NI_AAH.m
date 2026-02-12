let
    // === Parameters ===
    MonthsBack = -2,
    MonthsForward = 6,
    CurrentDate = Date.From(DateTime.LocalNow()),
    StartDate = Date.AddMonths(CurrentDate, MonthsBack),
    EndDate = Date.AddMonths(CurrentDate, MonthsForward),

    // === Load SharePoint Files (Direct Folder Access) ===
    Source = SharePoint.Contents(
        "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice",
        [ApiVersion = 15]
    ),
    Folder = Source{[Name="Shared Documents"]}[Content],
    DemandFolder =
        Folder{[Name="General"]}[Content]
              {[Name="Demand"]}[Content]
              {[Name="Master Data Files"]}[Content]
              {[Name="Daily Tracker Files UK Departures PBI"]}[Content],

    FilteredFiles = Table.SelectRows(
        DemandFolder,
        each Text.StartsWith([Name], "UK Departures") and Text.EndsWith([Name], ".xlsx")
    ),
    LatestFile = Table.Sort(FilteredFiles, {{"Date modified", Order.Descending}}){0}[Content],

    // === Load Excel Sheet ===
    ExcelData = Excel.Workbook(LatestFile, null, true),
    WarehouseSheet = Table.PromoteHeaders(
        Table.Skip(ExcelData{[Item="Warehouse", Kind="Sheet"]}[Data], 1),
        [PromoteAllScalars=true]
    ),

    // === Clean & Transform ===
    CleanedData = Table.SelectRows(
        WarehouseSheet,
        each not List.IsEmpty(List.RemoveMatchingItems(Record.FieldValues(_), {"", null}))
    ),
    ChangedTypes = Table.TransformColumnTypes(
        CleanedData,
        {
            {"ETD", type date},
            {"DEPARTURE", Int64.Type},
            {"Price", type number},
            {"Units", type number},
            {"Breda Tour", type text},
            {"1633 Item Code", type text},
            {"Breda Status Date", type date},
            {"EXP_DATE", type date},
            {"MFG_DATE", type date},
            {"INVOICE", type text}
        }
    ),
    FilteredETD = Table.SelectRows(ChangedTypes, each [ETD] >= StartDate and [ETD] <= EndDate),

    MergedA2B = Table.NestedJoin(FilteredETD, {"Breda Tour", "DEPARTURE"}, #"A2B Summary", {"Breda Tour", "Departure"}, "A2B", JoinKind.LeftOuter),
    ExpandedA2B = Table.ExpandTableColumn(
        MergedA2B,
        "A2B",
        {"Collection Date", "Expected Delivery Date", "Breda Tour", "Departure", "Status", "Location", "Custom Cleared Status"},
        {"A2B.Collection Date", "A2B.Expected Delivery Date", "A2B.Breda Tour", "A2B.Departure", "A2B.Status", "A2B.Location", "A2B.Custom Cleared Status"}
    ),
    AddedInboundStatus = Table.AddColumn(
        ExpandedA2B,
        "Inbound Status",
        each
            let
                fwd = [FORWARDER],
                expectedDate =
                    if fwd = "ESSERS" then
                        if [ETD] = null then null else Date.AddDays([ETD], 5)
                    else if fwd = "A2B" then
                        [A2B.Expected Delivery Date]
                    else
                        null
            in
                if expectedDate = null then null else
                let
                    weekDiff =
                        (Date.Year(expectedDate) - Date.Year(CurrentDate)) * 52 +
                        (Date.WeekOfYear(expectedDate) - Date.WeekOfYear(CurrentDate))
                in
                    if weekDiff = -1 then "Inbound - Last Week"
                    else if weekDiff = 0 then "Inbound - Current Week"
                    else if weekDiff = 1 then "Inbound - Next Week"
                    else if weekDiff > 1 then "Inbound - Newer than 2 Weeks"
                    else "Inbound - Older than 2 Weeks"
    ),

    AddedGITValue = Table.AddColumn(AddedInboundStatus, "GIT Value (£)", each [Units] * [Price], type number),

    // === Add Year & Month ===
    AddedYearMonth = Table.AddColumn(AddedGITValue, "Year (Current)", each Date.Year([ETD])),
    AddedMonth = Table.AddColumn(
        AddedYearMonth,
        "Month (Current)",
        each Text.PadStart(Text.From(Date.Month([ETD])), 2, "0") & " - " & Text.Start(Date.MonthName([ETD]), 3)
    ),

    #"Merged Queries" = Table.NestedJoin(AddedMonth, {"INVOICE", "1633 Item Code"}, MasterArrivalSchedule, {"FACT_Shipment_Actuals[Invoice]", "DIM_ProductMaster[MK_PRODUCT]"}, "MasterArrivalSchedule", JoinKind.LeftOuter),
    #"Expanded MasterArrivalSchedule" = Table.ExpandTableColumn(
        #"Merged Queries",
        "MasterArrivalSchedule",
        {
            "FACT_Shipment_Actuals[Ship_To_Address1]",
            "FACT_Shipment_Actuals[Ship_To_Address2]",
            "FACT_Shipment_Actuals[Ship_To_Address3]"
        },
        {
            "FACT_Shipment_Actuals[Ship_To_Address1]",
            "FACT_Shipment_Actuals[Ship_To_Address2]",
            "FACT_Shipment_Actuals[Ship_To_Address3]"
        }
    ),
    // === Add Columns ===
    AddedInboundWarehouse = Table.AddColumn(
        #"Expanded MasterArrivalSchedule",
        "Inbound Warehouse",
        each
            let podRaw = [Port of Discharge],
                pod = if podRaw = null then null else Text.Trim(podRaw)
            in
                if pod = "Belfast, Northern Ireland" then "075-XI" else
                if pod = "United Kingdom, Derby" then "075-UL" else
                if pod = "United Kingdom, Queenborough" then "075-UK" else
                "Check Port of Discharge"
    ),
    #"Added Custom" = Table.AddColumn(AddedInboundWarehouse, "Warehouse Name", each if [#"FACT_Shipment_Actuals[Ship_To_Address1]"] = "2 MARSHALLS ROAD" then "BELFAST" else null)
in
    #"Added Custom"

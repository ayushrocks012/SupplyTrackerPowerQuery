let
    Demand = fn_SharePointBase[Demand],
    SourceFile = Demand{[Name="AAH Bible.xlsx"]}[Content],
    Workbook = Excel.Workbook(SourceFile, null, true),
    Sheet = Workbook{[Item="Validations Conversion Factor", Kind="Sheet"]}[Data],
    Promoted = Table.PromoteHeaders(Sheet, [PromoteAllScalars=true]),
    Renamed = Table.RenameColumns(Promoted, {{"Factor", "Abbott Factor"}, {"Row Labels", "AAH Packsize"}})
in
    Renamed

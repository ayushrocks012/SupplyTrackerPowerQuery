// fn_GetLatestFile — Shared helper to find the most recently modified file
// in a SharePoint folder matching a prefix and suffix pattern.
// Replaces the identical GetLatestFile helper previously inlined in 12 queries.
(Folder as table, StartsWith as text, EndsWith as text) =>
    let
        Filtered = Table.SelectRows(Folder, each 
            Text.StartsWith([Name], StartsWith) and Text.EndsWith(Text.Lower([Name]), EndsWith)),
        Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
        Latest = Table.First(Sorted)[Content]
    in
        Latest

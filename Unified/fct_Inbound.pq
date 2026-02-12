let
    Source = stg_Inbound_A2B,
    Selected = Table.SelectColumns(Source, {"Booking ID", "Expected Delivery Date", "Status", "Location", "Custom Cleared Status"})
in
    Selected

-record(tunnel, {
  name :: binary(),
  secret :: binary(),
  host :: binary(),
  port :: pos_integer(),
  traffic_in_bytes = 0 :: non_neg_integer(),
  traffic_out_bytes = 0 :: non_neg_integer()
}).

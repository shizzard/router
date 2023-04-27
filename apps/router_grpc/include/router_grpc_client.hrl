%% gRPC events messages

-define(grpc_event_stream_killed(StreamRef), {router_grpc_client, stream_killed, StreamRef}).
-define(grpc_event_stream_unprocessed(StreamRef), {router_grpc_client, stream_unprocessed, StreamRef}).
-define(grpc_event_connection_down(StreamRef), {router_grpc_client, connection_down, StreamRef}).
-define(grpc_event_response(StreamRef, IsFin, Status, Headers), {router_grpc_client, response, StreamRef, IsFin, Status, Headers}).
-define(grpc_event_data(StreamRef, IsFin, Data), {router_grpc_client, data, StreamRef, IsFin, Data}).
-define(grpc_event_trailers(StreamRef, Trailers), {router_grpc_client, trailers, StreamRef, Trailers}).

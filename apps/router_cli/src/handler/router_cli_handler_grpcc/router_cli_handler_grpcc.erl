-module(router_cli_handler_grpcc).
-behavior(router_cli_handler).
-dialyzer({nowarn_function, [config/0, dispatch/2]}).

-include_lib("router_cli/include/router_cli.hrl").
-include_lib("router_cli/include/router_cli_getopt.hrl").
-include_lib("router_cli/include/router_cli_handler.hrl").
-include_lib("router_grpc/include/router_grpc_client.hrl").
-include_lib("gpb/include/gpb.hrl").

-record(params, {
  prompt :: binary() | undefined,
  out_dir :: list(),
  out_prefix :: list(),
  out_suffix :: list(),
  out_n = 0 :: integer(),
  host :: router_grpc_client:grpc_host(),
  port :: router_grpc_client:grpc_port(),
  service :: router_grpc_client:grpc_service(),
  method :: router_grpc_client:grpc_method(),
  rq_headers :: router_grpc_client:grpc_headers(),
  in_type :: atom(),
  out_type :: atom(),
  conn_pid :: pid() | undefined,
  stream_ref :: router_grpc_client:stream_ref() | undefined,
  h_pid :: pid() | undefined,
  o_pid :: pid() | undefined,
  i_pid :: pid() | undefined
}).

-define(prefix, "grpcc").
-define(suffix, "out").
-define(prompt, "> ").
-define(connection_timeout, 5000).

-define(msg_input(Data), {input, Data}).
-define(msg_headers(Data), {headers, Data}).
-define(msg_data(Data), {data, Data}).
-define(msg_trailers(Data), {trailers, Data}).
-define(msg_fin(Data), {fin, Data}).




%% Interface



config() ->
  [
    #getopt{r = true, s = {host, $h, "host", string, "Server host"}},
    #getopt{r = true, s = {port, $p, "port", integer, "Server port"}},
    #getopt{r = true, s = {service, $s, "service", string, "Fully-qualified service name (e.g. <package>.<service>)"}},
    #getopt{r = true, s = {method, $m, "method", string, "Method name"}},
    #getopt{r = true, s = {outdir, $o, "outdir", string, "Output directory for incoming PDUs"}},
    #getopt{s = {out_prefix, $P, "out-prefix", string, "File name prefix for incoming data files (default is 'grpcc')"}},
    #getopt{s = {out_suffix, $O, "out-suffix", string, "File name suffix for incoming data files (default is 'out')"}},
    #getopt{l = true, s = {header, $H, "header", string, "HTTP/2 header in format <name>=<value>"}},
    #getopt{s = {prompt, $C, "prompt", string, "Custom client prompt (default is '> ')"}}
  ].

additional_help_string() ->
  "Initiates a gRPC client with streaming capabilities. After launching the client, \n"
  "it will promptly establish a connection to the server.\n\n"
  "Once connected, the client will await user input following the client prompt \n"
  "(-P/--prompt). User input should be a path to a file containing a JSON \n"
  "object representing the gRPC PDU. The client will convert the JSON object to a \n"
  "protobuf-encoded PDU and transmit it to the server.\n\n"
  "Server responses will be converted to JSON and saved in a file within the output \n"
  "directory (-o/--outdir). The path to this file will be displayed with the proper \n"
  "prefix (HEADERS/DATA/TRAILERS).".



dispatch(Opts, _Rest) ->
  #params{
    host = Host, port = Port, service = Service, method = Method, in_type = InType, out_type = OutType
  } = Params = get_params(Opts),
  router_cli_log:log(
    "Router gRPCC connecting to ~ts:~p (~ts/~ts)~nInput type: ~ts~nOutput type: ~ts",
    [Host, Port, Service, Method, InType, OutType]
  ),
  {ok, _} = application:ensure_all_started(gun),
  {ok, ConnPid} = router_grpc_client:start_link(Host, Port),
  case router_grpc_client:await_ready(ConnPid, ?connection_timeout) of
    ok -> router_cli_log:log("Connection established");
    error -> router_cli:exit(?EXIT_CODE_INVALID_ARGS, "Cannot connect to ~ts:~p", [Host, Port])
  end,
  {ok, StreamRef} = router_grpc_client:grpc_request(ConnPid, self(), Service, Method, Params#params.rq_headers),
  OPid = spawn_o(Params),
  IPid = spawn_i(Params),
  h_loop(Params#params{conn_pid = ConnPid, stream_ref = StreamRef, o_pid = OPid, i_pid = IPid}).



%% Internals



get_params(#{host := Host, port := Port, service := Service, method := Method, outdir := Outdir} = Opts) ->
  Headers = get_headers(Opts),
  {InType, OutType} = get_types(Service, Method),
  #params{
    host = Host, port = Port, rq_headers = Headers, out_dir = Outdir,
    out_prefix = maps:get(out_prefix, Opts, ?prefix),
    out_suffix = maps:get(out_suffix, Opts, ?suffix),
    service = list_to_binary(Service),
    method = list_to_binary(Method),
    in_type = InType,
    out_type = OutType,
    prompt = list_to_binary(maps:get(prompt, Opts, ?prompt)),
    h_pid = self()
  }.



get_headers(#{header := RawHeaders}) ->
  maps:from_list([
    case binary:split(list_to_binary(RawHeader), <<"=">>) of
      [Key, Value] -> {Key, Value};
      _ -> router_cli:exit(?EXIT_CODE_INVALID_ARGS, "Invalid header provided: ~ts", [RawHeader])
    end || RawHeader <- RawHeaders
  ]);

get_headers(_) -> #{}.



get_types(Service, Method) ->
  try
    ServiceAtom = erlang:list_to_atom(Service),
    MethodAtom = erlang:list_to_atom(Method),
    {{service, ServiceAtom}, MethodsPL} = registry_definitions:get_service_def(ServiceAtom),
    #rpc{input = InType, output = OutType} = lists:keyfind(MethodAtom, #rpc.name, MethodsPL),
    {InType, OutType}
  catch _:_ ->
    router_cli:exit(?EXIT_CODE_INVALID_ARGS, "Cannot find service/method definition: ~ts/~ts", [Service, Method])
  end.



spawn_i(Params) ->
  spawn_link(fun() -> i_loop(Params) end).



i_loop(Params) ->
  case io:get_line(Params#params.prompt) of
    eof -> router_cli:exit(?EXIT_CODE_OK);
    {error, Reason} -> router_cli:exit(?EXIT_CODE_UNKNOWN, "~p", [Reason]);
    Data ->
      Params#params.h_pid ! ?msg_input(string:trim(Data)),
      i_loop(Params)
  end.



spawn_o(Params) ->
  spawn_link(fun() -> o_loop(Params) end).



o_loop(Params) ->
  receive
    ?msg_headers(Data) ->
      io:format("\rHEADERS:~ts~n", [Data]);
    ?msg_data(Data) ->
      io:format("\rDATA:~ts~n", [Data]);
    ?msg_trailers(Data) ->
      io:format("\rTRAILERS:~ts~n", [Data]);
    ?msg_fin(Data) ->
      io:format("~n~ts~n", [Data]);
    _ -> ignore
  end,
  o_loop(Params).



h_loop(#params{stream_ref = StreamRef} = Params) ->
  receive
    ?msg_input(Filename) ->
      h_loop(h_loop_handle_input(Filename, Params));
    ?grpc_event_response(StreamRef, IsFin, Status, Headers) ->
      h_loop(h_loop_handle_grpc_response(IsFin, Status, Headers, Params));
    ?grpc_event_data(StreamRef, IsFin, Data) ->
      h_loop(h_loop_handle_grpc_data(IsFin, Data, Params));
    ?grpc_event_trailers(StreamRef, Trailers) ->
      h_loop(h_loop_handle_grpc_trailers(Trailers, Params));
    ?grpc_event_stream_killed(StreamRef) ->
      Params#params.o_pid ! ?msg_fin("Stream closed"),
      router_cli:exit(?EXIT_CODE_OK);
    ?grpc_event_stream_unprocessed(StreamRef) ->
      Params#params.o_pid ! ?msg_fin("Stream closed (unprocessed)"),
      router_cli:exit(?EXIT_CODE_OK);
    ?grpc_event_connection_down(StreamRef) ->
      Params#params.o_pid ! ?msg_fin("Connection closed"),
      router_cli:exit(?EXIT_CODE_OK);
    Etc ->
      router_cli_log:log("Etc: ~p", [Etc]),
      h_loop(Params)
  end.



h_loop_handle_input("", Params) ->
  Params;

h_loop_handle_input(Filename, Params) ->
  case router_cli_handler_grpcc_json:decode(Params#params.in_type, Filename) of
    {ok, PduBin} ->
      h_loop_handle_input_send_pdu(PduBin, Params);
    {error, Reason} ->
      router_cli:exit(?EXIT_CODE_INVALID_INPUT, "Failed to decode json input: ~ts", [Reason])
  end.



h_loop_handle_input_send_pdu(PduBin, Params) ->
  ok = router_grpc_client:grpc_data(Params#params.conn_pid, Params#params.stream_ref, PduBin),
  Params.



h_loop_handle_grpc_response(_IsFin, Status, Headers, Params) ->
  case router_cli_handler_grpcc_json:encode_headers(
    Status, Headers, Params#params.out_dir, Params#params.out_prefix, Params#params.out_n, Params#params.out_suffix
  ) of
    {ok, Filename} ->
      Params#params.o_pid ! ?msg_headers(Filename);
    {error, Reason} ->
      router_cli:exit(?EXIT_CODE_UNKNOWN, "Failed to encode gRPC data: ~ts", [Reason])
  end,
  Params#params{out_n = Params#params.out_n + 1}.



h_loop_handle_grpc_data(_IsFin, Data, Params) ->
  case router_cli_handler_grpcc_json:encode_data(
    Params#params.out_type, Data, Params#params.out_dir, Params#params.out_prefix, Params#params.out_n, Params#params.out_suffix
  ) of
    {ok, Filename} ->
      Params#params.o_pid ! ?msg_data(Filename);
    {error, Reason} ->
      router_cli:exit(?EXIT_CODE_UNKNOWN, "Failed to encode gRPC data: ~ts", [Reason])
  end,
  Params#params{out_n = Params#params.out_n + 1}.



h_loop_handle_grpc_trailers(Trailers, Params) ->
  case router_cli_handler_grpcc_json:encode_trailers(
    Trailers, Params#params.out_dir, Params#params.out_prefix, Params#params.out_n, Params#params.out_suffix
  ) of
    {ok, Filename} ->
      Params#params.o_pid ! ?msg_trailers(Filename);
    {error, Reason} ->
      router_cli:exit(?EXIT_CODE_UNKNOWN, "Failed to encode gRPC data: ~ts", [Reason])
  end,
  Params#params{out_n = Params#params.out_n + 1}.

-module(router_cli_handler_grpcc_json).

-include_lib("router_cli/include/router_cli.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").

-export([decode/2, encode_headers/5, encode_data/5, encode_trailers/4]).

-define(format_error(Fmt, Args), iolist_to_binary(io_lib:format(Fmt, Args))).
-define(
  out_filename(Dir, Prefix, N, Suffix),
  lists:flatten([Dir, "/", Prefix, "-", integer_to_list(N), "-", Suffix, ".json"])
).

-define(prefix_headers, "headers").
-define(prefix_data, "data").
-define(prefix_trailers, "trailers").



%% Interface



-spec decode(Type :: atom(), Filename :: list()) ->
  type:generic_return(
    OkRet :: term(),
    ErrorRet :: binary()
  ).

decode(Type, Filename) ->
  decode_readfile(Type, Filename).



-spec encode_headers(
  Status :: pos_integer(),
  Headers :: router_grpc_client:grpc_headers(),
  Dir :: list(),
  N :: integer(),
  OutSuffix :: list()
) ->
  type:generic_return(
    OkRet :: list(),
    ErrorRet :: binary()
  ).

encode_headers(Status, Headers, Dir, N, OutSuffix) ->
  write_json(#{<<"status">> => Status, <<"headers">> => Headers}, Dir, ?prefix_headers, N, OutSuffix).



-spec encode_data(
  Type :: atom(),
  Data :: binary(),
  Dir :: list(),
  N :: integer(),
  Suffix :: list()
) ->
  type:generic_return(
    OkRet :: list(),
    ErrorRet :: binary()
  ).

encode_data(Type, Data, Dir, N, Suffix) ->
  encode_data_grpc_decode(Type, Data, Dir, N, Suffix).



-spec encode_trailers(
  Trailers :: router_grpc_client:grpc_headers(),
  Dir :: list(),
  N :: integer(),
  OutSuffix :: list()
) ->
  type:generic_return(
    OkRet :: list(),
    ErrorRet :: binary()
  ).
encode_trailers(Trailers, Dir, N, OutSuffix) ->
  write_json(#{<<"trailers">> => Trailers}, Dir, ?prefix_trailers, N, OutSuffix).



%% Internals



decode_readfile(Type, Filename) ->
  case file:read_file(Filename) of
    {ok, Bin} ->
      decode_parse(Type, Bin);
    {error, Reason} ->
      {error, ?format_error("Cannot read file '~ts': ~p", [Filename, Reason])}
  end.



decode_parse(Type, Bin) ->
  try
    decode_grpc_encode(decode_map(Type, jsone:decode(Bin)))
  catch _T:E ->
    {error, ?format_error("Cannot parse input file contents (~p)", [E])}
  end.



decode_grpc_encode(Record) -> {ok, registry_definitions:encode_msg(Record)}.



decode_map(_T, undefined) -> undefined;

decode_map('lg.service.router.RegisterVirtualServiceRq' = _T, Map) ->
  #'lg.service.router.RegisterVirtualServiceRq'{
    virtual_service = decode_map(
      'lg.core.grpc.VirtualService',
      maps:get(<<"virtual_service">>, Map, undefined)
    )
  };

decode_map('lg.service.router.RegisterVirtualServiceRs' = _T, _Map) ->
  #'lg.service.router.RegisterVirtualServiceRs'{};

decode_map('lg.service.router.UnregisterVirtualServiceRq' = _T, Map) ->
  #'lg.service.router.UnregisterVirtualServiceRq'{
    virtual_service = decode_map(
      'lg.core.grpc.VirtualService',
      maps:get(<<"virtual_service">>, Map, undefined)
    )
  };

decode_map('lg.service.router.UnregisterVirtualServiceRs' = _T, _Map) ->
  #'lg.service.router.UnregisterVirtualServiceRs'{};

decode_map('lg.service.router.EnableVirtualServiceMaintenanceRq' = _T, Map) ->
  #'lg.service.router.EnableVirtualServiceMaintenanceRq'{
    virtual_service = decode_map(
      'lg.core.grpc.VirtualService',
      maps:get(<<"virtual_service">>, Map, undefined)
    )
  };

decode_map('lg.service.router.EnableVirtualServiceMaintenanceRs' = _T, _Map) ->
  #'lg.service.router.EnableVirtualServiceMaintenanceRs'{};

decode_map('lg.service.router.DisableVirtualServiceMaintenanceRq' = _T, Map) ->
  #'lg.service.router.DisableVirtualServiceMaintenanceRq'{
    virtual_service = decode_map(
      'lg.core.grpc.VirtualService',
      maps:get(<<"virtual_service">>, Map, undefined)
    )
  };

decode_map('lg.service.router.DisableVirtualServiceMaintenanceRs' = _T, _Map) ->
  #'lg.service.router.DisableVirtualServiceMaintenanceRs'{};

decode_map('lg.service.router.ListVirtualServicesRq' = _T, Map) ->
  #'lg.service.router.ListVirtualServicesRq'{
    filter_fq_service_name = maps:get(<<"filter_fq_service_name">>, Map, undefined),
    filter_endpoint = decode_map('lg.core.network.Endpoint', maps:get(<<"filter_endpoint">>, Map, undefined)),
    pagination_request = decode_map('lg.core.trait.PaginationRq', maps:get(<<"pagination_request">>, Map, undefined))
  };

decode_map('lg.service.router.ListVirtualServicesRs' = _T, Map) ->
  #'lg.service.router.ListVirtualServicesRs'{
    services = [decode_map(
      'lg.core.grpc.VirtualService.StatelessVirtualService', Map_
    ) || Map_ <- maps:get(<<"services">>, Map, [])],
    pagination_response = decode_map('lg.core.trait.PaginationRs', maps:get(<<"pagination_response">>, Map, undefined))
  };

decode_map('lg.service.router.ControlStreamEvent.InitRq' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.InitRq'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    session_id = decode_map('lg.core.trait.Id', maps:get(<<"session_id">>, Map, undefined)),
    endpoint = decode_map('lg.core.network.Endpoint', maps:get(<<"endpoint">>, Map, undefined))
  };

decode_map('lg.service.router.ControlStreamEvent.InitRs' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.InitRs'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    session_id = decode_map('lg.core.trait.Id', maps:get(<<"session_id">>, Map, undefined)),
    result = decode_map('lg.core.network.Endpoint', maps:get(<<"result">>, Map, undefined))
  };

decode_map('lg.service.router.ControlStreamEvent.RegisterVirtualServiceRq' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRq'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    virtual_service = decode_map(
      'lg.core.grpc.VirtualService',
      maps:get(<<"virtual_service">>, Map, undefined)
    )
  };

decode_map('lg.service.router.ControlStreamEvent.RegisterVirtualServiceRs' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRs'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    result = decode_map('lg.core.network.Endpoint', maps:get(<<"result">>, Map, undefined))
  };

decode_map('lg.service.router.ControlStreamEvent.RegisterAgentRq' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.RegisterAgentRq'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    fq_service_name = maps:get(<<"fq_service_name">>, Map, undefined),
    agent_id = maps:get(<<"agent_id">>, Map, undefined),
    agent_instance = maps:get(<<"agent_instance">>, Map, undefined)
  };

decode_map('lg.service.router.ControlStreamEvent.RegisterAgentRs' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.RegisterAgentRs'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    agent_id = maps:get(<<"agent_id">>, Map, undefined),
    agent_instance = maps:get(<<"agent_instance">>, Map, undefined),
    result = decode_map('lg.core.network.Endpoint', maps:get(<<"result">>, Map, undefined))
  };

decode_map('lg.service.router.ControlStreamEvent.UnregisterAgentRq' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.UnregisterAgentRq'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    fq_service_name = maps:get(<<"fq_service_name">>, Map, undefined),
    agent_id = maps:get(<<"agent_id">>, Map, undefined),
    agent_instance = maps:get(<<"agent_instance">>, Map, undefined)
  };

decode_map('lg.service.router.ControlStreamEvent.UnregisterAgentRs' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.UnregisterAgentRs'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    result = decode_map('lg.core.network.Endpoint', maps:get(<<"result">>, Map, undefined))
  };

decode_map('lg.service.router.ControlStreamEvent.ConflictEvent' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent.ConflictEvent'{
    id = decode_map('lg.core.trait.Id', maps:get(<<"id">>, Map, undefined)),
    fq_service_name = maps:get(<<"fq_service_name">>, Map, undefined),
    agent_id = maps:get(<<"agent_id">>, Map, undefined),
    agent_instance = maps:get(<<"agent_instance">>, Map, undefined),
    reason = maps:get(<<"reason">>, Map, undefined)
  };

decode_map('lg.service.router.ControlStreamEvent' = _T, Map) ->
  #'lg.service.router.ControlStreamEvent'{
    event = decode_map('lg.service.router.ControlStreamEvent.event', maps:get(<<"event">>, Map, undefined))
  };

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"init_rq">> := Map}) ->
  {init_rq, decode_map('lg.service.router.ControlStreamEvent.InitRq', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"init_rs">> := Map}) ->
  {init_rs, decode_map('lg.service.router.ControlStreamEvent.InitRs', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"register_virtual_service_rq">> := Map}) ->
  {register_virtual_service_rq, decode_map('lg.service.router.ControlStreamEvent.RegisterVirtualServiceRq', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"register_virtual_service_rs">> := Map}) ->
  {register_virtual_service_rs, decode_map('lg.service.router.ControlStreamEvent.RegisterVirtualServiceRs', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"unregister_virtual_service_rq">> := Map}) ->
  {unregister_virtual_service_rq, decode_map('lg.service.router.ControlStreamEvent.UnregisterVirtualServiceRq', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"unregister_virtual_service_rs">> := Map}) ->
  {unregister_virtual_service_rs, decode_map('lg.service.router.ControlStreamEvent.UnregisterVirtualServiceRs', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"register_agent_rq">> := Map}) ->
  {register_agent_rq, decode_map('lg.service.router.ControlStreamEvent.RegisterAgentRq', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"unregister_agent_rq">> := Map}) ->
  {unregister_agent_rq, decode_map('lg.service.router.ControlStreamEvent.UnregisterAgentRq', Map)};

decode_map('lg.service.router.ControlStreamEvent.event' = _T, #{<<"conflict_event">> := Map}) ->
  {conflict_event, decode_map('lg.service.router.ControlStreamEvent.ConflictEvent', Map)};

decode_map('lg.core.grpc.VirtualService.Method' = _T, Map) ->
  #'lg.core.grpc.VirtualService.Method'{
    name = maps:get(<<"name">>, Map, undefined)
  };

decode_map('lg.core.grpc.VirtualService.StatelessVirtualService' = _T, Map) ->
  #'lg.core.grpc.VirtualService.StatelessVirtualService'{
    package = maps:get(<<"package">>, Map, undefined),
    name = maps:get(<<"name">>, Map, undefined),
    methods = [decode_map(
      'lg.core.grpc.VirtualService.Method', Map_
    ) || Map_ <- maps:get(<<"methods">>, Map, [])]
  };

decode_map('lg.core.grpc.VirtualService.StatefulVirtualService' = _T, Map) ->
  #'lg.core.grpc.VirtualService.StatefulVirtualService'{
    package = maps:get(<<"package">>, Map, undefined),
    name = maps:get(<<"name">>, Map, undefined),
    methods = [decode_map(
      'lg.core.grpc.VirtualService.Method', Map_
    ) || Map_ <- maps:get(<<"methods">>, Map, [])],
    cmp = decode_map('lg.core.grpc.VirtualService.StatefulVirtualService.cmp', maps:get(<<"cmp">>, Map, undefined))
  };

decode_map('lg.core.grpc.VirtualService.StatefulVirtualService.cmp' = _T, <<"PREEMPTIVE">>) -> 'PREEMPTIVE';

decode_map('lg.core.grpc.VirtualService.StatefulVirtualService.cmp' = _T, <<"BLOCKING">>) -> 'BLOCKING';

decode_map('lg.core.grpc.VirtualService' = _T, Map) ->
  #'lg.core.grpc.VirtualService'{
    service = decode_map('lg.core.grpc.VirtualService.service', maps:get(<<"service">>, Map, undefined)),
    maintenance_mode_enabled = maps:get(<<"maintenance_mode_enabled">>, Map, undefined),
    endpoint = decode_map('lg.core.network.Endpoint', maps:get(<<"endpoint">>, Map, undefined))
  };

decode_map('lg.core.grpc.VirtualService.service' = _T, #{<<"stateless">> := Map}) ->
  {stateless, decode_map('lg.core.grpc.VirtualService.StatelessVirtualService', Map)};

decode_map('lg.core.grpc.VirtualService.service' = _T, #{<<"stateful">> := Map}) ->
  {stateful, decode_map('lg.core.grpc.VirtualService.StatelfulVirtualService', Map)};

decode_map('lg.core.trait.PaginationRq' = _T, Map) ->
  #'lg.core.trait.PaginationRq'{
    page_token = maps:get(<<"page_token">>, Map, undefined),
    page_size = maps:get(<<"page_size">>, Map, undefined)
  };

decode_map('lg.core.trait.PaginationRs' = _T, Map) ->
  #'lg.core.trait.PaginationRs'{
    next_page_token = maps:get(<<"next_page_token">>, Map, undefined)
  };

decode_map('lg.core.trait.Id' = _T, Map) ->
  #'lg.core.trait.Id'{
    id = maps:get(<<"id">>, Map, undefined)
  };

decode_map('lg.core.trait.Result' = _T, Map) ->
  #'lg.core.trait.Result'{
    status = decode_map('lg.core.trait.Result.status', maps:get(<<"status">>, Map, undefined)),
    error_message = maps:get(<<"error_message">>, Map, undefined),
    error_meta = maps:to_list(maps:get(<<"error_meta">>, Map, #{})),
    debug_info = maps:to_list(maps:get(<<"debug_info">>, Map, #{}))
  };

decode_map('lg.core.network.Endpoint' = _T, Map) ->
  #'lg.core.network.Endpoint'{
    host = maps:get(<<"host">>, Map, undefined),
    port = maps:get(<<"port">>, Map, undefined)
  };

decode_map('lg.core.network.URI' = T, _Map) ->
  %% #'lg.core.network.URI'{}
  {error, ?format_error("PDU of type '~ts' is not implemented", [T])};

decode_map('lg.core.network.PlainURI' = T, _Map) ->
  %% #'lg.core.network.PlainURI'{}
  {error, ?format_error("PDU of type '~ts' is not implemented", [T])}.



encode_data_grpc_decode(Type, Data, Dir, N, Suffix) ->
  Record = registry_definitions:decode_msg(Data, Type),
  Map = encode_data_map(Record),
  write_json(Map, Dir, ?prefix_data, N, Suffix).



encode_data_map(#'lg.service.router.RegisterVirtualServiceRq'{
  virtual_service = VirtualService
}) ->
  #{<<"virtual_service">> => encode_data_map(VirtualService)};

encode_data_map(#'lg.service.router.RegisterVirtualServiceRs'{}) -> #{};

encode_data_map(#'lg.service.router.UnregisterVirtualServiceRq'{
  virtual_service = VirtualService
}) ->
  #{<<"virtual_service">> => encode_data_map(VirtualService)};

encode_data_map(#'lg.service.router.UnregisterVirtualServiceRs'{}) -> #{};

encode_data_map(#'lg.service.router.EnableVirtualServiceMaintenanceRq'{
  virtual_service = VirtualService
}) ->
  #{<<"virtual_service">> => encode_data_map(VirtualService)};

encode_data_map(#'lg.service.router.EnableVirtualServiceMaintenanceRs'{}) -> #{};

encode_data_map(#'lg.service.router.DisableVirtualServiceMaintenanceRq'{
  virtual_service = VirtualService
}) ->
  #{<<"virtual_service">> => encode_data_map(VirtualService)};

encode_data_map(#'lg.service.router.DisableVirtualServiceMaintenanceRs'{}) -> #{};

encode_data_map(#'lg.service.router.ListVirtualServicesRq'{
  filter_fq_service_name = FilterFqServiceName,
  filter_endpoint = FilterEndpoint,
  pagination_request = PaginationRequest
}) ->
  #{
    <<"filter_fq_service_name">> => FilterFqServiceName,
    <<"filter_endpoint">> => encode_data_map(FilterEndpoint),
    <<"pagination_request">> => encode_data_map(PaginationRequest)
  };

encode_data_map(#'lg.service.router.ListVirtualServicesRs'{
  services = Services,
  pagination_response = PaginationResponse
}) ->
  #{
    <<"services">> => [encode_data_map(Record) || Record <- Services],
    <<"pagination_response">> => encode_data_map(PaginationResponse)
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.InitRq'{
  id = Id,
  session_id = SessionId,
  endpoint = Endpoint
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"session_id">> => SessionId,
    <<"endpoint">> => encode_data_map(Endpoint)
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.InitRs'{
  id = Id,
  session_id = SessionId,
  result = Result
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"session_id">> => SessionId,
    <<"result">> => encode_data_map(Result)
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRq'{
  id = Id,
  virtual_service = VirtualService
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"virtual_service">> => encode_data_map(VirtualService)
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.RegisterVirtualServiceRs'{
  id = Id,
  result = Result
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"result">> => encode_data_map(Result)
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.RegisterAgentRq'{
  id = Id,
  fq_service_name = FqServiceName,
  agent_id = AgentId,
  agent_instance = AgentInstance
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"fq_service_name">> => FqServiceName,
    <<"agent_id">> => AgentId,
    <<"agent_instance">> => AgentInstance
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.RegisterAgentRs'{
  id = Id,
  agent_id = AgentId,
  agent_instance = AgentInstance,
  result = Result
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"agent_id">> => AgentId,
    <<"agent_instance">> => AgentInstance,
    <<"result">> => encode_data_map(Result)
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.UnregisterAgentRq'{
  id = Id,
  fq_service_name = FqServiceName,
  agent_id = AgentId,
  agent_instance = AgentInstance
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"fq_service_name">> => FqServiceName,
    <<"agent_id">> => AgentId,
    <<"agent_instance">> => AgentInstance
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.UnregisterAgentRs'{
  id = Id,
  result = Result
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"result">> => encode_data_map(Result)
  };

encode_data_map(#'lg.service.router.ControlStreamEvent.ConflictEvent'{
  id = Id,
  fq_service_name = FqServiceName,
  agent_id = AgentId,
  agent_instance = AgentInstance,
  reason = Reason
}) ->
  #{
    <<"id">> => encode_data_map(Id),
    <<"fq_service_name">> => FqServiceName,
    <<"agent_id">> => AgentId,
    <<"agent_instance">> => AgentInstance,
    <<"reason">> => Reason
  };

encode_data_map(#'lg.service.router.ControlStreamEvent'{event = {TypeAtom, Event}}) ->
  #{<<"event">> => #{atom_to_binary(TypeAtom) => encode_data_map(Event)}};

encode_data_map(#'lg.core.grpc.VirtualService.Method'{name = Name}) ->
  #{<<"name">> => Name};

encode_data_map(#'lg.core.grpc.VirtualService.StatelessVirtualService'{
  package = Package,
  name = Name,
  methods = Methods
}) ->
  #{
    <<"package">> => Package,
    <<"name">> => Name,
    <<"methods">> => [encode_data_map(Record) || Record <- Methods]
  };

encode_data_map(#'lg.core.grpc.VirtualService.StatefulVirtualService'{
  package = Package,
  name = Name,
  methods = Methods,
  cmp = Cmp
}) ->
  #{
    <<"package">> => Package,
    <<"name">> => Name,
    <<"methods">> => [encode_data_map(Record) || Record <- Methods],
    <<"cmp">> => atom_to_binary(Cmp)
  };

encode_data_map(#'lg.core.grpc.VirtualService'{
  service = {Type, Service},
  maintenance_mode_enabled = MaintenanceMode,
  endpoint = Endpoint
}) ->
  #{
    <<"service">> => #{atom_to_binary(Type) => encode_data_map(Service)},
    <<"maintenance_mode_enabled">> => MaintenanceMode,
    <<"endpoint">> => encode_data_map(Endpoint)
  };

encode_data_map(#'lg.core.trait.PaginationRq'{
  page_token = PageToken,
  page_size = PageSize
}) ->
  #{
    <<"page_token">> => PageToken,
    <<"page_size">> => PageSize
  };

encode_data_map(#'lg.core.trait.PaginationRs'{next_page_token = NextPageToken}) ->
  #{<<"next_page_token">> => NextPageToken};

encode_data_map(#'lg.core.trait.Id'{id = Id}) ->
  #{<<"id">> => Id};

encode_data_map(#'lg.core.trait.Result'{
  status = Status,
  error_message = ErrorMessage,
  error_meta = ErrorMeta,
  debug_info = DebugInfo
}) ->
  #{
    <<"status">> => atom_to_binary(Status),
    <<"error_message">> => ErrorMessage,
    <<"error_meta">> => ErrorMeta,
    <<"debug_info">> => DebugInfo
  };

encode_data_map(#'lg.core.network.Endpoint'{
  host = Host,
  port = Port
}) ->
  #{
    <<"host">> => Host,
    <<"port">> => Port
  };

encode_data_map(#'lg.core.network.URI'{}) ->
  #{<<"error">> => <<"not_implemented">>};

encode_data_map(#'lg.core.network.PlainURI'{}) ->
  #{<<"error">> => <<"not_implemented">>}.



write_json(Map, Dir, Prefix, N, Suffix) ->
  try
    Bin = jsone:encode(Map, [{indent, 2}, {space, 1}]),
    Filename = ?out_filename(Dir, Prefix, N, Suffix),
    case file:write_file(Filename, Bin) of
      ok ->
        {ok, Filename};
      {error, Reason} ->
        {error, ?format_error("Cannot write file '~ts': ~p", [Filename, Reason])}
    end
  catch _T:E ->
    {error, ?format_error("Cannot encode output file contents (~p)", [E])}
  end.

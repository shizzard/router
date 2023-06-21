-module(router_grpc_external_stream_h).
-behaviour(gen_server).

-include_lib("router_log/include/router_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").
-include_lib("router_pb/include/registry_definitions.hrl").
-include_lib("router_grpc/include/router_grpc_service_registry.hrl").
-include_lib("router_grpc/include/router_grpc_client.hrl").

-export([data/3]).
-export([
  start_link/3, init/1,
  handle_call/3, handle_cast/2, handle_info/2,
  terminate/2, code_change/3
]).

-record(state, {
  definition :: router_grpc:definition_external(),
  req :: cowboy_req:req(),
  worker_pid :: pid() | undefined,
  stream_ref :: cowboy_stream:streamid(),
  ctx :: router_grpc_external_context:t()
}).
-type state() :: #state{}.

-define(reinit_stream_backoff_ms, 500).



%% Messages



-define(msg_data(IsFin, Data), {msg_data, IsFin, Data}).



%% Metrics



%% Interface



-spec start_link(
  Definition :: router_grpc:definition_external(),
  Req :: cowboy_req:req(),
  Ctx :: router_grpc_external_context:t()
) ->
  typr:ok_return(OkRet :: pid()).

start_link(Definition, Req, Ctx) ->
  gen_server:start_link(?MODULE, {Definition, Req, Ctx}, []).



init({Definition, Req, Ctx}) ->
  router_log:component(router_grpc_external),
  ok = quickrand:seed(),
  ok = init_prometheus_metrics(),
  init_get_worker(#state{definition = Definition, req = Req, ctx = Ctx}).

init_get_worker(#state{definition = Definition} = S0) ->
  case router_grpc_client_pool:get_random_worker(Definition) of
    {ok, WorkerPid} ->
      init_send_request(S0#state{worker_pid = WorkerPid});
    {error, empty} ->
      {stop, no_available_workers}
  end.

init_send_request(#state{
  definition = Definition,
  req = #{path := Path, headers := Headers},
  worker_pid = WorkerPid,
  ctx = Ctx
} = S0) ->
  %% dirty
  [<<>>, _Fqsn, Method] = binary:split(Path, <<"/">>, [global]),
  case router_grpc_client:grpc_request(
    WorkerPid,
    self(),
    Definition#router_grpc_service_registry_definition_external.fq_service_name,
    Method,
    maps:merge(Headers, router_grpc_external_context:to_headers_map(Ctx))
  ) of
    {ok, StreamRef} ->
      {ok, S0#state{stream_ref = StreamRef}};
    {error, not_ready} ->
      {stop, worker_not_ready}
  end.



-spec data(
  Pid :: pid(),
  IsFin :: boolean(),
  Data ::binary()
) ->
  typr:ok_return().

data(Pid, IsFin, Data) ->
  gen_server:cast(Pid, ?msg_data(IsFin, Data)).



%% Handlers



handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(?msg_data(IsFin, Data), #state{
  worker_pid = WorkerPid, stream_ref = StreamRef
} = S0) ->
  router_grpc_client:grpc_data(WorkerPid, StreamRef, IsFin, Data),
  {noreply, S0};

handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



% grpc_event_stream_killed(StreamRef), {router_grpc_client, stream_killed, StreamRef}
% grpc_event_stream_unprocessed(StreamRef), {router_grpc_client, stream_unprocessed, StreamRef}
% grpc_event_connection_down(StreamRef), {router_grpc_client, connection_down, StreamRef}
% grpc_event_response(StreamRef, IsFin, Status, Headers), {router_grpc_client, response, StreamRef, IsFin, Status, Headers}
% grpc_event_data(StreamRef, IsFin, Data), {router_grpc_client, data, StreamRef, IsFin, Data}
% grpc_event_trailers(StreamRef, Trailers), {router_grpc_client, trailers, StreamRef, Trailers}

handle_info(?grpc_event_response(StreamRef, IsFin, Status, Headers), #state{
  req = Req, stream_ref = StreamRef, ctx = Ctx
} = S0) ->
  ok = router_grpc_h:push_headers(IsFin, Status, maps:merge(Headers, router_grpc_external_context:to_headers_map(Ctx)), Req),
  {noreply, S0};

handle_info(?grpc_event_data(StreamRef, IsFin, Data), #state{req = Req, stream_ref = StreamRef} = S0) ->
  ok = router_grpc_h:push_data(IsFin, Data, Req),
  {noreply, S0};

handle_info(?grpc_event_trailers(StreamRef, Trailers), #state{
  req = Req, stream_ref = StreamRef, ctx = Ctx
} = S0) ->
  ok = router_grpc_h:push_trailers(maps:merge(Trailers, router_grpc_external_context:to_headers_map(Ctx)), Req),
  {noreply, S0};

handle_info(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected info (incorrect stream ref?)", what => handle_info, details => Unexpected}),
  {noreply, S0}.



terminate(_Reason, _S0) ->
  ok.



code_change(_OldVsn, S0, _Extra) ->
  {ok, S0}.



%% Internals



init_prometheus_metrics() ->
  ok.

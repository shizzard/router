-module(rtgw_tunnel_registry).
-behaviour(gen_server).

-compile([nowarn_untyped_record]).

-include_lib("rtgw/include/rtgw_tunnel.hrl").
-include_lib("rtgw_log/include/rtgw_log.hrl").
-include_lib("typr/include/typr_specs_gen_server.hrl").

-export([create/4, lookup/1, add_traffic/3]).
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
  registry :: ets:tid()
}).
-type state() :: #state{}.



%% Messages



%% Metrics



%% Interface



-spec create(
  Name :: binary(),
  Secret :: binary(),
  Host :: binary(),
  Port :: pos_integer()
) ->
  typr:generic_return(ErrorRet :: duplicate).

create(Name, Secret, Host, Port) ->
  Tunnel = #tunnel{
    name = Name, secret = Secret, host = Host, port = Port
  },
  case ets:insert_new(?MODULE, Tunnel) of
    true -> ok;
    false -> {error, duplicate}
  end.



-spec lookup(Name :: binary()) ->
  typr:generic_return(
    OkRet :: #tunnel{},
    ErrorRet :: not_found
  ).

lookup(Name) ->
  case ets:lookup(?MODULE, Name) of
    [] -> {error, not_found};
    [Tunnel] -> {ok, Tunnel}
  end.



-spec add_traffic(
  Name :: binary(),
  Type :: in | out,
  Bytes :: pos_integer()
) ->
  typr:ok_return().

add_traffic(Name, Type, Bytes) ->
  case lookup(Name) of
    {ok, Tunnel0} ->
      Tunnel1 = case Type of
        in -> Tunnel0#tunnel{traffic_in_bytes = Tunnel0#tunnel.traffic_in_bytes + Bytes};
        out -> Tunnel0#tunnel{traffic_out_bytes = Tunnel0#tunnel.traffic_out_bytes + Bytes}
      end,
      ets:insert(?MODULE, Tunnel1),
      ok;
    {error, not_found} ->
      ok
  end.




-spec start_link() ->
  typr:ok_return(OkRet :: pid()).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, {}, []).



init({}) ->
  rtgw_log:component(rtgw_tunnel),
  ok = quickrand:seed(),
  S0 = #state{
    registry = ets:new(?MODULE, [
      named_table, ordered_set, public, {read_concurrency, true}, {keypos, #tunnel.name}
    ])
  },
  {ok, S0}.



%% Handlers



handle_call(Unexpected, _GenReplyTo, S0) ->
  ?l_error(#{text => "Unexpected call", what => handle_call, details => Unexpected}),
  {reply, badarg, S0}.



handle_cast(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected cast", what => handle_cast, details => Unexpected}),
  {noreply, S0}.



handle_info(Unexpected, S0) ->
  ?l_warning(#{text => "Unexpected info", what => handle_info, details => Unexpected}),
  {noreply, S0}.



terminate(_Reason, _S0) ->
  ok.



code_change(_OldVsn, S0, _Extra) ->
  {ok, S0}.



%% Internals

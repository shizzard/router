-define(trailer_package_empty, <<"package_empty">>).
-define(trailer_package_restricted, <<"package_restricted">>).
-define(trailer_name_empty, <<"name_empty">>).
-define(trailer_method_empty, <<"method_empty">>).
-define(trailer_cmp_invalid, <<"cmp_invalid">>).
-define(trailer_host_empty, <<"host_empty">>).
-define(trailer_port_invalid, <<"port_invalid">>).
-define(trailer_filter_endpoint_host_empty, <<"filter_endpoint_host_empty">>).
-define(trailer_filter_endpoint_port_invalid, <<"filter_endpoint_port_invalid">>).
-define(trailer_pagination_request_not_implemented, <<"pagination_request_not_implemented">>).
-define(trailer_pagination_request_page_size_invalid, <<"pagination_request_page_size_invalid">>).
-define(trailer_pagination_request_page_token_invalid, <<"pagination_request_page_token_invalid">>).
-define(trailer_id_empty, <<"id_empty">>).
-define(trailer_control_stream_reinit, <<"re_init">>).
-define(trailer_control_stream_noinit, <<"no_init">>).
-define(trailer_control_stream_session_expired, <<"session_expired">>).
-define(trailer_control_stream_session_resume_failed, <<"session_resume_failed">>).
-define(trailer_fq_service_name_empty, <<"fq_service_name_empty">>).
-define(trailer_agent_id_empty, <<"agent_id_empty">>).
-define(trailer_conflict, <<"conflict">>).
-define(trailer_service_invalid, <<"service_invalid">>).

-define(trailer_package_empty_message(_Package), <<"Virtual service package cannot be empty">>).
-define(trailer_package_restricted_message(Package), <<"Virtual service package is restricted: ", Package/binary>>).
-define(trailer_name_empty_message(_Name), <<"Virtual service name cannot be empty">>).
-define(trailer_method_empty_message(_Name), <<"Virtual service method cannot be empty">>).
-define(trailer_cmp_invalid_message(Cmp),
  iolist_to_binary(io_lib:format(
    "Existing registered virtual service conflict management policy mismatched with the provided one: ~ts",
    [Cmp]
  ))).
-define(trailer_host_empty_message(_Name), <<"Virtual service instance host cannot be empty">>).
-define(trailer_port_invalid_message(Port), <<"Virtual service instance port must fall into 1..65535 interval: ", (integer_to_binary(Port))/binary>>).
-define(trailer_filter_endpoint_host_empty_message(_Host), <<"Endpoint filter host cannot be empty with non-zero port">>).
-define(trailer_filter_endpoint_port_invalid_message(Port), <<"Endpoint filter port must fall into 1..65535 interval when endpoint filter host is not empty: ", (integer_to_binary(Port))/binary>>).
-define(trailer_pagination_request_not_implemented_message(_), <<"ListVirtualServices pagination_request not implemented">>).
-define(trailer_pagination_request_page_size_invalid_message(PageSize), <<"Pagination request page size is invalid: ", (integer_to_binary(PageSize))/binary>>).
-define(trailer_pagination_request_page_token_invalid_message(PageToken), <<"Pagination request page token is invalid: ", PageToken/binary>>).
-define(trailer_id_empty_message(_), <<"Request id cannot be empty">>).
-define(trailer_control_stream_reinit_message_init(_), <<"InitRq was already handled within the control stream">>).
-define(trailer_control_stream_reinit_message_resume(_), <<"InitRq was already handled within the control stream">>).
-define(trailer_control_stream_noinit_message(_), <<"InitRq/ResumeRq must be handled within the control stream first">>).
-define(trailer_control_stream_session_expired_message(_), <<"Session identified by provided id already expired">>).
-define(trailer_control_stream_session_resume_failed_message(Reason), case Reason of
  conn_alive -> <<"Session resume failed: original connection is still alive">>
end).
-define(trailer_fq_service_name_empty_message(_), <<"Fully qualified service name cannot be empty">>).
-define(trailer_agent_id_empty_message(_), <<"Agent id cannot be empty">>).
-define(trailer_service_invalid_message(Fqsn, Host, Port),
  iolist_to_binary(io_lib:format(
    "There is no registered service ~ts@~ts:~p",
    [Fqsn, Host, Port]
  ))
).
-define(trailer_service_invalid_stateless(_), <<"Control stream cannot be initiated with stateless virtual service declaration">>).

-define(control_stream_init_error_message_mismatched_virtual_service,
  <<"Existing registered virtual service significantly mismatches with the provided one">>).
-define(control_stream_register_agent_error_conflict_blocking,
  <<"Cannot register agent due to conflict management policy: blocking">>).
-define(control_stream_generic_error_ise, <<"Internal Server Error">>).

-define(control_stream_init_error_meta_mismatched_virtual_service_cmp, ?trailer_cmp_invalid).
-define(control_stream_init_error_meta_mismatched_virtual_service_cmp_message(Cmp), ?trailer_cmp_invalid_message(Cmp)).
-define(control_stream_register_agent_error_meta_conflict_blocking, <<"conflict">>).
-define(control_stream_register_agent_error_meta_conflict_blocking_message(Fqsn, AgentId, AgentInstance),
  iolist_to_binary(io_lib:format(
    "Agent ~ts@~ts/~ts is already registered in the system and the conflict management policy is set to 'BLOCKING'",
    [AgentId, Fqsn, AgentInstance]
  ))
).
-define(control_stream_register_agent_error_meta_ise, <<"internal_server_error">>).
-define(control_stream_register_agent_error_meta_ise_message(Fqsn, AgentId, AgentInstance),
  iolist_to_binary(io_lib:format(
    "Internal Server Error occured while trying to register agent ~ts@~ts/~ts; check server error logs for more information",
    [AgentId, Fqsn, AgentInstance]
  ))
).
-define(control_stream_unregister_agent_error_meta_ise, <<"internal_server_error">>).
-define(control_stream_unregister_agent_error_meta_ise_message(Fqsn, AgentId, AgentInstance),
  iolist_to_binary(io_lib:format(
    "Internal Server Error occured while trying to unregister agent ~ts@~ts/~ts; check server error logs for more information",
    [AgentId, Fqsn, AgentInstance]
  ))
).

-define(control_stream_conflict_event_reason_preemptive, <<"Force degeristration occured due to conflict management policy: preemptive">>).

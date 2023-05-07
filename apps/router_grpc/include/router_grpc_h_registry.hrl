-define(trailer_package_empty, <<"package_empty">>).
-define(trailer_package_restricted, <<"package_restricted">>).
-define(trailer_name_empty, <<"name_empty">>).
-define(trailer_method_empty, <<"method_empty">>).
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
-define(trailer_control_stream_session_recovery_failed, <<"session_recovery_failed">>).

-define(trailer_package_empty_message(_Package), <<"Virtual service package cannot be empty">>).
-define(trailer_package_restricted_message(Package), <<"Virtual service package is restricted: ", Package/binary>>).
-define(trailer_name_empty_message(_Name), <<"Virtual service name cannot be empty">>).
-define(trailer_method_empty_message(_Name), <<"Virtual service method cannot be empty">>).
-define(trailer_host_empty_message(_Name), <<"Virtual service instance host cannot be empty">>).
-define(trailer_port_invalid_message(Port), <<"Virtual service instance port must fall into 1..65535 interval: ", (integer_to_binary(Port))/binary>>).
-define(trailer_filter_endpoint_host_empty_message(_Host), <<"Endpoint filter host cannot be empty with non-zero port">>).
-define(trailer_filter_endpoint_port_invalid_message(Port), <<"Endpoint filter port must fall into 1..65535 interval when endpoint filter host is not empty: ", (integer_to_binary(Port))/binary>>).
-define(trailer_pagination_request_not_implemented_message(_), <<"ListVirtualServices pagination_request not implemented">>).
-define(trailer_pagination_request_page_size_invalid_message(PageSize), <<"Pagination request page size is invalid: ", (integer_to_binary(PageSize))/binary>>).
-define(trailer_pagination_request_page_token_invalid_message(PageToken), <<"Pagination request page token is invalid: ", PageToken/binary>>).
-define(trailer_id_empty_message(_), <<"Request id cannot be empty">>).
-define(trailer_control_stream_reinit_message(_), <<"InitRq was already handled within the control stream">>).
-define(trailer_control_stream_noinit_message(_), <<"InitRq must be handled within the control stream first">>).
-define(trailer_control_stream_session_expired_message(_), <<"Session identified by provided id already expired">>).
-define(trailer_control_stream_session_recovery_failed_message(Reason), case Reason of
  conn_alive -> <<"Session recovery failed: original connection is still alive">>;
  invalid_endpoint -> <<"Session recovery failed: endpoint parameters do not match original ones">>
end).

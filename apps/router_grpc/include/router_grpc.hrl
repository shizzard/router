%% Router-specific headers

-define(router_grpc_header_prefix, "x-router-").
-define(router_grpc_header_agent_id, <<?router_grpc_header_prefix, "agent-id">>).
-define(router_grpc_header_agent_instance, <<?router_grpc_header_prefix, "agent-instance">>).
-define(router_grpc_header_request_id, <<?router_grpc_header_prefix, "request-id">>).

%% Headers

-define(grpc_header_code, <<"grpc-status">>).
-define(grpc_header_message, <<"grpc-message">>).

-define(http2_header_content_type, <<"content-type">>).
-define(http2_header_te, <<"te">>).

-define(grpc_header_timeout, <<"grpc-timeout">>).
-define(grpc_header_encoding, <<"grpc-encoding">>).
-define(grpc_header_accept_encoding, <<"grpc-accept-encoding">>).
-define(grpc_header_user_agent, <<"grpc-user-agent">>).
-define(grpc_header_message_type, <<"grpc-message-type">>).

%% Response codes
-define(grpc_code_ok, 0).
-define(grpc_code_canceled, 1).
-define(grpc_code_unknown, 2).
-define(grpc_code_invalid_argument, 3).
-define(grpc_code_deadline_exceeded, 4).
-define(grpc_code_not_found, 5).
-define(grpc_code_already_exists, 6).
-define(grpc_code_permission_denied, 7).
-define(grpc_code_resource_exhausted, 8).
-define(grpc_code_failed_precondition, 9).
-define(grpc_code_aborted, 10).
-define(grpc_code_out_of_range, 11).
-define(grpc_code_unimplemented, 12).
-define(grpc_code_internal, 13).
-define(grpc_code_unavailable, 14).
-define(grpc_code_data_loss, 15).
-define(grpc_code_unauthenticated, 16).

%% Response messages
-define(grpc_message_ok, <<>>).
-define(grpc_message_canceled, <<"Request canceled">>).
-define(grpc_message_unknown, <<"Unknown error">>).
-define(grpc_message_invalid_argument, <<"Invalid argument">>).
-define(grpc_message_invalid_argument_payload, <<"Invalid payload">>).
-define(grpc_message_deadline_exceeded, <<"Deadline exceeded">>).
-define(grpc_message_not_found, <<"Entity not found">>).
-define(grpc_message_already_exists, <<"Entity already exists">>).
-define(grpc_message_permission_denied, <<"Permission denied">>).
-define(grpc_message_resource_exhausted, <<"Resource exhausted">>).
-define(grpc_message_failed_precondition, <<"Precondition failed">>).
-define(grpc_message_aborted, <<"Request aborted">>).
-define(grpc_message_out_of_range, <<"Out of range">>).
-define(grpc_message_unimplemented, <<"Not implemented">>).
-define(grpc_message_unimplemented_compression, <<"Payload compression is not supported">>).
-define(grpc_message_internal, <<"Internal server error">>).
-define(grpc_message_unavailable, <<"Unavailable">>).
-define(grpc_message_data_loss, <<"Fatal data loss">>).
-define(grpc_message_unauthenticated, <<"Unauthenticated">>).

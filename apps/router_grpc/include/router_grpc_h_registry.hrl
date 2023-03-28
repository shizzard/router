-define(trailer_package_empty, <<"package_empty">>).
-define(trailer_package_restricted, <<"package_restricted">>).
-define(trailer_name_empty, <<"name_empty">>).
-define(trailer_method_empty, <<"method_empty">>).
-define(trailer_host_empty, <<"host_empty">>).
-define(trailer_port_invalid, <<"port_invalid">>).
-define(trailer_filter_endpoint_host_empty, <<"filter_endpoint_host_empty">>).
-define(trailer_filter_endpoint_port_invalid, <<"filter_endpoint_port_invalid">>).
-define(trailer_pagination_request_not_implemented, <<"pagination_request_not_implemented">>).

-define(trailer_package_empty_message(_Package), <<"Virtual service package cannot be empty">>).
-define(trailer_package_restricted_message(Package), <<"Virtual service package is restricted: ", Package/binary>>).
-define(trailer_name_empty_message(_Name), <<"Virtual service name cannot be empty">>).
-define(trailer_method_empty_message(_Name), <<"Virtual service method cannot be empty">>).
-define(trailer_host_empty_message(_Name), <<"Virtual service instance host cannot be empty">>).
-define(trailer_port_invalid_message(Port), <<"Virtual service instance port must fall into 1..65535 interval: ", (integer_to_binary(Port))/binary>>).
-define(trailer_filter_endpoint_host_empty_message(_Host), <<"Endpoint filter host cannot be empty with non-zero port">>).
-define(trailer_filter_endpoint_port_invalid_message(Port), <<"Endpoint filter port must fall into 1..65535 interval when endpoint filter host is not empty: ", (integer_to_binary(Port))/binary>>).
-define(trailer_pagination_request_not_implemented_message(_), <<"ListVirtualServices pagination_request not implemented">>).
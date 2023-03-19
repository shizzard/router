-include_lib("kernel/include/logger.hrl").

-define(l_debug(Map), ?LOG_DEBUG(router_log:log_map(Map), router_log:log_meta(Map))).
-define(l_info(Map), ?LOG_INFO(router_log:log_map(Map), router_log:log_meta(Map))).
-define(l_notice(Map), ?LOG_NOTICE(router_log:log_map(Map), router_log:log_meta(Map))).
-define(l_warning(Map), ?LOG_WARNING(router_log:log_map(Map), router_log:log_meta(Map))).
-define(l_error(Map), ?LOG_ERROR(router_log:log_map(Map), router_log:log_meta(Map))).
-define(l_critical(Map), ?LOG_CRITICAL(router_log:log_map(Map), router_log:log_meta(Map))).
-define(l_alert(Map), ?LOG_ALERT(router_log:log_map(Map), router_log:log_meta(Map))).
-define(l_emergency(Map), ?LOG_EMERGENCY(router_log:log_map(Map), router_log:log_meta(Map))).
-include_lib("kernel/include/logger.hrl").

-define(l_dev(Map), ?LOG_DEBUG(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_debug(Map), ?LOG_DEBUG(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_info(Map), ?LOG_INFO(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_notice(Map), ?LOG_NOTICE(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_warning(Map), ?LOG_WARNING(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_error(Map), ?LOG_ERROR(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_critical(Map), ?LOG_CRITICAL(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_alert(Map), ?LOG_ALERT(echo_log:log_map(Map), echo_log:log_meta(Map))).
-define(l_emergency(Map), ?LOG_EMERGENCY(echo_log:log_map(Map), echo_log:log_meta(Map))).

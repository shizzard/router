-include_lib("kernel/include/logger.hrl").

-define(l_dev(Map), ?LOG_DEBUG(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_debug(Map), ?LOG_DEBUG(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_info(Map), ?LOG_INFO(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_notice(Map), ?LOG_NOTICE(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_warning(Map), ?LOG_WARNING(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_error(Map), ?LOG_ERROR(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_critical(Map), ?LOG_CRITICAL(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_alert(Map), ?LOG_ALERT(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).
-define(l_emergency(Map), ?LOG_EMERGENCY(rtgw_log:log_map(Map), rtgw_log:log_meta(Map))).

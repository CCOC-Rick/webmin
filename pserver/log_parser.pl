# log_parser.pl
# Functions for parsing this module's logs

do 'pserver-lib.pl';

# parse_webmin_log(user, script, action, type, object, &params)
# Converts logged information from this module into human-readable form
sub parse_webmin_log
{
local ($user, $script, $action, $type, $object, $p) = @_;
if ($type eq "user") {
	return &text("log_${action}_user",
		     "<tt>".&html_escape($object)."</tt>");
	}
else {
	return $text{"log_$action"};
	}
}


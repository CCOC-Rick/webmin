# iscsi-target-lib.pl
# Common functions for managing and configuring an iSCSI target

BEGIN { push(@INC, ".."); };
use strict;
use warnings;
use WebminCore;
&init_config();
&foreign_require("raid");
&foreign_require("fdisk");
&foreign_require("lvm");
&foreign_require("mount");
our (%text, %config, %gconfig, $module_config_file);

# check_config()
# Returns undef if the iSCSI server is installed, or an error message if
# missing
sub check_config
{
return &text('check_econfig', "<tt>$config{'config_file'}</tt>")
	if (!-r $config{'config_file'});
return &text('check_eietadm', "<tt>$config{'ietadm'}</tt>")
	if (!&has_command($config{'ietadm'}));
return undef;
}

# get_iscsi_config()
# Returns an array ref of entries from the iSCSI target config file
sub get_iscsi_config
{
my @rv;
my $fh = "CONFIG";
my $lnum = 0;
&open_readfile($fh, $config{'config_file'}) || return [ ];
my $parent = undef;
while(<$fh>) {
        s/\r|\n//g;
        s/#.*$//;
        my @w = split(/\s+/, $_);
	shift(@w) if ($w[0] eq '');	# Due to indentation
	my $dir;
	if (@w) {
		$dir = { 'name' => $w[0],
			 'value' => join(" ", @w[1..$#w]),
			 'values' => [ @w[1..$#w] ],
			 'line' => $lnum,
			 'eline' => $lnum };
		}
	if (/^\S/) {
		# Top-level directive
		$parent = $dir;
		push(@rv, $parent);
		}
	elsif (@w) {
		# Sub-directive
		$parent || &error("Sub-directive with no parent at line $lnum");
		$parent->{'members'} ||= [ ];
		push(@{$parent->{'members'}}, $dir);
		$dir->{'parent'} = $parent;
		$parent->{'eline'} = $dir->{'line'};
		}
	$lnum++;
	}
close($fh);
return \@rv;
}

# get_iscsi_config_parent()
# Returns a fake object for the whole config
sub get_iscsi_config_parent
{
my $conf = &get_iscsi_config();
my $lref = &read_file_lines($config{'config_file'}, 1);
return { 'members' => $conf,
	 'line' => 0,
	 'eline' => scalar(@$lref)-1 };
}

# save_directive(&config, &parent, name|&old-objects, value|&values)
# Updates some config entry
sub save_directive
{
my ($conf, $parent, $name_or_old, $values) = @_;
my $lref = &read_file_lines($config{'config_file'});

# Find old objects
my @o;
if (ref($name_or_old)) {
	@o = @{$name_or_old};
	}
else {
	@o = &find($parent->{'members'}, $name_or_old);
	}

# Construct new objects
$values = [ $values ] if (ref($values) ne 'ARRAY');
my @n = map { ref($_) ? $_ : { 'name' => $name_or_old,
			       'value' => $_ } } @$values;

for(my $i=0; $i<@n || $i<@o; $i++) {
	my $o = $i<@o ? $o[$i] : undef;
	my $n = $i<@n ? $n[$i] : undef;
	if ($o && $n) {
		# Update a directive
		if (defined($o->{'line'})) {
			$lref->[$o->{'line'}] = &make_directive_line(
							$n, $o->{'parent'});
			}
		$o->{'name'} = $n->{'name'};
		$o->{'value'} = $n->{'value'};
		}
	elsif (!$o && $n) {
		# Add a directive at end of parent
		my @lines = &make_directive_line($n, $o->{'parent'});
		splice(@$lref, $parent->{'eline'}+1, 0, @lines);
		push(@{$parent->{'members'}}, $n);
		$n->{'line'} = $parent->{'eline'} + 1;
		$n->{'eline'} = $n->{'line'} + scalar(@lines) - 1;
		$parent->{'eline'} = $n->{'eline'};

		# XXX renumber
		}
	elsif ($o && !$n) {
		# Remove a directive
		if (defined($o->{'line'})) {
			splice(@$lref, $o->{'line'},
			       $o->{'eline'} - $o->{'line'} + 1);
			# XXX renumber
			}
		my $idx = &indexof($o, @{$parent->{'members'}});
		if ($idx >= 0) {
			splice(@{$parent->{'members'}}, $idx, 1);
			}
		}
	}
}

# make_directive_line(&directive, indent?)
sub make_directive_line
{
my ($dir, $indent) = @_;
return ($indent ? "\t" : "").$dir->{'name'}." ".$dir->{'value'};
}

# find(&config, name)
# Returns all config objects with the given name
sub find
{
my ($conf, $name) = @_;
my @t = grep { lc($_->{'name'}) eq lc($name) } @$conf;
return wantarray ? @t : $t[0];
}

# find_value(&config, name)
# Returns config values with the given name
sub find_value
{
my ($conf, $name) = @_;
return map { $_->{'value'} } &find($conf, $name);
}


# is_iscsi_target_running()
# Returns the PID if the server process is running, or 0 if not
sub is_iscsi_target_running
{
return &check_pid_file($config{'pid_file'});
}

# find_host_name(&config)
# Returns the first host name part of the first target
sub find_host_name
{
my ($conf) = @_;
foreach my $t (&find_value($conf, "Target")) {
	my ($host) = split(/:/, $t);
	$hcount{$host}++;
	}
my @hosts = sort { $hcount{$b} <=> $hcount{$a} } (keys %hcount);
return $hosts[0];
}

# generate_host_name()
# Returns the first part of a target name, in the standard format
sub generate_host_name
{
my @tm = localtime(time());
return sprintf("iqn.%.4d-%.2d.%s", $tm[5]+1900, $tm[4]+1,
	       join(".", reverse(split(/\./, &get_system_hostname()))));
}

1;
######################################################################
# SCM Data Monitor
# Colin Robbins
# First release: November 2017
# Added to Github: February 2020
# Standard disclaimer, no warranties etc.  Use at you own risk.
# I do not claim this is good coding style, I am sure it could be a lot better
######################################################################

# CUSTOMISTAION
#
# You will need to...
# 1)  Create a .key file, and put your SCM API key there.  Change access permissions on the file to user only
# 2)  Modify parameters in the header sections below - marked with a MODIFY comment
# 3)  Modify some elements that are specific to our swim club - marked as CLUB SPECIFIC
# 4)  Create a .username, .userpassword and .sento file if you want the output results emailed to you.

########################################################################
# TO DO LIST
#
# Check out codes of conduct are set for all relevant people (Dependency: SCM Feature Request on API)
# Update emails lists (Dependency: SCM Feature Request on API)
# Cross check ASA registrations with CSV file from Swim England
###########################################################################

###########################################################################
# Quick notes on perl syntax as I use the complex hash of arrays capability
# @x is an array, with elements $x[0], $x[1]...
# %y is a hash, like an array, but non-numeric keys $y{'Tom'}, $y{'Dick'}...
# $y{'Tom'} = $x;  stores the array x in the hash y
# @{$y{'Tom'}} is used to access the array inside the hash
###########################################################################

######################
# DO NOT CHANGE
######################
use strict;
use warnings;
use LWP::UserAgent;
use Time::Piece;
use URI;
use JSON qw( decode_json encode_json);
use Data::Dumper;
use Getopt::Std;
use Text::CSV;


###############
# email package
###############

use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTPS;
use Email::Simple          ();
use Email::Simple::Creator ();

# MODIFY #
my $smtpserver = 'smtpout.secureserver.net';
my $smtpport   = 25;

##############
# Behaviour
##############

# MODIFY #
use constant FINANCE	=> 1;    # 1 = use finance feature, 0 otherwise  ---- CLUB SPECIFIC
use constant FACEBOOK	=> 1;    # 1 = use facebook feature, 0 otherwise  ---- CLUB SPECIFIC
use constant SWIMENGLAND => 1;    # 1 = use Swim England feature, 0 otherwise
use constant USERAGENT	=> 'SCM Access Script';    # SCM needs a user agent string in the https.

######################################################
# Exception strings found in SCM user's Notes field
# Used to stop certain things being flagged as errors
#######################################################

use constant EXCEPTION_NODBS        	 => 'API: Coach no DBS OK';
use constant EXCEPTION_NOSAFEGUARD     	 => 'API: Coach no Safeguard OK';
use constant EXCEPTION_NOSESSIONS        => 'API: Coach no sessions';
use constant EXCEPTION_PERMISSIONS       => 'API: Coach permission OK';
use constant EXCEPTION_NOEMAIL           => 'API: no email OK';
use constant EXCEPTION_EMAILDIFF         => 'API: different email OK';
use constant EXCEPTION_NONSWIMMINGMASTER => 'API: non swimming master';
use constant EXCEPTION_GROUPNOSESSION    => 'API: no sessions OK';
use constant EXCEPTION_TWOGROUPS	 => 'API: two groups OK';
use constant EXCEPTION_NOGROUPS	 	 => 'API: no groups OK';

##############################
# Group to session mappings
##############################

# CLUB SPECIFIC #
# Provides a mapping between a group name and a string found in a session name.
# Used to check members in a set of sessions are also in the relevant group an vice versa
# May not work - depends how you use SCM.

my %group_mapping = (
	'Senior Development'    => 'Senior Development',
	Development    => 'Club Session',
	'Junior Squad' => 'Junior',
	Masters        => 'Masters',
	'SNR Youth'    => 'Senior',
	'Water Polo'   => 'Water Polo'
);

# The session name is a substring, not exact match
my %session_mapping = (
	'Club Session'  => 'Development',
	'Junior Squad'  => 'Junior Squad',
	Masters         => 'Masters',
	'Masters #MNRN' => 'Masters',
	'Senior Squad'  => 'SNR Youth',
	'Water Polo'    => 'Water Polo'
);

##############
# Declarations
##############

# email
my $smtpuser     = "";    # Read from file
my $smtppassword = "";    # Read from file
my $smtpsendto   = "";    # Read from file

# Hash:  key guid, value JSON
my %session_guid;
my %member_guid;
my %parents_guid;
my %group_guid;
my %role_guid;

my %inactive_guid;

my %finance;
my %facebook;
my %se;
my %se_ka;
my %se_reverse;
my %se_asa;
my %se_cat;
my %se_asa_nomatch;
my %se_dob;
my %member_byname;
my %inactive_byname;
my %member_knownas;
my %no_register;

# error list
my %exceptions2;
my %exceptions;
my %okexceptions;
my %dbs_exceptions;
my %exceptions_guid;
my %dbs_exceptions_guid;
my $num_exceptions = 0;
my $num_dbs_exceptions = 0;
my %p_error;
my $num_p_error = 0;

# Hash:  key guid, array of guids
my %session_coaches;
my %session_swimmers;
my %coaches_perms;
my %swimmer_parents;
my %parents_swimmers;
my %group_swimmers;
my %role_members;
my %facebook_note;
my %facebook_surname;
my %surname;

# hash for groups / sessions
my %swimmers_by_group;
my %swimmers_by_session;
my %attendance_by_session;
my %session_lastseen;
my %session_lastseen_name;
my %member_lastseen;

# counts
my $n_users        = 0;
my $n_swimmers     = 0;
my $n_groups       = 0;
my $n_lists        = 0;
my $n_sessions     = 0;
my $n_coaches      = 0;
my $n_parents      = 0;
my $n_inactive     = 0;
my $n_notconfirmed = 0;
my $n_confirmed    = 0;
my $n_roles        = 0;
my $n_swimmer_no_parent = 0;

# current time
my $today = localtime;
my $quarter_offset;

# email list
my %wanted_lists;
my %current_lists;

# roles I am interested in
my @roles;
my $role_coaches;
my $role_registertaker;

# hashes for results
my %finance_nomatch;
my %scm_finance_nomatch;
my %facebook_nomatch;
my %se_nomatch;
my %scm_se_nomatch;
my %group_errors;
my %session_errors;
my %two_groups_errors;

my %two_groups;
my %not_confirmed;

# SCM API access key
my $apikey;

# Args
my %options=();

# SCM URLs
use constant URL_user => 'https://api.swimclubmanager.co.uk/Members';
use constant URL_session => 'https://api.swimclubmanager.co.uk/ClubSessions';
use constant URL_group => 'https://api.swimclubmanager.co.uk/ClubGroups';
use constant URL_lists => 'https://api.swimclubmanager.co.uk/EmailLists';
use constant URL_roles => 'https://api.swimclubmanager.co.uk/ClubRoles';

####################
# debug
####################

sub debug {
	my $p = shift;
	print STDERR "$p \n" ;
}

sub debug_json {
	my $p = shift;
	print STDERR Dumper "$p \n" ;
}

####################
# error handling
####################

sub error_in_sessions {
	my $u_guid = shift; # Guid
	my $p = shift;

	my $u = $member_guid{$u_guid};

	if ( $u eq "" ) {
		push @{ $exceptions2{'NONE'} }, $p;
	} else {
		# Check if there is a note
		push @{ $exceptions2{ print_name($u) } }, $p;
	}
}

sub dbs_exception {
	my $u = shift; # hash
	my $p = shift;

	if ( $u eq "" ) {
		push @{ $dbs_exceptions{' '} }, $p;
	} else {
		push @{ $dbs_exceptions{ print_name($u) } }, $p;
		$dbs_exceptions_guid{$u} = 1;
	}
	$num_dbs_exceptions++;
}

sub exception {
	my $u = shift; # hash
	my $p = shift;

	if ( $u eq "" ) {
		push @{ $exceptions{' '} }, $p;
	} else {
		my $n = print_name($u);
		if ((check_defined ($okexceptions{$n}) == 0) or ($okexceptions{$n} < $today)) {
			push @{ $exceptions{ $n } }, $p;
			$exceptions_guid{$u} = 1;
		}
	}
	$num_exceptions++;
}

sub parent_error {
	my $u = shift;
	my $p = shift;
	push @{ $p_error{$p} }, print_name($u);
	$num_p_error++;
}

###################
# Preperations
#######################
# Get the SCM API key from the local file '.key'
# make sure tyhe file permisions restrict access

sub get_key {
	my $filename = '.key';
	open( my $fh, '<:encoding(UTF-8)', $filename )
	  or die "Could not open file '$filename' $!";

	$apikey = <$fh>;
	chomp $apikey;
	close $fh;
}

##################
# read finance csv
##################

# CLUB SPECIFC #
# We don't use the finance features (... its a long story)
# We have a CSV file with the name of all the paying members
# Use to check everyone in SCM is paying

sub get_finance {

	if (defined $options{f} or defined $options{a}) {
		; 
	} else {
		return;
	}

	my $filename = 'leander_finance.csv';
	open( my $fh, '<:encoding(UTF-8)', $filename )
	  or die "Could not open file '$filename' $!";

	for my $l (<$fh>) {
		$l =~ s/\r//g;         # remove ^M
		$l =~ s/[^[:ascii:]]//g;  #remove non ascii
		$l =~ s/\s*,\s*/ /;    # remove space around comma
		$l =~ s/\s*-\s*/-/;    # remove space around hyphen
		$l =~ s/Mck/McK/;    # CLUB SPECIFIC hack
		chomp $l;
		$l =~ s/\s*$//;        # remove trail space
		$finance{$l} = $l;
	}

	close $fh;
}

##################
# read facebook csv
##################

# CLUB SPECIFC #

sub get_facebook {

	if (defined $options{F} or defined $options{a}) {
		; 
	} else {
		return;
	}

	my $filename = 'facebook.txt';
	open( my $fh, '<:encoding(UTF-8)', $filename )
	  or die "Could not open file '$filename' $!";

	for my $n (<$fh>) {
		$n =~ s/\r//g;         # remove ^M
		$n =~ s/[^[:ascii:]]//g;  #remove non ascii
		$n =~ s/\s*,\s*/ /;    # remove space around comma
		$n =~ s/\s*-\s*/-/;    # remove space around hyphen
		$n =~ s/Mck/McK/;    # CLUB SPECIFIC hack
		chomp $n;
		$n =~ s/\s*$//;        # remove trail space

		### my $swap = $n;
		### $swap =~ s/(.*)\s+(.*)/$2 $1/;
	
		my $fn = (split(' ', $n))[0];
		my $ln = (split(' ', $n))[-1];   # last element of splt

		$facebook{$ln . ' ' . $fn} = $n;
		$facebook_surname{$ln} = 1;
	}

		

	close $fh;
}

##################
# read swim england csv
##################

sub process_se {
      	my $r = shift;

        my @record = @$r;

	if ($record[2] eq "Surname") {
		return;  # Header row
	}

	my $name = $record[5] . " " . $record[3];
	my $name_ka = $record[5] . " " . $record[6];

	$se{$name} = $name;
	$se_ka{$name} = $name_ka;
	$se_reverse{$name_ka} = $name_ka;

	$se_dob{$name} = $record[7];
	$se_asa{$name} = $record[0];
	$se_cat{$name} = $record[1];

}

sub get_se {


	if (defined $options{m} or defined $options{a}) {
		; 
	} else {
		return;
	}

	my $filename = 'leander_se.csv';
	open( my $fh, '<:encoding(UTF-8)', $filename ) or die "Could not open file '$filename' $!";

        my $csv = Text::CSV->new ({
             binary    => 1, # Allow special character. Always set this
             auto_diag => 1, # Report irregularities immediately
             });

        while (my $row = $csv->getline ($fh)) {
              process_se ($row);
        }

	close $fh;
}

##################
# email
##################

sub get_email_credentials {
	my $filename = '.password';
	open( my $fh, '<:encoding(UTF-8)', $filename )
	  or die "Could not open file '$filename' $!";

	$smtppassword = <$fh>;
	chomp $smtppassword;
	close $fh;

	$filename = '.username';
	open( $fh, '<:encoding(UTF-8)', $filename )
	  or die "Could not open file '$filename' $!";

	$smtpuser = <$fh>;
	chomp $smtpuser;
	close $fh;

	$filename = '.sendto';
	open( $fh, '<:encoding(UTF-8)', $filename )
	  or die "Could not open file '$filename' $!";

	$smtpsendto = <$fh>;
	chomp $smtpsendto;
	close $fh;
}

sub send_email {
	my $message = shift;
	my $subject = shift;

	my $transport = Email::Sender::Transport::SMTPS->new(
		{
			host          => $smtpserver,
			ssl           => 'starttls',
			port          => $smtpport,
			sasl_username => $smtpuser,
			sasl_password => $smtppassword,
			debug         => 0,
		}
	);

	my $email = Email::Simple->create(
		header => [
			To      => $smtpsendto,
			From    => $smtpuser,
			Subject => $subject,
		],
		body => $message
	);
	sendmail( $email, { transport => $transport } );

	print STDERR ("Email Sent\n");
}

##################################
# Read exceptions.
# Temporary errors not to report
# while they are fixed
# file format:  name, date
##################################


sub get_exceptions {
        my $file =  "EXCEPTIONS";
        open(my $fh, '<', $file) or die "Could not open '$file' $!\n";

        while (my $row = <$fh>) {
              	chomp $row;
		
		my @str = split (/,/,$row);
		
              	$okexceptions{$str[0]} =  Time::Piece->strptime( $str[1], '%d/%m/%Y' );
        }
        close $fh;
}


##################################
# Read the SCM tables from the API
##################################

#
# SESSIONS
#
sub map_session {
	my $s = shift;

	foreach my $x ( keys %session_mapping ) {
		if ( index( $s, $x ) ne -1 ) {
			return $session_mapping{$x};
		}
	}
	return "";
}

sub get_session {
	my $u = shift;

	$n_sessions++;

	return if $u->{'Archived'};
	my $coaches  = $u->{'Coaches'};
	my $swimmers = $u->{'Members'};

	$session_guid{ $u->{'Guid'} } = $u;

	foreach (@$coaches) {
		push @{ $session_coaches{ $_->{'Guid'} } }, $u;
		push( @{ $attendance_by_session { $u->{'Guid'} } }, $_ );
	}

	foreach (@$swimmers) {
		push @{ $session_swimmers{ $_->{'Guid'} } }, $u;
		push( @{ $swimmers_by_session{ $u->{'Guid'} } }, $_->{'Guid'} );
		push( @{ $attendance_by_session { $u->{'Guid'} } }, $_ );
	}
}

sub get_sessions {
	my $ua = LWP::UserAgent->new;
	$ua->default_header(
		'Authorization-Token' => $apikey,
		'User-Agent'          => USERAGENT
	);
	my $res = $ua->get(URL_session);

	if ( $res->is_success ) {
		my $session = decode_json( $res->content );

		foreach (@$session) {
			get_session($_);
		}
	} else {
		die 'Web error ' . $res->status_line;
	}
}

#
# LISTS
#

sub get_lists {
	my $ua = LWP::UserAgent->new;
	$ua->default_header(
		'Authorization-Token' => $apikey,
		'User-Agent'          => USERAGENT
	);
	my $res = $ua->get(URL_lists);

	if ( $res->is_success ) {
		my $email_lists = decode_json( $res->content );
		foreach (@{$email_lists}) {
			$n_lists++;
			$current_lists {$_->{'ListName'}} = $_;
		}
	} else {
		die 'Web error ' . $res->status_line;
	}
}

#
# ROLES
#

sub get_role {
	my $u = shift;

	$n_roles++;
	my $swimmers = $u->{'Members'};

	if ( $u->{'RoleName'} eq 'Coaches' ) {
		$role_coaches = $u;
	} elsif ( $u->{'RoleName'} eq 'Register taker' ) {
		$role_registertaker = $u;
	}

	$role_guid{ $u->{'Guid'} } = $u;

	my $members = $u->{'Members'};

	foreach my $x (@$members) {
		if ( $role_members{ $x->{'Guid'} } ) {
			;    # ignore, already got them
		} else {
			$role_members{ $x->{'Guid'} } = $u->{'RoleName'};
		}
	}
}

sub get_roles {
	my $ua = LWP::UserAgent->new;
	$ua->default_header(
		'Authorization-Token' => $apikey,
		'User-Agent'          => USERAGENT
	);
	my $res = $ua->get(URL_roles);

	if ( $res->is_success ) {
		my $content = decode_json( $res->content );
		@roles = @$content;
		foreach (@roles) {
			get_role($_);
		}
	} else {
		die 'Web error ' . $res->status_line;
	}
}

#
# USERS
#

sub extract_notes {
	my $note = shift;
	if ($note =~ s/Facebook: *([a-zA-Z\-]+) ([a-zA-Z\-]+)//) {
                my $fb = $1;
                my $fb2 = $2;
                $facebook_note{$fb2 . " " . $fb} = 1;
		## recursion
		extract_notes ($note);
        }
}

sub get_facebook_note {
	my $u = shift;
	
	my $note = $u->{'Notes'};
	if ($note) {
		extract_notes ($note);
	}

}

sub get_user {
	my $u = shift;

	if ( $u->{'Active'} == 0 ) {
		$n_inactive++;
		$inactive_guid{ $u->{'Guid'} } = $u;
		my $name = $u->{'Lastname'} . ' ' . $u->{'Firstname'};
		$inactive_byname{$name} = $u;
		return;
	}

	if ($u->{'Notes'} ne "" ) {
		get_facebook_note ($u);
	}

	$n_users++;
	$member_guid{ $u->{'Guid'} } = $u;

	my $parents = $u->{'Parents'};
	foreach my $p (@$parents) {
		push @{ $swimmer_parents{ $p->{'Guid'} } }, $u;
		$parents_guid{ $p->{'Guid'} } = $u;
		if ( $p->{'Guid'} eq $u->{'Guid'} ) {  # We've had some of these
			exception( $u, 'Swimmer is own parent!' );
		}
	}

	my $swimmers = $u->{'Swimmers'};
	foreach (@$swimmers) {
		push @{ $parents_swimmers{ $_->{'Guid'} } }, $u;
	}
	my $name = $u->{'Lastname'} . ' ' . $u->{'Firstname'};
	$surname{$u->{'Lastname'}} = 1;
	if ( $member_byname{$name} ) {
		exception( $u, 'Duplicate member' );
	}
	$member_byname{$name} = $u;

	if ( $u->{'KnownAs'} ne "" ) {
		my $kname = $u->{'Lastname'} . ' ' . $u->{'KnownAs'};
		if ( $kname ne $name ) {
			if ( $member_byname{$kname} or $member_knownas{$kname} )
			{
				exception( $u, "Duplicate knownas member ($kname)" );
			}
			$member_knownas{$kname} = $u;
		}
	}

}

sub get_users_page {
	my $page = shift;

	my $ua = LWP::UserAgent->new;
	$ua->default_header(
		'Authorization-Token' => $apikey,
		'User-Agent'          => USERAGENT,
		'Page'                => $page
	);
	my $res = $ua->get(URL_user);


	if ( $res->is_success ) {
		my $swimmer = decode_json( $res->content );
		my $i       = 0;

		foreach (@$swimmer) {
			get_user($_);
			$i++;
		}
		return $i;
	} else {
		die 'Web error ' . $res->status_line;
	}
}

sub get_users {
	my $loop = 100;
	my $i    = 1;

	while ($loop == 100) {
		print STDERR " $i ";
		$loop = get_users_page($i);
		$i++;
	}
}

#
# Coaches
#

sub get_session_perms {
	my $u     = shift;
	my $perms = shift;

	foreach (@$perms) {
		push @{ $coaches_perms{ $u->{'Guid'} } }, $_->{'Guid'};
	}
}

sub get_coach {
	my $c = shift;

	my $coach = $member_guid{$c};
	get_session_perms( $coach, $coach->{'SessionRestrictions'} );

}

sub get_coaches {
	foreach my $x ( keys %member_guid )
	{    #do it for all membbers, noy just coacche
		get_coach($x);
	}
}

#
# GROUPS
#

sub get_group {
	my $u = shift;

	$n_groups++;

	$group_guid{ $u->{'Guid'} } = $u;

	my $swimmer = $u->{'Members'};
	foreach (@$swimmer) {
		push @{ $group_swimmers{ $_->{'Guid'} } },    $u;
		push @{ $swimmers_by_group{ $u->{'Guid'} } }, $_->{'Guid'};
	}
}

sub get_groups {
	my $ua = LWP::UserAgent->new;
	$ua->default_header(
		'Authorization-Token' => $apikey,
		'User-Agent'          => USERAGENT
	);
	my $res = $ua->get(URL_group);

	if ( $res->is_success ) {
		my $group = decode_json( $res->content );

		foreach (@$group) {
			get_group($_);
		}
	} else {
		die 'Web error ' . $res->status_line;
	}
}

##################################
# Update Lists
##################################

sub check_in_list {
	my $l = shift;
	my $u = shift;

	my $ml = $l . " (Generated)";
	
	foreach my $wanted (keys %wanted_lists) {
		if ($wanted eq $ml) {
			my $w = ${wanted_lists{$wanted}};
			foreach my $member (@$w) {
				if ($member eq $u) {
					return 1;
				}
			}
		}
	}
	return 0;
}

sub add_to_list {
	my $l = shift;
	my $u = shift;

	if (defined ($wanted_lists {$l}) == 0) {
		if (check_in_list ($l, $u->{'Guid'})){
			return ; # alerady on list
		}
	}

	if (check_defined ($u->{'Email'})) {
		$l .= " (Generated)";
		push @{$wanted_lists {$l} }, $u->{'Guid'};
	}
}

sub update_list {
	my $l = shift; # list
	my $mode = shift;	# 1 = push, 2 = put

	my $ua = LWP::UserAgent->new;

	my $req;

	if ($mode == 1) {
		$req = HTTP::Request->new( POST => URL_lists );	# Create
	} else {
		$req = HTTP::Request->new( PUT => URL_lists );	# Modify
	}

	$req->header( 'content-type'        => 'application/json' );
	$req->header( 'Authorization-Token' => $apikey );
	$req->header( 'User-Agent'          => USERAGENT );

	$req->content( encode_json $l);

	my $resp = $ua->request($req);
	if ( $resp->is_success ) {
		debug("Create/Modify $l->{'ListName'} OK");
	} else {
		die 'ERROR: ' . $resp->message;
	}
}

sub find_add_to_list {
	my $w = shift;
	my $member = shift;

	my $matched = 0;

	foreach my $list (keys %current_lists) {
		if ($list eq $w) {
			$matched = 1;
			my $list = $current_lists{$list};
        		push @{$list->{'Members'}},{Guid => $member};
		}
	}

	if ($matched == 0) {
		debug "List not found - creating $w...";
		$current_lists{$w} = { ListName => $w };
        	push @{$current_lists{$w}->{'Members'}},{Guid => $member};
	}
}

sub clear_lists {
	foreach my $list (keys %current_lists) {
		if (index ($list, 'Generated') != -1) {
			undef $current_lists{$list}->{'Members'};
		}
	}
}

sub update_lists {
	
	clear_lists ();

	foreach my $wanted (keys %wanted_lists) {
		my $w = ${wanted_lists{$wanted}};
		foreach my $member (@$w) {
			find_add_to_list ($wanted, $member);
		}
	}

	foreach my $list (keys %current_lists) {
		my $l = $current_lists {$list};
		
		if (index ($list, 'Generated') == -1) {
			next; #ignore
		}
		if ( check_defined ($l->{'Guid'}) ) {
			update_list ($l, 2);  # modify
		} else {
			update_list ($l, 1);  # create
		}
	}
}

#
# Create lists
#

# CLUB SPECIFIC

sub get_year {
	my $u = shift;

	my $td_d = Time::Piece->strptime( $u, '%Y-%m-%d' );

	return $td_d->year;
}

sub create_lists {
	
	foreach my $member (keys %member_guid) {
		my $m = $member_guid{$member};

		my $dob = $m ->{'DOB'};
		
		if (check_in_group ($m, "Water Polo")) {
			my $yob = get_year($dob);
			if ($yob == 2003 or $yob == 2004)  {
				if ($m->{'Gender'} eq 'M') {
					add_to_list ('Water Polo: Boys: 2003, 2004',$m);
				} else {
					add_to_list ('Water Polo: Girls: 2003, 2004',$m);
				}
			}
			if ($yob == 2005 or $yob == 2006 or $yob == 2007)  {
				if ($m->{'Gender'} eq 'M') {
					add_to_list ('Water Polo: Boys: 2005-2007',$m);
				} else {
					add_to_list ('Water Polo: Girls: 2005-2007',$m);
				}
			}
			if (calc_date($m,'DOB') > 16*365) {
				if ($m->{'Gender'} eq 'M') {
					add_to_list ('Water Polo: Men: 16 and over',$m);
				} else {
					add_to_list ('Water Polo: Women: 16 and over',$m);
				}
			}
		}
		if ($m->{'IsASwimmer'} == 1) {
			next if ( check_in_group( $m, 'Trialist' ) );
			next if ( check_in_group( $m, 'Tadpole' ) );
			next if ( check_in_group( $m, 'Resignation' ) );
			if (calc_age_eoy($m,'DOB') < 18 ) {
				add_to_list ("Swimmers: 17 and under on Dec 31", $m);
			} else {
				add_to_list ("Swimmers: 18 and over on Dec 31", $m);
			}
			if (calc_age_eoy($m,'DOB') <= 12 ) {
				add_to_list ("Swimmers: 12 and under on Dec 31", $m);
			}
			if ((calc_age_eoy($m,'DOB') >= 13 ) and (calc_age_eoy($m,'DOB') <= 20 )) {
				add_to_list ("Swimmers: between 13 and 20 on Dec 31", $m);
			}
		}
	}
}

##################################
# Print routines - return a string
##################################

sub print_session {
	my $y       = shift;
	my $session = $y->{'SessionName'};
	my $wd      = $y->{'WeekDay'};
	my $loc     = $y->{'SessionLocation'};
	my $t       = $y->{'StartTime'};
	return sprintf( '%s, %s, %s, %s', $session, $wd, $loc, $t );
}

sub print_session_guid {
	my $m = shift;
	my $y = $session_guid{$m};
	if ($y) {
		return print_session($y);
	}
	return '???';
}

sub print_group_guid {
	my $m = shift;
	my $opt;
	foreach my $group ( @{ $group_swimmers{$m} } ) {
		if ($opt) {
			$opt .= ', ' . $group->{'GroupName'};
		} else {
			$opt = $group->{'GroupName'};
		}
	}
	return $opt;
}

sub print_firstgroup_user {
	my $s = shift;
	my $opt;
	my $m = $s->{'Guid'};

	return "Water Polo" if (check_in_group ($s, "Water Polo"));
	return "Masters" if (check_in_group ($s, "Masters"));

	my $g = @{ $group_swimmers{$m} }[0];
	if (defined $g->{'GroupName'}) {
		return $g->{'GroupName'};
	} else {
		return "(No Group)";
	}
}

sub print_name {
	my $y = shift;

	my $f = $y->{'Firstname'};
	my $l = $y->{'Lastname'};

	if ( ( defined($f) == 0 ) or ( defined($l) == 0 ) ) {
		return '???';
	}
	if ( $f eq "" ) {
		$f = '?';
	}
	if ( $l eq "" ) {
		$l = 'ANON';
	}
	return sprintf( '%s %s', $f, $l );
}

sub print_name_guid {
	my $m = shift;
	my $y = $member_guid{$m};
	return print_name($y);
}

sub print_group {
	my $y = shift;
	my $f = $y->{'GroupName'};
	if ($f) {
		return $f;
	}
	return '???';
}

sub print_groups {
	my $y = shift;
	my $i = 0;
	my $res;

	foreach (@$y) {
		if ($i) {
			$res = sprintf( '%s, %s', $res, print_group($_) );
		} else {
			$res = print_group($_);
		}
		$i++;
	}
	return $res;
}

sub print_date {
	my $d = shift;

	if ($d ne 'Thu Jan  1 00:00:00 1970') {
		return $d->dmy("/");
	}
	return ('never');
}
sub print_date2 {
	my $d = shift;
	my $pd = Time::Piece->strptime( $d, '%Y-%m-%d' );
	return print_date($pd);
}

##################################
# Checking utilities
##################################

# Return true if they swimmer has recently joined
# They may not have been set up for long, so don't nag yet

sub check_defined {
	my $d = shift;

	return 0 if defined($d) == 0;
	return 1 if ( length $d > 0 );
	return 0;
}

sub set_quarter {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$mon = int ($mon / 3) * 3;
	$mon += 1;  
	if ($mon > 12) {
		$mon -= 12;
		$year ++;
	}
	$year += 1900;
	my $quarter = Time::Piece->strptime( "$year-$mon-01", '%Y-%m-%d' );
	$quarter_offset = int (($today - $quarter) / (60*60*24));

}

sub check_confirmed_date {
	my $a = shift;
	my $b = shift;

	my $atm = Time::Piece->strptime( $a->{'DetailsConfirmedCorrect'},'%Y-%m-%d' );
	my $btm = Time::Piece->strptime( $b->{'DetailsConfirmedCorrect'}, '%Y-%m-%d' );

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($atm);
	my $amon = int ($mon / 3) * 3;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($btm);
	$mon = int ($mon / 3) * 3;
	if ($mon == $amon) {
		return 0;
	} else {
		return 1;
	}
}
		

sub calc_date {
	my $s     = shift;
	my $field = shift;

	my $jd = $s->{$field};

	my $td_d = Time::Piece->strptime( $jd, '%Y-%m-%d' );
	my $days = ( $today - $td_d ) / ( 60 * 60 * 24 );

	return $days;
}

sub cmp_date_asa {
	my $a = shift;
	my $b = shift;

	my $td_a = Time::Piece->strptime( $a, '%Y-%m-%d' );
	my $td_b = Time::Piece->strptime( $b, '%d/%m/%Y' );

	return $td_a == $td_b;
}

sub calc_age_eoy {
	my $s     = shift;
	my $field = shift;

	my $year = $today->year;

	my $jd = $s->{$field};
	my $td_d = Time::Piece->strptime( $jd, '%Y-%m-%d' );
	my $dob_year = $td_d->year;

	return $year - $dob_year;
}

sub ignore_no_parent {
	my $m = shift;
	
	return 1 if ( check_defined( $m->{'DateJoinedClub'} ) == 0 ) ;

	my $jd = $m->{'DateJoinedClub'};
	my $td_d = Time::Piece->strptime( $jd, '%Y-%m-%d' );
	# CHANGE DATE!
	my $ref = Time::Piece->strptime( '2018-01-14', '%Y-%m-%d' );

	return 0 if ($td_d > $ref);
	return 1;

}

sub get_a_child {
	my $p = shift;

	my $swimmers = $p->{'Swimmers'};

	foreach my $c (@$swimmers) {
		my $x = $member_guid{$c->{'Guid'}};
		if (defined $x) {
			return $x;
		}
	}
	return 0;
}

sub recently_joined {
	my $s = shift;

	if ( check_defined($s->{'DateJoinedClub'}) == 1 ) {
		my $days = calc_date( $s, 'DateJoinedClub' );
		if ( $days > 90 + $quarter_offset ) {
			return 0;
		} else {
			return 1;
		}
	}
	
	if ( ($s->{'IsAParent'} ) and $s->{'Swimmers'} ) {
		my $c = get_a_child ($s);
		if ($c != 0) {
			if (check_defined ($c->{'DateJoinedClub'}) ) {
				my $days = calc_date( $c, 'DateJoinedClub' );
				if ( $days > 90 ) {
					return 0;
				} else {
					return 1;
				}
			} else {
				return 1;    # Swimmer with no join date - will create error anyway, so don't compund here
			}
		} else {
			debug "Parent: can't find child: " . print_name($s);
;
		}
	}
	
	return -1;  # can't tell, so give errors
}

sub check_in_group {
	my $u     = shift;    # user
	my $group = shift;    #group

	foreach my $g ( @{ $group_swimmers{ $u->{'Guid'} } } ) {
		if ( index( $g->{'GroupName'}, $group ) != -1 ) {
			return 1;
		}
	}
	return 0;
}

sub check_exceptions {
	my $u    = shift;
	my $code = shift;

	if ( index( $u->{'Notes'}, $code ) != -1 ) {
		return 1;
	} else {
		return 0;
	}
}

sub count_parents {
	foreach ( keys %parents_guid ) {
		$n_parents++;
	}
}

###############################
# Analytics
###############################

#
# COACHES
#

sub check_dbs {
	my $guid = shift;
	my $role = "Coach";

	my $s = $member_guid{$guid};

	if ( check_exceptions( $s, EXCEPTION_NODBS ) ) {
		return;
	}

	if ( $s->{'IsACoach'} == 0 ) {
		# not a coach
		if (check_in_group ($s, "Team Manager")) {
			$role = "Team Manager";
		} else {
			return;
		}
	}

	if ( my $jd = $s->{'DBSRenewalDate'} ) {
		my $days = calc_date( $s, 'DBSRenewalDate' );
		if ( $days > 0 ) {
			dbs_exception( $s, "$role with expired DBS: " . print_date2($jd));
		} elsif ( $days > -62 ) {
			dbs_exception( $s, "$role with DBS about to expire: " . print_date2($jd));
		}
	} else {
		dbs_exception( $s, "$role with no DBS" );
	}

	if ( check_exceptions( $s, EXCEPTION_NOSAFEGUARD ) ) {
		return;
	}

	if ( my $jd = $s->{'SafeguardingRenewalDate'} ) {
		my $days = calc_date( $s, 'SafeguardingRenewalDate' );
		if ( $days > 0 ) {
			dbs_exception( $s, "$role with expired Safeguading: " . print_date2($jd));
		}
	} else {

		# CLUB SPECIFIC
		dbs_exception ($s, "$role with no Safeguarding");
		;
	}

}

sub check_iscoach {
	my $guid = shift;

	my $s = $member_guid{$guid};

	if ( $s->{'IsACoach'} == 0 ) {

		# not a coach
		return;
	}
	if ( check_defined( $s->{'Email'} ) == 0 ) {
		if ( check_exceptions( $s, EXCEPTION_NOEMAIL ) ) {
			;
		} else {
			exception( $s, "Coach with no email" );
		}
	}
	$n_coaches++;
	if ( $session_coaches{ $s->{'Guid'} } ) {

		# are a session coach
		return;
	}
	if ( check_exceptions( $s, EXCEPTION_NOSESSIONS ) ) {
		return;
	}
	exception( $s, "Coach with no sessions" );
	return;
}

sub check_coaches {

	my $result;

	foreach my $x ( keys %member_guid ) {
		check_iscoach($x);
		check_dbs($x);
	}

}

#
# Groups / Sessions
#

sub check_session_coach {
	my $s = shift;    #session
	my $u = shift;    #user

	my $ses = $session_guid{$s};

	my $coaches = $ses->{'Coaches'};

	foreach (@$coaches) {
		if ( $_->{'Guid'} eq $u->{'Guid'} ) {
			return 1;
		}
	}
	return 0;
}

# CLUB SPECIFIC
# Check swimmer in membership only group is not in any sessions
sub check_member_only {

	my $match   = 0;
	my $matched = "";
	foreach my $u_guid ( keys %member_guid ) {
		my $u = $member_guid{$u_guid};
		if ( check_in_group( $u, "Membership Only" ) ) {
			foreach my $x ( keys %swimmers_by_session ) {
				foreach my $y ( @{ $swimmers_by_session{$x} } )
				{
					next if ( $u_guid ne $y );
					$match++;
					$matched = $u;
				}
			}
			if ( $match > 0 ) {
				exception( $matched, "In Membership Only group but in a swim session");
			}
			$match = 0;
		}
	}

	foreach my $u_guid ( keys %member_guid ) {
		my $u = $member_guid{$u_guid};
		if ( check_in_group( $u, "One Session Only" ) ) {
			foreach my $x ( keys %swimmers_by_session ) {
				foreach my $y ( @{ $swimmers_by_session{$x} } )
				{
					next if ( $u_guid ne $y );
					$match++;
					$matched = $u;
				}
			}
			if ( $match > 1 ) {
				exception( $matched, 'In "one session only" group but in two sessions');
			}
			$match = 0;
		}
	}
}

sub check_in_group2 {
	my $check = shift;    # session full name
	my $s     = shift;    # GUID of a swimmer
	my $c     = shift;    # session looking for

	$c = $session_mapping{$c};

	my $u = $member_guid{$s};

	if ( $exceptions_guid{$u} ) {
		# Ignore - already have errors
		return;
	}

	if ( check_exceptions( $u, EXCEPTION_GROUPNOSESSION ) ) {
		return;
	}

	my $match = 0;

	foreach my $x ( keys %swimmers_by_group ) {
		my $sn = $group_guid{$x}->{'GroupName'};
		next if ( $sn ne $c );
		foreach my $y ( @{ $swimmers_by_group{$x} } ) {
			if ( $y eq $s ) {
				$match++;
				last;
			}
		}
	}
	
	if ($match == 0) {
		push( @{ $session_errors{ $check  } }, print_name_guid($s) . " is not in the group $c, but in relevant sessions");
		error_in_sessions ($s, "Not in group $c, but in session: $check");
	}
	return $match;
}

sub check_in_session {
	my $check = shift;    # group
	my $s     = shift;    # GUID of a swimmer

	my $u = $member_guid{$s};
	return if ( recently_joined($u) != 0 );   # give then some time to get set up

	if ( $exceptions_guid{$u} ) {
		# Ignore - already have errors
		return;
	}

	my $c = $group_mapping{$check};

	my $match = 0;

	foreach my $x ( keys %swimmers_by_session ) {
		my $sn = $session_guid{$x}->{'SessionName'};
		next if ( index( $sn, $c ) eq -1 );
		foreach my $y ( @{ $swimmers_by_session{$x} } ) {
			if ( $y eq $s ) {
				$match++;
				last;
			}
		}
		if ( check_session_coach( $x, $u ) ) {
			$match++;
		}
	}

	if ($match) {
		return;
	}

	if ( $check eq 'Masters' ) {

		# CLUB SPECIFIC #
		if ( check_in_group( $u, 'Membership Only' ) ) {
			return;    # masters that do no swim
		}
		if ( check_in_group( $u, 'Life Member' ) ) {
			return;    # masters that do no swim
		}
		if ( check_exceptions( $u, EXCEPTION_NONSWIMMINGMASTER ) ) {
			return;
		}
	}
	if ( check_in_group( $u, 'Life Member' ) ) {
		return;            # masters / polo that do no swim
	}
	if ( check_in_group( $u, 'Nova' ) ) {
		if (check_in_group ($u, 'Nova Development' ) ) {
			;
		} else {
			return;            # Nova a special case...
		}
	}
	if ( check_in_group( $u, 'Student' ) ) {
		return;            # Students may be away...
	}
	if ( check_exceptions( $u, EXCEPTION_GROUPNOSESSION ) ) {
		return;
	}

	push( @{ $group_errors{ $check . " (" . $c . ")" } }, print_name_guid($s));
	error_in_sessions ($s, "in Group $check but not any sessions for that group ($c): ") ;
}

sub two_groups {
	my $u = shift;
	my $gn = shift;

	if ($two_groups{$u}) {
		$two_groups{$u}++ if ($gn eq 'Development');
		$two_groups{$u}++ if ($gn eq 'Junior Squad');
		$two_groups{$u}++ if ($gn eq 'SNR Youth');
	} else {
		$two_groups{$u} = 1 if ($gn eq 'Development');
		$two_groups{$u} = 1 if ($gn eq 'Junior Squad');
		$two_groups{$u} = 1 if ($gn eq 'SNR Youth');
	}
}

sub check_group {
	my $check = shift;    # Group name

	foreach my $x ( keys %group_guid ) {
		my $g = $group_guid{$x};
		if ( $g->{'GroupName'} eq $check ) {
			foreach my $y ( @{ $swimmers_by_group{ $g->{'Guid'} } } ) {
				check_in_session( $check, $y );
				
				two_groups ($y, $check);
			}
		}
	}

}

sub check_session {
	my $check = shift;    # Group name

	foreach my $x ( keys %session_guid ) {
		my $g  = $session_guid{$x};
		my $sn = $g->{'SessionName'};
		if ( $sn eq $check ) {
			foreach my $y ( @{ $swimmers_by_session{ $g->{'Guid'} } } ) {
				check_in_group2( print_session($g), $y, $check );
			}
		}
	}

}

sub check_nova {
	my $user = shift;

	my $u = $member_guid{$user};

	if ( check_in_group ($u, "Nova Development") ) {
		foreach my $g ( @{ $group_swimmers{ $u->{'Guid'} } } ) {
			if ( $g->{'GroupName'} eq "Nova" ) {
				my $grp = print_group_guid ($u);
				push( @{ $two_groups_errors { "Member in Nova and Nova Development" } },  print_name($u));
				error_in_sessions ($user," is in Nova and Nova Development");
			}
		}
	} 
}

sub check_groups {
	for my $x ( keys %group_mapping ) {
		check_group($x);
	}
	for my $x ( keys %session_mapping ) {
		check_session($x);
	}

	foreach my $u ( keys %member_guid) {
		if ( (defined $two_groups{$u}) and ($two_groups{$u} > 1 ) ) {

			my $user = $member_guid{$u};

			if ( check_exceptions( $user, EXCEPTION_TWOGROUPS ) ) {
				next	;
			}

			my $grp = print_group_guid ($u);
			push( @{ $two_groups_errors { "Member in two swimming groups ($grp)" } }, print_name_guid($u));
			error_in_sessions ($u," is in two swimming groups ($grp)");
		}

		check_nova($u) ;
	}

}

#
# ATTENDANCE
#

sub check_user_in_session {
	my $u = shift;
	my $session = shift;

	foreach my $m (@{$swimmers_by_session{$session}}) {
		if ( $m eq $u ) {
			return 1;
		}
	}
	return 0;
}

sub most_recent_session {
	my $u = shift; # Session guid
	my $lastseen = shift;

	my $lastattended = $session_lastseen{$u};

	my $d1 = Time::Piece->strptime( $lastseen, '%Y-%m-%d' );
	if (check_defined($lastattended) ) {
		return $lastattended if ( $d1 < $lastattended ) ;
	}
	return $d1 ;
}
		

sub most_recent {
	my $u = shift;
	my $lastseen = shift;

	my $lastattended = $member_lastseen{print_name($u)};

	my $d1 = Time::Piece->strptime( $lastseen, '%Y-%m-%d' );
	if (check_defined($lastattended) ) {
		return $lastattended if ( $d1 < $lastattended ) ;
	}
	return $d1 ;
}
		
sub check_attendance {

	my %two_sessions;
	my %two_message;

	foreach my $session (keys %attendance_by_session) {
		my $s = $session_guid{ $session };

		# CLUB SPECIFC
		next if ($s->{SessionName} eq 'Tadpoles');

		foreach my $attendee (@{$attendance_by_session {$session}} ) {
			my $user = $attendee->{'Guid'};
			my $u = $member_guid{$user};
			my $lastseen = $attendee->{'LastAttended'};
			
			$member_lastseen{print_name($u)} = most_recent ($u,$lastseen);
			$session_lastseen{$session} = most_recent_session ($session,$lastseen);
			$session_lastseen_name{print_session_guid($session)} = $session_lastseen{$session};


			if ( ($u->{'IsASwimmer'} ) and (recently_joined ($u) != 0) ) {
				next; # give time to get sessions right:1
			}

			if (check_user_in_session($user,$session) == 0) {
				next;  # not supposed to be in the session
			}
			if (check_defined($lastseen) == 0) {
				next if ( $exceptions_guid{$u} ) ;  # Ignore - already have errors
				push( @{ $session_errors{ print_session_guid($session)  } }, print_name($u) . " has never attended");
				error_in_sessions ($u->{'Guid'},"never attended session: " . print_session_guid($session));
				next; # not attended
			}
			if (calc_date ($attendee,'LastAttended') > 120 ) {
				next if ( $exceptions_guid{$u} ) ;  # Ignore - already have errors
				push( @{ $session_errors{ print_session_guid($session)  } }, print_name($u) . " has not attended for more than 120 days (last seen $lastseen)");
				error_in_sessions ($u->{'Guid'},"not attended session for > 120 days ($lastseen): " . print_session_guid($session));
			} else {
				if ( check_in_group( $u, "One Session Only" ) ) {
					if ($two_sessions {$user}) {
						$two_sessions {$user} ++;
						$two_message {$user} .= sprintf ( "(%s: %s) " , print_session_guid($session), $lastseen);
					} else {
						$two_sessions {$user} = 1;
						$two_message {$user} = sprintf ( "(%s: %s) " , print_session_guid($session), $lastseen);
					}
				}
			}
		}
	}

	foreach my $u (keys %two_sessions) {
		my $p = $member_guid{$u};

		if ( $two_sessions {$u} > 1 ) {
			exception ($p, "In One Session only, but has attended two sessions in last 120 days " . $two_message{$u});
		}

		if ( calc_date($p,'DOB') > 18*365 ) {
			exception ($p, "In One Session only, but is in no longer a junior (over 18)");
		}
	}

	# session last seen register
	foreach my $s ( keys %session_lastseen) {
		my $when = $session_lastseen{$s} ;
		my $days = ( $today - $when ) / ( 60 * 60 * 24 );
		if ($days > 60) {
			exception ("","Register for " . print_session_guid($s) .
				" not taken in over 60 days, last taken on " .
				print_date ($when));
			$no_register{print_session_guid($s)} = print_date($when);
		}
	}
}

#
# ROLES
#

sub check_role {
	my $rm_guid = shift;
	my $role    = shift;

	my $rm = $member_guid{$rm_guid};

	if ( check_defined($rm) == 0 ) {
		$rm = $inactive_guid{$rm_guid};
		if ( check_defined($rm) == 0 ) {
			debug "Role occupant does not exisit ($role)";
		} else {
			exception( $rm, "Role occupant is inactive ($role)" );
			return;
		}
	}
	my $e = $rm->{'Username'};
	if ( ( defined $e == 0 ) or $e eq "" ) {
		exception( $rm, "Role occupant with no username (so cannot log in)($role)");
	} else {
		$e = $rm->{'LastLoggedIn'};
		if ( ( defined $e == 0 ) or $e eq "" ) {
			exception( $rm, "Role occupant with login but has never logged in ($role)");
		} elsif ( calc_date( $rm, 'LastLoggedIn' ) > 180 ) {
			exception( $rm, "Role occupant with login but has not logged in for 180 days ($role)");
		}
	}
}

sub check_role_perms {

	my $r    = shift;
	my $mode = shift;

	$r = $r->{'Guid'};

	# Check role permissions for a member
	my $match = 0;

	my $u = $member_guid{$r};

	if ( check_defined($u) == 0 ) {
		$u = $inactive_guid{$r};
		if ( check_defined($u) == 0 ) {
			debug "Role occupant does not exisit";
		} else {
			exception( $u, "Role occupant is inactive" );
		}
	}

	if ( $u->{'IsASwimmer'} == 1 or $mode == 2) {
		;    # ingore this test if they are also a swimmer
			# or mode is 2 - don't know what sessions register taker should be in
	} else {
		foreach my $z ( @{ $session_swimmers{$r} } ) {
			exception( $u, "Coach with extra session: " . print_session_guid( $z->{'Guid'} ) );
		}
	}

	if ( $u->{'IsACoach'} == 0 and $mode == 1) {
		exception( $u, "In Coach role, but not a coach");
	}

	if ( check_exceptions( $u, EXCEPTION_PERMISSIONS ) ) {
		return;    # expection mentioned in notes
	}

	if ( check_defined( $u->{'Username'} ) == 0 ) {
		exception( $u, "Role occupant, but no logon" );
		return;    # dont worry about permission - no logon
	}

	if ( $mode == 1 ) {    # Coach

		foreach my $y ( @{ $session_coaches{$r} } ) {
			$match = 0;
			foreach my $z ( @{ $coaches_perms{$r} } ) {
				$match++ if ( $z eq $y->{'Guid'} );
			}
			if ( $match == 0 ) {
				exception( $u, "Coach with missing permission: " . print_session($y) );
			}
		}
		foreach my $z ( @{ $coaches_perms{$r} } ) {
			$match = 0;
			foreach my $y ( @{ $session_coaches{$r} } ) {
				$match++ if ( $z eq $y->{'Guid'} );
			}
			if ( $match == 0 ) {
				exception( $u, "Coach with extra permission: " . print_session_guid($z) );
			}
		}

	} else {

		# Register taker, don't know what sessions they should have
		if ( check_defined( $u->{'SessionRestrictions'} ) == 0 ) {
			exception( $u, "Register taker without restricted permissions");
		}
	}

}

sub check_roles {

	foreach my $r ( keys %role_members ) {
		check_role( $r, $role_members{$r} );
	}

	if ($role_coaches) {
		foreach my $r ( @{ $role_coaches->{'Members'} } ) {
			check_role_perms( $r, 1 );
		}
	} else {
		debug "Did not find coaches role";
	}

	if ($role_registertaker) {
		foreach my $r ( @{ $role_registertaker->{'Members'} } ) {
			check_role_perms( $r, 2 );
		}
	} else {
		debug "Did not find register taker role";
	}
}

#
# SWIMMERS
#

sub check_swimmer_email {
	my $s = shift;

	my $guid = $s->{'Guid'};

	if ( check_defined( $s->{'Email'} ) == 0 ) {

		if ( check_exceptions( $s, EXCEPTION_NOEMAIL ) ) {
			return;
		}
		return if ( check_in_group( $s, 'Trialist' ) );
		return if ( check_in_group( $s, 'Tadpole' ) );
		return if ( check_in_group( $s, 'Resignation' ) );

		exception( $s, "Swimmer with no email" );
	}
	if ( index( $s->{'Email'}, ' ' ) > 0 ) {
		exception( $s, 'Space in email address' );
	}
	if ( check_defined( $s->{'DOB'} ) == 0 ) {
		exception( $s, "Swimmer with no Date of Birth" );
	} else {
		if ( check_in_group ($s,'Masters') ) {
			if ( ( check_defined( $s->{'DOB'} ) and 
						( calc_date( $s, 'DOB' ) < 368*17 ))) {
				exception ( $s, "Master but under 17!" );
			}
		}
		if ( check_in_group ($s,'Tadpoles') ) {
			if ( ( check_defined( $s->{'DOB'} ) and 
						( calc_date( $s, 'DOB' ) > 365*10 ))) {
				exception ( $s, "Tadpole but over 10! " );
			}
		}
	}
	if ( check_defined( $s->{'Gender'} ) == 0 ) {
		exception( $s, "Swimmer with no Gender defined" );
	}
	if ( check_defined( $s->{'DateJoinedClub'} ) == 0 ) {
		exception( $s, 'Swimmer no join date' );
	}

	return if ( recently_joined($s) == 1 );
	return if ( check_in_group( $s, 'Trialist' ) );
	return if ( check_in_group( $s, 'Tadpole' ) );
	return if ( check_in_group( $s, 'Resignation' ) );

	if ( check_defined( $s->{'ASANumber'} ) == 0 ) {
		exception( $s, 'Swimmer no Swim England No.' );
	}

}

sub check_swimmers {
	foreach my $x ( keys %member_guid ) {
		my $m = $member_guid{$x};
		if ( $m->{'IsASwimmer'} == 0 ) {

			# not a swimmer
			# just a quick check they do have a role...
			if ( ($m->{'IsACoach'}) or
				( $m->{'IsAParent'} ) or
				( $m->{'CommitteeMember'} ) or
				( $m->{'IsAVolunteer'} ) or
				( check_in_group( $m, 'Life Member' ) ) ) {
				; # Ignore
			} else {
				exception ($m, "Person is not a Swimmer/Coach/Parent/Volunteer/Life Member - Who are they");
			}
			next;
		}
		$n_swimmers++;

		# check in a group
		if ( check_defined( $group_swimmers{ $m->{'Guid'} } ) == 0 ) {
			if ( check_exceptions( $m, EXCEPTION_NOGROUPS ) ) {
				;
			} else {
				exception( $m, 'Swimmer not in any group' );
			}
		}

		check_swimmer_email($m);

		my $email = "";

		if ( check_defined( $m->{'Email'} ) != 0 ){
			$email = $m->{'Email'}
		}

		if ( check_defined( $m->{'Username'} ) != 0 ) {

			# Don't want U16's with login - should be parent
			# CLUB SPECIFIC
			if ( ( check_defined( $m->{'DOB'} ) and ( calc_date( $m, 'DOB' ) <= 16*365 ))) {
				exception( $m, "Swimmer U16 with a login" );
			}
		}

		# Check no of parents
		my $p       = 0;
		my $email_match = 0;
		my $ex_email = "";
		my $pars    = ' ';
		my $parents = $m->{'Parents'};
		my $nce = 0;
		foreach my $x (@$parents) {
			my $q = $member_guid{ $x->{'Guid'} };
			next if ( defined $q == 0 );    #inactive
			if ( check_exceptions( $q, EXCEPTION_EMAILDIFF ) ) {
				$email_match = 1;   # cheat - dont match, but its OK
			}
			if ( check_defined( $q->{'Email'} ) != 0 ){
				$ex_email = $q->{'Email'};
				# Allow for emails with ';' in
				if (index (lc $q->{'Email'},lc $email) != -1) {
					$email_match = 1;
				} elsif (index (lc $email, lc $q->{'Email'}) != -1) {
                                        $email_match = 1;
				}
			}
			if ($m->{'DetailsConfirmedCorrect'}) {
				if ($q->{'DetailsConfirmedCorrect'}) {
					if (check_confirmed_date ($m, $q)) {
						$nce ++;
					}
				}
			}		
			$p++;
			$pars .= '(' . print_name($q) . ')';
		}
		if ( $p > 2 ) {
			exception( $m, "More than 2 parents $pars" );
		}
		if ( $nce > 0) {
			exception( $m, "Different confirmed dates" );
		}
		if ( $p == 0 ) {
			if ( ( check_defined( $m->{'DOB'} ) and ( calc_date( $m, 'DOB' ) <= 17*365 ))) {
				next if ( check_in_group( $m, 'Trialist' ) );
				next if ( check_in_group( $m, 'Tadpole' ) );
				next if ( check_in_group( $m, 'Resignation' ) );
				$n_swimmer_no_parent++;
				## next if ( ignore_no_parent ($m) );
				exception( $m, "Swimmer U17 with no parent" );
			}
		}
		if ( $email_match == 0) {
			if ( ( check_defined( $m->{'DOB'} ) and ( calc_date( $m, 'DOB' ) <= 17*365 ))) {
				exception( $m, "Swimmer U17 ($email) with different email to parent ($ex_email)" );
			}
		}

	}
}

#
# PARENTS
#

sub check_parent_email {
	my $s = shift;

	my $guid = $s->{'Guid'};

	my $e = $s->{'Email'};
	if ( ( defined $e == 0 ) or $e eq "" ) {
		exception( $s, 'Parent no email' );
	}
	if ( index( $s->{'Email'}, ' ' ) > 0 ) {
		exception( $s, 'Space in email address: ' );
	 }
}

sub check_parent_logins {
	my $s = shift;

	my $e = $s->{'Username'};

	return if ( recently_joined($s) == 1 );

	if ( ( (defined $e) == 0 ) or ($e eq "") ) {
		if ( $s->{'DetailsConfirmedCorrect'} ) {
			### add_to_list ('Parent no username, confirmed',$s);
		} else {
			###add_to_list ('Parent no username, not confirmed',$s);
		}
		parent_error( $s, 'Parent with no username (so cannot log in)' );
	} else {
		$e = $s->{'LastLoggedIn'};
		if ( ( (defined $e) == 0 ) or ($e eq "") ) {
			if ( $s->{'DetailsConfirmedCorrect'} ) {
				#### add_to_list ('Parent not logged in, confirmed',$s);
			} else {
				###add_to_list ('Parent not logged in, not confirmed',$s);
			}
			###parent_error( $s, 'Parent with login but has never logged in' );
		} else {
			if ( $s->{'DetailsConfirmedCorrect'} and ($s->{'DetailsConfirmedCorrect'} ne "")) {
				;
			} else {
				###add_to_list ('Parent has loggged in, not confirmed',$s);
			}
		}

	}

}

sub check_swimmers_active {
	my $s = shift;

	if ( my $jd = $s->{'DOB'} ) {
		my $days = calc_date( $s, 'DOB' );
		if ( $days < 365 * 18 ) {
			exception( $s, "Parent under 18 (Swimmers DoB perhaps?) " . print_date2($jd) );
		}
	}

	my $swimmers = $s->{'Swimmers'};
	if ( defined $swimmers == 0 ) {
		if ( $swimmers eq "" ) {
			exception( $s, 'Parent - no swimmers' );
			return;
		}
	}
	
	foreach my $x (@$swimmers) {
		my $u18 = 0;
		my $q = $member_guid{ $x->{'Guid'} };
		next if ( defined $q == 0 );    #inactive
		if ( my $jd = $q->{'DOB'} ) {
			my $days = calc_date( $q, 'DOB' );
			$u18++ if ( $days <= 365 * 18 );
			if ( $days > 365 * 21 ) {
				exception( $s, 'Parent with child over 21 (' . print_name($q) . ') ' . print_date2($jd) );
			}
		}
		check_parent_logins ($s) if ($u18 > 0);
	}

	# Dont care about inactive children if the have some purpose
	return if $s->{'IsACoach'};
	return if $s->{'IsASwimmer'};
	return if $s->{'CommitteeMember'};
	return if ( check_in_group( $s, 'Life Member' ) );

	my $m = 0;
	my $n = 0;
	my $opt;
	foreach my $x (@$swimmers) {
		my $q = $inactive_guid{ $x->{'Guid'} };
		if ($q) {
			$n++;
			$opt = print_name($s) . ' (' . print_name($q) . ')';
		} else {
			$m++;
		}
	}
	if ($n) {
		if ( $m == 0 ) {
			exception( $s, "Parent - swimmer not active: $opt" );
		}
	}
}

sub check_parents {
	foreach my $x ( keys %member_guid ) {
		my $m = $member_guid{$x};
		next if ( $m->{'IsAParent'} == 0 );
		check_parent_email($m);
		check_swimmers_active($m);
	}

	foreach my $x ( keys %parents_guid ) {
		my $m = $member_guid{$x};
		if ( defined $m == 0 ) {
			my $n = $inactive_guid{$x};
			if ( defined $n ) {

				# Possibly CLUB SPECFIC
				######	exception ($n, 'Parent inactive, but swimmer active (Not a big problem, can ignore) '  );
			} else {
				debug('NULL Parent ?');
			}
			next;
		}
	}
}

#
# CONFIRMED MEMBERSHIP
#

sub not_confirmed {
	my $m   = shift;
	my $n   = shift;
	my $e   = shift;
	my $msg = shift;

	return if ((check_defined ($okexceptions{$n}) == 1) and ($okexceptions{$n} > $today)) ;

	$n_notconfirmed++;

	if ( $e eq "" ) {
		push( @{ $not_confirmed{$m} }, $n . ' (No email)' );
	} elsif ($msg) {
		push( @{ $not_confirmed{$m} }, "$n ($msg) ($e)" );
	} else {
		push( @{ $not_confirmed{$m} }, "$n ($e)" );
	}
}

sub check_confirmed {

	foreach my $x ( keys %member_guid ) {
		my $match;
		my $m   = $member_guid{$x};
		my $msg = "";


		next if ( $m->{'Active'} == 0 );

		next if ( recently_joined($m) == 1 );
		next if ( check_in_group( $m, 'Trialist' ) );
		next if ( check_in_group( $m, 'Tadpole' ) );
		next if ( check_in_group( $m, 'Resignation' ) );

		my $e = $m->{'Email'};

		if ( my $cd = $m->{'DetailsConfirmedCorrect'} ) {
			my $days = calc_date( $m, 'DetailsConfirmedCorrect' );
			if ( $days > (365 + $quarter_offset)) {
				if ( $m->{'IsASwimmer'} == 1 ) {
					add_to_list ('Confirmation Expired (Swimmer)',$m);
				} elsif ( $m->{'IsAParent'} == 1 ) {
					add_to_list ('Confirmation Expired (Parent)',$m);
				} else {
					add_to_list ('Confirmation Expired (Other)',$m);
				}
				$msg = "Last confirmed: " . print_date2($cd) ;
				not_confirmed( 'Expired: ' . print_firstgroup_user($m), print_name($m), $e, $msg );
				next;
			} else {
				$n_confirmed++;
				next;
			}
		}

		if ( $m->{'IsASwimmer'} ) {
			if (my $ls = $member_lastseen{print_name($m)}){
				$msg .= " Last seen " . print_date($ls) ;
			} else {
				$msg .= " Never seen" ;
			}
			if ( check_defined($m->{'DateJoinedClub'}) == 1 ) {
				$msg .= " Joined " . print_date2($m->{'DateJoinedClub'}) ;
			}

			not_confirmed( 'Swimmer: ' . print_firstgroup_user($m), print_name($m), $e, $msg );
			add_to_list ('Swimmers not confirmed',$m);
		} elsif ( $m->{'IsAParent'} ) {
			not_confirmed( 'Parent', print_name($m), $e, $msg );
			add_to_list ('Parents not confirmed',$m);
		} elsif ( $m->{'IsACoach'} ) {
			not_confirmed( 'Coach', print_name($m), $e, $msg );
			add_to_list ('Other not confirmed',$m);
		} elsif ( $m->{'CommitteeMember'} ) {
			not_confirmed( 'Committee Member', print_name($m), $e, $msg );
			add_to_list ('Other not confirmed',$m);
		} elsif ( $m->{'IsAVolunteer'} ) {
			not_confirmed( 'Other', print_name($m), $e, $msg );
			add_to_list ('Other not confirmed',$m);
		} elsif ( check_in_group( $m, 'Life Member' ) ) {
			not_confirmed( 'Life Member', print_name($m), $e, $msg );
			add_to_list ('Other not confirmed',$m);
		} else {
			not_confirmed( 'Unknown', print_name($m), $e, $msg );
			add_to_list ('Other not confirmed',$m);
		}
	}
}

#
# FINANCE
#

# CLUB SPECIFIC #
# See comment above

sub check_finance {

	#loop through CSV look for swimmer
	foreach my $x ( keys %finance ) {
		my $m = $member_byname{$x};
		if ( defined $m == 0 ) {
			my $k = $member_knownas{$x};
			if ( defined $k == 0 ) {
				if ( $inactive_byname{$x} ) {
					$finance_nomatch{$x} = $finance{$x} . ' (Resigned/Inactive)';
				} else {
					$finance_nomatch{$x} = $finance{$x};
				}
			}
		}
	}
	
	foreach my $x ( keys %member_byname ) {
		my $match;
		my $gm;
		my $u = $member_byname{$x};
		if ( $u->{'IsASwimmer'} == 0 ) {
			next;    # only swimmers pay
		}

		# Check groups, exclude life members, and trialist
		$gm = 0;
		foreach my $g ( @{ $group_swimmers{ $u->{'Guid'} } } ) {

			# CLUB SPECIFC #
			# We have certain groups I don't care about here...
			if ( index( $g->{'GroupName'}, 'Resignations' ) != -1 )
			{
				$gm++;
			}
			if ( index( $g->{'GroupName'}, 'Tadpole' ) != -1 ) {
				$gm++;
			}
			if ( index( $g->{'GroupName'}, 'Trialist' ) != -1 ) {
				$gm++;
			}
			if ( index( $g->{'GroupName'}, 'Life Member' ) != -1 ) {
				$gm++;
			}
		}
		if ($gm) {
			next;    #ignore lifers etc
		}

		my $f = $finance{$x};
		if ( defined $f == 0 ) {
			my $knownas = $u->{'Lastname'} . ' ' . $u->{'KnownAs'};
			my $k       = $finance{$knownas};
			if ( defined $k == 0 ) {
				$scm_finance_nomatch{$x} = $member_byname{$x};
			}
		}
	}

}

#
# Facebook
#

# CLUB SPECIFIC #
# See comment above

sub check_facebook {

	#loop through CSV look for swimmer
	foreach my $x ( keys %facebook ) {
		my $m = $member_byname{$x};
		if ( defined $m == 0 ) {
			my $k = $member_knownas{$x};
			if ( defined $k == 0 ) {
				if ($facebook_note{$x}) {
					$k = 1;
				}
			}
			if ( defined $k == 0 ) {
				$x =~ /([A-Za-z]+)/;
				my $sn = $1;
				if ( $inactive_byname{$x} ) {
					$facebook_nomatch{$x} = $facebook{$x} . ' (Resigned/Inactive)';
				} elsif ($surname{$sn}) {
					$facebook_nomatch{$x} = $facebook{$x} . ' (Have swimmer with same surname - Parent?)';
				} else {
					$facebook_nomatch{$x} = $facebook{$x};
				}
			}
		}
	}
}
# Swim England

sub check_se {
		

	#loop through CSV look for swimmer
	foreach my $x ( keys %se ) {
		
		my $m = $member_byname{$x};
		my $inactive = $inactive_byname{$x};	
		
		if ( defined $m == 0 ) {
			$m = $member_knownas{$x};
		}

		if ( defined $m == 0 ) {
			my $x_ka = $se_ka{$x};
			my $k = $member_byname{$x_ka};
			if ( $inactive ) {
				;
			} else {
				$inactive = $inactive_byname{$x_ka};	
			}

			if ( defined $k == 0 ) {
				if ( $inactive_byname{$x} ) {
					$se_nomatch{$x} = $se{$x} . ' (Resigned/Inactive)';
				} else {
					$se_nomatch{$x} = $se{$x};
				}
			}
			$m = $k
		}

		if ( defined $m ) {
			# Check DOB and ASANumber
			my $asano;
			my $asacat;

			if (check_defined( $m->{'ASANumber'}) ){ 
				 $asano = $m->{'ASANumber'};
			} else {
				 $asano = "NONE";
			}
			if ( $asano eq $se_asa{$x}) {
				;
			} else {
				$se_asa_nomatch {$x} = " - SCM: " . $asano . ", SE: " . $se_asa{$x};
			}
			if (check_defined( $m->{'ASACategory'}) ){ 
				 $asacat = $m->{'ASACategory'};
			} else {
				 $asacat = "NONE";
			}
			if ( "ENG" . $asacat eq $se_cat{$x}) {
				;
			} else {
				$se_asa_nomatch {$x} = " - SCM: " . $asacat . ", SE: " . $se_cat{$x};
			}
			if ( cmp_date_asa ($m->{'DOB'}, $se_dob{$x})) {
				;
			} else {
				$se_asa_nomatch {$x} = " - SCM: " . $m->{'DOB'} . ", SE: " . $se_dob{$x};
			}
		}
	}
		
	foreach my $x ( keys %member_byname ) {
		my $match;
		my $gm;
		my $u = $member_byname{$x};
		if ( $u->{'IsASwimmer'} == 0 ) {
			next;    # only swimmers pay
		}
		next if ( recently_joined($u) != 0 );   # give then some time to get set up

		# Check groups, exclude life members, and trialist
		$gm = 0;
		foreach my $g ( @{ $group_swimmers{ $u->{'Guid'} } } ) {

			# CLUB SPECIFC #
			# We have certain groups I don't care about here...
			if ( index( $g->{'GroupName'}, 'Resignations' ) != -1 )
			{
				$gm++;
			}
			if ( index( $g->{'GroupName'}, 'Tadpole' ) != -1 ) {
				$gm++;
			}
			if ( index( $g->{'GroupName'}, 'Trialist' ) != -1 ) {
				$gm++;
			}
			if ( index( $g->{'GroupName'}, 'Life Member' ) != -1 ) {
				$gm++;
			}
		}
		if ($gm) {
			next;    #ignore lifers etc
		}

		my $f = $se{$x};
		if ( defined $f == 0 ) {
			$f = $se_reverse{$x};
		}
		if ( defined $f == 0 ) {
			my $knownas = $u->{'Lastname'} . ' ' . $u->{'KnownAs'};
			my $k       = $se{$knownas};
			if ( defined $k == 0 ) {
				$scm_se_nomatch{$x} = $member_byname{$x};
			}
		}
	}

}

#########################
# Print Results
#########################

#
# Finance
#


sub print_finance {
	my $opt  = "\n";
	my $opt1 = "\n";
	foreach my $x ( sort {$finance_nomatch{$a} cmp $finance_nomatch{$b}} keys %finance_nomatch ) {
		$opt .= "\t" . $finance_nomatch{$x} . "\n";
	}
	if ( ($opt) ne "\n" ) {
		$opt = "Swimmers in finance file but not in SCM $opt \n";
	}
	foreach my $x ( sort {print_name($scm_finance_nomatch{$a}) cmp print_name($scm_finance_nomatch{$b})} keys %scm_finance_nomatch ) {
		my $s = $scm_finance_nomatch{$x};
		my $n = print_name($s);
		next if ((check_defined ($okexceptions{$n}) == 1) and ($okexceptions{$n} > $today)) ;
		my $q = $n;
		if ( my $grp = print_group_guid( $s->{'Guid'} ) ) {
			$q .= " ($grp)";
		}
		if (check_defined $member_lastseen{$n}) {
			$q .=  " (Last seen: " . print_date($member_lastseen{$n}) . ")";
		} else {
			$q .=  " (Last seen: never )";
		}
		$opt1 .= "\t$q\n";
	}
	if ( $opt1 ne "\n" ) {
		return $opt . "Swimmers in SCM but not finance file $opt1\n";
	} elsif ( $opt ne "\n" ) {
		return $opt . "\n";
	}
	return "";
}

#
# Facebook
#


sub print_facebook {
	my $opt  = "\n";
	my $opt1 = "\n";
	foreach my $x ( sort {$facebook_nomatch{$a} cmp $facebook_nomatch{$b}} keys %facebook_nomatch ) {
		$opt .= $facebook_nomatch{$x} . "\n";
	}
	if ( ($opt) ne "\n" ) {
		$opt = "Swimmers in Facebook but not in SCM $opt \n";
	}
	if ( $opt ne "\n" ) {
		return $opt . "\n";
	}
	return "";
}


sub print_se {
	my $opt  = "\n";
	my $opt1 = "\n";
	my $opt2 = "\n";

	foreach my $x ( sort {$se_nomatch{$a} cmp $se_nomatch{$b}} keys %se_nomatch ) {
		$opt .= "\t" . $se_nomatch{$x} . "\n";
	}
	if ( ($opt) ne "\n" ) {
		$opt = "Swimmers in Swim England file but not in SCM $opt \n";
	}

	foreach my $x ( sort {print_name($scm_se_nomatch{$a}) cmp print_name($scm_se_nomatch{$b})} keys %scm_se_nomatch ) {
		my $s = $scm_se_nomatch{$x};
		my $n = print_name($s);
		next if ((check_defined ($okexceptions{$n}) == 1) and ($okexceptions{$n} > $today)) ;
		my $q = $n;
		if ( my $grp = print_group_guid( $s->{'Guid'} ) ) {
			$q .= " ($grp)";
		}
		if (check_defined $member_lastseen{$n}) {
			$q .=  " (Last seen: " . print_date($member_lastseen{$n}) . ")";
		} else {
			$q .=  " (Last seen: never )";
		}
		$opt1 .= "\t$q\n";
	}

	foreach my $x ( keys %se_asa_nomatch ) {
		$opt2 .= "\t" . $x . ":" . $se_asa_nomatch{$x} . "\n";
	}
	if ( ($opt2) ne "\n" ) {
		$opt .= "Swimmers with SE database differences $opt2 \n";
	}

	if ( $opt1 ne "\n" ) {
		return $opt . "Swimmers in SCM but not Swim England file $opt1\n";
	} elsif ( $opt ne "\n" ) {
		return $opt . "\n";
	}
	return "";
}

#
# Coaches
#

sub print_session_coaches {

	my $res = "Coaches listed per session:\n";

	foreach my $x ( sort { print_session_guid($a) cmp print_session_guid($b) } keys %session_guid ) {
		my $coaches = $session_guid{$x}->{'Coaches'};
		$res .= sprintf "%s\n", print_session_guid($x);
		foreach my $c ( sort @$coaches ) {
			my $ls = $c->{'LastAttended'};
			if (check_defined($ls) == 0) {
				$res .= "\t" . print_name_guid( $c->{'Guid'}) . " (Never seen)\n";
			} elsif (calc_date ($c,'LastAttended') < 120) {
				$res .= "\t" . print_name_guid( $c->{'Guid'}) . " \n";
			} else {
				$res .= "\t" . print_name_guid( $c->{'Guid'}) . " (Not seen since: $ls)\n" ;
			}
		}
	}
	return $res;
}

#
# groups
#

sub print_group_errors {
	my $match = 0;

	my $opt = "The following groups have swimmers that are not in any relevant sessions...\n";

	foreach my $x ( sort keys %group_errors ) {
		$opt .= $x . "\n";
		foreach my $y ( sort @{ $group_errors{$x} } ) {
			$opt .= "\t$y\n";
			$match++;
		}
	}

	$opt .= "\nThe following group have errors...\n";

	foreach my $x ( sort keys %two_groups_errors ) {
		$opt .= $x . "\n";
		foreach my $y ( sort @{ $two_groups_errors{$x} } ) {
			$opt .= "\t$y\n";
			$match++;
		}
	}

	if ($match) {
		return $opt . "\n";
	}

	return "";
}

sub print_session_errors {
	my $match = 0;

	my $opt = "\nThe following sessions have errors...\n";

	foreach my $x ( sort keys %session_errors ) {
		if ($no_register{$x}) {
			$opt .= "\n" . $x . "\n*** no register for 60 days ***\n*** last taken $no_register{$x} ***\n";
		} else {
			$opt .= "\n" . $x . " (register last taken: " . print_date($session_lastseen_name{$x}) . ")\n";
		}
		foreach my $y ( sort @{ $session_errors{$x} } ) {
			$opt .= "\t$y\n";
			$match++;
		}
	}

	if ($match) {
		return $opt . "\n";
	}

	return "";
}

#
# Not confirmed
#

sub print_not_confirmed {
	my $match;
	my $opt = "The following have not confirmed their details...\n";

	foreach my $x ( sort keys %not_confirmed ) {
		$opt .= "\n\n" . $x . " (XXX)\n";
		my $i = 0;
		foreach my $y ( sort @{ $not_confirmed{$x} } ) {
			$opt .= "   $y \n";
			$match++;
			$i++;
		}
		$opt =~ s/, $//;      # hack get rid of last comma
		$opt =~ s/XXX/$i/;    # hack add count back in
	}

	if ($match) {
		return $opt . "\n\n";
	}
	return "";
}

sub print_one_result {
	my $res   = shift;
	my $title = shift;

	return if ( $res eq "" );

	if ($options{E}) {
		send_email( $res, $title );
	}
	print $res;
}

sub print_parent_errors {

	return if ( $num_p_error == 0 );
	my $opt = "Login / username errors in Parent entries";

	foreach my $e ( sort keys %p_error ) {
		$opt .= "\n\n" . $e . "\n";
		foreach my $m ( sort @{ $p_error{$e} } ) {
			$opt .= $m . ", ";
		}
	}

	if ($options{E}) {
		send_email( $opt, 'SCM: Parent Exceptions' );
	}
	print $opt . "\n\n";
}

sub print_exceptions2 {

	return if ( $num_exceptions == 0 );
	my $opt = "Errors found in SCM members entries\n";

	foreach my $e ( sort keys %exceptions2 ) {
		if (check_defined $member_lastseen{$e}) {
			$opt .= $e . " (Last seen: " . print_date($member_lastseen{$e}) . ")\n\t";
		} else {
			$opt .= $e . " (Not seen)\n\t";
		}
		foreach my $m ( @{ $exceptions2{$e} } ) {
			$opt .= $m . "\n\t";
		}
		$opt .= "\n";
	}

	if ($options{E}) {
		send_email( $opt, 'SCM: Extended Exceptions' );
	}
	print $opt . "\n\n";
}

sub print_dbs_exceptions {

	return if ( $num_dbs_exceptions == 0 );
	my $opt = "Leander DBS that have expired, or about to expire... \n\n\n";

	foreach my $e ( sort keys %dbs_exceptions ) {
		if (check_defined $member_lastseen{$e}) {
			$opt .= $e . " (Last seen: " . print_date($member_lastseen{$e}) . ")\n\t";
		} else {
			if ($e eq ' ') {  # Special error case
				$opt .= $e . "\n\t";
			} else {
				$opt .= $e . " (Not seen)\n\t";
			}
		}
		foreach my $m ( @{ $dbs_exceptions{$e} } ) {
			$opt .= $m . "\n\t";
		}
		$opt .= "\n";
	}

	if ($options{E}) {
		send_email( $opt, 'SCM: DBS Errors' );
	}
	print $opt . "\n\n";
}

sub print_exceptions {

	return if ( $num_exceptions == 0 );
	my $opt = "Errors found in SCM members entries\n";

	foreach my $e ( sort keys %exceptions ) {
		if (check_defined $member_lastseen{$e}) {
			$opt .= $e . " (Last seen: " . print_date($member_lastseen{$e}) . ")\n\t";
		} else {
			if ($e eq ' ') {  # Special error case
				$opt .= $e . "\n\t";
			} else {
				$opt .= $e . " (Not seen)\n\t";
			}
		}
		foreach my $m ( @{ $exceptions{$e} } ) {
			$opt .= $m . "\n\t";
		}
		$opt .= "\n";
	}

	if ($options{E}) {
		send_email( $opt, 'SCM: Exceptions' );
	}
	print $opt . "\n\n";
}

sub print_notes {

	foreach my $x (%member_guid) {
		my $swimmer = $member_guid{$x};
		if (check_defined ($swimmer->{'Notes'})) {
			if ( index( $swimmer->{'Notes'}, "Facebook:" ) != -1 ) {	
				printf ("%s - %s\n", print_name ($swimmer),  $swimmer->{'Notes'});
			}
			if ( index( $swimmer->{'Notes'}, "API:" ) != -1 ) {	
				printf ("%s - %s\n", print_name ($swimmer),  $swimmer->{'Notes'});
			}
		}
	}

	foreach my $x (%inactive_guid) {
		my $swimmer = $inactive_guid{$x};
		if (check_defined ($swimmer->{'Notes'})) {
			if ( index( $swimmer->{'Notes'}, "Facebook:" ) != -1 ) {	
				printf ("%s (inactive) - %s\n", print_name ($swimmer),  $swimmer->{'Notes'});
			}
			if ( index( $swimmer->{'Notes'}, "API:" ) != -1 ) {	
				printf ("%s (inactive) - %s\n", print_name ($swimmer),  $swimmer->{'Notes'});
			}
		}
	}

}

sub print_summary {
	my $opt =
	    "\nUsers: " . $n_users
	  . "\nSwimmers: " . $n_swimmers
	  . "\nParents: " . $n_parents
	  . "\nCoaches: " . $n_coaches
	  . "\nInactive: " . $n_inactive
	  . "\n\nSwimmer no parents: " . $n_swimmer_no_parent 
	  . "\n\nLists: " . $n_lists
	  . "\nGroups: " . $n_groups
	  . "\nSessions: " . $n_sessions
	  . "\nRoles:" . $n_roles
	  . "\n\nConfirmed: " . $n_confirmed
	  . "\nNot Confirmed: " . $n_notconfirmed
	  . "\n";

	if ($options{E}) {
		send_email( $opt, 'SCM: Summary' );
	}
	print $opt;
}

#########################
# Pulling it all together
#########################
# Gather all the data
#########################

sub get_data {
	get_key();
	if (defined $options{f} ) {
		get_finance()           if (FINANCE);
	}
	if (defined $options{F} ) {
		get_facebook()          if (FACEBOOK);
	}
	if (defined $options{m} ) {
		get_se()     	      	if (SWIMENGLAND);
	}
	get_email_credentials() if ($options{E});
	
	print STDERR ('Groups...');	get_groups();
	print STDERR ('Lists...');	get_lists();
	print STDERR ('Roles...');	get_roles();
	print STDERR ('Sessions...');	get_sessions();
	print STDERR ('Users...');	get_users();
	print STDERR ("Coaches...\n");	get_coaches();

	count_parents();
}

##########################
# Run analytics
##########################

sub analyse_data {
	print STDERR ('Analysing...');

	check_coaches();
	check_parents();
	check_swimmers();
	if (defined $options{f} ) {
		check_finance() if (FINANCE);
	} 
	if (defined $options{F} ) {
		check_facebook() if (FACEBOOK);
	} 
	if (defined $options{m} ) {
		check_se() if (SWIMENGLAND);	
	}
	check_member_only();
	check_attendance();
	check_confirmed();  # relies on check_attendance()
	check_groups();
	check_roles();

	create_lists();
}

sub print_results {
	print STDERR ("\nResults...\n");

	if (defined $options{d} or defined $options{a}) {
		print_dbs_exceptions();
	}
	if (defined $options{e} or defined $options{a}) {
		print_exceptions();
	}
	if (defined $options{x} or defined $options{a}) {
		print_exceptions2 ();  # alternaitve format
	}
	if (defined $options{n} )
		{ print_notes();}
	
	if (defined $options{p} or defined $options{a})
		{ print_parent_errors();}
	
	if (defined $options{c} or defined $options{a})
		{ print_one_result( print_not_confirmed(), 'SCM: Swimmers not confirmed' );}

	if (defined $options{g} or defined $options{a})
		{print_one_result( print_group_errors(), 'SCM: Groups' );}

	if (defined $options{s} or defined $options{a})
		{print_one_result( print_session_errors(), 'SCM: Sessions' );}

	if (defined $options{m} )
		{print_one_result( print_se(), 'SCM: Swim England' ) if (SWIMENGLAND);};

	if (defined $options{F} )
		{print_one_result( print_facebook(), 'SCM: Facebook' ) if (FACEBOOK);};

	if (defined $options{f} )
		{print_one_result( print_finance(), 'SCM: Finance' ) if (FINANCE);};

	if (defined $options{t} or defined $options{a})
		{print_one_result (print_session_coaches(),'SCM: Session Coaches');};
}

##########################
# Main
##########################

getopts("adhumnexpfcgsFSEt",\%options);

if (defined $options{h}) {
	print << 'END';
	e - print expections
	x - print expections (all)
	p - parent errors
	f - finance
	F - Facebook
	c - confirmation
	g - groups
	s - sessions
	d - dbs
	S - summary
	E - Email
	u - update lists
	t - coaching team
	m - Swim England Membership
	n - print notes
	a - print all
END
	exit;
}

set_quarter();
get_exceptions();
get_data();
analyse_data();
print_results();
print_summary() if (defined $options{S} or defined $options{a});

update_lists ()   if (defined $options{u});

# end #

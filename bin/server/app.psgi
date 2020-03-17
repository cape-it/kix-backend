#!/usr/bin/perl
# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

use CGI;
use CGI::Emulate::PSGI;
use Module::Refresh;
use Plack::Builder;
use File::Path qw();
use Fcntl qw(:flock);

# use ../../ as lib location
use FindBin qw($Bin);
use lib "$Bin/../..";
use lib "$Bin/../../Kernel/cpan-lib";
use lib "$Bin/../../Custom";

use Kernel::API::Provider;
use Kernel::System::ObjectManager;

$Kernel::OM = Kernel::System::ObjectManager->new(
    'Kernel::System::Log' => {
        LogPrefix => 'API',
    },
);

use Kernel::Config;

# Workaround: some parts of KIX use exit to interrupt the control flow.
#   This would kill the Plack server, so just use die instead.
BEGIN {
    *CORE::GLOBAL::exit = sub { die "exit called\n"; };
}

_LockPID();
_Autostart();

my $App = CGI::Emulate::PSGI->handler(
    sub {

        # Cleanup values from previous requests.
        CGI::initialize_globals();

        # Populate SCRIPT_NAME as KIX needs it in some places.
        $ENV{SCRIPT_NAME} = 'api';

        eval {

            # Reload files in @INC that have changed since the last request.
            Module::Refresh->refresh();
        };
        warn $@ if $@;

        my $Profile;
        if ( $ENV{NYTPROF} && $ENV{REQUEST_URI} =~ /NYTProf=([\w-]+)/ ) {
            $Profile = 1;
            DB::enable_profile("nytprof-$1.out")
        }

        # run the request
        eval {
            do "$Bin/$ENV{SCRIPT_NAME}";
        };
        if ( $@ && $@ ne "exit called\n" ) {
            warn $@;
        }

        if ($Profile) {
            DB::finish_profile();
        }
    },
);

sub _LockPID {
	# create ConfigObject
	my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

	my $PIDDir  = $ConfigObject->Get('Home') . '/var/run/';
	my $PIDFile = $PIDDir . "service.pid";
	my $PIDFH;

	if ( !-e $PIDDir ) {

		File::Path::mkpath( $PIDDir, 0, 0770 );    ## no critic

		if ( !-e $PIDDir ) {
			print STDERR "Can't create directory '$PIDDir': $!";
			exit 1;
		}
	}
	if ( !-w $PIDDir ) {
		print STDERR "Don't have write permissions in directory '$PIDDir': $!";
		exit 1;
	}

	# create new PID file (set exclusive lock while writing the PIDFile)
	open my $FH, '>', $PIDFile || die "Can not create PID file: $PIDFile\n";    ## no critic
	return if !flock( $FH, LOCK_EX | LOCK_NB );
	print $FH $$;
	close $FH;
}

sub _Autostart {
    my $Result = $Kernel::OM->Get('Kernel::System::Autostart')->Run();
 	if ( $Result ) {
		print STDERR "At least one autostart module failed. Please see the KIX log for details.\n";
		exit $Result;
	}
}

# add middlewares
builder {
    enable "Refresh";
    enable "Deflater",
        content_type => ['application/json'],
        vary_user_agent => 1;
    enable "Plack::Middleware::AccessLog::Timed",
        format => "%h %l %u %t \"%r\" %>s %b %D";
    enable "StackTrace", 
        force => 1;
    $App;
};

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<http://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
COPYING for license information (AGPL). If you did not receive this file, see

<http://www.gnu.org/licenses/agpl.txt>.

=cut
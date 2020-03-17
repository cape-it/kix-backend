# --
# Modified version of the work: Copyright (C) 2006-2020 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

use Kernel::System::VariableCheck qw(:all);

# get needed objects
my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
my $ModuleObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::TransitionAction::TicketLockSet');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# define variables
my $UserID     = 1;
my $ModuleName = 'TicketLockSet';
my $RandomID   = $Helper->GetRandomID();

# set user details
my $TestUserLogin = $Helper->TestUserCreate();
my $TestUserID    = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
    UserLogin => $TestUserLogin,
);

# ----------------------------------------
# Create a test ticket
# ----------------------------------------
my $TicketID = $TicketObject->TicketCreate(
    Title         => 'test',
    QueueID       => 1,
    Lock          => 'lock',       # This value is specially important for this test
    Priority      => '3 normal',
    StateID       => 1,
    TypeID        => 1,
    OwnerID       => 1,
    ResponsibleID => 1,
    UserID        => $UserID,
);

# sanity checks
$Self->True(
    $TicketID,
    "TicketCreate() - $TicketID",
);

my %Ticket = $TicketObject->TicketGet(
    TicketID => $TicketID,
    UserID   => $UserID,
);
$Self->True(
    IsHashRefWithData( \%Ticket ),
    "TicketGet() - Get Ticket with ID $TicketID.",
);

# Run() tests
my @Tests = (
    {
        Name    => 'No Params',
        Config  => undef,
        Success => 0,
    },
    {
        Name   => 'No UserID',
        Config => {
            UserID => undef,
            Ticket => \%Ticket,
            Config => {
                CustomerID => 'test',
            },
        },
        Success => 0,
    },
    {
        Name   => 'No Ticket',
        Config => {
            UserID => $UserID,
            Ticket => undef,
            Config => {
                CustomerID => 'test',
            },
        },
        Success => 0,
    },
    {
        Name   => 'No Config',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {},
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Config',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                NoAgentNotify => 0,
            },
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Ticket Format',
        Config => {
            UserID => $UserID,
            Ticket => 1,
            Config => {
                Lock => 'lock',
            },
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Config Format',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => 1,
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Lock',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                Lock => 'NotExisting' . $RandomID,
            },
        },
        Success => 0,
    },
    {
        Name   => 'Wrong LockID',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                LockID => 'NotExisting' . $RandomID,
            },
        },
        Success => 0,
    },
    {
        Name   => 'Correct Lock unlock',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                Lock => 'unlock',
            },
        },
        Success => 1,
    },
    {
        Name   => 'Correct Lock lock',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                Lock => 'lock',
            },
        },
        Success => 1,
    },
    {
        Name   => 'Correct LockID unlock',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                LockID => 1,
            },
        },
        Success => 1,
    },
    {
        Name   => 'Correct LockID lock',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                LockID => 2,
            },
        },
        Success => 1,
    },
    {
        Name   => 'Correct Ticket->QueueID',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                LockID => '<KIX_TICKET_QueueID>',
            },
        },
        Success => 1,
    },
    {
        Name   => 'Wrong Ticket->NotExisiting',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                Lock => '<KIX_TICKET_BotExisting>',
            },
        },
        Success => 0,
    },
    {
        Name   => 'Correct Using Different UserID',
        Config => {
            UserID => $UserID,
            Ticket => \%Ticket,
            Config => {
                Lock   => 'unlock',
                UserID => $TestUserID,
            },
        },
        Success => 1,
    },
);

for my $Test (@Tests) {

    # make a deep copy to avoid changing the definition
    my $OrigTest = Storable::dclone($Test);

    my $Success = $ModuleObject->Run(
        %{ $Test->{Config} },
        ProcessEntityID          => 'P1',
        ActivityEntityID         => 'A1',
        TransitionEntityID       => 'T1',
        TransitionActionEntityID => 'TA1',
    );

    if ( $Test->{Success} ) {

        $Self->True(
            $Success,
            "$ModuleName Run() - Test:'$Test->{Name}' | executed with True"
        );

        # get ticket
        %Ticket = $TicketObject->TicketGet(
            TicketID => $TicketID,
            UserID   => 1,
        );

        ATTRIBUTE:
        for my $Attribute ( sort keys %{ $Test->{Config}->{Config} } ) {

            $Self->True(
                $Ticket{$Attribute},
                "$ModuleName - Test:'$Test->{Name}' | Attribute: $Attribute for TicketID:"
                    . " $TicketID exists with True",
            );

            my $ExpectedValue = $Test->{Config}->{Config}->{$Attribute};
            if (
                $OrigTest->{Config}->{Config}->{$Attribute}
                =~ m{\A<KIX_TICKET_([A-Za-z0-9_]+)>\z}msx
                )
            {
                $ExpectedValue = $Ticket{$1} // '';
                $Self->IsNot(
                    $Test->{Config}->{Config}->{$Attribute},
                    $OrigTest->{Config}->{Config}->{$Attribute},
                    "$ModuleName - Test:'$Test->{Name}' | Attribute: $Attribute value: $OrigTest->{Config}->{Config}->{$Attribute} should been replaced",
                );
            }

            $Self->Is(
                $Ticket{$Attribute},
                $ExpectedValue,
                "$ModuleName - Test:'$Test->{Name}' | Attribute: $Attribute for TicketID:"
                    . " $TicketID match expected value",
            );
        }

        if ( $OrigTest->{Config}->{Config}->{UserID} ) {
            $Self->Is(
                $Test->{Config}->{Config}->{UserID},
                undef,
                "$ModuleName - Test:'$Test->{Name}' | Attribute: UserID for TicketID:"
                    . " $TicketID should be removed (as it was used)",
            );
        }
    }
    else {
        $Self->False(
            $Success,
            "$ModuleName Run() - Test:'$Test->{Name}' | executed with False"
        );
    }
}

# cleanup is done by RestoreDatabase.

1;



=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-AGPL for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut

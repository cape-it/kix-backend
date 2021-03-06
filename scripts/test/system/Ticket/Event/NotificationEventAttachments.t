# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
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

# get config object
my $ConfigObject = $Kernel::OM->Get('Config');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('UnitTest::Helper');

my $Success = $ConfigObject->Set(
    Key   => 'Frontend::RichText',
    Value => 1,
);

$Self->True(
    $Success,
    "Enable RichText",
);

# use Test email backend
$Success = $ConfigObject->Set(
    Key   => 'SendmailModule',
    Value => 'Email::Test',
);

$Self->True(
    $Success,
    "Set Email Test backend with true",
);

my $TestEmailObject = $Kernel::OM->Get('Email::Test');

$Success = $TestEmailObject->CleanUp();

$Self->True(
    $Success,
    'Initial cleanup',
);

$Self->IsDeeply(
    $TestEmailObject->EmailsGet(),
    [],
    'Test backend empty after initial cleanup',
);

# get user object
my $UserObject = $Kernel::OM->Get('User');

my @UserIDs;

# create a new users
for ( 1 .. 4 ) {

    my $UserLogin = $Helper->TestUserCreate(
        Groups => ['users'],
    );

    my %UserData = $UserObject->GetUserData(
        User => $UserLogin,
    );

    my $UserID = $UserData{UserID};

    push @UserIDs, $UserID;
}

# get a random id
my $RandomID = $Helper->GetRandomID();

# get group object
my $GroupObject = $Kernel::OM->Get('Group');

# add group
my $GID = $GroupObject->GroupAdd(
    Name    => "example-group$RandomID",
    Comment => 'comment describing the group',
    ValidID => 1,
    UserID  => 1,
);

$Self->IsNot(
    $GID,
    undef,
    "GroupAdd() should not be undef",
);

# add role
my $RoleID = $GroupObject->RoleAdd(
    Name    => "example-role$RandomID",
    Comment => 'comment describing the role',
    ValidID => 1,
    UserID  => 1,
);

$Self->IsNot(
    $RoleID,
    undef,
    "RoleAdd() should not be undef",
);

for my $UserID (@UserIDs) {

    # add users to groups
    $Success = $GroupObject->PermissionGroupUserAdd(
        GID        => $GID,
        UID        => $UserID,
        Permission => {
            ro        => 1,
            move_into => 1,
            create    => 1,
            owner     => 1,
            priority  => 1,
            rw        => 1,
        },
        UserID => 1,
    );

    $Self->True(
        $Success,
        "Added User ID $UserID to Group ID $GID",
    );

    # add user to role
    $Success = $GroupObject->PermissionRoleUserAdd(
        RID    => $RoleID,
        UID    => $UserID,
        Active => 1,
        UserID => 1,
    );

    $Self->True(
        $Success,
        "Added User ID $UserID to Role ID $RoleID",
    );
}

# get queue object
my $QueueObject = $Kernel::OM->Get('Queue');

# get queue data
my %Queue = $QueueObject->QueueGet(
    ID => 1,
);

# set queue to special group
$Success = $QueueObject->QueueUpdate(
    QueueID => 1,
    %Queue,
    GroupID => $GID,
    UserID  => 1,
);

$Self->True(
    $Success,
    "Set Queue ID 1 to Group ID $GID",
);

# get ticket object
my $TicketObject = $Kernel::OM->Get('Ticket');

# create ticket
my $TicketID = $TicketObject->TicketCreate(
    Title         => 'Ticket One Title',
    QueueID       => 1,
    Lock          => 'unlock',
    Priority      => '3 normal',
    State         => 'new',
    CustomerID    => 'example.com',
    Contact  => 'customerOne@example.com',
    OwnerID       => $UserIDs[0],
    ResponsibleID => $UserIDs[1],
    UserID        => $UserIDs[2],
);

# sanity check
$Self->True(
    $TicketID,
    "TicketCreate() successful for Ticket ID $TicketID",
);

# get dynamic field object
my $DynamicFieldObject = $Kernel::OM->Get('DynamicField');

# create a dynamic field
my $FieldID = $DynamicFieldObject->DynamicFieldAdd(
    Name       => "DFT1$RandomID",
    Label      => 'Description',
    FieldOrder => 9991,
    FieldType  => 'Text',
    ObjectType => 'Ticket',
    Config     => {
        DefaultValue => 'Default',
    },
    ValidID => 1,
    UserID  => 1,
    Reorder => 0,
);

# define params for sending as CustomerMessageParams
my $CustomerMessageParams = {
    A => 'AAAAA',
    B => 'BBBBB',
    C => 'CCCCC',
};

my %OriginalCustomerMessageParams = %{$CustomerMessageParams};

my @Tests = (
    {
        Name => 'Single RecipientAgent',
        Data => {
            Events => [ 'TicketDynamicFieldUpdate_DFT1' . $RandomID . 'Update' ],

            # RecipientAgents => [$UserID],
        },
        Config => {
            Event => 'TicketDynamicFieldUpdate_DFT1' . $RandomID . 'Update',
            Data  => {
                TicketID              => $TicketID,
                Recipients            => \@UserIDs,
                CustomerMessageParams => $CustomerMessageParams,
            },
            Config => {},
            UserID => 1,
        },
        ExpectedResults => {
            '0' => 'text/plain; charset="utf-8"',
            '1' => 'text/html; charset="utf-8"'
        },
        Success => 1,
    },

);

my $NotificationEventObject      = $Kernel::OM->Get('NotificationEvent');
my $EventNotificationEventObject = $Kernel::OM->Get('Kernel::System::Ticket::Event::NotificationEvent');

my $Count = 0;
my $NotificationID;
TEST:
for my $Test (@Tests) {

    # add transport setting
    $Test->{Data}->{Transports} = ['Email'];

    $NotificationID = $NotificationEventObject->NotificationAdd(
        Name    => "JobName$Count-$RandomID",
        Comment => 'An optional comment',
        Data    => $Test->{Data},
        Message => {
            en => {
                Subject     => 'JobName',
                Body        => 'JobName <KIX_TICKET_TicketID> <KIX_CONFIG_SendmailModule> <KIX_OWNER_Firstname>',
                ContentType => 'text/plain',
            },
            de => {
                Subject     => 'JobName',
                Body        => 'JobName <KIX_TICKET_TicketID> <KIX_CONFIG_SendmailModule> <KIX_OWNER_Firstname>',
                ContentType => 'text/plain',
            },
        },
        ValidID => 1,
        UserID  => 1,
    );

    # sanity check
    $Self->IsNot(
        $NotificationID,
        undef,
        "$Test->{Name} - NotificationAdd() should not be undef",
    );

    my $Result = $EventNotificationEventObject->Run( %{ $Test->{Config} } );

    if ( !$Test->{Success} ) {
        $Self->False(
            $Result,
            "$Test->{Name} - NotificationEvent Run() with false",
        );

        # notification will be deleted in "continue" statement
        next TEST;
    }

    $Self->True(
        $Result,
        "$Test->{Name} - NotificationEvent Run() with true",
    );

    my $Emails = $TestEmailObject->EmailsGet();

    # remove not needed data
    for my $Email ( @{$Emails} ) {

        my $Counter = 0;
        my %Result;
        for my $Header ( split '\n', ${ $Email->{Body} } ) {

            if ( $Header =~ /^Content\-Type\:\ (.*?)\;.*?\"(.*?)\"/x ) {
                $Result{$Counter} = ( split ': ', $Header )[1];
                $Counter++;
            }
        }

        $Self->Is(
            $Counter,
            2,
            "Attachment number should be 2, plain and html.",
        );

        $Self->IsDeeply(
            \%Result,
            $Test->{ExpectedResults},
            "$Test->{Name} - Attachments",
        );

    }

}
continue {

    # delete notification event
    my $NotificationDelete = $NotificationEventObject->NotificationDelete(
        ID     => $NotificationID,
        UserID => 1,
    );

    # sanity check
    $Self->True(
        $NotificationDelete,
        "$Test->{Name} - NotificationDelete() successful for Notification ID $NotificationID",
    );

    $TestEmailObject->CleanUp();

    $Count++;
    undef $NotificationID;
}

# verify CustomerMessageParams reference have
# the same content as the beginning of this test
$Self->IsDeeply(
    $CustomerMessageParams,
    \%OriginalCustomerMessageParams,
    "CustomerMessageParams didn't grow after sending emails.",
);

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

# --
# Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Role;

use strict;
use warnings;

use base qw(
    Kernel::System::Role::Permission
    Kernel::System::Role::User
);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::User',
    'Kernel::System::Valid',
);

=head1 NAME

Kernel::System::Role - roles lib

=head1 SYNOPSIS

All role functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $RoleObject = $Kernel::OM->Get('Kernel::System::Role');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{CacheType} = 'Role';
    $Self->{CacheTTL}  = 60 * 60 * 24 * 20;

    return $Self;
}

=item RoleLookup()

get id or name for role

    my $Role = $RoleObject->RoleLookup(
        RoleID => $RoleID,
    );

    my $RoleID = $RoleObject->RoleLookup(
        Role => $Role,
    );

=cut

sub RoleLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Role} && !$Param{RoleID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no Role or RoleID!',
        );
        return;
    }

    # get role list
    my %RoleList = $Self->RoleList(
        Valid => 0,
    );

    return $RoleList{ $Param{RoleID} } if $Param{RoleID};

    # create reverse list
    my %RoleListReverse = reverse %RoleList;

    return $RoleListReverse{ $Param{Role} };
}

=item RoleGet()

returns a hash with role data

    my %RoleData = $RoleObject->RoleGet(
        ID => 2,
    );

This returns something like:

    %RoleData = (
        'Name'       => 'role_helpdesk_agent',
        'ID'         => 2,
        'Comment'    => 'Role for help-desk people.',
        'ValidID'    => '1',
        'CreateTime' => '2010-04-07 15:41:15',
        'CreateBy'   => 1,
        'ChangeTime' => '2010-04-07 15:41:15',
        'ChangeBy'   => 1
    );

=cut

sub RoleGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ID!'
        );
        return;
    }

    # check cache
    my $CacheKey = 'RoleGet::' . $Param{ID};
    my $Cache    = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;
    
    return if !$Kernel::OM->Get('Kernel::System::DB')->Prepare( 
        SQL   => "SELECT id, name, comments, valid_id, create_time, create_by, change_time, change_by FROM roles WHERE id = ?",
        Bind => [ \$Param{ID} ],
    );

    my %Role;
    
    # fetch the result
    while ( my @Row = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray() ) {
        %Role = (
            ID         => $Row[0],
            Name       => $Row[1],
            Commment   => $Row[2],
            ValidID    => $Row[3],
            CreateTime => $Row[4],
            CreateBy   => $Row[5],
            ChangeTime => $Row[6],
            ChangeBy   => $Row[7],
        );
    }
    
    # no data found...
    if ( !%Role ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Role with ID $Param{ID} not found!",
        );
        return;
    }
    
    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        TTL   => $Self->{CacheTTL},
        Key   => $CacheKey,
        Value => \%Role,
    ); 

    return %Role;
}

=item RoleAdd()

adds a new role

    my $RoleID = $RoleObject->RoleAdd(
        Name    => 'example-role',
        Comment => 'comment describing the role',   # optional
        ValidID => 1,
        UserID  => 123,
    );

=cut

sub RoleAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Name ValidID UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my %ExistingRoles = reverse $Self->RoleList( Valid => 0 );
    if ( defined $ExistingRoles{ $Param{Name} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "A Role with the name $Param{Name} already exists.",
        );
        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # insert
    return if !$DBObject->Do(
        SQL => 'INSERT INTO roles (name, comments, valid_id, '
            . 'create_time, create_by, change_time, change_by) '
            . 'VALUES (?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{Name}, \$Param{Comment}, \$Param{ValidID}, \$Param{UserID}, \$Param{UserID}
        ],
    );

    # get new group id
    my $RoleID;
    return if !$DBObject->Prepare(
        SQL  => 'SELECT id FROM roles WHERE name = ?',
        Bind => [ \$Param{Name}, ],
    );

    # fetch the result
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $RoleID = $Row[0];
    }

    # delete cache
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => $Self->{CacheType}
    );

    return $RoleID;
}

=item RoleUpdate()

update of a role

    my $Success = $RoleObject->RoleUpdate(
        ID      => 123,
        Name    => 'example-group',
        Comment => 'comment describing the role',   # optional
        ValidID => 1,
        UserID  => 123,
    );

=cut

sub RoleUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID Name ValidID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!",
            );
            return;
        }
    }

    my %ExistingRoles = reverse $Self->RoleList( Valid => 0 );
    if ( defined $ExistingRoles{ $Param{Name} } && $ExistingRoles{ $Param{Name} } != $Param{ID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "A Role with the name $Param{Name} already exists.",
        );
        return;
    }

    # set default value
    $Param{Comment} ||= '';

    # get current role data
    my %RoleData = $Self->RoleGet(
        ID => $Param{ID},
    );

    # check if update is required
    my $ChangeRequired;
    KEY:
    for my $Key (qw(Name Comment ValidID)) {

        next KEY if defined $RoleData{$Key} && $RoleData{$Key} eq $Param{$Key};

        $ChangeRequired = 1;

        last KEY;
    }

    return 1 if !$ChangeRequired;

    # update role in database
    return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL => 'UPDATE roles SET name = ?, comments = ?, valid_id = ?, '
            . 'change_time = current_timestamp, change_by = ? WHERE id = ?',
        Bind => [
            \$Param{Name}, \$Param{Comment}, \$Param{ValidID}, \$Param{UserID}, \$Param{ID}
        ],
    );

    # delete cache
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => $Self->{CacheType}
    );

    return 1;
}

=item RoleList()

returns a hash of all roles

    my %Roles = $RoleObject->RoleList(
        Valid => 1,
    );

the result looks like

    %Roles = (
        '1' => 'role_helpdesk_agent',
        '2' => 'role_systemsmanagement_agent',
        '3' => 'role_otrs_admin',
        '4' => 'role_faq_manager',
    );

=cut

sub RoleList {
    my ( $Self, %Param ) = @_;

    # set default value
    my $Valid = $Param{Valid} ? 1 : 0;

    # create cache key
    my $CacheKey = 'RoleList::' . $Valid;

    # read cache
    my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );
    return %{$Cache} if $Cache;

    my $SQL = 'SELECT id, name FROM roles';

    if ( $Param{Valid} ) {
        $SQL .= ' WHERE valid = 1'
    }

    return if !$Kernel::OM->Get('Kernel::System::DB')->Prepare( 
        SQL => $SQL,
    );

    my %Result;
    while ( my @Row = $Kernel::OM->Get('Kernel::System::DB')->FetchrowArray() ) {
        $Result{$Row[0]} = $Row[1];
    }

    # set cache
    $Kernel::OM->Get('Kernel::System::Cache')->Set(
        Type  => $Self->{CacheType},
        Key   => $CacheKey,
        Value => \%Result,
        TTL   => $Self->{CacheTTL},
    );

    return %Result;
}

=item RoleDelete()

delete a role

    my $Success = $RoleObject->RoleDelete(
        ID => 123,
    );

=cut

sub RoleDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(ID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # get database object
    return if !$Kernel::OM->Get('Kernel::System::DB')->Prepare(
        SQL  => 'DELETE FROM roles WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );
   
    # delete cache
    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
        Type => $Self->{CacheType}
    );

    return 1;

}

1;

=end Internal:




=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<http://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
COPYING for license information (AGPL). If you did not receive this file, see

<http://www.gnu.org/licenses/agpl.txt>.

=cut
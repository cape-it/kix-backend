# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Admin::Role::UpdatePermission;

use strict;
use warnings;

use base qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::System::Role',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Create a new role permission.');
    $Self->AddOption(
        Name        => 'role-name',
        Description => 'Name of the role.',
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'permission-id',
        Description => 'The ID of the permission to be updated.',
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'type',
        Description => 'The new type of the permission.',
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'target',
        Description => 'The new target of the permission.',
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'value',
        Description => 'The value of the new permission (CREATE,READ,UPDATE,DELETE,DENY). You can combine different values by using a comma and plus or minus sign to add or remove the permission, i.e. +READ,-UPDATE.',
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'required',
        Description => 'Set this permission as required. This only has effect when multiple attribute value permissions are defined for one object',
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/(yes|no)/smx,
    );
    $Self->AddOption(
        Name        => 'comment',
        Description => 'Comment for the new permission.',
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {

    my ( $Self, %Param ) = @_;

    $Self->{PermissionID} = $Self->GetOption('permission-id');
    $Self->{RoleName} = $Self->GetOption('role-name');
    $Self->{PermissionType} = $Self->GetOption('type');

    # check PermissionID
    my %Permission = $Kernel::OM->Get('Kernel::System::Role')->PermissionGet( ID => $Self->{PermissionID} );
    if ( !%Permission ) {
        die "Permission with ID $Self->{PermissionID} does not exist.\n";
    }
    $Self->{Permission} = \%Permission;

    # check role
    $Self->{RoleID} = $Kernel::OM->Get('Kernel::System::Role')->RoleLookup( Role => $Self->{RoleName} );
    if ( !$Self->{RoleID} ) {
        die "Role $Self->{RoleName} does not exist.\n";
    }

    # check if given PermissionID belongs to given role
    my %PermissionIDs = map {$_ => 1} $Kernel::OM->Get('Kernel::System::Role')->PermissionList(
        RoleID  => $Self->{RoleID},
        UserID  => 1,
    );
    if ( !$PermissionIDs{$Self->{PermissionID}} ) {
        die "Permission with ID $Self->{PermissionID} does not belong to role $Self->{RoleName}.\n";
    }

    # check permission type
    if ( $Self->{PermissionTypeID} ) {
        $Self->{PermissionTypeID} = $Kernel::OM->Get('Kernel::System::Role')->PermissionTypeLookup( Name => $Self->{PermissionType} );
        if ( !$Self->{PermissionTypeID} ) {
            die "Permission type $Self->{PermissionType} does not exist.\n";
        }
    }

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->Print("<yellow>Update permission $Self->{PermissionID} of role $Self->{RoleName}...</yellow>\n");

    my $Value = 0;
    if ( $Self->GetOption('value') ) {
        my $Mode = '';
        if ( $Self->GetOption('value') =~ /^\+/g ) {
            $Mode  = 'add';
            $Value = $Self->{Permission}->{Value};
        }
        elsif ( $Self->GetOption('value') =~ /^\-/g ) {
            $Mode = 'sub';
            $Value = $Self->{Permission}->{Value};
        }

        my %PossiblePermissions = %{Kernel::System::Role::Permission->PERMISSION};
        $PossiblePermissions{CRUD} = Kernel::System::Role::Permission->PERMISSION_CRUD;

        foreach my $Permission ( split(/\s*\,\s*/, $Self->GetOption('value') ) ) {            
            my $Mode = 'add';
            if ( $Permission =~ /^([+-])(.*?)$/g ) {
                $Mode = $1;
                $Permission = $2;
            }

            if ( $Mode eq '+' && ($Value & $PossiblePermissions{$Permission}) != $PossiblePermissions{$Permission} ) {
                $Value += $PossiblePermissions{$Permission};
            }
            elsif ( $Mode eq '-' && ($Value & $PossiblePermissions{$Permission}) == $PossiblePermissions{$Permission} ) {
                $Value -= $PossiblePermissions{$Permission};
            }
        }

        $Value = 0 if $Value < 0;
    }

    my $Result = $Kernel::OM->Get('Kernel::System::Role')->PermissionUpdate(
        ID         => $Self->{PermissionID},
        TypeID     => $Self->{PermissionTypeID} || $Self->{Permission}->{TypeID},
        Target     => $Self->GetOption('target') || $Self->{Permission}->{Target},
        Value      => defined $Self->GetOption('value') ? $Value : $Self->{Permission}->{Value},
        IsRequired => (defined $Self->GetOption('required') ? ($Self->GetOption('required') eq 'yes') : $Self->{Permission}->{IsRequired}) || 0,
        Comment    => defined $Self->GetOption('comment') ? $Self->GetOption('comment') : $Self->{Permission}->{Comment},
        UserID     => 1,
    );

    if ($Result) {
        $Self->Print("<green>Done</green>\n");
        return $Self->ExitCodeOk();
    }

    $Self->PrintError("Can't add permission");
    return $Self->ExitCodeError();
}

1;



=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<http://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
COPYING for license information (AGPL). If you did not receive this file, see

<http://www.gnu.org/licenses/agpl.txt>.

=cut
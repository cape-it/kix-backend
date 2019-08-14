# --
# Kernel/API/Operation/Notification/NotificationDelete.pm - API Notification Delete operation backend
# Copyright (C) 2006-2019 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/edited by:
# * Ricky(dot)Kaiser(at)cape(dash)it(dot)de
#
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::Notification::NotificationDelete;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(Kernel::API::Operation::V1::Common);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::Notification::NotificationDelete - API Notification Delete Operation backend

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::API::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {
            return $Self->_Error(
                Code    => 'Operation.InternalError',
                Message => "Got no $Needed!"
            );
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    return $Self;
}

=item ParameterDefinition()

define parameter preparation and check for this operation

    my $Result = $OperationObject->ParameterDefinition(
        Data => {
            ...
        },
    );

    $Result = {
        ...
    };

=cut

sub ParameterDefinition {
    my ( $Self, %Param ) = @_;

    return {
        'NotificationID' => {
            DataType => 'NUMERIC',
            Type     => 'ARRAY',
            Required => 1
        },
    };
}

=item Run()

perform NotificationDelete Operation. This will return the deleted NotificationID.

    my $Result = $OperationObject->Run(
        Data => {
            NotificationID => 1,
        },
    );

    $Result = {
        Message => '',                      # in case of error
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # start loop
    foreach my $NotificationID ( @{ $Param{Data}->{NotificationID} } ) {

        # check if Notification exists
        my %NotificationData = $Kernel::OM->Get('Kernel::System::NotificationEvent')->NotificationGet(
            ID => $NotificationID,
        );
        if ( !IsHashRefWithData(\%NotificationData) ) {
            return $Self->_Error(
                Code    => 'Object.NotFound',
            );
        }

        # delete Notification
        my $Success = $Kernel::OM->Get('Kernel::System::NotificationEvent')->NotificationDelete(
            ID     => $NotificationID,
            UserID => $Self->{Authorization}->{UserID}
        );

        if ( !$Success ) {
            return $Self->_Error(
                Code    => 'Object.UnableToDelete',
                Message => 'Could not delete Notification, please contact the system administrator',
            );
        }
    }

    # return result
    return $Self->_Success();
}

1;
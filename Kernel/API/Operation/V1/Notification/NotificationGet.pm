# --
# Kernel/API/Operation/V1/Notification/NotificationGet.pm - API Notification Get operation backend
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

package Kernel::API::Operation::V1::Notification::NotificationGet;

use strict;
use warnings;

use MIME::Base64;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsStringWithData);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::Notification::NotificationGet - API Notification Get Operation backend

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::API::Operation::V1::Notification::NotificationGet->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw(DebuggerObject WebserviceID)) {
        if ( !$Param{$Needed} ) {
            return $Self->_Error(
                Code    => 'Operation.InternalError',
                Message => "Got no $Needed!"
            );
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    # get config for this screen
    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('API::Operation::V1::Notification::NotificationGet');

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
            Type     => 'ARRAY',
            Required => 1
            }
    };
}

=item Run()

perform NotificationGet Operation. This function is able to return
one or more mail filter in one call.

    my $Result = $OperationObject->Run(
        Data => {
            NotificationID => 123       # comma separated in case of multiple or arrayref (depending on transport)
        },
    );

    $Result = {
        Success      => 1,                           # 0 or 1
        Code         => '',                          # In case of an error
        Message      => '',                          # In case of an error
        Data         => {
            Notification => [
                {
                    ...
                },
                {
                    ...
                },
            ]
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my @NotificationList;

    # start loop
    foreach my $NotificationID ( @{ $Param{Data}->{NotificationID} } ) {

        # get the Notification data
        my %NotificationData = $Kernel::OM->Get('Kernel::System::NotificationEvent')->NotificationGet( 
            ID => $NotificationID, 
        );

        if ( !IsHashRefWithData( \%NotificationData ) ) {
            return $Self->_Error( 
                Code => 'Object.NotFound',
            );
        }

        # add
        push( @NotificationList, \%NotificationData );
    }

    if ( scalar(@NotificationList) == 1 ) {
        return $Self->_Success( Notification => $NotificationList[0], );
    }

    # return result
    return $Self->_Success( Notification => \@NotificationList, );
}

1;
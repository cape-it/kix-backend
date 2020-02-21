# --
# Copyright (C) 2006-2020 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Operation::V1::SysConfig::SysConfigOptionDefinitionDelete;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::SysConfig::SysConfigOptionDefinitionDelete - API SysConfigOptionDefinitionDelete Operation backend

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
        'Option' => {
            DataType => 'STRING',
            Type     => 'ARRAY',
            Required => 1
        }                
    }
}

=item Run()

perform SysConfigOptionDefinitionDelete Operation. This will return nothing.

    my $Result = $OperationObject->Run(
        Data => {
            Option  => '...',
        },		
    );

    $Result = {
        Success    => 1,
        Code       => '',                       # in case of error    
        Message    => '',                       # in case of error
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;
 
    # start loop
    foreach my $Option ( @{$Param{Data}->{Option}} ) {

        # check if SysConfigOptionDefinition exists
        my $Exists = $Kernel::OM->Get('Kernel::System::SysConfig')->Exists(
            Name => $Option,
        );
        
        if ( !$Exists ) {
            return $Self->_Error(
                Code    => 'Object.NotFound',
                Message => "Cannot delete SysConfigOptionDefinition. SysConfigOptionDefinition '$Option' not found.",
            );
        }

        # delete SysConfigOptionDefinition	    
        my $Success = $Kernel::OM->Get('Kernel::System::SysConfig')->OptionDelete(
            Name    => $Option,
            UserID  => $Self->{Authorization}->{UserID},
        );

        if ( !$Success ) {
            return $Self->_Error(
                Code    => 'Object.UnableToDelete',
                Message => 'Could not delete SysConfigOptionDefinition, please contact the system administrator',
            );
        }
    }

    # return result
    return $Self->_Success();
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-GPL3 for license information (GPL3). If you did not receive this file, see

<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut

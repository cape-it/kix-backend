# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Operation::V1::TicketState::TicketStateUpdate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::TicketState::TicketStateUpdate - API TicketState Create Operation backend

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

    $Self->{Config} = $Kernel::OM->Get('Config')->Get('API::Operation::V1::TicketStateUpdate');

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
        'StateID' => {
            DataType => 'NUMERIC',
            Required => 1
        },                
        'TicketState' => {
            Type  => 'HASH',
            Required => 1
        },
        'TicketState::Name' => {
            Required => 1
        },
        'TicketState::TypeID' => {
            Required => 1
        },                                              
    }
}

=item Run()

perform TicketStateUpdate Operation. This will return the updated TicketStateID.

    my $Result = $OperationObject->Run(
        Data => {
        	StateID => '...',
        }        
    	TicketState => (
        	Name    => ''...',
        	ValidID => '...',
        	TypeID  => '...',
        	Comment => '...',        	        	
    	),
    );
    
    $Result = {
        Success      => 1,                  # 0 or 1
        Message      => '',                 # in case of error
        Data         => {                   # result data payload after Operation
            StateID  => '',                 #StateID 
            Error    => {                         # should not return errors
                    Code    => 'TicketState.Update.ErrorCode'
                    Message => 'Error Description'
            },
        },
    };
   
=cut


sub Run {
    my ( $Self, %Param ) = @_;

    # isolate and trim TicketState parameter
    my $TicketState = $Self->_Trim(
        Data => $Param{Data}->{TicketState},
    );
   
    my $StateID;
    
    # check if ticketState exists
    my %TicketStateData = $Kernel::OM->Get('State')->StateGet(
        ID => $Param{Data}->{StateID},
    );
    
    if ( !%TicketStateData ) {
        return $Self->_Error(
            Code => 'Object.NotFound',
        );
    }

    my $Success = $Kernel::OM->Get('State')->StateUpdate(
        %{$TicketState},    
        ID      => $Param{Data}->{StateID},
        UserID  => $Self->{Authorization}->{UserID},
    );

    if ( !$Success ) {
        return $Self->_Error(
            Code => 'Object.UnableToUpdate',
        );
    }
    
    # return result     
    return $Self->_Success(
        TicketStateID => $TicketStateData{ID},
    );    
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

# --
# Kernel/API/Operation/DynamicField/DynamicFieldDelete.pm - API DynamicField Delete operation backend
# Copyright (C) 2006-2016 c.a.p.e. IT GmbH, http://www.cape-it.de
#
# written/edited by:
# * Rene(dot)Boehm(at)cape(dash)it(dot)de
# 
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::API::Operation::V1::DynamicField::DynamicFieldDelete;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsString IsStringWithData);

use base qw(
    Kernel::API::Operation::V1::DynamicField::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::DynamicField::DynamicFieldDelete - API DynamicField DynamicFieldDelete Operation backend

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
        'DynamicFieldID' => {
            Type     => 'ARRAY',
            DataType => 'NUMERIC',
            Required => 1
        },           
    }
}

=item Run()

perform DynamicFieldDelete Operation. This will return the deleted DynamicFieldID.

    my $Result = $OperationObject->Run(
        Data => {
            DynamicFieldID  => '...',
        },		
    );

    $Result = {
        Message    => '',                      # in case of error
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;
        
    # start loop
    foreach my $DynamicFieldID ( @{$Param{Data}->{DynamicFieldID}} ) {

        # check if df is writeable
        my $DynamicFieldData = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
            ID   => $DynamicFieldID,
        );    
        if ( $DynamicFieldData->{InternalField} == 1 ) {
            return $Self->_Error(
                Code    => 'Forbidden',
                Message => "Can not delete DynamicField. DynamicField with ID '$Param{Data}->{DynamicFieldID}' is internal and cannot be deleted.",
            );        
        }

        # check if there is an object with this dynamic field
        foreach my $ValueType ( qw(Integer DateTime Text) ) {
            my $ExistingValues = $Kernel::OM->Get('Kernel::System::DynamicFieldValue')->HistoricalValueGet(
                FieldID   => $DynamicFieldID,
                ValueType => $ValueType,
            );
            if ( IsHashRefWithData($ExistingValues) ) {
                return $Self->_Error(
                    Code    => 'Object.DependingObjectExists',
                    Message => 'Cannot delete DynamicField. This DynamicField is used in at least one object.',
                );
            }
        }
        
        # delete DynamicField	    
        my $Success = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldDelete(
            ID      => $DynamicFieldID,
            UserID  => $Self->{Authorization}->{UserID},
        );

        if ( !$Success ) {
            return $Self->_Error(
                Code    => 'Object.UnableToDelete',
                Message => 'Could not delete DynamicField, please contact the system administrator',
            );
        }
    }

    # return result
    return $Self->_Success();
}

1;

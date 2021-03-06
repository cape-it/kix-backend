# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Operation::V1::DynamicField::DynamicFieldTypeSearch;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::DynamicField::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::DynamicField::DynamicFieldTypeSearch - API DynamicField Search Operation backend

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
    for my $Needed (qw(DebuggerObject WebserviceID)) {
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

=item Run()

perform DynamicFieldTypeSearch Operation. This will return a list of DynamicField FieldTypes.

    my $Result = $OperationObject->Run(
        Data => {
        }
    );

    $Result = {
        Success => 1,                                # 0 or 1
        Code    => '',                          # In case of an error
        Message => '',                          # In case of an error
        Data    => {
            DynamicFieldType => [
                { },
                { },
                ...
            ]
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $FieldTypeConfig = $Kernel::OM->Get('Config')->Get('DynamicFields::Driver');

    if ( !IsHashRefWithData($FieldTypeConfig) ) {
        return $Self->_Error(
            Code    => 'Operation.InternalError',
            Message => 'DynamicField::Driver config is not valid',
        );
    }

    my @FieldTypes;
    for my $FieldType ( sort keys %{$FieldTypeConfig} ) {
        push(@FieldTypes, {
            Name        => $FieldType,
            DisplayName => $FieldTypeConfig->{$FieldType}->{DisplayName},
        });
    }

    if ( scalar(@FieldTypes) == 1 ) {
        return $Self->_Success(
            DynamicFieldType => $FieldTypes[0],
        );    
    }

    # return result
    return $Self->_Success(
        DynamicFieldType => \@FieldTypes,
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

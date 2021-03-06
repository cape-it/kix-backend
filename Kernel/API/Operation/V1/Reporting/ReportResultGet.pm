# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Operation::V1::Reporting::ReportResultGet;

use strict;
use warnings;

use MIME::Base64;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::Reporting::ReportResultGet - API ReportResult Get Operation backend

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::API::Operation::V1::Reporting::ReportResultGet->new();

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
    $Self->{Config} = $Kernel::OM->Get('Config')->Get('API::Operation::V1::Reporting::ReportResultGet');

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
        'ReportID' => {
            DataType => 'NUMERIC',
            Required => 1
        },
        'ReportResultID' => {
            Type     => 'ARRAY',
            DataType => 'NUMERIC',
            Required => 1
        }
    }
}

=item Run()

perform ReportResultGet Operation. This function is able to return
one or more ReportResult entries in one call.

    my $Result = $OperationObject->Run(
        Data => {
            ReportResultID => 123       # comma separated in case of multiple or arrayref (depending on transport)
        },
    );

    $Result = {
        Success      => 1,                           # 0 or 1
        Code         => '',                          # In case of an error
        Message      => '',                          # In case of an error
        Data         => {
            ReportResult => [
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

    my @ReportResultList;

    # start loop
    foreach my $ReportResultID ( @{$Param{Data}->{ReportResultID}} ) {

        # get the ReportResult data
        my %ReportResultData = $Kernel::OM->Get('Reporting')->ReportResultGet(
            ID             => $ReportResultID,
            IncludeContent => $Param{Data}->{include}->{Content} ? 1 : 0,
        );

        if ( !%ReportResultData ) {
            return $Self->_Error(
                Code => 'Object.NotFound',
            );
        }

        if ( $Param{Data}->{include}->{Content} ) {
            # encode content base64
            $ReportResultData{Content} = MIME::Base64::encode_base64( $ReportResultData{Content} ),
        }

        # add
        push(@ReportResultList, \%ReportResultData);
    }

    if ( scalar(@ReportResultList) == 1 ) {
        return $Self->_Success(
            ReportResult => $ReportResultList[0],
        );    
    }

    # return result
    return $Self->_Success(
        ReportResult => \@ReportResultList,
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

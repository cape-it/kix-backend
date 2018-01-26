# --
# Kernel/API/Operation/StandardAttachment/StandardAttachmentSearch.pm - API StandardAttachment Search operation backend
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

package Kernel::API::Operation::V1::StandardAttachment::StandardAttachmentSearch;

use strict;
use warnings;

use Kernel::API::Operation::V1::StandardAttachment::StandardAttachmentGet;
use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::StandardAttachment::StandardAttachmentSearch - API StandardAttachment Search Operation backend

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

perform StandardAttachmentSearch Operation. This will return a StandardAttachment ID list.

    my $Result = $OperationObject->Run(
        Data => {
        }
    );

    $Result = {
        Success => 1,                                # 0 or 1
        Code    => '',                          # In case of an error
        Message => '',                          # In case of an error
        Data    => {
            StandardAttachment => [
                {},
                {}
            ]
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $Result = $Self->Init(
        WebserviceID => $Self->{WebserviceID},
    );

    if ( !$Result->{Success} ) {
        $Self->_Error(
            Code    => 'WebService.InvalidConfiguration',
            Message => $Result->{Message},
        );
    }

    # prepare data
    $Result = $Self->PrepareData(
        Data       => $Param{Data},
    );

    # check result
    if ( !$Result->{Success} ) {
        return $Self->_Error(
            Code    => 'Operation.PrepareDataError',
            Message => $Result->{Message},
        );
    }

    # perform StandardAttachment search
    my %StandardAttachmentList = $Kernel::OM->Get('Kernel::System::StdAttachment')->StdAttachmentList();

	# get already prepared StandardAttachment data from StandardAttachmentGet operation
    if ( IsHashRefWithData(\%StandardAttachmentList) ) {  	
        my $StandardAttachmentGetResult = $Self->ExecOperation(
            OperationType => 'V1::StandardAttachment::StandardAttachmentGet',
            Data      => {
                AttachmentID => join(',', sort keys %StandardAttachmentList),
            }
        );    

        if ( !IsHashRefWithData($StandardAttachmentGetResult) || !$StandardAttachmentGetResult->{Success} ) {
            return $StandardAttachmentGetResult;
        }

        my @StandardAttachmentDataList = IsArrayRefWithData($StandardAttachmentGetResult->{Data}->{StandardAttachment}) ? @{$StandardAttachmentGetResult->{Data}->{StandardAttachment}} : ( $StandardAttachmentGetResult->{Data}->{StandardAttachment} );

        if ( IsArrayRefWithData(\@StandardAttachmentDataList) ) {
            return $Self->_Success(
                StandardAttachment => \@StandardAttachmentDataList,
            )
        }
    }

    # return result
    return $Self->_Success(
        StandardAttachment => [],
    );
}

1;
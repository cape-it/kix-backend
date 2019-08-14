# --
# Kernel/API/Operation/V1/LogFile/LogFileGet.pm - API LogFile Get operation backend
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

package Kernel::API::Operation::V1::Log::LogFileGet;

use strict;
use warnings;

use MIME::Base64;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::Log::LogFileGet - API LogFile Get Operation backend

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
    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('API::Operation::V1::LogFile::LogFileGet');

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
        'LogFileID' => {
            Type     => 'ARRAY',
            Required => 1
        }                
    }
}

=item Run()

perform LogFileGet Operation. This function is able to return
one or more ticket entries in one call.

    my $Result = $OperationObject->Run(
        Data => {
            LogFileID => '....'       # comma separated in case of multiple or arrayref (depending on transport)
        },
    );

    $Result = {
        Success      => 1,                           # 0 or 1
        Code         => '',                          # In case of an error
        Message      => '',                          # In case of an error
        Data         => {
            LogFile => [
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

    my @LogFileList;

    # start loop
    foreach my $LogFileID ( @{$Param{Data}->{LogFileID}} ) {

        # get the LogFile data
        my %LogFileData = $Kernel::OM->Get('Kernel::System::LogFile')->LogFileGet(
            ID        => $LogFileID,
            NoContent => $Param{Data}->{include}->{Content} ? 0 : 1
        );

        if ( !%LogFileData ) {
            return $Self->_Error(
                Code => 'Object.NotFound',
            );
        }

        if ( $Param{Data}->{include}->{Content} ) {
            $LogFileData{Content} = MIME::Base64::encode_base64($LogFileData{Content}),
        }        
       
        # add
        push(@LogFileList, \%LogFileData);
    }

    if ( scalar(@LogFileList) == 1 ) {
        return $Self->_Success(
            LogFile => $LogFileList[0],
        );    
    }

    # return result
    return $Self->_Success(
        LogFile => \@LogFileList,
    );
}

1;
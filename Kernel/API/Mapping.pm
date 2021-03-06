# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Mapping;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

# prevent 'Used once' warning for Kernel::OM
use Kernel::System::ObjectManager;

use base qw(
    Kernel::API::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Mapping - API data mapping interface

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object.

    use Kernel::API::Debugger;
    use Kernel::API::Mapping;

    my $DebuggerObject = Kernel::API::Debugger->new(
        DebuggerConfig   => {
            DebugThreshold  => 'debug',
            TestMode        => 0,           # optional, in testing mode the data will not be written to the DB
            # ...
        },
        WebserviceID      => 12,
        CommunicationType => Requester, # Requester or Provider
        RemoteIP          => 192.168.1.1, # optional
    );
    my $MappingObject = Kernel::API::Mapping->new(
        DebuggerObject => $DebuggerObject,
        Invoker        => 'TicketLock',            # the name of the invoker in the web service
        InvokerType    => 'Nagios::TicketLock',    # the Invoker backend to use
        Operation      => 'TicketCreate',          # the name of the operation in the web service
        OperationType  => 'Ticket::TicketCreate',  # the local operation backend to use
        MappingConfig => {
            Type => 'MappingSimple',
            Config => {
                # ...
            },
        },
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed params
    for my $Needed (qw(DebuggerObject MappingConfig)) {
        if ( !$Param{$Needed} ) {

            return $Self->_Error(
                Code    => 'Mapping.InternalError',
                Message => "Got no $Needed!"
            );
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    # add optional params
    OPTIONAL:
    for my $Optional (qw(Invoker InvokerType Operation OperationType)) {
        next OPTIONAL if !$Param{$Optional};

        $Self->{$Optional} = $Param{$Optional};
    }

    # check config - we need at least a config type
    if ( !IsHashRefWithData( $Param{MappingConfig} ) ) {

        return $Self->_Error(
            Code    => 'Mapping.InternalError',
            Message => 'Got no MappingConfig as hash ref with content!',
        );
    }
    if ( !IsStringWithData( $Param{MappingConfig}->{Type} ) ) {

        return $Self->_Error(
            Code    => 'Mapping.InternalError',
            Message => 'Got no MappingConfig with Type as string with value!',
        );
    }

    # check config - if we have a map config, it has to be a non-empty hash ref
    if (
        defined $Param{MappingConfig}->{Config}
        && !IsHashRefWithData( $Param{MappingConfig}->{Config} )
        )
    {

        return $Self->_Error(
            Code    => 'Mapping.InvalidData',
            Message => 'Got MappingConfig with Data, but Data is no hash ref with content!',
        );
    }

    # load backend module
    my $BackendReg = $Kernel::OM->Get('Config')->Get('API::Mapping::Module');
    if ( !IsHashRefWithData($BackendReg) ) {
        return $Self->_Error(
            Code    => 'Transport.InternalError',            
            Message => "No backends found." 
        );
    }
    if ( !IsHashRefWithData($BackendReg->{$Self->{MappingConfig}->{Type}}) ) {
        return $Self->_Error(
            Code    => 'Transport.InternalError',            
            Message => "Backend $Self->{MappingConfig}->{Type} not found." 
        );
    }

    my $Backend = $BackendReg->{$Self->{MappingConfig}->{Type}}->{Module};    
    if ( !$Kernel::OM->Get('Main')->Require($Backend) ) {

        return $Self->_Error(
            Code    => 'Mapping.InternalError',
            Message => "Can't load module $Backend." 
        );
    }
    $Self->{BackendObject} = $Backend->new( %{$Self} );

    # pass back error message from backend if backend module could not be executed
    return $Self->{BackendObject} if ref $Self->{BackendObject} ne $Backend;

    return $Self;
}

=item Map()

perform data mapping in backend

    my $Result = $MappingObject->Map(
        Data => {              # data payload before mapping
            ...
        },
    );

    $Result = {
        Success         => 1,  # 0 or 1
        ErrorMessage    => '', # in case of error
        Data            => {   # data payload of after mapping
            ...
        },
    };

=cut

sub Map {
    my ( $Self, %Param ) = @_;

    # check data - only accept undef or hash ref
    if ( defined $Param{Data} && ref $Param{Data} ne 'HASH' ) {

        return $Self->_Error(
            Code    => 'Mapping.InvalidData',
            Message => 'Got Data but it is not a hash ref in Mapping handler!'
        );
    }

    # return if data is empty
    if ( !defined $Param{Data} || !%{ $Param{Data} } ) {

        return $Self->_Success(
            Data    => {},
        );
    }

    # start map on backend
    return $Self->{BackendObject}->Map(%Param);
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

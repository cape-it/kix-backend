# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::API::Operation::V1::Ticket::ArticleGet;

use strict;
use warnings;

use MIME::Base64;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::API::Operation::V1::Ticket::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::API::Operation::V1::Ticket::ArticleGet - API Ticket Get Operation backend

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::API::Operation::V1->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw(DebuggerObject WebserviceID)) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!",
            };
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
        'TicketID' => {
            Required => 1
        },
        'ArticleID' => {
            Type     => 'ARRAY',
            DataType => 'NUMERIC',
            Required => 1
        },
    }
}

=item Run()

perform ArticleGet Operation. This function is able to return
one or more ticket entries in one call.

    my $Result = $OperationObject->Run(
        Data => {
            TicketID             => '1',                                           # required
            ArticleID            => '32,33',                                       # required, could be comma separated IDs or an Array
            include              => '...',                                         # Optional, 0 as default. Include additional objects
                                                                                   # (supported: DynamicFields, Attachments)
            expand               => 0,                                             # Optional, 0 as default. Expand referenced objects
                                                                                   # (supported: Attachments)
        },
    );

    $Result = {
        Success      => 1,                                # 0 or 1
        Code         => '',                               # In case of an error
        Message      => '',                               # In case of an error
        Data         => {
            Article => [
                {
                    ArticleID
                    From
                    To
                    Cc
                    Subject
                    Body
                    ReplyTo
                    MessageID
                    InReplyTo
                    References
                    SenderType
                    SenderTypeID
                    ChannelID
                    ContentType
                    Charset
                    MimeType
                    IncomingTime

                    # If include=DynamicFields => 1 was passed, you'll get an entry like this for each dynamic field:
                    DynamicFields => [
                        {
                            Name  => 'some name',
                            Value => 'some value',
                        },
                    ],

                    # If include=Attachments => 1 was passed, you'll get an entry like this for each attachment:
                    Attachments => [
                        <AttachmentID>
                        # . . .
                    ]
                    # If include=Attachments => 1 AND expand=Attachments => 1 was passed, you'll get an entry like this for each attachment:
                    Attachments => [
                        {
                            AttachmentID       => 123
                            ContentAlternative => "",
                            ContentID          => "",
                            ContentType        => "application/pdf",
                            Filename           => "StdAttachment-Test1.pdf",
                            Filesize           => "4.6 KBytes",
                            FilesizeRaw        => 4722,
                        },
                        {
                            # . . .
                        },
                    ]
                },
                {
                    #. . .
                },
            ],
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Ticket');

    my @ArticleList;

    # start loop
    for my $ArticleID ( @{$Param{Data}->{ArticleID}} ) {

        my %ArticleRaw = $TicketObject->ArticleGet(
            ArticleID          => $ArticleID,
            DynamicFields      => $Param{Data}->{include}->{DynamicFields},
            UserID             => $Self->{Authorization}->{UserID},
        );

        # check if article exists
        if ( !%ArticleRaw ) {
            return $Self->_Error(
                Code => 'Object.NotFound',
            );
        }

        # check if article belongs to the given ticket
        if ( $ArticleRaw{TicketID} != $Param{Data}->{TicketID} ) {
            return $Self->_Error(
                Code => 'Object.NotFound',
            );
        }

        my %ArticleData;
        my @DynamicFields;

        # remove all dynamic fields from main article hash and set them into an array.
        ATTRIBUTE:
        for my $Attribute ( sort keys %ArticleRaw ) {

            if ( $Attribute =~ m{\A DynamicField_(.*) \z}msx ) {
                if ( $ArticleRaw{$Attribute} ) {
                    push @DynamicFields, {
                        Name  => $1,
                        Value => $ArticleRaw{$Attribute},
                    };
                }
                next ATTRIBUTE;
            }

            $ArticleData{$Attribute} = $ArticleRaw{$Attribute};
        }

        # add dynamic fields array into 'DynamicFields' hash key if included
        if ( $Param{Data}->{include}->{DynamicFields} ) {
            $ArticleData{DynamicFields} = \@DynamicFields;
        }

        # add flags array into 'Flags' hash key if included
        if ( $Param{Data}->{include}->{Flags} || $Param{Data}->{include}->{'Article.Flags'} ) {
            my %ArticleFlags = $TicketObject->ArticleFlagGet(
                ArticleID => $ArticleID,
                UserID    => $Self->{Authorization}->{UserID},
            );

            $ArticleData{Flags} = [ sort keys %ArticleFlags ];
        }

        if ( $Kernel::OM->Get('Queue')->NameExistsCheck(Name => $ArticleData{To}) ) {
            my %QueueInfo = $Kernel::OM->Get('Queue')->QueueGet(
                Name => $ArticleData{To},
            );

            my %QueueSystemeMailAddress = $Kernel::OM->Get('SystemAddress')->SystemAddressGet(
                ID => $QueueInfo{SystemAddressID},
            );

            $ArticleData{To} = $ArticleData{To} . ' <' . $QueueSystemeMailAddress{Name} . '>';
        }

        if ( $Param{Data}->{include}->{Plain} ) {
            my $PlainMessage = $TicketObject->ArticlePlain(
                ArticleID => $ArticleID,
                UserID    => $Self->{Authorization}->{UserID},
            ) || '';
            $ArticleData{Plain} = $PlainMessage;
        }

        # add
        push(@ArticleList, \%ArticleData);
    }

    if ( scalar(@ArticleList) == 1 ) {
        return $Self->_Success(
            Article => $ArticleList[0],
        );
    }

    return $Self->_Success(
        Article => \@ArticleList,
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

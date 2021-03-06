# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Installation::Migration::KIX17::Ticket::Ticket;

use strict;
use warnings;

use MIME::Base64;

use Kernel::System::EmailParser;
use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::System::AsynchronousExecutor
    Kernel::System::Installation::Migration::KIX17::Common
);

our @ObjectDependencies = (
    'Config',
    'DB',
    'Log',
);

=item Describe()

describe what is supported and what is required 

=cut

sub Describe {
    my ( $Self, %Param ) = @_;

    return {
        Supports => [
            'ticket'
        ],
        DependsOnType => [
            'customer_user',
            'customer_company',
            'ticket_history_type'
        ],
        Depends => {
            'change_by'           => 'users',
            'create_by'           => 'users',
            'user_id'             => 'users',
            'responsible_user_id' => 'users',
            'queue_id'            => 'queue',
            'ticket_priority_id'  => 'ticket_priority',
            'type_id'             => 'ticket_type',
            'ticket_state_id'     => 'ticket_state',
        },
    }
}

=item Run()

create a new item in the DB

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # only cache the following types in memory not redis 
    $Self->SetCacheOptions(
        ObjectType     => ['ticket', 'article', 'ticket_history', 'ticket_flag', 'article_flag', 'article_plain', 'article_attachment'],
        CacheInMemory  => 1,
        CacheInBackend => 0,
    );

    # disable the caching of type "Ticket"
    $Kernel::OM->Get('Cache')->{IgnoreTypes}->{Ticket} = 1;

    # get source data - only get the id, otherwise it's too much data
    my $SourceData = $Self->GetSourceData(Type => 'ticket', What => 'id', OrderBy => 'id');

    # bail out if we don't have something to todo
    return if !IsArrayRefWithData($SourceData);

    $Self->InitProgress(Type => $Param{Type}, ItemCount => scalar(@{$SourceData}));

    my $Result = $Self->_RunParallel(
        sub {
            my ( $Self, %Param ) = @_;
            my $Result;

            my $Item = $Param{Item};

            # check if this object is already mapped
            my $MappedID = $Self->GetOIDMapping(
                ObjectType     => 'ticket',
                SourceObjectID => $Item->{id},
                NoCache        => 1,        # don't cache this mass data
            );
            if ( $MappedID ) {
                return 'Ignored';
            }
            
            # get the ticket data
            $Item = $Self->GetSourceData(Type => 'ticket', Where => "id = $Item->{id}", NoProgress => 1);
            return if !IsArrayRefWithData($Item);
            $Item = $Item->[0];
            return if !IsHashRefWithData($Item);

            # check if this item already exists (i.e. some initial data)
            my $ID = $Self->Lookup(
                Table        => 'ticket',
                PrimaryKey   => 'id',
                Item         => $Item,
                RelevantAttr => [
                    'tn',
                    'title'
                ],
                NoCache => 1,        # don't cache this mass data
            );

            # insert row
            if ( !$ID ) {
                # check if this TN already exists - rare case but possible
                my $Exists = $Self->Lookup(
                    Table        => 'ticket',
                    PrimaryKey   => 'id',
                    Item         => $Item,
                    RelevantAttr => [
                        'tn',
                    ],
                    NoCache => 1,        # don't cache this mass data
                );
                if ( $Exists ) {
                    $Item->{tn} = 'Migration-'.$Item->{tn};
                }

                # assign the new organisation
                $Item->{organisation_id} = $Self->_AssignOrganisation(
                    Ticket => $Item
                );

                # assign the new contact
                $Item->{contact_id} = $Self->_AssignContact(
                    Ticket => $Item
                );

                $Item-> {type_id} = 1 if ! defined $Item-> {type_id};   # type fallback to Unclassified

                # separate insert method to support extensions in KIXPro, e.g. for SLA references
                $ID = $Self->_InsertTicket(
                    Ticket => $Item,
                );
            }

            if ( $ID ) {
                $Self->_MigrateTicketFlags(
                    TicketID       => $ID,
                    SourceTicketID => $Item->{id},
                );

                $Self->_MigrateArticles(
                    TicketID       => $ID,
                    SourceTicketID => $Item->{id},
                );

                $Self->_MigrateHistory(
                    TicketID       => $ID,
                    SourceTicketID => $Item->{id},
                );

                $Result = 'OK';
            }
            else {
                $Result = 'Error';
            }

            return $Result;
        },
        Items => $SourceData,
        %Param,
    );

   # trigger async rebuild of fulltext index
    $Self->AsyncCall(
        ObjectName               => $Kernel::OM->GetModuleFor('Ticket'),
        FunctionName             => 'TicketFulltextIndexRebuild',
        FunctionParams           => {},
        MaximumParallelInstances => 1,
    );

    return $Result;
}

sub _InsertTicket {
    my ( $Self, %Param ) = @_;

    # check needed params
    for my $Needed (qw(Ticket)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my %Ticket = %{$Param{Ticket}};

    # delete SLA ref (KIXPro feature)
    delete $Ticket{sla_id};

    my $ID = $Self->Insert(
        Table          => 'ticket',
        PrimaryKey     => 'id',
        Item           => \%Ticket,
        AutoPrimaryKey => 1,
    );

    return $ID;
}

sub _AssignOrganisation {
    my ( $Self, %Param ) = @_;

    # check needed params
    for my $Needed (qw(Ticket)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # do nothing of the ticket has no CustomerID
    return if !$Param{Ticket}->{customer_id};

    my $OrganisationObject = $Kernel::OM->Get('Organisation');

    # lookup organisation by ID
    my $OrgID = $Self->GetOIDMapping(
        ObjectType     => 'customer_company',
        SourceObjectID => $Param{Ticket}->{customer_id}
    );
    if ( !$OrgID ) {
        # organisation with that ID doesn't exist, lookup by number
        $OrgID = $OrganisationObject->OrganisationLookup(
            Number => $Param{Ticket}->{customer_id},
            Silent => 1,
        );
    }
    if ( !$OrgID ) {
        # organisation with that number doesn't exist, lookup by name
        my %OrgList = $OrganisationObject->OrganisationSearch(
            Name   => $Param{Ticket}->{customer_id},
        );
        if ( IsHashRefWithData(%OrgList) && scalar(keys %OrgList) == 1) {
            $OrgID = (keys %OrgList)[0];
        }
    }

    if ( !$OrgID ) {
        # we still don't have an organisation -> create a new one
        $OrgID = $OrganisationObject->OrganisationAdd(
            Number => $Param{Ticket}->{customer_id},
            Name   => $Param{Ticket}->{customer_id},
            UserID => 1,
        );
    }


    return $OrgID; 
}

sub _AssignContact {
    my ( $Self, %Param ) = @_;

    # check needed params
    for my $Needed (qw(Ticket)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $ContactObject = $Kernel::OM->Get('Contact');

    # lookup contact
    my @ContactIDs = $ContactObject->ContactSearch(
        LoginEquals => $Param{Ticket}->{customer_user_id},
    );
    my $ContactID = IsArrayRefWithData(\@ContactIDs) ? $ContactIDs[0] : undef;

    if ( !$ContactID ) {
        # we don't have a contact -> create a new one
        if ( !$Self->{ParserObject} ) {
            $Self->{ParserObject} = Kernel::System::EmailParser->new(
                Mode => 'Standalone',
            );
        }
        my $ContactEmail = $Self->{ParserObject}->GetEmailAddress(
            Email => $Param{Ticket}->{customer_user_id},
        );
        my $ContactEmailRealname = $Self->{ParserObject}->GetRealname(
            Email => $Param{Ticket}->{customer_user_id},
        );

        if ( !$ContactEmail && !$ContactEmailRealname ) {
            return;
        }

        my @NameChunks = split(' ', $ContactEmailRealname);
        $ContactID = $ContactObject->ContactLookup(
            Email  => $ContactEmail,
            Silent => 1,
        );

        if ( !$ContactID ) {
            # create a new contact
            $ContactID = $ContactObject->ContactAdd(
                Firstname             => (@NameChunks) ? $NameChunks[0] : $ContactEmail,
                Lastname              => (@NameChunks) ? join(" ", splice(@NameChunks, 1)) : $ContactEmail,
                Email                 => $ContactEmail,
                PrimaryOrganisationID => $Param{Ticket}->{organisation_id},
                ValidID               => 1,
                UserID                => 1
            );
        }
    }

    return $ContactID;
}

sub _MigrateArticles {
    my ( $Self, %Param ) = @_;
    my %Result;

    # check needed params
    for my $Needed (qw(TicketID SourceTicketID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # get source data
    my $SourceData = $Self->GetSourceData(
        Type       => 'article', 
        Where      => "ticket_id = $Param{SourceTicketID}", 
        OrderBy    => 'id',
        References => {
            'ticket_id' => 'ticket',
            'create_by' => 'users',
            'change_by' => 'users',
        },
        NoProgress => 1,
    );

    # bail out if we don't have something to todo
    return %Result if !IsArrayRefWithData($SourceData);

    if ( !$Self->{ArticleTypes} ) {
        my $ArticleTypesData = $Self->GetSourceData( Type => 'article_type', NoProgress => 1 );
        $Self->{ArticleTypes} = { map { $_->{id} => $_->{name} } @{$ArticleTypesData} }; 
    }

    if ( !$Self->{Channels} ) {
        my %ChannelList = $Kernel::OM->Get('Channel')->ChannelList();
        $Self->{Channels} = { reverse %ChannelList }; 
    }

    foreach my $Item ( @{$SourceData} ) {

        # check if this object is already mapped
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => 'article',
            SourceObjectID => $Item->{id}
        );
        next if $MappedID;

        # check if this item already exists (i.e. some initial data)
        my $ID = $Self->Lookup(
            Table        => 'article',
            PrimaryKey   => 'id',
            Item         => $Item,
            RelevantAttr => [
                'id',
                'ticket_id',
            ]
        );

        # insert row
        if ( !$ID ) {
            # migrate article type to channel and customer visible
            $Item->{channel_id} = $Self->{Channels}->{note};
            if ( $Self->{ArticleTypes}->{$Item->{article_type_id}} =~ /^email-/ ) {
                $Item->{channel_id} = $Self->{Channels}->{email};
            }

            $Item->{customer_visible} = 1;
            if ( $Self->{ArticleTypes}->{$Item->{article_type_id}} =~ /^.*?-(int|report)/ ) {
                $Item->{customer_visible} = 0;
            }

            $ID = $Self->Insert(
                Table          => 'article',
                PrimaryKey     => 'id',
                Item           => $Item,
                AutoPrimaryKey => 1,
            );

            $Self->_MigrateArticleFlags(
                %Param,
                ArticleID       => $ID,
                SourceArticleID => $Item->{id}
            );

            $Self->_MigrateAttachments(
                %Param,
                ArticleID       => $ID,
                SourceArticleID => $Item->{id}
            );
        }

        if ( $ID ) {
            $Result{OK}++;
        }
        else {
            $Result{Error}++;
        }
    }

    return %Result;
}

sub _MigrateAttachments {
    my ( $Self, %Param ) = @_;

    # check needed params
    for my $Needed (qw(TicketID SourceTicketID ArticleID SourceArticleID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # migrate article attachments
    my $Attachments = $Self->GetSourceData(
        Type       => 'article_attachment', 
        ObjectID   => $Param{SourceArticleID},
        NoProgress => 1
    );

    my $TicketObject = $Kernel::OM->Get('Ticket');

    foreach my $Attachment ( @{$Attachments} ) {
        my $Result = $TicketObject->ArticleWriteAttachment(
            %{$Attachment},
            Content   => MIME::Base64::decode_base64($Attachment->{Content}),
            ArticleID => $Param{ArticleID},
            UserID    => 1,
        );
        if ( !$Result ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Can't write attachment \"$Attachment->{Filename}\" of article $Param{ArticleID}!"
            );
        }
    }

    # get plain atttachments
    my $Plain = $Self->GetSourceData(
        Type       => 'article_plain', 
        ObjectID   => $Param{SourceArticleID},
        NoProgress => 1
    );
    if ( IsHashRefWithData($Plain) ) {
        $Plain->{Content} = MIME::Base64::decode_base64($Plain->{Content});
    
        my $Result = $TicketObject->ArticleWritePlain(
            ArticleID => $Param{ArticleID},
            Email     => $Plain->{Content},
            UserID    => 1,
        );
        if ( !$Result ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Can't write plain body of article $Param{ArticleID}!"
            );
        }
    }

    return 1;
}

sub _MigrateArticleFlags {
    my ( $Self, %Param ) = @_;
    my %Result;

    # check needed params
    for my $Needed (qw(ArticleID SourceArticleID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # get source data
    my $SourceData = $Self->GetSourceData(
        Type       => 'article_flag', 
        Where      => "article_id = $Param{SourceArticleID}", 
        References => {
            'article_id' => 'article',
            'create_by'  => 'users',
        },
        NoProgress => 1,
    );

    # bail out if we don't have something to todo
    return %Result if !IsArrayRefWithData($SourceData);

    foreach my $Item ( @{$SourceData} ) {

        # check if this object is already mapped
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => 'article_flag',
            SourceObjectID => $Param{SourceArticleID} . '::' . $Item->{article_key} . '::' . $Item->{'create_by::raw'}
        );
        next if $MappedID;

        # check if this item already exists (i.e. some initial data)
        my $ID = $Self->Lookup(
            Table        => 'article_flag',
            PrimaryKey   => 'id',
            Item         => $Item,
            RelevantAttr => [
                'article_id',
                'article_key',
                'create_by'
            ]
        );

        # insert row
        if ( !$ID ) {
            $ID = $Self->Insert(
                Table          => 'article_flag',
                PrimaryKey     => 'id',
                Item           => $Item,
                AutoPrimaryKey => 1,
                SourceObjectID => $Param{SourceArticleID} . '::' . $Item->{article_key} . '::' . $Item->{'create_by::raw'}
            );
        }

        if ( $ID ) {
            $Result{OK}++;
        }
        else {
            $Result{Error}++;
        }
    }

    return %Result;
}

sub _MigrateTicketFlags {
    my ( $Self, %Param ) = @_;
    my %Result;

    # check needed params
    for my $Needed (qw(TicketID SourceTicketID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # get source data
    my $SourceData = $Self->GetSourceData(
        Type       => 'ticket_flag', 
        Where      => "ticket_id = $Param{SourceTicketID}", 
        References => {
            'ticket_id' => 'ticket',
            'create_by' => 'users',
        },
        NoProgress => 1,
    );

    # bail out if we don't have something to todo
    return %Result if !IsArrayRefWithData($SourceData);

    foreach my $Item ( @{$SourceData} ) {

        # check if this object is already mapped
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => 'ticket_flag',
            SourceObjectID => $Param{SourceTicketID} . '::' . $Item->{ticket_key} . '::' . $Item->{'create_by::raw'}
        );
        next if $MappedID;

        # check if this item already exists (i.e. some initial data)
        my $ID = $Self->Lookup(
            Table        => 'ticket_flag',
            PrimaryKey   => 'id',
            Item         => $Item,
            RelevantAttr => [
                'ticket_id',
                'ticket_key',
                'create_by'
            ]
        );

        # insert row
        if ( !$ID ) {
            $ID = $Self->Insert(
                Table          => 'ticket_flag',
                PrimaryKey     => 'id',
                Item           => $Item,
                AutoPrimaryKey => 1,
                SourceObjectID => $Param{SourceTicketID} . '::' . $Item->{ticket_key} . '::' . $Item->{'create_by::raw'}
            );
        }

        if ( $ID ) {
            $Result{OK}++;
        }
        else {
            $Result{Error}++;
        }
    }

    return %Result;
}

sub _MigrateHistory {
    my ( $Self, %Param ) = @_;
    my %Result;

    # check needed params
    for my $Needed (qw(TicketID SourceTicketID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    # get source data
    my $SourceData = $Self->GetSourceData(
        Type       => 'ticket_history', 
        Where      => "ticket_id = $Param{SourceTicketID}", 
        OrderBy    => 'id',
        References => {
            'ticket_id'       => 'ticket',
            'article_id'      => 'article',
            'queue_id'        => 'queue',
            'type_id'         => 'ticket_type',
            'owner_id'        => 'users',
            'priority_id'     => 'ticket_priority',
            'state_id'        => 'ticket_state',
            'history_type_id' => 'ticket_history_type',
            'create_by'       => 'users',
            'change_by'       => 'users'
        },
        NoProgress => 1
    );

    # bail out if we don't have something to todo
    return %Result if !IsArrayRefWithData($SourceData);

    foreach my $Item ( @{$SourceData} ) {

        # check if this object is already mapped
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => 'ticket_history',
            SourceObjectID => $Item->{id}
        );
        next if $MappedID;

        # check if this item already exists (i.e. some initial data)
        my $ID = $Self->Lookup(
            Table        => 'ticket_history',
            PrimaryKey   => 'id',
            Item         => $Item,
            RelevantAttr => [
                'ticket_id',
                'article_id',
                'create_by',
                'create_time'
            ]
        );

        # insert row
        if ( !$ID ) {
            $Item-> {type_id} = 1 if ! defined $Item-> {type_id};   # type fallback to Unclassified

            $ID = $Self->Insert(
                Table          => 'ticket_history',
                PrimaryKey     => 'id',
                Item           => $Item,
                AutoPrimaryKey => 1,
            );
        }

        if ( $ID ) {
            $Result{OK}++;
        }
        else {
            $Result{Error}++;
        }
    }

    return %Result;
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

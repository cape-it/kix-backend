# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Ticket::Event::TicketAutoLinkConfigItem;

use strict;
use warnings;

our @ObjectDependencies = (
    'Config',
    'Log',
    'Ticket',
    'User',
    'GeneralCatalog',
    'ITSMConfigItem',
    'LinkObject',
);

use vars qw($VERSION);
$VERSION = qw($Revision$) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{ConfigObject}         = $Kernel::OM->Get('Config');
    $Self->{LogObject}            = $Kernel::OM->Get('Log');
    $Self->{TicketObject}         = $Kernel::OM->Get('Ticket');
    $Self->{UserObject}           = $Kernel::OM->Get('User');
    $Self->{GeneralCatalogObject} = $Kernel::OM->Get('GeneralCatalog');
    $Self->{ConfigItemObject}     = $Kernel::OM->Get('ITSMConfigItem');
    $Self->{LinkObject}           = $Kernel::OM->Get('LinkObject');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check required stuff...
    foreach (qw(Event Config)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}
                ->Log( Priority => 'error', Message => "TicketAutoLinkConfigItem: Need $_!" );
            return;
        }
    }
    if ( !$Param{Data}->{TicketID} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Need TicketID!"
        );
        return;
    }

    my $CISearchPatternRef =
        $Self->{ConfigObject}->Get('TicketAutoLinkConfigItem::CISearchPattern');

    my $OnlyFirstArticle =
        $Self->{ConfigObject}->Get('TicketAutoLinkConfigItem::FirstArticleOnly');

    #    my $SearchInClassesRef =
    #        $Self->{ConfigObject}->Get('TicketAutoLinkConfigItem::CISearchInClasses');
    my $SearchInClassesRefTemp =
        $Self->{ConfigObject}->Get('TicketAutoLinkConfigItem::CISearchInClasses');

    my $SearchInClassesRef;
    for my $Key ( %{$SearchInClassesRefTemp} ) {
        if ( $SearchInClassesRefTemp->{$Key} ) {
            $SearchInClassesRef->{$Key} = $SearchInClassesRefTemp->{$Key};
        }
    }

    my $SearchInClassesPerRecipientRef =
        $Self->{ConfigObject}->Get('TicketAutoLinkConfigItem::CISearchInClassesPerRecipient');

    # only lower case...
    for my $Key ( %{$SearchInClassesPerRecipientRef} ) {
        if ( $SearchInClassesPerRecipientRef->{$Key} ) {
            $SearchInClassesPerRecipientRef->{ lc($Key) } = $SearchInClassesPerRecipientRef->{$Key};
        }
    }

    my $LinkType =
        $Self->{ConfigObject}->Get('TicketAutoLinkConfigItem::LinkType')
        || 'RelevantTo';

    # get article data, if required...
    my %ArticleData = ();
    if ( $Param{Event} eq 'ArticleCreate' && $Param{ArticleID} ) {
        %ArticleData = $Self->{TicketObject}->ArticleGet(
            ArticleID => $Param{Data}->{ArticleID},
            UserID    => 1,
        );

        # check if it's the first article...
        if ($OnlyFirstArticle) {
            my %FirstArticleData = $Self->{TicketObject}->ArticleFirstArticle(
                TicketID => $Param{Data}->{TicketID},
                UserID   => 1,
            );

            return 0
                if (
                !$FirstArticleData{ArticleID}
                || $FirstArticleData{ArticleID} != $Param{Data}->{ArticleID}
                );
        }

    }
    elsif ( $Param{Event} eq 'ArticleCreate' && !$Param{Data}->{ArticleID} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "TicketAutoLinkConfigItem: event ArticleCreate requires ArticleID!"
        );
        return;
    }
    else {

        #use the last article...
        my @ArticleIDs = $Self->{TicketObject}->ArticleIndex(
            TicketID => $Param{Data}->{TicketID},
            UserID   => 1,
        );

        if (@ArticleIDs) {
            %ArticleData = $Self->{TicketObject}->ArticleGet(
                ArticleID => $ArticleIDs[-1],
                UserID    => 1,
            );
        }
    }

    my $SearchPatternRegExp = '';
    my $SearchInIndex       = 0;
    my $SearchIn            = '';
    my @SearchStrings       = ();

    #---------------------------------------------------------------------------
    # ArticleCreate
    if ( $Param{Event} eq 'ArticleCreate' ) {
        for my $Key ( keys %{$CISearchPatternRef} ) {
            my $SearchString = '';
            if ( $Key =~ /(Article_)(.*)/ ) {
                $SearchIn = $2;
                $SearchIn =~ s/_OR\d*//g;
                $SearchPatternRegExp = $CISearchPatternRef->{$Key} || '';
                if (
                    $SearchPatternRegExp
                    && $ArticleData{$SearchIn} =~ /$SearchPatternRegExp/m
                    )
                {
                    $SearchString = $1;
                    $SearchString =~ s/^\s+//g;
                    $SearchString =~ s/\s+$//g;
                    push( @SearchStrings, $SearchString );
                }
            }
        }
    }

    #---------------------------------------------------------------------------
    #TicketDynamicFieldUpdate
    elsif ( $Param{Event} =~ /TicketDynamicFieldUpdate_/ ) {

        # get ticket data...
        my $EventTrigger = $Param{Event};
        $EventTrigger =~ s/TicketDynamicFieldUpdate_//g;

        my %TicketData = $Self->{TicketObject}->TicketGet(
            TicketID      => $Param{Data}->{TicketID},
            UserID        => 1,
            DynamicFields => 1,
        );

        for my $Key ( keys( %{$CISearchPatternRef} ) ) {

            next if !$TicketData{$Key};

            my $ConfiguredDynamicField = $Key;
            $ConfiguredDynamicField =~ s/DynamicField_//g;
            next if ( $ConfiguredDynamicField ne $EventTrigger );
            my $SearchString = '';
            $Key =~ s/_OR\d$//g;

            #            if ( $TicketData{$Key} ) { #&& $Key =~ /(TicketFreeText)(\d+)/ ) {
            #$SearchInIndex = $2;
            $SearchPatternRegExp = $CISearchPatternRef->{$Key} || '';

            if (
                $SearchPatternRegExp

                #&& $TicketData{ 'TicketFreeText' . $SearchInIndex }
                && $TicketData{$Key}
                =~ /.*($SearchPatternRegExp).*/
                )
            {
                $SearchString = $1;
                $SearchString =~ s/^\s+//g;
                $SearchString =~ s/\s+$//g;
                push( @SearchStrings, $SearchString );
            }

            #            }
        }
    }

    return 0 if ( !scalar @SearchStrings );

    #---------------------------------------------------------------------------
    # limit search classes if restricted to-address...
    if ( keys %{$SearchInClassesPerRecipientRef} ) {
        my $ToAddress = lc( $ArticleData{To} || '' );
        $ToAddress =~ s/(.*<|>.*)//g;
        if ( $ToAddress && $SearchInClassesPerRecipientRef->{$ToAddress} ) {
            my @AllowedSearchClasses = split( ',', $SearchInClassesPerRecipientRef->{$ToAddress} );
            for my $CIClass ( keys %{$SearchInClassesRef} ) {
                if ( $SearchInClassesPerRecipientRef->{$ToAddress} !~ /(^|.*,\s+)$CIClass(,.*|$)/ )
                {
                    delete( $SearchInClassesRef->{$CIClass} );
                }
            }
        }
    }

    #---------------------------------------------------------------------------
    # perform CMDB search and link results...
    for my $CIClass ( keys %{$SearchInClassesRef} ) {
        if ( $SearchInClassesRef->{$CIClass} ) {
            my $SearchAttributeKeyList = $SearchInClassesRef->{$CIClass} || '';
            my $ClassItemRef = $Self->{GeneralCatalogObject}->ItemGet(
                Class => 'ITSM::ConfigItem::Class',
                Name  => $CIClass,
            ) || 0;

            if ( ref($ClassItemRef) eq 'HASH' && $ClassItemRef->{ItemID} ) {

                # get CI-class definition...
                my $XMLDefinition = $Self->{ConfigItemObject}->DefinitionGet(
                    ClassID => $ClassItemRef->{ItemID},
                );

                if ( !$XMLDefinition->{DefinitionID} ) {
                    $Self->{LogObject}->Log(
                        Priority => 'error',
                        Message =>
                            "TicketAutoLinkConfigItem: no definition found for class $CIClass!",
                    );
                }

                for my $SearchAttributeKey ( split( ',', $SearchAttributeKeyList ) ) {
                    $SearchAttributeKey =~ s/^\s+//g;
                    $SearchAttributeKey =~ s/\s+$//g;
                    next if ( !$SearchAttributeKey );
                    for my $CurrSearchString (@SearchStrings) {
                        my %SearchParams = ();
                        my %SearchData   = ();

                        # get search attributes
                        for my $AttributeValue (qw(Number Name)) {
                            next if $AttributeValue ne $SearchAttributeKey;
                            $SearchParams{$AttributeValue} = $CurrSearchString;
                        }

                        for my $AttributeArray (qw(DeplStateIDs InciStateIDs)) {
                            next if $AttributeArray ne $SearchAttributeKey;
                            $SearchParams{$AttributeArray} = [$CurrSearchString];
                        }

                        # build search params...
                        $SearchData{$SearchAttributeKey} = $CurrSearchString;

                        my @SearchParamsWhat;
                        $Self->_ExportXMLSearchDataPrepare(
                            XMLDefinition => $XMLDefinition->{DefinitionRef},
                            What          => \@SearchParamsWhat,
                            SearchData    => \%SearchData,
                        );

                        # build search hash...
                        if (@SearchParamsWhat) {
                            $SearchParams{What} = \@SearchParamsWhat;
                        }

                        # only search if something to search for...
                        if ( scalar( keys(%SearchParams) ) ) {
                            my $ConfigItemList =
                                $Self->{ConfigItemObject}->ConfigItemSearchExtended(
                                %SearchParams,
                                ClassIDs => [ $ClassItemRef->{ItemID} ],
                                UserID   => 1,
                                );

                            # link found ITSMConfigItem with current ticket
                            for my $ConfigItemID ( @{$ConfigItemList} ) {
                                $Self->{LinkObject}->LinkAdd(
                                    SourceObject => 'Ticket',
                                    SourceKey    => $Param{Data}->{TicketID},
                                    TargetObject => 'ConfigItem',
                                    TargetKey    => $ConfigItemID,
                                    Type         => $LinkType,
                                    UserID       => 1,
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    #---------------------------------------------------------------------------

    return 1;
}

=item _ExportXMLSearchDataPrepare()

recusion function to prepare the export XML search params

    $ObjectBackend->_ExportXMLSearchDataPrepare(
        XMLDefinition => $ArrayRef,
        What          => $ArrayRef,
        SearchData    => $HashRef,
    );

=cut

sub _ExportXMLSearchDataPrepare {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{XMLDefinition};
    return if !$Param{What};
    return if !$Param{SearchData};
    return if ref $Param{XMLDefinition} ne 'ARRAY';
    return if ref $Param{What} ne 'ARRAY';
    return if ref $Param{SearchData} ne 'HASH';

    ITEM:
    for my $Item ( @{ $Param{XMLDefinition} } ) {

        # create key
        my $Key = $Param{Prefix} ? $Param{Prefix} . '::' . $Item->{Key} : $Item->{Key};

        # prepare value
        my $Values = $Self->{ConfigItemObject}->XMLExportSearchValuePrepare(
            Item  => $Item,
            Value => $Param{SearchData}->{$Key},
        );

        if ($Values) {

            # create search key
            my $SearchKey = $Key;
            $SearchKey =~ s{ :: }{\'\}[%]\{\'}xmsg;

            # create search hash
            my $SearchHash = {
                '[1]{\'Version\'}[1]{\'' . $SearchKey . '\'}[%]{\'Content\'}' => $Values,
            };

            push @{ $Param{What} }, $SearchHash;
        }

        next ITEM if !$Item->{Sub};

        # start recursion, if "Sub" was found
        $Self->_ExportXMLSearchDataPrepare(
            XMLDefinition => $Item->{Sub},
            What          => $Param{What},
            SearchData    => $Param{SearchData},
            Prefix        => $Key,
        );
    }

    return 1;
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

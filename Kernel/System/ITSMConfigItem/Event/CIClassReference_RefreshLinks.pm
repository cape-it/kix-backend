# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::ITSMConfigItem::Event::CIClassReference_RefreshLinks;

use strict;
use warnings;

our @ObjectDependencies = (
    'ITSMConfigItem',
    'LinkObject',
    'Log'
);

sub new {
    my ( $Type, %Param ) = @_;

    #allocate new hash for object...
    my $Self = {};
    bless( $Self, $Type );

    $Self->{ConfigItemObject} = $Kernel::OM->Get('ITSMConfigItem');
    $Self->{LinkObject}       = $Kernel::OM->Get('LinkObject');
    $Self->{LogObject}        = $Kernel::OM->Get('Log');

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    #check required stuff...
    foreach (qw(Event Data)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Event::CIClassReference_RefreshLinks: Need $_!"
            );
            return;
        }
    }
    $Param{ConfigItemID} = $Param{Data}->{ConfigItemID};
    if ( !$Param{ConfigItemID} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Event::CIClassReference_RefreshLinks: No ConfigItemID in Data!"
        );
        return;
    }

    #get config item...
    my $ConfigItemRef = $Self->{ConfigItemObject}->ConfigItemGet(
        ConfigItemID => $Param{ConfigItemID},
    );
    return if ( !$ConfigItemRef || ref($ConfigItemRef) ne 'HASH' );

    #check if there is a version at all...
    my $VersionListRef = $Self->{ConfigItemObject}->VersionList(
        ConfigItemID => $Param{ConfigItemID},
    );
    return if ( !$VersionListRef->[0] );

    # get the the new version (that is being created)...
    # new links should be added for this version's attributes
    my $NewVersionData = $Self->{ConfigItemObject}->VersionGet(
        ConfigItemID => $Param{ConfigItemID},
    );
    return if ( !$NewVersionData || ref($NewVersionData) ne 'HASH' );

    # get the old version
    # old links should be deleted for this version's attributes
    my $OldVersionData = ();
    if ( $VersionListRef->[-2] ) {
        $OldVersionData = $Self->{ConfigItemObject}->VersionGet(
            VersionID => $VersionListRef->[-2],
        );
    }

    #---------------------------------------------------------------------------
    # get hash with all attribute-keys, referenced CI-classes,
    # corresponding link types and -directions from CI-class definition...

    my %RelAttrNewVersion = ();
    my %RelAttrOldVersion = ();
    my $XMLDefinition = $Self->{ConfigItemObject}->DefinitionGet(
        ClassID => $NewVersionData->{ClassID},
    );

    # _CreateCIReferencesHash() returns a hash with attributes of Type CICLassREference;
    # for non-empty attributes there are values for
    # $RelAttr{Key}->{ReferencedCIClassLinkType}
    # $RelAttr{Key}->{ReferencedCIClassLinkDirection}
    # Example:
#              'PartOfProject' => [
#                               {
#                                 'ReferencedCIClassLinkType' => 'PartOf',
#                                 'ReferencedCIClassLinkDirection' => '',
#                               }
#                             ]
    # relelvant attributes for the old version
    %RelAttrNewVersion = $Self->_CreateCIReferencesHash(
        XMLData       => $NewVersionData->{XMLData}->[1]->{Version}->[1],
        XMLDefinition => $XMLDefinition->{DefinitionRef},
    );
    # relelvant attributes for the new version
    %RelAttrOldVersion = $Self->_CreateCIReferencesHash(
        XMLData       => $OldVersionData->{XMLData}->[1]->{Version}->[1],
        XMLDefinition => $XMLDefinition->{DefinitionRef},
    );

    my $CIReferenceAttrDataRef = \();

    #---------------------------------------------------------------------------
    # update ConfigItem-links...
    if ( $NewVersionData && $XMLDefinition && %RelAttrNewVersion ) {

        #-----------------------------------------------------------------------
        #  delete links most likely created from previous version of this attribute...
        if ( $OldVersionData && %RelAttrOldVersion ) {
            for my $CurrKeyname ( keys(%RelAttrOldVersion) ) {

                next if ( !$RelAttrOldVersion{$CurrKeyname}->[0]->{ReferencedCIClassLinkType} );

                my $LastLinkType
                    = $RelAttrOldVersion{$CurrKeyname}->[0]->{ReferencedCIClassLinkType};

                # NOTE: result looks like {<$CurrKeyname> => [ <CIID1>, <CIID2>, ...]}
                $CIReferenceAttrDataRef = $Self->_GetAttributeDataByKey(
                    XMLData       => $OldVersionData->{XMLData}->[1]->{Version}->[1],
                    XMLDefinition => $XMLDefinition->{DefinitionRef},
                    KeyName       => $CurrKeyname,
                    Content => 1,    #need the CI-ID, not the shown value
                );

                if (
                    $CIReferenceAttrDataRef->{$CurrKeyname}
                    && ref( $CIReferenceAttrDataRef->{$CurrKeyname} ) eq 'ARRAY'
                    )
                {
                    for my $CurrPrevPartnerID ( @{ $CIReferenceAttrDataRef->{$CurrKeyname} } ) {
                        $Self->{LinkObject}->LinkDelete(
                            Object1 => 'ConfigItem',
                            Key1    => $Param{ConfigItemID},
                            Object2 => 'ConfigItem',
                            Key2    => $CurrPrevPartnerID,
                            Type    => $LastLinkType,
                            UserID  => 1,
                        );
                    }
                }
            }    #EO for my $CurrKeyname ( keys( %RelAttrOldVersion ))
        }

        #-----------------------------------------------------------------------
        #  create new linkes for attributes if the new version
        for my $CurrKeyname ( keys(%RelAttrNewVersion) ) {

            $CIReferenceAttrDataRef = $Self->_GetAttributeDataByKey(
                XMLData       => $NewVersionData->{XMLData}->[1]->{Version}->[1],
                XMLDefinition => $XMLDefinition->{DefinitionRef},
                KeyName       => $CurrKeyname,
                Content => 1,    #need the CI-ID, not the shown value
            );

            #-----------------------------------------------------------------------
            # create all links from available data...
            for my $SearchResult ( keys(%{$CIReferenceAttrDataRef}) ) {

                my @ReferenceCIIDs = @{ $CIReferenceAttrDataRef->{$SearchResult} };
                for my $CurrCIReferenceID (@ReferenceCIIDs) {

                    #create link between this CI and current CIReference-attribute...
                    if ( $CurrCIReferenceID && $Param{ConfigItemID} ) {

                        if (
                            $RelAttrNewVersion{$CurrKeyname}->[0]
                            ->{ReferencedCIClassLinkDirection}
                            && $RelAttrNewVersion{$CurrKeyname}->[0]
                            ->{ReferencedCIClassLinkDirection} eq 'Reverse'
                            )
                        {
                            $Self->{LinkObject}->LinkAdd(
                                SourceObject => 'ConfigItem',
                                SourceKey    => $CurrCIReferenceID,
                                TargetObject => 'ConfigItem',
                                TargetKey    => $Param{ConfigItemID},
                                Type         => $RelAttrNewVersion{$CurrKeyname}->[0]
                                    ->{ReferencedCIClassLinkType},
                                UserID => 1,
                            );

                        }
                        else {
                            $Self->{LinkObject}->LinkAdd(
                                TargetObject => 'ConfigItem',
                                TargetKey    => $CurrCIReferenceID,
                                SourceObject => 'ConfigItem',
                                SourceKey    => $Param{ConfigItemID},
                                Type         => $RelAttrNewVersion{$CurrKeyname}->[0]
                                    ->{ReferencedCIClassLinkType},
                                UserID => 1,
                            );
                        }

                    }    #EO if( $CurrCIReferenceID && $Param{ConfigItemID})

                }    #EO for my $CurrCIReferenceID( @ReferenceCIIDs )

            }    #EO foreach my $SearchResult ( keys( %{$CIReferenceAttrDataRef}))

        }    #EO for my $CurrKeyname ( keys( %RelAttrNewVersion ))

    }    #EO if ( $NewVersionData && $XMLDefinition && %RelAttrNewVersion)
    return;
}

sub _CreateCIReferencesHash {
    my ( $Self, %Param ) = @_;

    # check required params...
    if (
        ( !$Param{XMLData} )
        || ( !$Param{XMLDefinition} )
        || ( ref $Param{XMLData} ne 'HASH' )
        || ( ref $Param{XMLDefinition} ne 'ARRAY' )
        )
    {
        return;
    }

    my $CIRelAttr = $Self->{ConfigItemObject}->GetAttributeDataByType(
        XMLData       => $Param{XMLData},
        XMLDefinition => $Param{XMLDefinition},
        AttributeType => 'CIClassReference',
    );

    my %SumRelAttr = ();
    for my $Key ( keys %{$CIRelAttr} ) {

        my %RetHash = ();
        ITEM:
        for my $Item ( @{ $Param{XMLDefinition} } ) {

            COUNTER:
            for my $Counter ( 1 .. $Item->{CountMax} ) {
                if ( $Item->{Key} eq $Key ) {
                    for my $ParamRef (
                        qw(ReferencedCIClassLinkType ReferencedCIClassLinkDirection)
                        )
                    {
                        $RetHash{$ParamRef} = $Item->{Input}->{$ParamRef};
                    }
                }
                next COUNTER if !$Item->{Sub};

                # sub items in definitions
                if ( $Item->{Sub} ) {
                    %SumRelAttr = (
                        %SumRelAttr,
                        $Self->_CreateCIReferencesHash(
                            XMLDefinition => $Item->{Sub},
                            XMLData       => $Param{XMLData}->{ $Item->{Key} }->[$Counter],
                        )
                    );
                }
            }
        }
        push @{ $SumRelAttr{$Key} }, \%RetHash;

    }
    return %SumRelAttr;
}

=item _GetAttributeDataByKey()

    Returns a hashref with names and attribute values from the
    XML-DataHash for a specified data type.

    $ConfigItemObject->GetAttributeDataByKey(
        XMLData       => $XMLData,
        XMLDefinition => $XMLDefinition,
        KeyName => $Key,
    );

=cut

sub _GetAttributeDataByKey {
    my ( $Self, %Param ) = @_;

    my %Result;

    if ( $Param{Content} ) {
        my $CurrContent = $Self->{ConfigItemObject}->GetAttributeContentsByKey(
            KeyName       => $Param{KeyName},
            XMLData       => $Param{XMLData},
            XMLDefinition => $Param{XMLDefinition},
            );
        $Result{ $Param{KeyName} } = $CurrContent;
    }
    else {
        my $CurrVal = $Self->{ConfigItemObject}->GetAttributeValuesByKey(
            KeyName       => $Param{KeyName},
            XMLData       => $Param{XMLData},
            XMLDefinition => $Param{XMLDefinition},
            );
        $Result{ $Param{KeyName} } = $CurrVal;
    }
    return \%Result;

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

# --
# Copyright (C) 2006-2020 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Installation::Migration::KIX17::Asset::Item;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
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
            'configitem'
        ],
        DependsOnType => [
            'configitem_definition',
        ],
        Depends => {
            'change_by'         => 'users',
            'create_by'         => 'users',
            'class_id'          => 'general_catalog',
            'cur_depl_state_id' => 'general_catalog',
            'cur_inci_state_id' => 'general_catalog',
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
        ObjectType     => ['configitem', 'configitem_history', 'configitem_version', 'xml_storage'],
        CacheInMemory  => 1,
        CacheInBackend => 0,
    );

    # get source data
    my $SourceData = $Self->GetSourceData(Type => 'configitem', OrderBy => 'id');

    # bail out if we don't have something to todo
    return if !IsArrayRefWithData($SourceData);

    $Self->InitProgress(Type => $Param{Type}, ItemCount => scalar(@{$SourceData}));

    return $Self->_RunParallel(
        sub {
            my ( $Self, %Param ) = @_;
            my $Result;

            my $Item = $Param{Item};

            # check if this object is already mapped
            my $MappedID = $Self->GetOIDMapping(
                ObjectType     => 'configitem',
                SourceObjectID => $Item->{id},
            );
            if ( $MappedID ) {
                return 'Ignored';
            }

            # check if this item already exists (i.e. some initial data)
            my $ID = $Self->Lookup(
                Table        => 'configitem',
                PrimaryKey   => 'id',
                Item         => $Item,
                RelevantAttr => [
                    'configitem_number',
                    'class_id',
                ],
            );

            # insert row
            if ( !$ID ) {
                # remove reference to last version to prevent ring dependency
                delete $Item->{last_version_id};

                $ID = $Self->Insert(
                    Table          => 'configitem',
                    PrimaryKey     => 'id',
                    Item           => $Item,
                    AutoPrimaryKey => 1,
                );
            }

            if ( $ID ) {
                $Result = 'OK';

                my $SourceClassID = $Self->GetOIDMapping(
                    ObjectType => 'general_catalog',
                    ObjectID   => $Item->{class_id}
                );

                $Self->_MigrateHistory(
                    AssetID       => $ID,
                    SourceAssetID => $Item->{id},
                );
                $Self->_MigrateVersions(
                    AssetID       => $ID,
                    ClassID       => $Item->{class_id},
                    SourceAssetID => $Item->{id},
                    SourceClassID => $SourceClassID,
                );

                # update corresponding CIs
                return $Result if !$Kernel::OM->Get('DB')->Do(
                    SQL   => 'UPDATE configitem ci SET last_version_id = (SELECT MAX(id) FROM configitem_version WHERE configitem_id = ci.id), name = (SELECT name FROM configitem_version WHERE configitem_id = ci.id ORDER BY id DESC LIMIT 1) WHERE id = ' . $ID,
                );
            }
            else {
                $Result = 'Error';
            }

            return $Result;
        },
        Items => $SourceData,
        %Param,
    );
}

sub _MigrateHistory {
    my ( $Self, %Param ) = @_;
    my %Result;

    # check needed params
    for my $Needed (qw(AssetID SourceAssetID)) {
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
        Type => 'configitem_history', 
        Where => "configitem_id = $Param{SourceAssetID}", 
        OrderBy => 'id',
        References => {
            'configitem_id' => 'configitem',
            'create_by'     => 'users',
        },
        NoProgress => 1
    );

    # bail out if we don't have something to todo
    return %Result if !IsArrayRefWithData($SourceData);

    foreach my $Item ( @{$SourceData} ) {

        # check if this object is already mapped
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => 'configitem_history',
            SourceObjectID => $Item->{id}
        );
        next if $MappedID;

        # set new AssetID
        $Item->{configitem_id} = $Param{AssetID};

        # check if this item already exists (i.e. some initial data)
        my $ID = $Self->Lookup(
            Table        => 'configitem_history',
            PrimaryKey   => 'id',
            Item         => $Item,
            RelevantAttr => [
                'type_id',
                'configitem_id',
                'create_time'
            ]
        );

        # insert row
        if ( !$ID ) {
            $ID = $Self->Insert(
                Table          => 'configitem_history',
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

sub _MigrateVersions {
    my ( $Self, %Param ) = @_;
    my %Result;

    # check needed params
    for my $Needed (qw(AssetID ClassID SourceAssetID SourceClassID)) {
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
        Type       => 'configitem_version', 
        Where      => "configitem_id = $Param{SourceAssetID}", 
        OrderBy    => 'id',
        References => {
            'configitem_id' => 'configitem',
            'definition_id' => 'configitem_definition',
            'depl_state_id' => 'general_catalog',
            'inci_state_id' => 'general_catalog',
            'create_by'     => 'users',
        },
        NoProgress => 1
    );

    # bail out if we don't have something to todo
    return %Result if !IsArrayRefWithData($SourceData);

    foreach my $Item ( @{$SourceData} ) {

        # check if this object is already mapped
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => 'configitem_version',
            SourceObjectID => $Item->{id}
        );
        next if $MappedID;

        # check if this item already exists (i.e. some initial data)
        my $ID = $Self->Lookup(
            Table        => 'configitem_version',
            PrimaryKey   => 'id',
            Item         => $Item,
            RelevantAttr => [
                'name',
                'configitem_id',
                'id'
            ]
        );

        # insert row
        if ( !$ID ) {
            # remove all attributes we can't handle
            foreach my $Attr ( qw(name_lower ci_class_id ci_configitem_number ci_create_time ci_create_by is_last_version) ) {
                delete $Item->{$Attr};
            }

            $ID = $Self->Insert(
                Table          => 'configitem_version',
                PrimaryKey     => 'id',
                Item           => $Item,
                AutoPrimaryKey => 1,
            );

            $Self->_MigrateXMLData(
                %Param,
                VersionID       => $ID,
                SourceVersionID => $Item->{id},
                DefinitionID    => $Item->{definition_id},
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

sub _MigrateXMLData {
    my ( $Self, %Param ) = @_;
    my %Result;

    # check needed params
    for my $Needed (qw(SourceAssetID ClassID SourceClassID VersionID SourceVersionID DefinitionID)) {
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
        Type       => 'configitem_xmldata', 
        ObjectID   => $Param{SourceVersionID},
        NoProgress => 1
    );

    # bail out if we don't have something to todo
    return %Result if !IsArrayRefWithData($SourceData);

    # fake CI attachments as additional items
    my $CIAttachments = $Self->GetSourceData(
        Type       => 'configitem_attachment', 
        ObjectID   => $Param{SourceAssetID},
        NoProgress => 1
    );

    if ( IsArrayRefWithData($CIAttachments) ) {
        my $BackendObject = $Kernel::OM->Get('ITSMConfigItem::XML::Type::Attachment');
        my $Index = 1;
        foreach my $Attachment ( @{$CIAttachments} ) {
            my $AttachmentDirID = $BackendObject->InternalValuePrepare(
                Value => $Attachment,
            );
            push @{$SourceData}, {
                'xml_type'          => "ITSM::ConfigItem::$Param{SourceClassID}",
                'xml_key'           => $Param{SourceVersionID},
                'xml_content_key'   => "[1]{Version}[1]{CIAttachments}[$Index]{TagKey}",
                'xml_content_value' => "[1]{Version}[1]{CIAttachments}[$Index]",
            };
            push @{$SourceData}, {
                'xml_type'          => "ITSM::ConfigItem::$Param{SourceClassID}",
                'xml_key'           => $Param{SourceVersionID},
                'xml_content_key'   => "[1]{Version}[1]{CIAttachments}[$Index]{Content}",
                'xml_content_value' => $AttachmentDirID,
            };
            $Index++;
        }
    }

    foreach my $Item ( @{$SourceData} ) {

        # check if this object is already mapped
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => 'xml_storage',
            SourceObjectID => $Item->{xml_type} . '::' . $Item->{xml_key} . '::' . $Item->{xml_content_key}
        );
        next if $MappedID;

        # set new AssetID
        $Item->{xml_type} = "ITSM::ConfigItem::$Param{ClassID}";
        $Item->{xml_key}  = $Param{VersionID};

        # check if this item already exists (i.e. some initial data)
        my $ID = $Self->Lookup(
            Table        => 'xml_storage',
            PrimaryKey   => 'id',
            Item         => $Item,
            RelevantAttr => [
                'xml_type',
                'xml_key',
                'xml_content_key'
            ]
        );

        # insert row
        if ( !$ID ) {
            # map value if needed
            $Self->_MapAttributeValue(Item => $Item, DefinitionID => $Param{DefinitionID});

            my $ID = $Self->Insert(
                Table          => 'xml_storage',
                PrimaryKey     => 'id',
                Item           => $Item,
                SourceObjectID => $Item->{xml_type} . '::' . $Item->{xml_key} . '::' . $Item->{xml_content_key},
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

sub _MapAttributeValue {
    my ( $Self, %Param ) = @_;

    my %TypeLookupMapping = (
        'CIACCustomerCompany' => 'customer_company',
        'CIClassReference'    => 'configitem',
        'CustomerCompany'     => 'customer_company',
        'Customer'            => 'customer_user',
        'CustomerUserCompany' => 'customer_company',
        'GeneralCatalog'      => 'general_catalog',
    );

    # check needed params
    for my $Needed (qw(Item DefinitionID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
            return;
        }
    }

    my $Key = $Param{Item}->{xml_content_key};
    $Key =~ s/[\']//g;
    $Key =~ s/\[.*?\]//g;
    return 1 if $Key !~ /{Content}$/;
    return 1 if !$Param{Item}->{xml_content_value};

    if ( !$Self->{DefinitionFlatHash}->{$Param{DefinitionID}} ) {
        my $Definition = $Kernel::OM->Get('ITSMConfigItem')->DefinitionGet(
            DefinitionID => $Param{DefinitionID},
        );
        $Self->{DefinitionFlatHash}->{$Param{DefinitionID}} = $Self->_CreateDefinitionFlatHash(
            Definition => $Definition->{DefinitionRef},
        );
    }

    # prepare key
    my @PreparedKeyParts;
    while ( $Key ) {
        if ( $Key =~ /^{(.*?)}(.*?)$/ ) {
            $Key = $2;
            next if $1 =~ /Content|Version/;
            push @PreparedKeyParts, $1;
        }
    }
    my $PreparedKey = join('.', @PreparedKeyParts);
    return 1 if !$PreparedKey;
    return 1 if !$Self->{DefinitionFlatHash}->{$Param{DefinitionID}}->{$PreparedKey};
    
    my $TypeMapping = $TypeLookupMapping{$Self->{DefinitionFlatHash}->{$Param{DefinitionID}}->{$PreparedKey}};
    if ( $TypeMapping ) {
        my $MappedID = $Self->GetOIDMapping(
            ObjectType     => $TypeMapping,
            SourceObjectID => $Param{Item}->{xml_content_value},
        );
        if ( $MappedID ) {
            $Param{Item}->{xml_content_value} = $MappedID,
        }
    }

    return 1;
}

sub _CreateDefinitionFlatHash {
    my ( $Self, %Param ) = @_;
    my %Result;

    return if !$Param{Definition} || !IsArrayRefWithData($Param{Definition});

    foreach my $Attr ( @{$Param{Definition}} ) {
        my $Key = $Param{ParentKey} ? $Param{ParentKey}.'.'.$Attr->{Key} : $Attr->{Key};

        $Result{$Key} = $Attr->{Input}->{Type}; 
        if ( IsArrayRefWithData($Attr->{Sub}) ) {
            my $SubResult = $Self->_CreateDefinitionFlatHash(
                Definition => $Attr->{Sub},
                ParentKey  => $Key,
            );
            %Result = (
                %Result,
                %{$SubResult},
            );
        }
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
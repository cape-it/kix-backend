# --
# Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-GPL3 for license information (GPL3). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::Organisation::DB;

use strict;
use warnings;

our @ObjectDependencies = (
    'Cache',
    'DB',
    'Log',
    'Valid',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get customer company map
    $Self->{OrganisationMap} = $Param{OrganisationMap} || die "Got no OrganisationMap!";

    # config options
    $Self->{OrganisationTable} = $Self->{OrganisationMap}->{Params}->{Table}
        || die "Need Organisation->Params->Table in Kernel/Config.pm!";
    $Self->{OrganisationKey} = $Self->{OrganisationMap}->{OrganisationKey}
        || die "Need Organisation->OrganisationKey in Kernel/Config.pm!";
    $Self->{OrganisationValid} = $Self->{OrganisationMap}->{'OrganisationValid'};
    $Self->{SearchListLimit}      = $Self->{OrganisationMap}->{'OrganisationSearchListLimit'} || 0;
    $Self->{SearchPrefix}         = $Self->{OrganisationMap}->{'OrganisationSearchPrefix'};
    if ( !defined( $Self->{SearchPrefix} ) ) {
        $Self->{SearchPrefix} = '';
    }
    $Self->{SearchSuffix} = $Self->{OrganisationMap}->{'OrganisationSearchSuffix'};
    if ( !defined( $Self->{SearchSuffix} ) ) {
        $Self->{SearchSuffix} = '*';
    }

    # create cache object, but only if CacheTTL is set in customer config
    if ( $Self->{OrganisationMap}->{CacheTTL} ) {
        $Self->{CacheObject} = $Kernel::OM->Get('Cache');
        $Self->{CacheType}   = 'Organisation' . $Param{Count};
        $Self->{CacheTTL}    = $Self->{OrganisationMap}->{CacheTTL} || 0;
    }

    # get database object
    $Self->{DBObject} = $Kernel::OM->Get('DB');

    # create new db connect if DSN is given
    if ( $Self->{OrganisationMap}->{Params}->{DSN} ) {
        $Self->{DBObject} = Kernel::System::DB->new(
            DatabaseDSN  => $Self->{OrganisationMap}->{Params}->{DSN},
            DatabaseUser => $Self->{OrganisationMap}->{Params}->{User},
            DatabasePw   => $Self->{OrganisationMap}->{Params}->{Password},
            Type         => $Self->{OrganisationMap}->{Params}->{Type} || '',
        ) || die('Can\'t connect to database!');

        # remember that we have the DBObject not from parent call
        $Self->{NotParentDBObject} = 1;
    }

    # this setting specifies if the table has the create_time,
    # create_by, change_time and change_by fields of KIX
    $Self->{ForeignDB} = $Self->{OrganisationMap}->{Params}->{ForeignDB} ? 1 : 0;

    # defines if the database search will be performend case sensitive (1) or not (0)
    $Self->{CaseSensitive} = $Self->{OrganisationMap}->{Params}->{SearchCaseSensitive}
        // $Self->{OrganisationMap}->{Params}->{CaseSensitive} || 0;

    return $Self;
}

sub OrganisationSearch {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    my $Valid = 1;
    if ( !$Param{Valid} && defined( $Param{Valid} ) ) {
        $Valid = 0;
    }

    my $Limit = $Param{Limit} // $Self->{SearchListLimit};

    my $CacheType;
    my $CacheKey;

    # check cache
    if ( $Self->{CacheObject} ) {

        $CacheType = $Self->{CacheType} . '_OrganisationSearch';
        $CacheKey = "OrganisationSearch::${Valid}::${Limit}::" . ( $Param{Search} || '' );

        my $Data = $Self->{CacheObject}->Get(
            Type => $CacheType,
            Key  => $CacheKey,
        );
        return %{$Data} if ref $Data eq 'HASH';
    }

    # what is the result
    my $What;
    if ($Self->{OrganisationMap}->{OrganisationSearchFields}) {
        $What = join(
            ', ',
            @{ $Self->{OrganisationMap}->{OrganisationSearchFields} }
        );
    }
    else {
        $What = 'customer_id, name';
    }

    # add valid option if required
    my $SQL;
    my @Bind;

    if ($Valid) {

        # get valid object
        my $ValidObject = $Kernel::OM->Get('Valid');

        $SQL
            .= "$Self->{OrganisationValid} IN ( ${\(join ', ', $ValidObject->ValidIDsGet())} )";
    }

    # where
    if ( $Param{Search} ) {

        my @Parts = split /\+/, $Param{Search}, 6;
        for my $Part (@Parts) {
            $Part = $Self->{SearchPrefix} . $Part . $Self->{SearchSuffix};
            $Part =~ s/\*/%/g;
            $Part =~ s/%%/%/g;

            if ( defined $SQL ) {
                $SQL .= " AND ";
            }

            my $OrganisationSearchFields = $Self->{OrganisationMap}->{OrganisationSearchFields};

            if ( $OrganisationSearchFields && ref $OrganisationSearchFields eq 'ARRAY' ) {

                my @SQLParts;
                for my $Field ( @{$OrganisationSearchFields} ) {
                    if ( $Self->{CaseSensitive} ) {
                        push @SQLParts, "$Field LIKE ?";
                        push @Bind,     \$Part;
                    }
                    else {
                        push @SQLParts, "LOWER($Field) LIKE LOWER(?)";
                        push @Bind,     \$Part;
                    }
                }
                if (@SQLParts) {
                    $SQL .= join( ' OR ', @SQLParts );
                }
            }
        }
    }

    # sql
    my $CompleteSQL = "SELECT $Self->{OrganisationKey}, $What FROM $Self->{OrganisationTable}";
    $CompleteSQL .= $SQL ? " WHERE $SQL" : '';

    # ask database
    $Self->{DBObject}->Prepare(
        SQL   => $CompleteSQL,
        Bind  => \@Bind,
        Limit => $Limit,
    );

    # fetch the result
    my %List;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {

        my $OrganisationID = shift @Row;
        $List{$OrganisationID} = join( ' ', map { defined($_) ? $_ : '' } @Row );
    }

    # cache request
    if ( $Self->{CacheObject} ) {
        $Self->{CacheObject}->Set(
            Type  => $CacheType,
            Key   => $CacheKey,
            Value => \%List,
            TTL   => $Self->{CacheTTL},
        );
    }

    return %List;
}

sub OrganisationGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{CustomerID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need CustomerID!'
        );
        return;
    }

    # check cache
    if ( $Self->{CacheObject} ) {
        my $Data = $Self->{CacheObject}->Get(
            Type => $Self->{CacheType},
            Key  => "OrganisationGet::$Param{CustomerID}",
        );
        return %{$Data} if ref $Data eq 'HASH';
    }

    # build select
    my @Fields;
    my %FieldsMap;
    for my $Entry ( @{ $Self->{OrganisationMap}->{Map} } ) {
        push @Fields, $Entry->{MappedTo};
        $FieldsMap{ $Entry->{MappedTo} } = $Entry->{Attribute};
    }
    my $SQL = 'SELECT ' . join( ', ', @Fields );

    if ( !$Self->{ForeignDB} ) {
        $SQL .= ", create_time, create_by, change_time, change_by";
    }

    # this seems to be legacy, if Name is passed it should take precedence over CustomerID
    my $CustomerID = $Param{Name} || $Param{CustomerID};

    $SQL .= " FROM $Self->{OrganisationTable} WHERE ";

    if ( $Self->{CaseSensitive} ) {
        $SQL .= "$Self->{OrganisationKey} = ?";
    }
    else {
        $SQL .= "LOWER($Self->{OrganisationKey}) = LOWER( ? )";
    }

    # get initial data
    return if !$Self->{DBObject}->Prepare(
        SQL  => $SQL,
        Bind => [ \$CustomerID ]
    );

    # fetch the result
    my %Data;
    ROW:
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {

        my $MapCounter = 0;

        for my $Field (@Fields) {
            $Data{ $FieldsMap{$Field} } = $Row[$MapCounter];
            $MapCounter++;
        }

        next ROW if $Self->{ForeignDB};

        for my $Key (qw(CreateTime CreateBy ChangeTime ChangeBy)) {
            $Data{$Key} = $Row[$MapCounter];
            $MapCounter++;
        }
    }

    # cache request
    if ( $Self->{CacheObject} ) {
        $Self->{CacheObject}->Set(
            Type  => $Self->{CacheType},
            Key   => "OrganisationGet::$Param{CustomerID}",
            Value => \%Data,
            TTL   => $Self->{CacheTTL},
        );
    }

    # return data
    return (%Data);
}

sub OrganisationAdd {
    my ( $Self, %Param ) = @_;

    # check ro/rw
    if ( $Self->{ReadOnly} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Organisation backend is read only!'
        );
        return;
    }

    my @Fields;
    my @Placeholders;
    my @Values;

    for my $Entry ( @{ $Self->{OrganisationMap}->{Map} } ) {
        push @Fields,       $Entry->{MappedTo};
        push @Placeholders, '?';
        push @Values,       \$Param{ $Entry->{Attribute} };
    }
    if ( !$Self->{ForeignDB} ) {
        push @Fields,       qw(create_time create_by change_time change_by);
        push @Placeholders, qw(current_timestamp ? current_timestamp ?);
        push @Values, ( \$Param{UserID}, \$Param{UserID} );
    }

    # build insert
    my $SQL = "INSERT INTO $Self->{OrganisationTable} (";
    $SQL .= join( ', ', @Fields ) . " ) VALUES ( " . join( ', ', @Placeholders ) . " )";

    return if !$Self->{DBObject}->Do(
        SQL  => $SQL,
        Bind => \@Values,
    );

    # log notice
    $Kernel::OM->Get('Log')->Log(
        Priority => 'info',
        Message =>
            "Organisation: '$Param{OrganisationName}/$Param{CustomerID}' created successfully ($Param{UserID})!",
    );

    $Self->_OrganisationCacheClear( CustomerID => $Param{CustomerID} );

    return $Param{CustomerID};
}

sub OrganisationUpdate {
    my ( $Self, %Param ) = @_;

    # check ro/rw
    if ( $Self->{ReadOnly} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Customer backend is read only!'
        );
        return;
    }

    # check needed stuff
    for my $Entry ( @{ $Self->{OrganisationMap}->{Map} } ) {
        if ( !$Param{ $Entry->{Attribute} } && $Entry->{Required} && $Entry->{Attribute} ne 'UserPassword' ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Entry->{Attribute}!"
            );
            return;
        }
    }

    my @Fields;
    my @Values;

    FIELD:
    for my $Entry ( @{ $Self->{OrganisationMap}->{Map} } ) {
        next FIELD if $Entry->{Attribute} =~ /^UserPassword$/i;
        push @Fields, $Entry->{MappedTo} . ' = ?';
        push @Values, \$Param{ $Entry->{Attribute} };
    }
    if ( !$Self->{ForeignDB} ) {
        push @Fields, ( 'change_time = current_timestamp', 'change_by = ?' );
        push @Values, \$Param{UserID};
    }

    # create SQL statement
    my $SQL = "UPDATE $Self->{OrganisationTable} SET ";
    $SQL .= join( ', ', @Fields );

    if ( $Self->{CaseSensitive} ) {
        $SQL .= " WHERE $Self->{OrganisationKey} = ?";
    }
    else {
        $SQL .= " WHERE LOWER($Self->{OrganisationKey}) = LOWER( ? )";
    }
    push @Values, \$Param{OrganisationID};

    return if !$Self->{DBObject}->Do(
        SQL  => $SQL,
        Bind => \@Values,
    );

    # log notice
    $Kernel::OM->Get('Log')->Log(
        Priority => 'info',
        Message =>
            "Organisation: '$Param{OrganisationName}/$Param{CustomerID}' updated successfully ($Param{UserID})!",
    );

    $Self->_OrganisationCacheClear( CustomerID => $Param{CustomerID} );
    if ( $Param{OrganisationID} ne $Param{CustomerID} ) {
        $Self->_OrganisationCacheClear( CustomerID => $Param{OrganisationID} );
    }

    return 1;
}

sub _OrganisationCacheClear {
    my ( $Self, %Param ) = @_;

    return if !$Self->{CacheObject};

    if ( !$Param{CustomerID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need CustomerID!'
        );
        return;
    }

    $Self->{CacheObject}->Delete(
        Type => $Self->{CacheType},
        Key  => "OrganisationGet::$Param{CustomerID}",
    );

    # delete all search cache entries
    $Self->{CacheObject}->CleanUp(
        Type => $Self->{CacheType} . '_OrganisationSearch',
    );

    for my $Function (qw(OrganisationSearch)) {
        for my $Valid ( 0 .. 1 ) {
            $Self->{CacheObject}->Delete(
                Type => $Self->{CacheType},
                Key  => "${Function}::${Valid}",
            );
        }
    }

    return 1;
}

sub DESTROY {
    my $Self = shift;

    # disconnect if it's not a parent DBObject
    if ( $Self->{NotParentDBObject} ) {
        if ( $Self->{DBObject} ) {
            $Self->{DBObject}->Disconnect();
        }
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

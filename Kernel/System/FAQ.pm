# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::FAQ;

use strict;
use warnings;

use MIME::Base64 qw();

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::System::FAQ::Search
    Kernel::System::FAQ::Category
    Kernel::System::FAQ::Vote
    Kernel::System::EventHandler
);

our @ObjectDependencies = (
    'Config',
    'Cache',
    'DB',
    'DynamicField',
    'DynamicField::Backend',
    'Encode',
    'LinkObject',
    'Log',
    'Ticket',
    'Time',
    'Type',
    'User',
    'Valid',
);

=head1 NAME

Kernel::System::FAQ -  FAQ lib

=head1 SYNOPSIS

All FAQ functions. E. g. to add FAQs or to get FAQs.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $FAQObject = $Kernel::OM->Get('FAQ');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get like escape string needed for some databases (e.g. oracle)
    $Self->{LikeEscapeString} = $Kernel::OM->Get('DB')->GetDatabaseFunction('LikeEscapeString');

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # get default options
    $Self->{Voting} = $ConfigObject->Get('FAQ::Voting');

    # init cache settings
    $Self->{CacheType} = 'FAQ';
    $Self->{CacheTTL}  = int( $ConfigObject->Get('FAQ::CacheTTL') || 60 * 60 * 24 * 2 );

    # init of event handler
    # currently there are no FAQ event modules but is needed to initialize otherwise errors are
    #     log due to searching undefined setting into ConfigObject.
    $Self->EventHandlerInit(
        Config => '',
    );

    return $Self;
}

=item FAQGet()

get an FAQ item

    my %FAQ = $FAQObject->FAQGet(
        ItemID     => 123,
        ItemFields => 0,        # Optional, default 0. To include the item field content for this
                                #   FAQ item on the return structure.
        UserID     => 1,
    );

Returns:

    %FAQ = (
        ID                => 32,
        Number            => 100032,
        CategoryID        => '2',
        Language          => 'en',
        Title             => 'Article Title',
        Approved          => 1,                              # or 0
        ValidID           => 1,
        Valid             => 'valid',
        Keywords          => 'KeyWord1 KeyWord2',
        Visibility        => 'internal',                     # or 'external' or 'public'
        Field1            => 'The Symptoms',                 # if fields should be included
        Field2            => 'The Problem',                  # if fields should be included
        Field3            => 'The Solution',                 # if fields should be included
        Field4            => undef,                          # if fields should be included, Not active by default
        Field5            => undef,                          # if fields should be included, Not active by default
        Field6            => 'Comments',                     # if fields should be included
        CreatedBy         => 1,
        Changed'          => '2011-01-05 21:53:50',
        ChangedBy         => '1',
        Created           => '2011-01-05 21:53:50',
        DynamicFields     => 1 | 0                           # optional, default 0
    );

=cut

sub FAQGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(UserID ItemID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # check cache
    my $FetchItemFields = $Param{ItemFields} ? 1 : 0;

    my $CacheKey = 'FAQGet::ItemID::' . $Param{ItemID} . '::ItemFields::' . $FetchItemFields;

    # get cache object
    my $CacheObject = $Kernel::OM->Get('Cache');

    my $Cache = $CacheObject->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # set %Data from cache if any
    my %Data;
    if ( ref $Cache eq 'HASH' ) {
        %Data = %{$Cache};
    }

    # otherwise get %Data from the DB
    else {

        return if !$DBObject->Prepare(
            SQL => '
                SELECT id, f_name, language, f_subject, created, created_by, changed,
                    changed_by, category_id, visibility, f_keywords,
                    approved, valid_id, content_type, f_number
                FROM faq_item
                WHERE id = ?',
            Bind  => [ \$Param{ItemID} ],
            Limit => 1,
        );

        while ( my @Row = $DBObject->FetchrowArray() ) {

            %Data = (

                # get data attributes
                ItemID        => $Row[0],
                Name          => $Row[1],
                Language      => $Row[2],
                Title         => $Row[3],
                Created       => $Row[4],
                CreatedBy     => $Row[5],
                Changed       => $Row[6],
                ChangedBy     => $Row[7],
                CategoryID    => $Row[8],
                Visibility    => $Row[9],
                Keywords      => $Row[10],
                Approved      => $Row[11],
                ValidID       => $Row[12],
                ContentType   => $Row[13],
                Number        => $Row[14],
            );
        }

        # check error
        if ( !%Data ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "No such ItemID $Param{ItemID}!",
            );

            return;
        }

        # check if FAQ item fields are required
        if ($FetchItemFields) {

            for my $FieldNumber ( 1 .. 6 ) {

                # set field name
                my $Field = "Field$FieldNumber";

                # get each field content
                $Data{$Field} = $Self->ItemFieldGet(
                    %Param,
                    Field => $Field,
                );
            }
        }

        # update number
        if ( !$Data{Number} ) {

            my $Number = $ConfigObject->Get('SystemID') . '00' . $Data{ItemID};

            return if !$DBObject->Do(
                SQL  => 'UPDATE faq_item SET f_number = ? WHERE id = ?',
                Bind => [ \$Number, \$Data{ItemID} ],
            );

            $Data{Number} = $Number;
        }

        # cache result
        $CacheObject->Set(
            Type  => $Self->{CacheType},
            Key   => $CacheKey,
            Value => \%Data,
            TTL   => $Self->{CacheTTL},
        );
    }

    # check if need to return DynamicFields
    if ( $Param{DynamicFields} ) {

        # get all dynamic fields for the object type FAQ
        my $DynamicFieldList = $Kernel::OM->Get('DynamicField')->DynamicFieldListGet(
            ObjectType => 'FAQArticle'
        );

        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{$DynamicFieldList} ) {

            # validate each dynamic field
            next DYNAMICFIELD if !$DynamicFieldConfig;
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
            next DYNAMICFIELD if !$DynamicFieldConfig->{Name};
            next DYNAMICFIELD if !IsHashRefWithData( $DynamicFieldConfig->{Config} );

            # get the current value for each dynamic field
            my $Value = $Kernel::OM->Get('DynamicField::Backend')->ValueGet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $Param{ItemID},
            );

            # set the dynamic field name and value into the data hash
            $Data{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = $Value;
        }
    }

    return %Data;
}

sub ItemFieldGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(UserID ItemID Field)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # check for valid field name
    if ( $Param{Field} !~ m{ \A Field [1-6] \z }msxi ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Field '$Param{Field}' is invalid!",
        );

        return;
    }

    # check cache
    my $CacheKey = 'ItemFieldGet::ItemID::' . $Param{ItemID};

    # get cache object
    my $CacheObject = $Kernel::OM->Get('Cache');

    my $Cache = $CacheObject->Get(
        Type => $Self->{CacheType},
        Key  => $CacheKey,
    );

    # check if a cache entry exists for the given Field
    if ( ref $Cache eq 'HASH' && exists $Cache->{ $Param{Field} } ) {

        return $Cache->{ $Param{Field} };
    }

    # create a field lookup table
    my %FieldLookup = (
        Field1 => 'f_field1',
        Field2 => 'f_field2',
        Field3 => 'f_field3',
        Field4 => 'f_field4',
        Field5 => 'f_field5',
        Field6 => 'f_field6',
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT ' . $FieldLookup{ $Param{Field} } . '
            FROM faq_item
            WHERE id = ?',
        Bind  => [ \$Param{ItemID} ],
        Limit => 1,
    );

    my $Field;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Field = $Row[0] || '';
    }

    if ( ref $Cache eq 'HASH' ) {

        # Cache file for ItemID already exists, add field data.
        $Cache->{ $Param{Field} } = $Field;
    }
    else {

        # Create new cache file.
        $Cache = {
            $Param{Field} => $Field,
        };
    }

    # set cache
    $CacheObject->Set(
        Type  => $Self->{CacheType},
        Key   => $CacheKey,
        Value => $Cache,
        TTL   => $Self->{CacheTTL},
    );

    return $Field;
}

=item FAQAdd()

add an article

    my $ItemID = $FAQObject->FAQAdd(
        Title       => 'Some Text',
        CategoryID  => 1,
        Visibility  => 'internal',       # possible values 'internal', 'external' or 'public'
        Language    => 'en',
        Number      => '13402',          # (optional)
        Keywords    => 'some keywords',  # (optional)
        Field1      => 'Symptom...',     # (optional)
        Field2      => 'Problem...',     # (optional)
        Field3      => 'Solution...',    # (optional)
        Field4      => 'Field4...',      # (optional)
        Field5      => 'Field5...',      # (optional)
        Field6      => 'Comment...',     # (optional)
        Approved    => 1,                # (optional)
        ValidID     => 1,
        ContentType => 'text/plain',     # or 'text/html'
        UserID      => 1,
    );

Returns:

    $ItemID = 34;

=cut

sub FAQAdd {
    my ( $Self, %Param ) = @_;

    # get log object
    my $LogObject = $Kernel::OM->Get('Log');

    # check needed stuff
    for my $Argument (qw(CategoryID Visibility Language Title UserID ContentType)) {
        if ( !$Param{$Argument} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # set default value for ValidID
    if ( !defined $Param{ValidID} ) {

        # get the valid ids
        my @ValidIDs = $Kernel::OM->Get('Valid')->ValidIDsGet();

        $Param{ValidID} = $ValidIDs[0];
    }

    # check name
    if ( !$Param{Name} ) {
        $Param{Name} = time() . '-' . rand(100);
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # check number
    if ( !$Param{Number} ) {
        $Param{Number} = $ConfigObject->Get('SystemID') . rand(100);
    }

    # check if approval feature is used
    if ( $ConfigObject->Get('FAQ::ApprovalRequired') ) {

        # TODO!!! rbo-190327
        # # check permission
        # my %Groups = reverse $Kernel::OM->Get('Group')->GroupMemberList(
        #     UserID => $Param{UserID},
        #     Type   => 'ro',
        #     Result => 'HASH',
        # );

        # # get the approval group
        # my $ApprovalGroup = $ConfigObject->Get('FAQ::ApprovalGroup');

        # # set default to 0 if approved param is not given
        # # or if user does not have the rights to approve
        # if ( !defined $Param{Approved} || !$Groups{$ApprovalGroup} ) {
        #     $Param{Approved} = 0;
        # }
    }

    # if approval feature is not activated, a new FAQ item is always approved
    else {
        $Param{Approved} = 1;
    }

    # check for base64 encoded images in fields and store them
    my @AttachmentConvert;
    foreach my $Field ( qw(Field1 Field2 Field3 Field4 Field5 Field6) ) {
        if ($Param{$Field}) {
            $Kernel::OM->Get('HTMLUtils')->EmbeddedImagesExtract(
                DocumentRef    => \$Param{$Field},
                AttachmentsRef => \@AttachmentConvert,
            );
        }
    }

    return if !$Kernel::OM->Get('DB')->Do(
        SQL => '
            INSERT INTO faq_item
                (f_number, f_name, language, f_subject,
                category_id, visibility, f_keywords, approved, valid_id, content_type,
                f_field1, f_field2, f_field3, f_field4, f_field5, f_field6,
                created, created_by, changed, changed_by)
            VALUES
                (?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?,
                current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{Number},     \$Param{Name},    \$Param{Language}, \$Param{Title},
            \$Param{CategoryID}, \$Param{Visibility}, \$Param{Keywords},   \$Param{Approved},
            \$Param{ValidID},    \$Param{ContentType},
            \$Param{Field1}, \$Param{Field2}, \$Param{Field3},
            \$Param{Field4}, \$Param{Field5}, \$Param{Field6},
            \$Param{UserID}, \$Param{UserID},
        ],
    );

    # build SQL to get the id of the newly inserted FAQ article
    my $SQL = '
        SELECT id FROM faq_item
        WHERE f_number = ?
            AND f_name = ?
            AND language = ?
            AND category_id = ?
            AND visibility = ?
            AND approved = ?
            AND valid_id = ?
            AND created_by = ?
            AND changed_by = ?';

    # handle the title
    if ( $Param{Title} ) {
        $SQL .= '
            AND f_subject = ? ';
    }

    # additional SQL for the case that the title is an empty string
    # and the database is oracle, which treats empty strings as NULL
    else {
        $SQL .= '
            AND ((f_subject = ?) OR (f_subject IS NULL)) ';
    }

    # handle the keywords
    if ( $Param{Keywords} ) {
        $SQL .= '
            AND f_keywords = ? ';
    }

    # additional SQL for the case that keywords is an empty string
    # and the database is oracle, which treats empty strings as NULL
    else {
        $SQL .= '
            AND ((f_keywords = ?) OR (f_keywords IS NULL)) ';
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # get id
    return if !$DBObject->Prepare(
        SQL  => $SQL,
        Bind => [
            \$Param{Number},
            \$Param{Name},
            \$Param{Language},
            \$Param{CategoryID},
            \$Param{Visibility},
            \$Param{Approved},
            \$Param{ValidID},
            \$Param{UserID},
            \$Param{UserID},
            \$Param{Title},
            \$Param{Keywords},
        ],
        Limit => 1,
    );

    my $ID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $ID = $Row[0];
    }

    # update number
    my $Number = $ConfigObject->Get('SystemID') . '00' . $ID;

    return if !$DBObject->Do(
        SQL  => 'UPDATE faq_item SET f_number = ? WHERE id = ?',
        Bind => [ \$Number, \$ID ],
    );

    # add converted attachments
    for my $Attachment (@AttachmentConvert) {
        $Self->AttachmentAdd(
            %{$Attachment},
            ItemID => $ID,
            UserID => $Param{UserID},
        );
    }

    # add history
    $Self->FAQHistoryAdd(
        Name   => 'Created',
        ItemID => $ID,
        UserID => $Param{UserID},
    );

    # clear cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType}
    );

    # check if approval feature is enabled
    if ( $ConfigObject->Get('FAQ::ApprovalRequired') && !$Param{Approved} ) {

        # create new approval ticket
        my $Success = $Self->_FAQApprovalTicketCreate(
            ItemID     => $ID,
            CategoryID => $Param{CategoryID},
            Language   => $Param{Language},
            FAQNumber  => $Number,
            Title      => $Param{Title},
            Visibility => $Param{Visibility},
            UserID     => $Param{UserID},
        );

        # check error
        if ( !$Success ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => 'Could not create approval ticket!',
            );
        }
    }

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'CREATE',
        Namespace => 'FAQ.Article',
        ObjectID  => $ID,
    );

    return $ID;
}

=item FAQUpdate()

update an article

   my $Success = $FAQObject->FAQUpdate(
        ItemID      => 123,
        Title       => 'Some Text',
        CategoryID  => 1,
        Visibility  => 'internal',       # possible values 'internal', 'external' or 'public'
        Language    => 'en',
        Number      => '13402',          # (optional)
        Keywords    => 'some keywords',  # (optional)
        Field1      => 'Symptom...',     # (optional)
        Field2      => 'Problem...',     # (optional)
        Field3      => 'Solution...',    # (optional)
        Field4      => 'Field4...',      # (optional)
        Field5      => 'Field5...',      # (optional)
        Field6      => 'Comment...',     # (optional)
        Approved    => 1,                # (optional)
        ValidID     => 1,
        ContentType => 'text/plain',     # or 'text/html'
        UserID      => 1,
        ApprovalOff => 1,               # optional, (if set to 1 approval is ignored. This is
                                        #   important when called from FAQInlineAttachmentURLUpdate)
    );

Returns:

    $Success = 1 ;          # or undef if can't update the FAQ article

=cut

sub FAQUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID CategoryID Visibility Language Title ValidID UserID ContentType)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # check for base64 encoded images in fields and store them
    my @AttachmentConvert;
    foreach my $Field ( qw(Field1 Field2 Field3 Field4 Field5 Field6) ) {
        $Kernel::OM->Get('HTMLUtils')->EmbeddedImagesExtract(
            DocumentRef    => \$Param{$Field},
            AttachmentsRef => \@AttachmentConvert,
        );
    }

    return if !$Kernel::OM->Get('DB')->Do(
        SQL => '
            UPDATE faq_item SET
                f_name = ?, language = ?, f_subject = ?, category_id = ?,
                visibility = ?, f_keywords = ?, valid_id = ?, content_type = ?,
                f_field1 = ?, f_field2 = ?,
                f_field3 = ?, f_field4 = ?,
                f_field5 = ?, f_field6 = ?,
                changed = current_timestamp,
                changed_by = ?
            WHERE id = ?',
        Bind => [
            \$Param{Name},    \$Param{Language}, \$Param{Title},   \$Param{CategoryID},
            \$Param{Visibility}, \$Param{Keywords},   \$Param{ValidID}, \$Param{ContentType},
            \$Param{Field1},  \$Param{Field2},
            \$Param{Field3},  \$Param{Field4},
            \$Param{Field5},  \$Param{Field6},
            \$Param{UserID},
            \$Param{ItemID},
        ],
    );

    # delete existing inline attachments
    $Self->AttachmentInlineDelete(
        ItemID => $Param{ItemID},
        UserID => $Param{UserID},
    );
    # add converted attachments
    for my $Attachment (@AttachmentConvert) {
        $Self->AttachmentAdd(
            %{$Attachment},
            ItemID => $Param{ItemID},
            UserID => $Param{UserID},
        );
    }

    # clear cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType}
    );

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

    # update approval
    if ( $ConfigObject->Get('FAQ::ApprovalRequired') && !$Param{ApprovalOff} ) {

        # TODO!!! rbo-190327
        # # check permission
        # my %Groups = reverse $Kernel::OM->Get('Group')->GroupMemberList(
        #     UserID => $Param{UserID},
        #     Type   => 'ro',
        #     Result => 'HASH',
        # );

        # # get the approval group
        # my $ApprovalGroup = $ConfigObject->Get('FAQ::ApprovalGroup');

        # # set approval to 0 if user does not have the rights to approve
        # if ( !$Groups{$ApprovalGroup} ) {
        #     $Param{Approved} = 0;
        # }

        # update the approval
        my $UpdateSuccess = $Self->_FAQApprovalUpdate(
            ItemID   => $Param{ItemID},
            Approved => $Param{Approved} || 0,
            UserID   => $Param{UserID},
        );

        # check error
        if ( !$UpdateSuccess ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Could not update approval for ItemID $Param{ItemID}!",
            );

            return;
        }

        # clear cache
        $Kernel::OM->Get('Cache')->CleanUp(
            Type => $Self->{CacheType}
        );
    }

    # check if history entry should be added
    return 1 if $Param{HistoryOff};

    # write history entry
    $Self->FAQHistoryAdd(
        Name   => 'Updated',
        ItemID => $Param{ItemID},
        UserID => $Param{UserID},
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'UPDATE',
        Namespace => 'FAQ.Article',
        ObjectID  => $Param{ItemID},
    );

    return 1;
}

=item AttachmentAdd()

add article attachments, returns the attachment id

    my $AttachmentID = $FAQObject->AttachmentAdd(
        ItemID      => 123,
        Content     => $Content,
        ContentType => 'text/xml',
        ContentID   => 'cid-1234',   # optional
        Disposition => 'attachment', # or 'inline'
        Filename    => 'somename.xml',
        UserID      => 1,
    );

Returns:

    $AttachmentID = 123 ;               # or undef if can't add the attachment

=cut

sub AttachmentAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID Content ContentType Filename UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # set content id in angle brackets
    if ( $Param{ContentID} ) {
        $Param{ContentID} =~ s/^([^<].*[^>])$/<$1>/;
    }
    $Param{ContentID} //= '';

    my $Disposition;
    my $Filename;
    if ( $Param{Disposition} ) {
        ( $Disposition, $Filename ) = split ';', $Param{Disposition};
    }
    $Disposition //= '';

    # get attachment size
    {
        use bytes;
        $Param{Filesize} = length $Param{Content};
        no bytes;
    }

    # get all existing attachments
    my @Index = $Self->AttachmentIndex(
        ItemID => $Param{ItemID},
        UserID => $Param{UserID},
    );

    # get the filename
    my $NewFileName = $Param{Filename};

    # build a lookup hash of all existing file names
    my %UsedFile;
    for my $File (@Index) {
        $UsedFile{ $File->{Filename} } = 1;
    }

    # try to modify the the file name by adding a number if it exists already
    my $Count = 0;
    while ( $Count < 50 ) {

        # increase counter
        $Count++;

        # if the file name exists
        if ( exists $UsedFile{$NewFileName} ) {

            # filename has a file name extension (e.g. test.jpg)
            if ( $Param{Filename} =~ m{ \A (.*) \. (.+?) \z }xms ) {
                $NewFileName = "$1-$Count.$2";
            }
            else {
                $NewFileName = "$Param{Filename}-$Count";
            }
        }
    }

    # store the new filename
    $Param{Filename} = $NewFileName;

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # encode attachment if it's a postgresql backend!!!
    if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {

        $Kernel::OM->Get('Encode')->EncodeOutput( \$Param{Content} );

        $Param{Content} = MIME::Base64::encode_base64( $Param{Content} );
    }

    # write attachment to db
    return if !$DBObject->Do(
        SQL => 'INSERT INTO faq_attachment ' .
            ' (faq_id, filename, content_type, content_size, content_id, disposition, content, ' .
            ' created, created_by, changed, changed_by) VALUES ' .
            ' (?, ?, ?, ?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{ItemID},  \$Param{Filename}, \$Param{ContentType}, \$Param{Filesize}, \$Param{ContentID},
            \$Disposition, \$Param{Content}, \$Param{UserID}, \$Param{UserID},
        ],
    );

    # get the attachment id
    return if !$DBObject->Prepare(
        SQL => 'SELECT id '
            . 'FROM faq_attachment '
            . 'WHERE faq_id = ? AND filename = ? '
            . 'AND content_type = ? AND content_size = ? '
            . 'AND content_id = ? AND disposition = ? '
            . 'AND created_by = ? AND changed_by = ?',
        Bind => [
            \$Param{ItemID}, \$Param{Filename}, \$Param{ContentType}, \$Param{Filesize},
            \$Param{ContentID}, \$Disposition, \$Param{UserID}, \$Param{UserID},
        ],
        Limit => 1,
    );

    my $AttachmentID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $AttachmentID = $Row[0];
    }

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'CREATE',
        Namespace => 'FAQ.Article.Attachment',
        ObjectID  => $Param{ItemID}.'::'.$AttachmentID,
    );

    return $AttachmentID;
}

=item AttachmentGet()

get attachment of article

    my %File = $FAQObject->AttachmentGet(
        ItemID => 123,
        FileID => 1,
        UserID => 1,
    );

Returns:

    %File = (
        Filesize    => '540286',                # file size in bytes
        ContentType => 'image/jpeg',
        Filename    => 'Error.jpg',
        Content     => '...'                    # file binary content
        ContentID   => '...',                   # empty if no inline image
        Disposition => 'attachment',            # or 'inline'
    );

=cut

sub AttachmentGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID FileID UserID)) {
        if ( !defined $Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT filename, content_type, content_size, content, content_id, disposition, '
            . 'created, created_by, changed, changed_by '
            . 'FROM faq_attachment '
            . 'WHERE id = ? AND faq_id = ? '
            . 'ORDER BY created',
        Bind => [ \$Param{FileID}, \$Param{ItemID} ],
        Encode => [ 1, 1, 1, 0 ],
        Limit  => 1,
    );

    my %File;
    while ( my @Row = $DBObject->FetchrowArray() ) {

        my $DecodeBase64 = 0;
        if ( $Row[3] =~ /^base64;/ ) {
            # if the content starts with this pattern we need to replace it
            # this attachment has been created by the initial data import
            $Row[3] =~ s/^base64;//g;
            $DecodeBase64 = 1;
        }

        # decode attachment if it's a postgresql backend and not BLOB or if it is a base64 encoded attachment from the initial data import
        if ( $DecodeBase64 || !$DBObject->GetDatabaseFunction('DirectBlob') ) {
            $Row[3] = MIME::Base64::decode_base64( $Row[3] );
        }

        $File{ItemID}      = $Param{ItemID};
        $File{Filename}    = $Row[0];
        $File{ContentType} = $Row[1];
        $File{Filesize}    = $Row[2];
        $File{Content}     = $Row[3];
        $File{ContentID}   = $Row[4];
        $File{Disposition} = $Row[5];
        $File{Created}     = $Row[6];
        $File{CreatedBy}   = $Row[7];
        $File{Changed}     = $Row[8];
        $File{ChangedBy}   = $Row[9];
    }

    return %File;
}

=item AttachmentDelete()

delete attachment of article

    my $Success = $FAQObject->AttachmentDelete(
        ItemID => 123,
        FileID => 1,
        UserID => 1,
    );

Returns:

    $Success = 1 ;              # or undef if attachment could not be deleted

=cut

sub AttachmentDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID FileID UserID)) {
        if ( !defined $Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    return if !$Kernel::OM->Get('DB')->Do(
        SQL  => 'DELETE FROM faq_attachment WHERE id = ? AND faq_id = ? ',
        Bind => [ \$Param{FileID}, \$Param{ItemID} ],
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'DELETE',
        Namespace => 'FAQ.Article.Attachment',
        ObjectID  => $Param{ItemID}.'::'.$Param{FileID},
    );

    return 1;
}

=item AttachmentInlineDelete()

delete inline content attachments of article

    my $Success = $FAQObject->AttachmentInlineDelete(
        ItemID => 123,
        UserID => 1,
    );

Returns:

    $Success = 1 ;              # or undef if inline attachments could not be deleted

=cut

sub AttachmentInlineDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID UserID)) {
        if ( !defined $Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    return if !$Kernel::OM->Get('DB')->Do(
        SQL  => 'DELETE FROM faq_attachment WHERE disposition = \'inline\' AND faq_id = ? ',
        Bind => [ \$Param{ItemID} ],
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'DELETE',
        Namespace => 'FAQ.Article.InlineAttachment',
        ObjectID  => $Param{ItemID},
    );

    return 1;
}

=item AttachmentIndex()

return an attachment index of an article

    my @Index = $FAQObject->AttachmentIndex(
        ItemID     => 123,
        UserID     => 1,
    );

Returns:

    @Index = (
        {
            Filesize    => '527.6 KBytes',
            ContentType => 'image/jpeg',
            Filename    => 'Error.jpg',
            FilesizeRaw => 540286,
            FileID      => 6,
            ContentID   => '...',                   # empty if no inline image
            Disposition => 'attachment',            # or 'inline'
        },
        {,
            Filesize => '430.0 KBytes',
            ContentType => 'image/jpeg',
            Filename => 'Solution.jpg',
            FilesizeRaw => 440286,
            FileID => 5,
            ContentID   => '...',                   # empty if no inline image
            Disposition => 'attachment',            # or 'inline'
        },
        {
            Filesize => '296 Bytes',
            ContentType => 'text/plain',
            Filename => 'AdditionalComments.txt',
            FilesizeRaw => 296,
            FileID => 7,
            ContentID   => '...',                   # empty if no inline image
            Disposition => 'attachment',            # or 'inline'
        },
    );

=cut

sub AttachmentIndex {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL => 'SELECT id, filename, content_type, content_size, content_id, disposition '
            . 'FROM faq_attachment '
            . 'WHERE faq_id = ? '
            . 'ORDER BY filename',
        Bind  => [ \$Param{ItemID} ],
        Limit => 100,
    );

    my @Index;
    ATTACHMENT:
    while ( my @Row = $DBObject->FetchrowArray() ) {

        my $ID          = $Row[0];
        my $Filename    = $Row[1];
        my $ContentType = $Row[2];
        my $Filesize    = $Row[3];
        my $ContentID   = $Row[4];
        my $Disposition = $Row[5];

        # convert to human readable file size
        my $FileSizeRaw = $Filesize;
        if ($Filesize) {
            if ( $Filesize > ( 1024 * 1024 ) ) {
                $Filesize = sprintf "%.1f MBytes", ( $Filesize / ( 1024 * 1024 ) );
            }
            elsif ( $Filesize > 1024 ) {
                $Filesize = sprintf "%.1f KBytes", ( ( $Filesize / 1024 ) );
            }
            else {
                $Filesize = $Filesize . ' Bytes';
            }
        }

        push @Index, {
            FileID      => $ID,
            Filename    => $Filename,
            ContentType => $ContentType,
            Filesize    => $Filesize,
            FilesizeRaw => $FileSizeRaw,
            ContentID   => $ContentID,
            Disposition => $Disposition,
        };
    }

    return @Index;
}

=item FAQCount()

Count the number of articles for a defined category. Only valid FAQ articles will be counted.

    my $ArticleCount = $FAQObject->FAQCount(
        CategoryIDs => [1,2,3,4],
        ItemStates =>  {
            1 => 'internal',
            2 => 'external',
            3 => 'public',
        },
        OnlyApproved => 1,   # optional (default 0)
        Valid        => 1,   # optional (default 0)
        UserID       => 1,
    );

Returns:

    $ArticleCount = 3;

=cut

sub FAQCount {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(CategoryIDs ItemStates UserID)) {
        if ( !defined $Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # set default value
    my $Valid = $Param{Valid} ? 1 : 0;

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    my $CategoryIDString = '';
    if ( $Param{CategoryIDs} && ref $Param{CategoryIDs} eq 'ARRAY' && @{ $Param{CategoryIDs} } ) {

        # integer quote the category ids
        for my $CategoryID ( @{ $Param{CategoryIDs} } ) {
            $DBObject->Quote( $CategoryID, 'Integer' );
        }

        my @SortedIDs = sort @{ $Param{CategoryIDs} };

        # split IN statement with more than 900 elements in more statements combined with OR
        # because Oracle doesn't support more than 1000 elements in one IN statement.
        my @SQLStrings;
        LOOP:
        while ( scalar @SortedIDs ) {

            my @SortedIDsPart = splice @SortedIDs, 0, 900;

            my $IDString = join ',', @SortedIDsPart;

            push @SQLStrings, " i.category_id IN ($IDString) ";
        }

        my $SQLString = join ' OR ', @SQLStrings;

        $CategoryIDString .= 'AND ( ' . $SQLString . ' ) ';
    }

    # build valid id string
    my $ValidIDsString;
    if ($Valid) {
        $ValidIDsString = join ', ', $Kernel::OM->Get('Valid')->ValidIDsGet();
    }
    else {
        my %ValidList = $Kernel::OM->Get('Valid')->ValidList();
        $ValidIDsString = join ', ', keys %ValidList;
    }

    my $SQL = 'SELECT COUNT(*) '
        . 'FROM faq_item i, faq_state s '
        . 'WHERE i.state_id = s.id '
        . "AND i.valid_id IN ($ValidIDsString) "
        . $CategoryIDString;

    # count only approved articles
    if ( $Param{OnlyApproved} ) {
        $SQL .= ' AND i.approved = 1';
    }

    my $Ext = '';
    if ( $Param{ItemStates} && ref $Param{ItemStates} eq 'HASH' && %{ $Param{ItemStates} } ) {
        my $StatesString = join ', ', keys %{ $Param{ItemStates} };
        $Ext .= " AND s.type_id IN ($StatesString )";
    }
    $Ext .= ' GROUP BY category_id';
    $SQL .= $Ext;

    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Limit => 200,
    );

    my $Count = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Count = $Row[0];
    }

    return $Count;
}

=item FAQDelete()

Delete an article.

    my $DeleteSuccess = $FAQObject->FAQDelete(
        ItemID => 1,
        UserID => 123,
    );

Returns:

    $DeleteSuccess = 1;              # or undef if article could not be deleted

=cut

sub FAQDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # delete attachments
    my @Index = $Self->AttachmentIndex(
        ItemID => $Param{ItemID},
        UserID => $Param{UserID},
    );
    for my $FileID (@Index) {
        my $DeleteSuccess = $Self->AttachmentDelete(
            %Param,
            FileID => $FileID->{FileID},
            UserID => $Param{UserID},
        );

        return if !$DeleteSuccess;
    }

    # delete votes
    my $VoteIDsRef = $Self->VoteSearch(
        ItemID => $Param{ItemID},
        UserID => $Param{UserID},
    );
    for my $VoteID ( @{$VoteIDsRef} ) {
        my $DeleteSuccess = $Self->VoteDelete(
            VoteID => $VoteID,
            UserID => $Param{UserID},
        );

        return if !$DeleteSuccess;
    }

    # get dynamic field objects
    my $DynamicFieldObject        = $Kernel::OM->Get('DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('DynamicField::Backend');

    # get all dynamic fields for the object type FAQArticle
    my $DynamicFieldListTicket = $DynamicFieldObject->DynamicFieldListGet(
        ObjectType => 'FAQArticle',
        Valid      => 0,
    );

    # delete dynamicfield values for this faq article
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{$DynamicFieldListTicket} ) {

        next DYNAMICFIELD if !$DynamicFieldConfig;
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
        next DYNAMICFIELD if !$DynamicFieldConfig->{Name};
        next DYNAMICFIELD if !IsHashRefWithData( $DynamicFieldConfig->{Config} );

        $DynamicFieldBackendObject->ValueDelete(
            DynamicFieldConfig => $DynamicFieldConfig,
            ObjectID           => $Param{ItemID},
            UserID             => $Param{UserID},
            NoPostHandling     => 1,                # we will delete the faq article, so no additional handling needed when deleting the DF values
        );
    }

    # clear cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType}
    );

    # delete all FAQ links of this FAQ article
    $Kernel::OM->Get('LinkObject')->LinkDeleteAll(
        Object => 'FAQ',
        Key    => $Param{ItemID},
        UserID => $Param{UserID},
    );

    # delete history
    return if !$Self->FAQHistoryDelete(
        ItemID => $Param{ItemID},
        UserID => $Param{UserID},
    );

    # delete article
    return if !$Kernel::OM->Get('DB')->Do(
        SQL  => 'DELETE FROM faq_item WHERE id = ?',
        Bind => [ \$Param{ItemID} ],
    );

    # clear cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => $Self->{CacheType}
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'DELETE',
        Namespace => 'FAQ.Article',
        ObjectID  => $Param{ItemID},
    );

    return 1;
}

=item FAQHistoryAdd()

add an history to an article

    my $AddSuccess = $FAQObject->FAQHistoryAdd(
        ItemID => 1,
        Name   => 'Updated Article.',
        UserID => 1,
    );

Returns:

    $AddSuccess = 1;               # or undef if article history could not be added

=cut

sub FAQHistoryAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID Name UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    return if !$Kernel::OM->Get('DB')->Do(
        SQL => 'INSERT INTO faq_history (name, item_id, ' .
            ' created, created_by, changed, changed_by)' .
            ' VALUES ( ?, ?, current_timestamp, ?, current_timestamp, ?)',
        Bind => [
            \$Param{Name}, \$Param{ItemID}, \$Param{UserID}, \$Param{UserID},
        ],
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'CREATE',
        Namespace => 'FAQ.Article.History',
        ObjectID  => $Param{ItemID},
    );

    return 1;
}

=item FAQHistoryGet()

get a hash with the history item

    my %HistoryData = $FAQObject->FAQHistoryGet(
        ID => 1,
        UserID => 1,
    );

Returns:

    %HistoryData = {
        CreatedBy => 1,
        Created   => '2010-11-02 07:45:15',
        Name      => 'Created',
    };

=cut

sub FAQHistoryGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ID UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL => '
            SELECT id, item_id, name, created, created_by
            FROM faq_history
            WHERE id = ?',
        Bind => [ \$Param{ID} ],
    );

    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        %Data = (
            ID        => $Row[0],
            ItemID    => $Row[1],
            Name      => $Row[2],
            Created   => $Row[3],
            CreatedBy => $Row[4],
        );
    }

    return %Data;
}

=item FAQHistoryList()

get an array with hash reference with the history of an article

    my $HistoryDataArrayRef = $FAQObject->FAQHistoryList(
        ItemID => 1,
        UserID => 1,
    );

Returns:

    $HistoryDataArrayRef = [
        {
            CreatedBy => 1,
            Created   => '2010-11-02 07:45:15',
            Name      => 'Created',
        },
        {
            CreatedBy => 1,
            Created   => '2011-06-14 12:53:55',
            Name      => 'Updated',
        },
    ];

=cut

sub FAQHistoryList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    return if !$DBObject->Prepare(
        SQL => '
            SELECT id
            FROM faq_history
            WHERE item_id = ?
            ORDER BY created, id',
        Bind => [ \$Param{ItemID} ],
    );

    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Data, $Row[0];
    }

    return \@Data;
}

=item FAQHistoryDelete()

delete the history of an article

    my $DeleteSuccess = $FAQObject->FAQHistoryDelete(
        ItemID => 1,
        UserID => 1,
    );

Returns:

    $DeleteDuccess = 1;                # or undef if history could not be deleted

=cut

sub FAQHistoryDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    return if !$Kernel::OM->Get('DB')->Do(
        SQL  => 'DELETE FROM faq_history WHERE item_id = ?',
        Bind => [ \$Param{ItemID} ],
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'DELETE',
        Namespace => 'FAQ.Article.History',
        ObjectID  => $Param{ItemID},
    );

    return 1;
}

=item HistoryGet()

get the system history

    my $HistoryDataArrayRef = $FAQObject->HistoryGet(
        UserID => 1,
    );

Returns:

    $HistoryDataArrayRef = [
        {
            ItemID    => '32',
            Number    => '10004',
            Category  => 'My Category',
            Subject   => 'New Article',
            Action    => 'Created',
            CreatedBy => '1',
            Created   => '2011-01-05 21:53:50',
        },
        {
            ItemID    => '4',
            Number    => '10004',
            Category  => 'My Category',
            Subject   => "New Article",
            Action    => 'Updated',
            CreatedBy => '1',
            Created   => '2011-01-05 21:55:32',
        }
    ];

=cut

sub HistoryGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Need UserID!",
        );
        return;
    }

    # build SQL query
    my $SQL = 'SELECT i.id, h.name, h.created, h.created_by, c.name, i.f_subject, i.f_number '
        . 'FROM faq_item i, faq_state s, faq_history h, faq_category c '
        . 'WHERE s.id = i.state_id '
        . 'AND h.item_id = i.id '
        . 'AND i.category_id = c.id ';

    # add states condition
    if ( $Param{States} && ref $Param{States} eq 'ARRAY' && @{ $Param{States} } ) {
        my $StatesString = join ', ', @{ $Param{States} };
        $SQL .= "AND s.name IN ($StatesString) ";
    }

    # add order by clause
    $SQL .= 'ORDER BY h.created DESC';

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # get the data from db
    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Limit => 200,
    );

    my @Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my %Record = (
            ItemID    => $Row[0],
            Action    => $Row[1],
            Created   => $Row[2],
            CreatedBy => $Row[3],
            Category  => $Row[4],
            Subject   => $Row[5],
            Number    => $Row[6],
        );
        push @Data, \%Record;
    }

    return \@Data;
}

=item KeywordList()

get a list of keywords as a hash, with their count as the value:

    my %Keywords = $FAQObject->KeywordList(
        Valid  => 1,
        UserID => 1,
    );

Returns:

    %Keywords = (
          'macosx'   => 8,
          'ubuntu'   => 1,
          'outlook'  => 2,
          'windows'  => 3,
          'exchange' => 1,
    );

=cut

sub KeywordList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!',
        );

        return;
    }

    # set default
    my $Valid = 0;
    if ( defined $Param{Valid} ) {
        $Valid = $Param{Valid};
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # get keywords from db
    return if !$DBObject->Prepare(
        SQL => 'SELECT f_keywords FROM faq_item',
    );

    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {

        my $KeywordList = lc $Row[0];

        for my $Keyword ( split /\s/, $KeywordList ) {
            # increase keyword counter
            $Data{$Keyword}++;
        }
    }

    return %Data;
}

=item FAQPathListGet()

returns a category array reference

    my $CategoryIDArrayRef = $FAQObject->FAQPathListGet(
        CategoryID => 150,
        UserID     => 1,
    );

Returns:

    $CategoryIDArrayRef = [
        {
            CategoryID => '2',
            ParentID => '0',
            Name => 'My Category',
            Comment => 'My First Category',
            ValidID => '1',
        },
        {
            CategoryID => '4',
            ParentID => '2',
            Name => 'Sub Category A',
            Comment => 'This Is Category A',
            ValidID => '1',
        },
    ];

=cut

sub FAQPathListGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Need UserID!",
        );

        return;
    }

    my @CategoryList;
    my $TempCategoryID = $Param{CategoryID};
    while ($TempCategoryID) {
        my %Data = $Self->CategoryGet(
            CategoryID => $TempCategoryID,
            UserID     => $Param{UserID},
        );
        if (%Data) {
            push @CategoryList, \%Data;
        }
        $TempCategoryID = $Data{ParentID};
    }

    @CategoryList = reverse @CategoryList;

    return \@CategoryList;

}

=item FAQLogAdd()

adds accessed FAQ article to the access log table

    my $Success = $FAQObject->FAQLogAdd(
        ItemID    => '123456',
        Interface => 'internal',
        UserID    => 1,
    );

Returns:

    $Success =1;                # or undef if FAQLog could not be added

=cut

sub FAQLogAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID Interface UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # get environment variables
    my $IP        = $ENV{'REMOTE_ADDR'}     || 'NONE';
    my $UserAgent = $ENV{'HTTP_USER_AGENT'} || 'NONE';

    # get time object
    my $TimeObject = $Kernel::OM->Get('Time');

    # get current system time
    my $SystemTime = $TimeObject->SystemTime();

    # define time period where reloads will not be logged (10 minutes)
    my $ReloadBlockTime = 10 * 60;

    # subtract ReloadBlockTime
    $SystemTime = $SystemTime - $ReloadBlockTime;

    # convert to times-stamp
    my $TimeStamp = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $SystemTime,
    );

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # check if a log entry exists newer than the ReloadBlockTime
    return if !$DBObject->Prepare(
        SQL => 'SELECT id FROM faq_log '
            . 'WHERE item_id = ? AND ip = ? '
            . 'AND user_agent = ? AND created >= ? ',
        Bind  => [ \$Param{ItemID}, \$IP, \$UserAgent, \$TimeStamp ],
        Limit => 1,
    );

    # fetch the result
    my $AlreadyExists = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $AlreadyExists = 1;
    }

    return if $AlreadyExists;

    # insert new log entry
    return if !$DBObject->Do(
        SQL => 'INSERT INTO faq_log '
            . '(item_id, interface, ip, user_agent, created) VALUES '
            . '(?, ?, ?, ?, current_timestamp)',
        Bind => [
            \$Param{ItemID}, \$Param{Interface}, \$IP, \$UserAgent,
        ],
    );

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'CREATE',
        Namespace => 'FAQ.Article.Log',
        ObjectID  => $Param{ItemID},
    );

    return 1;
}

=item FAQTop10Get()

Returns an array with the top 10 FAQ article ids.

    my $Top10IDsRef = $FAQObject->FAQTop10Get(
        Interface   => 'public',
        CategoryIDs => [ 1, 2, 3 ],  # (optional) Only show the Top-10 articles from these categories
        Limit       => 10,           # (optional, default 10)
        UserID      => 1,
    );

Returns:

    $Top10IDsRef = [
        {
            'ItemID'    => 13,
            'Count'     => 159,               # number of visits
            'Interface' => 'public',
        },
        {
            'ItemID'    => 6,
            'Count'     => 78,
            'Interface' => 'public',
        },
        {
            'ItemID'    => 4,
            'Count'     => 59,
            'Interface' => 'internal',
        },
        {
            'ItemID'    => 20,
            'Count'     => 29,
            'Interface' => 'public',
        },
        {
            'ItemID'    => 1,
            'Count'     => 24,
            'Interface' => 'external',
        },
        {
            'ItemID'    => 11,
            'Count'     => 24,
            'Interface' => 'internal',
        },
        {
            'ItemID'    => 5,
            'Count'     => 18,
            'Interface' => 'internal',
        },
        {
            'ItemID'    => 9,
            'Count'     => 16,
            'Interface' => 'external',
        },
        {
            'ItemID'    => 2,
            'Count'     => 14,
            'Interface' => 'internal'
        },
        {
            'ItemID'    => 14,
            'Count'     => 6,
            'Interface' => 'public',
        }
    ];

=cut

sub FAQTop10Get {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Interface UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return [];
        }
    }

    # build valid id string
    my $ValidIDsString = join ', ', $Kernel::OM->Get('Valid')->ValidIDsGet();

    # prepare SQL
    my @Bind;
    my $SQL = 'SELECT item_id, count(item_id) as itemcount, faq_state_type.name, approved '
        . 'FROM faq_log, faq_item, faq_state, faq_state_type '
        . 'WHERE faq_log.item_id = faq_item.id '
        . 'AND faq_item.state_id = faq_state.id '
        . "AND faq_item.valid_id IN ($ValidIDsString) "
        . 'AND faq_state.type_id = faq_state_type.id ';

    # get database object
    my $DBObject = $Kernel::OM->Get('DB');

    # filter just categories with at least ro permission
    if ( $Param{CategoryIDs} && ref $Param{CategoryIDs} eq 'ARRAY' && @{ $Param{CategoryIDs} } ) {

        # integer quote the category ids
        for my $CategoryID ( @{ $Param{CategoryIDs} } ) {
            $DBObject->Quote( $CategoryID, 'Integer' );
        }

        my @SortedIDs = sort @{ $Param{CategoryIDs} };

        # split IN statement with more than 900 elements in more statements combined with OR
        # because Oracle doesn't support more than 1000 elements in one IN statement.
        my @SQLStrings;
        LOOP:
        while ( scalar @SortedIDs ) {

            my @SortedIDsPart = splice @SortedIDs, 0, 900;

            my $IDString = join ',', @SortedIDsPart;

            push @SQLStrings, " faq_item.category_id IN ($IDString) ";
        }

        my $SQLString = join ' OR ', @SQLStrings;

        $SQL .= ' AND ( ' . $SQLString . ' ) ';
    }

    # filter results for public and customer interface
    if ( ( $Param{Interface} eq 'public' ) || ( $Param{Interface} eq 'external' ) ) {

        # only show approved articles
        $SQL .= 'AND faq_item.approved = 1 ';

        # only show the public articles
        $SQL .= "AND ( ( faq_state_type.name = 'public' AND faq_log.interface = 'public' ) ";

        # customers can additionally see the external articles
        if ( $Param{Interface} eq 'external' ) {
            $SQL .= "OR ( faq_state_type.name = 'external' AND faq_log.interface = 'external' ) ";
        }

        $SQL .= ') ';
    }

    # filter results for defined time period
    if ( $Param{StartDate} && $Param{EndDate} ) {
        $SQL .= 'AND faq_log.created >= ? AND faq_log.created <= ? ';
        push @Bind, ( \$Param{StartDate}, \$Param{EndDate} );
    }

    # complete SQL statement
    $SQL .= 'GROUP BY item_id, faq_state_type.name, approved '
        . 'ORDER BY itemcount DESC';

    # get the top 10 article ids from database
    return [] if !$DBObject->Prepare(
        SQL   => $SQL,
        Bind  => \@Bind,
        Limit => $Param{Limit} || 10,
    );

    my @Result;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @Result, {
            ItemID    => $Row[0],
            Count     => $Row[1],
            Interface => $Row[2],
        };
    }

    return \@Result;
}

=item FAQArticleTitleClean()

strip/clean up a FAQ article title

    my $NewTitle = $FAQObject->FAQArticleTitleClean(
        Title      => $OldTitle,
        Size       => $TitleSizeToBeDisplayed   # optional, if 0 do not cut title
    );

=cut

sub FAQArticleTitleClean {
    my ( $Self, %Param ) = @_;

    my $Title = $Param{Title} || '';

    # get config options
    my $TitleSize = $Param{Size};
    if ( !defined $TitleSize ) {
        $TitleSize = $Kernel::OM->Get('Config')->Get('FAQ::TitleSize') || 100;
    }

    # trim white space at the beginning or end
    $Title =~ s/(^\s+|\s+$)//;

    # resize title based on config
    # do not cut title, if size parameter was 0
    if ($TitleSize) {
        $Title =~ s/^(.{$TitleSize}).*$/$1 [...]/;
    }

    return $Title;
}

=item FAQContentTypeSet()

Sets the content type of 1, some or all FAQ items, by a given parameter or determined by the FAQ item content

    my $Success = $FAQObject->FAQContentTypeSet(
        FAQItemIDs  => [ 1, 2, 3 ],             # optional,
        ContentType => 'some content type',     # optional,
    );

=cut

sub FAQContentTypeSet {
    my ( $Self, %Param ) = @_;

    if ( $Param{FAQItemIDs} && !IsArrayRefWithData( $Param{FAQItemIDs} ) ) {
        $Kernel::OM->Get('Log')->Log(
            Priority => 'error',
            Message  => "Invalid FAQItemIDs format!",
        );

        return;
    }

    # Get config object.
    my $ConfigObject = $Kernel::OM->Get('Config');

    my $ContentType = $Param{ContentType} || '';

    # Get default content type from the config if it was not given.
    if ( !$ContentType ) {

        $ContentType = 'text/plain';
        if ( $ConfigObject->Get('Frontend::RichText') && $ConfigObject->Get('FAQ::Item::HTML') ) {
            $ContentType = 'text/html';
        }
    }

    # SQL to set the content type (default or given).
    my $SQL = '
        UPDATE faq_item
        SET content_type = ?';

    # Get FAQ item IDs from the param.
    my @FAQItemIDs = @{ $Param{FAQItemIDs} // [] };

    # Restrict to only given FAQ item IDs (if any).
    if (@FAQItemIDs) {

        my $IDString = join ',', @FAQItemIDs;

        $SQL .= "
            WHERE id IN ($IDString)";
    }

    # Get DB object.
    my $DBObject = $Kernel::OM->Get('DB');

    # Set the content type either by the given param or according to the system settings.
    return if !$DBObject->Do(
        SQL  => $SQL,
        Bind => [
            \$ContentType,
        ],
    );

    # No need to go further if content type was given (it was already set).
    if ( $Param{ContentType} ) {

        # Delete cache
        $Kernel::OM->Get('Cache')->CleanUp(
            Type => 'FAQ',
        );

        return 1
    }

    # Otherwise content type has to be determined by the FAQ item content.

    # Get all FAQIDs (if no faq item was given).
    if ( !@FAQItemIDs ) {
        return if !$DBObject->Prepare(
            SQL => '
                SELECT DISTINCT(faq_item.id)
                FROM faq_item
                ORDER BY id ASC',
        );

        while ( my @Row = $DBObject->FetchrowArray() ) {
            push @FAQItemIDs, $Row[0];
        }
    }

    # Loop trough the FAQ items.
    ITEMID:
    for my $ItemID (@FAQItemIDs) {
        my $DeterminedContentType = 'text/plain';

        # Get the contents of each field
        FIELD:
        for my $Field (qw(Field1 Field2 Field3 Field4 Field5 Field6)) {

            my $FieldContent = $Self->ItemFieldGet(
                ItemID => $ItemID,
                Field  => $Field,
                UserID => 1,
            );

            next FIELD if !$FieldContent;

            # if field content seams to be HTML set the content type to HTML
            if (
                $FieldContent
                =~ m{(?: <br\s*/> | </li> | </ol> | </ul> | </table> | </tr> | </td> | </div> | </o> | </i> | </span> | </h\d> | </p> | </pre> )}msx
                )
            {
                $DeterminedContentType = 'text/html';
                last FIELD;
            }
        }

        next ITEMID if $DeterminedContentType eq $ContentType;

        # Set the content type according to the field content.
        return if !$DBObject->Do(
            SQL => '
                UPDATE faq_item
                SET content_type = ?
                WHERE id =?',
            Bind => [
                \$DeterminedContentType,
                \$ItemID,
            ],
        );

        # push client callback event
        $Kernel::OM->Get('ClientRegistration')->NotifyClients(
            Event     => 'UPDATE',
            Namespace => 'FAQ.Article',
            ObjectID  => $ItemID,
        );
    }

    # Delete cache
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => 'FAQ',
    );

    return 1;
}

=item GetAssignedFAQArticlesForObject()

return all assigned faq article IDs

    my $TicketIDList = $TicketObject->GetAssignedFAQArticlesForObject(
        ObjectType   => 'Contact',
        Object       => $ContactHashRef,                # (optional)
        ObjectIDList => $ObjectIDListArrayRef,          # (optional)
        UserID       => 1
    );

=cut

sub GetAssignedFAQArticlesForObject {
    my ( $Self, %Param ) = @_;

    my @AssignedFAQArticleIDs = ();

    my %SearchData = $Self->_GetAssignedSearchParams(
        %Param,
        AssignedObjectType => 'FAQArticle'
    );

    if (IsHashRefWithData(\%SearchData)) {
        my %IDSearch;
        if (IsArrayRefWithData($Param{ObjectIDList})) {
            $IDSearch{ArticleIDs} = $Param{ObjectIDList};
        }

        for my $Attribute ( keys %SearchData ) {

            my %Search;

            # TODO: extend possibilities
            if ( $Attribute eq 'CustomerVisible' && IsArrayRefWithData($SearchData{$Attribute}) ) {
                my @Visibility;
                for my $VisibleValue ( @{ $SearchData{$Attribute} } ) {
                    if ($VisibleValue) {
                        push(@Visibility, ('external', 'public'));
                    } else {
                        push(@Visibility, 'internal');
                    }
                }
                if (@Visibility) {
                    $Search{Visibility} = \@Visibility;
                }
            } elsif ($Attribute eq 'Languages' || $Attribute eq 'Language') {
                $Search{Languages} = IsArrayRefWithData($SearchData{$Attribute}) ? $SearchData{$Attribute} : [ $SearchData{$Attribute} ];
            } elsif ($Attribute eq 'CategoryIDs' || $Attribute eq 'CategoryID') {
                $Search{CategoryIDs} = IsArrayRefWithData($SearchData{$Attribute}) ? $SearchData{$Attribute} : [ $SearchData{$Attribute} ];
            } elsif ($Attribute =~ m/^DynamicField_/) {
                $Search{$Attribute} = {
                    Like => $SearchData{$Attribute}
                };
            } elsif ($Attribute eq 'Title') {
                $Search{$Attribute} = IsArrayRefWithData($SearchData{$Attribute}) ? $SearchData{$Attribute}->[0] : $SearchData{$Attribute};
            }

            if (keys %Search) {
                my @FoundIDs = $Self->FAQSearch(
                    %IDSearch,
                    %Search,
                    UserID => $Param{UserID},
                );

                @AssignedFAQArticleIDs = $Self->_GetCombinedList(
                    ListA => \@AssignedFAQArticleIDs,
                    ListB => \@FoundIDs,
                    Union => 1
                );
            }
        }

        if ( IsArrayRefWithData(\@AssignedFAQArticleIDs) ) {
            @AssignedFAQArticleIDs = map { 0 + $_ } @AssignedFAQArticleIDs;
        }
    }

    return \@AssignedFAQArticleIDs;
}

# TODO: move to a "common" module (used in other modules too)
=item _GetCombinedList()

combines to arrays (intersect or union)

    my @CombinedList = $Self->_GetCombinedList(
        ListA   => $ListAArrayRef,
        ListB   => $ListBArrayRef,
        Union   => 1                # (optional) default 0
    );

    e.g.
        ListA = [ 1, 2, 3, 4 ]
        ListB = [ 2, 4, 5 ]

        as union = [1, 2, 3, 4, 5 ]
        as intersect = [ 2, 4 ]

=cut

sub _GetCombinedList {
    my ( $Self, %Param ) = @_;

    my %Union;
    my %Isect;
    for my $E ( @{ $Param{ListA} }, @{ $Param{ListB} } ) {
        $Union{$E}++ && $Isect{$E}++
    }

    return $Param{Union} ? keys %Union : keys %Isect;
}

# TODO: move to a "common" module (used in other modules too)
=item _GetAssignedSearchParams()

prepares and transform config from AssignedObjectsMapping to a simple hash

    my %SearchData = $Self->_GetAssignedSearchParams(
        ObjectType         => 'Contact',
        Object             => $ContactHash,      # (optional)
        AssignedObjectType => 'Ticket'
    );

    e.g. if AssignedObjectType is 'Ticket'

    %SearchData = (
        ContactID      => 1,
        OrganisationID => 2,
        ...
    );

=cut

sub _GetAssignedSearchParams {
    my ( $Self, %Param ) = @_;

    for ( qw(AssignedObjectType ObjectType) ) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $MappingString = $Kernel::OM->Get('Config')->Get('AssignedObjectsMapping') || '';

    my %SearchData;
    if ( IsStringWithData($MappingString) ) {

        my $Mapping = $Kernel::OM->Get('JSON')->Decode(
            Data => $MappingString
        );

        if ( !IsHashRefWithData($Mapping) ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Invalid JSON for sysconfig option 'AssignedObjectsMapping'."
            );
        } elsif (
            IsHashRefWithData( $Mapping->{ $Param{ObjectType} } ) &&
            IsHashRefWithData( $Mapping->{ $Param{ObjectType} }->{ $Param{AssignedObjectType} } )
        ) {
            my %SearchAttributes = %{ $Mapping->{ $Param{ObjectType} }->{ $Param{AssignedObjectType} } };

            # prepare search data
            for my $SearchAttribute ( keys %SearchAttributes ) {
                next if (!$SearchAttribute);

                next if ( !IsHashRefWithData( $SearchAttributes{$SearchAttribute} ) );
                my $ObjectSearchAttributes = $SearchAttributes{$SearchAttribute}->{SearchAttributes};
                my $SearchStatics          = $SearchAttributes{$SearchAttribute}->{SearchStatic};
                next if ( !IsArrayRefWithData( $ObjectSearchAttributes ) && !IsArrayRefWithData($SearchStatics) );

                $SearchAttribute =~ s/^\s+//g;
                $SearchAttribute =~ s/\s+$//g;

                next if (!$SearchAttribute);

                $SearchData{$SearchAttribute} = [];

                # get attributes search data
                if (IsHashRefWithData( $Param{Object} )) {
                    for my $ObjectSearchAttribute ( @{$ObjectSearchAttributes} ) {
                        my $Value;

                        # check if value from sub-object (e.g. User of Contact)
                        if ( $ObjectSearchAttribute =~ /.+\..+/ ) {
                            my @AttributStructure = split(/\./, $ObjectSearchAttribute);
                            next if ( !$AttributStructure[0] || !$AttributStructure[1] || !IsHashRefWithData( $Param{Object}->{$AttributStructure[0]} ) );
                            $Value = $Param{Object}->{$AttributStructure[0]}->{$AttributStructure[1]}
                        } else {
                            $Value = $Param{Object}->{$ObjectSearchAttribute};
                        }

                        next if ( !defined $Value );

                        push (
                            @{ $SearchData{$SearchAttribute} },
                            IsArrayRefWithData($Value) ? @{$Value} : $Value
                        );
                    }
                }

                # get static search data
                for my $SearchStatic ( @{$SearchStatics} ) {
                    next if ( !defined $SearchStatic );
                    push ( @{ $SearchData{$SearchAttribute} }, $SearchStatic );
                }

                if (!scalar(@{ $SearchData{$SearchAttribute} })) {
                    delete $SearchData{$SearchAttribute};
                }
            }
        } else {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'info',
                Message  => "type '$Param{ObjectType}' or sub-type '$Param{AssignedObjectType}' not contained in 'AssignedObjectsMapping'."
            );
        }
    }

    return %SearchData;
}

=begin Internal:

=item _FAQApprovalUpdate()

update the approval state of an article

    my $Success = $FAQObject->_FAQApprovalUpdate(
        ItemID     => 123,
        Approved   => 1,    # 0|1 (default 0)
        UserID     => 1,
    );

=cut

sub _FAQApprovalUpdate {
    my ( $Self, %Param ) = @_;

    # get log object
    my $LogObject = $Kernel::OM->Get('Log');

    # check needed stuff
    for my $Argument (qw(ItemID UserID)) {
        if ( !$Param{$Argument} ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    if ( !defined $Param{Approved} ) {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'Need Approved parameter!',
        );

        return;
    }

    # update database
    return if !$Kernel::OM->Get('DB')->Do(
        SQL => 'UPDATE faq_item SET '
            . 'approved = ?, '
            . 'changed = current_timestamp, '
            . 'changed_by = ? '
            . 'WHERE id = ?',
        Bind => [
            \$Param{Approved},
            \$Param{UserID},
            \$Param{ItemID},
        ],
    );

    # approval feature is activated and FAQ article is not approved yet
    if ( $Kernel::OM->Get('Config')->Get('FAQ::ApprovalRequired') && !$Param{Approved} ) {

        # get FAQ data
        my %FAQData = $Self->FAQGet(
            ItemID     => $Param{ItemID},
            ItemFields => 0,
            UserID     => $Param{UserID},
        );

        # create new approval ticket
        my $Success = $Self->_FAQApprovalTicketCreate(
            ItemID     => $Param{ItemID},
            CategoryID => $FAQData{CategoryID},
            LanguageID => $FAQData{LanguageID},
            FAQNumber  => $FAQData{Number},
            Title      => $FAQData{Title},
            StateID    => $FAQData{StateID},
            UserID     => $Param{UserID},
        );

        # check error
        if ( !$Success ) {
            $LogObject->Log(
                Priority => 'error',
                Message  => 'Could not create approval ticket!',
            );
        }
    }

    # push client callback event
    $Kernel::OM->Get('ClientRegistration')->NotifyClients(
        Event     => 'UPDATE',
        Namespace => 'FAQ.Article',
        ObjectID  => $Param{ItemID},
    );

    return 1;
}

=item _FAQApprovalTicketCreate()

creates an approval ticket

    my $Success = $FAQObject->_FAQApprovalTicketCreate(
        ItemID     => 123,
        CategoryID => 2,
        Language   => 'en',
        FAQNumber  => 10211,
        Title      => 'Some Title',
        Visibility => 'agent',
        UserID     => 1,
    );

=cut

sub _FAQApprovalTicketCreate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(ItemID CategoryID FAQNumber Title Visibility UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );

            return;
        }
    }

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Ticket');

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Config');

#rbo - T2016121190001552 - added KIX placeholders
    # get subject
    my $Subject = $ConfigObject->Get('FAQ::ApprovalTicketSubject');
    $Subject =~ s{ <KIX_FAQ_NUMBER> }{$Param{FAQNumber}}xms;

    # check if we can find existing open approval tickets for this FAQ article
    my @TicketIDs = $TicketObject->TicketSearch(
        Result    => 'ARRAY',
        Title     => $Subject,
        StateType => 'Open',
        UserID    => 1,
    );

    # we don't need to create another approval ticket if there is still at least one ticket open
    # for this FAQ article
    return 1 if @TicketIDs;

    # get ticket type from SysConfig
    my $TicketType = $ConfigObject->Get('FAQ::ApprovalTicketType') || '';

    # validate ticket type if any
    if ($TicketType) {

        # get a ticket type lookup table
        my %TypeList   = $Kernel::OM->Get('Type')->TypeList();
        my %TypeLookup = reverse %TypeList;

        # set $TicketType to empty if TickeyType does not appear in the lookup table. If set to
        #    empty TicketCreate() will use as default TypeID = 1, no matter if it is valid or not.
        $TicketType = $TypeLookup{$TicketType} ? $TicketType : '';
    }

    # create ticket
    my $TicketID = $TicketObject->TicketCreate(
        Title    => $Subject,
        Queue    => $ConfigObject->Get('FAQ::ApprovalQueue') || 'Raw',
        Lock     => 'unlock',
        Priority => $ConfigObject->Get('FAQ::ApprovalTicketPriority') || '3 normal',
        State    => $ConfigObject->Get('FAQ::ApprovalTicketDefaultState') || 'new',
        Type     => $TicketType,
        OwnerID  => 1,
        UserID   => 1,
    );

    if ($TicketID) {

        # get user object
        my $UserObject = $Kernel::OM->Get('User');

        # get UserName
        my $UserName = $UserObject->UserName(
            UserID => $Param{UserID},
        );

        # categories can be nested; you can have some::long::category.
        my @CategoryNames;
        my $CategoryID = $Param{CategoryID};
        CATEGORY:
        while (1) {
            my %Category = $Self->CategoryGet(
                CategoryID => $CategoryID,
                UserID     => $Param{UserID},
            );
            push @CategoryNames, $Category{Name};
            last CATEGORY if !$Category{ParentID};
            $CategoryID = $Category{ParentID};
        }
        my $Category = join('::', reverse @CategoryNames);

        # get body from config
        my $Body = $ConfigObject->Get('FAQ::ApprovalTicketBody');
        $Body =~ s{ <KIX_FAQ_CATEGORYID> }{$Param{CategoryID}}xms;
        $Body =~ s{ <KIX_FAQ_CATEGORY>   }{$Category}xms;
        $Body =~ s{ <KIX_FAQ_LANGUAGE>   }{$Param{Language}}xms;
        $Body =~ s{ <KIX_FAQ_ITEMID>     }{$Param{ItemID}}xms;
        $Body =~ s{ <KIX_FAQ_NUMBER>     }{$Param{FAQNumber}}xms;
        $Body =~ s{ <KIX_FAQ_TITLE>      }{$Param{Title}}xms;
        $Body =~ s{ <KIX_FAQ_AUTHOR>     }{$UserName}xms;
        $Body =~ s{ <KIX_FAQ_STATE>      }{$Param{Visibility}}xms;

        #  gather contact data
        if ($Param{UserID}) {
            my %ContactData = $Self->{ContactObject}->ContactGet(
                UserID => $Param{UserID},
            );

            # create from string
            my $From = "\"$ContactData{Firstname} $ContactData{Lastname}\" <$ContactData{Email}>";

            # create article
            my $ArticleID = $TicketObject->ArticleCreate(
                TicketID       => $TicketID,
                Channel        => 'note',
                SenderType     => 'agent',
                From           => $From,
                Subject        => $Subject,
                Body           => $Body,
                ContentType    => 'text/plain; charset=utf-8',
                UserID         => $Param{UserID},
                HistoryType    =>
                    $ConfigObject->Get('Ticket::Frontend::AgentTicketNote')->{HistoryType}
                        || 'AddNote',
                HistoryComment =>
                    $ConfigObject->Get('Ticket::Frontend::AgentTicketNote')->{HistoryComment}
                        || '%%Note',
            );

            return $ArticleID;
        }
    }

    return;
}

1;

=end Internal:

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-AGPL for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut

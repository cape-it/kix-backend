# --
# Modified version of the work: Copyright (C) 2006-2017 c.a.p.e. IT GmbH, http://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::SysConfig::OptionType::TimeVacationDaysOneTime;

use strict;
use warnings;

use base qw(
    Kernel::System::SysConfig::OptionType::Hash
);

use Kernel::System::VariableCheck qw(:all);

=item ValidateSetting()

Validates the given setting and returns the prepared Setting as well as the default value.

    my $Success = $OptionTypeObject->ValidateSetting(
        Setting => {...},
    );

=cut

sub ValidateSetting {
    my ( $Self, %Param ) = @_;

    my @DefaultValue;

    if ( IsArrayRefWithData($Param{Setting}->{Item}) ) {
        foreach my $Item ( @{$Param{Setting}->{Item}} ) {
            next if !IsHashRefWithData($Item);
            my %PreparedItem = %{$Item};
            delete $PreparedItem{Tanslatable};
            push(@DefaultValue, \%PreparedItem);
        }
    }
    
    return (undef, \@DefaultValue);
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<http://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
COPYING for license information (AGPL). If you did not receive this file, see

<http://www.gnu.org/licenses/agpl.txt>.

=cut
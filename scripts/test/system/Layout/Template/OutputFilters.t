# --
# Modified version of the work: Copyright (C) 2006-2021 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2017 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE-AGPL for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

use Kernel::Output::HTML::Layout;

use Kernel::System::VariableCheck qw(:all);

# get helper object
$Kernel::OM->ObjectParamAdd(
    'UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('UnitTest::Helper');

my @Tests = (
    {
        Name   => 'Output filter post, all templates (ignored)',
        Config => {
            "Frontend::Output::FilterElementPost" => {
                "100-TestFilter" => {
                    Module    => 'scripts::test::system::Layout::Template::OutputFilter',
                    Templates => {
                        ALL => 1,
                    },
                    Prefix => "OutputFilterPostPrefix1:\n",
                },
            },
        },
        Data => {
            Title => 'B&B 1'
        },
        Output => 'OutputFilters',
        Result => 'Test: B&B 1
',
    },
    {
        Name   => 'Output filter post, all templates, cache test (cacheable)',
        Config => {
            "Frontend::Output::FilterElementPost" => {
                "100-TestFilter" => {
                    Module    => 'scripts::test::system::Layout::Template::OutputFilter',
                    Templates => {
                        ALL => 1,
                    },
                    Prefix => "OutputFilterPostPrefix2:\n",
                },
            },
        },
        Data => {
            Title => 'B&B 2'
        },
        Output => 'OutputFilters',
        Result => 'Test: B&B 2
',
    },
    {
        Name   => 'Output filter post, OutputFilters template',
        Config => {
            "Frontend::Output::FilterElementPost" => {
                "100-TestFilter" => {
                    Module    => 'scripts::test::system::Layout::Template::OutputFilter',
                    Templates => {
                        OutputFilters => 1,
                    },
                    Prefix => "OutputFilterPostPrefix3:\n",
                },
            },
        },
        Data => {
            Title => 'B&B 3'
        },
        Output => 'OutputFilters',
        Result => 'OutputFilterPostPrefix3:
Test: B&B 3
',
    },
    {
        Name   => 'Output filter post, OutputFilters template, cache test (cacheable)',
        Config => {
            "Frontend::Output::FilterElementPost" => {
                "100-TestFilter" => {
                    Module    => 'scripts::test::system::Layout::Template::OutputFilter',
                    Templates => {
                        OutputFilters => 1,
                    },
                    Prefix => "OutputFilterPostPrefix4:\n",
                },
            },
        },
        Data => {
            Title => 'B&B 4'
        },
        Output => 'OutputFilters',
        Result => 'OutputFilterPostPrefix4:
Test: B&B 4
',
    },
);

for my $Test (@Tests) {

    # cleanup the cache and run every test twice to also test the disk caching
    $Kernel::OM->Get('Cache')->CleanUp(
        Type => 'TemplateProvider',
    );

    for ( 0 .. 1 ) {

        my $ConfigObject = $Kernel::OM->Get('Config');

        for my $Key ( sort keys %{ $Test->{Config} || {} } ) {
            $ConfigObject->Set(
                Key   => $Key,
                Value => $Test->{Config}->{$Key}
            );
        }

        my $LayoutObject = Kernel::Output::HTML::Layout->new(
            UserID => 1,
            Lang   => 'de',
        );

        # call Output() once so that the TT objects are created.
        $LayoutObject->Output( Template => '' );

        # now add this directory as include path to be able to use the test templates
        my $IncludePaths = $LayoutObject->{TemplateProviderObject}->include_path();
        unshift @{$IncludePaths}, $ConfigObject->Get('Home') . '/scripts/test/system/Layout/Template';
        $LayoutObject->{TemplateProviderObject}->include_path($IncludePaths);

        for my $Block ( @{ $Test->{BlockData} || [] } ) {
            $LayoutObject->Block( %{$Block} );
        }

        my $Result = $LayoutObject->Output(
            TemplateFile => $Test->{Output},
            Data         => $Test->{Data} // {},
        );

        $Self->Is(
            $Result,
            $Test->{Result},
            $Test->{Name},
        );

        my $FileName = $ConfigObject->Get('Home') . '/scripts/test/system/Layout/Template/' . $Test->{Output} . '.tt';

        # remove duplicated //
        $FileName =~ s{/{2,}}{/}g;
        $Self->True(
            $LayoutObject->{TemplateProviderObject}->{_TemplateCache}->{$FileName},
            'Template added to cache',
        );
    }

}

# cleanup cache is done by RestoreDatabase

1;



=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE-AGPL for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut

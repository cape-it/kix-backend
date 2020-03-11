use warnings;

use Cwd;
use lib cwd();
use lib cwd() . '/Kernel/cpan-lib';
use lib cwd() . '/Custom';
use lib cwd() . '/scripts/test/api/Cucumber';

use LWP::UserAgent;
use HTTP::Request;
use JSON::XS qw(encode_json decode_json);
use JSON::Validator;

use Test::More;
use Test::BDD::Cucumber::StepFile;

use Data::Dumper;

use Kernel::System::ObjectManager;

$Kernel::OM = Kernel::System::ObjectManager->new();

# require our helper
require '_Helper.pl';

# require our common library
require '_StepsLib.pl';

# feature specific steps 

When qr/I delete this automation macro action$/, sub { 
   ( S->{Response}, S->{ResponseContent} ) = _Delete(
      Token => S->{Token},
      URL   => S->{API_URL}.'/system/automation/macros/'.S->{MacroID}.'/actions/'.S->{MacroActionID},
   );
};

When qr/delete all this automation macro actions$/, sub {
    for ($i=0;$i<@{S->{MacroActionIDArray}};$i++){ 
        ( S->{Response}, S->{ResponseContent} ) = _Delete(
            Token => S->{Token},
            URL   => S->{API_URL}.'/system/automation/macros/'.S->{MacroID}.'/actions/'.S->{MacroActionIDArray}->[$i],
        );
    }

    S->{MacroActionIDArray} = ();

};

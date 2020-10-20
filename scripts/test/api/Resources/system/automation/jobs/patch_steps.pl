use warnings;

use Cwd;
use lib cwd();
use lib cwd() . '/Kernel/cpan-lib';
use lib cwd() . '/plugins';
use lib cwd() . '/scripts/test/api/Cucumber';

use LWP::UserAgent;
use HTTP::Request;
use JSON::MaybeXS qw(encode_json decode_json);
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

When qr/I update this automation job$/, sub {
   ( S->{Response}, S->{ResponseContent} ) = _Patch(
      URL     => S->{API_URL}.'/system/automation/jobs/'.S->{JobID},
      Token   => S->{Token},
      Content => {
        Job => {
            Comment => "some comment update",
            Name => "new job".rand(),
            Type => "Ticket",
            ValidID => 1
        }
      }
   );
};
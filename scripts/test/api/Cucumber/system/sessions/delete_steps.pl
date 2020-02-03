#!perl

use strict;
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

use Kernel::System::ObjectManager;

$Kernel::OM = Kernel::System::ObjectManager->new();

# require our helper
require '_Helper.pl';

# require our common library
require '_StepsLib.pl';

# feature specific steps 
When qr/delete a session$/, sub {
   ( S->{Response}, S->{ResponseContent} ) = _Delete(
      Token => S->{Token},
      URL   => S->{API_URL}.'/system/sessions/'.S->{Token},
   );
};
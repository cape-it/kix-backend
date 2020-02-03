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
#require './_StepsLib.pl';

# feature specific steps 

Given qr/a permission$/, sub {
   ( S->{Response}, S->{ResponseContent} ) = _Post(
      URL     => S->{API_URL}.'/system/roles/'.S->{RoleID}.'/permissions',
      Token   => S->{Token},
      Content => {
        Permission => {
            Target => "/tickets",
            TypeID => 1,
            Value => 12
        }
      }
   );
};

When qr/I create a permission$/, sub {
   ( S->{Response}, S->{ResponseContent} ) = _Post(
      URL     => S->{API_URL}.'/system/roles/'.S->{RoleID}.'/permissions',
      Token   => S->{Token},
      Content => {
        Permission => {
            Target => "/tickets",
            TypeID => 1,
            Value => 12
        }
      }
   );
};


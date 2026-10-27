use Modern::Perl;
use Test::More;
use CGI;

use Koha::Plugin::Com::Biblibre::Orb;
use Koha::Token;

my $class = 'Koha::Plugin::Com::Biblibre::Orb';
my %store;
my $out;

no warnings 'redefine';
local *Koha::Plugin::Com::Biblibre::Orb::retrieve_data = sub { $store{ $_[1] } };
local *Koha::Plugin::Com::Biblibre::Orb::store_data = sub { %store = ( %store, %{ $_[1] } ) };
local *Koha::Plugin::Com::Biblibre::Orb::go_home     = sub { };
local *Koha::Plugin::Com::Biblibre::Orb::output_html = sub { $out = [ @_[ 1, 2 ] ] };
local *Koha::Token::check_csrf = sub { 1 };
use warnings 'redefine';

my $p = bless { class => $class }, $class;

subtest 'hooks honour the Staff and OPAC settings' => sub {
    %store = ( image_on_staff => 0, image_on_opac => 0 );
    is $p->intranet_cover_images, '', 'no staff script when unchecked';
    is $p->opac_cover_images,     '', 'no OPAC script when unchecked';

    %store = ( image_on_staff => 1, image_on_opac => 1 );
    like $p->intranet_cover_images, qr/function addOrbCover/, 'staff script when checked';
    like $p->opac_cover_images,     qr/function addOrbCover/, 'OPAC script when checked';
};

subtest 'install and upgrade' => sub {
    %store = ();
    ok $p->install, 'install returns true';
    is_deeply [ @store{qw(image_on_staff image_on_opac)} ], [ 1, 1 ], 'install checks both boxes';

    %store = ( __INSTALLED_VERSION__ => '4.2' );
    ok $p->upgrade, 'upgrade returns true';
    is_deeply [ @store{qw(image_on_staff image_on_opac)} ], [ 1, 1 ],
      'upgrade from 4.2 checks both boxes';

    %store = ( __INSTALLED_VERSION__ => '4.3', image_on_staff => 0, image_on_opac => 0 );
    ok $p->upgrade, 'upgrade returns true';
    is_deeply [ @store{qw(image_on_staff image_on_opac)} ], [ 0, 0 ],
      'upgrade from 4.3 keeps the saved choice';

    %store = ( __INSTALLED_VERSION__ => '4.2', base_url => 'https://api.base-orb.fr' );
    $p->upgrade;
    ok !defined $store{base_url},
      'upgrade from 4.2 drops the never used base url, the default one keeps being used';

    %store = ( __INSTALLED_VERSION__ => '4.3', base_url => 'https://orb.example.org/v2' );
    $p->upgrade;
    is $store{base_url}, 'https://orb.example.org/v2', 'upgrade from 4.3 keeps the base url';
};

subtest 'configure save' => sub {
    local $ENV{REQUEST_METHOD} = 'POST';

    %store = ( access_password => 'old' );
    $p->{cgi} = CGI->new( { op => 'cud-save', access_password => '', clear_password => 1 } );
    $p->configure;
    ok !defined $store{access_password}, 'clear_password removes the password';
    ok !exists $store{resume_on_opac}, 'resume_on_opac is not stored';

    %store = ( access_password => 'old' );
    $p->{cgi} = CGI->new( { op => 'cud-save', access_password => '' } );
    $p->configure;
    is $store{access_password}, 'old', 'empty password keeps the saved one';

    %store = ( access_password => 'old' );
    $p->{cgi} = CGI->new( { op => 'cud-save', access_password => 'new' } );
    $p->configure;
    is $store{access_password}, 'new', 'typed password replaces the saved one';

    %store = ();
    $p->{cgi} = CGI->new(
        {
            op              => 'cud-save',
            base_url        => [ 'https://a.example', 'injected', 'x' ],
            access_username => [ 'user', 'access_password', 'x' ]
        }
    );
    $p->configure;
    ok !exists $store{injected}, 'repeated base_url cannot add settings';
    ok !exists $store{access_password}, 'repeated access_username cannot set the password';
    is $store{base_url}, 'https://a.example', 'first base_url kept';

    local $ENV{REQUEST_METHOD} = 'GET';
    %store = ( access_password => 'old' );
    $out   = undef;
    $p->{cgi} = CGI->new( { op => 'cud-save', access_password => 'x' } );
    $p->configure;
    is $out->[1], '403 Forbidden', 'GET save is refused';
    is $store{access_password}, 'old', 'GET save stores nothing';
};

done_testing;

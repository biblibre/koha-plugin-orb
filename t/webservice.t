use Modern::Perl;
use Test::More;

use Koha::Plugin::Com::Biblibre::Orb::Controller::Webservice;

my $W = 'Koha::Plugin::Com::Biblibre::Orb::Controller::Webservice';

subtest '_parse_isbn10s' => sub {
    my $parse = $W->can('_parse_isbn10s');
    is_deeply [ $parse->(' 2070368228, ,2070368228,0306406152 ') ],
      [ '2070368228', '0306406152' ], 'trimmed, empties dropped, deduped';
};

subtest '_orb_base_url' => sub {
    my $base = $W->can('_orb_base_url');
    is $base->('https://api.base-orb.fr/v1/')->as_string,
      'https://api.base-orb.fr/v1', 'trailing slash stripped';
    is $base->('http://api.base-orb.fr/v1')->as_string,
      'https://api.base-orb.fr/v1', 'http rejected';
    is $base->('not an url')->as_string, 'https://api.base-orb.fr/v1',
      'garbage rejected';
    is $base->(undef)->as_string, 'https://api.base-orb.fr/v1',
      'default when unset';
    is $base->('https://orb.example.org/v2')->host_port, 'orb.example.org:443',
      'custom host kept';
};

subtest '_products_url' => sub {
    my $url = $W->can('_products_url')
      ->( URI->new('https://api.base-orb.fr/v1'), [ '9782070368228', '9780306406157' ] );
    is $url->as_string,
      'https://api.base-orb.fr/v1/products?eans=9782070368228,9780306406157&sort=ean_asc',
      'no double slash, comma separated EANs';
};

subtest '_safe_url' => sub {
    is $W->can('_safe_url')->('javascript:alert(1)'), undef, 'javascript: rejected';
    is $W->can('_safe_url')->('https://a/b.jpg'), 'https://a/b.jpg', 'https kept';
};

subtest '_front_images' => sub {
    is_deeply $W->can('_front_images')
      ->( { images => { front => { original => { src => 'https://a/o.jpg' } } } } ),
      {
        thumbnail => { src => 'https://a/o.jpg' },
        original  => { src => 'https://a/o.jpg' }
      },
      'size fallback';
};

done_testing;

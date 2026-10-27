package Koha::Plugin::Com::Biblibre::Orb::Controller::Webservice;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use LWP::UserAgent;
use LWP::Authen::OAuth2;
use JSON;
use URI;

use C4::Koha qw(NormalizeISBN);

our $DEFAULT_BASE_URL = 'https://api.base-orb.fr/v1';

=head1 API

=head2 Methods

Controller function that handles getting Orb images

=cut

sub get_orb_images {
    my $c = shift->openapi->valid_input or return;

    my $isbn10s = $c->param('isbn10s');

    return $c->render(
        status  => 400,
        openapi => { error => "No ISBN10s provided" }
    ) unless $isbn10s;

    my @isbn10_list = _parse_isbn10s($isbn10s);
    my %isbn10_to_ean13_map;
    my @ean13_list;

    for my $isbn10 (@isbn10_list) {
        my $isbn13 = NormalizeISBN(
            {
                isbn          => $isbn10,
                format        => 'ISBN-13',
                strip_hyphens => 1,
            }
        );
        if ($isbn13) {
            push @ean13_list, $isbn13;
            $isbn10_to_ean13_map{$isbn13} = $isbn10;
        }
    }

    return $c->render(
        status  => 400,
        openapi => { error => "No valid ISBN13s generated" }
    ) unless @ean13_list;

    my $plugin   = Koha::Plugin::Com::Biblibre::Orb->new();
    my $base     = _orb_base_url( $plugin->retrieve_data('base_url') );
    my $ua       = _ua( $plugin, $base );
    my $response = $ua->get( _products_url( $base, \@ean13_list ) );

    if ( $response->is_success ) {
        my $contents = eval { decode_json( $response->decoded_content ) };
        my $data = ref $contents eq 'HASH' ? $contents->{'data'} : undef;

        return $c->render(
            status  => 500,
            openapi => { error => "Orb error: unexpected response" },
        ) unless ref $data eq 'ARRAY';

        # Orb output is untrusted: only keep the fields we use, for the EANs
        # we asked for, with images that are plain https URLs
        my @images;
        for my $item (@$data) {
            next unless ref $item eq 'HASH';
            my $ean13 = $item->{'ean13'};
            next unless defined $ean13 && !ref $ean13;
            next unless exists $isbn10_to_ean13_map{$ean13};

            my $front = _front_images($item);
            next unless $front;

            push @images,
              {
                ean13  => $ean13,
                isbn10 => $isbn10_to_ean13_map{$ean13},
                images => { front => $front },
              };
        }

        return $c->render(
            status  => 200,
            openapi => \@images,
        );
    }
    else {
        warn "Orb error: " . $response->status_line;
        return $c->render(
            status  => 500,
            openapi => { error => "Orb webservice unavailable" },
        );
    }
}

sub _front_images {
    my ($item) = @_;

    my $front = ref $item->{'images'} eq 'HASH' ? $item->{'images'}{'front'} : undef;
    return unless ref $front eq 'HASH';

    my %src;
    for my $size (qw(thumbnail original)) {
        my $image = $front->{$size};
        next unless ref $image eq 'HASH';
        my $url = _safe_url( $image->{'src'} );
        $src{$size} = $url if $url;
    }
    return unless %src;

    # The JS reads both sizes, fall back on the one we have
    $src{thumbnail} //= $src{original};
    $src{original}  //= $src{thumbnail};

    return {
        thumbnail => { src => $src{thumbnail} },
        original  => { src => $src{original} },
    };
}

sub _safe_url {
    my ($url) = @_;

    return unless defined $url && !ref $url;

    my $uri = URI->new($url);
    return unless $uri->scheme && $uri->scheme eq 'https' && $uri->host;

    return $uri->canonical->as_string;
}

sub _parse_isbn10s {
    my ($isbn10s) = @_;

    my %seen;
    return grep { length && !$seen{$_}++ }
      map { s/^\s+|\s+$//gr } split( /,/, $isbn10s // '' );
}

# Credentials are sent to this URL, so anything but https falls back on the
# default one
sub _orb_base_url {
    my ($stored) = @_;

    my $uri = URI->new( $stored // '' );
    $uri = URI->new($DEFAULT_BASE_URL)
      unless $uri->scheme && $uri->scheme eq 'https' && $uri->host;

    my $path = $uri->path;
    $path =~ s{/+$}{};
    $uri->path($path);

    return $uri;
}

sub _products_url {
    my ( $base, $ean13s ) = @_;

    my $url = $base->clone;
    $url->path( $url->path . '/products' );
    $url->query( 'eans=' . join( ',', @$ean13s ) . '&sort=ean_asc' );

    return $url;
}

sub _ua {
    my ( $plugin, $base ) = @_;

    my $ua = LWP::UserAgent->new( timeout => 10 );
    $ua->credentials(
        $base->host_port, '',
        $plugin->retrieve_data('access_username'),
        $plugin->retrieve_data('access_password')
    );

    return $ua;
}

1;

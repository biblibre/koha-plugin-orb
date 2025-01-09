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
use HTTP::Request::Common;
use JSON;

use C4::Context;

=head1 API

=head2 Methods

Controller function that handles getting Electre images

=cut

sub get_orb_images {
    my $c = shift->openapi->valid_input or return;
    my $eans = $c->param('eans');

    my $ua = $c->_ua;
    my $response = $ua->get("https://api.base-orb.fr/v1/products?eans=$eans&sort=ean_asc");
    if ( $response->is_success ) {
        my $contents = decode_json($response->decoded_content);

        return $c->render(
            status => 200,
            data   => to_json($contents->{'data'}),
        );
    }
    elsif ( $response->is_error ) {
        return $c->render(
            status  => 500,
            openapi =>
              { error => "Orb error: " . $response->status_line },
        );
    }
}

sub _ua {
    my $ua = LWP::UserAgent->new();
    my $plugin = Koha::Plugin::Com::Biblibre::Orb->new();

    my $username = $plugin->retrieve_data('access_username');
    my $password = $plugin->retrieve_data('access_password');
    $ua->credentials('api.base-orb.fr:443', '', $username, $password);

    return $ua;
}

sub _is_thumbnail_size {
    my ( $self, $side ) = @_;

    my $plugin = Koha::Plugin::Com::Biblibre::Orb->new();

    return $plugin->retrieve_data("thumbnail_on_$side");
}

1;

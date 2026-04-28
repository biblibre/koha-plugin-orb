package Koha::Plugin::Com::Biblibre::Orb;

use Modern::Perl;
use base       qw(Koha::Plugins::Base);
use Mojo::JSON qw(decode_json);
use C4::Context;

our $VERSION         = "4.1";
our $MINIMUM_VERSION = "23.05";

our $metadata = {
    name            => 'Plugin Orb',
    author          => 'Thibaud Guillot',
    date_authored   => '2024-11-18',
    date_updated    => "2026-02-18",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     =>
      'This plugin implements enhanced content from Orb webservice',
    namespace => 'orb',
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    $self->{config_table} = $self->get_qualified_table_name('config');

    return $self;
}

# Mandatory even if does nothing
sub install {
    my ( $self, $args ) = @_;

    return 1;
}

# Mandatory even if does nothing
sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

# Mandatory even if does nothing
sub uninstall {
    my ( $self, $args ) = @_;

    return 1;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template =
          $self->get_template( { file => 'templates/index/configure.tt' } );

        my $base_url        = $self->retrieve_data('base_url')        // undef;
        my $access_username = $self->retrieve_data('access_username') // undef;
        my $access_password = $self->retrieve_data('access_password') // undef;
        my $image_on_staff  = $self->retrieve_data('image_on_staff')  // 0;
        my $image_on_opac   = $self->retrieve_data('image_on_opac')   // 0;
        my $thumbnail_on_staff = $self->retrieve_data('thumbnail_on_staff')
          // 0;
        my $thumbnail_on_opac = $self->retrieve_data('thumbnail_on_opac') // 0;

        $template->param(
            base_url           => $base_url,
            access_username    => $access_username,
            access_password    => $access_password,
            image_on_staff     => $image_on_staff,
            image_on_opac      => $image_on_opac,
            thumbnail_on_staff => $thumbnail_on_staff,
            thumbnail_on_opac  => $thumbnail_on_opac,
        );

        $self->output_html( $template->output() );
    }
    else {
        my $data = {
            base_url => $cgi->param('base_url') ? $cgi->param('base_url')
            : undef,
            access_username => $cgi->param('access_username')
            ? $cgi->param('access_username')
            : undef,
            access_password => $cgi->param('access_password')
            ? $cgi->param('access_password')
            : undef,
            resume_on_opac     => $cgi->param('resume_on_opac')     ? 1 : 0,
            image_on_staff     => $cgi->param('image_on_staff')     ? 1 : 0,
            image_on_opac      => $cgi->param('image_on_opac')      ? 1 : 0,
            thumbnail_on_staff => $cgi->param('thumbnail_on_staff') ? 1 : 0,
            thumbnail_on_opac  => $cgi->param('thumbnail_on_opac')  ? 1 : 0,
        };

        $self->store_data($data);
        $self->go_home();
    }
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_dir = $self->mbf_dir();

    my $schema = JSON::Validator::Schema::OpenAPIv2->new;
    my $spec   = $schema->resolve( $spec_dir . '/openapi.yaml' );

    return $self->_convert_refs_to_absolute( $spec->data->{'paths'},
        'file://' . $spec_dir . '/' );
}

sub api_namespace {
    my ($self) = @_;

    return 'orb';
}

sub _convert_refs_to_absolute {
    my ( $self, $hashref, $path_prefix ) = @_;

    foreach my $key ( keys %{$hashref} ) {
        if ( $key eq '$ref' ) {
            if ( $hashref->{$key} =~ /^(\.\/)?openapi/ ) {
                $hashref->{$key} = $path_prefix . $hashref->{$key};
            }
        }
        elsif ( ref $hashref->{$key} eq 'HASH' ) {
            $hashref->{$key} =
              $self->_convert_refs_to_absolute( $hashref->{$key},
                $path_prefix );
        }
        elsif ( ref( $hashref->{$key} ) eq 'ARRAY' ) {
            $hashref->{$key} =
              $self->_convert_array_refs_to_absolute( $hashref->{$key},
                $path_prefix );
        }
    }
    return $hashref;
}

sub _convert_array_refs_to_absolute {
    my ( $self, $arrayref, $path_prefix ) = @_;

    my @res;
    foreach my $item ( @{$arrayref} ) {
        if ( ref($item) eq 'HASH' ) {
            $item = $self->_convert_refs_to_absolute( $item, $path_prefix );
        }
        elsif ( ref($item) eq 'ARRAY' ) {
            $item =
              $self->_convert_array_refs_to_absolute( $item, $path_prefix );
        }
        push @res, $item;
    }
    return \@res;
}

sub intranet_cover_images {
    my ($self) = @_;
    my $cgi = $self->{'cgi'};
    my $thumbnail_on_staff = $self->_is_thumbnail_size('staff');

    my $js = <<"JS";
    <script>
        function addOrbCover(e) {
            const search_results_images = document.querySelectorAll('.cover-slides, .cover-slider');
            const existingCovers = document.querySelectorAll('.cover-image');
            const divDetail = \$('#catalogue_detail_biblio');
            const onResultPage = divDetail.length ? false : true;
            if(search_results_images.length){
                const isbn10s = [];
                const thumbnails = {};
                search_results_images.forEach((div, i) => {
                    let isbn = div.dataset.isbn;

                    if (isbn) {
                        const originalIsbn = isbn.length == 10 ? isbn : null;
                        if (originalIsbn) {
                            if (!thumbnails[originalIsbn]) {
                                thumbnails[originalIsbn] = [];
                            }
                            thumbnails[originalIsbn].push(div);
                            isbn10s.push(originalIsbn);
                        }
                    }
                    if(!onResultPage && existingCovers.length == 0 && isbn){
                        const coverSlide = thumbnails[isbn];
                        if(coverSlide){
                            \$(coverSlide).append(`
                                <div id="orb-bookcoverimg" class="cover-image orb-bookcoverimg">
                                    <a href="#" >
                                        <img class="orb-cover" alt="Orb cover image" />
                                    </a>
                                    <div class="hint">Image from Orb</div>
                                </div>
                            `);
                        }
                    }
                });

                if (isbn10s.length > 0) {
                    \$.get(
                        `/api/v1/contrib/orb/images?isbn10s=\${isbn10s.join(',')}`, function( response ) {
                            const injectedImgs = [];
                            if(response.length > 0) {
                                response.forEach(doc => {
                                    let sizeSrc;
                                    const coverSlides = thumbnails[doc.isbn10];
                                    if (coverSlides && doc.images) {
                                        if(onResultPage) {
                                            sizeSrc = doc.images.front.thumbnail.src;
                                            coverSlides.forEach(coverSlide => {
                                                const biblionumber = coverSlide.getAttribute('data-biblionumber');
                                                const divId = `orb-bookcoverimg-\${biblionumber}`;
                                                const wrapper = document.createElement('div');
                                                wrapper.id = divId;
                                                wrapper.className = 'cover-image orb-bookcoverimg';
                                                wrapper.innerHTML = `
                                                    <a href="\${sizeSrc}" >
                                                        <img class="orb-cover" src="\${sizeSrc}" alt="Orb cover image" />
                                                    </a>
                                                    <div class="hint">Orb cover image</div>
                                                `;
                                                coverSlide.appendChild(wrapper);
                                                injectedImgs.push(wrapper.querySelector('img'));
                                                // Manually remove no-image div if present
                                                if(coverSlide.querySelector('.no-image')){
                                                    coverSlide.querySelector('.no-image').remove();
                                                }
                                            });

                                        } else {
                                            sizeSrc = '$thumbnail_on_staff' == 1 ? doc.images.front.thumbnail.src : doc.images.front.original.src;
                                            if(existingCovers.length > 0) {
                                                \$(coverSlides).append(`
                                                    <div id="orb-bookcoverimg" class="cover-image orb-bookcoverimg">
                                                        <a href="\${sizeSrc}" >
                                                            <img class="orb-cover" src="\${sizeSrc}" alt="Orb cover image" />
                                                        </a>
                                                        <div class="hint">Image from Orb</div>
                                                    </div>
                                                `);
                                                verify_cover_images();
                                            } else {
                                                const orbThumbnail = \$("#orb-bookcoverimg");
                                                orbThumbnail.find('img').attr('src', sizeSrc);
                                                orbThumbnail.find('a').attr('href', sizeSrc);
                                            }
                                        }
                                    }
                                });
                            } else {
                                const orbThumbnail = \$("#orb-bookcoverimg");
                                orbThumbnail.remove();
                                verify_cover_images();
                            }

                            if (onResultPage) {
                                const total = injectedImgs.length;
                                let done = 0;
                                if (total === 0) { verify_cover_images(); }
                                injectedImgs.forEach(img => {
                                    if (img.complete) {
                                        done++;
                                        if (done === total) verify_cover_images();
                                    } else {
                                        img.addEventListener('load',  () => { done++; if (done === total) verify_cover_images(); });
                                        img.addEventListener('error', () => { done++; if (done === total) verify_cover_images(); });
                                    }
                                });
                            }
                        }
                );
                }
            }
        }
    document.addEventListener('DOMContentLoaded', addOrbCover, true);
    </script>
JS

    return "$js";
}

sub opac_cover_images {
    my ($self) = @_;
    my $cgi = $self->{'cgi'};
    my $thumbnail_on_opac = $self->_is_thumbnail_size('opac');

    my $js = <<"JS";
    <script>
        function addOrbCover() {
            const search_results_images = document.querySelectorAll('.cover-slides, .cover-slider');
            const existingCovers = document.querySelectorAll('.cover-image');
            const divDetail = \$('#catalogue_detail_biblio');
            const onResultPage = divDetail.length ? false : true;
            if(search_results_images.length){
                const isbn10s = [];
                const thumbnails = {};
                search_results_images.forEach((div, i) => {
                    let isbn = div.dataset.isbn;

                    if (isbn) {
                        const originalIsbn = isbn.length == 10 ? isbn : null;
                        if (originalIsbn) {
                            if (!thumbnails[originalIsbn]) {
                                thumbnails[originalIsbn] = [];
                            }
                            thumbnails[originalIsbn].push(div);
                            isbn10s.push(originalIsbn);
                        }
                    }
                    if(!onResultPage && existingCovers.length == 0 && isbn){
                        const coverSlide = thumbnails[isbn];
                        if(coverSlide){
                            \$(coverSlide).append(`
                                <div class="cover-image" id="orb-bookcoverimg">
                                    <a href="#" >
                                        <img alt="Orb cover image" class="orb-cover" />
                                    </a>
                                    <div class="hint">Image from Orb</div>
                                </div>
                            `);
                        }
                    }
                });

                if (isbn10s.length > 0) {
                    \$.get(
                        `/api/v1/contrib/orb/images?isbn10s=\${isbn10s.join(',')}`, function( response ) {
                            const injectedImgs = [];
                            if(response.length > 0) {
                                response.forEach(doc => {
                                    let sizeSrc;
                                    const coverSlides = thumbnails[doc.isbn10];
                                    if (coverSlides && doc.images) {
                                        if (onResultPage) {
                                            sizeSrc = doc.images.front.thumbnail.src;
                                            coverSlides.forEach(coverSlide => {
                                                if (coverSlide) {
                                                    const imgTitle = coverSlide.dataset.title;
                                                    const wrapper = document.createElement('div');
                                                    wrapper.className = 'cover-image orb-coverimg';
                                                    wrapper.title = imgTitle;
                                                    wrapper.innerHTML = `
                                                        <a href="\${sizeSrc}" >
                                                            <img src="\${sizeSrc}" alt="Orb cover image" class="item-thumbnail" />
                                                        </a>
                                                        <div class="hint">Image from Orb</div>
                                                    `;
                                                    coverSlide.appendChild(wrapper);
                                                    injectedImgs.push(wrapper.querySelector('img'));
                                                }
                                            });
                                        } else {
                                            sizeSrc = '$thumbnail_on_opac' == 1 ? doc.images.front.thumbnail.src : doc.images.front.original.src;
                                            if(existingCovers.length > 0) {
                                                \$(coverSlides).append(`
                                                    <div class="cover-image" id="orb-bookcoverimg">
                                                        <a href="\${sizeSrc}" >
                                                            <img src="\${sizeSrc}" alt="Orb cover image" class="orb-cover" />
                                                        </a>
                                                        <div class="hint">Image from Orb</div>
                                                    </div>
                                                `);
                                            } else {
                                                const orbThumbnail = \$("#orb-bookcoverimg");
                                                orbThumbnail.find('img').attr('src', sizeSrc);
                                                orbThumbnail.find('a').attr('href', sizeSrc);
                                            }
                                        }
                                        \$(".cover-nav").remove();
                                    }
                                });
                            } else {
                                const orbThumbnail = \$("#orb-bookcoverimg");
                                orbThumbnail.remove();
                                verify_cover_images();
                                return;
                            }

                            if (onResultPage) {
                                const total = injectedImgs.length;
                                let done = 0;
                                if (total === 0) { verify_cover_images(); return; }
                                injectedImgs.forEach(img => {
                                    if (img.complete) {
                                        done++;
                                        if (done === total) verify_cover_images();
                                    } else {
                                        img.addEventListener('load',  () => { done++; if (done === total) verify_cover_images(); });
                                        img.addEventListener('error', () => { done++; if (done === total) verify_cover_images(); });
                                    }
                                });
                            } else {
                                verify_cover_images();
                            }
                        });
                }
            }
        }
    document.addEventListener('DOMContentLoaded', addOrbCover, true);
    </script>
JS

    return "$js";
}

sub _is_thumbnail_size {
    my ( $self, $side ) = @_;

    my $plugin = Koha::Plugin::Com::Biblibre::Orb->new();

    return $plugin->retrieve_data("thumbnail_on_$side");
}

1;

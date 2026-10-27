package Koha::Plugin::Com::Biblibre::Orb;

use Modern::Perl;
use base       qw(Koha::Plugins::Base);
use Koha::Token;

our $VERSION         = "4.3";
our $MINIMUM_VERSION = "23.05";

our $metadata = {
    name            => 'Plugin Orb',
    author          => 'Thibaud Guillot',
    date_authored   => '2024-11-18',
    date_updated    => "2026-10-27",
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

sub install {
    my ( $self, $args ) = @_;

    $self->store_data( { image_on_staff => 1, image_on_opac => 1 } );

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    # Up to 4.2 the Staff/OPAC boxes and the base url had no effect: covers
    # were always shown, from the default url. Keep that behaviour now that
    # these settings are honoured
    my $installed = $self->retrieve_data('__INSTALLED_VERSION__') || 0;
    if ( version->parse($installed) < version->parse('4.3') ) {
        $self->store_data(
            { image_on_staff => 1, image_on_opac => 1, base_url => undef } );
    }

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

    unless ( ( $cgi->param('op') // '' ) eq 'cud-save' ) {
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
            has_password       => ( defined $access_password && $access_password ne '' ) ? 1 : 0,
            image_on_staff     => $image_on_staff,
            image_on_opac      => $image_on_opac,
            thumbnail_on_staff => $thumbnail_on_staff,
            thumbnail_on_opac  => $thumbnail_on_opac,
        );

        $self->output_html( $template->output() );
    }
    else {
        # Koha < 24.05 has no CSRF middleware, so the token and the method
        # are checked here too
        unless (
            $cgi->request_method eq 'POST'
            && Koha::Token->new->check_csrf(
                {
                    session_id => scalar $cgi->cookie('CGISESSID'),
                    token      => scalar $cgi->param('csrf_token'),
                }
            )
          )
        {
            $self->output_html( 'Invalid request', '403 Forbidden' );
            return;
        }

        my $access_password = $cgi->param('access_password');

        # scalar: in list context a repeated parameter would add keys to $data
        my $data = {
            base_url        => scalar $cgi->param('base_url')        || undef,
            access_username => scalar $cgi->param('access_username') || undef,
            image_on_staff     => $cgi->param('image_on_staff')     ? 1 : 0,
            image_on_opac      => $cgi->param('image_on_opac')      ? 1 : 0,
            thumbnail_on_staff => $cgi->param('thumbnail_on_staff') ? 1 : 0,
            thumbnail_on_opac  => $cgi->param('thumbnail_on_opac')  ? 1 : 0,
        };

        if ( $cgi->param('clear_password') ) {
            $data->{access_password} = undef;
        }
        elsif ( defined $access_password && $access_password ne '' ) {
            $data->{access_password} = $access_password;
        }

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

sub _orb_js_helpers {
    return <<'JS';
        // Only accept absolute https urls coming from the Orb webservice response
        function orbSafeUrl(url) {
            if (typeof url !== 'string') {
                return null;
            }
            try {
                const parsed = new URL(url);
                return parsed.protocol === 'https:' ? parsed.href : null;
            } catch (e) {
                return null;
            }
        }

        // Build the cover markup with DOM APIs so Orb data is never parsed as HTML
        function buildOrbCover({ id, className, title, imgClass, src, hint }) {
            const div = document.createElement('div');
            div.className = className;
            if (id) {
                div.id = id;
            }
            if (title) {
                div.title = title;
            }
            const link = document.createElement('a');
            link.href = src || '#';
            const img = document.createElement('img');
            img.className = imgClass;
            img.alt = 'Orb cover image';
            if (src) {
                img.src = src;
            }
            link.appendChild(img);
            const hintDiv = document.createElement('div');
            hintDiv.className = 'hint';
            hintDiv.textContent = hint;
            div.appendChild(link);
            div.appendChild(hintDiv);
            return div;
        }

        // verify_cover_images is not defined on every page (OPAC results before 24.05)
        function orbVerifyCovers() {
            if (typeof verify_cover_images === 'function') {
                verify_cover_images();
            }
        }

        // Remove the slots prepared before the API call when no cover comes back
        function orbCleanup() {
            document.querySelectorAll('.orb-placeholder').forEach(ph => ph.remove());
            $("#orb-bookcoverimg").remove();
            orbVerifyCovers();
        }
JS
}

sub intranet_cover_images {
    my ($self) = @_;
    return '' unless $self->retrieve_data('image_on_staff');

    my $thumbnail_on_staff = $self->_is_thumbnail_size('staff');
    my $orb_js_helpers = $self->_orb_js_helpers;

    my $js = <<"JS";
    <script>
$orb_js_helpers
        function addOrbCover(e) {
            const search_results_images = document.querySelectorAll('.cover-slides, .cover-slider');
            const existingCovers = document.querySelectorAll('.cover-image');
            const divDetail = \$('#catalogue_detail_biblio');
            const onResultPage = divDetail.length ? false : true;
            if(search_results_images.length){
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
                        }
                    }
                    if(!onResultPage && existingCovers.length == 0 && isbn){
                        const coverSlide = thumbnails[isbn];
                        if(coverSlide){
                            \$(coverSlide).append(buildOrbCover({
                                id: 'orb-bookcoverimg',
                                className: 'cover-image orb-bookcoverimg',
                                imgClass: 'orb-cover',
                                hint: 'Image from Orb',
                            }));
                        }
                    }
                });

                // One entry per ISBN even if several records share it
                const isbn10s = Object.keys(thumbnails);
                if (isbn10s.length > 0) {
                    if (onResultPage) {
                        Object.values(thumbnails).forEach(slides => {
                            slides.forEach(slide => {
                                const ph = document.createElement('div');
                                ph.className = 'cover-image orb-placeholder';
                                ph.style.display = 'none';
                                const phImg = document.createElement('img');
                                phImg.style.display = 'none';
                                ph.appendChild(phImg);
                                slide.appendChild(ph);
                            });
                        });
                    }
                    \$.get(
                        `/api/v1/contrib/orb/images?isbn10s=\${isbn10s.join(',')}`, function( response ) {
                            document.querySelectorAll('.orb-placeholder').forEach(ph => ph.remove());
                            if(response.length > 0) {
                                response.forEach(doc => {
                                    let sizeSrc;
                                    const coverSlides = thumbnails[doc.isbn10];
                                    if (coverSlides && doc.images) {
                                        if(onResultPage) {
                                            sizeSrc = orbSafeUrl(doc.images.front.thumbnail.src);
                                            if (sizeSrc) {
                                                coverSlides.forEach(coverSlide => {
                                                    const biblionumber = coverSlide.getAttribute('data-biblionumber');
                                                    coverSlide.appendChild(buildOrbCover({
                                                        id: 'orb-bookcoverimg-' + biblionumber,
                                                        className: 'cover-image orb-bookcoverimg',
                                                        imgClass: 'orb-cover',
                                                        src: sizeSrc,
                                                        hint: 'Orb cover image',
                                                    }));
                                                    // Manually remove no-image div if present
                                                    if(coverSlide.querySelector('.no-image')){
                                                        coverSlide.querySelector('.no-image').remove();
                                                    }
                                                });
                                            }

                                        } else {
                                            sizeSrc = orbSafeUrl('$thumbnail_on_staff' == 1 ? doc.images.front.thumbnail.src : doc.images.front.original.src);
                                            if (!sizeSrc) {
                                                // Drop the empty slot prepared before the call
                                                if(existingCovers.length == 0) {
                                                    \$("#orb-bookcoverimg").remove();
                                                    orbVerifyCovers();
                                                }
                                            } else if(existingCovers.length > 0) {
                                                \$(coverSlides).append(buildOrbCover({
                                                    id: 'orb-bookcoverimg',
                                                    className: 'cover-image orb-bookcoverimg',
                                                    imgClass: 'orb-cover',
                                                    src: sizeSrc,
                                                    hint: 'Image from Orb',
                                                }));
                                                orbVerifyCovers();
                                            } else {
                                                const orbThumbnail = \$("#orb-bookcoverimg");
                                                orbThumbnail.find('img').attr('src', sizeSrc);
                                                orbThumbnail.find('a').attr('href', sizeSrc);
                                            }
                                        }
                                    }
                                });
                            } else {
                                orbCleanup();
                            }

                            if (onResultPage) {
                                const length = \$('.orb-bookcoverimg').length;
                                let i = 0;
                                \$('.orb-cover').on('load', () => {
                                    i++;
                                    if (i == length) {
                                        orbVerifyCovers();
                                    }
                                });
                            }
                        }
                ).fail(orbCleanup);
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
    return '' unless $self->retrieve_data('image_on_opac');

    my $thumbnail_on_opac = $self->_is_thumbnail_size('opac');
    my $orb_js_helpers = $self->_orb_js_helpers;

    my $js = <<"JS";
    <script>
$orb_js_helpers
        function addOrbCover() {
            const search_results_images = document.querySelectorAll('.cover-slides, .cover-slider');
            const existingCovers = document.querySelectorAll('.cover-image');
            const divDetail = \$('#catalogue_detail_biblio');
            const onResultPage = divDetail.length ? false : true;
            if(search_results_images.length){
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
                        }
                    }
                    if(!onResultPage && existingCovers.length == 0 && isbn){
                        const coverSlide = thumbnails[isbn];
                        if(coverSlide){
                            \$(coverSlide).append(buildOrbCover({
                                id: 'orb-bookcoverimg',
                                className: 'cover-image',
                                imgClass: 'orb-cover',
                                hint: 'Image from Orb',
                            }));
                        }
                    }
                });

                // One entry per ISBN even if several records share it
                const isbn10s = Object.keys(thumbnails);
                if (isbn10s.length > 0) {
                    if (onResultPage) {
                        Object.values(thumbnails).forEach(slides => {
                            slides.forEach(slide => {
                                const ph = document.createElement('div');
                                ph.className = 'cover-image orb-placeholder';
                                ph.style.display = 'none';
                                const phImg = document.createElement('img');
                                phImg.style.display = 'none';
                                ph.appendChild(phImg);
                                slide.appendChild(ph);
                            });
                        });
                    }
                    \$.get(
                        `/api/v1/contrib/orb/images?isbn10s=\${isbn10s.join(',')}`, function( response ) {
                            document.querySelectorAll('.orb-placeholder').forEach(ph => ph.remove());
                            if(response.length > 0) {
                                response.forEach(doc => {
                                    let sizeSrc;
                                    const coverSlides = thumbnails[doc.isbn10];
                                    if (coverSlides && doc.images) {
                                        if (onResultPage) {
                                            sizeSrc = orbSafeUrl(doc.images.front.thumbnail.src);
                                            if (sizeSrc) {
                                                coverSlides.forEach(coverSlide => {
                                                    if (coverSlide) {
                                                        coverSlide.appendChild(buildOrbCover({
                                                            className: 'cover-image orb-coverimg',
                                                            title: coverSlide.dataset.title,
                                                            imgClass: 'item-thumbnail',
                                                            src: sizeSrc,
                                                            hint: 'Image from Orb',
                                                        }));
                                                    }
                                                });
                                            }
                                        } else {
                                            sizeSrc = orbSafeUrl('$thumbnail_on_opac' == 1 ? doc.images.front.thumbnail.src : doc.images.front.original.src);
                                            if (!sizeSrc) {
                                                // Drop the empty slot prepared before the call
                                                if(existingCovers.length == 0) {
                                                    \$("#orb-bookcoverimg").remove();
                                                }
                                            } else if(existingCovers.length > 0) {
                                                \$(coverSlides).append(buildOrbCover({
                                                    id: 'orb-bookcoverimg',
                                                    className: 'cover-image',
                                                    imgClass: 'orb-cover',
                                                    src: sizeSrc,
                                                    hint: 'Image from Orb',
                                                }));
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
                            }
                            orbVerifyCovers();
                        }).fail(orbCleanup);
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

    return $self->retrieve_data("thumbnail_on_$side");
}

1;

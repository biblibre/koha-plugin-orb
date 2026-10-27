# Orb webservice Koha plugin

This plugin lets you enrich records with covers from the Orb webservice

## What it does

- Adds a REST endpoint `GET /api/v1/contrib/orb/images?isbn10s=<isbn10>,<isbn10>,...`
  that converts the ISBN-10s to EAN-13, queries Orb (`/v1/products`) with the
  configured credentials and returns, for each matching product, its `ean13`,
  `isbn10` and front cover URLs (`thumbnail` and `original`).
  The Orb response is filtered server side: only those fields are kept, only
  for the EANs that were requested, and only `https` image URLs are returned.
- Uses the `intranet_cover_images` and `opac_cover_images` hooks to inject a
  script that calls this endpoint and displays the Orb covers:
  - on search results pages (thumbnail size),
  - on the record detail page (thumbnail or original size, depending on the
    configuration), alongside covers from other enabled providers.
- Records are matched on the ISBN-10 found in the `data-isbn` attribute of the
  cover containers.
- If the API call fails, the empty Orb slot is removed and the other cover
  providers are displayed as usual.

## Requirements

- Koha 23.05 or later (the cover image hooks were introduced in 23.05). The
  configuration form is protected against CSRF on every supported version: from
  24.05 Koha checks the token itself, and the plugin checks it again, which is
  what protects it on 23.05 and 23.11
- Orb API credentials access
- LWP::Authen::OAuth2

## Setup

Once the plugin is installed, you can access the plugin's configuration in the Koha's plugins home page.
- find the **Plugin Orb** plugin in the table
- click on *Action -> configure*
- add your credentials and settings

Settings:
- *Orb base url*: must be an `https` URL, otherwise the default
  `https://api.base-orb.fr/v1` is used (credentials are never sent in clear).
- *Orb username* / *Orb password*: the password is never displayed back in the
  form. Leave the field empty to keep the saved password, type a new one to
  replace it, or check *Clear the saved password* to remove it.
- *Show Orb images*: *Staff* and *OPAC* enable the covers on each interface
  (both are checked on install and when upgrading from 4.2 or older, and the
  base url is emptied on that upgrade since it was not used before), with the
  cover size to use on the detail page.

## Tests

From the plugin root, with Koha in `PERL5LIB`:

    prove -I. t/

## Test plan

1. Install and enable the plugin, make sure `enable_plugins` is set in
   `koha-conf.xml`.
2. Go to the plugin configuration page and fill in the Orb username and
   password, check *Staff* and *OPAC*, save. Set *Orb base url* to
   `https://api.base-orb.fr/v1/` (trailing slash): covers still load.
3. Reopen the configuration:
   - the username is displayed, the password field is empty and a hint says a
     password is saved,
   - the browser dev tools (Network tab) show the save was a `POST` and the
     password does not appear in the URL nor in the Apache/Plack access logs.
4. Change an option without typing a password, save: the covers still load
   (the password was kept). Type a wrong password, save: covers no longer load.
   Put the right password back. Check *Clear the saved password*, save: the
   hint says no password is saved and covers no longer load. Put it back.
5. Open `/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::Com::Biblibre::Orb&method=configure&op=cud-save&access_password=x`
   (a GET): the request is refused and the configuration is not changed (403
   under Plack, 400 under the `bin/intranet` Mojolicious dev server). A POST
   without a valid `csrf_token` is refused with a 403.
6. In the staff interface, search for records having an ISBN-10 known by Orb:
   Orb covers are displayed on the results page with the *Orb cover image*
   hint.
7. Open the detail page of one of these records: the Orb cover is displayed,
   in thumbnail or original size according to *Thumbnail size on detail page*.
8. Repeat 6 and 7 on the OPAC. Uncheck *OPAC*, save: no Orb cover on the
   OPAC anymore, still shown in the staff interface. Check it back.
9. Call the API directly (it is public, so that the anonymous OPAC can use it):
   `curl '<staff_url>/api/v1/contrib/orb/images?isbn10s=<isbn10>'`
   - the response only contains `ean13`, `isbn10` and `images.front.thumbnail.src`
     / `images.front.original.src`,
   - without `isbn10s`, or with an invalid ISBN, the API answers 400.
10. Untrusted Orb data: temporarily make the controller return an image `src`
   like `javascript:alert(1)` or `https://x/a.jpg"><img src=x onerror=alert(1)>`
   (or point it to a mock server): no script is run, the first one is dropped,
   the second one is URL encoded.
11. API failure: set *Orb base url* to `https://127.0.0.1:9`, open a detail
    page: no empty Orb slot, the other providers' covers still navigate.
    Restore the base url.

_Enjoy !_

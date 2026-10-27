# 2026-10-27
**Version 4.3**

**Upgrade note:** the Staff and OPAC checkboxes now really enable covers on each side. They had no effect before, so the upgrade checks both of them to keep covers displayed; uncheck them to hide Orb covers. The *Orb base url* setting is now used too: the upgrade empties it so the default `https://api.base-orb.fr/v1` keeps being used; set it again only if Orb gave you another url.

- Do not display the saved password in the configuration form, only replace it when a new one is typed
- Save the configuration with POST only, with a CSRF token checked by the plugin itself (Koha < 24.05 has no CSRF middleware)
- Read the form parameters in scalar context: a repeated `base_url` or `access_username` could set other settings, the password included
- Filter the Orb response server side (known fields, requested EANs, https image urls only)
- Build covers with DOM APIs instead of innerHTML
- Add a 10s timeout on Orb calls, query each ISBN only once, remove dead code
- Use the configured Orb base url (https only), hide upstream errors from API callers
- Honour the Staff and OPAC settings, allow clearing the saved password
- Remove the empty Orb slot when the API call fails
- Only call `verify_cover_images()` when the page defines it (OPAC results before 24.05)
- Replace the jQuery 3 deprecated `.load(fn)` with `.on("load", fn)` on staff search results
- Add unit tests (`prove -I. t/`)
- Describe the plugin and add a test plan in the README

# 2026-05-04
**Version 4.2**

- Bypass early cleanup by adding placeholder system 

# 2026-02-18
**Version 4.1**

- Add missing 400 and 500 error responses to OpenAPI spec
- Fix src injection if none images is provided by Orb

# 2026-02-06
**Version 4.0**

- Use isbn10 to get normalize isbn13 to get more covers
- Fix cover nav when more than one provider is active

# 2026-01-07
**Version 3.0**

- Fix bad header on api calls
- Fix covers display and request when many providers are active or when Orb is the only one
- Improve code and fix typo

# 2025-07-08
**Version 2.0**

- Remove permissions and useless api response code
- Add html filters

# 2025-03-24
**Version 1.1**

- Fix config form input and label
- Add correct permissions to API calls

# 2024-11-21
**Version 1.0**

Possibility to get enhanced content from Orb webservice like :
- covers (two sizes :  120x160 and 475x500 )

_Note that cover size is only in 120x160 format on results pages on the OPAC and Admin/Staff sides._

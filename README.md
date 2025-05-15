# Supabase

Toit client for Supabase.

This package supports Supabase's authentication, REST, RPC, and storage API.

This is a work in progress. The API is not stable yet, and some functionality is missing.

## Usage

See the [examples](examples) folder for examples of how to use this package.

``` toit
import supabase
import certificate_roots

main:
  // Create a client.
  // Ideally, you would also like to provide a local storage, so that
  // authentication tokens can be stored.
  // See the examples folder for an example of how to do this.
  client := supabase.Client.tls
      --uri="https://<project>.supabase.co"
      --anon="<anon_key>"

  client.auth.sign_in --email="<email>" --password="<password>"
  rows := client.rest.select "<table>"
  rows.do:
    print it
```

## Features and bugs
Please file feature requests and bugs at the [issue tracker](https://github.com/toitware/toit-supabase/issues).

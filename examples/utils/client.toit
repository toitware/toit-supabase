// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import certificate-roots
import host.os
import supabase
import .local-storage

SUPABASE-URL ::= ""
SUPABASE-ANON-KEY ::= ""

instantiate-client -> supabase.Client
    --url/string=SUPABASE-URL
    --anon/string=SUPABASE-ANON-KEY
    --local-storage/supabase.LocalStorage?=(ConfigLocalStorage --app-name="supabase-demo"):
  if url == "":
    url = os.env.get "SUPABASE_URL"
    anon = os.env.get "SUPABASE_ANON_KEY"

  if url == "" or anon == "":
    print "Please set SUPABASE_URL and SUPABASE_ANON_KEY environment variables"
    exit 1

  return supabase.Client
      --uri=url
      --anon=anon
      --local-storage=local-storage

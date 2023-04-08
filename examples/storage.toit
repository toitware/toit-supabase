// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import supabase
import .utils.client

// Assumes a completely public bucket 'test-demo-public' is available
// in the Supabase project.
// See the project in the supabase directory for an example.
main:
  client := instantiate_client
  client.storage.upload --path="test-demo-public/bar.txt" --content=#['h', 'e', 'l', 'l', 'o']
  data := client.storage.download --path="test-demo-public/bar.txt"
  print data.to_string

  public_url := client.storage.public_url_for --path="test-demo-public/bar.txt"
  print "The public URL is $public_url"

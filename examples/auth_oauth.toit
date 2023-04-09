// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import supabase
import .utils.client

class Ui implements supabase.Ui:
  info message/string:
    print "Info: $message"

login args/List:
  client := instantiate_client
  // Providers must be enabled in the Supabase dashboard.
  // See https://supabase.com/docs/guides/auth
  client.auth.sign_in --provider="github" --open_browser --ui=Ui
  print "Logged in"

main args:
  // OAuth does not require signups. At first signup a new user is
  // created.
  if args.size > 0:
    if args[0] == "login" or args[0] == "signin":
      login args
      return

  client := instantiate_client
  client.ensure_authenticated: | reason/string |
    print "Authentication failure: $reason"
    exit 1

  print "Authenticated"

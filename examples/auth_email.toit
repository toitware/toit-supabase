// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import .utils.client
import system

signup args/List:
  if args.size != 3:
    print "Usage: $system.program_name signup <email> <password>"
    exit 1

  client := instantiate_client
  client.auth.sign_up --email=args[1] --password=args[2]
  print "Signed up"

login args/List:
  if args.size != 3:
    print "Usage: $system.program_name login <email> <password>"
    exit 1

  client := instantiate_client
  client.auth.sign_in --email=args[1] --password=args[2]
  print "Logged in"

main args:
  if args.size > 0:
    if args[0] == "signup":
      signup args
      return

    if args[0] == "login" or args[0] == "signin":
      login args
      return

  client := instantiate_client
  client.ensure_authenticated: | reason/string |
    print "Authentication failure: $reason"
    exit 1

  print "Authenticated"

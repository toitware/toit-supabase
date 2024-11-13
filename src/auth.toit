// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import desktop
import http
import host.pipe
import log
import monitor
import net
import .supabase
import system show platform PLATFORM-LINUX PLATFORM-MACOS PLATFORM-WINDOWS

/**
A class that handles all authentication related functionality of the Supabase API.
*/
class Auth:
  client_/Client

  constructor .client_:

  /**
  Computes an OAuth URL for the given $provider.

  The user should follow the URL and authenticate there. They are then redirected to
    the given $redirect-url, which must extract the session information.

  Use $finish-oauth-sign-in to provide the returned information to this instance.
  */
  compute-authenticate-url --redirect-url/string --provider/string -> string:
    return "$(client_.uri_)/auth/v1/authorize?provider=$provider&redirect_to=$redirect-url"

  /**
  Finishes the OAuth sign-in.

  When the user authenticates on an URL that is provided by $compute-authenticate-url,
    then they are redirected to another URL with the authentication information in the
    hash part of the URL. The page should change this to a query part and then call this
    method with the path of the URL.
  */
  finish-oauth-sign-in path/string -> none:
    // Extract the session information.
    question-mark-pos := path.index-of "?"
    path = path[question-mark-pos + 1..]
    query-parameters := {:}
    parts := path.split "&"
    parts.do: | part |
      equals-pos := part.index-of "="
      key := part[..equals-pos]
      value := part[equals-pos + 1..]
      query-parameters[key] = value

    access-token := query-parameters["access_token"]
    expires-in := int.parse query-parameters["expires_in"]
    refresh-token := query-parameters["refresh_token"]
    token-type := query-parameters["token_type"]

    session := Session_
        --access-token=access-token
        --expires-in-s=expires-in
        --refresh-token=refresh-token
        --token-type=token-type

    client_.set-session_ session

  sign-up --email/string --password/string -> none:
    response := client_.request_
        --method=http.POST
        --path="/auth/v1/signup"
        --payload={
          "email": email,
          "password": password,
        }
    if response and response is Map:
      if (response.get "email") == email: return
      if user := response.get "user":
        if (user.get "email") == email: return
    throw "Failed to sign up"

  sign-in --email/string --password/string -> none:
    response := client_.request_
        --method=http.POST
        --path="/auth/v1/token"
        --payload={
          "email": email,
          "password": password,
        }
        --query-parameters={
          "grant_type": "password",
        }
    session := Session_
        --access-token=response["access_token"]
        --expires-in-s=response["expires_in"]
        --refresh-token=response["refresh_token"]
        --token-type=response["token_type"]
    client_.set-session_ session

  /**
  Signs in using an Oauth provider.

  The user is redirected to the provider's authentication page and then back to the
    a localhost URL so that the program can receive the access token. If a
    $redirect-url is provided, the page redirects to that URL afterwards with the
    same fragment that this program received. This can be used to provide nicer
    success or error messages.
  */
  sign-in --provider/string --ui/Ui --open-browser/bool=true --redirect-url/string?=null -> none:
    network := net.open
    try:
      server-socket := network.tcp-listen 0
      server := http.Server --logger=(log.default.with-level log.FATAL-LEVEL)
      port := server-socket.local-address.port

      authenticate-url := compute-authenticate-url
          --redirect-url="http://localhost:$port/auth"
          --provider=provider

      ui.info "Please authenticate at $authenticate-url"
      if open-browser: desktop.open-browser authenticate-url

      session-latch := monitor.Latch
      server-task := task::
        server.listen server-socket:: | request/http.Request writer/http.ResponseWriter |
          out := writer.out
          if request.path.starts-with "/success":
            finish-oauth-sign-in request.path
            out.write "You can close this window now."
            session-latch.set true
          else if request.path.starts-with "/auth":
            redirect-code := ""
            if redirect-url:
              redirect-code = """window.location.href = "$redirect-url" + window.location.hash;"""
            out.write """
            <html>
              <body>
                <p id="body">
                This page requires JavaScript to continue.
                </p>
                <script type="text/javascript">
                  const req = new XMLHttpRequest();
                  req.addEventListener("load", function() {
                    document.getElementById("body").innerHTML = "You can close this window now.";
                    $redirect-code
                  });
                  req.open("GET", "http://localhost:$port/success?" + window.location.hash.substring(1));
                  req.send();
                  document.getElementById("body").innerHTML = "Transmitting data to CLI...";
                </script>
              </body>
            </html>
            """
          else:
            out.write "Invalid request."

      session-latch.get
      sleep --ms=1  // Give the server time to respond with the success message.
      server-task.cancel
    finally:
      network.close

  /**
  Revokes all refresh tokens for the user.
  JWT tokens will still be valid for stateless auth until they expire.
  */
  logout:
    if not client_.session_: throw "No session available."
    response := client_.request_
        --method=http.POST
        --path="/auth/v1/logout"
        --payload=#[]
    client_.set-session_ null
    return response

  refresh-token:
    if not client_.session_: throw "No session available."
    response := client_.request_
        --method=http.POST
        --path="/auth/v1/token"
        --query-parameters={
          "grant_type": "refresh_token",
        }
        --payload={
          "refresh_token": client_.session_.refresh-token,
        }
    session := Session_
        --access-token=response["access_token"]
        --expires-in-s=response["expires_in"]
        --refresh-token=response["refresh_token"]
        --token-type=response["token_type"]
    client_.set-session_ session

  /**
  Sends a reauthentication OTP to the user's email or phone number.

  The nonce can be used in an $update-current-user call when updating a
    user's password.

  A reauthentication is only needed if the "Secure password change" is
    enabled in the project's email provider settings.

  Furthermore, a user doesn't need to reauthenticate if they have recently
    signed in. A user is deemed recently signed in if their session was created
    in the last 24 hours.
  */
  reauthenticate:
    if not client_.session_: throw "No session available."
    return client_.request_
        --method=http.GET
        --path="/auth/v1/reauthenticate"

  /**
  Returns the currently authenticated user.
  */
  // TODO(florian): We should have this information cached when we sign in.
  get-current-user -> Map?:
    if not client_.session_: throw "No session available."
    response := client_.request_
        --method=http.GET
        --path="/auth/v1/user"
    return response

  /**
  Updates the currently authenticated user.

  This method can be used to update a user's email, password, or metadata.

  Accepted values:
  - "email": The user's email.
  - "password": The user's password.
  - "phone": The user's phone.
  - "email_confirm": Confirms the user's email address if set to true. Only a service
    rule can modify.
  - "nonce": The nonce sent for reauthentication if the user's password is to be
    updated. Call `reauthenticate()` to get the nonce first.
  - "ban_duration": Determines how long a user is banned for. The format for the ban
    duration follows a strict sequence of decimal numbers with a unit suffix. Valid time
    units are "ns", "us" (or "µs"), "ms", "s", "m", "h". Setting the ban duration to
    "none" lifts the ban on the user.
  - "user_metadata": A custom data object to store the user's metadata. This maps
    to the `auth.users.user_metadata` column. The `user_metadata` should be a JSON
    object that includes user-specific info, such as their first and last name.
  - "app_metadata": A custom data object to store the user's application specific
    metadata.
    This maps to the `auth.users.app_metadata` column. Only a service role can modify.
    The `app_metadata` should be a JSON object that includes app-specific info, such as
    identity providers, roles, and other access control information.
  */
  update-current-user data/Map -> none:
    if not client_.session_: throw "No session available."
    client_.request_
        --method=http.PUT
        --path="/auth/v1/user"
        --payload=data

class Session_:
  access-token/string

  expires-at/Time

  refresh-token/string
  token-type/string

  /**
  Constructs a new session.

  The $expires-in-s is the number of seconds until the access token expires
    after it was issued. We assume that the token was issued at the time of
    the call to the constructor.
  */
  constructor
      --.access-token
      --expires-in-s
      --.refresh-token
      --.token-type:
    expires-at = Time.now + (Duration --s=expires-in-s)

  constructor.from-json json/Map:
    // TODO(florian): remove backwards-compatibility code.
    expires-in := json.get "expires_in"
    expires-at-epoch-ms := json.get "expires_at_epoch_ms"
    if expires-in and not expires-at-epoch-ms:
      // Simply make it such that the token has expired.
      // After all, we don't know when the token was issued.
      expires-at-epoch-ms = 0
    access-token = json["access_token"]
    expires-at = Time.epoch --ms=expires-at-epoch-ms
    refresh-token = json["refresh_token"]
    token-type = json["token_type"]

  to-json -> Map:
    return {
      "access_token": access-token,
      "expires_at_epoch_ms": expires-at.ms-since-epoch,
      "refresh_token": refresh-token,
      "token_type": token-type,
    }

  has-expired --min-remaining/Duration=Duration.ZERO -> bool:
    return Time.now + min-remaining > expires-at

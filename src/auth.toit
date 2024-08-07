// Copyright (C) 2022 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

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
    the given $redirect_url, which must extract the session information.

  Use $finish_oauth_sign_in to provide the returned information to this instance.
  */
  compute_authenticate_url --redirect_url/string --provider/string -> string:
    return "$(client_.uri_)/auth/v1/authorize?provider=$provider&redirect_to=$redirect_url"

  /**
  Finishes the OAuth sign-in.

  When the user authenticates on an URL that is provided by $compute_authenticate_url,
    then they are redirected to another URL with the authentication information in the
    hash part of the URL. The page should change this to a query part and then call this
    method with the path of the URL.
  */
  finish_oauth_sign_in path/string -> none:
    // Extract the session information.
    question_mark_pos := path.index_of "?"
    path = path[question_mark_pos + 1..]
    query_parameters := {:}
    parts := path.split "&"
    parts.do: | part |
      equals_pos := part.index_of "="
      key := part[..equals_pos]
      value := part[equals_pos + 1..]
      query_parameters[key] = value

    access_token := query_parameters["access_token"]
    expires_in := int.parse query_parameters["expires_in"]
    refresh_token := query_parameters["refresh_token"]
    token_type := query_parameters["token_type"]

    session := Session_
        --access_token=access_token
        --expires_in_s=expires_in
        --refresh_token=refresh_token
        --token_type=token_type

    client_.set_session_ session

  sign_up --email/string --password/string -> none:
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

  sign_in --email/string --password/string -> none:
    response := client_.request_
        --method=http.POST
        --path="/auth/v1/token"
        --payload={
          "email": email,
          "password": password,
        }
        --query_parameters={
          "grant_type": "password",
        }
    session := Session_
        --access_token=response["access_token"]
        --expires_in_s=response["expires_in"]
        --refresh_token=response["refresh_token"]
        --token_type=response["token_type"]
    client_.set_session_ session

  /**
  Signs in using an Oauth provider.

  The user is redirected to the provider's authentication page and then back to the
    a localhost URL so that the program can receive the access token. If a
    $redirect_url is provided, the page redirects to that URL afterwards with the
    same fragment that this program received. This can be used to provide nicer
    success or error messages.
  */
  sign_in --provider/string --ui/Ui --open_browser/bool=true --redirect_url/string?=null -> none:
    network := net.open
    try:
      server_socket := network.tcp_listen 0
      server := http.Server --logger=(log.default.with_level log.FATAL_LEVEL)
      port := server_socket.local_address.port

      authenticate_url := compute_authenticate_url
          --redirect_url="http://localhost:$port/auth"
          --provider=provider

      ui.info "Please authenticate at $authenticate_url"
      if open_browser:
        catch:
          command/string? := null
          args/List? := null
          if platform == PLATFORM_LINUX:
            command = "xdg-open"
            args = [ authenticate_url ]
          else if platform == PLATFORM_MACOS:
            command = "open"
            args = [ authenticate_url ]
          else if platform == PLATFORM_WINDOWS:
            command = "cmd"
            escaped_url := authenticate_url.replace "&" "^&"
            args = [ "/c", "start", escaped_url ]
          // If we have a supported platform try to open the URL.
          // For all other platforms we already printed the URL to the console.
          if command != null:
            fork_data := pipe.fork
                true  // Use path.
                pipe.PIPE_CREATED  // Stdin.
                pipe.PIPE_CREATED  // Stdout.
                pipe.PIPE_CREATED  // Stderr.
                command
                [ command ] + args
            pid := fork_data[3]
            task --background::
              // The 'open' command should finish in almost no time.
              // Even if it doesn't, then the CLI almost always terminates
              // shortly after calling 'open'.
              // However, if we modify the CLI, so it becomes long-running (for
              // example inside a server), we need to make sure we don't keep
              // spawned processes around.
              exception := catch: with_timeout --ms=20_000:
                pipe.wait_for pid
              if exception == DEADLINE_EXCEEDED_ERROR:
                SIGKILL ::= 9
                catch: pipe.kill_ pid SIGKILL

      session_latch := monitor.Latch
      server_task := task::
        server.listen server_socket:: | request/http.Request writer/http.ResponseWriter |
          out := writer.out
          if request.path.starts_with "/success":
            finish_oauth_sign_in request.path
            out.write "You can close this window now."
            session_latch.set true
          else if request.path.starts_with "/auth":
            redirect_code := ""
            if redirect_url:
              redirect_code = """window.location.href = "$redirect_url" + window.location.hash;"""
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
                    $redirect_code
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

      session_latch.get
      sleep --ms=1  // Give the server time to respond with the success message.
      server_task.cancel
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
    client_.set_session_ null
    return response

  refresh_token:
    if not client_.session_: throw "No session available."
    response := client_.request_
        --method=http.POST
        --path="/auth/v1/token"
        --query_parameters={
          "grant_type": "refresh_token",
        }
        --payload={
          "refresh_token": client_.session_.refresh_token,
        }
    session := Session_
        --access_token=response["access_token"]
        --expires_in_s=response["expires_in"]
        --refresh_token=response["refresh_token"]
        --token_type=response["token_type"]
    client_.set_session_ session

  /**
  Sends a reauthentication OTP to the user's email or phone number.

  The nonce can be used in an $update_current_user call when updating a
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
  get_current_user -> Map?:
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
  update_current_user data/Map -> none:
    if not client_.session_: throw "No session available."
    client_.request_
        --method=http.PUT
        --path="/auth/v1/user"
        --payload=data

class Session_:
  access_token/string

  expires_at/Time

  refresh_token/string
  token_type/string

  /**
  Constructs a new session.

  The $expires_in_s is the number of seconds until the access token expires
    after it was issued. We assume that the token was issued at the time of
    the call to the constructor.
  */
  constructor
      --.access_token
      --expires_in_s
      --.refresh_token
      --.token_type:
    expires_at = Time.now + (Duration --s=expires_in_s)

  constructor.from_json json/Map:
    // TODO(florian): remove backwards-compatibility code.
    expires_in := json.get "expires_in"
    expires_at_epoch_ms := json.get "expires_at_epoch_ms"
    if expires_in and not expires_at_epoch_ms:
      // Simply make it such that the token has expired.
      // After all, we don't know when the token was issued.
      expires_at_epoch_ms = 0
    access_token = json["access_token"]
    expires_at = Time.epoch --ms=expires_at_epoch_ms
    refresh_token = json["refresh_token"]
    token_type = json["token_type"]

  to_json -> Map:
    return {
      "access_token": access_token,
      "expires_at_epoch_ms": expires_at.ms_since_epoch,
      "refresh_token": refresh_token,
      "token_type": token_type,
    }

  has_expired --min_remaining/Duration=Duration.ZERO -> bool:
    return Time.now + min_remaining > expires_at

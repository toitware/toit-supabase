// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import http
import net
import net.x509
import http.status-codes
import encoding.json
import encoding.url
import io
import tls

import .auth
import .utils_ as utils
import .filter show Filter

interface ServerConfig:
  uri -> string
  anon -> string

/**
An interface for interactions with the user.
*/
interface Ui:
  info str/string

/**
A client for the Supabase API.

Supabase provides several different APIs under one umbrella.

A frontend ('Kong'), takes the requests and forwards them to the correct
  backend.
Each supported backend is available through a different getter.
For example, the Postgres backend is available through the $rest getter, and
  the storage backend is available through $storage.
*/
class Client:
  http-client_/http.Client? := null
  local-storage_/LocalStorage
  session_/Session_? := null

  /**
  The used network interface.
  This field is only set, if the $close function should close the network.
  */
  network-to-close_/net.Interface? := null

  /**
  The URL of the Supabase project.
  */
  uri_/string

  /**
  The anonymous key of the Supabase project.

  This key is used as api key.
  If the user is not authenticated the client uses this key as the bearer.
  */
  anon_/string

  rest_/PostgRest? := null
  storage_/Storage? := null
  auth_/Auth? := null

  constructor network/net.Interface?=null
      --uri/string
      --anon/string
      --local-storage/LocalStorage=NoLocalStorage:
    uri_ = uri
    anon_ = anon

    if not network:
      network = network-to-close_ = net.open

    http-client_ = http.Client network
    local-storage_ = local-storage
    add-finalizer this:: close

  constructor network/net.Interface?=null
      --server-config/ServerConfig
      --local-storage/LocalStorage=NoLocalStorage:
    return Client network
          --local-storage=local-storage
          --uri=server-config.uri
          --anon=server-config.anon

  /**
  Ensures that the user is authenticated.

  If a session is stored in the local storage and is still valid, uses that
    session. In that case no network request is made. If the session has been
    invalidated in the meantime an error will happen at later point in time.

  If no session is stored, or the refresh failed, calls the given $block with the
    reason for why the client isn't authenticated. This could include an error
    when refreshing an authorization token. In most cases it's simply "Not logged in".

  # Examples
  A simple example where the user is signed in using email and password:
  ```
  client.ensure_authenticated: | reason/string |
    print "Authentication failure: $reason"
    client.auth.sign_in --email="email" --password="password"
  ```

  Or, using oauth:
  ```
  client.ensure_authenticated: | reason/string |
    print "Authentication failure: $reason"
    client.auth.sign_in --provider="github" --ui=ui
  ```
  */
  ensure-authenticated [block]:
    exception := null
    if local-storage_.has-auth:
      exception = catch:
        session_ = Session_.from-json local-storage_.get-auth
        if session_.has-expired --min-remaining=(Duration --m=20):
          auth.refresh-token
        return
      // There was an exception.
      // Clear the stored session, and run the block for a fresh authentication.
      local-storage_.remove-auth
    reason := ?
    if exception:
      reason = "Error while refreshing the authentication: $exception"
    else:
      reason = "Not logged in"
    block.call reason

  close -> none:
    if not http-client_: return
    remove-finalizer this
    http-client_.close
    http-client_ = null
    if network-to-close_:
      network-to-close_.close
      network-to-close_ = null

  is-closed -> bool:
    return http-client_ == null

  rest -> PostgRest:
    if not rest_: rest_ = PostgRest this
    return rest_

  storage -> Storage:
    if not storage_: storage_ = Storage this
    return storage_

  auth -> Auth:
    if not auth_: auth_ = Auth this
    return auth_

  set-session_ session/Session_?:
    session_ = session
    if session:
      local-storage_.set-auth session.to-json
    else:
      local-storage_.remove-auth

  is-success-status-code_ code/int -> bool:
    return 200 <= code <= 299

  /**
  Does a request to the Supabase API, and returns the response without
    parsing it.

  It is the responsibility of the caller to drain the response.

  Query parameters can be provided in two ways:
  - with the $query parameter is a string that is appended to the path. It must
    be properly URL encoded (also known as percent-encoding), or
  - with the $query-parameters parameter, which is a map from keys to values.
    The value for each key must be a string or a list of strings. In the latter
    case, each value is added as a separate query parameter.
  It is an error to provide both $query and $query-parameters.
  */
  request_ --raw-response/bool -> http.Response
      --path/string
      --method/string
      --bearer/string? = null
      --query/string? = null
      --query-parameters/Map? = null
      --headers/http.Headers? = null
      --payload/any = null
      --schema/string? = null:

    if query and query-parameters:
      throw "Cannot provide both query and query_parameters"

    headers = headers ? headers.copy : http.Headers

    if not bearer:
      if not session_: bearer = anon_
      else: bearer = session_.access-token
    headers.set "Authorization" "Bearer $bearer"

    headers.add "apikey" anon_

    if schema:
      if method == http.GET or method == http.HEAD:
        headers.add "Accept-Profile" schema
      else:
        headers.add "Content-Profile" schema

    question-mark-pos := path.index-of "?"
    if question-mark-pos >= 0:
      // Replace the existing query parameters with ours.
      path = path[..question-mark-pos]
    if query-parameters:
      encoded-params := []
      query-parameters.do: | key value |
        encoded-key := url.encode key
        if value is List:
          value.do:
            encoded-params.add "$encoded-key=$(url.encode it)"
        else:
          encoded-params.add "$encoded-key=$(url.encode value)"
      path = "$path?$(encoded-params.join "&")"
    else if query:
      path = "$path?$query"

    uri := "$uri_$path"
    response/http.Response := ?
    if method == http.GET:
      if payload: throw "GET requests cannot have a payload"
      response = http-client_.get --uri=uri --headers=headers
    else if method == http.PATCH or method == http.DELETE or method == http.PUT:
      // TODO(florian): the http client should support PATCH.
      // TODO(florian): we should only do this if the payload is a Map.
      encoded := json.encode payload
      headers.set "Content-Type" "application/json"
      request := http-client_.new-request --uri=uri --headers=headers method
      request.body = io.Reader encoded
      response = request.send
    else:
      if method != http.POST: throw "UNIMPLEMENTED"
      if payload is Map:
        response = http-client_.post-json --uri=uri --headers=headers payload
      else:
        response = http-client_.post --uri=uri --headers=headers payload

    return response

  /**
  Variant of $(request_ --raw-response --path --method).

  Does a request to the Supabase API, and extracts the response.
  If $parse-response-json is true, then parses the response as a JSON
    object.
  Otherwise returns it as a byte array.
  */
  request_ -> any
      --path/string
      --method/string
      --bearer/string? = null
      --query/string? = null
      --query-parameters/Map? = null
      --headers/http.Headers? = null
      --parse-response-json/bool = true
      --payload/any = null
      --schema/string? = null:
    response := request_
        --raw-response
        --path=path
        --method=method
        --bearer=bearer
        --query=query
        --query-parameters=query-parameters
        --headers=headers
        --payload=payload
        --schema=schema

    body := response.body
    if not is-success-status-code_ response.status-code:
      body-bytes := utils.read-all body
      message := ""
      exception := catch:
        decoded := json.decode body-bytes
        message = decoded.get "msg" or
            decoded.get "message" or
            decoded.get "error_description" or
            decoded.get "error" or
            body-bytes.to-string-non-throwing
      if exception:
        message = body-bytes.to-string-non-throwing
      throw "FAILED: $response.status-code - $message"

    if not parse-response-json:
      return (utils.read-all body).to-string-non-throwing

    // Still check whether there is a response.
    // When performing an RPC we can't know in advance whether the function
    // returns something or not.
    buffered-body := body
    if not buffered-body.try-ensure-buffered 1:
      return null

    try:
      return json.decode-stream buffered-body
    finally:
      catch: response.drain

/**
An interface to store authentication information locally.

On desktops this should be the config file.
On mobile this could be something like HiveDB/Isar.
*/
interface LocalStorage:
  /**
  Whether the storage contains any authorization information.
  */
  has-auth -> bool

  /**
  Returns the stored authorization information.
  If none exists, returns null.
  */
  get-auth -> any?

  /**
  Sets the authorization information to $value.

  The $value must be JSON-encodable.
  */
  set-auth value/any -> none

  /**
  Removes any authorization information.
  */
  remove-auth -> none

/**
A simple implementation of $LocalStorage that simply discards all data.
*/
class NoLocalStorage implements LocalStorage:
  has-auth -> bool: return false
  get-auth -> any?: return null
  set-auth value/any: return
  remove-auth -> none: return

/**
A client for the PostgREST API.

PostgREST uses 'GET', 'POST', 'PATCH', 'PUT', and 'DELETE' requests to
  perform CRUD operations on tables.

- 'GET' requests are used to retrieve rows from a table.
- 'POST' requests are used to insert rows into a table.
- 'PATCH' requests are used to update rows in a table.
- 'PUT' requests are used to replace a single row in a table.
- 'DELETE' requests are used to delete rows from a table.
*/
class PostgRest:
  /**
  For 'POST' requests (inserts), the response is empty, and only
    contains a 'Location' header with the primary key of the newly
    inserted row.
  This return preference must not be used for other requests.

  Note that this return preference leads to a permission error if the
    table is only write-only.
  */
  static RETURN-HEADER-ONLY_ ::= "header-only"
  /**
  The response is the full representation.

  This return preference is allowed for 'POST', 'PATCH', 'DELETE' and
    'PUT' requests.
  */
  static RETURN-REPRESENTATION_ ::= "representation"
  /**
  The response does not include the 'Location' header, as would be
    the case with 'RETURN_HEADER_ONLY'. This return preference must
    be used when writing into a table that is write-only.

  This return preference is allowed for 'POST', 'PATCH', 'DELETE' and
    'PUT' requests.
  */
  static RETURN-MINIMAL_ ::= "minimal"

  client_/Client

  constructor .client_:

  encode-filters_ filters/List -> string:
    escaped := filters.map: | filter/Filter |
      filter.to-string --nested=false --negated=false
    return escaped.join "&"

  /**
  Returns a list of rows that match the $filters.

  The $filters must be instances of the $Filter class.
  */
  select table/string --filters/List=[] --schema/string?=null -> List:
    query-filters := encode-filters_ filters
    return client_.request_
        --method=http.GET
        --path="/rest/v1/$table"
        --query=query-filters
        --schema=schema

  /**
  Inserts a new row to the table.

  If the row would violate a unique constraint, then the operation fails.

  If $return-inserted is true, then returns the inserted row.
  */
  insert -> Map?
      table/string
      payload/Map
      --return-inserted/bool=true
      --schema/string?=null:
    headers := http.Headers
    headers.add "Prefer" "return=$(return-inserted ? RETURN-REPRESENTATION_ : RETURN-MINIMAL_)"
    response := client_.request_
        --method=http.POST
        --headers=headers
        --path="/rest/v1/$table"
        --payload=payload
        --parse-response-json=return-inserted
        --schema=schema
    if return-inserted:
      return response.size == 0 ? null : response[0]
    return null

  /**
  Performs an 'update' operation on a table.

  The $filters must be instances of the $Filter class.
  */
  update table/string payload/Map --filters/List --schema/string?=null -> none:
    query-filters := encode-filters_ filters
    // We are not using the response. Use the minimal response.
    headers := http.Headers
    headers.add "Prefer" RETURN-MINIMAL_
    client_.request_
        --method=http.PATCH
        --headers=headers
        --path="/rest/v1/$table"
        --payload=payload
        --parse-response-json=false
        --query=query-filters
        --schema=schema

  /**
  Performs an 'upsert' operation on a table.

  The word "upsert" is a combination of "update" and "insert".
  If adding a row would violate a unique constraint, then the row is
    updated instead.
  */
  upsert -> none
      table/string
      payload/Map
      --ignore-duplicates/bool=false
      --schema/string?=null:
    // TODO(florian): add support for '--on_conflict'.
    // In that case the conflict detection is on the column given by
    // on_column (which must be 'UNIQUE').
    // Verify this, and add the parameter.
    headers := http.Headers
    preference := ignore-duplicates
        ? "resolution=ignore-duplicates"
        : "resolution=merge-duplicates"
    headers.add "Prefer" preference
    // We are not using the response. Use the minimal response.
    headers.add "Prefer" RETURN-MINIMAL_
    client_.request_
        --method=http.POST
        --headers=headers
        --path="/rest/v1/$table"
        --payload=payload
        --parse-response-json=false
        --schema=schema

  /**
  Deletes all rows that match the filters.

  If no filters are given, then all rows are deleted. Note that some
    server configurations require at least one filter for a delete
    operation.

  The $filters must be instances of the $Filter class.
  */
  delete table/string --filters/List --schema/string?=null -> none:
    query-filters := encode-filters_ filters
    // We are not using the response. Use the minimal response.
    headers := http.Headers
    headers.add "Prefer" RETURN-MINIMAL_
    client_.request_
        --method=http.DELETE
        --headers=headers
        --path="/rest/v1/$table"
        --parse-response-json=false
        --query=query-filters
        --schema=schema

  /**
  Performs a remote procedure call (RPC).
  */
  rpc name/string payload/Map --schema/string?=null -> any:
    return client_.request_
        --method=http.POST
        --path="/rest/v1/rpc/$name"
        --payload=payload
        --schema=schema

class Storage:
  client_/Client

  constructor .client_:

  // TODO(florian): add support for changing and deleting.
  // TODO(florian): add support for 'get_public_url'.
  //    should be as simple as "$url/storage/v1/object/public/$path"

  /**
  Deprecated. Use $(upload --path --contents) instead.
  */
  upload --path/string --content/ByteArray --upsert/bool=true -> none:
    upload --path=path --contents=content --upsert=upsert

  /**
  Uploads data to the storage.

  If $upsert is true, then the data is overwritten if it already exists.
  */
  upload --path/string --contents/ByteArray --upsert/bool=true -> none:
    headers := http.Headers
    if upsert: headers.add "x-upsert" "true"
    headers.add "Content-Type" "application/octet-stream"
    client_.request_
        --method=http.POST
        --headers=headers
        --path="/storage/v1/object/$path"
        --payload=contents
        --parse-response-json=false

  /**
  Downloads the data stored in $path from the storage.

  If $public is true, downloads the data through the public URL.
  */
  download --path/string --public/bool=false -> ByteArray:
    download --path=path --public=public: | reader/io.Reader |
      return utils.read-all reader
    unreachable

  /**
  Downloads the data stored in $path from the storage.

  Calls the given $block with an $io.Reader for the resource.

  If $public is true, downloads the data through the public URL.
  */
  download --public/bool=false --path/string --offset/int=0 --size/int?=null [block] -> none:
    partial := false
    headers/http.Headers? := null
    if offset != 0 or size:
      partial = true
      end := size ? "$(offset + size - 1)" : ""
      headers = http.Headers
      headers.add "Range" "bytes=$offset-$end"
    full-path := public
        ? "/storage/v1/object/public/$path"
        : "/storage/v1/object/$path"
    response := client_.request_ --raw-response
        --method=http.GET
        --path=full-path
        --headers=headers
    // Check the status code. The correct result depends on whether
    // or not we're doing a partial fetch.
    status := response.status-code
    body := response.body
    okay := status == status-codes.STATUS-OK or (partial and status == status-codes.STATUS-PARTIAL-CONTENT)
    try:
      if not okay: throw "Not found ($status)"
      block.call body
    finally:
      catch: response.drain

  /**
  Returns a list of all buckets.
  */
  list-buckets -> List:
    return client_.request_
        --method=http.GET
        --path="/storage/v1/bucket"
        --parse-response-json=true

  /**
  Returns a list of all objects at the given path.
  The path must not be empty.
  */
  list path/string -> List:
    if path == "": throw "INVALID_ARGUMENT"
    first-slash := path.index-of "/"
    bucket/string := ?
    prefix/string := ?
    if first-slash == -1:
      bucket = path
      prefix = ""
    else:
      bucket = path[0..first-slash]
      prefix = path[first-slash + 1..path.size]

    payload := {
      "prefix": prefix,
    }
    return client_.request_
        --method=http.POST
        --path="/storage/v1/object/list/$bucket"
        --parse-response-json=true
        --payload=payload

  /**
  Computes the public URL for the given $path.
  */
  public-url-for --path/string -> string:
    return "$client_.uri_/storage/v1/object/public/$path"

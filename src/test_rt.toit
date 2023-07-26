import http
import certificate_roots
import net
import encoding.json

HOST ::= "voisfafsfolxhqpkudzd.supabase.co"
ANON ::= "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZvaXNmYWZzZm9seGhxcGt1ZHpkIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NzMzNzQyNDEsImV4cCI6MTk4ODk1MDI0MX0.dmfxNl5WssxnZ8jpvGJeryg4Fd47fOcrlZ8iGrHj2e4"
CERTIFICATE ::= certificate_roots.BALTIMORE_CYBERTRUST_ROOT

main:
  network := net.open
  client := http.Client.tls network --root_certificates=[CERTIFICATE]

  headers := http.Headers
  headers.add "apikey" ANON

  socket := client.web_socket
      --uri="wss://$HOST/realtime/v1?vsn=1.0.0&apikey=$ANON"

  task::
    while message := socket.receive:
      print message

  ref_counter := 0

  task::
    while true:
      sleep --ms=5_000
      message := json.encode {
        "topic": "phoenix",
        "event": "heartbeat",
        "payload": {:},
        "ref": "$(ref_counter++)"
      }
      socket.send message

  channel_topic := "realtime:random-$random"

  message := json.encode {
    "topic": channel_topic,
    "event": "phx_join",
    "payload": {
      "config": {
        "broadcast": {
          "ack": true,
          "self": true,
        },
      },
      "presence": { "key": "" },
    },
    "ref": "$(ref_counter++)"
  }
  socket.send message

  sleep --ms=1_000

  message = json.encode {
    "topic": channel_topic,
    "event": "broadcast",
    "payload": {
      "message": "Hello, world!",
    },
    "ref": "$(ref_counter++)"
  }
  socket.send message

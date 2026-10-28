#!/bin/sh
log="$2/http.log"
python3 -u -c '
import functools, http.server, socketserver, sys

class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = "127.0.0.1"
        self.server_port = self.server_address[1]

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
server = Server(("127.0.0.1", 0), handler)
print("Serving HTTP on 127.0.0.1 port %d" % server.server_port)
server.serve_forever()
' "$1" >"${log}" 2>&1 &
pid="$!"
printf '%s\n' "${pid}" >"$2/http.pid"
tries=0
while [ "${tries}" -lt 300 ]; do
  port="$(sed -n 's/.* port \([0-9][0-9]*\).*/\1/p' "${log}")"
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    exit 0
  fi
  kill -0 "${pid}" 2>/dev/null || break
  sleep 0.1
  tries=$((tries + 1))
done
printf 'the test server did not start:\n' >&2
cat "${log}" >&2
exit 1

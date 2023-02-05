#!/bin/bash

cat > index.html <<EOF
<h1>Hello, World</h1>
<p>DB address: </p>
<p>DB port: </p>
EOF

nohup busybox httpd -f -p ${server_port} &
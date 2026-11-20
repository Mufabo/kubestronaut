# Chapter 44 lab: solutions

Run every command inside the lab shell (`make shell`).

## Task 1: Visit a site without DNS

The site name only matters in the `Host` header (and, for HTTPS, in SNI). Send
it to the server's address:

```bash
on client curl -H 'Host: api.lab.internal' http://10.0.8.80/
```

```text
hello from the api site, code api-7q2kx9
```

`on client curl --resolve api.lab.internal:80:10.0.8.80 http://api.lab.internal/`
gets the same page. The code is random per setup:

```bash
echo api-7q2kx9 > /root/answers/44/api-code
```

## Task 2: Issue a server certificate

```bash
cd /root/tls
openssl req -newkey rsa:2048 -nodes -keyout web.key -out web.csr -subj "/CN=web.lab.internal" -addext "subjectAltName=DNS:web.lab.internal"
openssl x509 -req -in web.csr -CA /root/ca/ca.crt -CAkey /root/ca/ca.key -out web.crt -days 90 -copy_extensions copy
openssl verify -CAfile /root/ca/ca.crt web.crt
openssl x509 -in web.crt -noout -ext subjectAltName
```

## Task 3: Serve HTTPS

```bash
on web nohup labhttp --port 8443 --name web --cert /root/tls/web.crt --key /root/tls/web.key > /tmp/https.log 2>&1 &
on client curl --cacert /root/ca/ca.crt https://web.lab.internal:8443/
```

```text
hello from web
```

Without `--cacert`, curl fails with `unable to get local issuer certificate`;
with `https://10.0.8.80:8443/`, it fails because no SAN matches the IP address.

## Task 4: Mutual TLS

First see the refusal:

```bash
on client curl --cacert /root/ca/ca.crt https://web.lab.internal:9443/
```

```text
curl: (56) OpenSSL SSL_read: OpenSSL/3.5.7: error:0A00045C:SSL routines::tlsv13 alert certificate required, errno 0
```

Issue a client certificate from the same CA. A client certificate needs no SAN;
the server reads the subject:

```bash
cd /root/tls
openssl req -newkey rsa:2048 -nodes -keyout client.key -out client.csr -subj "/CN=client"
openssl x509 -req -in client.csr -CA /root/ca/ca.crt -CAkey /root/ca/ca.key -out client.crt -days 30
on client curl --cacert /root/ca/ca.crt --cert /root/tls/client.crt --key /root/tls/client.key https://web.lab.internal:9443/
```

```text
hello from web-mtls (client certificate: client)
```
